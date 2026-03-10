#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const {
  checkDocBindings,
  checkEvidenceSource,
  checkE2EEvidence,
  checkXtReadyGate,
} = require("./m3_check_xt_ready_gate.js");

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
  return fs.mkdtempSync(path.join(os.tmpdir(), "xt_ready_gate_test_"));
}

function write(filePath, text) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, String(text || ""), "utf8");
}

function makeDocFixture(baseDir) {
  const docs = {
    xt_ready_doc: path.join(baseDir, "xhub-hub-to-xterminal-capability-gate-v1.md"),
    m3_doc: path.join(baseDir, "xhub-memory-v3-m3-work-orders-v1.md"),
    exec_plan_doc: path.join(baseDir, "xhub-memory-v3-execution-plan.md"),
    working_index_doc: path.join(baseDir, "WORKING_INDEX.md"),
    x_memory_doc: path.join(baseDir, "X_MEMORY.md"),
    xt_parallel_doc: path.join(baseDir, "xterminal-parallel-work-orders-v1.md"),
    xt_supervisor_doc: path.join(baseDir, "xt-supervisor-autosplit-multilane-work-orders-v1.md"),
  };

  write(
    docs.xt_ready_doc,
    [
      "XT-Ready-G0",
      "XT-Ready-G5",
      "grant_pending",
      "awaiting_instruction",
      "runtime_error",
      "机器可判定断言",
      "scripts/m3_check_xt_ready_gate.js",
      "scripts/m3_resolve_xt_ready_audit_input.js",
      "scripts/m3_export_xt_ready_audit_from_db.js",
      "scripts/m3_generate_xt_ready_e2e_evidence.js",
      "scripts/m3_extract_xt_ready_incident_events_from_audit.js",
      "scripts/m3_fetch_connector_ingress_gate_snapshot.js",
      "scripts/fixtures/xt_ready_incident_events.sample.json",
      "scripts/fixtures/xt_ready_audit_events.sample.json",
    ].join("\n")
  );
  write(docs.m3_doc, "Gate-M3-XT-Ready");
  write(
    docs.exec_plan_doc,
    [
      "XT-Ready-G0..G5",
      "dispatch_rejected",
      "CT-DIS-D007",
    ].join("\n")
  );
  write(
    docs.working_index_doc,
    [
      "xhub-hub-to-xterminal-capability-gate-v1.md",
      "scripts/m3_resolve_xt_ready_audit_input.js",
      "scripts/m3_export_xt_ready_audit_from_db.js",
    ].join("\n")
  );
  write(
    docs.x_memory_doc,
    [
      "xhub-hub-to-xterminal-capability-gate-v1.md",
      "scripts/m3_resolve_xt_ready_audit_input.js",
      "scripts/m3_export_xt_ready_audit_from_db.js",
    ].join("\n")
  );
  write(docs.xt_parallel_doc, "xhub-hub-to-xterminal-capability-gate-v1.md");
  write(docs.xt_supervisor_doc, "XT-Ready-G0..G5");
  return docs;
}

function makeValidEvidence() {
  return {
    schema_version: "xt_ready_e2e.v1",
    run_id: "xt_ready_run_001",
    summary: {
      high_risk_lane_without_grant: 0,
      unaudited_auto_resolution: 0,
      high_risk_bypass_count: 0,
      blocked_event_miss_rate: 0,
      non_message_ingress_policy_coverage: 1,
    },
    source: {
      connector_gate_snapshot_attached: true,
      connector_gate_source_used: "audit",
      connector_gate_non_message_ingress_policy_coverage: 1,
      connector_gate_blocked_event_miss_rate: 0,
      audit_source_kind: "hub_runtime_export",
      audit_generated_by: "xterminal_supervisor",
      synthetic_runtime_evidence: false,
      synthetic_markers: [],
    },
    incidents: [
      {
        incident_code: "grant_pending",
        lane_id: "lane-2",
        detected_at_ms: 1000,
        handled_at_ms: 2500,
        event_type: "supervisor.incident.grant_pending.handled",
        deny_code: "grant_pending",
        audit_event_type: "supervisor.incident.handled",
        audit_ref: "audit-1",
      },
      {
        incident_code: "awaiting_instruction",
        lane_id: "lane-3",
        takeover_latency_ms: 800,
        event_type: "supervisor.incident.awaiting_instruction.handled",
        deny_code: "awaiting_instruction",
        audit_event_type: "supervisor.incident.handled",
        audit_ref: "audit-2",
      },
      {
        incident_code: "runtime_error",
        lane_id: "lane-4",
        takeover_latency_ms: 1500,
        event_type: "supervisor.incident.runtime_error.handled",
        deny_code: "runtime_error",
        audit_event_type: "supervisor.incident.handled",
        audit_ref: "audit-3",
      },
    ],
  };
}

function makeEvidenceSource(baseDir, sourceKind = "real_audit_export_build") {
  const auditPath = path.join(baseDir, "xt_ready_audit_export.json");
  write(auditPath, JSON.stringify({ events: [] }, null, 2));
  return {
    schema_version: "xt_ready_audit_input_selection.v1",
    selected_source: sourceKind,
    selected_audit_json: auditPath,
    selected_audit_json_resolved: auditPath,
  };
}

