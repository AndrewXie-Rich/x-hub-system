#!/usr/bin/env node
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const cp = require("node:child_process");

const repoRoot = path.resolve(__dirname, "..");
const reportsDirDefault = path.join(repoRoot, "build", "reports");
const outputPathDefault = path.join(
  reportsDirDefault,
  "lpr_w4_08_b_gguf_require_real_evidence.v1.json"
);
const artifactDirDefault = path.join(reportsDirDefault, "lpr_w4_08_b_gguf_require_real");
const helperBinaryPathDefault = path.join(os.homedir(), ".lmstudio", "bin", "lms");
const xhubBinaryDefault = path.join(
  repoRoot,
  "x-hub",
  "macos",
  "RELFlowHub",
  ".build",
  "debug",
  "XHub"
);

function isoNow() {
  return new Date().toISOString();
}

function normalizeString(value, fallback = "") {
  const trimmed = String(value ?? "").trim();
  return trimmed || fallback;
}

function normalizeArray(value) {
  return Array.isArray(value) ? value : [];
}

function normalizeObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function normalizeBoolean(value) {
  return value === true;
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function writeJSON(filePath, value) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function readJSONIfExists(filePath) {
  try {
    if (!filePath || !fs.existsSync(filePath)) return null;
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function readTextIfExists(filePath) {
  try {
    if (!filePath || !fs.existsSync(filePath)) return "";
    return fs.readFileSync(filePath, "utf8");
  } catch {
    return "";
  }
}

function parseJSONText(text) {
  try {
    return JSON.parse(String(text || ""));
  } catch {
    return null;
  }
}

function relPath(targetPath) {
  const normalized = normalizeString(targetPath);
  if (!normalized) return "";
  if (!path.isAbsolute(normalized)) return normalized.split(path.sep).join("/");
  if (!normalized.startsWith(repoRoot)) return normalized;
  return path.relative(repoRoot, normalized).split(path.sep).join("/");
}

function copyFileIfExists(sourcePath, destinationPath) {
  if (!sourcePath || !fs.existsSync(sourcePath)) return "";
  ensureDir(path.dirname(destinationPath));
  fs.copyFileSync(sourcePath, destinationPath);
  return destinationPath;
}

function uniqueStrings(values = []) {
  const seen = new Set();
  const out = [];
  for (const value of values) {
    const normalized = normalizeString(value);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    out.push(normalized);
  }
  return out;
}

function runCommand(command, args = [], options = {}) {
  const result = {
    command: [command, ...args],
    cwd: normalizeString(options.cwd, repoRoot),
    timeout_ms: Number.isFinite(options.timeoutMs) ? options.timeoutMs : 90_000,
    started_at: isoNow(),
  };
  try {
    const execResult = cp.spawnSync(command, args, {
      cwd: result.cwd,
      env: options.env || process.env,
      encoding: "utf8",
      timeout: result.timeout_ms,
      maxBuffer: 32 * 1024 * 1024,
    });
    result.exit_code = typeof execResult.status === "number" ? execResult.status : null;
    result.signal = execResult.signal || "";
    result.stdout = execResult.stdout || "";
    result.stderr = execResult.stderr || "";
    result.error = execResult.error ? String(execResult.error.message || execResult.error) : "";
    result.timed_out = !!execResult.error && execResult.error.code === "ETIMEDOUT";
    result.ok = result.exit_code === 0 && !result.timed_out;
  } catch (error) {
    result.exit_code = null;
    result.signal = "";
    result.stdout = "";
    result.stderr = "";
    result.error = String(error && error.message ? error.message : error);
    result.timed_out = false;
    result.ok = false;
  }
  result.finished_at = isoNow();
  return result;
}

function persistCommandArtifacts(artifactDir, prefix, result) {
  ensureDir(artifactDir);
  const stdoutPath = path.join(artifactDir, `${prefix}.stdout.log`);
  const stderrPath = path.join(artifactDir, `${prefix}.stderr.log`);
  const metaPath = path.join(artifactDir, `${prefix}.meta.json`);
  fs.writeFileSync(stdoutPath, String(result.stdout || ""), "utf8");
  fs.writeFileSync(stderrPath, String(result.stderr || ""), "utf8");
  writeJSON(metaPath, {
    command: result.command,
    cwd: result.cwd,
    timeout_ms: result.timeout_ms,
    started_at: result.started_at,
    finished_at: result.finished_at,
    exit_code: result.exit_code,
    signal: result.signal,
    ok: result.ok,
    timed_out: result.timed_out,
    error: result.error,
  });
  return {
    stdout: relPath(stdoutPath),
    stderr: relPath(stderrPath),
    meta: relPath(metaPath),
  };
}

function printUsage(exitCode) {
  const message = [
    "usage:",
    "  node scripts/generate_lpr_w4_08_b_gguf_require_real_evidence.js --base-dir /path/to/probe_base_dir",
    "options:",
    "  --base-dir <dir>        Runtime base dir that contains warmup/task request JSON and ai_runtime_status.json",
    "  --helper-binary <path>  LM Studio helper binary path (default ~/.lmstudio/bin/lms)",
    "  --xhub-bin <path>       XHub CLI binary path (default x-hub/macos/RELFlowHub/.build/debug/XHub)",
    "  --artifact-dir <dir>    Artifact capture directory under build/reports/",
    "  --out <path>            Output report JSON path",
    "  --skip-run              Reuse existing JSON artifacts instead of rerunning XHub local-runtime",
    "  --help                  Show this message",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function parseArgs(argv) {
  const options = {
    baseDir: "",
    helperBinaryPath: helperBinaryPathDefault,
    xhubBinaryPath: xhubBinaryDefault,
    artifactDir: artifactDirDefault,
    outputPath: outputPathDefault,
    skipRun: false,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = normalizeString(argv[i]);
    switch (token) {
      case "--base-dir":
        options.baseDir = path.resolve(normalizeString(argv[++i]));
        break;
      case "--helper-binary":
        options.helperBinaryPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--xhub-bin":
        options.xhubBinaryPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--artifact-dir":
        options.artifactDir = path.resolve(normalizeString(argv[++i]));
        break;
      case "--out":
        options.outputPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--skip-run":
        options.skipRun = true;
        break;
      case "--help":
      case "-h":
        printUsage(0);
        break;
      default:
        throw new Error(`unknown arg: ${token}`);
    }
  }

  if (!options.baseDir) {
    throw new Error("missing --base-dir");
  }

  return options;
}

function resolvePathCaseInsensitive(rootDir, basename) {
  const exactPath = path.join(rootDir, basename);
  if (fs.existsSync(exactPath)) return exactPath;
  return "";
}

function findProviderStatus(runtimeStatus, providerId) {
  const normalizedProviderId = normalizeString(providerId).toLowerCase();
  const providers = normalizeObject(runtimeStatus.providers);
  const direct = normalizeObject(providers[normalizedProviderId]);
  if (Object.keys(direct).length > 0) return direct;
  const directAlt = normalizeObject(providers[providerId]);
  if (Object.keys(directAlt).length > 0) return directAlt;
  return {};
}

function normalizeLoadedInstances(runtimeStatus, providerStatus) {
  const topLevel = normalizeArray(runtimeStatus.loadedInstances);
  const providerLevel = normalizeArray(providerStatus.loadedInstances);
  const combined = [...topLevel, ...providerLevel]
    .map((row) => normalizeObject(row))
    .filter((row) => Object.keys(row).length > 0);
  return combined;
}

function findMonitorProvider(runtimeStatus, providerId) {
  const normalizedProviderId = normalizeString(providerId).toLowerCase();
  const monitorSnapshot = normalizeObject(runtimeStatus.monitorSnapshot);
  return (
    normalizeArray(monitorSnapshot.providers)
      .map((row) => normalizeObject(row))
      .find((row) => normalizeString(row.provider).toLowerCase() === normalizedProviderId) || {}
  );
}

function findHelperLoadedIdentifier(helperLoadedRows, identifier) {
  const normalizedIdentifier = normalizeString(identifier);
  return normalizeArray(helperLoadedRows)
    .map((row) => normalizeObject(row))
    .some((row) => normalizeString(row.identifier) === normalizedIdentifier);
}

function findLoadedInstanceByModel(loadedInstances, modelId, instanceKey) {
  const normalizedModelId = normalizeString(modelId);
  const normalizedInstanceKey = normalizeString(instanceKey);
  return normalizeArray(loadedInstances)
    .map((row) => normalizeObject(row))
    .find((row) => {
      const rowModelId = normalizeString(row.modelId || row.model_id);
      const rowInstanceKey = normalizeString(row.instanceKey || row.instance_key || row.identifier);
      return (
        (normalizedInstanceKey && rowInstanceKey === normalizedInstanceKey)
        || (normalizedModelId && rowModelId === normalizedModelId)
      );
    }) || {};
}

function evaluateHelperBridge(helperProbe = {}) {
  const daemonStatus = normalizeObject(helperProbe.daemonStatus);
  const serverStatus = normalizeObject(helperProbe.serverStatus);
  const httpModels = normalizeArray(helperProbe.httpModels);
  const helperLoadedRows = normalizeArray(helperProbe.loadedRows);

  const daemonRunning = normalizeString(daemonStatus.status).toLowerCase() === "running";
  const serverRunning = normalizeBoolean(serverStatus.running);
  const httpReachable = httpModels.length > 0;
  const helperReady = daemonRunning && serverRunning && httpReachable;

  let reasonCode = "";
  if (!daemonRunning) reasonCode = "helper_daemon_not_running";
  else if (!serverRunning) reasonCode = "helper_server_not_running";
  else if (!httpReachable) reasonCode = "helper_http_models_unreachable";

  return {
    helper_ready: helperReady,
    daemon_running: daemonRunning,
    server_running: serverRunning,
    http_models_visible: httpReachable,
    loaded_model_count: helperLoadedRows.length,
    reason_code: reasonCode,
  };
}

function buildGGUFRequireRealReport(input = {}) {
  const generatedAt = normalizeString(input.generatedAt, isoNow());
  const warmup = normalizeObject(input.warmup);
  const task = normalizeObject(input.task);
  const taskRequest = normalizeObject(input.taskRequest);
  const helperProbe = normalizeObject(input.helperProbe);
  const runtimeStatus = normalizeObject(input.runtimeStatus);
  const providerStatus = findProviderStatus(runtimeStatus, "llama.cpp");
  const monitorProvider = findMonitorProvider(runtimeStatus, "llama.cpp");
  const loadedInstances = normalizeLoadedInstances(runtimeStatus, providerStatus);
  const helperAssessment = evaluateHelperBridge(helperProbe);

  const expectedModelId = normalizeString(
    task.modelId || task.model_id || warmup.modelId || warmup.model_id || taskRequest.model_id
  );
  const expectedInstanceKey = normalizeString(
    task.instanceKey || task.instance_key || warmup.instanceKey || warmup.instance_key
  );
  const expectedModelPath = normalizeString(
    task.modelPath || task.model_path || warmup.modelPath || warmup.model_path
  );

  const warmupReady = normalizeBoolean(warmup.ok)
    && normalizeString(warmup.provider).toLowerCase() === "llama.cpp"
    && normalizeString(warmup.taskKind || warmup.task_kind).toLowerCase() === "embedding"
    && normalizeString(warmup.instanceKey || warmup.instance_key) !== "";

  const taskReady = normalizeBoolean(task.ok)
    && normalizeString(task.provider).toLowerCase() === "llama.cpp"
    && normalizeString(task.taskKind || task.task_kind).toLowerCase() === "embedding"
    && Number(task.vectorCount || 0) >= 1
    && Number(task.dims || 0) >= 1;

  const loadedInstance = findLoadedInstanceByModel(loadedInstances, expectedModelId, expectedInstanceKey);
  const runtimeTruthVisible = normalizeBoolean(providerStatus.ok)
    && normalizeBoolean(providerStatus.packInstalled)
    && normalizeString(providerStatus.packState).toLowerCase() === "installed"
    && normalizeString(providerStatus.runtimeSource).toLowerCase() === "helper_binary_bridge"
    && ["helper_bridge_ready", "helper_bridge_loaded"].includes(
      normalizeString(providerStatus.runtimeReasonCode).toLowerCase()
    )
    && Object.keys(loadedInstance).length > 0;

  const monitorLoadedInstanceCount = Number(monitorProvider.loadedInstanceCount || 0);
  const monitorTruthVisible = normalizeBoolean(monitorProvider.ok)
    && normalizeString(monitorProvider.reasonCode).toLowerCase() === "helper_bridge_loaded"
    && monitorLoadedInstanceCount >= 1;

  const helperLoadedIdentifierVisible = findHelperLoadedIdentifier(
    helperProbe.loadedRows,
    expectedInstanceKey
  );

  const blockers = [];
  if (!helperAssessment.helper_ready) blockers.push(helperAssessment.reason_code || "helper_bridge_not_ready");
  if (!warmupReady) blockers.push(normalizeString(warmup.reasonCode || warmup.error, "warmup_failed"));
  if (!taskReady) blockers.push(normalizeString(task.reasonCode || task.error, "task_failed"));
  if (!runtimeTruthVisible) blockers.push("runtime_truth_missing_loaded_instance");
  if (!monitorTruthVisible) blockers.push("monitor_truth_missing_loaded_instance");
  if (!helperLoadedIdentifierVisible) blockers.push("helper_loaded_identifier_missing");

  const pass = blockers.length === 0;
  const primaryBlocker = blockers[0] || "";

  const nextRequiredArtifacts = [];
  if (!helperAssessment.helper_ready) {
    nextRequiredArtifacts.push("LM Studio helper daemon/server reachable and /v1/models returning provider entries");
  }
  if (!warmupReady) {
    nextRequiredArtifacts.push("Successful GGUF warmup output with helper-backed instanceKey");
  }
  if (!taskReady) {
    nextRequiredArtifacts.push("Successful GGUF embedding task output with vectorCount>=1 and dims>=1");
  }
  if (!runtimeTruthVisible || !monitorTruthVisible) {
    nextRequiredArtifacts.push("ai_runtime_status.json monitor snapshot showing loaded llama.cpp instance truth");
  }
  if (!helperLoadedIdentifierVisible) {
    nextRequiredArtifacts.push("LM Studio helper loaded-model inventory containing the expected GGUF identifier");
  }

  return {
    schema_version: "xhub.lpr_w4_08_b_gguf_require_real_evidence.v1",
    generated_at: generatedAt,
    task_id: "LPR-W4-08-B",
    status: pass
      ? "PASS(gguf_require_real_closure_ready)"
      : `FAIL(${primaryBlocker || "gguf_require_real_blocked"})`,
    summary: {
      provider: "llama.cpp",
      task_kind: "embedding",
      model_id: expectedModelId,
      model_path: expectedModelPath,
      helper_bridge_ready: helperAssessment.helper_ready,
      warmup_succeeded: warmupReady,
      task_succeeded: taskReady,
      runtime_truth_visible: runtimeTruthVisible,
      monitor_truth_visible: monitorTruthVisible,
      helper_loaded_identifier_visible: helperLoadedIdentifierVisible,
      vector_count: Number(task.vectorCount || 0),
      dims: Number(task.dims || 0),
    },
    machine_decision: {
      gate_verdict: pass
        ? "PASS(gguf_require_real_closure_ready)"
        : "NO_GO(gguf_require_real_blocked)",
      require_real_evidence_complete: pass,
      primary_blocker_reason_code: primaryBlocker,
      current_blockers: blockers,
      shared_runtime_truth: runtimeTruthVisible && monitorTruthVisible,
      helper_bridge_ready: helperAssessment.helper_ready,
      helper_server_running: helperAssessment.server_running,
      helper_daemon_running: helperAssessment.daemon_running,
      warmup_succeeded: warmupReady,
      task_succeeded: taskReady,
      loaded_instance_visible: Object.keys(loadedInstance).length > 0,
      monitor_loaded_instance_count: monitorLoadedInstanceCount,
      task_dims: Number(task.dims || 0),
      task_vector_count: Number(task.vectorCount || 0),
    },
    helper_bridge: {
      daemon_status: normalizeObject(helperProbe.daemonStatus),
      server_status: normalizeObject(helperProbe.serverStatus),
      loaded_rows: normalizeArray(helperProbe.loadedRows),
      http_models: normalizeArray(helperProbe.httpModels),
    },
    execution_capture: {
      warmup,
      task,
    },
    runtime_truth: {
      provider_status: providerStatus,
      monitor_provider: monitorProvider,
      loaded_instance: loadedInstance,
      loaded_instance_count: Number(runtimeStatus.loadedInstanceCount || 0),
    },
    evidence_refs: uniqueStrings(normalizeArray(input.evidenceRefs)),
    next_required_artifacts: uniqueStrings(nextRequiredArtifacts),
  };
}

function main() {
  const options = parseArgs(process.argv);
  ensureDir(options.artifactDir);

  const warmupRequestPath = resolvePathCaseInsensitive(options.baseDir, "warmup_request.json");
  const taskRequestPath = resolvePathCaseInsensitive(options.baseDir, "task_request.json");
  const runtimeStatusPath = resolvePathCaseInsensitive(options.baseDir, "ai_runtime_status.json");
  if (!warmupRequestPath || !taskRequestPath) {
    throw new Error("base dir must contain warmup_request.json and task_request.json");
  }

  const artifactWarmupRequestPath = path.join(options.artifactDir, "warmup_request.json");
  const artifactTaskRequestPath = path.join(options.artifactDir, "task_request.json");
  copyFileIfExists(warmupRequestPath, artifactWarmupRequestPath);
  copyFileIfExists(taskRequestPath, artifactTaskRequestPath);

  const warmupOutputPath = path.join(options.artifactDir, "warmup_output.json");
  const taskOutputPath = path.join(options.artifactDir, "task_output.json");

  const evidenceRefs = [];
  evidenceRefs.push(relPath(artifactWarmupRequestPath), relPath(artifactTaskRequestPath));

  let warmupCommandResult = null;
  let taskCommandResult = null;

  if (!options.skipRun) {
    const warmupArgs = [
      "local-runtime",
      "--command", "manage-local-model",
      "--request-json", artifactWarmupRequestPath,
      "--base-dir", options.baseDir,
      "--out-json", warmupOutputPath,
      "--timeout-sec", "90",
    ];
    warmupCommandResult = runCommand(options.xhubBinaryPath, warmupArgs, {
      cwd: path.dirname(options.xhubBinaryPath),
      timeoutMs: 95_000,
    });
    const warmupArtifacts = persistCommandArtifacts(options.artifactDir, "warmup_local_runtime", warmupCommandResult);
    evidenceRefs.push(warmupArtifacts.meta, warmupArtifacts.stdout, warmupArtifacts.stderr);

    const taskArgs = [
      "local-runtime",
      "--command", "run-local-task",
      "--request-json", artifactTaskRequestPath,
      "--base-dir", options.baseDir,
      "--out-json", taskOutputPath,
      "--timeout-sec", "90",
    ];
    taskCommandResult = runCommand(options.xhubBinaryPath, taskArgs, {
      cwd: path.dirname(options.xhubBinaryPath),
      timeoutMs: 95_000,
    });
    const taskArtifacts = persistCommandArtifacts(options.artifactDir, "task_local_runtime", taskCommandResult);
    evidenceRefs.push(taskArtifacts.meta, taskArtifacts.stdout, taskArtifacts.stderr);
  } else {
    const existingWarmup = resolvePathCaseInsensitive(options.baseDir, "warmup_output.json");
    const existingTask = resolvePathCaseInsensitive(options.baseDir, "task_output.json");
    copyFileIfExists(existingWarmup, warmupOutputPath);
    copyFileIfExists(existingTask, taskOutputPath);
  }

  const helperDaemonResult = runCommand(options.helperBinaryPath, ["daemon", "status", "--json"], {
    timeoutMs: 10_000,
  });
  const helperServerResult = runCommand(options.helperBinaryPath, ["server", "status", "--json"], {
    timeoutMs: 10_000,
  });
  const helperPSResult = runCommand(options.helperBinaryPath, ["ps", "--json"], {
    timeoutMs: 10_000,
  });
  const helperModelsResult = runCommand("curl", ["-fsS", "http://127.0.0.1:1234/v1/models"], {
    timeoutMs: 10_000,
  });
  const helperArtifacts = {
    daemon: persistCommandArtifacts(options.artifactDir, "helper_daemon_status", helperDaemonResult),
    server: persistCommandArtifacts(options.artifactDir, "helper_server_status", helperServerResult),
    ps: persistCommandArtifacts(options.artifactDir, "helper_ps", helperPSResult),
    models: persistCommandArtifacts(options.artifactDir, "helper_http_models", helperModelsResult),
  };
  evidenceRefs.push(
    helperArtifacts.daemon.meta,
    helperArtifacts.server.meta,
    helperArtifacts.ps.meta,
    helperArtifacts.models.meta
  );

  const artifactRuntimeStatusPath = path.join(options.artifactDir, "ai_runtime_status.json");
  copyFileIfExists(runtimeStatusPath, artifactRuntimeStatusPath);
  if (fs.existsSync(warmupOutputPath)) evidenceRefs.push(relPath(warmupOutputPath));
  if (fs.existsSync(taskOutputPath)) evidenceRefs.push(relPath(taskOutputPath));
  if (fs.existsSync(artifactRuntimeStatusPath)) evidenceRefs.push(relPath(artifactRuntimeStatusPath));

  const report = buildGGUFRequireRealReport({
    generatedAt: isoNow(),
    warmup: readJSONIfExists(warmupOutputPath),
    task: readJSONIfExists(taskOutputPath),
    taskRequest: readJSONIfExists(artifactTaskRequestPath),
    helperProbe: {
      daemonStatus: parseJSONText(helperDaemonResult.stdout),
      serverStatus: parseJSONText(helperServerResult.stdout),
      loadedRows: parseJSONText(helperPSResult.stdout),
      httpModels: normalizeArray(normalizeObject(parseJSONText(helperModelsResult.stdout)).data),
    },
    runtimeStatus: readJSONIfExists(artifactRuntimeStatusPath),
    evidenceRefs,
  });

  report.execution_capture.warmup_command = normalizeObject(warmupCommandResult);
  report.execution_capture.task_command = normalizeObject(taskCommandResult);
  report.helper_bridge.artifact_refs = {
    daemon_status: helperArtifacts.daemon.meta,
    server_status: helperArtifacts.server.meta,
    loaded_rows: helperArtifacts.ps.meta,
    http_models: helperArtifacts.models.meta,
  };

  writeJSON(options.outputPath, report);
  process.stdout.write(`${options.outputPath}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${String(error && error.message ? error.message : error)}\n`);
    process.exit(1);
  }
}

module.exports = {
  buildGGUFRequireRealReport,
  evaluateHelperBridge,
};
