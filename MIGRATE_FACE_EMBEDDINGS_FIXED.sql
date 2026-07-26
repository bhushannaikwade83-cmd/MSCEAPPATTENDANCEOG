-- ============================================
-- MIGRATE FACE EMBEDDINGS - FIXED VERSION
-- Handle face_embedding stored as double[] array
-- ============================================

-- STEP 1: Check actual data type
SELECT
  column_name,
  data_type,
  udt_name
FROM information_schema.columns
WHERE table_name = 'student_registrations'
  AND column_name = 'face_embedding';

-- STEP 2: Get sample data to see what we're working with
SELECT
  id,
  student_id,
  face_embedding,
  registration_photo_path
FROM student_registrations
WHERE student_id IN (SELECT id FROM students WHERE institute_id = '3001')
LIMIT 1;

-- ============================================
-- MIGRATION: Handle double[] array format
-- ============================================

UPDATE students s
SET
  face_embedding = jsonb_build_object(
    'version', 2,
    'embedding', sr.face_embedding,  -- Keep the double[] as-is, will be cast by app
    'modelVersion', 'mobilefacenet_tflite_v1',
    'qualityScore', 95.0
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

SELECT
  id,
  name,
  sr_no,
  face_embedding::text as embedding_preview,
  photo_url
FROM students
WHERE institute_id = '3001'
  AND face_embedding IS NOT NULL
ORDER BY sr_no
LIMIT 5;

-- Check if migration successful
SELECT
  COUNT(*) as students_with_embedding
FROM students
WHERE institute_id = '3001'
  AND face_embedding IS NOT NULL;
