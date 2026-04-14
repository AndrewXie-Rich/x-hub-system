#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const {
  repoRoot,
  resolveReportsDir,
  writeJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");
const {
  buildStaticMarkers,
  chooseReadyRuntime,
  classifyLoadability,
  collectModelDiscoveryInputs,
  directoryLooksLikeModel,
  normalizeCatalogModelDir,
  normalizeTaskKindHint,
  pathExists,
  resolveKnownModelDiscoveryForPath,
  runNativeLoadabilityProbe,
  slugForModel,
} = require("./generate_lpr_w3_03_c_model_native_loadability_probe.js");

const defaultOutputPath = path.join(
  resolveReportsDir(),
  "lpr_w3_03_sample1_candidate_validation.v1.json"
);
const artifactRoot = path.join(
  resolveReportsDir(),
  "lpr_w3_03_require_real",
  "sample1_candidate_validation"
);

function isoNow() {
  return new Date().toISOString();
}

function normalizeString(value, fallback = "") {
  const text = value === undefined || value === null ? "" : String(value).trim();
  if (text) return text;
  return fallback === undefined || fallback === null ? "" : String(fallback).trim();
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
  return path.relative(repoRoot, targetPath).split(path.sep).join("/");
}

function shellQuote(value) {
  const text = String(value || "");
  if (/^[A-Za-z0-9_./:@=,+-]+$/.test(text)) return text;
  return `'${text.replace(/'/g, `'\\''`)}'`;
}

function parseArgs(argv) {
  const out = {
    modelPath: "",
    taskKind: "embedding",
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
    "  node scripts/generate_lpr_w3_03_sample1_candidate_validation.js \\",
    "    --model-path /absolute/path/to/model_dir \\",
    "    [--task-kind embedding] \\",
    "    [--out-json build/reports/lpr_w3_03_sample1_candidate_validation.v1.json]",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function validationCommand(modelDir, taskKind) {
  return [
    "node scripts/generate_lpr_w3_03_sample1_candidate_validation.js",
    `  --model-path ${shellQuote(modelDir)}`,
    `  --task-kind ${shellQuote(taskKind)}`,
  ].join(" \\\n");
}

function validationCommandTemplate(taskKind) {
  return [
    "node scripts/generate_lpr_w3_03_sample1_candidate_validation.js",
    "  --model-path <absolute_model_dir>",
    `  --task-kind ${shellQuote(taskKind)}`,
  ].join(" \\\n");
}

function shortlistCommand(modelDir, taskKind) {
  return [
    "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js",
    `  --task-kind ${shellQuote(taskKind)}`,
    `  --model-path ${shellQuote(modelDir)}`,
  ].join(" \\\n");
}

function shortlistCommandTemplate(taskKind) {
  return [
    "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js",
    `  --task-kind ${shellQuote(taskKind)}`,
    "  --model-path <absolute_model_dir>",
  ].join(" \\\n");
}

function wideShortlistCommand(taskKind) {
  return [
    "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js",
    `  --task-kind ${shellQuote(taskKind)}`,
    "  --wide-common-user-roots",
  ].join(" \\\n");
}

function scanRootShortlistCommandTemplate(taskKind) {
  return [
    "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js",
    `  --task-kind ${shellQuote(taskKind)}`,
    "  --scan-root <absolute_search_root>",
  ].join(" \\\n");
}

function buildSample1CandidateValidationReport({
  generatedAt = isoNow(),
  requestedModelPath = "",
  normalizedModelDir = "",
  expectedTaskKind = "embedding",
  requestedPathExists = false,
  normalizedDirExists = false,
  modelDirLooksLikeModel = false,
  runtimeSelection = null,
  staticMarkers = null,
  loadProbe = null,
  loadability = null,
  artifactRefs = {},
} = {}) {
  const runtime = runtimeSelection && typeof runtimeSelection === "object" ? runtimeSelection : {};
  const bestRuntime = runtime.best && runtime.best.candidate ? runtime.best.candidate : null;
  const probes = Array.isArray(runtime.probes) ? runtime.probes : [];
  const normalizedTaskKind = normalizeTaskKindHint(expectedTaskKind) || "embedding";
  const inferredTaskHint = normalizeString(
    staticMarkers?.format_assessment?.task_hint,
    "unknown"
  );
  const taskHintSources = dedupeStrings(staticMarkers?.format_assessment?.task_hint_sources || []);
  const taskKindStatus = inferredTaskHint === normalizedTaskKind
    ? "confirmed_by_local_metadata"
    : inferredTaskHint === "unknown"
      ? "operator_asserted_only"
      : "mismatch";
  const loadabilityVerdict = normalizeString(loadability?.verdict, "not_probed");
  const loadabilityBlocker = normalizeString(loadability?.blocker_reason);
  const runtimeReady = !!bestRuntime;

  let gateVerdict = "NO_GO(sample1_candidate_validation_failed_closed)";
  let candidateUsableForSample1 = false;
  let actionId = "inspect_candidate_validation";
  let actionSummary = "Inspect the candidate path, runtime, and loadability report before using it for sample1.";
  let nextStep = "inspect_validation_report";

  if (!requestedPathExists) {
    actionId = "fix_candidate_model_path";
    actionSummary = "The requested candidate path does not exist on disk. Point the validator at a real local model directory.";
    nextStep = "supply_existing_model_path";
  } else if (!normalizedDirExists || !modelDirLooksLikeModel) {
    actionId = "point_to_actual_model_dir";
    actionSummary = "The requested path resolves to a directory, but it does not look like a local HF-style model directory yet.";
    nextStep = "use_model_dir_with_config_and_weights";
  } else if (!runtimeReady) {
    actionId = "restore_ready_transformers_runtime";
    actionSummary = "No ready torch/transformers runtime candidate is available, so sample1 cannot validate this model dir yet.";
    nextStep = "restore_combo_runtime_then_rerun_candidate_validation";
  } else if (taskKindStatus === "mismatch") {
    actionId = "source_embedding_model_dir_matching_sample1";
    actionSummary = `The candidate metadata points to task kind "${inferredTaskHint}", not "${normalizedTaskKind}". Do not use it for sample1.`;
    nextStep = "source_real_embedding_model_dir_then_rerun_validation";
  } else if (loadabilityVerdict === "native_loadable") {
    gateVerdict = "PASS(sample1_candidate_native_loadable_for_real_execution)";
    candidateUsableForSample1 = true;
    actionId = "use_candidate_for_sample1_real_run";
    actionSummary = "This candidate directory is native-loadable on the selected runtime and can be used for sample1 real execution.";
    nextStep = "prepare_and_execute_sample1_real_run";
  } else if (loadabilityBlocker === "unsupported_quantization_config") {
    actionId = "source_different_native_embedding_model_dir";
    actionSummary = "This candidate still looks like a quantized LM Studio / MLX layout that torch/transformers cannot natively load for sample1.";
    nextStep = "source_non_quantization_blocked_embedding_dir_then_rerun_validation";
  } else {
    actionId = "inspect_non_native_loadable_candidate";
    actionSummary = "This candidate path is real, but it is not yet native-loadable enough for sample1.";
    nextStep = "inspect_loadability_reasons_or_source_different_candidate";
  }

  const exactPathKnown = !!normalizeString(normalizedModelDir || requestedModelPath);
  const exactPathCommandsAllowedNow = requestedPathExists === true;
  const resolvedExactModelPath = normalizeString(normalizedModelDir || requestedModelPath);
  const searchRecovery = {
    exact_path_known: exactPathKnown,
    exact_path_commands_allowed_now: exactPathCommandsAllowedNow,
    exact_path_shortlist_refresh_command:
      exactPathKnown && exactPathCommandsAllowedNow
        ? shortlistCommand(resolvedExactModelPath, normalizedTaskKind)
        : "",
    exact_path_validation_command:
      exactPathKnown && exactPathCommandsAllowedNow
        ? validationCommand(resolvedExactModelPath, normalizedTaskKind)
        : "",
    explicit_model_path_shortlist_command_template: shortlistCommandTemplate(normalizedTaskKind),
    explicit_model_path_validation_command_template: validationCommandTemplate(normalizedTaskKind),
    wide_shortlist_search_command: wideShortlistCommand(normalizedTaskKind),
    custom_scan_root_shortlist_command_template: scanRootShortlistCommandTemplate(normalizedTaskKind),
  };

  const operatorSteps = candidateUsableForSample1
    ? [
        "Keep this exact directory path as the sample1 model_path source of truth.",
        `Generate the sample1 scaffold: node scripts/prepare_lpr_w3_03_require_real_sample.js --sample-id lpr_rr_01_embedding_real_model_dir_executes`,
        "Execute a real embedding run with real input text, monitor snapshot, and diagnostics export.",
        "Finalize the sample from the scaffold dir and regenerate QA.",
      ]
    : [
        "Do not mark sample1 green from this candidate yet.",
        "Refresh the shortlist with this exact dir path so the searched record stays machine-readable.",
        "If you just sourced a new model dir, rerun this validator against that exact directory path.",
        "If the model may live in Documents, Downloads, or Desktop, rerun the shortlist with the wide common-user-root scan before assuming no candidate exists.",
        "Only proceed to sample1 execution after this validator reports PASS(native_loadable_for_real_execution).",
      ];

  return {
    schema_version: "xhub.lpr_w3_03_sample1_candidate_validation.v1",
    generated_at: generatedAt,
    scope: "Validate one operator-supplied local model directory for LPR sample1 real execution.",
    fail_closed: true,
    sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
    requested_model_path: requestedModelPath,
    normalized_model_dir: normalizedModelDir,
    expected_task_kind: normalizedTaskKind,
    candidate_checks: {
      requested_path_exists: requestedPathExists,
      normalized_dir_exists: normalizedDirExists,
      model_dir_looks_like_model: modelDirLooksLikeModel,
      inferred_task_hint: inferredTaskHint,
      task_hint_sources: taskHintSources,
      task_kind_status: taskKindStatus,
    },
    runtime_resolution: {
      runtime_ready: runtimeReady,
      selected_runtime_id: bestRuntime ? normalizeString(bestRuntime.runtime_id) : "",
      selected_runtime_label: bestRuntime ? normalizeString(bestRuntime.label) : "",
      selected_runtime_command: bestRuntime ? normalizeString(bestRuntime.command) : "",
      runtime_probe_count: probes.length,
    },
    static_markers: staticMarkers || null,
    loadability: loadability
      ? {
          verdict: loadabilityVerdict,
          blocker_reason: loadabilityBlocker,
          reasons: dedupeStrings(loadability.reasons || []),
          auto_config_ok: loadability.auto_config_ok === true,
          auto_tokenizer_ok: loadability.auto_tokenizer_ok === true,
          auto_model_ok: loadability.auto_model_ok === true,
          auto_model_for_causal_lm_ok: loadability.auto_model_for_causal_lm_ok === true,
        }
      : null,
    machine_decision: {
      gate_verdict: gateVerdict,
      candidate_usable_for_sample1: candidateUsableForSample1,
      top_recommended_action: {
        action_id: actionId,
        action_summary: actionSummary,
        next_step: nextStep,
      },
    },
    search_recovery: searchRecovery,
    operator_steps: operatorSteps,
    artifact_refs: artifactRefs,
    command_refs: dedupeStrings([
      normalizedModelDir ? validationCommand(normalizedModelDir, normalizedTaskKind) : "",
      normalizedModelDir ? shortlistCommand(normalizedModelDir, normalizedTaskKind) : "",
      wideShortlistCommand(normalizedTaskKind),
      "node scripts/prepare_lpr_w3_03_require_real_sample.js --sample-id lpr_rr_01_embedding_real_model_dir_executes",
      "node scripts/finalize_lpr_w3_03_require_real_sample.js \\\n  --scaffold-dir build/reports/lpr_w3_03_require_real/lpr_rr_01_embedding_real_model_dir_executes",
      "node scripts/generate_lpr_w3_03_a_require_real_evidence.js",
      "node scripts/lpr_w3_03_require_real_status.js --json",
    ]),
  };
}

function main() {
  try {
    const args = parseArgs(process.argv);
    const requestedModelPath = path.resolve(args.modelPath);
    const normalizedModelDir = normalizeCatalogModelDir(requestedModelPath) || requestedModelPath;
    const requestedPathExists = pathExists(requestedModelPath);
    const normalizedDirExists = pathExists(normalizedModelDir);
    const modelDirLooksLikeModel = normalizedDirExists && directoryLooksLikeModel(normalizedModelDir);
    const runtimeSelection = chooseReadyRuntime();

    let staticMarkers = null;
    let loadProbe = null;
    let loadability = null;
    let artifactRefs = {};

    if (modelDirLooksLikeModel) {
      const discoveryInputs = collectModelDiscoveryInputs();
      const discoveredMeta = resolveKnownModelDiscoveryForPath(normalizedModelDir, discoveryInputs);
      staticMarkers = buildStaticMarkers(normalizedModelDir, discoveredMeta);
    }

    if (modelDirLooksLikeModel && runtimeSelection.best) {
      const artifactDir = path.join(artifactRoot, slugForModel(normalizedModelDir));
      fs.mkdirSync(artifactDir, { recursive: true });
      loadProbe = runNativeLoadabilityProbe(runtimeSelection.best, normalizedModelDir, artifactDir);
      loadability = classifyLoadability(staticMarkers, loadProbe);
      artifactRefs = {
        native_loadability_meta: relPath(path.join(artifactDir, "native_loadability.meta.json")),
        native_loadability_stdout: relPath(path.join(artifactDir, "native_loadability.stdout.log")),
        native_loadability_stderr: relPath(path.join(artifactDir, "native_loadability.stderr.log")),
      };
    }

    const report = buildSample1CandidateValidationReport({
      requestedModelPath,
      normalizedModelDir,
      expectedTaskKind: args.taskKind,
      requestedPathExists,
      normalizedDirExists,
      modelDirLooksLikeModel,
      runtimeSelection,
      staticMarkers,
      loadProbe,
      loadability,
      artifactRefs,
    });
    writeJSON(args.outJson, report);
    process.stdout.write(`${args.outJson}\n`);
  } catch (error) {
    process.stderr.write(`${String(error.message || error)}\n`);
    printUsage(1);
  }
}

module.exports = {
  buildSample1CandidateValidationReport,
  parseArgs,
  shortlistCommand,
  validationCommand,
  validationCommandTemplate,
  wideShortlistCommand,
};

if (require.main === module) {
  main();
}
