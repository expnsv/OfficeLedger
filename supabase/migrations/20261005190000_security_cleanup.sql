-- OfficeLedger security/schema cleanup.
-- Removes duplicated legacy fields and hardens profile/project/progress writes.

create or replace function app_private.username_format_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.username := lower(btrim(new.username));
  if new.username !~ '^[a-z0-9][a-z0-9._-]{2,31}$' then
    raise exception 'Username must be 3-32 characters and use only letters, numbers, dot, underscore or hyphen.';
  end if;
  return new;
end; $$;

create or replace function app_private.password_meets_policy(p_password text)
returns boolean language sql stable set search_path = '' as $$
  select p_password is not null and exists (
    select 1 from public.auth_password_policy ap
    where ap.id=true and length(p_password)=any(ap.allowed_lengths)
      and (ap.allow_spaces or p_password !~ '\s')
      and ((not ap.require_upper) or p_password ~ '[A-Z]')
      and ((not ap.require_lower) or p_password ~ '[a-z]')
      and ((not ap.require_number) or p_password ~ '[0-9]')
      and ((not ap.require_symbol) or p_password ~ '[^A-Za-z0-9\s]')
  );
$$;
revoke all on function app_private.username_format_guard() from public,anon,authenticated;
revoke all on function app_private.password_meets_policy(text) from public,anon,authenticated;

