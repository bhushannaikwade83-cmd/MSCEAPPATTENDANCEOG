-- Portal district viewers: 8 Maharashtra districts, view-only access by institute_code prefix (first 2 digits).

-- ---------------------------------------------------------------------------
-- District reference (prefixes from MSCE institute code scheme)
-- ---------------------------------------------------------------------------
create table if not exists public.portal_districts (
  district_key text primary key,
  district_name text not null,
  institute_prefixes text[] not null
);

insert into public.portal_districts (district_key, district_name, institute_prefixes)
values
  ('mumbai', 'Mumbai', array['11', '14', '15']),
  ('pune', 'Pune', array['21', '22', '23']),
  ('nashik', 'Nashik', array['31', '32', '33', '34']),
  ('kolhapur', 'Kolhapur', array['41', '42', '43', '44', '45']),
  ('chhatrapati_sambhajinagar', 'Chhatrapati Sambhajinagar', array['51', '52', '53', '54', '55']),
  ('amrawati', 'Amrawati', array['61', '62', '63', '64', '65']),
  ('nagpur', 'Nagpur', array['71', '72', '73', '74', '75', '76']),
  ('latur', 'Latur', array['81', '82', '83'])
on conflict (district_key) do update
set
  district_name = excluded.district_name,
  institute_prefixes = excluded.institute_prefixes;

alter table public.portal_districts enable row level security;

drop policy if exists "portal_districts_select_authenticated" on public.portal_districts;
create policy "portal_districts_select_authenticated"
  on public.portal_districts for select
  to authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- profiles.portal_district_key → portal_districts
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists portal_district_key text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_portal_district_key_fkey'
  ) then
    alter table public.profiles
      add constraint profiles_portal_district_key_fkey
      foreign key (portal_district_key)
      references public.portal_districts (district_key)
      on delete set null;
  end if;
exception
  when others then null;
end $$;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.is_portal_district_viewer()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role, '')) = 'portal_district_viewer'
      and lower(coalesce(p.status, 'approved')) in ('approved', 'active', 'pending')
      and p.portal_district_key is not null
      and btrim(p.portal_district_key) <> ''
  );
$$;

grant execute on function public.is_portal_district_viewer() to authenticated;

create or replace function public.portal_user_district_key()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select nullif(btrim(p.portal_district_key), '')
  from public.profiles p
  where p.id = auth.uid();
$$;

grant execute on function public.portal_user_district_key() to authenticated;

create or replace function public.portal_user_institute_prefixes()
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(d.institute_prefixes, array[]::text[])
  from public.profiles p
  join public.portal_districts d on d.district_key = p.portal_district_key
  where p.id = auth.uid();
$$;

grant execute on function public.portal_user_institute_prefixes() to authenticated;

create or replace function public.normalized_institute_code(p_code text)
returns text
language sql
immutable
as $$
  select lpad(btrim(coalesce(p_code, '')), 5, '0');
$$;

