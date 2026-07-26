-- Align minimally with Flutter app assumptions (existing DBs that skipped older ad-hoc SQL).
-- Safe to run multiple times.

-- students: face registration helper / delete scripts referenced this column (014 elsewhere)
alter table public.students
  add column if not exists registration_photo_path text;

-- B2 signed-URL memoization (see lib/services/b2b_storage_service.dart)
create table if not exists public.cached_photo_urls (
  id uuid primary key default gen_random_uuid(),
  object_path text not null,
  photo_url text not null,
  authorization_token text,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint cached_photo_urls_object_path_unique unique (object_path)
);

create index if not exists idx_cached_photo_urls_expires_at
  on public.cached_photo_urls (expires_at);

alter table public.cached_photo_urls enable row level security;

drop policy if exists "authenticated_all_cached_photo_urls" on public.cached_photo_urls;
create policy "authenticated_all_cached_photo_urls"
  on public.cached_photo_urls for all
  to authenticated
  using (true)
  with check (true);

-- student_registrations: student_face_registration_wrapper.dart (photo URL mirror)
create table if not exists public.student_registrations (
  id text primary key,
  student_id text not null,
  registration_photo_path text,
  face_embedding jsonb,
  institute_id text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index if not exists idx_student_registrations_student_id
  on public.student_registrations (student_id);

alter table public.student_registrations enable row level security;

drop policy if exists "authenticated_all_student_registrations" on public.student_registrations;
create policy "authenticated_all_student_registrations"
  on public.student_registrations for all
  to authenticated
  using (true)
  with check (true);

-- attendance_records: student_attendance_verification_wrapper.dart (optional flow)
create table if not exists public.attendance_records (
  id text primary key,
  student_id text not null,
  institute_id text,
  attendance_photo_path text,
  similarity_score double precision,
  matched boolean,
  attended_at timestamptz,
  created_at timestamptz default now()
);

create index if not exists idx_attendance_records_student
  on public.attendance_records (student_id);

create index if not exists idx_attendance_records_institute_created
  on public.attendance_records (institute_id, created_at desc);

alter table public.attendance_records enable row level security;

drop policy if exists "authenticated_all_attendance_records" on public.attendance_records;
create policy "authenticated_all_attendance_records"
  on public.attendance_records for all
  to authenticated
  using (true)
  with check (true);
