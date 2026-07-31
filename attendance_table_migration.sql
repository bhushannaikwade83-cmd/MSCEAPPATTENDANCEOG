-- Create daily attendance table for entry/exit tracking
-- SEPARATE records for entry and exit
CREATE TABLE IF NOT EXISTS attendance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- From students table
  student_id UUID NOT NULL,
  institute_id TEXT NOT NULL,
  sr_no TEXT NOT NULL,
  student_name TEXT NOT NULL,

  -- Date
  attendance_date DATE NOT NULL,

  -- Record type: 'entry' or 'exit'
  record_type TEXT NOT NULL,  -- 'entry' or 'exit'

  -- Time & Photo
  marked_time TIMESTAMP NOT NULL,
  photo_url TEXT,

  -- 512-D Embedding
  embedding TEXT NOT NULL,  -- JSON array of 512 floats
  similarity_score FLOAT,  -- Cosine similarity (0-1)

  -- Status
  status TEXT DEFAULT 'present',  -- 'present', 'absent', 'late'
  is_verified BOOLEAN DEFAULT FALSE,

  -- Timestamps
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  -- Constraints
  FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
  UNIQUE(sr_no, institute_id, attendance_date, record_type)  -- One entry + One exit per student per day
);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_attendance_date ON attendance(attendance_date);
CREATE INDEX IF NOT EXISTS idx_attendance_institute ON attendance(institute_id);
CREATE INDEX IF NOT EXISTS idx_attendance_student ON attendance(student_id);
CREATE INDEX IF NOT EXISTS idx_attendance_status ON attendance(status);
