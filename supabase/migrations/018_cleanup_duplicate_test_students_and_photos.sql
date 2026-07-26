-- Cleanup duplicate TEST data:
-- 1) duplicate students in same institute (same normalized full name + same registration photo signature)
-- 2) duplicate attendance photos for same student/day/type
--
-- Keep the oldest row (created_at, then id) and delete later duplicates.
-- Run in Supabase SQL Editor.

begin;

-- =========================
-- PREVIEW (safe to inspect)
-- =========================

-- Duplicate students preview
with students_norm as (
  select
    s.id,
    s.institute_id,
    lower(trim(regexp_replace(coalesce(s.name, ''), '\s+', ' ', 'g'))) as norm_name,
    nullif(
      coalesce(
        trim(s.registration_photo_path),
        trim(s.face_photo_url),
        ''
      ),
      ''
    ) as photo_sig,
    s.created_at
  from public.students s
),
student_dupes as (
  select
    id,
    institute_id,
    norm_name,
    photo_sig,
    created_at,
    row_number() over (
      partition by institute_id, norm_name, photo_sig
      order by created_at asc nulls last, id asc
    ) as rn,
    count(*) over (partition by institute_id, norm_name, photo_sig) as grp_cnt
  from students_norm
  where norm_name <> '' and photo_sig is not null
)
select institute_id, norm_name, photo_sig, grp_cnt
from student_dupes
where grp_cnt > 1
group by institute_id, norm_name, photo_sig, grp_cnt
order by grp_cnt desc, institute_id, norm_name;

-- Duplicate attendance photo preview
with attendance_norm as (
  select
    a.id,
    a.institute_code,
    a.student_id,
    a.attendance_date,
    a.type,
    nullif(
      coalesce(
        trim(a.photo_file_id),
        trim(a.photo_path),
        trim(a.photo_url),
        ''
      ),
      ''
    ) as photo_sig,
    a.created_at
  from public.attendance_in_out a
),
attendance_dupes as (
  select
    id,
    institute_code,
    student_id,
    attendance_date,
    type,
    photo_sig,
    created_at,
    row_number() over (
      partition by institute_code, student_id, attendance_date, type, photo_sig
      order by created_at asc nulls last, id asc
    ) as rn,
    count(*) over (
      partition by institute_code, student_id, attendance_date, type, photo_sig
    ) as grp_cnt
  from attendance_norm
  where photo_sig is not null
)
select institute_code, student_id, attendance_date, type, photo_sig, grp_cnt
from attendance_dupes
where grp_cnt > 1
group by institute_code, student_id, attendance_date, type, photo_sig, grp_cnt
order by grp_cnt desc, institute_code, student_id, attendance_date;

-- =========================
-- DELETE DUPLICATES
-- =========================

-- Delete duplicate students (keep rn = 1)
with students_norm as (
  select
    s.id,
    s.institute_id,
    lower(trim(regexp_replace(coalesce(s.name, ''), '\s+', ' ', 'g'))) as norm_name,
    nullif(
      coalesce(
        trim(s.registration_photo_path),
        trim(s.face_photo_url),
        ''
      ),
      ''
    ) as photo_sig,
    s.created_at
  from public.students s
),
to_delete as (
  select id
  from (
    select
      id,
      row_number() over (
        partition by institute_id, norm_name, photo_sig
        order by created_at asc nulls last, id asc
      ) as rn
    from students_norm
    where norm_name <> '' and photo_sig is not null
  ) ranked
  where rn > 1
)
delete from public.students s
using to_delete d
where s.id = d.id;

-- Delete duplicate attendance photo rows (keep rn = 1)
with attendance_norm as (
  select
    a.id,
    a.institute_code,
    a.student_id,
    a.attendance_date,
    a.type,
    nullif(
      coalesce(
        trim(a.photo_file_id),
        trim(a.photo_path),
        trim(a.photo_url),
        ''
      ),
      ''
    ) as photo_sig,
    a.created_at
  from public.attendance_in_out a
),
to_delete as (
  select id
  from (
    select
      id,
      row_number() over (
        partition by institute_code, student_id, attendance_date, type, photo_sig
        order by created_at asc nulls last, id asc
      ) as rn
    from attendance_norm
    where photo_sig is not null
  ) ranked
  where rn > 1
)
delete from public.attendance_in_out a
using to_delete d
where a.id = d.id;

-- Recompute institute student_count after student dedupe.
update public.institutes i
set student_count = coalesce(s.cnt, 0)
from (
  select institute_id, count(*)::int as cnt
  from public.students
  group by institute_id
) s
where i.id = s.institute_id;

update public.institutes i
set student_count = 0
where not exists (
  select 1
  from public.students s
  where s.institute_id = i.id
);

commit;
