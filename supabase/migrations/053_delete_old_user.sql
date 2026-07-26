-- Delete old naikwadebhushan@gmail.com user account

BEGIN;

-- Delete the auth user (cascades to profiles automatically)
DELETE FROM auth.users
WHERE email = 'naikwadebhushan@gmail.com';

-- Verify deletion
SELECT COUNT(*) as remaining_users
FROM auth.users
WHERE email = 'naikwadebhushan@gmail.com';

COMMIT;
