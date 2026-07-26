-- Run in Supabase SQL Editor when adding instructor #2 fails but list shows 0 or 1.
-- Change 99099 to your institute_code (or use institutes.id UUID).

-- 1) See all instructor profiles for this institute (including hidden by old RLS)
select
  p.id,
  p.name,
  p.email,
  p.phone_number,
  p.institute_id,
  p.pin_hash is not null as has_pin,
  p.created_at
from public.profiles p
where p.role = 'attendance_user'
  and (
    p.institute_id in (
      select i.id::text from public.institutes i
      where i.id = '99099' or i.institute_code = '99099'
    )
    or p.institute_id = '99099'
  )
order by p.created_at;

-- 2) Fix institute_id to canonical UUID (same as migration 071)
update public.profiles p
set institute_id = i.id
from public.institutes i
where p.role = 'attendance_user'
  and p.institute_id is not null
  and p.institute_id is distinct from i.id
  and (p.institute_id = i.institute_code or p.institute_id = i.id::text)
  and (i.id = '99099' or i.institute_code = '99099');

-- 3) Remove broken duplicate instructor rows (no name / no pin) — adjust ids after step 1
-- delete from public.profiles
-- where id in ('PASTE-UUID-OF-BROKEN-ROW')
--   and role = 'attendance_user';

-- 4) In Dashboard → Authentication → Users: delete @staff.msce-attendance.app users
--    that do NOT appear in step 1 (ghost logins from failed adds).
