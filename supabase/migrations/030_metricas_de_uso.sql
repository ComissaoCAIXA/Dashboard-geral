-- Métricas de uso do painel público, só em contadores por dia (sem IP, sem cookie, sem identificador).
-- O site manda, de tempos em tempos, uma lista curta de eventos ("visita de celular", "abriu a aba Vagas"...).
-- "Visitante do dia" e "visitante novo" são decididos no próprio navegador (data guardada no localStorage),
-- então o banco nunca sabe quem é quem: só soma.
create table public.metricas_dia (
  dia     date not null default (now() at time zone 'America/Sao_Paulo')::date,
  evento  text not null,
  detalhe text not null default '',
  total   integer not null default 0,
  primary key (dia, evento, detalhe)
);
comment on table public.metricas_dia is 'Contadores diários de uso do painel público (agregados, sem dados pessoais).';
alter table public.metricas_dia enable row level security;
revoke all on public.metricas_dia from anon, authenticated;
grant select on public.metricas_dia to authenticated;
create policy metricas_comissao on public.metricas_dia for select to authenticated using (public.eh_comissao());

-- Recebe até 30 eventos por chamada: [["visita","celular"],["aba","vagas"],...]. Eventos desconhecidos são ignorados.
create function public.registrar_uso(p_eventos jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare e jsonb; ev text; det text;
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  validos text[] := array['visita','visitante_dia','visitante_novo','aba','busca_fila','busca_lista','pdf',
                          'formulario','pedido_form','tour','noticias','simulacao','filtro_estado'];
begin
  if p_eventos is null or jsonb_typeof(p_eventos) <> 'array' or jsonb_array_length(p_eventos) = 0 then return; end if;
  begin
    perform public._limitar('uso', 40, interval '10 minutes');
  exception when others then return; -- excesso de chamadas: ignora em silêncio
  end;
  for e in select x from jsonb_array_elements(p_eventos) x limit 30 loop
    ev := left(coalesce(e ->> 0, ''), 30);
    det := left(regexp_replace(coalesce(e ->> 1, ''), '[^a-z0-9_-]', '', 'g'), 30);
    continue when not (ev = any (validos));
    insert into public.metricas_dia (dia, evento, detalhe, total) values (hoje, ev, det, 1)
    on conflict (dia, evento, detalhe) do update set total = public.metricas_dia.total + 1;
  end loop;
end $$;
revoke execute on function public.registrar_uso(jsonb) from public;
grant execute on function public.registrar_uso(jsonb) to anon, authenticated;

-- Resumo para a aba Métricas da área da comissão
create function public.comissao_metricas(p_dias int default 30) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare d int := greatest(7, least(coalesce(p_dias, 30), 365));
  hoje date := (now() at time zone 'America/Sao_Paulo')::date; ini date;
begin
  if not public.eh_comissao() then raise exception 'Acesso restrito à comissão.'; end if;
  ini := hoje - (d - 1);
  return jsonb_build_object(
    'hoje', hoje, 'inicio', ini,
    'desde', (select min(dia) from public.metricas_dia),
    'dias', (select jsonb_agg(jsonb_build_object('dia', g.dia,
               'visitas', coalesce((select sum(total) from public.metricas_dia m where m.dia = g.dia and m.evento = 'visita'), 0),
               'visitantes', coalesce((select sum(total) from public.metricas_dia m where m.dia = g.dia and m.evento = 'visitante_dia'), 0),
               'novos', coalesce((select sum(total) from public.metricas_dia m where m.dia = g.dia and m.evento = 'visitante_novo'), 0),
               'pedidos', (select count(*) from public.envios x where (x.criado_em at time zone 'America/Sao_Paulo')::date = g.dia),
               'mensagens', (select count(*) from public.mensagens x where (x.criado_em at time zone 'America/Sao_Paulo')::date = g.dia))
             order by g.dia)
             from generate_series(ini, hoje, interval '1 day') as g(dia)),
    'eventos', coalesce((select jsonb_agg(jsonb_build_object('evento', evento, 'detalhe', detalhe, 'total', t) order by t desc)
               from (select evento, detalhe, sum(total) t from public.metricas_dia where dia >= ini group by 1, 2) s), '[]'::jsonb),
    'total', jsonb_build_object(
       'visitas', coalesce((select sum(total) from public.metricas_dia where evento = 'visita'), 0),
       'visitantes_dia', coalesce((select sum(total) from public.metricas_dia where evento = 'visitante_dia'), 0),
       'novos', coalesce((select sum(total) from public.metricas_dia where evento = 'visitante_novo'), 0),
       'pedidos', (select count(*) from public.envios),
       'mensagens', (select count(*) from public.mensagens)),
    'noticias', coalesce((select jsonb_agg(jsonb_build_object('titulo', titulo, 'visualizacoes', visualizacoes, 'publicado_em', publicado_em) order by publicado_em desc)
               from public.noticias where publicada), '[]'::jsonb)
  );
end $$;
revoke execute on function public.comissao_metricas(int) from public, anon;
grant execute on function public.comissao_metricas(int) to authenticated;
