#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { DatabaseSync } = require("node:sqlite");

const {
  buildXtReadyReleaseDiagnostics,
  compactXtReadyReleaseDiagnostics,
} = require("./xt_ready_release_diagnostics.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("release diagnostics explain strict XT-ready blockers from compat runtime evidence", () => {
  const report = buildXtReadyReleaseDiagnostics({
    rootDir: "/tmp/xhub-test-root",
    xtReadyGate: {
      ok: true,
      require_real_audit_source: false,
    },
    xtReadySource: {
      selected_source: "compat_runtime_incident_report",
      require_real_audit: false,
    },
    connectorGate: {
      source_used: "scan",
      snapshot: { pass: true },
      snapshot_audit: {
        pass: false,
        incident_codes: ["audit_source_not_present"],
      },
    },
    runtimeIncidentPayload: {
      source: "supervisor_manager",
      events: [
        {
          incident_code: "grant_pending",
          event_type: "supervisor.incident.grant_pending.handled",
          audit_ref: "audit-real-1",
        },
        {
          incident_code: "grant_pending",
          event_type: "supervisor.incident.grant_pending.handled",
          audit_ref: "audit-real-2",
        },
      ],
    },
    dbCandidateRefs: [],
  });

  assert.equal(report.status, "blocked(strict_xt_ready_release_gap)");
  assert.equal(report.summary.current_release_strict_ready, false);
  assert.deepEqual(report.summary.runtime_missing_required_incidents, [
    "awaiting_instruction",
    "runtime_error",
  ]);
  assert.equal(report.summary.selected_audit_source, "compat_runtime_incident_report");
  assert.equal(report.summary.connector_gate_source_used, "scan");
  assert(report.blockers.some((item) => item.code === "xt_ready_require_real_audit_not_strict"));
  assert(report.blockers.some((item) => item.code === "xt_ready_selected_source_not_real"));
  assert(report.blockers.some((item) => item.code === "connector_gate_source_not_audit"));
  assert(report.blockers.some((item) => item.code === "runtime_missing_required_incidents"));
  assert(report.blockers.some((item) => item.code === "runtime_duplicate_required_incidents"));
  assert.equal(report.summary.recommended_next_path, "fetch_connector_audit_snapshot");
});

run("release diagnostics stay green when strict current artifacts already exist", () => {
  const report = buildXtReadyReleaseDiagnostics({
    rootDir: "/tmp/xhub-test-root",
    xtReadyGate: {
      ok: true,
      require_real_audit_source: true,
    },
    xtReadySource: {
      selected_source: "audit_export",
      require_real_audit: true,
    },
    connectorGate: {
      source_used: "audit",
      snapshot: { pass: true },
      snapshot_audit: { pass: true, incident_codes: [] },
    },
    runtimeIncidentPayload: null,
    dbCandidateRefs: [],
  });

  assert.equal(report.status, "pass(strict_xt_ready_release_inputs_ready)");
  assert.equal(report.summary.current_release_strict_ready, true);
  assert.equal(report.blockers.length, 0);
  assert.equal(report.summary.recommended_next_path, "already_strict_ready");
  assert.deepEqual(report.next_actions, []);

  const compact = compactXtReadyReleaseDiagnostics(report);
  assert.equal(compact.status, "pass(strict_xt_ready_release_inputs_ready)");
  assert.equal(compact.summary.current_release_strict_ready, true);
  assert.equal(compact.blockers.length, 0);
  assert.deepEqual(compact.next_actions, []);
});

run("release diagnostics record selected XT-ready artifact chain and refs", () => {
  const report = buildXtReadyReleaseDiagnostics({
    rootDir: "/tmp/xhub-test-root",
    xtReadyGate: {
      ok: true,
      require_real_audit_source: true,
    },
    xtReadySource: {
      selected_source: "audit_export",
      require_real_audit: true,
    },
    connectorGate: {
      source_used: "audit",
      snapshot: { pass: true },
      snapshot_audit: { pass: true, incident_codes: [] },
    },
    xtReadyArtifact: {
      mode: "require_real_release_chain",
      reportRef: "build/xt_ready_gate_e2e_require_real_report.json",
      sourceRef: "build/xt_ready_evidence_source.require_real.json",
      connectorGateRef: "build/connector_ingress_gate_snapshot.require_real.json",
    },
    dbCandidateRefs: [],
  });

  assert.equal(report.summary.xt_ready_artifact_mode, "require_real_release_chain");
  assert.equal(
    report.summary.xt_ready_gate_ref,
    "build/xt_ready_gate_e2e_require_real_report.json"
  );
  assert.equal(
    report.summary.xt_ready_source_ref,
    "build/xt_ready_evidence_source.require_real.json"
  );
  assert.equal(
    report.summary.connector_gate_ref,
    "build/connector_ingress_gate_snapshot.require_real.json"
  );
  assert.equal(
    report.current_release.artifact_selection.mode,
    "require_real_release_chain"
  );
  assert.equal(
    report.preferred_xt_ready_release_artifacts[0].mode,
    "require_real_release_chain"
  );
});

