-- Dense SR / roll numbers per institute: 1, 2, 3, … (by enrollment order).
-- Aligns students.sr_no and students.user_id, then refreshes attendance_in_out.sr_no.
--
-- Order: oldest created_at first (then id) within each institute_id.
-- Run once after backup if you rely on historical user_id values externally.

with ordered as (
  select
    id,
    institute_id,
    row_number() over (
      partition by institute_id
      order by coalesce(created_at, timestamp 'epoch'), id
    ) as seq
  from public.students
)
update public.students s
set
  sr_no = o.seq::text,
  user_id = o.seq::text,
  updated_at = now()
from ordered o
where s.id = o.id;

update public.attendance_in_out a
set sr_no = s.sr_no
from public.students s
where a.student_id = s.id;
