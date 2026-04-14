#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const DEFAULT_PATHS = {
  xt_report_index: "x-terminal/.axcoder/reports/xt-report-index.json",
  xt_gate_report: "x-terminal/.axcoder/reports/xt-gate-report.md",
  xt_overflow_report: "x-terminal/.axcoder/reports/xt-overflow-fairness-report.json",
  xt_origin_report: "x-terminal/.axcoder/reports/xt-origin-fallback-report.json",
  xt_cleanup_report: "x-terminal/.axcoder/reports/xt-dispatch-cleanup-report.json",
  doctor_report: "x-terminal/.axcoder/reports/doctor-report.json",
  secrets_dry_run_report: "x-terminal/.axcoder/reports/secrets-dry-run-report.json",
  xt_rollback_last_report: "x-terminal/.axcoder/reports/xt-rollback-last.json",
  xt_ready_gate_report: "build/xt_ready_gate_e2e_report.json",
  xt_ready_evidence_source: "build/xt_ready_evidence_source.json",
  connector_gate_snapshot: "build/connector_ingress_gate_snapshot.json",
  metrics_json: "build/internal_pass_metrics.json",
  sample_summary_json: "build/internal_pass_samples.json",
};
const PREFERRED_XT_READY_ARTIFACT_CANDIDATES = [
  {
    reportRef: "build/xt_ready_gate_e2e_require_real_report.json",
    sourceRefs: [
      "build/xt_ready_evidence_source.require_real.json",
      "build/xt_ready_evidence_source.json",
    ],
    connectorRefs: [
      "build/connector_ingress_gate_snapshot.require_real.json",
      "build/connector_ingress_gate_snapshot.json",
    ],
  },
  {
    reportRef: "build/xt_ready_gate_e2e_db_real_report.json",
    sourceRefs: [
      "build/xt_ready_evidence_source.db_real.json",
      "build/xt_ready_evidence_source.require_real.json",
      "build/xt_ready_evidence_source.json",
    ],
    connectorRefs: [
      "build/connector_ingress_gate_snapshot.db_real.json",
      "build/connector_ingress_gate_snapshot.require_real.json",
      "build/connector_ingress_gate_snapshot.json",
    ],
  },
  {
    reportRef: "build/xt_ready_gate_e2e_report.json",
    sourceRefs: [
      "build/xt_ready_evidence_source.json",
    ],
    connectorRefs: [
      "build/connector_ingress_gate_snapshot.json",
    ],
  },
];

const REQUIRED_COVERAGE_IDS = [
  "XT-W3-08",
  "CRK-W1-08",
  "CM-W5-20",
  "XT-W2-17",
  "XT-W2-18",
  "XT-W2-19",
];

const REQUIRED_EVIDENCE_KEYS = [
  "xt_gate_report",
  "xt_report_index",
  "xt_overflow_report",
  "xt_origin_report",
  "xt_cleanup_report",
  "doctor_report",
  "secrets_dry_run_report",
  "xt_rollback_last_report",
  "xt_ready_gate_report",
  "xt_ready_evidence_source",
  "connector_gate_snapshot",
];

const SAMPLE_THRESHOLDS = {
  lane_event_count: 1000,
  high_risk_request_count: 300,
  mergeback_runs: 100,
};

