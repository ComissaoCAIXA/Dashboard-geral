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
// Assunto com acentos: a biblioteca quebra o cabeçalho quando o assunto é longo (o e-mail chega "cru").
// Por isso o assunto já vai codificado em pedaços curtos (RFC 2047, base64), que todo leitor de e-mail junta de volta.
function assuntoCodificado(texto: string) {
  const b64 = (s: string) => btoa(String.fromCharCode(...new TextEncoder().encode(s)));
  const partes: string[] = [];
  let atual = "";
  for (const ch of Array.from(texto.replace(/[\r\n]+/g, " "))) {
    if (new TextEncoder().encode(atual + ch).length > 30) { partes.push(atual); atual = ""; }
    atual += ch;
  }
  if (atual) partes.push(atual);
  return partes.map((p) => `=?UTF-8?B?${b64(p)}?=`).join(" ");
}

// Mesmo visual dos e-mails de login (docs/emails/)
function emailHtml(m: Record<string, string>, quando: string) {
  const partes = m.nome.trim().split(/\s+/);
  const iniciais = ((partes[0]?.[0] ?? "") + (partes.length > 1 ? partes[partes.length - 1][0] : "")).toUpperCase();
  const primeiro = partes[0] ?? "";
  const responder = `mailto:${encodeURIComponent(m.email)}?subject=${encodeURIComponent("Re: " + m.assunto)}`;
  return `<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent">${esc(m.nome)}: ${esc(m.mensagem.slice(0, 110))}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#eef1f5" style="background:#eef1f5;font-family:'Segoe UI',Helvetica,Arial,sans-serif;color:#0b0b0b">
<tr><td align="center" style="padding:32px 12px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px">
  <tr><td style="padding:0 4px 14px"><table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
    <td width="30" height="30" bgcolor="#2a78d6" align="center" valign="middle" style="width:30px;height:30px;background:#2a78d6;border-radius:7px;color:#ffffff;font-weight:700;font-size:14px;line-height:30px">C</td>
    <td style="padding-left:10px;font-size:13px;font-weight:600;color:#3b3a37">Comissão de Aprovados · Concurso CAIXA 2026</td>
  </tr></table></td></tr>

  <tr><td bgcolor="#ffffff" style="background:#ffffff;border:1px solid #dde1e7;border-radius:12px;overflow:hidden">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
    <tr><td height="4" bgcolor="#2a78d6" style="height:4px;background:#2a78d6;font-size:0;line-height:0">&nbsp;</td></tr>
    <tr><td style="padding:26px 32px 4px">
      <div style="font-size:12px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:#2a78d6">Fale com a comissão · nova mensagem</div>
      <h1 style="margin:6px 0 0;font-size:21px;line-height:1.3;font-weight:700;color:#0b0b0b">${esc(m.assunto)}</h1>
    </td></tr>

    <!-- Quem enviou -->
    <tr><td style="padding:18px 32px 0"><table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
      <td width="42" height="42" bgcolor="#e3eefb" align="center" valign="middle" style="width:42px;height:42px;background:#e3eefb;border-radius:21px;color:#2a78d6;font-weight:700;font-size:15px;line-height:42px">${esc(iniciais)}</td>
      <td style="padding-left:12px;line-height:1.4">
        <div style="font-size:15px;font-weight:700;color:#0b0b0b">${esc(m.nome)}</div>
        <div style="font-size:13px"><a href="mailto:${esc(m.email)}" style="color:#2a78d6;text-decoration:none">${esc(m.email)}</a> <span style="color:#8a8d93">· ${esc(quando)}</span></div>
      </td>
    </tr></table></td></tr>

    <!-- Mensagem -->
    <tr><td style="padding:18px 32px 0"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
      <td bgcolor="#f7f8fa" style="background:#f7f8fa;border-left:3px solid #2a78d6;border-radius:0 8px 8px 0;padding:16px 18px;font-size:15px;line-height:1.6;color:#1f2023;white-space:pre-wrap">${esc(m.mensagem)}</td>
    </tr></table></td></tr>

    <!-- Ações -->
    <tr><td style="padding:24px 32px 6px"><table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
      <td bgcolor="#2a78d6" style="background:#2a78d6;border-radius:8px"><a href="${responder}" style="display:inline-block;padding:13px 26px;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:8px">Responder a ${esc(primeiro)} &rarr;</a></td>
      <td style="padding-left:14px;font-size:14px"><a href="${PAINEL}comissao.html" style="color:#2a78d6;text-decoration:none;font-weight:600">Abrir área da comissão</a></td>
    </tr></table></td></tr>

    <tr><td style="padding:16px 32px 28px">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
        <td bgcolor="#f7f8fa" style="background:#f7f8fa;border-radius:8px;padding:14px 16px;font-size:13px;line-height:1.55;color:#4a4d52">
          &#9993;&nbsp; Ao clicar em <b>Responder</b> no seu e-mail, a resposta vai direto para ${esc(primeiro)}.<br>
          &#10003;&nbsp; Depois de responder, marque como respondida na aba <b>Mensagens</b> da área da comissão, para ninguém responder duas vezes.
        </td>
      </tr></table>
    </td></tr>
  </table></td></tr>

  <tr><td align="center" style="padding:18px 8px 0;font-size:12px;line-height:1.6;color:#8a8d93">
    Aviso automático do <a href="${PAINEL}" style="color:#2a78d6;text-decoration:none">painel dos aprovados</a>. A mensagem também fica guardada na área da comissão.
  </td></tr>
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
      replyTo: `${assuntoCodificado(m.nome.replace(/[<>"\r\n]/g, ""))} <${m.email}>`,
      subject: assuntoCodificado(`[Fale com a comissão] ${m.assunto} · ${m.nome}`),
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
