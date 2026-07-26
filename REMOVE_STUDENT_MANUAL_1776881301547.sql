-- ============================================
-- REMOVE STUDENT: MANUAL_1776881301547
-- ============================================

-- Step 1: Find student details
SELECT
  id,
  name,
  sr_no,
  institute_id,
  user_id,
  created_at
FROM students
WHERE user_id = 'MANUAL_1776881301547'
   OR id = 'MANUAL_1776881301547'
LIMIT 1;

-- ============================================
-- STEP 2: DELETE ALL ASSOCIATED DATA
-- ============================================

-- Delete attendance records
DELETE FROM attendance_records
WHERE student_id IN (
  SELECT id FROM students
  WHERE user_id = 'MANUAL_1776881301547'
     OR id = 'MANUAL_1776881301547'
);

-- Delete face registration embedding
DELETE FROM student_registrations
WHERE student_id IN (
  SELECT id FROM students
  WHERE user_id = 'MANUAL_1776881301547'
     OR id = 'MANUAL_1776881301547'
);

-- Delete student record
DELETE FROM students
WHERE user_id = 'MANUAL_1776881301547'
   OR id = 'MANUAL_1776881301547';

-- ============================================
-- STEP 3: VERIFY DELETION
-- ============================================
SELECT
  'DELETION COMPLETE' as status,
  COUNT(*) as remaining_student_records
FROM students
WHERE user_id = 'MANUAL_1776881301547'
   OR id = 'MANUAL_1776881301547';

-- Should return: 0 remaining_student_records
