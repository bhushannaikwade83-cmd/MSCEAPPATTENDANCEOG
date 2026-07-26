-- Delete ALL dummy institutes and recreate them fresh

BEGIN;

-- Delete auth user with naikwadebhushan@gmail.com first
DELETE FROM auth.users
WHERE email = 'naikwadebhushan@gmail.com';

-- Delete all 4 institutes (cascades to profiles, students, etc.)
DELETE FROM public.institutes
WHERE id IN ('99099', '99098', '99097', '12345');

-- Delete any remaining admin invites for these institutes
DELETE FROM public.admin_invites
WHERE institute_id IN ('99099', '99098', '99097', '12345');

-- Now add all 4 institutes fresh

-- Institute 1: dummy1
INSERT INTO public.institutes (
  id,
  institute_code,
  name,
  location,
  address,
  city,
  state,
  country,
  mobile_no,
  is_active,
  created_at,
  updated_at
)
VALUES (
  '99099',
  '99099',
  'dummy1',
  'Pune',
  'Pune, Maharashtra 411001',
  'Pune',
  'Maharashtra',
  'India',
  '+91 98223 22990',
  true,
  now(),
  now()
);

INSERT INTO public.admin_invites (
  institute_id,
  full_name,
  phone,
  email,
  claimed,
  created_at,
  updated_at
)
VALUES (
  '99099',
  'admin1',
  '+91 98223 22990',
  'Latest.infotech@gmail.com',
  false,
  now(),
  now()
);

-- Institute 2: dummy2
INSERT INTO public.institutes (
  id,
  institute_code,
  name,
  location,
  address,
  city,
  state,
  country,
  mobile_no,
  is_active,
  created_at,
  updated_at
)
VALUES (
  '99098',
  '99098',
  'dummy2',
  'Pune',
  'Pune, Maharashtra 411001',
  'Pune',
  'Maharashtra',
  'India',
  '+91 98223 22990',
  true,
  now(),
  now()
);

INSERT INTO public.admin_invites (
  institute_id,
  full_name,
  phone,
  email,
  claimed,
  created_at,
  updated_at
)
VALUES (
  '99098',
  'admin2',
  '+91 98223 22990',
  'Latest.infotech@gmail.com',
  false,
  now(),
  now()
);

-- Institute 3: dummy3
INSERT INTO public.institutes (
  id,
  institute_code,
  name,
  location,
  address,
  city,
  state,
  country,
  mobile_no,
  is_active,
  created_at,
  updated_at
)
VALUES (
  '99097',
  '99097',
  'dummy3',
  'Pune',
  'Pune, Maharashtra 411001',
  'Pune',
  'Maharashtra',
  'India',
  '+91 98223 22990',
  true,
  now(),
  now()
);

INSERT INTO public.admin_invites (
  institute_id,
  full_name,
  phone,
  email,
  claimed,
  created_at,
  updated_at
)
VALUES (
  '99097',
  'admin3',
  '+91 98223 22990',
  'Latest.infotech@gmail.com',
  false,
  now(),
  now()
);

-- Institute 4: dummy4
INSERT INTO public.institutes (
  id,
  institute_code,
  name,
  location,
  address,
  city,
  state,
  country,
  mobile_no,
  is_active,
  created_at,
  updated_at
)
VALUES (
  '12345',
  '12345',
  'dummy4',
  'Pune',
  'Pune, Maharashtra 411001',
  'Pune',
  'Maharashtra',
  'India',
  '9773609077',
  true,
  now(),
  now()
);

INSERT INTO public.admin_invites (
  institute_id,
  full_name,
  phone,
  email,
  claimed,
  created_at,
  updated_at
)
VALUES (
  '12345',
  'bhushan naikwade',
  '9773609077',
  'naikwadebhushan@gmail.com',
  false,
  now(),
  now()
);

-- Verify: Count total institutes created
SELECT COUNT(*) as total_institutes_created
FROM public.institutes
WHERE id IN ('99099', '99098', '99097', '12345');

-- Show all 4 institutes
SELECT
  id,
  name,
  city,
  mobile_no,
  is_active
FROM public.institutes
WHERE id IN ('99099', '99098', '99097', '12345')
ORDER BY id DESC;

-- Show all admin invites
SELECT
  institute_id,
  full_name,
  email,
  phone,
  claimed
FROM public.admin_invites
WHERE institute_id IN ('99099', '99098', '99097', '12345')
ORDER BY institute_id DESC;

COMMIT;
