-- OfficeLedger: employee multi-role assignment + attendance engine + payroll automation.
-- Requires the production authorization/schema migrations before this migration.

create unique index if not exists employee_roles_employee_role_uidx on public.employee_roles(employee_id,role_id);

create table if not exists public.attendance_settings (
  id boolean primary key default true check (id=true),
  timezone text not null default 'Asia/Kolkata',
  office_start time not null default '09:30',
  office_end time not null default '18:30',
  working_days integer[] not null default array[1,2,3,4,5,6],
  daily_work_minutes integer not null default 540 check (daily_work_minutes>0),
  updated_by uuid references public.profiles(user_id),
  updated_at timestamptz not null default now()
);
insert into public.attendance_settings(id) values(true) on conflict(id) do nothing;

alter table public.attendance alter column status set default 'ABSENT';
alter table public.attendance add column if not exists is_working_day boolean not null default true;
alter table public.attendance add column if not exists late_minutes integer not null default 0;
alter table public.attendance add column if not exists scheduled_minutes integer not null default 540;
alter table public.attendance add column if not exists attendance_note text;

alter table public.compensations add column if not exists working_days integer not null default 0;
alter table public.compensations add column if not exists present_days integer not null default 0;
alter table public.compensations add column if not exists leave_days integer not null default 0;
alter table public.compensations add column if not exists holiday_days integer not null default 0;
alter table public.compensations add column if not exists sunday_days integer not null default 0;
alter table public.compensations add column if not exists worked_minutes bigint not null default 0;
alter table public.compensations add column if not exists payable_days numeric not null default 0;
create unique index if not exists compensations_employee_month_group_uidx on public.compensations(employee_id,compensation_month,compensation_group);

create or replace function app_private.attendance_day_is_working(p_date date)
returns boolean language sql stable security definer set search_path=public,app_private as $$
select extract(isodow from p_date)::int=any(coalesce((select working_days from public.attendance_settings where id=true),array[1,2,3,4,5,6]));
$$;

create or replace function app_private.guard_attendance_write()
returns trigger language plpgsql security definer set search_path=public,app_private as $$
declare is_admin boolean;
begin
  if current_setting('app.officeledger_system_job',true)='1' then return new; end if;
  select exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=(select auth.uid()) and r.code='ADMIN') into is_admin;
  if not is_admin then
    if tg_op='INSERT' then
      if new.employee_id is distinct from (select auth.uid()) then raise exception 'You can mark attendance only for yourself.'; end if;
      if new.attendance_date<>current_date then raise exception 'Attendance can only be marked for today.'; end if;
      new.check_in=now(); new.check_out=null;
    elsif tg_op='UPDATE' then
      if old.employee_id is distinct from (select auth.uid()) then raise exception 'You can update only your own attendance.'; end if;
      if old.attendance_date<>current_date and not app_private.attendance_correction_window(old.attendance_date) then raise exception 'Today attendance is expired for editing.'; end if;
      if new.attendance_date is distinct from old.attendance_date then raise exception 'Attendance date cannot be changed.'; end if;
      if new.check_in is distinct from old.check_in then raise exception 'Check-in time is system generated.'; end if;
      if old.check_out is not null and new.check_out is distinct from old.check_out then raise exception 'Check-out is already completed for this attendance.'; end if;
      if new.check_out is not null and new.check_out<old.check_in then raise exception 'Check-out cannot be before check-in.'; end if;
    end if;
  end if;
  return new;
end; $$;

create or replace function app_private.enforce_attendance_network()
returns trigger language plpgsql security definer set search_path=public,app_private as $$
begin
  if current_setting('app.officeledger_system_job',true)='1' then return new; end if;
  new.marked_ip:=app_private.request_client_ip();
  if app_private.is_office_network() then new.mode:='OFFICE';new.office_network_verified:=true;new.marked_location:='Office';
  else new.mode:='OUTDOOR';new.office_network_verified:=false;new.marked_location:=coalesce(nullif(new.marked_location,''),'Outdoor'); end if;
  return new;
end; $$;

