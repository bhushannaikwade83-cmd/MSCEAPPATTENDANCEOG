-- Delete test institutes
-- This migration removes all test institutes created for testing

BEGIN;

-- Delete students from test institutes first (due to foreign key constraints)
DELETE FROM students
WHERE institute_id IN (
  SELECT id FROM institutes
  WHERE name LIKE 'TEST%' OR name LIKE 'test%'
);

-- Delete institutes with test names
DELETE FROM institutes
WHERE name LIKE 'TEST%' OR name LIKE 'test%';

-- Verify deletion
SELECT COUNT(*) as remaining_test_institutes
FROM institutes
WHERE name LIKE 'TEST%' OR name LIKE 'test%';

COMMIT;
