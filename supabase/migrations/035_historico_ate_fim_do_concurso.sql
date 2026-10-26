-- O registro de alterações e os pedidos já analisados ficam guardados durante toda a validade do concurso
-- (em vez de 4 anos contados de cada registro, como na migração 034). A data do fim fica em configuracao
-- (chave fim_validade_concurso): homologação em 26/05/2026 + 2 anos + 2 de prorrogação = 26/05/2030.
-- Se a CAIXA não prorrogar a validade, troque a data para 2028-05-26 no Table Editor.
insert into public.configuracao (chave, valor) values ('fim_validade_concurso', '2030-05-26')
on conflict (chave) do nothing;

create or replace function public._apagar_registros_antigos() returns void
language plpgsql security definer set search_path = '' as $$
declare fim date := (select valor::date from public.configuracao where chave = 'fim_validade_concurso');
begin
  if fim is null or current_date <= fim then return; end if;
  delete from public.envios where status <> 'Pendente';
  -- inclui o que o gatilho de histórico acabou de registrar sobre os pedidos apagados
  delete from public.historico;
end $$;
revoke execute on function public._apagar_registros_antigos() from public, anon, authenticated;
