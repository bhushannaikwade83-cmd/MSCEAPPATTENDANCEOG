-- DANGER: destructive for the TARGET TEST institutes only — for local / staging test resets.
--
-- Does NOT delete other institutes.
--
-- For institutes 9999, 1234, 12345 only:
-- 1) Strips students, attendance, subjects, GPS, invites, staff profiles,
--    institute passwords, etc.; keeps `public.institutes` rows and `profiles` where role = 'admin'.
-- 2) Clears admin PIN + onboarding markers; removes admin_passwords so email / OTP flows are clean.
-- 3) Revokes existing auth sessions + refresh tokens for those admins (forces next login / OTP).
--
-- Does NOT delete auth.users (admins keep the same accounts). Does NOT touch `public.coders`.
-- Run in Supabase SQL Editor as postgres, or: supabase db push (after review).

do $$
declare
  keep_ids text[] := array['9999', '1234', '12345'];
begin
  -- Wipe operational data inside the three sandbox institutes only.
  if to_regclass('public.students') is not null then
    delete from public.students where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.batches') is not null then
    delete from public.batches where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.institute_subjects') is not null then
    delete from public.institute_subjects where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.gps_settings') is not null then
    delete from public.gps_settings where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.institute_geofence') is not null then
    delete from public.institute_geofence where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.institute_daily_status') is not null then
    delete from public.institute_daily_status where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.student_leaves') is not null then
    delete from public.student_leaves where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.teacher_attendance') is not null then
    delete from public.teacher_attendance where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.user_devices') is not null then
    delete from public.user_devices where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.suspicious_activity') is not null then
    delete from public.suspicious_activity where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.security_operations') is not null then
    delete from public.security_operations where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.security_incidents') is not null then
    delete from public.security_incidents where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.admin_override_requests') is not null then
    delete from public.admin_override_requests where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.security_audit_log') is not null then
    delete from public.security_audit_log where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.error_logs') is not null then
    delete from public.error_logs where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.auth_rate_limits') is not null then
    delete from public.auth_rate_limits where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.auth_lockouts') is not null then
    delete from public.auth_lockouts where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.admin_passwords') is not null then
    delete from public.admin_passwords where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.admin_invites') is not null then
    delete from public.admin_invites where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.user_credentials') is not null then
    delete from public.user_credentials where institute_id = any(keep_ids);
  end if;

  if to_regclass('public.attendance_in_out') is not null then
    delete from public.attendance_in_out
    where institute_code in (
      select i.id from public.institutes i where i.id = any(keep_ids)
      union
      select coalesce(i.institute_code, '')
      from public.institutes i
      where i.id = any(keep_ids) and nullif(i.institute_code, '') is not null
    );
  end if;

  -- Staff / non-admin app users for these institutes (attendance_user, etc.)
  if to_regclass('public.profiles') is not null then
    delete from public.profiles p
    where p.institute_id = any(keep_ids)
      and lower(coalesce(p.role, '')) <> 'admin';
  end if;

  delete from public.system_settings
  where key ~ '^institute_(setup|config|storage)_(9999|1234|12345)$';

  update public.institutes i
     set student_count             = 0,
         sr_no_migration_count     = null,
         sr_no_migration_completed = coalesce(i.sr_no_migration_completed, false),
         sr_no_migration_date      = null,
         updated_at                = now()
   where i.id = any(keep_ids);

  update public.profiles
     set pin_hash               = null,
         has_pin                = false,
         pin_set_at             = null,
         encrypted_password     = null,
         last_login             = null,
         last_login_ip          = null
   where institute_id = any(keep_ids)
     and lower(coalesce(role, '')) = 'admin';

  -- ── Phase 3: revoke sessions so next login runs full OTP/magic-link flow ────────────────────
  if to_regclass('auth.refresh_tokens') is not null then
    delete from auth.refresh_tokens r
    using public.profiles p
    where r.user_id = p.id
      and p.institute_id = any(keep_ids)
      and lower(coalesce(p.role, '')) = 'admin';
  end if;

  if to_regclass('auth.sessions') is not null then
    delete from auth.sessions s
    using public.profiles p
    where s.user_id = p.id
      and p.institute_id = any(keep_ids)
      and lower(coalesce(p.role, '')) = 'admin';
  end if;

  -- Reconcile institute.user_count with remaining admins
  update public.institutes i
     set user_count = coalesce(
           (select count(*)::int
            from public.profiles p
            where p.institute_id = i.id
              and lower(coalesce(p.role, '')) = 'admin'),
           0
         ),
         updated_at = now()
   where i.id = any(keep_ids);
end;
$$;

-- Ensure the three sandbox institute rows exist if missing.
-- Existing institute details are intentionally preserved.
insert into public.institutes (
  id,
  institute_code,
  name,
  location,
  address,
  city,
  district,
  taluka,
  state,
  country,
  mobile_no,
  is_active,
  user_count,
  student_count
)
values
  (
    '9999',
    '9999',
    'Test Institute 9999 (sandbox)',
    'Test',
    'Test',
    'Test City',
    'Pune',
    'Haveli',
    'Maharashtra',
    'India',
    '',
    true,
    0,
    0
  ),
  (
    '1234',
    '1234',
    'Test Institute 1234 (sandbox)',
    'Test',
    'Test',
    'Test City',
    'Pune',
    'Haveli',
    'Maharashtra',
    'India',
    '',
    true,
    0,
    0
  ),
  (
    '12345',
    '12345',
    'Test Institute 12345 (sandbox)',
    'Test',
    'Test',
    'Test City',
    'Pune',
    'Haveli',
    'Maharashtra',
    'India',
    '',
    true,
    0,
    0
  )
on conflict (id) do nothing;

-- Align counters without changing institute identity/details.
update public.institutes i
   set user_count = coalesce(
         (select count(*)::int
          from public.profiles p
          where p.institute_id = i.id
            and lower(coalesce(p.role, '')) = 'admin'),
         0
       ),
       student_count = 0,
       updated_at = now()
 where i.id in ('9999', '1234', '12345');
