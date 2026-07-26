-- MERGE DUPLICATE STUDENTS - SIMPLE STEP-BY-STEP APPROACH
-- Run each section separately, one at a time
-- This version is easier to debug and understand

-- ========================================
-- STEP 1: Find all duplicate student groups
-- ========================================

SELECT
  i.institute_code,
  s.name as student_name,
  COUNT(*) as duplicate_count,
  string_agg(DISTINCT s.id::text, ' | ') as record_ids
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.institute_code, i.id, s.institute_id, s.name
HAVING COUNT(*) > 1
ORDER BY i.institute_code, s.name;

-- ========================================
-- STEP 2: For ONE duplicate group, see all records
-- ========================================

-- CHANGE THIS to the student name you want to work with:
SELECT
  s.id,
  s.sr_no,
  s.name,
  s.subjects,
  s.year,
  s.created_at,
  s.face_photo_url,
  s.face_embedding
FROM public.students s
WHERE s.name = 'AASHISH BALARAM GAIKAR'  -- CHANGE THIS NAME
  AND s.institute_id = (
    SELECT id FROM public.institutes WHERE institute_code = '11063'  -- CHANGE THIS CODE
  )
ORDER BY s.created_at;

-- ========================================
-- STEP 3: Create backup of all duplicates
-- ========================================

CREATE TABLE students_merge_backup AS
SELECT s.*
FROM public.students s
WHERE (s.institute_id, s.name) IN (
  SELECT s2.institute_id, s2.name
  FROM public.students s2
  GROUP BY s2.institute_id, s2.name
  HAVING COUNT(*) > 1
);

SELECT COUNT(*) FROM students_merge_backup;

-- ========================================
-- STEP 4: For ONE duplicate group, get merged subjects
-- ========================================

-- Example: Get all subjects for AASHISH BALARAM GAIKAR in institute 11063
SELECT
  array_agg(DISTINCT elem ORDER BY elem) as merged_subjects
FROM (
  SELECT DISTINCT jsonb_array_elements_text(s.subjects) as elem
  FROM public.students s
  WHERE s.name = 'AASHISH BALARAM GAIKAR'  -- CHANGE THIS
    AND s.institute_id = (SELECT id FROM public.institutes WHERE institute_code = '11063')
) subjects_list;

-- ========================================
-- STEP 5: Identify which record to KEEP (the one with photo/newest)
-- ========================================

SELECT
  s.id,
  s.sr_no,
  s.name,
  s.created_at,
  CASE WHEN s.face_photo_url IS NOT NULL THEN 'YES' ELSE 'NO' END as has_photo,
  ROW_NUMBER() OVER (
    PARTITION BY s.institute_id, s.name
    ORDER BY
      CASE WHEN s.face_photo_url IS NOT NULL THEN 0 ELSE 1 END,
      CASE WHEN s.face_embedding IS NOT NULL THEN 0 ELSE 1 END,
      s.created_at DESC
  ) as priority_to_keep
FROM public.students s
WHERE s.name = 'AASHISH BALARAM GAIKAR'  -- CHANGE THIS
  AND s.institute_id = (SELECT id FROM public.institutes WHERE institute_code = '11063')  -- CHANGE THIS
ORDER BY s.created_at;

-- Record with priority_to_keep = 1 is the one to KEEP

-- ========================================
-- STEP 6: UPDATE the record to KEEP with merged subjects
-- ========================================

-- For AASHISH BALARAM GAIKAR in 11063:
-- Priority 1 = xyz-789-uvw (the one with photo, newest)
-- Merged subjects = ["Biology", "Chemistry", "Math", "Physics"]

UPDATE public.students
SET subjects = '["Biology", "Chemistry", "Math", "Physics"]'::jsonb
WHERE id = 'xyz-789-uvw'  -- CHANGE THIS to the ID of the record to keep
  AND name = 'AASHISH BALARAM GAIKAR';  -- CHANGE THIS

-- Verify the update:
SELECT id, name, subjects FROM public.students WHERE id = 'xyz-789-uvw';

-- ========================================
-- STEP 7: DELETE the old duplicate records
-- ========================================

-- For AASHISH BALARAM GAIKAR, delete all EXCEPT xyz-789-uvw

DELETE FROM public.students
WHERE name = 'AASHISH BALARAM GAIKAR'  -- CHANGE THIS
  AND institute_id = (SELECT id FROM public.institutes WHERE institute_code = '11063')  -- CHANGE THIS
  AND id != 'xyz-789-uvw';  -- CHANGE THIS to the ID to keep

-- Verify deletion:
SELECT COUNT(*) FROM public.students WHERE name = 'AASHISH BALARAM GAIKAR';
-- Should return: 1

-- ========================================
-- STEP 8: Repeat for all other duplicate groups
-- ========================================

-- Go back to STEP 2, pick the next duplicate student from STEP 1
-- Follow STEPS 3-7 for each one
--
-- Pattern:
-- 1. Get list from STEP 1
-- 2. For each student name:
--    a. STEP 2: See all records
--    b. STEP 4: Get merged subjects
--    c. STEP 5: Find which to keep (priority 1)
--    d. STEP 6: UPDATE with merged subjects
--    e. STEP 7: DELETE duplicates

-- ========================================
-- STEP 9: Verify all merges complete
-- ========================================

-- Check if any duplicates remain
SELECT
  i.institute_code,
  s.name,
  COUNT(*) as remaining_count
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.institute_code, i.id, s.institute_id, s.name
HAVING COUNT(*) > 1;

-- If this returns NO ROWS, all duplicates are merged!

-- ========================================
-- FINAL STATS
-- ========================================

SELECT
  'Before merge' as stage,
  COUNT(*) as total_records
FROM students_merge_backup
UNION ALL
SELECT
  'After merge' as stage,
  COUNT(*) as total_records
FROM public.students;

-- ========================================
-- Optional: Cleanup backup when verified
-- ========================================
-- DROP TABLE students_merge_backup;
