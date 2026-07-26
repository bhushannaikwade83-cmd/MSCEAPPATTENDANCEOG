-- MERGE: Combine subjects from duplicate student registrations - FIXED VERSION
-- Keep the NEWEST record, merge all subjects, delete the OLDER ones
-- Corrected for better SQL compatibility

-- ========================================
-- STEP 0: First, identify duplicate students (CTE-based - more reliable)
-- ========================================

WITH duplicate_groups AS (
  SELECT
    s.institute_id,
    s.name,
    COUNT(*) as total_count
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
)
SELECT 'Duplicate groups found' as status, COUNT(*) as group_count
FROM duplicate_groups;

-- ========================================
-- STEP 1: See what will be merged (SAFE - Read Only)
-- ========================================

WITH duplicate_groups AS (
  SELECT
    s.institute_id,
    s.name,
    COUNT(*) as total_count
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
),
duplicate_details AS (
  SELECT
    dg.institute_id,
    dg.name,
    dg.total_count,
    COUNT(DISTINCT s.sr_no) as different_sr_nos,
    string_agg(DISTINCT s.sr_no::text, ', ' ORDER BY s.sr_no::text) as all_sr_nos,
    string_agg(s.id::text, ', ') as all_record_ids,
    MIN(s.created_at) as oldest_registered,
    MAX(s.created_at) as newest_registered
  FROM duplicate_groups dg
  JOIN public.students s ON dg.institute_id = s.institute_id AND dg.name = s.name
  GROUP BY dg.institute_id, dg.name, dg.total_count
)
SELECT
  i.institute_code,
  dd.name as student_name,
  dd.total_count as total_registrations,
  dd.different_sr_nos,
  dd.all_sr_nos,
  dd.all_record_ids,
  dd.oldest_registered,
  dd.newest_registered
FROM duplicate_details dd
JOIN public.institutes i ON dd.institute_id = i.id
ORDER BY i.institute_code, dd.name;

-- ========================================
-- STEP 2: See detailed records for each duplicate group (SAFE - Read Only)
-- ========================================

WITH duplicate_groups AS (
  SELECT
    s.institute_id,
    s.name
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
)
SELECT
  i.institute_code,
  s.name as student_name,
  s.sr_no,
  s.user_id,
  s.id as record_id,
  s.subjects as current_subjects,
  s.year,
  s.created_at,
  CASE WHEN s.face_photo_url IS NOT NULL THEN 'YES' ELSE 'NO' END as has_photo,
  CASE WHEN s.face_embedding IS NOT NULL THEN 'YES' ELSE 'NO' END as has_embedding
FROM duplicate_groups dg
JOIN public.students s ON dg.institute_id = s.institute_id AND dg.name = s.name
JOIN public.institutes i ON s.institute_id = i.id
ORDER BY i.institute_code, s.name, s.created_at;

-- ========================================
-- STEP 3: Backup all records before merging (RECOMMENDED)
-- ========================================

CREATE TABLE students_merge_backup_2024_12_16 AS
WITH duplicate_groups AS (
  SELECT
    s.institute_id,
    s.name
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
)
SELECT s.*
FROM duplicate_groups dg
JOIN public.students s ON dg.institute_id = s.institute_id AND dg.name = s.name;

-- Verify backup
SELECT COUNT(*) as total_records_backed_up FROM students_merge_backup_2024_12_16;

-- ========================================
-- STEP 4: Identify records to KEEP (one per duplicate group)
-- ========================================

WITH duplicate_groups AS (
  SELECT
    s.institute_id,
    s.name
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
),
records_with_priority AS (
  SELECT
    s.id,
    s.institute_id,
    s.name,
    s.sr_no,
    s.created_at,
    s.face_photo_url,
    s.face_embedding,
    s.subjects,
    ROW_NUMBER() OVER (
      PARTITION BY s.institute_id, s.name
      ORDER BY
        CASE WHEN s.face_photo_url IS NOT NULL THEN 0 ELSE 1 END ASC,
        CASE WHEN s.face_embedding IS NOT NULL THEN 0 ELSE 1 END ASC,
        s.created_at DESC
    ) as priority
  FROM duplicate_groups dg
  JOIN public.students s ON dg.institute_id = s.institute_id AND dg.name = s.name
)
SELECT
  'KEEP' as action,
  i.institute_code,
  rwp.name,
  rwp.sr_no,
  rwp.id as record_id,
  rwp.created_at,
  CASE WHEN rwp.face_photo_url IS NOT NULL THEN 'YES' ELSE 'NO' END as has_photo,
  CASE WHEN rwp.face_embedding IS NOT NULL THEN 'YES' ELSE 'NO' END as has_embedding,
  rwp.subjects as current_subjects
FROM records_with_priority rwp
JOIN public.institutes i ON rwp.institute_id = i.id
WHERE rwp.priority = 1
ORDER BY i.institute_code, rwp.name;

-- ========================================
-- STEP 5: Get merged subjects for each group (SAFE - Read Only)
-- ========================================

