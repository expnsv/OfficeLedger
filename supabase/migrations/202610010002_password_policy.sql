-- OfficeLedger password lifecycle policy. Apply after 202610010001_officeledger.sql.
-- Passwords are handled only by Supabase Auth; this table stores lifecycle metadata, never passwords.

begin;

alter table public.profiles
  add column if not exists password_changed_at timestamptz;

-- Existing Admins are treated as having a password established at migration time.
update public.profiles
set password_changed_at = coalesce(password_changed_at, now())
where password_changed_at is null;

create or replace function public.mark_password_changed()
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  update public.profiles
  set password_changed_at = now(), updated_at = now()
  where user_id = auth.uid() and is_active = true;
  if not found then
    raise exception 'Active OfficeLedger profile not found.';
  end if;
end;
$$;

revoke all on function public.mark_password_changed() from public, anon;
grant execute on function public.mark_password_changed() to authenticated;

commit;
