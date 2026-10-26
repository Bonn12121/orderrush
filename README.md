# Order Rush

A live Vietnamese ordering game built with React, TypeScript, Vite, Supabase Auth, PostgreSQL, Realtime, dnd-kit, and Framer Motion.

## Run

1. Use Node.js 22 or newer. Run `npm ci`.
2. Copy `.env.example` to `.env` and fill in the Supabase URL and **public publishable key**. Never place a service-role key in the frontend.
3. In [Supabase Auth settings](https://supabase.com/dashboard/project/ykpmqjaoeioirkgobwyc/auth/providers), enable **Anonymous Sign-Ins**. The Supabase connector cannot change this project setting. Until enabled, the play button receives `anonymous_provider_disabled`.
4. Run `npm run dev`. For a production build, run `npm run build`.

The migration in `supabase/migrations/20261026000000_order_rush.sql` was applied to the linked project. For a new project, run that migration before starting the site. It creates all tables, RLS policies, server-side grading and leaderboard functions, Realtime publications, and the sample challenge.

## Teacher access

The linked project has a teacher account with username `admin`. Its password was supplied separately by the owner and is not stored in this repository. Open `/admin` to sign in. For a different project, create a normal **email/password** user in Supabase Auth, then add that user ID in the SQL editor:

```sql
insert into public.admin_users(user_id) values ('YOUR_AUTH_USER_UUID');
```

Only users in `admin_users` can create, edit, publish, activate, reset, replay their own attempt, or inspect protected data. The admin dashboard shows live players, elapsed time, and rankings. The answer table is unreadable by ordinary players. Published challenges can be activated; one challenge is active globally at a time.

## Deploy on Vercel

Import this folder as a Vite project. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` from `.env` as Vercel environment variables. Build command: `npm run build`; output directory: `dist`. Add a rewrite from `/(.*)` to `/index.html` if using direct `/admin` links.

## Verification

`npm run build` passed. `npm audit` reports zero vulnerabilities. `supabase/tests/game_flow.sql` is a transaction-safe integration test; it passed on the live project with two independent players, correct and incorrect grades, and duplicate rejection. The test transaction rolled back. End-to-end browser and presence testing still require enabling anonymous sign-ins.

