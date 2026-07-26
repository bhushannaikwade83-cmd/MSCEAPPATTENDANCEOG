-- ============================================
-- Add missing columns to students table
-- ============================================

-- Add semester column (varchar, nullable)
ALTER TABLE students
ADD COLUMN IF NOT EXISTS semester VARCHAR(50);

-- Add semester_name column (varchar, nullable)
ALTER TABLE students
ADD COLUMN IF NOT EXISTS semester_name VARCHAR(100);

-- Add status column (varchar, default 'approved')
ALTER TABLE students
ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'approved';

-- Add index for status column (for filtering)
CREATE INDEX IF NOT EXISTS idx_students_status ON students(status);
CREATE INDEX IF NOT EXISTS idx_students_semester ON students(semester);

-- Verify columns were added
SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'students'
  AND column_name IN ('semester', 'semester_name', 'status')
ORDER BY ordinal_position;
