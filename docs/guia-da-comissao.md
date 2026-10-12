# Guia da comissão — banco de dados

Como consultar, incluir e corrigir os dados dos aprovados direto no Supabase.

## Onde ficam os dados

Projeto **Dashboard-geral** no Supabase (organização "Comissão de aprovados CAIXA").
Acesse em supabase.com/dashboard → projeto → **Table Editor** (ícone de tabela no menu à esquerda).

| Tabela | O que guarda | Quem vê |
|---|---|---|
| `aprovados` | A base oficial: nome, inscrição, cargo, UF, cota, nota, situação e convocação | O site vê só iniciais, cargo, UF, cota, nota e situação. Nome e inscrição ficam só aqui |
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
1. Table Editor → `envios`, filtre `status` = **Pendente**.
2. Confira a informação (a coluna `aprovado_id` aponta para a pessoa em `aprovados`).
3. Mude `status` para:
   - **Aprovado**: a informação é aplicada sozinha em `aprovados`
     (Convocação → Convocado + data; Posse → Empossado + data; Desistência → Desistente).
     "Correção de dados" não é aplicada sozinha: corrija à mão em `aprovados`.
   - **Rejeitado**: nada muda. Se quiser, explique em `resposta_comissao`.

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
