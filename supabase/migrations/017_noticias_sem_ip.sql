-- Menos IP guardado:
-- 1) A contagem de visualizações das notícias deixa de usar o limite por IP (não grava nada do visitante).
--    Contar a mais não traz risco: o número só aparece para a comissão.
-- 2) Os registros do limite de tentativas dos formulários (que guardam o IP) passam a ser apagados
--    a cada 10 minutos, assim que saem da maior janela usada (1 hora), em vez de ficarem até 1 dia.

create or replace function public.ver_noticia(p_id bigint) returns void
language sql security definer set search_path = '' as $$
  update public.noticias set visualizacoes = visualizacoes + 1 where id = p_id and publicada;
$$;
revoke execute on function public.ver_noticia(bigint) from public;
grant execute on function public.ver_noticia(bigint) to anon, authenticated;

delete from public.limites where acao = 'noticia';

create or replace function public._limpar_limites() returns void
language sql security definer set search_path = '' as $$
  delete from public.limites where em < now() - interval '1 hour';
$$;
revoke execute on function public._limpar_limites() from public, anon, authenticated;
select cron.schedule('limpar-limites', '*/10 * * * *', 'select public._limpar_limites()');
