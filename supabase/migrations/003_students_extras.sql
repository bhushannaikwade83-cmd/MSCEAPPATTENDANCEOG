-- Extra columns to match Firestore student documents (manual + face flow)
alter table public.students add column if not exists email text default '';
alter table public.students add column if not exists batch_ids text[];
alter table public.students add column if not exists batch_name text;
alter table public.students add column if not exists batch_timing text;
alter table public.students add column if not exists subject text;
alter table public.students add column if not exists subjects text[];
alter table public.students add column if not exists semester text;
alter table public.students add column if not exists semester_name text;
alter table public.students add column if not exists role text default 'student';
alter table public.students add column if not exists status text default 'approved';
alter table public.students add column if not exists has_device boolean default false;
alter table public.students add column if not exists face_photo_url text;
alter table public.students add column if not exists uid text;
