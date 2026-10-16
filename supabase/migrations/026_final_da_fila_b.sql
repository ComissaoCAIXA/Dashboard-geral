-- Final da fila e vários pedidos num mesmo envio.
--  * aprovados.final_fila: a pessoa declarou que pretende pedir a reclassificação para o final da lista.
--    É só uma intenção (não um pedido feito à CAIXA). Vale depois que a comissão aprova o pedido.
--    Aparece como selo no painel público e pode ser considerada na simulação da fila.
--  * envios.lote: pedidos enviados juntos (ex.: correção de dados + final da fila). O primeiro pedido
--    do envio fica com lote nulo; os demais guardam o protocolo do primeiro. A pessoa recebe um protocolo só.
--  * enviar_pedidos: novo envio do formulário, com um ou mais pedidos. Valida tudo antes de gravar
--    (se algo estiver errado, nada é gravado). enviar_pedido continua existindo para páginas antigas em cache.

alter table public.aprovados add column final_fila boolean not null default false,
                             add column final_fila_em date;
grant select (final_fila) on public.aprovados to anon;
comment on column public.aprovados.final_fila is 'A pessoa declarou que pretende pedir o final da fila (reclassificação para o fim da lista). Só intenção, conferida pela comissão.';

alter table public.envios add column lote text;
create index envios_lote on public.envios (lote) where lote is not null;
comment on column public.envios.lote is 'Protocolo do primeiro pedido do mesmo envio (nulo no primeiro).';

-- Aprovar o pedido aplica a mudança no cadastro
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
      elsif new.tipo = 'Final da fila' then
        update public.aprovados set final_fila = true, final_fila_em = coalesce(final_fila_em, current_date)
         where id = new.aprovado_id;
      elsif new.tipo = 'Retirar final da fila' then
        update public.aprovados set final_fila = false, final_fila_em = null where id = new.aprovado_id;
      end if;
    end if;
  end if;
  return new;
end $$;

