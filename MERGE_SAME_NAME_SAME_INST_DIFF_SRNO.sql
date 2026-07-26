-- MERGE: Students with SAME NAME + SAME INSTITUTE but DIFFERENT SR_NO and DIFFERENT SUBJECTS
-- These are the true duplicates from multiple registrations

-- ========================================
-- QUERY 1: Find all students matching this pattern
-- ========================================

SELECT
  i.institute_code,
  i.name as institute_name,
  s.name as student_name,
  COUNT(*) as duplicate_count,
  string_agg(DISTINCT s.sr_no::text, ', ' ORDER BY s.sr_no::text) as all_sr_nos,
  COUNT(DISTINCT s.sr_no) as different_sr_nos,
  COUNT(DISTINCT s.subjects::text) as different_subject_sets,
  string_agg(DISTINCT s.subjects::text, ' | ' ORDER BY s.subjects::text) as all_subject_combos,
  string_agg(DISTINCT s.user_id, ', ') as user_ids,
  string_agg(s.id::text, ' | ') as all_record_ids
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.id, i.institute_code, i.name, s.institute_id, s.name
HAVING COUNT(*) > 1
  AND COUNT(DISTINCT s.sr_no) > 1
  AND COUNT(DISTINCT s.subjects::text) > 1
ORDER BY i.institute_code, s.name;

-- ========================================
-- QUERY 2: Count how many students match this pattern
-- ========================================

SELECT
  COUNT(*) as total_groups_to_merge,
  SUM(duplicate_count) as total_duplicate_records
FROM (
  SELECT
    COUNT(*) as duplicate_count
  FROM public.students s
  JOIN public.institutes i ON s.institute_id = i.id
  GROUP BY i.id, s.institute_id, s.name
  HAVING COUNT(*) > 1
    AND COUNT(DISTINCT s.sr_no) > 1
    AND COUNT(DISTINCT s.subjects::text) > 1
) subq;

-- ========================================
-- QUERY 3: For ONE student group, see all records side by side
-- ========================================

-- CHANGE institute_code and student_name below
SELECT
  s.id as record_id,
  s.sr_no,
  s.user_id,
  s.subjects,
  s.year,
  s.created_at,
  CASE WHEN s.face_photo_url IS NOT NULL THEN 'YES' ELSE 'NO' END as has_photo,
  CASE WHEN s.face_embedding IS NOT NULL THEN 'YES' ELSE 'NO' END as has_embedding,
  ROW_NUMBER() OVER (
    ORDER BY
      CASE WHEN s.face_photo_url IS NOT NULL THEN 0 ELSE 1 END ASC,
      CASE WHEN s.face_embedding IS NOT NULL THEN 0 ELSE 1 END ASC,
      s.created_at DESC
  ) as priority_to_keep
FROM public.students s
WHERE s.institute_id = (SELECT id FROM public.institutes WHERE institute_code = '11063')  -- CHANGE
  AND s.name = 'AASHISH BALARAM GAIKAR'  -- CHANGE
ORDER BY s.created_at;

-- Record with priority_to_keep = 1 is the BEST one to keep

-- ========================================
-- QUERY 4: Create backup of all these duplicates
-- ========================================

CREATE TABLE merge_backup_same_name_same_inst AS
SELECT s.*
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE (s.institute_id, s.name) IN (
  SELECT s2.institute_id, s2.name
  FROM public.students s2
  GROUP BY s2.institute_id, s2.name
  HAVING COUNT(*) > 1
    AND COUNT(DISTINCT s2.sr_no) > 1
    AND COUNT(DISTINCT s2.subjects::text) > 1
);

SELECT COUNT(*) as backup_record_count FROM merge_backup_same_name_same_inst;

-- ========================================
-- QUERY 5: Get merged subjects for ALL groups (preview)
-- ========================================

