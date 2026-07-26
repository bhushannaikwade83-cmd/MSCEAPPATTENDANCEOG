-- ============================================
-- MIGRATE FACE EMBEDDINGS FROM student_registrations TO students
-- For existing students that were registered before the fix
-- ============================================

-- STEP 1: Check how many students need migration (no face_embedding in students table)
SELECT
  COUNT(*) as students_without_embedding,
  COUNT(CASE WHEN sr.id IS NOT NULL THEN 1 END) as students_with_registration_data
FROM students s
LEFT JOIN student_registrations sr ON s.id = sr.student_id
WHERE s.institute_id = '3001'
  AND (s.face_embedding IS NULL OR s.face_embedding::text = 'null');

-- STEP 2: List students that need face embedding sync
SELECT
  s.id,
  s.name,
  s.sr_no,
  sr.id as registration_id,
  sr.face_embedding IS NOT NULL as has_embedding
FROM students s
LEFT JOIN student_registrations sr ON s.id = sr.student_id
WHERE s.institute_id = '3001'
  AND (s.face_embedding IS NULL OR s.face_embedding::text = 'null')
ORDER BY s.sr_no;

-- ============================================
-- MIGRATION STEP: Update students with face_embedding from student_registrations
-- ============================================

-- Get latest registration for each student and create proper embedding structure
UPDATE students s
SET
  face_embedding = jsonb_build_object(
    'version', 2,
    'embedding', (sr.face_embedding::jsonb->>'embedding')::text,
    'modelVersion', 'mobilefacenet_tflite_v1',
    'qualityScore', COALESCE((sr.face_embedding::jsonb->>'qualityScore')::float, 95.0)
  ),
  photo_url = sr.registration_photo_path,
  face_photo_url = sr.registration_photo_path
FROM (
  SELECT DISTINCT ON (student_id)
    student_id,
    face_embedding,
    registration_photo_path
  FROM student_registrations
  WHERE student_id IN (SELECT id FROM students WHERE institute_id = '3001')
    AND face_embedding IS NOT NULL
  ORDER BY student_id, created_at DESC
) sr
WHERE s.id = sr.student_id
  AND s.institute_id = '3001';

-- ============================================
-- VERIFY MIGRATION
-- ============================================

-- Check how many got migrated
SELECT
  COUNT(*) as students_with_embedding,
  COUNT(CASE WHEN face_embedding::text != 'null' THEN 1 END) as valid_embeddings
FROM students
WHERE institute_id = '3001';

-- Show details of migrated students
SELECT
  id,
  name,
  sr_no,
  face_embedding::text as embedding_preview,
  photo_url
FROM students
WHERE institute_id = '3001'
  AND face_embedding IS NOT NULL
ORDER BY sr_no;

-- ============================================
-- VERIFY ATTENDANCE VERIFICATION WILL WORK
-- ============================================

-- Check embedding version
SELECT
  id,
  name,
  sr_no,
  face_embedding->>'version' as version,
  face_embedding->>'modelVersion' as model_version,
  face_embedding->>'qualityScore' as quality_score
FROM students
WHERE institute_id = '3001'
  AND face_embedding IS NOT NULL
LIMIT 5;
