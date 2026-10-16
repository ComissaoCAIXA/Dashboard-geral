-- Novo tipo de pedido: a CAIXA já confirmou a reclassificação para o final da fila
-- (em arquivo separado porque o valor novo do enum só pode ser usado depois desta transação).
alter type public.tipo_envio add value if not exists 'Reclassificação confirmada';
