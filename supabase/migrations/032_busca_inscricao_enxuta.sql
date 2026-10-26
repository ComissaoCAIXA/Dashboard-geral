-- A busca de inscrição é pública e o número de inscrição também é público (homologação no DOU).
-- Por isso ela deixa de dizer QUAIS pedidos estão em análise: informa só que há pedido em análise.
-- Se a pessoa repetir um tipo que já está em análise, o envio (enviar_pedidos) avisa.
create or replace function public.buscar_inscricao(p_inscricao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a record; pend boolean; pend_g boolean;
begin
  perform public._limitar('buscar', 20, interval '10 minutes');
  p_inscricao := regexp_replace(coalesce(p_inscricao, ''), '\D', '', 'g');
  if p_inscricao !~ '^[0-9]{6,12}$' then
    return jsonb_build_object('ok', false, 'erro', 'Digite só os números da sua inscrição.');
  end if;
  select id, nome_publico, cargo, uf, cota, situacao, posicao_uf, convocacao, data_convocacao, hora_convocacao, no_grupo,
         final_fila, final_fila_confirmado into a
    from public.aprovados where inscricao = p_inscricao;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Não encontramos essa inscrição entre os aprovados.');
  end if;
  select exists (select 1 from public.envios where aprovado_id = a.id and status = 'Pendente' and tipo <> 'Entrada no grupo'),
         exists (select 1 from public.envios where aprovado_id = a.id and status = 'Pendente' and tipo = 'Entrada no grupo')
    into pend, pend_g;
  return jsonb_build_object('ok', true, 'nome', a.nome_publico, 'cargo', a.cargo, 'uf', a.uf,
    'cota', a.cota, 'situacao', a.situacao, 'posicao_uf', a.posicao_uf,
    'convocacao', a.convocacao, 'data_convocacao', a.data_convocacao, 'hora_convocacao', a.hora_convocacao,
    'no_grupo', a.no_grupo, 'final_fila', a.final_fila, 'final_fila_confirmado', a.final_fila_confirmado,
    'pendente', pend, 'pendente_grupo', pend_g);
end $$;
