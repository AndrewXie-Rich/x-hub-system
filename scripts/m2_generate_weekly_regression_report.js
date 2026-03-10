#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const DEFAULT_SCHEMA = "xhub.memory.weekly_regression_report.v1";
const DEFAULT_HISTORY_SCHEMA = "xhub.memory.weekly_regression_history.v1";

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

function boolArg(v, fallback = false) {
  if (v == null || v === "") return !!fallback;
  const s = String(v).trim().toLowerCase();
  if (["1", "true", "yes", "y", "on"].includes(s)) return true;
  if (["0", "false", "no", "n", "off"].includes(s)) return false;
  return !!fallback;
}

function readJson(fp) {
  return JSON.parse(fs.readFileSync(fp, "utf8"));
}

function readJsonl(fp) {
  if (!fp || !fs.existsSync(fp)) return [];
  const lines = String(fs.readFileSync(fp, "utf8") || "")
    .split(/\r?\n/)
    .map((x) => x.trim())
    .filter(Boolean);
  const rows = [];
  for (const line of lines) {
    try {
      const obj = JSON.parse(line);
      if (obj && typeof obj === "object") rows.push(obj);
    } catch {
      // ignore malformed line
    }
  }
  return rows;
}

function writeJson(fp, obj) {
  fs.mkdirSync(path.dirname(fp), { recursive: true });
  fs.writeFileSync(fp, `${JSON.stringify(obj, null, 2)}\n`, "utf8");
}

function writeText(fp, text) {
  fs.mkdirSync(path.dirname(fp), { recursive: true });
  fs.writeFileSync(fp, String(text || ""), "utf8");
}

function appendJsonl(fp, obj) {
  fs.mkdirSync(path.dirname(fp), { recursive: true });
  fs.appendFileSync(fp, `${JSON.stringify(obj)}\n`, "utf8");
}

function mergeThresholds(base, override) {
  const out = { ...base };
  if (!override || typeof override !== "object") return out;
  for (const k of Object.keys(base)) {
    if (Object.prototype.hasOwnProperty.call(override, k)) {
      out[k] = num(override[k], base[k]);
    }
  }
  return out;
}

function formatPct(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return "n/a";
  return `${(n * 100).toFixed(2)}%`;
}

function formatNum(v, digits = 4) {
  const n = Number(v);
  if (!Number.isFinite(n)) return "n/a";
  return Number(n.toFixed(digits)).toString();
}

function computeBenchDeltas({ baseline, current }) {
  const bGolden = baseline?.metrics?.golden || {};
  const cGolden = current?.metrics?.golden || {};
  const bAdv = baseline?.metrics?.adversarial || {};
  const cAdv = current?.metrics?.adversarial || {};

  const p95Base = Math.max(0.0001, num(bGolden?.latency_ms?.p95, 0.0001));
  const p95Current = num(cGolden?.latency_ms?.p95, 0);
  return {
    recall_delta: num(cGolden.recall_at_k_avg) - num(bGolden.recall_at_k_avg),
    precision_delta: num(cGolden.precision_at_k_avg) - num(bGolden.precision_at_k_avg),
    p95_latency_delta_ms: p95Current - p95Base,
    p95_latency_ratio: p95Current / p95Base,
    adversarial_match_delta: num(cAdv.expected_match_rate) - num(bAdv.expected_match_rate),
  };
}

function evaluateBenchChecks({ deltas, thresholds }) {
  return [
    {
      key: "recall",
      pass: deltas.recall_delta >= -thresholds.recall_drop_max,
      value: deltas.recall_delta,
      threshold: -thresholds.recall_drop_max,
      detail: `delta=${deltas.recall_delta.toFixed(4)} (max drop=${thresholds.recall_drop_max})`,
    },
    {
      key: "precision",
      pass: deltas.precision_delta >= -thresholds.precision_drop_max,
      value: deltas.precision_delta,
      threshold: -thresholds.precision_drop_max,
      detail: `delta=${deltas.precision_delta.toFixed(4)} (max drop=${thresholds.precision_drop_max})`,
    },
    {
      key: "p95_latency",
      pass: deltas.p95_latency_ratio <= (1 + thresholds.p95_latency_growth_max),
      value: deltas.p95_latency_ratio,
      threshold: 1 + thresholds.p95_latency_growth_max,
      detail: `ratio=${deltas.p95_latency_ratio.toFixed(4)} (max ratio=${(1 + thresholds.p95_latency_growth_max).toFixed(4)})`,
    },
    {
      key: "adversarial_match",
      pass: deltas.adversarial_match_delta >= -thresholds.adversarial_match_drop_max,
      value: deltas.adversarial_match_delta,
      threshold: -thresholds.adversarial_match_drop_max,
      detail: `delta=${deltas.adversarial_match_delta.toFixed(4)} (max drop=${thresholds.adversarial_match_drop_max})`,
    },
  ];
}

