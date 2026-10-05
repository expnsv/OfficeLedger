-- Final server-side authorization hardening for Admin read-only operational tracking.

-- Use IST for the 28th-day attendance revision regardless of database UTC setting.
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

-- CLIENTS: remove creator/assigned bypass for Admin; actual EDIT permission is required.
drop policy if exists clients_update on public.clients;
create policy clients_update on public.clients for update to authenticated
using (
  app_private.has_permission('CLIENTS_EDIT','EDIT','COMPANY')
  or (not exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN')
      and (assigned_to=(select auth.uid()) or created_by=(select auth.uid())))
)
with check (
  app_private.has_permission('CLIENTS_EDIT','EDIT','COMPANY')
  or (not exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN')
      and (assigned_to=(select auth.uid()) or created_by=(select auth.uid())))
);

-- PROJECTS already uses the permission-aware project access function.
drop policy if exists projects_update on public.projects;
create policy projects_update on public.projects for update to authenticated
using (app_private.can_access_project(id,'PROJECTS_EDIT','EDIT'))
with check (app_private.can_access_project(id,'PROJECTS_EDIT','EDIT'));

-- DAILY PROGRESS: Admin is tracking-only; employees retain own edit through permission.
drop policy if exists daily_progress_update on public.daily_progress;
create policy daily_progress_update on public.daily_progress for update to authenticated
using (
  app_private.has_permission('PROGRESS_EDIT','EDIT','COMPANY')
  or ((employee_id=(select auth.uid())) and not exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN')
      and app_private.has_permission('PROGRESS_EDIT','EDIT','OWN'))
)
with check (
  app_private.has_permission('PROGRESS_EDIT','EDIT','COMPANY')
  or ((employee_id=(select auth.uid())) and not exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN')
      and app_private.has_permission('PROGRESS_EDIT','EDIT','OWN'))
);

-- ATTENDANCE: Admin cannot use the employee self-mark/update bypass.
drop policy if exists attendance_insert on public.attendance;
create policy attendance_insert on public.attendance for insert to authenticated
with check (
  (app_private.has_permission('ATTENDANCE_CREATE','CREATE','COMPANY'))
  or ((employee_id=(select auth.uid()))
      and not exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN')
      and attendance_date=app_private.office_today())
);

drop policy if exists attendance_update on public.attendance;
create policy attendance_update on public.attendance for update to authenticated
using (
  app_private.has_permission('ATTENDANCE_EDIT','EDIT','COMPANY')
  or ((employee_id=(select auth.uid()))
      and not exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN')
      and ((attendance_date=app_private.office_today()) or app_private.attendance_correction_window(attendance_date)))
)
with check (
  app_private.has_permission('ATTENDANCE_EDIT','EDIT','COMPANY')
  or ((employee_id=(select auth.uid()))
      and not exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN')
      and ((attendance_date=app_private.office_today()) or app_private.attendance_correction_window(attendance_date)))
);

-- LEAVE: Admin can approve/reject, but cannot arbitrarily edit request fields unless LEAVE_EDIT exists.
drop policy if exists leave_update on public.leave_requests;
create policy leave_update on public.leave_requests for update to authenticated
using (
  app_private.has_permission('LEAVE_EDIT','EDIT','COMPANY')
  or app_private.has_permission('LEAVE_APPROVE','APPROVE','COMPANY')
  or ((employee_id=(select auth.uid())) and status='PENDING' and app_private.has_permission('LEAVE_EDIT','EDIT','OWN'))
)
with check (
  app_private.has_permission('LEAVE_EDIT','EDIT','COMPANY')
  or app_private.has_permission('LEAVE_APPROVE','APPROVE','COMPANY')
  or ((employee_id=(select auth.uid())) and status='PENDING' and app_private.has_permission('LEAVE_EDIT','EDIT','OWN'))
);

-- INVOICE / SURVEY REPORT: Admin may assign view access, but cannot edit document content.
create or replace function app_private.guard_admin_document_content()
returns trigger language plpgsql security definer set search_path=public,app_private as $$
begin
  if exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN') then
    if tg_table_name='invoices' then
      if new.document_number is distinct from old.document_number
         or new.document_type is distinct from old.document_type
         or new.document_date is distinct from old.document_date
         or new.payload is distinct from old.payload
         or new.created_by is distinct from old.created_by then
        raise exception 'Administrator accounts are read-only for invoice content. Only document assignment may be changed.';
      end if;
    elsif tg_table_name='survey_reports' then
      if new.report_number is distinct from old.report_number
         or new.report_date is distinct from old.report_date
         or new.survey_date is distinct from old.survey_date
         or new.department_id is distinct from old.department_id
         or new.payload is distinct from old.payload
         or new.created_by is distinct from old.created_by then
        raise exception 'Administrator accounts are read-only for survey report content. Only document assignment may be changed.';
      end if;
    end if;
  end if;
  return new;
end; $$;

drop trigger if exists trg_admin_document_content_guard_invoice on public.invoices;
create trigger trg_admin_document_content_guard_invoice before update on public.invoices for each row execute function app_private.guard_admin_document_content();
drop trigger if exists trg_admin_document_content_guard_survey on public.survey_reports;
create trigger trg_admin_document_content_guard_survey before update on public.survey_reports for each row execute function app_private.guard_admin_document_content();

create or replace function public.open_attendance_revision()
returns integer language plpgsql security invoker set search_path=public,app_private as $$
begin
  if auth.uid() is null then raise exception 'Authentication required.'; end if;
  if extract(day from app_private.office_today())<>28 then raise exception 'Attendance revision is available only on the 28th of the month.'; end if;
  return app_private.open_attendance_revision_internal();
end; $$;

create or replace function public.submit_attendance_revision(p_attendance_id uuid,p_check_in timestamptz,p_check_out timestamptz,p_note text)
returns public.attendance language plpgsql security invoker set search_path=public,app_private as $$
begin
  if auth.uid() is null then raise exception 'Authentication required.'; end if;
  if extract(day from app_private.office_today())<>28 then raise exception 'Attendance revision is available only on the 28th of the month.'; end if;
  return app_private.submit_attendance_revision_internal(p_attendance_id,p_check_in,p_check_out,p_note);
end; $$;

revoke all on function public.open_attendance_revision() from public,anon;
grant execute on function public.open_attendance_revision() to authenticated;
revoke all on function public.submit_attendance_revision(uuid,timestamptz,timestamptz,text) from public,anon;
grant execute on function public.submit_attendance_revision(uuid,timestamptz,timestamptz,text) to authenticated;
