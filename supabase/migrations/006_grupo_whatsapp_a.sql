-- Pedido de entrada no grupo de WhatsApp (parte 1: novos valores das listas)
alter type public.tipo_envio add value if not exists 'Entrada no grupo';
alter type public.status_envio add value if not exists 'Expirado';
