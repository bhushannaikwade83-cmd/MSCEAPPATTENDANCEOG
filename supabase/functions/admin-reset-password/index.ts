const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

function jsonResponse(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return jsonResponse(405, { success: false, error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    return jsonResponse(500, { success: false, error: "Server misconfigured" });
  }

  const adminClient = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    const body = await req.json().catch(() => ({}));
    const instituteKey = (body.instituteKey ?? body.institute_key ?? "").toString().trim();
    const email = (body.email ?? "").toString().trim().toLowerCase();
    const otp = (body.otp ?? "").toString().trim();
    const newPassword = (body.newPassword ?? body.new_password ?? "").toString();

    if (!instituteKey || !email || !otp || !newPassword) {
      return jsonResponse(400, { success: false, error: "Missing required fields" });
    }
    if (newPassword.length < 8) {
      return jsonResponse(400, {
        success: false,
        error: "Password must be at least 8 characters",
      });
    }

    const { data: verifyRaw, error: verifyErr } = await adminClient.rpc(
      "consume_admin_password_reset_otp",
      {
        p_institute_key: instituteKey,
        p_email: email,
        p_otp: otp,
      },
    );

    if (verifyErr) {
      console.error("consume_admin_password_reset_otp:", verifyErr);
      return jsonResponse(400, { success: false, error: verifyErr.message });
    }

    const verify =
      typeof verifyRaw === "object" && verifyRaw !== null
        ? verifyRaw as Record<string, unknown>
        : {};

    if (verify.success !== true) {
      return jsonResponse(400, {
        success: false,
        error: (verify.message ?? "OTP verification failed").toString(),
      });
    }

    const profileId = (verify.profile_id ?? "").toString();
    if (!profileId) {
      return jsonResponse(400, { success: false, error: "Profile not resolved" });
    }

    const { error: updateErr } = await adminClient.auth.admin.updateUserById(
      profileId,
      { password: newPassword },
    );

    if (updateErr) {
      console.error("updateUserById:", updateErr);
      return jsonResponse(500, {
        success: false,
        error: updateErr.message ?? "Could not update password",
      });
    }

    return jsonResponse(200, {
      success: true,
      message: "Password updated. Sign in with your new password.",
    });
  } catch (e) {
    console.error("admin-reset-password:", e);
    return jsonResponse(500, {
      success: false,
      error: e instanceof Error ? e.message : "Unexpected error",
    });
  }
});
