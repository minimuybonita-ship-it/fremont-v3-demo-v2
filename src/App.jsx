import React, { useEffect, useState } from "react";
import { supabase } from "./lib/supabaseClient";
import AuthGate from "./components/AuthGate";
import FamilyDashboard from "./components/FamilyDashboard";
import Registration from "./components/Registration";
import IdentityReview from "./components/IdentityReview";
import CommissionerCockpit from "./components/CommissionerCockpit";
import TeamHome from "./components/TeamHome";
import GameDay from "./components/GameDay";
import Reports from "./components/Reports";
import Admin from "./components/Admin";
import { Card, styles } from "./components/shared";

/* ============================================================
   APP SHELL — role-aware navigation + active-season resolution.
   FAIL-SAFE RULE: if the active season can't be resolved
   unambiguously (none open, or more than one simultaneously
   open/active), every screen that depends on a season shows a
   safe "contact your Commissioner" state instead of guessing.
   ============================================================ */
export default function App() {
  return (
    <div style={styles.app}>
      <div style={styles.main}>
        <AuthGate>
          {({ session, roles }) => <Authed session={session} roles={roles} />}
        </AuthGate>
      </div>
    </div>
  );
}

// Season resolution runs ONLY after sign-in (anonymous visitors can read nothing).
// Fails closed: zero or multiple open/active seasons -> season = null plus an explanation.
function Authed({ session, roles }) {
  const [season, setSeason] = useState(undefined); // undefined = loading, null = none/ambiguous
  const [seasonError, setSeasonError] = useState("");
  // The Commissioner can read every role row; only this user's own rows decide what UI to show.
  const myRoles = roles.filter((r) => r.auth_user_id === session.user.id);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data, error } = await supabase
        .from("season")
        .select("id, name, status")
        .in("status", ["registration_open", "active"]);
      if (cancelled) return;
      if (error) { setSeasonError(error.message); setSeason(null); return; }
      if (!data || data.length === 0) { setSeason(null); return; }
      if (data.length > 1) {
        setSeasonError(`${data.length} seasons are open/active at once. A Commissioner needs to close one before this can continue.`);
        setSeason(null);
        return;
      }
      const { data: cfg } = await supabase
        .from("season_config")
        .select("id, hours_per_child, minutes_per_child, fundraising_goal_per_child")
        .eq("season_id", data[0].id)
        .order("effective_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (!cancelled) setSeason({ ...data[0], season_config_id: cfg?.id || null });
    })();
    return () => { cancelled = true; };
  }, [session.user.id]);

  if (season === undefined) return <Card><p style={{ color: "#8a8a8a" }}>Loading season…</p></Card>;
  return <RoleRouter session={session} roles={myRoles} season={season} seasonError={seasonError} />;
}

const TABS_BY_ROLE = {
  guardian: [["household", "My Household"], ["dashboard", "Dashboard"]],
  team_parent: [["team", "My Team"], ["gameday", "Game Day"]],
  coach: [["team", "My Team"], ["gameday", "Game Day"]],
  commissioner: [
    ["cockpit", "Commissioner"],
    ["identity", "Identity Review"],
    ["gameday", "Game Day"],
    ["reports", "Reports"],
    ["admin", "Admin"],
  ],
  platform_owner: [["cockpit", "Commissioner"], ["admin", "Admin"]],
};

function RoleRouter({ session, roles, season, seasonError }) {
  const roleNames = Array.from(new Set(roles.map((r) => r.role)));
  const tabs = roleNames.flatMap((r) => TABS_BY_ROLE[r] || []);
  const uniqueTabs = Array.from(new Map(tabs).entries());
  const [active, setActive] = useState(uniqueTabs[0]?.[0] || null);

  const commissionerRole = roles.find((r) => r.role === "commissioner" || r.role === "platform_owner");
  const guardianRole = roles.find((r) => r.role === "guardian");
  const teamRole = roles.find((r) => r.role === "team_parent" || r.role === "coach");

  if (!uniqueTabs.length) {
    return <Card><p style={{ color: "#8a8a8a" }}>No screens are available for your current role.</p></Card>;
  }

  return (
    <div style={styles.stack}>
      <div style={{ display: "flex", gap: 8, overflowX: "auto", paddingBottom: 4 }}>
        {uniqueTabs.map(([key, label]) => (
          <button
            key={key}
            style={active === key ? styles.primaryBtn : styles.secondaryBtn}
            onClick={() => setActive(key)}
          >
            {label}
          </button>
        ))}
      </div>

      {seasonError && (
        <Card accent><p style={{ color: "#ffb454" }}>{seasonError}</p></Card>
      )}

      {active === "household" && guardianRole && <Registration session={session} familyId={guardianRole.family_id} activeSeason={season} />}
      {active === "dashboard" && guardianRole && <FamilyDashboard familyId={guardianRole.family_id} season={season} />}
      {active === "team" && teamRole && <TeamHome teamId={teamRole.team_id} season={season} />}
      {active === "gameday" && (commissionerRole || teamRole) && (
        <GameDay teamId={teamRole?.team_id} isCommissioner={!!commissionerRole} season={season} />
      )}
      {active === "reports" && season && commissionerRole && <Reports season={season} scopeTeamId={null} />}
      {active === "cockpit" && commissionerRole && <CommissionerCockpit seasonId={season?.id} />}
      {active === "identity" && commissionerRole && <IdentityReview />}
      {active === "admin" && commissionerRole && <Admin season={season} />}

      {!season && ["dashboard", "team", "reports", "cockpit"].includes(active) && (
        <Card><p style={{ color: "#8a8a8a" }}>Nothing to show until a season is unambiguously open or active.</p></Card>
      )}
    </div>
  );
}