function normalizeAlerts(dashboard = {}) {
  const summary = dashboard?.alerts?.summary && typeof dashboard.alerts.summary === "object"
    ? dashboard.alerts.summary
    : {};
  const items = Array.isArray(dashboard?.alerts?.items) ? dashboard.alerts.items : [];
  const warnItems = items.filter((it) => String(it?.status || "") === "warn" && it?.suppressed_by_noise !== true);
  const criticalItems = items.filter((it) => String(it?.status || "") === "critical");
  return {
    summary: {
      critical: Number(summary.critical || 0),
      warn: Number(summary.warn || 0),
      no_data: Number(summary.no_data || 0),
      total: Number(summary.total || 0),
    },
    critical_items: criticalItems,
    warn_items: warnItems,
    top_stage: dashboard?.pipeline_stages?.top_anomalies?.[0] || null,
  };
}

function buildHistoryEntry({ nowMs, currentReport, benchmarkChecks, dashboardAlerts, sourceCurrent, sourceDashboard }) {
  return {
    schema_version: DEFAULT_HISTORY_SCHEMA,
    generated_at_ms: Number(nowMs || Date.now()),
    source_current_report: String(sourceCurrent || ""),
    source_dashboard: String(sourceDashboard || ""),
    metrics: {
      precision_at_k_avg: num(currentReport?.metrics?.golden?.precision_at_k_avg, 0),
      recall_at_k_avg: num(currentReport?.metrics?.golden?.recall_at_k_avg, 0),
      p95_latency_ms: num(currentReport?.metrics?.golden?.latency_ms?.p95, 0),
      adversarial_match_rate: num(currentReport?.metrics?.adversarial?.expected_match_rate, 0),
      gate1_correctness: !!currentReport?.gate_hints?.gate1_correctness,
      gate2_performance: !!currentReport?.gate_hints?.gate2_performance,
      gate3_security: !!currentReport?.gate_hints?.gate3_security,
      failed_checks: benchmarkChecks.filter((x) => !x.pass).map((x) => x.key),
      alerts_critical: Number(dashboardAlerts?.summary?.critical || 0),
      alerts_warn: Number(dashboardAlerts?.summary?.warn || 0),
    },
  };
}

function tailHistoryEntries(entries = [], limit = 6) {
  const rows = Array.isArray(entries) ? entries : [];
  if (rows.length <= limit) return rows;
  return rows.slice(rows.length - limit);
}

function toMermaidTrend({ labels, recall, precision, p95, adversarial }) {
  const fmt = (arr, digits = 4) => arr.map((v) => {
    const n = Number(v);
    if (!Number.isFinite(n)) return "0";
    return Number(n.toFixed(digits)).toString();
  }).join(", ");
  const lbl = labels.map((x) => `"${String(x || "").replace(/"/g, "")}"`).join(", ");
  return [
    "```mermaid",
    "xychart-beta",
    '  title "M2 Weekly Regression Trends"',
    `  x-axis "week" [${lbl}]`,
    "  y-axis \"score\" 0 --> 1.6",
    `  line "recall" [${fmt(recall)}]`,
    `  line "precision" [${fmt(precision)}]`,
    `  line "adversarial_match" [${fmt(adversarial)}]`,
    `  line "p95_latency_ratio" [${fmt(p95)}]`,
    "```",
  ].join("\n");
}

