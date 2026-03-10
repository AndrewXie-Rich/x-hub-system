#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const {
  buildXtReadyE2EEvidence,
  parseEventType,
} = require("./m3_generate_xt_ready_e2e_evidence.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (err) {
    console.error(`not ok - ${name}`);
    throw err;
  }
}

function makeSampleEvents() {
  return {
    run_id: "xt_ready_generated_run_sample",
    events: [
      {
        timestamp_ms: 100,
        event_type: "supervisor.incident.grant_pending.detected",
        incident_code: "grant_pending",
        lane_id: "lane-2",
      },
      {
        timestamp_ms: 1500,
        event_type: "supervisor.incident.grant_pending.handled",
        incident_code: "grant_pending",
        lane_id: "lane-2",
        deny_code: "grant_pending",
        audit_event_type: "supervisor.incident.handled",
        audit_ref: "audit-grant-1",
      },
      {
        detected_at_ms: 200,
        handled_at_ms: 900,
        event_type: "supervisor.incident.awaiting_instruction.handled",
        incident_code: "awaiting_instruction",
        lane_id: "lane-3",
        deny_code: "awaiting_instruction",
        audit_ref: "audit-awaiting-1",
      },
      {
        timestamp_ms: 300,
        event_type: "supervisor.incident.runtime_error.detected",
        incident_code: "runtime_error",
        lane_id: "lane-4",
      },
      {
        timestamp_ms: 1000,
        event_type: "supervisor.incident.runtime_error.handled",
        incident_code: "runtime_error",
        lane_id: "lane-4",
        deny_code: "runtime_error",
        audit_ref: "audit-runtime-1",
      },
    ],
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
  };
}

run("XT-Ready evidence generator builds required incidents", () => {
  const out = buildXtReadyE2EEvidence(makeSampleEvents(), { strict: true });
  assert.equal(out.schema_version, "xt_ready_e2e.v1");
  assert.equal(out.run_id, "xt_ready_generated_run_sample");
  assert.equal(Array.isArray(out.incidents), true);
  assert.equal(out.incidents.length, 3);
  const codes = out.incidents.map((x) => x.incident_code);
  assert.deepEqual(codes, ["grant_pending", "awaiting_instruction", "runtime_error"]);
  assert.equal(out.incidents[0].takeover_latency_ms, 1400);
  assert.equal(out.incidents[1].takeover_latency_ms, 700);
  assert.equal(out.summary.high_risk_lane_without_grant, 0);
  assert.equal(out.summary.non_message_ingress_policy_coverage, 1);
  assert.equal(out.source.connector_gate_snapshot_attached, true);
  assert.equal(out.source.connector_gate_source_used, "audit");
  assert.equal(out.source.audit_source_kind, "hub_runtime_export");
  assert.equal(out.source.audit_generated_by, "xterminal_supervisor");
  assert.equal(out.source.synthetic_runtime_evidence, false);
});

run("XT-Ready evidence generator preserves synthetic markers from source metadata", () => {
  const sample = makeSampleEvents();
  sample.source.synthetic_runtime_evidence = true;
  sample.source.synthetic_markers = ["kind:synthetic_runtime", "audit_ref_prefix:audit-smoke (1)"];
  const out = buildXtReadyE2EEvidence(sample, { strict: true });
  assert.equal(out.source.synthetic_runtime_evidence, true);
  assert.deepEqual(
    out.source.synthetic_markers,
    ["kind:synthetic_runtime", "audit_ref_prefix:audit-smoke (1)"]
  );
});

run("XT-Ready evidence generator strict mode fails on missing required incident", () => {
  const sample = makeSampleEvents();
  sample.events = sample.events.filter((x) => String(x.incident_code || "") !== "runtime_error");
  assert.throws(
    () => buildXtReadyE2EEvidence(sample, { strict: true }),
    /missing required incident\(s\): runtime_error/
  );
});

run("XT-Ready evidence generator strict mode fails on duplicate required incident", () => {
  const sample = makeSampleEvents();
  sample.events.push({
    timestamp_ms: 1600,
    event_type: "supervisor.incident.grant_pending.handled",
    incident_code: "grant_pending",
    lane_id: "lane-2b",
    deny_code: "grant_pending",
    audit_event_type: "supervisor.incident.handled",
    audit_ref: "audit-grant-dup",
  });
  assert.throws(
    () => buildXtReadyE2EEvidence(sample, { strict: true }),
    /duplicate required incident\(s\) in strict mode: grant_pending:2/
  );
});

run("XT-Ready evidence generator parseEventType handles unknown safely", () => {
  const known = parseEventType("supervisor.incident.grant_pending.handled");
  assert.equal(known.incident_code, "grant_pending");
  assert.equal(known.phase, "handled");

  const unknown = parseEventType("supervisor.other.unknown");
  assert.equal(unknown.incident_code, "");
  assert.equal(unknown.phase, "");
});

run("XT-Ready evidence generator CLI writes output file", () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "xt_ready_evidence_gen_"));
  try {
    const inPath = path.join(tmpDir, "events.json");
    const outPath = path.join(tmpDir, "evidence.json");
    fs.writeFileSync(inPath, JSON.stringify(makeSampleEvents(), null, 2));
    const proc = spawnSync(
      process.execPath,
      [
        path.resolve(__dirname, "m3_generate_xt_ready_e2e_evidence.js"),
        "--events-json", inPath,
        "--out-json", outPath,
        "--strict",
      ],
      { encoding: "utf8" }
    );
    assert.equal(proc.status, 0, proc.stderr || proc.stdout);
    const content = JSON.parse(fs.readFileSync(outPath, "utf8"));
    assert.equal(content.schema_version, "xt_ready_e2e.v1");
    assert.equal(Array.isArray(content.incidents), true);
    assert.equal(content.incidents.length, 3);
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});

run("XT-Ready evidence generator strict mode passes canonical incident replay fixture", () => {
  const fixturePath = path.resolve(__dirname, "fixtures/xt_ready_incident_events.sample.json");
  const payload = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
  const out = buildXtReadyE2EEvidence(payload, { strict: true, run_id: "xt_ready_fixture_regression" });
  assert.equal(out.schema_version, "xt_ready_e2e.v1");
  assert.equal(out.run_id, "xt_ready_fixture_regression");
  assert.deepEqual(
    out.incidents.map((item) => item.incident_code),
    ["grant_pending", "awaiting_instruction", "runtime_error"]
  );
});
