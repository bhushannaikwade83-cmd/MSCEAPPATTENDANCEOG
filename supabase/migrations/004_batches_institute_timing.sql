alter table public.institutes add column if not exists batch_open_time jsonb;
alter table public.institutes add column if not exists batch_close_time jsonb;
alter table public.institutes add column if not exists batch_duration_minutes int default 60;
alter table public.institutes add column if not exists batch_timing_updated_at timestamptz;

alter table public.batches add column if not exists semester text;
alter table public.batches add column if not exists start_time jsonb;
alter table public.batches add column if not exists end_time jsonb;
alter table public.batches add column if not exists batch_duration_minutes int default 60;
alter table public.batches add column if not exists is_auto_generated boolean default false;
alter table public.batches add column if not exists updated_at timestamptz;