function buildTodos({ benchmarkChecks, dashboardAlerts, currentReport }) {
  const todos = [];
  for (const check of benchmarkChecks) {
    if (check.pass) continue;
    todos.push({
      id: `todo.regression.${check.key}`,
      severity: "p1",
      owner: "hub-memory",
      source: "benchmark_regression",
      summary: `Regression detected on ${check.key}`,
      detail: check.detail,
      suggested_action: "Investigate pipeline stage diff and update tuning or rollback candidate change.",
      stage_hint: check.key === "p95_latency" ? "queue" : "retrieval",
    });
  }

  const gate3Pass = !!currentReport?.gate_hints?.gate3_security;
  if (!gate3Pass) {
    todos.push({
      id: "todo.security.gate3",
      severity: "p0",
      owner: "security",
      source: "gate_hint",
      summary: "gate3_security is failing in weekly snapshot",
      detail: "Gate-3 requires prompt_bundle gate + secret_mode + credential deny + blocked consistency.",
      suggested_action: "Prioritize security gate hardening and verify adversarial block behavior.",
      stage_hint: "gate",
    });
  }

  const critical = Number(dashboardAlerts?.summary?.critical || 0);
  if (critical > 0) {
    todos.push({
      id: "todo.alerts.critical",
      severity: "p1",
      owner: "sre",
      source: "observability_alert",
      summary: `Critical observability alerts detected (${critical})`,
      detail: "At least one critical alert breached threshold.",
      suggested_action: "Inspect dashboard critical items and apply mitigation before next promotion.",
      stage_hint: String(dashboardAlerts?.top_stage?.stage || ""),
    });
  }

  const warn = Number(dashboardAlerts?.summary?.warn || 0);
  if (warn > 2) {
    todos.push({
      id: "todo.alerts.warn_noise",
      severity: "p2",
      owner: "sre",
      source: "observability_alert",
      summary: `Warn alerts over budget (${warn} > 2)`,
      detail: "Warn alert count exceeds weekly noise budget.",
      suggested_action: "Tune threshold/noise-control or fix noisy stage regressions.",
      stage_hint: String(dashboardAlerts?.top_stage?.stage || ""),
    });
  }

  return todos;
}

function buildWeeklyReport({
  nowMs,
  currentReport,
  baselineReport,
  regressionThresholds,
  dashboard,
  historyEntries,
  sourcePaths,
}) {
  const deltas = computeBenchDeltas({ baseline: baselineReport, current: currentReport });
  const checks = evaluateBenchChecks({
    deltas,
    thresholds: regressionThresholds,
  });
  const dashboardAlerts = normalizeAlerts(dashboard);
  const todos = buildTodos({
    benchmarkChecks: checks,
    dashboardAlerts,
    currentReport,
  });

  const currentEntry = buildHistoryEntry({
    nowMs,
    currentReport,
    benchmarkChecks: checks,
    dashboardAlerts,
    sourceCurrent: sourcePaths.current_report,
    sourceDashboard: sourcePaths.dashboard,
  });
  const trendRows = tailHistoryEntries([...(historyEntries || []), currentEntry], 6);
  const labels = trendRows.map((row, idx) => {
    const ts = Number(row?.generated_at_ms || 0);
    if (ts > 0) {
      const d = new Date(ts);
      const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
      const dd = String(d.getUTCDate()).padStart(2, "0");
      return `${mm}-${dd}`;
    }
    return `w${idx + 1}`;
  });

  const recallTrend = trendRows.map((x) => num(x?.metrics?.recall_at_k_avg, 0));
  const precisionTrend = trendRows.map((x) => num(x?.metrics?.precision_at_k_avg, 0));
  const advTrend = trendRows.map((x) => num(x?.metrics?.adversarial_match_rate, 0));
  const p95Base = Math.max(0.0001, num(baselineReport?.metrics?.golden?.latency_ms?.p95, 0.0001));
  const p95RatioTrend = trendRows.map((x) => num(x?.metrics?.p95_latency_ms, 0) / p95Base);

  return {
    schema_version: DEFAULT_SCHEMA,
    generated_at_ms: Number(nowMs || Date.now()),
    sources: sourcePaths,
    baseline: {
      precision_at_k_avg: num(baselineReport?.metrics?.golden?.precision_at_k_avg, 0),
      recall_at_k_avg: num(baselineReport?.metrics?.golden?.recall_at_k_avg, 0),
      p95_latency_ms: num(baselineReport?.metrics?.golden?.latency_ms?.p95, 0),
      adversarial_match_rate: num(baselineReport?.metrics?.adversarial?.expected_match_rate, 0),
    },
    current: {
      precision_at_k_avg: num(currentReport?.metrics?.golden?.precision_at_k_avg, 0),
      recall_at_k_avg: num(currentReport?.metrics?.golden?.recall_at_k_avg, 0),
      p95_latency_ms: num(currentReport?.metrics?.golden?.latency_ms?.p95, 0),
      adversarial_match_rate: num(currentReport?.metrics?.adversarial?.expected_match_rate, 0),
      gate_hints: currentReport?.gate_hints || {},
    },
    deltas,
    regression_thresholds: regressionThresholds,
    checks,
    observability_alerts: dashboardAlerts,
    trends: {
      labels,
      recall_at_k_avg: recallTrend,
      precision_at_k_avg: precisionTrend,
      adversarial_match_rate: advTrend,
      p95_latency_ratio_vs_baseline: p95RatioTrend,
      points: trendRows.length,
    },
    todos,
    summary: {
      check_fail_count: checks.filter((x) => !x.pass).length,
      critical_alerts: Number(dashboardAlerts?.summary?.critical || 0),
      warn_alerts: Number(dashboardAlerts?.summary?.warn || 0),
      todo_count: todos.length,
      gate3_security: !!currentReport?.gate_hints?.gate3_security,
    },
    history_entry: currentEntry,
  };
}

