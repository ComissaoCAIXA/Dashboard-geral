-- Avisos do Telegram sem dados pessoais: só o que chegou (tipo de pedido ou assunto da mensagem), o código
-- (protocolo do pedido ou MSG-<id> da mensagem), quando chegou e alertas sobre o pedido.
-- Nome, cargo, polo, cota, nota, observação, WhatsApp, e-mail e texto ficam só na área da comissão.
-- A função só devolve o mínimo, para nada além disso sair do banco rumo ao Telegram.
create or replace function public._telegram_reservar(p_tabela text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb; chat text := (select valor from public.configuracao where chave = 'telegram_chat_id');
begin
  if p_tabela = 'envios' then
    update public.envios e set telegram_enviado = true
     where e.id = p_id and not e.telegram_enviado and e.criado_em > now() - interval '10 minutes'
    returning jsonb_build_object('tabela', 'envios', 'id', e.id) into r;
    if r is not null then
      select jsonb_build_object('tabela', 'envios', 'protocolo', e.protocolo, 'envio', coalesce(e.lote, e.protocolo),
               'tipo', e.tipo, 'criado_em', e.criado_em, 'data', e.data_evento, 'hora', e.hora_evento,
               'final_fila_lista', e.final_fila_lista,
               'alertas', to_jsonb(public._alertas_pedido(e.id)),
               'pendentes', (select count(*) from public.envios x where x.status = 'Pendente'))
        into r
        from public.envios e
       where e.id = p_id;
    end if;
  elsif p_tabela = 'mensagens' then
    update public.mensagens m set telegram_enviado = true
     where m.id = p_id and not m.telegram_enviado and m.criado_em > now() - interval '10 minutes'
    returning jsonb_build_object('tabela', 'mensagens', 'id', m.id, 'assunto', m.assunto, 'criado_em', m.criado_em,
      'pendentes', (select count(*) from public.mensagens x where x.status = 'Nova'))
      into r;
  end if;
  return case when r is null then null else r || jsonb_build_object('chat', chat) end;
end $$;
