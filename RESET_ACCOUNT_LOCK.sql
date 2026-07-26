-- ============================================
-- RESET ACCOUNT LOCK
-- Clear failed PIN login attempts
-- ============================================

-- Find the user
SELECT
  id,
  email,
  (userData->>'name') as name,
  (userData->>'role') as role
FROM profiles
WHERE email = 'primacomputer@gmail.com';

-- ============================================
-- Option 1: Clear security_operations records
-- ============================================

-- Delete failed PIN login attempts for this user
DELETE FROM security_operations
WHERE identifier = 'primacomputer@gmail.com'
  AND action_type = 'admin_pin_login'
  AND success = false;

-- Verify deletion
SELECT
  COUNT(*) as remaining_failed_attempts,
  MAX(attempted_at) as last_failed_attempt
FROM security_operations
WHERE identifier = 'primacomputer@gmail.com'
  AND action_type = 'admin_pin_login'
  AND success = false;

-- ============================================
-- Option 2: Check biometric settings
-- ============================================

-- Get user ID first
WITH user_data AS (
  SELECT id FROM profiles WHERE email = 'primacomputer@gmail.com' LIMIT 1
)
SELECT
  id,
  email,
  (userData->>'biometricEnabled') as biometric_enabled,
  (userData->>'pinHash') as has_pin_hash
FROM profiles
WHERE id = (SELECT id FROM user_data);

-- ============================================
-- Option 3: Force enable biometric
-- ============================================

UPDATE profiles
SET userData = jsonb_set(
  userData,
  '{biometricEnabled}',
  'true'::jsonb
)
WHERE email = 'primacomputer@gmail.com';

-- Verify biometric is enabled
SELECT
  email,
  (userData->>'biometricEnabled') as biometric_enabled
FROM profiles
WHERE email = 'primacomputer@gmail.com';

-- ============================================
-- SUMMARY
-- ============================================

SELECT
  'ACCOUNT RESET COMPLETE' as status,
  'primacomputer@gmail.com' as email,
  'PIN login attempts cleared' as action_1,
  'Biometric enabled' as action_2;
