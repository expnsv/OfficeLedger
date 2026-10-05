-- OfficeLedger: Admin operational read-only model, exports, client-name entry, and IST attendance revision window.
-- Admin remains allowed to perform explicit management actions (roles/settings/approvals/assignments)
-- but cannot edit operational records or expense records through role permissions.

-- Remove Admin CRUD permissions for operational business records.
delete from public.role_permissions rp
using public.roles r, public.permissions p
where rp.role_id=r.id and rp.permission_id=p.id and r.code='ADMIN'
  and p.code in (
    'CLIENTS_CREATE','CLIENTS_EDIT','CLIENTS_DELETE',
    'PROJECTS_CREATE','PROJECTS_EDIT',
    'WORK_CREATE','WORK_EDIT','WORK_ASSIGN',
    'PROGRESS_CREATE','PROGRESS_EDIT',
    'ATTENDANCE_CREATE','ATTENDANCE_EDIT',
    'LEAVE_CREATE','LEAVE_EDIT',
    'FILES_CREATE','FILES_DELETE',
    'INVOICES_CREATE','INVOICES_EDIT',
    'SURVEY_REPORTS_CREATE','SURVEY_REPORTS_EDIT',
    'PAYMENTS_CREATE','PAYMENTS_EDIT','PAYMENTS_DELETE',
    'COMPENSATIONS_MANAGE'
  );

-- Admin can export tracking/financial read-only outputs, but never expenses themselves.
insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'COMPANY'
from public.roles r cross join public.permissions p
where r.code='ADMIN'
  and p.code in ('REPORTS_EXPORT','INVOICES_EXPORT','SURVEY_REPORTS_EXPORT','COMPENSATIONS_EXPORT','PAYMENTS_EXPORT')
  and not exists(select 1 from public.role_permissions x where x.role_id=r.id and x.permission_id=p.id and lower(x.scope)='company');

-- Explicitly ensure Admin has no expense permission, including export.
delete from public.role_permissions rp using public.roles r, public.permissions p
where rp.role_id=r.id and rp.permission_id=p.id and r.code='ADMIN' and lower(p.module)='expenses';

-- Admin must not update operational rows merely because the old broad policy allowed it.
-- These policies defer to actual role permissions; the Admin role now has no edit permission.
drop policy if exists clients_update on public.clients;
create policy clients_update on public.clients for update to authenticated
using (public.has_record_permission('CLIENTS_EDIT','EDIT',created_by,null,id))
with check (public.has_record_permission('CLIENTS_EDIT','EDIT',created_by,null,id));

drop policy if exists projects_update on public.projects;
create policy projects_update on public.projects for update to authenticated
using (public.has_record_permission('PROJECTS_EDIT','EDIT',created_by,id,client_id))
with check (public.has_record_permission('PROJECTS_EDIT','EDIT',created_by,id,client_id));

drop policy if exists progress_update on public.daily_progress;
create policy progress_update on public.daily_progress for update to authenticated
using (public.has_record_permission('PROGRESS_EDIT','EDIT',employee_id,project_id,null))
with check (public.has_record_permission('PROGRESS_EDIT','EDIT',employee_id,project_id,null));

drop policy if exists attendance_update on public.attendance;
create policy attendance_update on public.attendance for update to authenticated
using (public.has_record_permission('ATTENDANCE_EDIT','EDIT',employee_id,null,null))
with check (public.has_record_permission('ATTENDANCE_EDIT','EDIT',employee_id,null,null));

-- Attendance revision is always evaluated in the application timezone, not database UTC.
create or replace function app_private.office_today()
returns date language sql stable set search_path=public,app_private as $$
  select (now() at time zone 'Asia/Kolkata')::date;
$$;

create or replace function app_private.attendance_correction_window(p_date date)
returns boolean language sql stable set search_path=public,app_private as $$
  select extract(day from app_private.office_today())=28
     and date_trunc('month',p_date)=date_trunc('month',app_private.office_today())
     and p_date < app_private.office_today();
$$;

create or replace function public.open_attendance_revision()
returns integer language plpgsql security invoker set search_path=public,app_private as $$
begin
  if auth.uid() is null then raise exception 'Authentication required.'; end if;
  if extract(day from app_private.office_today())<>28 then
    raise exception 'Attendance revision is available only on the 28th of the month.';
  end if;
  return app_private.open_attendance_revision_internal();
end; $$;

create or replace function public.submit_attendance_revision(p_attendance_id uuid,p_check_in timestamptz,p_check_out timestamptz,p_note text)
returns public.attendance language plpgsql security invoker set search_path=public,app_private as $$
begin
  if auth.uid() is null then raise exception 'Authentication required.'; end if;
  if extract(day from app_private.office_today())<>28 then
    raise exception 'Attendance revision is available only on the 28th of the month.';
  end if;
  return app_private.submit_attendance_revision_internal(p_attendance_id,p_check_in,p_check_out,p_note);
end; $$;

-- Admin assignment of invoice/survey documents remains a management operation; document editing is not granted.
-- Existing assignment trigger/policies continue to allow Admin to change assigned_to only.

