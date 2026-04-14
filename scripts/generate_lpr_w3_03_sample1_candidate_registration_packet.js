#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const {
  readCaptureBundle,
  repoRoot,
  resolveReportsDir,
  writeJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");
const {
  findFocusSample,
  renderFinalizeCommand,
  renderPrepareCommand,
} = require("./lpr_w3_03_require_real_status.js");
const {
  buildSample1CandidateValidationReport,
  validationCommand,
  validationCommandTemplate,
} = require("./generate_lpr_w3_03_sample1_candidate_validation.js");
const {
  buildStaticMarkers,
  chooseReadyRuntime,
  classifyLoadability,
  collectModelDiscoveryInputs,
  defaultCatalogPaths,
  directoryLooksLikeModel,
  normalizeCatalogModelDir,
  normalizeTaskKindHint,
  pathExists,
  readCatalogModelRefs,
  resolveKnownModelDiscoveryForPath,
  runNativeLoadabilityProbe,
  slugForModel,
} = require("./generate_lpr_w3_03_c_model_native_loadability_probe.js");
const {
  buildCatalogPatchPlan,
  catalogPatchPlanCommand,
  compactCatalogPatchPlanSummary,
  defaultOutputPath: defaultCatalogPatchPlanOutputPath,
} = require("./generate_lpr_w3_03_sample1_candidate_catalog_patch_plan.js");

const defaultOutputPath = path.join(
  resolveReportsDir(),
  "lpr_w3_03_sample1_candidate_registration_packet.v1.json"
);
const artifactRoot = path.join(
  resolveReportsDir(),
  "lpr_w3_03_require_real",
  "sample1_candidate_registration_packet"
);
const acceptanceReportPath = path.join(
  resolveReportsDir(),
  "lpr_w3_03_sample1_candidate_acceptance.v1.json"
);

function isoNow() {
  return new Date().toISOString();
}

function normalizeString(value) {
  return String(value || "").trim();
}

function dedupeStrings(values = []) {
  const out = [];
  const seen = new Set();
  for (const value of values) {
    const text = normalizeString(value);
    if (!text || seen.has(text)) continue;
    seen.add(text);
    out.push(text);
  }
  return out;
}

function relPath(targetPath) {
  const resolved = path.resolve(String(targetPath || ""));
  const relative = path.relative(repoRoot, resolved);
  if (!relative || relative.startsWith("..")) return resolved;
  return relative.split(path.sep).join("/");
}

