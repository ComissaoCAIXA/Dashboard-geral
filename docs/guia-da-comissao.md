# Guia da comissão — banco de dados

## Área da comissão (recomendado)

Endereço: `https://comissaocaixa.github.io/Dashboard-geral/comissao.html`

- **Entrar:** digite seu e-mail e clique no link que chega por e-mail (sem senha), ou digite o
  código de números que vem no mesmo e-mail (útil quando o link abre em outro aparelho).
  Só entra quem está na tabela `comissao` com `ativo` marcado.
- **Mensagens:** o que chega pelo **Fale com a comissão** (link no rodapé do painel, ou
  `.../Dashboard-geral/#contato`). Cada mensagem também chega no e-mail da comissão; use
  **Responder** no e-mail (a resposta vai direto para a pessoa) e depois clique em
  **Marcar como respondida**. Se aparecer o alerta "o aviso não chegou ao e-mail", responda pelo botão
  **Responder por e-mail** da própria mensagem. Limite: 3 mensagens por visitante a cada hora.
- **Pedidos pendentes:** cada pedido mostra protocolo, o que a pessoa informou, os dados completos
  dela e alertas automáticos. Confira pelo WhatsApp e clique em **Aprovar** ou **Não aprovar**
  (a resposta opcional aparece para o aprovado na consulta do protocolo).
- **Grupo de WhatsApp:** quantos aprovados já estão no grupo, quantos faltam, por cargo e por estado,
  e a lista de quem falta (com filtros). Clique em **Marcar como no grupo** para quem já é membro.
  Para informar convocação pelo site, a pessoa precisa estar marcada como membro do grupo;
  quem não está é orientado a pedir a entrada primeiro.
- **Horário da convocação:** o aprovado pode informar o horário em que recebeu a convocação, junto com a
  convocação ou depois, pela opção "Quero informar o horário da minha convocação". Ao aprovar, o horário vai para
  a pessoa (e uma convocação presumida passa a confirmada). Também dá para editar o horário na aba Aprovados.
  O horário serve para descobrir a ordem real das chamadas feitas no mesmo dia e conferir o simulador da aba
  "Vagas e regras" do painel.
- **Pedidos de entrada no grupo:** mostram o WhatsApp informado e um botão para abrir a conversa.
  O número é apagado automaticamente ao aprovar/não aprovar, ou em 24 h se ninguém decidir
  (o pedido vira "Expirado"). O número nunca vai para o histórico.
- **Aprovados:** a lista completa, com totais (convocados, empossados, aguardando) e filtros por
  nome/inscrição, cargo, estado, cota, vaga imediata/reserva e situação.
  - **Editar várias pessoas de uma vez:** marque as caixinhas (a do cabeçalho marca todos os
    mostrados). Na barra azul, cada campo começa em *Não alterar*; escolha só o que quer mudar —
    situação, validação, data da convocação, data da posse (definir ou apagar), grupo de WhatsApp e
    nome no painel — e clique em **Aplicar aos selecionados**. A observação interna não muda em lote.
    Voltar para *Aguardando* apaga as datas e a validação.
  - **Validação da convocação:** *Confirmada* = a comissão falou com a pessoa (pedidos aprovados no
    formulário viram Confirmada sozinhos). *Presumida* = deduzida pela ordem de classificação; no painel
    público aparece com a marca "presumida". Quando encontrar a pessoa, mude para Confirmada.
  - **Convocações presumidas sugeridas:** quadro amarelo no topo da aba. Lista quem ainda está
    "Aguardando" mas tem alguém **atrás na mesma lista** (cargo + estado + cota) já convocado. Confira e
    clique em **Marcar selecionadas como convocação presumida** (usa a data da pessoa de referência).
  - **Editar tudo de uma pessoa:** clique no nome para alterar situação, datas, observação interna,
    **ocultar o nome** no painel ou marcar se está no grupo.
