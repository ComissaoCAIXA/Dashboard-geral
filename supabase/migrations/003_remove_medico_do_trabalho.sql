-- Decisão da comissão: Médico do Trabalho fica fora do banco e do painel.
delete from public.aprovados where cargo = 'Médico do Trabalho';
alter table public.aprovados add constraint aprovados_sem_medico
  check (cargo <> 'Médico do Trabalho');
alter table public.envios add constraint envios_sem_medico
  check (cargo <> 'Médico do Trabalho');
comment on type public.cargo is 'Médico do Trabalho existe na lista mas é bloqueado nas tabelas (decisão da comissão).';
