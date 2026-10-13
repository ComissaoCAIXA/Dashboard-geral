# Guia da comissão — banco de dados

## Área da comissão (recomendado)

Endereço: `https://comissaocaixa.github.io/Dashboard-geral/comissao.html`

- **Entrar:** digite seu e-mail e clique no link que chega por e-mail (sem senha).
  Só entra quem está na tabela `comissao` com `ativo` marcado.
- **Pedidos pendentes:** cada pedido mostra protocolo, o que a pessoa informou, os dados completos
  dela e alertas automáticos. Confira pelo WhatsApp e clique em **Aprovar** ou **Não aprovar**
  (a resposta opcional aparece para o aprovado na consulta do protocolo).
- **Aprovados:** busque por nome, inscrição ou UF e edite situação, datas, observação interna
  ou **ocultar o nome** no painel (para quem pediu para aparecer só com iniciais).
- **Histórico:** as últimas 100 alterações, com o e-mail de quem fez.
- **Exportar CSV:** baixa a base completa (guarde como cópia de segurança).

### Incluir ou remover membros
Supabase → Table Editor → tabela **`comissao`** → Insert row: preencha `email` (e, se quiser, `nome`).
Para tirar o acesso, desmarque `ativo`. Não é preciso mais nada: a pessoa já pode entrar pela área.

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

## Cuidados

- **Nunca** compartilhe a senha do banco nem a chave `service_role`.
- Para dar acesso a outro membro: **Organization settings → Team → Invite**.
  O papel **Developer** permite editar os dados. Um papel só de consulta (**Read-only**)
  pode depender do plano da organização.
- Apagar uma linha não tem "desfazer", mas os dados antigos ficam guardados no `historico`.
