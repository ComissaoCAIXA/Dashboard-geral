-- Novos tipos de pedido: indicar que pretende pedir o final da fila (reclassificação para o fim da lista)
-- e retirar essa indicação. Em arquivo separado porque um valor novo de enum só pode ser usado
-- depois que a transação que o criou termina (o resto está em 026_final_da_fila_b.sql).
alter type public.tipo_envio add value if not exists 'Final da fila';
alter type public.tipo_envio add value if not exists 'Retirar final da fila';
