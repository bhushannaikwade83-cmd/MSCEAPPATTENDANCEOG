-- Ensure institute 9999 stays active for testing/operations.

update public.institutes
set is_active = true,
    updated_at = now()
where id = '9999';
