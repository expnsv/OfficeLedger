-- OfficeLedger: hosted accounts, shared accounting data, and database-enforced access.
-- Apply this migration to a new Supabase project before opening the web app.

begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  email text not null unique,
  display_name text not null check (char_length(display_name) between 1 and 80),
  role text not null default 'EMPLOYEE' check (role in ('ADMIN', 'EMPLOYEE')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.settings (
  id text primary key check (id = 'main'),
  company_name text not null default 'Office' check (char_length(company_name) between 1 and 80),
  currency text not null default 'INR' check (currency ~ '^[A-Z]{3}$'),
  opening_petty_cash numeric(14, 2) not null default 0 check (opening_petty_cash >= 0),
  updated_by uuid references public.profiles (user_id) on delete set null,
  updated_at timestamptz not null default now()
);

insert into public.settings (id) values ('main') on conflict (id) do nothing;

create table if not exists public.records (
  id uuid primary key default gen_random_uuid(),
  transaction_id text not null unique check (char_length(transaction_id) between 1 and 80),
  category text not null check (category in (
    'Rent', 'Electricity', 'Salaries', 'GST', 'Petty Cash', 'Client Expenses',
    'Refunded Payments', 'Wi-Fi', 'Flat Maintenance', 'Washroom Cleaning',
    'Drinking Water Supply', 'Cleaner Expenses & Maintenance',
    'Tea Maker Expenses & Maintenance'
  )),
  record_date date not null,
  amount numeric(14, 2) not null check (amount >= 0),
  payment_method text,
  reference_number text,
  description text,
  created_by uuid references public.profiles (user_id) on delete set null,
  created_by_name text not null default '',
  created_at timestamptz not null default now(),
  updated_by uuid references public.profiles (user_id) on delete set null,
  updated_by_name text not null default '',
  updated_at timestamptz not null default now(),
  status text,
  client text,
  project text,
  vendor text,
  person text,
  employee_id uuid references public.profiles (user_id) on delete set null,
  related_record_id uuid references public.records (id) on delete restrict,
  archived_at timestamptz,
  archived_by uuid references public.profiles (user_id) on delete set null,
  attachment_id uuid,
  attachment_name text,
  attachment_path text,
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  constraint records_attachment_fields_together check (
    (attachment_id is null and attachment_name is null and attachment_path is null)
    or (attachment_id is not null and attachment_name is not null and attachment_path is not null)
  )
);

create index if not exists records_date_category_idx on public.records (record_date, category);
create index if not exists records_created_by_idx on public.records (created_by, record_date desc);
create index if not exists records_employee_idx on public.records (employee_id, record_date desc) where category = 'Salaries';
create index if not exists records_client_project_idx on public.records (client, project);
create index if not exists records_related_record_idx on public.records (related_record_id) where related_record_id is not null;
create index if not exists records_active_category_idx on public.records (category, record_date desc) where archived_at is null;
create unique index if not exists records_attachment_id_unique on public.records (attachment_id) where attachment_id is not null;

create table if not exists public.audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles (user_id) on delete set null,
  actor_name text not null default 'System',
  actor_role text not null default 'SYSTEM',
  action text not null,
  record_id text,
  category text not null default 'System',
  previous_value jsonb,
  new_value jsonb,
  occurred_at timestamptz not null default now()
);

create index if not exists audit_events_actor_time_idx on public.audit_events (actor_id, occurred_at desc);
create index if not exists audit_events_time_idx on public.audit_events (occurred_at desc);

create or replace function private.current_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.profiles as p
  where p.user_id = (select auth.uid())
    and p.is_active = true
  limit 1
$$;

create or replace function private.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles as p
    where p.user_id = (select auth.uid())
      and p.is_active = true
  )
$$;

revoke all on function private.current_role() from public, anon;
revoke all on function private.is_active_user() from public, anon;
grant execute on function private.current_role() to authenticated;
grant execute on function private.is_active_user() to authenticated;

create or replace function private.enforce_record_rules()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  actor_role text := private.current_role();
  actor_name text;
  source_row public.records%rowtype;
  already_refunded numeric(14, 2);
