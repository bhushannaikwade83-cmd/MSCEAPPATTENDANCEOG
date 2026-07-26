-- Add 4 students to each of 4 dummy institutes (16 total)
-- Each institute gets students with 1, 2, 3, and 4 subjects

BEGIN;

-- First, add institute subjects for all 4 institutes

-- Institute 99099 subjects
INSERT INTO public.institute_subjects (institute_id, name, code) VALUES ('99099', 'GCC TBC MAR 30', 'GCC TBC MAR 30');
INSERT INTO public.institute_subjects (institute_id, name, code) VALUES ('99099', 'GCC TBC MAR 40', 'GCC TBC MAR 40');
INSERT INTO public.institute_subjects (institute_id, name, code) VALUES ('99099', 'GCC TBC ENG 40', 'GCC TBC ENG 40');
INSERT INTO public.institute_subjects (institute_id, name, code) VALUES ('99099', 'GCC TBC ENG 30', 'GCC TBC ENG 30');

-- Institute 99098 subjects
INSERT INTO public.institute_subjects (institute_id, name, code) VALUES ('99098', 'GCC TBC MAR 30', 'GCC TBC MAR 30');
INSERT INTO public.institute_subjects (institute_id, name, code) VALUES ('99098', 'GCC TBC MAR 40', 'GCC TBC MAR 40');
INSERT INTO public.institute_subjects (institute_id, name, code) VALUES ('99098', 'GCC TBC ENG 40', 'GCC TBC ENG 40');
INSERT INTO public.institute_subjects (institute_id, name, code) VALUES ('99098', 'GCC TBC ENG 30', 'GCC TBC ENG 30');

-- Institute 99097 subjects
INSERT INTO public.institute_subjects (institute_id, name, code) VALUES ('99097', 'GCC TBC MAR 30', 'GCC TBC MAR 30');
INSERT INTO public.institute_subjects (institute_id, name, code) VALUES ('99097', 'GCC TBC MAR 40', 'GCC TBC MAR 40');
INSERT INTO public.institute_subjects (institute_id, name, code) VALUES ('99097', 'GCC TBC ENG 40', 'GCC TBC ENG 40');
INSERT INTO public.institute_subjects (institute_id, name, code) VALUES ('99097', 'GCC TBC ENG 30', 'GCC TBC ENG 30');

-- Institute 12345 subjects
INSERT INTO public.institute_subjects (institute_id, name, code) VALUES ('12345', 'GCC TBC MAR 30', 'GCC TBC MAR 30');
INSERT INTO public.institute_subjects (institute_id, name, code) VALUES ('12345', 'GCC TBC MAR 40', 'GCC TBC MAR 40');
INSERT INTO public.institute_subjects (institute_id, name, code) VALUES ('12345', 'GCC TBC ENG 40', 'GCC TBC ENG 40');
INSERT INTO public.institute_subjects (institute_id, name, code) VALUES ('12345', 'GCC TBC ENG 30', 'GCC TBC ENG 30');

-- ========== INSTITUTE 99099 (dummy1) - 4 STUDENTS ==========

-- Student 1: 1 subject
INSERT INTO public.students (
  institute_id, name, sr_no, user_id, year, subject, subjects
) VALUES (
  '99099', 'dummy1', '1', '1', '1st', 'GCC TBC MAR 30', ARRAY['GCC TBC MAR 30']
);

-- Student 2: 2 subjects
INSERT INTO public.students (
  institute_id, name, sr_no, user_id, year, subject, subjects
) VALUES (
  '99099', 'dummy2', '2', '2', '1st', 'GCC TBC MAR 30, GCC TBC MAR 40', ARRAY['GCC TBC MAR 30', 'GCC TBC MAR 40']
);

-- Student 3: 3 subjects
INSERT INTO public.students (
  institute_id, name, sr_no, user_id, year, subject, subjects
) VALUES (
  '99099', 'dummy3', '3', '3', '1st', 'GCC TBC MAR 30, GCC TBC MAR 40, GCC TBC ENG 40', ARRAY['GCC TBC MAR 30', 'GCC TBC MAR 40', 'GCC TBC ENG 40']
);

-- Student 4: 4 subjects
INSERT INTO public.students (
  institute_id, name, sr_no, user_id, year, subject, subjects
) VALUES (
  '99099', 'dummy4', '4', '4', '1st', 'GCC TBC MAR 30, GCC TBC MAR 40, GCC TBC ENG 40, GCC TBC ENG 30', ARRAY['GCC TBC MAR 30', 'GCC TBC MAR 40', 'GCC TBC ENG 40', 'GCC TBC ENG 30']
);

-- ========== INSTITUTE 99098 (dummy2) - 4 STUDENTS ==========

-- Student 1: 1 subject
INSERT INTO public.students (
  institute_id, name, sr_no, user_id, year, subject, subjects
) VALUES (
  '99098', 'dummy1', '1', '1', '1st', 'GCC TBC MAR 30', ARRAY['GCC TBC MAR 30']
);

-- Student 2: 2 subjects
INSERT INTO public.students (
  institute_id, name, sr_no, user_id, year, subject, subjects
) VALUES (
  '99098', 'dummy2', '2', '2', '1st', 'GCC TBC MAR 30, GCC TBC MAR 40', ARRAY['GCC TBC MAR 30', 'GCC TBC MAR 40']
);