run("XT-Ready checker: doc bindings pass with complete fixture", () => {
  const tmp = makeTmpDir();
  const docs = makeDocFixture(tmp);
  const out = checkDocBindings(docs);
  assert.equal(out.ok, true);
  assert.equal(out.errors.length, 0);
});

run("XT-Ready checker: e2e evidence pass for required incident mappings", () => {
  const out = checkE2EEvidence(makeValidEvidence(), { max_takeover_ms: 2000 });
  assert.equal(out.ok, true);
  assert.equal(out.errors.length, 0);
  assert.equal(out.summary.incident_total, 3);
});

run("XT-Ready checker: doc bindings fail when execution-plan lineage snapshot drifts", () => {
  const tmp = makeTmpDir();
  const docs = makeDocFixture(tmp);
  write(docs.exec_plan_doc, "XT-Ready-G0..G5");
  const out = checkDocBindings(docs);
  assert.equal(out.ok, false);
  assert.ok(out.errors.some((x) => x.includes("dispatch_rejected")));
  assert.ok(out.errors.some((x) => x.includes("CT-DIS-D007")));
});

run("XT-Ready checker: e2e evidence fails on deny_code mismatch", () => {
  const bad = makeValidEvidence();
  bad.incidents[0].deny_code = "grant_missing";
  const out = checkE2EEvidence(bad, { max_takeover_ms: 2000 });
  assert.equal(out.ok, false);
  assert.ok(out.errors.some((x) => x.includes("deny_code mismatch")));
});

run("XT-Ready checker: e2e evidence fails on low non-message ingress policy coverage", () => {
  const bad = makeValidEvidence();
  bad.summary.non_message_ingress_policy_coverage = 0.99;
  const out = checkE2EEvidence(bad, { max_takeover_ms: 2000 });
  assert.equal(out.ok, false);
  assert.ok(out.errors.some((x) => x.includes("non_message_ingress_policy_coverage")));
});

run("XT-Ready checker: e2e evidence fails on incident row missing incident_code", () => {
  const bad = makeValidEvidence();
  bad.incidents.push({
    lane_id: "lane-unknown",
    takeover_latency_ms: 100,
    event_type: "supervisor.incident.unknown.handled",
    deny_code: "unknown",
    audit_event_type: "supervisor.incident.handled",
    audit_ref: "audit-unknown",
  });
  const out = checkE2EEvidence(bad, { max_takeover_ms: 2000 });
  assert.equal(out.ok, false);
  assert.ok(out.errors.some((x) => x.includes("missing incident_code")));
});

run("XT-Ready checker: strict mode fails when evidence is missing", () => {
  const tmp = makeTmpDir();
  const docs = makeDocFixture(tmp);
  const out = checkXtReadyGate({
    docPaths: docs,
    e2eEvidence: null,
    strictE2E: true,
    maxTakeoverMs: 2000,
  });
  assert.equal(out.ok, false);
  assert.ok(out.errors.some((x) => x.includes("missing --e2e-evidence")));
});

run("XT-Ready checker: evidence source fails when selected audit path is missing", () => {
  const source = {
    selected_source: "real_audit_export_env",
    selected_audit_json: "/tmp/not-exists-audit-input.json",
  };
  const out = checkEvidenceSource(source, { require_real_audit_source: false });
  assert.equal(out.ok, false);
  assert.ok(out.errors.some((x) => x.includes("does not exist")));
});

run("XT-Ready checker: strict mode fails on unsupported incident_code", () => {
  const tmp = makeTmpDir();
  const docs = makeDocFixture(tmp);
  const bad = makeValidEvidence();
  bad.incidents.push({
    incident_code: "manual_override",
    lane_id: "lane-9",
    takeover_latency_ms: 200,
    event_type: "supervisor.incident.manual_override.handled",
    deny_code: "manual_override",
    audit_event_type: "supervisor.incident.handled",
    audit_ref: "audit-9",
  });
  const out = checkXtReadyGate({
    docPaths: docs,
    e2eEvidence: bad,
    strictE2E: true,
    maxTakeoverMs: 2000,
  });
  assert.equal(out.ok, false);
  assert.ok(out.errors.some((x) => x.includes("unsupported incident_code")));
});

run("XT-Ready checker: require-real-audit-source fails when source is sample fixture", () => {
  const tmp = makeTmpDir();
  const docs = makeDocFixture(tmp);
  const out = checkXtReadyGate({
    docPaths: docs,
    e2eEvidence: makeValidEvidence(),
    evidenceSource: makeEvidenceSource(tmp, "sample_fixture"),
    strictE2E: true,
    requireRealAuditSource: true,
    maxTakeoverMs: 2000,
  });
  assert.equal(out.ok, false);
  assert.ok(out.errors.some((x) => x.includes("require-real-audit-source")));
});

