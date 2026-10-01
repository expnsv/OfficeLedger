# OfficeLedger — production completion checklist

The ZIP contains the application code and Supabase migrations. The remaining account-specific steps must be run in the connected Supabase project because they require project-owner credentials and SMTP settings.

## 1. Apply the database migrations

Run the existing migration and then `supabase/migrations/202610010002_password_policy.sql` in the Supabase SQL Editor (or deploy with the Supabase CLI).

The second migration adds the 30-day password lifecycle metadata. It never stores passwords.

## 2. Create the first Admin

In **Supabase → Authentication → Users**, create the first user with an email and a password of 12–128 characters. Then run `supabase/bootstrap-admin.sql` after replacing `REPLACE_WITH_ADMIN_EMAIL` with that exact email.

## 3. Auth settings

- Turn **public sign-ups OFF**.
- Set minimum password length to **12**.
- Add the production application URL to **Site URL / Redirect URLs**.
- Configure a real SMTP provider before using invitations or password reset.

## 4. Deploy the employee invitation function

Set these secrets for the `create-employee` function:

- `APP_ORIGIN` = the exact HTTPS origin hosting OfficeLedger
- `APP_REDIRECT_URL` = the exact OfficeLedger `index.html` URL
- `SUPABASE_SECRET_KEY` (or the project's service-role compatibility variable)

Then deploy `create-employee`. **Never place the secret key in `js/config.js`.**

## 5. Browser configuration

`js/config.js` contains only the Supabase project URL and publishable browser key. Do not replace it with a secret/service-role key.

## 6. First live smoke test

1. Admin signs in.
2. Admin opens Employees and invites an employee.
3. Employee receives the invitation and sets a password.
4. Employee signs in.
5. Employee creates a non-salary accounting record.
6. Confirm the employee cannot change salary amounts or archive/delete records.
7. Admin disables the employee and confirm the next session check blocks access.
8. Confirm password change works and the password lifecycle timestamp updates.
9. Test backup export/import in a non-production workspace before importing historical data.

## 7. Password policy

OfficeLedger now enforces a **30-day password age check in the application** and forces a password setup for invited/recovery users. Passwords themselves remain entirely inside Supabase Auth.

Password history (forbidding reuse of the previous three passwords) is **not implemented**, because securely checking old Supabase Auth password hashes is not exposed to the browser and storing plaintext/reversible passwords would be unsafe. Passwords are instead required to be 12–128 characters, contain at least one letter and one number, and contain no spaces.
