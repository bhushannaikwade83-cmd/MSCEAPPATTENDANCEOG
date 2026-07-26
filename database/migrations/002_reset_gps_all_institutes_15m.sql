-- One-time policy: clear all per-admin locked GPS points and set 15 m radius.
-- Admins must open GPS Settings and save again (new 15 m circle from the new lock point).
-- Run in Supabase SQL editor (or your migration runner) as a privileged role.

UPDATE public.gps_settings
SET
  latitude = NULL,
  longitude = NULL,
  is_locked = false,
  radius = 15,
  locked_at = NULL,
  locked_by = NULL;

UPDATE public.institute_geofence
SET radius = 15;

UPDATE public.system_settings
SET
  value = jsonb_set(COALESCE(value, '{}'::jsonb), '{radius}', to_jsonb(15), true),
  updated_at = now()
WHERE key = 'gps_config';