-- Student 3: 3 subjects
INSERT INTO public.students (
  institute_id, name, sr_no, user_id, year, subject, subjects
) VALUES (
  '99098', 'dummy3', '3', '3', '1st', 'GCC TBC MAR 30, GCC TBC MAR 40, GCC TBC ENG 40', ARRAY['GCC TBC MAR 30', 'GCC TBC MAR 40', 'GCC TBC ENG 40']
);

-- Student 4: 4 subjects
INSERT INTO public.students (
  institute_id, name, sr_no, user_id, year, subject, subjects
) VALUES (
  '99098', 'dummy4', '4', '4', '1st', 'GCC TBC MAR 30, GCC TBC MAR 40, GCC TBC ENG 40, GCC TBC ENG 30', ARRAY['GCC TBC MAR 30', 'GCC TBC MAR 40', 'GCC TBC ENG 40', 'GCC TBC ENG 30']
);

-- ========== INSTITUTE 99097 (dummy3) - 4 STUDENTS ==========

-- Student 1: 1 subject
INSERT INTO public.students (
  institute_id, name, sr_no, user_id, year, subject, subjects
) VALUES (
  '99097', 'dummy1', '1', '1', '1st', 'GCC TBC MAR 30', ARRAY['GCC TBC MAR 30']
);

-- Student 2: 2 subjects
INSERT INTO public.students (
  institute_id, name, sr_no, user_id, year, subject, subjects
) VALUES (
  '99097', 'dummy2', '2', '2', '1st', 'GCC TBC MAR 30, GCC TBC MAR 40', ARRAY['GCC TBC MAR 30', 'GCC TBC MAR 40']
);

-- Student 3: 3 subjects
INSERT INTO public.students (
  institute_id, name, sr_no, user_id, year, subject, subjects
) VALUES (
  '99097', 'dummy3', '3', '3', '1st', 'GCC TBC MAR 30, GCC TBC MAR 40, GCC TBC ENG 40', ARRAY['GCC TBC MAR 30', 'GCC TBC MAR 40', 'GCC TBC ENG 40']
);

-- Student 4: 4 subjects
INSERT INTO public.students (
  institute_id, name, sr_no, user_id, year, subject, subjects
) VALUES (
  '99097', 'dummy4', '4', '4', '1st', 'GCC TBC MAR 30, GCC TBC MAR 40, GCC TBC ENG 40, GCC TBC ENG 30', ARRAY['GCC TBC MAR 30', 'GCC TBC MAR 40', 'GCC TBC ENG 40', 'GCC TBC ENG 30']
);

-- ========== INSTITUTE 12345 (dummy4) - 4 STUDENTS ==========

-- Student 1: 1 subject
INSERT INTO public.students (
  institute_id, name, sr_no, user_id, year, subject, subjects
) VALUES (
  '12345', 'dummy1', '1', '1', '1st', 'GCC TBC MAR 30', ARRAY['GCC TBC MAR 30']
);

-- Student 2: 2 subjects
INSERT INTO public.students (
  institute_id, name, sr_no, user_id, year, subject, subjects
) VALUES (
  '12345', 'dummy2', '2', '2', '1st', 'GCC TBC MAR 30, GCC TBC MAR 40', ARRAY['GCC TBC MAR 30', 'GCC TBC MAR 40']
);

-- Student 3: 3 subjects
INSERT INTO public.students (
  institute_id, name, sr_no, user_id, year, subject, subjects
) VALUES (
  '12345', 'dummy3', '3', '3', '1st', 'GCC TBC MAR 30, GCC TBC MAR 40, GCC TBC ENG 40', ARRAY['GCC TBC MAR 30', 'GCC TBC MAR 40', 'GCC TBC ENG 40']
);

-- Student 4: 4 subjects
INSERT INTO public.students (
  institute_id, name, sr_no, user_id, year, subject, subjects
) VALUES (
  '12345', 'dummy4', '4', '4', '1st', 'GCC TBC MAR 30, GCC TBC MAR 40, GCC TBC ENG 40, GCC TBC ENG 30', ARRAY['GCC TBC MAR 30', 'GCC TBC MAR 40', 'GCC TBC ENG 40', 'GCC TBC ENG 30']
);

-- ========== VERIFICATION ==========

-- Verify: Count total students by institute
SELECT
  institute_id,
  COUNT(*) as student_count,
  ARRAY_AGG(DISTINCT name) as student_names
FROM public.students
WHERE institute_id IN ('99099', '99098', '99097', '12345')
GROUP BY institute_id
ORDER BY institute_id;

-- Verify: Show all students with their subjects
SELECT
  institute_id,
  sr_no,
  name,
  subjects,
  array_length(subjects, 1) as subject_count
FROM public.students
WHERE institute_id IN ('99099', '99098', '99097', '12345')
ORDER BY institute_id, sr_no;

-- Verify: Count subjects per institute
SELECT
  institute_id,
  COUNT(*) as subject_count
FROM public.institute_subjects
WHERE institute_id IN ('99099', '99098', '99097', '12345')
GROUP BY institute_id
ORDER BY institute_id;

COMMIT;
