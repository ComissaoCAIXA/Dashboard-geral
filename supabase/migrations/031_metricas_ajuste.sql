-- Ajuste das métricas: o detalhe do evento passa para minúsculas antes da limpeza
-- (antes, "BA" virava vazio). Também zera os registros dos testes feitos antes da publicação.
create or replace function public.registrar_uso(p_eventos jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare e jsonb; ev text; det text;
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  validos text[] := array['visita','visitante_dia','visitante_novo','aba','busca_fila','busca_lista','pdf',
                          'formulario','pedido_form','tour','noticias','simulacao','filtro_estado'];
begin
  if p_eventos is null or jsonb_typeof(p_eventos) <> 'array' or jsonb_array_length(p_eventos) = 0 then return; end if;
  begin
    perform public._limitar('uso', 40, interval '10 minutes');
  exception when others then return;
  end;
  for e in select x from jsonb_array_elements(p_eventos) x limit 30 loop
    ev := left(coalesce(e ->> 0, ''), 30);
    det := left(regexp_replace(lower(coalesce(e ->> 1, '')), '[^a-z0-9_-]', '', 'g'), 30);
    continue when not (ev = any (validos));
    insert into public.metricas_dia (dia, evento, detalhe, total) values (hoje, ev, det, 1)
    on conflict (dia, evento, detalhe) do update set total = public.metricas_dia.total + 1;
  end loop;
end $$;
delete from public.metricas_dia;
