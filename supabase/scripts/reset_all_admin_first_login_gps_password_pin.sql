-- Reset all institutes to admin first-login state.
--
-- This keeps institutes, students, attendance, and admin profile rows.
-- It clears:
--   - GPS/geofence setup for every institute
--   - admin PIN and encrypted password fields
--   - admin password setup rows
--   - admin first-login/session markers
--
-- It preserves admin profile rows, admin invite/contact rows, and user credential
-- helper rows so institute/admin details are not wiped.
--
-- Run from Supabase SQL Editor as a privileged user after reviewing.

begin;

do $$
begin
  if to_regclass('public.gps_settings') is not null then
    delete from public.gps_settings;
  end if;

  if to_regclass('public.institute_geofence') is not null then
    delete from public.institute_geofence;
  end if;

  if to_regclass('public.admin_passwords') is not null then
    delete from public.admin_passwords;
  end if;

  if to_regclass('public.system_settings') is not null then
    delete from public.system_settings
    where key ~ '^institute_(setup|config|storage)_';
  end if;

  if to_regclass('public.profiles') is not null then
    update public.profiles
       set pin_hash = null,
           encrypted_password = null,
           has_pin = false,
           pin_set_at = null,
           last_login = null,
           last_login_ip = null,
           status = 'pending'
     where lower(coalesce(role, '')) = 'admin';
  end if;

  if to_regclass('auth.refresh_tokens') is not null
     and to_regclass('public.profiles') is not null then
    delete from auth.refresh_tokens r
    using public.profiles p
    where r.user_id::text = p.id::text
      and lower(coalesce(p.role, '')) = 'admin';
  end if;

  if to_regclass('auth.sessions') is not null
     and to_regclass('public.profiles') is not null then
    delete from auth.sessions s
    using public.profiles p
    where s.user_id::text = p.id::text
      and lower(coalesce(p.role, '')) = 'admin';
  end if;
end $$;

commit;

-- Verification summary
create temp table reset_all_admin_first_login_summary (
  metric text primary key,
  value bigint not null
);

do $$
begin
  if to_regclass('public.gps_settings') is not null then
    insert into reset_all_admin_first_login_summary
    select 'gps_settings_remaining', count(*) from public.gps_settings;
  end if;

  if to_regclass('public.institute_geofence') is not null then
    insert into reset_all_admin_first_login_summary
    select 'institute_geofence_remaining', count(*) from public.institute_geofence;
  end if;

  if to_regclass('public.admin_passwords') is not null then
    insert into reset_all_admin_first_login_summary
    select 'admin_passwords_remaining', count(*) from public.admin_passwords;
  else
    insert into reset_all_admin_first_login_summary values ('admin_passwords_remaining', 0);
  end if;

  if to_regclass('public.admin_invites') is not null then
    insert into reset_all_admin_first_login_summary
    select 'admin_invites_remaining', count(*) from public.admin_invites;
  end if;

  if to_regclass('public.user_credentials') is not null then
    insert into reset_all_admin_first_login_summary
    select 'user_credentials_remaining', count(*) from public.user_credentials;
  end if;

  if to_regclass('public.profiles') is not null then
    insert into reset_all_admin_first_login_summary
    select 'admin_profiles_still_configured', count(*)
    from public.profiles
    where lower(coalesce(role, '')) = 'admin'
      and (
        pin_hash is not null
        or encrypted_password is not null
        or has_pin is true
        or pin_set_at is not null
        or last_login is not null
        or last_login_ip is not null
      );
  end if;
end $$;

select * from reset_all_admin_first_login_summary order by metric;
