#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");
const { DatabaseSync } = require("node:sqlite");

const DEFAULTS = {
  xt_gate_report: "x-terminal/.axcoder/reports/xt-gate-report.md",
  xt_kpi_json: "x-terminal/.axcoder/metrics/xt-kpi-latest.json",
  xt_overflow_report: "x-terminal/.axcoder/reports/xt-overflow-fairness-report.json",
  xt_origin_report: "x-terminal/.axcoder/reports/xt-origin-fallback-report.json",
  xt_cleanup_report: "x-terminal/.axcoder/reports/xt-dispatch-cleanup-report.json",
  doctor_report: "x-terminal/.axcoder/reports/doctor-report.json",
  connector_gate_primary: "build/connector_ingress_gate_snapshot.require_real.json",
  connector_gate_secondary: "build/connector_ingress_gate_snapshot.db_real.json",
  connector_gate_fallback: "build/connector_ingress_gate_snapshot.json",
  xt_ready_incidents_primary: "build/hub_l5_release_xt_ready_incident_events.require_real.json",
  xt_ready_incidents_fallback: "build/xt_ready_incident_events.effective.json",
  xt_ready_gate_primary: "build/hub_l5_release_xt_ready_gate_e2e_require_real_report.json",
  xt_ready_gate_secondary: "build/xt_ready_gate_e2e_require_real_report.json",
  xt_ready_gate_tertiary: "build/xt_ready_gate_e2e_db_real_report.json",
  xt_ready_gate_fallback: "build/xt_ready_gate_e2e_report.json",
  sample_db_path: "x-hub/grpc-server/hub_grpc_server/data/hub.sqlite3",
  out_metrics_json: "build/internal_pass_metrics.json",
  out_samples_json: "build/internal_pass_samples.json",
  out_prep_json: "build/internal_pass_inputs_prep.json",
};

function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i += 1) {
    const token = String(argv[i] || "");
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (next && !String(next).startsWith("--")) {
      out[key] = String(next);
      i += 1;
    } else {
      out[key] = "1";
    }
  }
  return out;
}

function writeText(filePath, text) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, String(text || ""), "utf8");
}

function readJsonSafe(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return { ok: false, value: null, error: "missing" };
  try {
    return { ok: true, value: JSON.parse(fs.readFileSync(filePath, "utf8")), error: null };
  } catch (err) {
    return { ok: false, value: null, error: String(err.message || err) };
  }
}

function readTextSafe(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return { ok: false, value: "", error: "missing" };
  try {
    return { ok: true, value: String(fs.readFileSync(filePath, "utf8") || ""), error: null };
  } catch (err) {
    return { ok: false, value: "", error: String(err.message || err) };
  }
}

function pickExistingPath(...candidates) {
  const resolvedCandidates = candidates.map((candidate) => path.resolve(candidate));
  for (const candidate of resolvedCandidates) {
    if (fs.existsSync(candidate)) return candidate;
  }
  return resolvedCandidates[0];
}

function toFiniteNumber(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return n;
}

function extractXtGateStatuses(markdown) {
  const statuses = {};
  for (let i = 0; i <= 5; i += 1) {
    const gate = `XT-G${i}`;
    const passRe = new RegExp(`PASS:\\s*${gate}\\b`, "i");
    const failRe = new RegExp(`FAIL:\\s*${gate}\\b`, "i");
    if (passRe.test(markdown)) {
      statuses[`xt_g${i}_status`] = "PASS";
    } else if (failRe.test(markdown)) {
      statuses[`xt_g${i}_status`] = "FAIL";
    }
  }
  return statuses;
}

function extractSampleSummaryFromDb(dbPath) {
  const resolved = path.resolve(dbPath);
  if (!fs.existsSync(resolved)) {
    return {
      lane_event_count: null,
      high_risk_request_count: null,
      mergeback_runs: null,
      source_db_path: resolved,
      error: "db_missing",
    };
  }

  const db = new DatabaseSync(resolved);
  try {
    const hasAudit = db
      .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='audit_events'")
      .get();
    if (!hasAudit) {
      return {
        lane_event_count: null,
        high_risk_request_count: null,
        mergeback_runs: null,
        source_db_path: resolved,
        error: "missing_audit_events_table",
      };
    }
    const laneEventCount = Number(db.prepare("SELECT COUNT(*) AS c FROM audit_events").get()?.c || 0);
    const highRiskRequestCount = Number(
      db
        .prepare(
          `
            SELECT COUNT(*) AS c
            FROM audit_events
            WHERE event_type = 'policy_eval'
               OR event_type LIKE 'grant.request.%'
               OR event_type = 'supervisor.incident.grant_pending.handled'
          `
        )
        .get()?.c || 0
    );
    const mergebackRuns = Number(
      db
        .prepare(
          `
            SELECT COUNT(*) AS c
            FROM audit_events
            WHERE LOWER(event_type) LIKE '%mergeback%'
               OR LOWER(event_type) LIKE '%merge_back%'
          `
        )
        .get()?.c || 0
    );
    return {
      lane_event_count: laneEventCount,
      high_risk_request_count: highRiskRequestCount,
      mergeback_runs: mergebackRuns,
      source_db_path: resolved,
      error: null,
    };
  } finally {
    try {
      db.close();
    } catch {
      // ignore close failures
    }
  }
}

