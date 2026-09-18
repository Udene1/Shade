"use client";

type HealthCheck = { check_name: string; status: string; detail: string };

export function DataHealth({ checks }: { checks: HealthCheck[] }) {
  const errors = checks.filter((c) => c.status === "ERROR").length;
  const warnings = checks.filter((c) => c.status === "WARNING").length;
  return (
    <section className="card section">
      <div className="row">
        <div><h2>Data health</h2><p className="muted">Live integrity checks against the business ledger.</p></div>
        <strong>{errors ? `${errors} error${errors === 1 ? "" : "s"}` : warnings ? `${warnings} warning${warnings === 1 ? "" : "s"}` : "All clear"}</strong>
      </div>
      {checks.length === 0 ? <p className="muted">No health checks are available.</p> : checks.map((c) => (
        <div className="row" key={c.check_name}>
          <div><strong>{c.check_name.replaceAll("_", " ")}</strong><div className="muted">{c.detail}</div></div>
          <span>{c.status}</span>
        </div>
      ))}
    </section>
  );
}
