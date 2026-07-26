-- Fix forgot-password OTP staging: gen_salt('bf') was unknown type; ensure pgcrypto on search_path.

create extension if not exists pgcrypto;

create or replace function public.stage_admin_password_reset_otp(
  p_institute_key text,
  p_email text,
  p_otp text
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_institute_id text;
  v_expected_email text;
  v_norm_email text;
  v_otp text;
begin
  v_norm_email := lower(trim(coalesce(p_email, '')));
  v_otp := trim(coalesce(p_otp, ''));

  if v_norm_email = '' then
    return json_build_object('success', false, 'message', 'Email is required');
  end if;
  if length(v_otp) <> 6 or v_otp !~ '^[0-9]{6}$' then
    return json_build_object('success', false, 'message', 'Invalid OTP format');
  end if;

  select i.id into v_institute_id
  from public.institutes i
  where trim(i.id::text) = trim(p_institute_key)
     or trim(coalesce(i.institute_code, '')) = trim(p_institute_key)
  limit 1;

  if v_institute_id is null then
    return json_build_object('success', false, 'message', 'Institute not found');
  end if;

  v_expected_email := lower(trim(public.get_admin_reset_email_for_institute(p_institute_key)));
  if v_expected_email is null or v_expected_email = '' then
    return json_build_object('success', false, 'message', 'No admin email on file for this institute');
  end if;
  if v_norm_email <> v_expected_email then
    return json_build_object('success', false, 'message', 'Email does not match institute admin invite');
  end if;

  insert into public.admin_password_reset_otps (institute_id, email, otp_hash, expires_at)
  values (
    v_institute_id,
    v_norm_email,
    crypt(v_otp, gen_salt('bf'::text, 10)),
    now() + interval '10 minutes'
  )
  on conflict (institute_id, email) do update set
    otp_hash = excluded.otp_hash,
    expires_at = excluded.expires_at,
    created_at = now();

  return json_build_object('success', true, 'message', 'OTP staged');
end;
$$;

create or replace function public.consume_admin_password_reset_otp(
  p_institute_key text,
  p_email text,
  p_otp text
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_institute_id text;
  v_norm_email text;
  v_otp text;
  v_row public.admin_password_reset_otps%rowtype;
  v_profile_id uuid;
begin
  v_norm_email := lower(trim(coalesce(p_email, '')));
  v_otp := trim(coalesce(p_otp, ''));

  if v_norm_email = '' or length(v_otp) <> 6 then
    return json_build_object('success', false, 'message', 'Invalid request');
  end if;

  select i.id into v_institute_id
  from public.institutes i
  where trim(i.id::text) = trim(p_institute_key)
     or trim(coalesce(i.institute_code, '')) = trim(p_institute_key)
  limit 1;

  if v_institute_id is null then
    return json_build_object('success', false, 'message', 'Institute not found');
  end if;

  select * into v_row
  from public.admin_password_reset_otps r
  where r.institute_id = v_institute_id
    and r.email = v_norm_email;

  if not found then
    return json_build_object('success', false, 'message', 'No OTP found. Send OTP again.');
  end if;

  if v_row.expires_at < now() then
    delete from public.admin_password_reset_otps
    where institute_id = v_institute_id and email = v_norm_email;
    return json_build_object('success', false, 'message', 'OTP expired. Send OTP again.');
  end if;

  if v_row.otp_hash <> crypt(v_otp, v_row.otp_hash) then
    return json_build_object('success', false, 'message', 'Invalid OTP');
  end if;

  select p.id into v_profile_id
  from public.profiles p
  where p.institute_id = v_institute_id
    and p.role = 'admin'
    and lower(trim(coalesce(p.email::text, ''))) = v_norm_email
    and lower(coalesce(p.status, '')) in ('approved', 'active')
  order by p.last_login desc nulls last, p.created_at desc
  limit 1;

  if v_profile_id is null then
    return json_build_object('success', false, 'message', 'Admin account not found');
  end if;

  delete from public.admin_password_reset_otps
  where institute_id = v_institute_id and email = v_norm_email;

  return json_build_object(
    'success', true,
    'profile_id', v_profile_id,
    'message', 'OTP verified'
  );
end;
$$;
