-- Lets PostgREST `ilike` match enrolled subjects stored as text[] without raw SQL/RPC.
alter table public.students
  add column if not exists subjects_search text
  generated always as (coalesce(array_to_string(subjects, ' '), '')) stored;
