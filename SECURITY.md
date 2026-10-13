# Segurança e dados pessoais

Este painel é mantido voluntariamente pela Comissão de Aprovados do Concurso CAIXA 2026 e não
tem vínculo com a CAIXA. Levamos a sério a proteção dos dados dos aprovados.

## Como avisar

Se você encontrou uma falha de segurança, um dado pessoal exposto (inscrição, telefone, e-mail,
CPF) ou uma informação que deveria estar oculta:

1. **Não abra uma issue pública** e não divulgue o problema antes de ele ser corrigido.
2. Avise a comissão por um destes caminhos:
   - **Relato privado no GitHub:** aba *Security* deste repositório → *Report a vulnerability*;
   - **Fale com a comissão** no painel: https://comissaocaixa.github.io/Dashboard-geral/#contato
     (escolha o assunto "Correção de dados no painel" ou "Outro assunto").
3. Descreva o que encontrou e, se possível, como reproduzir.

A comissão responde assim que possível e corrige com prioridade qualquer exposição de dado pessoal.

## Pedido sobre os seus dados

Aprovados podem pedir, pelo Fale com a comissão, que o painel mostre só as iniciais do nome ou
que um dado seja corrigido.

## O que está no escopo

- O painel público (`index.html`) e a área da comissão (`comissao.html`).
- As regras de acesso do banco de dados (`supabase/migrations/`) e a função de aviso por e-mail
  (`supabase/functions/`).

Os sistemas da CAIXA, da banca e do Supabase/GitHub não fazem parte deste projeto.
