-- All institutes: fix instructor count + allow up to 4 real instructors (unique PIN each).
-- Removes broken rows (no pin_hash) that block adding instructor #2 everywhere.

-- Canonical count (join institutes — avoids bad .or() matches on profiles).
create or replace function public.count_institute_instructors(p_institute_key text)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
  from public.profiles p
  inner join public.institutes i
    on i.id = btrim(p_institute_key)
    or i.institute_code = btrim(p_institute_key)
  where p.role = 'attendance_user'
    and (
      p.institute_id = i.id::text
      or p.institute_id = i.institute_code
    )
    and p.pin_hash is not null
    and length(btrim(p.pin_hash)) > 0;
$$;

create or replace function public.institute_instructor_pin_taken(
  p_institute_key text,
  p_pin_hash text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    inner join public.institutes i
      on i.id = btrim(p_institute_key)
      or i.institute_code = btrim(p_institute_key)
    where p.role = 'attendance_user'
      and p.pin_hash = btrim(p_pin_hash)
      and (
        p.institute_id = i.id::text
        or p.institute_id = i.institute_code
      )
  );
$$;

revoke all on function public.count_institute_instructors(text) from public;
revoke all on function public.institute_instructor_pin_taken(text, text) from public;
grant execute on function public.count_institute_instructors(text) to authenticated, service_role;
grant execute on function public.institute_instructor_pin_taken(text, text) to authenticated, service_role;

-- Broken signups: attendance_user row but PIN never saved — cannot log in; still counted toward 4.
delete from public.profiles
where role = 'attendance_user'
  and (pin_hash is null or length(btrim(pin_hash)) = 0);

-- Align institute_id to institutes.id (safe re-run).
update public.profiles p
set institute_id = i.id
from public.institutes i
where p.role = 'attendance_user'
  and p.institute_id is not null
  and p.institute_id is distinct from i.id
  and (p.institute_id = i.institute_code or p.institute_id = i.id::text);
