-- Pincode for institutes (admin portal Add Institute + directory list).
-- Run in Supabase SQL Editor if the column is missing.
alter table public.institutes add column if not exists pincode text;

comment on column public.institutes.pincode is 'India PIN (6 digits); optional';
