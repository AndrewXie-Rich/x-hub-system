#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildRequireRealReport,
} = require("./generate_xt_w3_24_n_whatsapp_cloud_require_real_report.js");
const {
  updateBundle,
} = require("./update_xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.js");

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
    schema_version: "xhub.xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.v1",
    generated_at: "2026-03-13T00:00:00Z",
    status: "ready_for_execution",
    stop_on_first_defect: true,
    execution_order: samples.map((sample) => sample.sample_id),
    samples,
  };
}

function baseSample(overrides = {}) {
  return {
    sample_id: "xt_w3_24_n_rr_sample",
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

run("XT-W3-24-N require-real report stays NO_GO when samples are still pending", () => {
  const report = buildRequireRealReport(makeBundle([
    baseSample({
      sample_id: "xt_w3_24_n_rr_01",
      required_checks: [{ field: "signature_verified", equals: true }],
    }),
  ]), {
    generatedAt: "2026-03-13T00:30:00Z",
  });

  assert.equal(report.gate_verdict, "NO_GO(require_real_samples_pending)");
  assert.deepEqual(report.machine_decision.pending_samples, ["xt_w3_24_n_rr_01"]);
  assert.equal(report.release_stance, "no_go");
  assert.equal(report.channel_release_freeze[0].release_stage_current, "p1_release_blocked_require_real_pending");
});

run("XT-W3-24-N require-real report rejects synthetic evidence even if sample says passed", () => {
  const report = buildRequireRealReport(makeBundle([
    baseSample({
      sample_id: "xt_w3_24_n_rr_02",
      status: "passed",
      performed_at: "2026-03-13T01:00:00Z",
      success_boolean: true,
      evidence_refs: ["build/reports/proof.png"],
      synthetic_runtime_evidence: true,
      required_checks: [{ field: "signature_verified", equals: true }],
      signature_verified: true,
    }),
  ]));

  assert.equal(report.gate_verdict, "NO_GO(synthetic_runtime_evidence_not_accepted)");
  assert.deepEqual(report.machine_decision.synthetic_samples, ["xt_w3_24_n_rr_02"]);
});

run("XT-W3-24-N require-real report passes only when all samples are real and checks hold", () => {
  const report = buildRequireRealReport(makeBundle([
    baseSample({
      sample_id: "xt_w3_24_n_rr_03",
      status: "passed",
      performed_at: "2026-03-13T01:10:00Z",
      success_boolean: true,
      evidence_refs: ["build/reports/proof.png"],
      structured_action_name: "deploy.plan",
      route_mode: "hub_to_xt",
      execution_disposition: "prepared",
      audit_chain_complete: true,
      required_checks: [
        { field: "structured_action_name", equals: "deploy.plan" },
        { field: "route_mode", equals: "hub_to_xt" },
        { field: "execution_disposition", one_of: ["prepared", "queued"] },
        { field: "audit_chain_complete", equals: true },
      ],
    }),
  ]));

  assert.equal(report.gate_verdict, "PASS(whatsapp_cloud_require_real_samples_executed_and_verified)");
  assert.equal(report.machine_decision.all_samples_passed, true);
  assert.equal(report.release_stance, "candidate_go");
  assert.equal(report.channel_release_freeze[1].counted_toward_current_report, false);
});

run("XT-W3-24-N capture bundle updater dedupes refs and marks executed samples", () => {
  const bundle = makeBundle([
    baseSample({ sample_id: "xt_w3_24_n_rr_04" }),
  ]);

  const { bundle: updated, sample } = updateBundle(bundle, {
    sampleId: "xt_w3_24_n_rr_04",
    status: "passed",
    success: true,
    performedAt: "2026-03-13T02:00:00Z",
    evidenceRefs: ["build/reports/proof.png", "build/reports/proof.png"],
    operatorNote: "real run",
    setFields: {
      manual_command_template_present: "true",
      provider_reply_mode: "text_only",
    },
  }, "2026-03-13T02:00:00Z");

  assert.equal(sample.status, "passed");
  assert.equal(sample.success_boolean, true);
  assert.deepEqual(sample.evidence_refs, ["build/reports/proof.png"]);
  assert.equal(sample.manual_command_template_present, true);
  assert.equal(sample.provider_reply_mode, "text_only");
  assert.equal(updated.status, "executed");
});
