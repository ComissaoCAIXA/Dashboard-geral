-- =====================================================================
-- Formulário "Informar convocação"
-- O público usa só três funções:
--   buscar_inscricao(inscrição)        -> dados públicos da pessoa (sem nome)
--   enviar_pedido(inscrição, tipo, ...) -> cria pedido Pendente e devolve o protocolo
--   consultar_protocolo(código)         -> andamento do pedido
-- Nada é alterado em "aprovados" sem a comissão aprovar o pedido.
-- =====================================================================

-- A inscrição identifica a pessoa sozinha (é única no concurso)
create unique index aprovados_inscricao_unica on public.aprovados (inscricao);

-- Código de protocolo aleatório (não sequencial, para ninguém consultar pedidos de outros)
alter table public.envios add column protocolo text unique;

create function public._novo_protocolo() returns text
language plpgsql volatile set search_path = '' as $$
declare alfa text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; b bytea; s text; i int;
begin
  loop
    b := extensions.gen_random_bytes(6); s := '';
    for i in 0..5 loop s := s || substr(alfa, (get_byte(b, i) % 32) + 1, 1); end loop;
    s := substr(s, 1, 3) || '-' || substr(s, 4, 3);
    exit when not exists (select 1 from public.envios where protocolo = s);
  end loop;
  return s;
end $$;

create or replace function public.envios_ao_receber() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  select a.id into new.aprovado_id from public.aprovados a
   where a.cargo = new.cargo and a.inscricao = new.inscricao;
  if new.aprovado_id is null then
    raise exception 'Inscrição não encontrada entre os aprovados deste cargo.'
      using hint = 'Confira o cargo e o número de inscrição.';
  end if;
  new.status := 'Pendente';
  new.revisado_em := null;
  new.resposta_comissao := null;
  new.criado_em := now();
  new.protocolo := public._novo_protocolo();
  return new;
end $$;

-- ---------- Limite de tentativas por visitante (IP) ----------
create table public.limites (
  id    bigint generated always as identity primary key,
  chave text not null,
  acao  text not null,
  em    timestamptz not null default now()
);
create index limites_busca on public.limites (chave, acao, em);
alter table public.limites enable row level security;
revoke all on public.limites from anon, authenticated;
comment on table public.limites is 'Controle interno de tentativas do formulário (apagado automaticamente após 1 dia).';

create function public._ip() returns text
language sql stable set search_path = '' as $$
  select coalesce(nullif(trim(split_part(
    nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for', ',', 1)), ''), 'desconhecido')
$$;

create function public._limitar(p_acao text, p_max int, p_janela interval) returns void
language plpgsql security definer set search_path = '' as $$
declare k text := public._ip(); n int;
begin
  delete from public.limites where em < now() - interval '1 day';
  select count(*) into n from public.limites
   where chave = k and acao = p_acao and em > now() - p_janela;
  if n >= p_max then
    raise exception 'Muitas tentativas seguidas. Aguarde alguns minutos e tente de novo.';
  end if;
  insert into public.limites (chave, acao) values (k, p_acao);
end $$;

-- ---------- 1) Buscar inscrição ----------
-- Devolve só o que o painel público já mostra. Erros vêm como {"ok":false} (sem exceção)
-- para que a tentativa continue contando no limite.
create function public.buscar_inscricao(p_inscricao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a record; pend boolean;
begin
  perform public._limitar('buscar', 20, interval '10 minutes');
  p_inscricao := regexp_replace(coalesce(p_inscricao, ''), '\D', '', 'g');
  if p_inscricao !~ '^[0-9]{6,12}$' then
    return jsonb_build_object('ok', false, 'erro', 'Digite só os números da sua inscrição.');
  end if;
  select id, iniciais, cargo, uf, cota, situacao, posicao_uf, convocacao, data_convocacao into a
    from public.aprovados where inscricao = p_inscricao;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Não encontramos essa inscrição entre os aprovados.');
  end if;
  select exists (select 1 from public.envios where aprovado_id = a.id and status = 'Pendente') into pend;
  return jsonb_build_object('ok', true, 'iniciais', a.iniciais, 'cargo', a.cargo, 'uf', a.uf,
    'cota', a.cota, 'situacao', a.situacao, 'posicao_uf', a.posicao_uf,
    'convocacao', a.convocacao, 'data_convocacao', a.data_convocacao, 'pendente', pend);
end $$;

-- ---------- 2) Enviar pedido ----------
create function public.enviar_pedido(p_inscricao text, p_tipo text, p_data date, p_observacao text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a record; t public.tipo_envio; v_prot text; permitidos text[];
begin
  perform public._limitar('enviar', 5, interval '1 hour');
  p_inscricao := regexp_replace(coalesce(p_inscricao, ''), '\D', '', 'g');
  select id, cargo, inscricao, convocacao into a from public.aprovados where inscricao = p_inscricao;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Não encontramos essa inscrição entre os aprovados.');
  end if;
  if p_tipo is null or p_tipo not in ('Convocação', 'Posse', 'Desistência', 'Correção de dados') then
    return jsonb_build_object('ok', false, 'erro', 'Escolha o que aconteceu.');
  end if;
  t := p_tipo::public.tipo_envio;
  -- O que cada situação atual permite informar
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
  if length(coalesce(p_observacao, '')) > 1000 then
    return jsonb_build_object('ok', false, 'erro', 'A observação pode ter no máximo 1000 caracteres.');
  end if;
  if exists (select 1 from public.envios where aprovado_id = a.id and status = 'Pendente') then
    return jsonb_build_object('ok', false, 'erro',
      'Já existe um pedido desta inscrição em análise. Aguarde a comissão ou fale com ela no grupo de WhatsApp.');
  end if;
  insert into public.envios (cargo, inscricao, tipo, data_evento, observacao)
  values (a.cargo, a.inscricao, t, p_data, nullif(trim(p_observacao), ''))
  returning protocolo into v_prot;
  return jsonb_build_object('ok', true, 'protocolo', v_prot);
end $$;

-- ---------- 3) Consultar protocolo ----------
create function public.consultar_protocolo(p_codigo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e record; c text;
begin
  perform public._limitar('consultar', 30, interval '10 minutes');
  c := upper(regexp_replace(coalesce(p_codigo, ''), '[^A-Za-z0-9]', '', 'g'));
  if length(c) <> 6 then
    return jsonb_build_object('ok', false, 'erro', 'O protocolo tem 6 letras e números, como K7P-4QX.');
  end if;
  c := substr(c, 1, 3) || '-' || substr(c, 4, 3);
  select tipo, data_evento, status, criado_em, revisado_em, resposta_comissao into e
    from public.envios where protocolo = c;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Protocolo não encontrado. Confira o código.');
  end if;
  return jsonb_build_object('ok', true, 'protocolo', c, 'tipo', e.tipo, 'data_evento', e.data_evento,
    'status', e.status, 'enviado_em', e.criado_em, 'revisado_em', e.revisado_em,
    'resposta', e.resposta_comissao);
end $$;

-- ---------- Permissões ----------
-- O formulário passa a usar só as funções (não insere direto na tabela)
revoke insert on public.envios from anon, authenticated;
drop policy if exists "Envio pelo formulário" on public.envios;

revoke execute on function public._novo_protocolo(), public._ip(),
  public._limitar(text, int, interval) from anon, authenticated, public;
revoke execute on function public.buscar_inscricao(text), public.enviar_pedido(text, text, date, text),
  public.consultar_protocolo(text) from public;
grant execute on function public.buscar_inscricao(text), public.enviar_pedido(text, text, date, text),
  public.consultar_protocolo(text) to anon, authenticated;
