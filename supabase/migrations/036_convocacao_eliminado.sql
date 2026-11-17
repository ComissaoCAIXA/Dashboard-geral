-- Situação "Eliminado": o relatório nominal da CAIXA marca a pessoa como eliminada, sem informar o motivo.
-- No painel aparece como "Saiu do processo" e a vaga segue para a próxima pessoa da mesma lista.
alter type public.convocacao add value if not exists 'Eliminado' after 'Desistente';
