-- Run this FIRST to confirm SQL Editor can create objects (1 table only).
-- If this succeeds, open Table Editor → you should see "smoke_test".
-- If this fails, fix dashboard/connection (restore project, VPN, different browser) before running 001.

create extension if not exists "pgcrypto";

create table if not exists public.smoke_test (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now()
);

alter table public.smoke_test enable row level security;

-- Allow read for authenticated + anon so you can see it in dashboard after login (optional dev)
drop policy if exists "smoke_test_read" on public.smoke_test;
create policy "smoke_test_read" on public.smoke_test for select to authenticated, anon using (true);
