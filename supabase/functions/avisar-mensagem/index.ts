// Envia para o e-mail da comissão o aviso de uma mensagem nova do "Fale com a comissão".
//
// O site grava a mensagem com enviar_mensagem (que limita tentativas por IP) e, em seguida,
// chama esta função só com o id. A função não precisa de senha de quem chama porque só envia
// mensagens recém-criadas (últimos 10 min) que ainda não foram avisadas: cada mensagem gera
// no máximo um e-mail, e ninguém consegue ler nada por aqui.
//
// Segredos (Supabase > Edge Functions > Secrets):
//   SMTP_USER     Gmail da comissão (remetente e, por padrão, destinatário)
//   SMTP_PASS     senha de app do Gmail (16 letras)
//   CONTATO_PARA  opcional: outro e-mail para receber os avisos
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const ORIGENS = ["https://comissaocaixa.github.io", "http://localhost:8766", "http://127.0.0.1:8766"];
const PAINEL = "https://comissaocaixa.github.io/Dashboard-geral/";

function cors(req: Request) {
  const o = req.headers.get("origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ORIGENS.includes(o) ? o : ORIGENS[0],
    "Access-Control-Allow-Headers": "apikey, authorization, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

function emailHtml(m: Record<string, string>, quando: string) {
  const linha = (rot: string, val: string) =>
    `<tr><td style="padding:4px 12px 4px 0;color:#6b6a66;font-size:13px;white-space:nowrap;vertical-align:top">${rot}</td><td style="padding:4px 0;font-size:14px">${val}</td></tr>`;
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f2;padding:24px 12px;font-family:Segoe UI,Helvetica,Arial,sans-serif;color:#0b0b0b">
<tr><td align="center"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border:1px solid #e1e0d9;border-radius:8px">
<tr><td style="padding:20px 24px 4px"><div style="font-size:12px;color:#6b6a66">Fale com a comissão · nova mensagem</div>
<div style="font-size:18px;font-weight:700;margin-top:2px">${esc(m.assunto)}</div></td></tr>
<tr><td style="padding:10px 24px 0"><table role="presentation" cellpadding="0" cellspacing="0">
${linha("De", `<b>${esc(m.nome)}</b>`)}${linha("E-mail", `<a href="mailto:${esc(m.email)}" style="color:#2a78d6">${esc(m.email)}</a>`)}${linha("Enviada em", esc(quando))}
</table></td></tr>
<tr><td style="padding:14px 24px 4px"><div style="background:#f4f4f2;border-radius:6px;padding:12px 14px;font-size:14px;line-height:1.55;white-space:pre-wrap">${esc(m.mensagem)}</div></td></tr>
<tr><td style="padding:12px 24px 20px;font-size:13px;color:#52514e;line-height:1.5">Para responder, use <b>Responder</b> no seu e-mail: a resposta vai direto para ${esc(m.email)}.
Depois, marque como respondida na <a href="${PAINEL}comissao.html" style="color:#2a78d6">área da comissão</a> (aba Mensagens).</td></tr>
<tr><td style="padding:12px 24px;border-top:1px solid #e1e0d9;font-size:12px;color:#898781">Comissão de Aprovados CAIXA 2026 · aviso automático do <a href="${PAINEL}" style="color:#898781">painel dos aprovados</a></td></tr>
</table></td></tr></table>`;
}

Deno.serve(async (req) => {
  const h = { ...cors(req), "Content-Type": "application/json" };
  if (req.method === "OPTIONS") return new Response("ok", { headers: h });
  if (req.method !== "POST") return new Response(JSON.stringify({ ok: false }), { status: 405, headers: h });

  let id = 0;
  try { id = Number((await req.json()).id); } catch { /* corpo inválido */ }
  if (!Number.isInteger(id) || id <= 0) return new Response(JSON.stringify({ ok: false }), { status: 400, headers: h });

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  // "Reserva" a mensagem: só uma chamada consegue marcar aviso_enviado=true (e só nos primeiros 10 min)
  const { data: m, error: erroDb } = await db.rpc("_aviso_reservar", { p_id: id });
  if (erroDb) console.error("Falha ao reservar", id, erroDb.message);
  if (!m) return new Response(JSON.stringify({ ok: true, enviado: false }), { headers: h });

  const usuario = Deno.env.get("SMTP_USER"), senha = Deno.env.get("SMTP_PASS");
  const para = Deno.env.get("CONTATO_PARA") || usuario;
  try {
    if (!usuario || !senha) throw new Error("SMTP_USER/SMTP_PASS não configurados");
    const quando = new Date(m.criado_em).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo", dateStyle: "short", timeStyle: "short" });
    const smtp = new SMTPClient({ connection: { hostname: "smtp.gmail.com", port: 465, tls: true, auth: { username: usuario, password: senha } } });
    await smtp.send({
      from: `Painel dos aprovados <${usuario}>`,
      to: para!,
      replyTo: `${m.nome.replace(/[<>"\r\n]/g, "")} <${m.email}>`,
      subject: `[Fale com a comissão] ${m.assunto} · ${m.nome}`.replace(/[\r\n]/g, " "),
      content: `Nova mensagem pelo painel dos aprovados.\n\nDe: ${m.nome} <${m.email}>\nEnviada em: ${quando}\nAssunto: ${m.assunto}\n\n${m.mensagem}\n\nResponda a este e-mail para falar com a pessoa. Depois, marque como respondida na área da comissão.`,
      html: emailHtml(m, quando),
    });
    await smtp.close();
    return new Response(JSON.stringify({ ok: true, enviado: true }), { headers: h });
  } catch (e) {
    // A mensagem continua salva e aparece na área da comissão; registra o motivo da falha
    await db.rpc("_aviso_falhou", { p_id: id, p_erro: String(e) });
    console.error("Falha ao enviar aviso", id, String(e));
    return new Response(JSON.stringify({ ok: true, enviado: false }), { headers: h });
  }
});
