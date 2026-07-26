-- Cleanup script: Complete reset for students 3 and 4
-- Institute: 12345 ONLY
-- Clears: Face embedding, photos, entry/exit times, and all attendance marks
-- Run this in your Supabase SQL Editor

-- ========================================
-- 1. Clear face registration from students table
-- ========================================

UPDATE students
SET
  face_embedding = NULL,
  face_photo_url = NULL,
  updated_at = NOW()
WHERE sr_no = '3'
  AND institute_id = '12345';

UPDATE students
SET
  face_embedding = NULL,
  face_photo_url = NULL,
  updated_at = NOW()
WHERE sr_no = '4'
  AND institute_id = '12345';

-- ========================================
-- 2. Delete all attendance_in_out records (entry/exit photos, times, marks)
-- ========================================

DELETE FROM attendance_in_out
WHERE sr_no = '3'
  AND institute_code = '12345';

DELETE FROM attendance_in_out
WHERE sr_no = '4'
  AND institute_code = '12345';

-- ========================================
-- 3. Delete all attendance records
-- ========================================

DELETE FROM attendance
WHERE student_id IN (
  SELECT id FROM students
  WHERE sr_no IN ('3', '4')
    AND institute_id = '12345'
);

-- ========================================
-- 4. Verify the cleanup
-- ========================================

-- Check students face data cleared
SELECT sr_no, name,
       face_embedding IS NOT NULL as has_face_embedding,
       face_photo_url IS NOT NULL as has_face_photo
FROM students
WHERE sr_no IN ('3', '4')
  AND institute_id = '12345';

-- Check attendance_in_out records deleted
SELECT COUNT(*) as remaining_attendance_in_out_records
FROM attendance_in_out
WHERE sr_no IN ('3', '4')
  AND institute_code = '12345';

-- Check attendance records deleted
SELECT COUNT(*) as remaining_attendance_records
FROM attendance
WHERE student_id IN (
  SELECT id FROM students
  WHERE sr_no IN ('3', '4')
    AND institute_id = '12345'
);
