-- =====================================================================
-- Banco de dados dos aprovados — Concurso CAIXA 2026
-- Estrutura, regras de acesso e automações.
--
-- Quem acessa o quê:
--   * Público (site e formulário, chave "anon"):
--       - lê a tabela aprovados SEM nome e SEM inscrição (só iniciais);
--       - envia formulários para a tabela envios (sempre como "Pendente").
--   * Comissão: edita tudo pelo painel do Supabase (Table Editor).
-- =====================================================================

-- ---------- Listas de valores (viram menus no Table Editor) ----------
create type public.cargo as enum (
  'Arquiteto', 'Engenheiro Civil', 'Engenheiro Eletricista', 'Engenheiro Mecânico',
  'Engenheiro de Segurança do Trabalho', 'Médico do Trabalho');

create type public.uf as enum (
  'AC','AL','AM','AP','BA','CE','DF','ES','GO','MA','MG','MS','MT','PA',
  'PB','PE','PI','PR','RJ','RN','RO','RR','RS','SC','SE','SP','TO');

create type public.macropolo as enum ('Norte', 'Nordeste', 'Centro-Oeste', 'Sudeste', 'Sul');

-- Modalidades do edital (item 1.5). PN = pessoas negras ("PPP/PN" nas planilhas antigas)
create type public.cota as enum ('AC', 'PcD', 'PN', 'PI', 'PQ');

create type public.situacao as enum ('Vaga imediata', 'Cadastro reserva');

create type public.convocacao as enum (
  'Sem informação', 'Aguardando', 'Convocado', 'Empossado', 'Desistente');

create type public.tipo_envio as enum ('Convocação', 'Posse', 'Desistência', 'Correção de dados');

create type public.status_envio as enum ('Pendente', 'Aprovado', 'Rejeitado');

-- ---------- Funções auxiliares ----------
-- "João Paulo da Silva" -> "J. P. S."
create function public.iniciais(nome text) returns text
language sql immutable set search_path = '' as $$
  select string_agg(upper(left(p, 1)) || '.', ' ' order by ord)
  from unnest(regexp_split_to_array(trim(nome), '\s+')) with ordinality as t(p, ord)
  where lower(p) not in ('de', 'da', 'do', 'das', 'dos', 'e', 'd')
$$;

create function public.macropolo_da_uf(u public.uf) returns public.macropolo
language sql immutable set search_path = '' as $$
  select (case
    when u::text in ('AC','AM','AP','PA','RO','RR','TO') then 'Norte'
    when u::text in ('AL','BA','CE','MA','PB','PE','PI','RN','SE') then 'Nordeste'
    when u::text in ('DF','GO','MS','MT') then 'Centro-Oeste'
    when u::text in ('ES','MG','RJ','SP') then 'Sudeste'
    else 'Sul' end)::public.macropolo
$$;

-- ---------- Tabela principal ----------
create table public.aprovados (
  id              bigint generated always as identity primary key,
  inscricao       text not null check (inscricao ~ '^[0-9]{6,12}$'),
  nome            text not null check (length(trim(nome)) > 2),
  iniciais        text generated always as (public.iniciais(nome)) stored,
  cargo           public.cargo not null,
  uf              public.uf not null,
  macropolo       public.macropolo not null,  -- preenchido automaticamente pela UF
  cota            public.cota not null,
  situacao        public.situacao not null,
  nota            numeric(5,2) not null check (nota between 0 and 100),
  posicao_uf      integer not null check (posicao_uf > 0),
  class_macro     integer check (class_macro > 0),
  convocacao      public.convocacao not null default 'Aguardando',
  data_convocacao date,
  data_posse      date,
  observacao      text,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  unique (cargo, inscricao)
);
comment on table public.aprovados is 'Base oficial dos aprovados. Nome e inscrição nunca são expostos ao público.';
comment on column public.aprovados.macropolo is 'Preenchido automaticamente a partir da UF.';
comment on column public.aprovados.iniciais is 'Calculado automaticamente a partir do nome.';

create function public.aprovados_antes_salvar() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.macropolo := public.macropolo_da_uf(new.uf);
  new.atualizado_em := now();
  return new;
end $$;

create trigger aprovados_antes_salvar before insert or update on public.aprovados
for each row execute function public.aprovados_antes_salvar();

