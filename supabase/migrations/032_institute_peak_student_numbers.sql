-- Fast SR / roll numbering for institutes with tens of thousands of students.
-- Avoids transferring all sr_no/user_id rows to the client on each add-student action.

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
