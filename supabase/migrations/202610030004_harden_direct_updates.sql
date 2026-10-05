begin;
-- Employees never receive broad table UPDATE for field-sensitive client/payment records.
revoke update on public.clients from authenticated;
revoke update on public.client_payments from authenticated;
grant execute on function public.update_client_fields(uuid,text,text,text,text,text) to authenticated;
grant execute on function public.update_client_payment(uuid,numeric,date,text,text,text,text) to authenticated;

-- Assigned/owned employee roles must retain access to their own authorized payment fields.
insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'assigned' from public.roles r join public.permissions p on p.code in ('PAYMENTS_AMOUNT_EDIT','PAYMENTS_STATUS_EDIT','PAYMENTS_REFERENCE_EDIT') where r.code in ('SURVEY','LEAD') on conflict do nothing;
insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'assigned' from public.roles r join public.permissions p on p.code='PROJECTS_VIEW' where r.code='ASSOCIATE' on conflict do nothing;

commit;