function shellQuote(value) {
  const text = String(value || "");
  if (/^[A-Za-z0-9_./:@=,+-]+$/.test(text)) return text;
  return `'${text.replace(/'/g, `'\\''`)}'`;
}

function sha8(text) {
  return crypto.createHash("sha256").update(String(text || "")).digest("hex").slice(0, 8);
}

function sanitizeModelId(value) {
  return normalizeString(value)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function basenameNameHint(modelDir) {
  const base = normalizeString(path.basename(modelDir));
  return base || "Local Model";
}

function compactCatalogRefs(catalogEntryRefs = []) {
  return catalogEntryRefs.map((entry) => ({
    catalog_path: normalizeString(entry.catalog_path),
    model_id: normalizeString(entry.model_id),
    model_name: normalizeString(entry.model_name),
    backend: normalizeString(entry.backend),
    task_kinds: Array.isArray(entry.task_kinds) ? entry.task_kinds.map((item) => normalizeString(item)) : [],
    model_path: normalizeString(entry.model_path),
  }));
}

function readJSONIfExists(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function taskProfile(taskKind) {
  const normalizedTaskKind = normalizeTaskKindHint(taskKind) || "embedding";
  switch (normalizedTaskKind) {
    case "speech_to_text":
      return {
        input_modalities: ["audio"],
        output_modalities: ["text"],
        model_format: "huggingface",
      };
    case "vision":
      return {
        input_modalities: ["image", "text"],
        output_modalities: ["text"],
        model_format: "huggingface",
      };
    case "text_generate":
      return {
        input_modalities: ["text"],
        output_modalities: ["text"],
        model_format: "huggingface",
      };
    case "embedding":
    default:
      return {
        input_modalities: ["text"],
        output_modalities: ["embedding"],
        model_format: "huggingface",
      };
  }
}

function registrationCommand(modelDir, taskKind, extraArgs = {}) {
  const parts = [
    "node scripts/generate_lpr_w3_03_sample1_candidate_registration_packet.js",
    `  --model-path ${shellQuote(modelDir)}`,
    `  --task-kind ${shellQuote(taskKind)}`,
  ];
  if (normalizeString(extraArgs.modelId)) {
    parts.push(`  --model-id ${shellQuote(extraArgs.modelId)}`);
  }
  if (normalizeString(extraArgs.modelName)) {
    parts.push(`  --model-name ${shellQuote(extraArgs.modelName)}`);
  }
  return parts.join(" \\\n");
}

function shortlistCommand(modelDir, taskKind) {
  return [
    "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js",
    `  --task-kind ${shellQuote(taskKind)}`,
    `  --model-path ${shellQuote(modelDir)}`,
  ].join(" \\\n");
}

function wideShortlistCommand(taskKind) {
  return [
    "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js",
    `  --task-kind ${shellQuote(taskKind)}`,
    "  --wide-common-user-roots",
  ].join(" \\\n");
}

function shortlistCommandTemplate(taskKind) {
  return [
    "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js",
    `  --task-kind ${shellQuote(taskKind)}`,
    "  --model-path <absolute_model_dir>",
  ].join(" \\\n");
}

function scanRootShortlistCommandTemplate(taskKind) {
  return [
    "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js",
    `  --task-kind ${shellQuote(taskKind)}`,
    "  --scan-root <absolute_search_root>",
  ].join(" \\\n");
}

function buildDiscoveryInputs(extraCatalogPaths = []) {
  const base = collectModelDiscoveryInputs();
  const catalogPaths = dedupeStrings([
    ...defaultCatalogPaths.map((item) => path.resolve(item)),
    ...(Array.isArray(base.catalog_paths) ? base.catalog_paths : []).map((item) => path.resolve(item)),
    ...extraCatalogPaths.map((item) => path.resolve(item)),
  ]);
  const refsByKey = new Map();
  for (const catalogPath of catalogPaths) {
    if (!pathExists(catalogPath)) continue;
    for (const ref of readCatalogModelRefs(catalogPath)) {
      const key = [
        normalizeString(ref.catalog_path),
        normalizeString(ref.model_id),
        normalizeString(ref.model_dir),
      ].join("|");
      if (!refsByKey.has(key)) refsByKey.set(key, ref);
    }
  }
  return {
    scan_roots: Array.isArray(base.scan_roots) ? base.scan_roots : [],
    catalog_paths: catalogPaths,
    catalog_refs: Array.from(refsByKey.values()),
  };
}

function chooseExistingCatalogRef(existingCatalogRefs = []) {
  return existingCatalogRefs.find((entry) => normalizeString(entry.model_id)) || existingCatalogRefs[0] || null;
}

function proposeModelId({
  requestedModelId = "",
  normalizedModelDir = "",
  existingCatalogRefs = [],
  taskKind = "embedding",
} = {}) {
  const existing = chooseExistingCatalogRef(existingCatalogRefs);
  const explicit = sanitizeModelId(requestedModelId);
  if (explicit) return explicit;
  if (existing && normalizeString(existing.model_id)) return normalizeString(existing.model_id);
  const base = sanitizeModelId(path.basename(normalizedModelDir));
  const taskToken = normalizeTaskKindHint(taskKind) || "embedding";
  const prefix = taskToken === "embedding" ? "hf-embed" : `hf-${taskToken}`;
  if (!base) return `${prefix}-${sha8(normalizedModelDir)}`;
  if (base.startsWith("hf-") || base.startsWith("local-")) return base;
  return `${prefix}-${base}`;
}

function proposeModelName({
  requestedModelName = "",
  normalizedModelDir = "",
  existingCatalogRefs = [],
} = {}) {
  const explicit = normalizeString(requestedModelName);
  if (explicit) return explicit;
  const existing = chooseExistingCatalogRef(existingCatalogRefs);
  if (existing && normalizeString(existing.model_name)) return normalizeString(existing.model_name);
  return basenameNameHint(normalizedModelDir);
}

function buildProposedCatalogEntry({
  normalizedModelDir = "",
  taskKind = "embedding",
  backend = "transformers",
  requestedModelId = "",
  requestedModelName = "",
  existingCatalogRefs = [],
} = {}) {
  const normalizedTaskKind = normalizeTaskKindHint(taskKind) || "embedding";
  const profile = taskProfile(normalizedTaskKind);
  const proposedModelId = proposeModelId({
    requestedModelId,
    normalizedModelDir,
    existingCatalogRefs,
    taskKind: normalizedTaskKind,
  });
  const proposedModelName = proposeModelName({
    requestedModelName,
    normalizedModelDir,
    existingCatalogRefs,
  });
  return {
    id: proposedModelId,
    name: proposedModelName,
    backend: normalizeString(backend) || "transformers",
    runtimeProviderId: normalizeString(backend) || "transformers",
    modelPath: normalizedModelDir,
    taskKinds: [normalizedTaskKind],
    inputModalities: profile.input_modalities,
    outputModalities: profile.output_modalities,
    modelFormat: profile.model_format,
    note:
      "Generated by sample1 registration packet. Do not write this entry into a shared catalog until exact-path validation returns PASS(sample1_candidate_native_loadable_for_real_execution).",
  };
}

function buildTargetCatalogPaths({
  catalogPaths = [],
  normalizedModelDir = "",
  proposedModelEntry = null,
  validationReport = null,
} = {}) {
  const validationGateVerdict = normalizeString(
    validationReport?.machine_decision?.gate_verdict
  );
  const validationPass = validationGateVerdict === "PASS(sample1_candidate_native_loadable_for_real_execution)";
  const proposedModelId = normalizeString(proposedModelEntry?.id);

  return dedupeStrings(catalogPaths.map((item) => path.resolve(item))).map((catalogPath) => {
    const present = pathExists(catalogPath);
    const refs = present ? readCatalogModelRefs(catalogPath) : [];
    const exactMatches = refs.filter((ref) => normalizeString(ref.model_dir) === normalizeString(normalizedModelDir));
    const proposedIdConflicts = refs.filter(
      (ref) =>
        normalizeString(ref.model_id) === proposedModelId &&
        normalizeString(ref.model_dir) !== normalizeString(normalizedModelDir)
    );

    let catalogAction = "do_not_write_before_validator_pass";
    if (exactMatches.length > 0 && validationPass) {
      catalogAction = "reuse_existing_exact_dir_entry_after_validator_pass";
    } else if (exactMatches.length > 0) {
      catalogAction = "existing_entry_still_requires_validator_pass";
    } else if (proposedIdConflicts.length > 0) {
      catalogAction = "pick_different_model_id_before_manual_append";
    } else if (validationPass && present) {
      catalogAction = "manual_append_proposed_entry_after_validator_pass";
    } else if (validationPass && !present) {
      catalogAction = "create_catalog_file_then_append_proposed_entry_after_validator_pass";
    }

    return {
      catalog_path: catalogPath,
      present,
      exact_model_dir_registered: exactMatches.length > 0,
      exact_model_dir_entry_count: exactMatches.length,
      exact_model_dir_entry_refs: compactCatalogRefs(exactMatches),
      proposed_model_id: proposedModelId,
      proposed_model_id_conflict: proposedIdConflicts.length > 0,
      proposed_model_id_conflict_refs: compactCatalogRefs(proposedIdConflicts).slice(0, 3),
      catalog_write_allowed_now: validationPass && proposedIdConflicts.length === 0,
      recommended_action: catalogAction,
    };
  });
}

function buildAcceptanceContractSummary(acceptanceReport = null) {
  const acceptanceContract =
    acceptanceReport && acceptanceReport.acceptance_contract && typeof acceptanceReport.acceptance_contract === "object"
      ? acceptanceReport.acceptance_contract
      : {};
  return {
    required_gate_verdict:
      normalizeString(acceptanceContract.required_gate_verdict) ||
      "PASS(sample1_candidate_native_loadable_for_real_execution)",
    required_loadability_verdict:
      normalizeString(acceptanceContract.required_loadability_verdict) || "native_loadable",
    expected_task_kind: normalizeString(acceptanceContract.expected_task_kind) || "embedding",
    expected_provider: normalizeString(acceptanceContract.expected_provider) || "transformers",
  };
}

function buildRegistrationPacket({
  generatedAt = isoNow(),
  requestedModelPath = "",
  normalizedModelDir = "",
  expectedTaskKind = "embedding",
  backend = "transformers",
  validationReport = null,
  proposedCatalogEntry = null,
  targetCatalogPaths = [],
  existingCatalogRefs = [],
  acceptanceContract = null,
  focusSample = null,
  artifactRefs = {},
  requestedModelId = "",
  requestedModelName = "",
  catalogPatchPlanSummary = null,
} = {}) {
  const normalizedTaskKind = normalizeTaskKindHint(expectedTaskKind) || "embedding";
  const validationGateVerdict = normalizeString(validationReport?.machine_decision?.gate_verdict);
  const validationPass = validationGateVerdict === "PASS(sample1_candidate_native_loadable_for_real_execution)";
  const validationTopAction = validationReport?.machine_decision?.top_recommended_action || {};
  const validationLoadabilityVerdict = normalizeString(validationReport?.loadability?.verdict);
  const validationLoadabilityBlocker = normalizeString(validationReport?.loadability?.blocker_reason);
  const runtimeReady = validationReport?.runtime_resolution?.runtime_ready === true;
  const requestedPathExists = validationReport?.candidate_checks?.requested_path_exists === true;
  const modelDirLooksLikeModel = validationReport?.candidate_checks?.model_dir_looks_like_model === true;
  const exactCatalogRefs = Array.isArray(existingCatalogRefs) ? existingCatalogRefs : [];
  const idConflict = targetCatalogPaths.some((row) => row.proposed_model_id_conflict === true);
  const existingRegistration = exactCatalogRefs.length > 0;
  const acceptance = buildAcceptanceContractSummary({ acceptance_contract: acceptanceContract || {} });
  const catalogPatchAllowedNow = catalogPatchPlanSummary
    ? catalogPatchPlanSummary.manual_patch_allowed_now === true
    : validationPass && !idConflict;

  let actionId = "inspect_candidate_registration_packet";
  let actionSummary =
    "Inspect the registration packet, exact-path validation, and catalog targets before touching any shared catalog.";
  let nextStep = "review_packet_then_follow_validator";

  if (!requestedPathExists) {
    actionId = "fix_candidate_model_path";
    actionSummary = "The requested path does not exist. Point the registration packet at a real local model directory first.";
    nextStep = "supply_existing_model_path";
  } else if (!modelDirLooksLikeModel) {
    actionId = "point_to_actual_model_dir";
    actionSummary = "The normalized path does not yet look like a HF-style local model dir. Do not register it yet.";
    nextStep = "use_model_dir_with_config_and_weights";
  } else if (!runtimeReady) {
    actionId = "restore_ready_transformers_runtime";
    actionSummary = "The candidate dir can be inspected, but the local torch/transformers runtime is not ready, so registration must stay blocked.";
    nextStep = "restore_runtime_then_rerun_packet";
  } else if (validationPass && idConflict) {
    actionId = "change_proposed_model_id_before_catalog_write";
    actionSummary = "The candidate passes validation, but the proposed model_id collides with another directory in at least one target catalog.";
    nextStep = "pick_unique_model_id_then_append_manually";
  } else if (validationPass && existingRegistration) {
    actionId = "reuse_existing_exact_dir_registration_after_pass";
    actionSummary = "The exact dir already exists in a catalog and now passes validation; reuse or update that exact-dir entry rather than creating a duplicate.";
    nextStep = "execute_sample1_then_keep_existing_entry_consistent";
  } else if (validationPass) {
    actionId = "append_proposed_catalog_entry_after_validator_pass";
    actionSummary = "The exact dir passes validation. You can now manually append the proposed catalog entry to one chosen target catalog path.";
    nextStep = "append_proposed_entry_then_execute_sample1";
  } else if (validationLoadabilityBlocker === "unsupported_quantization_config") {
    actionId = "source_different_native_embedding_model_dir";
    actionSummary = "This directory still looks like a provider-specific quantized layout. Do not register it as sample1-ready.";
    nextStep = "source_non_quantized_native_embedding_dir_then_rerun_packet";
  } else if (existingRegistration) {
    actionId = "do_not_trust_existing_registration_without_pass";
    actionSummary = "The exact dir is already referenced by a catalog, but the validator still fails. Keep the shared catalog fail-closed until this path actually passes.";
    nextStep = "fix_candidate_or_source_different_dir";
  } else if (normalizeString(validationTopAction.action_id)) {
    actionId = normalizeString(validationTopAction.action_id);
    actionSummary =
      normalizeString(validationTopAction.action_summary) ||
      "The validator has not passed yet. Do not register this dir in a shared catalog.";
    nextStep = normalizeString(validationTopAction.next_step) || "follow_validator_action";
  }

  const resolvedExactModelPath = normalizeString(normalizedModelDir || requestedModelPath);
  const searchRecoveryPlan = {
    exact_path_known: !!resolvedExactModelPath,
    exact_path_exists: requestedPathExists,
    exact_path_shortlist_refresh_command:
      requestedPathExists && resolvedExactModelPath
        ? shortlistCommand(resolvedExactModelPath, normalizedTaskKind)
        : "",
    exact_path_validation_command:
      requestedPathExists && resolvedExactModelPath
        ? validationCommand(resolvedExactModelPath, normalizedTaskKind)
        : "",
    explicit_model_path_shortlist_command_template: shortlistCommandTemplate(normalizedTaskKind),
    explicit_model_path_validation_command_template: validationCommandTemplate(normalizedTaskKind),
    wide_shortlist_search_command: wideShortlistCommand(normalizedTaskKind),
    custom_scan_root_shortlist_command_template: scanRootShortlistCommandTemplate(normalizedTaskKind),
    preferred_next_step: validationPass
      ? "prepare_sample_after_pass"
      : runtimeReady
        ? "refresh_or_widen_machine_readable_search_then_revalidate_exact_path"
        : "restore_runtime_then_refresh_search_record",
  };

  return {
    schema_version: "xhub.lpr_w3_03_sample1_candidate_registration_packet.v1",
    generated_at: generatedAt,
    scope: "Normalize one candidate dir into a fail-closed import/register packet for LPR sample1.",
    fail_closed: true,
    sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
    requested_model_path: requestedModelPath,
    normalized_model_dir: normalizedModelDir,
    expected_task_kind: normalizedTaskKind,
    requested_registration_hints: {
      requested_model_id: normalizeString(requestedModelId),
      requested_model_name: normalizeString(requestedModelName),
      requested_backend: normalizeString(backend) || "transformers",
    },
    acceptance_contract: acceptance,
    candidate_validation: validationReport
      ? {
          gate_verdict: validationGateVerdict,
          candidate_usable_for_sample1: validationReport.machine_decision?.candidate_usable_for_sample1 === true,
          runtime_ready: runtimeReady,
          task_kind_status: normalizeString(validationReport.candidate_checks?.task_kind_status),
          inferred_task_hint: normalizeString(validationReport.candidate_checks?.inferred_task_hint),
          loadability_verdict: validationLoadabilityVerdict,
          loadability_blocker: validationLoadabilityBlocker,
          top_recommended_action: validationTopAction,
        }
      : null,
    existing_catalog_refs: compactCatalogRefs(exactCatalogRefs),
    proposed_catalog_entry_payload: proposedCatalogEntry,
    target_catalog_paths: targetCatalogPaths,
    catalog_patch_plan_summary: catalogPatchPlanSummary,
    search_recovery_plan: searchRecoveryPlan,
    machine_decision: {
      catalog_write_allowed_now: catalogPatchAllowedNow,
      validation_pass_required_before_catalog_write: true,
      already_registered_in_catalog: existingRegistration,
      catalog_patch_plan_required_before_manual_write: true,
      top_recommended_action: {
        action_id: actionId,
        action_summary: actionSummary,
        next_step: nextStep,
      },
    },
    operator_workflow: [
      {
        step_id: "review_acceptance_contract",
        allowed_now: true,
        description: "Review the acceptance contract first so catalog writes stay fail-closed.",
        command: "node scripts/generate_lpr_w3_03_sample1_candidate_acceptance.js",
      },
      {
        step_id: "inspect_registration_packet",
        allowed_now: true,
        description: "Normalize the exact path, preview the catalog payload, and inspect target catalog paths.",
        command: registrationCommand(normalizedModelDir || requestedModelPath, normalizedTaskKind, {
          modelId: requestedModelId,
          modelName: requestedModelName,
        }),
      },
      {
        step_id: "inspect_catalog_patch_plan",
        allowed_now: true,
        description:
          "Inspect the shape-aware patch plan before any manual edit so the chosen runtime base stays catalog/state consistent.",
        command: catalogPatchPlanCommand(),
      },
      {
        step_id: "validate_exact_path",
        allowed_now: requestedPathExists,
        description: "Keep using exact-path validation as the hard gate before any catalog write or sample execution.",
        command: validationCommand(normalizedModelDir || requestedModelPath, normalizedTaskKind),
      },
      {
        step_id: "refresh_shortlist_with_exact_dir",
        allowed_now: requestedPathExists,
        description: "Refresh the machine-readable shortlist so this exact dir becomes part of the searched record.",
        command: shortlistCommand(normalizedModelDir || requestedModelPath, normalizedTaskKind),
      },
      {
        step_id: "widen_shortlist_search_if_needed",
        allowed_now: true,
        description:
          "If the default roots still do not expose a usable embedding dir, widen the machine-readable search across common user download locations.",
        command: wideShortlistCommand(normalizedTaskKind),
      },
      {
        step_id: "manual_catalog_write_after_pass",
        allowed_now: catalogPatchAllowedNow,
        description:
          "Only after PASS, patch exactly one target runtime base and keep its models_catalog.json + models_state.json aligned as a pair. This packet never writes external files for you.",
        command:
          catalogPatchAllowedNow
            ? "Follow `catalog_patch_plan_summary.artifact_ref` and patch one chosen `target_base_plans[]` pair manually."
            : "",
      },
      {
        step_id: "prepare_sample",
        allowed_now: validationPass,
        description: "After PASS, prepare the sample1 scaffold.",
        command: focusSample ? renderPrepareCommand(focusSample) : "",
      },
      {
        step_id: "finalize_sample",
        allowed_now: validationPass,
        description: "After a real run, finalize the sample and regenerate QA.",
        command: focusSample ? renderFinalizeCommand(focusSample) : "",
      },
      {
        step_id: "regenerate_qa",
        allowed_now: true,
        description: "Refresh require-real QA so release/operator surfaces stay aligned with reality.",
        command: "node scripts/generate_lpr_w3_03_a_require_real_evidence.js",
      },
    ].filter((row) => !!normalizeString(row.command)),
    artifact_refs: artifactRefs,
    command_refs: dedupeStrings([
      "node scripts/generate_lpr_w3_03_sample1_candidate_acceptance.js",
      registrationCommand(normalizedModelDir || requestedModelPath, normalizedTaskKind, {
        modelId: requestedModelId,
        modelName: requestedModelName,
      }),
      catalogPatchPlanCommand(),
      shortlistCommand(normalizedModelDir || requestedModelPath, normalizedTaskKind),
      wideShortlistCommand(normalizedTaskKind),
      validationCommand(normalizedModelDir || requestedModelPath, normalizedTaskKind),
      focusSample ? renderPrepareCommand(focusSample) : "",
      focusSample ? renderFinalizeCommand(focusSample) : "",
      "node scripts/generate_lpr_w3_03_a_require_real_evidence.js",
      "node scripts/lpr_w3_03_require_real_status.js --json",
    ]),
    notes: [
      "This packet never auto-writes external catalog files. Shared model catalogs remain operator-owned.",
      "Use the catalog patch plan to choose one runtime base and keep its models_catalog.json + models_state.json aligned as a pair.",
      "An existing catalog entry for the same dir is not enough by itself. The exact-path validator must still return PASS before sample1 execution or catalog green-light.",
      "If the dir lives outside default scan roots, keep using the shortlist helper with `--model-path` so the search record stays machine-readable.",
    ],
  };
}

function parseArgs(argv) {
  const out = {
    modelPath: "",
    taskKind: "embedding",
    backend: "transformers",
    modelId: "",
    modelName: "",
    catalogPaths: [],
    outJson: defaultOutputPath,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = normalizeString(argv[i]);
    switch (token) {
      case "--model-path":
        out.modelPath = normalizeString(argv[++i]);
        break;
      case "--task-kind":
        out.taskKind = normalizeString(argv[++i]);
        break;
      case "--backend":
        out.backend = normalizeString(argv[++i]);
        break;
      case "--model-id":
        out.modelId = normalizeString(argv[++i]);
        break;
      case "--model-name":
        out.modelName = normalizeString(argv[++i]);
        break;
      case "--catalog-path":
        out.catalogPaths.push(normalizeString(argv[++i]));
        break;
      case "--out-json":
        out.outJson = path.resolve(normalizeString(argv[++i]));
        break;
      case "--help":
      case "-h":
        printUsage(0);
        break;
      default:
        throw new Error(`unknown arg: ${token}`);
    }
  }

  if (!out.modelPath) {
    throw new Error("missing required arg: --model-path");
  }
  return out;
}

function printUsage(exitCode) {
  const message = [
    "usage:",
    "  node scripts/generate_lpr_w3_03_sample1_candidate_registration_packet.js \\",
    "    --model-path /absolute/path/to/model_dir \\",
    "    [--task-kind embedding] \\",
    "    [--backend transformers] \\",
    "    [--model-id hf-embed-your-model] \\",
    "    [--model-name \"Your Model\"] \\",
    "    [--catalog-path /absolute/path/to/models_catalog.json]... \\",
    "    [--out-json build/reports/lpr_w3_03_sample1_candidate_registration_packet.v1.json]",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function main() {
  try {
    const args = parseArgs(process.argv);
    const requestedModelPath = path.resolve(args.modelPath);
    const normalizedModelDir = normalizeCatalogModelDir(requestedModelPath) || requestedModelPath;
    const expectedTaskKind = normalizeTaskKindHint(args.taskKind) || "embedding";
    const discoveryInputs = buildDiscoveryInputs(args.catalogPaths);
    const discoveredMeta = resolveKnownModelDiscoveryForPath(normalizedModelDir, discoveryInputs);
    const requestedPathExists = pathExists(requestedModelPath);
    const normalizedDirExists = pathExists(normalizedModelDir);
    const modelDirLooksLikeModel = normalizedDirExists && directoryLooksLikeModel(normalizedModelDir);
    const runtimeSelection = chooseReadyRuntime();
    const artifactDir = path.join(artifactRoot, slugForModel(normalizedModelDir || requestedModelPath));
    fs.mkdirSync(artifactDir, { recursive: true });

    let staticMarkers = null;
    let loadProbe = null;
    let loadability = null;
    let validationArtifactRefs = {};

    if (modelDirLooksLikeModel) {
      staticMarkers = buildStaticMarkers(normalizedModelDir, discoveredMeta);
    }

    if (modelDirLooksLikeModel && runtimeSelection.best) {
      loadProbe = runNativeLoadabilityProbe(runtimeSelection.best, normalizedModelDir, artifactDir);
      loadability = classifyLoadability(staticMarkers, loadProbe);
      validationArtifactRefs = {
        native_loadability_meta: relPath(path.join(artifactDir, "native_loadability.meta.json")),
        native_loadability_stdout: relPath(path.join(artifactDir, "native_loadability.stdout.log")),
        native_loadability_stderr: relPath(path.join(artifactDir, "native_loadability.stderr.log")),
      };
    }

    const validationReport = buildSample1CandidateValidationReport({
      requestedModelPath,
      normalizedModelDir,
      expectedTaskKind,
      requestedPathExists,
      normalizedDirExists,
      modelDirLooksLikeModel,
      runtimeSelection,
      staticMarkers,
      loadProbe,
      loadability,
      artifactRefs: validationArtifactRefs,
    });
    const validationReportPath = path.join(artifactDir, "candidate_validation.v1.json");
    writeJSON(validationReportPath, validationReport);

    const proposedCatalogEntry = buildProposedCatalogEntry({
      normalizedModelDir,
      taskKind: expectedTaskKind,
      backend: args.backend,
      requestedModelId: args.modelId,
      requestedModelName: args.modelName,
      existingCatalogRefs: Array.isArray(discoveredMeta.catalog_entry_refs) ? discoveredMeta.catalog_entry_refs : [],
    });
    const proposedCatalogEntryPath = path.join(artifactDir, "proposed_catalog_entry.v1.json");
    writeJSON(proposedCatalogEntryPath, proposedCatalogEntry);

    const targetCatalogPaths = buildTargetCatalogPaths({
      catalogPaths: discoveryInputs.catalog_paths,
      normalizedModelDir,
      proposedModelEntry: proposedCatalogEntry,
      validationReport,
    });

    const acceptanceReport = readJSONIfExists(acceptanceReportPath);
    const acceptanceContract =
      acceptanceReport && acceptanceReport.acceptance_contract && typeof acceptanceReport.acceptance_contract === "object"
        ? acceptanceReport.acceptance_contract
        : null;
    const bundle = readCaptureBundle();
    const focusSample = findFocusSample(
      Array.isArray(bundle.samples) ? bundle.samples : [],
      "lpr_rr_01_embedding_real_model_dir_executes"
    );

    const report = buildRegistrationPacket({
      requestedModelPath,
      normalizedModelDir,
      expectedTaskKind,
      backend: args.backend,
      validationReport,
      proposedCatalogEntry,
      targetCatalogPaths,
      existingCatalogRefs: Array.isArray(discoveredMeta.catalog_entry_refs) ? discoveredMeta.catalog_entry_refs : [],
      acceptanceContract,
      focusSample,
      requestedModelId: args.modelId,
      requestedModelName: args.modelName,
      artifactRefs: {
        acceptance_report: relPath(acceptanceReportPath),
        candidate_validation_report: relPath(validationReportPath),
        proposed_catalog_entry_payload: relPath(proposedCatalogEntryPath),
        native_loadability_meta: validationArtifactRefs.native_loadability_meta || "",
        native_loadability_stdout: validationArtifactRefs.native_loadability_stdout || "",
        native_loadability_stderr: validationArtifactRefs.native_loadability_stderr || "",
      },
    });

    const candidateCatalogPatchPlanPath = path.join(artifactDir, "candidate_catalog_patch_plan.v1.json");
    const candidateCatalogPatchPlan = buildCatalogPatchPlan({
      registrationPacket: report,
      sourceRegistrationPacketRef: relPath(args.outJson),
    });
    writeJSON(candidateCatalogPatchPlanPath, candidateCatalogPatchPlan);

    if (path.resolve(defaultCatalogPatchPlanOutputPath) !== path.resolve(candidateCatalogPatchPlanPath)) {
      writeJSON(defaultCatalogPatchPlanOutputPath, candidateCatalogPatchPlan);
    }

    const finalReport = buildRegistrationPacket({
      requestedModelPath,
      normalizedModelDir,
      expectedTaskKind,
      backend: args.backend,
      validationReport,
      proposedCatalogEntry,
      targetCatalogPaths,
      existingCatalogRefs: Array.isArray(discoveredMeta.catalog_entry_refs) ? discoveredMeta.catalog_entry_refs : [],
      acceptanceContract,
      focusSample,
      requestedModelId: args.modelId,
      requestedModelName: args.modelName,
      catalogPatchPlanSummary: compactCatalogPatchPlanSummary(
        candidateCatalogPatchPlan,
        relPath(candidateCatalogPatchPlanPath)
      ),
      artifactRefs: {
        acceptance_report: relPath(acceptanceReportPath),
        candidate_validation_report: relPath(validationReportPath),
        proposed_catalog_entry_payload: relPath(proposedCatalogEntryPath),
        candidate_catalog_patch_plan: relPath(candidateCatalogPatchPlanPath),
        native_loadability_meta: validationArtifactRefs.native_loadability_meta || "",
        native_loadability_stdout: validationArtifactRefs.native_loadability_stdout || "",
        native_loadability_stderr: validationArtifactRefs.native_loadability_stderr || "",
      },
    });

    writeJSON(args.outJson, finalReport);
    process.stdout.write(`${args.outJson}\n`);
  } catch (error) {
    process.stderr.write(`${String(error.message || error)}\n`);
    printUsage(1);
  }
}

module.exports = {
  buildAcceptanceContractSummary,
  buildDiscoveryInputs,
  buildProposedCatalogEntry,
  buildRegistrationPacket,
  buildTargetCatalogPaths,
  parseArgs,
  proposeModelId,
  proposeModelName,
  registrationCommand,
  shortlistCommand,
  wideShortlistCommand,
  taskProfile,
};

if (require.main === module) {
  main();
}