-- Busca da inscrição no formulário: agora também informa se a pessoa já indicou o final da fila
create or replace function public.buscar_inscricao(p_inscricao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a record; pend boolean; pend_g boolean;
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
         exists (select 1 from public.envios where aprovado_id = a.id and status = 'Pendente' and tipo = 'Entrada no grupo')
    into pend, pend_g;
  return jsonb_build_object('ok', true, 'nome', a.nome_publico, 'cargo', a.cargo, 'uf', a.uf,
    'cota', a.cota, 'situacao', a.situacao, 'posicao_uf', a.posicao_uf,
    'convocacao', a.convocacao, 'data_convocacao', a.data_convocacao, 'hora_convocacao', a.hora_convocacao,
    'no_grupo', a.no_grupo, 'final_fila', a.final_fila, 'pendente', pend, 'pendente_grupo', pend_g);
end $$;

-- Envio do formulário com um ou mais pedidos. p_itens: [{"tipo":..., "data":"AAAA-MM-DD", "hora":"HH:MM", "observacao":...}]
-- Erros de um item cancelam o envio inteiro (raise desfaz o que já foi gravado).
create function public.enviar_pedidos(p_inscricao text, p_itens jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a record; it jsonb; t public.tipo_envio; tipos text[]; permitidos text[];
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

  permitidos := case a.convocacao::text
    when 'Convocado'  then array['Posse', 'Desistência', 'Convocação', 'Horário da convocação', 'Correção de dados']
    when 'Empossado'  then array['Desistência', 'Horário da convocação', 'Correção de dados']
    when 'Desistente' then array['Correção de dados']
    else array['Convocação', 'Desistência', 'Correção de dados'] end;
  -- Final da fila: para quem ainda não tomou posse (aguardando, sem informação ou convocado)
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
  if exists (select 1 from public.envios where aprovado_id = a.id and status = 'Pendente' and tipo <> 'Entrada no grupo') then
    return jsonb_build_object('ok', false, 'erro',
      'Já existe um pedido desta inscrição em análise. Aguarde a comissão ou fale com ela no grupo de WhatsApp.');
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
revoke execute on function public.enviar_pedidos(text, jsonb) from public;
grant execute on function public.enviar_pedidos(text, jsonb) to anon, authenticated;

-- Consulta do protocolo: devolve também todos os pedidos do mesmo envio
create or replace function public.consultar_protocolo(p_codigo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e record; c text; chave text; itens jsonb;
begin
  perform public._limitar('consultar', 30, interval '10 minutes');
  c := upper(regexp_replace(coalesce(p_codigo, ''), '[^A-Za-z0-9]', '', 'g'));
  if length(c) <> 6 then
    return jsonb_build_object('ok', false, 'erro', 'O protocolo tem 6 letras e números, como K7P-4QX.');
  end if;
  c := substr(c, 1, 3) || '-' || substr(c, 4, 3);
  select protocolo, lote, tipo, data_evento, hora_evento, status, criado_em, revisado_em, resposta_comissao into e
    from public.envios where protocolo = c;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Protocolo não encontrado. Confira o código.');
  end if;
  chave := coalesce(e.lote, e.protocolo);
  select jsonb_agg(jsonb_build_object('tipo', x.tipo, 'data_evento', x.data_evento, 'hora_evento', x.hora_evento,
           'status', x.status, 'revisado_em', x.revisado_em, 'resposta', x.resposta_comissao) order by x.id)
    into itens from public.envios x where x.protocolo = chave or x.lote = chave;
  return jsonb_build_object('ok', true, 'protocolo', c, 'tipo', e.tipo, 'data_evento', e.data_evento,
    'hora_evento', e.hora_evento, 'status', e.status, 'enviado_em', e.criado_em, 'revisado_em', e.revisado_em,
    'resposta', e.resposta_comissao, 'itens', itens,
    'expira_em', case when e.tipo = 'Entrada no grupo' and e.status = 'Pendente' then e.criado_em + interval '24 hours' end);
end $$;

-- Alertas para a comissão sobre o pedido
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
         then 'Enviado junto com outro(s) pedido(s) (protocolo ' || coalesce(e.lote, e.protocolo) || '): cada um é aprovado separadamente.' end
  ], null)
  from public.envios e join public.aprovados a on a.id = e.aprovado_id
  where e.id = p_envio
$$;

-- Pendentes da comissão: com o envio (lote) e a indicação atual de final da fila
create or replace function public.comissao_pendentes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  return coalesce((
    select jsonb_agg(x order by x.criado_em, x.id)
    from (
      select e.id, e.protocolo, coalesce(e.lote, e.protocolo) as envio, e.tipo, e.data_evento, e.hora_evento, e.observacao, e.criado_em,
             e.telefone, e.nome_whatsapp,
             case when e.tipo = 'Entrada no grupo' then e.criado_em + interval '24 hours' end as expira_em,
             a.id as aprovado_id, a.nome, a.inscricao, a.cargo, a.uf, a.macropolo, a.cota, a.situacao,
             a.posicao_uf, a.nota, a.convocacao, a.data_convocacao, a.data_posse, a.no_grupo, a.final_fila,
             public._alertas_pedido(e.id) as alertas
        from public.envios e join public.aprovados a on a.id = e.aprovado_id
       where e.status = 'Pendente'
    ) x), '[]'::jsonb);
end $$;

-- Aviso no Telegram: inclui a indicação de final da fila
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
               'tipo', e.tipo, 'criado_em', e.criado_em,
               'data', e.data_evento, 'hora', e.hora_evento, 'observacao', left(e.observacao, 600),
               'nome_whatsapp', e.nome_whatsapp,
               'nome', a.nome, 'cargo', a.cargo, 'uf', a.uf, 'macropolo', a.macropolo, 'cota', a.cota,
               'situacao', a.situacao, 'posicao_uf', a.posicao_uf, 'class_macro', a.class_macro, 'nota', a.nota,
               'convocacao', a.convocacao, 'validacao', a.validacao, 'data_convocacao', a.data_convocacao,
               'hora_convocacao', a.hora_convocacao, 'data_posse', a.data_posse, 'no_grupo', a.no_grupo,
               'final_fila', a.final_fila,
               'alertas', to_jsonb(public._alertas_pedido(e.id)),
               'pendentes', (select count(*) from public.envios x where x.status = 'Pendente'))
        into r
        from public.envios e left join public.aprovados a on a.id = e.aprovado_id
       where e.id = p_id;
    end if;
  elsif p_tabela = 'mensagens' then
    update public.mensagens m set telegram_enviado = true
     where m.id = p_id and not m.telegram_enviado and m.criado_em > now() - interval '10 minutes'
    returning jsonb_build_object('tabela', 'mensagens', 'assunto', m.assunto, 'nome', m.nome, 'email', m.email,
      'mensagem', left(m.mensagem, 1500), 'tamanho', char_length(m.mensagem), 'criado_em', m.criado_em,
      'pendentes', (select count(*) from public.mensagens x where x.status = 'Nova'))
      into r;
  end if;
  return case when r is null then null else r || jsonb_build_object('chat', chat) end;
