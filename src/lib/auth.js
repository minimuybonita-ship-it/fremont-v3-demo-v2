// FREMONT V3 — auth helpers
import { supabase } from "./supabaseClient";

export async function sendMagicLink(email) {
  const { error } = await supabase.auth.signInWithOtp({ email, options: { emailRedirectTo: window.location.origin } });
  if (error) throw error;
}
export async function signOut() { await supabase.auth.signOut(); }
export function onAuthChange(callback) {
  const { data } = supabase.auth.onAuthStateChange((_event, session) => callback(session));
  return () => data.subscription.unsubscribe();
}
export async function getMyRoles() {
  const { data, error } = await supabase.from("app_role").select("*");
  if (error) throw error;
  return data || [];
}
export async function claimMyHousehold() {
  const { data, error } = await supabase.rpc("claim_my_household");
  if (error) throw error;
  return data;
}
export async function createMyHousehold({ displayName, guardianName, guardianPhone }) {
  const { data, error } = await supabase.rpc("create_my_household", {
    p_display_name: displayName,
    p_guardian_name: guardianName,
    p_guardian_phone: guardianPhone || null,
  });
  if (error) throw error;
  return data;
}
