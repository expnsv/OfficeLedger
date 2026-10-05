# Production setup checklist

### Database

Run these files in order in Supabase SQL Editor:

1. `202610030001_officeledger_production.sql`
2. `202610030002_field_level_controls.sql`
3. `202610030003_audit_triggers.sql`
4. `202610030004_harden_direct_updates.sql`

### First Admin

Create the first Auth user, then edit `bootstrap-admin.sql` with the exact email and run it once.

### Edge Function

Set:

- `APP_ORIGIN` — exact HTTPS origin of the app
- `APP_REDIRECT_URL` — exact invite/recovery URL
- `SUPABASE_SECRET_KEY` — server-only secret

Deploy `create-employee`. Never commit the secret key.

### Auth

- Disable public sign-up.
- Configure Site URL and Redirect URLs.
- Configure SMTP.
- Keep minimum password length at 12 or greater.

### Storage

The migration creates private bucket `office-files` with a 5 MB limit. Access is controlled by Storage RLS and the `files` table.

### Test matrix

Test at minimum:

- Admin
- Accounting
- Survey
- Lead
- Associate
- Accounting + Survey
- Employee assigned to Project A but not Project B
- Payment belonging to authorized Project A
- Unauthorized Project B payment
- Direct REST update attempts against protected payment/client fields
- Role assignment/removal
- Disabled account
- File download outside authorized project scope
- Audit history after payment, assignment, role and expense changes
