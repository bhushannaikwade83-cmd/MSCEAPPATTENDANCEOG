-- =============================================================================
-- Name filter: Bhushan Ashok Naikwade (case-insensitive; extras allowed between parts).
-- All three parts must appear in students.name.
-- Keeps the student row, face_registration, registrations — wipes daily marks so
-- you can test entry/exit again from scratch.
--
-- WHY MATCHING MATTERS
-- attendance_in_out: HierarchicalAttendanceService maps institute id →
--   institutes.institute_code when inserting, so aio.institute_code is often the
--   **code**, not institutes.id — students.institute_id is the **id**.
-- teacher_attendance: student_id may be roll (admin) OR students.id UUID (teacher
--   screen / legacy student self-flow). Rows are deleted if institute matches rolls,
--   OR globally if student_id equals the student's id (UUID is unique).
--
-- Run in Supabase Dashboard → SQL Editor. If deletes affect 0 rows but step 5
-- shows orphaned rows: use the service_role key / postgres role — RLS policies
-- (especially teacher_attendance_delete_coder_only) may block deletes for your user.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) SEE who matches (runs first; confirm rows)
-- ---------------------------------------------------------------------------
SELECT
  id AS student_uuid,
  name,
  institute_id,
  user_id AS roll_login,
  sr_no,
  ( SELECT i.institute_code
    FROM institutes i
    WHERE i.id = students.institute_id
  ) AS institute_code_snapshot
FROM students
WHERE name ILIKE '%bhushan%'
  AND name ILIKE '%ashok%'
  AND name ILIKE '%naikwade%'
ORDER BY institute_id, name;

-- ---------------------------------------------------------------------------
-- 2) ROW COUNTS BEFORE DELETE (optional)
-- ---------------------------------------------------------------------------
WITH targ AS (
  SELECT id, institute_id, user_id, sr_no
  FROM students
  WHERE name ILIKE '%bhushan%'
    AND name ILIKE '%ashok%'
    AND name ILIKE '%naikwade%'
)
SELECT
  'teacher_attendance' AS tbl,
  count(*) AS n
FROM teacher_attendance ta
WHERE EXISTS (
      SELECT 1
      FROM targ s
      WHERE ta.institute_id = s.institute_id
        AND trim(both FROM coalesce(ta.student_id, '')) <> ''
        AND (
             trim(both FROM ta.student_id) = trim(both FROM coalesce(s.user_id, ''))
          OR trim(both FROM ta.student_id) = trim(both FROM coalesce(s.sr_no, ''))
          OR trim(both FROM ta.student_id) = trim(both FROM s.id::text)
        )
    )
   OR EXISTS (
      SELECT 1
      FROM targ s
      WHERE trim(both FROM coalesce(ta.student_id, '')) = trim(both FROM s.id::text)
    )
UNION ALL
SELECT
  'attendance_in_out',
  count(*)
FROM attendance_in_out aio
WHERE EXISTS (
    SELECT 1
    FROM targ s
    JOIN public.institutes i ON i.id = s.institute_id
    WHERE trim(both FROM aio.student_id) = trim(both FROM s.id::text)
      AND (
           trim(both FROM aio.institute_code) = trim(both FROM s.institute_id)
        OR (
             coalesce(nullif(trim(both FROM i.institute_code), ''), '') <> ''
             AND trim(both FROM aio.institute_code) =
                 trim(both FROM i.institute_code)
           )
      )
);

-- ---------------------------------------------------------------------------
-- 3) DELETE (order does not heavily matter; no FK from student → these)
-- ---------------------------------------------------------------------------

WITH targ AS (
  SELECT id, institute_id, user_id, sr_no
  FROM students
  WHERE name ILIKE '%bhushan%'
    AND name ILIKE '%ashok%'
    AND name ILIKE '%naikwade%'
)
DELETE FROM teacher_attendance ta
WHERE EXISTS (
    SELECT 1
    FROM targ s
    WHERE ta.institute_id = s.institute_id
      AND trim(both FROM coalesce(ta.student_id, '')) <> ''
      AND (
           trim(both FROM ta.student_id) = trim(both FROM coalesce(s.user_id, ''))
        OR trim(both FROM ta.student_id) = trim(both FROM coalesce(s.sr_no, ''))
        OR trim(both FROM ta.student_id) = trim(both FROM s.id::text)
      )
  )
   OR EXISTS (
    SELECT 1
    FROM targ s
    WHERE trim(both FROM coalesce(ta.student_id, '')) =
          trim(both FROM s.id::text)
  );

