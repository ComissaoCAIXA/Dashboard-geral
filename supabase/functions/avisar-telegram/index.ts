// Avisa no grupo de Telegram da comissão quando chega um pedido novo ou uma mensagem nova.
//
// Quem chama é o próprio banco (gatilho com pg_net, migração 020), só com {tabela, id}.
// A função não precisa de senha de quem chama porque só avisa registros recém-criados (10 min)
// que ainda não foram avisados: cada registro gera no máximo uma mensagem no grupo.
//
// Privacidade (migração 033): o aviso diz só O QUE chegou (tipo do pedido ou assunto da mensagem), o código
// (protocolo do pedido ou MSG-<id> da mensagem), quando chegou e os alertas sobre o pedido. Nada de quem é:
// nome, cargo, polo, cota, nota, observação, WhatsApp, e-mail e texto ficam só na área da comissão.
// O Telegram tem servidores fora do Brasil; por isso nenhum dado pessoal vai para lá.
//
// Segredo (Supabase > Edge Functions > Secrets):
//   TELEGRAM_TOKEN  chave do bot (@BotFather)
// O número do grupo fica na tabela configuracao (chave telegram_chat_id).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const AREA = "https://comissaocaixa.github.io/Dashboard-geral/comissao.html";
type R = Record<string, any>;
const esc = (s: unknown) => String(s ?? "").replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]!));
const dataBR = (d?: string | null) => d ? String(d).slice(0, 10).split("-").reverse().join("/") : "";
const horaBR = (h?: string | null) => h ? String(h).slice(0, 5) : "";
const quandoBR = (iso: string) => new Date(iso).toLocaleString("pt-BR", {
  timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit",
});
const ICONE: Record<string, string> = {
  "Convocação": "📩", "Posse": "🎉", "Desistência": "🚪", "Correção de dados": "✏️",
  "Entrada no grupo": "👥", "Horário da convocação": "🕐", "Final da fila": "⤵️", "Retirar final da fila": "↩️", "Reclassificação confirmada": "⏬",
};

// O que foi informado (sem dados da pessoa) e o que acontece ao aprovar
function informado(r: R): string[] {
  const d = dataBR(r.data), h = horaBR(r.hora);
  switch (r.tipo) {
    case "Convocação":
      return [`Data informada: <b>${d || "não informada"}</b>${h ? ` às <b>${h}</b>` : ""}`];
    case "Posse":
      return [`Data da posse informada: <b>${d || "não informada"}</b>`];
    case "Desistência":
      return [d ? `Data informada: <b>${d}</b>` : "Sem data informada"];
    case "Horário da convocação":
      return [`Convocação em <b>${d || "–"}</b> às <b>${h || "–"}</b>`];
    case "Final da fila":
    case "Reclassificação confirmada":
      return r.final_fila_lista ? [`Lista indicada: <b>${esc(r.final_fila_lista)}</b>`] : [];
    case "Entrada no grupo": {
      const expira = new Date(new Date(r.criado_em).getTime() + 24 * 3600 * 1000).toISOString();
      return [`<i>Responda até ${quandoBR(expira)}: depois disso o pedido expira e o número é apagado.</i>`];
    }
  }
  return [];
}

function textoPedido(r: R) {
  const tipo = String(r.tipo);
  const linhas = [
    `${ICONE[tipo] ?? "📌"} <b>Novo pedido: ${esc(tipo)}</b>`,
    `Código: <code>${esc(r.protocolo)}</code>${r.envio && r.envio !== r.protocolo ? ` (enviado junto com <code>${esc(r.envio)}</code>)` : ""}`,
    `Recebido em ${quandoBR(r.criado_em)}`,
  ];
  const inf = informado(r);
  if (inf.length) linhas.push("", ...inf);
  const al: string[] = r.alertas ?? [];
  if (al.length) linhas.push("", `⚠️ <b>Atenção</b>`, ...al.map((a) => `• ${esc(a)}`));
  linhas.push("", `Quem enviou e os detalhes estão na área da comissão (procure pelo código).`,
    `Pedidos aguardando análise: <b>${r.pendentes}</b>`);
  return linhas.join("\n");
}

function textoMensagem(r: R) {
  return [
    `💬 <b>Nova mensagem no Fale com a comissão</b>`,
    `Código: <code>MSG-${esc(r.id)}</code>`,
    `Assunto: <b>${esc(r.assunto)}</b>`,
    `Recebida em ${quandoBR(r.criado_em)}`,
    "",
    `Quem enviou e o texto estão na área da comissão e no e-mail da comissão (procure pelo código).`,
    `Mensagens sem resposta: <b>${r.pendentes}</b>`,
  ].join("\n");
}

async function enviar(token: string, chat: string, html: string, aba: string) {
  const corpo = {
    chat_id: chat, text: html.slice(0, 4000), parse_mode: "HTML", disable_web_page_preview: true,
    reply_markup: { inline_keyboard: [[{ text: aba, url: AREA }]] },
  };
  const r = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(corpo),
  });
  return await r.json();
}

Deno.serve(async (req) => {
  const ok = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { "Content-Type": "application/json" } });
  if (req.method !== "POST") return ok({ ok: false }, 405);
  let tabela = "", id = 0;
  try { ({ tabela, id } = await req.json()); } catch { return ok({ ok: false }, 400); }
  if (!["envios", "mensagens"].includes(tabela) || !Number.isInteger(id)) return ok({ ok: false }, 400);

  const token = (Deno.env.get("TELEGRAM_TOKEN") ?? "").trim();
  if (!token) return ok({ ok: false, erro: "TELEGRAM_TOKEN ausente" }, 500);
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const { data: r, error } = await sb.rpc("_telegram_reservar", { p_tabela: tabela, p_id: id });
  if (error) return ok({ ok: false, erro: error.message }, 500);
  if (!r) return ok({ ok: true, ignorado: true }); // já avisado, antigo ou inexistente

  const html = tabela === "mensagens" ? textoMensagem(r) : textoPedido(r);
  const aba = tabela === "mensagens" ? "Abrir mensagens" : "Abrir pedidos pendentes";
  let res = await enviar(token, r.chat, html, aba);
  // Grupo virou supergrupo: o Telegram informa o número novo
  const novo = res?.parameters?.migrate_to_chat_id;
  if (!res.ok && novo) {
    await sb.rpc("_telegram_novo_chat", { p_chat: String(novo) });
    res = await enviar(token, String(novo), html, aba);
  }
  if (!res.ok) {
    await sb.rpc("_telegram_falhou", { p_tabela: tabela, p_id: id });
    return ok({ ok: false, erro: res.description }, 502);
  }
  return ok({ ok: true });
});
