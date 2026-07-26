-- DANGER: destructive cleanup.
-- Deletes all institute-linked data for every institute except 9999 and 1234.
-- This includes students, admin profiles, invites, attendance, GPS, subjects, and institute rows.

do $$
declare
  keep_ids text[] := array['9999', '1234'];
begin
  -- Optional tables may not exist in every environment.
  if to_regclass('public.admin_invites') is not null then
    delete from public.admin_invites where institute_id <> all(keep_ids);
  end if;
  if to_regclass('public.user_credentials') is not null then
    delete from public.user_credentials where institute_id <> all(keep_ids);
  end if;
  if to_regclass('public.institute_subjects') is not null then
    delete from public.institute_subjects where institute_id <> all(keep_ids);
  end if;
  if to_regclass('public.gps_settings') is not null then
    delete from public.gps_settings where institute_id <> all(keep_ids);
  end if;
  if to_regclass('public.institute_geofence') is not null then
    delete from public.institute_geofence where institute_id <> all(keep_ids);
  end if;
  if to_regclass('public.institute_daily_status') is not null then
    delete from public.institute_daily_status where institute_id <> all(keep_ids);
  end if;
  if to_regclass('public.student_leaves') is not null then
    delete from public.student_leaves where institute_id <> all(keep_ids);
  end if;
  if to_regclass('public.teacher_attendance') is not null then
    delete from public.teacher_attendance where institute_id <> all(keep_ids);
  end if;
  if to_regclass('public.user_devices') is not null then
    delete from public.user_devices where institute_id <> all(keep_ids);
  end if;
  if to_regclass('public.suspicious_activity') is not null then
    delete from public.suspicious_activity where institute_id <> all(keep_ids);
  end if;
  if to_regclass('public.security_operations') is not null then
    delete from public.security_operations where institute_id <> all(keep_ids);
  end if;
  if to_regclass('public.security_incidents') is not null then
    delete from public.security_incidents where institute_id <> all(keep_ids);
  end if;
  if to_regclass('public.admin_override_requests') is not null then
    delete from public.admin_override_requests where institute_id <> all(keep_ids);
  end if;
  if to_regclass('public.security_audit_log') is not null then
    delete from public.security_audit_log where institute_id <> all(keep_ids);
  end if;
  if to_regclass('public.error_logs') is not null then
    delete from public.error_logs where institute_id <> all(keep_ids);
  end if;

  -- Rows keyed by institute_id
  if to_regclass('public.students') is not null then
    delete from public.students where institute_id <> all(keep_ids);
  end if;
  if to_regclass('public.batches') is not null then
    delete from public.batches where institute_id <> all(keep_ids);
  end if;

  -- Profile/admin rows linked to removed institutes
  if to_regclass('public.profiles') is not null then
    delete from public.profiles where institute_id <> all(keep_ids);
  end if;

  -- Attendance table uses institute_code/id string, so filter from institutes
  if to_regclass('public.attendance_in_out') is not null then
    delete from public.attendance_in_out
    where institute_code in (
      select i.id from public.institutes i where i.id <> all(keep_ids)
      union
      select coalesce(i.institute_code, '') from public.institutes i
      where i.id <> all(keep_ids) and nullif(i.institute_code, '') is not null
    );
  end if;

  -- Finally delete institute rows themselves
  delete from public.institutes where id <> all(keep_ids);
end;
$$;
