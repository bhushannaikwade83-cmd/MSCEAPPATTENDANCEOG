-- Resend email queue + logs for high-volume delivery from Edge Functions
-- Run after existing migrations.

create table if not exists public.email_jobs (
  id bigint generated always as identity primary key,
  to_email text not null,
  subject text not null,
  html text not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'sent', 'failed', 'dead')),
  attempts int not null default 0,
  max_attempts int not null default 5,
  next_attempt_at timestamptz not null default now(),
  provider_message_id text,
  last_error text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_email_jobs_status_next_attempt
  on public.email_jobs (status, next_attempt_at);

create index if not exists idx_email_jobs_created_at
  on public.email_jobs (created_at);

create table if not exists public.email_logs (
  id bigint generated always as identity primary key,
  job_id bigint references public.email_jobs (id) on delete set null,
  to_email text not null,
  subject text not null,
  status text not null check (status in ('sent', 'failed', 'queued')),
  provider_message_id text,
  error_message text,
  provider_response jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_email_logs_job_id on public.email_logs (job_id);
create index if not exists idx_email_logs_created_at on public.email_logs (created_at desc);

create or replace function public.set_email_jobs_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_email_jobs_updated_at on public.email_jobs;
create trigger trg_email_jobs_updated_at
before update on public.email_jobs
for each row
execute function public.set_email_jobs_updated_at();

create or replace function public.enqueue_email_job(
  p_to_email text,
  p_subject text,
  p_html text,
  p_metadata jsonb default '{}'::jsonb,
  p_max_attempts int default 5
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job_id bigint;
begin
  insert into public.email_jobs (
    to_email, subject, html, metadata, max_attempts
  )
  values (
    trim(p_to_email), p_subject, p_html, coalesce(p_metadata, '{}'::jsonb), greatest(1, p_max_attempts)
  )
  returning id into v_job_id;

  insert into public.email_logs (job_id, to_email, subject, status)
  values (v_job_id, trim(p_to_email), p_subject, 'queued');

  return v_job_id;
end;
$$;

create or replace function public.claim_email_jobs(p_limit int default 50)
returns setof public.email_jobs
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with claimed as (
    select j.id
    from public.email_jobs j
    where j.status in ('pending', 'failed')
      and j.next_attempt_at <= now()
      and j.attempts < j.max_attempts
    order by j.created_at
    for update skip locked
    limit greatest(1, least(p_limit, 500))
  )
  update public.email_jobs j
  set status = 'processing',
      attempts = attempts + 1,
      updated_at = now()
  from claimed
  where j.id = claimed.id
  returning j.*;
end;
$$;

create or replace function public.mark_email_job_sent(
  p_job_id bigint,
  p_provider_message_id text default null,
  p_provider_response jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_to text;
  v_subject text;
begin
  update public.email_jobs
  set status = 'sent',
      provider_message_id = p_provider_message_id,
      last_error = null,
      updated_at = now()
  where id = p_job_id;

  select to_email, subject into v_to, v_subject
  from public.email_jobs
  where id = p_job_id;

  insert into public.email_logs (
    job_id, to_email, subject, status, provider_message_id, provider_response
  )
  values (
    p_job_id, coalesce(v_to, ''), coalesce(v_subject, ''), 'sent', p_provider_message_id, coalesce(p_provider_response, '{}'::jsonb)
  );
end;
$$;

create or replace function public.mark_email_job_failed(
  p_job_id bigint,
  p_error_message text,
  p_retry_delay_seconds int default 60,
  p_provider_response jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_attempts int;
  v_max_attempts int;
  v_to text;
  v_subject text;
begin
  select attempts, max_attempts, to_email, subject
  into v_attempts, v_max_attempts, v_to, v_subject
  from public.email_jobs
  where id = p_job_id;

  update public.email_jobs
  set status = case when coalesce(v_attempts, 0) >= coalesce(v_max_attempts, 1) then 'dead' else 'failed' end,
      last_error = p_error_message,
      next_attempt_at = now() + make_interval(secs => greatest(5, p_retry_delay_seconds)),
      updated_at = now()
  where id = p_job_id;

  insert into public.email_logs (
    job_id, to_email, subject, status, error_message, provider_response
  )
  values (
    p_job_id, coalesce(v_to, ''), coalesce(v_subject, ''), 'failed', p_error_message, coalesce(p_provider_response, '{}'::jsonb)
  );
end;
$$;

grant execute on function public.enqueue_email_job(text, text, text, jsonb, int) to service_role;
grant execute on function public.claim_email_jobs(int) to service_role;
grant execute on function public.mark_email_job_sent(bigint, text, jsonb) to service_role;
grant execute on function public.mark_email_job_failed(bigint, text, int, jsonb) to service_role;

alter table public.email_jobs enable row level security;
alter table public.email_logs enable row level security;

drop policy if exists "email_jobs_service_role_all" on public.email_jobs;
drop policy if exists "email_logs_service_role_all" on public.email_logs;

create policy "email_jobs_service_role_all"
  on public.email_jobs for all
  to service_role
  using (true)
  with check (true);

create policy "email_logs_service_role_all"
  on public.email_logs for all
  to service_role
  using (true)
  with check (true);
