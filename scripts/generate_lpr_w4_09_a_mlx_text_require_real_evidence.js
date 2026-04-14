#!/usr/bin/env node
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const cp = require("node:child_process");
const { randomUUID } = require("node:crypto");

const {
  repoRoot,
  resolveReportsDir,
  writeJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");

const reportsDir = resolveReportsDir();
const defaultOutputPath = path.join(
  reportsDir,
  "lpr_w4_09_a_mlx_text_require_real_evidence.v1.json"
);
const defaultArtifactDir = path.join(reportsDir, "lpr_w4_09_a_mlx_text_require_real");
const legacyRuntimeEntry = path.join(
  repoRoot,
  "x-hub",
  "python-runtime",
  "python_service",
  "relflowhub_mlx_runtime.py"
);
const defaultPythonCandidates = [
  "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
  "/opt/homebrew/bin/python3",
  "python3",
];
const defaultModelCandidates = [
  path.join(os.homedir(), ".lmstudio", "models", "mlx-community", "Llama-3.2-3B-Instruct-4bit"),
  path.join(os.homedir(), ".lmstudio", "models", "mlx-community", "Qwen2.5-3B-Instruct-4bit"),
];

function isoNow() {
  return new Date().toISOString();
}

function normalizeString(value, fallback = "") {
  const normalized = String(value ?? "").trim();
  return normalized || fallback;
}

function normalizeObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function normalizeArray(value) {
  return Array.isArray(value) ? value : [];
}

function normalizeBoolean(value) {
  return value === true;
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function pathExists(targetPath) {
  return !!targetPath && fs.existsSync(targetPath);
}

function relPath(targetPath) {
  const normalized = normalizeString(targetPath);
  if (!normalized) return "";
  if (!path.isAbsolute(normalized)) return normalized.split(path.sep).join("/");
  if (!normalized.startsWith(repoRoot)) return normalized;
  return path.relative(repoRoot, normalized).split(path.sep).join("/");
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

function commandExists(command) {
  const normalized = normalizeString(command);
  if (!normalized) return false;
  if (normalized.includes(path.sep)) return pathExists(normalized);
  try {
    const result = cp.spawnSync("which", [normalized], {
      encoding: "utf8",
      timeout: 5_000,
      stdio: ["ignore", "pipe", "pipe"],
    });
    return result.status === 0;
  } catch {
    return false;
  }
}

function resolvePythonBinary(explicitPath) {
  const normalizedExplicit = normalizeString(explicitPath);
  if (normalizedExplicit) return normalizedExplicit;
  return (
    defaultPythonCandidates.find((candidate) => commandExists(candidate)) || defaultPythonCandidates[0]
  );
}

function resolveModelPath(explicitPath) {
  const normalizedExplicit = normalizeString(explicitPath);
  if (normalizedExplicit) return path.resolve(normalizedExplicit);
  const discovered = defaultModelCandidates.find((candidate) => pathExists(candidate));
  return path.resolve(discovered || defaultModelCandidates[0]);
}

function modelIdFromPath(modelPath) {
  const basename = path.basename(normalizeString(modelPath)).toLowerCase();
  const slug = basename.replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  return `mlx-text-${slug || "model"}-real`;
}

function buildRuntimeEnv(baseDir) {
  return {
    ...process.env,
    REL_FLOW_HUB_BASE_DIR: baseDir,
    PYTHONUNBUFFERED: "1",
    HF_HUB_OFFLINE: "1",
    TRANSFORMERS_OFFLINE: "1",
    HF_DATASETS_OFFLINE: "1",
    TOKENIZERS_PARALLELISM: "false",
  };
}

function buildModelCatalog(modelId, modelPath) {
  return {
    models: [
      {
        id: modelId,
        name: path.basename(modelPath),
        backend: "mlx",
        runtimeProviderID: "mlx",
        modelPath,
        taskKinds: ["text_generate"],
        maxContextLength: 8192,
      },
    ],
  };
}

function buildProviderPackRegistry() {
  return {
    schemaVersion: "xhub.provider_pack_registry.v1",
    updatedAt: Date.now() / 1000,
    packs: [
      {
        providerId: "mlx",
        engine: "mlx-llm",
        version: "builtin-2026-03-16",
        supportedFormats: ["mlx"],
        supportedDomains: ["text"],
        runtimeRequirements: {
          executionMode: "builtin_python",
          pythonModules: ["mlx", "mlx_lm"],
          notes: ["offline_only", "legacy_runtime_compatible"],
        },
        minHubVersion: "2026.03",
        installed: true,
        enabled: true,
        packState: "installed",
        reasonCode: "builtin_pack_registered",
      },
    ],
  };
}

function buildRoutingSettings(modelId) {
  return {
    schemaVersion: "xhub.routing_settings.v2",
    updatedAt: Date.now() / 1000,
    hubDefaultModelIdByTaskKind: {
      text_generate: modelId,
    },
    devicePreferredModelIdByTaskKind: {},
  };
}

function buildGenerateRequest(modelId) {
  return {
    type: "generate",
    req_id: randomUUID(),
    app_id: "lpr_w4_09_a_mlx_text_require_real",
    model_id: modelId,
    preferred_model_id: modelId,
    task_type: "text_generate",
    device_id: "release_evidence",
    prompt: "Reply in one short sentence confirming the local MLX legacy text path is working.",
    max_tokens: 48,
    temperature: 0.1,
    top_p: 0.95,
    created_at: Date.now() / 1000,
    auto_load: false,
  };
}

function buildModelCommand(action, modelId) {
  return {
    type: "model_command",
    req_id: randomUUID(),
    action,
    model_id: modelId,
    requested_at: Date.now() / 1000,
  };
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForProcessExit(child, timeoutMs) {
  if (!child) return { exited: true, exitCode: null, signal: "" };
  if (child.exitCode !== null || child.signalCode !== null) {
    return {
      exited: true,
      exitCode: child.exitCode,
      signal: child.signalCode || "",
    };
  }
  return new Promise((resolve) => {
    let settled = false;
    const finish = (payload) => {
      if (settled) return;
      settled = true;
      child.removeListener("exit", onExit);
      child.removeListener("error", onError);
      clearTimeout(timer);
      resolve(payload);
    };
    const onExit = (code, signal) => finish({ exited: true, exitCode: code, signal: signal || "" });
    const onError = (error) => finish({ exited: true, exitCode: null, signal: "", error: String(error && error.message ? error.message : error) });
    const timer = setTimeout(() => {
      finish({
        exited: child.exitCode !== null || child.signalCode !== null,
        exitCode: child.exitCode,
        signal: child.signalCode || "",
      });
    }, Math.max(1, timeoutMs));
    child.once("exit", onExit);
    child.once("error", onError);
  });
}

async function waitForRuntimeReady(baseDir, child, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  const runtimeStatusPath = path.join(baseDir, "ai_runtime_status.json");
  while (Date.now() < deadline) {
    if (child && child.exitCode !== null) {
      return {
        ok: false,
        reason: `runtime_exited:${child.exitCode}`,
        runtimeStatus: readJSONIfExists(runtimeStatusPath),
      };
    }
    const runtimeStatus = readJSONIfExists(runtimeStatusPath);
    const providerStatus = findProviderStatus(runtimeStatus, "mlx");
    if (normalizeBoolean(providerStatus.ok) && normalizeArray(providerStatus.availableTaskKinds).includes("text_generate")) {
      return {
        ok: true,
        runtimeStatus,
      };
    }
    await wait(250);
  }
  return {
    ok: false,
    reason: "runtime_ready_timeout",
    runtimeStatus: readJSONIfExists(runtimeStatusPath),
  };
}

async function waitForJSONFile(filePath, child, timeoutMs, validator = null) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (child && child.exitCode !== null) break;
    const payload = readJSONIfExists(filePath);
    if (payload) {
      if (!validator || validator(payload)) return payload;
    }
    await wait(200);
  }
  return readJSONIfExists(filePath);
}

function parseJSONL(text) {
  return String(text || "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch {
        return null;
      }
    })
    .filter((row) => row && typeof row === "object");
}