function toMarkdown(report) {
  const lines = [];
  lines.push("# M2 Weekly Regression Report");
  lines.push("");
  lines.push(`- generated_at: ${new Date(Number(report?.generated_at_ms || Date.now())).toISOString()}`);
  lines.push(`- schema_version: ${String(report?.schema_version || "")}`);
  lines.push("");

  lines.push("## Baseline vs Current");
  lines.push("| Metric | Baseline | Current | Delta |");
  lines.push("|---|---:|---:|---:|");
  lines.push(`| precision@k(avg) | ${formatNum(report?.baseline?.precision_at_k_avg)} | ${formatNum(report?.current?.precision_at_k_avg)} | ${formatNum(report?.deltas?.precision_delta)} |`);
  lines.push(`| recall@k(avg) | ${formatNum(report?.baseline?.recall_at_k_avg)} | ${formatNum(report?.current?.recall_at_k_avg)} | ${formatNum(report?.deltas?.recall_delta)} |`);
  lines.push(`| p95 latency(ms) | ${formatNum(report?.baseline?.p95_latency_ms, 3)} | ${formatNum(report?.current?.p95_latency_ms, 3)} | ${formatNum(report?.deltas?.p95_latency_delta_ms, 3)} |`);
  lines.push(`| adversarial match rate | ${formatPct(report?.baseline?.adversarial_match_rate)} | ${formatPct(report?.current?.adversarial_match_rate)} | ${formatNum(report?.deltas?.adversarial_match_delta)} |`);
  lines.push("");

  lines.push("## Regression Checks");
  lines.push("| Check | Status | Detail |");
  lines.push("|---|---|---|");
  for (const item of report?.checks || []) {
    lines.push(`| ${item.key} | ${item.pass ? "pass" : "fail"} | ${item.detail} |`);
  }
  lines.push("");

  const alertSummary = report?.observability_alerts?.summary || {};
  lines.push("## Observability Alerts");
  lines.push(`- critical: ${Number(alertSummary.critical || 0)}`);
  lines.push(`- warn: ${Number(alertSummary.warn || 0)}`);
  lines.push(`- no_data: ${Number(alertSummary.no_data || 0)}`);
  const topStage = report?.observability_alerts?.top_stage || null;
  if (topStage) {
    lines.push(`- top_stage_anomaly: ${String(topStage.stage || "unknown")} (score=${Number(topStage.anomaly_score || 0)})`);
  }
  lines.push("");

  lines.push("## Trend Chart");
  lines.push(toMermaidTrend({
    labels: report?.trends?.labels || [],
    recall: report?.trends?.recall_at_k_avg || [],
    precision: report?.trends?.precision_at_k_avg || [],
    p95: report?.trends?.p95_latency_ratio_vs_baseline || [],
    adversarial: report?.trends?.adversarial_match_rate || [],
  }));
  lines.push("");

  lines.push("## Auto TODO");
  const todos = Array.isArray(report?.todos) ? report.todos : [];
  if (!todos.length) {
    lines.push("- none");
  } else {
    for (const t of todos) {
      lines.push(`- [${String(t.severity || "p2").toUpperCase()}] ${t.summary} (owner=${t.owner}, stage=${t.stage_hint || "n/a"}, source=${t.source})`);
      lines.push(`  - detail: ${t.detail}`);
      lines.push(`  - action: ${t.suggested_action}`);
    }
  }
  lines.push("");

  lines.push("## Gate Snapshot");
  lines.push(`- gate1_correctness: ${report?.current?.gate_hints?.gate1_correctness ? "pass" : "fail"}`);
  lines.push(`- gate2_performance: ${report?.current?.gate_hints?.gate2_performance ? "pass" : "fail"}`);
  lines.push(`- gate3_security: ${report?.current?.gate_hints?.gate3_security ? "pass" : "fail"}`);
  lines.push("");

  return `${lines.join("\n")}\n`;
}

