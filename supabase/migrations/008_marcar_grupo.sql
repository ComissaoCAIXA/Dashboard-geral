-- Marcação rápida de membro do grupo pela área da comissão (fica registrada no histórico com o e-mail)
create function public.comissao_marcar_grupo(p_id bigint, p_no_grupo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  update public.aprovados
     set no_grupo = p_no_grupo,
         no_grupo_em = case when p_no_grupo then coalesce(no_grupo_em, current_date) else null end
   where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'erro', 'Aprovado não encontrado.'); end if;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.comissao_marcar_grupo(bigint, boolean) from public, anon;
grant execute on function public.comissao_marcar_grupo(bigint, boolean) to authenticated;