const HARD_LINE_RULES = [
  // HL-01 Gate complete
  { hl: "HL-01", keys: ["gate_m3_0_status"], op: "eq", expected: "PASS" },
  { hl: "HL-01", keys: ["gate_m3_1_status"], op: "eq", expected: "PASS" },
  { hl: "HL-01", keys: ["gate_m3_2_status"], op: "eq", expected: "PASS" },
  { hl: "HL-01", keys: ["gate_m3_3_status"], op: "eq", expected: "PASS" },
  { hl: "HL-01", keys: ["gate_m3_4_status"], op: "eq", expected: "PASS" },
  { hl: "HL-01", keys: ["xt_ready_g0_status"], op: "eq", expected: "PASS" },
  { hl: "HL-01", keys: ["xt_ready_g1_status"], op: "eq", expected: "PASS" },
  { hl: "HL-01", keys: ["xt_ready_g2_status"], op: "eq", expected: "PASS" },
  { hl: "HL-01", keys: ["xt_ready_g3_status"], op: "eq", expected: "PASS" },
  { hl: "HL-01", keys: ["xt_ready_g4_status"], op: "eq", expected: "PASS" },
  { hl: "HL-01", keys: ["xt_ready_g5_status"], op: "eq", expected: "PASS" },
  { hl: "HL-01", keys: ["xt_g0_status"], op: "eq", expected: "PASS" },
  { hl: "HL-01", keys: ["xt_g1_status"], op: "eq", expected: "PASS" },
  { hl: "HL-01", keys: ["xt_g2_status"], op: "eq", expected: "PASS" },
  { hl: "HL-01", keys: ["xt_g3_status"], op: "eq", expected: "PASS" },
  { hl: "HL-01", keys: ["xt_g4_status"], op: "eq", expected: "PASS" },
  { hl: "HL-01", keys: ["xt_g5_status"], op: "eq", expected: "PASS" },

  // HL-03 Efficiency
  { hl: "HL-03", keys: ["queue_wait_p90_ms"], op: "lte", expected: 3200 },
  { hl: "HL-03", keys: ["split_to_parallel_start_p95_ms"], op: "lte", expected: 8000 },
  { hl: "HL-03", keys: ["proposal_ready_p95_ms"], op: "lte", expected: 4000 },
  { hl: "HL-03", keys: ["lane_stall_detect_p95_ms"], op: "lte", expected: 2000 },
  { hl: "HL-03", keys: ["supervisor_action_latency_p95_ms"], op: "lte", expected: 1500 },
  { hl: "HL-03", keys: ["child_project_assignment_success_rate"], op: "gte", expected: 98 },
  { hl: "HL-03", keys: ["mergeback_first_pass_rate"], op: "gte", expected: 70 },
  { hl: "HL-03", keys: ["mean_time_to_root_cause"], op: "lte", expected: 30 },

  // HL-04 Security (grant chain)
  { hl: "HL-04", keys: ["high_risk_lane_without_grant"], op: "eq", expected: 0 },
  { hl: "HL-04", keys: ["bypass_grant_execution"], op: "eq", expected: 0 },
  { hl: "HL-04", keys: ["high_risk_bypass_count"], op: "eq", expected: 0 },
  { hl: "HL-04", keys: ["unaudited_auto_resolution"], op: "eq", expected: 0 },
  { hl: "HL-04", keys: ["unsigned_high_risk_skill_exec"], op: "eq", expected: 0 },
  { hl: "HL-04", keys: ["credential_finding_block_rate"], op: "eq", expected: 100 },

  // HL-05 Security (ingress + preauth)
  { hl: "HL-05", keys: ["non_message_ingress_policy_coverage"], op: "eq", expected: 100 },
  { hl: "HL-05", keys: ["blocked_event_miss_rate"], op: "lt", expected: 1 },
  { hl: "HL-05", keys: ["preauth_memory_growth_unbounded"], op: "eq", expected: 0 },
  { hl: "HL-05", keys: ["webhook_replay_accept_count"], op: "eq", expected: 0 },
  { hl: "HL-05", keys: ["cross_channel_fallback_blocked"], op: "eq", expected: 100 },

  // HL-06 Token / cost
  { hl: "HL-06", keys: ["token_per_task_delta"], op: "lte", expected: -20 },
  { hl: "HL-06", keys: ["token_budget_overrun_rate"], op: "lte", expected: 3 },
  { hl: "HL-06", keys: ["cross_session_dedup_hit_rate"], op: "gte", expected: 60 },
  { hl: "HL-06", keys: ["cross_lane_context_dedup_hit_rate"], op: "gte", expected: 60 },
  { hl: "HL-06", keys: ["parent_fork_overflow_silent_fail"], op: "eq", expected: 0 },
  { hl: "HL-06", keys: ["parent_fork_overflow_detect_p95_ms"], op: "lte", expected: 1000 },

  // HL-07 Reliability
  { hl: "HL-07", keys: ["enqueue_during_drain_silent_drop"], op: "eq", expected: 0 },
  { hl: "HL-07", keys: ["retry_starvation_incidents"], op: "eq", expected: 0 },
  { hl: "HL-07", keys: ["restart_recovery_success_rate"], op: "gte", expected: 99 },
  { hl: "HL-07", keys: ["dispatch_idle_stuck_incidents"], op: "eq", expected: 0 },
  { hl: "HL-07", keys: ["route_origin_fallback_violations"], op: "eq", expected: 0 },

  // HL-08 Lineage
  { hl: "HL-08", keys: ["lineage_visibility_coverage"], op: "eq", expected: 100 },
  { hl: "HL-08", keys: ["hard_split_without_child_project"], op: "eq", expected: 0 },
  { hl: "HL-08", keys: ["soft_split_lineage_pollution"], op: "eq", expected: 0 },
  { hl: "HL-08", keys: ["lineage_cycle_incidents"], op: "eq", expected: 0 },

  // HL-09 Rollback
  { hl: "HL-09", keys: ["mergeback_rollback_success_rate"], op: "gte", expected: 99 },

  // HL-10 Contract stability
  { hl: "HL-10", keys: ["contract_test_drift_incidents"], op: "eq", expected: 0 },
  { hl: "HL-10", keys: ["missing_deny_code_coverage"], op: "eq", expected: 0 },
];

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

