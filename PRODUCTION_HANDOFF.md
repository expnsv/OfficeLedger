# OfficeLedger — Handoff

## Code-side work completed
- Core accounting, ledger, reports, employee access, audit, attachments and backup/import flows retained.
- Supabase Auth session handling retained and hardened.
- Password lifecycle metadata migration retained.
- Passwords now require 12–128 characters, at least one letter and one number, and no spaces.
- Reusing the current password is rejected when changing a password.
- Password history is intentionally not stored; previous Supabase Auth password hashes must never be copied into application tables.
- First-admin bootstrap SQL is included.
- Employee invitation Edge Function is included and requires server-side secret configuration.
- No service-role/secret key is embedded in the frontend.
- All JavaScript source files pass `node --check` syntax validation.
- No TODO/FIXME/coming-soon placeholders remain in source.

## Your turn — Supabase only
1. Open the Supabase project whose URL is in `js/config.js`.
2. SQL Editor → run `supabase/migrations/202610010001_officeledger.sql` if the schema is not already installed.
3. SQL Editor → run `supabase/migrations/202610010002_password_policy.sql`.
4. Authentication → Users → create the first Admin Auth user using your chosen email/password.
5. SQL Editor → copy `supabase/bootstrap-admin.sql`, replace `REPLACE_WITH_ADMIN_EMAIL`, and run it once.
6. Configure the Edge Function secrets described in `PRODUCTION_SETUP.md` and deploy `supabase/functions/create-employee`.
7. Configure Auth redirect/site URLs and SMTP for invitation/reset email delivery.

Do not send passwords or service-role/secret keys in chat.
