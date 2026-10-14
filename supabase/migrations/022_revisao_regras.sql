-- Revisão geral (14/10/2026): correções de regra de negócio.

-- 1) Situação "Aguardando"/"Sem informação" não pode ter datas nem validação.
--    A edição em lote já limpava; a edição individual e o Table Editor deixavam datas para trás
--    (ex.: pessoa marcada como convocada por engano e voltada para Aguardando).
--    Também recusa datas fora do período do concurso.
create or replace function public._validacao_coerente() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.convocacao in ('Aguardando', 'Sem informação') then
    new.validacao := null;
    new.data_convocacao := null;
    new.hora_convocacao := null;
    new.data_posse := null;
  elsif new.validacao is null then
    new.validacao := 'Confirmada';
  end if;
  if new.data_convocacao is not null and (new.data_convocacao < date '2026-05-26' or new.data_convocacao > current_date + 1)
     or new.data_posse is not null and (new.data_posse < date '2026-05-26' or new.data_posse > current_date + 1) then
    raise exception 'As datas precisam estar entre a homologação (26/05/2026) e hoje.';
  end if;
  if new.data_posse is not null and new.data_convocacao is not null and new.data_posse < new.data_convocacao then
    raise exception 'A data da posse não pode ser anterior à data da convocação.';
  end if;
  return new;
end $$;
revoke execute on function public._validacao_coerente() from public, anon, authenticated;

-- 2) Histórico: pedidos enviados pelo site aparecem como "formulário" (antes saíam como "postgres",
--    porque as funções do formulário rodam com o dono do banco).
create or replace function public.registrar_historico() returns trigger
language plpgsql security definer set search_path = '' as $$
declare claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
begin
  insert into public.historico (tabela, registro_id, acao, antes, depois, feito_por)
  values (tg_table_name,
          coalesce(new.id, old.id),
          tg_op,
          case when tg_op <> 'INSERT' then to_jsonb(old) - 'telefone' - 'nome_whatsapp' end,
          case when tg_op <> 'DELETE' then to_jsonb(new) - 'telefone' - 'nome_whatsapp' end,
          coalesce(claims ->> 'email',
                   case when claims ->> 'role' = 'anon' then 'formulário'
                        when claims ->> 'role' = 'service_role' then 'automático'
                        else current_user end));
  return coalesce(new, old);
end $$;

-- 3) Mensagem de erro do grupo: vale para qualquer pedido, não só convocação, posse e desistência
create or replace function public._exige_grupo() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.tipo <> 'Entrada no grupo'
     and not exists (select 1 from public.aprovados a where a.id = new.aprovado_id and a.no_grupo) then
    raise exception 'Para enviar este pedido, primeiro peça para entrar no grupo de WhatsApp dos aprovados.';
  end if;
  return new;
end $$;
