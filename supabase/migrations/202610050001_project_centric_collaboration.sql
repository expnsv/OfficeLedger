begin;

-- Central department model. No separate Approvals workflow is introduced.
create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z][A-Z0-9_]{1,40}$'),
  name text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.employee_departments (
  employee_id uuid not null references public.profiles(user_id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete cascade,
  assigned_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  primary key(employee_id,department_id)
);

insert into public.departments(code,name) values
('SURVEY_FIELD','Survey Field'),
('SURVEY_OFFICE','Survey Office'),
('ARCHITECTURE','Architecture'),
('STRUCTURAL','Structural'),
('ACCOUNTING','Accounting')
on conflict(code) do update set name=excluded.name;

-- Project-centric relationships.
alter table public.projects add column if not exists overall_progress numeric(5,2) not null default 0 check (overall_progress between 0 and 100);
alter table public.projects add column if not exists requirements text;
alter table public.projects add column if not exists pending_work text;
alter table public.projects add column if not exists remarks text;
alter table public.projects add column if not exists expected_completion_date date;
alter table public.projects add column if not exists actual_completion_date date;

create table if not exists public.project_departments (
  project_id uuid not null references public.projects(id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete restrict,
  created_by uuid not null references public.profiles(user_id),
  created_at timestamptz not null default now(),
  primary key(project_id,department_id)
);

create table if not exists public.work_types (
  id uuid primary key default gen_random_uuid(),
  department_id uuid not null references public.departments(id) on delete restrict,
  code text not null unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(department_id,name)
);

insert into public.work_types(department_id,code,name)
select d.id,x.code,x.name from public.departments d cross join (values
 ('SURVEY_FIELD','SURVEY_TOPOGRAPHY','Topography'),
 ('SURVEY_FIELD','SURVEY_CONTOUR','Contour'),
 ('SURVEY_FIELD','SURVEY_MAPPING','Fixing / Mapping'),
 ('SURVEY_OFFICE','SURVEY_DRAWING','Survey Drawing'),
 ('SURVEY_OFFICE','SURVEY_REPORT','Survey Report'),
 ('ARCHITECTURE','ARCH_LAYOUT','Layout Plan'),
 ('ARCHITECTURE','ARCH_FLOOR','Floor Plan'),
 ('ARCHITECTURE','ARCH_COLUMN','Column Marking'),
 ('ARCHITECTURE','ARCH_ELEVATION','Elevation'),
 ('STRUCTURAL','STRUCT_GENERAL','Structural Work')
) x(dept,code,name) where d.code=x.dept on conflict(code) do nothing;

alter table public.work_assignments add column if not exists department_id uuid references public.departments(id);
alter table public.work_assignments add column if not exists work_type_id uuid references public.work_types(id);

create table if not exists public.assignment_history (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.work_assignments(id) on delete cascade,
  previous_assigned_to uuid references public.profiles(user_id),
  new_assigned_to uuid references public.profiles(user_id),
  previous_department_id uuid references public.departments(id),
  new_department_id uuid references public.departments(id),
  previous_work_type_id uuid references public.work_types(id),
  new_work_type_id uuid references public.work_types(id),
  reassigned_by uuid not null references public.profiles(user_id),
  reason text,
  created_at timestamptz not null default now()
);

alter table public.daily_progress add column if not exists department_id uuid references public.departments(id);
alter table public.daily_progress add column if not exists work_type_id uuid references public.work_types(id);
alter table public.daily_progress add column if not exists updated_by uuid references public.profiles(user_id);
alter table public.daily_progress add column if not exists completed_work text;
alter table public.daily_progress add column if not exists pending_work text;
alter table public.daily_progress add column if not exists remarks text;

-- Attendance revision history.
create table if not exists public.attendance_revisions (
  id uuid primary key default gen_random_uuid(),
  attendance_id uuid not null references public.attendance(id) on delete cascade,
  employee_id uuid not null references public.profiles(user_id) on delete cascade,
  existing_status text,
  requested_status text,
  requested_check_in timestamptz,
  requested_check_out timestamptz,
  work_remarks text,
  supporting_file_id uuid,
  submitted_by uuid not null references public.profiles(user_id),
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references public.profiles(user_id),
  reviewed_at timestamptz,
  approval_status text not null default 'PENDING' check(approval_status in ('PENDING','APPROVED','REJECTED')),
  review_reason text
);

-- Requests: one place for Leave + Allowance/Advance.
create table if not exists public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(user_id) on delete cascade,
  start_date date not null,
  end_date date not null,
  reason text,
  status text not null default 'PENDING' check(status in ('PENDING','APPROVED','REJECTED')),
  reviewed_by uuid references public.profiles(user_id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(end_date >= start_date)
);

alter table public.expenses add column if not exists request_type text not null default 'EXPENSE' check(request_type in ('EXPENSE','ADVANCE_REQUEST'));

-- Document persistence for the supplied Invoice and Survey Report editors.
create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.projects(id) on delete set null,
  client_id uuid references public.clients(id) on delete set null,
  document_type text not null default 'QUOTATION' check(document_type in ('QUOTATION','TAX_INVOICE')),
  document_number text not null unique,
  document_date date not null default current_date,
  payload jsonb not null default '{}'::jsonb,
  verification_hash text,
  created_by uuid not null references public.profiles(user_id),
  updated_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.survey_reports (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.projects(id) on delete set null,
  report_number text not null unique,
  report_date date not null default current_date,
  survey_date date,
  department_id uuid references public.departments(id),
  payload jsonb not null default '{}'::jsonb,
  verification_hash text,
  created_by uuid not null references public.profiles(user_id),
  updated_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Centralized file metadata extensions.
alter table public.files add column if not exists bucket text not null default 'office-files';
alter table public.files add column if not exists extension text;
alter table public.files add column if not exists department_id uuid references public.departments(id);
alter table public.files add column if not exists work_type_id uuid references public.work_types(id);
alter table public.files add column if not exists record_type text;
alter table public.files add column if not exists record_id uuid;
alter table public.files add column if not exists visibility text not null default 'CONTEXT' check(visibility in ('CONTEXT','PRIVATE'));
alter table public.files add column if not exists version integer not null default 1;
alter table public.files add column if not exists deleted_at timestamptz;

create table if not exists public.file_shares (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references public.files(id) on delete cascade,
  sender_id uuid not null references public.profiles(user_id) on delete cascade,
  recipient_id uuid not null references public.profiles(user_id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(file_id,sender_id,recipient_id)
);

create table if not exists public.file_versions (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references public.files(id) on delete cascade,
  version integer not null,
  storage_path text not null unique,
  file_name text not null,
  size_bytes bigint check(size_bytes >= 0),
  uploaded_by uuid not null references public.profiles(user_id),
  created_at timestamptz not null default now(),
  unique(file_id,version)
);

-- Private one-to-one chat.
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  unique(id)
);

create table if not exists public.conversation_participants (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  employee_id uuid not null references public.profiles(user_id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key(conversation_id,employee_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(user_id) on delete cascade,
  body text not null check(char_length(body) between 1 and 5000),
  sent_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz
);

create table if not exists public.message_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  file_id uuid not null references public.files(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(message_id,file_id)
);

create index if not exists idx_project_departments_department on public.project_departments(department_id);
create index if not exists idx_work_types_department on public.work_types(department_id);
create index if not exists idx_assignment_history_assignment on public.assignment_history(assignment_id,created_at desc);
create index if not exists idx_progress_employee_date on public.daily_progress(employee_id,progress_date desc);
create index if not exists idx_attendance_revisions_employee on public.attendance_revisions(employee_id,submitted_at desc);
create index if not exists idx_leave_employee_date on public.leave_requests(employee_id,start_date desc);
create index if not exists idx_invoices_project_date on public.invoices(project_id,document_date desc);
create index if not exists idx_survey_reports_project_date on public.survey_reports(project_id,report_date desc);
create index if not exists idx_files_record on public.files(record_type,record_id);
create index if not exists idx_file_shares_recipient on public.file_shares(recipient_id,created_at desc);
create index if not exists idx_messages_conversation on public.messages(conversation_id,sent_at desc);

-- Seed legacy profile.department into normalized memberships where a matching department exists.
insert into public.employee_departments(employee_id,department_id)
select p.user_id,d.id from public.profiles p join public.departments d on d.code=upper(coalesce(p.department,''))
on conflict do nothing;

-- Document permissions: Admin and Accounting for Invoice; Survey departments through explicit department memberships.
insert into public.permissions(code,module,action,field_name,description) values
('INVOICES_VIEW','INVOICE','VIEW',null,'View invoice/quotation documents'),
('INVOICES_CREATE','INVOICE','CREATE',null,'Create invoice/quotation documents'),
('INVOICES_EDIT','INVOICE','EDIT',null,'Edit invoice/quotation documents'),
('INVOICES_EXPORT','INVOICE','EXPORT',null,'Export invoice/quotation documents'),
('SURVEY_REPORTS_VIEW','SURVEY_REPORTS','VIEW',null,'View survey reports'),
('SURVEY_REPORTS_CREATE','SURVEY_REPORTS','CREATE',null,'Create survey reports'),
('SURVEY_REPORTS_EDIT','SURVEY_REPORTS','EDIT',null,'Edit survey reports'),
('SURVEY_REPORTS_EXPORT','SURVEY_REPORTS','EXPORT',null,'Export survey reports'),
('CHAT_VIEW','CHAT','VIEW',null,'View private one-to-one conversations'),
('CHAT_CREATE','CHAT','CREATE',null,'Create/send private messages'),
('CHAT_EDIT','CHAT','EDIT',null,'Edit own messages'),
('CHAT_DELETE','CHAT','DELETE',null,'Delete own messages'),
('CHAT_SHARE','CHAT','SHARE',null,'Share private chat attachments'),
('FILES_UPLOAD','FILES','UPLOAD',null,'Upload authorized files'),
('FILES_DOWNLOAD','FILES','DOWNLOAD',null,'Download authorized files'),
('FILES_SHARE','FILES','SHARE',null,'Share private files')
on conflict(code) do nothing;

insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'company' from public.roles r join public.permissions p on p.code in ('INVOICES_VIEW','INVOICES_CREATE','INVOICES_EDIT','INVOICES_EXPORT') where r.code in ('ADMIN','ACCOUNTING') on conflict do nothing;
insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'department' from public.roles r join public.permissions p on p.code in ('SURVEY_REPORTS_VIEW','SURVEY_REPORTS_CREATE','SURVEY_REPORTS_EDIT','SURVEY_REPORTS_EXPORT') where r.code in ('LEAD','ASSOCIATE','SURVEY') on conflict do nothing;
insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'own' from public.roles r join public.permissions p on p.code in ('CHAT_VIEW','CHAT_CREATE','CHAT_EDIT','CHAT_DELETE','CHAT_SHARE','FILES_UPLOAD','FILES_DOWNLOAD','FILES_SHARE') where r.code in ('ADMIN','ACCOUNTING','LEAD','ASSOCIATE','SURVEY') on conflict do nothing;

-- RLS
alter table public.departments enable row level security;
alter table public.employee_departments enable row level security;
alter table public.project_departments enable row level security;
alter table public.work_types enable row level security;
alter table public.assignment_history enable row level security;
alter table public.attendance_revisions enable row level security;
alter table public.leave_requests enable row level security;
alter table public.invoices enable row level security;
alter table public.survey_reports enable row level security;
alter table public.file_shares enable row level security;
alter table public.file_versions enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.messages enable row level security;
alter table public.message_attachments enable row level security;

create policy departments_select on public.departments for select to authenticated using (auth.uid() is not null);
create policy employee_departments_select on public.employee_departments for select to authenticated using (employee_id=auth.uid() or public.is_admin());
create policy employee_departments_manage on public.employee_departments for all to authenticated using (public.is_admin()) with check(public.is_admin());
create policy project_departments_select on public.project_departments for select to authenticated using (public.has_record_permission('PROJECTS_VIEW','VIEW',null,project_id,null) or public.is_admin());
create policy project_departments_manage on public.project_departments for all to authenticated using (public.has_permission('PROJECTS_ASSIGN','ASSIGN','company') or public.is_admin()) with check(public.has_permission('PROJECTS_ASSIGN','ASSIGN','company') or public.is_admin());
create policy work_types_select on public.work_types for select to authenticated using (auth.uid() is not null);
create policy work_types_manage on public.work_types for all to authenticated using (public.is_admin()) with check(public.is_admin());
create policy assignment_history_select on public.assignment_history for select to authenticated using (public.has_record_permission('WORK_VIEW','VIEW',new_assigned_to,assignment_id,null) or public.is_admin());
create policy attendance_revisions_select on public.attendance_revisions for select to authenticated using (employee_id=auth.uid() or public.is_admin());
create policy attendance_revisions_insert on public.attendance_revisions for insert to authenticated with check(employee_id=auth.uid() or public.is_admin());
create policy attendance_revisions_update on public.attendance_revisions for update to authenticated using (public.is_admin()) with check(public.is_admin());
create policy leave_select on public.leave_requests for select to authenticated using (employee_id=auth.uid() or public.is_admin());
create policy leave_insert on public.leave_requests for insert to authenticated with check(employee_id=auth.uid() and status='PENDING');
create policy leave_update on public.leave_requests for update to authenticated using (public.is_admin() or (employee_id=auth.uid() and status='PENDING')) with check(public.is_admin() or (employee_id=auth.uid() and status='PENDING'));
create policy leave_delete on public.leave_requests for delete to authenticated using (public.is_admin());
create policy invoices_select on public.invoices for select to authenticated using (public.has_permission('INVOICES_VIEW','VIEW','company') or public.is_admin());
create policy invoices_insert on public.invoices for insert to authenticated with check(public.has_permission('INVOICES_CREATE','CREATE','company') or public.is_admin());
create policy invoices_update on public.invoices for update to authenticated using (public.has_permission('INVOICES_EDIT','EDIT','company') or public.is_admin()) with check(public.has_permission('INVOICES_EDIT','EDIT','company') or public.is_admin());
create policy survey_reports_select on public.survey_reports for select to authenticated using (public.is_admin() or (public.has_permission('SURVEY_REPORTS_VIEW','VIEW','department') and exists(select 1 from public.employee_departments ed where ed.employee_id=auth.uid() and ed.department_id=survey_reports.department_id)));
create policy survey_reports_insert on public.survey_reports for insert to authenticated with check(public.is_admin() or (public.has_permission('SURVEY_REPORTS_CREATE','CREATE','department') and created_by=auth.uid() and exists(select 1 from public.employee_departments ed where ed.employee_id=auth.uid() and ed.department_id=department_id)));
create policy survey_reports_update on public.survey_reports for update to authenticated using (public.is_admin() or (created_by=auth.uid() and public.has_permission('SURVEY_REPORTS_EDIT','EDIT','department'))) with check(public.is_admin() or (created_by=auth.uid() and public.has_permission('SURVEY_REPORTS_EDIT','EDIT','department')));
create policy file_shares_select on public.file_shares for select to authenticated using (sender_id=auth.uid() or recipient_id=auth.uid() or public.is_admin());
create policy file_shares_insert on public.file_shares for insert to authenticated with check(sender_id=auth.uid() and public.has_permission('FILES_SHARE','SHARE','own'));
create policy file_shares_delete on public.file_shares for delete to authenticated using (sender_id=auth.uid() or public.is_admin());
create policy file_versions_select on public.file_versions for select to authenticated using (uploaded_by=auth.uid() or public.is_admin() or exists(select 1 from public.files f where f.id=file_versions.file_id and public.has_record_permission('FILES_VIEW','VIEW',f.uploaded_by,f.project_id,f.client_id)));
create policy conversations_select on public.conversations for select to authenticated using (exists(select 1 from public.conversation_participants cp where cp.conversation_id=conversations.id and cp.employee_id=auth.uid()));
create policy conversations_insert on public.conversations for insert to authenticated with check(auth.uid() is not null);
create policy participants_select on public.conversation_participants for select to authenticated using (employee_id=auth.uid() or exists(select 1 from public.conversation_participants cp where cp.conversation_id=conversation_participants.conversation_id and cp.employee_id=auth.uid()));
create policy participants_insert on public.conversation_participants for insert to authenticated using(false) with check(false);
create policy messages_select on public.messages for select to authenticated using (exists(select 1 from public.conversation_participants cp where cp.conversation_id=messages.conversation_id and cp.employee_id=auth.uid()));
create policy messages_insert on public.messages for insert to authenticated with check(sender_id=auth.uid() and exists(select 1 from public.conversation_participants cp where cp.conversation_id=messages.conversation_id and cp.employee_id=auth.uid()));
create policy messages_update on public.messages for update to authenticated using(sender_id=auth.uid()) with check(sender_id=auth.uid());
create policy messages_delete on public.messages for delete to authenticated using(sender_id=auth.uid());
create policy message_attachments_select on public.message_attachments for select to authenticated using(exists(select 1 from public.messages m join public.conversation_participants cp on cp.conversation_id=m.conversation_id where m.id=message_attachments.message_id and cp.employee_id=auth.uid()));
create policy message_attachments_insert on public.message_attachments for insert to authenticated with check(exists(select 1 from public.messages m join public.conversation_participants cp on cp.conversation_id=m.conversation_id where m.id=message_attachments.message_id and cp.employee_id=auth.uid()));

-- Privileged creation of a one-to-one conversation avoids exposing a broad participant INSERT policy.
create or replace function public.create_private_conversation(p_other_employee uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare cid uuid; a uuid:=auth.uid();
begin
 if a is null or p_other_employee is null or a=p_other_employee then raise exception 'A private conversation requires two different authenticated employees'; end if;
 if not exists(select 1 from public.profiles where user_id=p_other_employee and is_active) then raise exception 'Employee is not active'; end if;
 select cp1.conversation_id into cid from public.conversation_participants cp1 join public.conversation_participants cp2 on cp2.conversation_id=cp1.conversation_id where cp1.employee_id=a and cp2.employee_id=p_other_employee limit 1;
 if cid is not null then return cid; end if;
 insert into public.conversations default values returning id into cid;
 insert into public.conversation_participants(conversation_id,employee_id) values(cid,a),(cid,p_other_employee);
 return cid;
end $$;
grant execute on function public.create_private_conversation(uuid) to authenticated;

do $$ declare t text; begin foreach t in array array['departments','employee_departments','project_departments','work_types','assignment_history','attendance_revisions','leave_requests','invoices','survey_reports','file_shares','file_versions','conversations','conversation_participants','messages','message_attachments'] loop execute format('grant select on public.%I to authenticated',t); end loop; end $$;
grant insert,update on public.leave_requests,public.attendance_revisions,public.messages,public.message_attachments to authenticated;
grant execute on function public.create_private_conversation(uuid) to authenticated;

commit;
