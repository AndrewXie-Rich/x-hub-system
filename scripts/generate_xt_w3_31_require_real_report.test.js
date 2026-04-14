#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildRequireRealReport,
} = require("./generate_xt_w3_31_require_real_report.js");
const {
  updateBundle,
  applyFromJSONArgs,
} = require("./update_xt_w3_31_require_real_capture_bundle.js");

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
    schema_version: "xhub.xt_w3_31_require_real_capture_bundle.v1",
    generated_at: "2026-03-11T12:00:00Z",
    updated_at: "2026-03-11T12:00:00Z",
    status: "ready_for_execution",
    stop_on_first_defect: true,
    execution_order: samples.map((sample) => sample.sample_id),
    samples,
  };
}

function baseSample(overrides = {}) {
  return {
    sample_id: "xt_spf_rr_sample",
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

run("XT-W3-31 require-real report stays NO_GO when samples are still pending", () => {
  const report = buildRequireRealReport(makeBundle([
    baseSample({
      sample_id: "xt_spf_rr_01",
      required_checks: [{ field: "project_id", not_equals: "" }],
    }),
  ]), {
    generatedAt: "2026-03-11T12:30:00Z",
  });

  assert.equal(report.gate_verdict, "NO_GO(capture_bundle_ready_but_require_real_samples_not_yet_executed)");
  assert.deepEqual(report.machine_decision.pending_samples, ["xt_spf_rr_01"]);
  assert.equal(report.release_stance, "no_go");
});

run("XT-W3-31 require-real report rejects synthetic evidence even if sample says passed", () => {
  const report = buildRequireRealReport(makeBundle([
    baseSample({
      sample_id: "xt_spf_rr_02",
      status: "passed",
      performed_at: "2026-03-11T13:00:00Z",
      success_boolean: true,
      evidence_refs: ["build/reports/screenshot.png"],
      synthetic_runtime_evidence: true,
      required_checks: [{ field: "brief_notification_emitted", equals: true }],
      brief_notification_emitted: true,
    }),
  ]));

  assert.equal(report.gate_verdict, "NO_GO(synthetic_runtime_evidence_not_accepted)");
  assert.deepEqual(report.machine_decision.synthetic_samples, ["xt_spf_rr_02"]);
});

run("XT-W3-31 require-real report passes only when all samples are real and checks hold", () => {
  const report = buildRequireRealReport(makeBundle([
    baseSample({
      sample_id: "xt_spf_rr_03",
      status: "passed",
      performed_at: "2026-03-11T13:10:00Z",
      success_boolean: true,
      evidence_refs: ["build/reports/proof.png"],
      project_id: "proj_alpha",
      jurisdiction_role: "owner",
      observed_result: "visible_in_1600ms",
      first_visible_latency_ms: 1600,
      required_checks: [
        { field: "project_id", not_equals: "" },
        { field: "jurisdiction_role", equals: "owner" },
        { field: "first_visible_latency_ms", max: 3000 },
      ],
    }),
  ]));

  assert.equal(report.gate_verdict, "PASS(require_real_samples_executed_and_verified)");
  assert.equal(report.machine_decision.all_samples_passed, true);
  assert.equal(report.release_stance, "candidate_go");
});

run("XT-W3-31 capture bundle updater dedupes refs and marks executed samples", () => {
  const bundle = makeBundle([
    baseSample({
      sample_id: "xt_spf_rr_04",
      machine_readable_fields_to_record: [
        "project_id",
        "project_state",
        "current_action_cleared",
        "top_blocker_cleared",
        "completed_event_logged",
        "observed_result",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "project_state", equals: "completed" },
        { field: "current_action_cleared", equals: true },
      ],
    }),
  ]);

  const { bundle: updated, sample } = updateBundle(bundle, {
    sampleId: "xt_spf_rr_04",
    status: "passed",
    success: true,
    performedAt: "2026-03-11T14:00:00Z",
    evidenceRefs: ["build/reports/proof.png", "build/reports/proof.png"],
    operatorNote: "real run",
    setFields: {
      project_id: "proj_alpha",
      project_state: "completed",
      current_action_cleared: true,
      top_blocker_cleared: true,
      completed_event_logged: true,
      observed_result: "completed_cleanly",
      evidence_origin: "real_runtime",
      synthetic_runtime_evidence: false,
      synthetic_markers: [],
    },
  }, "2026-03-11T14:00:00Z");

  assert.equal(sample.status, "passed");
  assert.equal(sample.success_boolean, true);
  assert.deepEqual(sample.evidence_refs, ["build/reports/proof.png"]);
  assert.equal(sample.project_state, "completed");
  assert.equal(updated.status, "executed");
});

run("XT-W3-31 capture bundle updater rejects passed samples with missing machine-readable fields", () => {
  const bundle = makeBundle([
    baseSample({
      sample_id: "xt_spf_rr_06",
      machine_readable_fields_to_record: [
        "project_id",
        "evidence_origin",
      ],
      required_checks: [
        { field: "project_id", not_equals: "" },
      ],
    }),
  ]);

  assert.throws(() => updateBundle(bundle, {
    sampleId: "xt_spf_rr_06",
    status: "passed",
    success: true,
    performedAt: "2026-03-11T15:00:00Z",
    evidenceRefs: ["build/reports/proof.png"],
    setFields: {
      project_id: "proj_alpha",
    },
  }, "2026-03-11T15:00:00Z"), /machine_readable_field_missing:evidence_origin/);
});

run("XT-W3-31 capture bundle updater rejects synthetic passed samples", () => {
  const bundle = makeBundle([
    baseSample({
      sample_id: "xt_spf_rr_07",
      machine_readable_fields_to_record: [
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
    }),
  ]);

  assert.throws(() => updateBundle(bundle, {
    sampleId: "xt_spf_rr_07",
    status: "passed",
    success: true,
    performedAt: "2026-03-11T15:30:00Z",
    evidenceRefs: ["build/reports/proof.png"],
    setFields: {
      evidence_origin: "synthetic_fixture",
      synthetic_runtime_evidence: true,
      synthetic_markers: ["fixture"],
    },
  }, "2026-03-11T15:30:00Z"), /synthetic_runtime_evidence_not_accepted/);
});

run("XT-W3-31 updater can hydrate machine-readable fields from --from-json payloads", () => {
  const merged = applyFromJSONArgs({
    sampleId: "xt_spf_rr_08",
    setFields: {
      jurisdiction_role: "owner",
    },
  }, {
    machine_readable_template: {
      project_id: "proj_alpha",
      jurisdiction_role: "observer",
      evidence_origin: "real_runtime",
      synthetic_runtime_evidence: false,
      synthetic_markers: [],
    },
  });

  assert.deepEqual(merged.setFields, {
    project_id: "proj_alpha",
    jurisdiction_role: "owner",
    evidence_origin: "real_runtime",
    synthetic_runtime_evidence: false,
    synthetic_markers: [],
  });
});
