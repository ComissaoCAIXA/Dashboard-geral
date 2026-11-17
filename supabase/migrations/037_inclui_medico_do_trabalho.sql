-- Decisão da comissão (17/11/2026): Médico do Trabalho passa a fazer parte do banco e do painel.
-- Desfaz a trava da migration 003. Os 95 aprovados do cargo foram importados do resultado final
-- (importacao/aprovados-importacao.csv) e as convocações vieram dos relatórios nominais da CAIXA.
alter table public.aprovados drop constraint if exists aprovados_sem_medico;
alter table public.envios drop constraint if exists envios_sem_medico;
comment on type public.cargo is 'Cargos do concurso que fazem parte do painel.';
