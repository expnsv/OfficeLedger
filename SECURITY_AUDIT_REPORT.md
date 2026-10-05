# OfficeLedger Security Audit & Debug Report

**Audit date:** 2026-10-05  
**Scope:** UI (HTML/CSS/Vanilla JS), Supabase database/RLS/functions/triggers, authentication integration, document editors, and package consistency.

## Executive certification

**STATUS: NOT CERTIFIED AS FULLY SECURE YET.**

The application has materially improved security controls, but a production security certificate cannot honestly be issued while the live Supabase project still reports two unresolved security classes:

1. `resolve_login_username(text)` is intentionally exposed to `anon` and `authenticated` as a `SECURITY DEFINER` function because username login needs an unauthenticated username-to-email lookup. Supabase's security advisor flags this exposure.
2. Supabase Auth leaked-password protection is disabled and must be enabled in the Supabase Auth Password Security configuration.

These are explicit residual risks, not hidden or ignored findings.

## Fixes applied during this audit

### UI / frontend
- Restored missing `openProgress()` handler. The Daily Progress button previously called a function that did not exist.
- Restored missing Invoice/Survey save and assignment handlers in the main application shell.
- Main application now pulls Invoice and Survey document state from the embedded editors and saves it to Supabase.
- Removed browser business-data persistence from the application/editor layer; IndexedDB/localStorage/sessionStorage are no longer used for OfficeLedger business records.
- Removed editable `Assigned By` from the project form. Assignment provenance is now server-owned.
- Daily Progress UI now uses one canonical set of fields: Completed Work, Pending Work, Remarks.
- Removed UI fallback to deleted legacy Daily Progress fields (`summary`, `blockers`, `next_action`).
- Project UI no longer asks the user to choose the assignment originator.

### Database / backend
- Removed duplicate legacy profile fields: `profiles.role` and `profiles.department`.
- Normalized compensation grouping to use `employee_departments` instead of `profiles.department`.
- Removed duplicate attendance field `attendance.notes`; `attendance.attendance_note` is canonical.
- Removed legacy Daily Progress aliases: `summary`, `blockers`, `next_action`.
- Added server-side profile update guard preventing ordinary employees from changing email, activation state, username, salary, working hours, password timestamp, or other security-sensitive profile attributes.
- Added server-side project write guard: `created_by` and `assigned_by` are server-owned; unauthorized reassignment is rejected.
- Added server-side Daily Progress guard for employee identity, current-day rule, progress range, and text lengths.
- Pinned search paths on the username/password helper functions and removed unnecessary execute grants from trigger-only helpers.
- Removed an obsolete `monthly_payroll_summary` view that depended on the removed duplicate profile department field.
- Rebuilt compensation profile synchronization so it depends on normalized department membership.

## Findings discovered

| ID | Severity | Finding | Status |
|---|---|---|---|
| SEC-01 | HIGH | Public `SECURITY DEFINER` username resolver | **OPEN / intentional residual** |
| SEC-02 | HIGH | Leaked-password protection disabled | **OPEN / platform setting required** |
| SEC-03 | HIGH | Employee profile UPDATE policy was broad enough to permit self-edit attempts against sensitive fields | **FIXED** with trigger guard |
| SEC-04 | HIGH | Project form exposed editable `Assigned By` | **FIXED**; server owns it |
| SEC-05 | HIGH | Daily Progress UI called missing `openProgress()` | **FIXED** |
| SEC-06 | HIGH | Main Invoice/Survey shell referenced missing save/assignment handlers | **FIXED** |
| SEC-07 | MEDIUM | Duplicate/legacy profile role and department columns | **REMOVED** |
| SEC-08 | MEDIUM | Duplicate Attendance note fields | **REMOVED** |
| SEC-09 | MEDIUM | Duplicate Daily Progress text fields | **REMOVED** |
| SEC-10 | MEDIUM | Security helper functions had mutable search paths | **FIXED** |
| SEC-11 | MEDIUM | Unnecessary execute privileges on internal helper/trigger functions | **FIXED** |
| SEC-12 | MEDIUM | Package migration contained repeated definitions of several RPCs/policies | **Marked for cleanup in package migration** |
| SEC-13 | MEDIUM | Local package migration history did not exactly match the live Supabase migration history | **DOCUMENTED; must be reconciled before automated production migration replay** |
| SEC-14 | LOW | Legacy archive tables lack primary keys | **Performance advisory; not exposed by the public API schema** |
| SEC-15 | LOW | Supabase reports unused indexes | **Performance advisory; no security impact** |

