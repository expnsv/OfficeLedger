begin;
create or replace function public.audit_row_change() returns trigger language plpgsql security definer set search_path=public as $$
declare rid uuid; act text; oldj jsonb; newj jsonb;
begin
 rid=coalesce(NEW.id,OLD.id); act=TG_OP; oldj=case when TG_OP in ('UPDATE','DELETE') then to_jsonb(OLD) end; newj=case when TG_OP in ('INSERT','UPDATE') then to_jsonb(NEW) end;
 insert into public.audit_logs(actor_id,module,action,record_id,previous_value,new_value) values(auth.uid(),TG_TABLE_NAME,act,rid,oldj,newj);
 return coalesce(NEW,OLD);
end $$;

do $$ declare t text; begin
 foreach t in array array['clients','projects','work_assignments','daily_progress','attendance','expenses','compensations','client_payments'] loop
  execute format('drop trigger if exists trg_%s_audit on public.%I',t,t);
  execute format('create trigger trg_%s_audit after insert or update or delete on public.%I for each row execute function public.audit_row_change()',t,t);
 end loop;
end $$;

create or replace function public.audit_employee_role_change() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.audit_logs(actor_id,module,action,record_id,previous_value,new_value)
 values(auth.uid(),'ROLES',TG_OP,coalesce(NEW.employee_id,OLD.employee_id),case when TG_OP='DELETE' then to_jsonb(OLD) end,case when TG_OP<>'DELETE' then to_jsonb(NEW) end);
 return coalesce(NEW,OLD);
end $$;
drop trigger if exists trg_employee_roles_audit on public.employee_roles;
create trigger trg_employee_roles_audit after insert or update or delete on public.employee_roles for each row execute function public.audit_employee_role_change();

commit;