async function waitForAIResponse(responsePath, child, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (child && child.exitCode !== null) break;
    const text = readTextIfExists(responsePath);
    const events = parseJSONL(text);
    if (events.some((event) => normalizeString(event.type) === "done")) {
      return {
        path: responsePath,
        text,
        events,
      };
    }
    await wait(250);
  }
  const text = readTextIfExists(responsePath);
  return {
    path: responsePath,
    text,
    events: parseJSONL(text),
  };
}

function summarizeTextTaskResponse(events) {
  const normalizedEvents = normalizeArray(events).map((event) => normalizeObject(event));
  const startEvent = normalizedEvents.find((event) => normalizeString(event.type) === "start") || {};
  const doneEvent =
    [...normalizedEvents].reverse().find((event) => normalizeString(event.type) === "done") || {};
  const deltaEvents = normalizedEvents.filter((event) => normalizeString(event.type) === "delta");
  const outputText = deltaEvents.map((event) => normalizeString(event.text)).join("");
  const outputCharCount = outputText.length;
  return {
    ok: normalizeBoolean(doneEvent.ok) && outputCharCount > 0,
    provider: "mlx",
    taskKind: "text_generate",
    modelId: normalizeString(startEvent.model_id || doneEvent.model_id),
    instanceKey: normalizeString(doneEvent.instance_key || startEvent.instance_key),
    loadProfileHash: normalizeString(doneEvent.load_profile_hash || startEvent.load_profile_hash),
    effectiveContextLength: Number(
      doneEvent.effective_context_length || startEvent.effective_context_length || 0
    ),
    promptTokens: Number(doneEvent.promptTokens || 0),
    generationTokens: Number(doneEvent.generationTokens || 0),
    generationTPS: Number(doneEvent.generationTPS || 0),
    elapsedMs: Number(doneEvent.elapsed_ms || 0),
    reason: normalizeString(doneEvent.reason),
    deltaCount: deltaEvents.length,
    outputTextExcerpt: outputText.slice(0, 300),
    outputCharCount,
    startEvent,
    doneEvent,
  };
}

