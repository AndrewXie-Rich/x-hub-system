#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const {
  repoRoot,
  resolveReportsDir,
  writeJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");

const defaultRegistrationPath = path.join(
  resolveReportsDir(),
  "lpr_w3_03_sample1_candidate_registration_packet.v1.json"
);
const defaultOutputPath = path.join(
  resolveReportsDir(),
  "lpr_w3_03_sample1_candidate_catalog_patch_plan.v1.json"
);

function isoNow() {
  return new Date().toISOString();
}

function unixNowSeconds() {
  return Number((Date.now() / 1000).toFixed(3));
}

function normalizeString(value) {
  return String(value || "").trim();
}

function normalizeArray(value) {
  return Array.isArray(value) ? value : [];
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

function normalizeTaskKind(value) {
  const text = normalizeString(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  switch (text) {
    case "embed":
    case "embeddings":
      return "embedding";
    case "text_generation":
    case "generate":
      return "text_generate";
    case "asr":
    case "speech":
      return "speech_to_text";
    case "vision":
    case "ocr":
      return "vision_understand";
    default:
      return text || "embedding";
  }
}

function defaultInputModalities(taskKind) {
  switch (normalizeTaskKind(taskKind)) {
    case "speech_to_text":
      return ["audio"];
    case "vision_understand":
      return ["image", "text"];
    case "text_generate":
      return ["text"];
    case "embedding":
    default:
      return ["text"];
  }
}

function defaultOutputModalities(taskKind) {
  switch (normalizeTaskKind(taskKind)) {
    case "speech_to_text":
      return ["text"];
    case "vision_understand":
      return ["text"];
    case "text_generate":
      return ["text"];
    case "embedding":
    default:
      return ["embedding"];
  }
}

function defaultRoles(taskKind) {
  switch (normalizeTaskKind(taskKind)) {
    case "speech_to_text":
      return ["transcribe"];
    case "vision_understand":
      return ["vision", "extract"];
    case "text_generate":
      return ["general"];
    case "embedding":
    default:
      return ["embed", "retrieve"];
  }
}

function defaultProcessorRequirements(taskKind) {
  switch (normalizeTaskKind(taskKind)) {
    case "speech_to_text":
      return {
        tokenizerRequired: true,
        processorRequired: true,
        featureExtractorRequired: true,
      };
    case "vision_understand":
      return {
        tokenizerRequired: true,
        processorRequired: true,
        featureExtractorRequired: false,
      };
    case "text_generate":
    case "embedding":
    default:
      return {
        tokenizerRequired: true,
        processorRequired: false,
        featureExtractorRequired: false,
      };
  }
}

function baseLabelForDir(baseDir) {
  const normalized = path.resolve(String(baseDir || ""));
  if (normalized.includes("/Library/Containers/com.rel.flowhub/Data/RELFlowHub")) {
    return "container_managed_runtime_base";
  }
  if (normalized.endsWith("/RELFlowHub")) {
    return "legacy_home_runtime_base";
  }
  return "custom_runtime_base";
}

function detectFileKind(filePath) {
  const name = path.basename(String(filePath || ""));
  if (name === "models_catalog.json") return "models_catalog";
  if (name === "models_state.json") return "models_state";
  return "unknown";
}

function detectModelsArrayKey(root) {
  if (!root || typeof root !== "object") return "";
  if (Array.isArray(root.models)) return "models";
  if (Array.isArray(root.items)) return "items";
  if (Array.isArray(root.entries)) return "entries";
  return "";
}

function firstObjectEntry(models = []) {
  return models.find((row) => row && typeof row === "object" && !Array.isArray(row)) || null;
}

function detectShapeFamily(fileKind, peerEntry) {
  if (!peerEntry || typeof peerEntry !== "object") {
    return fileKind === "unknown" ? "unknown" : "empty_models_array";
  }
  const enrichedMarkers = [
    "taskKinds",
    "inputModalities",
    "outputModalities",
    "offlineReady",
    "modelFormat",
    "defaultLoadProfile",
    "trustProfile",
    "processorRequirements",
  ];
  const markerCount = enrichedMarkers.filter((key) => Object.prototype.hasOwnProperty.call(peerEntry, key)).length;
  if (markerCount >= 4) return "managed_enriched";
  if (fileKind === "unknown") return "unknown";
  return "legacy_minimal";
}

function compactEntryRef(entry = null) {
  if (!entry || typeof entry !== "object") return null;
  return {
    id: normalizeString(entry.id),
    name: normalizeString(entry.name),
    backend: normalizeString(entry.backend),
    model_path: normalizeString(entry.modelPath || entry.model_path),
    task_kinds: dedupeStrings(entry.taskKinds || entry.task_kinds || []),
  };
}

function buildRuntimeSafeEntry(registrationPacket = {}, fileKind = "models_catalog") {
  const proposed = registrationPacket.proposed_catalog_entry_payload || {};
  const acceptance = registrationPacket.acceptance_contract || {};
  const requestedTaskKind = normalizeTaskKind(
    normalizeArray(proposed.taskKinds)[0]
      || acceptance.expected_task_kind
      || registrationPacket.expected_task_kind
      || "embedding"
  );
  const backend = normalizeString(proposed.backend || acceptance.expected_provider || "transformers");
  const baseEntry = {
    id: normalizeString(proposed.id),
    name: normalizeString(proposed.name),
    backend,
    runtimeProviderId: normalizeString(proposed.runtimeProviderId || backend),
    modelPath: normalizeString(proposed.modelPath || registrationPacket.normalized_model_dir),
    taskKinds: dedupeStrings(normalizeArray(proposed.taskKinds).length > 0
      ? proposed.taskKinds
      : [requestedTaskKind]),
    inputModalities: dedupeStrings(normalizeArray(proposed.inputModalities).length > 0
      ? proposed.inputModalities
      : defaultInputModalities(requestedTaskKind)),
    outputModalities: dedupeStrings(normalizeArray(proposed.outputModalities).length > 0
      ? proposed.outputModalities
      : defaultOutputModalities(requestedTaskKind)),
    offlineReady: true,
    modelFormat: normalizeString(proposed.modelFormat || "huggingface"),
    note:
      "manual_registration_after_validator_pass; generated by sample1 catalog patch plan",
    trustProfile: {
      allowRemoteExport: false,
      allowSecretInput: false,
    },
    roles: defaultRoles(requestedTaskKind),
    processorRequirements: defaultProcessorRequirements(requestedTaskKind),
  };
  if (fileKind === "models_state") {
    baseEntry.state = "available";
  }
  return baseEntry;
}

function buildShapePreservingEntry(peerEntry, runtimeSafeEntry, fileKind) {
  if (!peerEntry || typeof peerEntry !== "object") {
    const minimal = {
      id: runtimeSafeEntry.id,
      name: runtimeSafeEntry.name,
      backend: runtimeSafeEntry.backend,
      modelPath: runtimeSafeEntry.modelPath,
      note: runtimeSafeEntry.note,
    };
    if (fileKind === "models_state") {
      minimal.taskKinds = runtimeSafeEntry.taskKinds;
      minimal.inputModalities = runtimeSafeEntry.inputModalities;
      minimal.outputModalities = runtimeSafeEntry.outputModalities;
      minimal.state = runtimeSafeEntry.state || "available";
    }
    return minimal;
  }

  const out = {};
  for (const key of Object.keys(peerEntry)) {
    switch (key) {
      case "id":
      case "name":
      case "backend":
      case "runtimeProviderId":
      case "modelPath":
      case "taskKinds":
      case "inputModalities":
      case "outputModalities":
      case "offlineReady":
      case "modelFormat":
      case "note":
      case "trustProfile":
      case "roles":
      case "processorRequirements":
      case "state":
        if (Object.prototype.hasOwnProperty.call(runtimeSafeEntry, key)) {
          out[key] = runtimeSafeEntry[key];
        }
        break;
      default:
        break;
    }
  }

  for (const requiredKey of ["id", "name", "backend", "modelPath"]) {
    if (!Object.prototype.hasOwnProperty.call(out, requiredKey)) {
      out[requiredKey] = runtimeSafeEntry[requiredKey];
    }
  }

  if (fileKind === "models_state") {
    if (!Object.prototype.hasOwnProperty.call(out, "taskKinds")) {
      out.taskKinds = runtimeSafeEntry.taskKinds;
    }
    if (!Object.prototype.hasOwnProperty.call(out, "inputModalities")) {
      out.inputModalities = runtimeSafeEntry.inputModalities;
    }
    if (!Object.prototype.hasOwnProperty.call(out, "outputModalities")) {
      out.outputModalities = runtimeSafeEntry.outputModalities;
    }
    if (!Object.prototype.hasOwnProperty.call(out, "state")) {
      out.state = runtimeSafeEntry.state || "available";
    }
  }

  return out;
}

function suggestedManualReviewFields(peerEntry, shapeFamily) {
  const peerKeys = peerEntry && typeof peerEntry === "object" ? Object.keys(peerEntry) : [];
  const fields = [];
  for (const key of peerKeys) {
    if ([
      "paramsB",
      "quant",
      "contextLength",
      "maxContextLength",
      "defaultLoadProfile",
      "resourceProfile",
      "memoryBytes",
      "tokensPerSec",
    ].includes(key)) {
      fields.push(key);
    }
  }
  if (shapeFamily === "managed_enriched") {
    fields.push("defaultLoadProfile.contextLength");
  }
  return dedupeStrings(fields);
}

function suggestedOptionalAlignmentFields(peerEntry, runtimeSafeEntry) {
  const peerKeys = peerEntry && typeof peerEntry === "object" ? Object.keys(peerEntry) : [];
  return dedupeStrings(
    peerKeys.filter((key) =>
      !Object.prototype.hasOwnProperty.call(runtimeSafeEntry, key)
      && !["id", "name", "backend", "modelPath"].includes(key)
    )
  );
}

function buildRootPatchPlan({
  root = null,
  arrayKey = "",
  modelCount = 0,
  timestampSeconds = unixNowSeconds(),
} = {}) {
  if (!root || typeof root !== "object") {
    return [
      {
        op: "create_root_object",
        value_preview: {
          updatedAt: timestampSeconds,
          models: [],
        },
      },
      {
        op: "set",
        path: "updatedAt",
        value_type: "unix_seconds_float",
        value_preview: timestampSeconds,
      },
      {
        op: "append_array",
        path: "models",
        expected_length_before: 0,
      },
    ];
  }

  const targetArrayKey = arrayKey || "models";
  const plan = [
    {
      op: "set",
      path: "updatedAt",
      value_type: "unix_seconds_float",
      value_preview: timestampSeconds,
    },
  ];
  if (!arrayKey) {
    plan.push({
      op: "create_array",
      path: targetArrayKey,
      value_preview: [],
    });
  }
  plan.push({
    op: "append_array",
    path: targetArrayKey,
    expected_length_before: Number(modelCount || 0),
  });
  return plan;
}

function compactRootKeys(root) {
  return root && typeof root === "object" ? Object.keys(root).slice(0, 20) : [];
}

function buildTargetFilePlan({
  filePath = "",
  registrationPacket = null,
  timestampSeconds = unixNowSeconds(),
} = {}) {
  const resolvedPath = path.resolve(String(filePath || ""));
  const fileKind = detectFileKind(resolvedPath);
  const validationGateVerdict = normalizeString(
    registrationPacket?.candidate_validation?.gate_verdict
  );
  const validationPass =
    validationGateVerdict === "PASS(sample1_candidate_native_loadable_for_real_execution)";
  const proposedModelID = normalizeString(registrationPacket?.proposed_catalog_entry_payload?.id);
  const normalizedModelDir = normalizeString(registrationPacket?.normalized_model_dir);
  const present = fs.existsSync(resolvedPath);
  const root = readJSONIfExists(resolvedPath);
  const parseOK = !present || root !== null;
  const arrayKey = parseOK ? detectModelsArrayKey(root) : "";
  const models = parseOK && arrayKey ? normalizeArray(root[arrayKey]) : [];
  const exactIndexes = [];
  const idConflictIndexes = [];
  for (let index = 0; index < models.length; index += 1) {
    const row = models[index];
    if (!row || typeof row !== "object") continue;
    if (normalizeString(row.modelPath || row.model_path) === normalizedModelDir) {
      exactIndexes.push(index);
    }
    if (
      normalizeString(row.id) === proposedModelID
      && normalizeString(row.modelPath || row.model_path) !== normalizedModelDir
    ) {
      idConflictIndexes.push(index);
    }
  }

  const exactEntry = exactIndexes.length > 0 ? models[exactIndexes[0]] : null;
  const peerEntry = exactEntry || firstObjectEntry(models);
  const shapeFamily = detectShapeFamily(fileKind, peerEntry);
  const runtimeSafeEntry = buildRuntimeSafeEntry(registrationPacket, fileKind);
  const shapePreservingEntry = buildShapePreservingEntry(peerEntry, runtimeSafeEntry, fileKind);

  let blockedReason = "";
  let entryOperation = "append_new_entry";
  if (!validationPass) {
    blockedReason = "validator_not_pass";
    entryOperation = "blocked_until_validator_pass";
  } else if (!parseOK) {
    blockedReason = "json_parse_failed";
    entryOperation = "blocked_json_parse_failed";
  } else if (present && !arrayKey) {
    blockedReason = "unsupported_root_shape";
    entryOperation = "blocked_unsupported_root_shape";
  } else if (idConflictIndexes.length > 0) {
    blockedReason = "proposed_model_id_conflict";
    entryOperation = "blocked_model_id_conflict";
  } else if (exactIndexes.length > 0) {
    entryOperation = "review_and_update_existing_exact_dir_entry";
  } else if (!present) {
    entryOperation = "create_file_then_append_entry";
  }

  const targetEligibleNow = blockedReason === "";
  const rootPatchPlan = buildRootPatchPlan({
    root: parseOK ? root : null,
    arrayKey,
    modelCount: models.length,
    timestampSeconds,
  });

  const notes = [
    fileKind === "models_state"
      ? "Hub runtime reads models_state.json as the configured-model snapshot, so keep this file aligned with models_catalog.json in the same base dir."
      : "",
    fileKind === "models_catalog"
      ? "Do not patch this catalog file alone if the sibling models_state.json in the same base dir would remain stale."
      : "",
    exactIndexes.length > 0
      ? "The exact modelPath already exists in this file. Update that entry instead of appending a duplicate."
      : "",
    idConflictIndexes.length > 0
      ? "The proposed model id already points at a different directory in this file. Pick a different model id before manual patch."
      : "",
    !validationPass
      ? "Keep manual patch blocked until the exact-path validator returns PASS(sample1_candidate_native_loadable_for_real_execution)."
      : "",
  ].filter(Boolean);

  return {
    catalog_path: resolvedPath,
    catalog_path_ref: relPath(resolvedPath),
    base_dir: path.dirname(resolvedPath),
    base_label: baseLabelForDir(path.dirname(resolvedPath)),
    file_kind: fileKind,
    present,
    parse_ok: parseOK,
    root_shape: arrayKey ? "object_with_models_array" : present ? "unsupported" : "missing",
    models_array_key: arrayKey || (present ? "" : "models"),
    observed_root_keys: compactRootKeys(root),
    observed_model_count: models.length,
    observed_entry_keys_sample: peerEntry && typeof peerEntry === "object" ? Object.keys(peerEntry) : [],
    shape_family: shapeFamily,
    exact_model_dir_registered: exactIndexes.length > 0,
    exact_model_dir_entry_indexes: exactIndexes,
    exact_model_dir_entry_preview: compactEntryRef(exactEntry),
    proposed_model_id_conflict: idConflictIndexes.length > 0,
    proposed_model_id_conflict_indexes: idConflictIndexes,
    proposed_model_id_conflict_preview:
      idConflictIndexes.length > 0 ? compactEntryRef(models[idConflictIndexes[0]]) : null,
    target_eligible_now: targetEligibleNow,
    blocked_reason: blockedReason,
    root_patch_plan: rootPatchPlan,
    model_patch_plan: {
      array_path: arrayKey || "models",
      operation: entryOperation,
      append_index: models.length,
      match_exact_model_path: normalizedModelDir,
      proposed_model_id: proposedModelID,
    },
    payload_preview: {
      shape_preserving_payload: shapePreservingEntry,
      runtime_safe_minimum_payload: runtimeSafeEntry,
    },
    manual_review_fields: suggestedManualReviewFields(peerEntry, shapeFamily),
    optional_alignment_fields: suggestedOptionalAlignmentFields(peerEntry, runtimeSafeEntry),
    notes,
  };
}

function buildTargetBasePlans(targetFilePlans = []) {
  const byBase = new Map();
  for (const plan of targetFilePlans) {
    const baseDir = normalizeString(plan.base_dir);
    if (!byBase.has(baseDir)) byBase.set(baseDir, []);
    byBase.get(baseDir).push(plan);
  }

  return Array.from(byBase.entries()).map(([baseDir, filePlans]) => {
    const plans = filePlans.slice().sort((a, b) => a.catalog_path.localeCompare(b.catalog_path));
    const catalogPlan = plans.find((item) => item.file_kind === "models_catalog") || null;
    const statePlan = plans.find((item) => item.file_kind === "models_state") || null;
    const patchAllowedNow = plans.length > 0 && plans.every((item) => item.target_eligible_now === true);
    const blockedReasons = dedupeStrings(plans.map((item) => item.blocked_reason));
    let recommendedAction = "patch_catalog_and_state_as_pair_after_validator_pass";
    if (!patchAllowedNow && blockedReasons.includes("validator_not_pass")) {
      recommendedAction = "do_not_patch_base_until_validator_pass";
    } else if (!patchAllowedNow && blockedReasons.includes("proposed_model_id_conflict")) {
      recommendedAction = "pick_different_model_id_before_patching_this_base";
    } else if (
      !patchAllowedNow
      && blockedReasons.some((reason) => ["json_parse_failed", "unsupported_root_shape"].includes(reason))
    ) {
      recommendedAction = "repair_or_replace_target_file_shape_before_manual_patch";
    }

    return {
      base_dir: baseDir,
      base_dir_ref: relPath(baseDir),
      base_label: baseLabelForDir(baseDir),
      required_pair_present: {
        models_catalog: !!catalogPlan,
        models_state: !!statePlan,
      },
      patch_allowed_now: patchAllowedNow,
      blocked_reasons: blockedReasons,
      recommended_action: recommendedAction,
      files: plans,
      notes: [
        "Choose one runtime base only. Do not mix one base dir's models_catalog.json with another base dir's models_state.json.",
        "If you patch this base, keep the catalog/state pair aligned before rerunning probes or sample execution.",
      ],
    };
  });
}

function buildCatalogPatchPlan({
  registrationPacket = null,
  generatedAt = isoNow(),
  sourceRegistrationPacketRef = "",
  overrideCatalogPaths = [],
} = {}) {
  const packet = registrationPacket && typeof registrationPacket === "object" ? registrationPacket : {};
  const targetPaths = dedupeStrings(
    normalizeArray(overrideCatalogPaths).length > 0
      ? overrideCatalogPaths
      : normalizeArray(packet.target_catalog_paths).map((item) => item && item.catalog_path)
  );
  const timestampSeconds = unixNowSeconds();
  const targetFilePlans = targetPaths.map((filePath) =>
    buildTargetFilePlan({
      filePath,
      registrationPacket: packet,
      timestampSeconds,
    })
  );
  const targetBasePlans = buildTargetBasePlans(targetFilePlans);
  const patchAllowedNow = targetBasePlans.some((item) => item.patch_allowed_now === true);
  const validatorPass =
    normalizeString(packet?.candidate_validation?.gate_verdict)
      === "PASS(sample1_candidate_native_loadable_for_real_execution)";

  let blockedReason = "";
  let blockedSummary = "";
  if (!validatorPass) {
    blockedReason = "validator_not_pass";
    blockedSummary =
      "Manual catalog/state patch stays blocked because the exact-path validator is not PASS yet.";
  } else if (!patchAllowedNow) {
    blockedReason = "no_eligible_target_runtime_base";
    blockedSummary =
      "The candidate passed validation, but none of the inspected runtime-base catalog/state pairs are currently eligible for a safe manual patch.";
  }

  return {
    schema_version: "xhub.lpr_w3_03_sample1_candidate_catalog_patch_plan.v1",
    generated_at: generatedAt,
    scope:
      "Shape-aware manual patch plan for one sample1 candidate registration packet. This report never auto-writes external catalog/state files.",
    fail_closed: true,
    source_registration_packet_ref: normalizeString(sourceRegistrationPacketRef),
    requested_model_path: normalizeString(packet.requested_model_path),
    normalized_model_dir: normalizeString(packet.normalized_model_dir),
    acceptance_contract: packet.acceptance_contract || null,
    candidate_validation: packet.candidate_validation || null,
    proposed_catalog_entry_payload: packet.proposed_catalog_entry_payload || null,
    machine_decision: {
      manual_patch_scope:
        "choose_one_target_runtime_base_and_keep_models_catalog_and_models_state_in_sync",
      manual_patch_allowed_now: patchAllowedNow,
      blocked_reason: blockedReason,
      blocked_summary: blockedSummary,
      eligible_target_base_count: targetBasePlans.filter((item) => item.patch_allowed_now === true).length,
      blocked_target_base_count: targetBasePlans.filter((item) => item.patch_allowed_now !== true).length,
      top_recommended_action: packet.machine_decision?.top_recommended_action || null,
    },
    target_base_plans: targetBasePlans,
    operator_workflow: [
      {
        step_id: "inspect_registration_packet",
        allowed_now: true,
        description: "Confirm the normalized model dir, proposed model id, and validation truth first.",
        command: normalizeString(sourceRegistrationPacketRef)
          ? `cat ${shellQuote(sourceRegistrationPacketRef)}`
          : "",
      },
      {
        step_id: "inspect_catalog_patch_plan",
        allowed_now: true,
        description:
          "Use this patch plan to inspect the catalog/state pair in each target runtime base before any manual edit.",
        command: "node scripts/generate_lpr_w3_03_sample1_candidate_catalog_patch_plan.js",
      },
      {
        step_id: "patch_one_runtime_base_pair",
        allowed_now: patchAllowedNow,
        description:
          "Only after validator PASS, patch exactly one runtime base and keep its models_catalog.json + models_state.json aligned as a pair.",
        command: "",
      },
    ].filter((item) => item.command || item.allowed_now),
    notes: [
      "This plan never writes external files for you. Shared runtime base files remain operator-owned.",
      "Bump updatedAt whenever you manually edit one of the target files.",
      "If the exact normalized modelPath is already present in a file, update that entry instead of appending a duplicate.",
      "If proposed_model_id_conflict=true anywhere in the chosen base, pick a different model id before patching.",
    ],
  };
}

function compactCatalogPatchPlanSummary(plan = null, artifactRef = "") {
  if (!plan || typeof plan !== "object") return null;
  return {
    artifact_ref: normalizeString(artifactRef),
    manual_patch_scope: normalizeString(plan.machine_decision?.manual_patch_scope),
    manual_patch_allowed_now: plan.machine_decision?.manual_patch_allowed_now === true,
    blocked_reason: normalizeString(plan.machine_decision?.blocked_reason),
    blocked_summary: normalizeString(plan.machine_decision?.blocked_summary),
    eligible_target_base_count: Number(plan.machine_decision?.eligible_target_base_count || 0),
    blocked_target_base_count: Number(plan.machine_decision?.blocked_target_base_count || 0),
    target_base_plans: normalizeArray(plan.target_base_plans).map((base) => ({
      base_dir: normalizeString(base.base_dir),
      base_label: normalizeString(base.base_label),
      patch_allowed_now: base.patch_allowed_now === true,
      blocked_reasons: dedupeStrings(base.blocked_reasons),
      recommended_action: normalizeString(base.recommended_action),
      files: normalizeArray(base.files).map((file) => ({
        catalog_path: normalizeString(file.catalog_path),
        file_kind: normalizeString(file.file_kind),
        shape_family: normalizeString(file.shape_family),
        target_eligible_now: file.target_eligible_now === true,
        blocked_reason: normalizeString(file.blocked_reason),
        model_patch_operation: normalizeString(file.model_patch_plan?.operation),
      })),
    })),
  };
}

function catalogPatchPlanCommand(registrationJson = "", outJson = "") {
  const parts = ["node scripts/generate_lpr_w3_03_sample1_candidate_catalog_patch_plan.js"];
  if (normalizeString(registrationJson) && path.resolve(registrationJson) !== defaultRegistrationPath) {
    parts.push(`  --registration-json ${shellQuote(registrationJson)}`);
  }
  if (normalizeString(outJson) && path.resolve(outJson) !== defaultOutputPath) {
    parts.push(`  --out-json ${shellQuote(outJson)}`);
  }
  return parts.join(" \\\n");
}

function parseArgs(argv) {
  const out = {
    registrationJson: defaultRegistrationPath,
    catalogPaths: [],
    outJson: defaultOutputPath,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = normalizeString(argv[i]);
    switch (token) {
      case "--registration-json":
        out.registrationJson = path.resolve(normalizeString(argv[++i]));
        break;
      case "--catalog-path":
        out.catalogPaths.push(path.resolve(normalizeString(argv[++i])));
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
  return out;
}

function printUsage(exitCode) {
  const message = [
    "usage:",
    "  node scripts/generate_lpr_w3_03_sample1_candidate_catalog_patch_plan.js \\",
    "    [--registration-json build/reports/lpr_w3_03_sample1_candidate_registration_packet.v1.json] \\",
    "    [--catalog-path /absolute/path/to/models_catalog.json]... \\",
    "    [--out-json build/reports/lpr_w3_03_sample1_candidate_catalog_patch_plan.v1.json]",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function main() {
  try {
    const args = parseArgs(process.argv);
    const registrationPacket = readJSON(args.registrationJson);
    const plan = buildCatalogPatchPlan({
      registrationPacket,
      sourceRegistrationPacketRef: relPath(args.registrationJson),
      overrideCatalogPaths: args.catalogPaths,
    });
    writeJSON(args.outJson, plan);
    process.stdout.write(`${args.outJson}\n`);
  } catch (error) {
    process.stderr.write(`${String(error.message || error)}\n`);
    printUsage(1);
  }
}

module.exports = {
  buildCatalogPatchPlan,
  buildTargetBasePlans,
  buildTargetFilePlan,
  catalogPatchPlanCommand,
  compactCatalogPatchPlanSummary,
  defaultOutputPath,
  defaultRegistrationPath,
  parseArgs,
};

if (require.main === module) {
  main();
}
