#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildBundleReport,
  buildRefreshSequence,
  resolveEffectiveModelPath,
} = require("./refresh_lpr_w3_03_sample1_candidate_bundle.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("resolveEffectiveModelPath prefers explicit path, then default shortlist, then wide shortlist", () => {
  assert.deepEqual(
    resolveEffectiveModelPath({
      requestedModelPath: "/explicit/model",
      shortlist: {
        candidates: [{ normalized_model_dir: "/default/model" }],
      },
      wideShortlist: {
        candidates: [{ normalized_model_dir: "/wide/model" }],
      },
    }),
    {
      model_path: "/explicit/model",
      source: "explicit_model_path",
    }
  );

  assert.deepEqual(
    resolveEffectiveModelPath({
      shortlist: {
        candidates: [{ normalized_model_dir: "/default/model" }],
      },
      wideShortlist: {
        candidates: [{ normalized_model_dir: "/wide/model" }],
      },
    }),
    {
      model_path: "/default/model",
      source: "default_shortlist_top_candidate",
    }
  );

  assert.deepEqual(
    resolveEffectiveModelPath({
      shortlist: {
        candidates: [],
      },
      wideShortlist: {
        candidates: [{ normalized_model_dir: "/wide/model" }],
      },
    }),
    {
      model_path: "/wide/model",
      source: "wide_shortlist_top_candidate",
    }
  );
});

run("buildRefreshSequence skips wide shortlist when an explicit model path already fixes the candidate", () => {
  const steps = buildRefreshSequence({
    taskKind: "embedding",
    effectiveModelPath: "/models/native-embed",
    effectiveModelPathSource: "explicit_model_path",
    wideCommonUserRoots: true,
    reportsDir: "/tmp/reports",
  });

  assert.deepEqual(
    steps.map((step) => step.step_id),
    [
      "refresh_shortlist_default",
      "refresh_acceptance_bootstrap",
      "refresh_helper_local_service_recovery",
      "refresh_validation",
      "refresh_registration",
      "refresh_handoff_first_pass",
      "refresh_acceptance_final",
      "refresh_handoff_final",
      "refresh_require_real",
    ]
  );
  assert.equal(
    steps.some((step) => step.command.includes("--wide-common-user-roots")),
    false
  );
  assert.equal(
    steps.some((step) => step.command.includes("generate_lpr_w3_03_sample1_candidate_registration_packet.js")),
    true
  );
  assert.equal(
    steps
      .filter((step) => step.step_id === "refresh_shortlist_default" || step.step_id === "refresh_shortlist_wide")
      .every((step) => step.command.includes("--model-path /models/native-embed")),
    true
  );
});

run("buildRefreshSequence keeps wide shortlist when the effective path came from discovery rather than an explicit path", () => {
  const steps = buildRefreshSequence({
    taskKind: "embedding",
    effectiveModelPath: "/models/native-embed",
    effectiveModelPathSource: "default_shortlist_top_candidate",
    wideCommonUserRoots: true,
    reportsDir: "/tmp/reports",
  });

  assert.equal(
    steps.some((step) => step.step_id === "refresh_shortlist_wide"),
    true
  );
});

run("buildBundleReport surfaces blocker-aware summary and patch plan refs", () => {
  const report = buildBundleReport({
    reportsDir: "/tmp/reports",
    requestedModelPath: "",
    effectiveModelPath: "/models/qwen-embed",
    effectiveModelPathSource: "default_shortlist_top_candidate",
    taskKind: "embedding",
    wideCommonUserRoots: true,
    refreshSteps: [
      {
        step_id: "refresh_shortlist_default",
        command: "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js --task-kind embedding",
        output_path: "/tmp/reports/lpr_w3_03_sample1_candidate_shortlist.v1.json",
      },
      {
        step_id: "refresh_require_real",
        command: "node scripts/generate_lpr_w3_03_a_require_real_evidence.js",
        output_path: "/tmp/reports/lpr_w3_03_a_require_real_evidence.v1.json",
      },
    ],
    shortlist: {
      scan_profile: "default_roots_only_or_explicit_custom_roots",
      summary: {
        search_outcome: "searched_no_pass_candidate",
        candidates_considered: 1,
        filtered_out_task_mismatch_count: 4,
      },
      candidates: [
        {
          normalized_model_dir: "/models/qwen-embed",
          candidate_validation: {
            loadability_blocker: "unsupported_quantization_config",
          },
        },
      ],
    },
    wideShortlist: {
      scan_profile: "default_roots_plus_common_user_roots",
    },
    acceptance: {
      current_machine_state: {
        handoff_state: "blocked",
        top_recommended_action: {
          action_id: "source_or_import_different_native_embedding_model_dir",
          next_step: "source_native_model_dir",
        },
      },
    },
    helperLocalServiceRecovery: {
      helper_route_contract: {
        helper_route_ready_verdict:
          "NO_GO(helper_bridge_not_ready_for_secondary_reference_route)",
      },
      top_recommended_action: {
        action_id: "enable_lm_studio_local_service",
        next_step: "turn_on_local_service_then_rerun_helper_probe",
      },
    },
    validation: {
      machine_decision: {
        gate_verdict: "NO_GO(sample1_candidate_validation_failed_closed)",
      },
    },
    registration: {
      candidate_validation: {
        gate_verdict: "NO_GO(sample1_candidate_validation_failed_closed)",
      },
      machine_decision: {
        catalog_write_allowed_now: false,
      },
      catalog_patch_plan_summary: {
        artifact_ref: "build/reports/lpr_w3_03_sample1_candidate_catalog_patch_plan.v1.json",
        blocked_reason: "validator_not_pass",
      },
    },
    handoff: {
      handoff_state: "blocked",
      blocker_class: "current_embedding_dirs_incompatible_with_native_transformers_load",
    },
    requireReal: {
      gate_verdict: "NO_GO(require_real_samples_pending)",
      verdict_reason:
        "sample1_real_embedding_still_blocked_by_current_model_format(unsupported_quantization_config)",
      next_required_artifacts: [
        "sample1 recommended action: source_different_native_embedding_model_dir",
      ],
      machine_decision: {
        sample1_overall_recommended_action_id: "source_different_native_embedding_model_dir",
        sample1_execution_ready: false,
        sample1_current_blockers: [
          "unsupported_quantization_config",
        ],
      },
    },
  });

  assert.equal(report.current_machine_state.handoff_state, "blocked");
  assert.equal(
    report.current_machine_state.helper_route_ready_verdict,
    "NO_GO(helper_bridge_not_ready_for_secondary_reference_route)"
  );
  assert.equal(report.current_machine_state.require_real_gate_verdict, "NO_GO(require_real_samples_pending)");
  assert.equal(report.current_machine_state.registration_catalog_patch_blocked_reason, "validator_not_pass");
  assert.equal(
    report.artifact_refs.helper_local_service_recovery_report,
    "/tmp/reports/lpr_w3_03_sample1_helper_local_service_recovery.v1.json"
  );
  assert.equal(
    report.artifact_refs.candidate_catalog_patch_plan,
    "build/reports/lpr_w3_03_sample1_candidate_catalog_patch_plan.v1.json"
  );
  assert.ok(
    report.next_actions.includes("source_different_native_embedding_model_dir")
  );
  assert.ok(
    report.next_actions.includes("turn_on_local_service_then_rerun_helper_probe")
  );
});
