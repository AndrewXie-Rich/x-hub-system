#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildHumanLines,
  buildSample1OperatorHandoff,
  buildSample1UnblockSummary,
  compactQAContext,
  helperRouteReady,
} = require("./lpr_w3_03_require_real_status.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("helperRouteReady only turns true when helper is actually ready", () => {
  assert.equal(
    helperRouteReady({
      helper_binary_found: true,
      server_models_endpoint_ok: true,
      daemon_probe_after: "helper_bridge_ready",
    }),
    true
  );
  assert.equal(
    helperRouteReady({
      helper_binary_found: true,
      server_models_endpoint_ok: false,
      daemon_probe_after: "helper_bridge_ready",
    }),
    false
  );
});

run("sample1 unblock summary prefers native model dir when current dirs are unsupported quantized layouts", () => {
  const summary = buildSample1UnblockSummary({
    runtimeProbe: {
      verdict: "sample1_blocked_by_model_format",
      blocker_reason: "unsupported_quantization_config",
    },
    modelProbe: {
      native_loadable_embedding_candidates: 0,
      best_native_candidate_model_path: "",
      primary_blocker:
        "current_embedding_dirs_not_torch_transformers_native_loadable(unsupported_quantization_config)",
      recommended_next_step:
        "source_one_native_torch_transformers_loadable_real_embedding_model_dir_or_restore_lmstudio_helper_daemon_then_rerun_sample1",
    },
    helperProbe: {
      helper_binary_found: true,
      server_models_endpoint_ok: false,
      daemon_probe_after: "helper_local_service_disabled",
      primary_blocker:
        "helper_local_service_disabled_before_probe;server_port_1234_not_reachable",
      recommended_next_step:
        "enable_lm_studio_local_service_or_complete_first_launch_then_rerun_helper_bridge_probe",
      lmstudio_environment: {
        enable_local_service: false,
      },
    },
    sample: {
      sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
    },
  });

  assert.equal(summary.overall_recommended_action_id, "source_native_loadable_embedding_model_dir");
  assert.equal(summary.preferred_route.route_id, "native_embedding_model_dir");
  assert.equal(summary.preferred_route.ready, false);
  assert.equal(summary.secondary_route.route_id, "helper_bridge_reference");
  assert.equal(summary.secondary_route.reference_only, true);
  assert.equal(summary.secondary_route.ready, false);
  assert.ok(
    summary.notes.some((item) =>
      item.includes("Prefer a torch/transformers-native real embedding model dir")
    )
  );
});

