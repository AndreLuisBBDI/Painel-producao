# Painel de Produção

Painel do Grupo BBDI para acompanhar produção por grupo, colaborador e dia:
lançamentos, capacidade instalada, metas, pedidos diários, justificativas e
clima da equipe. Um arquivo HTML só, sem build.

- **No ar:** https://painel-producao-two.vercel.app/
- **Publicar:** `git push` na `main` — a Vercel sobe o `index.html` da raiz.

## Os dados ficam na nuvem

Até 17/09/2026 o painel guardava tudo em `localStorage`. Isso não era um
bug de sincronização: **não existia sincronização nenhuma**. Quem importava
o TOTVS num computador via os números só naquele computador, e cada máquina
tinha a sua verdade particular.

Agora a verdade é uma linha no Supabase e o `localStorage` é só uma cópia
para a tela abrir na hora e para o painel continuar funcionando sem internet.

| onde | o quê |
|---|---|
| projeto Supabase | `nuxbnsdkddudwkzijexw` (o mesmo do abastecimento — a org está no limite de 2 projetos do plano gratuito) |
| tabela | `public.painel_producao`, uma linha só: `id = 'principal'` |
| conteúdo | o estado inteiro em `jsonb`, mais `rev`, `atualizado_em`, `atualizado_por` |
| histórico | `public.painel_producao_hist` guarda as 20 últimas versões, gravadas por gatilho |
| DDL | [`db/painel_producao.sql`](db/painel_producao.sql) |

O painel não tem login. A chave publicável é a de todo mundo, então o que
dá para travar está travado: uma linha só, `insert` e `update` presos a
`id = 'principal'`, **sem política de delete**, e o histórico é só de
leitura para o navegador — quem escreve nele é o gatilho.

### Como duas máquinas não se atropelam

Duas coisas, e as duas importam:

**1. `rev`, contra gravação em cima de cópia velha.** Quem grava diz qual
revisão leu (`.eq("rev", n)`). Se alguém salvou no meio, o `update` não
casa linha nenhuma — o supabase-js **não trata isso como erro**, devolve
`data: null` — o painel puxa o que chegou, funde e tenta de novo (até 4
vezes).

**2. Fusão de três lados (base / este PC / nuvem).** Não é "o último que
gravou ganha": isso apagaria a importação do outro. Cada coleção tem chave
própria (`lancamentos` por `id`, `grupos` por `nome`, `gruposFinos` por
`codigo`) e cada item é decidido separadamente:

- item que só existe num lado → fica;
- item que sumiu de um lado mas **estava na base** → foi apagado de
  propósito, continua apagado;
- **a menos que** o outro lado o tenha alterado — aí a alteração ganha.
  Apagar num PC não engole em silêncio a correção feita no outro;
- mesmo item mexido nos dois → vale o deste PC, e o painel conta o conflito;
- primeiro contacto (sem base) → união, ninguém perde nada.

Para valores soltos (capacidade, metas) não há como fundir: quem mexeu
sozinho ganha; se os dois mexeram, vale o deste PC.

A prova disso é código que roda:

```
node tools/teste-sincronizacao.js     # 21 asserções
```

### Ids estáveis

Duas máquinas que produzem o mesmo registro têm de produzir a **mesma
chave**, senão a fusão duplica tudo. Por isso:

- o histórico semeado usa `hist-<data>-<grupo>-<colaborador>-<qtd>`;
- a importação TOTVS usa `totvs-<data>-<grupo>-<grupoFino>-<colaborador>`
  (é exatamente a chave por onde `agregarRegistros` já agrupa, então não
  colide).

E a semeadura do histórico só acontece **depois** que a nuvem respondeu:
um navegador novo que semeasse antes empurraria 376 lançamentos por cima
do que já existe.

### O selo no cabeçalho

| selo | o que quer dizer |
|---|---|
| ☁️ Sincronizado | a nuvem tem o que está na tela |
| ⏳ Enviando… | gravando |
| ⚠️ Nuvem fora — salvo neste PC | sem tabela, sem rede ou erro; o painel continua funcionando e sobe quando voltar |
| 💾 Só neste PC | o supabase-js não carregou |

### "Usar os dados deste PC"

Botão em **Dados e backup**. Manda o estado desta máquina por cima da
nuvem, **sem fundir**. Serve para duas situações:

- **o arranque** — o computador que já tinha os dados de verdade dita o
  ponto de partida;
- **emergência** — a fusão deixou a nuvem errada e alguém precisa mandar
  nela.

Não é caminho sem volta: a versão anterior fica em `painel_producao_hist`.

## Estrutura

```
index.html                      o painel inteiro (supabase-js embutido, sem CDN)
db/painel_producao.sql          tabela, histórico, gatilho, RLS e realtime
tools/teste-sincronizacao.js    prova da fusão, extraída do próprio index.html
```

O `tools/teste-sincronizacao.js` não testa uma cópia do código: ele arranca
`nuvemIgual`, `nuvemFundirLista` e `nuvemFundirEstado` de dentro do
`index.html` por nome. Se alguém mexer na fusão e esquecer do teste, o
teste quebra.
