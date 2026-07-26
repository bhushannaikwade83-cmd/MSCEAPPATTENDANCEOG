-- Run this in Supabase SQL Editor AFTER you create the auth user
-- (Dashboard → Authentication → Users → Add user → gcctbcsupport@gmail.com).
-- Safe to run multiple times (upserts on profiles.id).

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
  name = excluded.name,
  institute_id = null,
  institute_name = null;

delete from public.coders
where lower(coalesce(email, '')) = 'gcctbcsupport@gmail.com';
