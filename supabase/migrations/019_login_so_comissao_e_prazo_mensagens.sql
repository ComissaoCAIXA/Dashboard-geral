-- 1) Só e-mails da comissão podem ter conta.
--    O login da comissão usa o código/link por e-mail do Supabase. Sem esta regra, qualquer e-mail
--    digitado na tela de login virava uma conta nova (sem acesso a nada) e recebia um e-mail da comissão.
--    Esta função é chamada pelo Supabase Auth antes de criar qualquer conta ("Before User Created hook")
--    e recusa e-mails que não estão ativos na tabela comissao. Ativar em:
--    Authentication → Hooks → Before User Created → Postgres → public.hook_so_comissao
create or replace function public.hook_so_comissao(event jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if exists (select 1 from public.comissao
              where lower(email) = lower(event -> 'user' ->> 'email') and ativo) then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object('error', jsonb_build_object(
    'http_code', 403,
    'message', 'Este e-mail não está cadastrado na comissão.'));
end $$;
revoke execute on function public.hook_so_comissao(jsonb) from public, anon, authenticated;
grant execute on function public.hook_so_comissao(jsonb) to supabase_auth_admin;

-- 2) Mensagens do "Fale com a comissão" são apagadas 6 meses depois de recebidas
--    (o aviso por e-mail continua na caixa de entrada da comissão).
create or replace function public._apagar_mensagens_antigas() returns void
language sql security definer set search_path = '' as $$
  delete from public.mensagens where criado_em < now() - interval '6 months';
$$;
revoke execute on function public._apagar_mensagens_antigas() from public, anon, authenticated;
select cron.schedule('apagar-mensagens-antigas', '30 3 * * *', 'select public._apagar_mensagens_antigas()');
