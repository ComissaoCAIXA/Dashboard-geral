-- Notícias da comissão: avisos escritos na área da comissão e mostrados no painel público.
-- O público lê só as notícias publicadas (sem a contagem de visualizações).
-- A comissão cria, edita, publica, despublica e apaga pelas funções comissao_noticia_*.
-- "Já vi" fica no navegador do visitante; o banco só soma uma visualização por navegador.

create table public.noticias (
  id            bigint generated always as identity primary key,
  titulo        text not null check (char_length(titulo) between 3 and 120),
  texto         text not null check (char_length(texto) between 3 and 4000),
  importancia   text not null default 'Aviso' check (importancia in ('Importante', 'Aviso', 'Informativo')),
  categoria     text not null default 'Geral' check (categoria in ('Convocações', 'Documentos', 'Melhorias do painel', 'Comissão', 'Geral')),
  destaque      boolean not null default true,   -- aparece na janela do meio da tela ao abrir o painel
  publicada     boolean not null default false,
  publicado_em  timestamptz,
  criado_em     timestamptz not null default now(),
  criado_por    text,
  atualizado_em timestamptz not null default now(),
  atualizado_por text,
  visualizacoes integer not null default 0
);
create index noticias_publicadas on public.noticias (publicado_em desc) where publicada;
alter table public.noticias enable row level security;
revoke all on public.noticias from anon, authenticated;
grant select (id, titulo, texto, importancia, categoria, destaque, publicada, publicado_em) on public.noticias to anon;
grant select on public.noticias to authenticated;
create policy "Público lê notícias publicadas" on public.noticias
  for select to anon, authenticated using (publicada);
create policy "Comissão lê todas as notícias" on public.noticias
  for select to authenticated using (public.eh_comissao());
-- Histórico das mudanças da comissão (a simples soma de visualizações não entra)
create trigger noticias_historico after insert or delete on public.noticias
for each row execute function public.registrar_historico();
create trigger noticias_historico_alteracao after update on public.noticias
for each row when ((to_jsonb(old) - 'visualizacoes') is distinct from (to_jsonb(new) - 'visualizacoes'))
execute function public.registrar_historico();
comment on table public.noticias is 'Notícias publicadas pela comissão no painel.';

-- ---------- Comissão: criar ou editar ----------
-- p_id nulo cria. p_publicar = true publica (na primeira publicação grava a data);
-- false salva sem mudar a situação (nova notícia fica como rascunho).
create function public.comissao_noticia_salvar(p_id bigint, p_titulo text, p_texto text, p_importancia text, p_categoria text,
                                               p_destaque boolean, p_publicar boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint; quem text := auth.jwt() ->> 'email';
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  p_titulo := trim(coalesce(p_titulo, ''));
  p_texto := trim(coalesce(p_texto, ''));
  if char_length(p_titulo) < 3 then return jsonb_build_object('ok', false, 'erro', 'Escreva um título.'); end if;
  if char_length(p_texto) < 3 then return jsonb_build_object('ok', false, 'erro', 'Escreva o texto da notícia.'); end if;
  if p_importancia not in ('Importante', 'Aviso', 'Informativo') then return jsonb_build_object('ok', false, 'erro', 'Escolha a importância.'); end if;
  if p_categoria not in ('Convocações', 'Documentos', 'Melhorias do painel', 'Comissão', 'Geral') then return jsonb_build_object('ok', false, 'erro', 'Escolha a tag.'); end if;
  if p_id is null then
    insert into public.noticias (titulo, texto, importancia, categoria, destaque, publicada, publicado_em, criado_por, atualizado_por)
    values (left(p_titulo, 120), left(p_texto, 4000), p_importancia, p_categoria, coalesce(p_destaque, true), coalesce(p_publicar, false),
            case when p_publicar then now() end, quem, quem)
    returning id into v_id;
  else
    update public.noticias
       set titulo = left(p_titulo, 120), texto = left(p_texto, 4000), importancia = p_importancia, categoria = p_categoria,
           destaque = coalesce(p_destaque, destaque),
           publicado_em = case when p_publicar and not publicada then now() else publicado_em end,
           publicada = publicada or coalesce(p_publicar, false),
           atualizado_em = now(), atualizado_por = quem
     where id = p_id
    returning id into v_id;
    if v_id is null then return jsonb_build_object('ok', false, 'erro', 'Notícia não encontrada.'); end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke execute on function public.comissao_noticia_salvar(bigint, text, text, text, text, boolean, boolean) from public, anon;
grant execute on function public.comissao_noticia_salvar(bigint, text, text, text, text, boolean, boolean) to authenticated;

-- ---------- Comissão: publicar, despublicar ou apagar ----------
-- Publicar de novo uma notícia despublicada grava a data atual (ela volta a ser a mais recente).
create function public.comissao_noticia_acao(p_id bigint, p_acao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare quem text := auth.jwt() ->> 'email';
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  if p_acao = 'apagar' then
    delete from public.noticias where id = p_id;
  elsif p_acao = 'publicar' then
    update public.noticias set publicada = true, publicado_em = now(), atualizado_em = now(), atualizado_por = quem where id = p_id;
  elsif p_acao = 'despublicar' then
    update public.noticias set publicada = false, atualizado_em = now(), atualizado_por = quem where id = p_id;
  else
    return jsonb_build_object('ok', false, 'erro', 'Ação inválida.');
  end if;
  if not found then return jsonb_build_object('ok', false, 'erro', 'Notícia não encontrada.'); end if;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.comissao_noticia_acao(bigint, text) from public, anon;
grant execute on function public.comissao_noticia_acao(bigint, text) to authenticated;

-- ---------- Público: somar uma visualização ----------
-- O painel chama uma vez por navegador e notícia. Sem dado pessoal; limite contra abuso.
create function public.ver_noticia(p_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public._limitar('noticia', 60, interval '1 hour');
  update public.noticias set visualizacoes = visualizacoes + 1 where id = p_id and publicada;
end $$;
revoke execute on function public.ver_noticia(bigint) from public;
grant execute on function public.ver_noticia(bigint) to anon, authenticated;
