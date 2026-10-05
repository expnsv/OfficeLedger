# OfficeLedger Production Handoff

## Application architecture

The active frontend is `index.html` + `styles.css` + the five files in `js/`.

There is one authentication layer, one DB adapter, one permission engine and one application renderer. The dashboard is generated from the permission model and automatically lays out accessible module cards using CSS Grid.

## Required Supabase execution

Run, in order:

1. `supabase/migrations/202610030001_officeledger_production.sql`
2. `supabase/migrations/202610030002_field_level_controls.sql`
3. `supabase/migrations/202610030003_audit_triggers.sql`
4. `supabase/migrations/202610030004_harden_direct_updates.sql`
5. `supabase/bootstrap-admin.sql` after creating the first Auth user.

## Required account configuration

- Disable public sign-ups.
- Configure Auth Site URL/Redirect URLs.
- Configure SMTP.
- Deploy `create-employee` with server-only secrets.
- Never expose the server secret in `js/config.js`.

## QA status

Static JavaScript syntax checks pass for all active browser modules. The package also contains the database/RLS definitions needed for the requested multi-role/scoped architecture.

A live database test is still account-specific and must be run against the connected Supabase project after the migrations are applied.

## Security audit status — 2026-10-05

A live Supabase security/schema hardening pass was performed. See `SECURITY_AUDIT_REPORT.md`.

**Certification status: NOT CERTIFIED AS FULLY SECURE YET.**

Remaining platform/security items are explicitly documented:
- Supabase Auth leaked-password protection must be enabled.
- Username login currently uses an intentionally exposed username-to-email `SECURITY DEFINER` resolver; this should be replaced with a tightly controlled server-side login lookup/rate-limited endpoint before final certification.
- Credentialed browser UAT with Admin, Accounting, Lead and Associate sessions is still required.

The database cleanup migration is `supabase/migrations/20261005190000_security_cleanup.sql`.