WITH dups AS (
  SELECT
    s.institute_id,
    s.name
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
    AND COUNT(DISTINCT s.sr_no) > 1
    AND COUNT(DISTINCT s.subjects::text) > 1
)
SELECT
  i.institute_code,
  d.name as student_name,
  array_agg(DISTINCT elem ORDER BY elem) as merged_subjects
FROM dups d
JOIN public.institutes i ON d.institute_id = i.id
JOIN public.students s ON d.institute_id = s.institute_id AND d.name = s.name,
LATERAL jsonb_array_elements_text(COALESCE(s.subjects, '[]'::jsonb)) as elem
GROUP BY i.id, i.institute_code, d.institute_id, d.name
ORDER BY i.institute_code, d.name;

-- ========================================
-- QUERY 6: Merge - UPDATE each kept record with merged subjects
-- ========================================

WITH dups_to_merge AS (
  SELECT
    s.institute_id,
    s.name
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
    AND COUNT(DISTINCT s.sr_no) > 1
    AND COUNT(DISTINCT s.subjects::text) > 1
),
records_with_priority AS (
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
  FROM dups_to_merge dtm
  JOIN public.students s ON dtm.institute_id = s.institute_id AND dtm.name = s.name
),
merged_subjects_per_group AS (
  SELECT
    rwp.institute_id,
    rwp.name,
    array_agg(DISTINCT elem ORDER BY elem) as all_subjects
  FROM records_with_priority rwp
  JOIN public.students s ON rwp.institute_id = s.institute_id AND rwp.name = s.name,
  LATERAL jsonb_array_elements_text(COALESCE(s.subjects, '[]'::jsonb)) as elem
  WHERE rwp.priority = 1
  GROUP BY rwp.institute_id, rwp.name
)
UPDATE public.students s
SET subjects = to_jsonb(msg.all_subjects)
FROM merged_subjects_per_group msg
WHERE s.institute_id = msg.institute_id
  AND s.name = msg.name
  AND s.id IN (
    SELECT id FROM records_with_priority WHERE priority = 1
  );

-- ========================================
-- QUERY 7: Delete old duplicate records
-- ========================================

WITH dups_to_merge AS (
  SELECT
    s.institute_id,
    s.name
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
    AND COUNT(DISTINCT s.sr_no) > 1
    AND COUNT(DISTINCT s.subjects::text) > 1
),
records_with_priority AS (
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
  FROM dups_to_merge dtm
  JOIN public.students s ON dtm.institute_id = s.institute_id AND dtm.name = s.name
)
DELETE FROM public.students s
WHERE (s.institute_id, s.name) IN (
  SELECT institute_id, name FROM dups_to_merge
)
AND s.id NOT IN (
  SELECT id FROM records_with_priority WHERE priority = 1
);

-- ========================================
-- QUERY 8: Verify merge was successful
-- ========================================

-- Should return NO ROWS if all merged successfully
SELECT
  i.institute_code,
  s.name as student_name,
  COUNT(*) as remaining_count
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.id, i.institute_code, s.institute_id, s.name
HAVING COUNT(*) > 1
  AND COUNT(DISTINCT s.sr_no) > 1
  AND COUNT(DISTINCT s.subjects::text) > 1
ORDER BY i.institute_code, s.name;

-- ========================================
-- QUERY 9: Show results - before vs after
-- ========================================

SELECT
  'Before merge' as stage,
  COUNT(*) as total_records
FROM merge_backup_same_name_same_inst
UNION ALL
SELECT
  'After merge' as stage,
  COUNT(*) as total_records
FROM public.students;

-- ========================================
-- QUERY 10: Show merged results
-- ========================================

-- See ONE merged student (change values)
SELECT
  i.institute_code,
  s.name,
  s.sr_no,
  s.id,
  s.subjects as merged_subjects,
  s.created_at
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE i.institute_code = '11063'  -- CHANGE
  AND s.name = 'AASHISH BALARAM GAIKAR'  -- CHANGE
ORDER BY s.created_at;

-- ========================================
-- Optional: Cleanup backup when verified
-- ========================================
-- DROP TABLE merge_backup_same_name_same_inst;
