-- Create daily attendance table for entry/exit tracking
CREATE TABLE IF NOT EXISTS attendance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- From students table
  student_id UUID NOT NULL,
  institute_id TEXT NOT NULL,
  sr_no TEXT NOT NULL,
  student_name TEXT NOT NULL,

  attendance_date DATE NOT NULL,

  -- Entry details
  entry_time TIMESTAMP,
  entry_photo_url TEXT,
  entry_embedding TEXT, -- 512-D ArcFace embedding (JSON array)
  entry_confidence FLOAT,

  -- Exit details
  exit_time TIMESTAMP,
  exit_photo_url TEXT,
  exit_embedding TEXT, -- 512-D ArcFace embedding (JSON array)
  exit_confidence FLOAT,

  -- Status
  status TEXT DEFAULT 'present', -- 'present', 'absent', 'late', 'left-early'
  is_verified BOOLEAN DEFAULT FALSE,

  -- Timestamps
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  -- Constraints
  FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
  UNIQUE(sr_no, institute_id, attendance_date)  -- One entry per sr_no per day per institute
);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_attendance_date ON attendance(attendance_date);
CREATE INDEX IF NOT EXISTS idx_attendance_institute ON attendance(institute_id);
CREATE INDEX IF NOT EXISTS idx_attendance_student ON attendance(student_id);
CREATE INDEX IF NOT EXISTS idx_attendance_status ON attendance(status);
