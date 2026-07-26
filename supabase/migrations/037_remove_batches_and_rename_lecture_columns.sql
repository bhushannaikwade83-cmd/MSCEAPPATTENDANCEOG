-- Remove `batches` and all student/institute columns whose names contained "batch".
-- Replaces institute timing JSONB fields with lecture_* names (data preserved via RENAME).

-- ── public.batches ─────────────────────────────────────────────────────────
do $$
begin
  if to_regclass('public.batches') is not null then
    drop policy if exists "authenticated_all_batches" on public.batches;
    drop policy if exists "batches_all_institute_admin" on public.batches;
    drop policy if exists "batches_super_admin_select" on public.batches;
    drop table public.batches cascade;
  end if;
end $$;

drop index if exists public.idx_batches_institute;
drop index if exists public.idx_batches_institute_id;
drop index if exists public.idx_batches_year;

-- ── students ───────────────────────────────────────────────────────────────
alter table public.students drop column if exists batch_id;
alter table public.students drop column if exists batch_ids;
alter table public.students drop column if exists batch_name;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'students' and column_name = 'batch_timing'
  ) then
    alter table public.students rename column batch_timing to lecture_timing;
  elsif not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'students' and column_name = 'lecture_timing'
  ) then
    alter table public.students add column lecture_timing text;
  end if;
end $$;

drop index if exists public.idx_students_batch_id;
drop index if exists public.idx_students_institute_batch_status;

-- ── institutes (from migration 004) ───────────────────────────────────────
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'institutes' and column_name = 'batch_open_time'
  ) then
    alter table public.institutes rename column batch_open_time to lecture_open_time;
  end if;
end $$;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'institutes' and column_name = 'batch_close_time'
  ) then
    alter table public.institutes rename column batch_close_time to lecture_close_time;
  end if;
end $$;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'institutes' and column_name = 'batch_duration_minutes'
  ) then
    alter table public.institutes rename column batch_duration_minutes to lecture_slot_duration_minutes;
  end if;
end $$;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'institutes' and column_name = 'batch_timing_updated_at'
  ) then
    alter table public.institutes rename column batch_timing_updated_at to lecture_timing_updated_at;
  end if;
end $$;
