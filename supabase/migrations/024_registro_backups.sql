-- Registro dos backups diários, mostrado na aba "Backups" da área da comissão.
-- A tarefa do repositório privado ComissaoCAIXA/Dashboard-backup grava uma linha a cada execução
-- (sucesso ou falha). O usuário backup_leitura só pode INSERIR aqui; continua sem alterar mais nada.
-- Só metadados: nenhum dado de aprovado vai para esta tabela.

create table public.backups (
  id          bigint generated always as identity primary key,
  criado_em   timestamptz not null default now(),
  status      text not null check (status in ('ok', 'falha')),
  arquivo     text check (char_length(arquivo) <= 120),
  tamanho     integer check (tamanho >= 0),
  registros   jsonb,                       -- {"aprovados": 640, "envios": 12, ...}
  execucao    text check (execucao ~ '^https://github\.com/ComissaoCAIXA/Dashboard-backup/actions/runs/[0-9]+$'),
  erro        text check (char_length(erro) <= 300)
);
create index backups_recentes on public.backups (criado_em desc);
alter table public.backups enable row level security;
revoke all on public.backups from public, anon, authenticated;
grant select on public.backups to authenticated;
create policy "Comissão lê os backups" on public.backups
  for select to authenticated using (public.eh_comissao());
grant insert (status, arquivo, tamanho, registros, execucao, erro) on public.backups to backup_leitura;
create policy "Tarefa de backup registra" on public.backups
  for insert to backup_leitura with check (true);
comment on table public.backups is 'Registro de cada execução do backup diário (só metadados).';

-- Guarda só o último ano de registros
create or replace function public._limpar_limites() returns void
language sql security definer set search_path = '' as $$
  delete from public.limites where em < now() - interval '1 hour';
  delete from public._sal where hora < date_trunc('hour', now());
  delete from public.backups where criado_em < now() - interval '1 year';
$$;
revoke execute on function public._limpar_limites() from public, anon, authenticated;
