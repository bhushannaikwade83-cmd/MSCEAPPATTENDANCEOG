-- Portal: edit pending admin_invites (name, email, mobile) before password setup in app.

create or replace function public.update_pending_admin_invite_portal(
  p_invite_id uuid,
  p_full_name text,
  p_email text,
  p_phone text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := nullif(btrim(coalesce(p_full_name, '')), '');
  v_phone text := nullif(btrim(coalesce(p_phone, '')), '');
  v_email text := lower(nullif(btrim(coalesce(p_email, '')), ''));
  v_institute_id text;
begin
  if not public.can_access_portal_onboarding_list() then
    return jsonb_build_object('success', false, 'message', 'Not authorized');
  end if;

  if p_invite_id is null then
    return jsonb_build_object('success', false, 'message', 'Invite ID is required');
  end if;

  if v_name is null then
    return jsonb_build_object('success', false, 'message', 'Admin name is required');
  end if;

  if v_phone is null then
    return jsonb_build_object('success', false, 'message', 'Mobile number is required');
  end if;

  if v_email is null then
    return jsonb_build_object('success', false, 'message', 'Email is required');
  end if;

  if v_email !~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$' then
    return jsonb_build_object('success', false, 'message', 'Enter a valid email address');
  end if;

  update public.admin_invites ai
     set full_name = v_name,
         phone = v_phone,
         email = v_email,
         updated_at = now()
   where ai.id = p_invite_id
     and ai.claimed = false
   returning ai.institute_id into v_institute_id;

  if v_institute_id is null then
    return jsonb_build_object(
      'success', false,
      'message', 'Pending invite not found or already claimed in the app'
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'message', 'Invite updated',
    'institute_id', v_institute_id,
    'invite_id', p_invite_id
  );
end;
$$;

grant execute on function public.update_pending_admin_invite_portal(uuid, text, text, text) to authenticated;
