-- Project access hardening: direct assigned_by/assigned_to users are valid project owners.
-- Canonicalize legacy department labels used by existing project rows.
create or replace function app_private.can_access_project(p_project uuid, p_code text, p_action text)
returns boolean
language sql
stable
security definer
set search_path = public, app_private
as $$
  select
    exists (
      select 1 from public.employee_roles er
      join public.roles r on r.id = er.role_id
      where er.employee_id = auth.uid() and r.code = 'ADMIN'
    )
    or exists (
      select 1
      from public.role_permissions rp
      join public.permissions p on p.id = rp.permission_id
      join public.employee_roles er on er.role_id = rp.role_id
      where er.employee_id = auth.uid()
        and p.code = p_code
        and p.action = p_action
        and (
          rp.scope = 'COMPANY'
          or (rp.scope = 'ASSIGNED' and exists (
            select 1 from public.project_members pm
            where pm.project_id = p_project and pm.employee_id = auth.uid() and pm.is_active
          ))
          or (rp.scope in ('TEAM','DEPARTMENT') and exists (
            select 1
            from public.projects pr
            join public.employee_departments ed on ed.employee_id = auth.uid() and ed.is_active
            join public.departments d on d.id = ed.department_id
            where pr.id = p_project
              and (upper(d.code) = upper(pr.department) or upper(d.name) = upper(pr.department))
          ))
          or (rp.scope = 'OWN' and exists (
            select 1 from public.projects pr
            where pr.id = p_project
              and (
                pr.created_by = auth.uid()
                or pr.assigned_to = auth.uid()
                or pr.assigned_by = auth.uid()
                or exists (
                  select 1 from public.work_assignments wa
                  where wa.project_id = p_project and wa.assigned_to = auth.uid()
                )
              )
          ))
        )
    );
$$;

update public.projects
set department = 'SURVEY_FIELD'
where lower(department) in ('survey','survey field');

create index if not exists idx_projects_assigned_by on public.projects(assigned_by);