create or replace function app_private.refresh_attendance_derived()
returns trigger language plpgsql security definer set search_path=public,app_private as $$
declare settings public.attendance_settings%rowtype; minutes integer:=0; late integer:=0; holiday boolean:=false; sunday boolean:=false; working boolean:=false; leave_id uuid;
begin
 select * into settings from public.attendance_settings where id=true;
 sunday:=extract(isodow from new.attendance_date)=7;
 working:=extract(isodow from new.attendance_date)::int=any(settings.working_days);
 select exists(select 1 from public.holidays h where h.holiday_date=new.attendance_date and h.is_active) into holiday;
 select lr.id into leave_id from public.leave_requests lr where lr.employee_id=new.employee_id and lr.leave_date=new.attendance_date and lr.status='APPROVED' order by lr.created_at desc limit 1;
 new.is_sunday:=sunday;new.is_holiday:=holiday;new.is_working_day:=working and not holiday and leave_id is null;new.leave_request_id:=coalesce(new.leave_request_id,leave_id);new.scheduled_minutes:=settings.daily_work_minutes;
 new.status:=case when new.check_in is null then 'ABSENT' else 'PRESENT' end;
 if new.check_in is not null and new.check_out is not null and new.check_out>=new.check_in then minutes:=floor(extract(epoch from(new.check_out-new.check_in))/60);new.worked_minutes:=greatest(minutes,0);elsif new.check_in is null then new.worked_minutes:=0;end if;
 if new.check_in is not null then late:=greatest(floor(extract(epoch from((new.check_in at time zone settings.timezone)::time-settings.office_start))/60),0);new.late_minutes:=late;else new.late_minutes:=0;new.mode:='OUTDOOR';new.office_network_verified:=false;new.marked_ip:=null;new.marked_location:='Absent';end if;
 return new;
end; $$;
drop trigger if exists trg_attendance_metrics on public.attendance;
drop trigger if exists trg_calculate_attendance_metrics on public.attendance;
drop trigger if exists zzz_attendance_metrics on public.attendance;
create trigger zzz_attendance_metrics before insert or update on public.attendance for each row execute function app_private.refresh_attendance_derived();

create or replace function app_private.calculate_monthly_payroll_internal(p_employee_id uuid,p_month date)
returns table(employee_id uuid,month_start date,month_end date,working_days integer,present_days integer,leave_days integer,holiday_days integer,sunday_days integer,worked_minutes bigint,monthly_salary numeric,payable_days numeric,gross_pay numeric)
language sql stable security definer set search_path=public,app_private as $$
with bounds as (select date_trunc('month',p_month)::date s,(date_trunc('month',p_month)+interval '1 month - 1 day')::date e),
cal as (select gs::date d from bounds b,generate_series(b.s,b.e,interval '1 day') gs),
flags as (select c.d,extract(isodow from c.d)::int dow,exists(select 1 from public.holidays h where h.holiday_date=c.d and h.is_active) hol,exists(select 1 from public.leave_requests l where l.employee_id=p_employee_id and l.leave_date=c.d and l.status='APPROVED') lv,coalesce((select a.status='PRESENT' from public.attendance a where a.employee_id=p_employee_id and a.attendance_date=c.d),false) present,coalesce((select a.worked_minutes from public.attendance a where a.employee_id=p_employee_id and a.attendance_date=c.d),0)::bigint mins from cal c),
agg as (select count(*) filter(where dow<>7 and not hol and not lv)::int working_days,count(*) filter(where dow<>7 and not hol and not lv and present)::int present_days,count(*) filter(where lv)::int leave_days,count(*) filter(where hol and dow<>7)::int holiday_days,count(*) filter(where dow=7)::int sunday_days,coalesce(sum(mins),0)::bigint worked_minutes from flags),
sal as (select coalesce(monthly_salary,0)::numeric monthly_salary from public.profiles where user_id=p_employee_id)
select p_employee_id,(select s from bounds),(select e from bounds),a.working_days,a.present_days,a.leave_days,a.holiday_days,a.sunday_days,a.worked_minutes,s.monthly_salary,case when a.working_days=0 then 0 else a.present_days::numeric end,case when a.working_days=0 then 0 else round(s.monthly_salary*(a.present_days::numeric/a.working_days::numeric),2) end from agg a cross join sal s;
$$;