- **Notícias:** avisos que aparecem no painel público (botão "Notícias" no topo).
  - Escreva o **título** e o **texto**. A barra de formatação tem negrito, itálico, subtítulo, listas,
    destaque (caixa amarela), link e emojis; à direita aparece a prévia de como fica.
  - **Importância:** *Importante* (todos precisam ver, ex.: nova rodada de convocações), *Aviso* (notícia
    relevante) ou *Informativo* (melhorias do painel e recados). **Tag:** Convocações, Documentos,
    Melhorias do painel, Comissão ou Geral.
  - **Mostrar em destaque ao abrir o painel:** quem ainda não viu a notícia a vê numa janela no meio da tela
    ao entrar. Só a notícia em destaque mais recente aparece assim; as outras ficam na lista. Ao escolher
    *Informativo*, essa opção é desmarcada (dá para marcar de novo).
  - **Escrever com IA:** abra "✨ Escrever com IA" embaixo do texto, copie o prompt, cole na IA (ChatGPT,
    Claude, Gemini…) com as informações da notícia no fim e cole a resposta inteira no campo Texto: título,
    importância e tag são preenchidos sozinhos. Resposta em HTML também é convertida. Revise sempre.
  - **Publicar** coloca no painel na hora; **Salvar como rascunho** guarda sem mostrar. Na tabela embaixo:
    Editar, Publicar/Despublicar e Apagar. Publicar de novo uma notícia despublicada faz dela a mais recente.
  - **Visualizações:** uma por navegador que abriu a notícia. O painel não guarda IP nem dados de quem leu;
    o "já vi" fica no próprio navegador da pessoa.
- **Histórico:** as últimas 100 alterações, com o e-mail de quem fez.
- **Exportar CSV:** baixa a base completa (guarde como cópia de segurança).

### Incluir ou remover membros
Supabase → Table Editor → tabela **`comissao`** → Insert row: preencha `email` (e, se quiser, `nome`).
Para tirar o acesso, desmarque `ativo`. Não é preciso mais nada: a pessoa já pode entrar pela área.

Só e-mails desta tabela conseguem criar conta: a função `hook_so_comissao` (ligada em
Authentication → Hooks → *Before User Created*) recusa qualquer outro e-mail na tela de login.

### Avisos no Telegram
O bot **@ComissaoCaixa2026Bot** avisa no grupo "Comissão CAIXA - Avisos do painel" a cada **pedido novo**
(nome completo, cargo, estado, cota, classificação, nota, situação no painel, grupo de WhatsApp, o que foi
informado, o que acontece ao aprovar, observação e alertas) e a cada **mensagem nova** do Fale com a comissão
(nome, e-mail, assunto e texto). O aviso nunca traz telefone nem número de inscrição; o botão abre a área da
comissão. Lembre que o que vai para o Telegram fica no histórico do grupo: apague avisos antigos se quiser.
- Para alguém receber os avisos, basta entrar no grupo do Telegram.
- A chave do bot fica só em Supabase → Edge Functions → Secrets → `TELEGRAM_TOKEN`. Se vazar: no
  @BotFather, `/revoke`, e cole a chave nova no mesmo segredo.
- Para mandar os avisos para outro grupo: adicione o bot no grupo novo, mande `/start@ComissaoCaixa2026Bot`
  lá e peça a um administrador para trocar o número em `configuracao` (chave `telegram_chat_id`).

### Mensagens antigas
As mensagens do Fale com a comissão são apagadas do banco 6 meses depois de recebidas. O aviso
que chegou no e-mail da comissão continua lá.

## Direto no Supabase (para administradores)

Como consultar, incluir e corrigir os dados dos aprovados direto no Supabase.

## Onde ficam os dados

Projeto **Dashboard-geral** no Supabase (organização "Comissão de aprovados CAIXA").
Acesse em supabase.com/dashboard → projeto → **Table Editor** (ícone de tabela no menu à esquerda).

| Tabela | O que guarda | Quem vê |
|---|---|---|
| `aprovados` | A base oficial: nome, inscrição, cargo, UF, cota, nota, situação e convocação | O site mostra nome (ou iniciais, se `ocultar_nome`), cargo, UF, cota, nota e situação. Inscrição e observação ficam só com a comissão |
| `envios` | O que chega pelo formulário do site | Só a comissão |
| `historico` | Registro automático de toda inclusão, alteração e exclusão | Só a comissão |
| `mensagens` | Mensagens do Fale com a comissão (nome, e-mail, assunto, texto) | Só a comissão |

## Campos da tabela `aprovados`

| Campo | Como preencher |
|---|---|
| `inscricao` | Só números (6 a 12 dígitos) |
| `nome` | Nome completo |
| `iniciais` | **Automático** a partir do nome. Não dá para editar |
| `cargo` | Escolha na lista. **Médico do Trabalho** aparece no menu, mas o banco recusa: por decisão da comissão, esse cargo fica fora do painel |
| `uf` | Escolha na lista |
| `macropolo` | **Automático** a partir da UF (pode deixar qualquer valor; é corrigido ao salvar) |
| `cota` | AC, PcD, PN, PI ou PQ (PN = pessoas negras, antigo "PPP/PN") |
| `situacao` | Vaga imediata ou Cadastro reserva |
| `nota` | Número com ponto: `63.5` (não use vírgula) |
| `posicao_uf` | Posição no ranking da UF |
| `class_macro` | Classificação no macropolo, na lista da cota (pode ficar vazio) |
| `convocacao` | Sem informação, Aguardando, Convocado, Empossado ou Desistente |
| `data_convocacao` / `data_posse` | Datas, se houver |
| `observacao` | Texto livre, só a comissão vê |

