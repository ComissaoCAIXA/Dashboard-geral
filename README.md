# Dashboard dos aprovados — Concurso CAIXA 2026

Painel de acompanhamento dos aprovados e das convocações do concurso CAIXA 2026
(Edital nº 01/2025/NS, cargos de nível superior), mantido pela Comissão de Aprovados.

Os nomes aparecem apenas pelas iniciais. Nomes completos, números de inscrição e
qualquer outro dado pessoal **não** ficam neste repositório.

## Estrutura

| Arquivo | O que é |
|---|---|
| `index.html` | O painel (página única, abre no navegador e no GitHub Pages) |

Em construção:

- Banco de dados no Supabase, que substituirá as planilhas como fonte única dos dados.
- Formulário para os aprovados informarem convocação, posse ou desistência
  (os envios ficam pendentes até a comissão aprovar).

## Fonte dos dados

Até a ligação com o banco de dados, o painel usa uma cópia dos dados embutida no
`index.html`, gerada em 12/10/2026 a partir da planilha da comissão, contendo só as
iniciais.

## O que nunca deve entrar aqui

- Nomes completos, inscrições, CPF, contatos ou datas de nascimento.
- A senha do banco ou a chave `service_role` do Supabase.

A chave pública (`anon`) do Supabase pode ficar no código: o acesso aos dados é
controlado pelas regras do próprio banco.

## Créditos

Mapa dos estados: [giuliano-macedo/geodata-br-states](https://github.com/giuliano-macedo/geodata-br-states).
