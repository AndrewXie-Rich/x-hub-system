#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const {
  buildIncidentEventsFromAudit,
} = require("./m3_extract_xt_ready_incident_events_from_audit.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (err) {
    console.error(`not ok - ${name}`);
    throw err;
  }
}

function makeSampleAuditPayload() {
  return {
    run_id: "xt_ready_audit_sample",
    summary: {
      high_risk_lane_without_grant: 0,
      unaudited_auto_resolution: 0,
      high_risk_bypass_count: 0,
      blocked_event_miss_rate: 0,
      non_message_ingress_policy_coverage: 1,
    },
    events: [
      {
        event_id: "audit-1",
        event_type: "supervisor.incident.grant_pending.detected",
        created_at_ms: 100,
        ext_json: JSON.stringify({
          lane_id: "lane-2",
        }),
      },
      {
        event_id: "audit-2",
        event_type: "supervisor.incident.grant_pending.handled",
        created_at_ms: 1400,
        error_code: "grant_pending",
        ext_json: JSON.stringify({
          lane_id: "lane-2",
          detected_at_ms: 100,
          audit_ref: "audit-ref-grant",
          audit_event_type: "supervisor.incident.handled",
        }),
      },
      {
        event_id: "audit-3",
        event_type: "supervisor.incident.awaiting_instruction.handled",
        created_at_ms: 900,
        error_code: "awaiting_instruction",
        ext_json: JSON.stringify({
          lane_id: "lane-3",
          detected_at_ms: 250,
          handled_at_ms: 900,
          audit_ref: "audit-ref-awaiting",
        }),
      },
      {
        event_id: "audit-4",
        event_type: "supervisor.incident.runtime_error.detected",
        created_at_ms: 300,
        ext_json: JSON.stringify({
          lane_id: "lane-4",
        }),
      },
      {
        event_id: "audit-5",
        event_type: "supervisor.incident.runtime_error.handled",
        created_at_ms: 1200,
        error_code: "runtime_error",
        ext_json: JSON.stringify({
          lane_id: "lane-4",
          detected_at_ms: 300,
          handled_at_ms: 1200,
          audit_ref: "audit-ref-runtime",
        }),
      },
      {
        event_id: "audit-ignore",
        event_type: "project.lineage.upserted",
        created_at_ms: 500,
      },
    ],
  };
}

run("audit extractor builds incident events for required codes", () => {
  const out = buildIncidentEventsFromAudit(makeSampleAuditPayload(), { strict: true });
  assert.equal(out.run_id, "xt_ready_audit_sample");
  assert.equal(Array.isArray(out.events), true);
  assert.equal(out.events.length, 5);
  const handledCodes = out.events
    .filter((row) => String(row.event_type || "").endsWith(".handled"))
    .map((row) => String(row.incident_code || ""));
  assert.deepEqual(handledCodes, ["awaiting_instruction", "runtime_error", "grant_pending"]);
  const grantHandled = out.events.find((row) => String(row.event_type) === "supervisor.incident.grant_pending.handled");
  assert.ok(grantHandled);
  assert.equal(String(grantHandled.deny_code || ""), "grant_pending");
  assert.equal(String(grantHandled.audit_ref || ""), "audit-ref-grant");
  assert.equal(Number(out.source.audit_row_total || 0), 6);
  assert.equal(Number(out.source.incident_event_total || 0), 5);
  assert.equal(!!out.source.synthetic_runtime_evidence, false);
});

run("audit extractor strict mode fails when handled incident is missing", () => {
  const payload = makeSampleAuditPayload();
  payload.events = payload.events.filter((row) => !String(row.event_type || "").includes("runtime_error.handled"));
  assert.throws(
    () => buildIncidentEventsFromAudit(payload, { strict: true }),
    /missing required incident handled event\(s\): runtime_error/
  );
});

run("audit extractor strict mode fails when required handled incident is duplicated", () => {
  const payload = makeSampleAuditPayload();
  payload.events.push({
    event_id: "audit-dup",
    event_type: "supervisor.incident.grant_pending.handled",
    created_at_ms: 1450,
    error_code: "grant_pending",
    ext_json: JSON.stringify({
      lane_id: "lane-2b",
      detected_at_ms: 110,
      handled_at_ms: 1450,
      audit_ref: "audit-ref-grant-dup",
    }),
  });
  assert.throws(
    () => buildIncidentEventsFromAudit(payload, { strict: true }),
    /duplicate required incident handled event\(s\): grant_pending:2/
  );
});

