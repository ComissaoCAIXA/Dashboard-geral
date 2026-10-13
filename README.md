# Dashboard dos aprovados — Concurso CAIXA 2026

Painel de acompanhamento dos aprovados e das convocações do concurso CAIXA 2026
(Edital nº 01/2025/NS, cargos de nível superior), mantido pela Comissão de Aprovados.

| Para quem | Endereço |
|---|---|
| Público | `https://comissaocaixa.github.io/Dashboard-geral/` |
| Aprovado: informar convocação, posse ou desistência | `…/Dashboard-geral/#informar` |
| Aprovado: pedir entrada no grupo de WhatsApp | `…/Dashboard-geral/#grupo` |
| Qualquer pessoa: falar com a comissão | `…/Dashboard-geral/#contato` |
| Comissão (login por e-mail) | `…/Dashboard-geral/comissao.html` |

## O que o painel faz

**Para o público**
- Mapa do Brasil por estado, rankings por cargo, estado e macrorregião, filtros por cota.
- Aba de convocações: quem foi convocado (com data), quem aguarda e o cadastro reserva.
  Convocações deduzidas pela ordem de classificação aparecem como **presumidas** até a
  comissão confirmar com a pessoa.
- Aba **Vagas e regras** (`…/#vagas`): quadro de vagas do Anexo I, regras de convocação com os itens do
  edital e simulador animado da fila de convocação por cargo e estado. A regra da simulação está descrita
  em `montarFila()` no `index.html` e é conferida ao vivo com as convocações registradas.
- Visão objetiva (padrão) e visão detalhada; ajuda "?" em cada card; modo claro e escuro; celular.
- **Novidades**: histórico público de atualizações (ícone de relógio no topo).
- Dados ao vivo do banco, com nova consulta a cada 2 minutos. Se o banco não responder,
  usa a cópia de reserva embutida no `index.html` e avisa a data dela.

**Formulários** (nada muda no painel sem a comissão aprovar)
- *Informar convocação*: pelo número de inscrição, sem documentos; gera um protocolo para
  acompanhar. Exige estar no grupo de WhatsApp dos aprovados, onde a comissão confirma.
- *Participar do grupo de WhatsApp*: inscrição + WhatsApp. O número é apagado na decisão
  da comissão ou em no máximo 24 horas, e nunca vai para o histórico.
- *Fale com a comissão*: nome, e-mail, assunto e mensagem; chega no e-mail da comissão.
- Limite de tentativas por visitante e proteção contra robôs simples.

**Para a comissão** (área restrita, login por link ou código enviado por e-mail)
- Pedidos pendentes (aprovar / não aprovar), mensagens do Fale com a comissão,
  acompanhamento do grupo de WhatsApp, lista completa de aprovados com filtros,
  edição individual e em lote, sugestões de convocação presumida e histórico de alterações.
- Passo a passo em [`docs/guia-da-comissao.md`](docs/guia-da-comissao.md).

## Como funciona

| Peça | Onde |
|---|---|
| Páginas (HTML, CSS e JS, sem etapa de build) | `index.html` (painel) e `comissao.html` (área da comissão), publicadas pelo GitHub Pages |
| Banco de dados, regras de acesso e automações | Supabase (Postgres). Estrutura em `supabase/migrations/` (001 a 015, aplicadas em ordem) |
| Aviso por e-mail do Fale com a comissão | Função `supabase/functions/avisar-mensagem` (Supabase Edge Functions) |
| Modelos dos e-mails de login | `docs/emails/` (colados em Authentication → Emails → Templates) |

Segurança: as páginas usam a chave **pública** do Supabase. O que cada visitante pode ler ou
fazer é decidido pelas regras do próprio banco: o público lê só as colunas do painel; o envio
de formulários passa por funções com validação e limite de tentativas; a área da comissão só
funciona para e-mails cadastrados na tabela `comissao`. Senhas (banco, SMTP) e a chave
`service_role` ficam só no Supabase.

## Manutenção

- **Nova novidade pública:** acrescente uma linha no topo da lista `NOVIDADES` em `index.html`
  (data e hora, tipo `novo`/`melhoria`/`correcao`/`dados`, título e descrição para o público).
- **Mudança no banco:** crie o próximo arquivo em `supabase/migrations/` e aplique no Supabase.
- **Cópia de reserva:** a lista `SNAPSHOT` em `index.html` pode ser atualizada com os dados
  públicos do banco (as mesmas colunas que o painel lê).

## Privacidade

Por decisão da comissão, o painel mostra o nome completo dos aprovados (já público na
homologação); quem pedir aparece só pelas iniciais. **Nunca** entram neste repositório:
números de inscrição, CPF, telefones, e-mails de aprovados, observações internas, planilhas
com dados pessoais (`*.csv`, `*.xlsx` e `dados/` são ignorados pelo Git), senhas ou chaves secretas.

Médico do Trabalho não faz parte do painel nem do banco, por decisão da comissão.

## Créditos

Elaborado pela Comissão de Aprovados do Concurso CAIXA 2026 · Felipe Almeida.
Mapa dos estados: [giuliano-macedo/geodata-br-states](https://github.com/giuliano-macedo/geodata-br-states).
