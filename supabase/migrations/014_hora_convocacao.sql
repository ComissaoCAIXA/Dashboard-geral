-- Horário da convocação: ajuda a descobrir a ordem real das chamadas numa mesma data.
-- O aprovado pode informar no formulário (opcional); ao aprovar o pedido, vai para aprovados.hora_convocacao.

alter table public.aprovados add column hora_convocacao time;
alter table public.envios add column hora_evento time;
grant select (hora_convocacao) on public.aprovados to anon;
comment on column public.aprovados.hora_convocacao is 'Horário em que a pessoa recebeu a convocação (informado por ela ou pela comissão).';

-- Formulário: novo parâmetro opcional p_hora (só vale para Convocação)
drop function public.enviar_pedido(text, text, date, text, text, text);
create function public.enviar_pedido(p_inscricao text, p_tipo text, p_data date, p_observacao text,
  p_telefone text default null, p_nome_whatsapp text default null, p_hora time default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a record; t public.tipo_envio; v_prot text; permitidos text[]; tel text;
begin
  perform public._limitar('enviar', 5, interval '1 hour');
  p_inscricao := regexp_replace(coalesce(p_inscricao, ''), '\D', '', 'g');
  select id, cargo, inscricao, convocacao into a from public.aprovados where inscricao = p_inscricao;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Não encontramos essa inscrição entre os aprovados.');
  end if;
  if p_tipo is null or p_tipo not in ('Convocação', 'Posse', 'Desistência', 'Correção de dados', 'Entrada no grupo') then
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
    when 'Convocado'  then array['Posse', 'Desistência', 'Convocação', 'Correção de dados']
    when 'Empossado'  then array['Desistência', 'Correção de dados']
    when 'Desistente' then array['Correção de dados']
    else array['Convocação', 'Desistência', 'Correção de dados'] end;
  if not (p_tipo = any (permitidos)) then
    return jsonb_build_object('ok', false, 'erro', 'Essa opção não vale para a sua situação atual.');
  end if;
  if t in ('Convocação', 'Posse') and p_data is null then
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
  values (a.cargo, a.inscricao, t, p_data, case when t = 'Convocação' then p_hora end, nullif(trim(p_observacao), ''))
  returning protocolo into v_prot;
  return jsonb_build_object('ok', true, 'protocolo', v_prot);
end $$;
revoke execute on function public.enviar_pedido(text, text, date, text, text, text, time) from public;
grant execute on function public.enviar_pedido(text, text, date, text, text, text, time) to anon, authenticated;

-- Pedido de convocação aprovado: grava também o horário
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

-- Pedidos pendentes mostram o horário informado
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
               case when e.tipo = 'Entrada no grupo' and a.no_grupo
                    then 'Já consta como verificada e membro do grupo.' end
             ], null) as alertas
        from public.envios e join public.aprovados a on a.id = e.aprovado_id
       where e.status = 'Pendente'
    ) x), '[]'::jsonb);
end $$;

-- Edição individual: horário (p_alterar_hora = true para gravar, inclusive apagar)
drop function public.comissao_atualizar(bigint, text, date, date, text, boolean, boolean, text);
create function public.comissao_atualizar(p_id bigint, p_convocacao text, p_data_convocacao date, p_data_posse date,
  p_observacao text, p_ocultar_nome boolean, p_no_grupo boolean default null, p_validacao text default null,
  p_hora_convocacao time default null, p_alterar_hora boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  update public.aprovados
     set convocacao = p_convocacao::public.convocacao,
         validacao = coalesce(p_validacao::public.validacao_conv, validacao),
         data_convocacao = p_data_convocacao,
         hora_convocacao = case when p_alterar_hora then p_hora_convocacao else hora_convocacao end,
         data_posse = p_data_posse,
         observacao = nullif(trim(coalesce(p_observacao, '')), ''),
         ocultar_nome = coalesce(p_ocultar_nome, false),
         no_grupo = coalesce(p_no_grupo, no_grupo),
         no_grupo_em = case when coalesce(p_no_grupo, no_grupo) then coalesce(no_grupo_em, current_date) else null end
   where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'erro', 'Aprovado não encontrado.'); end if;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.comissao_atualizar(bigint, text, date, date, text, boolean, boolean, text, time, boolean) from public, anon;
grant execute on function public.comissao_atualizar(bigint, text, date, date, text, boolean, boolean, text, time, boolean) to authenticated;

-- Edição em lote: voltar para Aguardando / Sem informação apaga também o horário
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
    ocultar_nome    = coalesce((p_campos ->> 'ocultar_nome')::boolean, ocultar_nome)
  where id = any(p_ids);
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'alterados', n);
end $$;
