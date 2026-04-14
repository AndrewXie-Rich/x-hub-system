#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildConnectorSnapshotPayload,
  buildInternalPassReports,
  buildReleaseDecisionPayload,
  buildRequireRealProvenancePayload,
  buildXtReadyEvidenceSourcePayload,
  extractDecisionFromXtGateReport,
  extractXtGateStatuses,
} = require("./generate_release_legacy_compat_artifacts.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("legacy release compat: parses XT gate decision and statuses", () => {
  const markdown = [
    "# XT Gate",
    "- decision: GO",
    "PASS: XT-G0",
    "FAIL: XT-G3",
  ].join("\n");
  assert.equal(extractDecisionFromXtGateReport(markdown), "GO");
  assert.deepEqual(extractXtGateStatuses(markdown), {
    xt_g0_status: "PASS",
    xt_g3_status: "FAIL",
  });
});

run("legacy release compat: release decision keeps GO but preserves scope freeze note", () => {
  const payload = buildReleaseDecisionPayload({
    xtReportIndex: {
      release_decision: "GO",
      summary: { pass: 62, warn: 0, fail: 0 },
      coverage: {
        "XT-W3-08": "PASS",
        "CRK-W1-08": "PASS",
        "CM-W5-20": "PASS",
      },
    },
    xtGateDecision: "GO",
  });
  assert.equal(payload.release_ready, true);
  assert.equal(payload.release_decision, "GO");
  assert.match(payload.non_scope_note, /Scope remains frozen/i);
});

run("legacy release compat: XT ready source stays non-strict without claiming audit-grade provenance", () => {
  const payload = buildXtReadyEvidenceSourcePayload({
    xtReadyGate: {
      ok: true,
      require_real_audit_source: false,
    },
  });
  assert.equal(payload.require_real_audit, false);
  assert.ok(["compat_runtime_incident_report", "sample_fixture"].includes(payload.selected_source));
});

run("legacy release compat: preserves preferred XT-ready evidence source when present", () => {
  const payload = buildXtReadyEvidenceSourcePayload({
    xtReadyGate: {
      ok: true,
      require_real_audit_source: true,
    },
    xtReadyArtifacts: {
      reportRef: "build/xt_ready_gate_e2e_require_real_report.json",
      sourceRef: "build/xt_ready_evidence_source.require_real.json",
    },
    xtReadySource: {
      schema_version: "xt_ready_audit_input_selection.v1",
      selected_source: "audit_export",
      selected_audit_json: "./build/xt_ready_audit_export.json",
      require_real_audit: true,
    },
  });

  assert.equal(payload.selected_source, "audit_export");
  assert.equal(payload.require_real_audit, true);
  assert.deepEqual(payload.compat_source_refs, [
    "build/xt_ready_gate_e2e_require_real_report.json",
    "build/xt_ready_evidence_source.require_real.json",
  ]);
});

run("legacy release compat: connector snapshot uses scan source and keeps pass/fail machine-readable", () => {
  const payload = buildConnectorSnapshotPayload({
    runtimeIncidents: {
      summary: {
        non_message_ingress_policy_coverage: 1,
        blocked_event_miss_rate: 0,
      },
    },
    doctorReport: {
      doctor: {
        non_message_ingress_policy_coverage: 1,
      },
    },
  });
  assert.equal(payload.source_used, "scan");
  assert.equal(payload.snapshot.pass, true);
  assert.equal(payload.summary.non_message_ingress_policy_coverage, 1);
  assert.equal(payload.summary.blocked_event_miss_rate, 0);
});

run("legacy release compat: connector snapshot preserves preferred strict connector evidence when present", () => {
  const payload = buildConnectorSnapshotPayload({
    xtReadyArtifacts: {
      connectorRef: "build/connector_ingress_gate_snapshot.require_real.json",
      connector: {
        source_used: "audit",
        snapshot: {
          pass: true,
        },
        summary: {
          blocked_event_miss_rate: 0,
        },
      },
    },
  });

  assert.equal(payload.source_used, "audit");
  assert.equal(payload.snapshot.pass, true);
  assert.deepEqual(payload.compat_source_refs, [
    "build/connector_ingress_gate_snapshot.require_real.json",
  ]);
});

run("legacy release compat: provenance remains fail-closed until require-real and strict audit both align", () => {
  const releaseDecision = buildReleaseDecisionPayload({
    xtReportIndex: { release_decision: "GO" },
    xtGateDecision: "GO",
  });
  const xtReadySource = {
    selected_source: "compat_runtime_incident_report",
    selected_audit_json: "./x-terminal/.axcoder/reports/xt_ready_incident_events.runtime.json",
  };
  const connector = {
    source_used: "scan",
    snapshot: { pass: true },
  };
  const payload = buildRequireRealProvenancePayload(
    {
      requireRealEvidence: {
        gate_verdict: "NO_GO(require_real_samples_pending)",
        release_stance: "no_go",
        verdict_reason: "pending",
        machine_decision: {
          pending_samples: ["lpr_rr_01"],
          missing_evidence_samples: ["lpr_rr_01"],
        },
      },
      xtReadyGate: {
        ok: true,
        require_real_audit_source: false,
      },
    },
    releaseDecision,
    xtReadySource,
    connector,
  );
  assert.equal(payload.summary.strict_xt_ready_require_real_pass, false);
  assert.equal(payload.summary.unified_release_ready_provenance_pass, false);
  assert.equal(payload.summary.release_stance, "no_go");
  assert.ok(payload.summary.blockers.includes("lpr_require_real_not_ready"));
  assert.ok(payload.summary.blockers.includes("xt_ready_require_real_audit_not_strict"));
  assert.ok(payload.summary.blockers.includes("connector_gate_not_audit_source"));
});

run("legacy release compat: internal pass report accepts preferred XT-ready report ref", () => {
  const report = buildInternalPassReports({
    xtReadyArtifacts: {
      reportRef: "build/xt_ready_gate_e2e_require_real_report.json",
    },
  });
  assert.ok(
    report.compat_source_refs.includes("build/xt_ready_gate_e2e_require_real_report.json")
  );
});