run("audit extractor can derive blocked_event_miss_rate from connector gate snapshot payload", () => {
  const payload = makeSampleAuditPayload();
  payload.summary = {
    high_risk_lane_without_grant: 0,
    unaudited_auto_resolution: 0,
    high_risk_bypass_count: 0,
  };
  const out = buildIncidentEventsFromAudit(payload, {
    strict: true,
    connector_gate_payload: {
      source_used: "audit",
      snapshot: {
        schema_version: "xhub.connector.non_message_ingress_gate.v1",
        metrics: {
          non_message_ingress_policy_coverage: 1,
          blocked_event_miss_rate: 0.007,
        },
      },
    },
  });
  assert.equal(Number(out.summary.blocked_event_miss_rate), 0.007);
  assert.equal(Number(out.summary.non_message_ingress_policy_coverage), 1);
  assert.equal(!!out.source.connector_gate_snapshot_attached, true);
  assert.equal(String(out.source.connector_gate_source_used || ""), "audit");
  assert.equal(Number(out.source.connector_gate_non_message_ingress_policy_coverage || 0), 1);
  assert.equal(Number(out.source.connector_gate_blocked_event_miss_rate || 0), 0.007);
});

run("audit extractor accepts row-level deny_code/audit_ref fields", () => {
  const payload = {
    run_id: "xt_ready_row_level_fields",
    summary: {
      high_risk_lane_without_grant: 0,
      unaudited_auto_resolution: 0,
      high_risk_bypass_count: 0,
      blocked_event_miss_rate: 0,
      non_message_ingress_policy_coverage: 1,
    },
    events: [
      {
        event_type: "supervisor.incident.grant_pending.handled",
        created_at_ms: 1000,
        lane_id: "lane-2",
        deny_code: "grant_pending",
        audit_ref: "audit-row-grant",
      },
      {
        event_type: "supervisor.incident.awaiting_instruction.handled",
        created_at_ms: 1100,
        lane_id: "lane-3",
        deny_code: "awaiting_instruction",
        audit_ref: "audit-row-awaiting",
      },
      {
        event_type: "supervisor.incident.runtime_error.handled",
        created_at_ms: 1200,
        lane_id: "lane-4",
        deny_code: "runtime_error",
        audit_ref: "audit-row-runtime",
      },
    ],
  };

  const out = buildIncidentEventsFromAudit(payload, { strict: true });
  const refs = out.events
    .filter((row) => String(row.event_type || "").endsWith(".handled"))
    .map((row) => String(row.audit_ref || ""))
    .sort();
  assert.deepEqual(refs, ["audit-row-awaiting", "audit-row-grant", "audit-row-runtime"]);
});

run("audit extractor marks synthetic runtime evidence when source/audit_ref indicate smoke", () => {
  const payload = makeSampleAuditPayload();
  payload.source = {
    kind: "synthetic_runtime",
    generated_by: "xt_release_evidence_smoke",
  };
  payload.events[1].ext_json = JSON.stringify({
    lane_id: "lane-2",
    detected_at_ms: 100,
    audit_ref: "audit-smoke-grant",
    audit_event_type: "supervisor.incident.handled",
  });
  const out = buildIncidentEventsFromAudit(payload, { strict: true });
  assert.equal(!!out.source.synthetic_runtime_evidence, true);
  const markers = Array.isArray(out.source.synthetic_markers) ? out.source.synthetic_markers : [];
  assert.ok(markers.some((x) => String(x).includes("kind:synthetic_runtime")));
  assert.ok(markers.some((x) => String(x).includes("generated_by:xt_release_evidence_smoke")));
  assert.ok(markers.some((x) => String(x).includes("audit_ref_prefix:audit-smoke")));
});

run("audit extractor CLI writes output file", () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "xt_ready_audit_extract_"));
  try {
    const inPath = path.join(tmpDir, "audit_events.json");
    const outPath = path.join(tmpDir, "incident_events.json");
    fs.writeFileSync(inPath, JSON.stringify(makeSampleAuditPayload(), null, 2));
    const proc = spawnSync(
      process.execPath,
      [
        path.resolve(__dirname, "m3_extract_xt_ready_incident_events_from_audit.js"),
        "--audit-json", inPath,
        "--out-json", outPath,
        "--strict",
      ],
      { encoding: "utf8" }
    );
    assert.equal(proc.status, 0, proc.stderr || proc.stdout);
    const out = JSON.parse(fs.readFileSync(outPath, "utf8"));
    assert.equal(Array.isArray(out.events), true);
    assert.equal(out.events.length, 5);
    assert.equal(String(out.summary.blocked_event_miss_rate), "0");
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});
