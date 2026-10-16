-- 1) A pessoa pode ter mais de um pedido em análise ao mesmo tempo. Só não pode repetir um pedido
--    do mesmo tipo que ainda esteja em análise. buscar_inscricao informa quais tipos estão em análise,
--    para o formulário marcar essas opções como "já em análise".
-- 2) A comissão consegue ver os pedidos já analisados (aprovados, não aprovados e expirados),
--    com quem decidiu e quando, para tirar dúvidas depois.

create or replace function public.buscar_inscricao(p_inscricao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a record; pend boolean; pend_g boolean; tipos jsonb;
begin
  perform public._limitar('buscar', 20, interval '10 minutes');
  p_inscricao := regexp_replace(coalesce(p_inscricao, ''), '\D', '', 'g');
  if p_inscricao !~ '^[0-9]{6,12}$' then
    return jsonb_build_object('ok', false, 'erro', 'Digite só os números da sua inscrição.');
  end if;
  select id, nome_publico, cargo, uf, cota, situacao, posicao_uf, convocacao, data_convocacao, hora_convocacao, no_grupo, final_fila into a
    from public.aprovados where inscricao = p_inscricao;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Não encontramos essa inscrição entre os aprovados.');
  end if;
  select exists (select 1 from public.envios where aprovado_id = a.id and status = 'Pendente' and tipo <> 'Entrada no grupo'),
         exists (select 1 from public.envios where aprovado_id = a.id and status = 'Pendente' and tipo = 'Entrada no grupo'),
         coalesce((select jsonb_agg(distinct tipo) from public.envios where aprovado_id = a.id and status = 'Pendente'), '[]'::jsonb)
    into pend, pend_g, tipos;
  return jsonb_build_object('ok', true, 'nome', a.nome_publico, 'cargo', a.cargo, 'uf', a.uf,
    'cota', a.cota, 'situacao', a.situacao, 'posicao_uf', a.posicao_uf,
    'convocacao', a.convocacao, 'data_convocacao', a.data_convocacao, 'hora_convocacao', a.hora_convocacao,
    'no_grupo', a.no_grupo, 'final_fila', a.final_fila, 'pendente', pend, 'pendente_grupo', pend_g,
    'pendentes_tipos', tipos);
end $$;

create or replace function public.enviar_pedidos(p_inscricao text, p_itens jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a record; it jsonb; t public.tipo_envio; tipos text[]; permitidos text[]; repetido text;
        v_data date; v_hora time; v_obs text; v_prot text; v_lote text; n int := 0;
begin
  perform public._limitar('enviar', 5, interval '1 hour');
  p_inscricao := regexp_replace(coalesce(p_inscricao, ''), '\D', '', 'g');
  select id, cargo, inscricao, convocacao, data_convocacao, final_fila into a from public.aprovados where inscricao = p_inscricao;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Não encontramos essa inscrição entre os aprovados.');
  end if;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    return jsonb_build_object('ok', false, 'erro', 'Escolha o que você quer fazer.');
  end if;
  if jsonb_array_length(p_itens) > 4 then
    return jsonb_build_object('ok', false, 'erro', 'Escolha no máximo 4 pedidos de uma vez.');
  end if;
  select array_agg(x ->> 'tipo') into tipos from jsonb_array_elements(p_itens) x;
  if (select count(distinct v) from unnest(tipos) v) <> cardinality(tipos) then
    return jsonb_build_object('ok', false, 'erro', 'O mesmo pedido foi escolhido mais de uma vez.');
  end if;
  -- Um pedido do mesmo tipo ainda em análise: não repete (os demais tipos podem ser enviados)
  select e.tipo::text into repetido from public.envios e
   where e.aprovado_id = a.id and e.status = 'Pendente' and e.tipo::text = any (tipos) limit 1;
  if repetido is not null then
    return jsonb_build_object('ok', false, 'erro',
      'Você já tem um pedido de "' || repetido || '" em análise. Aguarde a comissão ou desmarque essa opção.');
  end if;

  permitidos := case a.convocacao::text
    when 'Convocado'  then array['Posse', 'Desistência', 'Convocação', 'Horário da convocação', 'Correção de dados']
    when 'Empossado'  then array['Desistência', 'Horário da convocação', 'Correção de dados']
    when 'Desistente' then array['Correção de dados']
    else array['Convocação', 'Desistência', 'Correção de dados'] end;
  if a.final_fila then
    permitidos := permitidos || array['Retirar final da fila'];
  elsif a.convocacao::text in ('Aguardando', 'Sem informação', 'Convocado') then
    permitidos := permitidos || array['Final da fila'];
  end if;
  if exists (select 1 from unnest(tipos) v where v is null or not (v = any (permitidos))) then
    return jsonb_build_object('ok', false, 'erro', 'Alguma opção escolhida não vale para a sua situação atual.');
  end if;
  if (select count(*) from unnest(tipos) v where v in ('Convocação', 'Posse', 'Desistência')) > 1 then
    return jsonb_build_object('ok', false, 'erro', 'Escolha só uma entre convocação, posse e desistência.');
  end if;
  if 'Convocação' = any (tipos) and 'Horário da convocação' = any (tipos) then
    return jsonb_build_object('ok', false, 'erro', 'O horário já vai junto com a convocação: escolha só uma das duas opções.');
  end if;
  if 'Desistência' = any (tipos) and 'Final da fila' = any (tipos) then
    return jsonb_build_object('ok', false, 'erro', 'Quem desiste da vaga não pede o final da fila: escolha só uma das duas opções.');
  end if;

  for it in select x from jsonb_array_elements(p_itens) x loop
    t := (it ->> 'tipo')::public.tipo_envio;
    v_obs := nullif(trim(coalesce(it ->> 'observacao', '')), '');
    if length(coalesce(v_obs, '')) > 1000 then
      raise exception 'A observação pode ter no máximo 1000 caracteres.';
    end if;
    begin
      v_data := nullif(it ->> 'data', '')::date;
      v_hora := nullif(it ->> 'hora', '')::time;
    exception when others then
      raise exception 'Data ou horário inválido.';
    end;
    if t not in ('Convocação', 'Posse', 'Desistência', 'Horário da convocação') then v_data := null; end if;
    if t not in ('Convocação', 'Horário da convocação') then v_hora := null; end if;
    if t = 'Horário da convocação' then
      if v_hora is null then raise exception 'Informe o horário da convocação.'; end if;
      v_data := coalesce(v_data, a.data_convocacao);
    end if;
    if t in ('Convocação', 'Posse', 'Horário da convocação') and v_data is null then
      raise exception 'Informe a data.';
    end if;
    if v_data is not null and (v_data > current_date or v_data < date '2026-05-26') then
      raise exception 'A data precisa estar entre a homologação (26/05/2026) e hoje.';
    end if;
    if t = 'Correção de dados' and v_obs is null then
      raise exception 'Conte o que está errado no campo de observação.';
    end if;
    insert into public.envios (cargo, inscricao, tipo, data_evento, hora_evento, observacao, lote)
    values (a.cargo, a.inscricao, t, v_data, v_hora, v_obs, v_lote)
    returning protocolo into v_prot;
    v_lote := coalesce(v_lote, v_prot);
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'protocolo', v_lote, 'pedidos', n);
end $$;

-- Alerta extra para a comissão: a pessoa tem outro pedido em análise enviado em outro momento
create or replace function public._alertas_pedido(p_envio bigint) returns text[]
language sql stable security definer set search_path = '' as $$
  select array_remove(array[
    case when e.tipo = 'Convocação' and a.situacao = 'Cadastro reserva' and exists (
           select 1 from public.aprovados b
            where b.cargo = a.cargo and b.uf = a.uf and b.cota = a.cota
              and b.situacao = 'Vaga imediata' and b.convocacao = 'Aguardando')
         then 'Pessoa do cadastro reserva, mas ainda há vagas imediatas aguardando no mesmo cargo, estado e cota.' end,
    case when e.tipo = 'Convocação' and (select count(*) from public.aprovados b
              where b.cargo = a.cargo and b.uf = a.uf and b.cota = a.cota
                and b.posicao_uf < a.posicao_uf and b.convocacao in ('Aguardando', 'Sem informação')) > 0
         then (select count(*) from public.aprovados b
                where b.cargo = a.cargo and b.uf = a.uf and b.cota = a.cota
                  and b.posicao_uf < a.posicao_uf and b.convocacao in ('Aguardando', 'Sem informação'))::text
              || ' pessoa(s) à frente na mesma lista (cargo, estado e cota) ainda sem convocação registrada.' end,
    case when e.tipo in ('Convocação', 'Posse') and a.convocacao = 'Desistente'
         then 'A pessoa consta como desistente.' end,
    case when e.tipo = 'Posse' and a.data_convocacao is not null and e.data_evento < a.data_convocacao
         then 'Data da posse é anterior à data da convocação registrada.' end,
    case when e.tipo = 'Convocação' and a.convocacao = 'Convocado' and e.data_evento = a.data_convocacao
         then 'Já consta como convocada nesta mesma data.' end,
    case when e.tipo = 'Horário da convocação' and a.hora_convocacao is not null
         then 'Já há um horário registrado: ' || to_char(a.hora_convocacao, 'HH24:MI') || '. Aprovar substitui.' end,
    case when e.tipo = 'Horário da convocação' and a.data_convocacao is not null and e.data_evento <> a.data_convocacao
         then 'A data informada é diferente da data de convocação registrada (' || to_char(a.data_convocacao, 'DD/MM/YYYY') || ').' end,
    case when e.tipo = 'Entrada no grupo' and a.no_grupo
         then 'Já consta como verificada e membro do grupo.' end,
    case when e.tipo = 'Final da fila' and a.final_fila
         then 'Já consta que pretende pedir o final da fila.' end,
    case when e.tipo = 'Final da fila' and a.convocacao in ('Empossado', 'Desistente')
         then 'A pessoa consta como ' || a.convocacao::text || ': o final da fila não se aplica.' end,
    case when e.tipo = 'Retirar final da fila' and not a.final_fila
         then 'Não consta indicação de final da fila para retirar.' end,
    case when e.lote is not null or exists (select 1 from public.envios x where x.lote = e.protocolo)
         then 'Enviado junto com outro(s) pedido(s) (protocolo ' || coalesce(e.lote, e.protocolo) || '): cada um é aprovado separadamente.' end,
    case when exists (select 1 from public.envios x
                       where x.aprovado_id = e.aprovado_id and x.id <> e.id and x.status = 'Pendente'
                         and x.tipo <> 'Entrada no grupo' and coalesce(x.lote, x.protocolo) <> coalesce(e.lote, e.protocolo))
         then 'A pessoa tem outro pedido em análise, enviado em outro momento: confira os dois juntos.' end
  ], null)
  from public.envios e join public.aprovados a on a.id = e.aprovado_id
  where e.id = p_envio
$$;

-- Pedidos já analisados (mais recentes primeiro), com quem decidiu
create function public.comissao_pedidos_analisados(p_limite int default 300) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  return coalesce((
    select jsonb_agg(x order by x.revisado_em desc nulls last, x.id desc)
    from (
      select e.id, e.protocolo, coalesce(e.lote, e.protocolo) as envio, e.tipo, e.data_evento, e.hora_evento,
             e.observacao, e.status, e.resposta_comissao, e.criado_em, e.revisado_em,
             a.nome, a.inscricao, a.cargo, a.uf, a.cota,
             (select h.feito_por from public.historico h
               where h.tabela = 'envios' and h.registro_id = e.id and h.acao = 'UPDATE'
                 and (h.depois ->> 'status') is distinct from (h.antes ->> 'status')
               order by h.id desc limit 1) as decidido_por
        from public.envios e left join public.aprovados a on a.id = e.aprovado_id
       where e.status <> 'Pendente'
       order by e.revisado_em desc nulls last, e.id desc
       limit greatest(1, least(coalesce(p_limite, 300), 2000))
    ) x), '[]'::jsonb);
end $$;
revoke execute on function public.comissao_pedidos_analisados(int) from public, anon;
grant execute on function public.comissao_pedidos_analisados(int) to authenticated;
