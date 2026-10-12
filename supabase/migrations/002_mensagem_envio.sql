-- Mensagem clara (HTTP 400) quando o formulário recebe uma inscrição que não existe no cargo.
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
  return new;
end $$;
revoke execute on function public.envios_ao_receber() from anon, authenticated, public;