Não pode existir a mesma inscrição duas vezes no mesmo cargo: o banco recusa.

## Tarefas do dia a dia

### Marcar uma convocação
1. Table Editor → `aprovados`.
2. Use **Filter** para achar a pessoa (por `inscricao` ou `nome`).
3. Clique duas vezes na célula `convocacao`, escolha **Convocado** e preencha `data_convocacao`.
4. A alteração é salva na hora e entra no `historico`.

### Incluir um aprovado
**Insert → Insert row**, preencha os campos e clique em **Save**.

### Incluir vários de uma vez (planilha)
1. Monte um CSV com as colunas exatamente com estes nomes:
   `inscricao, nome, cargo, uf, macropolo, cota, situacao, nota, posicao_uf, class_macro, convocacao`
2. Table Editor → `aprovados` → **Insert → Import data from CSV**.
3. Confira a pré-visualização e clique em **Import data**.

Os valores de `cargo`, `uf`, `cota`, `situacao` e `convocacao` precisam ser escritos
exatamente como nas listas (com acentos e maiúsculas). Se algum estiver errado, o
Supabase mostra o erro e nada é importado.

### Revisar o que chegou pelo formulário
O aprovado preenche a aba **Informar convocação** do site (link direto: `.../Dashboard-geral/#informar`)
e recebe um **protocolo** de 6 caracteres (ex.: `K7P-4QX`). O formulário não pede nome, e-mail
nem documentos: a comissão confere pessoalmente, pelo grupo de WhatsApp.

1. Table Editor → `envios`, filtre `status` = **Pendente**.
2. Use o `protocolo` e a `inscricao` para achar a pessoa no grupo e conferir com ela
   (a coluna `aprovado_id` aponta para a pessoa em `aprovados`).
3. Mude `status` para:
   - **Aprovado**: a informação é aplicada sozinha em `aprovados`
     (Convocação → Convocado + data; Posse → Empossado + data; Desistência → Desistente).
     "Correção de dados" não é aplicada sozinha: corrija à mão em `aprovados`.
   - **Rejeitado**: nada muda. Se quiser, explique em `resposta_comissao`.
4. O aprovado acompanha o andamento no quadro **Acompanhar meu pedido**, digitando o protocolo.
   Ele vê "Em análise", "Aprovado" ou "Não aprovado" e o texto de `resposta_comissao`, se houver.

Regras automáticas do formulário: só aceita inscrição existente; as opções dependem da situação
atual (ex.: só quem já está Convocado pode informar Posse); data obrigatória para convocação e posse,
entre 26/05/2026 e hoje; um pedido em análise por vez para cada inscrição; limite de tentativas por
visitante (20 buscas a cada 10 min e 5 envios por hora).

### Ver quem mudou o quê
Table Editor → `historico`. Cada linha mostra a tabela, a ação, os dados antes e depois e
quando foi feito. Alterações feitas pelo painel do Supabase aparecem como `postgres`;
as que vêm do formulário aparecem como `formulário`.

## E-mail (SMTP)

Os e-mails saem pelo Gmail da comissão, com uma **senha de app** (myaccount.google.com/apppasswords,
exige verificação em duas etapas). A senha é colada em dois lugares do Supabase e em nenhum outro:

1. **Authentication → Emails → SMTP Settings** (e-mails de login): host `smtp.gmail.com`, porta `465`,
   usuário = Gmail da comissão, senha = senha de app.
2. **Edge Functions → Secrets** (avisos do Fale com a comissão): `SMTP_USER` = Gmail da comissão,
   `SMTP_PASS` = senha de app. Opcional: `CONTATO_PARA` para receber os avisos em outro e-mail.

Os modelos dos e-mails de login ficam em `docs/emails/` (colar em **Authentication → Emails → Templates**:
`login.html` em *Magic Link* e `primeiro-acesso.html` em *Confirm signup*; o assunto está no comentário
do topo de cada arquivo). Se trocar a senha do Gmail ou revogar a senha de app, atualize os dois lugares.

## Cuidados

- **Nunca** compartilhe a senha do banco nem a chave `service_role`.
- Para dar acesso a outro membro: **Organization settings → Team → Invite**.
  O papel **Developer** permite editar os dados. Um papel só de consulta (**Read-only**)
  pode depender do plano da organização.
- Apagar uma linha não tem "desfazer", mas os dados antigos ficam guardados no `historico`.
