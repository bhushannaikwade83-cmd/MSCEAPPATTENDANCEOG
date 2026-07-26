-- ============================================
-- VERIFY DATABASE CLEANUP
-- Check which columns remain in each table
-- ============================================

-- ============================================
-- 1. STUDENTS TABLE - Show all columns
-- ============================================

SELECT
  'STUDENTS TABLE' as table_name,
  COUNT(*) as total_columns,
  STRING_AGG(column_name, ', ' ORDER BY ordinal_position) as all_columns
FROM information_schema.columns
WHERE table_name = 'students';

-- List each column with type
SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'students'
ORDER BY ordinal_position;

-- ============================================
-- 2. ATTENDANCE_RECORDS TABLE - Show all columns
-- ============================================

SELECT
  'ATTENDANCE_RECORDS TABLE' as table_name,
  COUNT(*) as total_columns,
  STRING_AGG(column_name, ', ' ORDER BY ordinal_position) as all_columns
FROM information_schema.columns
WHERE table_name = 'attendance_records';

-- List each column with type
SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'attendance_records'
ORDER BY ordinal_position;

-- ============================================
-- 3. ATTENDANCE_IN_OUT TABLE - Show all columns
-- ============================================

SELECT
  'ATTENDANCE_IN_OUT TABLE' as table_name,
  COUNT(*) as total_columns,
  STRING_AGG(column_name, ', ' ORDER BY ordinal_position) as all_columns
FROM information_schema.columns
WHERE table_name = 'attendance_in_out';

-- List each column with type
SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'attendance_in_out'
ORDER BY ordinal_position;

-- ============================================
-- 4. STUDENT_REGISTRATIONS TABLE - Show all columns
-- ============================================

SELECT
  'STUDENT_REGISTRATIONS TABLE' as table_name,
  COUNT(*) as total_columns,
  STRING_AGG(column_name, ', ' ORDER BY ordinal_position) as all_columns
FROM information_schema.columns
WHERE table_name = 'student_registrations';

-- List each column with type
SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'student_registrations'
ORDER BY ordinal_position;

-- ============================================
-- VERIFY UNUSED COLUMNS ARE GONE
-- ============================================

-- Check if any removed columns still exist
SELECT 'REMOVED COLUMNS CHECK' as check_type;

SELECT
  CASE
    WHEN COUNT(*) = 0 THEN '✅ REMOVED - roll_number'
    ELSE '❌ NOT REMOVED - roll_number'
  END as status
FROM information_schema.columns
WHERE table_name = 'students' AND column_name = 'roll_number';

SELECT
  CASE
    WHEN COUNT(*) = 0 THEN '✅ REMOVED - contact'
    ELSE '❌ NOT REMOVED - contact'
  END as status
FROM information_schema.columns
WHERE table_name = 'students' AND column_name = 'contact';

SELECT
  CASE
    WHEN COUNT(*) = 0 THEN '✅ REMOVED - latitude'
    ELSE '❌ NOT REMOVED - latitude'
  END as status
FROM information_schema.columns
WHERE table_name = 'attendance_records' AND column_name = 'latitude';

SELECT
  CASE
    WHEN COUNT(*) = 0 THEN '✅ REMOVED - entry_latitude'
    ELSE '❌ NOT REMOVED - entry_latitude'
  END as status
FROM information_schema.columns
WHERE table_name = 'attendance_in_out' AND column_name = 'entry_latitude';

SELECT
  CASE
    WHEN COUNT(*) = 0 THEN '✅ REMOVED - embedding_version'
    ELSE '❌ NOT REMOVED - embedding_version'
  END as status
FROM information_schema.columns
WHERE table_name = 'student_registrations' AND column_name = 'embedding_version';

-- ============================================
-- DATA INTEGRITY CHECK
-- ============================================

SELECT 'DATA INTEGRITY' as check_type;

SELECT
  COUNT(*) as total_students,
  COUNT(CASE WHEN face_embedding IS NOT NULL THEN 1 END) as with_embedding,
  COUNT(CASE WHEN photo_url IS NOT NULL THEN 1 END) as with_photo,
  COUNT(CASE WHEN sr_no IS NOT NULL THEN 1 END) as with_sr_no
FROM students;

SELECT
  COUNT(*) as total_attendance,
  COUNT(CASE WHEN status IS NOT NULL THEN 1 END) as with_status,
  COUNT(CASE WHEN embedding_similarity IS NOT NULL THEN 1 END) as with_similarity
FROM attendance_records;

SELECT
  COUNT(*) as total_in_out,
  COUNT(CASE WHEN entry_time IS NOT NULL THEN 1 END) as with_entry,
  COUNT(CASE WHEN exit_time IS NOT NULL THEN 1 END) as with_exit
FROM attendance_in_out;

SELECT
  COUNT(*) as total_registrations,
  COUNT(CASE WHEN face_embedding IS NOT NULL THEN 1 END) as with_embedding,
  COUNT(CASE WHEN registration_photo_path IS NOT NULL THEN 1 END) as with_photo
FROM student_registrations;

-- ============================================
-- FINAL SUMMARY
-- ============================================

SELECT 'CLEANUP SUMMARY' as section;

SELECT
  'students' as table_name,
  (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'students') as total_columns,
  '12 columns (ideal)' as expected
UNION ALL
SELECT
  'attendance_records' as table_name,
  (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'attendance_records') as total_columns,
  '10 columns (ideal)' as expected
UNION ALL
SELECT
  'attendance_in_out' as table_name,
  (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'attendance_in_out') as total_columns,
  '11 columns (ideal)' as expected
UNION ALL
SELECT
  'student_registrations' as table_name,
  (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'student_registrations') as total_columns,
  '5 columns (ideal)' as expected;
