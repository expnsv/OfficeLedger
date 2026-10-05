-- OfficeLedger first-admin bootstrap state.
-- This does NOT store a plaintext password. The hosted project migration creates the one-time bootstrap verifier.
-- The bootstrap login is:
--   Username: admin
--   Password: Admin@2026
-- After first login, the application forces a permanent 6/8-character mixed password.
begin;
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
commit;
