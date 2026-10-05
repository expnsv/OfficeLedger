-- OfficeLedger final hardening: Admin expense exclusion, assigned document access,
-- reliable Admin role assignment, and monthly attendance revision on the 28th.

-- Admin does not receive expense-management permissions. Accounting remains the financial owner.
delete from public.role_permissions rp
using public.roles r, public.permissions p
where rp.role_id=r.id and rp.permission_id=p.id and r.code='ADMIN' and lower(p.module)='expenses';

insert into public.permissions(code,module,action,field_name,description) values
('INVOICES_ASSIGNED_VIEW','INVOICE','VIEW',null,'View invoice/quotation documents explicitly assigned to the employee'),
('SURVEY_REPORTS_ASSIGNED_VIEW','SURVEY_REPORTS','VIEW',null,'View survey reports explicitly assigned to the employee')
on conflict(code) do update set module=excluded.module,action=excluded.action,field_name=excluded.field_name,description=excluded.description;

alter table public.invoices add column if not exists assigned_to uuid references public.profiles(user_id);
alter table public.survey_reports add column if not exists assigned_to uuid references public.profiles(user_id);
create index if not exists idx_invoices_assigned_to on public.invoices(assigned_to);
create index if not exists idx_survey_reports_assigned_to on public.survey_reports(assigned_to);

insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'ASSIGNED' from public.roles r cross join public.permissions p
where r.code in ('ACCOUNTING','LEAD','ASSOCIATE') and p.code in ('INVOICES_ASSIGNED_VIEW','SURVEY_REPORTS_ASSIGNED_VIEW')
and not exists (select 1 from public.role_permissions x where x.role_id=r.id and x.permission_id=p.id);

create or replace function app_private.guard_document_assignment()
returns trigger language plpgsql security definer set search_path=public,app_private as $$
begin
 if tg_op='INSERT' then
   if new.assigned_to is not null and not exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=auth.uid() and r.code='ADMIN') and new.assigned_to is distinct from auth.uid() then
     raise exception 'Only an administrator can assign this document to another employee.';
   end if;
 elsif tg_op='UPDATE' and new.assigned_to is distinct from old.assigned_to then
   if not exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=auth.uid() and r.code='ADMIN') then
     raise exception 'Only an administrator can change document assignment.';
   end if;
 end if;
 return new;
end; $$;

drop trigger if exists trg_invoice_assignment_guard on public.invoices;
create trigger trg_invoice_assignment_guard before insert or update on public.invoices for each row execute function app_private.guard_document_assignment();
drop trigger if exists trg_survey_assignment_guard on public.survey_reports;
create trigger trg_survey_assignment_guard before insert or update on public.survey_reports for each row execute function app_private.guard_document_assignment();

-- Permission evaluation is permission-driven. Admin receives company access through its preloaded
-- permissions; the Admin role is not an implicit bypass for unrelated modules such as Expenses.
create or replace function app_private.has_permission(p_code text,p_action text,p_scope text default null)
returns boolean language sql stable security definer set search_path=public,app_private as $$
select exists(
  select 1 from public.employee_roles er
  join public.role_permissions rp on rp.role_id=er.role_id
  join public.permissions p on p.id=rp.permission_id
  where er.employee_id=auth.uid() and p.code=p_code and p.action=p_action
    and (p_scope is null or rp.scope=p_scope)
);
$$;

-- Exposed RPC wrappers are SECURITY INVOKER; privileged writes live in app_private SECURITY DEFINER helpers.
create or replace function public.admin_set_employee_roles(p_employee_id uuid,p_role_ids uuid[])
returns void language plpgsql security invoker set search_path=public,app_private as $$
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
 if not app_private.has_permission('EMPLOYEES_MANAGE','MANAGE','COMPANY') then raise exception 'Only authorized administrators can assign employee roles.'; end if;
 perform app_private.admin_set_employee_roles_internal(p_employee_id,p_role_ids,auth.uid());
end; $$;

create or replace function app_private.open_attendance_revision_internal()
returns integer language plpgsql security definer set search_path=public,app_private as $$
declare n integer;
begin
 perform set_config('app.officeledger_system_job','1',true);
 insert into public.attendance(employee_id,attendance_date,status,is_working_day,is_sunday,is_holiday,worked_minutes,scheduled_minutes)
 select auth.uid(),gs::date,'ABSENT',app_private.attendance_day_is_working(gs::date),extract(isodow from gs)::int=7,
        exists(select 1 from public.holidays h where h.holiday_date=gs::date and h.is_active),0,
        coalesce((select daily_work_minutes from public.attendance_settings where id=true),540)
 from generate_series(date_trunc('month',current_date)::date,current_date-1,interval '1 day') gs
 on conflict(employee_id,attendance_date) do nothing;
 get diagnostics n=row_count; return n;
end; $$;

create or replace function public.open_attendance_revision()
returns integer language plpgsql security invoker set search_path=public,app_private as $$
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
 if extract(day from current_date)<>28 then raise exception 'Attendance revision is available only on the 28th of the month.'; end if;
 return app_private.open_attendance_revision_internal();
end; $$;

