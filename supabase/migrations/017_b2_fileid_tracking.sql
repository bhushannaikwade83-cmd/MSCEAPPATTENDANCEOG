-- Track B2 file IDs so secure delete can use b2_delete_file_version

alter table public.attendance_in_out
  add column if not exists photo_file_id text;

-- Optional helper index for cleanup jobs or reverse lookups.
create index if not exists idx_attendance_in_out_photo_file_id
  on public.attendance_in_out (photo_file_id);
