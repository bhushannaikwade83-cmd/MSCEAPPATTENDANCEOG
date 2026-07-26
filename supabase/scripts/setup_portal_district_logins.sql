-- Setup 8 district view-only portal logins (run AFTER migration 076_portal_district_viewers.sql)
--
-- 1) In Supabase Dashboard → Authentication → Users → Add user (email + password you assign)
-- 2) Run the matching block below for that email (replace YOUR_EMAIL@example.com)
-- 3) Repeat for all 8 districts
--
-- Same login page as super admin: email + password. Each user only sees institutes whose
-- 5-digit institute_code starts with one of their district prefixes (view-only).

-- Mumbai — prefixes 11, 14, 15
-- insert into public.profiles (id, email, role, status, name, portal_district_key, created_at)
-- select u.id, u.email, 'portal_district_viewer', 'approved', 'Mumbai District Viewer', 'mumbai', now()
-- from auth.users u where lower(u.email) = lower('YOUR_EMAIL@example.com')
-- on conflict (id) do update set
--   email = excluded.email,
--   role = 'portal_district_viewer',
--   status = 'approved',
--   name = excluded.name,
--   portal_district_key = 'mumbai';

-- Pune — 21, 22, 23  → portal_district_key = 'pune'
-- Nashik — 31–34      → 'nashik'
-- Kolhapur — 41–45    → 'kolhapur'
-- Chhatrapati Sambhajinagar — 51–55 → 'chhatrapati_sambhajinagar'
-- Amrawati — 61–65    → 'amrawati'
-- Nagpur — 71–76      → 'nagpur'
-- Latur — 81–83       → 'latur'

-- Verify after login (as that user) in SQL editor:
-- select public.portal_session_info();

-- List all district portal accounts:
select
  p.email,
  p.name,
  p.role,
  p.status,
  p.portal_district_key,
  d.district_name,
  d.institute_prefixes
from public.profiles p
left join public.portal_districts d on d.district_key = p.portal_district_key
where lower(coalesce(p.role, '')) = 'portal_district_viewer'
order by d.district_name;
