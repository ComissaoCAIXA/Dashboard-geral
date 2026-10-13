# Dashboard dos aprovados — Concurso CAIXA 2026

Painel de acompanhamento dos aprovados e das convocações do concurso CAIXA 2026
(Edital nº 01/2025/NS, cargos de nível superior), mantido pela Comissão de Aprovados.

Por decisão da comissão, o painel mostra o nome completo dos aprovados (que já é público na
homologação). Quem pedir à comissão aparece só pelas iniciais. Números de inscrição,
observações internas e qualquer outro dado pessoal **não** ficam neste repositório.

- Painel: `https://comissaocaixa.github.io/Dashboard-geral/`
- Formulário para o aprovado: `https://comissaocaixa.github.io/Dashboard-geral/#informar`
- Área da comissão (login por e-mail): `https://comissaocaixa.github.io/Dashboard-geral/comissao.html`

## Estrutura

| Arquivo | O que é |
|---|---|
| `index.html` | O painel (página única, abre no navegador e no GitHub Pages) |
| `supabase/migrations/` | Estrutura do banco de dados no Supabase (tabelas, regras de acesso, automações) |
| `docs/guia-da-comissao.md` | Como a comissão consulta, inclui e corrige dados no Supabase |

Em construção:

- Formulário para os aprovados informarem convocação, posse ou desistência
  (os envios ficam pendentes até a comissão aprovar), com aviso à comissão.

## Fonte dos dados

O painel lê o banco de dados no Supabase a cada acesso e consulta de novo a cada
2 minutos enquanto a página está aberta. Ele só recebe as colunas liberadas ao público
(iniciais, cargo, UF, cota, situação, nota, classificação e convocação): nome e inscrição
são bloqueados pelo próprio banco.

Se o banco não responder, o painel mostra uma cópia dos dados embutida no `index.html`
(só iniciais) e avisa a data dessa cópia.

Médico do Trabalho não faz parte do painel nem do banco, por decisão da comissão.

## O que nunca deve entrar aqui

- Nomes completos, inscrições, CPF, contatos ou datas de nascimento.
- A senha do banco ou a chave `service_role` do Supabase.

A chave pública (`anon`) do Supabase pode ficar no código: o acesso aos dados é
controlado pelas regras do próprio banco.

## Créditos

Mapa dos estados: [giuliano-macedo/geodata-br-states](https://github.com/giuliano-macedo/geodata-br-states).
