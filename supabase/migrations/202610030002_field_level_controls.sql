begin;
alter table public.client_payments add column if not exists status text not null default 'RECEIVED' check (status in ('PENDING','RECEIVED','RECONCILED','CANCELLED'));
insert into public.permissions(code,module,action,field_name,description) values
('CLIENTS_DEPARTMENT_EDIT','CLIENTS','EDIT','department','Edit client department'),
('CLIENTS_ASSIGN_EDIT','CLIENTS','EDIT','assignment','Edit client/project assignment')
on conflict(code) do nothing;

create or replace function public.update_client_fields(p_id uuid,p_name text default null,p_contact text default null,p_location text default null,p_department text default null,p_notes text default null)
returns public.clients language plpgsql security definer set search_path=public as $$
declare old public.clients; n public.clients;
begin
 select * into old from public.clients where id=p_id for update;
 if old.id is null then raise exception 'Client not found'; end if;
 if not public.has_record_permission('CLIENTS_EDIT','EDIT',old.created_by,null,old.id) then raise exception 'You are not authorized to edit this client'; end if;
 if p_department is not null and p_department<>coalesce(old.department,'') and not public.has_permission('CLIENTS_DEPARTMENT_EDIT','EDIT','company') then raise exception 'You are not authorized to change the client department'; end if;
 update public.clients set name=coalesce(p_name,name),contact=coalesce(p_contact,contact),location=coalesce(p_location,location),department=case when p_department is null then department else p_department end,notes=coalesce(p_notes,notes),updated_by=auth.uid(),updated_at=now() where id=p_id returning * into n;
 perform public.write_audit('CLIENTS','EDIT',p_id,null,to_jsonb(old),to_jsonb(n),null);
 return n;
end $$;

-- Payment edits must go through the field-aware RPC. Direct UPDATE is deliberately removed.
revoke update on public.client_payments from authenticated;
grant execute on function public.update_client_fields(uuid,text,text,text,text,text) to authenticated;

-- Replace payment RPC to enforce status/reference permissions individually.
create or replace function public.update_client_payment(p_id uuid, p_amount numeric default null, p_payment_date date default null, p_payment_method text default null, p_reference text default null, p_notes text default null, p_status text default null)
returns public.client_payments language plpgsql security definer set search_path=public as $$
declare old public.client_payments; n public.client_payments;
begin
 select * into old from public.client_payments where id=p_id for update;
 if old.id is null then raise exception 'Payment not found'; end if;
 if not public.can_access_payment(old.project_id,old.client_id,old.created_by,'PAYMENTS_EDIT','EDIT') then raise exception 'You are not authorized to edit this payment'; end if;
 if p_amount is not null and p_amount<>old.amount and not public.has_permission('PAYMENTS_AMOUNT_EDIT','EDIT') then raise exception 'You are not authorized to edit the payment amount'; end if;
 if p_status is not null and p_status<>old.status and not public.has_permission('PAYMENTS_STATUS_EDIT','EDIT') then raise exception 'You are not authorized to edit payment status'; end if;
 if p_reference is not null and p_reference<>coalesce(old.reference,'') and not public.has_permission('PAYMENTS_REFERENCE_EDIT','EDIT') then raise exception 'You are not authorized to edit payment reference'; end if;
 update public.client_payments set amount=coalesce(p_amount,amount),payment_date=coalesce(p_payment_date,payment_date),payment_method=coalesce(p_payment_method,payment_method),reference=case when p_reference is null then reference else p_reference end,notes=case when p_notes is null then notes else p_notes end,status=coalesce(p_status,status),updated_by=auth.uid(),updated_at=now() where id=p_id returning * into n;
 perform public.write_audit('PAYMENTS','EDIT',p_id,null,to_jsonb(old),to_jsonb(n),null);
 return n;
end $$;
grant execute on function public.update_client_payment(uuid,numeric,date,text,text,text,text) to authenticated;
commit;
