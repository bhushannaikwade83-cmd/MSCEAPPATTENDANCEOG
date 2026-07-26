-- Production RLS — replaces permissive policies from 001 / 005
-- Run after 001–005. Safe to re-run: drops named policies then recreates.

-- ---------------------------------------------------------------------------
-- Helpers (SECURITY DEFINER = bypass RLS on profiles when evaluating rules)
-- ---------------------------------------------------------------------------

create or replace function public.current_profile_institute_id()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.institute_id from public.profiles p where p.id = auth.uid();
$$;

create or replace function public.current_profile_institute_code()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(nullif(trim(i.institute_code), ''), i.id::text)
  from public.profiles p
  join public.institutes i on i.id = p.institute_id
  where p.id = auth.uid();
$$;

create or replace function public.is_institute_admin()
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
      and p.role = 'admin'
      and lower(coalesce(p.status, 'approved')) in ('approved', 'active')
  );
$$;

create or replace function public.is_coder()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.coders c where c.id = auth.uid());
$$;

create or replace function public.profile_has_no_institute()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.institute_id is null
  );
$$;

grant execute on function public.current_profile_institute_id() to authenticated, anon;
grant execute on function public.current_profile_institute_code() to authenticated;
grant execute on function public.is_institute_admin() to authenticated;
grant execute on function public.is_coder() to authenticated;
grant execute on function public.profile_has_no_institute() to authenticated;

-- ---------------------------------------------------------------------------
-- Drop old permissive policies (001 + 005)
-- ---------------------------------------------------------------------------

drop policy if exists "authenticated_all_institutes" on public.institutes;
drop policy if exists "authenticated_all_profiles" on public.profiles;
drop policy if exists "authenticated_all_students" on public.students;
drop policy if exists "authenticated_all_batches" on public.batches;
drop policy if exists "authenticated_all_attendance" on public.attendance_in_out;
drop policy if exists "authenticated_all_error_logs" on public.error_logs;
drop policy if exists "authenticated_all_user_cred" on public.user_credentials;
drop policy if exists "authenticated_all_subjects" on public.institute_subjects;
drop policy if exists "authenticated_all_settings" on public.system_settings;
drop policy if exists "anon_insert_error_logs" on public.error_logs;

drop policy if exists "authenticated_all_gps" on public.gps_settings;
drop policy if exists "authenticated_all_inst_geofence" on public.institute_geofence;
drop policy if exists "authenticated_all_daily_status" on public.institute_daily_status;
drop policy if exists "authenticated_all_leaves" on public.student_leaves;
drop policy if exists "authenticated_all_coders" on public.coders;
drop policy if exists "authenticated_all_suspicious" on public.suspicious_activity;
drop policy if exists "authenticated_all_user_devices" on public.user_devices;
drop policy if exists "authenticated_all_teacher_att" on public.teacher_attendance;

-- Drop production policies from a prior partial run of this migration
drop policy if exists "institutes_select_anon_active" on public.institutes;
drop policy if exists "institutes_select_authenticated" on public.institutes;
drop policy if exists "institutes_insert_authenticated" on public.institutes;
drop policy if exists "institutes_update_authenticated" on public.institutes;
drop policy if exists "institutes_delete_coder" on public.institutes;
drop policy if exists "profiles_select" on public.profiles;
drop policy if exists "profiles_insert_own" on public.profiles;
drop policy if exists "profiles_update_own_or_admin_peer" on public.profiles;
drop policy if exists "profiles_delete_own" on public.profiles;
drop policy if exists "profiles_delete_coder" on public.profiles;
drop policy if exists "students_all_institute_admin" on public.students;
drop policy if exists "batches_all_institute_admin" on public.batches;
drop policy if exists "institute_subjects_all_institute_admin" on public.institute_subjects;
drop policy if exists "attendance_in_out_all_institute_admin" on public.attendance_in_out;
drop policy if exists "error_logs_select_coder_or_institute" on public.error_logs;
drop policy if exists "error_logs_insert_authenticated" on public.error_logs;
drop policy if exists "error_logs_insert_anon_limited" on public.error_logs;
drop policy if exists "error_logs_update_coder" on public.error_logs;
drop policy if exists "error_logs_delete_coder" on public.error_logs;
drop policy if exists "user_credentials_all_institute_admin" on public.user_credentials;
drop policy if exists "system_settings_select_authenticated" on public.system_settings;
drop policy if exists "system_settings_write_coder" on public.system_settings;
drop policy if exists "system_settings_update_coder" on public.system_settings;
drop policy if exists "system_settings_delete_coder" on public.system_settings;
drop policy if exists "gps_settings_all" on public.gps_settings;
drop policy if exists "institute_geofence_all" on public.institute_geofence;
drop policy if exists "institute_daily_status_all" on public.institute_daily_status;
drop policy if exists "student_leaves_all" on public.student_leaves;
drop policy if exists "coders_select_self" on public.coders;
drop policy if exists "coders_update_coder" on public.coders;
drop policy if exists "coders_delete_coder" on public.coders;
drop policy if exists "suspicious_activity_all" on public.suspicious_activity;
drop policy if exists "user_devices_all" on public.user_devices;
drop policy if exists "teacher_attendance_all" on public.teacher_attendance;

-- ---------------------------------------------------------------------------
-- institutes
-- ---------------------------------------------------------------------------
-- Public read of active institutes (search / registration before full login)
create policy "institutes_select_anon_active"
  on public.institutes for select
  to anon
  using (coalesce(is_active, true));

