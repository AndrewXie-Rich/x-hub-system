#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const {
  repoRoot,
  resolveReportsDir,
  writeJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");
const {
  buildSample1CandidateValidationReport,
  validationCommand,
  validationCommandTemplate,
} = require("./generate_lpr_w3_03_sample1_candidate_validation.js");
const {
  buildStaticMarkers,
  chooseReadyRuntime,
  classifyLoadability,
  collectDiscoveredModelDirs,
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
  "lpr_w3_03_sample1_candidate_shortlist.v1.json"
);
const artifactRoot = path.join(
  resolveReportsDir(),
  "lpr_w3_03_require_real",
  "sample1_candidate_shortlist"
);
const commonUserWideScanRoots = [
  path.join(require("node:os").homedir(), "Documents"),
  path.join(require("node:os").homedir(), "Downloads"),
  path.join(require("node:os").homedir(), "Desktop"),
];

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
  return path.relative(repoRoot, targetPath).split(path.sep).join("/");
}

function shellQuote(value) {
  const text = String(value || "");
  if (/^[A-Za-z0-9_./:@=,+-]+$/.test(text)) return text;
  return `'${text.replace(/'/g, `'\\''`)}'`;
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

function parseArgs(argv) {
  const out = {
    modelPaths: [],
    scanRoots: [],
    wideCommonUserRoots: false,
    taskKind: "embedding",
    outJson: defaultOutputPath,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = normalizeString(argv[i]);
    switch (token) {
      case "--model-path":
        out.modelPaths.push(normalizeString(argv[++i]));
        break;
      case "--scan-root":
        out.scanRoots.push(normalizeString(argv[++i]));
        break;
      case "--wide-common-user-roots":
        out.wideCommonUserRoots = true;
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

  return out;
}

function printUsage(exitCode) {
  const message = [
    "usage:",
    "  node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js \\",
    "    [--task-kind embedding] \\",
    "    [--wide-common-user-roots] \\",
    "    [--model-path /absolute/path/to/model_dir]... \\",
    "    [--scan-root /absolute/path/to/search_root]... \\",
    "    [--out-json build/reports/lpr_w3_03_sample1_candidate_shortlist.v1.json]",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function buildDiscoveryInputs(extraScanRoots = [], options = {}) {
  const base = collectModelDiscoveryInputs();
  const wideRoots = options.wideCommonUserRoots === true ? commonUserWideScanRoots : [];
  return {
    ...base,
    scan_roots: dedupeStrings([
      ...(Array.isArray(base.scan_roots) ? base.scan_roots : []),
      ...wideRoots.map((item) => path.resolve(item)),
      ...extraScanRoots.map((item) => path.resolve(item)),
    ]),
  };
}

function collectCandidateRequests({ discoveryInputs, explicitModelPaths = [] }) {
  const discoveredModelDirs = collectDiscoveredModelDirs(discoveryInputs);
  const byDir = new Map();

  const upsert = (modelDir, input = {}) => {
    const normalizedModelDir = normalizeCatalogModelDir(modelDir) || path.resolve(String(modelDir || ""));
    const current = byDir.get(normalizedModelDir) || {
      model_path: normalizedModelDir,
      requested_model_paths: [],
      discovery_sources: [],
      catalog_entry_refs: [],
      source_root: "",
    };
    current.requested_model_paths = dedupeStrings([
      ...current.requested_model_paths,
      ...(Array.isArray(input.requested_model_paths) ? input.requested_model_paths : []),
    ]);
    current.discovery_sources = dedupeStrings([
      ...current.discovery_sources,
      ...(Array.isArray(input.discovery_sources) ? input.discovery_sources : []),
    ]);
    current.catalog_entry_refs = [
      ...current.catalog_entry_refs,
      ...(Array.isArray(input.catalog_entry_refs) ? input.catalog_entry_refs : []),
    ];
    current.source_root = current.source_root || normalizeString(input.source_root);
    byDir.set(normalizedModelDir, current);
  };

  for (const row of discoveredModelDirs) {
    upsert(row.model_path, {
      requested_model_paths: [row.model_path],
      discovery_sources: row.discovery_sources,
      catalog_entry_refs: row.catalog_entry_refs,
      source_root: row.source_root,
    });
  }

  for (const rawPath of explicitModelPaths) {
    const requestedModelPath = path.resolve(rawPath);
    const normalizedModelDir = normalizeCatalogModelDir(requestedModelPath) || requestedModelPath;
    const known = resolveKnownModelDiscoveryForPath(normalizedModelDir, discoveryInputs);
    upsert(normalizedModelDir, {
      requested_model_paths: [requestedModelPath],
      discovery_sources: [
        `explicit_model_path:${requestedModelPath}`,
        ...(Array.isArray(known.discovery_sources) ? known.discovery_sources : []),
      ],
      catalog_entry_refs: Array.isArray(known.catalog_entry_refs) ? known.catalog_entry_refs : [],
      source_root: normalizeString(known.source_root) || path.dirname(requestedModelPath),
    });
  }

  return Array.from(byDir.values()).sort((a, b) =>
    String(a.model_path || "").localeCompare(String(b.model_path || ""))
  );
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

function buildShortlistCandidate({
  candidate,
  runtimeSelection,
  expectedTaskKind,
}) {
  const requestedModelPath = candidate.requested_model_paths[0] || candidate.model_path;
  const normalizedModelDir = candidate.model_path;
  const requestedPathExists = pathExists(requestedModelPath);
  const normalizedDirExists = pathExists(normalizedModelDir);
  const modelDirLooksLikeModel = normalizedDirExists && directoryLooksLikeModel(normalizedModelDir);
  const runtimeReady = !!(runtimeSelection && runtimeSelection.best);
  const artifactDir = path.join(artifactRoot, slugForModel(normalizedModelDir || requestedModelPath));

  let staticMarkers = null;
  let loadProbe = null;
  let loadability = null;
  const artifactRefs = {};

  if (modelDirLooksLikeModel) {
    staticMarkers = buildStaticMarkers(normalizedModelDir, candidate);
  }

  if (modelDirLooksLikeModel && runtimeReady) {
    fs.mkdirSync(artifactDir, { recursive: true });
    loadProbe = runNativeLoadabilityProbe(runtimeSelection.best, normalizedModelDir, artifactDir);
    loadability = classifyLoadability(staticMarkers, loadProbe);
    artifactRefs.native_loadability_meta = relPath(path.join(artifactDir, "native_loadability.meta.json"));
    artifactRefs.native_loadability_stdout = relPath(path.join(artifactDir, "native_loadability.stdout.log"));
    artifactRefs.native_loadability_stderr = relPath(path.join(artifactDir, "native_loadability.stderr.log"));
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
    artifactRefs,
  });

  fs.mkdirSync(artifactDir, { recursive: true });
  const validationReportPath = path.join(artifactDir, "candidate_validation.v1.json");
  writeJSON(validationReportPath, validationReport);
  const explicitPathSupplied = (candidate.discovery_sources || []).some((item) =>
    String(item || "").startsWith("explicit_model_path:")
  );
  const taskKindStatus = normalizeString(validationReport.candidate_checks.task_kind_status);
  const matchesExpectedTaskKind =
    taskKindStatus === "confirmed_by_local_metadata" ||
    (taskKindStatus === "operator_asserted_only" && explicitPathSupplied);

  return {
    normalized_model_dir: normalizedModelDir,
    requested_model_paths: dedupeStrings(candidate.requested_model_paths || []),
    explicit_path_supplied: explicitPathSupplied,
    matches_expected_task_kind: matchesExpectedTaskKind,
    source_root: normalizeString(candidate.source_root),
    discovery_sources: dedupeStrings(candidate.discovery_sources || []),
    catalog_entry_refs: compactCatalogRefs(candidate.catalog_entry_refs || []),
    candidate_validation: {
      gate_verdict: validationReport.machine_decision.gate_verdict,
      candidate_usable_for_sample1: validationReport.machine_decision.candidate_usable_for_sample1,
      runtime_ready: validationReport.runtime_resolution.runtime_ready,
      task_kind_status: validationReport.candidate_checks.task_kind_status,
      inferred_task_hint: validationReport.candidate_checks.inferred_task_hint,
      task_hint_sources: dedupeStrings(validationReport.candidate_checks.task_hint_sources || []),
      model_dir_looks_like_model: validationReport.candidate_checks.model_dir_looks_like_model,
      loadability_verdict: normalizeString(validationReport.loadability && validationReport.loadability.verdict),
      loadability_blocker: normalizeString(validationReport.loadability && validationReport.loadability.blocker_reason),
      top_recommended_action: validationReport.machine_decision.top_recommended_action,
    },
    artifact_refs: {
      ...artifactRefs,
      candidate_validation_report: relPath(validationReportPath),
    },
    command_refs: dedupeStrings([
      validationCommand(normalizedModelDir || requestedModelPath, expectedTaskKind),
    ]),
  };
}

function scoreCandidate(row) {
  let score = 0;
  if (row.matches_expected_task_kind === false) score -= 400;
  if (row.candidate_validation.candidate_usable_for_sample1) score += 1000;
  if (
    row.matches_expected_task_kind !== false &&
    row.candidate_validation.loadability_verdict === "native_loadable"
  ) {
    score += 400;
  }
  if (row.candidate_validation.runtime_ready) score += 200;
  if (row.candidate_validation.task_kind_status === "confirmed_by_local_metadata") score += 80;
  if (row.candidate_validation.model_dir_looks_like_model) score += 40;
  if (row.explicit_path_supplied) score += 20;
  return score;
}

function buildSample1CandidateShortlistReport({
  generatedAt = isoNow(),
  expectedTaskKind = "embedding",
  runtimeSelection = null,
  discoveryInputs = {},
  explicitModelPaths = [],
  candidateRows = [],
  wideCommonUserRoots = false,
} = {}) {
  const rows = Array.isArray(candidateRows) ? candidateRows.slice() : [];
  const inScopeRows = rows.filter((row) => row.matches_expected_task_kind !== false);
  const outOfScopeRows = rows.filter((row) => row.matches_expected_task_kind === false);
  const runtimeReady = !!(runtimeSelection && runtimeSelection.best);
  const normalizedTaskKind = normalizeTaskKindHint(expectedTaskKind) || "embedding";
  const passCandidates = inScopeRows.filter((row) => row.candidate_validation.candidate_usable_for_sample1 === true);
  const topCandidate = passCandidates[0] || inScopeRows[0] || null;
  const topAction =
    topCandidate && topCandidate.candidate_validation
      ? topCandidate.candidate_validation.top_recommended_action || {}
      : {};
  const topCandidateModelPath = topCandidate ? normalizeString(topCandidate.normalized_model_dir) : "";

  let searchOutcome = "no_candidate_dirs_found";
  let actionId = "source_or_import_first_native_embedding_model_dir";
  let actionSummary =
    "No usable local candidate is currently known. Source or import a real torch/transformers-native embedding model dir, then rerun the shortlist.";
  let nextStep = "source_or_import_candidate_then_rerun_shortlist";

  if (!runtimeReady) {
    searchOutcome = "runtime_not_ready";
    actionId = "restore_ready_transformers_runtime";
    actionSummary =
      "No ready torch/transformers runtime candidate is available, so shortlisted model dirs cannot be trusted for sample1 yet.";
    nextStep = "restore_runtime_then_rerun_shortlist";
  } else if (passCandidates.length > 0) {
    searchOutcome = "ready_candidate_found";
    actionId = "use_best_shortlisted_candidate_for_sample1";
    actionSummary =
      "At least one shortlisted candidate is native-loadable and can be used for sample1 real execution.";
    nextStep = "prepare_and_execute_sample1_real_run";
  } else if (inScopeRows.length > 0) {
    searchOutcome = "searched_no_pass_candidate";
    if (inScopeRows.some((row) => row.candidate_validation.loadability_blocker === "unsupported_quantization_config")) {
      actionId = "source_or_import_different_native_embedding_model_dir";
      actionSummary =
        "The searched candidates are real enough to inspect, but the current embedding dirs still look like unsupported quantized layouts for native transformers loading.";
      nextStep = "source_non_quantized_native_embedding_dir_then_rerun_shortlist";
    } else {
      actionId = normalizeString(topAction.action_id) || "inspect_or_import_native_embedding_model_dir";
      actionSummary =
        normalizeString(topAction.action_summary) ||
        "Inspect the top shortlisted candidate or import a different native-loadable embedding dir.";
      nextStep =
        normalizeString(topAction.next_step) ||
        "inspect_top_candidate_or_import_native_embedding_dir";
    }
  }

  return {
    schema_version: "xhub.lpr_w3_03_sample1_candidate_shortlist.v1",
    generated_at: generatedAt,
    scope: "Search and rank local sample1 embedding candidates across known roots and optional explicit paths.",
    fail_closed: true,
    sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
    expected_task_kind: normalizedTaskKind,
    scan_profile: wideCommonUserRoots === true
      ? "default_roots_plus_common_user_roots"
      : "default_roots_only_or_explicit_custom_roots",
    runtime_resolution: {
      runtime_ready: runtimeReady,
      selected_runtime_id:
        runtimeSelection && runtimeSelection.best
          ? normalizeString(runtimeSelection.best.candidate.runtime_id)
          : "",
      selected_runtime_label:
        runtimeSelection && runtimeSelection.best
          ? normalizeString(runtimeSelection.best.candidate.label)
          : "",
      selected_runtime_command:
        runtimeSelection && runtimeSelection.best
          ? normalizeString(runtimeSelection.best.candidate.command)
          : "",
      runtime_probe_count:
        runtimeSelection && Array.isArray(runtimeSelection.probes)
          ? runtimeSelection.probes.length
          : 0,
    },
    searched_inputs: {
      scan_roots: Array.isArray(discoveryInputs.scan_roots)
        ? discoveryInputs.scan_roots.map((root) => ({
            path: root,
            present: pathExists(root),
          }))
        : [],
      catalog_paths: Array.isArray(discoveryInputs.catalog_paths)
        ? dedupeStrings(discoveryInputs.catalog_paths)
        : [],
      explicit_model_paths: dedupeStrings(explicitModelPaths.map((item) => path.resolve(item))),
    },
    scan_roots: Array.isArray(discoveryInputs.scan_roots)
      ? discoveryInputs.scan_roots.map((root) => ({
          path: root,
          present: pathExists(root),
        }))
      : [],
    summary: {
      search_outcome: searchOutcome,
      candidates_considered: inScopeRows.length,
      filtered_out_task_mismatch_count: outOfScopeRows.length,
      pass_candidate_count: passCandidates.length,
      no_go_candidate_count: inScopeRows.length - passCandidates.length,
      top_candidate_model_path: topCandidateModelPath,
      top_recommended_action: {
        action_id: actionId,
        action_summary: actionSummary,
        next_step: nextStep,
      },
    },
    search_recovery: {
      top_candidate_model_path: topCandidateModelPath,
      top_candidate_exact_path_shortlist_refresh_command: topCandidateModelPath
        ? shortlistCommand(topCandidateModelPath, normalizedTaskKind)
        : "",
      top_candidate_exact_path_validation_command: topCandidateModelPath
        ? validationCommand(topCandidateModelPath, normalizedTaskKind)
        : "",
      explicit_model_path_shortlist_command_template: shortlistCommandTemplate(normalizedTaskKind),
      explicit_model_path_validation_command_template: validationCommandTemplate(normalizedTaskKind),
      wide_shortlist_search_command: wideShortlistCommand(normalizedTaskKind),
      custom_scan_root_shortlist_command_template: scanRootShortlistCommandTemplate(normalizedTaskKind),
      common_user_root_candidates: commonUserWideScanRoots.map((root) => ({
        path: root,
        present: pathExists(root),
      })),
    },
    candidates: inScopeRows,
    filtered_out_task_mismatch: outOfScopeRows.map((row) => ({
      normalized_model_dir: row.normalized_model_dir,
      requested_model_paths: row.requested_model_paths,
      discovery_sources: row.discovery_sources,
      candidate_validation: row.candidate_validation,
    })),
    next_actions: passCandidates.length > 0
      ? [
          "Use the top PASS candidate for sample1 real execution.",
          "Prepare the sample scaffold, execute the real run, then finalize and regenerate QA.",
        ]
      : [
          "Treat this shortlist as fail-closed evidence of what the machine actually searched.",
          "If you import or source a new model dir outside the default roots, rerun this helper with `--model-path` or `--scan-root` so the next report stays machine-readable.",
          "Only proceed to sample1 execution after a candidate row reports PASS.",
        ],
    command_refs: dedupeStrings([
      "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js",
      wideCommonUserRoots === true ? wideShortlistCommand(normalizedTaskKind) : "",
      ...rows.slice(0, 3).flatMap((row) => row.command_refs || []),
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
    const expectedTaskKind = normalizeTaskKindHint(args.taskKind) || "embedding";
    const discoveryInputs = buildDiscoveryInputs(args.scanRoots, {
      wideCommonUserRoots: args.wideCommonUserRoots,
    });
    const runtimeSelection = chooseReadyRuntime();
    const candidateRequests = collectCandidateRequests({
      discoveryInputs,
      explicitModelPaths: args.modelPaths,
    });
    const candidateRows = candidateRequests
      .map((candidate) =>
        buildShortlistCandidate({
          candidate,
          runtimeSelection,
          expectedTaskKind,
        })
      )
      .sort((left, right) => {
        const scoreDelta = scoreCandidate(right) - scoreCandidate(left);
        if (scoreDelta !== 0) return scoreDelta;
        return String(left.normalized_model_dir || "").localeCompare(String(right.normalized_model_dir || ""));
      })
      .map((row, index) => ({
        candidate_rank: index + 1,
        ...row,
      }));

    const report = buildSample1CandidateShortlistReport({
      expectedTaskKind,
      runtimeSelection,
      discoveryInputs,
      explicitModelPaths: args.modelPaths,
      candidateRows,
      wideCommonUserRoots: args.wideCommonUserRoots,
    });
    writeJSON(args.outJson, report);
    process.stdout.write(`${args.outJson}\n`);
  } catch (error) {
    process.stderr.write(`${String(error.message || error)}\n`);
    printUsage(1);
  }
}

module.exports = {
  buildDiscoveryInputs,
  buildSample1CandidateShortlistReport,
  commonUserWideScanRoots,
  collectCandidateRequests,
  parseArgs,
  scoreCandidate,
};

if (require.main === module) {
  main();
}