create or replace function app_private.sync_employee_compensation(p_employee_id uuid,p_month date)
returns void language plpgsql security definer set search_path=public,app_private as $$
declare r record; grp text; admin_id uuid;
begin
 select * into r from app_private.calculate_monthly_payroll_internal(p_employee_id,p_month) limit 1;
 if not found then return; end if;
 select user_id into admin_id from public.profiles p where p.is_active and exists(select 1 from public.employee_roles er join public.roles ro on ro.id=er.role_id where er.employee_id=p.user_id and ro.code='ADMIN') order by p.created_at limit 1;
 grp:=case when (select department from public.profiles where user_id=p_employee_id)='SURVEY_FIELD' then 'SURVEY_FIELD_EMPLOYEE' when (select department from public.profiles where user_id=p_employee_id) in ('SURVEY_OFFICE','ARCHITECTURE','STRUCTURAL','ACCOUNTING') then 'OFFICE_EMPLOYEE' else 'MISCELLANEOUS' end;
 if admin_id is null then return; end if;
 insert into public.compensations(employee_id,compensation_group,compensation_month,amount,status,notes,created_by,working_days,present_days,leave_days,holiday_days,sunday_days,worked_minutes,payable_days)
 values(p_employee_id,grp,date_trunc('month',p_month)::date,r.gross_pay,'PENDING',format('Auto-calculated: %s present / %s working days; Sundays, holidays and approved leaves excluded from payable denominator.',r.present_days,r.working_days),admin_id,r.working_days,r.present_days,r.leave_days,r.holiday_days,r.sunday_days,r.worked_minutes,r.payable_days)
 on conflict(employee_id,compensation_month,compensation_group) do update set amount=excluded.amount,working_days=excluded.working_days,present_days=excluded.present_days,leave_days=excluded.leave_days,holiday_days=excluded.holiday_days,sunday_days=excluded.sunday_days,worked_minutes=excluded.worked_minutes,payable_days=excluded.payable_days,notes=excluded.notes,updated_at=now();
end; $$;

create or replace function app_private.sync_compensation_after_attendance() returns trigger language plpgsql security definer set search_path=public,app_private as $$ begin perform app_private.sync_employee_compensation(new.employee_id,new.attendance_date); return new; end; $$;
drop trigger if exists trg_sync_compensation_after_attendance on public.attendance;
create trigger trg_sync_compensation_after_attendance after insert or update on public.attendance for each row execute function app_private.sync_compensation_after_attendance();

create or replace function app_private.sync_compensation_after_leave() returns trigger language plpgsql security definer set search_path=public,app_private as $$ begin perform app_private.sync_employee_compensation(new.employee_id,new.leave_date); if tg_op='UPDATE' and (old.employee_id is distinct from new.employee_id or old.leave_date is distinct from new.leave_date) then perform app_private.sync_employee_compensation(old.employee_id,old.leave_date); end if; return new; end; $$;
drop trigger if exists trg_sync_compensation_after_leave on public.leave_requests;
create trigger trg_sync_compensation_after_leave after insert or update on public.leave_requests for each row execute function app_private.sync_compensation_after_leave();

create or replace function app_private.sync_compensation_after_holiday() returns trigger language plpgsql security definer set search_path=public,app_private as $$ declare uid uuid; begin for uid in select user_id from public.profiles where is_active loop perform app_private.sync_employee_compensation(uid,new.holiday_date); if tg_op='UPDATE' and old.holiday_date is distinct from new.holiday_date then perform app_private.sync_employee_compensation(uid,old.holiday_date); end if; end loop; return new; end; $$;
drop trigger if exists trg_sync_compensation_after_holiday on public.holidays;
create trigger trg_sync_compensation_after_holiday after insert or update on public.holidays for each row execute function app_private.sync_compensation_after_holiday();

create or replace function app_private.sync_compensation_after_profile() returns trigger language plpgsql security definer set search_path=public,app_private as $$ begin if tg_op='INSERT' or new.monthly_salary is distinct from old.monthly_salary or new.department is distinct from old.department then perform app_private.sync_employee_compensation(new.user_id,current_date); end if; return new; end; $$;
drop trigger if exists trg_sync_compensation_after_profile on public.profiles;
create trigger trg_sync_compensation_after_profile after insert or update of monthly_salary,department on public.profiles for each row execute function app_private.sync_compensation_after_profile();

alter table public.attendance_settings enable row level security;
drop policy if exists attendance_settings_read on public.attendance_settings;
drop policy if exists attendance_settings_manage on public.attendance_settings;
create policy attendance_settings_read on public.attendance_settings for select to authenticated using(true);
create policy attendance_settings_manage on public.attendance_settings for all to authenticated using(app_private.has_permission('SETTINGS_MANAGE','MANAGE','COMPANY')) with check(app_private.has_permission('SETTINGS_MANAGE','MANAGE','COMPANY'));
grant select on public.attendance_settings to authenticated;

