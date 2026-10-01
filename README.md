# OfficeLedger

OfficeLedger is a responsive office accounting app with a static HTML/CSS/JavaScript frontend and a hosted Supabase backend. Supabase Auth handles email/password accounts; Postgres stores shared records; database Row Level Security and triggers enforce roles, salary privacy, refund limits, archive rules, and audit history.

## Hosting and backend

GitHub Pages can host the static website files. It does not provide the app's login server or database. Supabase provides those hosted services. The app uses the Supabase publishable key in the browser; its secret/service-role key is used only by the employee invitation Edge Function.

## Connected Supabase project

OfficeLedger is connected to Supabase project `kguimplvnuvycccofgxg` in the Mumbai region. The initial schema and RLS policies are included in the repository. Apply `supabase/migrations/202610010002_password_policy.sql` after the base migration to enable the 30-day password lifecycle. The browser config in `js/config.js` contains the project URL and publishable key, and GitHub Pages serves the app at `https://expnsv.github.io/OfficeLedger/`.

### First Admin setup

1. In Supabase **Authentication → Users**, create your own first user with an email address and password.
2. Open `supabase/bootstrap-admin.sql`, replace `REPLACE_WITH_ADMIN_EMAIL` with that exact email, and run the SQL once. The bootstrap refuses to run if an Admin already exists.
3. Turn off public sign-ups in Supabase Auth. Accounts without an OfficeLedger profile cannot access the data, and the app creates Employee profiles only after its Admin-checked invitation function succeeds. Invited/recovery users must set a password before normal use, and passwords are required to be changed every 30 days.
4. Set the password minimum to 12 characters and add `https://expnsv.github.io/OfficeLedger/index.html` to the allowed Auth redirect URLs.
5. The `create-employee` Edge Function is deployed with the GitHub Pages origin and invite redirect. It reads Supabase's built-in secret key at runtime; no service key is stored in GitHub.
6. Configure a custom SMTP provider in Supabase Auth before relying on employee invitations or password-reset emails.

   ```sh
   supabase secrets set APP_ORIGIN=https://YOUR_NAME.github.io APP_REDIRECT_URL=https://YOUR_NAME.github.io/YOUR_REPOSITORY/index.html
   supabase secrets set SUPABASE_SECRET_KEY=YOUR_SERVER_SECRET_KEY
   supabase functions deploy create-employee
   ```

   Supabase may provide the server key under `SUPABASE_SERVICE_ROLE_KEY`; the function accepts either environment name. For publishable credentials it reads `SUPABASE_PUBLISHABLE_KEY`, the current `SUPABASE_PUBLISHABLE_KEYS` mapping, or the compatibility `SUPABASE_ANON_KEY`. Never put the server secret in GitHub Pages or `js/config.js`.

8. Set the project URL and **publishable** key in `js/config.js`. The publishable key is intended for browser apps; database access is controlled by the signed-in user's RLS policies.
9. Serve the app through HTTPS; opening `index.html` from a local file URL will not connect to Supabase.

### Move data from the earlier browser-only version

Before switching an existing browser profile to the Supabase version, open `legacy-export.html` in the same browser profile and at the same file or web origin used by the previous local app. Export the JSON file there, then sign in as the Supabase Admin and use **Settings → JSON backup → Import**. The exporter reads the old `officeledger-db` IndexedDB stores but never uploads data or includes password hashes. If the old app was used under another origin, use that same origin to run the exporter.

The SQL grants authenticated access only after enabling RLS, and explicitly grants the functions and tables used by the app. If the project has Data API exposure controls enabled, keep `public` exposed and do not expose the `private` schema.

## What is enforced in the database

- Employees can create non-salary entries and update their own records. Only Admins can create or change salary amounts. RLS rejects employee delete requests; no browser role has table-level DELETE privileges. Admins archive records through an update, retaining financial history and its audit event.
- Employees see only their own salary rows. They can update permitted payment details, while a database trigger blocks changes to salary amount, deductions, net, employee, and salary month.
- Profiles cannot be promoted from the browser. The Admin role is stored in a protected database profile, not user-editable Auth metadata.
- The invitation Edge Function verifies the caller's Supabase JWT and Admin profile before using its server key. Its CORS origin must match `APP_ORIGIN`.
- Transaction IDs are unique. Refunds require a valid, reimbursable client expense and cannot exceed its outstanding amount, including concurrent refund requests.
- Database triggers add audit events for transaction, archive, profile-access, and settings changes. Audit rows cannot be updated or deleted by browser users.
- Attachments live in a private Supabase Storage bucket with a 4 MB file limit and database-backed access checks. Employees can access attachments on visible shared records and their own salary records; Admins can access all records.
- Shared transaction fields are stored once as table columns. Category-specific fields are stored in one JSON details column, which the app presents through one field per form.

## Accounting and export features

- Separate categories for Rent, Electricity, Salaries, GST, Petty Cash, Client Expenses, Refunded Payments, Wi-Fi, Flat Maintenance, Washroom Cleaning, Drinking Water Supply, Cleaner Expenses & Maintenance, and Tea Maker Expenses & Maintenance.
- The Petty Cash category list includes the four options from the supplied screenshot: Washroom Cleaning, Drinking Water Supply, Cleaner Expenses & Maintenance, and Tea Maker Expenses & Maintenance.
- Dashboard and reports calculate monthly totals, refunds, outstanding reimbursements, salaries, and petty cash from the same transaction rows. Net office expenses are gross expenses less recorded refunds.
- Searchable ledger, category and date filters, client reimbursement reports, salary reports, and audit history.
- JSON backup export, additive JSON import, CSV/Excel reports, and print-to-PDF through the browser print dialog.

JSON import adds new transaction records and skips IDs or transaction IDs already present. It does not replace workspace settings or audit history. Imported transactions create new audit events. Old employee IDs that do not exist in the Supabase project are associated with the importing Admin for permissions; the imported employee name is retained in the record details. Import is not a substitute for a complete migration of historical user accounts.

### Password lifecycle

The app stores only `password_changed_at` metadata in `profiles`; it never stores passwords or password hashes. A newly invited/recovery user must set a password, and an existing password expires after 30 days. The UI forces a password change after expiry. Password-history reuse prevention is not implemented because Supabase Auth does not expose previous password hashes to the browser and retaining plaintext/reversible passwords would be unsafe.

### Load the demo data

After configuring Supabase and signing in as an Admin, open **Settings → JSON backup → Import** and select `demo-data.json`. It adds 22 illustrative entries across all accounting categories, including pending payments, petty cash movements, salaries, client expenses, and a partial reimbursement. The importer skips matching IDs and transaction IDs and does not replace workspace settings or audit history. Use a demo workspace if you want to keep sample transactions separate from live accounts.

## Security limits

GitHub Pages is a static host. The Supabase session token is held in browser `sessionStorage`, so an XSS vulnerability in the page could act as the signed-in user. The page has a restrictive Content Security Policy, app-generated content is escaped, server keys stay in the Edge Function, and database RLS remains the authorization boundary. For deployments that require HttpOnly cookie sessions or strict control of browser script access, put a server-side application/BFF in front of Supabase instead of serving only a static page.

## Verification status

The Supabase migration is recorded in the project, all four public tables have RLS enabled, and the security advisor reported no findings after setup. Initial Admin creation, Auth URL settings, SMTP delivery, Edge Function deployment, and real-user flows still require the project owner to finish the account-specific setup above. See `PRODUCTION_SETUP.md` for the exact final checklist.
