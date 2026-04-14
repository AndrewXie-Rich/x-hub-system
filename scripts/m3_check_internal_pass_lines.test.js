#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const {
  checkInternalPassLines,
  evaluateSampleSufficiency,
  extractDecisionFromXtGateReport,
  resolvePreferredXtReadyPaths,
} = require("./m3_check_internal_pass_lines.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (err) {
    console.error(`not ok - ${name}`);
    throw err;
  }
}

function makeTmpDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "internal_pass_lines_test_"));
}

function write(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, String(content || ""), "utf8");
}

function writeJson(filePath, payload) {
  write(filePath, `${JSON.stringify(payload, null, 2)}\n`);
}

function makeFixture(baseDir) {
  const paths = {
    xt_report_index: path.join(baseDir, "x-terminal/.axcoder/reports/xt-report-index.json"),
    xt_gate_report: path.join(baseDir, "x-terminal/.axcoder/reports/xt-gate-report.md"),
    xt_overflow_report: path.join(baseDir, "x-terminal/.axcoder/reports/xt-overflow-fairness-report.json"),
    xt_origin_report: path.join(baseDir, "x-terminal/.axcoder/reports/xt-origin-fallback-report.json"),
    xt_cleanup_report: path.join(baseDir, "x-terminal/.axcoder/reports/xt-dispatch-cleanup-report.json"),
    doctor_report: path.join(baseDir, "x-terminal/.axcoder/reports/doctor-report.json"),
    secrets_dry_run_report: path.join(baseDir, "x-terminal/.axcoder/reports/secrets-dry-run-report.json"),
    xt_rollback_last_report: path.join(baseDir, "x-terminal/.axcoder/reports/xt-rollback-last.json"),
    xt_ready_gate_report: path.join(baseDir, "build/xt_ready_gate_e2e_report.json"),
    xt_ready_evidence_source: path.join(baseDir, "build/xt_ready_evidence_source.json"),
    connector_gate_snapshot: path.join(baseDir, "build/connector_ingress_gate_snapshot.json"),
    metrics_json: path.join(baseDir, "build/internal_pass_metrics.json"),
    sample_summary_json: path.join(baseDir, "build/internal_pass_samples.json"),
  };

  writeJson(paths.xt_report_index, {
    schema_version: "xt_report_index.v1",
    release_decision: "GO",
    coverage: {
      "XT-W3-08": "PASS",
      "CRK-W1-08": "PASS",
      "CM-W5-20": "PASS",
      "XT-W2-17": "PASS",
      "XT-W2-18": "PASS",
      "XT-W2-19": "PASS",
    },
  });
  write(
    paths.xt_gate_report,
    [
      "# XT Gate Report",
      "- decision: GO",
      "## 新增工单ID覆盖区块",
      "- XT-W3-08: PASS",
      "- CRK-W1-08: PASS",
      "- CM-W5-20: PASS",
      "- XT-W2-17: PASS",
      "- XT-W2-18: PASS",
      "- XT-W2-19: PASS",
    ].join("\n")
  );

  writeJson(paths.xt_overflow_report, { status: "pass" });
  writeJson(paths.xt_origin_report, { status: "pass" });
  writeJson(paths.xt_cleanup_report, { status: "pass" });
  writeJson(paths.doctor_report, { status: "pass" });
  writeJson(paths.secrets_dry_run_report, { status: "pass" });
  writeJson(paths.xt_rollback_last_report, {
    status: "pass",
    copied_previous_to_current: 1,
  });
  writeJson(paths.xt_ready_gate_report, {
    ok: true,
    require_real_audit_source: true,
  });
  writeJson(paths.xt_ready_evidence_source, {
    selected_source: "real_audit_export_build",
    selected_audit_json: "./build/xt_ready_audit_export.json",
  });
  writeJson(paths.connector_gate_snapshot, {
    source_used: "audit",
  });

  writeJson(paths.metrics_json, {
    gate_m3_0_status: "PASS",
    gate_m3_1_status: "PASS",
    gate_m3_2_status: "PASS",
    gate_m3_3_status: "PASS",
    gate_m3_4_status: "PASS",
    xt_ready_g0_status: "PASS",
    xt_ready_g1_status: "PASS",
    xt_ready_g2_status: "PASS",
    xt_ready_g3_status: "PASS",
    xt_ready_g4_status: "PASS",
    xt_ready_g5_status: "PASS",
    xt_g0_status: "PASS",
    xt_g1_status: "PASS",
    xt_g2_status: "PASS",
    xt_g3_status: "PASS",
    xt_g4_status: "PASS",
    xt_g5_status: "PASS",
    queue_wait_p90_ms: 1200,
    split_to_parallel_start_p95_ms: 4500,
    proposal_ready_p95_ms: 1800,
    lane_stall_detect_p95_ms: 900,
    supervisor_action_latency_p95_ms: 700,
    child_project_assignment_success_rate: 99,
    mergeback_first_pass_rate: 75,
    mean_time_to_root_cause: 18,
    high_risk_lane_without_grant: 0,
    bypass_grant_execution: 0,
    high_risk_bypass_count: 0,
    unaudited_auto_resolution: 0,
    unsigned_high_risk_skill_exec: 0,
    credential_finding_block_rate: 100,
    non_message_ingress_policy_coverage: 100,
    blocked_event_miss_rate: 0.2,
    preauth_memory_growth_unbounded: 0,
    webhook_replay_accept_count: 0,
    cross_channel_fallback_blocked: 100,
    token_per_task_delta: -25,
    token_budget_overrun_rate: 1.2,
    cross_session_dedup_hit_rate: 66,
    cross_lane_context_dedup_hit_rate: 71,
    parent_fork_overflow_silent_fail: 0,
    parent_fork_overflow_detect_p95_ms: 900,
    enqueue_during_drain_silent_drop: 0,
    retry_starvation_incidents: 0,
    restart_recovery_success_rate: 99.8,
    dispatch_idle_stuck_incidents: 0,
    route_origin_fallback_violations: 0,
    lineage_visibility_coverage: 100,
    hard_split_without_child_project: 0,
    soft_split_lineage_pollution: 0,
    lineage_cycle_incidents: 0,
    mergeback_rollback_success_rate: 99.5,
    contract_test_drift_incidents: 0,
    missing_deny_code_coverage: 0,
  });
  writeJson(paths.sample_summary_json, {
    lane_event_count: 2000,
    high_risk_request_count: 500,
    mergeback_runs: 180,
  });
  return paths;
}

