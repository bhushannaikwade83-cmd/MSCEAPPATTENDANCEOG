-- =============================================================================
-- MANUAL SCRIPT: Remove ALL student / attendance photo references from Postgres
-- =============================================================================
-- WARNING: IRREVERSIBLE. Run only in Supabase SQL Editor (service_role / postgres).
--
-- This script does NOT delete B2 files. After running SQL, invoke Edge Function:
--   POST /functions/v1/clear-b2-storage
--   Header: Authorization: Bearer <valid Supabase JWT>
--
-- Optional institute scope: append AND institute_id = '<uuid>' to UPDATE students /
-- teacher_attendance; for attendance_in_out use AND institute_code = '<code>'.
-- =============================================================================

BEGIN;

-- 1) Student registration & face vectors
UPDATE public.students
SET
  face_photo_url = NULL,
  photo_url = NULL,
  registration_photo_path = NULL,
  face_embedding = NULL;

-- 2) Flat attendance row photos + JSON extras on attendance_in_out
UPDATE public.attendance_in_out
SET
  photo_url = NULL,
  photo_path = NULL,
  photo_file_id = NULL,
  additional = COALESCE(additional, '{}'::jsonb)
    #- 'entryPhoto'
    #- 'exitPhoto'
    #- 'entryPhotoPath'
    #- 'exitPhotoPath'
    #- 'entryPhotoFileId'
    #- 'exitPhotoFileId'
    #- 'photoUrl';

-- 3) teacher_attendance.payload (nested subjectSessions / lectures)
CREATE OR REPLACE FUNCTION public._strip_photo_keys_from_jsonb_obj(o jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(o, '{}'::jsonb)
    #- 'entryPhoto'
    #- 'exitPhoto'
    #- 'entryPhotoPath'
    #- 'exitPhotoPath'
    #- 'entryPhotoFileId'
    #- 'exitPhotoFileId'
    #- 'photoUrl'
    #- 'faceScanPhoto'
    #- 'faceScanPhotoPath'
    #- 'faceScanPhotoFileId';
$$;

CREATE OR REPLACE FUNCTION public.strip_teacher_attendance_payload_photos(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  result jsonb := public._strip_photo_keys_from_jsonb_obj(p);
  ss jsonb := result -> 'subjectSessions';
  lec jsonb := result -> 'lectures';
  new_ss jsonb := '{}'::jsonb;
  new_lec jsonb := '{}'::jsonb;
  k text;
  v jsonb;
BEGIN
  IF ss IS NOT NULL AND jsonb_typeof(ss) = 'object' THEN
    FOR k, v IN SELECT * FROM jsonb_each(ss)
    LOOP
      new_ss := new_ss || jsonb_build_object(k, public._strip_photo_keys_from_jsonb_obj(v));
    END LOOP;
    result := jsonb_set(result, '{subjectSessions}', new_ss, true);
  END IF;

  IF lec IS NOT NULL AND jsonb_typeof(lec) = 'object' THEN
    FOR k, v IN SELECT * FROM jsonb_each(lec)
    LOOP
      new_lec := new_lec || jsonb_build_object(k, public._strip_photo_keys_from_jsonb_obj(v));
    END LOOP;
    result := jsonb_set(result, '{lectures}', new_lec, true);
  END IF;

  RETURN result;
END;
$$;

UPDATE public.teacher_attendance
SET
  payload = public.strip_teacher_attendance_payload_photos(payload),
  verification_selfie = NULL;

DROP FUNCTION IF EXISTS public.strip_teacher_attendance_payload_photos(jsonb);
DROP FUNCTION IF EXISTS public._strip_photo_keys_from_jsonb_obj(jsonb);

-- 4) Signed URL cache table (skip if table was never created)
DO $$
BEGIN
  DELETE FROM public.cached_photo_urls;
EXCEPTION
  WHEN undefined_table THEN
    RAISE NOTICE 'cached_photo_urls missing — skipped';
END $$;

COMMIT;
