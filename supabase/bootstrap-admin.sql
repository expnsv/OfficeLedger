-- Run this once in the Supabase SQL Editor after creating the first Auth user.
-- OfficeLedger first Admin bootstrap for shreeaditya2025@gmail.com.
begin;

do $$
declare
  target_email text := lower(trim('shreeaditya2025@gmail.com'));
  target_user auth.users%rowtype;
  admin_count integer;
begin
  if target_email = '' then
    raise exception 'Admin email is required.';
  end if;

  select count(*) into admin_count from public.profiles where role = 'ADMIN';
  if admin_count > 0 then
    raise exception 'An Admin profile already exists. This bootstrap can only run before the first Admin is assigned.';
  end if;

  select * into target_user from auth.users where lower(email) = target_email limit 1;
  if target_user.id is null then
    raise exception 'Create this user in Supabase Authentication first: %', target_email;
  end if;

  insert into public.profiles (user_id, email, display_name, role, is_active, password_changed_at)
  values (
    target_user.id,
    lower(target_user.email),
    left(coalesce(nullif(trim(target_user.raw_user_meta_data ->> 'display_name'), ''),
      nullif(trim(target_user.raw_user_meta_data ->> 'name'), ''), split_part(target_user.email, '@', 1)), 80),
    'ADMIN',
    true,
    now()
  );

  insert into public.audit_events (actor_id, actor_name, actor_role, action, record_id, category, new_value)
  select user_id, display_name, 'ADMIN', 'Initial Admin created', user_id::text, 'Employees',
    jsonb_build_object('email', email, 'role', 'ADMIN')
  from public.profiles where user_id = target_user.id;
end;
$$;

commit;
