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
node tools/teste-sincronizacao.js     # 30 asserções
```

### Ids estáveis

Duas máquinas que produzem o mesmo registro têm de produzir a **mesma
chave**, senão a fusão duplica tudo. Todo lançamento **gerado por
máquina** tira o id do próprio conteúdo:

- o histórico semeado usa `hist-<data>-<grupo>-<colaborador>-<qtd>`;
- a importação TOTVS usa `totvs-<data>-<grupo>-<grupoFino>-<colaborador>`
  (é exatamente a chave por onde `agregarRegistros` já agrupa, então não
  colide).

Lançamento digitado à mão fica com id aleatório de propósito: duas pessoas
podem produzir a mesma peça no mesmo dia e são dois lançamentos de verdade.

E a semeadura do histórico só acontece **depois** que a nuvem respondeu:
um navegador novo que semeasse antes empurraria 376 lançamentos por cima
do que já existe.

**O conserto dos PCs antigos.** Até 17/09/2026 o histórico era semeado com
`crypto.randomUUID()` — cada computador tinha 376 ids só dele. Ao encontrar
a nuvem pela primeira vez nada casava e os 376 viravam **752**. Por isso
`normalizarIdsImportados()` roda em tudo que entra, venha do `localStorage`
ou da nuvem: reescreve os ids importados para a chave do conteúdo e junta
os que caem na mesma chave. Um estado já duplicado se desfaz sozinho na
primeira leitura, sem ninguém apagar nada à mão.

### O selo no cabeçalho

| selo | o que quer dizer |
|---|---|
| 🟢 (bolinha verde) | quem está com o painel aberto agora — clicar abre a aba **Logs** |
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

## Quem fez o quê: a aba Logs

A aba **Logs** responde duas perguntas: *quem está aqui agora* e *quem fez
o quê, quando*. As duas coisas moram em tabelas próprias, **fora** do
`jsonb` do estado — e isso é decisão, não preguiça. O estado é um bloco
que se funde e se reescreve inteiro a cada gravação; log é o contrário
disso: linha que nasce, não muda e não some. Juntos, cada lançamento
reenviaria o histórico de acessos inteiro, e a fusão de três lados teria
de resolver conflito em algo que, por definição, não conflita.

| tabela | o quê |
|---|---|
| `public.painel_producao_log` | `quem`, `acao`, `detalhe`, `dados` (jsonb), `criado_em` |
| `public.painel_producao_presenca` | `quem` (chave primária), `visto_em`, `aba` |
| DDL | [`db/painel_producao_log.sql`](db/painel_producao_log.sql) |

**O log é só de escrita.** Não é promessa no código: `anon` tem `select` e
`insert` e mais nada, então `update` e `delete` voltam `42501` mesmo que
alguém use a chave publicável na mão. Os campos têm teto (`quem` 80,
`acao` 40, `detalhe` 500) para que a tabela não vire depósito.

O que fica registrado: acesso, importação do TOTVS (arquivo, período,
quantos lançamentos, quantos substituídos), importação de vendas médias,
lançamento manual, exclusão, backup exportado, backup restaurado, "usar
os dados deste PC", capacidade e metas.

Um acesso vale por **visita, não por F5**: quem recarrega cinco vezes
testando alguma coisa não vira cinco linhas (janela de 30 min por nome).
Trocar o nome no alto da tela conta como visita nova — é outra pessoa
sentada ali.

**A presença é por tabela, não por Realtime Presence** — a chave nova não
é JWT. Cada painel aberto bate na sua linha a cada 30 s (`quem` é chave
primária, então duas abas da mesma pessoa são uma linha só e a tabela não
acumula fantasma). Está online quem bateu nos últimos 100 s. Fechar a aba
tira a pessoa da lista na hora, por um `PATCH` com `keepalive` que joga a
última batida para o passado — **não** um delete: a política só deixa
apagar linha parada há mais de 2 h, para ninguém derrubar quem está
mesmo trabalhando.

O nome que aparece nas duas telas vem de tabela pública e escrita com a
chave que está dentro do `index.html`. Nada que saia dali entra no HTML
sem passar por `esc()`.

## Estrutura

```
index.html                      o painel inteiro (supabase-js embutido, sem CDN)
db/painel_producao.sql          tabela, histórico, gatilho, RLS e realtime
db/painel_producao_log.sql      log de atividade e presença (append-only)
tools/teste-sincronizacao.js    prova da fusão, extraída do próprio index.html
```

O `tools/teste-sincronizacao.js` não testa uma cópia do código: ele arranca
`nuvemIgual`, `nuvemFundirLista`, `nuvemFundirEstado` e a normalização de
ids de dentro do
`index.html` por nome. Se alguém mexer na fusão e esquecer do teste, o
teste quebra.
