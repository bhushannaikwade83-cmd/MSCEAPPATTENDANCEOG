-- Speed up per-institute daily attendance reads (teacher screen, auto-close, reports).
create index if not exists idx_teacher_att_inst_date
  on public.teacher_attendance (institute_id, date);

-- Face-duplicate checks: institute + non-null embedding only.
create index if not exists idx_students_institute_face_embedding
  on public.students (institute_id)
  where face_embedding is not null;
