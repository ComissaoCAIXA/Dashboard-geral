-- "Fale com a comissão": mensagens de qualquer visitante para a comissão.
-- O site grava a mensagem (enviar_mensagem) e pede o aviso por e-mail à função "avisar-mensagem".
-- Só a comissão lê as mensagens; o visitante não consegue ler nada de volta.

create type public.status_mensagem as enum ('Nova', 'Respondida');

create table public.mensagens (
  id            bigint generated always as identity primary key,
  criado_em     timestamptz not null default now(),
  nome          text not null check (char_length(nome) between 2 and 120),
  email         text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 200),
  assunto       text not null check (char_length(assunto) between 2 and 80),
  mensagem      text not null check (char_length(mensagem) between 10 and 4000),
  status        public.status_mensagem not null default 'Nova',
  respondida_por text,
  respondida_em timestamptz,
  aviso_enviado boolean not null default false,  -- e-mail de aviso já saiu para a comissão
  aviso_erro    text
);
create index mensagens_status on public.mensagens (status, criado_em desc);
alter table public.mensagens enable row level security;
revoke all on public.mensagens from anon, authenticated;
grant select on public.mensagens to authenticated;
create policy "Comissão lê mensagens" on public.mensagens
  for select to authenticated using (public.eh_comissao());
comment on table public.mensagens is 'Mensagens do formulário "Fale com a comissão". Só a comissão lê.';

-- ---------- Público: enviar mensagem ----------
create function public.enviar_mensagem(p_nome text, p_email text, p_assunto text, p_mensagem text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id bigint; n int;
begin
  perform public._limitar('mensagem', 3, interval '1 hour');
  -- teto geral, para um robô não lotar a caixa de e-mail da comissão
  select count(*) into n from public.mensagens where criado_em > now() - interval '1 hour';
  if n >= 30 then
    return jsonb_build_object('ok', false, 'erro', 'Recebemos muitas mensagens agora. Tente de novo mais tarde.');
  end if;
  p_nome := trim(regexp_replace(coalesce(p_nome, ''), '\s+', ' ', 'g'));
  p_email := lower(trim(coalesce(p_email, '')));
  p_assunto := trim(coalesce(p_assunto, ''));
  p_mensagem := trim(coalesce(p_mensagem, ''));
  if char_length(p_nome) < 2 then return jsonb_build_object('ok', false, 'erro', 'Informe seu nome.'); end if;
  if p_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return jsonb_build_object('ok', false, 'erro', 'Confira o e-mail: é por ele que a comissão vai responder.'); end if;
  if char_length(p_assunto) < 2 then return jsonb_build_object('ok', false, 'erro', 'Escolha o assunto.'); end if;
  if char_length(p_mensagem) < 10 then return jsonb_build_object('ok', false, 'erro', 'Escreva a mensagem (pelo menos 10 caracteres).'); end if;
  insert into public.mensagens (nome, email, assunto, mensagem)
  values (left(p_nome, 120), left(p_email, 200), left(p_assunto, 80), left(p_mensagem, 4000))
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke execute on function public.enviar_mensagem(text, text, text, text) from public;
grant execute on function public.enviar_mensagem(text, text, text, text) to anon, authenticated;

-- ---------- Comissão: marcar como respondida / nova, ou apagar ----------
create function public.comissao_mensagem(p_id bigint, p_acao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  if p_acao = 'apagar' then
    delete from public.mensagens where id = p_id;
  elsif p_acao in ('Respondida', 'Nova') then
    update public.mensagens
       set status = p_acao::public.status_mensagem,
           respondida_por = case when p_acao = 'Respondida' then auth.jwt() ->> 'email' end,
           respondida_em  = case when p_acao = 'Respondida' then now() end
     where id = p_id;
  else
    return jsonb_build_object('ok', false, 'erro', 'Ação inválida.');
  end if;
  if not found then return jsonb_build_object('ok', false, 'erro', 'Mensagem não encontrada.'); end if;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.comissao_mensagem(bigint, text) from public, anon;
grant execute on function public.comissao_mensagem(bigint, text) to authenticated;
