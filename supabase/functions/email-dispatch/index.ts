import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-queue-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type SendPayload = {
  to: string;
  subject: string;
  html: string;
  metadata?: Record<string, unknown>;
  sendNow?: boolean;
};

type ProcessPayload = {
  mode: "process";
  limit?: number;
  delayMs?: number;
};

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const EMAIL_FROM = Deno.env.get("EMAIL_FROM") ?? "Attendance App <no-reply@example.com>";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const EMAIL_QUEUE_CRON_SECRET = Deno.env.get("EMAIL_QUEUE_CRON_SECRET") ?? "";

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

function jsonResponse(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

async function resendSendEmail(to: string, subject: string, html: string) {
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: EMAIL_FROM,
      to: [to],
      subject,
      html,
    }),
  });

  const body = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, body };
}

function getBackoffSeconds(attempts: number): number {
  const backoff = Math.min(3600, Math.pow(2, Math.max(1, attempts)) * 15);
  return Math.floor(backoff);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse(405, { success: false, error: "Method not allowed" });
  }

  if (!RESEND_API_KEY || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return jsonResponse(500, {
      success: false,
      error: "Missing required server environment variables",
    });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  let payload: SendPayload | ProcessPayload;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse(400, { success: false, error: "Invalid JSON body" });
  }

  // Queue processor mode for cron/internal calls.
  if ((payload as ProcessPayload).mode === "process") {
    const secret = req.headers.get("x-queue-secret") ?? "";
    if (!EMAIL_QUEUE_CRON_SECRET || secret !== EMAIL_QUEUE_CRON_SECRET) {
      return jsonResponse(401, { success: false, error: "Unauthorized queue processor call" });
    }

    const processPayload = payload as ProcessPayload;
    const limit = Math.max(1, Math.min(processPayload.limit ?? 50, 200));
    const delayMs = Math.max(50, Math.min(processPayload.delayMs ?? 120, 2000));

    const { data: jobs, error: claimError } = await supabase.rpc("claim_email_jobs", {
      p_limit: limit,
    });

    if (claimError) {
      return jsonResponse(500, {
        success: false,
        error: "Failed to claim email jobs",
        details: claimError.message,
      });
    }

    let sent = 0;
    let failed = 0;
    for (const job of jobs ?? []) {
      const emailResult = await resendSendEmail(job.to_email, job.subject, job.html);
      if (emailResult.ok) {
        await supabase.rpc("mark_email_job_sent", {
          p_job_id: job.id,
          p_provider_message_id: emailResult.body?.id ?? null,
          p_provider_response: emailResult.body ?? {},
        });
        sent += 1;
      } else {
        const retryDelay = getBackoffSeconds(job.attempts ?? 1);
        await supabase.rpc("mark_email_job_failed", {
          p_job_id: job.id,
          p_error_message: emailResult.body?.message ?? `Resend status ${emailResult.status}`,
          p_retry_delay_seconds: retryDelay,
          p_provider_response: emailResult.body ?? {},
        });
        failed += 1;
      }
      await sleep(delayMs);
    }

    return jsonResponse(200, {
      success: true,
      mode: "process",
      claimed: (jobs ?? []).length,
      sent,
      failed,
    });
  }

  const sendPayload = payload as SendPayload;
  const to = sendPayload.to?.trim();
  const subject = sendPayload.subject?.trim();
  const html = sendPayload.html;

  if (!to || !subject || !html) {
    return jsonResponse(400, {
      success: false,
      error: "Fields 'to', 'subject', and 'html' are required",
    });
  }
  if (!isValidEmail(to)) {
    return jsonResponse(400, { success: false, error: "Invalid recipient email" });
  }

  // Queue-first default: fast response and non-blocking app flow.
  const { data: jobId, error: enqueueError } = await supabase.rpc("enqueue_email_job", {
    p_to_email: to,
    p_subject: subject,
    p_html: html,
    p_metadata: sendPayload.metadata ?? {},
    p_max_attempts: 5,
  });

  if (enqueueError) {
    return jsonResponse(500, {
      success: false,
      error: "Failed to enqueue email",
      details: enqueueError.message,
    });
  }

  // Optional synchronous send for urgent emails.
  if (sendPayload.sendNow === true) {
    const emailResult = await resendSendEmail(to, subject, html);
    if (emailResult.ok) {
      await supabase.rpc("mark_email_job_sent", {
        p_job_id: jobId,
        p_provider_message_id: emailResult.body?.id ?? null,
        p_provider_response: emailResult.body ?? {},
      });
      return jsonResponse(200, {
        success: true,
        mode: "send_now",
        jobId,
        providerMessageId: emailResult.body?.id ?? null,
      });
    }

    await supabase.rpc("mark_email_job_failed", {
      p_job_id: jobId,
      p_error_message: emailResult.body?.message ?? `Resend status ${emailResult.status}`,
      p_retry_delay_seconds: 60,
      p_provider_response: emailResult.body ?? {},
    });

    return jsonResponse(502, {
      success: false,
      mode: "send_now",
      jobId,
      error: "Provider rejected email",
      providerStatus: emailResult.status,
      providerResponse: emailResult.body ?? {},
    });
  }

  return jsonResponse(202, {
    success: true,
    mode: "queued",
    jobId,
    message: "Email queued successfully",
  });
});
