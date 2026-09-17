-- ============================================================
-- Painel de Producao: os dados saem do navegador e vao para a nuvem.
-- Uma linha so (id = 'principal') com o estado inteiro em jsonb.
-- O 'rev' e o que impede um PC com copia velha de apagar a
-- importacao que outro acabou de fazer: quem grava tem de dizer
-- qual rev leu, e se ela mudou o navegador funde e tenta de novo.
-- ============================================================

create table if not exists public.painel_producao (
  id             text        primary key,
  dados          jsonb       not null,
  rev            bigint      not null default 1,
  atualizado_em  timestamptz not null default now(),
  atualizado_por text
);

-- Historico: toda versao gravada fica guardada, para uma importacao
-- errada nao ser um caminho sem volta. Mantem as 20 ultimas.
create table if not exists public.painel_producao_hist (
  seq            bigserial   primary key,
  id             text        not null,
  rev            bigint      not null,
  dados          jsonb       not null,
  atualizado_em  timestamptz not null default now(),
  atualizado_por text
);

create index if not exists painel_producao_hist_id_rev
  on public.painel_producao_hist (id, rev desc);

create or replace function public.painel_producao_versionar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.painel_producao_hist (id, rev, dados, atualizado_em, atualizado_por)
  values (old.id, old.rev, old.dados, old.atualizado_em, old.atualizado_por);

  delete from public.painel_producao_hist h
   where h.id = old.id
     and h.seq < (
       select min(seq) from (
         select seq from public.painel_producao_hist
          where id = old.id order by seq desc limit 20
       ) ultimos
     );
  return new;
end;
$$;

drop trigger if exists trg_painel_producao_versionar on public.painel_producao;
create trigger trg_painel_producao_versionar
  before update on public.painel_producao
  for each row execute function public.painel_producao_versionar();

-- ------------------------------------------------------------
-- RLS. O painel nao tem login: a chave publicavel e a de todo
-- mundo. O que da para travar e travado: uma linha so, sem delete.
-- ------------------------------------------------------------
alter table public.painel_producao      enable row level security;
alter table public.painel_producao_hist enable row level security;

drop policy if exists painel_producao_ler      on public.painel_producao;
drop policy if exists painel_producao_criar    on public.painel_producao;
drop policy if exists painel_producao_alterar  on public.painel_producao;

create policy painel_producao_ler on public.painel_producao
  for select to anon, authenticated using (true);

create policy painel_producao_criar on public.painel_producao
  for insert to anon, authenticated with check (id = 'principal');

create policy painel_producao_alterar on public.painel_producao
  for update to anon, authenticated using (id = 'principal') with check (id = 'principal');

-- Historico: so leitura pelo navegador. Quem escreve nele e o gatilho.
drop policy if exists painel_producao_hist_ler on public.painel_producao_hist;
create policy painel_producao_hist_ler on public.painel_producao_hist
  for select to anon, authenticated using (true);

revoke all on public.painel_producao      from anon, authenticated;
revoke all on public.painel_producao_hist from anon, authenticated;
grant select, insert, update on public.painel_producao      to anon, authenticated;
grant select                 on public.painel_producao_hist to anon, authenticated;
grant usage, select on sequence public.painel_producao_hist_seq_seq to anon, authenticated;

-- ------------------------------------------------------------
-- Realtime: o outro PC ve a mudanca sem recarregar a pagina.
-- O navegador ignora o conteudo do evento e busca a linha de novo
-- (o jsonb pode estourar o limite de payload; o aviso basta).
-- ------------------------------------------------------------
do $$
begin
  alter publication supabase_realtime add table public.painel_producao;
exception
  when duplicate_object then null;
  when undefined_object then null;
end
$$;

-- Confere o que ficou de pe.
select
  (select count(*) from public.painel_producao)                                as linhas_painel,
  (select count(*) from pg_policies where tablename = 'painel_producao')       as politicas,
  (select count(*) from pg_publication_tables
     where pubname = 'supabase_realtime' and tablename = 'painel_producao')    as no_realtime;