run("release diagnostics surface hub pairing smoke support as non-blocking evidence", () => {
  const report = buildXtReadyReleaseDiagnostics({
    rootDir: "/tmp/xhub-test-root",
    xtReadyGate: {
      ok: true,
      require_real_audit_source: true,
    },
    xtReadySource: {
      selected_source: "audit_export",
      require_real_audit: true,
    },
    connectorGate: {
      source_used: "audit",
      snapshot: { pass: true },
      snapshot_audit: { pass: true, incident_codes: [] },
    },
    hubPairingLaunchOnlyPayload: {
      mode: "launch_only",
      ok: true,
      launch: {
        action: "already_ready",
      },
      discovery: {
        ok: true,
        status: 200,
        response: {
          pairing_enabled: true,
          pairing_port: 50055,
          internet_host_hint: "17.81.10.243",
        },
      },
      adminToken: {
        resolved: false,
      },
      pairing: {
        cleanupVerified: false,
      },
      errors: [],
    },
    hubPairingVerifyOnlyPayload: {
      mode: "verify_only",
      ok: true,
      launch: {
        action: "verify_only_existing_hub",
      },
      discovery: {
        ok: true,
        status: 200,
        response: {
          pairing_enabled: true,
          pairing_port: 50055,
          internet_host_hint: "17.81.10.243",
        },
      },
      adminToken: {
        resolved: true,
      },
      pairing: {
        postStatus: 201,
        pendingListContainsRequest: true,
        cleanupStatus: "denied",
        cleanupVerified: true,
      },
      errors: [],
    },
    dbCandidateRefs: [],
  });

  assert.equal(report.status, "pass(strict_xt_ready_release_inputs_ready)");
  assert.equal(report.summary.hub_pairing_launch_only_ok, true);
  assert.equal(report.summary.hub_pairing_verify_only_ok, true);
  assert.equal(report.summary.hub_pairing_verify_cleanup_verified, true);
  assert.equal(
    report.support.hub_pairing_roundtrip.launch_only.launch_action,
    "already_ready"
  );
  assert.equal(
    report.support.hub_pairing_roundtrip.verify_only.cleanup_verified,
    true
  );
  assert.equal(
    report.support.hub_pairing_roundtrip.verify_only.pending_list_contains_request,
    true
  );
  assert(
    report.evidence_refs.includes(
      "build/reports/xhub_background_launch_only_smoke_evidence.v1.json"
    )
  );
  assert(
    report.evidence_refs.includes(
      "build/reports/xhub_pairing_roundtrip_verify_only_smoke_evidence.v1.json"
    )
  );

  const compact = compactXtReadyReleaseDiagnostics(report);
  assert.equal(compact.support.hub_pairing_roundtrip.launch_only.ok, true);
  assert.equal(
    compact.support.hub_pairing_roundtrip.verify_only.cleanup_status,
    "denied"
  );
});

run("release diagnostics detect a strict-ready DB window even when full DB export would duplicate grant_pending", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-xt-ready-db-"));
  const dbPath = path.join(root, "hub.sqlite3");
  const db = new DatabaseSync(dbPath);

  try {
    db.exec(
      `CREATE TABLE audit_events (
        event_id TEXT,
        event_type TEXT,
        created_at_ms INTEGER,
        error_code TEXT
      )`
    );
    const insert = db.prepare(
      "INSERT INTO audit_events (event_id, event_type, created_at_ms, error_code) VALUES (?, ?, ?, ?)"
    );
    insert.run(
      "grant-1",
      "supervisor.incident.grant_pending.handled",
      1000,
      "grant_pending"
    );
    insert.run(
      "await-1",
      "supervisor.incident.awaiting_instruction.handled",
      1000,
      "awaiting_instruction"
    );
    insert.run(
      "runtime-1",
      "supervisor.incident.runtime_error.handled",
      1000,
      "runtime_error"
    );
    insert.run(
      "grant-2",
      "supervisor.incident.grant_pending.handled",
      5000,
      "grant_pending"
    );
  } finally {
    db.close();
  }

  try {
    const report = buildXtReadyReleaseDiagnostics({
      rootDir: root,
      xtReadyGate: {
        ok: true,
        require_real_audit_source: false,
      },
      xtReadySource: {
        selected_source: "compat_runtime_incident_report",
        require_real_audit: false,
      },
      connectorGate: {
        source_used: "scan",
        snapshot: { pass: true },
        snapshot_audit: {
          pass: false,
          incident_codes: ["audit_source_not_present"],
        },
      },
      runtimeIncidentPayload: null,
      dbCandidateRefs: [dbPath],
    });

    assert.equal(report.summary.db_candidate_ready, true);
    assert.equal(report.summary.db_selected_strict_ready_mode, "windowed_export");
    assert.equal(
      report.recovery_candidates.hub_audit_db.selected_best_window.from_ms,
      1000
    );
    assert.equal(
      report.recovery_candidates.hub_audit_db.selected_best_window.to_ms,
      1000
    );
    assert(report.next_actions.some((item) => item.action_id === "rerun_db_windowed_export"));
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
