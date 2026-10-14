-- Avisos do Telegram mais detalhados (a pedido da comissão):
-- pedido novo: nome completo, situação da pessoa no painel, o que foi informado e os alertas;
-- mensagem nova: nome, e-mail, assunto e o texto (até 1.500 caracteres).
-- Continuam fora do aviso: telefone e número de inscrição.
-- Os alertas ficam numa função só (_alertas_pedido), usada pelo aviso e pela área da comissão.

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
         then 'Já consta como verificada e membro do grupo.' end
  ], null)
  from public.envios e join public.aprovados a on a.id = e.aprovado_id
  where e.id = p_envio
$$;
revoke execute on function public._alertas_pedido(bigint) from public, anon, authenticated;

-- Área da comissão: mesmos dados de antes, alertas vindos da função comum
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
             public._alertas_pedido(e.id) as alertas
        from public.envios e join public.aprovados a on a.id = e.aprovado_id
       where e.status = 'Pendente'
    ) x), '[]'::jsonb);
end $$;

create or replace function public._telegram_reservar(p_tabela text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb; chat text := (select valor from public.configuracao where chave = 'telegram_chat_id');
begin
  if p_tabela = 'envios' then
    update public.envios e set telegram_enviado = true
     where e.id = p_id and not e.telegram_enviado and e.criado_em > now() - interval '10 minutes'
    returning jsonb_build_object('tabela', 'envios', 'id', e.id) into r;
    if r is not null then
      select jsonb_build_object('tabela', 'envios', 'protocolo', e.protocolo, 'tipo', e.tipo, 'criado_em', e.criado_em,
               'data', e.data_evento, 'hora', e.hora_evento, 'observacao', left(e.observacao, 600),
               'nome_whatsapp', e.nome_whatsapp,
               'nome', a.nome, 'cargo', a.cargo, 'uf', a.uf, 'macropolo', a.macropolo, 'cota', a.cota,
               'situacao', a.situacao, 'posicao_uf', a.posicao_uf, 'class_macro', a.class_macro, 'nota', a.nota,
               'convocacao', a.convocacao, 'validacao', a.validacao, 'data_convocacao', a.data_convocacao,
               'hora_convocacao', a.hora_convocacao, 'data_posse', a.data_posse, 'no_grupo', a.no_grupo,
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
revoke execute on function public._telegram_reservar(text, bigint) from public, anon, authenticated;
grant execute on function public._telegram_reservar(text, bigint) to service_role;