function copyFileIfExists(sourcePath, destinationPath) {
  if (!sourcePath || !fs.existsSync(sourcePath)) return "";
  ensureDir(path.dirname(destinationPath));
  fs.copyFileSync(sourcePath, destinationPath);
  return destinationPath;
}

function persistText(filePath, text) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, String(text || ""), "utf8");
}

function findProviderStatus(runtimeStatus, providerId) {
  const providers = normalizeObject(normalizeObject(runtimeStatus).providers);
  return normalizeObject(providers[normalizeString(providerId).toLowerCase()] || providers[providerId]);
}

function normalizeLoadedInstances(runtimeStatus, providerStatus) {
  const topLevel = normalizeArray(normalizeObject(runtimeStatus).loadedInstances);
  const providerLevel = normalizeArray(normalizeObject(providerStatus).loadedInstances);
  return [...topLevel, ...providerLevel]
    .map((row) => normalizeObject(row))
    .filter((row) => Object.keys(row).length > 0);
}

function findLoadedInstanceByModel(loadedInstances, modelId, instanceKey) {
  const normalizedModelId = normalizeString(modelId);
  const normalizedInstanceKey = normalizeString(instanceKey);
  return (
    normalizeArray(loadedInstances)
      .map((row) => normalizeObject(row))
      .find((row) => {
        const rowModelId = normalizeString(row.modelId || row.model_id);
        const rowInstanceKey = normalizeString(row.instanceKey || row.instance_key);
        return (
          (normalizedInstanceKey && rowInstanceKey === normalizedInstanceKey) ||
          (normalizedModelId && rowModelId === normalizedModelId)
        );
      }) || {}
  );
}