WITH targ AS (
  SELECT id, institute_id
  FROM students
  WHERE name ILIKE '%bhushan%'
    AND name ILIKE '%ashok%'
    AND name ILIKE '%naikwade%'
)
DELETE FROM attendance_in_out aio
USING targ s
JOIN public.institutes i ON i.id = s.institute_id
WHERE trim(both FROM aio.student_id) = trim(both FROM s.id::text)
  AND (
       trim(both FROM aio.institute_code) = trim(both FROM s.institute_id)
    OR (
         coalesce(nullif(trim(both FROM i.institute_code), ''), '') <> ''
         AND trim(both FROM aio.institute_code) =
             trim(both FROM i.institute_code)
       )
  );

-- Older / parallel table (only deletes if table exists — safe on minimal schemas).
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'attendance_records'
  ) THEN
    DELETE FROM attendance_records ar
    WHERE ar.student_id IN (
      SELECT id
      FROM students
      WHERE name ILIKE '%bhushan%'
        AND name ILIKE '%ashok%'
        AND name ILIKE '%naikwade%'
    )
    OR ar.student_id::text IN (
      SELECT trim(both FROM coalesce(user_id, ''))
      FROM students
      WHERE name ILIKE '%bhushan%'
        AND name ILIKE '%ashok%'
        AND name ILIKE '%naikwade%'
        AND coalesce(user_id, '') <> ''
    )
    OR ar.student_id::text IN (
      SELECT trim(both FROM coalesce(sr_no, ''))
      FROM students
      WHERE name ILIKE '%bhushan%'
        AND name ILIKE '%ashok%'
        AND name ILIKE '%naikwade%'
        AND coalesce(sr_no, '') <> ''
    );
    -- Legacy text keys sometimes store auth/profile id alongside students.id:
    -- If deletes no rows, inspect: SELECT * FROM attendance_records ar
    -- JOIN students s ON ... WHERE s.name ILIKE '%bhushan%' ...
  END IF;
END
$body$;

-- ---------------------------------------------------------------------------
-- 4) VERIFY ZERO (counts should all be 0)
-- ---------------------------------------------------------------------------
WITH targ AS (
  SELECT id, institute_id, user_id, sr_no
  FROM students
  WHERE name ILIKE '%bhushan%'
    AND name ILIKE '%ashok%'
    AND name ILIKE '%naikwade%'
)
SELECT
  'teacher_attendance' AS tbl,
  count(*) AS remaining
FROM teacher_attendance ta
WHERE EXISTS (
      SELECT 1
      FROM targ s
      WHERE ta.institute_id = s.institute_id
        AND trim(both FROM coalesce(ta.student_id, '')) <> ''
        AND (
             trim(both FROM ta.student_id) = trim(both FROM coalesce(s.user_id, ''))
          OR trim(both FROM ta.student_id) = trim(both FROM coalesce(s.sr_no, ''))
          OR trim(both FROM ta.student_id) = trim(both FROM s.id::text)
        )
    )
   OR EXISTS (
      SELECT 1
      FROM targ s
      WHERE trim(both FROM coalesce(ta.student_id, '')) =
            trim(both FROM s.id::text)
    )
UNION ALL
SELECT
  'attendance_in_out',
  count(*)
FROM attendance_in_out aio
WHERE EXISTS (
    SELECT 1
    FROM targ s
    JOIN public.institutes i ON i.id = s.institute_id
    WHERE trim(both FROM aio.student_id) = trim(both FROM s.id::text)
      AND (
           trim(both FROM aio.institute_code) = trim(both FROM s.institute_id)
        OR (
             coalesce(nullif(trim(both FROM i.institute_code), ''), '') <> ''
             AND trim(both FROM aio.institute_code) =
                 trim(both FROM i.institute_code)
           )
      )
);

-- ---------------------------------------------------------------------------
-- 5) DIAGNOSTIC: any rows left for this student id / roll (manual check)
-- ---------------------------------------------------------------------------
WITH targ AS (
  SELECT id::text AS sid,
    institute_id::text AS iid,
    trim(both FROM coalesce(user_id, '')) AS uid,
    trim(both FROM coalesce(sr_no, '')) AS sno
  FROM students
  WHERE name ILIKE '%bhushan%'
    AND name ILIKE '%ashok%'
    AND name ILIKE '%naikwade%'
)
SELECT 'teacher_attendance' AS src, ta.id, ta.institute_id, ta.student_id, ta.date::text
FROM teacher_attendance ta, targ t
WHERE ta.student_id IS NOT DISTINCT FROM t.sid
   OR trim(both FROM coalesce(ta.student_id, '')) IN (t.uid, t.sno)
UNION ALL
SELECT 'attendance_in_out', aio.id::text, aio.institute_code, aio.student_id,
  aio.attendance_date::text
FROM attendance_in_out aio, targ t
WHERE trim(both FROM aio.student_id) = t.sid;
