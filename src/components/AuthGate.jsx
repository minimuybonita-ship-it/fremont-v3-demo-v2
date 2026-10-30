import React, { useEffect, useState } from "react";
import { supabase } from "../lib/supabaseClient";
import { sendMagicLink, onAuthChange, getMyRoles, claimMyHousehold, createMyHousehold, signOut } from "../lib/auth";
import { Card, styles } from "./shared";

export default function AuthGate({ children }) {
  const [session, setSession] = useState(undefined);
  const [roles, setRoles] = useState([]);
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);
  const [error, setError] = useState("");
  const [profile, setProfile] = useState({ familyName: "", guardianName: "", phone: "" });
  const [creating, setCreating] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    return onAuthChange((s) => setSession(s));
  }, []);

  useEffect(() => {
    if (session) {
      (async () => {
        try {
          let r = await getMyRoles();
          if (r.filter((x) => x.auth_user_id === session.user.id).length === 0) {
            try { await claimMyHousehold(); } catch (e) { setError(e.message); }
            r = await getMyRoles();
          }
          setRoles(r);
        } catch (e) { setError(e.message); }
      })();
    } else setRoles([]);
  }, [session]);

  if (session === undefined) return <Card><p style={{ color: "#8a8a8a" }}>Checking sign-in…</p></Card>;

  if (!session) return (
    <Card>
      <p style={styles.eyebrow}>Sign In</p>
      <h1 style={styles.h1}>Fremont Command Center</h1>
      <p style={{ color: "#b5b5b5", marginBottom: 14 }}>Enter your email. We'll send a one-time sign-in link — no password to remember.</p>
      {sent ? <p style={{ color: "#8fce8f" }}>Check your email for a sign-in link. You can close this tab.</p> : <>
        <input style={styles.input} type="email" placeholder="you@example.com" value={email} onChange={(e) => setEmail(e.target.value)} />
        {error && <p style={{ color: "#ff6b6b", marginBottom: 8 }}>{error}</p>}
        <button style={styles.primaryBtn} onClick={async () => { setError(""); try { await sendMagicLink(email); setSent(true); } catch (e) { setError(e.message); } }}>Send sign-in link</button>
      </>}
    </Card>
  );

  if (roles.filter((r) => r.auth_user_id === session.user.id).length === 0) return (
    <Card>
      <p style={styles.eyebrow}>Family Setup</p>
      <h1 style={styles.h1}>Create your family profile</h1>
      <p style={{ color: "#b5b5b5", marginBottom: 14 }}>You're signed in. Set up your family, then you'll be able to add your player or players for the season.</p>
      {error && <p style={{ color: "#ffb454", marginBottom: 10 }}>{error}</p>}
      <input style={styles.input} placeholder="Family name (example: Llamas Family)" value={profile.familyName} onChange={(e) => setProfile({ ...profile, familyName: e.target.value })} />
      <input style={styles.input} placeholder="Your full name" value={profile.guardianName} onChange={(e) => setProfile({ ...profile, guardianName: e.target.value })} />
      <input style={styles.input} type="tel" placeholder="Phone (optional)" value={profile.phone} onChange={(e) => setProfile({ ...profile, phone: e.target.value })} />
      <button style={styles.primaryBtn} disabled={creating || !profile.familyName.trim() || !profile.guardianName.trim()} onClick={async () => {
        setCreating(true); setError("");
        try {
          await createMyHousehold({ displayName: profile.familyName, guardianName: profile.guardianName, guardianPhone: profile.phone });
          const r = await getMyRoles();
          setRoles(r);
        } catch (e) { setError(e.message); }
        finally { setCreating(false); }
      }}>{creating ? "Creating…" : "Create Family Profile"}</button>
      <button style={{ ...styles.linkBtn, marginTop: 10 }} onClick={signOut}>Sign out</button>
    </Card>
  );

  return children({ session, roles });
}
