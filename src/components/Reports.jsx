import React, { useEffect, useState } from "react";
import { supabase } from "../lib/supabaseClient";
import { Card, StatCard, styles } from "./shared";

/* ============================================================
   REPORTS — reuses the same server-side summary RPCs that back
   the Commissioner Cockpit and Season Closeout, so the numbers
   here can never drift from what closeout actually checks.
   Team Parent/Coach view is scoped to their own team (no
   ledger-level financial detail — aggregate only).
   ============================================================ */
export default function Reports({ season, scopeTeamId }) {
  const [closeout, setCloseout] = useState(null);
  const [canClose, setCanClose] = useState(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!season) return;
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const [{ data: summary, error: sErr }, { data: close, error: cErr }] = await Promise.all([
          supabase.rpc("season_closeout_summary", { p_season_id: season.id }),
          scopeTeamId ? Promise.resolve({ data: null, error: null }) : supabase.rpc("can_close_season", { p_season_id: season.id }),
        ]);
        if (sErr) throw sErr;
        if (cErr) throw cErr;
        if (!cancelled) {
          setCloseout(summary?.[0] || null);
          setCanClose(close?.[0] || null);
        }
      } catch (e) {
        if (!cancelled) setError(e.message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [season, scopeTeamId]);

  if (!season) return <Card><p style={{ color: "#8a8a8a" }}>No active season.</p></Card>;
  if (loading) return <Card><p style={{ color: "#8a8a8a" }}>Loading report…</p></Card>;
  if (error) return <Card accent><p style={{ color: "#ff6b6b" }}>{error}</p></Card>;
  if (!closeout) return <Card><p style={{ color: "#8a8a8a" }}>No data yet for {season.name}.</p></Card>;

  return (
    <div style={styles.stack}>
      <Card>
        <p style={styles.eyebrow}>Reports</p>
        <h1 style={styles.h1}>{season.name}</h1>
      </Card>

      <Card>
        <h2 style={styles.h2}>Registration / Onboarding</h2>
        <div style={styles.grid3}>
          <StatCard icon="📋" label="Total" value={closeout.registration_total} />
          <StatCard icon="✅" label="Season Ready" value={closeout.registration_season_ready} />
          <StatCard icon="📈" label="Percent" value={`${closeout.registration_percent}%`} />
        </div>
      </Card>

      <Card>
        <h2 style={styles.h2}>Volunteer Hours (minutes, exact)</h2>
        <div style={styles.grid3}>
          <StatCard icon="🎯" label="Required" value={closeout.volunteer_required_minutes} />
          <StatCard icon="✅" label="Verified" value={closeout.volunteer_verified_minutes} />
          <StatCard icon="📈" label="Percent" value={`${closeout.volunteer_percent}%`} />
        </div>
      </Card>

      <Card>
        <h2 style={styles.h2}>Fundraising</h2>
        <div style={styles.grid3}>
          <StatCard icon="🎯" label="Required" value={`$${Number(closeout.fundraising_required).toLocaleString()}`} />
          <StatCard icon="💰" label="Raised" value={`$${Number(closeout.fundraising_raised).toLocaleString()}`} />
          <StatCard icon="📈" label="Percent" value={`${closeout.fundraising_percent}%`} />
        </div>
      </Card>

      <Card>
        <h2 style={styles.h2}>Uniforms</h2>
        <div style={styles.grid3}>
          <StatCard icon="👕" label="Total" value={closeout.equipment_total} />
          <StatCard icon="✅" label="Delivered" value={closeout.equipment_delivered} />
          <StatCard icon="📈" label="Percent" value={`${closeout.equipment_percent}%`} />
        </div>
      </Card>

      {canClose && (
        <Card accent>
          <h2 style={styles.h2}>Season Closeout Readiness</h2>
          {canClose.ready ? (
            <p style={{ color: "#3fb950", fontWeight: 800 }}>READY TO CLOSE ✓</p>
          ) : (
            <>
              <p style={{ color: "#ffb454", fontWeight: 800 }}>NOT READY — fails closed</p>
              <ul style={{ color: "#b5b5b5", fontSize: 13 }}>
                {(canClose.reasons || []).map((r, i) => <li key={i}>{r}</li>)}
              </ul>
            </>
          )}
        </Card>
      )}
    </div>
  );
}
