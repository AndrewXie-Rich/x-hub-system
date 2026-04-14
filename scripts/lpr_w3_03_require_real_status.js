#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const {
  readCaptureBundle,
  repoRoot,
  resolveBundlePath,
  resolveHelperProbePath,
  resolveModelProbePath,
  resolveReportsDir,
  resolveRequireRealEvidencePath,
  resolveRuntimeProbePath,
} = require("./lpr_w3_03_require_real_bundle_lib.js");

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

function parseArgs(argv) {
  const out = {
    json: false,
    all: false,
    sampleId: "",
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = String(argv[i] || "").trim();
    switch (token) {
      case "--json":
        out.json = true;
        break;
      case "--all":
        out.all = true;
        break;
      case "--sample-id":
        out.sampleId = String(argv[++i] || "").trim();
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
    "  node scripts/lpr_w3_03_require_real_status.js",
    "  node scripts/lpr_w3_03_require_real_status.js --all",
    "  node scripts/lpr_w3_03_require_real_status.js --sample-id lpr_rr_01_embedding_real_model_dir_executes",
    "  node scripts/lpr_w3_03_require_real_status.js --json",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function isExecuted(sample) {
  return typeof sample.performed_at === "string" && sample.performed_at.trim() !== "";
}

function hasEvidence(sample) {
  return Array.isArray(sample.evidence_refs) && sample.evidence_refs.length > 0;
}

function isPassed(sample) {
  return isExecuted(sample) && sample.success_boolean === true && hasEvidence(sample);
}

function normalizeString(value) {
  return String(value || "").trim();
}

function dedupeStrings(values = []) {
  const seen = new Set();
  const out = [];
  for (const value of values) {
    const text = normalizeString(value);
    if (!text || seen.has(text)) continue;
    seen.add(text);
    out.push(text);
  }
  return out;
}

function compactQAContext(qa = null) {
  if (!qa || typeof qa !== "object") {
    return {
      gate_verdict: "missing(run_generate_first)",
      release_stance: "missing(run_generate_first)",
      verdict_reason: "",
      next_required_artifacts: [],
      machine_decision: null,
    };
  }

  const machineDecision =
    qa.machine_decision && typeof qa.machine_decision === "object" ? qa.machine_decision : null;
  const sample1OperatorHandoff =
    machineDecision &&
    machineDecision.sample1_operator_handoff &&
    typeof machineDecision.sample1_operator_handoff === "object"
      ? machineDecision.sample1_operator_handoff
      : null;

  return {
    gate_verdict: normalizeString(qa.gate_verdict) || "unknown",
    release_stance: normalizeString(qa.release_stance) || "unknown",
    verdict_reason: normalizeString(qa.verdict_reason),
    next_required_artifacts: dedupeStrings(
      Array.isArray(qa.next_required_artifacts) ? qa.next_required_artifacts : []
    ),
    machine_decision: machineDecision
      ? {
          pending_samples: dedupeStrings(machineDecision.pending_samples),
          missing_evidence_samples: dedupeStrings(machineDecision.missing_evidence_samples),
          sample1_current_blockers: dedupeStrings(machineDecision.sample1_current_blockers),
          sample1_runtime_ready: machineDecision.sample1_runtime_ready === true,
          sample1_execution_ready: machineDecision.sample1_execution_ready === true,
          sample1_overall_recommended_action_id: normalizeString(
            machineDecision.sample1_overall_recommended_action_id
          ),
          sample1_operator_handoff_state: normalizeString(
            machineDecision.sample1_operator_handoff_state ||
              (sample1OperatorHandoff && sample1OperatorHandoff.handoff_state)
          ),
          sample1_operator_handoff_blocker_class: normalizeString(
            machineDecision.sample1_operator_handoff_blocker_class ||
              (sample1OperatorHandoff && sample1OperatorHandoff.blocker_class)
          ),
        }
      : null,
  };
}

function helperRouteReady(helperProbe = {}) {
  return !!(
    helperProbe &&
    helperProbe.helper_binary_found === true &&
    helperProbe.server_models_endpoint_ok === true &&
    normalizeString(helperProbe.daemon_probe_after) === "helper_bridge_ready"
  );
}

function compactSample1RuntimeProbe(runtimeProbe = null) {
  if (!runtimeProbe || typeof runtimeProbe !== "object") return null;
  const candidate =
    runtimeProbe.current_best_candidate && typeof runtimeProbe.current_best_candidate === "object"
      ? runtimeProbe.current_best_candidate
      : runtimeProbe;
  const compact = {
    runtime_id: normalizeString(candidate.runtime_id || runtimeProbe.runtime_id),
    verdict: normalizeString(candidate.verdict),
    blocker_reason: normalizeString(candidate.blocker_reason),
    summary: normalizeString(candidate.summary),
  };
  return Object.values(compact).some(Boolean) ? compact : null;
}

function compactSample1ModelProbe(modelProbe = null) {
  if (!modelProbe || typeof modelProbe !== "object") return null;
  const summary =
    modelProbe.summary && typeof modelProbe.summary === "object"
      ? modelProbe.summary
      : modelProbe;
  const runtimeResolution =
    modelProbe.runtime_resolution && typeof modelProbe.runtime_resolution === "object"
      ? modelProbe.runtime_resolution
      : modelProbe;
  const compact = {
    selected_runtime_id: normalizeString(runtimeResolution.selected_runtime_id),
    discovered_embedding_candidates: Number(summary.discovered_embedding_candidates || 0),
    native_loadable_embedding_candidates: Number(summary.native_loadable_embedding_candidates || 0),
    partially_loadable_embedding_candidates: Number(summary.partially_loadable_embedding_candidates || 0),
    best_native_candidate_model_path: normalizeString(summary.best_native_candidate_model_path),
    primary_blocker: normalizeString(summary.primary_blocker),
    recommended_next_step: normalizeString(summary.recommended_next_step),
  };
  const hasMeaningfulValue =
    compact.selected_runtime_id ||
    compact.best_native_candidate_model_path ||
    compact.primary_blocker ||
    compact.recommended_next_step ||
    compact.discovered_embedding_candidates > 0 ||
    compact.native_loadable_embedding_candidates > 0 ||
    compact.partially_loadable_embedding_candidates > 0;
  return hasMeaningfulValue ? compact : null;
}

function compactSample1HelperProbe(helperProbe = null) {
  if (!helperProbe || typeof helperProbe !== "object") return null;
  const summary =
    helperProbe.summary && typeof helperProbe.summary === "object"
      ? helperProbe.summary
      : helperProbe;
  const compact = {
    helper_binary_found: summary.helper_binary_found === true,
    daemon_probe_before: normalizeString(summary.daemon_probe_before),
    daemon_probe_after: normalizeString(summary.daemon_probe_after),
    server_models_endpoint_ok: summary.server_models_endpoint_ok === true,
    primary_blocker: normalizeString(summary.primary_blocker),
    recommended_next_step: normalizeString(summary.recommended_next_step),
    lmstudio_environment:
      summary.lmstudio_environment && typeof summary.lmstudio_environment === "object"
        ? summary.lmstudio_environment
        : {},
  };
  const hasMeaningfulValue =
    compact.helper_binary_found === true ||
    compact.server_models_endpoint_ok === true ||
    compact.daemon_probe_before ||
    compact.daemon_probe_after ||
    compact.primary_blocker ||
    compact.recommended_next_step ||
    Object.keys(compact.lmstudio_environment).length > 0;
  return hasMeaningfulValue ? compact : null;
}

function sample1RejectedCandidates(modelProbe = {}) {
  const candidates = Array.isArray(modelProbe.embedding_candidates)
    ? modelProbe.embedding_candidates
    : [];
  return candidates
    .filter((candidate) => normalizeString(candidate?.loadability?.verdict) !== "native_loadable")
    .slice(0, 3)
    .map((candidate) => ({
      model_path: normalizeString(candidate.model_path),
      model_name_hint: normalizeString(candidate.model_name_hint),
      task_hint: normalizeString(candidate.task_hint),
      task_hint_sources:
        candidate &&
        candidate.static_markers &&
        candidate.static_markers.format_assessment &&
        Array.isArray(candidate.static_markers.format_assessment.task_hint_sources)
          ? dedupeStrings(candidate.static_markers.format_assessment.task_hint_sources)
          : [],
      blocker_reason: normalizeString(candidate?.loadability?.blocker_reason),
      rejection_reasons: dedupeStrings(candidate?.loadability?.reasons || []).slice(0, 6),
      discovery_sources: dedupeStrings(candidate.discovery_sources || []),
      artifact_refs: dedupeStrings(
        candidate && candidate.artifact_refs && typeof candidate.artifact_refs === "object"
          ? Object.values(candidate.artifact_refs)
          : []
      ),
    }));
}

function compactCandidateAcceptanceForHandoff(candidateAcceptance = null) {
  if (!candidateAcceptance || typeof candidateAcceptance !== "object") return null;
  return {
    current_machine_state: candidateAcceptance.current_machine_state
      ? {
          runtime_ready: candidateAcceptance.current_machine_state.runtime_ready === true,
          search_outcome: normalizeString(candidateAcceptance.current_machine_state.search_outcome),
          handoff_state: normalizeString(candidateAcceptance.current_machine_state.handoff_state),
          blocker_class: normalizeString(candidateAcceptance.current_machine_state.blocker_class),
          candidates_considered: Number(
            candidateAcceptance.current_machine_state.candidates_considered || 0
          ),
          filtered_out_task_mismatch_count: Number(
            candidateAcceptance.current_machine_state.filtered_out_task_mismatch_count || 0
          ),
          top_recommended_action: candidateAcceptance.current_machine_state.top_recommended_action || null,
        }
      : null,
    acceptance_contract: candidateAcceptance.acceptance_contract
      ? {
          expected_provider: normalizeString(candidateAcceptance.acceptance_contract.expected_provider),
          expected_task_kind: normalizeString(candidateAcceptance.acceptance_contract.expected_task_kind),
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
          normalized_model_dir: normalizeString(candidateAcceptance.current_no_go_example.normalized_model_dir),
          gate_verdict: normalizeString(candidateAcceptance.current_no_go_example.gate_verdict),
          task_kind_status: normalizeString(candidateAcceptance.current_no_go_example.task_kind_status),
          loadability_blocker: normalizeString(candidateAcceptance.current_no_go_example.loadability_blocker),
        }
      : null,
    filtered_out_examples: Array.isArray(candidateAcceptance.filtered_out_examples)
      ? candidateAcceptance.filtered_out_examples.map((row) => ({
          normalized_model_dir: normalizeString(row.normalized_model_dir),
          task_kind_status: normalizeString(row.task_kind_status),
          inferred_task_hint: normalizeString(row.inferred_task_hint),
        }))
      : [],
    artifact_refs:
      candidateAcceptance.artifact_refs && typeof candidateAcceptance.artifact_refs === "object"
        ? candidateAcceptance.artifact_refs
        : null,
  };
}

function shortlistScanRootCount(shortlist = null) {
  return shortlist && Array.isArray(shortlist.scan_roots) ? shortlist.scan_roots.length : 0;
}

function selectPreferredSample1Shortlist(defaultShortlist = null, wideShortlist = null) {
  const defaultPayload =
    defaultShortlist && typeof defaultShortlist === "object" ? defaultShortlist : null;
  const widePayload =
    wideShortlist && typeof wideShortlist === "object" ? wideShortlist : null;
  if (!widePayload) return defaultPayload;
  if (!defaultPayload) return widePayload;

  const wideProfile = normalizeString(widePayload.scan_profile);
  if (
    wideProfile === "default_roots_plus_common_user_roots" &&
    shortlistScanRootCount(widePayload) >= shortlistScanRootCount(defaultPayload)
  ) {
    return widePayload;
  }

  return shortlistScanRootCount(widePayload) > shortlistScanRootCount(defaultPayload)
    ? widePayload
    : defaultPayload;
}

function compactSearchRecoveryPlan(searchRecoveryPlan = null) {
  if (!searchRecoveryPlan || typeof searchRecoveryPlan !== "object") return null;
  return {
    exact_path_known: searchRecoveryPlan.exact_path_known === true,
    exact_path_exists: searchRecoveryPlan.exact_path_exists === true,
    exact_path_shortlist_refresh_command: normalizeString(
      searchRecoveryPlan.exact_path_shortlist_refresh_command
    ),
    exact_path_validation_command: normalizeString(
      searchRecoveryPlan.exact_path_validation_command
    ),
    explicit_model_path_shortlist_command_template: normalizeString(
      searchRecoveryPlan.explicit_model_path_shortlist_command_template
    ),
    explicit_model_path_validation_command_template: normalizeString(
      searchRecoveryPlan.explicit_model_path_validation_command_template
    ),
    wide_shortlist_search_command: normalizeString(
      searchRecoveryPlan.wide_shortlist_search_command
    ),
    custom_scan_root_shortlist_command_template: normalizeString(
      searchRecoveryPlan.custom_scan_root_shortlist_command_template
    ),
    preferred_next_step: normalizeString(searchRecoveryPlan.preferred_next_step),
  };
}

function candidateValidationPassed(candidateValidation = null) {
  return (
    normalizeString(candidateValidation && candidateValidation.gate_verdict) ===
    "PASS(sample1_candidate_native_loadable_for_real_execution)"
  );
}

function shortlistPassCandidates(candidateShortlist = null) {
  const shortlist =
    candidateShortlist && typeof candidateShortlist === "object" ? candidateShortlist : {};
  const candidates = Array.isArray(shortlist.candidates) ? shortlist.candidates : [];
  return candidates.filter((row) => candidateValidationPassed(row && row.candidate_validation));
}

function bestReadySample1Candidate(candidateShortlist = null, candidateRegistration = null) {
  const registration =
    candidateRegistration && typeof candidateRegistration === "object" ? candidateRegistration : {};
  const registrationPath = normalizeString(
    registration.normalized_model_dir || registration.requested_model_path
  );
  if (registrationPath && candidateValidationPassed(registration.candidate_validation)) {
    return {
      model_path: registrationPath,
      source: "candidate_registration",
    };
  }

  const shortlistReady = shortlistPassCandidates(candidateShortlist)[0] || null;
  if (shortlistReady) {
    return {
      model_path: normalizeString(shortlistReady.normalized_model_dir),
      source: "candidate_shortlist",
    };
  }

  return {
    model_path: "",
    source: "none",
  };
}

function compactCandidateRegistrationForHandoff(candidateRegistration = null) {
  if (!candidateRegistration || typeof candidateRegistration !== "object") return null;
  return {
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
          task_kinds: Array.isArray(candidateRegistration.proposed_catalog_entry_payload.taskKinds)
            ? candidateRegistration.proposed_catalog_entry_payload.taskKinds.map((item) => normalizeString(item))
            : [],
        }
      : null,
    target_catalog_paths: Array.isArray(candidateRegistration.target_catalog_paths)
      ? candidateRegistration.target_catalog_paths.map((item) => ({
          catalog_path: normalizeString(item.catalog_path),
          present: item.present === true,
          exact_model_dir_registered: item.exact_model_dir_registered === true,
          proposed_model_id_conflict: item.proposed_model_id_conflict === true,
          recommended_action: normalizeString(item.recommended_action),
        }))
      : [],
    search_recovery_plan: compactSearchRecoveryPlan(candidateRegistration.search_recovery_plan),
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
          eligible_target_base_count: Number(
            candidateRegistration.catalog_patch_plan_summary.eligible_target_base_count || 0
          ),
          blocked_target_base_count: Number(
            candidateRegistration.catalog_patch_plan_summary.blocked_target_base_count || 0
          ),
          target_base_plans: Array.isArray(
            candidateRegistration.catalog_patch_plan_summary.target_base_plans
          )
            ? candidateRegistration.catalog_patch_plan_summary.target_base_plans.map((base) => ({
                base_dir: normalizeString(base.base_dir),
                base_label: normalizeString(base.base_label),
                patch_allowed_now: base.patch_allowed_now === true,
                blocked_reasons: dedupeStrings(base.blocked_reasons || []),
                recommended_action: normalizeString(base.recommended_action),
                files: Array.isArray(base.files)
                  ? base.files.map((file) => ({
                      catalog_path: normalizeString(file.catalog_path),
                      file_kind: normalizeString(file.file_kind),
                      shape_family: normalizeString(file.shape_family),
                      target_eligible_now: file.target_eligible_now === true,
                      blocked_reason: normalizeString(file.blocked_reason),
                      model_patch_operation: normalizeString(file.model_patch_operation),
                    }))
                  : [],
              }))
            : [],
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
    artifact_refs:
      candidateRegistration.artifact_refs && typeof candidateRegistration.artifact_refs === "object"
        ? candidateRegistration.artifact_refs
        : null,
  };
}

function compactHelperLocalServiceRecoveryForHandoff(helperRecovery = null) {
  if (!helperRecovery || typeof helperRecovery !== "object") return null;
  return {
    current_machine_state: helperRecovery.current_machine_state
      ? {
          helper_binary_found: helperRecovery.current_machine_state.helper_binary_found === true,
          helper_binary_path: normalizeString(helperRecovery.current_machine_state.helper_binary_path),
          helper_server_base_url: normalizeString(
            helperRecovery.current_machine_state.helper_server_base_url
          ),
          daemon_probe_before: normalizeString(
            helperRecovery.current_machine_state.daemon_probe_before
          ),
          daemon_probe_after: normalizeString(
            helperRecovery.current_machine_state.daemon_probe_after
          ),
          server_result_reason: normalizeString(
            helperRecovery.current_machine_state.server_result_reason
          ),
          server_models_endpoint_ok:
            helperRecovery.current_machine_state.server_models_endpoint_ok === true,
          settings_found: helperRecovery.current_machine_state.settings_found === true,
          settings_path: normalizeString(helperRecovery.current_machine_state.settings_path),
          enable_local_service:
            typeof helperRecovery.current_machine_state.enable_local_service === "boolean"
              ? helperRecovery.current_machine_state.enable_local_service
              : null,
          cli_installed:
            typeof helperRecovery.current_machine_state.cli_installed === "boolean"
              ? helperRecovery.current_machine_state.cli_installed
              : null,
          app_first_load:
            typeof helperRecovery.current_machine_state.app_first_load === "boolean"
              ? helperRecovery.current_machine_state.app_first_load
              : null,
          attempted_install_lms_cli_on_startup:
            typeof helperRecovery.current_machine_state.attempted_install_lms_cli_on_startup === "boolean"
              ? helperRecovery.current_machine_state.attempted_install_lms_cli_on_startup
              : null,
          primary_blocker: normalizeString(helperRecovery.current_machine_state.primary_blocker),
          recommended_next_step: normalizeString(
            helperRecovery.current_machine_state.recommended_next_step
          ),
        }
      : null,
    helper_route_contract: helperRecovery.helper_route_contract
      ? {
          helper_route_role: normalizeString(
            helperRecovery.helper_route_contract.helper_route_role
          ),
          helper_route_ready_verdict: normalizeString(
            helperRecovery.helper_route_contract.helper_route_ready_verdict
          ),
          required_ready_signals: dedupeStrings(
            helperRecovery.helper_route_contract.required_ready_signals || []
          ),
          reject_signals: Array.isArray(helperRecovery.helper_route_contract.reject_signals)
            ? helperRecovery.helper_route_contract.reject_signals.map((item) => ({
                signal: normalizeString(item.signal),
                reason: normalizeString(item.reason),
              }))
            : [],
        }
      : null,
    top_recommended_action: helperRecovery.top_recommended_action || null,
    operator_workflow: Array.isArray(helperRecovery.operator_workflow)
      ? helperRecovery.operator_workflow.map((item) => ({
          step_id: normalizeString(item.step_id),
          allowed_now: item.allowed_now !== false,
          description: normalizeString(item.description),
          command: normalizeString(item.command),
          command_or_ref: normalizeString(item.command_or_ref),
        }))
      : [],
    artifact_refs:
      helperRecovery.artifact_refs && typeof helperRecovery.artifact_refs === "object"
        ? helperRecovery.artifact_refs
        : null,
  };
}

function buildSample1OperatorHandoff({
  runtimeProbe = null,
  modelProbe = null,
  helperProbe = null,
  sample = null,
  unblockSummary = null,
  candidateShortlist = null,
  candidateAcceptance = null,
  candidateRegistration = null,
  helperLocalServiceRecovery = null,
} = {}) {
  const runtime = runtimeProbe && typeof runtimeProbe === "object" ? runtimeProbe : {};
  const model = modelProbe && typeof modelProbe === "object" ? modelProbe : {};
  const helper = helperProbe && typeof helperProbe === "object" ? helperProbe : {};
  const shortlist =
    candidateShortlist && typeof candidateShortlist === "object" ? candidateShortlist : {};
  const summary = unblockSummary && typeof unblockSummary === "object" ? unblockSummary : {};
  const focusSample = sample && typeof sample === "object" ? sample : null;

  const runtimeReady = summary.runtime_ready === true;
  const nativeRouteReady = !!(summary.preferred_route && summary.preferred_route.ready === true);
  const helperReady = helperRouteReady(helper);
  const currentActionId = normalizeString(summary.overall_recommended_action_id);
  const currentActionSummary = normalizeString(summary.overall_recommended_action_summary);
  const shortlistReadyCandidates = shortlistPassCandidates(shortlist);
  const nativeCandidateCount = Math.max(
    Number(summary?.preferred_route?.native_loadable_candidate_count || 0),
    Number(model?.summary?.native_loadable_embedding_candidates || model?.native_loadable_embedding_candidates || 0),
    shortlistReadyCandidates.length
  );
  const discoveredEmbeddingCandidateCount = Math.max(
    Number(shortlist?.summary?.candidates_considered || 0),
    Number(model?.summary?.discovered_embedding_candidates || model?.discovered_embedding_candidates || 0)
  );
  const compactRegistration = compactCandidateRegistrationForHandoff(candidateRegistration);
  const compactHelperLocalServiceRecovery =
    compactHelperLocalServiceRecoveryForHandoff(helperLocalServiceRecovery);
  const searchRecovery = compactRegistration && compactRegistration.search_recovery_plan
    ? compactRegistration.search_recovery_plan
    : {
        exact_path_known: false,
        exact_path_exists: false,
        exact_path_shortlist_refresh_command: "",
        exact_path_validation_command: "",
        explicit_model_path_shortlist_command_template: [
          "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js",
          "  --task-kind embedding",
          "  --model-path <absolute_model_dir>",
        ].join(" \\\n"),
        explicit_model_path_validation_command_template: [
          "node scripts/generate_lpr_w3_03_sample1_candidate_validation.js",
          "  --model-path <absolute_model_dir>",
          "  --task-kind embedding",
        ].join(" \\\n"),
        wide_shortlist_search_command: [
          "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js",
          "  --task-kind embedding",
          "  --wide-common-user-roots",
        ].join(" \\\n"),
        custom_scan_root_shortlist_command_template: [
          "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js",
          "  --task-kind embedding",
          "  --scan-root <absolute_search_root>",
        ].join(" \\\n"),
        preferred_next_step: "refresh_or_widen_machine_readable_search_then_revalidate_exact_path",
      };

  let handoffState = "blocked";
  let blockerClass = "sample1_unclassified";
  if (!runtimeReady) {
    blockerClass = "runtime_unavailable";
  } else if (nativeRouteReady) {
    handoffState = "ready_to_execute";
    blockerClass = "native_route_ready";
  } else if (discoveredEmbeddingCandidateCount === 0) {
    blockerClass = "native_embedding_model_missing";
  } else if (
    normalizeString(summary.preferred_route && summary.preferred_route.blocker).includes("unsupported_quantization_config")
  ) {
    blockerClass = "current_embedding_dirs_incompatible_with_native_transformers_load";
  } else {
    blockerClass = "native_embedding_model_not_confirmed";
  }

  return {
    schema_version: "xhub.lpr_w3_03_sample1_operator_handoff.v1",
    sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
    handoff_state: handoffState,
    blocker_class: blockerClass,
    top_recommended_action: {
      action_id: currentActionId || "inspect_sample1_operator_handoff",
      action_summary:
        currentActionSummary ||
        "Inspect runtime, native model-dir probe, and helper probe before attempting sample1.",
      owner: nativeRouteReady ? "Hub-L5 + operator" : "operator",
    },
    route_policy: {
      primary_route: "native_embedding_model_dir",
      secondary_route: "helper_bridge_reference",
      helper_is_reference_only: true,
      helper_ready: helperReady,
    },
    readiness: {
      runtime_ready: runtimeReady,
      native_route_ready: nativeRouteReady,
      helper_route_ready: helperReady,
      discovered_embedding_candidate_count: discoveredEmbeddingCandidateCount,
      native_candidate_count: nativeCandidateCount,
    },
    checked_sources: {
      scan_roots: Array.isArray(shortlist.scan_roots) && shortlist.scan_roots.length > 0
        ? shortlist.scan_roots.map((item) => ({
            path: normalizeString(item && item.path),
            present: item && item.present === true,
          }))
        : Array.isArray(model.scan_roots)
          ? model.scan_roots.map((item) => ({
            path: normalizeString(item && item.path),
            present: item && item.present === true,
          }))
          : [],
      catalog_paths:
        model && model.catalog_sources && Array.isArray(model.catalog_sources.catalog_paths)
          ? dedupeStrings(model.catalog_sources.catalog_paths)
          : [],
    },
    search_recovery: searchRecovery,
    rejected_current_candidates: sample1RejectedCandidates(model),
    native_execution_contract: {
      provider: "transformers",
      task_kind: "embedding",
      must_pass: [
        "AutoConfig.from_pretrained(model_path, local_files_only=true, trust_remote_code=false)",
        "AutoTokenizer.from_pretrained(model_path, local_files_only=true, trust_remote_code=false)",
        "AutoModel.from_pretrained(...) or AutoModelForCausalLM.from_pretrained(...) must succeed on the selected ready runtime",
      ],
      reject_if: [
        "model only works behind helper-only or provider-specific shims",
        "quantization_config is incompatible with the selected torch/transformers runtime",
        "no real local model directory path can be recorded into sample1 evidence",
      ],
    },
    operator_steps: nativeRouteReady
      ? [
          "Use the best native-loadable embedding model dir reported by the model probe.",
          "If you need the hard accept/reject contract before execution, read `node scripts/generate_lpr_w3_03_sample1_candidate_acceptance.js` output first.",
          focusSample ? `Generate or refresh the sample scaffold: ${renderPrepareCommand(focusSample)}` : "",
          "Capture a real embedding run with real input text, monitor snapshot, and diagnostics export.",
          focusSample ? `Finalize the sample from the scaffold dir: ${renderFinalizeCommand(focusSample)}` : "",
          "Regenerate QA and verify `NO_GO(require_real_samples_pending)` moves forward honestly.",
        ].filter(Boolean)
      : [
          "Source or register one real torch/transformers-native embedding model directory on this machine.",
          "Read `node scripts/generate_lpr_w3_03_sample1_candidate_acceptance.js` output to see the hard accept/reject contract before importing or validating a new dir.",
          compactHelperLocalServiceRecovery
            ? "If you still need the helper secondary route, read `node scripts/generate_lpr_w3_03_sample1_helper_local_service_recovery.js` and satisfy its ready contract before trusting LM Studio local service."
            : "",
          "Generate a fail-closed registration packet for that exact path with `node scripts/generate_lpr_w3_03_sample1_candidate_registration_packet.js --model-path <absolute_model_dir>` so the normalized dir, proposed catalog payload, and target catalog paths are machine-readable before any manual catalog write.",
          "Inspect `candidate_registration.catalog_patch_plan_summary` or run `node scripts/generate_lpr_w3_03_sample1_candidate_catalog_patch_plan.js` so any later manual patch keeps one chosen runtime base's models_catalog.json + models_state.json aligned as a pair.",
          "Run `node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js` first to see which local dirs were searched and why each one is PASS or NO_GO.",
          "If you suspect the model lives in a common user download location, widen the search with `node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js --wide-common-user-roots` before assuming the machine has no other candidate.",
          "Validate that exact candidate path with `node scripts/generate_lpr_w3_03_sample1_candidate_validation.js --model-path <absolute_model_dir>` before attempting sample1.",
          "Re-run runtime/model/helper/status probes to confirm `native_loadable_embedding_candidates>=1`.",
          focusSample ? `Generate or refresh the sample scaffold: ${renderPrepareCommand(focusSample)}` : "",
          "Execute a real embedding run and capture monitor snapshot + diagnostics export + real input artifact.",
          focusSample ? `Finalize the sample from the scaffold dir: ${renderFinalizeCommand(focusSample)}` : "",
          "Regenerate QA and verify the gate moves with real evidence only.",
        ].filter(Boolean),
    capture_requirements: focusSample
      ? {
          recommended_evidence_dir: recommendedEvidenceDir(focusSample),
          recommended_template_path: recommendedTemplatePath(focusSample),
          required_capture: Array.isArray(focusSample.what_to_capture) ? focusSample.what_to_capture : [],
          required_machine_fields: Array.isArray(focusSample.machine_readable_fields_to_record)
            ? focusSample.machine_readable_fields_to_record
            : [],
        }
      : null,
    helper_local_service_recovery: compactHelperLocalServiceRecovery,
    candidate_acceptance: compactCandidateAcceptanceForHandoff(candidateAcceptance),
    candidate_registration: compactRegistration,
    command_refs: dedupeStrings([
      "node scripts/generate_lpr_w3_03_b_runtime_candidate_probe.js",
      "node scripts/generate_lpr_w3_03_c_model_native_loadability_probe.js",
      "node scripts/generate_lpr_w3_03_sample1_candidate_acceptance.js",
      "node scripts/generate_lpr_w3_03_sample1_helper_local_service_recovery.js",
      "node scripts/generate_lpr_w3_03_sample1_candidate_registration_packet.js --model-path <absolute_model_dir>",
      "node scripts/generate_lpr_w3_03_sample1_candidate_catalog_patch_plan.js",
      "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js",
      "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js --wide-common-user-roots",
      "node scripts/generate_lpr_w3_03_sample1_candidate_validation.js --model-path <absolute_model_dir>",
      "node scripts/generate_lpr_w3_03_d_helper_bridge_probe.js",
      "node scripts/lpr_w3_03_require_real_status.js --json",
      focusSample ? renderPrepareCommand(focusSample) : "",
      focusSample ? renderFinalizeCommand(focusSample) : "",
      "node scripts/generate_lpr_w3_03_a_require_real_evidence.js",
    ]),
  };
}

function buildSample1UnblockSummary({
  runtimeProbe = null,
  modelProbe = null,
  helperProbe = null,
  sample = null,
  candidateShortlist = null,
  candidateRegistration = null,
} = {}) {
  const runtime = runtimeProbe && typeof runtimeProbe === "object" ? runtimeProbe : {};
  const model = modelProbe && typeof modelProbe === "object" ? modelProbe : {};
  const helper = helperProbe && typeof helperProbe === "object" ? helperProbe : {};
  const focusSample = sample && typeof sample === "object" ? sample : null;

  const runtimeVerdict = normalizeString(runtime.verdict);
  const runtimeBlocker = normalizeString(runtime.blocker_reason);
  const readyCandidate = bestReadySample1Candidate(candidateShortlist, candidateRegistration);
  const runtimeReady =
    runtimeVerdict !== "sample1_blocked_by_runtime" && runtimeBlocker !== "missing_runtime";
  const nativeCandidateCount = Math.max(
    Number(model.native_loadable_embedding_candidates || 0),
    shortlistPassCandidates(candidateShortlist).length,
    readyCandidate.model_path ? 1 : 0
  );
  const bestNativeCandidateModelPath = normalizeString(
    readyCandidate.model_path || model.best_native_candidate_model_path
  );
  const nativeRouteReady = runtimeReady && nativeCandidateCount > 0 && !!bestNativeCandidateModelPath;
  const modelBlocker = nativeRouteReady ? "" : normalizeString(model.primary_blocker);
  const modelNextStep = nativeRouteReady
    ? "prepare_and_execute_sample1_real_run"
    : normalizeString(model.recommended_next_step);
  const helperBlocker = normalizeString(helper.primary_blocker);
  const helperNextStep = normalizeString(helper.recommended_next_step);
  const helperReady = helperRouteReady(helper);
  const helperLocalServiceEnabled =
    helper && helper.lmstudio_environment && typeof helper.lmstudio_environment === "object"
      ? helper.lmstudio_environment.enable_local_service
      : null;

  let overallRecommendedActionId = "inspect_sample1_unblock_state";
  let overallRecommendedActionSummary = "Inspect runtime, native model-dir, and helper probe outputs before rerunning sample1.";

  if (runtimeVerdict === "sample1_pass") {
    overallRecommendedActionId = "finalize_sample1_real_run";
    overallRecommendedActionSummary =
      "Sample1 already has a passing runtime probe; capture real evidence and finalize the require-real sample.";
  } else if (!runtimeReady || modelBlocker === "no_ready_transformers_runtime_candidate") {
    overallRecommendedActionId = "restore_ready_transformers_runtime";
    overallRecommendedActionSummary =
      "Restore one ready transformers runtime candidate first; sample1 cannot proceed until the runtime itself is ready.";
  } else if (nativeRouteReady) {
    overallRecommendedActionId = "run_sample1_with_best_native_embedding_dir";
    overallRecommendedActionSummary =
      `Use the best native-loadable real embedding model dir for sample1: ${bestNativeCandidateModelPath}`;
  } else if (modelBlocker.includes("unsupported_quantization_config")) {
    overallRecommendedActionId = "source_native_loadable_embedding_model_dir";
    overallRecommendedActionSummary =
      "Current embedding dirs look like LM Studio / MLX quantized layouts, not torch/transformers-native dirs. Source one native-loadable real embedding model dir first.";
  } else if (helperReady) {
    overallRecommendedActionId = "probe_helper_bridge_as_secondary_route";
    overallRecommendedActionSummary =
      "Helper bridge looks ready, but keep it as a secondary route; prefer a native-loadable real embedding dir when available.";
  } else if (helperLocalServiceEnabled === false) {
    overallRecommendedActionId = "prefer_native_dir_over_helper_settings";
    overallRecommendedActionSummary =
      "Helper bridge is currently blocked by LM Studio local service being disabled. Keep native-loadable embedding dir as the primary unblock path.";
  }

  const notes = [
    "Prefer a torch/transformers-native real embedding model dir before relying on the LM Studio helper bridge.",
    helperLocalServiceEnabled === false
      ? nativeRouteReady
        ? "LM Studio helper local service is still disabled, but it is only a secondary/reference route once a native embedding dir is ready."
        : "Current helper bridge path is blocked because LM Studio local service is disabled on this machine."
      : "",
    nativeRouteReady
      ? "A native-loadable embedding dir is already available, so sample1 can move from diagnosis to real execution."
      : "",
  ].filter(Boolean);

  const blockers = nativeRouteReady
    ? dedupeStrings([])
    : dedupeStrings([
        runtimeBlocker,
        modelBlocker,
        helperBlocker,
      ]);

  return {
    schema_version: "xhub.lpr_w3_03_sample1_unblock_summary.v1",
    sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
    runtime_ready: runtimeReady,
    execution_ready: runtimeVerdict === "sample1_pass" || nativeRouteReady,
    overall_recommended_action_id: overallRecommendedActionId,
    overall_recommended_action_summary: overallRecommendedActionSummary,
    current_blockers: blockers,
    preferred_route: {
      route_id: "native_embedding_model_dir",
      priority: "primary",
      ready: nativeRouteReady,
      blocker: modelBlocker,
      next_step: modelNextStep,
      best_model_path: bestNativeCandidateModelPath,
      native_loadable_candidate_count: nativeCandidateCount,
    },
    secondary_route: {
      route_id: "helper_bridge_reference",
      priority: "secondary",
      reference_only: true,
      ready: helperReady,
      blocker: helperBlocker,
      next_step: helperNextStep,
      helper_binary_found: helper.helper_binary_found === true,
      server_models_endpoint_ok: helper.server_models_endpoint_ok === true,
      helper_local_service_enabled: helperLocalServiceEnabled,
    },
    notes,
    command_refs: dedupeStrings([
      focusSample ? renderPrepareCommand(focusSample) : "",
      focusSample ? renderFinalizeCommand(focusSample) : "",
      "node scripts/generate_lpr_w3_03_b_runtime_candidate_probe.js",
      "node scripts/generate_lpr_w3_03_c_model_native_loadability_probe.js",
      "node scripts/generate_lpr_w3_03_d_helper_bridge_probe.js",
      "node scripts/generate_lpr_w3_03_a_require_real_evidence.js",
    ]),
  };
}

function findFocusSample(samples, sampleId) {
  if (sampleId) {
    return samples.find((sample) => String(sample.sample_id || "").trim() === sampleId) || null;
  }
  return samples.find((sample) => !isPassed(sample)) || samples[0] || null;
}

function recommendedEvidenceDir(sample) {
  return `build/reports/lpr_w3_03_require_real/${sample.sample_id}`;
}

function recommendedTemplatePath(sample) {
  return `${recommendedEvidenceDir(sample)}/machine_readable_template.v1.json`;
}

function recommendedCompletionNotePath(sample) {
  return `${recommendedEvidenceDir(sample)}/completion_notes.txt`;
}

function exampleValueForField(sample, fieldName) {
  const checks = Array.isArray(sample.required_checks) ? sample.required_checks : [];
  const directCheck = checks.find((check) => String(check.field || "").trim() === fieldName) || null;

  if (directCheck) {
    if (Object.prototype.hasOwnProperty.call(directCheck, "equals")) {
      return typeof directCheck.equals === "string" ? directCheck.equals : JSON.stringify(directCheck.equals);
    }
    if (Array.isArray(directCheck.one_of) && directCheck.one_of.length > 0) {
      const first = directCheck.one_of[0];
      return typeof first === "string" ? first : JSON.stringify(first);
    }
    if (Array.isArray(directCheck.contains_all) && directCheck.contains_all.length > 0) {
      return JSON.stringify(directCheck.contains_all);
    }
    if (typeof directCheck.min === "number") {
      return String(directCheck.min);
    }
    if (typeof directCheck.max === "number") {
      return String(directCheck.max);
    }
    if (Object.prototype.hasOwnProperty.call(directCheck, "not_equals")) {
      return typeof directCheck.not_equals === "string" && directCheck.not_equals === ""
        ? `<${fieldName}>`
        : JSON.stringify(directCheck.not_equals);
    }
  }

  const currentValue = sample[fieldName];
  if (typeof currentValue === "boolean") return JSON.stringify(currentValue);
  if (typeof currentValue === "number") return String(currentValue);
  if (Array.isArray(currentValue)) return JSON.stringify(currentValue);
  if (fieldName.endsWith("_id")) return `<${fieldName}>`;
  return `<${fieldName}>`;
}

function renderUpdateCommand(sample) {
  return [
    "node scripts/update_lpr_w3_03_require_real_capture_bundle.js",
    `  --scaffold-dir ${recommendedEvidenceDir(sample)}`,
    "  --status passed",
    "  --success true",
    "  --note <operator_notes>",
  ].join(" \\\n");
}

function renderFinalizeCommand(sample) {
  return [
    "node scripts/finalize_lpr_w3_03_require_real_sample.js",
    `  --scaffold-dir ${recommendedEvidenceDir(sample)}`,
  ].join(" \\\n");
}

function renderPrepareCommand(sample) {
  return `node scripts/prepare_lpr_w3_03_require_real_sample.js --sample-id ${sample.sample_id}`;
}

function buildSummary(bundle, qa, focusSample, allSamples) {
  const samples = Array.isArray(bundle.samples) ? bundle.samples : [];
  const resolvedBundlePath = resolveBundlePath();
  const resolvedQAPath = resolveRequireRealEvidencePath();
  const resolvedRuntimeProbePath = resolveRuntimeProbePath();
  const resolvedModelProbePath = resolveModelProbePath();
  const resolvedHelperProbePath = resolveHelperProbePath();
  const reportsDir = resolveReportsDir();
  const resolvedCandidateAcceptancePath = path.join(
    reportsDir,
    "lpr_w3_03_sample1_candidate_acceptance.v1.json"
  );
  const resolvedHelperLocalServiceRecoveryPath = path.join(
    reportsDir,
    "lpr_w3_03_sample1_helper_local_service_recovery.v1.json"
  );
  const resolvedCandidateShortlistPath = path.join(
    reportsDir,
    "lpr_w3_03_sample1_candidate_shortlist.v1.json"
  );
  const resolvedCandidateWideShortlistPath = path.join(
    reportsDir,
    "lpr_w3_03_sample1_candidate_shortlist.wide_scan.v1.json"
  );
  const resolvedCandidateRegistrationPath = path.join(
    reportsDir,
    "lpr_w3_03_sample1_candidate_registration_packet.v1.json"
  );
  const executedSamples = samples.filter(isExecuted);
  const passedSamples = samples.filter(isPassed);
  const failedSamples = samples.filter((sample) => isExecuted(sample) && sample.success_boolean === false);
  const pendingSamples = samples.filter((sample) => !isPassed(sample));
  const runtimeProbe = readJSONIfExists(resolvedRuntimeProbePath);
  const modelProbe = readJSONIfExists(resolvedModelProbePath);
  const helperProbe = readJSONIfExists(resolvedHelperProbePath);
  const helperLocalServiceRecovery = readJSONIfExists(resolvedHelperLocalServiceRecoveryPath);
  const candidateShortlist = selectPreferredSample1Shortlist(
    readJSONIfExists(resolvedCandidateShortlistPath),
    readJSONIfExists(resolvedCandidateWideShortlistPath)
  );
  const candidateAcceptance = readJSONIfExists(resolvedCandidateAcceptancePath);
  const candidateRegistration = readJSONIfExists(resolvedCandidateRegistrationPath);
  const sample1RuntimeProbe = compactSample1RuntimeProbe(runtimeProbe);
  const sample1ModelProbe = compactSample1ModelProbe(modelProbe);
  const sample1HelperProbe = compactSample1HelperProbe(helperProbe);
  const sample1ReferenceSample = samples.find(
    (sample) => normalizeString(sample.sample_id) === "lpr_rr_01_embedding_real_model_dir_executes"
  ) || focusSample;
  const sample1UnblockSummary = buildSample1UnblockSummary({
    runtimeProbe: sample1RuntimeProbe,
    modelProbe: sample1ModelProbe,
    helperProbe: sample1HelperProbe,
    sample: sample1ReferenceSample,
    candidateShortlist,
    candidateRegistration,
  });
  const sample1OperatorHandoff = buildSample1OperatorHandoff({
    runtimeProbe: sample1RuntimeProbe,
    modelProbe,
    helperProbe: sample1HelperProbe,
    sample: sample1ReferenceSample,
    unblockSummary: sample1UnblockSummary,
    candidateShortlist,
    candidateAcceptance,
    candidateRegistration,
    helperLocalServiceRecovery,
  });
  const qaContext = compactQAContext(qa);

  return {
    bundle_path: path.relative(repoRoot, resolvedBundlePath),
    qa_path: path.relative(repoRoot, resolvedQAPath),
    runtime_probe_path: path.relative(repoRoot, resolvedRuntimeProbePath),
    model_probe_path: path.relative(repoRoot, resolvedModelProbePath),
    helper_probe_path: path.relative(repoRoot, resolvedHelperProbePath),
    bundle_status: String(bundle.status || "").trim() || "unknown",
    qa_gate_verdict: qaContext.gate_verdict,
    qa_release_stance: qaContext.release_stance,
    qa_verdict_reason: qaContext.verdict_reason,
    qa_next_required_artifacts: qaContext.next_required_artifacts,
    qa_machine_decision: qaContext.machine_decision,
    sample1_runtime_probe: sample1RuntimeProbe,
    sample1_model_probe: sample1ModelProbe,
    sample1_helper_probe: sample1HelperProbe,
    sample1_unblock_summary: sample1UnblockSummary,
    sample1_operator_handoff: sample1OperatorHandoff,
    total_samples: samples.length,
    executed_count: executedSamples.length,
    passed_count: passedSamples.length,
    failed_count: failedSamples.length,
    pending_count: pendingSamples.length,
    next_pending_sample_id: focusSample ? focusSample.sample_id : "",
    next_pending_sample: focusSample
      ? {
          sample_id: focusSample.sample_id,
          status: focusSample.status,
          precondition: focusSample.precondition || "",
          expected_result: focusSample.expected_result || "",
          what_to_capture: Array.isArray(focusSample.what_to_capture) ? focusSample.what_to_capture : [],
          machine_readable_fields_to_record: Array.isArray(focusSample.machine_readable_fields_to_record)
            ? focusSample.machine_readable_fields_to_record
            : [],
          recommended_evidence_dir: recommendedEvidenceDir(focusSample),
          recommended_template_path: recommendedTemplatePath(focusSample),
          recommended_completion_note_path: recommendedCompletionNotePath(focusSample),
          prepare_command: renderPrepareCommand(focusSample),
          suggested_finalize_command: renderFinalizeCommand(focusSample),
          suggested_update_command: renderUpdateCommand(focusSample),
          regenerate_command: "node scripts/generate_lpr_w3_03_a_require_real_evidence.js",
        }
      : null,
    all_sample_details: allSamples
      ? samples.map((sample) => ({
          sample_id: sample.sample_id,
          status: sample.status,
          precondition: sample.precondition || "",
          expected_result: sample.expected_result || "",
          what_to_capture: Array.isArray(sample.what_to_capture) ? sample.what_to_capture : [],
          machine_readable_fields_to_record: Array.isArray(sample.machine_readable_fields_to_record)
            ? sample.machine_readable_fields_to_record
            : [],
          recommended_evidence_dir: recommendedEvidenceDir(sample),
          recommended_template_path: recommendedTemplatePath(sample),
          recommended_completion_note_path: recommendedCompletionNotePath(sample),
          prepare_command: renderPrepareCommand(sample),
          suggested_finalize_command: renderFinalizeCommand(sample),
          suggested_update_command: renderUpdateCommand(sample),
          regenerate_command: "node scripts/generate_lpr_w3_03_a_require_real_evidence.js",
          performed_at: sample.performed_at || "",
          success_boolean: sample.success_boolean,
          evidence_ref_count: Array.isArray(sample.evidence_refs) ? sample.evidence_refs.length : 0,
        }))
      : undefined,
    sample_statuses: allSamples
      ? samples.map((sample) => ({
          sample_id: sample.sample_id,
          status: sample.status,
          performed_at: sample.performed_at || "",
          success_boolean: sample.success_boolean,
          evidence_ref_count: Array.isArray(sample.evidence_refs) ? sample.evidence_refs.length : 0,
        }))
      : undefined,
  };
}

function buildHumanLines(summary) {
  const lines = [];
  lines.push("LPR-W3-03 require-real status");
  lines.push(`bundle_status: ${summary.bundle_status}`);
  lines.push(`qa_gate_verdict: ${summary.qa_gate_verdict}`);
  lines.push(`qa_release_stance: ${summary.qa_release_stance}`);
  if (summary.qa_verdict_reason) {
    lines.push(`qa_verdict_reason: ${summary.qa_verdict_reason}`);
  }
  if (
    summary.qa_machine_decision &&
    Array.isArray(summary.qa_machine_decision.sample1_current_blockers) &&
    summary.qa_machine_decision.sample1_current_blockers.length > 0
  ) {
    lines.push("qa_sample1_current_blockers:");
    for (const blocker of summary.qa_machine_decision.sample1_current_blockers) {
      lines.push(`  - ${blocker}`);
    }
  }
  if (Array.isArray(summary.qa_next_required_artifacts) && summary.qa_next_required_artifacts.length > 0) {
    lines.push("next_required_artifacts:");
    for (const item of summary.qa_next_required_artifacts) {
      lines.push(`  - ${item}`);
    }
  }
  if (summary.sample1_runtime_probe && summary.sample1_runtime_probe.verdict) {
    lines.push(`sample1_runtime_probe: ${summary.sample1_runtime_probe.verdict} (${summary.sample1_runtime_probe.blocker_reason || "no_blocker_reason"})`);
  }
  if (summary.sample1_model_probe && summary.sample1_model_probe.primary_blocker) {
    lines.push(`sample1_model_probe: ${summary.sample1_model_probe.primary_blocker}`);
    lines.push(`sample1_next_step: ${summary.sample1_model_probe.recommended_next_step}`);
  }
  if (summary.sample1_helper_probe && summary.sample1_helper_probe.primary_blocker) {
    lines.push(`sample1_helper_probe: ${summary.sample1_helper_probe.primary_blocker}`);
  }
  if (summary.sample1_unblock_summary) {
    lines.push(`sample1_recommended_action: ${summary.sample1_unblock_summary.overall_recommended_action_id}`);
    lines.push(`sample1_recommended_summary: ${summary.sample1_unblock_summary.overall_recommended_action_summary}`);
    lines.push(
      `sample1_native_route: ${summary.sample1_unblock_summary.preferred_route.ready ? "ready" : "blocked"} (${summary.sample1_unblock_summary.preferred_route.blocker || "no_blocker"})`
    );
    lines.push(
      `sample1_helper_route: ${summary.sample1_unblock_summary.secondary_route.ready ? "ready" : "blocked"} (${summary.sample1_unblock_summary.secondary_route.blocker || "no_blocker"})`
    );
  }
  if (summary.sample1_operator_handoff) {
    lines.push(
      `sample1_operator_handoff: ${summary.sample1_operator_handoff.handoff_state} (${summary.sample1_operator_handoff.blocker_class})`
    );
  }
  lines.push(
    `progress: executed=${summary.executed_count}/${summary.total_samples}, passed=${summary.passed_count}, failed=${summary.failed_count}, pending=${summary.pending_count}`
  );

  if (Array.isArray(summary.all_sample_details) && summary.all_sample_details.length > 0) {
    lines.push("samples:");
    for (const sample of summary.all_sample_details) {
      lines.push(`sample_id: ${sample.sample_id}`);
      lines.push(`status: ${sample.status}`);
      lines.push(`performed_at: ${sample.performed_at}`);
      lines.push(`success_boolean: ${sample.success_boolean}`);
      lines.push(`evidence_ref_count: ${sample.evidence_ref_count}`);
      lines.push(`precondition: ${sample.precondition}`);
      lines.push(`expected_result: ${sample.expected_result}`);
      lines.push(`recommended_evidence_dir: ${sample.recommended_evidence_dir}`);
      lines.push(`recommended_template_path: ${sample.recommended_template_path}`);
      lines.push(`recommended_completion_note_path: ${sample.recommended_completion_note_path}`);
      lines.push("what_to_capture:");
      for (const item of sample.what_to_capture) {
        lines.push(`  - ${item}`);
      }
      lines.push("machine_readable_fields_to_record:");
      for (const item of sample.machine_readable_fields_to_record) {
        lines.push(`  - ${item}`);
      }
      lines.push(`prepare_command: ${sample.prepare_command}`);
      lines.push("suggested_finalize_command:");
      lines.push(sample.suggested_finalize_command);
      lines.push("suggested_update_command:");
      lines.push(sample.suggested_update_command);
      lines.push(`regenerate_command: ${sample.regenerate_command}`);
      lines.push("---");
    }
    return lines;
  }

  if (!summary.next_pending_sample) {
    lines.push("next_sample: none");
    return lines;
  }

  const sample = summary.next_pending_sample;
  lines.push(`next_sample: ${sample.sample_id}`);
  lines.push(`precondition: ${sample.precondition}`);
  lines.push(`expected_result: ${sample.expected_result}`);
  lines.push(`recommended_evidence_dir: ${sample.recommended_evidence_dir}`);
  lines.push(`recommended_template_path: ${sample.recommended_template_path}`);
  lines.push(`recommended_completion_note_path: ${sample.recommended_completion_note_path}`);
  lines.push("what_to_capture:");
  for (const item of sample.what_to_capture) {
    lines.push(`  - ${item}`);
  }
  lines.push("machine_readable_fields_to_record:");
  for (const item of sample.machine_readable_fields_to_record) {
    lines.push(`  - ${item}`);
  }
  lines.push(`prepare_command: ${sample.prepare_command}`);
  lines.push("suggested_finalize_command:");
  lines.push(sample.suggested_finalize_command);
  lines.push("suggested_update_command:");
  lines.push(sample.suggested_update_command);
  lines.push(`regenerate_command: ${sample.regenerate_command}`);
  return lines;
}

function printHuman(summary) {
  const lines = buildHumanLines(summary);
  process.stdout.write(`${lines.join("\n")}\n`);
}

function main() {
  try {
    const args = parseArgs(process.argv);
    const bundle = readCaptureBundle();
    const qa = readJSONIfExists(resolveRequireRealEvidencePath());
    const samples = Array.isArray(bundle.samples) ? bundle.samples : [];
    const focusSample = findFocusSample(samples, args.sampleId);

    if (args.sampleId && !focusSample) {
      throw new Error(`sample not found: ${args.sampleId}`);
    }

    const summary = buildSummary(bundle, qa, focusSample, args.all);
    if (args.json) {
      process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
      return;
    }
    printHuman(summary);
  } catch (error) {
    process.stderr.write(`${String(error.message || error)}\n`);
    printUsage(1);
  }
}

module.exports = {
  buildSummary,
  buildSample1OperatorHandoff,
  buildSample1UnblockSummary,
  compactSample1HelperProbe,
  compactSample1ModelProbe,
  compactSample1RuntimeProbe,
  compactCandidateAcceptanceForHandoff,
  compactCandidateRegistrationForHandoff,
  compactHelperLocalServiceRecoveryForHandoff,
  compactQAContext,
  selectPreferredSample1Shortlist,
  exampleValueForField,
  findFocusSample,
  helperRouteReady,
  buildHumanLines,
  parseArgs,
  readJSON,
  recommendedCompletionNotePath,
  recommendedEvidenceDir,
  recommendedTemplatePath,
  renderFinalizeCommand,
  renderPrepareCommand,
  renderUpdateCommand,
};

if (require.main === module) {
  main();
}