begin
  if actor_role is null then raise exception 'An active OfficeLedger account is required.'; end if;
  select p.display_name into actor_name from public.profiles as p where p.user_id = (select auth.uid());

  if tg_op = 'INSERT' then
    if new.created_by is distinct from (select auth.uid()) and actor_role <> 'ADMIN' then
      raise exception 'Employees can only create records under their own account.';
    end if;
    if new.archived_at is not null or new.archived_by is not null then
      raise exception 'New records cannot be created in an archived state.';
    end if;
    new.created_by := (select auth.uid());
    new.created_by_name := coalesce(actor_name, 'Unknown user');
    new.created_at := now();
  else
    if new.id is distinct from old.id
      or new.transaction_id is distinct from old.transaction_id
      or new.category is distinct from old.category
      or new.created_by is distinct from old.created_by
      or new.created_by_name is distinct from old.created_by_name
      or new.created_at is distinct from old.created_at then
      raise exception 'Record ID, transaction ID, and creation history are immutable.';
    end if;
    if actor_role = 'EMPLOYEE' then
      if old.category = 'Salaries' then
        if old.employee_id is distinct from (select auth.uid()) then
          raise exception 'Employees can only update their own salary records.';
        end if;
        if new.employee_id is distinct from old.employee_id
          or new.amount is distinct from old.amount
          or new.details ->> 'grossSalary' is distinct from old.details ->> 'grossSalary'
          or new.details ->> 'deductions' is distinct from old.details ->> 'deductions'
          or new.details ->> 'salaryMonth' is distinct from old.details ->> 'salaryMonth' then
          raise exception 'Employees cannot change salary amounts or salary month.';
        end if;
      elsif old.created_by is distinct from (select auth.uid()) then
        raise exception 'Employees can only update entries they created.';
      end if;
      if new.archived_at is distinct from old.archived_at
        or new.archived_by is distinct from old.archived_by then
        raise exception 'Employees cannot archive accounting records.';
      end if;
      if old.category = 'Refunded Payments' and new.related_record_id is distinct from old.related_record_id then
        raise exception 'Employees cannot change the original expense linked to a refund.';
      end if;
      if new.attachment_path is distinct from old.attachment_path
        and new.attachment_path is not null
        and (storage.foldername(new.attachment_path))[1] is distinct from (select auth.uid())::text then
        raise exception 'Employees can only attach files they uploaded.';
      end if;
    end if;
  end if;

  if tg_op = 'INSERT' and actor_role = 'EMPLOYEE' and new.attachment_path is not null
    and (storage.foldername(new.attachment_path))[1] is distinct from (select auth.uid())::text then
    raise exception 'Employees can only attach files they uploaded.';
  end if;

  new.updated_by := (select auth.uid());
  new.updated_by_name := coalesce(actor_name, 'Unknown user');
  new.updated_at := now();

  if new.category <> 'Salaries' and new.amount <= 0 then
    raise exception 'Accounting amounts must be greater than zero.';
  end if;

  if new.category = 'Salaries' then
    if new.employee_id is null then raise exception 'A salary record must identify an employee.'; end if;
    if coalesce((new.details ->> 'grossSalary')::numeric, 0) < coalesce((new.details ->> 'deductions')::numeric, 0) then
      raise exception 'Salary deductions cannot exceed gross salary.';
    end if;
    if round(coalesce((new.details ->> 'grossSalary')::numeric, 0) - coalesce((new.details ->> 'deductions')::numeric, 0), 2) <> new.amount then
      raise exception 'Net salary must equal gross salary less deductions.';
    end if;
  end if;

  if new.category = 'Refunded Payments' then
    if new.related_record_id is null then raise exception 'A refund must be linked to a client expense.'; end if;
    select * into source_row from public.records where id = new.related_record_id for update;
    if not found or source_row.category <> 'Client Expenses' or source_row.archived_at is not null then
      raise exception 'The linked client expense is unavailable.';
    end if;
    if coalesce((source_row.details ->> 'reimbursable')::boolean, false) is not true then
      raise exception 'The linked client expense is not marked reimbursable.';
    end if;
    select coalesce(sum(r.amount), 0) into already_refunded
      from public.records as r
      where r.category = 'Refunded Payments'
        and r.related_record_id = new.related_record_id
        and r.archived_at is null
        and r.id <> new.id;
    if already_refunded + new.amount > source_row.amount + 0.005 then
      raise exception 'Refund amount exceeds the outstanding client expense.';
    end if;
  end if;

  if new.category = 'Client Expenses' and new.archived_at is not null then
    if exists (
      select 1 from public.records as r
      where r.category = 'Refunded Payments'
        and r.related_record_id = new.id
        and r.archived_at is null
    ) then
      raise exception 'Archive linked refund records before archiving the client expense.';
    end if;
  end if;

  if new.category = 'Client Expenses' then
    if tg_op = 'UPDATE' and (new.amount is distinct from old.amount
      or new.details ->> 'reimbursable' is distinct from old.details ->> 'reimbursable') then
      select coalesce(sum(r.amount), 0) into already_refunded
        from public.records as r
        where r.category = 'Refunded Payments'
          and r.related_record_id = new.id
          and r.archived_at is null;
      if already_refunded > new.amount + 0.005
        or (already_refunded > 0 and coalesce((new.details ->> 'reimbursable')::boolean, false) is not true) then
        raise exception 'This expense has linked refunds; keep its reimbursable flag and amount consistent.';
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists officeledger_record_guard on public.records;
create trigger officeledger_record_guard
before insert or update on public.records
for each row execute function private.enforce_record_rules();

