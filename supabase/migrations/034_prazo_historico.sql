-- Prazo de guarda do registro de alterações e dos pedidos já analisados: 4 anos, o prazo máximo de
-- validade do concurso (2 anos, prorrogáveis por mais 2). Depois disso, são apagados todo dia às 03:40.
create or replace function public._apagar_registros_antigos() returns void
language plpgsql security definer set search_path = '' as $$
declare ids bigint[];
begin
  with x as (delete from public.envios where status <> 'Pendente' and criado_em < now() - interval '4 years' returning id)
  select array_agg(id) into ids from x;
  -- o gatilho de histórico registra a exclusão com os dados do pedido: esse registro também sai
  delete from public.historico
   where feito_em < now() - interval '4 years'
      or (tabela = 'envios' and registro_id = any(coalesce(ids, '{}')));
end $$;
revoke execute on function public._apagar_registros_antigos() from public, anon, authenticated;
select cron.schedule('apagar-registros-antigos', '40 3 * * *', 'select public._apagar_registros_antigos()');