create or replace function app_private.submit_attendance_revision_internal(p_attendance_id uuid,p_check_in timestamptz,p_check_out timestamptz,p_note text)
returns public.attendance language plpgsql security definer set search_path=public,app_private as $$
declare a public.attendance%rowtype;
begin
 select * into a from public.attendance where id=p_attendance_id and employee_id=auth.uid() for update;
 if not found then raise exception 'Attendance record not found.'; end if;
 if not app_private.attendance_correction_window(a.attendance_date) then raise exception 'Only forgotten attendance entries from the current month can be revised on the 28th.'; end if;
 if p_check_in is not null and p_check_in::date<>a.attendance_date then raise exception 'Check-in must belong to the attendance date.'; end if;
 if p_check_out is not null and p_check_out::date<>a.attendance_date then raise exception 'Check-out must belong to the attendance date.'; end if;
 if p_check_in is not null and p_check_out is not null and p_check_out<p_check_in then raise exception 'Check-out cannot be before check-in.'; end if;
 perform set_config('app.officeledger_system_job','1',true);
 update public.attendance set check_in=p_check_in,check_out=p_check_out,attendance_note=left(coalesce(p_note,''),1000),mode='OUTDOOR',office_network_verified=false,marked_location=case when p_check_in is null then 'Absent' else 'Monthly revision' end,marked_ip=null,updated_by=auth.uid(),updated_at=now()
 where id=p_attendance_id returning * into a;
 insert into public.attendance_revisions(attendance_id,employee_id,existing_status,requested_status,requested_check_in,requested_check_out,work_remarks,submitted_by,submitted_at,approval_status,review_reason)
 values(a.id,auth.uid(),'ABSENT',case when a.check_in is null then 'ABSENT' else 'PRESENT' end,a.check_in,a.check_out,left(coalesce(p_note,'Monthly attendance revision'),1000),auth.uid(),now(),'APPROVED','Employee monthly revision');
 return a;
end; $$;

create or replace function public.submit_attendance_revision(p_attendance_id uuid,p_check_in timestamptz,p_check_out timestamptz,p_note text)
returns public.attendance language plpgsql security invoker set search_path=public,app_private as $$
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
 if extract(day from current_date)<>28 then raise exception 'Attendance revision is available only on the 28th of the month.'; end if;
 return app_private.submit_attendance_revision_internal(p_attendance_id,p_check_in,p_check_out,p_note);
end; $$;

-- RLS init-plan optimization: evaluate auth.uid() once per statement.
drop policy if exists invoices_select on public.invoices;
create policy invoices_select on public.invoices for select to authenticated using (
 exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN')
 or app_private.has_permission('INVOICES_VIEW','VIEW','COMPANY')
 or (assigned_to=(select auth.uid()) and app_private.has_permission('INVOICES_ASSIGNED_VIEW','VIEW','ASSIGNED'))
);
drop policy if exists invoices_insert on public.invoices;
create policy invoices_insert on public.invoices for insert to authenticated with check (
 exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN')
 or (created_by=(select auth.uid()) and (app_private.has_permission('INVOICES_CREATE','CREATE','COMPANY') or app_private.has_permission('INVOICES_CREATE','CREATE','ASSIGNED')))
);
drop policy if exists invoices_update on public.invoices;
create policy invoices_update on public.invoices for update to authenticated using (
 exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN')
 or app_private.has_permission('INVOICES_EDIT','EDIT','COMPANY')
) with check (
 exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN')
 or app_private.has_permission('INVOICES_EDIT','EDIT','COMPANY')
);
drop policy if exists survey_reports_select on public.survey_reports;
create policy survey_reports_select on public.survey_reports for select to authenticated using (
 exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN')
 or (assigned_to=(select auth.uid()) and app_private.has_permission('SURVEY_REPORTS_ASSIGNED_VIEW','VIEW','ASSIGNED'))
 or app_private.has_permission('SURVEY_REPORTS_VIEW','VIEW','COMPANY')
 or (app_private.has_permission('SURVEY_REPORTS_VIEW','VIEW','DEPARTMENT') and exists(select 1 from public.employee_departments ed where ed.employee_id=(select auth.uid()) and ed.department_id=survey_reports.department_id and ed.is_active))
);
drop policy if exists survey_reports_insert on public.survey_reports;
create policy survey_reports_insert on public.survey_reports for insert to authenticated with check (
 exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN')
 or (created_by=(select auth.uid()) and (app_private.has_permission('SURVEY_REPORTS_CREATE','CREATE','COMPANY') or app_private.has_permission('SURVEY_REPORTS_CREATE','CREATE','DEPARTMENT')))
);
drop policy if exists survey_reports_update on public.survey_reports;
create policy survey_reports_update on public.survey_reports for update to authenticated using (
 exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN')
 or app_private.has_permission('SURVEY_REPORTS_EDIT','EDIT','COMPANY')
 or (created_by=(select auth.uid()) and app_private.has_permission('SURVEY_REPORTS_EDIT','EDIT','DEPARTMENT'))
) with check (
 exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN')
 or app_private.has_permission('SURVEY_REPORTS_EDIT','EDIT','COMPANY')
 or (created_by=(select auth.uid()) and app_private.has_permission('SURVEY_REPORTS_EDIT','EDIT','DEPARTMENT'))
);
