# Demo environment — separate from the chocolate app

**Never deploy this over https://fremont-s-fundraiser.vercel.app or its GitHub repo.** The demo is a NEW Vercel project
reading ONLY the V3 staging database (`xyhtaufdyyokjvzctums`).

## A. Deploy (about 10 minutes, Minerva)
1. GitHub → **New repository** `fremont-v3-demo` (private). Upload the contents of this folder (not the zip itself).
2. Vercel → **Add New → Project** → import `fremont-v3-demo` (Framework: Vite; build `npm run build`; output `dist`).
3. Environment variables:
   - `VITE_SUPABASE_URL` = `https://xyhtaufdyyokjvzctums.supabase.co`
   - `VITE_SUPABASE_ANON_KEY` = `sb_publishable_GcNY-c1_KzEnHrgylVcslQ_NwCZgVNj`
4. Deploy. Copy the new `*.vercel.app` address.
5. Supabase staging project → **Authentication → URL Configuration**: set Site URL and add Redirect URL = that address.
6. Send me the URL if you want me to re-check; I could not deploy it myself (no GitHub/Vercel access from my workspace).

## B. Demo logins (magic links — use Gmail plus-addresses so one inbox covers every role)
| Persona | Sign in with | Then |
|---|---|---|
| Commissioner (Kelly's view) | mini.muy.bonita+commish@gmail.com | run SQL 1 |
| Family: Alex + Ben | mini.muy.bonita+alexben@gmail.com | none — links automatically (household already exists) |
| New household | create in Admin → Households with mini.muy.bonita+newfam@gmail.com | sign in; auto-links |
| Team parent (Hawks) | mini.muy.bonita+hawks@gmail.com | run SQL 2 |
Sign in once per persona first, then run (Supabase SQL editor, staging project only):
```sql
-- 1
insert into app_role (auth_user_id, role) select id,'commissioner' from auth.users where email='mini.muy.bonita+commish@gmail.com';
-- 2
insert into app_role (auth_user_id, role, team_id) select id,'team_parent','00000000-0000-0000-0000-00000000b011' from auth.users where email='mini.muy.bonita+hawks@gmail.com';
-- Alex+Ben: add the guardian email once so claim_my_household can link them
insert into guardian (family_id, full_name, email, is_primary) values ('5c9ad1b7-dfb8-4813-ac7e-d17547fc5750','Alex (demo)','mini.muy.bonita+alexben@gmail.com',true);
```
(The old `*.test.fremont.local` accounts cannot receive email; they exist only for the automated tests.)

## C. Kelly demo, 10–15 minutes
1. **Commissioner → Commissioner tab** (2m): today's exceptions, registration review queue, identity review count.
2. **Admin → Households** (1m): add a household; **Seasons**: show one open season and the forward-only buttons.
3. **Family (Alex+Ben)** (3m): 2 children, 6h/360 min household total; open jobs → claim one; "Need a replacement" explains the $25.
4. **Commissioner → Phase B** (2m): Propose (nothing written) → review → Apply.
5. **Game Day** (3m): check in → enter exact minutes → Complete → Verify; report a no-show; show the closeout blocker.
6. **Replacement** (2m): other household takes the shift → staff "Mark Worked" → Commissioner "Verify & Credit" → $25 household credit.
7. **Fundraising** (1m): record cash (separate from credits); approve a $1 share link (board-gated).
8. **Reports** (1m): closeout readiness and totals.

## D. Click-through checklist for Minerva
Everything above, once per persona. I verified the database behavior (213 role/workflow assertions) and that every screen
renders and calls the right functions in a headless browser with mock data; **nobody has clicked through the real deployed
app yet** — that is the one remaining test.
