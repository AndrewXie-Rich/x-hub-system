#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildDefaultCaptureBundle,
} = require("./lpr_w3_03_require_real_bundle_lib.js");
const {
  buildW9C5RequireRealClosureEvidence,
  detectReadmePendingSignals,
  parseCapabilityMatrixStatus,
} = require("./generate_w9_c5_require_real_closure_evidence.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("W9-C5 closure evidence stays blocked when require-real samples are still pending", () => {
  const bundle = buildDefaultCaptureBundle({ generatedAt: "2026-03-24T12:00:00Z" });
  const qa = {
    gate_verdict: "NO_GO(require_real_samples_pending)",
    release_stance: "no_go",
  };
  const summary = {
    bundle_status: "ready_for_execution",
    qa_gate_verdict: qa.gate_verdict,
    qa_release_stance: qa.release_stance,
    total_samples: 4,
    executed_count: 0,
    passed_count: 0,
    failed_count: 0,
    pending_count: 4,
    next_pending_sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
    next_pending_sample: {
      prepare_command: "node scripts/prepare_lpr_w3_03_require_real_sample.js --sample-id lpr_rr_01_embedding_real_model_dir_executes",
    },
    qa_machine_decision: {
      pending_samples: [
        "lpr_rr_01_embedding_real_model_dir_executes",
        "lpr_rr_02_asr_real_model_dir_executes",
      ],
      missing_evidence_samples: [
        "lpr_rr_01_embedding_real_model_dir_executes",
      ],
      sample1_runtime_ready: true,
      sample1_execution_ready: false,
      sample1_overall_recommended_action_id: "source_native_loadable_embedding_model_dir",
      sample1_operator_handoff_state: "blocked",
      sample1_operator_handoff_blocker_class: "current_embedding_dirs_incompatible_with_native_transformers_load",
      sample1_current_blockers: [
        "unsupported_quantization_config",
      ],
    },
    qa_next_required_artifacts: [
      "execute real sample: lpr_rr_01_embedding_real_model_dir_executes",
    ],
    sample1_runtime_probe: {
      runtime_id: "lmstudio_cpython311_combo_transformers",
    },
    sample1_model_probe: {
      native_loadable_embedding_candidates: 0,
    },
    sample1_helper_probe: {
      helper_binary_found: true,
      server_models_endpoint_ok: false,
    },
  };

  const report = buildW9C5RequireRealClosureEvidence({
    bundle,
    requireRealEvidence: qa,
    statusSummary: summary,
    readmeText: `
      - with the remaining caveat that require-real smoke is still pending
      - Bench v2 is delivered, but it still needs require-real fixture runs on actual user model directories
    `,
    capabilityMatrixText: "| Local provider runtime | desc | `implementation-in-progress` | note | refs |",
    generatedAt: "2026-03-24T12:05:00Z",
  });

  assert.equal(report.status, "blocked");
  assert.equal(report.closure_verdict.closure_ready, false);
  assert.deepEqual(report.closure_verdict.blockers, [
    "qa_gate=NO_GO(require_real_samples_pending)",
    "readme_still_declares_require_real_pending",
    "capability_matrix_local_provider_runtime_not_elevated",
  ]);
  assert.equal(report.require_real_execution.pending_count, 4);
  assert.equal(report.sample1_focus.execution_ready, false);
  assert.equal(report.governance_posture.readme_require_real_pending, true);
  assert.equal(report.governance_posture.capability_matrix_local_provider_runtime_status, "implementation-in-progress");
  assert.ok(report.next_actions.includes("execute real sample: lpr_rr_01_embedding_real_model_dir_executes"));
});

run("W9-C5 closure evidence turns ready only when QA and release posture both elevate", () => {
  const report = buildW9C5RequireRealClosureEvidence({
    bundle: buildDefaultCaptureBundle({ generatedAt: "2026-03-24T12:10:00Z" }),
    requireRealEvidence: {
      gate_verdict: "GO(require_real_complete)",
      release_stance: "ready",
    },
    statusSummary: {
      bundle_status: "complete",
      qa_gate_verdict: "GO(require_real_complete)",
      qa_release_stance: "ready",
      total_samples: 4,
      executed_count: 4,
      passed_count: 4,
      failed_count: 0,
      pending_count: 0,
      next_pending_sample_id: "",
      next_pending_sample: {},
      qa_machine_decision: {
        pending_samples: [],
        missing_evidence_samples: [],
        sample1_runtime_ready: true,
        sample1_execution_ready: true,
        sample1_overall_recommended_action_id: "",
        sample1_operator_handoff_state: "ready",
        sample1_operator_handoff_blocker_class: "",
        sample1_current_blockers: [],
      },
      qa_next_required_artifacts: [],
      sample1_runtime_probe: {},
      sample1_model_probe: {},
      sample1_helper_probe: {},
    },
    readmeText: "The remaining forward product path is LPR-W4-07 / W4-08 / W4-09.",
    capabilityMatrixText: "| Local provider runtime | desc | `preview-working` | note | refs |",
    generatedAt: "2026-03-24T12:15:00Z",
  });

  assert.equal(report.status, "ready");
  assert.equal(report.closure_verdict.closure_ready, true);
  assert.deepEqual(report.closure_verdict.blockers, []);
  assert.equal(report.governance_posture.readme_require_real_pending, false);
  assert.equal(report.governance_posture.capability_matrix_local_provider_runtime_status, "preview-working");
  assert.equal(report.governance_posture.capability_matrix_allows_elevation, true);
});

run("W9-C5 helpers detect README pending lines and capability-matrix state", () => {
  assert.deepEqual(
    detectReadmePendingSignals(`
      - with the remaining caveat that require-real smoke is still pending
      - Bench v2 is delivered, but it still needs require-real fixture runs on actual user model directories
    `),
    [
      "- with the remaining caveat that require-real smoke is still pending",
      "- Bench v2 is delivered, but it still needs require-real fixture runs on actual user model directories",
    ]
  );
  assert.equal(
    parseCapabilityMatrixStatus("| Local provider runtime | desc | `implementation-in-progress` | note | refs |"),
    "implementation-in-progress"
  );
  assert.deepEqual(
    detectReadmePendingSignals(`
      - LPR-W3-03 require-real closure is now in the ready state, so release credibility no longer depends on old blocker wording
    `),
    []
  );
});
