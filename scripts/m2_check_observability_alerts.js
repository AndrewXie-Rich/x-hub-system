#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i += 1) {
    const cur = String(argv[i] || "");
    if (!cur.startsWith("--")) continue;
    const key = cur.slice(2);
    const nxt = argv[i + 1];
    if (nxt && !String(nxt).startsWith("--")) {
      out[key] = String(nxt);
      i += 1;
    } else {
      out[key] = "1";
    }
  }
  return out;
}

function num(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function readJson(fp) {
  return JSON.parse(fs.readFileSync(fp, "utf8"));
}

function fail(msg, details = {}) {
  console.error(JSON.stringify({ ok: false, error: String(msg || "failed"), ...details }, null, 2));
  process.exit(2);
}

function main() {
  const args = parseArgs(process.argv);
  const repoRoot = path.resolve(__dirname, "..");
  const dashboardPath = path.resolve(
    args.dashboard || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w5-observability/dashboard_snapshot.json")
  );
  const maxCritical = Math.max(0, num(args["max-critical"], 0));
  const maxWarn = Math.max(0, num(args["max-warn"], Number.POSITIVE_INFINITY));
  const ignoreSuppressedWarn = String(args["ignore-suppressed-warn"] || "1").trim() !== "0";

  if (!fs.existsSync(dashboardPath)) fail("dashboard_not_found", { dashboard: dashboardPath });
  const dashboard = readJson(dashboardPath);
  const items = Array.isArray(dashboard?.alerts?.items) ? dashboard.alerts.items : [];

  const criticalItems = items.filter((it) => String(it?.status || "") === "critical");
  const warnItems = items.filter((it) => {
    if (String(it?.status || "") !== "warn") return false;
    if (!ignoreSuppressedWarn) return true;
    return it?.suppressed_by_noise !== true;
  });
  const summary = {
    critical: criticalItems.length,
    warn: warnItems.length,
    no_data: items.filter((it) => String(it?.status || "") === "no_data").length,
    total: items.length,
  };

  const out = {
    ok: summary.critical <= maxCritical && summary.warn <= maxWarn,
    dashboard: path.relative(repoRoot, dashboardPath),
    limits: { max_critical: maxCritical, max_warn: maxWarn },
    summary,
    critical_items: criticalItems.slice(0, 10).map((it) => ({
      id: it?.id || "",
      value: it?.value ?? null,
      threshold: it?.threshold ?? null,
      stage_hint: it?.stage_hint || "",
      hint: it?.hint || "",
    })),
    warn_items: warnItems.slice(0, 10).map((it) => ({
      id: it?.id || "",
      value: it?.value ?? null,
      threshold: it?.threshold ?? null,
      stage_hint: it?.stage_hint || "",
      hint: it?.hint || "",
    })),
  };

  if (!out.ok) {
    console.error(JSON.stringify(out, null, 2));
    process.exit(2);
  }
  console.log(JSON.stringify(out, null, 2));
}

main();
