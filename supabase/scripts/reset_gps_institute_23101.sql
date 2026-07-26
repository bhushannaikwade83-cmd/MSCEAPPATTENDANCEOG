-- Reset GPS settings for Institute 23101 only
--
-- This clears:
--   - GPS/geofence location and radius for institute 23101
--   - Allows admin to redo GPS setup when they next login
--
-- Preserves: All student data, attendance records, and other institute settings
--
-- Run from Supabase SQL Editor as a privileged user

begin;

do $$
declare
  institute_id_val text := '23101';
begin
  -- Delete GPS settings for this institute
  if to_regclass('public.gps_settings') is not null then
    delete from public.gps_settings
    where institute_id::text = institute_id_val;
  end if;

  -- Delete geofence settings for this institute
  if to_regclass('public.institute_geofence') is not null then
    delete from public.institute_geofence
    where institute_id::text = institute_id_val;
  end if;
end $$;

commit;

-- Verification
select 'GPS Reset Complete for Institute 23101' as status,
       (select count(*) from public.gps_settings where institute_id::text = '23101') as gps_settings_remaining,
       (select count(*) from public.institute_geofence where institute_id::text = '23101') as geofence_settings_remaining;