run("sample1 unblock summary switches to execution when a native candidate is available", () => {
  const summary = buildSample1UnblockSummary({
    runtimeProbe: {
      verdict: "sample1_fail_closed",
      blocker_reason: "",
    },
    modelProbe: {
      native_loadable_embedding_candidates: 1,
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
    sample: {
      sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
    },
  });

  assert.equal(summary.overall_recommended_action_id, "run_sample1_with_best_native_embedding_dir");
  assert.equal(summary.preferred_route.ready, true);
  assert.equal(summary.execution_ready, true);
  assert.equal(summary.preferred_route.best_model_path, "/models/native-embed");
});

run("sample1 unblock summary prefers PASS candidate registration over stale model-probe blockers", () => {
  const summary = buildSample1UnblockSummary({
    runtimeProbe: {
      verdict: "sample1_blocked_by_model_format",
      blocker_reason: "unsupported_quantization_config",
    },
    modelProbe: {
      native_loadable_embedding_candidates: 0,
      best_native_candidate_model_path: "",
      primary_blocker:
        "current_embedding_dirs_not_torch_transformers_native_loadable(unsupported_quantization_config)",
      recommended_next_step:
        "source_one_native_torch_transformers_loadable_real_embedding_model_dir_or_restore_lmstudio_helper_daemon_then_rerun_sample1",
    },
    helperProbe: {
      helper_binary_found: true,
      server_models_endpoint_ok: false,
      daemon_probe_after: "helper_local_service_disabled",
      primary_blocker:
        "helper_local_service_disabled_before_probe;server_port_1234_not_reachable",
      recommended_next_step:
        "enable_lm_studio_local_service_or_complete_first_launch_then_rerun_helper_bridge_probe",
      lmstudio_environment: {
        enable_local_service: false,
      },
    },
    candidateShortlist: {
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
    candidateRegistration: {
      normalized_model_dir: "/models/native-embed",
      candidate_validation: {
        gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
      },
    },
  });

  assert.equal(summary.execution_ready, true);
  assert.equal(summary.overall_recommended_action_id, "run_sample1_with_best_native_embedding_dir");
  assert.equal(summary.preferred_route.ready, true);
  assert.equal(summary.preferred_route.best_model_path, "/models/native-embed");
  assert.deepEqual(summary.current_blockers, []);
});

run("sample1 unblock summary prioritizes runtime recovery when runtime itself is missing", () => {
  const summary = buildSample1UnblockSummary({
    runtimeProbe: {
      verdict: "sample1_blocked_by_runtime",
      blocker_reason: "missing_runtime",
    },
    modelProbe: {
      native_loadable_embedding_candidates: 0,
      best_native_candidate_model_path: "",
      primary_blocker: "no_ready_transformers_runtime_candidate",
      recommended_next_step: "restore_combo_runtime_or_helper_bridge_before_rerunning_sample1",
    },
    helperProbe: {
      helper_binary_found: false,
      server_models_endpoint_ok: false,
      daemon_probe_after: "",
      primary_blocker: "helper_binary_missing",
      recommended_next_step: "",
    },
  });

  assert.equal(summary.overall_recommended_action_id, "restore_ready_transformers_runtime");
  assert.equal(summary.runtime_ready, false);
  assert.ok(summary.current_blockers.includes("missing_runtime"));
});

run("sample1 operator handoff produces a fail-closed work order when current embedding dirs are incompatible", () => {
  const unblockSummary = buildSample1UnblockSummary({
    runtimeProbe: {
      verdict: "sample1_blocked_by_model_format",
      blocker_reason: "unsupported_quantization_config",
    },
    modelProbe: {
      native_loadable_embedding_candidates: 0,
      best_native_candidate_model_path: "",
      primary_blocker:
        "current_embedding_dirs_not_torch_transformers_native_loadable(unsupported_quantization_config)",
      recommended_next_step:
        "source_one_native_torch_transformers_loadable_real_embedding_model_dir_or_restore_lmstudio_helper_daemon_then_rerun_sample1",
    },
    helperProbe: {
      helper_binary_found: true,
      server_models_endpoint_ok: false,
      daemon_probe_after: "helper_local_service_disabled",
      primary_blocker: "helper_local_service_disabled_before_probe",
      recommended_next_step: "enable_lm_studio_local_service_or_complete_first_launch_then_rerun_helper_bridge_probe",
      lmstudio_environment: {
        enable_local_service: false,
      },
    },
    sample: {
      sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
      what_to_capture: ["真实输入文本工件", "runtime monitor / diagnostics export"],
      machine_readable_fields_to_record: ["provider", "task_kind", "model_path"],
    },
  });

  const handoff = buildSample1OperatorHandoff({
    runtimeProbe: {
      verdict: "sample1_blocked_by_model_format",
      blocker_reason: "unsupported_quantization_config",
    },
    modelProbe: {
      summary: {
        discovered_embedding_candidates: 1,
        native_loadable_embedding_candidates: 0,
      },
      scan_roots: [
        { path: "/models", present: true },
      ],
      catalog_sources: {
        catalog_paths: ["/catalog/models_catalog.json"],
      },
      embedding_candidates: [
        {
          model_path: "/models/qwen-embed",
          model_name_hint: "Qwen Embed",
          task_hint: "embedding",
          discovery_sources: ["scan_root:/models"],
          static_markers: {
            format_assessment: {
              task_hint_sources: ["path_name:qwen-embed"],
            },
          },
          loadability: {
            verdict: "partially_loadable_metadata_only",
            blocker_reason: "unsupported_quantization_config",
            reasons: ["auto_model_failed:quant_method missing"],
          },
          artifact_refs: {
            native_loadability_meta: "build/reports/meta.json",
          },
        },
      ],
    },
    helperProbe: {
      helper_binary_found: true,
      server_models_endpoint_ok: false,
      daemon_probe_after: "helper_local_service_disabled",
    },
    sample: {
      sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
      what_to_capture: ["真实输入文本工件", "runtime monitor / diagnostics export"],
      machine_readable_fields_to_record: ["provider", "task_kind", "model_path"],
    },
    unblockSummary,
    candidateShortlist: {
      scan_roots: [
        { path: "/models", present: true },
        { path: "/Users/demo/Downloads", present: true },
      ],
    },
    helperLocalServiceRecovery: {
      current_machine_state: {
        helper_binary_found: true,
        helper_server_base_url: "http://127.0.0.1:1234",
        daemon_probe_after: "helper_local_service_disabled",
        server_models_endpoint_ok: false,
        settings_path: "/Users/demo/.lmstudio/settings.json",
        enable_local_service: false,
        primary_blocker: "helper_local_service_disabled_before_probe",
        recommended_next_step:
          "enable_lm_studio_local_service_or_complete_first_launch_then_rerun_helper_bridge_probe",
      },
      helper_route_contract: {
        helper_route_role: "secondary_reference_only",
        helper_route_ready_verdict:
          "NO_GO(helper_bridge_not_ready_for_secondary_reference_route)",
        required_ready_signals: ["helper_binary_found=true", "server_models_endpoint_ok=true"],
        reject_signals: [
          {
            signal: "lmstudio_environment.enable_local_service=false",
            reason: "blocked",
          },
        ],
      },
      top_recommended_action: {
        action_id: "enable_lm_studio_local_service",
        action_summary: "Turn local service on first.",
        next_step: "turn_on_local_service_then_rerun_helper_probe",
      },
      operator_workflow: [
        {
          step_id: "refresh_helper_probe",
          allowed_now: true,
          description: "Refresh helper probe.",
          command: "node scripts/generate_lpr_w3_03_d_helper_bridge_probe.js",
        },
      ],
    },
    candidateAcceptance: {
      current_machine_state: {
        runtime_ready: true,
        search_outcome: "searched_no_pass_candidate",
        blocker_class: "current_embedding_dirs_incompatible_with_native_transformers_load",
        candidates_considered: 1,
        filtered_out_task_mismatch_count: 2,
      },
      acceptance_contract: {
        expected_provider: "transformers",
        expected_task_kind: "embedding",
        required_gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
        required_loadability_verdict: "native_loadable",
      },
      current_no_go_example: {
        normalized_model_dir: "/models/qwen-embed",
        gate_verdict: "NO_GO(sample1_candidate_validation_failed_closed)",
        task_kind_status: "confirmed_by_local_metadata",
        loadability_blocker: "unsupported_quantization_config",
      },
      filtered_out_examples: [
        {
          normalized_model_dir: "/models/qwen-text",
          task_kind_status: "mismatch",
          inferred_task_hint: "text_generate",
        },
      ],
    },
    candidateRegistration: {
      requested_model_path: "/models/qwen-embed",
      normalized_model_dir: "/models/qwen-embed",
      acceptance_contract: {
        expected_provider: "transformers",
        expected_task_kind: "embedding",
        required_gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
        required_loadability_verdict: "native_loadable",
      },
      candidate_validation: {
        gate_verdict: "NO_GO(sample1_candidate_validation_failed_closed)",
        loadability_blocker: "unsupported_quantization_config",
      },
      proposed_catalog_entry_payload: {
        id: "hf-embed-qwen",
        name: "Qwen Embed",
        backend: "transformers",
        modelPath: "/models/qwen-embed",
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
      search_recovery_plan: {
        exact_path_known: true,
        exact_path_exists: true,
        exact_path_shortlist_refresh_command:
          "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js \\\n  --task-kind embedding \\\n  --model-path /models/qwen-embed",
        exact_path_validation_command:
          "node scripts/generate_lpr_w3_03_sample1_candidate_validation.js \\\n  --model-path /models/qwen-embed \\\n  --task-kind embedding",
        explicit_model_path_shortlist_command_template:
          "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js \\\n  --task-kind embedding \\\n  --model-path <absolute_model_dir>",
        explicit_model_path_validation_command_template:
          "node scripts/generate_lpr_w3_03_sample1_candidate_validation.js \\\n  --model-path <absolute_model_dir> \\\n  --task-kind embedding",
        wide_shortlist_search_command:
          "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js \\\n  --task-kind embedding \\\n  --wide-common-user-roots",
        custom_scan_root_shortlist_command_template:
          "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js \\\n  --task-kind embedding \\\n  --scan-root <absolute_search_root>",
        preferred_next_step: "refresh_or_widen_machine_readable_search_then_revalidate_exact_path",
      },
      catalog_patch_plan_summary: {
        artifact_ref: "build/reports/lpr_w3_03_sample1_candidate_catalog_patch_plan.v1.json",
        manual_patch_scope:
          "choose_one_target_runtime_base_and_keep_models_catalog_and_models_state_in_sync",
        manual_patch_allowed_now: false,
        blocked_reason: "validator_not_pass",
        eligible_target_base_count: 0,
        blocked_target_base_count: 1,
        target_base_plans: [
          {
            base_dir: "/catalog",
            base_label: "custom_runtime_base",
            patch_allowed_now: false,
            blocked_reasons: ["validator_not_pass"],
            recommended_action: "do_not_patch_base_until_validator_pass",
            files: [
              {
                catalog_path: "/catalog/models_catalog.json",
                file_kind: "models_catalog",
                shape_family: "legacy_minimal",
                target_eligible_now: false,
                blocked_reason: "validator_not_pass",
                model_patch_operation: "blocked_until_validator_pass",
              },
            ],
          },
        ],
      },
      machine_decision: {
        catalog_write_allowed_now: false,
        validation_pass_required_before_catalog_write: true,
        already_registered_in_catalog: false,
        top_recommended_action: {
          action_id: "source_different_native_embedding_model_dir",
          action_summary: "This dir is not sample1-ready.",
        },
      },
    },
  });

  assert.equal(handoff.handoff_state, "blocked");
  assert.equal(
    handoff.blocker_class,
    "current_embedding_dirs_incompatible_with_native_transformers_load"
  );
  assert.equal(handoff.top_recommended_action.action_id, "source_native_loadable_embedding_model_dir");
  assert.equal(handoff.rejected_current_candidates.length, 1);
  assert.ok(
    handoff.operator_steps.some((item) =>
      item.includes("Source or register one real torch/transformers-native embedding model directory")
    )
  );
  assert.ok(
    handoff.operator_steps.some((item) =>
      item.includes("generate_lpr_w3_03_sample1_candidate_acceptance.js")
    )
  );
  assert.ok(
    handoff.operator_steps.some((item) =>
      item.includes("generate_lpr_w3_03_sample1_candidate_registration_packet.js --model-path")
    )
  );
  assert.ok(
    handoff.operator_steps.some((item) =>
      item.includes("generate_lpr_w3_03_sample1_candidate_shortlist.js")
    )
  );
  assert.ok(
    handoff.operator_steps.some((item) =>
      item.includes("generate_lpr_w3_03_sample1_candidate_validation.js --model-path")
    )
  );
  assert.equal(
    handoff.candidate_acceptance.acceptance_contract.required_gate_verdict,
    "PASS(sample1_candidate_native_loadable_for_real_execution)"
  );
  assert.equal(
    handoff.candidate_acceptance.current_machine_state.filtered_out_task_mismatch_count,
    2
  );
  assert.equal(
    handoff.candidate_acceptance.filtered_out_examples[0].normalized_model_dir,
    "/models/qwen-text"
  );
  assert.equal(
    handoff.helper_local_service_recovery.top_recommended_action.action_id,
    "enable_lm_studio_local_service"
  );
  assert.equal(
    handoff.helper_local_service_recovery.helper_route_contract.helper_route_ready_verdict,
    "NO_GO(helper_bridge_not_ready_for_secondary_reference_route)"
  );
  assert.deepEqual(handoff.checked_sources.scan_roots, [
    { path: "/models", present: true },
    { path: "/Users/demo/Downloads", present: true },
  ]);
  assert.equal(
    handoff.candidate_registration.machine_decision.catalog_write_allowed_now,
    false
  );
  assert.equal(
    handoff.candidate_registration.proposed_catalog_entry.id,
    "hf-embed-qwen"
  );
  assert.equal(
    handoff.candidate_registration.catalog_patch_plan_summary.blocked_reason,
    "validator_not_pass"
  );
  assert.equal(handoff.search_recovery.exact_path_known, true);
  assert.equal(
    handoff.search_recovery.wide_shortlist_search_command.includes("--wide-common-user-roots"),
    true
  );
  assert.equal(
    handoff.candidate_registration.search_recovery_plan.exact_path_validation_command.includes("--model-path /models/qwen-embed"),
    true
  );
  assert.ok(
    handoff.command_refs.some((item) =>
      item.includes("generate_lpr_w3_03_sample1_candidate_catalog_patch_plan.js")
    )
  );
  assert.ok(
    handoff.command_refs.some((item) =>
      item.includes("--wide-common-user-roots")
    )
  );
});

run("sample1 operator handoff flips to ready_to_execute when a native candidate is available", () => {
  const unblockSummary = buildSample1UnblockSummary({
    runtimeProbe: {
      verdict: "sample1_fail_closed",
      blocker_reason: "",
    },
    modelProbe: {
      native_loadable_embedding_candidates: 1,
      best_native_candidate_model_path: "/models/native-embed",
      primary_blocker: "",
      recommended_next_step: "use_best_native_loadable_embedding_dir_for_lpr_rr_01",
    },
    helperProbe: {
      helper_binary_found: true,
      server_models_endpoint_ok: true,
      daemon_probe_after: "helper_bridge_ready",
    },
    sample: {
      sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
    },
  });

  const handoff = buildSample1OperatorHandoff({
    runtimeProbe: {
      verdict: "sample1_fail_closed",
      blocker_reason: "",
    },
    modelProbe: {
      summary: {
        discovered_embedding_candidates: 1,
        native_loadable_embedding_candidates: 1,
      },
    },
    helperProbe: {
      helper_binary_found: true,
      server_models_endpoint_ok: true,
      daemon_probe_after: "helper_bridge_ready",
    },
    sample: {
      sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
    },
    unblockSummary,
  });

  assert.equal(handoff.handoff_state, "ready_to_execute");
  assert.equal(handoff.blocker_class, "native_route_ready");
  assert.equal(handoff.route_policy.helper_is_reference_only, true);
});

run("compactQAContext preserves blocker-aware require-real guidance", () => {
  const qa = compactQAContext({
    gate_verdict: "NO_GO(require_real_samples_pending)",
    release_stance: "no_go",
    verdict_reason: "pending real samples",
    next_required_artifacts: [
      "execute real sample: lpr_rr_01_embedding_real_model_dir_executes",
      "sample1 recommended action: source_native_loadable_embedding_model_dir",
      "sample1 recommended action: source_native_loadable_embedding_model_dir",
    ],
    machine_decision: {
      pending_samples: [
        "lpr_rr_01_embedding_real_model_dir_executes",
        "lpr_rr_02_asr_real_model_dir_executes",
      ],
      missing_evidence_samples: ["lpr_rr_01_embedding_real_model_dir_executes"],
      sample1_current_blockers: [
        "unsupported_quantization_config",
        "helper_local_service_disabled_before_probe",
      ],
      sample1_runtime_ready: true,
      sample1_execution_ready: false,
      sample1_overall_recommended_action_id: "source_native_loadable_embedding_model_dir",
      sample1_operator_handoff: {
        handoff_state: "blocked",
        blocker_class: "current_embedding_dirs_incompatible_with_native_transformers_load",
      },
    },
  });

  assert.equal(qa.gate_verdict, "NO_GO(require_real_samples_pending)");
  assert.equal(qa.release_stance, "no_go");
  assert.equal(qa.verdict_reason, "pending real samples");
  assert.deepEqual(qa.next_required_artifacts, [
    "execute real sample: lpr_rr_01_embedding_real_model_dir_executes",
    "sample1 recommended action: source_native_loadable_embedding_model_dir",
  ]);
  assert.deepEqual(qa.machine_decision.pending_samples, [
    "lpr_rr_01_embedding_real_model_dir_executes",
    "lpr_rr_02_asr_real_model_dir_executes",
  ]);
  assert.equal(qa.machine_decision.sample1_runtime_ready, true);
  assert.equal(qa.machine_decision.sample1_execution_ready, false);
  assert.equal(
    qa.machine_decision.sample1_operator_handoff_state,
    "blocked"
  );
  assert.equal(
    qa.machine_decision.sample1_operator_handoff_blocker_class,
    "current_embedding_dirs_incompatible_with_native_transformers_load"
  );
});

run("buildHumanLines surfaces next required artifacts for operator follow-through", () => {
  const lines = buildHumanLines({
    bundle_status: "ready_for_execution",
    qa_gate_verdict: "NO_GO(require_real_samples_pending)",
    qa_release_stance: "no_go",
    qa_verdict_reason: "pending real samples",
    qa_next_required_artifacts: [
      "execute real sample: lpr_rr_01_embedding_real_model_dir_executes",
      "sample1 recommended action: source_native_loadable_embedding_model_dir",
    ],
    qa_machine_decision: {
      sample1_current_blockers: [
        "unsupported_quantization_config",
      ],
    },
    executed_count: 0,
    total_samples: 4,
    passed_count: 0,
    failed_count: 0,
    pending_count: 4,
    next_pending_sample: null,
  });

  assert.ok(lines.includes("next_required_artifacts:"));
  assert.ok(
    lines.includes("  - execute real sample: lpr_rr_01_embedding_real_model_dir_executes")
  );
  assert.ok(
    lines.includes("  - sample1 recommended action: source_native_loadable_embedding_model_dir")
  );
  assert.ok(lines.includes("qa_sample1_current_blockers:"));
  assert.ok(lines.includes("  - unsupported_quantization_config"));
});
