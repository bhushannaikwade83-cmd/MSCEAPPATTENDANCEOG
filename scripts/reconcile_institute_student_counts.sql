-- Refresh public.institutes.student_count from actual student rows (run after bulk CSV import).
--
-- Supabase: SQL Editor → paste → Run once (or after each large import).

update public.institutes i
set student_count = coalesce(c.cnt, 0),
    updated_at      = now()
from (
  select institute_id::text as iid,
         count(*)::int       as cnt
  from public.students
  group by institute_id
) c
where i.id = c.iid;

-- Zero out institutes that currently have no student rows.
update public.institutes i
set student_count = 0,
    updated_at    = now()
where not exists (
  select 1 from public.students s where s.institute_id = i.id
);
