-- Remove contact fields from students only (profiles / admin data unchanged).
DROP INDEX IF EXISTS idx_students_phone;

ALTER TABLE public.students DROP COLUMN IF EXISTS phone_number;
ALTER TABLE public.students DROP COLUMN IF EXISTS email;
