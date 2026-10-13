-- =====================================================================
-- 1) Nomes completos no painel público (decisão da comissão), com opção de ocultar
-- 2) Tabela de membros da comissão (preenchida à mão no Table Editor)
-- 3) Área da comissão: leitura completa e ações registradas com o e-mail de quem fez
-- =====================================================================

-- ---------- 1) Nome público ----------
alter table public.aprovados add column ocultar_nome boolean not null default false;
comment on column public.aprovados.ocultar_nome is 'Marque se a pessoa pediu para não ter o nome completo no painel (aparecem só as iniciais).';
alter table public.aprovados add column nome_publico text
  generated always as (case when ocultar_nome then public.iniciais(nome) else nome end) stored;
comment on column public.aprovados.nome_publico is 'Automático: nome completo, ou iniciais se "ocultar_nome" estiver marcado.';
grant select (nome_publico) on public.aprovados to anon;

create or replace function public.buscar_inscricao(p_inscricao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a record; pend boolean;
begin
  perform public._limitar('buscar', 20, interval '10 minutes');
  p_inscricao := regexp_replace(coalesce(p_inscricao, ''), '\D', '', 'g');
  if p_inscricao !~ '^[0-9]{6,12}$' then
    return jsonb_build_object('ok', false, 'erro', 'Digite só os números da sua inscrição.');
  end if;
  select id, nome_publico, cargo, uf, cota, situacao, posicao_uf, convocacao, data_convocacao into a
    from public.aprovados where inscricao = p_inscricao;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Não encontramos essa inscrição entre os aprovados.');
  end if;
  select exists (select 1 from public.envios where aprovado_id = a.id and status = 'Pendente') into pend;
  return jsonb_build_object('ok', true, 'nome', a.nome_publico, 'cargo', a.cargo, 'uf', a.uf,
    'cota', a.cota, 'situacao', a.situacao, 'posicao_uf', a.posicao_uf,
    'convocacao', a.convocacao, 'data_convocacao', a.data_convocacao, 'pendente', pend);
end $$;

-- ---------- 2) Membros da comissão ----------
create table public.comissao (
  email     text primary key check (email = lower(trim(email)) and email like '%_@_%._%'),
  nome      text,
  ativo     boolean not null default true,
  criado_em timestamptz not null default now()
);
comment on table public.comissao is 'Quem pode entrar na área da comissão. Para incluir alguém, adicione uma linha com o e-mail (minúsculo). Para tirar o acesso, desmarque "ativo".';
alter table public.comissao enable row level security;
revoke all on public.comissao from anon, authenticated;

-- E-mail sempre minúsculo e sem espaços (evita erro de digitação no Table Editor)
create function public.comissao_normalizar() returns trigger
language plpgsql set search_path = '' as $$
begin new.email := lower(trim(new.email)); return new; end $$;
create trigger comissao_normalizar before insert or update on public.comissao
for each row execute function public.comissao_normalizar();

-- Quem está logado é membro ativo da comissão?
create function public.eh_comissao() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.comissao c
                  where c.ativo and c.email = lower(coalesce(auth.jwt() ->> 'email', '')))
$$;

-- ---------- 3) Leitura completa para a comissão (via RLS) ----------
-- O público (anon) continua com as colunas limitadas. Usuários logados só leem se forem da comissão.
drop policy if exists "Leitura pública sem dados pessoais" on public.aprovados;
create policy "Leitura pública sem dados pessoais" on public.aprovados
  for select to anon using (true);
create policy "Comissão lê tudo" on public.aprovados
  for select to authenticated using (public.eh_comissao());
revoke select on public.aprovados from authenticated;
grant select on public.aprovados to authenticated;

grant select on public.envios, public.historico to authenticated;
create policy "Comissão lê envios" on public.envios
  for select to authenticated using (public.eh_comissao());
create policy "Comissão lê histórico" on public.historico
  for select to authenticated using (public.eh_comissao());

