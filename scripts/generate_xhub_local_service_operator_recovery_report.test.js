#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildOperatorRecoveryReport,
} = require("./generate_xhub_local_service_operator_recovery_report.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

function makeSummary(overrides = {}) {
  return {
    overall_status: "pass",
    hub_local_service_snapshot_support: {
      hub_local_service_snapshot_smoke_status: "pass",
      hub_local_service_snapshot: {
        primary_issue_reason_code: "xhub_local_service_unreachable",
        doctor_failure_code: "xhub_local_service_unreachable",
        doctor_provider_check_status: "fail",
        provider_id: "transformers",
        service_state: "unreachable",
        runtime_reason_code: "xhub_local_service_unreachable",
        managed_process_state: "down",
        managed_start_attempt_count: 2,
        provider_count: 1,
        ready_provider_count: 0,
      },
    },
    ...overrides,
  };
}

function makeSnapshotEvidence(overrides = {}) {
  return {
    hub_local_service_snapshot: {
      primary_issue: {
        reason_code: "xhub_local_service_unreachable",
        headline: "Hub-managed local service is unreachable",
        message: "Providers are pinned to xhub_local_service, but Hub cannot reach /health at http://127.0.0.1:50171.",
        next_step: "Inspect the managed service snapshot before retrying startup or routing live traffic.",
      },
      doctor_projection: {
        current_failure_code: "xhub_local_service_unreachable",
        provider_check_status: "fail",
        repair_destination_ref: "hub://settings/diagnostics",
      },
      provider_count: 1,
      ready_provider_count: 0,
      providers: [
        {
          provider_id: "transformers",
          service_state: "unreachable",
          runtime_reason_code: "xhub_local_service_unreachable",
          service_base_url: "http://127.0.0.1:50171",
          execution_mode: "xhub_local_service",
          managed_service_state: {
            processState: "down",
            startAttemptCount: 2,
            lastStartError: "spawn_exit_1",
            lastProbeError: "ConnectionRefusedError:[Errno 61] Connection refused",
          },
        },
      ],
    },
    ...overrides,
  };
}

function makeRecoveryGuidance(overrides = {}) {
  return {
    guidance_present: true,
    current_failure_code: "xhub_local_service_unreachable",
    current_failure_issue: "provider_readiness",
    provider_check_status: "fail",
    provider_check_blocking: true,
    action_category: "inspect_snapshot_before_retry",
    severity: "high",
    install_hint: "Inspect the managed service snapshot before retrying startup or routing live traffic.",
    repair_destination_ref: "hub://settings/diagnostics",
    service_base_url: "http://127.0.0.1:50171",
    managed_process_state: "down",
    managed_start_attempt_count: 2,
    managed_last_start_error: "spawn_exit_1",
    blocked_capabilities: ["ai.embed.local"],
    primary_issue: {
      reason_code: "xhub_local_service_unreachable",
      headline: "Hub-managed local service is unreachable",
      message: "Providers are pinned to xhub_local_service, but Hub cannot reach /health at http://127.0.0.1:50171.",
      next_step: "Inspect the managed service snapshot before retrying startup or routing live traffic.",
    },
    recommended_actions: [
      {
        rank: 1,
        action_id: "inspect_managed_service_snapshot",
        title: "Inspect managed service snapshot before retry",
        why: "Hub has already attempted startup and the structured snapshot contains the most precise current failure reason.",
        command_or_ref: "Hub Settings -> Diagnostics -> Export unified doctor report",
      },
    ],
    support_faq: [
      {
        faq_id: "why_fail_closed",
        question: "Why is Hub staying fail-closed here?",
        answer: "Because no ready xhub_local_service-backed provider currently satisfies the local task contract.",
      },
    ],
    ...overrides,
  };
}

run("operator recovery report stays conservative on release wording while require-real is pending", () => {
  const report = buildOperatorRecoveryReport({
    generatedAt: "2026-03-22T12:00:00Z",
    sourceGateSummary: makeSummary(),
    snapshotEvidence: makeSnapshotEvidence(),
    requireReal: { release_stance: "no_go" },
  });

  assert.equal(report.gate_verdict, "PASS(operator_recovery_report_generated_from_structured_snapshot_truth)");
  assert.equal(report.release_stance, "no_go");
  assert.equal(report.machine_decision.support_ready, true);
  assert.equal(report.machine_decision.require_real_release_stance, "no_go");
  assert.equal(report.local_service_truth.primary_issue_reason_code, "xhub_local_service_unreachable");
  assert.equal(report.recovery_classification.action_category, "inspect_snapshot_before_retry");
  assert.equal(report.recommended_actions[0].action_id, "inspect_managed_service_snapshot");
  assert.equal(
    report.release_wording.external_status_line.includes("require-real closure reaches candidate_go"),
    true
  );
});

run("operator recovery report exposes require-real sample1 focus when sample1 handoff is present", () => {
  const report = buildOperatorRecoveryReport({
    sourceGateSummary: makeSummary(),
    snapshotEvidence: makeSnapshotEvidence(),
    requireReal: {
      release_stance: "no_go",
      machine_decision: {
        sample1_operator_handoff: {
          handoff_state: "blocked",
          blocker_class: "current_embedding_dirs_incompatible_with_native_transformers_load",
          top_recommended_action: {
            action_id: "source_native_loadable_embedding_model_dir",
            action_summary:
              "Current embedding dirs look like LM Studio / MLX quantized layouts, not torch/transformers-native dirs. Source one native-loadable real embedding model dir first.",
          },
          operator_steps: [
            "Source or register one real torch/transformers-native embedding model directory on this machine.",
          ],
          checked_sources: {
            scan_roots: [
              { path: "/models", present: true },
              { path: "/Users/demo/Downloads", present: true },
            ],
          },
          search_recovery: {
            wide_shortlist_search_command:
              "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js --wide-common-user-roots",
          },
          helper_local_service_recovery: {
            helper_route_contract: {
              helper_route_ready_verdict:
                "NO_GO(helper_bridge_not_ready_for_secondary_reference_route)",
              required_ready_signals: [
                "helper_binary_found=true",
                "lmstudio_environment.enable_local_service=true",
              ],
            },
            top_recommended_action: {
              action_id: "enable_lm_studio_local_service",
              action_summary: "Turn local service on first.",
            },
          },
        },
        sample1_candidate_acceptance: {
          current_machine_state: {
            runtime_ready: true,
            top_recommended_action: {
              action_id: "source_or_import_different_native_embedding_model_dir",
            },
          },
          acceptance_contract: {
            required_gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
            required_loadability_verdict: "native_loadable",
          },
          current_no_go_example: {
            normalized_model_dir: "/models/quantized-embed",
            loadability_blocker: "unsupported_quantization_config",
          },
        },
        sample1_candidate_registration: {
          requested_model_path: "/models/quantized-embed",
          normalized_model_dir: "/models/quantized-embed",
          acceptance_contract: {
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
            modelPath: "/models/quantized-embed",
            taskKinds: ["embedding"],
          },
          machine_decision: {
            catalog_write_allowed_now: false,
            top_recommended_action: {
              action_id: "source_different_native_embedding_model_dir",
              action_summary: "This dir is not sample1-ready.",
            },
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
        },
      },
    },
  });

  assert.equal(report.machine_decision.require_real_focus_present, true);
  assert.equal(
    report.require_real_focus.blocker_class,
    "current_embedding_dirs_incompatible_with_native_transformers_load"
  );
  assert.equal(
    report.require_real_focus.top_recommended_action.action_id,
    "source_native_loadable_embedding_model_dir"
  );
  assert.equal(
    report.require_real_focus.candidate_acceptance.acceptance_contract.required_gate_verdict,
    "PASS(sample1_candidate_native_loadable_for_real_execution)"
  );
  assert.equal(report.machine_decision.require_real_focus_acceptance_present, true);
  assert.equal(report.machine_decision.require_real_focus_registration_present, true);
  assert.equal(
    report.machine_decision.require_real_focus_helper_local_service_recovery_present,
    true
  );
  assert.equal(
    report.require_real_focus.helper_local_service_recovery.top_recommended_action.action_id,
    "enable_lm_studio_local_service"
  );
  assert.deepEqual(report.require_real_focus.checked_sources.scan_roots, [
    { path: "/models", present: true },
    { path: "/Users/demo/Downloads", present: true },
  ]);
  assert.equal(
    report.require_real_focus.search_recovery.wide_shortlist_search_command.includes("--wide-common-user-roots"),
    true
  );
  assert.equal(
    report.require_real_focus.candidate_registration.machine_decision.catalog_write_allowed_now,
    false
  );
  assert.equal(
    report.require_real_focus.candidate_registration.proposed_catalog_entry.id,
    "hf-embed-qwen"
  );
  assert.equal(
    report.require_real_focus.candidate_registration.catalog_patch_plan_summary.blocked_reason,
    "validator_not_pass"
  );
  assert.ok(report.support_faq.some((item) => item.faq_id === "require_real_next_move"));
  assert.ok(report.support_faq.some((item) => item.faq_id === "require_real_acceptance_contract"));
  assert.ok(report.support_faq.some((item) => item.faq_id === "require_real_registration_gate"));
  assert.ok(report.support_faq.some((item) => item.faq_id === "require_real_catalog_patch_plan"));
  assert.ok(report.support_faq.some((item) => item.faq_id === "require_real_helper_route_gate"));
});

run("operator recovery report maps missing config to a concrete config repair action", () => {
  const report = buildOperatorRecoveryReport({
    sourceGateSummary: makeSummary({
      hub_local_service_snapshot_support: {
        hub_local_service_snapshot_smoke_status: "pass",
        hub_local_service_snapshot: {
          primary_issue_reason_code: "xhub_local_service_config_missing",
          doctor_failure_code: "xhub_local_service_config_missing",
          doctor_provider_check_status: "fail",
          provider_id: "transformers",
          service_state: "missing_config",
          runtime_reason_code: "xhub_local_service_config_missing",
          managed_process_state: "unknown",
          managed_start_attempt_count: 0,
          provider_count: 1,
          ready_provider_count: 0,
        },
      },
    }),
    snapshotEvidence: {
      hub_local_service_snapshot: {
        primary_issue: {
          reason_code: "xhub_local_service_config_missing",
          headline: "Hub-managed local service is not configured",
          message: "Providers are pinned to xhub_local_service, but no service base URL is configured.",
          next_step: "Set runtimeRequirements.serviceBaseUrl or XHUB_LOCAL_SERVICE_BASE_URL, then refresh diagnostics.",
        },
        doctor_projection: {
          current_failure_code: "xhub_local_service_config_missing",
          provider_check_status: "fail",
          repair_destination_ref: "hub://settings/diagnostics",
        },
        provider_count: 1,
        ready_provider_count: 0,
        providers: [
          {
            provider_id: "transformers",
            service_state: "missing_config",
            runtime_reason_code: "xhub_local_service_config_missing",
            service_base_url: "",
            execution_mode: "xhub_local_service",
            managed_service_state: {},
          },
        ],
      },
    },
    requireReal: { release_stance: "no_go" },
  });

  assert.equal(report.recovery_classification.action_category, "repair_config");
  assert.equal(report.recommended_actions[0].action_id, "set_loopback_service_base_url");
  assert.equal(
    report.recommended_actions[0].command_or_ref.includes("runtimeRequirements.serviceBaseUrl"),
    true
  );
});

run("operator recovery report prefers structured recovery guidance when present", () => {
  const report = buildOperatorRecoveryReport({
    sourceGateSummary: {
      ...makeSummary(),
      hub_local_service_recovery_guidance_support: {
        hub_local_service_recovery_guidance_smoke_status: "pass",
        hub_local_service_recovery_guidance: {
          action_category: "repair_managed_launch_failure",
          severity: "high",
          install_hint: "Inspect the managed service snapshot and stderr log before retrying startup.",
          top_recommended_action: {
            rank: 1,
            action_id: "inspect_managed_launch_error",
            title: "Inspect managed service launch error",
            command_or_ref: "spawn_exit_1",
          },
          top_support_faq: {
            faq_id: "why_fail_closed",
            question: "Why is Hub staying fail-closed here?",
            answer: "Because no ready xhub_local_service-backed provider currently satisfies the local task contract.",
          },
        },
      },
    },
    snapshotEvidence: makeSnapshotEvidence({
      hub_local_service_recovery_guidance: makeRecoveryGuidance({
        action_category: "repair_managed_launch_failure",
        install_hint: "Inspect the managed service snapshot and stderr log before retrying startup.",
        managed_process_state: "launch_failed",
        recommended_actions: [
          {
            rank: 1,
            action_id: "inspect_managed_launch_error",
            title: "Inspect managed service launch error",
            why: "Hub already attempted a managed launch and the process failed before health became ready.",
            command_or_ref: "spawn_exit_1",
          },
        ],
      }),
    }),
    requireReal: { release_stance: "candidate_go" },
  });

  assert.equal(report.gate_verdict, "PASS(operator_recovery_report_generated_from_structured_snapshot_truth)");
  assert.equal(report.release_stance, "candidate_go");
  assert.equal(report.machine_decision.recovery_guidance_smoke_status, "pass");
  assert.equal(report.machine_decision.recovery_guidance_source, "snapshot_evidence");
  assert.equal(report.recovery_classification.action_category, "repair_managed_launch_failure");
  assert.equal(report.recommended_actions[0].action_id, "inspect_managed_launch_error");
  assert.equal(report.support_faq[0].faq_id, "why_fail_closed");
});

run("operator recovery report appends require-real acceptance FAQ even when structured guidance FAQ exists", () => {
  const report = buildOperatorRecoveryReport({
    sourceGateSummary: {
      ...makeSummary(),
      hub_local_service_recovery_guidance_support: {
        hub_local_service_recovery_guidance_smoke_status: "pass",
        hub_local_service_recovery_guidance: {
          action_category: "repair_managed_launch_failure",
          top_recommended_action: {
            rank: 1,
            action_id: "inspect_managed_launch_error",
            title: "Inspect managed service launch error",
            command_or_ref: "spawn_exit_1",
          },
          top_support_faq: {
            faq_id: "why_fail_closed",
            question: "Why is Hub staying fail-closed here?",
            answer: "Because no ready xhub_local_service-backed provider currently satisfies the local task contract.",
          },
        },
      },
    },
    snapshotEvidence: makeSnapshotEvidence({
      hub_local_service_recovery_guidance: makeRecoveryGuidance(),
    }),
    requireReal: {
      release_stance: "no_go",
      machine_decision: {
        sample1_operator_handoff: {
          handoff_state: "blocked",
          blocker_class: "current_embedding_dirs_incompatible_with_native_transformers_load",
          top_recommended_action: {
            action_id: "source_native_loadable_embedding_model_dir",
            action_summary: "Need a native-loadable embedding dir first.",
          },
        },
        sample1_candidate_acceptance: {
          acceptance_contract: {
            required_gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
            required_loadability_verdict: "native_loadable",
          },
        },
      },
    },
  });

  assert.ok(report.support_faq.some((item) => item.faq_id === "why_fail_closed"));
  assert.ok(report.support_faq.some((item) => item.faq_id === "require_real_next_move"));
  assert.ok(report.support_faq.some((item) => item.faq_id === "require_real_acceptance_contract"));
});

run("operator recovery report fails closed when structured snapshot support is missing", () => {
  const report = buildOperatorRecoveryReport({
    sourceGateSummary: { overall_status: "fail", hub_local_service_snapshot_support: {} },
    snapshotEvidence: null,
    requireReal: null,
  });

  assert.equal(report.gate_verdict, "NO_GO(hub_local_service_snapshot_support_missing)");
  assert.equal(report.machine_decision.support_ready, false);
  assert.equal(report.release_stance, "no_go");
});
