-- Institute "attendance only" staff: Supabase Auth users with role attendance_user.
-- Created via Edge Function create-institute-attendance-user (service role).
-- Login: synthetic email + derived password (see app AttendanceStaffAuth).

create or replace function public.handle_institute_admin_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  iid text;
  iname text;
  uname text;
  phone text;
  app_role text;
  staff_username text;
  full_name text;
begin
  iid := nullif(btrim(coalesce(new.raw_user_meta_data->>'institute_id', '')), '');
  app_role := nullif(lower(btrim(coalesce(new.raw_user_meta_data->>'app_role', ''))), '');

  if app_role = 'attendance_user' and iid is not null then
    if exists (select 1 from public.profiles p where p.id = new.id) then
      return new;
    end if;

    staff_username := nullif(btrim(coalesce(new.raw_user_meta_data->>'attendance_username', '')), '');
    full_name := coalesce(nullif(btrim(new.raw_user_meta_data->>'full_name'), ''), 'Staff');
    iname := coalesce(new.raw_user_meta_data->>'institute_name', '');

    if staff_username is null or staff_username = '' then
      raise exception 'attendance_username required in user metadata';
    end if;

    insert into public.profiles (
      id,
      email,
      name,
      role,
      institute_id,
      institute_name,
      user_id,
      phone_number,
      status,
      has_pin,
      created_at,
      last_login
    )
    values (
      new.id,
      new.email,
      full_name,
      'attendance_user',
      iid,
      iname,
      staff_username,
      null,
      'active',
      true,
      now(),
      null
    );

    return new;
  end if;

  if iid is null then
    return new;
  end if;

  iname := coalesce(new.raw_user_meta_data->>'institute_name', '');
  uname := coalesce(new.raw_user_meta_data->>'name', '');
  phone := coalesce(new.raw_user_meta_data->>'phone_number', '');

  if exists (select 1 from public.profiles p where p.id = new.id) then
    return new;
  end if;

  insert into public.profiles (
    id,
    email,
    name,
    role,
    institute_id,
    institute_name,
    phone_number,
    status,
    created_at,
    last_login
  )
  values (
    new.id,
    new.email,
    uname,
    'admin',
    iid,
    iname,
    phone,
    'pending',
    now(),
    null
  );

  if not exists (select 1 from public.user_credentials where profile_id = new.id) then
    insert into public.user_credentials (institute_id, profile_id, email, email_sent)
    values (iid, new.id, new.email, false);
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS helpers and policies for attendance_user (mark attendance only)
-- ---------------------------------------------------------------------------

create or replace function public.is_attendance_user()
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
      and p.role = 'attendance_user'
      and lower(coalesce(p.status, 'active')) in ('approved', 'active')
  );
$$;

grant execute on function public.is_attendance_user() to authenticated;

create or replace function public.is_institute_admin_or_attendance_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_institute_admin() or public.is_attendance_user();
$$;

grant execute on function public.is_institute_admin_or_attendance_user() to authenticated;

-- Allow attendance staff to resolve an institute admin row (for GPS fence).
drop policy if exists "profiles_select_admins_same_institute_attendance_user" on public.profiles;
create policy "profiles_select_admins_same_institute_attendance_user"
  on public.profiles for select
  to authenticated
  using (
    public.is_attendance_user()
    and institute_id is not null
    and institute_id = public.current_profile_institute_id()
    and role = 'admin'
    and lower(coalesce(status, '')) in ('approved', 'active')
  );

drop policy if exists "students_select_attendance_user" on public.students;
create policy "students_select_attendance_user"
  on public.students for select
  to authenticated
  using (
    public.is_attendance_user()
    and institute_id = public.current_profile_institute_id()
  );

drop policy if exists "gps_settings_select_attendance_user" on public.gps_settings;
create policy "gps_settings_select_attendance_user"
  on public.gps_settings for select
  to authenticated
  using (
    public.is_attendance_user()
    and institute_id = public.current_profile_institute_id()
  );

drop policy if exists "institute_daily_status_select_attendance_user" on public.institute_daily_status;
create policy "institute_daily_status_select_attendance_user"
  on public.institute_daily_status for select
  to authenticated
  using (
    public.is_attendance_user()
    and institute_id = public.current_profile_institute_id()
  );

drop policy if exists "teacher_attendance_all" on public.teacher_attendance;
create policy "teacher_attendance_all"
  on public.teacher_attendance for all
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin_or_attendance_user()
      and institute_id is not null
      and institute_id = public.current_profile_institute_id()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin_or_attendance_user()
      and institute_id is not null
      and institute_id = public.current_profile_institute_id()
    )
  );

drop policy if exists "attendance_in_out_all_institute_admin" on public.attendance_in_out;
create policy "attendance_in_out_all_institute_admin"
  on public.attendance_in_out for all
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin_or_attendance_user()
      and institute_code = public.current_profile_institute_code()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin_or_attendance_user()
      and institute_code = public.current_profile_institute_code()
    )
  );