function fail(msg, details = {}) {
  console.error(JSON.stringify({ ok: false, error: String(msg || "failed"), ...details }, null, 2));
  process.exit(2);
}

function main() {
  const args = parseArgs(process.argv);
  const repoRoot = path.resolve(__dirname, "..");
  const currentPath = path.resolve(
    args.current || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w1/report_baseline_week1.json")
  );
  const baselinePath = path.resolve(
    args.baseline || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w1/report_baseline_week1.json")
  );
  const thresholdsPath = path.resolve(
    args.thresholds || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w1/regression_thresholds.json")
  );
  const dashboardPath = path.resolve(
    args.dashboard || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w5-observability/dashboard_snapshot.json")
  );
  const historyPath = path.resolve(
    args.history || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w5-weekly/weekly_regression_history.jsonl")
  );
  const outJsonPath = path.resolve(
    args["out-json"] || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w5-weekly/weekly_regression_report.json")
  );
  const outMdPath = path.resolve(
    args["out-md"] || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w5-weekly/weekly_regression_report.md")
  );
  const appendHistory = boolArg(args["append-history"], true);
  const nowMs = Math.max(0, Number(args["now-ms"] || Date.now()));

  if (!fs.existsSync(currentPath)) fail("current_report_not_found", { current: currentPath });
  if (!fs.existsSync(baselinePath)) fail("baseline_report_not_found", { baseline: baselinePath });
  if (!fs.existsSync(thresholdsPath)) fail("thresholds_not_found", { thresholds: thresholdsPath });
  if (!fs.existsSync(dashboardPath)) fail("dashboard_not_found", { dashboard: dashboardPath });

  const current = readJson(currentPath);
  const baseline = readJson(baselinePath);
  const thresholdRaw = readJson(thresholdsPath);
  const dashboard = readJson(dashboardPath);
  const history = readJsonl(historyPath);

  const thresholds = mergeThresholds(
    {
      recall_drop_max: 0.02,
      precision_drop_max: 0.03,
      p95_latency_growth_max: 0.5,
      adversarial_match_drop_max: 0.01,
    },
    thresholdRaw
  );

  const sourcePaths = {
    current_report: path.relative(repoRoot, currentPath),
    baseline_report: path.relative(repoRoot, baselinePath),
    thresholds: path.relative(repoRoot, thresholdsPath),
    dashboard: path.relative(repoRoot, dashboardPath),
    history: path.relative(repoRoot, historyPath),
  };

  const report = buildWeeklyReport({
    nowMs,
    currentReport: current,
    baselineReport: baseline,
    regressionThresholds: thresholds,
    dashboard,
    historyEntries: history,
    sourcePaths,
  });

  writeJson(outJsonPath, report);
  writeText(outMdPath, toMarkdown(report));
  if (appendHistory) {
    appendJsonl(historyPath, report.history_entry);
  }

  const result = {
    ok: true,
    schema_version: report.schema_version,
    out_json: path.relative(repoRoot, outJsonPath),
    out_md: path.relative(repoRoot, outMdPath),
    history: path.relative(repoRoot, historyPath),
    history_appended: appendHistory,
    summary: report.summary,
    todo_count: Number(report?.todos?.length || 0),
  };
  console.log(JSON.stringify(result, null, 2));
}

if (require.main === module) {
  try {
    main();
  } catch (err) {
    fail(err?.message || err || "m2_weekly_report_failed");
  }
}

module.exports = {
  buildWeeklyReport,
  computeBenchDeltas,
  evaluateBenchChecks,
  normalizeAlerts,
  toMarkdown,
  toMermaidTrend,
};
