-- Extra tables for Firestore parity (GPS, teacher attendance, coders, etc.)

create table if not exists public.gps_settings (
  institute_id text not null references public.institutes (id) on delete cascade,
  admin_id text not null,
  latitude double precision,
  longitude double precision,
  radius double precision default 30,
  is_locked boolean default false,
  locked_at timestamptz,
  locked_by text,
  unlocked_at timestamptz,
  unlocked_by text,
  unlocked_by_email text,
  extra jsonb default '{}'::jsonb,
  primary key (institute_id, admin_id)
);

create table if not exists public.institute_geofence (
  institute_id text primary key references public.institutes (id) on delete cascade,
  radius double precision,
  data jsonb default '{}'::jsonb,
  updated_at timestamptz default now()
);

create table if not exists public.institute_daily_status (
  id uuid primary key default gen_random_uuid (),
  institute_id text not null references public.institutes (id) on delete cascade,
  student_id text not null,
  date_key text not null,
  payload jsonb default '{}'::jsonb,
  unique (institute_id, student_id, date_key)
);

create table if not exists public.student_leaves (
  id uuid primary key default gen_random_uuid (),
  institute_id text not null references public.institutes (id) on delete cascade,
  student_id text,
  user_id text,
  payload jsonb default '{}'::jsonb,
  created_at timestamptz default now ()
);

create table if not exists public.coders (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  created_at timestamptz default now ()
);

create table if not exists public.suspicious_activity (
  id uuid primary key default gen_random_uuid (),
  institute_id text,
  payload jsonb default '{}'::jsonb,
  created_at timestamptz default now ()
);

create table if not exists public.user_devices (
  id uuid primary key default gen_random_uuid (),
  institute_id text,
  device_id text,
  payload jsonb default '{}'::jsonb,
  created_at timestamptz default now ()
);

-- Root-level teacher attendance (was Firestore collection "attendance")
create table if not exists public.teacher_attendance (
  id text primary key,
  institute_id text,
  student_id text not null,
  student_name text,
  date text not null,
  status text,
  verification_selfie text,
  payload jsonb default '{}'::jsonb,
  created_at timestamptz default now (),
  updated_at timestamptz default now ()
);

create index if not exists idx_teacher_att_date on public.teacher_attendance (date);
create index if not exists idx_teacher_att_inst on public.teacher_attendance (institute_id);

alter table public.gps_settings enable row level security;
alter table public.institute_geofence enable row level security;
alter table public.institute_daily_status enable row level security;
alter table public.student_leaves enable row level security;
alter table public.coders enable row level security;
alter table public.suspicious_activity enable row level security;
alter table public.user_devices enable row level security;
alter table public.teacher_attendance enable row level security;

drop policy if exists "authenticated_all_gps" on public.gps_settings;
drop policy if exists "authenticated_all_inst_geofence" on public.institute_geofence;
drop policy if exists "authenticated_all_daily_status" on public.institute_daily_status;
drop policy if exists "authenticated_all_leaves" on public.student_leaves;
drop policy if exists "authenticated_all_coders" on public.coders;
drop policy if exists "authenticated_all_suspicious" on public.suspicious_activity;
drop policy if exists "authenticated_all_user_devices" on public.user_devices;
drop policy if exists "authenticated_all_teacher_att" on public.teacher_attendance;

create policy "authenticated_all_gps" on public.gps_settings for all to authenticated using (true) with check (true);
create policy "authenticated_all_inst_geofence" on public.institute_geofence for all to authenticated using (true) with check (true);
create policy "authenticated_all_daily_status" on public.institute_daily_status for all to authenticated using (true) with check (true);
create policy "authenticated_all_leaves" on public.student_leaves for all to authenticated using (true) with check (true);
create policy "authenticated_all_coders" on public.coders for all to authenticated using (true) with check (true);
create policy "authenticated_all_suspicious" on public.suspicious_activity for all to authenticated using (true) with check (true);
create policy "authenticated_all_user_devices" on public.user_devices for all to authenticated using (true) with check (true);
create policy "authenticated_all_teacher_att" on public.teacher_attendance for all to authenticated using (true) with check (true);