run("XT-Ready checker: require-real-audit-source fails when connector gate source is not audit", () => {
  const tmp = makeTmpDir();
  const docs = makeDocFixture(tmp);
  const bad = makeValidEvidence();
  bad.source.connector_gate_source_used = "scan";
  const out = checkXtReadyGate({
    docPaths: docs,
    e2eEvidence: bad,
    evidenceSource: makeEvidenceSource(tmp, "real_audit_export_build"),
    strictE2E: true,
    requireRealAuditSource: true,
    maxTakeoverMs: 2000,
  });
  assert.equal(out.ok, false);
  assert.ok(out.errors.some((x) => x.includes("connector_gate_source_used")));
});

run("XT-Ready checker: require-real-audit-source fails on synthetic source markers", () => {
  const tmp = makeTmpDir();
  const docs = makeDocFixture(tmp);
  const bad = makeValidEvidence();
  bad.source.synthetic_runtime_evidence = true;
  bad.source.audit_source_kind = "synthetic_runtime";
  bad.source.audit_generated_by = "xt_release_evidence_smoke";
  bad.source.synthetic_markers = ["kind:synthetic_runtime"];
  const out = checkXtReadyGate({
    docPaths: docs,
    e2eEvidence: bad,
    evidenceSource: makeEvidenceSource(tmp, "real_audit_export_build"),
    strictE2E: true,
    requireRealAuditSource: true,
    maxTakeoverMs: 2000,
  });
  assert.equal(out.ok, false);
  assert.ok(out.errors.some((x) => x.includes("synthetic_runtime_evidence")));
  assert.ok(out.errors.some((x) => x.includes("audit_source_kind")));
  assert.ok(out.errors.some((x) => x.includes("audit_generated_by")));
});

run("XT-Ready checker: require-real-audit-source fails on incident synthetic audit_ref", () => {
  const tmp = makeTmpDir();
  const docs = makeDocFixture(tmp);
  const bad = makeValidEvidence();
  bad.incidents[0].audit_ref = "audit-smoke-grant";
  const out = checkXtReadyGate({
    docPaths: docs,
    e2eEvidence: bad,
    evidenceSource: makeEvidenceSource(tmp, "real_audit_export_build"),
    strictE2E: true,
    requireRealAuditSource: true,
    maxTakeoverMs: 2000,
  });
  assert.equal(out.ok, false);
  assert.ok(out.errors.some((x) => x.includes("synthetic audit_ref")));
});

run("XT-Ready checker: strict mode fails on duplicate required incident_code", () => {
  const tmp = makeTmpDir();
  const docs = makeDocFixture(tmp);
  const bad = makeValidEvidence();
  bad.incidents.push({
    incident_code: "grant_pending",
    lane_id: "lane-2b",
    takeover_latency_ms: 300,
    event_type: "supervisor.incident.grant_pending.handled",
    deny_code: "grant_pending",
    audit_event_type: "supervisor.incident.handled",
    audit_ref: "audit-dup",
  });
  const out = checkXtReadyGate({
    docPaths: docs,
    e2eEvidence: bad,
    strictE2E: true,
    maxTakeoverMs: 2000,
  });
  assert.equal(out.ok, false);
  assert.ok(out.errors.some((x) => x.includes("must appear exactly once")));
  assert.ok(out.errors.some((x) => x.includes("strict e2e expects exactly 3 incidents")));
});

run("XT-Ready checker: strict-e2e passes with real evidence source", () => {
  const tmp = makeTmpDir();
  const docs = makeDocFixture(tmp);
  const out = checkXtReadyGate({
    docPaths: docs,
    e2eEvidence: makeValidEvidence(),
    evidenceSource: makeEvidenceSource(tmp, "real_audit_export_build"),
    strictE2E: true,
    requireRealAuditSource: true,
    maxTakeoverMs: 2000,
  });
  assert.equal(out.ok, true);
  assert.equal(Boolean(out.summary.evidence_source_checked), true);
});

run("XT-Ready checker: CLI strict-e2e succeeds with valid evidence fixture", () => {
  const tmp = makeTmpDir();
  const docs = makeDocFixture(tmp);
  const evidencePath = path.join(tmp, "xt_ready_e2e_evidence.json");
  write(evidencePath, JSON.stringify(makeValidEvidence(), null, 2));

  const scriptPath = path.join(__dirname, "m3_check_xt_ready_gate.js");
  const proc = spawnSync(
    process.execPath,
    [
      scriptPath,
      "--strict-e2e",
      "--e2e-evidence",
      evidencePath,
      "--xt-ready-doc",
      docs.xt_ready_doc,
      "--m3-doc",
      docs.m3_doc,
      "--exec-plan-doc",
      docs.exec_plan_doc,
      "--working-index-doc",
      docs.working_index_doc,
      "--x-memory-doc",
      docs.x_memory_doc,
      "--xt-parallel-doc",
      docs.xt_parallel_doc,
      "--xt-supervisor-doc",
      docs.xt_supervisor_doc,
    ],
    { encoding: "utf8" }
  );

  assert.equal(proc.status, 0, proc.stderr || proc.stdout);
  assert.ok((proc.stdout || "").includes("ok - XT-Ready gate passed"));
});