-- ---------- Envios do formulário ----------
create table public.envios (
  id            bigint generated always as identity primary key,
  cargo         public.cargo not null,
  inscricao     text not null check (inscricao ~ '^[0-9]{6,12}$'),
  tipo          public.tipo_envio not null,
  data_evento   date,
  observacao    text check (length(observacao) <= 1000),
  status        public.status_envio not null default 'Pendente',
  aprovado_id   bigint references public.aprovados (id) on delete set null,
  resposta_comissao text,
  criado_em     timestamptz not null default now(),
  revisado_em   timestamptz
);
comment on table public.envios is 'Informações enviadas pelo formulário. Só valem depois que a comissão muda o status para Aprovado.';

-- Ao receber: confere se a inscrição existe no cargo e força o status Pendente
create function public.envios_ao_receber() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  select a.id into new.aprovado_id from public.aprovados a
   where a.cargo = new.cargo and a.inscricao = new.inscricao;
  if new.aprovado_id is null then
    raise exception 'Inscrição não encontrada entre os aprovados deste cargo.' using errcode = 'P0002';
  end if;
  new.status := 'Pendente';
  new.revisado_em := null;
  new.resposta_comissao := null;
  new.criado_em := now();
  return new;
end $$;

create trigger envios_ao_receber before insert on public.envios
for each row execute function public.envios_ao_receber();

-- Ao aprovar: aplica a informação na tabela aprovados
create function public.envios_ao_revisar() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.status is distinct from old.status then
    new.revisado_em := now();
    if new.status = 'Aprovado' and new.aprovado_id is not null then
      if new.tipo = 'Convocação' then
        update public.aprovados set convocacao = 'Convocado',
               data_convocacao = coalesce(new.data_evento, data_convocacao)
         where id = new.aprovado_id;
      elsif new.tipo = 'Posse' then
        update public.aprovados set convocacao = 'Empossado',
               data_posse = coalesce(new.data_evento, data_posse)
         where id = new.aprovado_id;
      elsif new.tipo = 'Desistência' then
        update public.aprovados set convocacao = 'Desistente' where id = new.aprovado_id;
      end if;
      -- 'Correção de dados' é aplicada à mão pela comissão
    end if;
  end if;
  return new;
end $$;

create trigger envios_ao_revisar before update on public.envios
for each row execute function public.envios_ao_revisar();

-- ---------- Histórico de alterações ----------
create table public.historico (
  id          bigint generated always as identity primary key,
  tabela      text not null,
  registro_id bigint,
  acao        text not null,
  antes       jsonb,
  depois      jsonb,
  feito_por   text not null,
  feito_em    timestamptz not null default now()
);
comment on table public.historico is 'Registro automático de toda inclusão, alteração e exclusão em aprovados e envios.';

create function public.registrar_historico() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.historico (tabela, registro_id, acao, antes, depois, feito_por)
  values (tg_table_name,
          coalesce(new.id, old.id),
          tg_op,
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end,
          coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email',
                   case when current_user in ('anon') then 'formulário' else current_user end));
  return coalesce(new, old);
end $$;

create trigger aprovados_historico after insert or update or delete on public.aprovados
for each row execute function public.registrar_historico();
create trigger envios_historico after insert or update or delete on public.envios
for each row execute function public.registrar_historico();

-- ---------- Regras de acesso (RLS) ----------
alter table public.aprovados enable row level security;
alter table public.envios    enable row level security;
alter table public.historico enable row level security;

-- Ninguém de fora tem acesso a nada, a não ser o que está liberado abaixo
revoke all on public.aprovados, public.envios, public.historico from anon, authenticated;

-- Público lê aprovados, mas só estas colunas (sem nome e sem inscrição)
grant select (id, iniciais, cargo, uf, macropolo, cota, situacao, nota, posicao_uf,
              class_macro, convocacao, data_convocacao, data_posse, atualizado_em)
  on public.aprovados to anon, authenticated;
create policy "Leitura pública sem dados pessoais" on public.aprovados
  for select to anon, authenticated using (true);

-- Público só envia formulário (não lê envios de ninguém)
grant insert (cargo, inscricao, tipo, data_evento, observacao) on public.envios to anon, authenticated;
create policy "Envio pelo formulário" on public.envios
  for insert to anon, authenticated with check (status = 'Pendente');

-- Funções internas não são chamáveis pela API
revoke execute on function public.envios_ao_receber(), public.envios_ao_revisar(),
  public.registrar_historico(), public.aprovados_antes_salvar() from anon, authenticated, public;
