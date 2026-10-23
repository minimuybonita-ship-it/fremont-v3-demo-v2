// FREMONT V3 — auth helpers
// Email magic-link sign-in. No passwords for parents to manage or forget.
// Role resolution happens server-side via RLS (see schema/006_auth_and_rls.sql);
// this module never trusts a client-held role value for access decisions —
// it only uses the resolved role to decide what UI to show.

import { supabase } from "./supabaseClient";

export async function sendMagicLink(email) {
  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: { emailRedirectTo: window.location.origin },
  });
  if (error) throw error;
}

export async function signOut() {
  await supabase.auth.signOut();
}

export function onAuthChange(callback) {
  const { data } = supabase.auth.onAuthStateChange((_event, session) => {
    callback(session);
  });
  return () => data.subscription.unsubscribe();
}

// Resolves this user's role rows. The RLS policies on app_role itself
// restrict this to the caller's own rows, so this is safe to call directly —
// it cannot be used to enumerate anyone else's roles.
export async function getMyRoles() {
  const { data, error } = await supabase.from("app_role").select("*");
  if (error) throw error;
  return data || [];
}

// Links this VERIFIED login email to the single household the Commissioner created for it (server-side, fail-closed).
// Returns the family id, or null when there is nothing to link.
export async function claimMyHousehold() {
  const { data, error } = await supabase.rpc("claim_my_household");
  if (error) throw error;
  return data;
}