create or replace function public.institute_code_in_portal_scope(p_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_super_admin()
    or public.is_coder()
    or (
      public.is_portal_district_viewer()
      and exists (
        select 1
        from unnest(public.portal_user_institute_prefixes()) pref
        where length(btrim(pref)) >= 2
          and left(public.normalized_institute_code(p_code), 2) = btrim(pref)
      )
    );
$$;

grant execute on function public.institute_code_in_portal_scope(text) to authenticated;

create or replace function public.institute_id_in_portal_scope(p_institute_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.institutes i
    where i.id = btrim(coalesce(p_institute_id, ''))
      and public.institute_code_in_portal_scope(i.institute_code)
  );
$$;

grant execute on function public.institute_id_in_portal_scope(text) to authenticated;

-- Backward-compatible alias (drop uuid version if a partial run created it)
drop function if exists public.institute_uuid_in_portal_scope(uuid);

-- ---------------------------------------------------------------------------
-- Narrow institute directory for district viewers (authenticated users)
-- ---------------------------------------------------------------------------
drop policy if exists "institutes_select_authenticated" on public.institutes;

create policy "institutes_select_authenticated"
  on public.institutes for select
  to authenticated
  using (
    public.is_super_admin()
    or public.is_coder()
    or (
      public.is_portal_district_viewer()
      and public.institute_code_in_portal_scope(institute_code)
    )
    or (
      not public.is_portal_district_viewer()
      and (
        public.is_institute_admin()
        or coalesce(is_active, true)
      )
    )
  );

drop policy if exists "institutes_insert_authenticated" on public.institutes;

create policy "institutes_insert_authenticated"
  on public.institutes for insert
  to authenticated
  with check (
    not public.is_portal_district_viewer()
    and (
      public.is_coder()
      or public.profile_has_no_institute()
    )
  );

-- ---------------------------------------------------------------------------
-- Read-only SELECT for district viewers (reports / students / institutes)
-- ---------------------------------------------------------------------------
drop policy if exists "students_portal_district_select" on public.students;
create policy "students_portal_district_select"
  on public.students for select
  to authenticated
  using (
    public.is_portal_district_viewer()
    and public.institute_id_in_portal_scope(institute_id)
  );

drop policy if exists "batches_portal_district_select" on public.batches;
create policy "batches_portal_district_select"
  on public.batches for select
  to authenticated
  using (
    public.is_portal_district_viewer()
    and public.institute_id_in_portal_scope(institute_id)
  );

drop policy if exists "institute_subjects_portal_district_select" on public.institute_subjects;
create policy "institute_subjects_portal_district_select"
  on public.institute_subjects for select
  to authenticated
  using (
    public.is_portal_district_viewer()
    and public.institute_id_in_portal_scope(institute_id)
  );

drop policy if exists "attendance_in_out_portal_district_select" on public.attendance_in_out;
create policy "attendance_in_out_portal_district_select"
  on public.attendance_in_out for select
  to authenticated
  using (
    public.is_portal_district_viewer()
    and public.institute_code_in_portal_scope(institute_code)
  );

drop policy if exists "teacher_attendance_portal_district_select" on public.teacher_attendance;
create policy "teacher_attendance_portal_district_select"
  on public.teacher_attendance for select
  to authenticated
  using (
    public.is_portal_district_viewer()
    and public.institute_id_in_portal_scope(institute_id)
  );

-- ---------------------------------------------------------------------------
-- portal_session_info — expose district viewer mode to the website
-- ---------------------------------------------------------------------------
create or replace function public.portal_session_info()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_role text;
  v_status text;
  v_institute_id text;
  v_district_key text;
  v_district_name text;
  v_prefixes text[];
  v_is_district boolean;
  v_is_super boolean;
begin
  if v_uid is null then
    return jsonb_build_object(
      'authenticated', false,
      'can_list_onboarding', false,
      'portal_mode', 'anonymous',
      'read_only', true,
      'message', 'Not signed in'
    );
  end if;

  select lower(u.email::text) into v_email from auth.users u where u.id = v_uid;

  select p.role, p.status, p.institute_id, p.portal_district_key
  into v_role, v_status, v_institute_id, v_district_key
  from public.profiles p
  where p.id = v_uid;

  v_is_super := public.is_super_admin();
  v_is_district := public.is_portal_district_viewer();

  if v_is_district then
    select d.district_name, d.institute_prefixes
    into v_district_name, v_prefixes
    from public.portal_districts d
    where d.district_key = v_district_key;
  end if;

  return jsonb_build_object(
    'authenticated', true,
    'user_id', v_uid,
    'email', v_email,
    'profile_role', v_role,
    'profile_status', v_status,
    'institute_id', v_institute_id,
    'is_super_admin_fn', v_is_super,
    'is_coder_fn', public.is_coder(),
    'is_portal_district_viewer', v_is_district,
    'portal_district_key', v_district_key,
    'district_name', v_district_name,
    'institute_prefixes', coalesce(v_prefixes, array[]::text[]),
    'portal_mode',
      case
        when v_is_super then 'super_admin'
        when v_is_district then 'district_viewer'
        else 'other'
      end,
    'read_only', v_is_district and not v_is_super,
    'can_list_onboarding', public.can_access_portal_onboarding_list(),
    'allowed_tabs',
      case
        when v_is_super then jsonb_build_array(
          'overview', 'admins', 'instructors', 'institutes', 'add', 'students', 'integrity', 'reports'
        )
        when v_is_district then jsonb_build_array('institutes', 'students', 'reports')
        else jsonb_build_array()
      end,
    'message',
      case
        when v_is_super then 'OK — full portal access'
        when v_is_district then format(
          'OK — %s district view-only (institute codes: %s)',
          coalesce(v_district_name, v_district_key),
          array_to_string(coalesce(v_prefixes, array[]::text[]), ', ')
        )
        when public.can_access_portal_onboarding_list() then 'OK — portal onboarding list allowed'
        when v_role is null then 'No profiles row — contact MSCE tech support'
        when lower(coalesce(v_role, '')) = 'portal_district_viewer' and v_district_key is null then
          'District login missing portal_district_key on profiles — run migration 076 setup script'
        when lower(coalesce(v_role, '')) <> 'super_admin' then
          format('profiles.role is "%s" — not authorised for this portal', v_role)
        when lower(coalesce(v_status, '')) not in ('approved', 'active', 'pending') then
          format('profiles.status is "%s" — set to approved', v_status)
        else 'Access denied — contact MSCE tech support'
      end
  );
end;
$$;

grant execute on function public.portal_session_info() to authenticated;
