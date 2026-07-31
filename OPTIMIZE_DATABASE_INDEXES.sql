-- =====================================================
-- OPTIMIZE SUPABASE INDEXES FOR FAST QUERIES
-- =====================================================
-- Add these indexes to speed up attendance marking from 30-50s to <100ms

-- PRIMARY: Fast lookup by institute + registration status
CREATE INDEX IF NOT EXISTS idx_students_institute_status
  ON students(institute_id, face_registration_status)
  WHERE face_registration_status = 'registered';

-- SECONDARY: Fast lookup by institute alone
CREATE INDEX IF NOT EXISTS idx_students_institute
  ON students(institute_id);

-- TERTIARY: Fast lookup by sr_no (student roll number)
CREATE INDEX IF NOT EXISTS idx_students_sr_no
  ON students(sr_no);

-- OPTIONAL: If filtering by registration time
CREATE INDEX IF NOT EXISTS idx_students_registered_at
  ON students(face_registered_at DESC)
  WHERE face_registered_at IS NOT NULL;

-- =====================================================
-- RUN THESE IN SUPABASE SQL EDITOR:
-- 1. Go to Supabase dashboard
-- 2. Click "SQL Editor"
-- 3. Click "New Query"
-- 4. Paste each CREATE INDEX statement above
-- 5. Execute
-- =====================================================

-- VERIFY INDEXES ARE CREATED:
-- SELECT indexname FROM pg_indexes WHERE tablename = 'students';
