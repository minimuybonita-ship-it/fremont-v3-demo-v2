# Final Delivery Checklist — Handoff to Another Developer or to the Organization

- [ ] All schema files (001–006, 999) reviewed and, if applied, confirmed matching the live staging/production schema
- [ ] `get_advisors` (security) clean on the target project
- [ ] Auth/RLS tested per QA_CHECKLIST.md privacy section
- [ ] Gate 0 fix deployed and verified in production (not just staging)
- [ ] Data migration run, reviewed, and spot-checked against the original backup
- [ ] Original `app_state` rows preserved post-cutover, not deleted
- [ ] BUILD_STATUS_MATRIX.md reviewed — every NOT BUILT / PARTIAL / NEEDS FOUNDER DECISION item has an owner and next step, none silently dropped
- [ ] Rollback plan (DEPLOYMENT_MIGRATION_ROLLBACK.md Step 6) tested at least once in staging, not just written
- [ ] Credentials/environment variables documented (without secrets committed to any file) for whoever runs this next
- [ ] This document package itself (schema/, src/, docs/) handed over as a single, versioned unit
