-- =============================================================================
-- SIMPLE FIX: user_id → sr_no (copy ONE block → Run → next block)
-- =============================================================================
-- ORDER IS IMPORTANT for teacher_attendance (D1 → D3 → D2 → D4).
-- =============================================================================


-- ── QUERY A (preview) — attendance_in_out ───────────────────────────────────
select count(*) as fix_count
from public.attendance_in_out a
join public.students s on a.student_id = s.id
where btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(coalesce(a.sr_no, '')) = btrim(coalesce(s.user_id, ''));


-- ── QUERY B (FIX attendance_in_out) ─────────────────────────────────────────
update public.attendance_in_out a
set sr_no = btrim(s.sr_no)
from public.students s
where a.student_id = s.id
  and btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(coalesce(a.sr_no, '')) = btrim(coalesce(s.user_id, ''));


-- ── QUERY C (preview) — teacher_attendance using user_id ────────────────────
select count(*) as fix_count
from public.teacher_attendance ta
join public.students s on btrim(ta.student_id) = btrim(coalesce(s.user_id, ''))
where btrim(coalesce(s.sr_no, '')) <> '';


-- ── QUERY D1 — set student_id to sr_no (run first) ──────────────────────────
update public.teacher_attendance ta
set
  student_id = btrim(s.sr_no),
  updated_at = now()
from public.students s
where btrim(ta.student_id) = btrim(coalesce(s.user_id, ''))
  and btrim(coalesce(s.sr_no, '')) <> '';


-- ── QUERY D2a — MERGE (legacy id has user_id, correct id has sr_no) ───────────
-- Run BEFORE D3. Fixes: duplicate key 23505 on id=(99099_002_2026-05-09)
update public.teacher_attendance t
set
  payload = coalesce(t.payload, '{}'::jsonb) || coalesce(ta.payload, '{}'::jsonb),
  status = coalesce(ta.status, t.status),
  verification_selfie = coalesce(ta.verification_selfie, t.verification_selfie),
  student_name = coalesce(ta.student_name, t.student_name),
  student_id = btrim(s.sr_no),
  updated_at = now()
from public.teacher_attendance ta
join public.students s
  on ta.id = btrim(ta.institute_id) || '_' || btrim(s.user_id) || '_' || btrim(ta.date)
where btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(coalesce(s.user_id, '')) <> ''
  and t.id = btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date)
  and ta.id <> t.id;


-- ── QUERY D2b — DELETE legacy row when sr_no doc already exists ─────────────
delete from public.teacher_attendance ta
using public.students s
where ta.id = btrim(ta.institute_id) || '_' || btrim(s.user_id) || '_' || btrim(ta.date)
  and btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(coalesce(s.user_id, '')) <> ''
  and exists (
    select 1
    from public.teacher_attendance good
    where good.id = btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date)
  );


-- ── QUERY D3 — rename id only when NO sr_no doc yet (safe after D2) ─────────
update public.teacher_attendance ta
set
  id = btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date),
  student_id = btrim(s.sr_no),
  updated_at = now()
from public.students s
where ta.id = btrim(ta.institute_id) || '_' || btrim(s.user_id) || '_' || btrim(ta.date)
  and btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(coalesce(s.user_id, '')) <> ''
  and not exists (
    select 1
    from public.teacher_attendance other
    where other.id = btrim(ta.institute_id) || '_' || btrim(s.sr_no) || '_' || btrim(ta.date)
  );


-- ── QUERY E (verify — both should be 0) ─────────────────────────────────────
select count(*) as bad_attendance_in_out
from public.attendance_in_out a
join public.students s on a.student_id = s.id
where btrim(coalesce(s.sr_no, '')) <> ''
  and btrim(coalesce(a.sr_no, '')) = btrim(coalesce(s.user_id, ''));

select count(*) as bad_teacher_attendance
from public.teacher_attendance ta
join public.students s on btrim(ta.student_id) = btrim(coalesce(s.user_id, ''))
where btrim(coalesce(s.sr_no, '')) <> '';
