-- Sandbox institutes kept by 026 (delete all except 9999 + 1234).
-- Ensures both rows exist, stay active, and feel like "first admin login":
-- no PIN, no saved GPS/geofence, invites + setup markers cleared so the portal can re-provision
-- website signup / institute wizard from scratch.
--
-- Does NOT delete auth.users, profiles, or students; use 026 / 028 if you need that.

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
    'Test Institute 9999 (first-login sandbox)',
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
    'Test Institute 1234 (first-login sandbox)',
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
on conflict (id) do update set
  institute_code = excluded.institute_code,
  name           = excluded.name,
  is_active      = true,
  updated_at     = now();

-- Same intent as 027, but for both sandboxes.
update public.institutes
set is_active = true,
    updated_at = now()
where id in ('9999', '1234');

delete from public.gps_settings
where institute_id in ('9999', '1234');

delete from public.institute_geofence
where institute_id in ('9999', '1234');

update public.profiles
set pin_hash   = null,
    has_pin    = false,
    pin_set_at = null
where institute_id in ('9999', '1234')
  and role = 'admin';

delete from public.admin_invites
where institute_id in ('9999', '1234');

delete from public.system_settings
where key ~ '^institute_(setup|config|storage)_(9999|1234)$';

delete from public.user_credentials
where institute_id in ('9999', '1234');
