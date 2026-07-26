-- Fix legacy attendance rows that stored students.user_id (or wrong roll key)
-- in attendance_in_out.sr_no and teacher_attendance.student_id / id.
--
-- Safe to re-run: only updates rows that still match the legacy pattern.
-- Run preview block in supabase/scripts/fix_attendance_user_id_to_sr_no.sql first.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) attendance_in_out: set sr_no (and additional.srNo) from students.sr_no
-- ─────────────────────────────────────────────────────────────────────────────
update public.attendance_in_out as a
set
  sr_no = btrim(s.sr_no),
  additional = coalesce(a.additional, '{}'::jsonb)
    || jsonb_build_object(
      'srNo', btrim(s.sr_no),
      'legacyRollKeyFix', 'user_id_to_sr_no',
      'legacyRollKeyBefore', a.sr_no
    )
from public.students as s
where a.student_id = s.id
  and btrim(coalesce(s.sr_no, '')) <> ''
  and (
    btrim(coalesce(a.sr_no, '')) = btrim(coalesce(s.user_id, ''))
    or btrim(coalesce(a.additional ->> 'srNo', '')) = btrim(coalesce(s.user_id, ''))
  )
  and btrim(coalesce(a.sr_no, '')) is distinct from btrim(s.sr_no);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) teacher_attendance: rows keyed by user_id instead of sr_no
-- ─────────────────────────────────────────────────────────────────────────────
create temp table _ta_roll_fix on commit drop as
select
  ta.id as old_id,
  ta.institute_id,
  ta.date,
  ta.student_id as old_roll_key,
  btrim(s.sr_no) as canonical_sr,
  ta.student_name,
  ta.status,
  ta.verification_selfie,
  ta.payload,
  (btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date)) as new_id,
  exists (
    select 1
    from public.teacher_attendance t2
    where t2.id = (btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date))
      and t2.id <> ta.id
  ) as target_exists
from public.teacher_attendance ta
inner join public.students s
  on btrim(ta.student_id) = btrim(coalesce(s.user_id, ''))
where btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(ta.student_id) is distinct from btrim(s.sr_no)
  and (
    ta.institute_id = s.institute_id
    or ta.institute_id in (
      select i.institute_code
      from public.institutes i
      where i.id = s.institute_id
        and btrim(coalesce(i.institute_code, '')) <> ''
    )
    or ta.institute_id in (
      select i.id
      from public.institutes i
      where i.institute_code = s.institute_id
    )
  );

-- Merge into existing canonical doc when both user_id-keyed and sr_no-keyed rows exist
update public.teacher_attendance t
set
  payload = coalesce(t.payload, '{}'::jsonb) || coalesce(f.payload, '{}'::jsonb),
  status = coalesce(f.status, t.status),
  verification_selfie = coalesce(f.verification_selfie, t.verification_selfie),
  student_name = coalesce(f.student_name, t.student_name),
  student_id = f.canonical_sr,
  updated_at = now()
from _ta_roll_fix f
where t.id = f.new_id
  and f.target_exists;

delete from public.teacher_attendance ta
using _ta_roll_fix f
where ta.id = f.old_id
  and f.target_exists;

-- Rename remaining legacy docs to canonical id + sr_no roll key
update public.teacher_attendance ta
set
  id = f.new_id,
  student_id = f.canonical_sr,
  updated_at = now()
from _ta_roll_fix f
where ta.id = f.old_id
  and not f.target_exists;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) teacher_attendance: id segment still uses user_id (student_id already sr_no)
-- ─────────────────────────────────────────────────────────────────────────────
create temp table _ta_id_fix on commit drop as
select
  ta.id as old_id,
  (btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date)) as new_id,
  btrim(s.sr_no) as canonical_sr,
  ta.payload,
  ta.status,
  ta.verification_selfie,
  ta.student_name,
  exists (
    select 1
    from public.teacher_attendance t2
    where t2.id = (btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date))
      and t2.id <> ta.id
  ) as target_exists
from public.teacher_attendance ta
inner join public.students s
  on btrim(ta.student_id) = btrim(s.sr_no)
where btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(coalesce(s.user_id, '')) <> ''
  and ta.id = (btrim(ta.institute_id) || '_' || btrim(s.user_id) || '_' || btrim(ta.date))
  and ta.id is distinct from (btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date));

update public.teacher_attendance t
set
  payload = coalesce(t.payload, '{}'::jsonb) || coalesce(f.payload, '{}'::jsonb),
  status = coalesce(f.status, t.status),
  verification_selfie = coalesce(f.verification_selfie, t.verification_selfie),
  student_name = coalesce(f.student_name, t.student_name),
  student_id = f.canonical_sr,
  updated_at = now()
from _ta_id_fix f
where t.id = f.new_id
  and f.target_exists;

delete from public.teacher_attendance ta
using _ta_id_fix f
where ta.id = f.old_id
  and f.target_exists;

update public.teacher_attendance ta
set
  id = f.new_id,
  updated_at = now()
from _ta_id_fix f
where ta.id = f.old_id
  and not f.target_exists;
