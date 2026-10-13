-- Validação da convocação: como a comissão sabe que a pessoa foi convocada.
--   Confirmada: a comissão falou com a pessoa (ou aprovou o pedido dela no formulário)
--   Presumida:  deduzida pela ordem de classificação (alguém atrás na mesma lista já foi convocado)
-- Vale para Convocado, Empossado e Desistente; fica vazia para Aguardando / Sem informação.

create type public.validacao_conv as enum ('Confirmada', 'Presumida');
alter table public.aprovados add column validacao public.validacao_conv;
grant select (validacao) on public.aprovados to anon;
comment on column public.aprovados.validacao is 'Confirmada (comissão falou com a pessoa) ou Presumida (pela ordem de classificação).';

-- Por decisão da comissão, as convocações já registradas contam como confirmadas
update public.aprovados set validacao = 'Confirmada' where convocacao in ('Convocado', 'Empossado', 'Desistente');

-- Mantém o campo coerente: vazio enquanto aguarda; Confirmada quando ninguém disser o contrário
create function public._validacao_coerente() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.convocacao in ('Aguardando', 'Sem informação') then
    new.validacao := null;
  elsif new.validacao is null then
    new.validacao := 'Confirmada';
  end if;
  return new;
end $$;
create trigger aprovados_validacao before insert or update of convocacao, validacao on public.aprovados
  for each row execute function public._validacao_coerente();

-- Pedido aprovado no formulário = a comissão falou com a pessoa: vira Confirmada
create or replace function public.envios_ao_revisar() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.status is distinct from old.status then
    new.revisado_em := now();
    if new.status <> 'Pendente' then
      new.telefone := null;
      new.nome_whatsapp := null;
    end if;
    if new.status = 'Aprovado' and new.aprovado_id is not null then
      if new.tipo = 'Convocação' then
        update public.aprovados set convocacao = 'Convocado', validacao = 'Confirmada',
               data_convocacao = coalesce(new.data_evento, data_convocacao)
         where id = new.aprovado_id;
      elsif new.tipo = 'Posse' then
        update public.aprovados set convocacao = 'Empossado', validacao = 'Confirmada',
               data_posse = coalesce(new.data_evento, data_posse)
         where id = new.aprovado_id;
      elsif new.tipo = 'Desistência' then
        update public.aprovados set convocacao = 'Desistente', validacao = 'Confirmada' where id = new.aprovado_id;
      elsif new.tipo = 'Entrada no grupo' then
        update public.aprovados set no_grupo = true, no_grupo_em = coalesce(no_grupo_em, current_date)
         where id = new.aprovado_id;
      end if;
    end if;
  end if;
  return new;
end $$;

-- Convocação em lote passa a receber a validação
drop function public.comissao_convocar(bigint[], text, date);
create function public.comissao_convocar(p_ids bigint[], p_convocacao text, p_data date default null,
                                         p_validacao text default 'Confirmada') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  if p_convocacao not in ('Convocado', 'Empossado', 'Desistente', 'Aguardando') then
    return jsonb_build_object('ok', false, 'erro', 'Situação inválida.');
  end if;
  if coalesce(p_validacao, 'Confirmada') not in ('Confirmada', 'Presumida') then
    return jsonb_build_object('ok', false, 'erro', 'Validação inválida.');
  end if;
  if p_convocacao in ('Convocado', 'Empossado') and p_data is null then
    return jsonb_build_object('ok', false, 'erro', 'Informe a data.');
  end if;
  if p_data is not null and (p_data < date '2026-05-26' or p_data > current_date) then
    return jsonb_build_object('ok', false, 'erro', 'A data precisa estar entre 26/05/2026 e hoje.');
  end if;
  if coalesce(array_length(p_ids, 1), 0) = 0 then
    return jsonb_build_object('ok', false, 'erro', 'Nenhuma pessoa selecionada.');
  end if;
  update public.aprovados
     set convocacao = p_convocacao::public.convocacao,
         validacao = case when p_convocacao = 'Aguardando' then null
                          else coalesce(p_validacao, 'Confirmada')::public.validacao_conv end,
         data_convocacao = case p_convocacao when 'Convocado' then p_data
                                             when 'Aguardando' then null
                                             else data_convocacao end,
         data_posse = case p_convocacao when 'Empossado' then p_data
                                        when 'Aguardando' then null
                                        else data_posse end
   where id = any(p_ids);
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'alterados', n);
end $$;
revoke execute on function public.comissao_convocar(bigint[], text, date, text) from public, anon;
grant execute on function public.comissao_convocar(bigint[], text, date, text) to authenticated;

