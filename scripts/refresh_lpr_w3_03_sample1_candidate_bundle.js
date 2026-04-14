#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");

const {
  repoRoot,
  resolveReportsDir,
  writeJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");

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

function shellQuote(value) {
  const text = String(value || "");
  if (/^[A-Za-z0-9_./:@=,+-]+$/.test(text)) return text;
  return `'${text.replace(/'/g, `'\\''`)}'`;
}

function relPath(targetPath) {
  const resolved = path.resolve(String(targetPath || ""));
  const relative = path.relative(repoRoot, resolved);
  if (!relative || relative.startsWith("..")) return resolved;
  return relative.split(path.sep).join("/");
}

function readJSONIfExists(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function defaultOutputPath(reportsDir = resolveReportsDir()) {
  return path.join(reportsDir, "lpr_w3_03_sample1_candidate_bundle.v1.json");
}

function defaultWideShortlistPath(reportsDir = resolveReportsDir()) {
  return path.join(reportsDir, "lpr_w3_03_sample1_candidate_shortlist.wide_scan.v1.json");
}

function defaultValidationPath(reportsDir = resolveReportsDir()) {
  return path.join(reportsDir, "lpr_w3_03_sample1_candidate_validation.v1.json");
}

function defaultShortlistPath(reportsDir = resolveReportsDir()) {
  return path.join(reportsDir, "lpr_w3_03_sample1_candidate_shortlist.v1.json");
}

function defaultAcceptancePath(reportsDir = resolveReportsDir()) {
  return path.join(reportsDir, "lpr_w3_03_sample1_candidate_acceptance.v1.json");
}

function defaultHelperLocalServiceRecoveryPath(reportsDir = resolveReportsDir()) {
  return path.join(reportsDir, "lpr_w3_03_sample1_helper_local_service_recovery.v1.json");
}

function defaultRegistrationPath(reportsDir = resolveReportsDir()) {
  return path.join(reportsDir, "lpr_w3_03_sample1_candidate_registration_packet.v1.json");
}

function defaultHandoffPath(reportsDir = resolveReportsDir()) {
  return path.join(reportsDir, "lpr_w3_03_sample1_operator_handoff.v1.json");
}

function defaultRequireRealPath(reportsDir = resolveReportsDir()) {
  return path.join(reportsDir, "lpr_w3_03_a_require_real_evidence.v1.json");
}

function printUsage(exitCode) {
  const message = [
    "usage:",
    "  node scripts/refresh_lpr_w3_03_sample1_candidate_bundle.js \\",
    "    [--model-path /absolute/path/to/model_dir] \\",
    "    [--task-kind embedding] \\",
    "    [--wide-common-user-roots] \\",
    "    [--reports-dir build/reports] \\",
    "    [--out-json build/reports/lpr_w3_03_sample1_candidate_bundle.v1.json]",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function parseArgs(argv) {
  const out = {
    modelPath: "",
    taskKind: "embedding",
    wideCommonUserRoots: false,
    reportsDir: "",
    outJson: "",
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = normalizeString(argv[i]);
    switch (token) {
      case "--model-path":
        out.modelPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--task-kind":
        out.taskKind = normalizeString(argv[++i]) || "embedding";
        break;
      case "--wide-common-user-roots":
        out.wideCommonUserRoots = true;
        break;
      case "--reports-dir":
        out.reportsDir = path.resolve(normalizeString(argv[++i]));
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

  const resolvedReportsDir = out.reportsDir || resolveReportsDir();
  return {
    ...out,
    reportsDir: resolvedReportsDir,
    outJson: out.outJson || defaultOutputPath(resolvedReportsDir),
  };
}

function resolveEffectiveModelPath({
  requestedModelPath = "",
  shortlist = null,
  wideShortlist = null,
} = {}) {
  const explicit = normalizeString(requestedModelPath);
  if (explicit) {
    return {
      model_path: explicit,
      source: "explicit_model_path",
    };
  }

  const defaultCandidate =
    shortlist && Array.isArray(shortlist.candidates) && shortlist.candidates[0]
      ? shortlist.candidates[0]
      : null;
  if (defaultCandidate && normalizeString(defaultCandidate.normalized_model_dir)) {
    return {
      model_path: normalizeString(defaultCandidate.normalized_model_dir),
      source: "default_shortlist_top_candidate",
    };
  }

  const wideCandidate =
    wideShortlist && Array.isArray(wideShortlist.candidates) && wideShortlist.candidates[0]
      ? wideShortlist.candidates[0]
      : null;
  if (wideCandidate && normalizeString(wideCandidate.normalized_model_dir)) {
    return {
      model_path: normalizeString(wideCandidate.normalized_model_dir),
      source: "wide_shortlist_top_candidate",
    };
  }

  return {
    model_path: "",
    source: "none",
  };
}

function buildRefreshSequence({
  taskKind = "embedding",
  effectiveModelPath = "",
  effectiveModelPathSource = "none",
  wideCommonUserRoots = false,
  reportsDir = resolveReportsDir(),
} = {}) {
  const wideShortlistPath = defaultWideShortlistPath(reportsDir);
  const shortlistArgs = ["--task-kind", taskKind];
  if (normalizeString(effectiveModelPath)) {
    shortlistArgs.push("--model-path", effectiveModelPath);
  }
  const steps = [
    {
      step_id: "refresh_shortlist_default",
      script: "scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js",
      args: shortlistArgs,
      output_path: defaultShortlistPath(reportsDir),
    },
  ];

  const shouldRefreshWideShortlist =
    wideCommonUserRoots === true && normalizeString(effectiveModelPathSource) !== "explicit_model_path";

  if (shouldRefreshWideShortlist) {
    steps.push({
      step_id: "refresh_shortlist_wide",
      script: "scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js",
      args: [
        ...shortlistArgs,
        "--wide-common-user-roots",
        "--out-json",
        wideShortlistPath,
      ],
      output_path: wideShortlistPath,
    });
  }

  steps.push({
    step_id: "refresh_acceptance_bootstrap",
    script: "scripts/generate_lpr_w3_03_sample1_candidate_acceptance.js",
    args: [],
    output_path: defaultAcceptancePath(reportsDir),
  });
  steps.push({
    step_id: "refresh_helper_local_service_recovery",
    script: "scripts/generate_lpr_w3_03_sample1_helper_local_service_recovery.js",
    args: [],
    output_path: defaultHelperLocalServiceRecoveryPath(reportsDir),
  });

  if (normalizeString(effectiveModelPath)) {
    steps.push(
      {
        step_id: "refresh_validation",
        script: "scripts/generate_lpr_w3_03_sample1_candidate_validation.js",
        args: ["--model-path", effectiveModelPath],
        output_path: defaultValidationPath(reportsDir),
      },
      {
        step_id: "refresh_registration",
        script: "scripts/generate_lpr_w3_03_sample1_candidate_registration_packet.js",
        args: ["--model-path", effectiveModelPath, "--task-kind", taskKind],
        output_path: defaultRegistrationPath(reportsDir),
      }
    );
  }

  steps.push(
    {
      step_id: "refresh_handoff_first_pass",
      script: "scripts/generate_lpr_w3_03_sample1_operator_handoff.js",
      args: [],
      output_path: defaultHandoffPath(reportsDir),
    },
    {
      step_id: "refresh_acceptance_final",
      script: "scripts/generate_lpr_w3_03_sample1_candidate_acceptance.js",
      args: [],
      output_path: defaultAcceptancePath(reportsDir),
    },
    {
      step_id: "refresh_handoff_final",
      script: "scripts/generate_lpr_w3_03_sample1_operator_handoff.js",
      args: [],
      output_path: defaultHandoffPath(reportsDir),
    },
    {
      step_id: "refresh_require_real",
      script: "scripts/generate_lpr_w3_03_a_require_real_evidence.js",
      args: [],
      output_path: defaultRequireRealPath(reportsDir),
    }
  );

  return steps.map((step) => ({
    ...step,
    command: [
      "node",
      step.script,
      ...step.args.map((item) => shellQuote(item)),
    ].join(" "),
  }));
}

function buildBundleReport({
  generatedAt = isoNow(),
  reportsDir = resolveReportsDir(),
  requestedModelPath = "",
  effectiveModelPath = "",
  effectiveModelPathSource = "none",
  taskKind = "embedding",
  wideCommonUserRoots = false,
  refreshSteps = [],
  shortlist = null,
  wideShortlist = null,
  acceptance = null,
  helperLocalServiceRecovery = null,
  registration = null,
  handoff = null,
  requireReal = null,
  validation = null,
} = {}) {
  const topCandidate =
    shortlist && Array.isArray(shortlist.candidates) && shortlist.candidates[0]
      ? shortlist.candidates[0]
      : null;
  const requireRealDecision =
    requireReal && requireReal.machine_decision && typeof requireReal.machine_decision === "object"
      ? requireReal.machine_decision
      : {};
  const registrationPatchSummary =
    registration && registration.catalog_patch_plan_summary && typeof registration.catalog_patch_plan_summary === "object"
      ? registration.catalog_patch_plan_summary
      : null;
  const wideShortlistRefreshed = Array.isArray(refreshSteps)
    && refreshSteps.some((step) => normalizeString(step.step_id) === "refresh_shortlist_wide");

  return {
    schema_version: "xhub.lpr_w3_03_sample1_candidate_bundle.v1",
    generated_at: generatedAt,
    scope:
      "One-shot refresh bundle for sample1 candidate discovery, exact-path validation, registration, operator handoff, acceptance contract, and require-real gate truth.",
    fail_closed: true,
    reports_dir: relPath(reportsDir),
    task_kind: normalizeString(taskKind) || "embedding",
    requested_model_path: normalizeString(requestedModelPath),
    effective_model_path: normalizeString(effectiveModelPath),
    effective_model_path_source: normalizeString(effectiveModelPathSource) || "none",
    wide_common_user_roots_refreshed: wideShortlistRefreshed,
    refresh_steps: refreshSteps.map((step) => ({
      step_id: step.step_id,
      command: step.command,
      output_ref: relPath(step.output_path),
    })),
    artifact_refs: {
      shortlist_report: relPath(defaultShortlistPath(reportsDir)),
      wide_shortlist_report: wideShortlistRefreshed ? relPath(defaultWideShortlistPath(reportsDir)) : "",
      acceptance_report: relPath(defaultAcceptancePath(reportsDir)),
      helper_local_service_recovery_report: relPath(
        defaultHelperLocalServiceRecoveryPath(reportsDir)
      ),
      validation_report: validation ? relPath(defaultValidationPath(reportsDir)) : "",
      registration_report: registration ? relPath(defaultRegistrationPath(reportsDir)) : "",
      operator_handoff_report: relPath(defaultHandoffPath(reportsDir)),
      require_real_report: relPath(defaultRequireRealPath(reportsDir)),
      candidate_catalog_patch_plan:
        registrationPatchSummary && normalizeString(registrationPatchSummary.artifact_ref)
          ? normalizeString(registrationPatchSummary.artifact_ref)
          : "",
    },
    search_context: {
      default_scan_profile: normalizeString(shortlist && shortlist.scan_profile),
      wide_scan_profile: normalizeString(wideShortlist && wideShortlist.scan_profile),
      search_outcome: normalizeString(shortlist && shortlist.summary && shortlist.summary.search_outcome),
      candidates_considered: Number(shortlist && shortlist.summary && shortlist.summary.candidates_considered || 0),
      filtered_out_task_mismatch_count: Number(
        shortlist && shortlist.summary && shortlist.summary.filtered_out_task_mismatch_count || 0
      ),
      top_candidate_model_path: normalizeString(topCandidate && topCandidate.normalized_model_dir),
      top_candidate_blocker: normalizeString(
        topCandidate && topCandidate.candidate_validation && topCandidate.candidate_validation.loadability_blocker
      ),
    },
    current_machine_state: {
      acceptance_handoff_state: normalizeString(
        acceptance && acceptance.current_machine_state && acceptance.current_machine_state.handoff_state
      ),
      acceptance_top_recommended_action:
        acceptance && acceptance.current_machine_state
          ? acceptance.current_machine_state.top_recommended_action || null
          : null,
      validation_gate_verdict: normalizeString(validation && validation.machine_decision && validation.machine_decision.gate_verdict),
      registration_gate_verdict: normalizeString(registration && registration.candidate_validation && registration.candidate_validation.gate_verdict),
      registration_catalog_write_allowed_now:
        registration && registration.machine_decision && registration.machine_decision.catalog_write_allowed_now === true,
      registration_catalog_patch_blocked_reason: normalizeString(
        registrationPatchSummary && registrationPatchSummary.blocked_reason
      ),
      handoff_state: normalizeString(handoff && handoff.handoff_state),
      handoff_blocker_class: normalizeString(handoff && handoff.blocker_class),
      helper_route_ready_verdict: normalizeString(
        helperLocalServiceRecovery &&
          helperLocalServiceRecovery.helper_route_contract &&
          helperLocalServiceRecovery.helper_route_contract.helper_route_ready_verdict
      ),
      helper_top_recommended_action:
        helperLocalServiceRecovery && helperLocalServiceRecovery.top_recommended_action
          ? helperLocalServiceRecovery.top_recommended_action
          : null,
      require_real_gate_verdict: normalizeString(requireReal && requireReal.gate_verdict),
      require_real_verdict_reason: normalizeString(requireReal && requireReal.verdict_reason),
      sample1_overall_recommended_action_id: normalizeString(
        requireRealDecision.sample1_overall_recommended_action_id
      ),
      sample1_execution_ready: requireRealDecision.sample1_execution_ready === true,
      sample1_current_blockers: dedupeStrings(requireRealDecision.sample1_current_blockers || []),
    },
    next_actions: dedupeStrings([
      normalizeString(
        acceptance &&
          acceptance.current_machine_state &&
          acceptance.current_machine_state.top_recommended_action &&
          acceptance.current_machine_state.top_recommended_action.next_step
      ),
      normalizeString(
        registration &&
          registration.machine_decision &&
          registration.machine_decision.top_recommended_action &&
          registration.machine_decision.top_recommended_action.next_step
      ),
      normalizeString(
        helperLocalServiceRecovery &&
          helperLocalServiceRecovery.top_recommended_action &&
          helperLocalServiceRecovery.top_recommended_action.next_step
      ),
      normalizeString(requireRealDecision.sample1_overall_recommended_action_id),
      ...(Array.isArray(requireReal && requireReal.next_required_artifacts)
        ? requireReal.next_required_artifacts.map((item) => normalizeString(item))
        : []),
    ]),
    notes: dedupeStrings([
      "This helper refreshes sample1 candidate truth only. It does not auto-write external models_catalog.json / models_state.json files.",
      "If you need release-facing boundary/readiness exports after this bundle, rerun `bash scripts/refresh_oss_release_evidence.sh`.",
      wideCommonUserRoots && !wideShortlistRefreshed
        ? "Wide common-user-root scanning was requested, but skipped because an explicit model path already defined the exact candidate to validate."
        : "",
      normalizeString(effectiveModelPath)
        ? "An effective model path was resolved, so exact-path validation and registration were refreshed in the same run."
        : "No effective model path was available, so this run refreshed shortlist/acceptance/handoff/require-real without exact-path validation or registration.",
    ]),
  };
}

function runNodeScript(step, env = process.env) {
  const result = cp.spawnSync(
    process.execPath,
    [path.join(repoRoot, step.script), ...step.args],
    {
      cwd: repoRoot,
      env,
      encoding: "utf8",
    }
  );
  if (result.status !== 0) {
    throw new Error(
      [
        `step ${step.step_id} failed`,
        normalizeString(result.stderr),
        normalizeString(result.stdout),
      ]
        .filter(Boolean)
        .join("\n")
    );
  }
  return normalizeString(result.stdout) || step.output_path;
}

function refreshSample1CandidateBundle(args, options = {}) {
  const env = {
    ...process.env,
    ...(options.env || {}),
  };
  if (normalizeString(args.reportsDir)) {
    env.LPR_W3_03_REQUIRE_REAL_REPORTS_DIR = args.reportsDir;
  }

  const baseShortlistStep = buildRefreshSequence({
    taskKind: args.taskKind,
    effectiveModelPath: args.modelPath,
    effectiveModelPathSource: normalizeString(args.modelPath) ? "explicit_model_path" : "none",
    wideCommonUserRoots: args.wideCommonUserRoots,
    reportsDir: args.reportsDir,
  }).filter((step) =>
    step.step_id === "refresh_shortlist_default" || step.step_id === "refresh_shortlist_wide"
  );

  for (const step of baseShortlistStep) {
    runNodeScript(step, env);
  }

  const shortlist = readJSONIfExists(defaultShortlistPath(args.reportsDir));
  const wideShortlist = args.wideCommonUserRoots
    ? readJSONIfExists(defaultWideShortlistPath(args.reportsDir))
    : null;
  const resolvedModelPath = resolveEffectiveModelPath({
    requestedModelPath: args.modelPath,
    shortlist,
    wideShortlist,
  });

  const refreshSteps = buildRefreshSequence({
    taskKind: args.taskKind,
    effectiveModelPath: resolvedModelPath.model_path,
    effectiveModelPathSource: resolvedModelPath.source,
    wideCommonUserRoots: args.wideCommonUserRoots,
    reportsDir: args.reportsDir,
  });

  const alreadyRan = new Set(baseShortlistStep.map((step) => step.step_id));
  for (const step of refreshSteps) {
    if (alreadyRan.has(step.step_id)) continue;
    runNodeScript(step, env);
  }

  const acceptance = readJSONIfExists(defaultAcceptancePath(args.reportsDir));
  const helperLocalServiceRecovery = readJSONIfExists(
    defaultHelperLocalServiceRecoveryPath(args.reportsDir)
  );
  const validation = resolvedModelPath.model_path
    ? readJSONIfExists(defaultValidationPath(args.reportsDir))
    : null;
  const registration = resolvedModelPath.model_path
    ? readJSONIfExists(defaultRegistrationPath(args.reportsDir))
    : null;
  const handoff = readJSONIfExists(defaultHandoffPath(args.reportsDir));
  const requireReal = readJSONIfExists(defaultRequireRealPath(args.reportsDir));

  const report = buildBundleReport({
    reportsDir: args.reportsDir,
    requestedModelPath: args.modelPath,
    effectiveModelPath: resolvedModelPath.model_path,
    effectiveModelPathSource: resolvedModelPath.source,
    taskKind: args.taskKind,
    wideCommonUserRoots: args.wideCommonUserRoots,
    refreshSteps,
    shortlist,
    wideShortlist,
    acceptance,
    helperLocalServiceRecovery,
    validation,
    registration,
    handoff,
    requireReal,
  });

  writeJSON(args.outJson, report);
  return report;
}

function main() {
  try {
    const args = parseArgs(process.argv);
    const report = refreshSample1CandidateBundle(args);
    process.stdout.write(`${args.outJson}\n`);
    if (!report || !report.schema_version) {
      throw new Error("bundle report missing schema_version");
    }
  } catch (error) {
    process.stderr.write(`${String(error.message || error)}\n`);
    printUsage(1);
  }
}

module.exports = {
  buildBundleReport,
  buildRefreshSequence,
  defaultOutputPath,
  refreshSample1CandidateBundle,
  resolveEffectiveModelPath,
};

if (require.main === module) {
  main();
}
