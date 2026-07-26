const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const B2_KEY_ID = Deno.env.get("B2B_KEY_ID") ?? "";
const B2_APP_KEY = Deno.env.get("B2B_APPLICATION_KEY") ?? "";
const B2_BUCKET_NAME = Deno.env.get("B2B_BUCKET_NAME") ?? "";
const B2_BUCKET_ID = Deno.env.get("B2B_BUCKET_ID") ?? "";
const B2_API_BASE = "https://api.backblazeb2.com/b2api/v2";

function jsonResponse(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

async function b2Authorize() {
  const credentials = btoa(`${B2_KEY_ID}:${B2_APP_KEY}`);
  const res = await fetch(`${B2_API_BASE}/b2_authorize_account`, {
    method: "GET",
    headers: { Authorization: `Basic ${credentials}` },
  });
  if (!res.ok) throw new Error(`b2_authorize_account failed: ${res.status}`);
  const body = await res.json();
  return {
    authToken: body.authorizationToken as string,
    apiUrl: body.apiUrl as string,
    downloadUrl: body.downloadUrl as string,
  };
}

async function getUploadUrl(apiUrl: string, authToken: string) {
  const res = await fetch(`${apiUrl}/b2api/v2/b2_get_upload_url`, {
    method: "POST",
    headers: {
      Authorization: authToken,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ bucketId: B2_BUCKET_ID }),
  });
  if (!res.ok) throw new Error(`b2_get_upload_url failed: ${res.status}`);
  return await res.json();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse(405, { success: false, error: "Method not allowed" });

  if (!B2_KEY_ID || !B2_APP_KEY || !B2_BUCKET_NAME || !B2_BUCKET_ID) {
    return jsonResponse(500, { success: false, error: "Missing B2 edge env secrets" });
  }

  try {
    const body = await req.json();
    const action = (body?.action ?? "").toString();
    const { authToken, apiUrl, downloadUrl } = await b2Authorize();

    if (action === "upload_url") {
      const upload = await getUploadUrl(apiUrl, authToken);
      return jsonResponse(200, {
        success: true,
        uploadUrl: upload.uploadUrl,
        uploadAuthToken: upload.authorizationToken,
        bucketName: B2_BUCKET_NAME,
        downloadUrl,
      });
    }

    if (action === "download_auth") {
      const objectPath = (body?.objectPath ?? "").toString();
      const validSeconds = Number(body?.validSeconds ?? 300);
      if (!objectPath) return jsonResponse(400, { success: false, error: "objectPath required" });
      const res = await fetch(`${apiUrl}/b2api/v2/b2_get_download_authorization`, {
        method: "POST",
        headers: {
          Authorization: authToken,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          bucketId: B2_BUCKET_ID,
          fileNamePrefix: objectPath,
          validDurationInSeconds: Math.max(60, Math.min(validSeconds, 3600)),
        }),
      });
      if (!res.ok) throw new Error(`b2_get_download_authorization failed: ${res.status}`);
      const d = await res.json();
      return jsonResponse(200, {
        success: true,
        authorizationToken: d.authorizationToken,
        downloadUrl,
        bucketName: B2_BUCKET_NAME,
      });
    }

    if (action === "delete_file_version") {
      const fileName = (body?.fileName ?? "").toString();
      const fileId = (body?.fileId ?? "").toString();
      if (!fileName || !fileId) {
        return jsonResponse(400, { success: false, error: "fileName and fileId required" });
      }
      const res = await fetch(`${apiUrl}/b2api/v2/b2_delete_file_version`, {
        method: "POST",
        headers: {
          Authorization: authToken,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ fileName, fileId }),
      });
      if (!res.ok) throw new Error(`b2_delete_file_version failed: ${res.status}`);
      return jsonResponse(200, { success: true });
    }

    return jsonResponse(400, { success: false, error: "Unsupported action" });
  } catch (e) {
    return jsonResponse(500, { success: false, error: (e as Error).message });
  }
});