-- Só troca a validação (ex.: a comissão encontrou a pessoa e confirmou)
create function public.comissao_validar(p_ids bigint[], p_validacao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  if p_validacao not in ('Confirmada', 'Presumida') then
    return jsonb_build_object('ok', false, 'erro', 'Validação inválida.');
  end if;
  update public.aprovados set validacao = p_validacao::public.validacao_conv
   where id = any(p_ids) and convocacao in ('Convocado', 'Empossado', 'Desistente');
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'alterados', n);
end $$;
revoke execute on function public.comissao_validar(bigint[], text) from public, anon;
grant execute on function public.comissao_validar(bigint[], text) to authenticated;

-- Edição completa ganha a validação (null = mantém como está)
drop function public.comissao_atualizar(bigint, text, date, date, text, boolean, boolean);
create function public.comissao_atualizar(p_id bigint, p_convocacao text, p_data_convocacao date, p_data_posse date,
  p_observacao text, p_ocultar_nome boolean, p_no_grupo boolean default null, p_validacao text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  update public.aprovados
     set convocacao = p_convocacao::public.convocacao,
         validacao = coalesce(p_validacao::public.validacao_conv, validacao),
         data_convocacao = p_data_convocacao,
         data_posse = p_data_posse,
         observacao = nullif(trim(coalesce(p_observacao, '')), ''),
         ocultar_nome = coalesce(p_ocultar_nome, false),
         no_grupo = coalesce(p_no_grupo, no_grupo),
         no_grupo_em = case when coalesce(p_no_grupo, no_grupo) then coalesce(no_grupo_em, current_date) else null end
   where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'erro', 'Aprovado não encontrado.'); end if;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.comissao_atualizar(bigint, text, date, date, text, boolean, boolean, text) from public, anon;
grant execute on function public.comissao_atualizar(bigint, text, date, date, text, boolean, boolean, text) to authenticated;

-- Sugestões: quem ainda aguarda, mas tem alguém atrás na mesma lista (cargo + estado + cota) já convocado
create function public.comissao_sugestoes_presumidas() returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when not public.eh_comissao() then null else coalesce(jsonb_agg(s order by s->>'cargo', s->>'uf', s->>'cota', (s->>'posicao_uf')::int), '[]') end
  from (
    select jsonb_build_object(
      'id', a.id, 'nome', a.nome, 'cargo', a.cargo, 'uf', a.uf, 'cota', a.cota, 'posicao_uf', a.posicao_uf, 'situacao', a.situacao,
      'ref_nome', r.nome, 'ref_posicao', r.posicao_uf, 'ref_convocacao', r.convocacao, 'ref_validacao', r.validacao,
      'ref_data', r.data_convocacao) s
    from public.aprovados a
    cross join lateral (
      select b.nome, b.posicao_uf, b.convocacao, b.validacao, b.data_convocacao
        from public.aprovados b
       where b.cargo = a.cargo and b.uf = a.uf and b.cota = a.cota and b.posicao_uf > a.posicao_uf
         and b.convocacao in ('Convocado', 'Empossado', 'Desistente')
       order by (b.validacao = 'Confirmada') desc, b.posicao_uf
       limit 1) r
    where a.convocacao in ('Aguardando', 'Sem informação')
  ) x
$$;
revoke execute on function public.comissao_sugestoes_presumidas() from public, anon;
grant execute on function public.comissao_sugestoes_presumidas() to authenticated;
