-- Backend error fixes applied to the live OfficeLedger Supabase project.
-- 1) Normalize one-to-one conversation user ordering server-side.
-- 2) Allow company-scoped Survey Report Admin operations without requiring a survey department membership.

create or replace function app_private.normalize_direct_conversation_users()
returns trigger
language plpgsql
security definer
set search_path=public,app_private
as $$
declare a uuid; b uuid;
begin
  a := new.user_one;
  b := new.user_two;
  if a = b then
    raise exception 'A private conversation requires two different employees.';
  end if;
  if a > b then
    new.user_one := b;
    new.user_two := a;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_normalize_direct_conversation_users on public.direct_conversations;
create trigger trg_normalize_direct_conversation_users
before insert or update of user_one,user_two on public.direct_conversations
for each row execute function app_private.normalize_direct_conversation_users();

drop policy if exists survey_reports_select on public.survey_reports;
drop policy if exists survey_reports_insert on public.survey_reports;
drop policy if exists survey_reports_update on public.survey_reports;

create policy survey_reports_select on public.survey_reports
for select to authenticated
using (
  (select app_private.has_permission('SURVEY_REPORTS_VIEW','VIEW','COMPANY'))
  or (
    (select app_private.has_permission('SURVEY_REPORTS_VIEW','VIEW','DEPARTMENT'))
    and exists (
      select 1 from public.employee_departments ed
      where ed.employee_id=(select auth.uid())
        and ed.department_id=survey_reports.department_id
        and ed.is_active
    )
  )
);

create policy survey_reports_insert on public.survey_reports
for insert to authenticated
with check (
  created_by=(select auth.uid())
  and (
    (select app_private.has_permission('SURVEY_REPORTS_CREATE','CREATE','COMPANY'))
    or (
      (select app_private.has_permission('SURVEY_REPORTS_CREATE','CREATE','DEPARTMENT'))
      and exists (
        select 1 from public.employee_departments ed
        where ed.employee_id=(select auth.uid())
          and ed.department_id=survey_reports.department_id
          and ed.is_active
      )
    )
  )
);

create policy survey_reports_update on public.survey_reports
for update to authenticated
using (
  (select app_private.has_permission('SURVEY_REPORTS_EDIT','EDIT','COMPANY'))
  or (
    created_by=(select auth.uid())
    and (select app_private.has_permission('SURVEY_REPORTS_EDIT','EDIT','DEPARTMENT'))
    and exists (
      select 1 from public.employee_departments ed
      where ed.employee_id=(select auth.uid())
        and ed.department_id=survey_reports.department_id
        and ed.is_active
    )
  )
)
with check (
  (select app_private.has_permission('SURVEY_REPORTS_EDIT','EDIT','COMPANY'))
  or (
    created_by=(select auth.uid())
    and (select app_private.has_permission('SURVEY_REPORTS_EDIT','EDIT','DEPARTMENT'))
    and exists (
      select 1 from public.employee_departments ed
      where ed.employee_id=(select auth.uid())
        and ed.department_id=survey_reports.department_id
        and ed.is_active
    )
  )
);
