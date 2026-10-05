# OfficeLedger — Production Business Management System

Vanilla HTML5/CSS3/ES6+ frontend with Supabase Auth, PostgreSQL, RLS and private Storage.

## Architecture

`Supabase Auth → profiles → employee_roles → roles → role_permissions → scoped RLS`

Employees may have multiple roles. Effective permissions are the union of their assigned roles. Admin is an explicit role and is never inferred from combinations such as Accounting + Survey.

## Modules

Dashboard, Employees, Roles & Permissions, Work Progress, Daily Progress, Attendance, Requests, Expenses, Payroll & Payslips, Invoice, Survey Reports, Reports, Files, Chat, Audit Logs and Settings.

## Security model

- Frontend permissions control UX only.
- PostgreSQL RLS is the authorization boundary.
- Payment rows are scoped by project/client ownership and assignment.
- Payment edits use a SECURITY DEFINER RPC so amount/status/reference field permissions are enforced server-side.
- Client edits use a SECURITY DEFINER RPC so restricted fields cannot be changed through direct table updates.
- Audit triggers retain important insert/update/delete and role changes.
- Storage bucket `office-files` is private.
- No service-role key is shipped to the browser.

## Supabase setup

1. Run `supabase/migrations/202610030001_officeledger_production.sql`.
2. Run `202610030002_field_level_controls.sql`.
3. Run `202610030003_audit_triggers.sql`.
4. Run `202610030004_harden_direct_updates.sql`.
5. Create the first Auth user.
6. Edit the email in `supabase/bootstrap-admin.sql` and run it once.
7. Disable public sign-ups.
8. Configure Auth Site URL/redirect URLs for the hosted application.
9. Deploy `functions/create-employee` with `SUPABASE_SECRET_KEY`, `APP_ORIGIN`, and `APP_REDIRECT_URL` secrets.
10. Configure SMTP before relying on invitations or password reset.

## Browser configuration

`js/config.js` contains only the Supabase project URL and publishable key. Never put a secret/service-role key there.

## QA scope completed in the package

- JavaScript syntax validation performed on revised frontend modules.
- Removed the broken `app (1).js` / `app.js` mismatch.
- Removed the broken `styles (1).css` / `styles.css` mismatch.
- Removed the previous accounting-only permission architecture from the active application path.
- Added multi-role and scoped permission data model.
- Added payment ownership and field-level server controls.
- Added permission-aware responsive dashboard cards.

A live Supabase smoke test still requires access to the project's SQL/Auth/Storage environment; this package does not claim that account-specific deployment steps have been executed.


## Authentication policy (2026-10-05)
- Login identifier: OfficeLedger username (not email).
- Username: 3-32 characters; letters, numbers, dot, underscore, hyphen.
- Password: exactly 6 or 8 characters.
- Password must contain uppercase, lowercase, number and symbol; spaces are rejected.
- Supabase Auth remains the password authority; no plaintext password is stored in PostgreSQL.
- `profiles.username` is only the login-name mapping to the Auth user's email.
- `auth_password_policy` stores policy metadata and `resolve_login_username()` maps the login username to the Auth email for `signInWithPassword()`.
- On managed Supabase, the Auth dashboard password-strength setting should be configured to minimum 6 and require lowercase/uppercase/digit/symbol. The exact 6-or-8 maximum is additionally enforced by OfficeLedger because Supabase Auth exposes minimum-length/required-character controls rather than an application-specific maximum-length rule.

## Initial Administrator Login

OfficeLedger now supports a one-time administrator bootstrap:

- Username: `admin`
- Password: `Admin@2026`
- The credential is accepted only while the existing Admin profile has `bootstrap_pending=true` and `must_change_password=true`.
- The bootstrap password is verified against a bcrypt hash; it is not stored as plaintext in the application database.
- After successful sign-in, the application immediately requires a permanent password using the normal 6/8-character mixed-character policy.
- The bootstrap state is then disabled and the bootstrap credential cannot be reused.

### Employee authentication management

Administrators can edit username, registered email, role assignments, department and active/inactive status. Existing passwords are never displayed. Password recovery is performed through Supabase Auth email recovery.

### Recovery

The login screen includes `Forgot password?`. The user may enter either their OfficeLedger username or registered email. Supabase Auth sends the recovery email and the application provides a secure password-reset flow.

Privileged employee email changes and password recovery initiation are handled by the server-side Supabase Edge Function `officeledger-admin-employee-auth`. The Supabase service-role key is never included in frontend files.