run("internal pass-lines: markdown decision extractor parses GO", () => {
  const decision = extractDecisionFromXtGateReport("- decision: GO\n");
  assert.equal(decision, "GO");
});

run("internal pass-lines: sample sufficiency marks insufficient when counts are low", () => {
  const out = evaluateSampleSufficiency({
    lane_event_count: 200,
    high_risk_request_count: 120,
    mergeback_runs: 12,
  });
  assert.equal(out.ok, false);
  assert.ok(out.errors.some((x) => x.includes("lane_event_count")));
});

run("internal pass-lines: check returns GO when fixture satisfies all hard lines", () => {
  const tmp = makeTmpDir();
  const paths = makeFixture(tmp);
  const out = checkInternalPassLines({
    paths,
    requireRealAudit: true,
    windowLabel: "2026-02-21..2026-02-28",
  });
  assert.equal(out.release_decision, "GO");
  assert.equal(out.failed_hard_lines.length, 0);
  assert.equal(out.missing_evidence.length, 0);
});

run("internal pass-lines: check returns NO-GO when required coverage id is not PASS", () => {
  const tmp = makeTmpDir();
  const paths = makeFixture(tmp);
  const idx = JSON.parse(fs.readFileSync(paths.xt_report_index, "utf8"));
  idx.coverage["XT-W2-18"] = "WARN";
  fs.writeFileSync(paths.xt_report_index, `${JSON.stringify(idx, null, 2)}\n`, "utf8");

  const out = checkInternalPassLines({ paths, requireRealAudit: true });
  assert.equal(out.release_decision, "NO-GO");
  assert.ok(out.failed_hard_lines.includes("HL-01"));
});

