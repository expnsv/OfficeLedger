-- OfficeLedger document-module permissions.
-- Navigation is additionally gated by role/department in the frontend; this migration
-- reserves explicit permission codes for future persisted invoice/survey-report records.
insert into public.permissions(code,module,action,field_name,description) values
 ('INVOICES_VIEW','INVOICE','VIEW',null,'View authorized invoice/quotation documents'),
 ('INVOICES_CREATE','INVOICE','CREATE',null,'Create invoice/quotation documents'),
 ('INVOICES_EDIT','INVOICE','EDIT',null,'Edit invoice/quotation documents'),
 ('INVOICES_EXPORT','INVOICE','EXPORT',null,'Export invoice/quotation documents'),
 ('SURVEY_REPORTS_VIEW','SURVEY_REPORTS','VIEW',null,'View survey reports in authorized survey department'),
 ('SURVEY_REPORTS_CREATE','SURVEY_REPORTS','CREATE',null,'Create survey reports in authorized survey department'),
 ('SURVEY_REPORTS_EDIT','SURVEY_REPORTS','EDIT',null,'Edit survey reports in authorized survey department'),
 ('SURVEY_REPORTS_EXPORT','SURVEY_REPORTS','EXPORT',null,'Export survey reports in authorized survey department')
on conflict (code) do update set module=excluded.module,action=excluded.action,field_name=excluded.field_name,description=excluded.description;

-- Admin gets all document permissions.
insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'company' from public.roles r cross join public.permissions p
where r.code='ADMIN' and p.code in ('INVOICES_VIEW','INVOICES_CREATE','INVOICES_EDIT','INVOICES_EXPORT','SURVEY_REPORTS_VIEW','SURVEY_REPORTS_CREATE','SURVEY_REPORTS_EDIT','SURVEY_REPORTS_EXPORT')
on conflict do nothing;

-- Accounting gets the invoice/quotation document workflow.
insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'company' from public.roles r cross join public.permissions p
where r.code='ACCOUNTING' and p.code in ('INVOICES_VIEW','INVOICES_CREATE','INVOICES_EDIT','INVOICES_EXPORT')
on conflict do nothing;

-- Survey operational roles receive survey-report permissions; department membership remains
-- a separate boundary and is checked by application/RLS when persisted report storage is added.
insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'department' from public.roles r cross join public.permissions p
where r.code in ('LEAD','ASSOCIATE') and p.code in ('SURVEY_REPORTS_VIEW','SURVEY_REPORTS_CREATE','SURVEY_REPORTS_EDIT','SURVEY_REPORTS_EXPORT')
on conflict do nothing;
