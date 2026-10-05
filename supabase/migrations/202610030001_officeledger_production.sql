-- OfficeLedger production schema: multi-role, scoped permissions, project/client/payment ownership.
-- Run after enabling Supabase Auth. This migration is intentionally self-contained.

begin;
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  display_name text not null check (char_length(display_name) between 1 and 80),
  is_active boolean not null default true,
  department text,
  phone text,
  password_changed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z][A-Z0-9_]{1,40}$'),
  name text not null unique,
  description text,
  is_system boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  module text not null,
  action text not null check (action in ('VIEW','CREATE','EDIT','DELETE','APPROVE','ASSIGN','EXPORT','MANAGE')),
  field_name text,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.employee_roles (
  employee_id uuid not null references public.profiles(user_id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete cascade,
  assigned_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  primary key (employee_id, role_id)
);

create table if not exists public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  scope text not null default 'company' check (scope in ('own','assigned','team','department','company')),
  primary key (role_id, permission_id)
);

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 160),
  contact text,
  location text,
  department text,
  notes text,
  is_active boolean not null default true,
  created_by uuid not null references public.profiles(user_id),
  updated_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete restrict,
  name text not null,
  project_code text unique,
  department text,
  status text not null default 'ACTIVE' check (status in ('PLANNED','ACTIVE','ON_HOLD','COMPLETED','CANCELLED')),
  start_date date,
  due_date date,
  budget numeric(14,2) not null default 0 check (budget >= 0),
  description text,
  created_by uuid not null references public.profiles(user_id),
  updated_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.project_members (
  project_id uuid not null references public.projects(id) on delete cascade,
  employee_id uuid not null references public.profiles(user_id) on delete cascade,
  member_role text,
  assigned_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  primary key (project_id, employee_id)
);

