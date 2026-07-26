-- Institute ID + PIN login: resolve the Supabase Auth email from institute + PIN hash.
-- Multiple attendance_user rows per institute use unique emails; this keeps login unauthenticated-safe.
-- Returns one email only when exactly one profile matches (avoids wrong login if PIN ever duplicated).

create or replace function public.resolve_attendance_staff_email(
  p_institute_id text,
  p_pin_hash text
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select (array_agg(p.email order by p.created_at))[1]::text
  from public.profiles p
  where p.institute_id = nullif(btrim(p_institute_id), '')
    and p.role = 'attendance_user'
    and p.pin_hash = nullif(btrim(p_pin_hash), '')
    and p.email is not null
    and length(btrim(p.email)) > 0
  group by ()
  having count(*) = 1;
$$;

revoke all on function public.resolve_attendance_staff_email(text, text) from public;
grant execute on function public.resolve_attendance_staff_email(text, text) to anon, authenticated;
