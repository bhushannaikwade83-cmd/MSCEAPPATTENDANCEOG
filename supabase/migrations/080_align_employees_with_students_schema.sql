-- Align employees table schema with students table for institute 90999
-- This ensures both tables have compatible columns for the unified management screen

-- Add missing name columns (decompose 'name' if needed for consistency)
ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS fname text,
  ADD COLUMN IF NOT EXISTS lname text,
  ADD COLUMN IF NOT EXISTS mname text,
  ADD COLUMN IF NOT EXISTS form_serial_no text,
  ADD COLUMN IF NOT EXISTS mother_nm text,
  ADD COLUMN IF NOT EXISTS ctcd text,
  ADD COLUMN IF NOT EXISTS identy_no text;

-- Add face embedding variants (keep single embedding as primary, add variants if available)
ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS face_embedding_front jsonb,
  ADD COLUMN IF NOT EXISTS face_embedding_left jsonb,
  ADD COLUMN IF NOT EXISTS face_embedding_right jsonb,
  ADD COLUMN IF NOT EXISTS face_registered_at timestamptz,
  ADD COLUMN IF NOT EXISTS face_registration_status text DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS is_face_real boolean,
  ADD COLUMN IF NOT EXISTS original_face_photo_url text,
  ADD COLUMN IF NOT EXISTS original_registration_photo_path text,
  ADD COLUMN IF NOT EXISTS face_photo_changed_at timestamptz;

-- Add subject columns (may not be used for employees, but for schema compatibility)
ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS sub1 text,
  ADD COLUMN IF NOT EXISTS sub2 text,
  ADD COLUMN IF NOT EXISTS sub3 text,
  ADD COLUMN IF NOT EXISTS sub4 text,
  ADD COLUMN IF NOT EXISTS sub5 text,
  ADD COLUMN IF NOT EXISTS sub6 text,
  ADD COLUMN IF NOT EXISTS sub7 text,
  ADD COLUMN IF NOT EXISTS sub8 text;

-- Ensure sr_no is properly set (or use e_code as sr_no for lookups)
ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS sr_no text;

-- Copy face_embedding to face_embedding_front for multi-angle support
UPDATE public.employees
  SET face_embedding_front = face_embedding
  WHERE face_embedding IS NOT NULL
    AND face_embedding_front IS NULL;

-- Set face_registration_status to 'registered' for employees with existing face_embedding
UPDATE public.employees
  SET face_registration_status = 'registered'
  WHERE face_embedding IS NOT NULL
    AND face_registration_status = 'pending';

-- Copy sr_no from e_code if not set
UPDATE public.employees
  SET sr_no = e_code
  WHERE sr_no IS NULL
    AND e_code IS NOT NULL;

-- Add comments for clarity
COMMENT ON COLUMN public.employees.fname IS 'First name (from name field if not split)';
COMMENT ON COLUMN public.employees.lname IS 'Last name';
COMMENT ON COLUMN public.employees.face_embedding_front IS 'Face embedding from front-facing photo';
COMMENT ON COLUMN public.employees.face_embedding_left IS 'Face embedding from left-facing photo (if available)';
COMMENT ON COLUMN public.employees.face_embedding_right IS 'Face embedding from right-facing photo (if available)';
COMMENT ON COLUMN public.employees.face_registration_status IS 'Status: pending, registered, failed';
COMMENT ON COLUMN public.employees.sr_no IS 'Serial number (mapped from e_code for attendance lookups)';
