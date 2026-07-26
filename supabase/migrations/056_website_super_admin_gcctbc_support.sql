-- Website MSCE admin portal: ensure this auth user gets super_admin in public.profiles
-- (same pattern as migration 029 for admin@gmail.com).
-- 1) Create the user in Supabase Dashboard → Authentication → Users (email + password).
-- 2) Run this migration (or push migrations). Passwords are never stored in SQL or app code.

insert into public.profiles (
  id,
  email,
  role,
  status,
  name,
  created_at
)
select
  u.id,
  u.email,
  'super_admin',
  'approved',
  'MSCE Website Support',
  now()
from auth.users u
where lower(u.email) = 'gcctbcsupport@gmail.com'
on conflict (id) do update
set
  email = excluded.email,
  role = 'super_admin',
  status = 'approved',
  name = excluded.name;

delete from public.coders
where lower(coalesce(email, '')) = 'gcctbcsupport@gmail.com';
