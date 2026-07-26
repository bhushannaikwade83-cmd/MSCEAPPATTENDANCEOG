-- Extend numeric peak parsing: plain digits (1, 002) and legacy SR_001 / SR-002 styles.

create or replace function public.institute_peak_student_numbers(p_institute_id text)
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object(
    'sr_max', coalesce(max(
      case
        when trim(coalesce(sr_no, '')) ~ '^[0-9]+$' then trim(sr_no)::integer
        when regexp_replace(lower(trim(coalesce(sr_no, ''))), '^sr[_-]?', '') ~ '^[0-9]+$'
          then regexp_replace(lower(trim(sr_no)), '^sr[_-]?', '')::integer
      end
    ), 0),
    'roll_max', coalesce(max(
      case
        when trim(coalesce(user_id, '')) ~ '^[0-9]+$' then trim(user_id)::integer
        when regexp_replace(lower(trim(coalesce(user_id, ''))), '^sr[_-]?', '') ~ '^[0-9]+$'
          then regexp_replace(lower(trim(user_id)), '^sr[_-]?', '')::integer
      end
    ), 0)
  )
  from students
  where institute_id = p_institute_id;
$$;

grant execute on function public.institute_peak_student_numbers(text) to authenticated;
