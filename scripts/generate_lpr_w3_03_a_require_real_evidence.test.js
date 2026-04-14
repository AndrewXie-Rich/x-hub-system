#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildRequireRealEvidence,
  PREREQUISITE_EVIDENCE,
} = require("./generate_lpr_w3_03_a_require_real_evidence.js");
const {
  buildDefaultCaptureBundle,
} = require("./lpr_w3_03_require_real_bundle_lib.js");
const {
  updateBundle,
} = require("./update_lpr_w3_03_require_real_capture_bundle.js");

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
    schema_version: "xhub.lpr_w3_03_require_real_capture_bundle.v1",
    generated_at: "2026-03-15T12:00:00Z",
    status: "ready_for_execution",
    stop_on_first_defect: true,
    execution_order: samples.map((sample) => sample.sample_id),
    samples,
  };
}

function prerequisitePresence(allPresent = true) {
  const out = {};
  for (const item of PREREQUISITE_EVIDENCE) {
    out[item.path] = allPresent;
  }
  return out;
}

function baseSample(overrides = {}) {
  return {
    sample_id: "lpr_rr_sample",
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

run("LPR-W3-03 require-real report stays NO_GO when samples are pending", () => {
  const report = buildRequireRealEvidence(makeBundle([
    baseSample({
      sample_id: "lpr_rr_01",
      required_checks: [{ field: "vector_count", min: 1 }],
    }),
  ]), {
    generatedAt: "2026-03-15T12:30:00Z",
    prerequisitePresence: prerequisitePresence(true),
  });

  assert.equal(report.gate_verdict, "NO_GO(require_real_samples_pending)");
  assert.deepEqual(report.machine_decision.pending_samples, ["lpr_rr_01"]);
  assert.equal(report.release_stance, "no_go");
});

run("LPR-W3-03 require-real report surfaces sample1 blockers and recommended action from probes", () => {
  const report = buildRequireRealEvidence(makeBundle([
    baseSample({
      sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
      required_checks: [{ field: "vector_count", min: 1 }],
    }),
  ]), {
    generatedAt: "2026-03-15T12:31:00Z",
    prerequisitePresence: prerequisitePresence(true),
    runtimeProbe: {
      current_best_candidate: {
        runtime_id: "lmstudio_cpython311_combo_transformers",
        verdict: "sample1_blocked_by_model_format",
        blocker_reason: "unsupported_quantization_config",
        summary: "runtime 已 ready，但当前本机 embedding 模型目录对 torch/transformers 原生加载不兼容。",
      },
    },
    modelProbe: {
      runtime_resolution: {
        selected_runtime_id: "lmstudio_cpython311_combo_transformers",
      },
      summary: {
        discovered_embedding_candidates: 1,
        native_loadable_embedding_candidates: 0,
        partially_loadable_embedding_candidates: 1,
        best_native_candidate_model_path: "",
        primary_blocker:
          "current_embedding_dirs_not_torch_transformers_native_loadable(unsupported_quantization_config)",
        recommended_next_step:
          "source_one_native_torch_transformers_loadable_real_embedding_model_dir_or_restore_lmstudio_helper_daemon_then_rerun_sample1",
      },
    },
    helperProbe: {
      summary: {
        helper_binary_found: true,
        daemon_probe_before: "helper_local_service_disabled",
        daemon_probe_after: "helper_local_service_disabled",
        server_models_endpoint_ok: false,
        primary_blocker:
          "helper_local_service_disabled_before_probe;server_port_1234_not_reachable",
        recommended_next_step:
          "enable_lm_studio_local_service_or_complete_first_launch_then_rerun_helper_bridge_probe",
        lmstudio_environment: {
          enable_local_service: false,
        },
      },
    },
    candidateShortlist: {
      scan_roots: [
        { path: "/models", present: true },
        { path: "/Users/demo/Downloads", present: true },
      ],
    },
    candidateShortlistWide: {
      scan_profile: "default_roots_plus_common_user_roots",
      scan_roots: [
        { path: "/models", present: true },
        { path: "/Users/demo/Downloads", present: true },
        { path: "/Users/demo/Desktop", present: true },
      ],
    },
    helperLocalServiceRecovery: {
      current_machine_state: {
        enable_local_service: false,
        primary_blocker: "helper_local_service_disabled_before_probe",
      },
      helper_route_contract: {
        helper_route_ready_verdict:
          "NO_GO(helper_bridge_not_ready_for_secondary_reference_route)",
      },
      top_recommended_action: {
        action_id: "enable_lm_studio_local_service",
        action_summary: "Turn local service on first.",
        next_step: "turn_on_local_service_then_rerun_helper_probe",
      },
    },
    candidateAcceptance: {
      current_machine_state: {
        runtime_ready: true,
        search_outcome: "searched_no_pass_candidate",
        blocker_class: "current_embedding_dirs_incompatible_with_native_transformers_load",
        top_recommended_action: {
          action_id: "source_or_import_different_native_embedding_model_dir",
          action_summary: "Need a different native dir.",
          next_step: "source_non_quantized_native_embedding_dir_then_rerun_shortlist",
        },
      },
      acceptance_contract: {
        expected_provider: "transformers",
        expected_task_kind: "embedding",
        accepted_task_kind_statuses: ["confirmed_by_local_metadata"],
        required_gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
        required_loadability_verdict: "native_loadable",
      },
      current_no_go_example: {
        normalized_model_dir: "/models/quantized-embed",
        loadability_blocker: "unsupported_quantization_config",
      },
      artifact_refs: {
        shortlist_report: "build/reports/lpr_w3_03_sample1_candidate_shortlist.v1.json",
      },
    },
    candidateRegistration: {
      requested_model_path: "/models/quantized-embed",
      normalized_model_dir: "/models/quantized-embed",
      acceptance_contract: {
        required_gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
        required_loadability_verdict: "native_loadable",
        expected_provider: "transformers",
        expected_task_kind: "embedding",
      },
      candidate_validation: {
        gate_verdict: "NO_GO(sample1_candidate_validation_failed_closed)",
        loadability_blocker: "unsupported_quantization_config",
      },
      proposed_catalog_entry_payload: {
        id: "hf-embed-qwen",
        name: "Qwen Embed",
        backend: "transformers",
        modelPath: "/models/quantized-embed",
        taskKinds: ["embedding"],
      },
      target_catalog_paths: [
        {
          catalog_path: "/catalog/models_catalog.json",
          present: true,
          exact_model_dir_registered: false,
          proposed_model_id_conflict: false,
          recommended_action: "do_not_write_before_validator_pass",
        },
      ],
      catalog_patch_plan_summary: {
        artifact_ref: "build/reports/lpr_w3_03_sample1_candidate_catalog_patch_plan.v1.json",
        manual_patch_scope:
          "choose_one_target_runtime_base_and_keep_models_catalog_and_models_state_in_sync",
        manual_patch_allowed_now: false,
        blocked_reason: "validator_not_pass",
        eligible_target_base_count: 0,
        blocked_target_base_count: 1,
      },
      machine_decision: {
        catalog_write_allowed_now: false,
        validation_pass_required_before_catalog_write: true,
        already_registered_in_catalog: false,
        top_recommended_action: {
          action_id: "source_different_native_embedding_model_dir",
          action_summary: "This dir is not sample1-ready.",
          next_step: "source_native_dir",
        },
      },
    },
  });

  assert.equal(report.gate_verdict, "NO_GO(require_real_samples_pending)");
  assert.deepEqual(report.machine_decision.sample1_current_blockers, [
    "unsupported_quantization_config",
    "current_embedding_dirs_not_torch_transformers_native_loadable(unsupported_quantization_config)",
    "helper_local_service_disabled_before_probe;server_port_1234_not_reachable",
  ]);
  assert.equal(report.machine_decision.sample1_execution_ready, false);
  assert.equal(
    report.machine_decision.sample1_overall_recommended_action_id,
    "source_native_loadable_embedding_model_dir"
  );
  assert.equal(report.machine_decision.sample1_operator_handoff_state, "blocked");
  assert.equal(
    report.machine_decision.sample1_operator_handoff_blocker_class,
    "current_embedding_dirs_incompatible_with_native_transformers_load"
  );
  assert.equal(report.machine_decision.sample1_preferred_route.ready, false);
  assert.equal(report.machine_decision.sample1_candidate_acceptance_present, true);
  assert.equal(
    report.machine_decision.sample1_candidate_acceptance.acceptance_contract.required_gate_verdict,
    "PASS(sample1_candidate_native_loadable_for_real_execution)"
  );
  assert.equal(
    report.machine_decision.sample1_candidate_acceptance.current_no_go_example.loadability_blocker,
    "unsupported_quantization_config"
  );
  assert.equal(
    report.sample1_require_real_support.operator_handoff.top_recommended_action.action_id,
    "source_native_loadable_embedding_model_dir"
  );
  assert.deepEqual(report.sample1_require_real_support.operator_handoff.checked_sources.scan_roots, [
    { path: "/models", present: true },
    { path: "/Users/demo/Downloads", present: true },
    { path: "/Users/demo/Desktop", present: true },
  ]);
  assert.equal(
    report.sample1_require_real_support.helper_local_service_recovery_packet.top_recommended_action.action_id,
    "enable_lm_studio_local_service"
  );
  assert.equal(
    report.sample1_require_real_support.candidate_acceptance_packet.acceptance_contract.required_loadability_verdict,
    "native_loadable"
  );
  assert.equal(report.machine_decision.sample1_candidate_registration_present, true);
  assert.equal(
    report.machine_decision.sample1_candidate_registration.machine_decision.catalog_write_allowed_now,
    false
  );
  assert.equal(
    report.machine_decision.sample1_candidate_registration.candidate_validation.gate_verdict,
    "NO_GO(sample1_candidate_validation_failed_closed)"
  );
  assert.equal(
    report.machine_decision.sample1_candidate_registration.catalog_patch_plan_summary.blocked_reason,
    "validator_not_pass"
  );
  assert.ok(
    report.verdict_reason.includes("recommended_action=source_native_loadable_embedding_model_dir")
  );
  assert.ok(
    report.verdict_reason.includes("registration_action=source_different_native_embedding_model_dir")
  );
  assert.ok(
    report.next_required_artifacts.includes(
      "sample1 primary route next step: source_one_native_torch_transformers_loadable_real_embedding_model_dir_or_restore_lmstudio_helper_daemon_then_rerun_sample1"
    )
  );
  assert.ok(
    report.next_required_artifacts.includes(
      "sample1 helper local-service action: enable_lm_studio_local_service"
    )
  );
  assert.ok(
    report.next_required_artifacts.includes(
      "sample1 helper local-service gate: NO_GO(helper_bridge_not_ready_for_secondary_reference_route)"
    )
  );
  assert.ok(
    report.next_required_artifacts.includes(
      "sample1 candidate acceptance gate: PASS(sample1_candidate_native_loadable_for_real_execution)"
    )
  );
  assert.ok(
    report.next_required_artifacts.includes(
      "sample1 candidate registration action: source_different_native_embedding_model_dir"
    )
  );
  assert.ok(
    report.next_required_artifacts.includes(
      "sample1 candidate registration gate: NO_GO(sample1_candidate_validation_failed_closed)"
    )
  );
  assert.ok(
    report.next_required_artifacts.includes(
      "sample1 candidate catalog patch plan blocked reason: validator_not_pass"
    )
  );
  assert.ok(report.evidence_refs.includes("build/reports/lpr_w3_03_b_runtime_candidate_probe.v1.json"));
  assert.ok(report.evidence_refs.includes("build/reports/lpr_w3_03_c_model_native_loadability_probe.v1.json"));
  assert.ok(report.evidence_refs.includes("build/reports/lpr_w3_03_d_helper_bridge_probe.v1.json"));
  assert.ok(report.evidence_refs.includes("build/reports/lpr_w3_03_sample1_helper_local_service_recovery.v1.json"));
  assert.ok(report.evidence_refs.includes("build/reports/lpr_w3_03_sample1_candidate_acceptance.v1.json"));
  assert.ok(report.evidence_refs.includes("build/reports/lpr_w3_03_sample1_candidate_registration_packet.v1.json"));
  assert.ok(report.evidence_refs.includes("build/reports/lpr_w3_03_sample1_candidate_catalog_patch_plan.v1.json"));
});

run("LPR-W3-03 require-real report marks sample1 execution ready when a native candidate is available", () => {
  const report = buildRequireRealEvidence(makeBundle([
    baseSample({
      sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
    }),
  ]), {
    prerequisitePresence: prerequisitePresence(true),
    runtimeProbe: {
      verdict: "sample1_fail_closed",
      blocker_reason: "",
    },
    modelProbe: {
      selected_runtime_id: "lmstudio_cpython311_combo_transformers",
      discovered_embedding_candidates: 2,
      native_loadable_embedding_candidates: 1,
      partially_loadable_embedding_candidates: 1,
      best_native_candidate_model_path: "/models/native-embed",
      primary_blocker: "",
      recommended_next_step: "use_best_native_loadable_embedding_dir_for_lpr_rr_01",
    },
    helperProbe: {
      helper_binary_found: true,
      server_models_endpoint_ok: true,
      daemon_probe_after: "helper_bridge_ready",
      primary_blocker: "",
      recommended_next_step: "",
      lmstudio_environment: {
        enable_local_service: true,
      },
    },
    candidateShortlist: {
      summary: {
        search_outcome: "ready_candidate_found",
        candidates_considered: 1,
      },
      candidates: [
        {
          normalized_model_dir: "/models/native-embed",
          candidate_validation: {
            gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
            candidate_usable_for_sample1: true,
          },
        },
      ],
    },
    candidateAcceptance: {
      current_machine_state: {
        runtime_ready: true,
        search_outcome: "ready_candidate_found",
        handoff_state: "ready_to_execute",
        blocker_class: "native_route_ready",
        top_recommended_action: {
          action_id: "use_best_shortlisted_candidate_for_sample1",
        },
      },
      acceptance_contract: {
        required_gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
      },
    },
    candidateRegistration: {
      normalized_model_dir: "/models/native-embed",
      candidate_validation: {
        gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
      },
      machine_decision: {
        catalog_write_allowed_now: true,
        top_recommended_action: {
          action_id: "append_proposed_catalog_entry_after_validator_pass",
        },
      },
      catalog_patch_plan_summary: {
        blocked_reason: "",
      },
    },
  });

  assert.equal(report.machine_decision.sample1_execution_ready, true);
  assert.equal(
    report.machine_decision.sample1_overall_recommended_action_id,
    "run_sample1_with_best_native_embedding_dir"
  );
  assert.equal(report.machine_decision.sample1_operator_handoff_state, "ready_to_execute");
  assert.equal(report.machine_decision.sample1_preferred_route.ready, true);
  assert.equal(report.machine_decision.sample1_preferred_route.best_model_path, "/models/native-embed");
  assert.ok(
    report.next_required_artifacts.includes("sample1 recommended action: run_sample1_with_best_native_embedding_dir")
  );
});

run("LPR-W3-03 require-real report reflects helper local-service disabled as a blocker summary", () => {
  const report = buildRequireRealEvidence(makeBundle([
    baseSample({
      sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
    }),
  ]), {
    prerequisitePresence: prerequisitePresence(true),
    runtimeProbe: {
      verdict: "sample1_fail_closed",
      blocker_reason: "",
    },
    modelProbe: {
      selected_runtime_id: "lmstudio_cpython311_combo_transformers",
      discovered_embedding_candidates: 0,
      native_loadable_embedding_candidates: 0,
      partially_loadable_embedding_candidates: 0,
      best_native_candidate_model_path: "",
      primary_blocker: "no_native_loadable_embedding_candidate_discovered",
      recommended_next_step: "source_real_native_embedding_dir_then_rerun_sample1",
    },
    helperProbe: {
      helper_binary_found: true,
      server_models_endpoint_ok: false,
      daemon_probe_after: "helper_local_service_disabled",
      primary_blocker: "helper_local_service_disabled_before_probe",
      recommended_next_step:
        "enable_lm_studio_local_service_or_complete_first_launch_then_rerun_helper_bridge_probe",
      lmstudio_environment: {
        enable_local_service: false,
      },
    },
    candidateShortlist: null,
    candidateShortlistWide: null,
    candidateAcceptance: null,
    candidateRegistration: null,
  });

  assert.equal(
    report.machine_decision.sample1_overall_recommended_action_id,
    "prefer_native_dir_over_helper_settings"
  );
  assert.ok(report.machine_decision.sample1_current_blockers.includes("helper_local_service_disabled_before_probe"));
  assert.ok(report.verdict_reason.includes("helper_local_service_disabled_before_probe"));
  assert.ok(
    report.next_required_artifacts.includes(
      "sample1 secondary route next step: enable_lm_studio_local_service_or_complete_first_launch_then_rerun_helper_bridge_probe"
    )
  );
});

run("LPR-W3-03 default capture bundle seeds the four canonical real samples in execution order", () => {
  const bundle = buildDefaultCaptureBundle({ generatedAt: "2026-03-20T12:00:00Z" });
  assert.equal(bundle.schema_version, "xhub.lpr_w3_03_require_real_capture_bundle.v1");
  assert.deepEqual(bundle.execution_order, [
    "lpr_rr_01_embedding_real_model_dir_executes",
    "lpr_rr_02_asr_real_model_dir_executes",
    "lpr_rr_03_vision_real_model_dir_exercised",
    "lpr_rr_04_doctor_and_release_export_match_real_runs",
  ]);
  assert.equal(bundle.samples.length, 4);
  assert.equal(bundle.samples[0].status, "pending");
  assert.equal(bundle.samples[0].success_boolean, null);
  assert.deepEqual(bundle.samples[0].evidence_refs, []);
});

run("LPR-W3-03 require-real report rejects synthetic evidence even if sample says passed", () => {
  const report = buildRequireRealEvidence(makeBundle([
    baseSample({
      sample_id: "lpr_rr_02",
      status: "passed",
      performed_at: "2026-03-15T13:00:00Z",
      success_boolean: true,
      evidence_refs: ["build/reports/proof.png"],
      synthetic_runtime_evidence: true,
      required_checks: [{ field: "task_kind", equals: "embedding" }],
      task_kind: "embedding",
    }),
  ]), {
    prerequisitePresence: prerequisitePresence(true),
  });

  assert.equal(report.gate_verdict, "NO_GO(synthetic_runtime_evidence_not_accepted)");
  assert.deepEqual(report.machine_decision.synthetic_samples, ["lpr_rr_02"]);
});

run("LPR-W3-03 require-real report fails closed when prerequisite evidence is missing", () => {
  const presence = prerequisitePresence(true);
  presence["build/reports/lpr_w3_07_c_monitor_export_evidence.v1.json"] = false;

  const report = buildRequireRealEvidence(makeBundle([
    baseSample({
      sample_id: "lpr_rr_03",
      status: "passed",
      performed_at: "2026-03-15T13:10:00Z",
      success_boolean: true,
      evidence_refs: ["build/reports/proof.png"],
      task_kind: "embedding",
      provider: "transformers",
      model_id: "transformers/test-embed",
      model_path: "/tmp/model",
      device_id: "xt-01",
      route_source: "device_override",
      load_profile_hash: "hash-1",
      input_artifact_ref: "build/reports/input.txt",
      vector_count: 3,
      monitor_snapshot_captured: true,
      diagnostics_export_captured: true,
      required_checks: [
        { field: "task_kind", equals: "embedding" },
        { field: "vector_count", min: 1 },
      ],
    }),
  ]), {
    prerequisitePresence: presence,
  });

  assert.equal(report.gate_verdict, "NO_GO(prerequisite_evidence_missing)");
  assert.ok(report.machine_decision.missing_prerequisite_evidence.includes("build/reports/lpr_w3_07_c_monitor_export_evidence.v1.json"));
});

run("LPR-W3-03 require-real report passes only when all samples are real and checks hold", () => {
  const report = buildRequireRealEvidence(makeBundle([
    baseSample({
      sample_id: "lpr_rr_04",
      status: "passed",
      performed_at: "2026-03-15T13:20:00Z",
      success_boolean: true,
      evidence_refs: ["build/reports/proof.png"],
      task_kind: "vision_understand",
      provider: "transformers",
      model_id: "transformers/test-vision",
      model_path: "/tmp/model",
      device_id: "xt-02",
      route_source: "hub_default",
      input_artifact_ref: "build/reports/image.png",
      outcome_kind: "fail_closed",
      outcome_summary: "real_runtime_returned_precise_reason",
      real_runtime_touched: true,
      monitor_snapshot_captured: true,
      diagnostics_export_captured: true,
      required_checks: [
        { field: "task_kind", equals: "vision_understand" },
        { field: "outcome_kind", one_of: ["ran", "fail_closed"] },
        { field: "real_runtime_touched", equals: true },
      ],
    }),
  ]), {
    prerequisitePresence: prerequisitePresence(true),
  });

  assert.equal(report.gate_verdict, "PASS(local_provider_runtime_require_real_samples_executed_and_verified)");
  assert.equal(report.machine_decision.all_samples_passed, true);
  assert.equal(report.release_stance, "candidate_go");
});

run("LPR-W3-03 capture bundle updater dedupes refs and marks executed samples", () => {
  const bundle = makeBundle([
    baseSample({ sample_id: "lpr_rr_05" }),
  ]);

  const { bundle: updated, sample } = updateBundle(bundle, {
    sampleId: "lpr_rr_05",
    status: "passed",
    success: true,
    performedAt: "2026-03-15T14:00:00Z",
    evidenceRefs: ["build/reports/proof.png", "build/reports/proof.png"],
    operatorNote: "real run",
    setFields: {
      covered_task_kinds: "[\"embedding\",\"speech_to_text\",\"vision_understand\"]",
      runtime_truth_shared: "true",
    },
  }, "2026-03-15T14:00:00Z");

  assert.equal(sample.status, "passed");
  assert.equal(sample.success_boolean, true);
  assert.deepEqual(sample.evidence_refs, ["build/reports/proof.png"]);
  assert.deepEqual(sample.covered_task_kinds, ["embedding", "speech_to_text", "vision_understand"]);
  assert.equal(sample.runtime_truth_shared, true);
  assert.equal(updated.status, "executed");
});
