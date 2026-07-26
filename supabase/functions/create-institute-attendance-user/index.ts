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

async function sha256Hex(message: string): Promise<string> {
  const msgBuffer = new TextEncoder().encode(message);
  const hashBuffer = await crypto.subtle.digest("SHA-256", msgBuffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

function mergeFullName(
  full: string,
  first?: string,
  middle?: string,
  last?: string,
): string {
  const parts = [first, middle, last].map((s) => (s ?? "").toString().trim()).filter((p) => p.length > 0);
  const joined = parts.join(" ").replace(/\s+/g, " ").trim();
  const fromFields = joined.length > 0 ? joined : "";
  const fromFull = full.trim();
  if (fromFull.length > 0) return fromFull;
  return fromFields.length > 0 ? fromFields : "Staff";
}

const STAFF_EMAIL_DOMAIN = "@staff.msce-attendance.app";

/** Older builds used one fixed email per institute (UUID or institute_code). */
function legacyStaffEmails(instituteId: string, instituteCode: string): string[] {
  const emails = new Set<string>();
  emails.add(`att.${instituteId}${STAFF_EMAIL_DOMAIN}`.toLowerCase());
  if (instituteCode) {
    emails.add(`att.${instituteCode}${STAFF_EMAIL_DOMAIN}`.toLowerCase());
  }
  return [...emails];
}

function staffBelongsToInstitute(
  email: string,
  meta: Record<string, unknown>,
  instId: string,
  instituteCode: string,
  legacyEmails: Set<string>,
): boolean {
  const metaInst = (meta.institute_id ?? "").toString().trim();
  const metaRole = (meta.app_role ?? "").toString().toLowerCase();
  if (legacyEmails.has(email.toLowerCase())) return true;
  if (metaRole !== "attendance_user") return false;
  return metaInst === instId || (instituteCode.length > 0 && metaInst === instituteCode);
}

async function deleteAuthUserById(
  adminClient: ReturnType<typeof createClient>,
  userId: string,
): Promise<void> {
  await adminClient.auth.admin.deleteUser(userId);
}

/** Remove Auth users for this institute when profiles has no attendance_user (ghost / failed signup). */
async function cleanupOrphanInstructorAuth(
  adminClient: ReturnType<typeof createClient>,
  instId: string,
  instituteCode: string,
): Promise<number> {
  let removed = 0;
  const legacyEmails = new Set(legacyStaffEmails(instId, instituteCode));

  let page = 1;
  const perPage = 200;
  for (;;) {
    const { data, error } = await adminClient.auth.admin.listUsers({ page, perPage });
    if (error || !data?.users?.length) break;

    for (const u of data.users) {
      const email = (u.email ?? "").toLowerCase();
      if (!email.endsWith(STAFF_EMAIL_DOMAIN)) continue;

      const meta = (u.user_metadata ?? {}) as Record<string, unknown>;
      if (!staffBelongsToInstitute(email, meta, instId, instituteCode, legacyEmails)) {
        continue;
      }

      const { data: prof } = await adminClient
        .from("profiles")
        .select("role")
        .eq("id", u.id)
        .maybeSingle();

      const role = (prof?.role ?? "").toString();
      if (role === "attendance_user") continue;

      await deleteAuthUserById(adminClient, u.id);
      removed++;
    }

    if (data.users.length < perPage) break;
    page++;
  }

  return removed;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse(405, { success: false, error: "Method not allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    return jsonResponse(500, { success: false, error: "Server misconfigured" });
  }

  const adminClient = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!jwt) {
      return jsonResponse(401, { success: false, error: "Unauthorized" });
    }

    const { data: userData, error: userErr } = await adminClient.auth.getUser(jwt);
    if (userErr || !userData?.user) {
      return jsonResponse(401, { success: false, error: "Invalid session" });
    }

    const callerId = userData.user.id;

    const { data: prof, error: profErr } = await adminClient
      .from("profiles")
      .select("role, institute_id, status")
      .eq("id", callerId)
      .maybeSingle();

    if (profErr || !prof) {
      return jsonResponse(403, { success: false, error: "Profile not found" });
    }

    const role = (prof.role ?? "").toString();
    const st = (prof.status ?? "").toString().toLowerCase();
    if (role !== "admin" || !["approved", "active"].includes(st)) {
      return jsonResponse(403, { success: false, error: "Only institute admins can add institute instructors" });
    }

    const adminInstituteId = prof.institute_id as string;
    if (!adminInstituteId) {
      return jsonResponse(403, { success: false, error: "Admin has no institute" });
    }

    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!body) {
      return jsonResponse(400, { success: false, error: "Invalid JSON body" });
    }

    const instituteKey = (body.instituteKey ?? body.institute_id ?? "").toString().trim();
    const pin = (body.pin ?? "").toString().trim();
    const fullNameRaw = (body.fullName ?? body.full_name ?? "").toString();
    const first = (body.firstName ?? body.first_name ?? "").toString().trim();
    const middle = (body.middleName ?? body.middle_name ?? "").toString().trim();
    const last = (body.lastName ?? body.last_name ?? "").toString().trim();

    if (!first || !middle || !last) {
      return jsonResponse(400, {
        success: false,
        error: "First name, middle name, and last name are all required.",
      });
    }

    const mobileDigits = ((body.mobile ?? body.phone ?? body.phone_number ?? "") as string).toString().replace(/\D/g, "");
    if (mobileDigits.length < 10 || mobileDigits.length > 15) {
      return jsonResponse(400, {
        success: false,
        error: "Enter a valid mobile number (10–15 digits).",
      });
    }

    const fullName = mergeFullName(fullNameRaw, first, middle, last);
    if (fullName.length < 2 || fullName.length > 200) {
      return jsonResponse(400, { success: false, error: "Invalid full name length" });
    }

    if (!/^\d{4}$/.test(pin)) {
      return jsonResponse(400, { success: false, error: "PIN must be 4 digits" });
    }

    const { data: inst, error: instErr } = await adminClient
      .from("institutes")
      .select("id, name, institute_code")
      .or(`id.eq.${instituteKey},institute_code.eq.${instituteKey}`)
      .limit(1)
      .maybeSingle();

    if (instErr || !inst?.id) {
      return jsonResponse(400, { success: false, error: "Institute not found for that ID" });
    }

    const instId = inst.id as string;
    const instituteCode = (inst.institute_code ?? "").toString().trim();

    const { data: adminInstRow } = await adminClient
      .from("institutes")
      .select("id")
      .or(`id.eq.${adminInstituteId},institute_code.eq.${adminInstituteId}`)
      .maybeSingle();
    const adminCanonicalId = (adminInstRow?.id ?? adminInstituteId).toString().trim();
    if (instId !== adminCanonicalId) {
      return jsonResponse(403, { success: false, error: "You can only add users to your own institute" });
    }

    const pinHash = await sha256Hex(pin);
    const instituteKeyForRpc = instituteCode.length > 0 ? instituteCode : instId;

    const { data: pinTaken, error: pinTakenErr } = await adminClient.rpc(
      "institute_instructor_pin_taken",
      { p_institute_key: instituteKeyForRpc, p_pin_hash: pinHash },
    );
    if (pinTakenErr) {
      return jsonResponse(500, { success: false, error: "Could not verify PIN uniqueness" });
    }
    if (pinTaken === true) {
      return jsonResponse(409, {
        success: false,
        error:
          "This PIN is already in use in your institute. Use a different PIN for the institute instructor.",
      });
    }

    const { data: countData, error: cntErr } = await adminClient.rpc(
      "count_institute_instructors",
      { p_institute_key: instituteKeyForRpc },
    );
    if (cntErr) {
      return jsonResponse(500, { success: false, error: "Could not verify instructor count" });
    }
    const maxInstructors = 4;
    const instructorCount = typeof countData === "number" ? countData : Number(countData ?? 0);
    if (instructorCount >= maxInstructors) {
      return jsonResponse(409, {
        success: false,
        error:
          `This institute already has ${instructorCount} instructor account(s) (max ${maxInstructors}). ` +
          `Open Institute instructor and refresh the list. Delete extras in Supabase if the list shows fewer than ${instructorCount}.`,
        instructorCount,
        maxInstructors,
      });
    }

    const orphansRemoved = await cleanupOrphanInstructorAuth(adminClient, instId, instituteCode);

    const instituteName = (inst.name ?? "").toString();
    const emailLocal = `att.${instId}.${crypto.randomUUID().replace(/-/g, "").slice(0, 16)}`;
    const email = `${emailLocal}${STAFF_EMAIL_DOMAIN}`;
    const password = `${pin}|${instId}|msceStaffV2`;

    const createStaffUser = async () =>
      adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          institute_id: instId,
          institute_name: instituteName,
          app_role: "attendance_user",
          full_name: fullName,
          phone_number: mobileDigits,
        },
      });

    let { data: created, error: createErr } = await createStaffUser();

    if (createErr || !created?.user?.id) {
      const msg = createErr?.message ?? "Could not create user";
      if (msg.toLowerCase().includes("already")) {
        const removed = await cleanupOrphanInstructorAuth(adminClient, instId, instituteCode);
        if (removed > 0) {
          ({ data: created, error: createErr } = await createStaffUser());
        }
      }
    }

    if (createErr || !created?.user?.id) {
      const msg = createErr?.message ?? "Could not create user";
      if (msg.toLowerCase().includes("already")) {
        const legacyList = legacyStaffEmails(instId, instituteCode);
        return jsonResponse(409, {
          success: false,
          error:
            "A leftover instructor login exists in Supabase Auth (often hidden in the app). " +
            "Dashboard → Authentication → Users → delete @staff.msce-attendance.app users for your institute " +
            `that are not in the instructor list. Check: ${legacyList.join(", ")}`,
          legacyEmails: legacyList,
          instituteId: instId,
          instructorCount,
          orphansRemoved,
        });
      }
      return jsonResponse(400, { success: false, error: msg });
    }

    const newId = created.user.id;
    const pinSetAt = new Date().toISOString();

    // Upsert (not patch-only update): signup trigger may have inserted a stub row without
    // full name / pin_hash, or skipped insert when a profile already existed.
    const { error: profileErr } = await adminClient.from("profiles").upsert(
      {
        id: newId,
        email,
        name: fullName,
        role: "attendance_user",
        institute_id: instId,
        institute_name: instituteName,
        phone_number: mobileDigits,
        pin_hash: pinHash,
        pin_set_at: pinSetAt,
        has_pin: true,
        status: "active",
      },
      { onConflict: "id" },
    );

    if (profileErr) {
      await adminClient.auth.admin.deleteUser(newId);
      return jsonResponse(500, {
        success: false,
        error: "Profile sync failed (name/PIN); user was not created",
      });
    }

    const { data: verifyRow, error: verifyErr } = await adminClient
      .from("profiles")
      .select("id, name, pin_hash")
      .eq("id", newId)
      .maybeSingle();

    if (verifyErr || !verifyRow?.pin_hash) {
      await adminClient.auth.admin.deleteUser(newId);
      return jsonResponse(500, {
        success: false,
        error: "Instructor PIN was not saved. Try again or contact support.",
      });
    }

    return jsonResponse(200, {
      success: true,
      userId: newId,
      email,
      fullName: (verifyRow.name ?? fullName).toString(),
      message: "Institute instructor created",
      instructorCount: instructorCount + 1,
      orphansRemoved,
    });
  } catch (e) {
    return jsonResponse(500, { success: false, error: (e as Error).message });
  }
});
