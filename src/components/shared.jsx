import React from "react";

/* ============================================================
   SHARED UI PRIMITIVES — lifted verbatim from the existing
   LeagueFundraiserCommandCenter.jsx per the audit's Section E
   ("reusable components"). Same visual language, so Family
   Hub / Volunteer Engine / Commissioner Cockpit all feel like
   one continuous product rather than a rebuild.
   ============================================================ */

export function Card({ children, accent }) {
  return <div style={{ ...styles.card, ...(accent ? styles.cardAccent : {}) }}>{children}</div>;
}
export function ProgressBar({ percent }) {
  return (
    <div style={styles.progressTrack}>
      <div style={{ ...styles.progressFill, width: `${Math.max(4, percent)}%` }}>
        <span style={styles.progressLabel}>{percent}%</span>
      </div>
    </div>
  );
}
export function BigStat({ label, value }) {
  return (
    <div>
      <div style={{ fontSize: 12, color: "#8a8a8a", textTransform: "uppercase", letterSpacing: 1 }}>{label}</div>
      <div style={{ fontSize: 32, fontWeight: 900, color: "#c8102e" }}>{value}</div>
    </div>
  );
}
export function StatCard({ icon, label, value }) {
  return (
    <div style={styles.statCard}>
      <div style={{ fontSize: 20 }}>{icon}</div>
      <div style={{ fontSize: 20, fontWeight: 900 }}>{value}</div>
      <div style={{ fontSize: 11, color: "#8a8a8a", textTransform: "uppercase", letterSpacing: 0.5 }}>{label}</div>
    </div>
  );
}
export function MiniStat({ label, value }) {
  return (
    <div style={styles.miniStat}>
      <div style={{ fontSize: 18, fontWeight: 800 }}>{value}</div>
      <div style={{ fontSize: 10, color: "#8a8a8a", textTransform: "uppercase" }}>{label}</div>
    </div>
  );
}

export function StatusPill({ status }) {
  const map = {
    open: ["#8a8a8a", "Open"],
    claimed: ["#d4af37", "Claimed"],
    confirmed: ["#d4af37", "Confirmed"],
    scheduled: ["#3fa7d6", "Scheduled"],
    checked_in: ["#3fa7d6", "Checked In"],
    completed: ["#8fce8f", "Completed"],
    verified: ["#3fb950", "Verified"],
    credited: ["#3fb950", "Credited"],
    swap_requested: ["#d4af37", "Swap Requested"],
    replacement_requested: ["#d4af37", "Replacement Requested"],
    cancelled: ["#ff8a8a", "Cancelled"],
    no_show: ["#c8102e", "No Show"],
    excused: ["#8a8a8a", "Excused"],
    exempt: ["#8a8a8a", "Exempt"],
    needs_review: ["#ffb454", "Needs Review"],
    pending: ["#d4af37", "Pending"],
    approved: ["#3fb950", "Approved"],
    rejected: ["#ff8a8a", "Rejected"],
  };
  const [color, label] = map[status] || ["#8a8a8a", status];
  return (
    <span style={{ ...styles.statusPill, color, borderColor: color }}>{label}</span>
  );
}

export const styles = {
  app: { minHeight: "100vh", background: "#0a0a0a", color: "#f5f5f5", fontFamily: "'Inter','Helvetica Neue',Arial,sans-serif", paddingBottom: 40 },
  main: { maxWidth: 820, margin: "0 auto", padding: "16px" },
  stack: { display: "flex", flexDirection: "column", gap: 14 },
  card: { background: "#141414", border: "1px solid #241010", borderRadius: 18, padding: 18 },
  cardAccent: { borderColor: "#d4af37" },
  eyebrow: { fontSize: 11, letterSpacing: 1.5, textTransform: "uppercase", color: "#c8102e", fontWeight: 800, margin: 0 },
  h1: { fontSize: 24, fontWeight: 900, margin: "4px 0 12px" },
  h2: { fontSize: 17, fontWeight: 800, margin: "0 0 10px" },
  grid2: { display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 },
  grid3: { display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8, marginTop: 12 },
  grid4: { display: "grid", gridTemplateColumns: "1fr 1fr 1fr 1fr", gap: 8 },
  statCard: { background: "#141414", border: "1px solid #241010", borderRadius: 16, padding: 14, textAlign: "center" },
  miniStat: { background: "#1c1c1c", borderRadius: 12, padding: "10px 6px", textAlign: "center" },
  progressTrack: { height: 26, background: "#1c1c1c", borderRadius: 999, overflow: "hidden" },
  progressFill: { height: "100%", background: "linear-gradient(90deg,#c8102e,#8a0c1f)", display: "flex", alignItems: "center", justifyContent: "flex-end", paddingRight: 10, transition: "width .3s ease" },
  progressLabel: { fontSize: 12, fontWeight: 800 },
  input: { width: "100%", boxSizing: "border-box", background: "#1c1c1c", border: "1px solid #2a2a2a", borderRadius: 10, padding: "12px 12px", color: "#fff", marginBottom: 10, fontSize: 14 },
  primaryBtn: { background: "#c8102e", color: "#fff", border: "none", borderRadius: 12, padding: "12px 16px", fontWeight: 800, fontSize: 14, cursor: "pointer" },
  secondaryBtn: { background: "#1c1c1c", color: "#fff", border: "1px solid #d4af37", borderRadius: 12, padding: "12px 16px", fontWeight: 800, fontSize: 14, cursor: "pointer" },
  secondaryBtnSm: { background: "#1c1c1c", color: "#fff", border: "1px solid #d4af37", borderRadius: 8, padding: "6px 10px", fontWeight: 700, fontSize: 12, cursor: "pointer" },
  linkBtn: { background: "transparent", border: "none", color: "#d4af37", fontWeight: 700, fontSize: 12, padding: 0, marginTop: 6, cursor: "pointer" },
  requestRow: { display: "flex", justifyContent: "space-between", alignItems: "center", padding: "10px 0", borderBottom: "1px solid #241010", gap: 10 },
  table: { width: "100%", borderCollapse: "collapse", fontSize: 12, minWidth: 560 },
  th: { textAlign: "left", padding: "8px 6px", color: "#8a8a8a", fontWeight: 700, borderBottom: "1px solid #2a2a2a" },
  td: { padding: "8px 6px", borderBottom: "1px solid #1c1c1c" },
  statusPill: { fontSize: 11, fontWeight: 800, border: "1px solid", borderRadius: 999, padding: "3px 10px", whiteSpace: "nowrap" },
};
