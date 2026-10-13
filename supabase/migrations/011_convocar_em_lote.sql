-- Área da comissão: muda a situação de convocação de uma ou várias pessoas de uma vez
-- (fica registrado no histórico com o e-mail de quem fez, como as demais alterações).
--   Convocado  -> grava a data da convocação
--   Empossado  -> grava a data da posse (mantém a data da convocação)
--   Desistente -> mantém as datas
--   Aguardando -> apaga as datas de convocação e posse
create function public.comissao_convocar(p_ids bigint[], p_convocacao text, p_data date default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  if p_convocacao not in ('Convocado', 'Empossado', 'Desistente', 'Aguardando') then
    return jsonb_build_object('ok', false, 'erro', 'Situação inválida.');
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
revoke execute on function public.comissao_convocar(bigint[], text, date) from public, anon;
grant execute on function public.comissao_convocar(bigint[], text, date) to authenticated;
