-- Orphan institute instructors: exist in auth.users but NOT as attendance_user in public.profiles
-- (app shows "no instructor" but add fails with "already exists").
--
-- Run in Supabase SQL Editor. Replace YOUR_INSTITUTE_UUID with institutes.id
-- (or find it: select id, institute_code, name from institutes where institute_code = '99099';)

-- 1) Instructors the app can see
select id, name, email, phone_number, status, created_at
from public.profiles
where role = 'attendance_user'
  and institute_id = 'YOUR_INSTITUTE_UUID';

-- 2) Ghost logins in Auth (manual delete in Dashboard → Authentication → Users)
select
  u.id,
  u.email,
  u.created_at,
  u.raw_user_meta_data->>'institute_id' as meta_institute_id,
  u.raw_user_meta_data->>'app_role' as meta_app_role,
  p.role as profile_role
from auth.users u
left join public.profiles p on p.id = u.id
where u.email ilike '%@staff.msce-attendance.app%'
  and (
    u.email ilike 'att.YOUR_INSTITUTE_UUID@staff.msce-attendance.app'
    or u.raw_user_meta_data->>'institute_id' = 'YOUR_INSTITUTE_UUID'
  )
order by u.created_at desc;

-- Legacy single-email pattern (old app versions):
--   att.{institute-uuid}@staff.msce-attendance.app
--
-- After deleting ghost users in Dashboard → Auth, add the instructor again in the app.