function resolvePaths(args = {}) {
  const explicitXtReadyGate = args["xt-ready-gate-report"];
  const explicitXtReadySource = args["xt-ready-evidence-source"];
  const explicitConnectorGate = args["connector-gate-snapshot"];
  const preferredXtReadyPaths =
    explicitXtReadyGate || explicitXtReadySource || explicitConnectorGate
      ? {
          reportPath: path.resolve(explicitXtReadyGate || DEFAULT_PATHS.xt_ready_gate_report),
          sourcePath: path.resolve(explicitXtReadySource || DEFAULT_PATHS.xt_ready_evidence_source),
          connectorPath: explicitConnectorGate
            ? path.resolve(explicitConnectorGate)
            : resolveConnectorPathForXtReadyOverride({
                explicitXtReadyGate,
                explicitXtReadySource,
              }),
        }
      : resolvePreferredXtReadyPaths();
  return {
    xt_report_index: path.resolve(args["xt-report-index"] || DEFAULT_PATHS.xt_report_index),
    xt_gate_report: path.resolve(args["xt-gate-report"] || DEFAULT_PATHS.xt_gate_report),
    xt_overflow_report: path.resolve(args["xt-overflow-report"] || DEFAULT_PATHS.xt_overflow_report),
    xt_origin_report: path.resolve(args["xt-origin-report"] || DEFAULT_PATHS.xt_origin_report),
    xt_cleanup_report: path.resolve(args["xt-cleanup-report"] || DEFAULT_PATHS.xt_cleanup_report),
    doctor_report: path.resolve(args["doctor-report"] || DEFAULT_PATHS.doctor_report),
    secrets_dry_run_report: path.resolve(args["secrets-dry-run-report"] || DEFAULT_PATHS.secrets_dry_run_report),
    xt_rollback_last_report: path.resolve(args["xt-rollback-last-report"] || DEFAULT_PATHS.xt_rollback_last_report),
    xt_ready_gate_report: preferredXtReadyPaths.reportPath,
    xt_ready_evidence_source: preferredXtReadyPaths.sourcePath,
    connector_gate_snapshot:
      explicitXtReadyGate || explicitXtReadySource
        ? preferredXtReadyPaths.connectorPath
        : explicitConnectorGate
          ? path.resolve(explicitConnectorGate)
          : preferredXtReadyPaths.connectorPath,
    metrics_json: path.resolve(args["metrics-json"] || DEFAULT_PATHS.metrics_json),
    sample_summary_json: path.resolve(args["sample-summary-json"] || DEFAULT_PATHS.sample_summary_json),
  };
}

function toComparablePath(filePath = "") {
  const resolved = path.resolve(String(filePath || ""));
  try {
    return fs.realpathSync(resolved);
  } catch {
    return resolved;
  }
}

function resolveConnectorPathForXtReadyOverride({
  explicitXtReadyGate = "",
  explicitXtReadySource = "",
  baseDir = process.cwd(),
} = {}) {
  const resolvedGate = explicitXtReadyGate ? toComparablePath(explicitXtReadyGate) : "";
  const resolvedSource = explicitXtReadySource ? toComparablePath(explicitXtReadySource) : "";
  for (const candidate of PREFERRED_XT_READY_ARTIFACT_CANDIDATES) {
    const reportPath = toComparablePath(path.resolve(baseDir, candidate.reportRef));
    const sourcePaths = candidate.sourceRefs.map((ref) =>
      toComparablePath(path.resolve(baseDir, ref))
    );
    if (
      (resolvedGate && resolvedGate === reportPath) ||
      (resolvedSource && sourcePaths.includes(resolvedSource))
    ) {
      return (
        candidate.connectorRefs
          .map((ref) => path.resolve(baseDir, ref))
          .find((ref) => fs.existsSync(ref)) ||
        path.resolve(baseDir, candidate.connectorRefs[0])
      );
    }
  }
  return path.resolve(baseDir, DEFAULT_PATHS.connector_gate_snapshot);
}

