// Avisa no grupo de Telegram da comissão quando chega um pedido novo ou uma mensagem nova.
//
// Quem chama é o próprio banco (gatilho com pg_net, migração 020), só com {tabela, id}.
// A função não precisa de senha de quem chama porque só avisa registros recém-criados (10 min)
// que ainda não foram avisados: cada registro gera no máximo uma mensagem no grupo.
// O aviso traz o nome, a situação da pessoa no painel, o que foi informado e os alertas
// (migração 021). Telefone e número de inscrição nunca vão para o Telegram.
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
const nota = (v: unknown) => v == null ? "–" : Number(v).toLocaleString("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 2 });
const UF: Record<string, string> = {
  AC: "Acre", AL: "Alagoas", AP: "Amapá", AM: "Amazonas", BA: "Bahia", CE: "Ceará", DF: "Distrito Federal",
  ES: "Espírito Santo", GO: "Goiás", MA: "Maranhão", MT: "Mato Grosso", MS: "Mato Grosso do Sul", MG: "Minas Gerais",
  PA: "Pará", PB: "Paraíba", PR: "Paraná", PE: "Pernambuco", PI: "Piauí", RJ: "Rio de Janeiro", RN: "Rio Grande do Norte",
  RS: "Rio Grande do Sul", RO: "Rondônia", RR: "Roraima", SC: "Santa Catarina", SP: "São Paulo", SE: "Sergipe", TO: "Tocantins",
};
const COTA: Record<string, string> = {
  AC: "Ampla concorrência", PcD: "Pessoa com deficiência", PN: "Pessoas negras", PI: "Pessoas indígenas", PQ: "Pessoas quilombolas",
};
const ICONE: Record<string, string> = {
  "Convocação": "📩", "Posse": "🎉", "Desistência": "🚪", "Correção de dados": "✏️",
  "Entrada no grupo": "👥", "Horário da convocação": "🕐",
};

// Situação atual da pessoa no painel
function situacao(r: R) {
  const c = r.convocacao ?? "Sem informação";
  let s = esc(c);
  if (c === "Convocado" || c === "Empossado" || c === "Desistente") {
    if (r.validacao === "Presumida") s += " (presumida)";
    if (r.data_convocacao) s += ` em ${dataBR(r.data_convocacao)}${r.hora_convocacao ? " às " + horaBR(r.hora_convocacao) : ""}`;
  }
  if (r.data_posse) s += ` · posse em ${dataBR(r.data_posse)}`;
  return s;
}

// O que a pessoa informou e o que acontece ao aprovar, por tipo de pedido
function informado(r: R): string[] {
  const d = dataBR(r.data), h = horaBR(r.hora);
  switch (r.tipo) {
    case "Convocação":
      return [`Data da convocação: <b>${d || "não informada"}</b>${h ? ` às <b>${h}</b>` : ""}`,
        `<i>Ao aprovar: passa a Convocado (confirmada) em ${d}${h ? " às " + h : ""}.</i>`];
    case "Posse":
      return [`Data da posse: <b>${d || "não informada"}</b>`, `<i>Ao aprovar: passa a Empossado em ${d}.</i>`];
    case "Desistência":
      return [d ? `Data informada: <b>${d}</b>` : "Sem data informada", `<i>Ao aprovar: passa a Desistente e sai da fila.</i>`];
    case "Horário da convocação":
      return [`Convocação em <b>${d || "–"}</b> às <b>${h || "–"}</b>`,
        `<i>Ao aprovar: o horário é gravado${r.validacao === "Presumida" ? " e a convocação presumida passa a confirmada" : ""}.</i>`];
    case "Correção de dados":
      return [`<i>A correção não é aplicada sozinha: ajuste à mão na aba Aprovados depois de conferir.</i>`];
    case "Entrada no grupo": {
      const expira = new Date(new Date(r.criado_em).getTime() + 24 * 3600 * 1000).toISOString();
      return [r.nome_whatsapp ? `Nome no WhatsApp: <b>${esc(r.nome_whatsapp)}</b>` : "Nome no WhatsApp: não informado",
        `WhatsApp: veja na área da comissão (o número não vem para o Telegram).`,
        `<i>Responda até ${quandoBR(expira)}: depois disso o pedido expira e o número é apagado.</i>`];
    }
  }
  return [];
}

function textoPedido(r: R) {
  const tipo = String(r.tipo);
  const linhas = [
    `${ICONE[tipo] ?? "📌"} <b>Novo pedido: ${esc(tipo)}</b>`,
    `Protocolo <code>${esc(r.protocolo)}</code> · recebido em ${quandoBR(r.criado_em)}`,
    "",
    `👤 <b>${esc(r.nome ?? "Pessoa não encontrada")}</b>`,
  ];
  if (r.cargo) {
    linhas.push(
      `${esc(r.cargo)} · ${esc(UF[r.uf] ?? r.uf)} (${esc(r.uf)}) · ${esc(r.macropolo)}`,
      `${esc(COTA[r.cota] ?? r.cota)} · ${esc(r.situacao)}`,
      `${r.posicao_uf}º no estado${r.class_macro ? ` · ${r.class_macro}º no macropolo` : ""} · nota ${nota(r.nota)}`,
      `No painel: ${situacao(r)}`,
      `Grupo de WhatsApp: ${r.no_grupo ? "✅ verificado" : "❌ ainda não marcado"}`,
    );
  }
  linhas.push("", `📝 <b>Informado</b>`, ...informado(r));
  if (r.observacao) linhas.push("", `💬 <b>Observação da pessoa</b>`, `<blockquote>${esc(r.observacao)}</blockquote>`);
  const al: string[] = r.alertas ?? [];
  if (al.length) linhas.push("", `⚠️ <b>Atenção</b>`, ...al.map((a) => `• ${esc(a)}`));
  linhas.push("", `Pedidos aguardando análise: <b>${r.pendentes}</b>`);
  return linhas.join("\n");
}

function textoMensagem(r: R) {
  const cortada = Number(r.tamanho) > String(r.mensagem ?? "").length;
  return [
    `💬 <b>Nova mensagem no Fale com a comissão</b>`,
    `Recebida em ${quandoBR(r.criado_em)}`,
    "",
    `Assunto: <b>${esc(r.assunto)}</b>`,
    `👤 ${esc(r.nome)}`,
    `✉️ ${esc(r.email)}`,
    "",
    `<blockquote>${esc(r.mensagem)}${cortada ? "…" : ""}</blockquote>`,
    cortada ? `<i>Texto cortado: a mensagem completa está na área da comissão e no e-mail.</i>` : "",
    `Para responder, use o e-mail da comissão (Responder no aviso) e depois marque como respondida.`,
    "",
    `Mensagens sem resposta: <b>${r.pendentes}</b>`,
  ].filter((l, i, a) => !(l === "" && a[i - 1] === "")).join("\n");
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