run("internal pass-lines: check returns INSUFFICIENT_EVIDENCE when sample thresholds are not met", () => {
  const tmp = makeTmpDir();
  const paths = makeFixture(tmp);
  writeJson(paths.sample_summary_json, {
    lane_event_count: 10,
    high_risk_request_count: 20,
    mergeback_runs: 30,
  });
  const out = checkInternalPassLines({ paths, requireRealAudit: true });
  assert.equal(out.release_decision, "INSUFFICIENT_EVIDENCE");
});

run("internal pass-lines: preferred XT-ready resolver picks require-real artifacts before current gate", () => {
  const tmp = makeTmpDir();
  const paths = makeFixture(tmp);
  fs.rmSync(paths.xt_ready_gate_report, { force: true });
  fs.rmSync(paths.xt_ready_evidence_source, { force: true });
  fs.rmSync(paths.connector_gate_snapshot, { force: true });

  const requireRealGate = path.join(tmp, "build/xt_ready_gate_e2e_require_real_report.json");
  const requireRealSource = path.join(tmp, "build/xt_ready_evidence_source.require_real.json");
  const requireRealConnector = path.join(
    tmp,
    "build/connector_ingress_gate_snapshot.require_real.json"
  );
  writeJson(requireRealGate, {
    ok: true,
    require_real_audit_source: true,
  });
  writeJson(requireRealSource, {
    selected_source: "audit_export",
  });
  writeJson(requireRealConnector, {
    source_used: "audit",
  });

  const resolved = resolvePreferredXtReadyPaths(tmp);
  assert.equal(resolved.reportPath, requireRealGate);
  assert.equal(resolved.sourcePath, requireRealSource);
  assert.equal(resolved.connectorPath, requireRealConnector);
});

run("internal pass-lines: CLI default XT-ready path selection accepts require-real artifacts", () => {
  const tmp = makeTmpDir();
  const paths = makeFixture(tmp);
  fs.rmSync(paths.xt_ready_gate_report, { force: true });
  fs.rmSync(paths.xt_ready_evidence_source, { force: true });
  fs.rmSync(paths.connector_gate_snapshot, { force: true });

  const requireRealGate = path.join(tmp, "build/xt_ready_gate_e2e_require_real_report.json");
  const requireRealSource = path.join(tmp, "build/xt_ready_evidence_source.require_real.json");
  const requireRealConnector = path.join(
    tmp,
    "build/connector_ingress_gate_snapshot.require_real.json"
  );
  writeJson(requireRealGate, {
    ok: true,
    require_real_audit_source: true,
  });
  writeJson(requireRealSource, {
    selected_source: "real_audit_export_build",
    selected_audit_json: "./build/xt_ready_audit_export.json",
  });
  writeJson(requireRealConnector, {
    source_used: "audit",
  });

  const outPath = path.join(tmp, "build/internal_pass_lines_require_real_report.json");
  const proc = spawnSync(
    process.execPath,
    [
      path.join(__dirname, "m3_check_internal_pass_lines.js"),
      "--xt-report-index",
      paths.xt_report_index,
      "--xt-gate-report",
      paths.xt_gate_report,
      "--xt-overflow-report",
      paths.xt_overflow_report,
      "--xt-origin-report",
      paths.xt_origin_report,
      "--xt-cleanup-report",
      paths.xt_cleanup_report,
      "--doctor-report",
      paths.doctor_report,
      "--secrets-dry-run-report",
      paths.secrets_dry_run_report,
      "--xt-rollback-last-report",
      paths.xt_rollback_last_report,
      "--metrics-json",
      paths.metrics_json,
      "--sample-summary-json",
      paths.sample_summary_json,
      "--out-json",
      outPath,
    ],
    { cwd: tmp, encoding: "utf8" }
  );

  assert.equal(proc.status, 0, proc.stderr || proc.stdout);
  const out = JSON.parse(fs.readFileSync(outPath, "utf8"));
  assert.equal(out.release_decision, "GO");
  assert.equal(out.missing_evidence.length, 0);
  assert.equal(out.loader_errors.length, 0);
});

