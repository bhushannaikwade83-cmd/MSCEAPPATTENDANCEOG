-- One-time registration photo change: keep original, use new face for attendance.
-- App: student_management_screen change-photo button (once per student).
-- Website: StudentsSection shows original_face_photo_url + face_photo_url when changed.

alter table public.students
  add column if not exists original_face_photo_url text,
  add column if not exists original_registration_photo_path text,
  add column if not exists face_photo_changed_once boolean not null default false,
  add column if not exists face_photo_changed_at timestamptz;

comment on column public.students.original_face_photo_url is
  'First registration portrait kept when staff use one-time photo change.';
comment on column public.students.original_registration_photo_path is
  'B2 object path for the original registration photo.';
comment on column public.students.face_photo_changed_once is
  'True after staff changed registration photo once; blocks further changes.';
comment on column public.students.face_photo_changed_at is
  'When the one-time registration photo change was saved.';
