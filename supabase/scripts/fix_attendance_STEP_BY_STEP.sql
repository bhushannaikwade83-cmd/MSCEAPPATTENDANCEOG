-- =============================================================================
-- STEP-BY-STEP fix (use if full migration gives "Failed to fetch api.supabase.com")
-- =============================================================================
-- Run ONE gray box at a time in SQL Editor → Run (or Ctrl+Enter).
-- Wait for "Success" before the next step.
--
-- If even STEP 0 fails → network / paused project (see TROUBLESHOOTING below).
-- Each STEP is standalone (no temp tables) — safe to run one at a time.
-- =============================================================================

-- ─── TROUBLESHOOTING: Failed to fetch (api.supabase.com) ───
-- • Not a SQL syntax error — the browser lost contact with Supabase.
-- • Check https://status.supabase.com
-- • Dashboard → Project → confirm project is Active (not Paused)
-- • Try: Incognito window, disable VPN/ad-blocker, different Wi‑Fi or mobile hotspot
-- • Try: Supabase CLI from your Mac:
--     supabase link --project-ref YOUR_PROJECT_REF
--     supabase db execute -f supabase/scripts/fix_attendance_STEP_BY_STEP.sql
-- • Or connect with psql using Connection string from Settings → Database
-- =============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 0 — Connection test (run this first)
-- ═══════════════════════════════════════════════════════════════════════════
select 1 as ok, now() as server_time;


-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 1 — Preview: how many rows need fixing? (read-only, small)
-- ═══════════════════════════════════════════════════════════════════════════
select count(*) as attendance_in_out_to_fix
from public.attendance_in_out a
join public.students s on a.student_id = s.id
where btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(coalesce(a.sr_no, '')) = btrim(coalesce(s.user_id, ''))
  and btrim(a.sr_no) is distinct from btrim(s.sr_no);


-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 2 — Fix attendance_in_out.sr_no (usually fast; run alone)
-- ═══════════════════════════════════════════════════════════════════════════
update public.attendance_in_out a
set
  sr_no = btrim(s.sr_no),
  additional = coalesce(a.additional, '{}'::jsonb)
    || jsonb_build_object(
      'srNo', btrim(s.sr_no),
      'legacyRollKeyFix', 'user_id_to_sr_no',
      'legacyRollKeyBefore', a.sr_no
    )
from public.students s
where a.student_id = s.id
  and btrim(coalesce(s.sr_no, '')) <> ''
  and (
    btrim(coalesce(a.sr_no, '')) = btrim(coalesce(s.user_id, ''))
    or btrim(coalesce(a.additional ->> 'srNo', '')) = btrim(coalesce(s.user_id, ''))
  )
  and btrim(coalesce(a.sr_no, '')) is distinct from btrim(s.sr_no);


-- ═══════════════════════════════════════════════════════════════════════════
-- STEPS 3–6 — teacher_attendance (run 3 → 4 → 5 → 6 in order; each step alone OK)
-- ═══════════════════════════════════════════════════════════════════════════

-- STEP 3 — Preview: teacher_attendance rows still keyed by user_id
select count(*) as teacher_attendance_to_fix
from public.teacher_attendance ta
join public.students s on btrim(ta.student_id) = btrim(coalesce(s.user_id, ''))
where btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(ta.student_id) is distinct from btrim(s.sr_no)
  and (
    ta.institute_id = s.institute_id
    or ta.institute_id in (
      select i.institute_code from public.institutes i where i.id = s.institute_id
    )
  );


-- STEP 4 — Merge legacy row into existing sr_no doc (when both exist for same day)
update public.teacher_attendance t
set
  payload = coalesce(t.payload, '{}'::jsonb) || coalesce(ta.payload, '{}'::jsonb),
  status = coalesce(ta.status, t.status),
  verification_selfie = coalesce(ta.verification_selfie, t.verification_selfie),
  student_name = coalesce(ta.student_name, t.student_name),
  student_id = btrim(s.sr_no),
  updated_at = now()
from public.teacher_attendance ta
join public.students s on btrim(ta.student_id) = btrim(coalesce(s.user_id, ''))
where btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(ta.student_id) is distinct from btrim(s.sr_no)
  and (
    ta.institute_id = s.institute_id
    or ta.institute_id in (
      select i.institute_code from public.institutes i where i.id = s.institute_id
    )
  )
  and t.id = (btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date))
  and ta.id <> t.id;


-- STEP 5 — Delete legacy user_id-keyed row (after merge in step 4)
delete from public.teacher_attendance ta
using public.students s
where btrim(ta.student_id) = btrim(coalesce(s.user_id, ''))
  and btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(ta.student_id) is distinct from btrim(s.sr_no)
  and (
    ta.institute_id = s.institute_id
    or ta.institute_id in (
      select i.institute_code from public.institutes i where i.id = s.institute_id
    )
  )
  and exists (
    select 1
    from public.teacher_attendance t2
    where t2.id = (btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date))
      and t2.id <> ta.id
  );


-- STEP 6 — Rename legacy doc when no sr_no-keyed row exists yet for that day
update public.teacher_attendance ta
set
  id = (btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date)),
  student_id = btrim(s.sr_no),
  updated_at = now()
from public.students s
where btrim(ta.student_id) = btrim(coalesce(s.user_id, ''))
  and btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(ta.student_id) is distinct from btrim(s.sr_no)
  and (
    ta.institute_id = s.institute_id
    or ta.institute_id in (
      select i.institute_code from public.institutes i where i.id = s.institute_id
    )
  )
  and not exists (
    select 1
    from public.teacher_attendance t2
    where t2.id = (btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date))
      and t2.id <> ta.id
  );


-- STEP 6b — Doc id still has user_id segment but student_id is already sr_no
update public.teacher_attendance ta
set id = (btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date)),
    updated_at = now()
from public.students s
where btrim(ta.student_id) = btrim(s.sr_no)
  and btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(coalesce(s.user_id, '')) <> ''
  and ta.id = (btrim(ta.institute_id) || '_' || btrim(s.user_id) || '_' || btrim(ta.date))
  and not exists (
    select 1 from public.teacher_attendance t2
    where t2.id = (btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date))
      and t2.id <> ta.id
  );


-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 7 — Verify (both counts should be 0)
-- ═══════════════════════════════════════════════════════════════════════════
select count(*) as remaining_wrong_sr_no
from public.attendance_in_out a
join public.students s on a.student_id = s.id
where btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(coalesce(a.sr_no, '')) = btrim(coalesce(s.user_id, ''))
  and btrim(a.sr_no) is distinct from btrim(s.sr_no);

select count(*) as remaining_teacher_attendance_user_id_key
from public.teacher_attendance ta
join public.students s on btrim(ta.student_id) = btrim(coalesce(s.user_id, ''))
where btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(ta.student_id) is distinct from btrim(s.sr_no);
