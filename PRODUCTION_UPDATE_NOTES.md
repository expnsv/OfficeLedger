# OfficeLedger Production Revision — 2026-10-05

Applied the latest project-centric Supabase specification while preserving the user's current business rules.

## Included
- Central normalized Departments + Employee Department memberships.
- Project ↔ Department and Department ↔ Work Type relationships.
- Assignment Department/Work Type fields and reassignment history.
- Daily Progress department/work type, completed/pending/remarks and separate updated-by field.
- Attendance revision history.
- Combined Requests backend for Leave plus existing expense-based allowance/advance requests.
- Central Invoice persistence for the supplied SAGT Invoice/Quotation editor.
- Department-scoped Survey Report persistence for the supplied SAGT Survey Report editor.
- Central file metadata extensions, private file shares and version records.
- Private one-to-one conversations, participants, messages and private chat attachments.
- Realtime-ready schema for chat; subscriptions can be enabled selectively in the deployed project.
- RLS policies for department membership, survey reports, invoices, private files and private chat.
- Database RPC for creating a private two-person conversation without exposing a broad participant INSERT policy.
- Invoice and Survey Report editors expose their current document state to the OfficeLedger parent so the user can explicitly save the document to Supabase.
- Responsive chat/editor layout for phone, tablet and desktop.
- Fixed the earlier document-permission migration schema error (`permissions` has no `scope` column).
- No separate Approvals workflow/module was introduced.

## Retesting completed
- Node syntax checks: `app.js`, `db.js`, `permissions.js`, `auth.js` — passed.
- Local HTTP smoke load: `index.html`, `invoice.html`, `survey-report.html` — HTTP 200.
- Navigation source audit: no Approvals navigation/module introduced.
- ZIP integrity/package creation — passed.

## Important deployment note
The new migration `202610050001_project_centric_collaboration.sql` must be applied to the live Supabase project after the existing migrations. The package does not claim that the live hosted database has been migrated merely because the migration file is included.

Authenticated browser/RLS end-to-end tests against the live Supabase project were not performed in this environment, so the build is delivered as a revised production candidate, not falsely certified as fully deployed production-ready.

## 2026-10-05 backend/frontend error-fix pass

- Fixed private chat attachment storage path to `direct/<conversation_id>/...` so it matches the private Storage RLS policies.
- Fixed attachment-only chat messages by removing the contradictory HTML `required` constraint from the message body.
- Added client-side normalization of one-to-one chat participants and a server-side trigger so `(A,B)` and `(B,A)` cannot create duplicate/rejected conversations.
- Fixed Survey Report RLS so company-scoped Admin permissions do not incorrectly require survey-department membership.
- Changed frontend refresh behavior so failed table loads are surfaced as errors instead of silently becoming an apparently empty dataset.
- Re-ran JavaScript syntax checks after the changes.

Live Supabase migrations verified through `2026-10-05` include:
- `officeledger_supabase_full_integration_20261005_v3`
- `officeledger_supabase_integration_hardening_20261005`
- `officeledger_rls_performance_hardening_20261005`
- `officeledger_work_types_rls_hardening_20261005`
- `officeledger_backend_error_fixes_20261005`

## Storage compression hardening — 2026-10-05
- Applied PostgreSQL LZ4 TOAST compression to large text/JSONB backend payload columns.
- Project/work records remain normalized around UUID references; no business data is moved to browser storage.
- Added project indexes for client/status/priority, assignee/status, and payment status/update.
- Supabase PostgreSQL 17.11 supports LZ4; migration `20261005110000_storage_compression_lz4_hardening.sql` is included.
