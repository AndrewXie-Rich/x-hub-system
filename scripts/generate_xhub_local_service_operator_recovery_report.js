#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");
const defaultSourceGateSummaryPath = path.join(
  repoRoot,
  "build/reports/xhub_doctor_source_gate_summary.v1.json"
);
const defaultSnapshotEvidencePath = path.join(
  repoRoot,
  "build/reports/xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json"
);
const defaultRequireRealPath = path.join(
  repoRoot,
  "build/reports/lpr_w3_03_a_require_real_evidence.v1.json"
);
const defaultOutputPath = path.join(
  repoRoot,
  "build/reports/xhub_local_service_operator_recovery_report.v1.json"
);

function isoNow() {
  return new Date().toISOString();
}

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readJSONIfExists(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    return readJSON(filePath);
  } catch {
    return null;
  }
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function normalizeString(value, fallback = "") {
  const trimmed = String(value ?? "").trim();
  return trimmed || fallback;
}

function normalizeInteger(value, fallback = 0) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.max(0, Math.trunc(value));
  }
  const trimmed = String(value ?? "").trim();
  if (/^-?\d+$/.test(trimmed)) {
    return Math.max(0, Number.parseInt(trimmed, 10));
  }
  return fallback;
}

function normalizeArray(value) {
  return Array.isArray(value) ? value : [];
}