create or replace function private.write_record_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor public.profiles%rowtype;
  event_action text;
begin
  select * into actor from public.profiles where user_id = (select auth.uid());
  if tg_op = 'INSERT' then
    event_action := case
      when new.category = 'Refunded Payments' then 'Refund recorded'
      when new.status = 'Paid' then 'Payment recorded'
      else 'Created'
    end;
    insert into public.audit_events (actor_id, actor_name, actor_role, action, record_id, category, new_value)
    values ((select auth.uid()), coalesce(actor.display_name, 'System'), coalesce(actor.role, 'SYSTEM'), event_action,
      new.transaction_id, new.category, to_jsonb(new));
    return new;
  end if;
  event_action := case
    when old.archived_at is null and new.archived_at is not null then 'Deleted'
    when old.status is distinct from new.status then 'Status changed'
    else 'Updated'
  end;
  insert into public.audit_events (actor_id, actor_name, actor_role, action, record_id, category, previous_value, new_value)
  values ((select auth.uid()), coalesce(actor.display_name, 'System'), coalesce(actor.role, 'SYSTEM'), event_action,
    new.transaction_id, new.category, to_jsonb(old), to_jsonb(new));
  return new;
end;
$$;

drop trigger if exists officeledger_record_audit on public.records;
create trigger officeledger_record_audit
after insert or update on public.records
for each row execute function private.write_record_audit();

create or replace function private.write_profile_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor public.profiles%rowtype;
begin
  select * into actor from public.profiles where user_id = (select auth.uid());
  insert into public.audit_events (actor_id, actor_name, actor_role, action, record_id, category, previous_value, new_value)
  values ((select auth.uid()), coalesce(actor.display_name, 'System'), coalesce(actor.role, 'SYSTEM'),
    case when old.is_active is distinct from new.is_active then
      case when new.is_active then 'Employee activated' else 'Employee disabled' end
    else 'Employee profile updated' end,
    new.user_id::text, 'Employees', to_jsonb(old), to_jsonb(new));
  return new;
end;
$$;

drop trigger if exists officeledger_profile_audit on public.profiles;
create trigger officeledger_profile_audit
after update on public.profiles
for each row execute function private.write_profile_audit();

create or replace function private.write_settings_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor public.profiles%rowtype;
begin
  select * into actor from public.profiles where user_id = (select auth.uid());
  insert into public.audit_events (actor_id, actor_name, actor_role, action, record_id, category, previous_value, new_value)
  values ((select auth.uid()), coalesce(actor.display_name, 'System'), coalesce(actor.role, 'SYSTEM'),
    'Updated', new.id, 'Settings', to_jsonb(old), to_jsonb(new));
  return new;
end;
$$;

drop trigger if exists officeledger_settings_audit on public.settings;
create trigger officeledger_settings_audit
after update on public.settings
for each row execute function private.write_settings_audit();

revoke all on function private.enforce_record_rules() from public, anon, authenticated;
revoke all on function private.write_record_audit() from public, anon, authenticated;
revoke all on function private.write_profile_audit() from public, anon, authenticated;
revoke all on function private.write_settings_audit() from public, anon, authenticated;

