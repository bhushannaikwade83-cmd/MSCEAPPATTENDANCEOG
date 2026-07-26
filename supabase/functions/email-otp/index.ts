const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/**
 * OTP and credential emails via **Brevo** Transactional API.
 *
 * Supabase Dashboard → Project → Edge Functions → Secrets:
 * - BREVO_API_KEY — https://app.brevo.com → SMTP & API → API keys (transactional emails)
 *   (alias: SENDINBLUE_API_KEY)
 * - EMAIL_FROM    e.g. "MSCE Attendance <otp@yourdomain.com>" — must match a verified sender in Brevo
 *
 * If `BREVO_API_KEY` is not set, requests fail with HTTP 503.
 *
 * Deploy: `supabase functions deploy email-otp`
 */
const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? Deno.env.get("SENDINBLUE_API_KEY") ?? "";
const EMAIL_FROM = Deno.env.get("EMAIL_FROM") ?? "Attendance App <no-reply@example.com>";

function jsonResponse(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function escapeHtml(v: string): string {
  return v
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

/** Parses `Name <email@x.com>` or plain email. */
function parseEmailFrom(header: string): { name?: string; email: string } {
  const trimmed = header.trim();
  const angle = trimmed.match(/^(.+)<([^>]+)>$/);
  if (angle) {
    const name = angle[1].trim().replace(/^["']|["']$/g, "");
    return { name: name || undefined, email: angle[2].trim().toLowerCase() };
  }
  return { email: trimmed.toLowerCase() };
}

async function sendEmailBrevo(to: string, subject: string, html: string) {
  const sender = parseEmailFrom(EMAIL_FROM);
  const res = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      "api-key": BREVO_API_KEY,
    },
    body: JSON.stringify({
      sender: {
        name: sender.name ?? sender.email.split("@")[0] ?? "App",
        email: sender.email,
      },
      to: [{ email: to }],
      subject,
      htmlContent: html,
    }),
  });
  const body = await res.json().catch(() => ({}));
  // Brevo returns 201 on success
  const ok = res.ok || res.status === 201;
  return { ok, status: res.status, body, vendor: "brevo" as const };
}

async function sendEmail(to: string, subject: string, html: string) {
  if (BREVO_API_KEY) {
    return sendEmailBrevo(to, subject, html);
  }
  return { ok: false, status: 0, body: {} as Record<string, unknown>, vendor: "none" as const };
}

function friendlyBrevoError(errText: string): string {
  const lower = errText.toLowerCase();
  if (
    lower.includes("unrecognised ip") ||
    lower.includes("unrecognized ip") ||
    lower.includes("authorised_ips") ||
    lower.includes("authorized_ips")
  ) {
    return (
      "Brevo blocked this email (Supabase uses a new IP each time). " +
      "Fix: Brevo → Settings → Security → Authorized IPs → Deactivate blocking for API keys. " +
      "Do not whitelist one IP. Create a new API key and update Supabase secret BREVO_API_KEY."
    );
  }
  return errText;
}

function providerErrorMessage(body: unknown, vendor: string): string {
  if (!body || typeof body !== "object") return "";
  const o = body as Record<string, unknown>;
  if (typeof o.message === "string" && o.message.length > 0) {
    return friendlyBrevoError(o.message);
  }
  // Brevo validation errors sometimes use `code` + message array
  if (Array.isArray(o.message)) {
    try {
      return JSON.stringify(o.message);
    } catch {
      return String(o.message);
    }
  }
  void vendor;
  return "";
}

function hasOutboundEmailConfigured(): boolean {
  return Boolean(BREVO_API_KEY);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse(405, { success: false, error: "Method not allowed" });

  try {
    const body = await req.json();
    const mode = (body?.mode ?? "").toString();
    const to = (body?.to ?? "").toString().trim().toLowerCase();

    if (!hasOutboundEmailConfigured()) {
      return jsonResponse(503, {
        success: false,
        error: "Transactional email is not configured. Set BREVO_API_KEY on Edge Function secrets.",
      });
    }

    if (!to) return jsonResponse(400, { success: false, error: "to is required" });

    if (mode === "otp") {
      const otp = (body?.otp ?? "").toString();
      const purpose = (body?.purpose ?? "Login verification").toString();
      if (!otp) return jsonResponse(400, { success: false, error: "otp is required" });
      const subject = `Your OTP for ${purpose}`;
      const html = `
        <div style="font-family:Arial,sans-serif;line-height:1.5">
          <h2>Your One-Time Password</h2>
          <p>Use this OTP to continue:</p>
          <p style="font-size:28px;font-weight:bold;letter-spacing:4px">${escapeHtml(otp)}</p>
          <p>This OTP expires in 10 minutes.</p>
        </div>
      `;
      const sent = await sendEmail(to, subject, html);
      const errText = providerErrorMessage(sent.body, sent.vendor);
      return jsonResponse(sent.ok ? 200 : 502, {
        success: sent.ok,
        status: sent.status,
        provider: sent.body,
        emailVendor: sent.vendor,
        ...(sent.ok ? {} : { error: errText || `Brevo error (HTTP ${sent.status})` }),
      });
    }

    if (mode === "credentials") {
      const username = (body?.username ?? "").toString();
      const password = (body?.password ?? "").toString();
      const instituteName = (body?.instituteName ?? "").toString();
      const subject = "Your registration details";
      const html = `
        <div style="font-family:Arial,sans-serif;line-height:1.5">
          <h2>Registration Successful</h2>
          <p>Your account has been created${instituteName ? ` for <b>${escapeHtml(instituteName)}</b>` : ""}.</p>
          <p><b>Username:</b> ${escapeHtml(username || to)}</p>
          <p><b>Password:</b> ${escapeHtml(password)}</p>
          <p>Please change your password after first login.</p>
        </div>
      `;
      const sent = await sendEmail(to, subject, html);
      const errText = providerErrorMessage(sent.body, sent.vendor);
      return jsonResponse(sent.ok ? 200 : 502, {
        success: sent.ok,
        status: sent.status,
        provider: sent.body,
        emailVendor: sent.vendor,
        ...(sent.ok ? {} : { error: errText || `Brevo error (HTTP ${sent.status})` }),
      });
    }

    return jsonResponse(400, { success: false, error: "Unsupported mode. Use otp or credentials." });
  } catch (e) {
    return jsonResponse(500, { success: false, error: (e as Error).message });
  }
});
