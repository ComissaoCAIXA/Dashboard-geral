// Avisa no grupo de Telegram da comissão quando chega um pedido novo ou uma mensagem nova.
//
// Quem chama é o próprio banco (gatilho com pg_net, migração 020), só com {tabela, id}.
// A função não precisa de senha de quem chama porque só avisa registros recém-criados (10 min)
// que ainda não foram avisados: cada registro gera no máximo uma mensagem no grupo.
// O aviso não leva telefone, inscrição nem o texto da mensagem.
//
// Segredo (Supabase > Edge Functions > Secrets):
//   TELEGRAM_TOKEN  chave do bot (@BotFather)
// O número do grupo fica na tabela configuracao (chave telegram_chat_id).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const AREA = "https://comissaocaixa.github.io/Dashboard-geral/comissao.html";
const esc = (s: unknown) => String(s ?? "").replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]!));
const dataBR = (d?: string) => d ? d.split("-").reverse().join("/") : "";
const ICONE: Record<string, string> = {
  "Convocação": "📩", "Posse": "🎉", "Desistência": "🚪", "Correção de dados": "✏️",
  "Entrada no grupo": "👥", "Horário da convocação": "🕐",
};
const CARGO: Record<string, string> = {
  "Engenheiro Civil": "Eng. Civil", "Engenheiro Eletricista": "Eng. Eletricista", "Engenheiro Mecânico": "Eng. Mecânico",
  "Engenheiro de Segurança do Trabalho": "Eng. Seg. Trabalho",
};

function texto(r: Record<string, unknown>) {
  if (r.tabela === "mensagens") {
    return `💬 <b>Nova mensagem no Fale com a comissão</b>\n` +
      `Assunto: <b>${esc(r.assunto)}</b>\nDe: ${esc(r.nome)}\n\n` +
      `${r.aviso_email ? "O texto completo chegou no e-mail da comissão." : "Leia na área da comissão (aba Mensagens)."}\n` +
      `Mensagens sem resposta: <b>${r.pendentes}</b>`;
  }
  const tipo = String(r.tipo);
  const quem = [CARGO[String(r.cargo)] ?? r.cargo, r.uf, r.cota].filter(Boolean).map(esc).join(" · ");
  const quando = r.data ? `\nData informada: ${dataBR(String(r.data))}${r.hora ? " às " + String(r.hora).slice(0, 5) : ""}` :
    (r.hora ? `\nHorário informado: ${String(r.hora).slice(0, 5)}` : "");
  return `${ICONE[tipo] ?? "📌"} <b>Novo pedido: ${esc(tipo)}</b>\n` +
    `Protocolo <code>${esc(r.protocolo)}</code>\n${quem}${r.iniciais ? " · " + esc(r.iniciais) : ""}${quando}\n\n` +
    `Pedidos aguardando análise: <b>${r.pendentes}</b>`;
}

async function enviar(token: string, chat: string, html: string, aba: string) {
  const corpo = {
    chat_id: chat, text: html, parse_mode: "HTML", disable_web_page_preview: true,
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

  const aba = tabela === "mensagens" ? "Abrir mensagens" : "Abrir pedidos pendentes";
  let res = await enviar(token, r.chat, texto(r), aba);
  // Grupo virou supergrupo: o Telegram informa o número novo
  const novo = res?.parameters?.migrate_to_chat_id;
  if (!res.ok && novo) {
    await sb.rpc("_telegram_novo_chat", { p_chat: String(novo) });
    res = await enviar(token, String(novo), texto(r), aba);
  }
  if (!res.ok) {
    await sb.rpc("_telegram_falhou", { p_tabela: tabela, p_id: id });
    return ok({ ok: false, erro: res.description }, 502);
  }
  return ok({ ok: true });
});
