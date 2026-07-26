-- Clear face enrollment for institute 43130
-- Run ONE block at a time in Supabase SQL Editor (do not select the whole file).

-- =============================================================================
-- STEP 1 — Preview only (run this first)
-- =============================================================================
WITH target_inst AS (
  SELECT id::text AS inst_id, institute_code
  FROM public.institutes
  WHERE btrim(institute_code) = '43130'
     OR id::text = '43130'
  LIMIT 1
)
SELECT
  ti.inst_id,
  ti.institute_code,
  count(*) AS total_students,
  count(s.face_embedding) AS has_face_embedding,
  count(s.face_photo_url) FILTER (
    WHERE s.face_photo_url IS NOT NULL AND btrim(s.face_photo_url) <> ''
  ) AS has_face_photo_url,
  count(s.photo_thumbnail) FILTER (
    WHERE s.photo_thumbnail IS NOT NULL AND btrim(s.photo_thumbnail) <> ''
  ) AS has_photo_thumbnail
FROM public.students s
CROSS JOIN target_inst ti
WHERE s.institute_id = ti.inst_id
   OR s.institute_id = ti.institute_code
GROUP BY ti.inst_id, ti.institute_code;

-- =============================================================================
-- STEP 2 — Apply clear (run ONLY this block after preview looks correct)
-- Copy from WITH through the semicolon; do not include STEP 1 above.
-- =============================================================================

-- WITH target_inst AS (
--   SELECT id::text AS inst_id, institute_code
--   FROM public.institutes
--   WHERE btrim(institute_code) = '43130'
--      OR id::text = '43130'
--   LIMIT 1
-- )
-- UPDATE public.students s
-- SET
--   face_embedding = NULL,
--   face_photo_url = NULL,
--   photo_thumbnail = NULL,
--   updated_at = timezone('utc', now())
-- FROM target_inst ti
-- WHERE s.institute_id = ti.inst_id
--    OR s.institute_id = ti.institute_code;
