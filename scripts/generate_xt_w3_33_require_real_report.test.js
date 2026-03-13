#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildRequireRealReport,
} = require("./generate_xt_w3_33_require_real_report.js");
const {
  updateBundle,
} = require("./update_xt_w3_33_require_real_capture_bundle.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

function makeBundle(samples) {
  return {
    schema_version: "xhub.xt_w3_33_require_real_capture_bundle.v1",
    generated_at: "2026-03-11T12:00:00Z",
    status: "ready_for_execution",
    stop_on_first_defect: true,
    execution_order: samples.map((sample) => sample.sample_id),
    samples,
  };
}

function baseSample(overrides = {}) {
  return {
    sample_id: "xt_w3_33_rr_sample",
    status: "pending",
    performed_at: "",
    success_boolean: null,
    evidence_refs: [],
    synthetic_runtime_evidence: false,
    synthetic_markers: [],
    required_checks: [],
    ...overrides,
  };
}

run("XT-W3-33 require-real report stays NO_GO when samples are still pending", () => {
  const report = buildRequireRealReport(makeBundle([
    baseSample({
      sample_id: "xt_w3_33_rr_01",
      required_checks: [{ field: "decision_track_written", equals: true }],
    }),
  ]), {
    generatedAt: "2026-03-11T12:30:00Z",
  });

  assert.equal(report.gate_verdict, "NO_GO(require_real_samples_pending)");
  assert.deepEqual(report.machine_decision.pending_samples, ["xt_w3_33_rr_01"]);
  assert.equal(report.release_stance, "no_go");
});

run("XT-W3-33 require-real report rejects synthetic evidence even if sample says passed", () => {
  const report = buildRequireRealReport(makeBundle([
    baseSample({
      sample_id: "xt_w3_33_rr_02",
      status: "passed",
      performed_at: "2026-03-11T13:00:00Z",
      success_boolean: true,
      evidence_refs: ["build/reports/screenshot.png"],
      synthetic_runtime_evidence: true,
      required_checks: [{ field: "fail_closed", equals: true }],
      fail_closed: true,
    }),
  ]));

  assert.equal(report.gate_verdict, "NO_GO(synthetic_runtime_evidence_not_accepted)");
  assert.deepEqual(report.machine_decision.synthetic_samples, ["xt_w3_33_rr_02"]);
});

run("XT-W3-33 require-real report passes only when all samples are real and checks hold", () => {
  const report = buildRequireRealReport(makeBundle([
    baseSample({
      sample_id: "xt_w3_33_rr_03",
      status: "passed",
      performed_at: "2026-03-11T13:10:00Z",
      success_boolean: true,
      evidence_refs: ["build/reports/proof.png"],
      governance_mode: "proposal_with_timeout_escalation",
      approval_state: "proposal_pending",
      proposal_generated: true,
      required_checks: [
        { field: "proposal_generated", equals: true },
        { field: "approval_state", equals: "proposal_pending" },
        { field: "governance_mode", one_of: ["proposal_only", "proposal_with_timeout_escalation", "auto_adopt_if_policy_allows"] },
      ],
    }),
  ]));

  assert.equal(report.gate_verdict, "PASS(require_real_governance_samples_executed_and_verified)");
  assert.equal(report.machine_decision.all_samples_passed, true);
  assert.equal(report.release_stance, "candidate_go");
});

run("XT-W3-33 capture bundle updater dedupes refs and marks executed samples", () => {
  const bundle = makeBundle([
    baseSample({ sample_id: "xt_w3_33_rr_04" }),
  ]);

  const { bundle: updated, sample } = updateBundle(bundle, {
    sampleId: "xt_w3_33_rr_04",
    status: "passed",
    success: true,
    performedAt: "2026-03-11T14:00:00Z",
    evidenceRefs: ["build/reports/proof.png", "build/reports/proof.png"],
    operatorNote: "real run",
    setFields: {
      decision_node_loss: "0",
      release_refs_traceable: "true",
    },
  }, "2026-03-11T14:00:00Z");

  assert.equal(sample.status, "passed");
  assert.equal(sample.success_boolean, true);
  assert.deepEqual(sample.evidence_refs, ["build/reports/proof.png"]);
  assert.equal(sample.decision_node_loss, 0);
  assert.equal(sample.release_refs_traceable, true);
  assert.equal(updated.status, "executed");
});

run("XT-W3-33 require-real report carries refreshed F/G shadow statuses when provided", () => {
  const report = buildRequireRealReport(makeBundle([
    baseSample({ sample_id: "xt_w3_33_rr_05" }),
  ]), {
    shadowStatuses: {
      f: "candidate_pass_runtime_output_wired",
      g: "candidate_pass_runtime_digest_rollup_wired",
    },
  });

  assert.equal(report.shadow_checklist[0].current_status, "candidate_pass_runtime_output_wired");
  assert.equal(report.shadow_checklist[1].current_status, "candidate_pass_runtime_digest_rollup_wired");
  assert.equal(report.gate_readiness["XT-SDK-G5"], "candidate_pass(runtime_output_wired)");
  assert.equal(report.gate_readiness["XT-SDK-G6"], "candidate_pass(runtime_digest_rollup_wired)");
});
