-- Server-side roster search for mark-attendance (avoids loading every roll for large institutes).
-- Hardening: peak numbering uses invoker rights so RLS still applies (no cross-institute leaks).

create or replace function public.institute_peak_student_numbers(p_institute_id text)
returns json
language sql
stable
set search_path = public
as $$
  select json_build_object(
    'sr_max', coalesce(max(
      case
        when trim(coalesce(sr_no, '')) ~ '^[0-9]+$' then trim(sr_no)::integer
      end
    ), 0),
    'roll_max', coalesce(max(
      case
        when trim(coalesce(user_id, '')) ~ '^[0-9]+$' then trim(user_id)::integer
      end
    ), 0)
  )
  from students
  where institute_id = p_institute_id;
$$;

grant execute on function public.institute_peak_student_numbers(text) to authenticated;

create or replace function public.institute_attendance_roll_search(
  p_institute_id text,
  p_search text default '',
  p_limit int default 300
)
returns table(roll text)
language sql
stable
set search_path = public
as $$
  with q as (
    select trim(user_id) as roll
    from students
    where institute_id = p_institute_id
      and trim(coalesce(user_id, '')) <> ''
      and (
        nullif(trim(p_search), '') is null
        or trim(user_id) ilike '%' || trim(p_search) || '%'
      )
    union
    select trim(sr_no) as roll
    from students
    where institute_id = p_institute_id
      and trim(coalesce(sr_no, '')) <> ''
      and (
        nullif(trim(p_search), '') is null
        or trim(sr_no) ilike '%' || trim(p_search) || '%'
      )
  )
  select q.roll
  from q
  order by
    case when q.roll ~ '^[0-9]+$' then 0 else 1 end,
    case when q.roll ~ '^[0-9]+$' then q.roll::bigint else 0 end,
    q.roll
  limit least(greatest(coalesce(nullif(p_limit, 0), 300), 1), 5000);
$$;

grant execute on function public.institute_attendance_roll_search(text, text, int) to authenticated;
