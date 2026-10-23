# SAHM online accounts and chat setup

The updated `index_sahm_online.html` is prepared for Supabase email/password authentication, searchable registered profiles, shared follows/friend links, and realtime friend-only messages. It cannot connect to a cloud database until you add your own project URL and **publishable/anon key** and run the SQL schema below.

## 1. Create a Supabase project

1. Create a project in the Supabase dashboard: https://supabase.com/dashboard
2. Wait until the database is ready.
3. Open **Project Settings → API Keys** (or the API page in your dashboard). Copy the **Project URL** and the **publishable key**. An older project may show an `anon` public key; that key also works here.
4. Never put a `service_role` key or any secret key in this HTML. Browser code is public by design.

## 2. Create the database tables and security rules

1. Open the project's **SQL Editor**.
2. Open `sahm_supabase_setup.sql`, copy all of it into a new SQL query, and run it.
3. Confirm the query completes. The script creates public profile fields, follower records, friend links, messages, row-level security policies, helper functions, and the message realtime publication.

Profiles intentionally do **not** expose the account email. Supabase Auth stores and verifies passwords; this page does not store passwords in local storage. Message queries are limited by database policies to the sender/receiver and require an existing friend link.

## 3. Add your project keys to the HTML

Open `index_sahm_online.html` in a code editor. Near the end of the file, find:

```js
window.SAHM_SUPABASE_CONFIG = {
  url: 'https://YOUR_PROJECT_ID.supabase.co',
  publishableKey: 'YOUR_SUPABASE_PUBLISHABLE_KEY'
};
```

Replace those two placeholder values with your own Project URL and publishable/anon key, save the file, and do not add a `service_role`/secret key.

## 4. Configure email verification and redirect URLs

1. In Supabase, open **Authentication → URL Configuration**.
2. Set the **Site URL** to your real website URL.
3. Add that exact site URL as an allowed redirect URL. For GitHub Pages, use the actual published page URL, such as `https://YOUR-USERNAME.github.io/YOUR-REPOSITORY/`.
4. In **Authentication → Providers → Email**, leave email/password enabled. Email confirmation is recommended so people verify control of their email addresses before signing in.
5. For reliable verification emails to many users, configure a custom SMTP provider in Supabase. The built-in email service is intended for limited testing and is rate-limited.

## 5. Host the page

Use a static host such as GitHub Pages, Netlify, or another HTTPS host. Do not test email confirmation from a `file://` URL because it does not provide the real website origin needed for redirect configuration. Publish `index_sahm_online.html` as `index.html` on your host if you want it to be the main page.

## 6. Test with two accounts

1. Register Account A with a real email address, unique username, and password.
2. Confirm the email from its inbox, then sign in.
3. Open **People** and search Account B by their chosen username or display name.
4. Open their profile and choose **Add friend**.
5. Sign in as Account B in a separate browser/profile and add Account A as a friend if needed. The friend link is enough for both participants to message one another.
6. Open **Chats**, select the friend, and send a message. Messages are stored in the shared database and should appear in the other signed-in browser in realtime.

## Important scope notes

- The online **authentication, public profile directory, follows, friend links and chat messages** use Supabase when configured.
- The existing stock-price simulator, portfolio trades, rewards balance, and coupon claims were not migrated into this database by this update. Those features remain demo/browser-local and should not be represented as real money or real executed trades.
- Profiles are searchable by username/name only after sign-in. Emails are not shown in the public profile directory.
- Keep Supabase RLS policies enabled. Do not remove them and do not expose service/secret keys.
