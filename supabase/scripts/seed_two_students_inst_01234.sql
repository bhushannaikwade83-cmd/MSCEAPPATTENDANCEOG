-- Seed 2 students for institute id/code 01234 (run after migration 044).
-- Subjects: exactly the 8 strings from SubjectService.getPredefinedSubjects() (lib/services/subject_service.dart).
-- Also ensures institute_subjects rows exist for 01234 so the app catalog matches enrolled subjects.

INSERT INTO public.institutes (id, institute_code, name, is_active)
VALUES ('01234', '01234', 'Institute 01234', true)
ON CONFLICT (id) DO NOTHING;

-- App catalog for this institute (codes match SubjectService._generateSubjectCode)
INSERT INTO public.institute_subjects (institute_id, name, code, created_at)
SELECT '01234', v.name, v.code, now()
FROM (
  VALUES
    ('GCC-TBC ENGLISH 30 WPM', 'GCCTBC_ENGLISH_30_WPM'),
    ('GCC-TBC ENGLISH 40 WPM', 'GCCTBC_ENGLISH_40_WPM'),
    ('GCC-TBC ENGLISH 50 WPM', 'GCCTBC_ENGLISH_50_WPM'),
    ('GCC-TBC ENGLISH 60 WPM', 'GCCTBC_ENGLISH_60_WPM'),
    ('GCC-TBC MARATHI 30 WPM', 'GCCTBC_MARATHI_30_WPM'),
    ('GCC-TBC MARATHI 40 WPM', 'GCCTBC_MARATHI_40_WPM'),
    ('GCC-TBC HINDI 30 WPM', 'GCCTBC_HINDI_30_WPM'),
    ('GCC-TBC HINDI 40 WPM', 'GCCTBC_HINDI_40_WPM')
) AS v(name, code)
WHERE NOT EXISTS (
  SELECT 1
  FROM public.institute_subjects s
  WHERE s.institute_id = '01234'
    AND s.name = v.name
);

WITH peak AS (
  SELECT COALESCE(
    MAX(
      GREATEST(
        CASE WHEN btrim(COALESCE(s.sr_no, '')) ~ '^[0-9]+$' THEN btrim(s.sr_no)::int ELSE 0 END,
        CASE WHEN btrim(COALESCE(s.user_id, '')) ~ '^[0-9]+$' THEN btrim(s.user_id)::int ELSE 0 END
      )
    ),
    0
  ) AS n
  FROM public.students s
  WHERE s.institute_id = '01234'
),
app_subjects AS (
  SELECT ARRAY[
    'GCC-TBC ENGLISH 30 WPM',
    'GCC-TBC ENGLISH 40 WPM',
    'GCC-TBC ENGLISH 50 WPM',
    'GCC-TBC ENGLISH 60 WPM',
    'GCC-TBC MARATHI 30 WPM',
    'GCC-TBC MARATHI 40 WPM',
    'GCC-TBC HINDI 30 WPM',
    'GCC-TBC HINDI 40 WPM'
  ]::text[] AS subjects
),
ins AS (
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
    'MANUAL_' || floor(extract(epoch from now()) * 1000)::text || '_1',
    '01234',
    'MANUAL_' || floor(extract(epoch from now()) * 1000)::text || '_1',
    (peak.n + 1)::text,
    (peak.n + 1)::text,
    'Bhushan Ashok N',
    'Bhushan',
    'Ashok',
    'N',
    'FY',
    array_to_string(app_subjects.subjects, ', '),
    app_subjects.subjects,
    'student',
    'approved',
    false,
    now(),
    now()
  FROM peak
  CROSS JOIN app_subjects
  RETURNING id
),
ins2 AS (
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
    'MANUAL_' || floor(extract(epoch from now()) * 1000)::text || '_2',
    '01234',
    'MANUAL_' || floor(extract(epoch from now()) * 1000)::text || '_2',
    (peak.n + 2)::text,
    (peak.n + 2)::text,
    'San Prakash Rao',
    'San',
    'Prakash',
    'Rao',
    'FY',
    array_to_string(app_subjects.subjects, ', '),
    app_subjects.subjects,
    'student',
    'approved',
    false,
    now(),
    now()
  FROM peak
  CROSS JOIN app_subjects
  RETURNING id
)
UPDATE public.institutes i
SET student_count = sub.cnt,
    updated_at = now()
FROM (
  SELECT COUNT(*)::int AS cnt FROM public.students WHERE institute_id = '01234'
) sub
WHERE i.id = '01234';
