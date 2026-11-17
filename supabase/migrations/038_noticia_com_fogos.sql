-- Notícia com fogos: a comissão pode marcar uma notícia para abrir com fogos de artifício no painel
-- (só na primeira vez que cada pessoa a vê em destaque; respeita "reduzir animações" do aparelho).
alter table public.noticias add column if not exists fogos boolean not null default false;
grant select (fogos) on public.noticias to anon, authenticated;

drop function if exists public.comissao_noticia_salvar(bigint, text, text, text, text, boolean, boolean);
create or replace function public.comissao_noticia_salvar(p_id bigint, p_titulo text, p_texto text, p_importancia text, p_categoria text, p_destaque boolean, p_publicar boolean, p_fogos boolean default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
    insert into public.noticias (titulo, texto, importancia, categoria, destaque, fogos, publicada, publicado_em, criado_por, atualizado_por)
    values (left(p_titulo, 120), left(p_texto, 4000), p_importancia, p_categoria, coalesce(p_destaque, true), coalesce(p_fogos, false), coalesce(p_publicar, false),
            case when p_publicar then now() end, quem, quem)
    returning id into v_id;
  else
    update public.noticias
       set titulo = left(p_titulo, 120), texto = left(p_texto, 4000), importancia = p_importancia, categoria = p_categoria,
           destaque = coalesce(p_destaque, destaque),
           fogos = coalesce(p_fogos, fogos),
           publicado_em = case when p_publicar and not publicada then now() else publicado_em end,
           publicada = publicada or coalesce(p_publicar, false),
           atualizado_em = now(), atualizado_por = quem
     where id = p_id
    returning id into v_id;
    if v_id is null then return jsonb_build_object('ok', false, 'erro', 'Notícia não encontrada.'); end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $function$;
revoke execute on function public.comissao_noticia_salvar(bigint, text, text, text, text, boolean, boolean, boolean) from public, anon;
grant execute on function public.comissao_noticia_salvar(bigint, text, text, text, text, boolean, boolean, boolean) to authenticated;
