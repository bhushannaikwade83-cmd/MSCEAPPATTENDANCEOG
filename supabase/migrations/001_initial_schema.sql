-- Smart Attendance App — Supabase schema (Firebase replacement)
-- Apply in Supabase Dashboard → SQL Editor, or: supabase db push
-- Tighten RLS policies before production.

-- Extensions
create extension if not exists "pgcrypto";

-- Institutes
create table if not exists public.institutes (
  id text primary key,
  institute_code text,
  name text not null default '',
  location text,
  address text,
  city text,
  district text,
  taluka text,
  state text,
  country text default 'India',
  mobile_no text,
  is_active boolean default true,
  user_count int default 0,
  student_count int default 0,
  last_user_added timestamptz,
  sr_no_migration_completed boolean default false,
  sr_no_migration_date timestamptz,
  sr_no_migration_count int,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Profiles (1:1 with auth.users — app admins / staff)
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  user_id text,
  name text,
  role text default 'admin',
  institute_id text references public.institutes (id),
  institute_name text,
  phone_number text,
  status text default 'pending',
  pin_hash text,
  encrypted_password text,
  has_pin boolean default false,
  pin_set_at timestamptz,
  created_at timestamptz default now(),
  last_login timestamptz,
  last_login_ip text
);

create index if not exists idx_profiles_institute on public.profiles (institute_id);
create index if not exists idx_profiles_email on public.profiles (email);
create index if not exists idx_profiles_user_id on public.profiles (user_id);

-- Students (per institute)
create table if not exists public.students (
  id text primary key default gen_random_uuid()::text,
  institute_id text not null references public.institutes (id) on delete cascade,
  name text,
  first_name text,
  middle_name text,
  last_name text,
  sr_no text,
  user_id text,
  year text,
  batch_id text,
  face_embedding jsonb,
  photo_url text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  sr_no_migrated_at timestamptz
);

create index if not exists idx_students_institute on public.students (institute_id);

-- Batches
create table if not exists public.batches (
  id uuid primary key default gen_random_uuid(),
  institute_id text not null references public.institutes (id) on delete cascade,
  name text not null,
  year text not null,
  timing text not null,
  subjects text[] default '{}',
  student_count int default 0,
  created_by text,
  created_at timestamptz default now()
);

create index if not exists idx_batches_institute on public.batches (institute_id);

-- Attendance in/out (flat table; replaces hierarchical Firestore path)
create table if not exists public.attendance_in_out (
  id uuid primary key default gen_random_uuid(),
  institute_code text not null,
  student_id text not null,
  student_name text,
  sr_no text,
  year int not null,
  semester_code text not null,
  attendance_date date not null,
  type text not null check (type in ('entry', 'exit')),
  unique_id text not null,
  photo_url text,
  photo_path text,
  additional jsonb default '{}'::jsonb,
  created_at timestamptz default now(),
  unique (institute_code, student_id, attendance_date, unique_id)
);

create index if not exists idx_att_inst_date on public.attendance_in_out (institute_code, attendance_date);
create index if not exists idx_att_student on public.attendance_in_out (institute_code, student_id);

-- Error logs
create table if not exists public.error_logs (
  id uuid primary key default gen_random_uuid(),
  error_type text,
  error_code text,
  error_message text,
  stack_trace text,
  context text,
  user_id text,
  user_email text,
  institute_id text,
  app_type text default 'admin',
  device_info jsonb,
  additional_data jsonb default '{}'::jsonb,
  resolved boolean default false,
  resolved_at timestamptz,
  resolved_by text,
  created_at timestamptz default now()
);

-- Optional: user credentials staging (avoid plain passwords in prod)
create table if not exists public.user_credentials (
  id uuid primary key default gen_random_uuid(),
  institute_id text references public.institutes (id) on delete cascade,
  profile_id uuid references public.profiles (id) on delete cascade,
  email text,
  created_at timestamptz default now(),
  email_sent boolean default false,
  email_sent_at timestamptz
);

-- Subjects / system settings / leaves — flexible key-value per institute
create table if not exists public.institute_subjects (
  id uuid primary key default gen_random_uuid(),
  institute_id text not null references public.institutes (id) on delete cascade,
  name text not null,
  code text,
  created_at timestamptz default now()
);

create table if not exists public.system_settings (
  key text primary key,
  value jsonb,
  updated_at timestamptz default now()
);

-- RLS (permissive for development — replace with proper policies)
alter table public.institutes enable row level security;
alter table public.profiles enable row level security;
alter table public.students enable row level security;
alter table public.batches enable row level security;
alter table public.attendance_in_out enable row level security;
alter table public.error_logs enable row level security;
alter table public.user_credentials enable row level security;
alter table public.institute_subjects enable row level security;
alter table public.system_settings enable row level security;

-- Idempotent: safe to re-run after errors
drop policy if exists "authenticated_all_institutes" on public.institutes;
drop policy if exists "authenticated_all_profiles" on public.profiles;
drop policy if exists "authenticated_all_students" on public.students;
drop policy if exists "authenticated_all_batches" on public.batches;
drop policy if exists "authenticated_all_attendance" on public.attendance_in_out;
drop policy if exists "authenticated_all_error_logs" on public.error_logs;
drop policy if exists "authenticated_all_user_cred" on public.user_credentials;
drop policy if exists "authenticated_all_subjects" on public.institute_subjects;
drop policy if exists "authenticated_all_settings" on public.system_settings;
drop policy if exists "anon_insert_error_logs" on public.error_logs;

-- Allow authenticated users full access (tighten later)
create policy "authenticated_all_institutes" on public.institutes for all to authenticated using (true) with check (true);
create policy "authenticated_all_profiles" on public.profiles for all to authenticated using (true) with check (true);
create policy "authenticated_all_students" on public.students for all to authenticated using (true) with check (true);
create policy "authenticated_all_batches" on public.batches for all to authenticated using (true) with check (true);
create policy "authenticated_all_attendance" on public.attendance_in_out for all to authenticated using (true) with check (true);
create policy "authenticated_all_error_logs" on public.error_logs for all to authenticated using (true) with check (true);
create policy "authenticated_all_user_cred" on public.user_credentials for all to authenticated using (true) with check (true);
create policy "authenticated_all_subjects" on public.institute_subjects for all to authenticated using (true) with check (true);
create policy "authenticated_all_settings" on public.system_settings for all to authenticated using (true) with check (true);

-- Allow anon insert for error_logs during pre-login failures (optional — disable if abused)
create policy "anon_insert_error_logs" on public.error_logs for insert to anon with check (true);