create policy "institutes_select_authenticated"
  on public.institutes for select
  to authenticated
  using (
    public.is_coder()
    or coalesce(is_active, true)
  );

-- Create institute: coder, or onboarding user not yet assigned to an institute
create policy "institutes_insert_authenticated"
  on public.institutes for insert
  to authenticated
  with check (
    public.is_coder()
    or public.profile_has_no_institute()
  );

create policy "institutes_update_authenticated"
  on public.institutes for update
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and id = public.current_profile_institute_id()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and id = public.current_profile_institute_id()
    )
  );

create policy "institutes_delete_coder"
  on public.institutes for delete
  to authenticated
  using (public.is_coder());

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create policy "profiles_select"
  on public.profiles for select
  to authenticated
  using (
    id = auth.uid()
    or public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id is not null
      and institute_id = public.current_profile_institute_id()
    )
  );

create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check (id = auth.uid());

create policy "profiles_update_own_or_admin_peer"
  on public.profiles for update
  to authenticated
  using (
    id = auth.uid()
    or public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id is not null
      and institute_id = public.current_profile_institute_id()
    )
  )
  with check (
    id = auth.uid()
    or public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id is not null
      and institute_id = public.current_profile_institute_id()
    )
  );

create policy "profiles_delete_own"
  on public.profiles for delete
  to authenticated
  using (id = auth.uid());

create policy "profiles_delete_coder"
  on public.profiles for delete
  to authenticated
  using (public.is_coder());

-- ---------------------------------------------------------------------------
-- students, batches, institute_subjects (institute-scoped, admin)
-- ---------------------------------------------------------------------------

create policy "students_all_institute_admin"
  on public.students for all
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  );

create policy "batches_all_institute_admin"
  on public.batches for all
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  );

create policy "institute_subjects_all_institute_admin"
  on public.institute_subjects for all
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  );

-- ---------------------------------------------------------------------------
-- attendance_in_out (match institute code to caller's institute)
-- ---------------------------------------------------------------------------

create policy "attendance_in_out_all_institute_admin"
  on public.attendance_in_out for all
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_code = public.current_profile_institute_code()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_code = public.current_profile_institute_code()
    )
  );

-- ---------------------------------------------------------------------------
-- error_logs
-- ---------------------------------------------------------------------------

create policy "error_logs_select_coder_or_institute"
  on public.error_logs for select
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and (
        institute_id is null
        or institute_id = public.current_profile_institute_id()
      )
    )
  );

create policy "error_logs_insert_authenticated"
  on public.error_logs for insert
  to authenticated
  with check (
    institute_id is null
    or institute_id = public.current_profile_institute_id()
    or public.is_coder()
  );

-- Pre-login logging: narrow; disable if abused (spam)
create policy "error_logs_insert_anon_limited"
  on public.error_logs for insert
  to anon
  with check (
    coalesce(length(coalesce(error_message, '')), 0) <= 20000
    and coalesce(length(coalesce(stack_trace, '')), 0) <= 50000
  );

create policy "error_logs_update_coder"
  on public.error_logs for update
  to authenticated
  using (public.is_coder())
  with check (public.is_coder());

create policy "error_logs_delete_coder"
  on public.error_logs for delete
  to authenticated
  using (public.is_coder());

-- ---------------------------------------------------------------------------
-- user_credentials
-- ---------------------------------------------------------------------------

create policy "user_credentials_all_institute_admin"
  on public.user_credentials for all
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  );

-- ---------------------------------------------------------------------------
-- system_settings (read for app; write for coders only)
-- ---------------------------------------------------------------------------

create policy "system_settings_select_authenticated"
  on public.system_settings for select
  to authenticated
  using (true);

create policy "system_settings_write_coder"
  on public.system_settings for insert
  to authenticated
  with check (public.is_coder());

create policy "system_settings_update_coder"
  on public.system_settings for update
  to authenticated
  using (public.is_coder())
  with check (public.is_coder());

create policy "system_settings_delete_coder"
  on public.system_settings for delete
  to authenticated
  using (public.is_coder());

-- ---------------------------------------------------------------------------
-- 005 aux tables
-- ---------------------------------------------------------------------------

create policy "gps_settings_all"
  on public.gps_settings for all
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  );

create policy "institute_geofence_all"
  on public.institute_geofence for all
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  );

create policy "institute_daily_status_all"
  on public.institute_daily_status for all
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  );

create policy "student_leaves_all"
  on public.student_leaves for all
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  );

-- Coders: only see own row (login check). Inserts via service role / dashboard SQL.
create policy "coders_select_self"
  on public.coders for select
  to authenticated
  using (id = auth.uid() or public.is_coder());

-- Inserts: use Supabase Dashboard SQL or service role (bypasses RLS). No client policy.

create policy "coders_update_coder"
  on public.coders for update
  to authenticated
  using (public.is_coder())
  with check (public.is_coder());

create policy "coders_delete_coder"
  on public.coders for delete
  to authenticated
  using (public.is_coder());

create policy "suspicious_activity_all"
  on public.suspicious_activity for all
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  );

create policy "user_devices_all"
  on public.user_devices for all
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  );

-- Rows with null institute_id are only visible to coders (legacy / fix data in SQL).
create policy "teacher_attendance_all"
  on public.teacher_attendance for all
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id is not null
      and institute_id = public.current_profile_institute_id()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id is not null
      and institute_id = public.current_profile_institute_id()
    )
  );
