-- One student + one subject for a sandbox institute: **123456** (preferred), else **01234**, else **1234**.
--
-- Matches **id OR institute_code** (UUID id + numeric code is OK).
-- If none of those institutes exist yet, inserts id/code **123456** (seed row).
-- Run in Supabase SQL Editor as **postgres** / service role.

INSERT INTO public.institutes (id, institute_code, name, is_active)
SELECT '123456', '123456', 'Institute 123456 (seed)', true
WHERE NOT EXISTS (
  SELECT 1
  FROM public.institutes i
  WHERE lower(btrim(coalesce(i.institute_code, ''))) IN ('123456', '01234', '1234')
    OR btrim(i.id) IN ('123456', '01234', '1234')
);

WITH
ranked_inst AS (
  SELECT
    i.id AS institute_id,
    CASE
      WHEN btrim(i.id) = '123456' OR lower(btrim(coalesce(i.institute_code, ''))) = '123456' THEN 0
      WHEN btrim(i.id) = '01234' OR lower(btrim(coalesce(i.institute_code, ''))) = '01234' THEN 1
      WHEN btrim(i.id) = '1234' OR lower(btrim(coalesce(i.institute_code, ''))) = '1234' THEN 2
      ELSE 9
    END AS ord
  FROM public.institutes i
  WHERE btrim(i.id) IN ('123456', '01234', '1234')
    OR lower(btrim(coalesce(i.institute_code, ''))) IN ('123456', '01234', '1234')
),
inst_pick AS (
  SELECT institute_id
  FROM ranked_inst
  WHERE ord < 9
  ORDER BY ord
  LIMIT 1
),
subj AS (
  SELECT
    'GCC-TBC MARATHI 30 WPM'::text AS name,
    'GCCTBC_MARATHI_30_WPM'::text AS code
),
ins_subj AS (
  INSERT INTO public.institute_subjects (institute_id, name, code, created_at)
  SELECT ip.institute_id, s.name, s.code, now()
  FROM inst_pick ip
  CROSS JOIN subj s
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.institute_subjects x
    WHERE x.institute_id = ip.institute_id
      AND x.name = s.name
  )
  RETURNING institute_id
),
peak AS (
  SELECT
    ip.institute_id,
    COALESCE(
      MAX(
        GREATEST(
          CASE WHEN btrim(COALESCE(st.sr_no, '')) ~ '^[0-9]+$'
            THEN btrim(st.sr_no)::int
            ELSE 0 END,
          CASE WHEN btrim(COALESCE(st.user_id, '')) ~ '^[0-9]+$'
            THEN btrim(st.user_id)::int
            ELSE 0 END
        )
      ),
      0
    ) AS n
  FROM inst_pick ip
  LEFT JOIN public.students st ON st.institute_id = ip.institute_id
  GROUP BY ip.institute_id
),
new_stu AS (
  INSERT INTO public.students (
    id,
    institute_id,
    uid,
    user_id,
    sr_no,
    name,
    first_name,
    middle_name,
    last_name,
    year,
    subject,
    subjects,
    role,
    status,
    has_device,
    created_at,
    updated_at
  )
  SELECT
    ('MANUAL_SEED_' || replace(gen_random_uuid()::text, '-', ''))::text,
    ip.institute_id,
    ('MANUAL_SEED_' || replace(gen_random_uuid()::text, '-', ''))::text,
    (pk.n + 1)::text,
    (pk.n + 1)::text,
    'Demo Student One',
    'Demo',
    'Test',
    'One',
    'FY',
    s.name,
    ARRAY[s.name]::text[],
    'student',
    'approved',
    false,
    now(),
    now()
  FROM inst_pick ip
  CROSS JOIN subj s
  CROSS JOIN peak pk
  WHERE pk.institute_id = ip.institute_id
  RETURNING id, institute_id, name, sr_no
)
UPDATE public.institutes i
SET
  student_count = (SELECT COUNT(*)::int FROM public.students st WHERE st.institute_id = i.id),
  updated_at = now()
FROM inst_pick ip
WHERE i.id = ip.institute_id;

-- Sanity check: latest “Demo Student One” on the institute we picked (123456 > 01234 > 1234).
WITH ranked_inst AS (
  SELECT i.id AS institute_id,
    CASE
      WHEN btrim(i.id) = '123456' OR lower(btrim(coalesce(i.institute_code, ''))) = '123456' THEN 0
      WHEN btrim(i.id) = '01234' OR lower(btrim(coalesce(i.institute_code, ''))) = '01234' THEN 1
      WHEN btrim(i.id) = '1234' OR lower(btrim(coalesce(i.institute_code, ''))) = '1234' THEN 2
      ELSE 9
    END AS ord
  FROM public.institutes i
  WHERE btrim(i.id) IN ('123456', '01234', '1234')
    OR lower(btrim(coalesce(i.institute_code, ''))) IN ('123456', '01234', '1234')
),
inst_pick AS (
  SELECT institute_id FROM ranked_inst WHERE ord < 9 ORDER BY ord LIMIT 1
)
SELECT s.id AS student_id, s.institute_id, i.institute_code, s.name, s.sr_no, s.subjects,
  'If student_id is null here, INSERT did not run.' AS hint
FROM inst_pick ip
JOIN public.institutes i ON i.id = ip.institute_id
LEFT JOIN LATERAL (
  SELECT *
  FROM public.students st
  WHERE st.institute_id = ip.institute_id
    AND st.name = 'Demo Student One'
  ORDER BY st.created_at DESC
  LIMIT 1
) s ON true;
