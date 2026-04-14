#!/usr/bin/env node
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const cp = require("node:child_process");

const {
  repoRoot,
  resolveReportsDir,
  writeJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");
const {
  chooseReadyRuntime,
  pathExists,
} = require("./generate_lpr_w3_03_c_model_native_loadability_probe.js");

const reportsDir = resolveReportsDir();
const defaultOutDir = path.join(reportsDir, "lpr_w4_07_c_real_run");
const localRuntimeEntry = path.join(
  repoRoot,
  "x-hub",
  "python-runtime",
  "python_service",
  "relflowhub_local_runtime.py"
);
const defaultHelperBinaryPath = path.join(os.homedir(), ".lmstudio", "bin", "lms");
const benchFixturePackSource = path.join(
  repoRoot,
  "x-hub",
  "macos",
  "RELFlowHub",
  "Sources",
  "RELFlowHub",
  "Resources",
  "BenchFixtures",
  "bench_fixture_pack.v1.json"
);
const defaultModelCandidates = [
  path.join(os.homedir(), ".lmstudio", "models", "mlx-community", "Qwen3-VL-4B-Instruct-3bit"),
  path.join(os.homedir(), ".lmstudio", "models", "mlx-community", "GLM-4.6V-Flash-MLX-4bit"),
  "/Users/andrew.xie/Documents/AX/Local Model/GLM-4.6V-Flash-MLX-4bit",
  "/Users/andrew.xie/Documents/AX/Local Model/Qwen3-VL-30B-A3B-Instruct-MLX-4bit",
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

function dedupeStrings(values) {
  const seen = new Set();
  const out = [];
  for (const value of values || []) {
    const normalized = normalizeString(value);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    out.push(normalized);
  }
  return out;
}

function relPath(targetPath) {
  const normalized = normalizeString(targetPath);
  if (!normalized) return "";
  if (!path.isAbsolute(normalized)) return normalized.split(path.sep).join("/");
  return path.relative(repoRoot, normalized).split(path.sep).join("/");
}

function safeMkdir(targetPath) {
  fs.mkdirSync(targetPath, { recursive: true });
}

function readJSONIfExists(filePath) {
  try {
    if (!filePath || !fs.existsSync(filePath)) return null;
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function resolveRequestedModelPath(explicitPath) {
  const normalizedExplicit = normalizeString(explicitPath);
  if (normalizedExplicit) return path.resolve(normalizedExplicit);
  const discovered = defaultModelCandidates.find((candidate) => pathExists(candidate));
  return path.resolve(discovered || defaultModelCandidates[0]);
}

function resolvePythonRuntime(explicitPath) {
  const normalizedExplicit = normalizeString(explicitPath);
  if (normalizedExplicit) {
    return {
      runtime_id: "override_python",
      label: "Override Python runtime",
      command: path.resolve(normalizedExplicit),
      env: {},
    };
  }
  const selection = chooseReadyRuntime();
  if (selection.best && selection.best.candidate) {
    return selection.best.candidate;
  }
  throw new Error("no_ready_python_runtime_for_mlx_vlm_real_capture");
}

function runCommand(command, args, options = {}) {
  const result = {
    command: [command, ...(args || [])],
    cwd: options.cwd || repoRoot,
    timeout_ms: Number.isFinite(options.timeoutMs) ? options.timeoutMs : 60_000,
    started_at: isoNow(),
  };
  try {
    const execResult = cp.spawnSync(command, args || [], {
      cwd: result.cwd,
      env: options.env || process.env,
      input: options.input || undefined,
      encoding: "utf8",
      timeout: result.timeout_ms,
      maxBuffer: 32 * 1024 * 1024,
    });
    result.exit_code = typeof execResult.status === "number" ? execResult.status : null;
    result.signal = execResult.signal || "";
    result.stdout = execResult.stdout || "";
    result.stderr = execResult.stderr || "";
    result.timed_out = !!execResult.error && execResult.error.code === "ETIMEDOUT";
    result.error = execResult.error ? String(execResult.error.message || execResult.error) : "";
    result.ok = result.exit_code === 0 && !result.timed_out;
  } catch (error) {
    result.exit_code = null;
    result.signal = "";
    result.stdout = "";
    result.stderr = "";
    result.timed_out = false;
    result.error = String(error && error.message ? error.message : error);
    result.ok = false;
  }
  result.finished_at = isoNow();
  return result;
}

function persistCommandArtifacts(dirPath, prefix, result) {
  safeMkdir(dirPath);
  const stdoutPath = path.join(dirPath, `${prefix}.stdout.log`);
  const stderrPath = path.join(dirPath, `${prefix}.stderr.log`);
  const metaPath = path.join(dirPath, `${prefix}.meta.json`);
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
    timed_out: result.timed_out,
    ok: result.ok,
    error: result.error,
  });
  return {
    meta: relPath(metaPath),
    stdout: relPath(stdoutPath),
    stderr: relPath(stderrPath),
  };
}

function parseJSONText(text) {
  const raw = String(text || "").trim();
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function buildModelCatalog(modelId, modelPath) {
  return {
    models: [
      {
        id: modelId,
        name: path.basename(modelPath),
        backend: "mlx",
        runtimeProviderID: "mlx_vlm",
        modelPath,
        taskKinds: ["vision_understand", "ocr"],
        default_load_config: {
          identifier: "mlx-vlm-require-real",
          ttl: 600,
          parallel: 1,
          context_length: 4096,
          vision: {
            image_max_dimension: 2048,
          },
        },
        maxContextLength: 65536,
      },
    ],
  };
}

function buildProviderPackRegistry(helperBinaryPath) {
  return {
    schemaVersion: "xhub.provider_pack_registry.v1",
    updatedAt: Date.now() / 1000,
    packs: [
      {
        providerId: "mlx_vlm",
        runtimeRequirements: {
          executionMode: "helper_binary_bridge",
          helperBinary: helperBinaryPath,
        },
      },
    ],
  };
}

function buildImageFixtureSpec() {
  return {
    schema_version: "xhub.lpr_w4_07_c_real_input_fixture_spec.v1",
    generated_at: isoNow(),
    fixtures: [
      {
        id: "vision_scene",
        path: "vision_scene.png",
        width: 1280,
        height: 768,
        text: [
          "X-Hub local vision check",
          "Desktop layout with sidebar, list, and action panel",
          "Observe the visible headings and summarize the scene",
        ],
      },
      {
        id: "ocr_page",
        path: "ocr_page.png",
        width: 1400,
        height: 1800,
        text: [
          "Invoice 2026-03-26",
          "Customer: X-Hub QA",
          "Item A  2 x  19.00",
          "Item B  1 x 149.00",
          "Total 187.00 USD",
        ],
      },
    ],
  };
}

function generateInputImages(baseDir, pythonRuntime) {
  const fixtureSpec = buildImageFixtureSpec();
  const fixtureSpecPath = path.join(baseDir, "input_fixture_spec.json");
  writeJSON(fixtureSpecPath, fixtureSpec);
  const script = [
    "import json, os, sys",
    "from PIL import Image, ImageDraw, ImageFont",
    "spec_path = sys.argv[1]",
    "base_dir = sys.argv[2]",
    "with open(spec_path, 'r', encoding='utf-8') as handle:",
    "    spec = json.load(handle)",
    "font = ImageFont.load_default()",
    "for fixture in spec.get('fixtures', []):",
    "    width = int(fixture.get('width') or 800)",
    "    height = int(fixture.get('height') or 600)",
    "    image = Image.new('RGB', (width, height), color=(248, 249, 251))",
    "    draw = ImageDraw.Draw(image)",
    "    draw.rectangle((48, 48, width - 48, 150), outline=(40, 52, 73), width=4, fill=(230, 236, 245))",
    "    draw.rectangle((48, 190, 330, height - 60), outline=(78, 100, 128), width=3, fill=(238, 242, 247))",
    "    draw.rectangle((370, 190, width - 60, height - 60), outline=(78, 100, 128), width=3, fill=(255, 255, 255))",
    "    y = 76",
    "    for line in fixture.get('text', []):",
    "        draw.text((84, y), str(line), fill=(12, 24, 48), font=font)",
    "        y += 44",
    "    if fixture.get('id') == 'ocr_page':",
    "        draw.line((420, 360, width - 100, 360), fill=(20, 20, 20), width=2)",
    "        draw.line((420, 720, width - 100, 720), fill=(20, 20, 20), width=2)",
    "    out_path = os.path.join(base_dir, str(fixture.get('path')))",
    "    image.save(out_path, format='PNG')",
    "print(json.dumps({'ok': True, 'count': len(spec.get('fixtures', []))}, ensure_ascii=False))",
  ].join("\n");
  const commandResult = runCommand(pythonRuntime.command, ["-c", script, fixtureSpecPath, baseDir], {
    env: {
      ...process.env,
      ...normalizeObject(pythonRuntime.env),
      PYTHONUNBUFFERED: "1",
    },
    timeoutMs: 60_000,
  });
  const parsed = parseJSONText(commandResult.stdout);
  if (!(commandResult.ok && parsed && parsed.ok === true)) {
    throw new Error(`image_fixture_generation_failed:${commandResult.error || commandResult.stderr || commandResult.stdout}`);
  }
  return {
    fixtureSpecPath,
    visionImagePath: path.join(baseDir, "vision_scene.png"),
    ocrImagePath: path.join(baseDir, "ocr_page.png"),
    commandResult,
  };
}

function buildRuntimeEnv(baseDir, pythonRuntime) {
  return {
    ...process.env,
    ...normalizeObject(pythonRuntime.env),
    REL_FLOW_HUB_BASE_DIR: baseDir,
    PYTHONUNBUFFERED: "1",
    TRANSFORMERS_OFFLINE: "1",
    HF_HUB_OFFLINE: "1",
  };
}

function runLocalRuntimeJSON(pythonRuntime, baseDir, subcommand, request, timeoutMs) {
  const args = [localRuntimeEntry, subcommand];
  if (request !== undefined && request !== null) {
    args.push("-");
  }
  const result = runCommand(pythonRuntime.command, args, {
    env: buildRuntimeEnv(baseDir, pythonRuntime),
    input: request !== undefined && request !== null ? JSON.stringify(request) : undefined,
    timeoutMs,
  });
  return {
    raw: result,
    json: parseJSONText(result.stdout),
  };
}

function deriveRealRuntimeTouched(result) {
  const normalized = normalizeObject(result);
  const routeTrace = normalizeObject(normalized.routeTrace);
  const executionPath = normalizeString(routeTrace.executionPath).toLowerCase();
  const deviceBackend = normalizeString(normalized.deviceBackend).toLowerCase();
  const runtimeSource = normalizeString(normalized.runtimeSource).toLowerCase();
  return (
    executionPath === "helper_bridge" ||
    executionPath === "real_runtime" ||
    deviceBackend === "helper_binary_bridge" ||
    runtimeSource === "helper_binary_bridge"
  );
}

function normalizeTaskCapture(result) {
  const normalized = normalizeObject(result);
  return {
    ...normalized,
    real_runtime_touched: deriveRealRuntimeTouched(normalized),
  };
}

function buildMLXVLMRealCaptureBundle(input = {}) {
  const topLevelTask = normalizeTaskCapture(input.task);
  const ocrTask = normalizeTaskCapture(input.ocrTask);
  return {
    schema_version: "xhub.lpr_w4_07_c_real_run_capture_bundle.v1",
    generated_at: normalizeString(input.generatedAt, isoNow()),
    performed_at: normalizeString(input.performedAt, isoNow()),
    provider: "mlx_vlm",
    task_kind: normalizeString(input.taskKind, "vision_understand"),
    model_id: normalizeString(input.modelId),
    model_path: normalizeString(input.modelPath),
    helper_binary_path: normalizeString(input.helperBinaryPath),
    python_runtime: {
      runtime_id: normalizeString(input.pythonRuntime && input.pythonRuntime.runtime_id),
      label: normalizeString(input.pythonRuntime && input.pythonRuntime.label),
      command: normalizeString(input.pythonRuntime && input.pythonRuntime.command),
      env_overrides: normalizeObject(input.pythonRuntime && input.pythonRuntime.env),
    },
    warmup: normalizeObject(input.warmup),
    task: topLevelTask,
    ocr_task: ocrTask,
    bench: normalizeObject(input.bench),
    monitor: normalizeObject(input.monitor),
    helper_probe: normalizeObject(input.helperProbe),
    command_refs: dedupeStrings(input.commandRefs || []),
    evidence_refs: dedupeStrings(input.evidenceRefs || []),
  };
}

function printUsage(exitCode) {
  const message = [
    "usage:",
    "  node scripts/generate_lpr_w4_07_c_real_run_capture.js",
    "options:",
    "  --model-path <path>",
    "  --python-bin <path>",
    "  --helper-bin <path>",
    "  --out-dir <path>",
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
    helperBin: defaultHelperBinaryPath,
    outDir: defaultOutDir,
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
      case "--helper-bin":
        options.helperBin = normalizeString(argv[++i]);
        break;
      case "--out-dir":
        options.outDir = path.resolve(normalizeString(argv[++i]));
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

function main() {
  const options = parseArgs(process.argv);
  const performedAt = isoNow();
  const modelPath = resolveRequestedModelPath(options.modelPath);
  const helperBinaryPath = path.resolve(normalizeString(options.helperBin, defaultHelperBinaryPath));
  if (!pathExists(modelPath)) {
    throw new Error(`model_path_not_found:${modelPath}`);
  }
  if (!pathExists(helperBinaryPath)) {
    throw new Error(`helper_binary_not_found:${helperBinaryPath}`);
  }
  if (!pathExists(localRuntimeEntry)) {
    throw new Error(`local_runtime_entry_missing:${localRuntimeEntry}`);
  }
  if (!pathExists(benchFixturePackSource)) {
    throw new Error(`bench_fixture_pack_missing:${benchFixturePackSource}`);
  }

  const pythonRuntime = resolvePythonRuntime(options.pythonBin);
  const outDir = path.resolve(options.outDir);
  const runtimeBaseDir = path.join(outDir, "runtime_base_dir");
  const modelId = "qwen3-vl-helper-real";
  fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
  safeMkdir(runtimeBaseDir);
  safeMkdir(outDir);

  const modelsCatalogPath = path.join(runtimeBaseDir, "models_catalog.json");
  const providerPackRegistryPath = path.join(runtimeBaseDir, "provider_pack_registry.json");
  const benchFixturePackPath = path.join(outDir, "bench_fixture_pack.v1.json");
  writeJSON(modelsCatalogPath, buildModelCatalog(modelId, modelPath));
  writeJSON(providerPackRegistryPath, buildProviderPackRegistry(helperBinaryPath));
  fs.copyFileSync(benchFixturePackSource, benchFixturePackPath);

  const inputImages = generateInputImages(outDir, pythonRuntime);
  const imageArtifacts = persistCommandArtifacts(outDir, "generate_input_images", inputImages.commandResult);

  const warmupRequestPath = path.join(outDir, "warmup_request.json");
  const visionTaskRequestPath = path.join(outDir, "vision_task_request.json");
  const ocrTaskRequestPath = path.join(outDir, "ocr_task_request.json");
  const benchRequestPath = path.join(outDir, "bench_request.json");

  const warmupRequest = {
    action: "warmup_local_model",
    provider: "mlx_vlm",
    model_id: modelId,
    allow_daemon_proxy: false,
  };
  const visionTaskRequest = {
    provider: "mlx_vlm",
    model_id: modelId,
    task_kind: "vision_understand",
    allow_daemon_proxy: false,
    multimodal_messages: [
      {
        role: "user",
        content: [
          {
            type: "text",
            text: "Summarize the visible layout and any readable heading text.",
          },
          {
            type: "image",
            image_path: inputImages.visionImagePath,
          },
        ],
      },
    ],
  };
  const ocrTaskRequest = {
    provider: "mlx_vlm",
    model_id: modelId,
    task_kind: "ocr",
    allow_daemon_proxy: false,
    input: {
      image_path: inputImages.ocrImagePath,
    },
    options: {
      language: "en",
    },
  };
  const benchRequest = {
    provider: "mlx_vlm",
    model_id: modelId,
    task_kind: "vision_understand",
    fixture_profile: "vision_single_image",
    fixture_pack_path: benchFixturePackPath,
    allow_bench_fallback: false,
    allow_daemon_proxy: false,
  };

  writeJSON(warmupRequestPath, warmupRequest);
  writeJSON(visionTaskRequestPath, visionTaskRequest);
  writeJSON(ocrTaskRequestPath, ocrTaskRequest);
  writeJSON(benchRequestPath, benchRequest);

  const warmup = runLocalRuntimeJSON(pythonRuntime, runtimeBaseDir, "manage-local-model", warmupRequest, 600_000);
  const warmupArtifacts = persistCommandArtifacts(outDir, "warmup_local_runtime", warmup.raw);
  if (!(warmup.raw.ok && warmup.json && warmup.json.ok === true)) {
    throw new Error(`mlx_vlm_warmup_failed:${warmup.raw.error || warmup.raw.stderr || warmup.raw.stdout}`);
  }
  const warmupOutputPath = path.join(outDir, "warmup_output.json");
  writeJSON(warmupOutputPath, warmup.json);

  const visionTask = runLocalRuntimeJSON(pythonRuntime, runtimeBaseDir, "run-local-task", visionTaskRequest, 600_000);
  const visionTaskArtifacts = persistCommandArtifacts(outDir, "vision_task_local_runtime", visionTask.raw);
  if (!(visionTask.raw.ok && visionTask.json && visionTask.json.ok === true)) {
    throw new Error(`mlx_vlm_vision_task_failed:${visionTask.raw.error || visionTask.raw.stderr || visionTask.raw.stdout}`);
  }
  const visionTaskOutputPath = path.join(outDir, "vision_task_output.json");
  writeJSON(visionTaskOutputPath, visionTask.json);

  const ocrTask = runLocalRuntimeJSON(pythonRuntime, runtimeBaseDir, "run-local-task", ocrTaskRequest, 600_000);
  const ocrTaskArtifacts = persistCommandArtifacts(outDir, "ocr_task_local_runtime", ocrTask.raw);
  if (!(ocrTask.raw.ok && ocrTask.json && ocrTask.json.ok === true)) {
    throw new Error(`mlx_vlm_ocr_task_failed:${ocrTask.raw.error || ocrTask.raw.stderr || ocrTask.raw.stdout}`);
  }
  const ocrTaskOutputPath = path.join(outDir, "ocr_task_output.json");
  writeJSON(ocrTaskOutputPath, ocrTask.json);

  const bench = runLocalRuntimeJSON(pythonRuntime, runtimeBaseDir, "run-local-bench", benchRequest, 600_000);
  const benchArtifacts = persistCommandArtifacts(outDir, "bench_local_runtime", bench.raw);
  if (!(bench.raw.ok && bench.json && bench.json.ok === true)) {
    throw new Error(`mlx_vlm_bench_failed:${bench.raw.error || bench.raw.stderr || bench.raw.stdout}`);
  }
  const benchOutputPath = path.join(outDir, "bench_output.json");
  writeJSON(benchOutputPath, bench.json);

  const runtimeStatus = runLocalRuntimeJSON(pythonRuntime, runtimeBaseDir, "status", null, 30_000);
  const runtimeStatusArtifacts = persistCommandArtifacts(outDir, "runtime_status", runtimeStatus.raw);
  if (!(runtimeStatus.raw.ok && runtimeStatus.json && runtimeStatus.json.providers)) {
    throw new Error(`runtime_status_capture_failed:${runtimeStatus.raw.error || runtimeStatus.raw.stderr || runtimeStatus.raw.stdout}`);
  }
  const runtimeStatusPath = path.join(outDir, "ai_runtime_status.json");
  writeJSON(runtimeStatusPath, runtimeStatus.json);

  const helperDaemonResult = runCommand(helperBinaryPath, ["daemon", "status", "--json"], { timeoutMs: 15_000 });
  const helperServerResult = runCommand(helperBinaryPath, ["server", "status", "--json"], { timeoutMs: 15_000 });
  const helperPSResult = runCommand(helperBinaryPath, ["ps", "--json"], { timeoutMs: 15_000 });
  const helperModelsResult = runCommand("curl", ["-fsS", "http://127.0.0.1:1234/v1/models"], { timeoutMs: 15_000 });
  const helperDaemonArtifacts = persistCommandArtifacts(outDir, "helper_daemon_status", helperDaemonResult);
  const helperServerArtifacts = persistCommandArtifacts(outDir, "helper_server_status", helperServerResult);
  const helperPSArtifacts = persistCommandArtifacts(outDir, "lms_ps_final", helperPSResult);
  const helperModelsArtifacts = persistCommandArtifacts(outDir, "helper_http_models", helperModelsResult);

  const helperDaemonJSON = parseJSONText(helperDaemonResult.stdout);
  const helperServerJSON = parseJSONText(helperServerResult.stdout);
  const helperPSJSON = parseJSONText(helperPSResult.stdout);
  const helperModelsJSON = parseJSONText(helperModelsResult.stdout);
  if (helperPSJSON) {
    writeJSON(path.join(outDir, "lms_ps_final.json"), helperPSJSON);
  }
  if (helperModelsJSON) {
    writeJSON(path.join(outDir, "helper_http_models.json"), helperModelsJSON);
  }

  const providerStatus = normalizeObject(normalizeObject(runtimeStatus.json.providers).mlx_vlm);
  const monitorSnapshot = normalizeObject(runtimeStatus.json.monitorSnapshot);
  const recentBenchResults = normalizeArray(runtimeStatus.json.recentBenchResults);
  const monitor = {
    snapshot_captured: Object.keys(providerStatus).length > 0,
    provider_status: providerStatus,
    loaded_instance_count: normalizeArray(providerStatus.loadedInstances).length,
    loaded_instances: normalizeArray(providerStatus.loadedInstances),
    recent_bench_results: recentBenchResults,
    runtime_status_ref: relPath(runtimeStatusPath),
    lms_ps_ref: relPath(path.join(outDir, "lms_ps_final.json")),
    helper_http_models_ref: relPath(path.join(outDir, "helper_http_models.json")),
    monitor_snapshot: monitorSnapshot,
  };

  const evidenceRefs = dedupeStrings([
    relPath(modelsCatalogPath),
    relPath(providerPackRegistryPath),
    relPath(benchFixturePackPath),
    relPath(inputImages.fixtureSpecPath),
    relPath(inputImages.visionImagePath),
    relPath(inputImages.ocrImagePath),
    relPath(warmupRequestPath),
    relPath(visionTaskRequestPath),
    relPath(ocrTaskRequestPath),
    relPath(benchRequestPath),
    relPath(warmupOutputPath),
    relPath(visionTaskOutputPath),
    relPath(ocrTaskOutputPath),
    relPath(benchOutputPath),
    relPath(runtimeStatusPath),
    relPath(path.join(outDir, "lms_ps_final.json")),
    relPath(path.join(outDir, "helper_http_models.json")),
    imageArtifacts.meta,
    imageArtifacts.stdout,
    imageArtifacts.stderr,
    warmupArtifacts.meta,
    warmupArtifacts.stdout,
    warmupArtifacts.stderr,
    visionTaskArtifacts.meta,
    visionTaskArtifacts.stdout,
    visionTaskArtifacts.stderr,
    ocrTaskArtifacts.meta,
    ocrTaskArtifacts.stdout,
    ocrTaskArtifacts.stderr,
    benchArtifacts.meta,
    benchArtifacts.stdout,
    benchArtifacts.stderr,
    runtimeStatusArtifacts.meta,
    runtimeStatusArtifacts.stdout,
    runtimeStatusArtifacts.stderr,
    helperDaemonArtifacts.meta,
    helperDaemonArtifacts.stdout,
    helperDaemonArtifacts.stderr,
    helperServerArtifacts.meta,
    helperServerArtifacts.stdout,
    helperServerArtifacts.stderr,
    helperPSArtifacts.meta,
    helperPSArtifacts.stdout,
    helperPSArtifacts.stderr,
    helperModelsArtifacts.meta,
    helperModelsArtifacts.stdout,
    helperModelsArtifacts.stderr,
  ]);

  const captureBundle = buildMLXVLMRealCaptureBundle({
    generatedAt: isoNow(),
    performedAt,
    modelId,
    modelPath,
    taskKind: "vision_understand",
    helperBinaryPath,
    pythonRuntime,
    warmup: warmup.json,
    task: visionTask.json,
    ocrTask: ocrTask.json,
    bench: bench.json,
    monitor,
    helperProbe: {
      daemon_status: helperDaemonJSON,
      server_status: helperServerJSON,
      loaded_rows: helperPSJSON,
      http_models: helperModelsJSON,
    },
    evidenceRefs,
    commandRefs: [
      `node scripts/generate_lpr_w4_07_c_real_run_capture.js --model-path '${modelPath}'`,
      `${normalizeString(pythonRuntime.command)} ${relPath(localRuntimeEntry)} manage-local-model -`,
      `${normalizeString(pythonRuntime.command)} ${relPath(localRuntimeEntry)} run-local-task -`,
      `${normalizeString(pythonRuntime.command)} ${relPath(localRuntimeEntry)} run-local-bench -`,
      `${helperBinaryPath} ps --json`,
      "curl -fsS http://127.0.0.1:1234/v1/models",
    ],
  });

  const captureBundlePath = path.join(outDir, "capture_bundle.json");
  writeJSON(captureBundlePath, captureBundle);
  process.stdout.write(`${captureBundlePath}\n`);
}

module.exports = {
  buildMLXVLMRealCaptureBundle,
  buildModelCatalog,
  buildProviderPackRegistry,
  deriveRealRuntimeTouched,
  normalizeTaskCapture,
  parseArgs,
  resolvePythonRuntime,
  resolveRequestedModelPath,
};

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${String(error && error.message ? error.message : error)}\n`);
    process.exit(1);
  }
}
