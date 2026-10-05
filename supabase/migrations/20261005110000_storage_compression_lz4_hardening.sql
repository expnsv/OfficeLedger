-- Storage efficiency hardening: use PostgreSQL LZ4 TOAST compression for large backend payloads.
-- Business data remains fully queryable in Supabase/Postgres; no client-side/local storage is used.

alter table public.invoices alter column payload set compression lz4;
alter table public.survey_reports alter column payload set compression lz4;
alter table public.audit_logs
  alter column previous_value set compression lz4,
  alter column new_value set compression lz4,
  alter column reason set compression lz4;
alter table public.daily_progress
  alter column summary set compression lz4,
  alter column blockers set compression lz4,
  alter column next_action set compression lz4,
  alter column completed_work set compression lz4,
  alter column pending_work set compression lz4,
  alter column remarks set compression lz4;
alter table public.projects
  alter column description set compression lz4,
  alter column requirements set compression lz4,
  alter column pending_work set compression lz4,
  alter column remarks set compression lz4;
alter table public.clients alter column notes set compression lz4;
alter table public.expenses alter column description set compression lz4;
alter table public.leave_requests alter column reason set compression lz4;
alter table public.attendance
  alter column notes set compression lz4,
  alter column marked_location set compression lz4,
  alter column attendance_note set compression lz4;
alter table public.compensations alter column notes set compression lz4;
alter table public.direct_messages alter column body set compression lz4;
alter table public.files
  alter column storage_path set compression lz4,
  alter column file_name set compression lz4;
alter table public.file_versions
  alter column storage_path set compression lz4,
  alter column file_name set compression lz4;
alter table public.direct_message_attachments
  alter column storage_path set compression lz4,
  alter column file_name set compression lz4;

create index if not exists idx_projects_client_status_priority
  on public.projects(client_id, status, priority);
create index if not exists idx_projects_assigned_to_status
  on public.projects(assigned_to, status);
create index if not exists idx_projects_payment_status_update
  on public.projects(payment_status, payment_update);
