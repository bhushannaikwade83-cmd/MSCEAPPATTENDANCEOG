-- ONE-TIME fix for every institute: cannot add instructor #2 after the first.
-- Run entire script in Supabase SQL Editor (safe to re-run).
-- Creates helper functions first, then cleans data.

-- ── 0) Functions (required by app / edge function after this fix) ─────────────
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

-- ── A) Show institutes with broken or excess instructor rows ─────────────────
select
  i.institute_code,
  i.name,
  count(*) filter (where p.pin_hash is not null and length(btrim(p.pin_hash)) > 0) as valid_instructors,
  count(*) filter (where p.pin_hash is null or length(btrim(coalesce(p.pin_hash, ''))) = 0) as broken_no_pin,
  count(*) as total_rows
from public.institutes i
left join public.profiles p
  on p.role = 'attendance_user'
  and (p.institute_id = i.id::text or p.institute_id = i.institute_code)
group by i.id, i.institute_code, i.name
having count(*) > 0
order by total_rows desc, i.institute_code;

-- ── B) Remove broken rows (no PIN saved — blocks slot, cannot login) ─────────
delete from public.profiles
where role = 'attendance_user'
  and (pin_hash is null or length(btrim(pin_hash)) = 0);

-- ── C) Normalize institute_id to UUID on all instructor profiles ─────────────
update public.profiles p
set institute_id = i.id
from public.institutes i
where p.role = 'attendance_user'
  and p.institute_id is not null
  and p.institute_id is distinct from i.id
  and (p.institute_id = i.institute_code or p.institute_id = i.id::text);

-- ── D) Per-institute count after fix (should be 0–4) ─────────────────────────
select
  i.institute_code,
  i.name,
  public.count_institute_instructors(i.institute_code) as instructor_count
from public.institutes i
where public.count_institute_instructors(i.institute_code) > 0
order by instructor_count desc, i.institute_code;

-- ── E) Manual: Dashboard → Authentication → Users ───────────────────────────
-- Delete @staff.msce-attendance.app users with NO matching row in:
--   select id, email, name from public.profiles where role = 'attendance_user';
