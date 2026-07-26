-- Drop semester tracking for students and attendance rows (GCC-TBC flow uses subjects only).

DROP INDEX IF EXISTS public.idx_students_semester;

ALTER TABLE public.students
  DROP COLUMN IF EXISTS semester;

ALTER TABLE public.students
  DROP COLUMN IF EXISTS semester_name;

ALTER TABLE public.attendance_in_out
  DROP COLUMN IF EXISTS semester_code;
