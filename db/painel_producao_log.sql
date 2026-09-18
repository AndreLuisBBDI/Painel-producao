-- ============================================================
-- Painel de Produção — log de atividade e presença
-- ============================================================
--
-- Estas duas tabelas ficam FORA do jsonb de painel_producao de propósito.
-- O estado do painel é um bloco que se funde e se reescreve inteiro a cada
-- gravação; log é o contrário disso — linha que nasce, não muda e não some.
-- Misturar os dois faria cada lançamento reenviar o histórico inteiro de
-- acessos, e a fusão de três lados teria de resolver conflito em algo que,
-- por definição, não conflita.
--
-- O painel não tem login e a chave publicável é a de todo mundo. Então o
-- que dá para travar está travado: o log é append-only (sem update, sem
-- delete — ninguém apaga o próprio rastro) e os campos têm teto de tamanho
-- para que ninguém use a tabela como depósito.

-- ------------------------------------------------------------ log
create table if not exists public.painel_producao_log (
  seq        bigserial primary key,
  quem       text        not null,
  acao       text        not null,
  detalhe    text,
  dados      jsonb,
  criado_em  timestamptz not null default now(),
  constraint painel_producao_log_quem_cabe    check (char_length(quem)    between 1 and 80),
  constraint painel_producao_log_acao_cabe    check (char_length(acao)    between 1 and 40),
  constraint painel_producao_log_detalhe_cabe check (detalhe is null or char_length(detalhe) <= 500)
);

-- a tela lê sempre os mais recentes primeiro
create index if not exists painel_producao_log_recente
  on public.painel_producao_log (criado_em desc);

-- ------------------------------------------------------- presença
-- Uma linha por pessoa: duas abas do mesmo nome batem na mesma linha, que
-- é o que se quer — a pergunta é "quem está aqui", não "quantas abas".
-- Ninguém some ao fechar a aba: quem para de bater sai sozinho pela idade
-- do carimbo (o painel considera online quem bateu nos últimos 100 s).
create table if not exists public.painel_producao_presenca (
  quem      text        primary key,
  visto_em  timestamptz not null default now(),
  aba       text,
  constraint painel_producao_presenca_quem_cabe check (char_length(quem) between 1 and 80),
  constraint painel_producao_presenca_aba_cabe  check (aba is null or char_length(aba) <= 40)
);

-- ------------------------------------------------------------ RLS
alter table public.painel_producao_log      enable row level security;
alter table public.painel_producao_presenca enable row level security;

drop policy if exists painel_producao_log_ler    on public.painel_producao_log;
drop policy if exists painel_producao_log_gravar on public.painel_producao_log;

create policy painel_producao_log_ler
  on public.painel_producao_log for select using (true);

-- escrever pode; reescrever e apagar, não. É o que faz do log um log.
create policy painel_producao_log_gravar
  on public.painel_producao_log for insert with check (true);

drop policy if exists painel_producao_presenca_ler      on public.painel_producao_presenca;
drop policy if exists painel_producao_presenca_entrar   on public.painel_producao_presenca;
drop policy if exists painel_producao_presenca_bater    on public.painel_producao_presenca;
drop policy if exists painel_producao_presenca_limpar   on public.painel_producao_presenca;

create policy painel_producao_presenca_ler
  on public.painel_producao_presenca for select using (true);
create policy painel_producao_presenca_entrar
  on public.painel_producao_presenca for insert with check (true);
create policy painel_producao_presenca_bater
  on public.painel_producao_presenca for update using (true) with check (true);

-- apagar só fantasma: quem está online de verdade não pode ser derrubado
create policy painel_producao_presenca_limpar
  on public.painel_producao_presenca for delete
  using (visto_em < now() - interval '2 hours');

-- --------------------------------------------------------- grants
revoke all on public.painel_producao_log      from anon, authenticated;
revoke all on public.painel_producao_presenca from anon, authenticated;

grant select, insert on public.painel_producao_log to anon, authenticated;
grant usage, select on sequence public.painel_producao_log_seq_seq to anon, authenticated;
grant select, insert, update, delete on public.painel_producao_presenca to anon, authenticated;

-- ------------------------------------------------------- realtime
-- a bolinha verde e a aba de logs acendem sem ninguém recarregar
do $$
begin
  alter publication supabase_realtime add table public.painel_producao_log;
exception when duplicate_object then null; when undefined_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.painel_producao_presenca;
exception when duplicate_object then null; when undefined_object then null;
end $$;

-- ----------------------------------------------------- conferência
select
  (select count(*) from public.painel_producao_log)                                          as linhas_log,
  (select count(*) from public.painel_producao_presenca)                                     as linhas_presenca,
  (select count(*) from pg_policies
     where schemaname='public' and tablename='painel_producao_log')                          as politicas_log,
  (select count(*) from pg_policies
     where schemaname='public' and tablename='painel_producao_presenca')                     as politicas_presenca,
  (select count(*) from pg_publication_tables
     where pubname='supabase_realtime' and schemaname='public'
       and tablename in ('painel_producao_log','painel_producao_presenca'))                  as no_realtime;
