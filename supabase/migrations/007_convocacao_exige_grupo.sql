-- Para informar convocação/posse/desistência/correção, a pessoa precisa estar no grupo de WhatsApp
-- (é por lá que a comissão confirma). Quem não está é orientado a pedir a entrada primeiro.

create or replace function public.buscar_inscricao(p_inscricao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a record; pend boolean; pend_g boolean;
begin
  perform public._limitar('buscar', 20, interval '10 minutes');
  p_inscricao := regexp_replace(coalesce(p_inscricao, ''), '\D', '', 'g');
  if p_inscricao !~ '^[0-9]{6,12}$' then
    return jsonb_build_object('ok', false, 'erro', 'Digite só os números da sua inscrição.');
  end if;
  select id, nome_publico, cargo, uf, cota, situacao, posicao_uf, convocacao, data_convocacao, no_grupo into a
    from public.aprovados where inscricao = p_inscricao;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Não encontramos essa inscrição entre os aprovados.');
  end if;
  select exists (select 1 from public.envios where aprovado_id = a.id and status = 'Pendente' and tipo <> 'Entrada no grupo'),
         exists (select 1 from public.envios where aprovado_id = a.id and status = 'Pendente' and tipo = 'Entrada no grupo')
    into pend, pend_g;
  return jsonb_build_object('ok', true, 'nome', a.nome_publico, 'cargo', a.cargo, 'uf', a.uf,
    'cota', a.cota, 'situacao', a.situacao, 'posicao_uf', a.posicao_uf,
    'convocacao', a.convocacao, 'data_convocacao', a.data_convocacao,
    'no_grupo', a.no_grupo, 'pendente', pend, 'pendente_grupo', pend_g);
end $$;

-- Regra também no envio (não depende só da tela)
create or replace function public._exige_grupo() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.tipo <> 'Entrada no grupo'
     and not exists (select 1 from public.aprovados a where a.id = new.aprovado_id and a.no_grupo) then
    raise exception 'Para informar convocação, posse ou desistência, primeiro peça para entrar no grupo de WhatsApp dos aprovados.';
  end if;
  return new;
end $$;
-- roda depois de envios_ao_receber (que preenche aprovado_id): ordem alfabética dos gatilhos
create trigger envios_exige_grupo before insert on public.envios
for each row execute function public._exige_grupo();
revoke execute on function public._exige_grupo() from public, anon, authenticated;
