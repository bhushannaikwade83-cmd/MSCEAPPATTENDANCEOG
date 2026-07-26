-- Cleanup old institute-password login path.
-- New admin login uses institute id -> admin email resolution + Supabase Auth.

drop function if exists public.admin_login_by_institute(text, text);
drop function if exists public.set_admin_password(uuid, text);

drop table if exists public.admin_passwords;