create or replace function private.can_read_attachment(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_active_user()
    and (
      private.current_role() = 'ADMIN'
      or exists (
        select 1 from public.records as r
        where r.attachment_path = object_name
          and r.archived_at is null
          and (r.category <> 'Salaries' or r.employee_id = (select auth.uid()))
      )
      or (
        (storage.foldername(object_name))[1] = (select auth.uid())::text
        and not exists (select 1 from public.records as r where r.attachment_path = object_name)
      )
    )
$$;

revoke all on function private.can_read_attachment(text) from public, anon;
grant execute on function private.can_read_attachment(text) to authenticated;

alter table public.profiles enable row level security;
alter table public.settings enable row level security;
alter table public.records enable row level security;
alter table public.audit_events enable row level security;

drop policy if exists profiles_read_permitted on public.profiles;
create policy profiles_read_permitted on public.profiles
for select to authenticated
using (
  private.is_active_user()
  and (private.current_role() = 'ADMIN' or user_id = (select auth.uid()))
);

drop policy if exists profiles_admin_update_employees on public.profiles;
create policy profiles_admin_update_employees on public.profiles
for update to authenticated
using (private.current_role() = 'ADMIN' and role = 'EMPLOYEE')
with check (private.current_role() = 'ADMIN' and role = 'EMPLOYEE');

drop policy if exists settings_read_active_users on public.settings;
create policy settings_read_active_users on public.settings
for select to authenticated
using (private.is_active_user());

drop policy if exists settings_admin_update on public.settings;
create policy settings_admin_update on public.settings
for update to authenticated
using (private.current_role() = 'ADMIN')
with check (private.current_role() = 'ADMIN');

drop policy if exists records_read_permitted on public.records;
create policy records_read_permitted on public.records
for select to authenticated
using (
  private.is_active_user()
  and (
    private.current_role() = 'ADMIN'
    or (archived_at is null and (category <> 'Salaries' or employee_id = (select auth.uid())))
  )
);

drop policy if exists records_create_permitted on public.records;
create policy records_create_permitted on public.records
for insert to authenticated
with check (
  private.is_active_user()
  and (
    private.current_role() = 'ADMIN'
    or (private.current_role() = 'EMPLOYEE' and created_by = (select auth.uid())
      and archived_at is null and category <> 'Salaries')
  )
);

drop policy if exists records_update_permitted on public.records;
create policy records_update_permitted on public.records
for update to authenticated
using (
  private.is_active_user()
  and (
    private.current_role() = 'ADMIN'
    or (archived_at is null and (
      (category = 'Salaries' and employee_id = (select auth.uid()))
      or (category <> 'Salaries' and created_by = (select auth.uid()))
    ))
  )
)
with check (
  private.is_active_user()
  and (
    private.current_role() = 'ADMIN'
    or (archived_at is null and (
      (category = 'Salaries' and employee_id = (select auth.uid()))
      or (category <> 'Salaries' and created_by = (select auth.uid()))
    ))
  )
);

drop policy if exists audit_read_own_or_admin on public.audit_events;
create policy audit_read_own_or_admin on public.audit_events
for select to authenticated
using (
  private.is_active_user()
  and (private.current_role() = 'ADMIN' or actor_id = (select auth.uid()))
);

revoke all on table public.profiles, public.settings, public.records, public.audit_events from anon, authenticated;
grant all on table public.profiles, public.settings, public.records, public.audit_events to service_role;
grant select on table public.profiles, public.settings, public.records, public.audit_events to authenticated;
grant update (is_active, display_name) on table public.profiles to authenticated;
grant update (company_name, currency, opening_petty_cash, updated_by, updated_at) on table public.settings to authenticated;
grant insert (id, transaction_id, category, record_date, amount, payment_method, reference_number, description,
  created_by, created_by_name, created_at, status, client, project, vendor, person, employee_id,
  related_record_id, attachment_id, attachment_name, attachment_path, details) on table public.records to authenticated;
grant update (record_date, amount, payment_method, reference_number, description, updated_by, updated_by_name,
  updated_at, status, client, project, vendor, person, employee_id, related_record_id, archived_at,
  archived_by, attachment_id, attachment_name, attachment_path, details) on table public.records to authenticated;
revoke insert, update, delete, truncate, references, trigger on table public.audit_events from anon, authenticated;
revoke delete, truncate, references, trigger on table public.records, public.profiles, public.settings from anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit)
values ('office-attachments', 'office-attachments', false, 4194304)
on conflict (id) do update set public = false, file_size_limit = 4194304;

drop policy if exists officeledger_upload_own_files on storage.objects;
create policy officeledger_upload_own_files on storage.objects
for insert to authenticated
with check (
  bucket_id = 'office-attachments'
  and private.is_active_user()
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists officeledger_read_permitted_files on storage.objects;
create policy officeledger_read_permitted_files on storage.objects
for select to authenticated
using (
  bucket_id = 'office-attachments'
  and private.can_read_attachment(name)
);

drop policy if exists officeledger_delete_own_files on storage.objects;
create policy officeledger_delete_own_files on storage.objects
for delete to authenticated
using (
  bucket_id = 'office-attachments'
  and private.is_active_user()
  and ((storage.foldername(name))[1] = (select auth.uid())::text or private.current_role() = 'ADMIN')
);

commit;