function resolvePreferredXtReadyPaths(baseDir = process.cwd()) {
  for (const candidate of PREFERRED_XT_READY_ARTIFACT_CANDIDATES) {
    const reportPath = path.resolve(baseDir, candidate.reportRef);
    if (!fs.existsSync(reportPath)) continue;
    const sourcePath =
      candidate.sourceRefs
        .map((ref) => path.resolve(baseDir, ref))
        .find((ref) => fs.existsSync(ref)) ||
      path.resolve(baseDir, candidate.sourceRefs[0]);
    const connectorPath =
      candidate.connectorRefs
        .map((ref) => path.resolve(baseDir, ref))
        .find((ref) => fs.existsSync(ref)) ||
      path.resolve(baseDir, candidate.connectorRefs[0]);
    return {
      reportPath,
      sourcePath,
      connectorPath,
    };
  }

  return {
    reportPath: path.resolve(baseDir, DEFAULT_PATHS.xt_ready_gate_report),
    sourcePath: path.resolve(baseDir, DEFAULT_PATHS.xt_ready_evidence_source),
    connectorPath: path.resolve(baseDir, DEFAULT_PATHS.connector_gate_snapshot),
  };
}

function readText(filePath) {
  return String(fs.readFileSync(filePath, "utf8") || "");
}

function readJson(filePath) {
  return JSON.parse(readText(filePath));
}

function writeText(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, String(content || ""), "utf8");
}

function safeLoadJson(filePath) {
  if (!filePath || !fs.existsSync(filePath)) {
    return { ok: false, value: null, error: `missing file: ${filePath}` };
  }
  try {
    return { ok: true, value: readJson(filePath), error: null };
  } catch (err) {
    return { ok: false, value: null, error: `invalid json: ${filePath} (${err.message})` };
  }
}

function safeLoadText(filePath) {
  if (!filePath || !fs.existsSync(filePath)) {
    return { ok: false, value: "", error: `missing file: ${filePath}` };
  }
  try {
    return { ok: true, value: readText(filePath), error: null };
  } catch (err) {
    return { ok: false, value: "", error: `read failed: ${filePath} (${err.message})` };
  }
}

