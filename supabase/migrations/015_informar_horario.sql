-- Quem já foi convocado pode informar só o horário da convocação (novo tipo de pedido).
-- Aplicada em duas partes: o novo valor do tipo precisa existir antes de ser usado.

-- Parte 1
alter type public.tipo_envio add value if not exists 'Horário da convocação';

-- Parte 2
-- Busca devolve também o horário já registrado
create or replace function public.buscar_inscricao(p_inscricao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a record; pend boolean; pend_g boolean;
begin
  perform public._limitar('buscar', 20, interval '10 minutes');
  p_inscricao := regexp_replace(coalesce(p_inscricao, ''), '\D', '', 'g');
  if p_inscricao !~ '^[0-9]{6,12}$' then
    return jsonb_build_object('ok', false, 'erro', 'Digite só os números da sua inscrição.');
  end if;
  select id, nome_publico, cargo, uf, cota, situacao, posicao_uf, convocacao, data_convocacao, hora_convocacao, no_grupo into a
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
    'no_grupo', a.no_grupo, 'pendente', pend, 'pendente_grupo', pend_g);
end $$;

-- Envio: novo tipo, com horário obrigatório; a data vem da convocação já registrada se não for informada
create or replace function public.enviar_pedido(p_inscricao text, p_tipo text, p_data date, p_observacao text,
  p_telefone text default null, p_nome_whatsapp text default null, p_hora time default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a record; t public.tipo_envio; v_prot text; permitidos text[]; tel text;
begin
  perform public._limitar('enviar', 5, interval '1 hour');
  p_inscricao := regexp_replace(coalesce(p_inscricao, ''), '\D', '', 'g');
  select id, cargo, inscricao, convocacao, data_convocacao into a from public.aprovados where inscricao = p_inscricao;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Não encontramos essa inscrição entre os aprovados.');
  end if;
  if p_tipo is null or p_tipo not in ('Convocação', 'Posse', 'Desistência', 'Correção de dados', 'Entrada no grupo', 'Horário da convocação') then
    return jsonb_build_object('ok', false, 'erro', 'Escolha o que você quer fazer.');
  end if;
  t := p_tipo::public.tipo_envio;
  if length(coalesce(p_observacao, '')) > 1000 then
    return jsonb_build_object('ok', false, 'erro', 'A observação pode ter no máximo 1000 caracteres.');
  end if;

  if t = 'Entrada no grupo' then
    tel := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
    if length(tel) in (10, 11) then tel := '55' || tel; end if;
    if tel !~ '^55[1-9][0-9][0-9]{8,9}$' then
      return jsonb_build_object('ok', false, 'erro', 'Informe o WhatsApp com DDD, por exemplo (61) 99999-9999.');
    end if;
    if length(coalesce(p_nome_whatsapp, '')) > 60 then
      return jsonb_build_object('ok', false, 'erro', 'O nome no WhatsApp pode ter no máximo 60 caracteres.');
    end if;
    if exists (select 1 from public.envios where aprovado_id = a.id and status = 'Pendente' and tipo = 'Entrada no grupo') then
      return jsonb_build_object('ok', false, 'erro', 'Já existe um pedido de entrada no grupo desta inscrição em análise.');
    end if;
    insert into public.envios (cargo, inscricao, tipo, observacao, telefone, nome_whatsapp)
    values (a.cargo, a.inscricao, t, nullif(trim(p_observacao), ''), tel, nullif(trim(p_nome_whatsapp), ''))
    returning protocolo into v_prot;
    return jsonb_build_object('ok', true, 'protocolo', v_prot);
  end if;

  permitidos := case a.convocacao::text
    when 'Convocado'  then array['Posse', 'Desistência', 'Convocação', 'Horário da convocação', 'Correção de dados']
    when 'Empossado'  then array['Desistência', 'Horário da convocação', 'Correção de dados']
    when 'Desistente' then array['Correção de dados']
    else array['Convocação', 'Desistência', 'Correção de dados'] end;
  if not (p_tipo = any (permitidos)) then
    return jsonb_build_object('ok', false, 'erro', 'Essa opção não vale para a sua situação atual.');
  end if;
  if t = 'Horário da convocação' then
    if p_hora is null then return jsonb_build_object('ok', false, 'erro', 'Informe o horário da convocação.'); end if;
    p_data := coalesce(p_data, a.data_convocacao);
  end if;
  if t in ('Convocação', 'Posse', 'Horário da convocação') and p_data is null then
    return jsonb_build_object('ok', false, 'erro', 'Informe a data.');
  end if;
  if p_data is not null and (p_data > current_date or p_data < date '2026-05-26') then
    return jsonb_build_object('ok', false, 'erro', 'A data precisa estar entre a homologação (26/05/2026) e hoje.');
  end if;
  if exists (select 1 from public.envios where aprovado_id = a.id and status = 'Pendente' and tipo <> 'Entrada no grupo') then
    return jsonb_build_object('ok', false, 'erro',
      'Já existe um pedido desta inscrição em análise. Aguarde a comissão ou fale com ela no grupo de WhatsApp.');
  end if;
  insert into public.envios (cargo, inscricao, tipo, data_evento, hora_evento, observacao)
  values (a.cargo, a.inscricao, t, p_data, case when t in ('Convocação', 'Horário da convocação') then p_hora end,
          nullif(trim(p_observacao), ''))
  returning protocolo into v_prot;
  return jsonb_build_object('ok', true, 'protocolo', v_prot);
end $$;

-- Aprovação do novo tipo: grava horário (e data) e marca a convocação como confirmada
create or replace function public.envios_ao_revisar() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.status is distinct from old.status then
    new.revisado_em := now();
    if new.status <> 'Pendente' then
      new.telefone := null;
      new.nome_whatsapp := null;
    end if;
    if new.status = 'Aprovado' and new.aprovado_id is not null then
      if new.tipo = 'Convocação' then
        update public.aprovados set convocacao = 'Convocado', validacao = 'Confirmada',
               data_convocacao = coalesce(new.data_evento, data_convocacao),
               hora_convocacao = coalesce(new.hora_evento, hora_convocacao)
         where id = new.aprovado_id;
      elsif new.tipo = 'Horário da convocação' then
        update public.aprovados set
               hora_convocacao = coalesce(new.hora_evento, hora_convocacao),
               data_convocacao = coalesce(new.data_evento, data_convocacao),
               validacao = case when convocacao in ('Convocado', 'Empossado', 'Desistente') then 'Confirmada' else validacao end
         where id = new.aprovado_id;
      elsif new.tipo = 'Posse' then
        update public.aprovados set convocacao = 'Empossado', validacao = 'Confirmada',
               data_posse = coalesce(new.data_evento, data_posse)
         where id = new.aprovado_id;
      elsif new.tipo = 'Desistência' then
        update public.aprovados set convocacao = 'Desistente', validacao = 'Confirmada' where id = new.aprovado_id;
      elsif new.tipo = 'Entrada no grupo' then
        update public.aprovados set no_grupo = true, no_grupo_em = coalesce(no_grupo_em, current_date)
         where id = new.aprovado_id;
      end if;
    end if;
  end if;
  return new;
end $$;

-- Consulta do protocolo mostra o horário informado
create or replace function public.consultar_protocolo(p_codigo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e record; c text;
begin
  perform public._limitar('consultar', 30, interval '10 minutes');
  c := upper(regexp_replace(coalesce(p_codigo, ''), '[^A-Za-z0-9]', '', 'g'));
  if length(c) <> 6 then
    return jsonb_build_object('ok', false, 'erro', 'O protocolo tem 6 letras e números, como K7P-4QX.');
  end if;
  c := substr(c, 1, 3) || '-' || substr(c, 4, 3);
  select tipo, data_evento, hora_evento, status, criado_em, revisado_em, resposta_comissao into e
    from public.envios where protocolo = c;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Protocolo não encontrado. Confira o código.');
  end if;
  return jsonb_build_object('ok', true, 'protocolo', c, 'tipo', e.tipo, 'data_evento', e.data_evento,
    'hora_evento', e.hora_evento, 'status', e.status, 'enviado_em', e.criado_em, 'revisado_em', e.revisado_em,
    'resposta', e.resposta_comissao,
    'expira_em', case when e.tipo = 'Entrada no grupo' and e.status = 'Pendente' then e.criado_em + interval '24 hours' end);
end $$;

-- Pedidos pendentes: avisa se a pessoa já tem horário registrado
create or replace function public.comissao_pendentes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  return coalesce((
    select jsonb_agg(x order by x.criado_em)
    from (
      select e.id, e.protocolo, e.tipo, e.data_evento, e.hora_evento, e.observacao, e.criado_em,
             e.telefone, e.nome_whatsapp,
             case when e.tipo = 'Entrada no grupo' then e.criado_em + interval '24 hours' end as expira_em,
             a.id as aprovado_id, a.nome, a.inscricao, a.cargo, a.uf, a.macropolo, a.cota, a.situacao,
             a.posicao_uf, a.nota, a.convocacao, a.data_convocacao, a.data_posse, a.no_grupo,
             array_remove(array[
               case when e.tipo = 'Convocação' and a.situacao = 'Cadastro reserva' and exists (
                      select 1 from public.aprovados b
                       where b.cargo = a.cargo and b.uf = a.uf and b.cota = a.cota
                         and b.situacao = 'Vaga imediata' and b.convocacao = 'Aguardando')
                    then 'Pessoa do cadastro reserva, mas ainda há vagas imediatas aguardando no mesmo cargo, estado e cota.' end,
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
                    then 'Já consta como verificada e membro do grupo.' end
             ], null) as alertas
        from public.envios e join public.aprovados a on a.id = e.aprovado_id
       where e.status = 'Pendente'
    ) x), '[]'::jsonb);
end $$;
