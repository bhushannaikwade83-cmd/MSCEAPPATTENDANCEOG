-- Migration: Subject-based allotted hours policy for attendance table
-- Date: 2026-08-01
--
-- Rules:
--  1 subject  = 1.0h
--  2 subjects = 2.5h
--  3 subjects = 3.5h
--  4 subjects = 4.5h
--  5+ subjects = subjectCount + 0.5h
--
-- students.allotted_hours auto-recomputes whenever sub1..sub8 change.
-- attendance.allotted_target_hr is frozen onto the ENTRY row at insert time
-- (so later subject changes don't retroactively alter past records).
-- attendance.attendance_alloted_hr / attendance.remark are computed on the
-- EXIT row: actual duration if within target, else floor(target) + 'EXIT LATE MARKED'.
-- A nightly pg_cron job closes entries with no same-day exit: 1.0h fixed +
-- 'NOT EXITED BUT ENTRY'.

-- ============================================================
-- STEP 1: allotted_hours column on students
-- ============================================================
ALTER TABLE students
ADD COLUMN IF NOT EXISTS allotted_hours NUMERIC(4,2) DEFAULT NULL;

-- ============================================================
-- STEP 2: formula function (subject count -> allotted hours)
-- ============================================================
CREATE OR REPLACE FUNCTION compute_student_allotted_hours(
  p_sub1 text, p_sub2 text, p_sub3 text, p_sub4 text,
  p_sub5 text, p_sub6 text, p_sub7 text, p_sub8 text
) RETURNS numeric AS $$
DECLARE
  v_count integer := 0;
BEGIN
  IF p_sub1 IS NOT NULL AND trim(p_sub1) <> '' THEN v_count := v_count + 1; END IF;
  IF p_sub2 IS NOT NULL AND trim(p_sub2) <> '' THEN v_count := v_count + 1; END IF;
  IF p_sub3 IS NOT NULL AND trim(p_sub3) <> '' THEN v_count := v_count + 1; END IF;
  IF p_sub4 IS NOT NULL AND trim(p_sub4) <> '' THEN v_count := v_count + 1; END IF;
  IF p_sub5 IS NOT NULL AND trim(p_sub5) <> '' THEN v_count := v_count + 1; END IF;
  IF p_sub6 IS NOT NULL AND trim(p_sub6) <> '' THEN v_count := v_count + 1; END IF;
  IF p_sub7 IS NOT NULL AND trim(p_sub7) <> '' THEN v_count := v_count + 1; END IF;
  IF p_sub8 IS NOT NULL AND trim(p_sub8) <> '' THEN v_count := v_count + 1; END IF;

  IF v_count <= 1 THEN
    RETURN 1.0;
  END IF;
  RETURN v_count + 0.5;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================
-- STEP 3: trigger on students -> auto-update allotted_hours
--         whenever sub1..sub8 change (insert or update)
-- ============================================================
CREATE OR REPLACE FUNCTION students_set_allotted_hours()
RETURNS TRIGGER AS $$
BEGIN
  NEW.allotted_hours := compute_student_allotted_hours(
    NEW.sub1, NEW.sub2, NEW.sub3, NEW.sub4,
    NEW.sub5, NEW.sub6, NEW.sub7, NEW.sub8
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_students_set_allotted_hours ON students;
CREATE TRIGGER trg_students_set_allotted_hours
BEFORE INSERT OR UPDATE OF sub1, sub2, sub3, sub4, sub5, sub6, sub7, sub8
ON students
FOR EACH ROW
EXECUTE FUNCTION students_set_allotted_hours();

-- ============================================================
-- STEP 4: backfill allotted_hours for existing students
-- ============================================================
UPDATE students
SET allotted_hours = compute_student_allotted_hours(sub1, sub2, sub3, sub4, sub5, sub6, sub7, sub8);

-- ============================================================
-- STEP 5: new columns on attendance
-- ============================================================
ALTER TABLE attendance
ADD COLUMN IF NOT EXISTS allotted_target_hr NUMERIC(4,2) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS attendance_alloted_hr TEXT DEFAULT NULL,
ADD COLUMN IF NOT EXISTS remark TEXT DEFAULT NULL;

-- ============================================================
-- STEP 6: trigger on attendance ENTRY insert -> freeze target hours
--         from students.allotted_hours (drives the countdown timer)
-- ============================================================
CREATE OR REPLACE FUNCTION attendance_set_entry_target()
RETURNS TRIGGER AS $$
DECLARE
  v_allotted numeric;
BEGIN
  IF NEW.record_type = 'entry' THEN
    SELECT allotted_hours INTO v_allotted
    FROM students
    WHERE sr_no = NEW.sr_no AND institute_id = NEW.institute_id
    LIMIT 1;

    NEW.allotted_target_hr := COALESCE(v_allotted, 1.0);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_attendance_set_entry_target ON attendance;
CREATE TRIGGER trg_attendance_set_entry_target
BEFORE INSERT ON attendance
FOR EACH ROW
WHEN (NEW.record_type = 'entry')
EXECUTE FUNCTION attendance_set_entry_target();

-- ============================================================
-- STEP 7: trigger on attendance EXIT insert -> compute credited hours
--         vs the matching entry row's frozen allotted_target_hr
-- ============================================================
CREATE OR REPLACE FUNCTION attendance_set_exit_credit()
RETURNS TRIGGER AS $$
DECLARE
  v_entry_row RECORD;
  v_allotted numeric;
  v_actual_seconds integer;
  v_allotted_seconds integer;
  v_floor_hours integer;
BEGIN
  IF NEW.record_type = 'exit' THEN
    SELECT * INTO v_entry_row
    FROM attendance
    WHERE sr_no = NEW.sr_no
      AND institute_id = NEW.institute_id
      AND attendance_date = NEW.attendance_date
      AND record_type = 'entry'
      AND marked_time <= NEW.marked_time
    ORDER BY marked_time DESC
    LIMIT 1;

    IF v_entry_row IS NULL THEN
      RETURN NEW; -- no matching entry today, leave as-is
    END IF;

    v_allotted := COALESCE(v_entry_row.allotted_target_hr, 1.0);
    v_actual_seconds := GREATEST(0, EXTRACT(EPOCH FROM (NEW.marked_time - v_entry_row.marked_time))::integer);
    v_allotted_seconds := ROUND(v_allotted * 3600)::integer;

    NEW.allotted_target_hr := v_allotted;

    IF v_actual_seconds <= v_allotted_seconds THEN
      NEW.attendance_alloted_hr :=
        lpad((v_actual_seconds / 3600)::text, 2, '0') || ':' ||
        lpad(((v_actual_seconds % 3600) / 60)::text, 2, '0') || ':' ||
        lpad((v_actual_seconds % 60)::text, 2, '0');
      NEW.remark := NULL;
    ELSE
      v_floor_hours := floor(v_allotted)::integer;
      NEW.attendance_alloted_hr := lpad(v_floor_hours::text, 2, '0') || ':00:00';
      NEW.remark := 'EXIT LATE MARKED';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_attendance_set_exit_credit ON attendance;
CREATE TRIGGER trg_attendance_set_exit_credit
BEFORE INSERT ON attendance
FOR EACH ROW
WHEN (NEW.record_type = 'exit')
EXECUTE FUNCTION attendance_set_exit_credit();

-- ============================================================
-- STEP 8: nightly job -> close entries with no same-day exit
--         (fixed 1.0h regardless of subject count)
-- ============================================================
CREATE OR REPLACE FUNCTION close_missing_exit_attendance()
RETURNS void AS $$
BEGIN
  UPDATE attendance
  SET attendance_alloted_hr = '01:00:00',
      remark = 'NOT EXITED BUT ENTRY'
  WHERE record_type = 'entry'
    AND attendance_date = (CURRENT_DATE - INTERVAL '1 day')::date
    AND attendance_alloted_hr IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM attendance a2
      WHERE a2.sr_no = attendance.sr_no
        AND a2.institute_id = attendance.institute_id
        AND a2.attendance_date = attendance.attendance_date
        AND a2.record_type = 'exit'
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- STEP 9: schedule the nightly job (requires pg_cron extension)
--         20:30 UTC = 2:00 AM IST (next calendar day)
--         If this errors, enable "pg_cron" first via
--         Supabase Dashboard -> Database -> Extensions, then re-run just this step.
-- ============================================================
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.unschedule('close-missing-exit-attendance')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'close-missing-exit-attendance'
);

SELECT cron.schedule(
  'close-missing-exit-attendance',
  '30 20 * * *',
  $$ SELECT close_missing_exit_attendance(); $$
);
