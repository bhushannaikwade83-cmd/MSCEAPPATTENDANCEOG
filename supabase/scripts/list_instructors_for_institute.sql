-- List instructors for one institute. Change '99099' to your institute code or UUID.

select
  p.id,
  p.name,
  p.email,
  p.phone_number,
  p.institute_id,
  p.created_at
from public.profiles p
where p.role = 'attendance_user'
  and (
    p.institute_id in (
      select i.id from public.institutes i
      where i.id = '99099' or i.institute_code = '99099'
    )
    or p.institute_id = '99099'
  )
order by p.created_at;

-- If this returns more than 4 rows, delete extras (or broken rows) before adding new instructors.
-- In Authentication → Users, also delete @staff.msce-attendance.app users not listed here (ghost logins).
