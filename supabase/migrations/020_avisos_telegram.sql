-- Avisos no grupo de Telegram da comissão a cada pedido novo (envios) e mensagem nova (mensagens).
-- Ao gravar, um gatilho chama a função "avisar-telegram" (pg_net). A função pede os dados a
-- _telegram_reservar, que marca o registro como avisado: cada registro gera no máximo um aviso,
-- só nos primeiros 10 minutos, e por isso a função não precisa de senha de quem chama.
-- O aviso não leva telefone, inscrição nem o texto da mensagem: só o necessário para a comissão
-- saber que há algo novo na área da comissão.
-- Segredo do bot: Supabase → Edge Functions → Secrets → TELEGRAM_TOKEN.

create extension if not exists pg_net;

create table public.configuracao (
  chave text primary key,
  valor text not null
);
alter table public.configuracao enable row level security;
revoke all on public.configuracao from public, anon, authenticated;
comment on table public.configuracao is 'Configurações internas (ex.: número do grupo de Telegram da comissão).';
insert into public.configuracao (chave, valor) values ('telegram_chat_id', '-5361475727');

alter table public.envios    add column telegram_enviado boolean not null default false;
alter table public.mensagens add column telegram_enviado boolean not null default false;

create function public._telegram_reservar(p_tabela text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb; chat text := (select valor from public.configuracao where chave = 'telegram_chat_id');
begin
  if p_tabela = 'envios' then
    update public.envios e set telegram_enviado = true
     where e.id = p_id and not e.telegram_enviado and e.criado_em > now() - interval '10 minutes'
    returning jsonb_build_object('tabela', 'envios', 'protocolo', e.protocolo, 'tipo', e.tipo, 'cargo', e.cargo,
      'data', e.data_evento, 'hora', e.hora_evento, 'criado_em', e.criado_em,
      'uf', (select a.uf from public.aprovados a where a.id = e.aprovado_id),
      'cota', (select a.cota from public.aprovados a where a.id = e.aprovado_id),
      'iniciais', (select a.iniciais from public.aprovados a where a.id = e.aprovado_id),
      'pendentes', (select count(*) from public.envios x where x.status = 'Pendente'))
      into r;
  elsif p_tabela = 'mensagens' then
    update public.mensagens m set telegram_enviado = true
     where m.id = p_id and not m.telegram_enviado and m.criado_em > now() - interval '10 minutes'
    returning jsonb_build_object('tabela', 'mensagens', 'assunto', m.assunto, 'nome', split_part(m.nome, ' ', 1),
      'criado_em', m.criado_em, 'aviso_email', m.aviso_enviado,
      'pendentes', (select count(*) from public.mensagens x where x.status = 'Nova'))
      into r;
  end if;
  return case when r is null then null else r || jsonb_build_object('chat', chat) end;
end $$;

create function public._telegram_falhou(p_tabela text, p_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_tabela = 'envios' then update public.envios set telegram_enviado = false where id = p_id;
  elsif p_tabela = 'mensagens' then update public.mensagens set telegram_enviado = false where id = p_id;
  end if;
end $$;

-- O Telegram troca o número quando um grupo vira "supergrupo": a função grava o novo aqui
create function public._telegram_novo_chat(p_chat text) returns void
language sql security definer set search_path = '' as $$
  update public.configuracao set valor = p_chat where chave = 'telegram_chat_id';
$$;

revoke execute on function public._telegram_reservar(text, bigint), public._telegram_falhou(text, bigint),
  public._telegram_novo_chat(text) from public, anon, authenticated;
grant execute on function public._telegram_reservar(text, bigint), public._telegram_falhou(text, bigint),
  public._telegram_novo_chat(text) to service_role;

-- Gatilho: chama a função de aviso sem atrasar o envio do formulário (pg_net é assíncrono)
create function public._telegram_disparar() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform net.http_post(
    url := 'https://ssgtryzcesgyuiltovmu.supabase.co/functions/v1/avisar-telegram',
    body := jsonb_build_object('tabela', tg_table_name, 'id', new.id),
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 10000);
  return new;
exception when others then
  return new; -- aviso nunca impede o pedido de ser gravado
end $$;
revoke execute on function public._telegram_disparar() from public, anon, authenticated;

create trigger envios_telegram after insert on public.envios
for each row execute function public._telegram_disparar();
create trigger mensagens_telegram after insert on public.mensagens
for each row execute function public._telegram_disparar();

-- A marca "telegram_enviado" não entra no histórico dos pedidos
drop trigger envios_historico on public.envios;
create trigger envios_historico after insert or delete on public.envios
for each row execute function public.registrar_historico();
create trigger envios_historico_alteracao after update on public.envios
for each row when ((to_jsonb(old) - 'telegram_enviado') is distinct from (to_jsonb(new) - 'telegram_enviado'))
execute function public.registrar_historico();