function compactRequireRealSample1Handoff(requireReal) {
  if (!requireReal || typeof requireReal !== "object") return null;
  const machineDecision = requireReal.machine_decision || {};
  const support = requireReal.sample1_require_real_support || {};
  const handoff =
    (machineDecision.sample1_operator_handoff && typeof machineDecision.sample1_operator_handoff === "object")
      ? machineDecision.sample1_operator_handoff
      : (support.operator_handoff && typeof support.operator_handoff === "object")
        ? support.operator_handoff
        : null;
  const candidateAcceptance =
    (machineDecision.sample1_candidate_acceptance && typeof machineDecision.sample1_candidate_acceptance === "object")
      ? machineDecision.sample1_candidate_acceptance
      : (handoff && handoff.candidate_acceptance && typeof handoff.candidate_acceptance === "object")
        ? handoff.candidate_acceptance
      : (support.candidate_acceptance_packet && typeof support.candidate_acceptance_packet === "object")
        ? support.candidate_acceptance_packet
        : null;
  const candidateRegistration =
    (machineDecision.sample1_candidate_registration && typeof machineDecision.sample1_candidate_registration === "object")
      ? machineDecision.sample1_candidate_registration
      : (handoff && handoff.candidate_registration && typeof handoff.candidate_registration === "object")
        ? handoff.candidate_registration
      : (support.candidate_registration_packet && typeof support.candidate_registration_packet === "object")
        ? support.candidate_registration_packet
        : null;
  const helperLocalServiceRecovery =
    (handoff && handoff.helper_local_service_recovery && typeof handoff.helper_local_service_recovery === "object")
      ? handoff.helper_local_service_recovery
      : (support.helper_local_service_recovery_packet
        && typeof support.helper_local_service_recovery_packet === "object")
        ? support.helper_local_service_recovery_packet
        : null;
  if (!handoff && !candidateAcceptance && !candidateRegistration && !helperLocalServiceRecovery) return null;

  return {
    handoff_state: normalizeString(handoff?.handoff_state, "unknown"),
    blocker_class: normalizeString(handoff?.blocker_class, "unknown"),
    top_recommended_action: handoff?.top_recommended_action || null,
    route_policy: handoff?.route_policy || null,
    readiness: handoff?.readiness || null,
    checked_sources: handoff?.checked_sources || null,
    search_recovery: handoff?.search_recovery || null,
    rejected_current_candidates: normalizeArray(handoff?.rejected_current_candidates),
    operator_steps: normalizeArray(handoff?.operator_steps),
    capture_requirements: handoff?.capture_requirements || null,
    command_refs: normalizeArray(handoff?.command_refs),
    helper_local_service_recovery: helperLocalServiceRecovery
      ? {
          current_machine_state: helperLocalServiceRecovery.current_machine_state || null,
          helper_route_contract: helperLocalServiceRecovery.helper_route_contract || null,
          top_recommended_action: helperLocalServiceRecovery.top_recommended_action || null,
          operator_workflow: normalizeArray(helperLocalServiceRecovery.operator_workflow),
          artifact_refs: helperLocalServiceRecovery.artifact_refs || null,
        }
      : null,
    candidate_acceptance: candidateAcceptance
      ? {
          current_machine_state: candidateAcceptance.current_machine_state || null,
          acceptance_contract: candidateAcceptance.acceptance_contract
            ? {
                expected_provider: normalizeString(candidateAcceptance.acceptance_contract.expected_provider),
                expected_task_kind: normalizeString(candidateAcceptance.acceptance_contract.expected_task_kind),
                accepted_task_kind_statuses: normalizeArray(
                  candidateAcceptance.acceptance_contract.accepted_task_kind_statuses
                ),
                required_gate_verdict: normalizeString(
                  candidateAcceptance.acceptance_contract.required_gate_verdict
                ),
                required_loadability_verdict: normalizeString(
                  candidateAcceptance.acceptance_contract.required_loadability_verdict
                ),
              }
            : null,
          current_no_go_example: candidateAcceptance.current_no_go_example
            ? {
                normalized_model_dir: normalizeString(
                  candidateAcceptance.current_no_go_example.normalized_model_dir
                ),
                gate_verdict: normalizeString(candidateAcceptance.current_no_go_example.gate_verdict),
                task_kind_status: normalizeString(
                  candidateAcceptance.current_no_go_example.task_kind_status
                ),
                loadability_blocker: normalizeString(
                  candidateAcceptance.current_no_go_example.loadability_blocker
                ),
              }
            : null,
          artifact_refs: candidateAcceptance.artifact_refs || null,
        }
      : null,
    candidate_registration: candidateRegistration
      ? {
          requested_model_path: normalizeString(candidateRegistration.requested_model_path),
          normalized_model_dir: normalizeString(candidateRegistration.normalized_model_dir),
          acceptance_contract: candidateRegistration.acceptance_contract
            ? {
                expected_provider: normalizeString(candidateRegistration.acceptance_contract.expected_provider),
                expected_task_kind: normalizeString(candidateRegistration.acceptance_contract.expected_task_kind),
                required_gate_verdict: normalizeString(
                  candidateRegistration.acceptance_contract.required_gate_verdict
                ),
                required_loadability_verdict: normalizeString(
                  candidateRegistration.acceptance_contract.required_loadability_verdict
                ),
              }
            : null,
          candidate_validation: candidateRegistration.candidate_validation
            ? {
                gate_verdict: normalizeString(candidateRegistration.candidate_validation.gate_verdict),
                loadability_blocker: normalizeString(
                  candidateRegistration.candidate_validation.loadability_blocker
                ),
              }
            : null,
          proposed_catalog_entry: candidateRegistration.proposed_catalog_entry_payload
            ? {
                id: normalizeString(candidateRegistration.proposed_catalog_entry_payload.id),
                name: normalizeString(candidateRegistration.proposed_catalog_entry_payload.name),
                backend: normalizeString(candidateRegistration.proposed_catalog_entry_payload.backend),
                model_path: normalizeString(candidateRegistration.proposed_catalog_entry_payload.modelPath),
                task_kinds: normalizeArray(candidateRegistration.proposed_catalog_entry_payload.taskKinds),
              }
            : null,
          target_catalog_paths: normalizeArray(candidateRegistration.target_catalog_paths).map((item) => ({
            catalog_path: normalizeString(item.catalog_path),
            present: item.present === true,
            exact_model_dir_registered: item.exact_model_dir_registered === true,
            proposed_model_id_conflict: item.proposed_model_id_conflict === true,
            recommended_action: normalizeString(item.recommended_action),
          })),
          catalog_patch_plan_summary: candidateRegistration.catalog_patch_plan_summary
            ? {
                artifact_ref: normalizeString(candidateRegistration.catalog_patch_plan_summary.artifact_ref),
                manual_patch_scope: normalizeString(
                  candidateRegistration.catalog_patch_plan_summary.manual_patch_scope
                ),
                manual_patch_allowed_now:
                  candidateRegistration.catalog_patch_plan_summary.manual_patch_allowed_now === true,
                blocked_reason: normalizeString(
                  candidateRegistration.catalog_patch_plan_summary.blocked_reason
                ),
                eligible_target_base_count: normalizeInteger(
                  candidateRegistration.catalog_patch_plan_summary.eligible_target_base_count
                ),
                blocked_target_base_count: normalizeInteger(
                  candidateRegistration.catalog_patch_plan_summary.blocked_target_base_count
                ),
              }
            : null,
          machine_decision: candidateRegistration.machine_decision
            ? {
                catalog_write_allowed_now:
                  candidateRegistration.machine_decision.catalog_write_allowed_now === true,
                validation_pass_required_before_catalog_write:
                  candidateRegistration.machine_decision.validation_pass_required_before_catalog_write !== false,
                already_registered_in_catalog:
                  candidateRegistration.machine_decision.already_registered_in_catalog === true,
                catalog_patch_plan_required_before_manual_write:
                  candidateRegistration.machine_decision.catalog_patch_plan_required_before_manual_write !== false,
                top_recommended_action: candidateRegistration.machine_decision.top_recommended_action || null,
              }
            : null,
        }
      : null,
  };
}

function compactRecoveryAction(value, fallbackRank = 1) {
  if (!value || typeof value !== "object") return null;
  const actionID = normalizeString(value.action_id || value.actionID, "");
  const title = normalizeString(value.title, "");
  const commandOrReference = normalizeString(value.command_or_ref || value.commandOrReference, "");
  const why = normalizeString(value.why, "");
  if (!actionID && !title && !commandOrReference && !why) {
    return null;
  }
  return {
    rank: normalizeInteger(value.rank, fallbackRank),
    action_id: actionID,
    title,
    why,
    command_or_ref: commandOrReference,
  };
}

