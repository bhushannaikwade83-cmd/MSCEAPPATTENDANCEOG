const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

// Baseline free verifier:
// - no client secret required
// - validates basic platform/token shape only
// - suitable as a low-cost pre-login device trust gate
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse(405, { success: false, error: "Method not allowed" });

  try {
    const body = await req.json();
    const platform = (body?.platform ?? "").toString().toLowerCase();
    const token = (body?.token ?? "").toString();

    if (!platform || !token) {
      return jsonResponse(400, { success: false, verified: false, reason: "platform and token required" });
    }

    // App sends a deterministic device fingerprint token (16 chars) in free mode.
    const looksValid = token.length >= 16 && (platform === "android" || platform === "ios");
    return jsonResponse(200, {
      success: true,
      verified: looksValid,
      riskLevel: looksValid ? "low" : "high",
      reason: looksValid ? "token accepted by baseline verifier" : "token shape invalid",
    });
  } catch (e) {
    return jsonResponse(500, { success: false, verified: false, reason: (e as Error).message });
  }
});