create table if not exists public.work_assignments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete restrict,
  assigned_to uuid not null references public.profiles(user_id),
  assigned_by uuid not null references public.profiles(user_id),
  title text not null,
  description text,
  priority text not null default 'NORMAL' check (priority in ('LOW','NORMAL','HIGH','URGENT')),
  status text not null default 'ASSIGNED' check (status in ('ASSIGNED','IN_PROGRESS','BLOCKED','COMPLETED','CANCELLED')),
  due_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.daily_progress (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  assignment_id uuid references public.work_assignments(id) on delete set null,
  employee_id uuid not null references public.profiles(user_id),
  progress_date date not null default current_date,
  progress_percent numeric(5,2) not null default 0 check (progress_percent between 0 and 100),
  summary text not null,
  blockers text,
  next_action text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.attendance (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(user_id) on delete cascade,
  attendance_date date not null,
  check_in timestamptz,
  check_out timestamptz,
  mode text not null default 'OFFICE' check (mode in ('OFFICE','OUTDOOR','REMOTE')),
  office_network_verified boolean not null default false,
  notes text,
  updated_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(employee_id, attendance_date)
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  expense_group text not null check (expense_group in ('FLAT','OFFICE','SURVEY_FIELD')),
  category text not null,
  expense_date date not null default current_date,
  amount numeric(14,2) not null check (amount > 0),
  payment_method text,
  vendor text,
  client_id uuid references public.clients(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  description text,
  reference text,
  status text not null default 'PAID' check (status in ('PENDING','PAID','CANCELLED')),
  created_by uuid not null references public.profiles(user_id),
  updated_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.compensations (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid references public.profiles(user_id) on delete set null,
  compensation_group text not null check (compensation_group in ('SURVEY_FIELD_EMPLOYEE','OFFICE_EMPLOYEE','MISCELLANEOUS')),
  compensation_month date not null,
  amount numeric(14,2) not null check (amount >= 0),
  status text not null default 'PENDING' check (status in ('PENDING','PAID','CANCELLED')),
  notes text,
  created_by uuid not null references public.profiles(user_id),
  updated_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.client_payments (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete restrict,
  project_id uuid not null references public.projects(id) on delete restrict,
  payment_type text not null check (payment_type in ('ADVANCE','PARTIAL','FINAL')),
  payment_date date not null default current_date,
  amount numeric(14,2) not null check (amount > 0),
  payment_method text,
  reference text,
  notes text,
  supporting_file_id uuid,
  created_by uuid not null references public.profiles(user_id),
  updated_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.files (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.projects(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  uploaded_by uuid not null references public.profiles(user_id),
  storage_path text not null unique,
  file_name text not null,
  mime_type text,
  size_bytes bigint check (size_bytes >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(user_id),
  module text not null,
  action text not null,
  record_id uuid,
  field_name text,
  previous_value jsonb,
  new_value jsonb,
  reason text,
  occurred_at timestamptz not null default now()
);

create table if not exists public.settings (
  id text primary key default 'main',
  company_name text not null default 'OfficeLedger',
  currency text not null default 'INR',
  office_router_hint text,
  updated_by uuid references public.profiles(user_id),
  updated_at timestamptz not null default now()
);
insert into public.settings(id) values ('main') on conflict do nothing;

create index if not exists idx_projects_client on public.projects(client_id);
create index if not exists idx_project_members_employee on public.project_members(employee_id);
create index if not exists idx_assignments_employee on public.work_assignments(assigned_to);
create index if not exists idx_progress_project_date on public.daily_progress(project_id, progress_date desc);
create index if not exists idx_attendance_employee_date on public.attendance(employee_id, attendance_date desc);
create index if not exists idx_expenses_group_date on public.expenses(expense_group, expense_date desc);
create index if not exists idx_payments_project_date on public.client_payments(project_id, payment_date desc);
create index if not exists idx_payments_client_date on public.client_payments(client_id, payment_date desc);
create index if not exists idx_files_project on public.files(project_id);
create index if not exists idx_audit_occurred on public.audit_logs(occurred_at desc);

-- Seed system roles. Multiple roles may be assigned to the same employee.
insert into public.roles(code,name,description,is_system) values
('ADMIN','Admin','Full system management',true),
('ACCOUNTING','Accounting','Financial and accounting operations',true),
('SURVEY','Survey','Surveying and field work',true),
('LEAD','Lead','Department/team coordination',true),
('ASSOCIATE','Associate','Assigned work and own operational records',true)
on conflict(code) do update set name=excluded.name, description=excluded.description;

-- Permission catalog. Field-specific permissions are deliberately separate from module permissions.
insert into public.permissions(code,module,action,field_name,description) values
('EMPLOYEES_VIEW','EMPLOYEES','VIEW',null,'View employee directory'),
('EMPLOYEES_MANAGE','EMPLOYEES','MANAGE',null,'Manage employee accounts'),
('ROLES_MANAGE','ROLES','MANAGE',null,'Manage roles and permissions'),
('CLIENTS_VIEW','CLIENTS','VIEW',null,'View clients'),
('CLIENTS_CREATE','CLIENTS','CREATE',null,'Create clients'),
('CLIENTS_EDIT','CLIENTS','EDIT',null,'Edit authorized client fields'),
('CLIENTS_DELETE','CLIENTS','DELETE',null,'Delete/archive clients'),
('PROJECTS_VIEW','PROJECTS','VIEW',null,'View projects'),
('PROJECTS_CREATE','PROJECTS','CREATE',null,'Create projects'),
('PROJECTS_EDIT','PROJECTS','EDIT',null,'Edit projects'),
('PROJECTS_ASSIGN','PROJECTS','ASSIGN',null,'Assign project/team work'),
('WORK_VIEW','WORK','VIEW',null,'View assigned work'),
('WORK_CREATE','WORK','CREATE',null,'Create work assignments'),
('WORK_EDIT','WORK','EDIT',null,'Edit authorized work'),
('WORK_ASSIGN','WORK','ASSIGN',null,'Assign work to team members'),
('PROGRESS_VIEW','PROGRESS','VIEW',null,'View daily progress'),
('PROGRESS_CREATE','PROGRESS','CREATE',null,'Create daily progress'),
('PROGRESS_EDIT','PROGRESS','EDIT',null,'Edit own/authorized progress'),
('ATTENDANCE_VIEW','ATTENDANCE','VIEW',null,'View attendance'),
('ATTENDANCE_CREATE','ATTENDANCE','CREATE',null,'Mark attendance'),
('ATTENDANCE_EDIT','ATTENDANCE','EDIT',null,'Edit authorized attendance'),
('EXPENSES_VIEW','EXPENSES','VIEW',null,'View expenses'),
('EXPENSES_CREATE','EXPENSES','CREATE',null,'Create expenses'),
('EXPENSES_EDIT','EXPENSES','EDIT',null,'Edit authorized expenses'),
('EXPENSES_DELETE','EXPENSES','DELETE',null,'Delete/archive expenses'),
('COMPENSATIONS_VIEW','COMPENSATIONS','VIEW',null,'View compensations'),
('COMPENSATIONS_MANAGE','COMPENSATIONS','MANAGE',null,'Manage compensations'),
('PAYMENTS_VIEW','PAYMENTS','VIEW',null,'View authorized client payments'),
('PAYMENTS_CREATE','PAYMENTS','CREATE',null,'Create authorized client payments'),
('PAYMENTS_EDIT','PAYMENTS','EDIT',null,'Edit authorized client payments'),
('PAYMENTS_DELETE','PAYMENTS','DELETE',null,'Delete/archive payments'),
('PAYMENTS_AMOUNT_EDIT','PAYMENTS','EDIT','amount','Edit payment amount'),
('PAYMENTS_STATUS_EDIT','PAYMENTS','EDIT','status','Edit payment status'),
('PAYMENTS_REFERENCE_EDIT','PAYMENTS','EDIT','reference','Edit payment reference'),
('FILES_VIEW','FILES','VIEW',null,'View authorized files'),
('FILES_CREATE','FILES','CREATE',null,'Upload files'),
('FILES_DELETE','FILES','DELETE',null,'Delete authorized files'),
('REPORTS_VIEW','REPORTS','VIEW',null,'View reports'),
('REPORTS_EXPORT','REPORTS','EXPORT',null,'Export reports'),
('AUDIT_VIEW','AUDIT','VIEW',null,'View audit history'),
('SETTINGS_MANAGE','SETTINGS','MANAGE',null,'Manage workspace settings')
on conflict(code) do nothing;

-- Default role-permission mappings. Admin gets all permissions at company scope.
insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'company' from public.roles r cross join public.permissions p where r.code='ADMIN'
on conflict do nothing;

-- Accounting role: financial access, no employee/role/security administration.
insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'company' from public.roles r join public.permissions p on p.code in (
'CLIENTS_VIEW','PROJECTS_VIEW','PAYMENTS_VIEW','PAYMENTS_CREATE','PAYMENTS_EDIT','PAYMENTS_AMOUNT_EDIT','PAYMENTS_STATUS_EDIT','PAYMENTS_REFERENCE_EDIT',
'EXPENSES_VIEW','EXPENSES_CREATE','EXPENSES_EDIT','COMPENSATIONS_VIEW','COMPENSATIONS_MANAGE','REPORTS_VIEW','REPORTS_EXPORT','FILES_VIEW','FILES_CREATE') where r.code='ACCOUNTING'
on conflict do nothing;

insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'assigned' from public.roles r join public.permissions p on p.code in (
'CLIENTS_VIEW','PROJECTS_VIEW','PAYMENTS_VIEW','PAYMENTS_CREATE','PAYMENTS_EDIT','PAYMENTS_AMOUNT_EDIT','PAYMENTS_STATUS_EDIT','PAYMENTS_REFERENCE_EDIT',
'EXPENSES_VIEW','EXPENSES_CREATE','EXPENSES_EDIT','PROGRESS_VIEW','FILES_VIEW','FILES_CREATE','REPORTS_VIEW') where r.code='SURVEY'
on conflict do nothing;

insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'team' from public.roles r join public.permissions p on p.code in (
'EMPLOYEES_VIEW','EMPLOYEES_VIEW','CLIENTS_VIEW','PROJECTS_VIEW','PROJECTS_ASSIGN','WORK_VIEW','WORK_CREATE','WORK_EDIT','WORK_ASSIGN','PROGRESS_VIEW','PROGRESS_CREATE','PROGRESS_EDIT',
'ATTENDANCE_VIEW','ATTENDANCE_EDIT','PAYMENTS_VIEW','PAYMENTS_EDIT','PAYMENTS_STATUS_EDIT','FILES_VIEW','FILES_CREATE','REPORTS_VIEW') where r.code='LEAD'
on conflict do nothing;

insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'own' from public.roles r join public.permissions p on p.code in (
'CLIENTS_VIEW','PROJECTS_VIEW','WORK_VIEW','WORK_EDIT','PROGRESS_VIEW','PROGRESS_CREATE','PROGRESS_EDIT','ATTENDANCE_VIEW','ATTENDANCE_CREATE','ATTENDANCE_EDIT',
'PAYMENTS_VIEW','PAYMENTS_CREATE','PAYMENTS_EDIT','PAYMENTS_AMOUNT_EDIT','PAYMENTS_STATUS_EDIT','PAYMENTS_REFERENCE_EDIT','FILES_VIEW','FILES_CREATE','REPORTS_VIEW') where r.code='ASSOCIATE'
on conflict do nothing;

create or replace function public.set_updated_at() returns trigger language plpgsql security definer set search_path=public as $$
begin new.updated_at=now(); return new; end; $$;

do $$ declare t text; begin
  foreach t in array array['profiles','clients','projects','work_assignments','daily_progress','attendance','expenses','compensations','client_payments','settings'] loop
    execute format('drop trigger if exists trg_%s_updated on public.%I',t,t);
    execute format('create trigger trg_%s_updated before update on public.%I for each row execute function public.set_updated_at()',t,t);
  end loop;
end $$;

create or replace function public.is_admin(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=uid and r.code='ADMIN')
  or exists(select 1 from public.profiles p where p.user_id=uid and p.is_active and p.user_id=uid and exists(select 1 from public.roles r join public.employee_roles er on er.role_id=r.id where er.employee_id=uid and r.code='ADMIN'));
$$;

create or replace function public.has_permission(p_code text, p_action text default null, p_scope text default null)
returns boolean language sql stable security definer set search_path=public as $$
  select public.is_admin(auth.uid()) or exists(
    select 1 from public.employee_roles er
    join public.role_permissions rp on rp.role_id=er.role_id
    join public.permissions p on p.id=rp.permission_id
    where er.employee_id=auth.uid() and p.code=p_code
      and (p_action is null or p.action=p_action)
      and (p_scope is null or rp.scope=p_scope)
  );
$$;

create or replace function public.has_record_permission(p_code text, p_action text, p_owner uuid default null, p_project uuid default null, p_client uuid default null)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare s text; ok boolean;
begin
  if public.is_admin(auth.uid()) then return true; end if;
  for s in select distinct rp.scope from public.employee_roles er join public.role_permissions rp on rp.role_id=er.role_id join public.permissions p on p.id=rp.permission_id where er.employee_id=auth.uid() and p.code=p_code and p.action=p_action loop
    if s='company' then return true; end if;
    if s='own' and p_owner=auth.uid() then return true; end if;
    if s='assigned' and (p_owner=auth.uid() or exists(select 1 from public.project_members pm where pm.project_id=p_project and pm.employee_id=auth.uid()) or exists(select 1 from public.work_assignments wa where wa.project_id=p_project and wa.assigned_to=auth.uid())) then return true; end if;
    if s='team' and (p_owner=auth.uid() or exists(select 1 from public.project_members pm where pm.project_id=p_project and pm.employee_id=auth.uid()) or exists(select 1 from public.projects pr join public.profiles me on me.user_id=auth.uid() where pr.id=p_project and pr.department is not null and pr.department=me.department)) then return true; end if;
    if s='department' and exists(select 1 from public.profiles p1 join public.profiles p2 on p2.user_id=auth.uid() where p1.user_id=p_owner and p1.department=p2.department and p1.department is not null) then return true; end if;
  end loop;
  return false;
end $$;

create or replace function public.can_access_payment(payment_project uuid, payment_client uuid, payment_owner uuid, p_code text, p_action text)
returns boolean language sql stable security definer set search_path=public as $$
  select public.has_record_permission(p_code,p_action,payment_owner,payment_project,payment_client)
  or exists(select 1 from public.project_members pm where pm.project_id=payment_project and pm.employee_id=auth.uid() and public.has_permission(p_code,p_action,'assigned'));
$$;

-- Audit helper for application/RPC use. Direct table insert is not granted to normal users.
create or replace function public.write_audit(p_module text,p_action text,p_record_id uuid,p_field text,p_old jsonb,p_new jsonb,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
 insert into public.audit_logs(actor_id,module,action,record_id,field_name,previous_value,new_value,reason)
 values(auth.uid(),p_module,p_action,p_record_id,p_field,p_old,p_new,p_reason);
end $$;

-- Payment updates use an RPC so field-level rules are enforced server-side, not just by UI.
create or replace function public.update_client_payment(p_id uuid, p_amount numeric default null, p_payment_date date default null, p_payment_method text default null, p_reference text default null, p_notes text default null, p_status text default null)
returns public.client_payments language plpgsql security definer set search_path=public as $$
declare old public.client_payments; newrow public.client_payments; begin
 select * into old from public.client_payments where id=p_id for update;
 if old.id is null then raise exception 'Payment not found'; end if;
 if not public.can_access_payment(old.project_id,old.client_id,old.created_by,'PAYMENTS_EDIT','EDIT') then raise exception 'You are not authorized to edit this payment'; end if;
 if p_amount is not null and p_amount<>old.amount and not public.has_permission('PAYMENTS_AMOUNT_EDIT','EDIT') then raise exception 'You are not authorized to edit the payment amount'; end if;
 update public.client_payments set amount=coalesce(p_amount,amount), payment_date=coalesce(p_payment_date,payment_date), payment_method=coalesce(p_payment_method,payment_method), reference=coalesce(p_reference,reference), notes=coalesce(p_notes,notes), updated_by=auth.uid(), updated_at=now() where id=p_id returning * into newrow;
 perform public.write_audit('PAYMENTS','EDIT',p_id,null,to_jsonb(old),to_jsonb(newrow),null);
 return newrow;
end $$;

-- RLS
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.employee_roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.clients enable row level security;
alter table public.projects enable row level security;
alter table public.project_members enable row level security;
alter table public.work_assignments enable row level security;
alter table public.daily_progress enable row level security;
alter table public.attendance enable row level security;
alter table public.expenses enable row level security;
alter table public.compensations enable row level security;
alter table public.client_payments enable row level security;
alter table public.files enable row level security;
alter table public.audit_logs enable row level security;
alter table public.settings enable row level security;

-- Profiles
create policy profiles_select on public.profiles for select to authenticated using (user_id=auth.uid() or public.has_permission('EMPLOYEES_VIEW','VIEW','company'));
create policy profiles_admin_update on public.profiles for update to authenticated using (public.has_permission('EMPLOYEES_MANAGE','MANAGE','company')) with check (public.has_permission('EMPLOYEES_MANAGE','MANAGE','company'));

-- Metadata catalogs
create policy roles_select on public.roles for select to authenticated using (auth.uid() is not null);
create policy roles_manage on public.roles for all to authenticated using (public.has_permission('ROLES_MANAGE','MANAGE','company')) with check (public.has_permission('ROLES_MANAGE','MANAGE','company'));
create policy permissions_select on public.permissions for select to authenticated using (auth.uid() is not null);
create policy employee_roles_select on public.employee_roles for select to authenticated using (employee_id=auth.uid() or public.has_permission('EMPLOYEES_VIEW','VIEW','company'));
create policy employee_roles_manage on public.employee_roles for all to authenticated using (public.has_permission('ROLES_MANAGE','MANAGE','company')) with check (public.has_permission('ROLES_MANAGE','MANAGE','company'));
create policy role_permissions_select on public.role_permissions for select to authenticated using (auth.uid() is not null);
create policy role_permissions_manage on public.role_permissions for all to authenticated using (public.has_permission('ROLES_MANAGE','MANAGE','company')) with check (public.has_permission('ROLES_MANAGE','MANAGE','company'));

-- Clients/projects
create policy clients_select on public.clients for select to authenticated using (public.has_record_permission('CLIENTS_VIEW','VIEW',created_by,null,id));
create policy clients_insert on public.clients for insert to authenticated with check (public.has_permission('CLIENTS_CREATE','CREATE','company') or public.has_permission('CLIENTS_CREATE','CREATE','assigned'));
create policy clients_update on public.clients for update to authenticated using (public.has_record_permission('CLIENTS_EDIT','EDIT',created_by,null,id)) with check (public.has_record_permission('CLIENTS_EDIT','EDIT',created_by,null,id));
create policy clients_delete on public.clients for delete to authenticated using (public.has_record_permission('CLIENTS_DELETE','DELETE',created_by,null,id));

create policy projects_select on public.projects for select to authenticated using (public.has_record_permission('PROJECTS_VIEW','VIEW',created_by,id,client_id) or exists(select 1 from public.project_members pm where pm.project_id=id and pm.employee_id=auth.uid()));
create policy projects_insert on public.projects for insert to authenticated with check (public.has_permission('PROJECTS_CREATE','CREATE','company'));
create policy projects_update on public.projects for update to authenticated using (public.has_record_permission('PROJECTS_EDIT','EDIT',created_by,id,client_id)) with check (public.has_record_permission('PROJECTS_EDIT','EDIT',created_by,id,client_id));

create policy project_members_select on public.project_members for select to authenticated using (employee_id=auth.uid() or public.has_permission('PROJECTS_VIEW','VIEW','company') or public.has_permission('PROJECTS_ASSIGN','ASSIGN','team'));
create policy project_members_manage on public.project_members for all to authenticated using (public.has_record_permission('PROJECTS_ASSIGN','ASSIGN',assigned_by,project_id,null)) with check (public.has_record_permission('PROJECTS_ASSIGN','ASSIGN',assigned_by,project_id,null));

-- Work/progress
create policy work_select on public.work_assignments for select to authenticated using (assigned_to=auth.uid() or assigned_by=auth.uid() or public.has_record_permission('WORK_VIEW','VIEW',assigned_to,project_id,client_id));
create policy work_insert on public.work_assignments for insert to authenticated with check (public.has_record_permission('WORK_CREATE','CREATE',assigned_by,project_id,client_id) or public.has_record_permission('WORK_ASSIGN','ASSIGN',assigned_by,project_id,client_id));
create policy work_update on public.work_assignments for update to authenticated using (public.has_record_permission('WORK_EDIT','EDIT',assigned_to,project_id,client_id) or public.has_record_permission('WORK_ASSIGN','ASSIGN',assigned_by,project_id,client_id)) with check (public.has_record_permission('WORK_EDIT','EDIT',assigned_to,project_id,client_id) or public.has_record_permission('WORK_ASSIGN','ASSIGN',assigned_by,project_id,client_id));

create policy progress_select on public.daily_progress for select to authenticated using (employee_id=auth.uid() or public.has_record_permission('PROGRESS_VIEW','VIEW',employee_id,project_id,null));
create policy progress_insert on public.daily_progress for insert to authenticated with check (employee_id=auth.uid() and (public.has_permission('PROGRESS_CREATE','CREATE','own') or public.has_permission('PROGRESS_CREATE','CREATE','team') or public.is_admin()));
create policy progress_update on public.daily_progress for update to authenticated using (public.has_record_permission('PROGRESS_EDIT','EDIT',employee_id,project_id,null)) with check (public.has_record_permission('PROGRESS_EDIT','EDIT',employee_id,project_id,null));

-- Attendance
create policy attendance_select on public.attendance for select to authenticated using (employee_id=auth.uid() or public.has_record_permission('ATTENDANCE_VIEW','VIEW',employee_id,null,null));
create policy attendance_insert on public.attendance for insert to authenticated with check (employee_id=auth.uid() and (public.has_permission('ATTENDANCE_CREATE','CREATE','own') or public.is_admin()));
create policy attendance_update on public.attendance for update to authenticated using (public.has_record_permission('ATTENDANCE_EDIT','EDIT',employee_id,null,null)) with check (public.has_record_permission('ATTENDANCE_EDIT','EDIT',employee_id,null,null));

-- Expenses/compensation
create policy expenses_select on public.expenses for select to authenticated using (public.has_record_permission('EXPENSES_VIEW','VIEW',created_by,project_id,client_id));
create policy expenses_insert on public.expenses for insert to authenticated with check (public.has_permission('EXPENSES_CREATE','CREATE','company') or public.has_permission('EXPENSES_CREATE','CREATE','assigned'));
create policy expenses_update on public.expenses for update to authenticated using (public.has_record_permission('EXPENSES_EDIT','EDIT',created_by,project_id,client_id)) with check (public.has_record_permission('EXPENSES_EDIT','EDIT',created_by,project_id,client_id));
create policy expenses_delete on public.expenses for delete to authenticated using (public.has_record_permission('EXPENSES_DELETE','DELETE',created_by,project_id,client_id));
create policy compensation_select on public.compensations for select to authenticated using (employee_id=auth.uid() or public.has_permission('COMPENSATIONS_VIEW','VIEW','company'));
create policy compensation_manage on public.compensations for all to authenticated using (public.has_permission('COMPENSATIONS_MANAGE','MANAGE','company')) with check (public.has_permission('COMPENSATIONS_MANAGE','MANAGE','company'));

-- Payments: row scope follows project/client ownership; amount/status/reference fields are controlled by permissions/RPC.
create policy payments_select on public.client_payments for select to authenticated using (public.can_access_payment(project_id,client_id,created_by,'PAYMENTS_VIEW','VIEW'));
create policy payments_insert on public.client_payments for insert to authenticated with check (public.can_access_payment(project_id,client_id,created_by,'PAYMENTS_CREATE','CREATE'));
create policy payments_update on public.client_payments for update to authenticated using (public.can_access_payment(project_id,client_id,created_by,'PAYMENTS_EDIT','EDIT')) with check (public.can_access_payment(project_id,client_id,created_by,'PAYMENTS_EDIT','EDIT'));
create policy payments_delete on public.client_payments for delete to authenticated using (public.can_access_payment(project_id,client_id,created_by,'PAYMENTS_DELETE','DELETE'));

-- Files
create policy files_select on public.files for select to authenticated using (uploaded_by=auth.uid() or public.has_record_permission('FILES_VIEW','VIEW',uploaded_by,project_id,client_id));
create policy files_insert on public.files for insert to authenticated with check (uploaded_by=auth.uid() and (public.has_permission('FILES_CREATE','CREATE','own') or public.has_permission('FILES_CREATE','CREATE','assigned') or public.is_admin()));
create policy files_delete on public.files for delete to authenticated using (public.has_record_permission('FILES_DELETE','DELETE',uploaded_by,project_id,client_id));

create policy audit_select on public.audit_logs for select to authenticated using (public.has_permission('AUDIT_VIEW','VIEW','company'));
create policy settings_select on public.settings for select to authenticated using (auth.uid() is not null);
create policy settings_update on public.settings for update to authenticated using (public.has_permission('SETTINGS_MANAGE','MANAGE','company')) with check (public.has_permission('SETTINGS_MANAGE','MANAGE','company'));

-- No browser role gets direct DELETE on audit history. Audit writes happen through SECURITY DEFINER helpers/triggers.
revoke all on public.audit_logs from authenticated;
revoke delete on public.client_payments from authenticated;

grant select,insert,update on public.profiles to authenticated;
grant select on public.roles,public.permissions,public.employee_roles,public.role_permissions to authenticated;
grant select,insert,update,delete on public.clients,public.projects,public.project_members,public.work_assignments,public.daily_progress,public.attendance,public.expenses,public.compensations,public.client_payments,public.files,public.settings to authenticated;
grant execute on function public.has_permission(text,text,text),public.has_record_permission(text,text,uuid,uuid,uuid),public.can_access_payment(uuid,uuid,uuid,text,text),public.update_client_payment(uuid,numeric,date,text,text,text,text) to authenticated;

-- Storage bucket is private. Application should use signed/authenticated download APIs.
insert into storage.buckets(id,name,public,file_size_limit) values ('office-files','office-files',false,5242880) on conflict(id) do update set public=false,file_size_limit=5242880;
create policy office_files_read on storage.objects for select to authenticated using (bucket_id='office-files' and (owner_id=auth.uid()::text or exists(select 1 from public.files f where f.storage_path=name and public.has_record_permission('FILES_VIEW','VIEW',f.uploaded_by,f.project_id,f.client_id))));
create policy office_files_insert on storage.objects for insert to authenticated with check (bucket_id='office-files' and owner_id=auth.uid()::text);
create policy office_files_delete on storage.objects for delete to authenticated using (bucket_id='office-files' and (owner_id=auth.uid()::text or public.is_admin()));

commit;