function normalizeMetricKey(raw) {
  return String(raw || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function collectMetricBag(input, bag = {}) {
  if (Array.isArray(input)) {
    input.forEach((item, idx) => {
      collectMetricBag(item, bag);
      bag[normalizeMetricKey(`array_${idx}`)] = item;
    });
    return bag;
  }
  if (input && typeof input === "object") {
    for (const [k, v] of Object.entries(input)) {
      const nk = normalizeMetricKey(k);
      if (v && typeof v === "object") {
        collectMetricBag(v, bag);
      } else {
        bag[nk] = v;
      }
    }
  }
  return bag;
}

function getMetric(metricBag, keys = []) {
  for (const key of keys) {
    const norm = normalizeMetricKey(key);
    if (Object.prototype.hasOwnProperty.call(metricBag, norm)) {
      return metricBag[norm];
    }
  }
  return undefined;
}

function toNumber(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return n;
}

function compareMetric(value, op, expected) {
  if (op === "eq") {
    if (typeof expected === "string") {
      return String(value || "").trim().toUpperCase() === String(expected || "").trim().toUpperCase();
    }
    const n = toNumber(value);
    return n !== null && n === Number(expected);
  }
  const n = toNumber(value);
  const target = Number(expected);
  if (n === null || !Number.isFinite(target)) return false;
  if (op === "lt") return n < target;
  if (op === "lte") return n <= target;
  if (op === "gt") return n > target;
  if (op === "gte") return n >= target;
  return false;
}

function extractDecisionFromXtGateReport(markdown = "") {
  const m = String(markdown || "").match(/- decision:\s*([A-Z_]+)/);
  return m ? String(m[1] || "").trim() : "";
}

function evaluateSampleSufficiency(metricBag = {}) {
  const summary = {};
  const errors = [];
  for (const [metricKey, threshold] of Object.entries(SAMPLE_THRESHOLDS)) {
    const raw = getMetric(metricBag, [metricKey]);
    const n = toNumber(raw);
    summary[metricKey] = n;
    if (n === null) {
      errors.push(`${metricKey} is missing`);
      continue;
    }
    if (n < threshold) {
      errors.push(`${metricKey} ${n} < ${threshold}`);
    }
  }
  return {
    ok: errors.length === 0,
    errors,
    summary,
  };
}

function evaluateHardLines(metricBag = {}) {
  const byHl = {};
  for (const rule of HARD_LINE_RULES) {
    if (!byHl[rule.hl]) byHl[rule.hl] = [];
    const value = getMetric(metricBag, rule.keys);
    const ok = value !== undefined && compareMetric(value, rule.op, rule.expected);
    byHl[rule.hl].push({
      keys: rule.keys,
      op: rule.op,
      expected: rule.expected,
      value,
      ok,
      message: ok
        ? ""
        : value === undefined
          ? `missing metric: ${rule.keys.join("|")}`
          : `metric check failed: ${rule.keys[0]} ${rule.op} ${rule.expected}, got ${value}`,
    });
  }

  const lineResults = {};
  for (const [hl, checks] of Object.entries(byHl)) {
    const failed = checks.filter((x) => !x.ok).map((x) => x.message);
    lineResults[hl] = {
      ok: failed.length === 0,
      failed,
      checks,
    };
  }
  return lineResults;
}

function checkInternalPassLines({
  paths = {},
  windowLabel = "",
  requireRealAudit = true,
} = {}) {
  const missingEvidence = [];
  for (const key of REQUIRED_EVIDENCE_KEYS) {
    const p = String(paths[key] || "").trim();
    if (!p || !fs.existsSync(p)) {
      missingEvidence.push(p || `(missing path for ${key})`);
    }
  }

  const xtIndex = safeLoadJson(paths.xt_report_index);
  const xtGateMd = safeLoadText(paths.xt_gate_report);
  const xtReadyGate = safeLoadJson(paths.xt_ready_gate_report);
  const evidenceSource = safeLoadJson(paths.xt_ready_evidence_source);
  const connectorSnapshot = safeLoadJson(paths.connector_gate_snapshot);
  const rollbackReport = safeLoadJson(paths.xt_rollback_last_report);
  const metricsDoc = safeLoadJson(paths.metrics_json);
  const sampleDoc = safeLoadJson(paths.sample_summary_json);

  const loaderErrors = [];
  [xtIndex, xtGateMd, xtReadyGate, evidenceSource, connectorSnapshot, rollbackReport, metricsDoc, sampleDoc]
    .forEach((x) => {
      if (!x.ok && x.error) loaderErrors.push(x.error);
    });

  const metricBag = {};
  if (metricsDoc.ok) collectMetricBag(metricsDoc.value, metricBag);
  if (sampleDoc.ok) collectMetricBag(sampleDoc.value, metricBag);

  const hardLines = evaluateHardLines(metricBag);
  const failedHardLines = Object.entries(hardLines)
    .filter(([, result]) => !result.ok)
    .map(([hl]) => hl);

  const releaseChecks = {
    xt_report_index_schema_ok:
      xtIndex.ok && String(xtIndex.value.schema_version || "") === "xt_report_index.v1",
    xt_report_index_decision_go:
      xtIndex.ok && String(xtIndex.value.release_decision || "").trim().toUpperCase() === "GO",
    xt_gate_report_decision_go:
      xtGateMd.ok && extractDecisionFromXtGateReport(xtGateMd.value) === "GO",
    xt_ready_gate_report_ok:
      xtReadyGate.ok && xtReadyGate.value && xtReadyGate.value.ok === true,
    xt_ready_gate_require_real_audit:
      xtReadyGate.ok && Boolean(xtReadyGate.value?.require_real_audit_source) === true,
    xt_ready_source_not_sample:
      evidenceSource.ok && String(evidenceSource.value?.selected_source || "") !== "sample_fixture",
    connector_snapshot_audit_source:
      connectorSnapshot.ok && String(connectorSnapshot.value?.source_used || "").toLowerCase() === "audit",
    rollback_status_ok:
      rollbackReport.ok &&
      String(rollbackReport.value?.status || "").toLowerCase() === "pass" &&
      Number(rollbackReport.value?.copied_previous_to_current) === 1,
  };

  const coverageChecks = {};
  for (const id of REQUIRED_COVERAGE_IDS) {
    coverageChecks[id] =
      xtIndex.ok &&
      String(xtIndex.value?.coverage?.[id] || "").trim().toUpperCase() === "PASS";
  }

  const releaseCheckFailures = [];
  for (const [name, ok] of Object.entries(releaseChecks)) {
    if (!ok) releaseCheckFailures.push(name);
  }
  const coverageFailures = Object.entries(coverageChecks)
    .filter(([, ok]) => !ok)
    .map(([id]) => id);

  // HL-01 and HL-02 include structured release/evidence checks.
  if (releaseCheckFailures.length > 0 || coverageFailures.length > 0) {
    if (!failedHardLines.includes("HL-01")) failedHardLines.push("HL-01");
  }
  if (requireRealAudit) {
    const requireRealFailed = [
      !releaseChecks.xt_ready_source_not_sample,
      !releaseChecks.connector_snapshot_audit_source,
      !releaseChecks.xt_ready_gate_require_real_audit,
    ].some(Boolean);
    if (requireRealFailed && !failedHardLines.includes("HL-02")) {
      failedHardLines.push("HL-02");
    }
  }
  if (!releaseChecks.rollback_status_ok && !failedHardLines.includes("HL-09")) {
    failedHardLines.push("HL-09");
  }

  const sampleSufficiency = evaluateSampleSufficiency(metricBag);
  let releaseDecision = "GO";
  if (!sampleSufficiency.ok) {
    releaseDecision = "INSUFFICIENT_EVIDENCE";
  } else if (missingEvidence.length > 0 || loaderErrors.length > 0 || failedHardLines.length > 0) {
    releaseDecision = "NO-GO";
  }

  const report = {
    schema_version: "xhub_internal_pass_lines_report.v1",
    generated_at: new Date().toISOString(),
    release_decision: releaseDecision,
    window: windowLabel || "",
    failed_hard_lines: Array.from(new Set(failedHardLines)).sort(),
    missing_evidence: missingEvidence,
    sample_summary: sampleSufficiency.summary,
    checks: {
      sample_sufficiency: sampleSufficiency,
      release_checks: releaseChecks,
      coverage_checks: coverageChecks,
      hard_lines: hardLines,
    },
    loader_errors: loaderErrors,
    notes: [
      "Pass-lines source: docs/memory-new/xhub-internal-pass-lines-v1.md",
      `require_real_audit=${requireRealAudit ? "1" : "0"}`,
    ],
  };

  return report;
}

function runCli(argv = process.argv) {
  const args = parseArgs(argv);
  const paths = resolvePaths(args);
  const requireRealAudit = String(args["require-real-audit"] || "1") !== "0";
  const report = checkInternalPassLines({
    paths,
    requireRealAudit,
    windowLabel: String(args.window || "").trim(),
  });
  const outJson = String(args["out-json"] || "build/internal_pass_lines_report.json").trim();
  if (outJson) {
    writeText(path.resolve(outJson), `${JSON.stringify(report, null, 2)}\n`);
  }

  if (report.release_decision === "GO") {
    console.log(`ok - internal pass-lines gate is GO (${report.window || "window=unspecified"})`);
    return report;
  }

  const failed = report.failed_hard_lines.join(", ") || "none";
  const missing = report.missing_evidence.length;
  const sampleErrors = report.checks?.sample_sufficiency?.errors || [];
  const reason = report.release_decision === "INSUFFICIENT_EVIDENCE"
    ? `insufficient sample: ${sampleErrors.join(" | ")}`
    : `failed_hard_lines=${failed}; missing_evidence=${missing}; loader_errors=${report.loader_errors.length}`;
  throw new Error(`internal pass-lines gate ${report.release_decision}: ${reason}`);
}

if (require.main === module) {
  try {
    runCli(process.argv);
  } catch (err) {
    console.error(`error: ${err.message}`);
    process.exit(1);
  }
}

module.exports = {
  DEFAULT_PATHS,
  HARD_LINE_RULES,
  PREFERRED_XT_READY_ARTIFACT_CANDIDATES,
  REQUIRED_COVERAGE_IDS,
  REQUIRED_EVIDENCE_KEYS,
  SAMPLE_THRESHOLDS,
  checkInternalPassLines,
  collectMetricBag,
  compareMetric,
  evaluateHardLines,
  evaluateSampleSufficiency,
  extractDecisionFromXtGateReport,
  parseArgs,
  resolvePreferredXtReadyPaths,
  resolvePaths,
  runCli,
};