function findLegacyBenchRow(modelsBench, modelId) {
  return (
    normalizeArray(normalizeObject(modelsBench).results)
      .map((row) => normalizeObject(row))
      .find((row) => {
        return (
          normalizeString(row.modelId || row.model_id) === normalizeString(modelId) &&
          normalizeString(row.taskKind || row.task_kind).toLowerCase() === "text_generate" &&
          normalizeString(row.resultKind || row.result_kind).toLowerCase() === "legacy_text_bench"
        );
      }) || {}
  );
}

function buildMLXTextRequireRealReport(input = {}) {
  const generatedAt = normalizeString(input.generatedAt, isoNow());
  const modelPath = normalizeString(input.modelPath || normalizeObject(input.task).modelPath);
  const modelExists =
    input.modelExists === false ? false : !!normalizeString(modelPath);
  const modelId = normalizeString(
    input.modelId ||
      normalizeObject(input.task).modelId ||
      normalizeObject(input.loadResult).model_id ||
      normalizeObject(input.loadResult).modelId
  );
  const loadResult = normalizeObject(input.loadResult);
  const task = normalizeObject(input.task);
  const benchResult = normalizeObject(input.benchResult);
  const runtimeStatus = normalizeObject(input.runtimeStatus);
  const modelsBench = normalizeObject(input.modelsBench);
  const providerStatus = findProviderStatus(runtimeStatus, "mlx");
  const loadedInstances = normalizeLoadedInstances(runtimeStatus, providerStatus);
  const loadedInstance = findLoadedInstanceByModel(loadedInstances, modelId, task.instanceKey);
  const benchRow = findLegacyBenchRow(modelsBench, modelId);
  const captureError = normalizeObject(input.captureError);

  const runtimeReady = normalizeBoolean(providerStatus.ok);
  const runtimeStatusVisible = Number(runtimeStatus.updatedAt || 0) > 0;
  const loadReady = normalizeBoolean(loadResult.ok);
  const taskReady =
    normalizeBoolean(task.ok) &&
    normalizeString(task.reason).toLowerCase() === "eos" &&
    Number(task.outputCharCount || task.output_char_count || 0) > 0;
  const benchCommandReady = normalizeBoolean(benchResult.ok);
  const benchRowReady =
    normalizeBoolean(benchRow.ok) &&
    normalizeString(benchRow.resultKind || benchRow.result_kind).toLowerCase() === "legacy_text_bench" &&
    Number(benchRow.throughputValue || benchRow.generationTPS || 0) > 0;
  const runtimeTruthVisible =
    runtimeReady &&
    normalizeArray(providerStatus.availableTaskKinds).includes("text_generate") &&
    Object.keys(loadedInstance).length > 0;

  const blockers = [];
  if (!modelExists) blockers.push("model_path_not_found");
  if (!runtimeStatusVisible) blockers.push("runtime_status_missing");
  if (!runtimeReady) blockers.push(normalizeString(providerStatus.importError || captureError.error, "runtime_not_ready"));
  if (!loadReady) blockers.push(normalizeString(loadResult.msg || loadResult.error, "load_failed"));
  if (!taskReady) blockers.push(normalizeString(task.reason || task.error, "task_failed"));
  if (!benchCommandReady) blockers.push(normalizeString(benchResult.msg || benchResult.error, "bench_command_failed"));
  if (!benchRowReady) blockers.push("legacy_bench_missing");
  if (!runtimeTruthVisible) blockers.push("runtime_truth_missing_loaded_instance");
  const pass = blockers.length === 0;
  const primaryBlocker = blockers[0] || "";

  const nextRequiredArtifacts = [];
  if (!modelExists) nextRequiredArtifacts.push("Accessible local MLX text model directory");
  if (!runtimeStatusVisible || !runtimeReady) {
    nextRequiredArtifacts.push("Fresh ai_runtime_status.json showing mlx provider ready");
  }
  if (!loadReady) {
    nextRequiredArtifacts.push("Successful legacy model_command load result for the selected MLX text model");
  }
  if (!taskReady) {
    nextRequiredArtifacts.push("Successful legacy generate response JSONL with non-empty local text output");
  }
  if (!benchCommandReady || !benchRowReady) {
    nextRequiredArtifacts.push("models_bench.json row with resultKind=legacy_text_bench for the selected model");
  }
  if (!runtimeTruthVisible) {
    nextRequiredArtifacts.push("Runtime status showing the loaded MLX legacy instance after real task execution");
  }

  return {
    schema_version: "xhub.lpr_w4_09_a_mlx_text_require_real_evidence.v1",
    generated_at: generatedAt,
    work_order: "LPR-W4-09-A",
    status: pass
      ? "PASS(mlx_text_require_real_closure_ready)"
      : `FAIL(${primaryBlocker || "mlx_text_require_real_blocked"})`,
    summary: {
      provider: "mlx",
      lifecycle_mode: normalizeString(providerStatus.lifecycleMode || providerStatus.lifecycle_mode, "mlx_legacy"),
      model_id: modelId,
      model_path: modelPath,
      runtime_ready: runtimeReady,
      load_succeeded: loadReady,
      task_succeeded: taskReady,
      legacy_bench_ready: benchCommandReady && benchRowReady,
      runtime_truth_visible: runtimeTruthVisible,
      output_char_count: Number(task.outputCharCount || task.output_char_count || 0),
      generation_tps: Number(benchRow.throughputValue || benchRow.generationTPS || 0),
      peak_memory_bytes: Number(benchRow.peakMemoryBytes || 0),
    },
    machine_decision: {
      gate_verdict: pass
        ? "PASS(mlx_text_require_real_closure_ready)"
        : "NO_GO(mlx_text_require_real_blocked)",
      require_real_evidence_complete: pass,
      primary_blocker_reason_code: primaryBlocker,
      current_blockers: blockers,
      shared_runtime_truth: runtimeTruthVisible,
      runtime_ready: runtimeReady,
      load_succeeded: loadReady,
      task_succeeded: taskReady,
      legacy_bench_ready: benchCommandReady && benchRowReady,
      recommended_route: "mlx_legacy_runtime_loop",
    },
    execution_capture: {
      load_result: loadResult,
      task,
      bench_result: benchResult,
      capture_error: captureError,
    },
    runtime_truth: {
      provider_status: providerStatus,
      loaded_instance: loadedInstance,
      loaded_instance_count: Number(runtimeStatus.loadedInstanceCount || 0),
      bench_row: benchRow,
    },
    evidence_refs: uniqueStrings(normalizeArray(input.evidenceRefs)),
    next_required_artifacts: uniqueStrings(nextRequiredArtifacts),
  };
}

