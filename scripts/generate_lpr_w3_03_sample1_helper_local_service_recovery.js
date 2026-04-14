#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const {
  resolveReportsDir,
  writeJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");
const {
  readJSON,
} = require("./lpr_w3_03_require_real_status.js");

const HELPER_PROBE_REF = "build/reports/lpr_w3_03_d_helper_bridge_probe.v1.json";
const defaultOutputPath = path.join(
  resolveReportsDir(),
  "lpr_w3_03_sample1_helper_local_service_recovery.v1.json"
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
    outJson: defaultOutputPath,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = normalizeString(argv[i]);
    switch (token) {
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
    "  node scripts/generate_lpr_w3_03_sample1_helper_local_service_recovery.js",
    "  node scripts/generate_lpr_w3_03_sample1_helper_local_service_recovery.js --out-json build/reports/lpr_w3_03_sample1_helper_local_service_recovery.v1.json",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function helperRouteReady(summary = {}) {
  const environment =
    summary.lmstudio_environment && typeof summary.lmstudio_environment === "object"
      ? summary.lmstudio_environment
      : {};
  return !!(
    summary.helper_binary_found === true &&
    environment.enable_local_service === true &&
    normalizeString(summary.daemon_probe_after) === "helper_bridge_ready" &&
    summary.server_models_endpoint_ok === true
  );
}

function buildTopRecommendedAction(helperProbe = null) {
  const probe = helperProbe && typeof helperProbe === "object" ? helperProbe : {};
  const summary = probe.summary && typeof probe.summary === "object" ? probe.summary : {};
  const environment =
    summary.lmstudio_environment && typeof summary.lmstudio_environment === "object"
      ? summary.lmstudio_environment
      : {};
  const helperBinaryPath = normalizeString(probe.helper_binary_path) || "~/.lmstudio/bin/lms";
  const settingsPath = normalizeString(environment.settings_path) || "~/.lmstudio/settings.json";

  if (summary.helper_binary_found !== true) {
    return {
      action_id: "restore_lm_studio_helper_binary",
      action_summary:
        "The LM Studio helper binary is missing, so the helper route cannot be treated as a usable secondary route.",
      next_step: "install_or_restore_lms_binary_then_rerun_helper_probe",
      command_or_ref: "Restore ~/.lmstudio/bin/lms by completing LM Studio installation or repair.",
    };
  }

  if (environment.enable_local_service === false) {
    return {
      action_id: "enable_lm_studio_local_service",
      action_summary:
        `LM Studio helper is installed, but ${settingsPath} still resolves to enableLocalService=false. Turn local service on before trusting the helper route.`,
      next_step: "turn_on_local_service_then_rerun_helper_probe",
      command_or_ref: `LM Studio -> Settings -> Developer -> Local Service (${settingsPath})`,
    };
  }

  if (environment.app_first_load === true || environment.cli_installed === false) {
    return {
      action_id: "complete_lm_studio_first_launch",
      action_summary:
        "LM Studio still looks like a first-launch environment. Finish first-launch tasks and local service setup before treating the helper route as ready.",
      next_step: "complete_first_launch_then_rerun_helper_probe",
      command_or_ref: "Open LM Studio once and complete first-launch prompts, then verify local service is enabled.",
    };
  }

  if (
    normalizeString(summary.daemon_probe_after) !== "helper_bridge_ready" ||
    summary.server_models_endpoint_ok !== true
  ) {
    return {
      action_id: "inspect_helper_bridge_startup",
      action_summary:
        "Local service no longer looks config-disabled, but the helper server still is not answering the ready contract on loopback.",
      next_step: "inspect_lms_server_status_then_rerun_helper_probe",
      command_or_ref: `${helperBinaryPath} server status --json`,
    };
  }

  return {
    action_id: "keep_helper_route_secondary_only",
    action_summary:
      "The helper bridge looks ready, but it remains a secondary reference route. Prefer a native-loadable embedding dir when one is available.",
    next_step: "refresh_sample1_bundle_and_compare_native_vs_helper_routes",
    command_or_ref: "node scripts/refresh_lpr_w3_03_sample1_candidate_bundle.js --wide-common-user-roots",
  };
}

function buildRequiredReadySignals() {
  return [
    "helper_binary_found=true",
    "lmstudio_environment.enable_local_service=true",
    "daemon_probe_after=helper_bridge_ready",
    "server_models_endpoint_ok=true",
    "helper server loopback endpoint /v1/models returns HTTP 200",
  ];
}

function buildRejectSignals() {
  return [
    {
      signal: "helper_binary_found=false",
      reason: "No LM Studio helper binary is available, so the helper route cannot be treated as ready.",
    },
    {
      signal: "lmstudio_environment.enable_local_service=false",
      reason: "LM Studio local service is disabled in settings, so the helper route stays blocked.",
    },
    {
      signal: "daemon_probe_after=helper_local_service_disabled",
      reason: "Even after startup attempts, helper probing still reports the local-service-disabled state.",
    },
    {
      signal: "server_result_reason=helper_local_service_disabled",
      reason: "The helper could not auto-start a usable loopback server while local service remains disabled.",
    },
    {
      signal: "server_models_endpoint_ok=false",
      reason: "The helper loopback endpoint is not actually serving /v1/models yet.",
    },
  ];
}

function buildOperatorWorkflow(helperProbe = null) {
  const probe = helperProbe && typeof helperProbe === "object" ? helperProbe : {};
  const summary = probe.summary && typeof probe.summary === "object" ? probe.summary : {};
  const environment =
    summary.lmstudio_environment && typeof summary.lmstudio_environment === "object"
      ? summary.lmstudio_environment
      : {};
  const helperBinaryPath = normalizeString(probe.helper_binary_path) || "~/.lmstudio/bin/lms";
  const settingsPath = normalizeString(environment.settings_path) || "~/.lmstudio/settings.json";
  const steps = [
    {
      step_id: "refresh_helper_probe",
      allowed_now: true,
      description:
        "Refresh the helper bridge probe first so settings, daemon status, and loopback reachability stay machine-readable.",
      command: "node scripts/generate_lpr_w3_03_d_helper_bridge_probe.js",
    },
    environment.enable_local_service === false
      ? {
          step_id: "enable_lmstudio_local_service",
          allowed_now: true,
          description:
            `Turn on LM Studio local service in ${settingsPath} before trusting the helper route.`,
          command_or_ref: `LM Studio -> Settings -> Developer -> Local Service (${settingsPath})`,
        }
      : null,
    environment.app_first_load === true || environment.cli_installed === false
      ? {
          step_id: "complete_first_launch",
          allowed_now: true,
          description:
            "If LM Studio still looks like a first-launch install, complete its first-launch prompts before retrying helper startup.",
          command_or_ref: "Open LM Studio once and complete first-launch prompts.",
        }
      : null,
    {
      step_id: "inspect_server_status",
      allowed_now: true,
      description:
        "Inspect whether LM Studio thinks the helper server is already running on the expected loopback port.",
      command: `${helperBinaryPath} server status --json`,
    },
    {
      step_id: "probe_loopback_models_endpoint",
      allowed_now: environment.enable_local_service === true,
      description:
        "Confirm the helper loopback endpoint answers /v1/models before treating the helper route as usable.",
      command: "curl -fsS http://127.0.0.1:1234/v1/models",
    },
    {
      step_id: "refresh_helper_recovery_packet",
      allowed_now: true,
      description:
        "After any settings or startup change, regenerate this recovery packet so downstream operator surfaces reflect the new truth.",
      command: "node scripts/generate_lpr_w3_03_sample1_helper_local_service_recovery.js",
    },
    {
      step_id: "refresh_sample1_bundle",
      allowed_now: true,
      description:
        "Refresh the sample1 bundle so handoff, require-real, and product-exit surfaces inherit the latest helper-route truth.",
      command: "node scripts/refresh_lpr_w3_03_sample1_candidate_bundle.js --wide-common-user-roots",
    },
  ];
  return steps.filter(Boolean);
}

function buildHelperLocalServiceRecoveryReport({
  generatedAt = isoNow(),
  helperProbe = null,
} = {}) {
  const probe = helperProbe && typeof helperProbe === "object" ? helperProbe : {};
  const summary = probe.summary && typeof probe.summary === "object" ? probe.summary : {};
  const environment =
    summary.lmstudio_environment && typeof summary.lmstudio_environment === "object"
      ? summary.lmstudio_environment
      : {};
  const ready = helperRouteReady(summary);
  const topRecommendedAction = buildTopRecommendedAction(probe);

  return {
    schema_version: "xhub.lpr_w3_03_sample1_helper_local_service_recovery.v1",
    generated_at: generatedAt,
    scope:
      "Operator-facing helper/local-service recovery contract for sample1's secondary helper bridge route.",
    fail_closed: true,
    sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
    current_machine_state: {
      helper_binary_found: summary.helper_binary_found === true,
      helper_binary_path: normalizeString(probe.helper_binary_path),
      helper_server_base_url: normalizeString(probe.helper_server_base_url),
      daemon_probe_before: normalizeString(summary.daemon_probe_before),
      daemon_probe_after: normalizeString(summary.daemon_probe_after),
      server_result_reason: normalizeString(summary.server_result_reason),
      server_models_endpoint_ok: summary.server_models_endpoint_ok === true,
      settings_found: environment.settings_found === true,
      settings_path: normalizeString(environment.settings_path),
      enable_local_service:
        typeof environment.enable_local_service === "boolean" ? environment.enable_local_service : null,
      cli_installed:
        typeof environment.cli_installed === "boolean" ? environment.cli_installed : null,
      app_first_load:
        typeof environment.app_first_load === "boolean" ? environment.app_first_load : null,
      attempted_install_lms_cli_on_startup:
        typeof environment.attempted_install_lms_cli_on_startup === "boolean"
          ? environment.attempted_install_lms_cli_on_startup
          : null,
      llmster_pid_lock_path: normalizeString(environment.llmster_pid_lock_path),
      llmster_pid_lock_value: normalizeString(environment.llmster_pid_lock_value),
      primary_blocker: normalizeString(summary.primary_blocker),
      recommended_next_step: normalizeString(summary.recommended_next_step),
    },
    helper_route_contract: {
      helper_route_role: "secondary_reference_only",
      helper_route_ready_verdict: ready
        ? "PASS(helper_bridge_ready_for_secondary_reference_route)"
        : "NO_GO(helper_bridge_not_ready_for_secondary_reference_route)",
      required_ready_signals: buildRequiredReadySignals(),
      reject_signals: buildRejectSignals(),
    },
    top_recommended_action: topRecommendedAction,
    operator_workflow: buildOperatorWorkflow(probe),
    artifact_refs: {
      helper_probe_report: HELPER_PROBE_REF,
      helper_probe_artifacts:
        probe.artifact_refs && typeof probe.artifact_refs === "object" ? probe.artifact_refs : null,
    },
    command_refs: dedupeStrings([
      "node scripts/generate_lpr_w3_03_d_helper_bridge_probe.js",
      "node scripts/generate_lpr_w3_03_sample1_helper_local_service_recovery.js",
      "node scripts/refresh_lpr_w3_03_sample1_candidate_bundle.js --wide-common-user-roots",
      normalizeString(probe.helper_binary_path)
        ? `${normalizeString(probe.helper_binary_path)} server status --json`
        : "",
      "curl -fsS http://127.0.0.1:1234/v1/models",
    ]),
    notes: dedupeStrings([
      "This helper route stays secondary/reference-only. A native-loadable embedding dir remains the preferred path for sample1.",
      summary.server_models_endpoint_ok === true
        ? "The helper loopback endpoint is currently reachable, but do not let that override the native-dir contract."
        : "Do not count the helper route as ready until /v1/models is actually reachable on loopback.",
      environment.enable_local_service === false
        ? "Current machine truth says LM Studio local service is disabled in settings."
        : "",
    ]),
  };
}

function main() {
  try {
    const args = parseArgs(process.argv);
    const reportsDir = resolveReportsDir();
    const helperProbe = readJSONIfExists(path.join(reportsDir, "lpr_w3_03_d_helper_bridge_probe.v1.json"));
    const report = buildHelperLocalServiceRecoveryReport({ helperProbe });
    writeJSON(args.outJson, report);
    process.stdout.write(`${args.outJson}\n`);
  } catch (error) {
    process.stderr.write(`${String(error.message || error)}\n`);
    printUsage(1);
  }
}

module.exports = {
  buildHelperLocalServiceRecoveryReport,
  helperRouteReady,
};

if (require.main === module) {
  main();
}