WITH duplicate_groups AS (
  SELECT
    s.institute_id,
    s.name
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
),
all_subjects_combined AS (
  SELECT
    dg.institute_id,
    dg.name,
    array_agg(DISTINCT subject_elem ORDER BY subject_elem) as merged_subjects
  FROM duplicate_groups dg
  JOIN public.students s ON dg.institute_id = s.institute_id AND dg.name = s.name,
  LATERAL jsonb_array_elements_text(COALESCE(s.subjects, '[]'::jsonb)) as subject_elem
  GROUP BY dg.institute_id, dg.name
)
SELECT
  i.institute_code,
  merged.name as student_name,
  merged.merged_subjects as new_merged_subjects
FROM all_subjects_combined merged
JOIN public.institutes i ON merged.institute_id = i.id
ORDER BY i.institute_code, merged.name;

-- ========================================
-- STEP 6: MERGE - Update with merged subjects and delete duplicates
-- ========================================

-- Step 6a: Identify which record to KEEP and which to DELETE for each group
WITH duplicate_groups AS (
  SELECT
    s.institute_id,
    s.name
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
),
records_ranked AS (
  SELECT
    s.id,
    s.institute_id,
    s.name,
    ROW_NUMBER() OVER (
      PARTITION BY s.institute_id, s.name
      ORDER BY
        CASE WHEN s.face_photo_url IS NOT NULL THEN 0 ELSE 1 END ASC,
        CASE WHEN s.face_embedding IS NOT NULL THEN 0 ELSE 1 END ASC,
        s.created_at DESC
    ) as priority
  FROM duplicate_groups dg
  JOIN public.students s ON dg.institute_id = s.institute_id AND dg.name = s.name
),
merged_subjects_per_group AS (
  SELECT
    rr.institute_id,
    rr.name,
    (SELECT to_jsonb(array_agg(DISTINCT elem ORDER BY elem))
     FROM (
       SELECT DISTINCT jsonb_array_elements_text(COALESCE(s.subjects, '[]'::jsonb)) as elem
       FROM duplicate_groups dg
       JOIN public.students s ON dg.institute_id = s.institute_id AND dg.name = s.name
       WHERE dg.institute_id = rr.institute_id AND dg.name = rr.name
     ) t
    ) as all_merged_subjects
  FROM records_ranked rr
  WHERE rr.priority = 1
  GROUP BY rr.institute_id, rr.name
)
-- Step 6b: Update the KEPT record with merged subjects
UPDATE public.students s
SET subjects = msg.all_merged_subjects
FROM merged_subjects_per_group msg
WHERE s.institute_id = msg.institute_id
  AND s.name = msg.name
  AND s.id IN (
    SELECT id FROM records_ranked WHERE priority = 1
  );

-- Step 6c: DELETE duplicate records (all except priority 1)
DELETE FROM public.students
WHERE (institute_id, name) IN (
  SELECT institute_id, name FROM (
    SELECT s.institute_id, s.name
    FROM public.students s
    GROUP BY s.institute_id, s.name
    HAVING COUNT(*) > 1
  ) dups
)
AND id NOT IN (
  SELECT id FROM (
    SELECT
      s.id,
      s.institute_id,
      s.name,
      ROW_NUMBER() OVER (
        PARTITION BY s.institute_id, s.name
        ORDER BY
          CASE WHEN s.face_photo_url IS NOT NULL THEN 0 ELSE 1 END ASC,
          CASE WHEN s.face_embedding IS NOT NULL THEN 0 ELSE 1 END ASC,
          s.created_at DESC
      ) as priority
    FROM public.students s
    WHERE (s.institute_id, s.name) IN (
      SELECT s2.institute_id, s2.name
      FROM public.students s2
      GROUP BY s2.institute_id, s2.name
      HAVING COUNT(*) > 1
    )
  ) ranked
  WHERE priority = 1
);

-- ========================================
-- STEP 7: Verify merge was successful (SAFE - Read Only)
-- ========================================

-- Check that no duplicates remain
WITH duplicate_groups AS (
  SELECT
    s.institute_id,
    s.name,
    COUNT(*) as remaining_count
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
)
SELECT
  i.institute_code,
  dg.name,
  dg.remaining_count,
  s.sr_no,
  s.subjects
FROM duplicate_groups dg
JOIN public.students s ON dg.institute_id = s.institute_id AND dg.name = s.name
JOIN public.institutes i ON dg.institute_id = i.id
ORDER BY i.institute_code, dg.name;

-- If result is empty (no rows), merge was successful!

-- ========================================
-- STEP 8: Final statistics
-- ========================================

SELECT
  'Merge Complete' as status,
  COUNT(*) as total_student_records_remaining
FROM public.students;

-- Compare backup vs current
SELECT
  'Before merge' as stage,
  COUNT(*) as total_records
FROM students_merge_backup_2024_12_16
UNION ALL
SELECT
  'After merge' as stage,
  COUNT(*) as total_records
FROM public.students;

-- ========================================
-- Optional: Cleanup
-- ========================================

-- When done and verified, optionally drop backup:
-- DROP TABLE students_merge_backup_2024_12_16;
