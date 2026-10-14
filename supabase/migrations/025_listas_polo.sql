-- Classificação de cada aprovado em todas as listas do polo (homologação, DOU de 26/05/2026).
-- Ex.: {"AC": 17, "PN": 5} = 17ª na ampla concorrência e 5ª na lista de pessoas negras.
-- Preenchida só para quem aparece em mais de uma lista; para os demais vale a cota e a posicao_uf.
-- A coluna "cota" continua sendo o grupo em que a homologação colocou a pessoa.
-- Dado público (consta da homologação); usado pelo simulador da aba "Vagas e regras".
alter table public.aprovados add column listas_polo jsonb;
grant select (listas_polo) on public.aprovados to anon;
comment on column public.aprovados.listas_polo is 'Classificação no polo em cada lista em que a pessoa aparece (homologação), ex.: {"AC":17,"PN":5}.';
-- Os valores foram carregados a partir da homologação, cruzando pelo número de inscrição.
