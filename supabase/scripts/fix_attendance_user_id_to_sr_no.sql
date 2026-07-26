-- =============================================================================
-- Fix attendance roll keys: user_id → official students.sr_no
-- =============================================================================
-- Run in Supabase Dashboard → SQL Editor.
--
-- If you see "Failed to fetch (api.supabase.com)" → use instead:
--   supabase/scripts/fix_attendance_STEP_BY_STEP.sql
-- (run one STEP at a time; start with STEP 0)
--
-- 1) Run SECTION A (preview) and review counts/sample rows.
-- 2) Run SECTION B (apply) — same logic as migration 069.
--
-- What it fixes:
--   • attendance_in_out.sr_no (and additional.srNo) saved as students.user_id
--   • teacher_attendance.student_id saved as user_id
--   • teacher_attendance.id = {institute}_{user_id}_{date} → {institute}_{sr_no}_{date}
--
-- Does NOT change attendance_in_out.student_id (that should stay students.id UUID).
-- Skips students with empty sr_no (fix roster first).
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION A — PREVIEW (read-only)
-- ─────────────────────────────────────────────────────────────────────────────

-- A1) attendance_in_out rows that would be updated
select count(*) as attendance_in_out_rows_to_fix
from public.attendance_in_out a
inner join public.students s on a.student_id = s.id
where btrim(coalesce(s.sr_no, '')) <> ''
  and (
    btrim(coalesce(a.sr_no, '')) = btrim(coalesce(s.user_id, ''))
    or btrim(coalesce(a.additional ->> 'srNo', '')) = btrim(coalesce(s.user_id, ''))
  )
  and btrim(coalesce(a.sr_no, '')) is distinct from btrim(s.sr_no);

select
  a.id,
  a.institute_code,
  a.attendance_date,
  a.type,
  a.sr_no as current_sr_no,
  s.sr_no as correct_sr_no,
  s.user_id,
  s.name
from public.attendance_in_out a
inner join public.students s on a.student_id = s.id
where btrim(coalesce(s.sr_no, '')) <> ''
  and (
    btrim(coalesce(a.sr_no, '')) = btrim(coalesce(s.user_id, ''))
    or btrim(coalesce(a.additional ->> 'srNo', '')) = btrim(coalesce(s.user_id, ''))
  )
  and btrim(coalesce(a.sr_no, '')) is distinct from btrim(s.sr_no)
order by a.attendance_date desc
limit 50;

-- A2) teacher_attendance rows keyed by user_id (student_id column)
select count(*) as teacher_attendance_student_id_rows_to_fix
from public.teacher_attendance ta
inner join public.students s on btrim(ta.student_id) = btrim(coalesce(s.user_id, ''))
where btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(ta.student_id) is distinct from btrim(s.sr_no)
  and (
    ta.institute_id = s.institute_id
    or ta.institute_id in (
      select i.institute_code from public.institutes i where i.id = s.institute_id
    )
  );

select
  ta.id as old_doc_id,
  (btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date)) as new_doc_id,
  ta.student_id as current_roll_key,
  s.sr_no as correct_sr_no,
  s.user_id,
  s.name,
  ta.date
from public.teacher_attendance ta
inner join public.students s on btrim(ta.student_id) = btrim(coalesce(s.user_id, ''))
where btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(ta.student_id) is distinct from btrim(s.sr_no)
  and (
    ta.institute_id = s.institute_id
    or ta.institute_id in (
      select i.institute_code from public.institutes i where i.id = s.institute_id
    )
  )
order by ta.date desc
limit 50;

-- A3) teacher_attendance doc id still contains user_id segment
select count(*) as teacher_attendance_id_segment_rows_to_fix
from public.teacher_attendance ta
inner join public.students s on btrim(ta.student_id) = btrim(s.sr_no)
where btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(coalesce(s.user_id, '')) <> ''
  and ta.id = (btrim(ta.institute_id) || '_' || btrim(s.user_id) || '_' || btrim(ta.date))
  and ta.id is distinct from (btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date));

-- A4) Ambiguous: user_id matches multiple students (manual review — script skips these)
select
  s.user_id,
  count(*) as student_count,
  array_agg(s.id order by s.id) as student_ids,
  array_agg(s.sr_no order by s.sr_no) as sr_nos
from public.students s
where btrim(coalesce(s.user_id, '')) <> ''
group by s.institute_id, s.user_id
having count(*) > 1
limit 20;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION B — APPLY (run after preview looks correct)
-- ─────────────────────────────────────────────────────────────────────────────
-- In SQL Editor: open and run the full file (recommended):
--   supabase/migrations/069_fix_attendance_roll_keys_user_id_to_sr_no.sql
--
-- Optional dry-run:
--   BEGIN;
--   -- paste migration 069 contents here
--   -- re-run SECTION C verify queries; expect zeros
--   ROLLBACK;  -- or COMMIT; when satisfied

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION C — VERIFY (after apply)
-- ─────────────────────────────────────────────────────────────────────────────

select count(*) as remaining_attendance_in_out_wrong_sr
from public.attendance_in_out a
inner join public.students s on a.student_id = s.id
where btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(coalesce(a.sr_no, '')) = btrim(coalesce(s.user_id, ''))
  and btrim(coalesce(a.sr_no, '')) is distinct from btrim(s.sr_no);

select count(*) as remaining_teacher_attendance_user_id_key
from public.teacher_attendance ta
inner join public.students s on btrim(ta.student_id) = btrim(coalesce(s.user_id, ''))
where btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(ta.student_id) is distinct from btrim(s.sr_no);