function maybeSetMetric(target, key, value) {
  if (value === null || value === undefined) return;
  target[key] = value;
}

function recordSource(metricSources, metric, sourcePath) {
  if (!metric || !sourcePath) return;
  metricSources.push({
    metric,
    source: sourcePath,
  });
}

function run(argv = process.argv) {
  const args = parseArgs(argv);
  const xtGateReportPath = path.resolve(args["xt-gate-report"] || DEFAULTS.xt_gate_report);
  const xtKpiPath = path.resolve(args["xt-kpi-json"] || DEFAULTS.xt_kpi_json);
  const overflowPath = path.resolve(args["xt-overflow-report"] || DEFAULTS.xt_overflow_report);
  const originPath = path.resolve(args["xt-origin-report"] || DEFAULTS.xt_origin_report);
  const cleanupPath = path.resolve(args["xt-cleanup-report"] || DEFAULTS.xt_cleanup_report);
  const doctorPath = path.resolve(args["doctor-report"] || DEFAULTS.doctor_report);
  const connectorPath = pickExistingPath(
    args["connector-gate-json"] || DEFAULTS.connector_gate_primary,
    DEFAULTS.connector_gate_secondary,
    DEFAULTS.connector_gate_fallback
  );
  const xtReadyIncidentsPath = pickExistingPath(
    args["xt-ready-incidents-json"] || DEFAULTS.xt_ready_incidents_primary,
    DEFAULTS.xt_ready_incidents_fallback
  );
  const xtReadyGatePath = pickExistingPath(
    args["xt-ready-gate-report"] || DEFAULTS.xt_ready_gate_primary,
    DEFAULTS.xt_ready_gate_secondary,
    DEFAULTS.xt_ready_gate_tertiary,
    DEFAULTS.xt_ready_gate_fallback
  );
  const sampleDbPath = path.resolve(args["sample-db-path"] || DEFAULTS.sample_db_path);

  const outMetrics = path.resolve(args["out-metrics-json"] || DEFAULTS.out_metrics_json);
  const outSamples = path.resolve(args["out-samples-json"] || DEFAULTS.out_samples_json);
  const outPrep = path.resolve(args["out-prep-json"] || DEFAULTS.out_prep_json);

  const gateMd = readTextSafe(xtGateReportPath);
  const kpi = readJsonSafe(xtKpiPath);
  const overflow = readJsonSafe(overflowPath);
  const origin = readJsonSafe(originPath);
  const cleanup = readJsonSafe(cleanupPath);
  const doctor = readJsonSafe(doctorPath);
  const connector = readJsonSafe(connectorPath);
  const xtReadyIncidents = readJsonSafe(xtReadyIncidentsPath);
  const xtReadyGate = readJsonSafe(xtReadyGatePath);

  const metrics = {
    schema_version: "xhub_internal_pass_metrics.v1",
    generated_at: new Date().toISOString(),
    require_real: true,
    forbid_synthetic: true,
  };

  const metricSources = [];
  if (gateMd.ok) {
    const gateStatuses = extractXtGateStatuses(gateMd.value);
    for (const [k, v] of Object.entries(gateStatuses)) {
      metrics[k] = v;
      recordSource(metricSources, k, xtGateReportPath);
    }
  }

  if (xtReadyGate.ok && xtReadyGate.value && xtReadyGate.value.ok === true) {
    // Inference: strict XT-Ready gate "ok=true" implies G0..G5 all pass in this gate run.
    for (let i = 0; i <= 5; i += 1) {
      const key = `xt_ready_g${i}_status`;
      metrics[key] = "PASS";
      recordSource(metricSources, key, xtReadyGatePath);
    }
  }

  if (kpi.ok && kpi.value) {
    maybeSetMetric(metrics, "queue_wait_p90_ms", toFiniteNumber(kpi.value.queue_wait_p90_ms));
    maybeSetMetric(
      metrics,
      "token_budget_overrun_rate",
      toFiniteNumber(kpi.value.token_budget_overrun_rate)
    );
    if (metrics.queue_wait_p90_ms !== undefined) recordSource(metricSources, "queue_wait_p90_ms", xtKpiPath);
    if (metrics.token_budget_overrun_rate !== undefined) {
      recordSource(metricSources, "token_budget_overrun_rate", xtKpiPath);
    }
  }

  if (overflow.ok && overflow.value) {
    const v = toFiniteNumber(overflow.value?.kpi_snapshot?.parent_fork_overflow_silent_fail);
    maybeSetMetric(metrics, "parent_fork_overflow_silent_fail", v);
    if (v !== null) recordSource(metricSources, "parent_fork_overflow_silent_fail", overflowPath);
  }
  if (origin.ok && origin.value) {
    const v = toFiniteNumber(origin.value?.kpi_snapshot?.route_origin_fallback_violations);
    maybeSetMetric(metrics, "route_origin_fallback_violations", v);
    if (v !== null) recordSource(metricSources, "route_origin_fallback_violations", originPath);
  }
  if (cleanup.ok && cleanup.value) {
    const v = toFiniteNumber(cleanup.value?.kpi_snapshot?.dispatch_idle_stuck_incidents);
    maybeSetMetric(metrics, "dispatch_idle_stuck_incidents", v);
    if (v !== null) recordSource(metricSources, "dispatch_idle_stuck_incidents", cleanupPath);
  }

  if (doctor.ok && doctor.value) {
    const rawCoverage = toFiniteNumber(doctor.value?.doctor?.non_message_ingress_policy_coverage);
    if (rawCoverage !== null) {
      const normalized = rawCoverage <= 1 ? rawCoverage * 100 : rawCoverage;
      maybeSetMetric(metrics, "non_message_ingress_policy_coverage", normalized);
      recordSource(metricSources, "non_message_ingress_policy_coverage", doctorPath);
    }
  }

  if (connector.ok && connector.value) {
    maybeSetMetric(
      metrics,
      "blocked_event_miss_rate",
      toFiniteNumber(connector.value?.blocked_event_miss_rate)
    );
    if (metrics.blocked_event_miss_rate !== undefined) {
      recordSource(metricSources, "blocked_event_miss_rate", connectorPath);
    }
  }

  if (xtReadyIncidents.ok && xtReadyIncidents.value) {
    const summary = xtReadyIncidents.value.summary || {};
    for (const key of [
      "high_risk_lane_without_grant",
      "high_risk_bypass_count",
      "unaudited_auto_resolution",
    ]) {
      const v = toFiniteNumber(summary[key]);
      maybeSetMetric(metrics, key, v);
      if (v !== null) recordSource(metricSources, key, xtReadyIncidentsPath);
    }
  }

  metrics.metric_sources = metricSources;

  const sampleSummary = extractSampleSummaryFromDb(sampleDbPath);
  const sampleDoc = {
    schema_version: "xhub_internal_pass_samples.v1",
    generated_at: new Date().toISOString(),
    require_real: true,
    forbid_synthetic: true,
    lane_event_count: sampleSummary.lane_event_count,
    high_risk_request_count: sampleSummary.high_risk_request_count,
    mergeback_runs: sampleSummary.mergeback_runs,
    source_db_path: sampleSummary.source_db_path,
    source_refs: [sampleSummary.source_db_path],
    extraction_error: sampleSummary.error,
  };

  const prep = {
    schema_version: "xhub_internal_pass_inputs_prep.v1",
    generated_at: new Date().toISOString(),
    require_real: true,
    forbid_synthetic: true,
    status: "prepared",
    outputs: {
      metrics_json: outMetrics,
      samples_json: outSamples,
    },
    inputs: {
      xt_gate_report: xtGateReportPath,
      xt_kpi_json: xtKpiPath,
      xt_overflow_report: overflowPath,
      xt_origin_report: originPath,
      xt_cleanup_report: cleanupPath,
      doctor_report: doctorPath,
      connector_gate_json: connectorPath,
      xt_ready_incidents_json: xtReadyIncidentsPath,
      xt_ready_gate_report: xtReadyGatePath,
      sample_db_path: sampleDbPath,
    },
    load_status: {
      xt_gate_report: gateMd.ok,
      xt_kpi_json: kpi.ok,
      xt_overflow_report: overflow.ok,
      xt_origin_report: origin.ok,
      xt_cleanup_report: cleanup.ok,
      doctor_report: doctor.ok,
      connector_gate_json: connector.ok,
      xt_ready_incidents_json: xtReadyIncidents.ok,
      xt_ready_gate_report: xtReadyGate.ok,
    },
    notes: [
      "This preparer only materializes existing machine-readable evidence into internal pass-lines input files.",
      "Unknown metrics are intentionally left absent to keep fail-closed semantics.",
    ],
  };

  writeText(outMetrics, `${JSON.stringify(metrics, null, 2)}\n`);
  writeText(outSamples, `${JSON.stringify(sampleDoc, null, 2)}\n`);
  writeText(outPrep, `${JSON.stringify(prep, null, 2)}\n`);

  console.log(`ok - prepared internal pass inputs (${outMetrics}, ${outSamples})`);
  return { metrics, sampleDoc, prep };
}

if (require.main === module) {
  try {
    run(process.argv);
  } catch (err) {
    console.error(`error: ${err.message}`);
    process.exit(1);
  }
}

module.exports = {
  DEFAULTS,
  extractSampleSummaryFromDb,
  extractXtGateStatuses,
  parseArgs,
  run,
};
