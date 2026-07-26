-- Investigate why student management screen shows students twice
-- Even though database has 0 duplicates

-- 1. Find students with SAME NAME but DIFFERENT SR_NO (not caught as duplicates)
SELECT
  i.institute_code,
  i.name as institute_name,
  s.name as student_name,
  s.sr_no,
  s.user_id,
  s.subjects,
  s.id,
  s.created_at
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE (i.institute_code = '23101' OR i.name LIKE '%Prima%')  -- Change institute code as needed
ORDER BY s.name, s.sr_no;

-- 2. Find students with SAME NAME but DIFFERENT USER_ID
SELECT
  i.institute_code,
  s.name,
  COUNT(DISTINCT s.user_id) as different_user_ids,
  string_agg(DISTINCT s.user_id, ', ') as user_ids,
  COUNT(DISTINCT s.sr_no) as different_sr_nos,
  string_agg(DISTINCT s.sr_no, ', ') as sr_nos,
  COUNT(*) as total_records
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.institute_code, s.name
HAVING COUNT(*) > 1
ORDER BY total_records DESC;

-- 3. Look for partial name matches that might show as duplicates
-- (e.g., "Bhushan" and "Bhushan Ashok Naikwade" both show in search)
SELECT
  i.institute_code,
  COUNT(*) as student_count,
  string_agg(DISTINCT s.name, ' | ' ORDER BY s.name) as names
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE LOWER(s.name) LIKE '%bhushan%'  -- Change name as needed
GROUP BY i.institute_code;

-- 4. Check if subjects are stored as separate records somehow
SELECT
  i.institute_code,
  s.sr_no,
  s.name,
  s.subjects,
  s.subject as single_subject,
  COUNT(*) as how_many_with_same_sr_no_name
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE i.institute_code = '23101'  -- Change as needed
GROUP BY i.institute_code, s.sr_no, s.name, s.subjects, s.subject
ORDER BY s.sr_no, s.name;

-- 5. Check if attendance_in_out records are being shown as students
SELECT
  'attendance_in_out' as source,
  COUNT(*) as count,
  COUNT(DISTINCT student_id) as unique_students,
  COUNT(DISTINCT sr_no) as unique_sr_nos
FROM public.attendance_in_out
WHERE institute_code = '23101';  -- Change as needed

-- 6. Compare student table vs attendance_in_out
SELECT
  'students table' as source,
  COUNT(*) as total_records,
  COUNT(DISTINCT sr_no) as unique_sr_nos,
  COUNT(DISTINCT name) as unique_names
FROM public.students
WHERE institute_id = (SELECT id FROM public.institutes WHERE institute_code = '23101');

-- 7. Find students where sr_no is NULL or empty (might show duplicate)
SELECT
  i.institute_code,
  s.name,
  s.sr_no,
  s.user_id,
  s.id,
  'SR_NO IS EMPTY' as issue
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE (s.sr_no IS NULL OR s.sr_no = '')
ORDER BY i.institute_code, s.name;

-- 8. Find students with special characters or spaces in name
-- (might cause duplicate display due to trimming)
SELECT
  i.institute_code,
  s.name,
  LENGTH(s.name) as name_length,
  s.sr_no,
  s.subjects,
  COUNT(*) as count
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.institute_code, s.name, s.sr_no, s.subjects
HAVING COUNT(*) > 1
ORDER BY i.institute_code;

-- 9. Check the actual query used by student_management_screen
-- (based on code: id, name, user_id, sr_no, year, subject, subjects, face_photo_url, face_embedding)
SELECT
  id,
  name,
  user_id,
  sr_no,
  year,
  subject,
  subjects,
  face_photo_url,
  CASE WHEN face_embedding IS NOT NULL THEN 'YES' ELSE 'NO' END as has_embedding
FROM public.students
WHERE institute_id = (SELECT id FROM public.institutes WHERE institute_code = '23101')
ORDER BY name, sr_no;

-- 10. Check if there are multiple institute records with same name
-- (Admin creating institutes with same name)
SELECT
  institute_code,
  name,
  id,
  COUNT(*) as duplicates
FROM public.institutes
GROUP BY name
HAVING COUNT(*) > 1
ORDER BY name;

-- 11. Look for students that might have whitespace issues
SELECT
  i.institute_code,
  '|' || s.name || '|' as student_name_with_pipes,
  s.sr_no,
  s.subjects,
  COUNT(*) as duplicates
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.institute_code, s.name, s.sr_no, s.subjects
HAVING COUNT(*) > 1
ORDER BY i.institute_code;

-- 12. Final diagnostic: Show exactly what student_management_screen would fetch
SELECT
  s.id,
  s.name,
  s.user_id,
  s.sr_no,
  s.year,
  s.subject,
  s.subjects,
  CASE WHEN s.face_photo_url IS NOT NULL THEN 'HAS PHOTO' ELSE 'NO PHOTO' END as photo_status,
  s.created_at,
  ROW_NUMBER() OVER (PARTITION BY s.sr_no, s.name ORDER BY s.created_at) as occurrence
FROM public.students s
WHERE s.institute_id = (SELECT id FROM public.institutes WHERE institute_code = '23101')
ORDER BY s.name, s.sr_no, s.created_at;
