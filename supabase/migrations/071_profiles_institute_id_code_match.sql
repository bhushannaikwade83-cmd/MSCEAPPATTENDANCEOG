-- Admin could not see instructors (list empty) while server still counted them toward the 4 limit.
-- Cause: profiles.institute_id stored as institute_code (e.g. 99099) but RLS compared only to admin UUID.

create or replace function public.current_profile_institute_code()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(nullif(trim(i.institute_code), ''), i.id::text)
  from public.profiles p
  join public.institutes i
    on i.id = p.institute_id
    or i.institute_code = p.institute_id
  where p.id = auth.uid()
  limit 1;
$$;

create or replace function public.profile_institute_matches(p_institute_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    btrim(coalesce(p_institute_id, '')) <> ''
    and (
      btrim(p_institute_id) = nullif(btrim(coalesce(public.current_profile_institute_id(), '')), '')
      or btrim(p_institute_id) = nullif(btrim(coalesce(public.current_profile_institute_code(), '')), '')
    );
$$;

revoke all on function public.profile_institute_matches(text) from public;
grant execute on function public.profile_institute_matches(text) to authenticated;

drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select"
  on public.profiles for select
  to authenticated
  using (
    id = auth.uid()
    or public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id is not null
      and public.profile_institute_matches(institute_id)
    )
  );

drop policy if exists "profiles_update_own_or_admin_peer" on public.profiles;
create policy "profiles_update_own_or_admin_peer"
  on public.profiles for update
  to authenticated
  using (
    id = auth.uid()
    or public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id is not null
      and public.profile_institute_matches(institute_id)
    )
  )
  with check (
    id = auth.uid()
    or public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id is not null
      and public.profile_institute_matches(institute_id)
    )
  );

-- Normalize instructor rows to canonical institutes.id (safe to re-run).
update public.profiles p
set institute_id = i.id
from public.institutes i
where p.role = 'attendance_user'
  and p.institute_id is not null
  and p.institute_id is distinct from i.id
  and (p.institute_id = i.institute_code or p.institute_id = i.id::text);