-- ---------- Funções da área da comissão ----------
-- Todas checam se quem chamou é membro ativo; o histórico registra o e-mail (feito_por).

create function public.comissao_eu() returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when public.eh_comissao()
    then jsonb_build_object('ok', true, 'email', c.email, 'nome', c.nome)
    else jsonb_build_object('ok', false) end
  from (select 1) x left join public.comissao c on c.email = lower(coalesce(auth.jwt() ->> 'email', ''))
$$;

-- Pedidos pendentes com os dados completos da pessoa e alertas automáticos
create function public.comissao_pendentes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  return coalesce((
    select jsonb_agg(x order by x.criado_em)
    from (
      select e.id, e.protocolo, e.tipo, e.data_evento, e.observacao, e.criado_em,
             a.id as aprovado_id, a.nome, a.inscricao, a.cargo, a.uf, a.macropolo, a.cota, a.situacao,
             a.posicao_uf, a.nota, a.convocacao, a.data_convocacao, a.data_posse,
             array_remove(array[
               case when e.tipo = 'Convocação' and a.situacao = 'Cadastro reserva' and exists (
                      select 1 from public.aprovados b
                       where b.cargo = a.cargo and b.uf = a.uf and b.cota = a.cota
                         and b.situacao = 'Vaga imediata' and b.convocacao = 'Aguardando')
                    then 'Pessoa do cadastro reserva, mas ainda há vagas imediatas aguardando no mesmo cargo, estado e cota.' end,
               case when e.tipo in ('Convocação', 'Posse') and a.convocacao = 'Desistente'
                    then 'A pessoa consta como desistente.' end,
               case when e.tipo = 'Posse' and a.data_convocacao is not null and e.data_evento < a.data_convocacao
                    then 'Data da posse é anterior à data da convocação registrada.' end,
               case when e.tipo = 'Convocação' and a.convocacao = 'Convocado' and e.data_evento = a.data_convocacao
                    then 'Já consta como convocada nesta mesma data.' end
             ], null) as alertas
        from public.envios e join public.aprovados a on a.id = e.aprovado_id
       where e.status = 'Pendente'
    ) x), '[]'::jsonb);
end $$;

-- Aprovar ou rejeitar um pedido (a aprovação aplica a mudança em "aprovados" pelo gatilho existente)
create function public.comissao_decidir(p_envio bigint, p_status text, p_resposta text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  if p_status not in ('Aprovado', 'Rejeitado') then raise exception 'Decisão inválida.'; end if;
  update public.envios
     set status = p_status::public.status_envio,
         resposta_comissao = nullif(trim(coalesce(p_resposta, '')), '')
   where id = p_envio and status = 'Pendente';
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('ok', false, 'erro', 'Este pedido já foi decidido por outro membro.'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- Editar a situação de um aprovado diretamente (quando a comissão confirmou por outro meio)
create function public.comissao_atualizar(p_id bigint, p_convocacao text, p_data_convocacao date,
  p_data_posse date, p_observacao text, p_ocultar_nome boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  update public.aprovados
     set convocacao = p_convocacao::public.convocacao,
         data_convocacao = p_data_convocacao,
         data_posse = p_data_posse,
         observacao = nullif(trim(coalesce(p_observacao, '')), ''),
         ocultar_nome = coalesce(p_ocultar_nome, false)
   where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'erro', 'Aprovado não encontrado.'); end if;
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.eh_comissao(), public.comissao_eu(), public.comissao_pendentes(),
  public.comissao_decidir(bigint, text, text),
  public.comissao_atualizar(bigint, text, date, date, text, boolean),
  public.comissao_normalizar() from public, anon;
grant execute on function public.eh_comissao(), public.comissao_eu(), public.comissao_pendentes(),
  public.comissao_decidir(bigint, text, text),
  public.comissao_atualizar(bigint, text, date, date, text, boolean) to authenticated;
