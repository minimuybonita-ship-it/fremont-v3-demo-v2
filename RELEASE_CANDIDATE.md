# Fremont V3 — Release Candidate (staging only)
Updated 2026-10-22. Database: Supabase staging `xyhtaufdyyokjvzctums`. The live chocolate system was not touched.

## What changed in this pass
- Migrations 027–032: all grants locked down; anonymous users have no table or function access; every consequential write is a
  narrow server-side function (assignments, replacement credit, share credit, cash, no-show, household link, season status).
- App rewired to those functions; season loads after sign-in; roles filtered to the signed-in user; fails closed on 0 or >1 open seasons.
- Verified: QA Suite A 213/213, Suite B 5/5, cash-import test, clean rebuild 001→032 identical to staging, app bundles, headless smoke test.

## Known V1 limitations
- Schedule/jobs and team-parent/coach roles are set by SQL (docs/V1_PROCEDURES.md).
- Empty season passes closeout readiness (vacuous).
- Staging holds real legacy roster names (Commissioner-visible) — use a scrubbed copy before showing outsiders.
- Uniform/ack self-attestation by families is allowed; no money depends on it.
- Swap requests (V2) still use the older permissive policy; nothing financial reads them.
- Demo season config has `share_credit_board_approved = true` for demonstration only.
- Real Vite build runs on Vercel (npm blocked in my workspace); bundle verified with esbuild.

## V2 / FUTURE parking list
Admin job-role editor · Standard Home Game template editor · in-app role assignment · swap workflow hardening · scheduled reminders · exports.

## Exact pre-go-live manual actions (none is done yet)
1. **Leaked-password protection** (required gate, NOT done): Supabase dashboard → project → Authentication → Sign In / Providers (or Attack Protection) → Password security → turn on "Prevent use of leaked passwords" → Save. Re-run the advisors to confirm.
2. Set `share_credit_board_approved=false` in the production config until the board approves.
3. Create the production V3 project, apply schema 001→032 in order, no demo fixtures; set Auth redirect URLs.
4. Optional tidy: `028b` inert-policy drops (needs your approval).
5. Production activation only after Minerva approves; legacy import (999b) as its own approved step.