function compactSupportFAQItem(value) {
  if (!value || typeof value !== "object") return null;
  const faqID = normalizeString(value.faq_id || value.faqID, "");
  const question = normalizeString(value.question, "");
  const answer = normalizeString(value.answer, "");
  if (!faqID && !question && !answer) {
    return null;
  }
  return {
    faq_id: faqID,
    question,
    answer,
  };
}

function parseArgs(argv) {
  const out = {
    summaryPath: defaultSourceGateSummaryPath,
    snapshotEvidencePath: defaultSnapshotEvidencePath,
    requireRealPath: defaultRequireRealPath,
    outputPath: defaultOutputPath,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = normalizeString(argv[i]);
    switch (token) {
      case "--summary":
        out.summaryPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--snapshot-evidence":
        out.snapshotEvidencePath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--require-real":
        out.requireRealPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--out":
        out.outputPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--help":
      case "-h":
        printUsage(0);
        break;
      default:
        throw new Error(`unknown arg: ${token}`);
    }
  }
  return out;
}

function printUsage(exitCode) {
  const message = [
    "usage:",
    "  node scripts/generate_xhub_local_service_operator_recovery_report.js",
    "  node scripts/generate_xhub_local_service_operator_recovery_report.js \\",
    "    --summary build/reports/xhub_doctor_source_gate_summary.v1.json \\",
    "    --snapshot-evidence build/reports/xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json \\",
    "    --require-real build/reports/lpr_w3_03_a_require_real_evidence.v1.json \\",
    "    --out build/reports/xhub_local_service_operator_recovery_report.v1.json",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function extractStructuredRecoveryGuidance(sourceGateSummary, snapshotEvidence) {
  const support = sourceGateSummary?.hub_local_service_recovery_guidance_support || {};
  const compact = support.hub_local_service_recovery_guidance || {};
  const detailed = snapshotEvidence?.hub_local_service_recovery_guidance || {};
  const detailedPrimaryIssue = detailed.primary_issue || {};
  const compactTopAction = compactRecoveryAction(compact.top_recommended_action, 1);
  const compactTopFAQ = compactSupportFAQItem(compact.top_support_faq);
  const recommendedActions = normalizeArray(detailed.recommended_actions)
    .map((item, index) => compactRecoveryAction(item, index + 1))
    .filter(Boolean);
  const supportFAQ = normalizeArray(detailed.support_faq)
    .map((item) => compactSupportFAQItem(item))
    .filter(Boolean);

  return {
    smokeStatus: normalizeString(
      support.hub_local_service_recovery_guidance_smoke_status || snapshotEvidence?.status,
      "missing"
    ),
    guidancePresent:
      detailed.guidance_present === true ||
      normalizeString(detailed.action_category || compact.action_category, "") !== "" ||
      recommendedActions.length > 0 ||
      !!compactTopAction,
    source: detailed.guidance_present === true
      ? "snapshot_evidence"
      : (normalizeString(compact.action_category, "") ? "source_gate_summary" : "missing"),
    currentFailureCode: normalizeString(detailed.current_failure_code || compact.current_failure_code, ""),
    currentFailureIssue: normalizeString(detailed.current_failure_issue || compact.current_failure_issue, ""),
    providerCheckStatus: normalizeString(detailed.provider_check_status || compact.provider_check_status, ""),
    providerCheckBlocking: detailed.provider_check_blocking === true || compact.provider_check_blocking === true,
    actionCategory: normalizeString(detailed.action_category || compact.action_category, ""),
    severity: normalizeString(detailed.severity || compact.severity, ""),
    installHint: normalizeString(detailed.install_hint || compact.install_hint, ""),
    repairDestinationRef: normalizeString(detailed.repair_destination_ref || compact.repair_destination_ref, ""),
    serviceBaseURL: normalizeString(detailed.service_base_url || compact.service_base_url, ""),
    managedProcessState: normalizeString(detailed.managed_process_state || compact.managed_process_state, ""),
    managedStartAttemptCount: normalizeInteger(
      detailed.managed_start_attempt_count ?? compact.managed_start_attempt_count,
      0
    ),
    managedLastStartError: normalizeString(detailed.managed_last_start_error || compact.managed_last_start_error, ""),
    blockedCapabilities: normalizeArray(detailed.blocked_capabilities || compact.blocked_capabilities)
      .map((value) => normalizeString(value))
      .filter(Boolean),
    primaryIssueReasonCode: normalizeString(
      detailedPrimaryIssue.reason_code || compact.primary_issue_reason_code || detailed.current_failure_code || compact.current_failure_code,
      ""
    ),
    primaryIssueHeadline: normalizeString(detailedPrimaryIssue.headline, ""),
    primaryIssueMessage: normalizeString(detailedPrimaryIssue.message, ""),
    primaryIssueNextStep: normalizeString(detailedPrimaryIssue.next_step, ""),
    recommendedActions: recommendedActions.length > 0 ? recommendedActions : (compactTopAction ? [compactTopAction] : []),
    supportFAQ: supportFAQ.length > 0 ? supportFAQ : (compactTopFAQ ? [compactTopFAQ] : []),
  };
}

function extractSnapshotTruth(sourceGateSummary, snapshotEvidence) {
  const support = sourceGateSummary?.hub_local_service_snapshot_support || {};
  const compact = support.hub_local_service_snapshot || {};
  const detailedSnapshot = snapshotEvidence?.hub_local_service_snapshot || {};
  const recoveryGuidance = extractStructuredRecoveryGuidance(sourceGateSummary, snapshotEvidence);
  const primaryIssue = detailedSnapshot.primary_issue || {};
  const doctorProjection = detailedSnapshot.doctor_projection || {};
  const providers = Array.isArray(detailedSnapshot.providers) ? detailedSnapshot.providers : [];
  const provider = providers[0] || {};
  const managed = provider.managed_service_state || {};

  return {
    sourceGateOverallStatus: normalizeString(sourceGateSummary?.overall_status, "missing"),
    snapshotSmokeStatus: normalizeString(support.hub_local_service_snapshot_smoke_status || snapshotEvidence?.status, "missing"),
    providerCount: normalizeInteger(compact.provider_count ?? detailedSnapshot.provider_count, 0),
    readyProviderCount: normalizeInteger(compact.ready_provider_count ?? detailedSnapshot.ready_provider_count, 0),
    providerID: normalizeString(compact.provider_id || provider.provider_id, "unknown"),
    primaryIssueReasonCode: normalizeString(
      compact.primary_issue_reason_code
        || primaryIssue.reason_code
        || recoveryGuidance.primaryIssueReasonCode
        || compact.doctor_failure_code
        || doctorProjection.current_failure_code
        || recoveryGuidance.currentFailureCode,
      "unknown"
    ),
    doctorFailureCode: normalizeString(
      compact.doctor_failure_code || doctorProjection.current_failure_code || recoveryGuidance.currentFailureCode,
      "unknown"
    ),
    doctorProviderCheckStatus: normalizeString(
      compact.doctor_provider_check_status || doctorProjection.provider_check_status || recoveryGuidance.providerCheckStatus,
      "unknown"
    ),
    headline: normalizeString(
      primaryIssue.headline || recoveryGuidance.primaryIssueHeadline || doctorProjection.headline,
      "Hub-managed local service needs review"
    ),
    message: normalizeString(
      primaryIssue.message || recoveryGuidance.primaryIssueMessage || doctorProjection.message,
      "Snapshot truth is missing a precise explanation."
    ),
    nextStep: normalizeString(
      primaryIssue.next_step || recoveryGuidance.primaryIssueNextStep || doctorProjection.next_step,
      "Inspect the managed service snapshot before retrying live traffic."
    ),
    serviceState: normalizeString(compact.service_state || provider.service_state, "unknown"),
    runtimeReasonCode: normalizeString(compact.runtime_reason_code || provider.runtime_reason_code, "unknown"),
    serviceBaseURL: normalizeString(provider.service_base_url || recoveryGuidance.serviceBaseURL, ""),
    executionMode: normalizeString(provider.execution_mode, ""),
    managedProcessState: normalizeString(
      compact.managed_process_state || managed.processState || managed.process_state || recoveryGuidance.managedProcessState,
      "unknown"
    ),
    managedStartAttemptCount: normalizeInteger(
      compact.managed_start_attempt_count
        ?? managed.startAttemptCount
        ?? managed.start_attempt_count
        ?? recoveryGuidance.managedStartAttemptCount,
      0
    ),
    managedLastStartError: normalizeString(
      managed.lastStartError || managed.last_start_error || recoveryGuidance.managedLastStartError,
      ""
    ),
    managedLastProbeError: normalizeString(managed.lastProbeError || managed.last_probe_error, ""),
    repairDestinationRef: normalizeString(
      doctorProjection.repair_destination_ref || recoveryGuidance.repairDestinationRef,
      ""
    ),
    recoveryGuidance,
  };
}

function classifyRecovery(truth) {
  const structuredGuidance = truth.recoveryGuidance || {};
  if (structuredGuidance.guidancePresent && structuredGuidance.actionCategory) {
    return {
      actionCategory: structuredGuidance.actionCategory,
      severity: normalizeString(structuredGuidance.severity, "high"),
      installHint: normalizeString(structuredGuidance.installHint, truth.nextStep),
      recommendedActions: structuredGuidance.recommendedActions,
    };
  }

  const reasonCode = truth.primaryIssueReasonCode;
  const serviceBaseURL = truth.serviceBaseURL || "http://127.0.0.1:50171";
  const rerunCommand = "bash scripts/ci/xhub_doctor_source_gate.sh";
  const baseActions = [
    {
      action_id: "rerun_doctor_source_gate",
      title: "Rerun cross-surface doctor source gate",
      why: "This refreshes Hub doctor, Hub local-service snapshot smoke, XT source smoke, and the aggregate summary from one command.",
      command_or_ref: rerunCommand,
    },
  ];

  if (reasonCode === "xhub_local_service_config_missing") {
    return {
      actionCategory: "repair_config",
      severity: "high",
      installHint: `Set runtimeRequirements.serviceBaseUrl or XHUB_LOCAL_SERVICE_BASE_URL to a loopback endpoint such as ${serviceBaseURL}.`,
      recommendedActions: [
        {
          action_id: "set_loopback_service_base_url",
          title: "Set a loopback serviceBaseUrl for xhub_local_service",
          why: "Hub fails closed when providers are pinned to xhub_local_service but no local endpoint is configured.",
          command_or_ref: `Set runtimeRequirements.serviceBaseUrl or XHUB_LOCAL_SERVICE_BASE_URL to ${serviceBaseURL}`,
        },
        ...baseActions,
      ],
    };
  }

  if (reasonCode === "xhub_local_service_nonlocal_endpoint") {
    return {
      actionCategory: "repair_endpoint",
      severity: "high",
      installHint: `Change runtimeRequirements.serviceBaseUrl to a local loopback HTTP endpoint such as ${serviceBaseURL}.`,
      recommendedActions: [
        {
          action_id: "replace_nonlocal_endpoint",
          title: "Replace the non-local service endpoint with a loopback endpoint",
          why: "Hub only auto-starts and trusts xhub_local_service on loopback endpoints.",
          command_or_ref: `Set runtimeRequirements.serviceBaseUrl to ${serviceBaseURL}`,
        },
        ...baseActions,
      ],
    };
  }

  if (reasonCode === "xhub_local_service_starting") {
    return {
      actionCategory: "wait_for_health_ready",
      severity: "medium",
      installHint: "Wait until /health reports ready before routing live traffic or declaring release readiness.",
      recommendedActions: [
        {
          action_id: "wait_for_health_ready",
          title: "Wait for /health to reach ready",
          why: "The managed service is still starting and may not have completed warmup or provider registration.",
          command_or_ref: "Poll the Hub diagnostics surface or /health until ready_for_first_task becomes true",
        },
        ...baseActions,
      ],
    };
  }

  if (reasonCode === "xhub_local_service_not_ready") {
    return {
      actionCategory: "inspect_health_payload",
      severity: "high",
      installHint: "Inspect the service health payload, provider registry, and runtime manager before retrying live traffic.",
      recommendedActions: [
        {
          action_id: "inspect_service_health_payload",
          title: "Inspect service health payload and provider registry",
          why: "The service answered, but it did not satisfy the ready contract.",
          command_or_ref: "Export diagnostics and compare /health with provider registry and runtime manager state",
        },
        ...baseActions,
      ],
    };
  }

  if (reasonCode === "xhub_local_service_internal_runtime_missing") {
    return {
      actionCategory: "repair_service_runtime",
      severity: "high",
      installHint: "Repair the service-hosted runtime dependencies before retrying provider warmup or live traffic.",
      recommendedActions: [
        {
          action_id: "repair_service_hosted_runtime_dependencies",
          title: "Repair the service-hosted runtime dependencies",
          why: "The provider pack is selected, but the service-hosted runtime cannot satisfy the provider requirements.",
          command_or_ref: "Repair the xhub_local_service runtime environment, then rerun diagnostics",
        },
        ...baseActions,
      ],
    };
  }

  if (reasonCode === "xhub_local_service_unreachable") {
    if (truth.managedProcessState === "launch_failed") {
      return {
        actionCategory: "repair_managed_launch_failure",
        severity: "high",
        installHint: "Inspect the managed service snapshot and stderr log before retrying startup.",
        recommendedActions: [
          {
            action_id: "inspect_managed_launch_error",
            title: "Inspect managed service launch error",
            why: "Hub already attempted a managed launch and the process failed before health became ready.",
            command_or_ref: truth.managedLastStartError
              ? `Inspect managed service stderr and last_start_error=${truth.managedLastStartError}`
              : "Inspect managed service stderr and launch logs",
          },
          ...baseActions,
        ],
      };
    }

    if (truth.managedLastStartError.startsWith("health_timeout:")) {
      return {
        actionCategory: "inspect_health_timeout",
        severity: "high",
        installHint: "Inspect recent stderr and warmup progress, then retry once /health reaches ready.",
        recommendedActions: [
          {
            action_id: "inspect_health_timeout",
            title: "Inspect warmup progress after health timeout",
            why: "Hub launched the service, but /health did not become ready before timeout.",
            command_or_ref: truth.managedLastStartError,
          },
          ...baseActions,
        ],
      };
    }

    if (truth.managedStartAttemptCount > 0) {
      return {
        actionCategory: "inspect_snapshot_before_retry",
        severity: "high",
        installHint: "Inspect the managed service snapshot before retrying startup or routing live traffic.",
        recommendedActions: [
          {
            action_id: "inspect_managed_service_snapshot",
            title: "Inspect managed service snapshot before retry",
            why: "Hub has already attempted startup and the snapshot contains the most precise structured reason for the current failure.",
            command_or_ref: "build/reports/xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json",
          },
          truth.managedLastStartError
            ? {
                action_id: "review_last_start_error",
                title: "Review the last managed start error",
                why: "The last start error often explains whether the next move is config repair, dependency repair, or startup retry.",
                command_or_ref: truth.managedLastStartError,
              }
            : null,
          ...baseActions,
        ].filter(Boolean),
      };
    }

    return {
      actionCategory: "start_service_or_fix_endpoint",
      severity: "high",
      installHint: "Start xhub_local_service or fix the configured endpoint, then refresh diagnostics.",
      recommendedActions: [
        {
          action_id: "start_service_or_fix_endpoint",
          title: "Start xhub_local_service or fix the configured endpoint",
          why: "Hub cannot reach /health and has not yet produced a richer managed-launch explanation.",
          command_or_ref: serviceBaseURL ? `Verify /health at ${serviceBaseURL}` : "Verify the configured loopback /health endpoint",
        },
        ...baseActions,
      ],
    };
  }

  return {
    actionCategory: "inspect_snapshot",
    severity: "high",
    installHint: "Export diagnostics and inspect the managed service snapshot before routing live traffic.",
    recommendedActions: [
      {
        action_id: "inspect_snapshot",
        title: "Inspect the managed service snapshot",
        why: "The current status snapshot does not map cleanly to a narrower recovery category.",
        command_or_ref: "build/reports/xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json",
      },
      ...baseActions,
    ],
  };
}

function buildSupportFAQ(truth, recovery, requireReal) {
  const structuredGuidance = truth.recoveryGuidance || {};
  const requireRealStance = normalizeString(requireReal?.release_stance, "missing");
  const sample1Handoff = compactRequireRealSample1Handoff(requireReal);
  const releaseAnswer = requireRealStance === "candidate_go"
    ? "Because require-real is already candidate_go, release wording can talk about structured recovery truth being in place, but external launch claims should still stay inside the verified capability boundary."
    : "Because require-real is not candidate_go yet. Structured doctor/export truth is ready, but real embedding / ASR / vision execution closure is still the release blocker.";
  const baseFAQ =
    structuredGuidance.guidancePresent && structuredGuidance.supportFAQ.length > 0
      ? structuredGuidance.supportFAQ
      : [
    {
      faq_id: "release_no_go_boundary",
      question: "Why is release wording still conservative even though source-run doctor gate is green?",
      answer: releaseAnswer,
      trigger_reason_codes: [truth.primaryIssueReasonCode],
      trigger_process_states: [truth.managedProcessState],
    },
    {
      faq_id: "current_primary_issue",
      question: "What is the current primary xhub_local_service issue?",
      answer: `${truth.headline}. ${truth.message}`,
      trigger_reason_codes: [truth.primaryIssueReasonCode],
      trigger_process_states: [truth.managedProcessState],
    },
    {
      faq_id: "next_operator_move",
      question: "What should the operator do next?",
      answer: recovery.recommendedActions[0]
        ? `${recovery.recommendedActions[0].title}. ${recovery.recommendedActions[0].why}`
        : truth.nextStep,
      trigger_reason_codes: [truth.primaryIssueReasonCode],
      trigger_process_states: [truth.managedProcessState],
    },
  ];

  return [
    ...baseFAQ,
    sample1Handoff && requireRealStance !== "candidate_go"
      ? {
          faq_id: "require_real_next_move",
          question: "What is the next require-real closure move?",
          answer: sample1Handoff.top_recommended_action
            ? `${normalizeString(sample1Handoff.top_recommended_action.action_summary)}`
            : `Follow the sample1 handoff until require-real is no longer blocked by ${sample1Handoff.blocker_class}.`,
          trigger_reason_codes: [truth.primaryIssueReasonCode],
          trigger_process_states: [truth.managedProcessState],
        }
      : null,
    sample1Handoff?.candidate_acceptance && requireRealStance !== "candidate_go"
      ? {
          faq_id: "require_real_acceptance_contract",
          question: "What must a new sample1 embedding dir satisfy before execution?",
          answer: sample1Handoff.candidate_acceptance.acceptance_contract
            ? `Only proceed after exact-path validation returns ${normalizeString(sample1Handoff.candidate_acceptance.acceptance_contract.required_gate_verdict)} and ${normalizeString(sample1Handoff.candidate_acceptance.acceptance_contract.required_loadability_verdict)}.`
            : "Review the sample1 candidate acceptance contract before importing or validating a new embedding dir.",
          trigger_reason_codes: [truth.primaryIssueReasonCode],
          trigger_process_states: [truth.managedProcessState],
        }
      : null,
    sample1Handoff?.candidate_registration && requireRealStance !== "candidate_go"
      ? {
          faq_id: "require_real_registration_gate",
          question: "Can the operator manually register the current sample1 dir in a shared catalog now?",
          answer:
            sample1Handoff.candidate_registration.machine_decision?.catalog_write_allowed_now === true
              ? "Yes. The current registration packet says catalog_write_allowed_now=true, so the operator may patch one chosen runtime base and keep its models_catalog.json + models_state.json aligned as a pair."
              : sample1Handoff.candidate_registration.acceptance_contract
                ? `No. Keep catalog writes blocked until exact-path validation returns ${normalizeString(sample1Handoff.candidate_registration.acceptance_contract.required_gate_verdict)} and ${normalizeString(sample1Handoff.candidate_registration.acceptance_contract.required_loadability_verdict)}.`
                : "No. Keep catalog writes blocked until the sample1 registration packet explicitly allows them.",
          trigger_reason_codes: [truth.primaryIssueReasonCode],
          trigger_process_states: [truth.managedProcessState],
        }
      : null,
    sample1Handoff?.candidate_registration?.catalog_patch_plan_summary && requireRealStance !== "candidate_go"
      ? {
          faq_id: "require_real_catalog_patch_plan",
          question: "If the validator passes later, how should the operator patch the target files safely?",
          answer:
            sample1Handoff.candidate_registration.catalog_patch_plan_summary.manual_patch_allowed_now === true
              ? "Use the catalog patch plan and patch exactly one runtime base. Keep that base's models_catalog.json and models_state.json aligned as a pair."
              : `Follow the catalog patch plan artifact and keep manual patch blocked while blocked_reason=${normalizeString(sample1Handoff.candidate_registration.catalog_patch_plan_summary.blocked_reason || "unknown")}.`,
          trigger_reason_codes: [truth.primaryIssueReasonCode],
          trigger_process_states: [truth.managedProcessState],
        }
      : null,
    sample1Handoff?.helper_local_service_recovery && requireRealStance !== "candidate_go"
      ? {
          faq_id: "require_real_helper_route_gate",
          question: "What must be true before the helper secondary route counts as ready?",
          answer: sample1Handoff.helper_local_service_recovery.helper_route_contract
            ? `Only treat the helper route as usable after ${normalizeArray(sample1Handoff.helper_local_service_recovery.helper_route_contract.required_ready_signals).join("; ")}.`
            : "Review the helper local-service recovery packet before trusting the LM Studio helper route.",
          trigger_reason_codes: [truth.primaryIssueReasonCode],
          trigger_process_states: [truth.managedProcessState],
        }
      : null,
  ].filter(Boolean);
}

function buildReleaseWording(truth, supportReady, requireReal) {
  const requireRealStance = normalizeString(requireReal?.release_stance, "missing");
  const candidateGo = supportReady && requireRealStance === "candidate_go";

  return {
    external_status_line: candidateGo
      ? "Structured xhub_local_service doctor/export/recovery truth is integrated, and require-real closure is candidate_go."
      : "Structured xhub_local_service doctor/export/recovery truth is integrated, but release remains blocked until require-real closure reaches candidate_go.",
    allowed_claims: supportReady ? [
      "Hub doctor/export can emit structured xhub_local_service failure truth including primary issue and doctor projection.",
      "XT incident export can consume the newer Hub local-service snapshot instead of reverse-parsing detail text.",
      "Repo-level source gate validates structured Hub local-service snapshot support end to end.",
    ] : [],
    blocked_claims: [
      "Do not market the local provider runtime as release-ready while require-real remains below candidate_go.",
      "Do not describe xhub_local_service recovery as verified by real runtime execution if the current blocker is still synthetic-free but pending require-real closure.",
      `Do not downplay the current primary issue (${truth.primaryIssueReasonCode}) as a cosmetic warning.`,
    ],
  };
}

function buildOperatorRecoveryReport(inputs = {}) {
  const generatedAt = inputs.generatedAt || isoNow();
  const timezone = inputs.timezone || "Asia/Shanghai";
  const sourceGateSummary = inputs.sourceGateSummary || null;
  const snapshotEvidence = inputs.snapshotEvidence || null;
  const requireReal = inputs.requireReal || null;
  const truth = extractSnapshotTruth(sourceGateSummary, snapshotEvidence);
  const snapshotSupport = sourceGateSummary?.hub_local_service_snapshot_support || {};
  const guidanceSupport = sourceGateSummary?.hub_local_service_recovery_guidance_support || {};
  const guidanceReady = truth.recoveryGuidance.guidancePresent
    && truth.recoveryGuidance.smokeStatus === "pass"
    && normalizeString(truth.recoveryGuidance.actionCategory, "") !== "";
  const snapshotReady = truth.snapshotSmokeStatus === "pass"
    && truth.providerCount > 0
    && truth.doctorFailureCode !== "unknown";
  const supportReady = guidanceReady || snapshotReady;
  const recovery = classifyRecovery(truth);
  const requireRealStance = normalizeString(requireReal?.release_stance, "missing");
  const requireRealFocus = compactRequireRealSample1Handoff(requireReal);
  const releaseStance = supportReady && requireRealStance === "candidate_go" ? "candidate_go" : "no_go";

  let gateVerdict = "PASS(operator_recovery_report_generated_from_structured_snapshot_truth)";
  let verdictReason = `Structured xhub_local_service snapshot truth is available for ${truth.primaryIssueReasonCode}, so operator/support/release wording can reuse machine-readable diagnosis instead of reverse-parsing text.`;
  if (!supportReady) {
    gateVerdict = "NO_GO(hub_local_service_snapshot_support_missing)";
    verdictReason = "Structured xhub_local_service snapshot support is missing or incomplete, so operator/support output must fail closed.";
  } else if (releaseStance !== "candidate_go") {
    verdictReason += " Release wording remains conservative because require-real is not candidate_go yet.";
  }

  return {
    schema_version: "xhub.operator.xhub_local_service_recovery_report.v1",
    generated_at: generatedAt,
    timezone,
    scope: "xhub_local_service operator recovery / support faq / release wording",
    fail_closed: true,
    gate_verdict: gateVerdict,
    verdict_reason: verdictReason,
    release_stance: releaseStance,
    machine_decision: {
      support_ready: supportReady,
      release_ready: releaseStance === "candidate_go",
      source_gate_status: truth.sourceGateOverallStatus,
      snapshot_smoke_status: truth.snapshotSmokeStatus,
      recovery_guidance_smoke_status: normalizeString(guidanceSupport.hub_local_service_recovery_guidance_smoke_status, "missing"),
      recovery_guidance_source: truth.recoveryGuidance.source,
      require_real_release_stance: requireRealStance,
      require_real_focus_present: !!requireRealFocus,
      require_real_focus_helper_local_service_recovery_present:
        !!(requireRealFocus && requireRealFocus.helper_local_service_recovery),
      require_real_focus_acceptance_present: !!(requireRealFocus && requireRealFocus.candidate_acceptance),
      require_real_focus_registration_present: !!(requireRealFocus && requireRealFocus.candidate_registration),
      action_category: recovery.actionCategory,
    },
    local_service_truth: {
      provider_id: truth.providerID,
      primary_issue_reason_code: truth.primaryIssueReasonCode,
      doctor_failure_code: truth.doctorFailureCode,
      doctor_provider_check_status: truth.doctorProviderCheckStatus,
      headline: truth.headline,
      message: truth.message,
      next_step: truth.nextStep,
      service_state: truth.serviceState,
      runtime_reason_code: truth.runtimeReasonCode,
      service_base_url: truth.serviceBaseURL,
      execution_mode: truth.executionMode,
      provider_count: truth.providerCount,
      ready_provider_count: truth.readyProviderCount,
      managed_process_state: truth.managedProcessState,
      managed_start_attempt_count: truth.managedStartAttemptCount,
      managed_last_start_error: truth.managedLastStartError,
      managed_last_probe_error: truth.managedLastProbeError,
      repair_destination_ref: truth.repairDestinationRef,
    },
    recovery_classification: {
      action_category: recovery.actionCategory,
      severity: recovery.severity,
      install_hint: recovery.installHint,
    },
    recommended_actions: recovery.recommendedActions.map((action, index) => ({
      rank: index + 1,
      ...action,
    })),
    support_faq: buildSupportFAQ(truth, recovery, requireReal),
    require_real_focus: requireRealFocus,
    release_wording: buildReleaseWording(truth, supportReady, requireReal),
    evidence_refs: [
      "build/reports/xhub_doctor_source_gate_summary.v1.json",
      "build/reports/xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json",
      "build/reports/lpr_w3_03_a_require_real_evidence.v1.json",
      "build/reports/lpr_w3_03_sample1_helper_local_service_recovery.v1.json",
      "build/reports/lpr_w3_03_sample1_candidate_acceptance.v1.json",
      "build/reports/lpr_w3_03_sample1_candidate_catalog_patch_plan.v1.json",
      "build/reports/lpr_w3_03_sample1_candidate_registration_packet.v1.json",
      "scripts/generate_xhub_local_service_operator_recovery_report.js",
    ],
    inputs: {
      source_gate_summary_present: !!sourceGateSummary,
      snapshot_evidence_present: !!snapshotEvidence,
      require_real_present: !!requireReal,
      recovery_guidance_present: truth.recoveryGuidance.guidancePresent,
      source_gate_summary_ref: "build/reports/xhub_doctor_source_gate_summary.v1.json",
      snapshot_evidence_ref: "build/reports/xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json",
      require_real_ref: "build/reports/lpr_w3_03_a_require_real_evidence.v1.json",
    },
  };
}

function main() {
  const args = parseArgs(process.argv);
  const sourceGateSummary = readJSONIfExists(args.summaryPath);
  const snapshotEvidence = readJSONIfExists(args.snapshotEvidencePath);
  const requireReal = readJSONIfExists(args.requireRealPath);
  const report = buildOperatorRecoveryReport({
    sourceGateSummary,
    snapshotEvidence,
    requireReal,
  });
  writeJSON(args.outputPath, report);
  process.stdout.write(`${args.outputPath}\n`);
}

if (require.main === module) {
  main();
}

module.exports = {
  buildOperatorRecoveryReport,
  classifyRecovery,
  extractSnapshotTruth,
  parseArgs,
};