## Security controls verified

- Public application uses a Supabase publishable key, not a service-role key.
- Service-role credential is kept in the Edge Function environment, not browser configuration.
- Public tables have RLS enabled.
- Authorization is enforced with RLS plus database functions/triggers; UI visibility is not treated as the security boundary.
- Admin/employee role logic is backed by normalized `employee_roles` and permissions.
- Passwords are not stored in business tables.
- Username format is database-validated.
- Password policy is checked by the application and policy metadata; Supabase Auth remains the credential authority.
- Security-definer functions inspected in the live database have pinned search paths after this audit, except the username resolver which remains intentionally exposed for username login.

## Testing performed

### Static/UI tests
- JavaScript syntax checks passed for `auth.js`, `app.js`, `db.js`, and `permissions.js`.
- HTML duplicate-ID checks passed for `index.html`, `invoice.html`, and `survey-report.html`.
- Searches performed for local/session storage, service-role exposure, dynamic-code execution, and obvious hard-coded secrets.
- Undefined main-shell handlers identified and repaired for Daily Progress, Invoice, and Survey actions.

### Live Supabase tests
- Live project migration inventory inspected.
- Live table/column inventory inspected.
- RLS status and policy counts inspected across public tables.
- Live security advisors re-run after hardening.
- Live trigger/function inventory inspected.
- Live role/permission function execution grants inspected.
- Live duplicate/legacy field dependencies checked before destructive cleanup.
- Live schema confirmed after cleanup: removed `profiles.role`, `profiles.department`, `attendance.notes`, `daily_progress.summary`, `daily_progress.blockers`, and `daily_progress.next_action`.

### Current Supabase advisor result

After the database hardening, the security advisor reports **3 remaining warnings**:

- username resolver is a callable `SECURITY DEFINER` function for anonymous username login;
- username resolver is also callable by authenticated users;
- leaked-password protection is disabled.

No claim of zero security warnings is made.

## Why the application is not certified yet

A secure application is not the same as a UI that hides buttons. The final production certification requires the remaining Auth configuration issue to be closed and the username resolver architecture to be hardened or explicitly risk-accepted.

### Required before certification

1. Enable **Leaked Password Protection** in Supabase Auth Password Security.
2. Replace the public `SECURITY DEFINER` username resolver with a tightly controlled server-side username-login endpoint/Edge Function, or document and accept the residual username enumeration risk with additional rate limiting and monitoring.
3. Re-run the Supabase security advisor and require **zero HIGH/WARN security findings attributable to OfficeLedger configuration**.
4. Run authenticated browser UAT for Admin, Accounting, Lead and Associate accounts, including positive and negative authorization tests.
5. Test storage access, chat participant isolation, document assignment isolation, attendance correction, payroll visibility, and employee profile modification with real authenticated sessions.

## Regression rule

No future change should be considered production-ready unless:

- JavaScript syntax checks pass;
- all main-shell referenced handlers exist;
- no removed database column is referenced by UI or SQL;
- all exposed tables remain RLS protected;
- all SECURITY DEFINER functions have an explicitly pinned search path;
- sensitive profile fields remain server-protected;
- assignment provenance is server-owned;
- security and performance advisors are re-run after DDL changes;
- authenticated positive/negative RLS tests pass;
- migration history is reconciled before deployment.

## Important testing limitation

A full authenticated penetration test could not be truthfully claimed from this environment because it requires valid Admin, Accounting, Lead and Associate sessions and a real browser against the deployed origin. The database was inspected and hardened live, but credentialed browser UAT remains a separate required certification stage.
