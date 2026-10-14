# Painel dos Aprovados: Concurso CAIXA 2026

Painel **independente e voluntário** para acompanhar os aprovados e as convocações do concurso
público da CAIXA de 2025/2026 (Edital nº 01/2025/NS, cargos de nível superior). É organizado e
mantido pela **Comissão de Aprovados**, formada por aprovados no próprio concurso.

**Acesse:** https://comissaocaixa.github.io/Dashboard-geral/

> [!IMPORTANT]
> **Este painel não é da CAIXA e não tem caráter oficial.** É uma iniciativa da Comissão de
> Aprovados, sem vínculo com a CAIXA Econômica Federal nem com a banca do concurso.
>
> - As informações vêm de **fontes públicas** (ver abaixo) e de relatos dos próprios aprovados,
>   conferidos pela comissão. Podem conter erros, atrasos ou omissões.
> - Convocações marcadas como **presumidas** foram deduzidas pela ordem de classificação e ainda
>   não foram confirmadas com a pessoa.
> - O **simulador da fila** e o **checklist de documentos** são interpretações da comissão, feitas
>   como ajuda. Quem define a ordem, o momento e as exigências de cada convocação é a CAIXA.
> - Nada aqui gera direito, garante convocação ou substitui o edital, as publicações no Diário
>   Oficial da União e as comunicações oficiais da CAIXA. **Confira sempre os documentos oficiais.**
> - A comissão não se responsabiliza por decisões tomadas com base neste painel.

## De onde vêm os dados

| Fonte | O que traz |
|---|---|
| **Edital nº 01/2025/NS** da CAIXA e retificações | Cargos, polos, vagas (Anexo I), cotas, regras de convocação e documentos exigidos |
| **Homologação do resultado final** (Edital nº 4/2025/NS, DOU de 26/05/2026) | Nome, cargo, polo, nota e classificação de cada aprovado, por modalidade |
| **Relatórios públicos da CAIXA** de convocações por polo e macropolo | Quantos foram convocados em cada cargo, polo e modalidade, para conferência |
| **Grupo de WhatsApp dos aprovados** | Relatos de convocação, posse e desistência informados pelos próprios aprovados e conferidos pela comissão |

O painel não usa nenhum dado sigiloso. Números de inscrição e informações de contato ficam só
com a comissão e nunca aparecem no painel nem neste repositório.

## Recursos

**Para todos**
- **Panorama:** mapa por estado, rankings por cargo, estado e macrorregião, filtros por cota,
  distribuição das notas e lista completa de aprovados (com PDF).
- **Convocações:** quem já foi convocado (com data), quem tem vaga imediata e aguarda, e o
  cadastro reserva. Convocações presumidas aparecem com marca própria.
- **Vagas e regras:** busca pelo próprio nome com a chamada prevista e quantas faltam, próximas chamadas,
  fila completa animada, e (na visão detalhada) quem está em duas listas, memória de cálculo e conferência.
  Também traz o quadro de vagas do Anexo I, regras de convocação com os itens do edital e
  simulador animado da fila de convocação por cargo e estado, conferido com as convocações reais.
- **Documentos:** checklist personalizado dos documentos da etapa de comprovação de requisitos,
  com explicação de cada item e PDF para imprimir. As respostas ficam só no aparelho da pessoa.
- **Notícias da comissão:** avisos publicados pela comissão, com importância e tag.
- **Tour** guiado pelos recursos, **Novidades** (histórico de atualizações), modo claro e escuro,
  versão para celular e ajuda "?" em cada indicador.

**Para os aprovados** (nada muda no painel sem a comissão conferir)
- **Informar convocação, posse, desistência ou horário da convocação** pelo número de inscrição,
  sem documentos, com protocolo para acompanhar o pedido.
- **Pedir entrada no grupo de WhatsApp** dos aprovados.
- **Fale com a comissão:** dúvidas, sugestões e correções.

**Para a comissão** (área restrita, em `comissao.html`)
- Pedidos pendentes, mensagens, acompanhamento do grupo, lista completa de aprovados com edição
  individual e em lote, validação das convocações (confirmada ou presumida), notícias e histórico
  de todas as alterações. Passo a passo em [`docs/guia-da-comissao.md`](docs/guia-da-comissao.md).

## Como funciona

| Peça | Onde |
|---|---|
| Páginas (HTML, CSS e JavaScript, sem etapa de build) | `index.html` (painel) e `comissao.html` (área da comissão), publicadas pelo GitHub Pages |
| Banco de dados, regras de acesso e automações | Supabase (Postgres). Estrutura em `supabase/migrations/` (001 a 025, aplicadas em ordem) |
| Aviso por e-mail do Fale com a comissão | Função `supabase/functions/avisar-mensagem` (Supabase Edge Functions) |
| Avisos da comissão no Telegram (pedido novo e mensagem nova) | Função `supabase/functions/avisar-telegram`, chamada pelo banco (migração 020) |
| Modelos dos e-mails de login da comissão | `docs/emails/` |

## Segurança e privacidade

- As páginas usam só a chave **pública** do Supabase. O que cada visitante pode ler ou fazer é
  decidido pelas regras do próprio banco (Row Level Security e permissões por coluna): o público
  lê apenas as colunas mostradas no painel.
- Os formulários passam por funções com validação e limite de tentativas por visitante. O limite não
  guarda o IP: guarda só um código irreversível, com um tempero secreto que troca a cada hora e é apagado.
- A área da comissão exige login por e-mail e só funciona para e-mails cadastrados pela comissão.
  Toda alteração fica registrada no histórico, com quem fez.
- O WhatsApp informado para entrar no grupo é apagado na decisão da comissão ou em no máximo 24 horas.
- Senhas, a chave `service_role` e a senha do e-mail ficam só no Supabase, nunca no código.
- **Nunca** entram neste repositório: números de inscrição, CPF, telefones, e-mails de aprovados,
  observações internas, planilhas ou arquivos com dados pessoais.
- Por decisão da comissão, o painel mostra o nome completo dos aprovados, que já é público na
  homologação. Quem preferir aparece só pelas iniciais: basta pedir à comissão.
- Encontrou um problema de segurança ou um dado pessoal exposto? Veja [`SECURITY.md`](SECURITY.md).

Médico do Trabalho não faz parte do painel por decisão da comissão.

## Manutenção

- **Nova novidade pública:** acrescente uma linha no topo da lista `NOVIDADES` em `index.html`.
- **Mudança no banco:** crie o próximo arquivo em `supabase/migrations/` e aplique no Supabase.
- **Cópia de reserva:** a lista `SNAPSHOT` em `index.html` guarda os dados públicos do painel para
  quando o banco não responder.

## Créditos

Elaborado pela Comissão de Aprovados do Concurso CAIXA 2026 · Felipe Almeida.
Mapa dos estados: [giuliano-macedo/geodata-br-states](https://github.com/giuliano-macedo/geodata-br-states).