create or replace function public.resolve_login_username(p_username text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_email text;
begin
  if p_username is null or btrim(p_username)='' then return null; end if;
  select p.email into v_email from public.profiles p
  where lower(p.username)=lower(btrim(p_username)) and p.is_active=true limit 1;
  return v_email;
end; $$;
revoke all on function public.resolve_login_username(text) from public;
grant execute on function public.resolve_login_username(text) to anon,authenticated;

create or replace function app_private.guard_profile_update()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'Authentication required.'; end if;
  if not public.is_admin() and not public.has_permission('EMPLOYEES_MANAGE','MANAGE','COMPANY') then
    if new.user_id is distinct from old.user_id
       or new.email is distinct from old.email
       or new.is_active is distinct from old.is_active
       or new.password_changed_at is distinct from old.password_changed_at
       or new.working_hours_per_day is distinct from old.working_hours_per_day
       or new.monthly_salary is distinct from old.monthly_salary
       or new.username is distinct from old.username then
      raise exception 'Only authorized employee management can change protected profile fields.';
    end if;
  end if;
  if new.display_name is null or char_length(btrim(new.display_name)) not between 1 and 80 then
    raise exception 'Display name must be 1-80 characters.';
  end if;
  if new.phone is not null and char_length(new.phone)>30 then raise exception 'Phone number is too long.'; end if;
  if new.monthly_salary < 0 then raise exception 'Monthly salary cannot be negative.'; end if;
  if new.working_hours_per_day < 0 or new.working_hours_per_day > 24 then raise exception 'Working hours must be between 0 and 24.'; end if;
  return new;
end; $$;
drop trigger if exists trg_profiles_security_guard on public.profiles;
create trigger trg_profiles_security_guard before update on public.profiles for each row execute function app_private.guard_profile_update();

drop trigger if exists trg_sync_compensation_after_profile on public.profiles;
drop view if exists public.monthly_payroll_summary;

create or replace function app_private.sync_employee_compensation(p_employee_id uuid, p_month date)
returns void language plpgsql security definer set search_path = '' as $$
declare r record; grp text; admin_id uuid; dept_code text;
begin
  select * into r from app_private.calculate_monthly_payroll_internal(p_employee_id,p_month) limit 1;
  if not found then return; end if;
  select d.code into dept_code from public.employee_departments ed join public.departments d on d.id=ed.department_id
  where ed.employee_id=p_employee_id and ed.is_active=true order by ed.is_primary desc,ed.assigned_at asc limit 1;
  select p.user_id into admin_id from public.profiles p where p.is_active and exists(
    select 1 from public.employee_roles er join public.roles ro on ro.id=er.role_id where er.employee_id=p.user_id and ro.code='ADMIN'
  ) order by p.created_at limit 1;
  grp:=case when dept_code='SURVEY_FIELD' then 'SURVEY_FIELD_EMPLOYEE'
            when dept_code in ('SURVEY_OFFICE','ARCHITECTURE','STRUCTURAL','ACCOUNTING') then 'OFFICE_EMPLOYEE'
            else 'MISCELLANEOUS' end;
  if admin_id is null then return; end if;
  insert into public.compensations(employee_id,compensation_group,compensation_month,amount,status,notes,created_by,working_days,present_days,leave_days,holiday_days,sunday_days,worked_minutes,payable_days)
  values(p_employee_id,grp,date_trunc('month',p_month)::date,r.gross_pay,'PENDING',format('Auto-calculated: %s present / %s working days; Sundays, holidays and approved leaves excluded from payable denominator.',r.present_days,r.working_days),admin_id,r.working_days,r.present_days,r.leave_days,r.holiday_days,r.sunday_days,r.worked_minutes,r.payable_days)
  on conflict(employee_id,compensation_month,compensation_group) do update set amount=excluded.amount,working_days=excluded.working_days,present_days=excluded.present_days,leave_days=excluded.leave_days,holiday_days=excluded.holiday_days,sunday_days=excluded.sunday_days,worked_minutes=excluded.worked_minutes,payable_days=excluded.payable_days,notes=excluded.notes,updated_at=now();
end; $$;

alter table public.profiles drop column if exists role;
alter table public.profiles drop column if exists department;
alter table public.attendance drop column if exists notes;
alter table public.daily_progress drop column if exists summary;
alter table public.daily_progress drop column if exists blockers;
alter table public.daily_progress drop column if exists next_action;

create trigger trg_sync_compensation_after_profile after insert or update of monthly_salary on public.profiles for each row execute function app_private.sync_compensation_after_profile();

create or replace function app_private.guard_project_write()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'Authentication required.'; end if;
  if tg_op='INSERT' then
    new.created_by := (select auth.uid());
    new.assigned_by := (select auth.uid());
  else
    new.created_by := old.created_by;
    new.assigned_by := old.assigned_by;
    if new.assigned_to is distinct from old.assigned_to
       and not public.has_permission('PROJECTS_ASSIGN','ASSIGN','COMPANY')
       and not public.has_permission('WORK_ASSIGN','ASSIGN','COMPANY') then
      raise exception 'You are not authorized to change project assignment.';
    end if;
  end if;
  if new.name is null or char_length(btrim(new.name)) not between 1 and 200 then raise exception 'Project name must be 1-200 characters.'; end if;
  if new.budget < 0 then raise exception 'Project budget cannot be negative.'; end if;
  if new.overall_progress < 0 or new.overall_progress > 100 then raise exception 'Project progress must be between 0 and 100.'; end if;
  return new;
end; $$;
drop trigger if exists trg_guard_project_write on public.projects;
create trigger trg_guard_project_write before insert or update on public.projects for each row execute function app_private.guard_project_write();

create or replace function app_private.guard_daily_progress_write()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'Authentication required.'; end if;
  if tg_op='INSERT' then new.employee_id := (select auth.uid());
  elsif old.employee_id is distinct from (select auth.uid()) and not public.has_permission('PROGRESS_EDIT','EDIT','COMPANY') then
    raise exception 'You are not authorized to change another employee progress record.';
  end if;
  if new.progress_percent < 0 or new.progress_percent > 100 then raise exception 'Progress must be between 0 and 100.'; end if;
  if new.completed_work is not null and char_length(new.completed_work)>5000 then raise exception 'Completed work is too long.'; end if;
  if new.pending_work is not null and char_length(new.pending_work)>5000 then raise exception 'Pending work is too long.'; end if;
  if new.remarks is not null and char_length(new.remarks)>5000 then raise exception 'Remarks are too long.'; end if;
  if not public.has_permission('PROGRESS_EDIT','EDIT','COMPANY') and new.progress_date <> app_private.office_today() then raise exception 'Daily progress can only be submitted for the current office date.'; end if;
  new.updated_by := (select auth.uid());
  return new;
end; $$;
drop trigger if exists trg_guard_daily_progress_write on public.daily_progress;
create trigger trg_guard_daily_progress_write before insert or update on public.daily_progress for each row execute function app_private.guard_daily_progress_write();
