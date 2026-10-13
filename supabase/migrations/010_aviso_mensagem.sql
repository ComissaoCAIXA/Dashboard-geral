-- Usadas só pela função avisar-mensagem (papel service_role); a tabela mensagens continua fechada.
-- Reserva a mensagem para o aviso: só funciona uma vez por mensagem e só nos 10 min após o envio.
create function public._aviso_reservar(p_id bigint) returns jsonb
language sql security definer set search_path = '' as $$
  update public.mensagens set aviso_enviado = true, aviso_erro = null
   where id = p_id and not aviso_enviado and criado_em > now() - interval '10 minutes'
  returning jsonb_build_object('id', id, 'nome', nome, 'email', email, 'assunto', assunto, 'mensagem', mensagem, 'criado_em', criado_em)
$$;
-- Registra a falha do envio (a mensagem continua na área da comissão, com o alerta)
create function public._aviso_falhou(p_id bigint, p_erro text) returns void
language sql security definer set search_path = '' as $$
  update public.mensagens set aviso_enviado = false, aviso_erro = left(p_erro, 300) where id = p_id
$$;
revoke execute on function public._aviso_reservar(bigint), public._aviso_falhou(bigint, text) from public, anon, authenticated;
grant execute on function public._aviso_reservar(bigint), public._aviso_falhou(bigint, text) to service_role;
