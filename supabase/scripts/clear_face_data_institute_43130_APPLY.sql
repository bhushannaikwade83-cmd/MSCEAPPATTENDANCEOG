-- STEP 2 — Run this alone after preview in clear_face_data_institute_43130.sql

WITH target_inst AS (
  SELECT id::text AS inst_id, institute_code
  FROM public.institutes
  WHERE btrim(institute_code) = '43130'
     OR id::text = '43130'
  LIMIT 1
)
UPDATE public.students s
SET
  face_embedding = NULL,
  face_photo_url = NULL,
  photo_thumbnail = NULL,
  updated_at = timezone('utc', now())
FROM target_inst ti
WHERE s.institute_id = ti.inst_id
   OR s.institute_id = ti.institute_code;
