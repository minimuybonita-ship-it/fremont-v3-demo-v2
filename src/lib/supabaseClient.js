// FREMONT V3 — CONTROLLED WORKING VERSION
// This file intentionally does NOT point at the live production project.
// Fill in a STAGING project's URL/key before running this anywhere.
// Wiring this at real credentials is a deliberate, separate cutover step —
// see docs/DEPLOYMENT_MIGRATION_ROLLBACK.md.

import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = import.meta.env?.VITE_SUPABASE_URL || "REPLACE_WITH_STAGING_PROJECT_URL";
const SUPABASE_ANON_KEY = import.meta.env?.VITE_SUPABASE_ANON_KEY || "REPLACE_WITH_STAGING_ANON_KEY";

if (SUPABASE_URL.startsWith("REPLACE_WITH")) {
  // Loud, impossible-to-miss warning rather than a silent fallback —
  // the whole point of Gate 0 was an app that lies about its own state.
  // eslint-disable-next-line no-console
  console.warn(
    "[fremont-v3] supabaseClient is NOT configured. This build will not " +
    "read or write any real data until VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY " +
    "are set to a real (staging, not production) project."
  );
}

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
