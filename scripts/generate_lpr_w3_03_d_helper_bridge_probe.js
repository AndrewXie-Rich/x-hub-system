#!/usr/bin/env node
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const cp = require("node:child_process");

const {
  reportsDir,
  repoRoot,
  writeJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");

const outputPath = path.join(reportsDir, "lpr_w3_03_d_helper_bridge_probe.v1.json");
const artifactRoot = path.join(reportsDir, "lpr_w3_03_require_real", "helper_bridge_probe");
const lmStudioHome = path.join(os.homedir(), ".lmstudio");
const helperBinaryPath = path.join(os.homedir(), ".lmstudio", "bin", "lms");
const helperServerBaseUrl = "http://127.0.0.1:1234";
const helperModuleDir = path.join(repoRoot, "x-hub", "python-runtime", "python_service");
const lmStudioSettingsPath = path.join(lmStudioHome, "settings.json");
const llmsterPidLockPath = path.join(lmStudioHome, ".internal", "llmster-pid.lock");

function isoNow() {
  return new Date().toISOString();
}

function pathExists(targetPath) {
  try {
    return fs.existsSync(targetPath);
  } catch {
    return false;
  }
}

function relPath(targetPath) {
  return path.relative(repoRoot, targetPath).split(path.sep).join("/");
}

function safeMkdir(targetPath) {
  fs.mkdirSync(targetPath, { recursive: true });
}

function readTextIfExists(targetPath) {
  try {
    if (!fs.existsSync(targetPath)) return "";
    return fs.readFileSync(targetPath, "utf8");
  } catch {
    return "";
  }
}

function readJSONIfExists(targetPath) {
  return tryParseJSON(readTextIfExists(targetPath));
}

function trimOutput(text, maxChars = 8000) {
  const normalized = String(text || "").trim();
  if (!normalized) return "";
  if (normalized.length <= maxChars) return normalized;
  return `${normalized.slice(0, maxChars)}\n...[truncated]`;
}

function shellJoin(parts) {
  return parts
    .map((part) => {
      const text = String(part);
      if (/^[A-Za-z0-9_./:@=,+-]+$/.test(text)) return text;
      return `'${text.replace(/'/g, `'\\''`)}'`;
    })
    .join(" ");
}

function runCommand(command, args, options = {}) {
  const startedAt = Date.now();
  const result = cp.spawnSync(command, args, {
    cwd: options.cwd || repoRoot,
    env: options.env || process.env,
    input: options.input || undefined,
    encoding: "utf8",
    timeout: Number.isFinite(options.timeoutMs) ? options.timeoutMs : 15000,
    maxBuffer: 32 * 1024 * 1024,
  });
  const finishedAt = Date.now();
  return {
    command: shellJoin([command, ...args]),
    cwd: relPath(options.cwd || repoRoot),
    started_at_utc: new Date(startedAt).toISOString(),
    finished_at_utc: new Date(finishedAt).toISOString(),
    duration_ms: Math.max(0, finishedAt - startedAt),
    exit_code: typeof result.status === "number" ? result.status : -1,
    signal: result.signal || "",
    ok: result.status === 0,
    timed_out: !!(result.error && result.error.code === "ETIMEDOUT"),
    error: result.error ? String(result.error.message || result.error) : "",
    stdout: result.stdout || "",
    stderr: result.stderr || "",
  };
}

function persist(dirPath, prefix, runResult) {
  safeMkdir(dirPath);
  fs.writeFileSync(path.join(dirPath, `${prefix}.stdout.log`), String(runResult.stdout || ""), "utf8");
  fs.writeFileSync(path.join(dirPath, `${prefix}.stderr.log`), String(runResult.stderr || ""), "utf8");
  writeJSON(path.join(dirPath, `${prefix}.meta.json`), {
    command: runResult.command,
    cwd: runResult.cwd,
    started_at_utc: runResult.started_at_utc,
    finished_at_utc: runResult.finished_at_utc,
    duration_ms: runResult.duration_ms,
    exit_code: runResult.exit_code,
    signal: runResult.signal,
    ok: runResult.ok,
    timed_out: runResult.timed_out,
    error: runResult.error,
  });
}

function tryParseJSON(text) {
  const raw = String(text || "").trim();
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function pythonHelperProbe(options = {}) {
  const script = [
    "import json, pathlib, sys",
    `sys.path.insert(0, ${JSON.stringify(helperModuleDir)})`,
    "from helper_binary_bridge import probe_helper_binary_bridge, ensure_helper_bridge_server, list_helper_bridge_downloaded_models, list_helper_bridge_loaded_models",
    "probe = probe_helper_binary_bridge('lms')",
    "out = {",
    "  'probe': probe.to_dict(),",
    "  'downloaded_models': list_helper_bridge_downloaded_models(probe),",
    "  'loaded_models': list_helper_bridge_loaded_models(probe),",
    "}",
    options.ensureServer
      ? `out['server_result'] = ensure_helper_bridge_server(probe, auto_start_daemon=${options.autoStartDaemon ? "True" : "False"}, auto_start_server=${options.autoStartServer ? "True" : "False"}, timeout_sec=${Number(options.timeoutSec || 8)})`
      : "",
    "out['probe_after'] = probe_helper_binary_bridge('lms').to_dict()",
    "print(json.dumps(out, ensure_ascii=False))",
  ].filter(Boolean).join("\n");
  return runCommand("python3", ["-c", script], {
    timeoutMs: Number.isFinite(options.timeoutMs) ? options.timeoutMs : 30000,
  });
}

function helperEnvironmentFromProbe(probe) {
  return (((probe || {}).metadata || {}).lmStudioEnvironment || {});
}

function boolOrNull(value) {
  return typeof value === "boolean" ? value : null;
}

function lmStudioEnvironmentSummary(probe) {
  const probeEnvironment = helperEnvironmentFromProbe(probe);
  const probeFlags = probeEnvironment.settingsFlags || {};
  const settingsJson = readJSONIfExists(lmStudioSettingsPath) || {};
  const developer = (settingsJson && typeof settingsJson === "object" && settingsJson.developer && typeof settingsJson.developer === "object")
    ? settingsJson.developer
    : {};
  return {
    home_path: pathExists(lmStudioHome) ? lmStudioHome : "",
    settings_path: pathExists(lmStudioSettingsPath) ? lmStudioSettingsPath : "",
    settings_found: pathExists(lmStudioSettingsPath),
    enable_local_service:
      boolOrNull(probeFlags.enableLocalService) ?? boolOrNull(settingsJson.enableLocalService),
    cli_installed:
      boolOrNull(probeFlags.cliInstalled) ?? boolOrNull(settingsJson.cliInstalled),
    app_first_load:
      boolOrNull(probeFlags.appFirstLoad) ?? boolOrNull(settingsJson.appFirstLoad),
    attempted_install_lms_cli_on_startup:
      boolOrNull(probeFlags.attemptedInstallLmsCliOnStartup)
      ?? boolOrNull(developer.attemptedInstallLmsCliOnStartup),
    llmster_pid_lock_path: pathExists(llmsterPidLockPath) ? llmsterPidLockPath : "",
    llmster_pid_lock_value: String(readTextIfExists(llmsterPidLockPath) || "").trim(),
  };
}

function summarize(before, daemonUp, serverStartDirect, after, curlModels, serverStatusAfter) {
  const beforeJson = tryParseJSON(before.stdout) || {};
  const afterJson = tryParseJSON(after.stdout) || {};
  const probeBefore = beforeJson.probe || {};
  const probeAfter = afterJson.probe_after || afterJson.probe || {};
  const serverResult = afterJson.server_result || {};
  const environment = lmStudioEnvironmentSummary(probeBefore);
  const blocker = [];
  if (!pathExists(helperBinaryPath)) blocker.push("helper_binary_missing");
  if (String(probeBefore.reasonCode || "") === "helper_local_service_disabled") {
    blocker.push("helper_local_service_disabled_before_probe");
  }
  if (String(probeBefore.reasonCode || "") === "helper_service_down") blocker.push("helper_service_down_before_probe");
  if (daemonUp.timed_out) blocker.push("daemon_up_hangs_without_becoming_ready");
  if (serverStartDirect.timed_out) blocker.push("server_start_hangs_without_listening");
  if (String(probeAfter.reasonCode || "") !== "helper_bridge_ready") blocker.push(`probe_after=${String(probeAfter.reasonCode || "unknown")}`);
  if (serverResult && serverResult.ok !== true) blocker.push(`server_result=${String(serverResult.reasonCode || "unknown")}`);
  if (!curlModels.ok) blocker.push("server_port_1234_not_reachable");
  const localServiceDisabled = environment.enable_local_service === false
    || String(probeAfter.reasonCode || "") === "helper_local_service_disabled";
  return {
    helper_binary_found: pathExists(helperBinaryPath),
    daemon_probe_before: String(probeBefore.reasonCode || ""),
    daemon_up_command_timed_out: !!daemonUp.timed_out,
    daemon_up_output_excerpt: trimOutput([daemonUp.stdout, daemonUp.stderr].filter(Boolean).join("\n"), 240),
    server_start_direct_timed_out: !!serverStartDirect.timed_out,
    server_start_direct_output_excerpt: trimOutput([serverStartDirect.stdout, serverStartDirect.stderr].filter(Boolean).join("\n"), 240),
    daemon_probe_after: String(probeAfter.reasonCode || ""),
    server_result_reason: String(serverResult.reasonCode || ""),
    server_status_after: serverStatusAfter.parsed || {},
    server_models_endpoint_ok: !!curlModels.ok,
    lmstudio_environment: environment,
    primary_blocker: blocker.join(";"),
    recommended_next_step:
      String(probeAfter.reasonCode || "") === "helper_bridge_ready" && curlModels.ok
        ? "helper_bridge_is_ready_try_loading_embedding_model_via_helper_route"
        : localServiceDisabled
          ? "enable_lm_studio_local_service_or_complete_first_launch_then_rerun_helper_bridge_probe"
          : "manual_lm_studio_launch_or_os_level_service_repair_then_rerun_helper_bridge_probe",
  };
}

function filterHelperProcessLines(text) {
  return String(text || "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => /LM Studio|lms|llmster/i.test(line))
    .join("\n");
}

function main() {
  safeMkdir(artifactRoot);
  const before = pythonHelperProbe({ ensureServer: false, timeoutMs: 15000 });
  persist(artifactRoot, "python_probe_before", before);

  const daemonStatusBefore = runCommand(helperBinaryPath, ["daemon", "status"], { timeoutMs: 8000 });
  persist(artifactRoot, "daemon_status_before", daemonStatusBefore);

  const serverStatusBefore = runCommand(helperBinaryPath, ["server", "status", "--json"], { timeoutMs: 8000 });
  persist(artifactRoot, "server_status_before", serverStatusBefore);

  const daemonUp = runCommand(helperBinaryPath, ["daemon", "up", "--json"], { timeoutMs: 15000 });
  persist(artifactRoot, "daemon_up", daemonUp);

  const serverStartDirect = runCommand(helperBinaryPath, ["server", "start", "--bind", "127.0.0.1", "--port", "1234"], { timeoutMs: 15000 });
  persist(artifactRoot, "server_start_direct", serverStartDirect);

  const after = pythonHelperProbe({
    ensureServer: true,
    autoStartDaemon: true,
    autoStartServer: true,
    timeoutSec: 10,
    timeoutMs: 30000,
  });
  persist(artifactRoot, "python_probe_after", after);

  const daemonStatusAfter = runCommand(helperBinaryPath, ["daemon", "status"], { timeoutMs: 8000 });
  persist(artifactRoot, "daemon_status_after", daemonStatusAfter);

  const serverStatusAfter = runCommand(helperBinaryPath, ["server", "status", "--json"], { timeoutMs: 8000 });
  persist(artifactRoot, "server_status_after", serverStatusAfter);

  const curlModels = runCommand("curl", ["-fsS", `${helperServerBaseUrl}/v1/models`], { timeoutMs: 8000 });
  persist(artifactRoot, "curl_models", curlModels);

  const llmsterPid = String(readTextIfExists(llmsterPidLockPath) || "").trim();
  const llmsterLsof = /^[0-9]+$/.test(llmsterPid)
    ? runCommand("lsof", ["-nP", "-p", llmsterPid], { timeoutMs: 5000 })
    : null;
  if (llmsterLsof) persist(artifactRoot, "llmster_lsof", llmsterLsof);

  const beforeJson = tryParseJSON(before.stdout);
  const afterJson = tryParseJSON(after.stdout);
  const report = {
    schema_version: "xhub.lpr_w3_03_helper_bridge_probe.v1",
    generated_at: isoNow(),
    scope: "Probe whether LM Studio helper bridge can replace the missing native-loadable embedding directory path for sample1.",
    fail_closed: true,
    helper_binary_path: pathExists(helperBinaryPath) ? helperBinaryPath : "",
    helper_server_base_url: helperServerBaseUrl,
    probe_before: beforeJson,
    probe_after: afterJson,
    command_results: {
      daemon_status_before: {
        ok: daemonStatusBefore.ok,
        exit_code: daemonStatusBefore.exit_code,
        output_excerpt: trimOutput([daemonStatusBefore.stdout, daemonStatusBefore.stderr].filter(Boolean).join("\n"), 240),
      },
      server_status_before: {
        ok: serverStatusBefore.ok,
        exit_code: serverStatusBefore.exit_code,
        parsed: tryParseJSON(serverStatusBefore.stdout),
        output_excerpt: trimOutput([serverStatusBefore.stdout, serverStatusBefore.stderr].filter(Boolean).join("\n"), 240),
      },
      daemon_up: {
        ok: daemonUp.ok,
        exit_code: daemonUp.exit_code,
        timed_out: daemonUp.timed_out,
        output_excerpt: trimOutput([daemonUp.stdout, daemonUp.stderr].filter(Boolean).join("\n"), 240),
        error: daemonUp.error,
      },
      server_start_direct: {
        ok: serverStartDirect.ok,
        exit_code: serverStartDirect.exit_code,
        timed_out: serverStartDirect.timed_out,
        output_excerpt: trimOutput([serverStartDirect.stdout, serverStartDirect.stderr].filter(Boolean).join("\n"), 240),
        error: serverStartDirect.error,
      },
      daemon_status_after: {
        ok: daemonStatusAfter.ok,
        exit_code: daemonStatusAfter.exit_code,
        output_excerpt: trimOutput([daemonStatusAfter.stdout, daemonStatusAfter.stderr].filter(Boolean).join("\n"), 240),
      },
      server_status_after: {
        ok: serverStatusAfter.ok,
        exit_code: serverStatusAfter.exit_code,
        parsed: tryParseJSON(serverStatusAfter.stdout),
        output_excerpt: trimOutput([serverStatusAfter.stdout, serverStatusAfter.stderr].filter(Boolean).join("\n"), 240),
      },
      curl_models: {
        ok: curlModels.ok,
        exit_code: curlModels.exit_code,
        output_excerpt: trimOutput([curlModels.stdout, curlModels.stderr].filter(Boolean).join("\n"), 240),
      },
      llmster_process_snapshot: {
        ok: llmsterLsof ? llmsterLsof.ok : false,
        exit_code: llmsterLsof ? llmsterLsof.exit_code : -1,
        pid_lock_value: llmsterPid,
        output_excerpt: trimOutput(llmsterLsof ? filterHelperProcessLines(llmsterLsof.stdout) : "", 1200),
      },
    },
    summary: summarize(before, daemonUp, serverStartDirect, after, curlModels, {
      parsed: tryParseJSON(serverStatusAfter.stdout),
    }),
    artifact_refs: {
      python_probe_before_meta: relPath(path.join(artifactRoot, "python_probe_before.meta.json")),
      daemon_up_meta: relPath(path.join(artifactRoot, "daemon_up.meta.json")),
      server_start_direct_meta: relPath(path.join(artifactRoot, "server_start_direct.meta.json")),
      python_probe_after_meta: relPath(path.join(artifactRoot, "python_probe_after.meta.json")),
      curl_models_meta: relPath(path.join(artifactRoot, "curl_models.meta.json")),
      llmster_lsof_meta: llmsterLsof ? relPath(path.join(artifactRoot, "llmster_lsof.meta.json")) : "",
    },
  };

  writeJSON(outputPath, report);
  process.stdout.write(`${outputPath}\n`);
}

if (require.main === module) {
  main();
}