run("internal pass-lines: explicit require-real gate/source infer matching connector snapshot when connector arg is omitted", () => {
  const tmp = makeTmpDir();
  const paths = makeFixture(tmp);
  fs.rmSync(paths.xt_ready_gate_report, { force: true });
  fs.rmSync(paths.xt_ready_evidence_source, { force: true });
  fs.rmSync(paths.connector_gate_snapshot, { force: true });

  const requireRealGate = path.join(tmp, "build/xt_ready_gate_e2e_require_real_report.json");
  const requireRealSource = path.join(tmp, "build/xt_ready_evidence_source.require_real.json");
  const requireRealConnector = path.join(
    tmp,
    "build/connector_ingress_gate_snapshot.require_real.json"
  );
  writeJson(requireRealGate, {
    ok: true,
    require_real_audit_source: true,
  });
  writeJson(requireRealSource, {
    selected_source: "real_audit_export_build",
    selected_audit_json: "./build/xt_ready_audit_export.json",
  });
  writeJson(requireRealConnector, {
    source_used: "audit",
  });

  const outPath = path.join(tmp, "build/internal_pass_lines_require_real_explicit_report.json");
  const proc = spawnSync(
    process.execPath,
    [
      path.join(__dirname, "m3_check_internal_pass_lines.js"),
      "--xt-report-index",
      paths.xt_report_index,
      "--xt-gate-report",
      paths.xt_gate_report,
      "--xt-overflow-report",
      paths.xt_overflow_report,
      "--xt-origin-report",
      paths.xt_origin_report,
      "--xt-cleanup-report",
      paths.xt_cleanup_report,
      "--doctor-report",
      paths.doctor_report,
      "--secrets-dry-run-report",
      paths.secrets_dry_run_report,
      "--xt-rollback-last-report",
      paths.xt_rollback_last_report,
      "--xt-ready-gate-report",
      requireRealGate,
      "--xt-ready-evidence-source",
      requireRealSource,
      "--metrics-json",
      paths.metrics_json,
      "--sample-summary-json",
      paths.sample_summary_json,
      "--out-json",
      outPath,
    ],
    { cwd: tmp, encoding: "utf8" }
  );

  assert.equal(proc.status, 0, proc.stderr || proc.stdout);
  const out = JSON.parse(fs.readFileSync(outPath, "utf8"));
  assert.equal(out.release_decision, "GO");
  assert.equal(out.missing_evidence.length, 0);
  assert.equal(out.loader_errors.length, 0);
});

run("internal pass-lines: CLI returns non-zero for NO-GO", () => {
  const tmp = makeTmpDir();
  const paths = makeFixture(tmp);
  const idx = JSON.parse(fs.readFileSync(paths.xt_report_index, "utf8"));
  idx.release_decision = "GO_WITH_RISK";
  fs.writeFileSync(paths.xt_report_index, `${JSON.stringify(idx, null, 2)}\n`, "utf8");
  const outPath = path.join(tmp, "build/internal_pass_lines_report.json");

  const proc = spawnSync(
    process.execPath,
    [
      path.join(__dirname, "m3_check_internal_pass_lines.js"),
      "--xt-report-index",
      paths.xt_report_index,
      "--xt-gate-report",
      paths.xt_gate_report,
      "--xt-overflow-report",
      paths.xt_overflow_report,
      "--xt-origin-report",
      paths.xt_origin_report,
      "--xt-cleanup-report",
      paths.xt_cleanup_report,
      "--doctor-report",
      paths.doctor_report,
      "--secrets-dry-run-report",
      paths.secrets_dry_run_report,
      "--xt-rollback-last-report",
      paths.xt_rollback_last_report,
      "--xt-ready-gate-report",
      paths.xt_ready_gate_report,
      "--xt-ready-evidence-source",
      paths.xt_ready_evidence_source,
      "--connector-gate-snapshot",
      paths.connector_gate_snapshot,
      "--metrics-json",
      paths.metrics_json,
      "--sample-summary-json",
      paths.sample_summary_json,
      "--out-json",
      outPath,
    ],
    { encoding: "utf8" }
  );

  assert.notEqual(proc.status, 0, proc.stdout);
  assert.ok(fs.existsSync(outPath));
});
