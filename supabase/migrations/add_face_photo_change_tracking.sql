-- Add face photo change tracking columns to students table
ALTER TABLE students ADD COLUMN IF NOT EXISTS face_photo_change_count INT DEFAULT 0;
ALTER TABLE students ADD COLUMN IF NOT EXISTS face_photo_change_disabled BOOLEAN DEFAULT FALSE;

-- Create index for quick lookups
CREATE INDEX IF NOT EXISTS idx_students_face_photo_change_count
ON students(id, face_photo_change_count, face_photo_change_disabled);

-- Backfill existing students with default values (0 uses, not disabled)
UPDATE students
SET face_photo_change_count = 0, face_photo_change_disabled = FALSE
WHERE face_photo_change_count IS NULL OR face_photo_change_disabled IS NULL;
