-- Migration: Add UNIQUE constraint on (institute_id, sr_no)
-- Purpose: Prevent duplicate SR-NOs within the same institute

-- Step 1: Remove duplicates (keep only latest registration)
-- Find duplicates
WITH duplicates AS (
  SELECT
    institute_id,
    sr_no,
    COUNT(*) as count,
    array_agg(id ORDER BY created_at DESC) as ids
  FROM public.students
  WHERE sr_no IS NOT NULL
    AND sr_no != ''
  GROUP BY institute_id, sr_no
  HAVING COUNT(*) > 1
)
-- Delete older duplicates, keep latest
DELETE FROM public.students
WHERE id IN (
  SELECT id
  FROM (
    SELECT
      UNNEST(ids[2:]) as id
    FROM duplicates
  ) x
);

-- Step 2: Drop old index if exists
DROP INDEX IF EXISTS idx_students_institute_sr_no;

-- Step 3: Add UNIQUE constraint
-- Constraint: (institute_id, sr_no) must be unique
-- NULL values are allowed and don't violate uniqueness
ALTER TABLE public.students
ADD CONSTRAINT unique_institute_sr_no UNIQUE (institute_id, sr_no)
WHERE sr_no IS NOT NULL AND sr_no != '';

-- Step 4: Create index for performance
CREATE INDEX idx_students_institute_sr_no
ON public.students (institute_id, sr_no)
WHERE sr_no IS NOT NULL AND sr_no != '';

-- Step 5: Log completion
COMMENT ON CONSTRAINT unique_institute_sr_no ON public.students IS
'Prevents duplicate SR-NOs within the same institute. Allows NULL/empty values.';
