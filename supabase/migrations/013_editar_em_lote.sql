-- Área da comissão: edição em lote de vários aprovados de uma vez (todos os campos, menos a observação interna).
-- p_campos traz só o que deve mudar; o que não vier fica como está. Chaves aceitas:
--   convocacao (Aguardando | Convocado | Empossado | Desistente | Sem informação)
--   validacao (Confirmada | Presumida)
--   data_convocacao, data_posse (data, ou null para apagar)
--   no_grupo (true/false), ocultar_nome (true/false)
-- Voltar para Aguardando / Sem informação sem informar datas apaga as datas e a validação.
-- Substitui comissao_convocar e comissao_validar (que só mudavam a situação ou a validação).
drop function if exists public.comissao_convocar(bigint[], text, date, text);
drop function if exists public.comissao_validar(bigint[], text);

create function public.comissao_editar_lote(p_ids bigint[], p_campos jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  n int; v_conv text := p_campos ->> 'convocacao'; v_val text := p_campos ->> 'validacao';
  v_dc date; v_dp date; d date;
  limpa boolean := (p_campos ->> 'convocacao') in ('Aguardando', 'Sem informação');
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  if coalesce(array_length(p_ids, 1), 0) = 0 then return jsonb_build_object('ok', false, 'erro', 'Nenhuma pessoa selecionada.'); end if;
  if p_campos is null or p_campos = '{}'::jsonb then return jsonb_build_object('ok', false, 'erro', 'Escolha pelo menos um campo para alterar.'); end if;
  if v_conv is not null and v_conv not in ('Aguardando', 'Convocado', 'Empossado', 'Desistente', 'Sem informação') then
    return jsonb_build_object('ok', false, 'erro', 'Situação inválida.'); end if;
  if v_val is not null and v_val not in ('Confirmada', 'Presumida') then
    return jsonb_build_object('ok', false, 'erro', 'Validação inválida.'); end if;
  v_dc := nullif(p_campos ->> 'data_convocacao', '')::date;
  v_dp := nullif(p_campos ->> 'data_posse', '')::date;
  foreach d in array array[v_dc, v_dp] loop
    if d is not null and (d < date '2026-05-26' or d > current_date) then
      return jsonb_build_object('ok', false, 'erro', 'As datas precisam estar entre 26/05/2026 e hoje.'); end if;
  end loop;

  update public.aprovados set
    convocacao      = coalesce(v_conv::public.convocacao, convocacao),
    validacao       = case when v_val is not null then v_val::public.validacao_conv
                           when v_conv is not null and not limpa then coalesce(validacao, 'Confirmada')
                           else validacao end,
    data_convocacao = case when p_campos ? 'data_convocacao' then v_dc when limpa then null else data_convocacao end,
    data_posse      = case when p_campos ? 'data_posse' then v_dp when limpa then null else data_posse end,
    no_grupo        = coalesce((p_campos ->> 'no_grupo')::boolean, no_grupo),
    no_grupo_em     = case when coalesce((p_campos ->> 'no_grupo')::boolean, no_grupo) then coalesce(no_grupo_em, current_date) else null end,
    ocultar_nome    = coalesce((p_campos ->> 'ocultar_nome')::boolean, ocultar_nome)
  where id = any(p_ids);
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'alterados', n);
end $$;
revoke execute on function public.comissao_editar_lote(bigint[], jsonb) from public, anon;
grant execute on function public.comissao_editar_lote(bigint[], jsonb) to authenticated;
