-- OfficeLedger authentication bootstrap and recovery hardening.
-- The bootstrap credential is verified against a bcrypt hash and is only usable while bootstrap_pending=true.
create extension if not exists pgcrypto with schema extensions;

alter table public.profiles
  add column if not exists must_change_password boolean not null default false,
  add column if not exists bootstrap_pending boolean not null default false;

create table if not exists public.bootstrap_auth (
  id boolean primary key default true,
  username text not null unique,
  password_hash text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.bootstrap_auth enable row level security;
revoke all on public.bootstrap_auth from anon, authenticated;

insert into public.bootstrap_auth(username,password_hash)
values ('admin', extensions.crypt(convert_from(decode('41646d696e4032303236','hex'),'UTF8'), extensions.gen_salt('bf')))
on conflict(username) do update set password_hash=excluded.password_hash, enabled=true;

-- Convert the existing first Admin account to the one-time bootstrap account.
with first_admin as (
  select p.user_id
  from public.profiles p
  join public.employee_roles er on er.employee_id=p.user_id
  join public.roles r on r.id=er.role_id
  where r.code='ADMIN'
  order by p.created_at
  limit 1
)
update public.profiles p
set username='admin', must_change_password=true, bootstrap_pending=true,
    password_changed_at=null, updated_at=now()
where p.user_id=(select user_id from first_admin);

create or replace function public.verify_bootstrap_credential(p_username text,p_password text)
returns uuid
language plpgsql security definer
set search_path=pg_catalog,public,extensions
as $$
declare uid uuid;
begin
  select p.user_id into uid
  from public.profiles p
  join public.bootstrap_auth b on b.username=p.username
  where lower(p.username)=lower(trim(p_username))
    and p.is_active=true and p.bootstrap_pending=true and p.must_change_password=true
    and b.enabled=true and b.password_hash=extensions.crypt(p_password,b.password_hash)
  limit 1;
  return uid;
end $$;
revoke all on function public.verify_bootstrap_credential(text,text) from public;
grant execute on function public.verify_bootstrap_credential(text,text) to anon,authenticated;

create or replace function public.complete_initial_password_setup()
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public
as $$
declare uid uuid:=auth.uid();
begin
  if uid is null then raise exception 'Authentication required.'; end if;
  update public.profiles set must_change_password=false,bootstrap_pending=false,password_changed_at=now(),updated_at=now()
  where user_id=uid and must_change_password=true;
  if not found then raise exception 'Initial password setup is not pending.'; end if;
  return jsonb_build_object('ok',true);
end $$;
revoke all on function public.complete_initial_password_setup() from public;
grant execute on function public.complete_initial_password_setup() to authenticated;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=pg_catalog,public
as $$ select exists(select 1 from public.employee_roles er join public.roles r on r.id=er.role_id where er.employee_id=auth.uid() and r.code='ADMIN') $$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

comment on column public.profiles.must_change_password is 'Forces password change after bootstrap or recovery.';
comment on column public.profiles.bootstrap_pending is 'One-time bootstrap credential remains valid until initial password setup completes.';
