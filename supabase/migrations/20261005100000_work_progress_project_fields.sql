-- Work Progress project-centric refinement.
-- The project record is the single operational view for client, assignment,
-- work status, priority and payment status/update.

alter table public.projects
  add column if not exists assigned_by uuid references public.profiles(user_id),
  add column if not exists assigned_to uuid references public.profiles(user_id),
  add column if not exists priority text not null default 'NORMAL'
    check (priority in ('LOW','NORMAL','HIGH','URGENT')),
  add column if not exists payment_status text not null default 'PENDING'
    check (payment_status in ('PENDING','PARTIALLY_PAID','PAID')),
  add column if not exists payment_update text not null default 'ADVANCE'
    check (payment_update in ('ADVANCE','PARTIAL','FINAL'));

-- Backfill the project assignment fields from the current primary/latest assignment
-- without deleting existing assignment history.
update public.projects p
set assigned_to = x.assigned_to,
    assigned_by = x.assigned_by,
    priority = coalesce(nullif(x.priority,''), p.priority)
from (
  select distinct on (project_id) project_id, assigned_to, assigned_by, priority
  from public.work_assignments
  order by project_id, updated_at desc nulls last, created_at desc nulls last
) x
where x.project_id = p.id
  and (p.assigned_to is null or p.assigned_by is null);

-- Preserve the latest payment state where legacy client_payments exist.
update public.projects p
set payment_status = case
  when q.final_paid then 'PAID'
  when q.payment_count > 0 then 'PARTIALLY_PAID'
  else p.payment_status
end,
payment_update = case
  when q.latest_type is not null then q.latest_type
  else p.payment_update
end
from (
  select project_id,
         count(*) as payment_count,
         bool_or(payment_type='FINAL') as final_paid,
         (array_agg(payment_type order by payment_date desc nulls last, created_at desc nulls last))[1] as latest_type
  from public.client_payments
  group by project_id
) q
where q.project_id = p.id;

create index if not exists idx_projects_assigned_to on public.projects(assigned_to);
create index if not exists idx_projects_payment_status on public.projects(payment_status);
create index if not exists idx_projects_priority on public.projects(priority);
