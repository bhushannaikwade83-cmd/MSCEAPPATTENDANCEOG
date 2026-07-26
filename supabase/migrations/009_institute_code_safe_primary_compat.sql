-- Safe compatibility migration:
-- Keep institutes.id as PK (app compatibility), but make institute_code first-class.
-- 1) Backfill missing institute_code from id
-- 2) Enforce unique non-empty institute_code
-- 3) Auto-sync id/institute_code on new inserts/updates

-- Backfill historical rows where institute_code is empty
update public.institutes
set institute_code = id
where institute_code is null or btrim(institute_code) = '';

-- Normalize whitespace for existing rows
update public.institutes
set institute_code = btrim(institute_code),
    id = btrim(id)
where institute_code is not null;

-- Unique business key (case-insensitive) for non-empty codes
create unique index if not exists uq_institutes_institute_code_nocase
  on public.institutes (lower(institute_code))
  where institute_code is not null and btrim(institute_code) <> '';

-- Enforce non-empty id at DB level (PK already not null, this blocks blank strings)
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'institutes_id_not_blank'
  ) then
    alter table public.institutes
      add constraint institutes_id_not_blank check (btrim(id) <> '');
  end if;
end$$;

-- Enforce non-empty institute_code now that we've backfilled
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'institutes_code_not_blank'
  ) then
    alter table public.institutes
      add constraint institutes_code_not_blank check (btrim(institute_code) <> '');
  end if;
end$$;

-- Keep id/code in sync for new writes while preserving backward compatibility.
-- If caller sends only one, the other is auto-filled.
create or replace function public.sync_institute_id_and_code()
returns trigger
language plpgsql
as $$
begin
  new.id := nullif(btrim(coalesce(new.id, '')), '');
  new.institute_code := nullif(btrim(coalesce(new.institute_code, '')), '');

  if new.id is null and new.institute_code is null then
    raise exception 'Either id or institute_code must be provided';
  end if;

  if new.id is null then
    new.id := new.institute_code;
  end if;

  if new.institute_code is null then
    new.institute_code := new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sync_institute_id_and_code on public.institutes;
create trigger trg_sync_institute_id_and_code
before insert or update on public.institutes
for each row
execute function public.sync_institute_id_and_code();
