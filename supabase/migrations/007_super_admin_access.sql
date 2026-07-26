-- Super Admin access overlay (additive policies)
-- Run AFTER 006_rls_production.sql
-- This keeps strict institute-admin RLS, and additionally grants cross-institute access
-- to users whose profile role is 'super_admin' (or coder users).

create or replace function public.is_super_admin()
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
      and p.role = 'super_admin'
      and lower(coalesce(p.status, 'approved')) in ('approved', 'active')
  )
  or public.is_coder();
$$;

grant execute on function public.is_super_admin() to authenticated;

drop policy if exists "institutes_super_admin_all" on public.institutes;
drop policy if exists "profiles_super_admin_all" on public.profiles;
drop policy if exists "institute_geofence_super_admin_all" on public.institute_geofence;
drop policy if exists "system_settings_super_admin_all" on public.system_settings;
drop policy if exists "user_credentials_super_admin_all" on public.user_credentials;
drop policy if exists "students_super_admin_select" on public.students;
drop policy if exists "batches_super_admin_select" on public.batches;
drop policy if exists "attendance_in_out_super_admin_select" on public.attendance_in_out;
drop policy if exists "teacher_attendance_super_admin_select" on public.teacher_attendance;
drop policy if exists "gps_settings_super_admin_select" on public.gps_settings;
drop policy if exists "institute_daily_status_super_admin_select" on public.institute_daily_status;
drop policy if exists "error_logs_super_admin_select" on public.error_logs;

-- institutes: full management for super admin
create policy "institutes_super_admin_all"
  on public.institutes for all
  to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

-- profiles: allow super admin to create/manage institute admins across institutes
create policy "profiles_super_admin_all"
  on public.profiles for all
  to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

-- tables touched by super admin setup + dashboards
create policy "institute_geofence_super_admin_all"
  on public.institute_geofence for all
  to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

create policy "system_settings_super_admin_all"
  on public.system_settings for all
  to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

create policy "user_credentials_super_admin_all"
  on public.user_credentials for all
  to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

-- read access across institutes for attendance explorer / reporting
create policy "students_super_admin_select"
  on public.students for select
  to authenticated
  using (public.is_super_admin());

create policy "batches_super_admin_select"
  on public.batches for select
  to authenticated
  using (public.is_super_admin());

create policy "attendance_in_out_super_admin_select"
  on public.attendance_in_out for select
  to authenticated
  using (public.is_super_admin());

create policy "teacher_attendance_super_admin_select"
  on public.teacher_attendance for select
  to authenticated
  using (public.is_super_admin());

create policy "gps_settings_super_admin_select"
  on public.gps_settings for select
  to authenticated
  using (public.is_super_admin());

create policy "institute_daily_status_super_admin_select"
  on public.institute_daily_status for select
  to authenticated
  using (public.is_super_admin());

create policy "error_logs_super_admin_select"
  on public.error_logs for select
  to authenticated
  using (public.is_super_admin());
