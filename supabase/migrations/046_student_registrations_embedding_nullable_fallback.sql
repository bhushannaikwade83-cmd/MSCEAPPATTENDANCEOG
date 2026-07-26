-- If student_registrations was created with face_embedding NOT NULL but the old app only
-- sent registration_photo_path, inserts failed. Prefer the app sending face_embedding JSON
-- (see student_face_registration_wrapper). This migration loosens the constraint where present.

alter table public.student_registrations
  alter column face_embedding drop not null;