async function stopRuntime(child, baseDir) {
  if (!child) return { exited: true, exitCode: null, signal: "" };
  if (child.exitCode !== null || child.signalCode !== null) {
    return {
      exited: true,
      exitCode: child.exitCode,
      signal: child.signalCode || "",
    };
  }
  const stopPath = path.join(baseDir, "ai_runtime_stop.json");
  writeJSON(stopPath, {
    req_id: `stop-${randomUUID()}`,
    requested_at: Date.now() / 1000,
  });
  let exitState = await waitForProcessExit(child, 8_000);
  if (exitState.exited) return exitState;
  try {
    child.kill("SIGTERM");
  } catch {}
  exitState = await waitForProcessExit(child, 5_000);
  if (exitState.exited) return exitState;
  try {
    child.kill("SIGKILL");
  } catch {}
  return waitForProcessExit(child, 2_000);
}

async function runCapture(options) {
  const artifactDir = path.resolve(options.artifactDir);
  const runtimeBaseDir = path.join(artifactDir, "runtime_base_dir");
  const pythonBin = resolvePythonBinary(options.pythonBin);
  const modelPath = resolveModelPath(options.modelPath);
  const modelId = modelIdFromPath(modelPath);
  const runtimeStdoutPath = path.join(artifactDir, "runtime.stdout.log");
  const runtimeStderrPath = path.join(artifactDir, "runtime.stderr.log");
  const captureErrorPath = path.join(artifactDir, "capture_error.json");
  const evidenceRefs = [];

  fs.rmSync(artifactDir, { recursive: true, force: true });
  ensureDir(artifactDir);
  ensureDir(runtimeBaseDir);

  const modelCatalogPath = path.join(runtimeBaseDir, "models_catalog.json");
  const providerPackRegistryPath = path.join(runtimeBaseDir, "provider_pack_registry.json");
  const routingSettingsPath = path.join(runtimeBaseDir, "routing_settings.json");
  writeJSON(modelCatalogPath, buildModelCatalog(modelId, modelPath));
  writeJSON(providerPackRegistryPath, buildProviderPackRegistry());
  writeJSON(routingSettingsPath, buildRoutingSettings(modelId));
  evidenceRefs.push(relPath(modelCatalogPath), relPath(providerPackRegistryPath), relPath(routingSettingsPath));

  const stdoutStream = fs.createWriteStream(runtimeStdoutPath, { flags: "a" });
  const stderrStream = fs.createWriteStream(runtimeStderrPath, { flags: "a" });
  const child = cp.spawn(pythonBin, [legacyRuntimeEntry], {
    cwd: repoRoot,
    env: buildRuntimeEnv(runtimeBaseDir),
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (child.stdout) child.stdout.on("data", (chunk) => stdoutStream.write(chunk));
  if (child.stderr) child.stderr.on("data", (chunk) => stderrStream.write(chunk));
  evidenceRefs.push(relPath(runtimeStdoutPath), relPath(runtimeStderrPath));

  const artifactRefs = {
    runtime_stdout: relPath(runtimeStdoutPath),
    runtime_stderr: relPath(runtimeStderrPath),
  };

  try {
    const runtimeReady = await waitForRuntimeReady(runtimeBaseDir, child, 120_000);
    if (!runtimeReady.ok) {
      const captureError = {
        error: normalizeString(runtimeReady.reason, "runtime_not_ready"),
        runtimeStatus: normalizeObject(runtimeReady.runtimeStatus),
      };
      writeJSON(captureErrorPath, captureError);
      evidenceRefs.push(relPath(captureErrorPath));
      return {
        modelId,
        modelPath,
        runtimeBaseDir,
        artifactRefs,
        evidenceRefs,
        captureError,
      };
    }

    const loadCommand = buildModelCommand("load", modelId);
    const loadCommandPath = path.join(artifactDir, "load_request.json");
    const loadRuntimePath = path.join(runtimeBaseDir, "model_commands", `cmd_${loadCommand.req_id}.json`);
    const loadResultRuntimePath = path.join(runtimeBaseDir, "model_results", `res_${loadCommand.req_id}.json`);
    const loadResultPath = path.join(artifactDir, "load_result.json");
    writeJSON(loadCommandPath, loadCommand);
    writeJSON(loadRuntimePath, loadCommand);
    evidenceRefs.push(relPath(loadCommandPath));
    const loadResult = await waitForJSONFile(loadResultRuntimePath, child, 180_000);
    if (loadResult) {
      writeJSON(loadResultPath, loadResult);
      evidenceRefs.push(relPath(loadResultPath));
    }

    const taskRequest = buildGenerateRequest(modelId);
    const taskRequestPath = path.join(artifactDir, "task_request.json");
    const taskRuntimePath = path.join(runtimeBaseDir, "ai_requests", `req_${taskRequest.req_id}.json`);
    const taskResponseRuntimePath = path.join(runtimeBaseDir, "ai_responses", `resp_${taskRequest.req_id}.jsonl`);
    const taskResponsePath = path.join(artifactDir, "task_response.jsonl");
    const taskOutputPath = path.join(artifactDir, "task_output.json");
    writeJSON(taskRequestPath, taskRequest);
    writeJSON(taskRuntimePath, taskRequest);
    evidenceRefs.push(relPath(taskRequestPath));
    const taskResponse = await waitForAIResponse(taskResponseRuntimePath, child, 240_000);
    if (taskResponse.text) {
      persistText(taskResponsePath, taskResponse.text);
      evidenceRefs.push(relPath(taskResponsePath));
    }
    const taskOutput = summarizeTextTaskResponse(taskResponse.events);
    writeJSON(taskOutputPath, taskOutput);
    evidenceRefs.push(relPath(taskOutputPath));

    const benchCommand = buildModelCommand("bench", modelId);
    const benchCommandPath = path.join(artifactDir, "bench_request.json");
    const benchRuntimePath = path.join(runtimeBaseDir, "model_commands", `cmd_${benchCommand.req_id}.json`);
    const benchResultRuntimePath = path.join(runtimeBaseDir, "model_results", `res_${benchCommand.req_id}.json`);
    const benchResultPath = path.join(artifactDir, "bench_result.json");
    writeJSON(benchCommandPath, benchCommand);
    writeJSON(benchRuntimePath, benchCommand);
    evidenceRefs.push(relPath(benchCommandPath));
    const benchResult = await waitForJSONFile(benchResultRuntimePath, child, 240_000);
    if (benchResult) {
      writeJSON(benchResultPath, benchResult);
      evidenceRefs.push(relPath(benchResultPath));
    }

    const runtimeStatusPath = path.join(artifactDir, "ai_runtime_status.json");
    const modelsBenchPath = path.join(artifactDir, "models_bench.json");
    const modelsStatePath = path.join(artifactDir, "models_state.json");
    copyFileIfExists(path.join(runtimeBaseDir, "ai_runtime_status.json"), runtimeStatusPath);
    copyFileIfExists(path.join(runtimeBaseDir, "models_bench.json"), modelsBenchPath);
    copyFileIfExists(path.join(runtimeBaseDir, "models_state.json"), modelsStatePath);
    if (pathExists(runtimeStatusPath)) evidenceRefs.push(relPath(runtimeStatusPath));
    if (pathExists(modelsBenchPath)) evidenceRefs.push(relPath(modelsBenchPath));
    if (pathExists(modelsStatePath)) evidenceRefs.push(relPath(modelsStatePath));

    return {
      modelId,
      modelPath,
      runtimeBaseDir,
      artifactRefs,
      evidenceRefs,
      loadResult: readJSONIfExists(loadResultPath),
      task: readJSONIfExists(taskOutputPath),
      benchResult: readJSONIfExists(benchResultPath),
      runtimeStatus: readJSONIfExists(runtimeStatusPath),
      modelsBench: readJSONIfExists(modelsBenchPath),
      captureError: readJSONIfExists(captureErrorPath),
    };
  } catch (error) {
    const captureError = {
      error: String(error && error.message ? error.message : error),
      at: isoNow(),
    };
    writeJSON(captureErrorPath, captureError);
    evidenceRefs.push(relPath(captureErrorPath));
    return {
      modelId,
      modelPath,
      runtimeBaseDir,
      artifactRefs,
      evidenceRefs,
      captureError,
    };
  } finally {
    const exitState = await stopRuntime(child, runtimeBaseDir);
    stdoutStream.end();
    stderrStream.end();
    const runtimeProcessMetaPath = path.join(artifactDir, "runtime_process.meta.json");
    writeJSON(runtimeProcessMetaPath, {
      command: [pythonBin, legacyRuntimeEntry],
      pid: child.pid || null,
      exit_code: exitState.exitCode,
      signal: exitState.signal || "",
      exited: exitState.exited === true,
      generated_at: isoNow(),
    });
  }
}

function printUsage(exitCode) {
  const message = [
    "usage:",
    "  node scripts/generate_lpr_w4_09_a_mlx_text_require_real_evidence.js",
    "options:",
    "  --model-path <path>",
    "  --python-bin <path>",
    "  --artifact-dir <path>",
    "  --out <path>",
    "  --skip-run",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function parseArgs(argv) {
  const options = {
    modelPath: "",
    pythonBin: "",
    artifactDir: defaultArtifactDir,
    outputPath: defaultOutputPath,
    skipRun: false,
  };
  for (let i = 2; i < argv.length; i += 1) {
    const token = normalizeString(argv[i]);
    switch (token) {
      case "--model-path":
        options.modelPath = normalizeString(argv[++i]);
        break;
      case "--python-bin":
        options.pythonBin = normalizeString(argv[++i]);
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
  return options;
}

async function main() {
  const options = parseArgs(process.argv);
  ensureDir(options.artifactDir);

  let capture = {};
  if (!options.skipRun) {
    capture = await runCapture(options);
  }

  const modelPath = resolveModelPath(options.modelPath);
  const modelId = modelIdFromPath(modelPath);
  const artifactDir = path.resolve(options.artifactDir);

  const report = buildMLXTextRequireRealReport({
    generatedAt: isoNow(),
    modelId,
    modelPath,
    modelExists: pathExists(modelPath),
    loadResult: readJSONIfExists(path.join(artifactDir, "load_result.json")) || capture.loadResult,
    task: readJSONIfExists(path.join(artifactDir, "task_output.json")) || capture.task,
    benchResult: readJSONIfExists(path.join(artifactDir, "bench_result.json")) || capture.benchResult,
    runtimeStatus:
      readJSONIfExists(path.join(artifactDir, "ai_runtime_status.json")) || capture.runtimeStatus,
    modelsBench: readJSONIfExists(path.join(artifactDir, "models_bench.json")) || capture.modelsBench,
    captureError:
      readJSONIfExists(path.join(artifactDir, "capture_error.json")) || capture.captureError,
    evidenceRefs: uniqueStrings([
      ...normalizeArray(capture.evidenceRefs),
      relPath(path.join(artifactDir, "load_request.json")),
      relPath(path.join(artifactDir, "load_result.json")),
      relPath(path.join(artifactDir, "task_request.json")),
      relPath(path.join(artifactDir, "task_response.jsonl")),
      relPath(path.join(artifactDir, "task_output.json")),
      relPath(path.join(artifactDir, "bench_request.json")),
      relPath(path.join(artifactDir, "bench_result.json")),
      relPath(path.join(artifactDir, "ai_runtime_status.json")),
      relPath(path.join(artifactDir, "models_bench.json")),
      relPath(path.join(artifactDir, "models_state.json")),
      relPath(path.join(artifactDir, "runtime.stdout.log")),
      relPath(path.join(artifactDir, "runtime.stderr.log")),
      relPath(path.join(artifactDir, "runtime_process.meta.json")),
      relPath(path.join(artifactDir, "capture_error.json")),
    ].filter((item) => item && pathExists(path.join(repoRoot, item)))),
  });

  writeJSON(options.outputPath, report);
  process.stdout.write(`${options.outputPath}\n`);
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${String(error && error.message ? error.message : error)}\n`);
    process.exit(1);
  });
}

module.exports = {
  buildMLXTextRequireRealReport,
  summarizeTextTaskResponse,
};