end $$;

-- Edição em lote da comissão: aceita também final_fila
create or replace function public.comissao_editar_lote(p_ids bigint[], p_campos jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  n int; v_conv text := p_campos ->> 'convocacao'; v_val text := p_campos ->> 'validacao';
  v_dc date; v_dp date; d date;
  limpa boolean := (p_campos ->> 'convocacao') in ('Aguardando', 'Sem informação');
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  if coalesce(array_length(p_ids, 1), 0) = 0 then return jsonb_build_object('ok', false, 'erro', 'Nenhuma pessoa selecionada.'); end if;
  if p_campos is null or p_campos = '{}'::jsonb then return jsonb_build_object('ok', false, 'erro', 'Escolha pelo menos um campo para alterar.'); end if;
  if v_conv is not null and v_conv not in ('Aguardando', 'Convocado', 'Empossado', 'Desistente', 'Sem informação') then
    return jsonb_build_object('ok', false, 'erro', 'Situação inválida.'); end if;
  if v_val is not null and v_val not in ('Confirmada', 'Presumida') then
    return jsonb_build_object('ok', false, 'erro', 'Validação inválida.'); end if;
  v_dc := nullif(p_campos ->> 'data_convocacao', '')::date;
  v_dp := nullif(p_campos ->> 'data_posse', '')::date;
  foreach d in array array[v_dc, v_dp] loop
    if d is not null and (d < date '2026-05-26' or d > current_date) then
      return jsonb_build_object('ok', false, 'erro', 'As datas precisam estar entre 26/05/2026 e hoje.'); end if;
  end loop;

  update public.aprovados set
    convocacao      = coalesce(v_conv::public.convocacao, convocacao),
    validacao       = case when v_val is not null then v_val::public.validacao_conv
                           when v_conv is not null and not limpa then coalesce(validacao, 'Confirmada')
                           else validacao end,
    data_convocacao = case when p_campos ? 'data_convocacao' then v_dc when limpa then null else data_convocacao end,
    hora_convocacao = case when limpa and not (p_campos ? 'data_convocacao') then null else hora_convocacao end,
    data_posse      = case when p_campos ? 'data_posse' then v_dp when limpa then null else data_posse end,
    no_grupo        = coalesce((p_campos ->> 'no_grupo')::boolean, no_grupo),
    no_grupo_em     = case when coalesce((p_campos ->> 'no_grupo')::boolean, no_grupo) then coalesce(no_grupo_em, current_date) else null end,
    ocultar_nome    = coalesce((p_campos ->> 'ocultar_nome')::boolean, ocultar_nome),
    final_fila      = coalesce((p_campos ->> 'final_fila')::boolean, final_fila),
    final_fila_em   = case when coalesce((p_campos ->> 'final_fila')::boolean, final_fila) then coalesce(final_fila_em, current_date) else null end
  where id = any(p_ids);
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'alterados', n);
end $$;
