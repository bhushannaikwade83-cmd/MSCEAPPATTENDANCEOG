-- Migration: Add credited hours columns to attendance_in_out table
-- Date: 2026-05-08
-- Purpose: Store calculated credited hours directly in database instead of calculating on-the-fly

-- Add new columns to attendance_in_out table
ALTER TABLE attendance_in_out
ADD COLUMN IF NOT EXISTS credited_hours NUMERIC(5,2) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS hours_calculation_note TEXT DEFAULT NULL,
ADD COLUMN IF NOT EXISTS hours_calculated_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

-- Create index on credited_hours for faster report queries
CREATE INDEX IF NOT EXISTS idx_attendance_in_out_credited_hours
ON attendance_in_out(credited_hours);

-- Create index on student_id and attendance_date for report filtering
CREATE INDEX IF NOT EXISTS idx_attendance_in_out_student_date
ON attendance_in_out(student_id, attendance_date);

-- Create index on attendance_date for daily summaries
CREATE INDEX IF NOT EXISTS idx_attendance_in_out_attendance_date
ON attendance_in_out(attendance_date);

-- Add comment for clarity
COMMENT ON COLUMN attendance_in_out.credited_hours
IS 'Credited hours calculated based on attendance policy (within window, after window, or no exit)';

COMMENT ON COLUMN attendance_in_out.hours_calculation_note
IS 'Note explaining how hours were calculated (e.g., "Within 4h window", "After window - fixed 2.5h", "No exit by midnight - fixed 1h")';

COMMENT ON COLUMN attendance_in_out.hours_calculated_at
IS 'Timestamp when hours were calculated and stored';