-- Final security hardening for the public RPC surface.
create or replace function app_private.admin_set_employee_roles_internal(p_employee_id uuid,p_role_ids uuid[],p_assigned_by uuid)
returns void language plpgsql security definer set search_path=public,app_private as $$
declare rid uuid;
begin
 if p_employee_id is null then raise exception 'Employee is required.'; end if;
 if coalesce(array_length(p_role_ids,1),0)=0 then raise exception 'At least one role must be assigned.'; end if;
 if exists(select 1 from unnest(p_role_ids) x where not exists(select 1 from public.roles r where r.id=x)) then raise exception 'One or more selected roles are invalid.'; end if;
 delete from public.employee_roles where employee_id=p_employee_id;
 foreach rid in array p_role_ids loop insert into public.employee_roles(employee_id,role_id,assigned_by) values(p_employee_id,rid,p_assigned_by); end loop;
end; $$;

create or replace function public.admin_set_employee_roles(p_employee_id uuid,p_role_ids uuid[])
returns void language plpgsql security invoker set search_path=public,app_private as $$
begin
 if not app_private.has_permission('EMPLOYEES_MANAGE','MANAGE','COMPANY') then raise exception 'Only authorized administrators can assign employee roles.'; end if;
 perform app_private.admin_set_employee_roles_internal(p_employee_id,p_role_ids,(select auth.uid()));
end; $$;
revoke all on function public.admin_set_employee_roles(uuid,uuid[]) from anon,public;
grant execute on function public.admin_set_employee_roles(uuid,uuid[]) to authenticated;

create or replace function public.calculate_monthly_payroll(p_employee_id uuid,p_month date)
returns table(employee_id uuid,month_start date,month_end date,working_days integer,present_days integer,leave_days integer,holiday_days integer,sunday_days integer,worked_minutes bigint,monthly_salary numeric,payable_days numeric,gross_pay numeric)
language sql stable security invoker set search_path=public,app_private as $$
select * from app_private.calculate_monthly_payroll_internal(p_employee_id,p_month)
where p_employee_id=(select auth.uid()) or app_private.has_permission('COMPENSATIONS_VIEW','VIEW','COMPANY');
$$;
revoke all on function public.calculate_monthly_payroll(uuid,date) from anon,public;
grant execute on function public.calculate_monthly_payroll(uuid,date) to authenticated;

create or replace function app_private.ensure_daily_attendance_internal(p_date date)
returns integer language plpgsql security definer set search_path=public,app_private as $$
declare n integer;
begin
 perform set_config('app.officeledger_system_job','1',true);
 insert into public.attendance(employee_id,attendance_date,status,is_working_day,is_sunday,is_holiday,worked_minutes,scheduled_minutes)
 select p.user_id,p_date,'ABSENT',app_private.attendance_day_is_working(p_date),extract(isodow from p_date)=7,exists(select 1 from public.holidays h where h.holiday_date=p_date and h.is_active),0,coalesce((select daily_work_minutes from public.attendance_settings where id=true),540)
 from public.profiles p where p.is_active on conflict(employee_id,attendance_date) do nothing;
 get diagnostics n=row_count; return n;
end; $$;

create or replace function public.ensure_daily_attendance(p_date date default current_date)
returns integer language sql security invoker set search_path=public,app_private as $$
select app_private.ensure_daily_attendance_internal(p_date) where p_date=current_date;
$$;
revoke all on function public.ensure_daily_attendance(date) from anon,public;
grant execute on function public.ensure_daily_attendance(date) to authenticated;

revoke all on function app_private.admin_set_employee_roles_internal(uuid,uuid[],uuid) from public,anon,authenticated;
revoke all on function app_private.ensure_daily_attendance_internal(date) from public,anon,authenticated;

-- Avoid overlapping SELECT policies on attendance settings.
drop policy if exists attendance_settings_manage on public.attendance_settings;
drop policy if exists attendance_settings_insert on public.attendance_settings;
drop policy if exists attendance_settings_update on public.attendance_settings;
drop policy if exists attendance_settings_delete on public.attendance_settings;
create policy attendance_settings_insert on public.attendance_settings for insert to authenticated with check(app_private.has_permission('SETTINGS_MANAGE','MANAGE','COMPANY'));
create policy attendance_settings_update on public.attendance_settings for update to authenticated using(app_private.has_permission('SETTINGS_MANAGE','MANAGE','COMPANY')) with check(app_private.has_permission('SETTINGS_MANAGE','MANAGE','COMPANY'));
create policy attendance_settings_delete on public.attendance_settings for delete to authenticated using(app_private.has_permission('SETTINGS_MANAGE','MANAGE','COMPANY'));
create index if not exists attendance_settings_updated_by_idx on public.attendance_settings(updated_by);
