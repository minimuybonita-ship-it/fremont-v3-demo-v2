import React, { useEffect, useState } from "react";
import { supabase } from "../lib/supabaseClient";
import { sendMagicLink, onAuthChange, getMyRoles, claimMyHousehold, signOut } from "../lib/auth";
import { Card, styles } from "./shared";

/* ============================================================
   AUTH GATE — replaces the old shared/hardcoded PIN model.
   This is the direct fix for the audit's #1 conflict: the
   Family view previously had NO access control at all.
   ============================================================ */
export default function AuthGate({ children }) {
  const [session, setSession] = useState(undefined); // undefined = still checking
  const [roles, setRoles] = useState([]);
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);
  const [error, setError] = useState("");

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
            // First sign-in: link this VERIFIED email to exactly one household the Commissioner created.
            // Server fails closed (no match / ambiguous / unverified -> no role).
            try { await claimMyHousehold(); } catch (e) { setError(e.message); }
            r = await getMyRoles();
          }
          setRoles(r);
        } catch (e) { setError(e.message); }
      })();
    } else {
      setRoles([]);
    }
  }, [session]);

  if (session === undefined) {
    return <Card><p style={{ color: "#8a8a8a" }}>Checking sign-in…</p></Card>;
  }

  if (!session) {
    return (
      <Card>
        <p style={styles.eyebrow}>Sign In</p>
        <h1 style={styles.h1}>Fremont Command Center</h1>
        <p style={{ color: "#b5b5b5", marginBottom: 14 }}>
          Enter your email. We'll send a one-time sign-in link — no password to remember.
        </p>
        {sent ? (
          <p style={{ color: "#8fce8f" }}>
            Check your email for a sign-in link. You can close this tab.
          </p>
        ) : (
          <>
            <input
              style={styles.input}
              type="email"
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
            {error && <p style={{ color: "#ff6b6b", marginBottom: 8 }}>{error}</p>}
            <button
              style={styles.primaryBtn}
              onClick={async () => {
                setError("");
                try {
                  await sendMagicLink(email);
                  setSent(true);
                } catch (e) {
                  setError(e.message);
                }
              }}
            >
              Send sign-in link
            </button>
          </>
        )}
      </Card>
    );
  }

  // Signed in but no role row yet — commissioner/coach/team-parent/guardian
  // roles are assigned by an administrator (app_role table), not self-granted.
  if (roles.filter((r) => r.auth_user_id === session.user.id).length === 0) {
    return (
      <Card>
        <p style={styles.eyebrow}>Account Pending</p>
        <h1 style={styles.h1}>Almost there</h1>
        <p style={{ color: "#b5b5b5" }}>
          You're signed in, but your account isn't linked to a family or team yet.
          Contact your Commissioner or Team Parent to finish setup.
        </p>
        {error && <p style={{ color: "#ff6b6b", marginTop: 8 }}>{error}</p>}
        <button style={{ ...styles.linkBtn, marginTop: 10 }} onClick={signOut}>Sign out</button>
      </Card>
    );
  }

  return children({ session, roles });
}
