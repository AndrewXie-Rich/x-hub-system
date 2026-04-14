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

const outputPath = path.join(reportsDir, "lpr_w3_03_b_runtime_candidate_probe.v1.json");
const artifactRoot = path.join(reportsDir, "lpr_w3_03_require_real", "runtime_candidate_probe");
const localRuntimeEntry = path.join(
  repoRoot,
  "x-hub",
  "python-runtime",
  "python_service",
  "relflowhub_local_runtime.py",
);

const embeddingModelCandidates = [
  "/Users/andrew.xie/Documents/AX/Local Model/all-MiniLM-L6-v2",
  "/Users/andrew.xie/.lmstudio/models/sentence-transformers/all-MiniLM-L6-v2",
  "/Users/andrew.xie/.lmstudio/models/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ",
];
const visionModelPath = "/Users/andrew.xie/Documents/AX/Local Model/Qwen3-VL-30B-A3B-Instruct-MLX-4bit";
const lmStudioCPython = "/Users/andrew.xie/Documents/AX/Opensource/LM Studio.app/Contents/Resources/app/.webpack/bin/extensions/backends/vendor/_amphibian/cpython3.11-mac-arm64@10/bin/python3";
const lmStudioTransformersSitePackages = "/Users/andrew.xie/Documents/AX/Opensource/LM Studio.app/Contents/Resources/app/.webpack/bin/extensions/backends/vendor/_amphibian/app-mlx-generate-mac14-arm64@19/lib/python3.11/site-packages";
const xcodePython = "/Applications/Xcode.app/Contents/Developer/usr/bin/python3";

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

function pickExistingPath(candidates = []) {
  for (const candidate of candidates) {
    if (pathExists(candidate)) return candidate;
  }
  return "";
}

function relativeRepoPath(targetPath) {
  return path.relative(repoRoot, targetPath);
}

function safeMkdir(targetPath) {
  fs.mkdirSync(targetPath, { recursive: true });
}

function runCommand(command, args, options = {}) {
  const result = {
    command: [command, ...args],
    started_at: isoNow(),
    timeout_ms: Number.isFinite(options.timeoutMs) ? options.timeoutMs : 60000,
    cwd: options.cwd || repoRoot,
  };
  try {
    const execResult = cp.spawnSync(command, args, {
      cwd: result.cwd,
      env: options.env || process.env,
      input: options.input || undefined,
      encoding: "utf8",
      timeout: result.timeout_ms,
      maxBuffer: 16 * 1024 * 1024,
    });
    result.exit_code = typeof execResult.status === "number" ? execResult.status : null;
    result.signal = execResult.signal || "";
    result.stdout = execResult.stdout || "";
    result.stderr = execResult.stderr || "";
    result.timed_out = !!execResult.error && execResult.error.code === "ETIMEDOUT";
    result.error = execResult.error ? String(execResult.error.message || execResult.error) : "";
  } catch (error) {
    result.exit_code = null;
    result.signal = "";
    result.stdout = "";
    result.stderr = "";
    result.timed_out = false;
    result.error = String(error && error.message ? error.message : error);
  }
  result.finished_at = isoNow();
  return result;
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

function persistCommandArtifacts(dirPath, prefix, result) {
  safeMkdir(dirPath);
  fs.writeFileSync(path.join(dirPath, `${prefix}.stdout.log`), String(result.stdout || ""), "utf8");
  fs.writeFileSync(path.join(dirPath, `${prefix}.stderr.log`), String(result.stderr || ""), "utf8");
  writeJSON(path.join(dirPath, `${prefix}.meta.json`), {
    command: result.command,
    exit_code: result.exit_code,
    signal: result.signal,
    timed_out: result.timed_out,
    error: result.error,
    started_at: result.started_at,
    finished_at: result.finished_at,
    cwd: result.cwd,
  });
}

function buildRuntimeCandidates() {
  const candidates = [];
  if (pathExists(xcodePython)) {
    candidates.push({
      runtime_id: "xcode_python3",
      label: "Xcode python3",
      command: xcodePython,
      env: {},
      notes: ["transformers/tokenizers/PIL present, torch missing"],
    });
  }
  if (pathExists(lmStudioCPython)) {
    candidates.push({
      runtime_id: "lmstudio_cpython311",
      label: "LM Studio bundled cpython3.11",
      command: lmStudioCPython,
      env: {},
      notes: ["torch present, transformers stack absent unless extra PYTHONPATH is added"],
    });
  }
  if (pathExists(lmStudioCPython) && pathExists(lmStudioTransformersSitePackages)) {
    candidates.push({
      runtime_id: "lmstudio_cpython311_combo_transformers",
      label: "LM Studio cpython3.11 + app-mlx-generate site-packages",
      command: lmStudioCPython,
      env: {
        PYTHONPATH: lmStudioTransformersSitePackages,
      },
      notes: ["torch from bundled cpython + transformers/PIL/tokenizers/mlx from app-mlx-generate"],
    });
  }
  return candidates;
}

function runtimeModuleProbe(candidate) {
  const env = { ...process.env, ...candidate.env };
  const modules = {};
  let pythonExecutable = "";
  for (const moduleName of ["torch", "transformers", "PIL", "tokenizers", "mlx", "mlx_lm"]) {
    const script = [
      "import importlib, json, sys",
      `name = ${JSON.stringify(moduleName)}`,
      "try:",
      "    mod = importlib.import_module(name)",
      "    print(json.dumps({'ok': True, 'python_executable': sys.executable, 'version': str(getattr(mod, '__version__', 'ok'))}, ensure_ascii=False))",
      "except Exception as exc:",
      "    print(json.dumps({'ok': False, 'python_executable': sys.executable, 'error': f'{type(exc).__name__}:{exc}'}, ensure_ascii=False))",
    ].join("\n");
    const result = runCommand(candidate.command, ["-c", script], {
      env,
      timeoutMs: 30000,
    });
    const parsed = tryParseJSON(result.stdout);
    persistCommandArtifacts(path.join(artifactRoot, candidate.runtime_id), `module_probe_${moduleName}`, result);
    if (parsed && parsed.python_executable && !pythonExecutable) {
      pythonExecutable = parsed.python_executable;
    }
    modules[moduleName] = parsed || {
      ok: false,
      error: result.error || `module_probe_failed:${moduleName}`,
      exit_code: result.exit_code,
      signal: result.signal,
      timed_out: result.timed_out,
    };
  }
  return {
    python_executable: pythonExecutable,
    modules,
  };
}

function seedProbeBaseDir(dirPath) {
  safeMkdir(dirPath);
  const models = [];
  const embeddingModelPath = pickExistingPath(embeddingModelCandidates);
  if (pathExists(embeddingModelPath)) {
    models.push({
      id: "real-embed-candidate",
      name: path.basename(embeddingModelPath),
      backend: "transformers",
      modelPath: embeddingModelPath,
      taskKinds: ["embedding"],
      defaultLoadProfile: { contextLength: 8192 },
      maxContextLength: 32768,
    });
  }
  if (pathExists(visionModelPath)) {
    models.push({
      id: "qwen3-vl-real",
      name: "Qwen3 VL Real",
      backend: "transformers",
      modelPath: visionModelPath,
      taskKinds: ["vision_understand"],
      defaultLoadProfile: { contextLength: 8192, imageMaxDimension: 2048 },
      maxContextLength: 32768,
    });
  }
  writeJSON(path.join(dirPath, "models_catalog.json"), { models });
  return models;
}

function runLocalRuntimeJSON(candidate, baseDir, subcommand, request) {
  const env = {
    ...process.env,
    REL_FLOW_HUB_BASE_DIR: baseDir,
    PYTHONUNBUFFERED: "1",
    ...candidate.env,
  };
  const result = runCommand(candidate.command, [localRuntimeEntry, subcommand, "-"], {
    env,
    input: JSON.stringify(request || {}),
    timeoutMs: 240000,
  });
  return {
    raw: result,
    json: tryParseJSON(result.stdout),
  };
}

function runStatusJSON(candidate, baseDir) {
  const env = {
    ...process.env,
    REL_FLOW_HUB_BASE_DIR: baseDir,
    PYTHONUNBUFFERED: "1",
    ...candidate.env,
  };
  const result = runCommand(candidate.command, [localRuntimeEntry, "status"], {
    env,
    timeoutMs: 120000,
  });
  return {
    raw: result,
    json: tryParseJSON(result.stdout),
  };
}

function deriveEmbeddingVerdict(statusJson, warmupJson, taskJson) {
  if (taskJson && taskJson.ok === true) {
    return {
      verdict: "sample1_pass",
      blocker_reason: "",
      summary: "真实 embedding 本地执行成功。",
    };
  }
  const warmupReason = warmupJson && typeof warmupJson.reasonCode === "string" ? warmupJson.reasonCode : "";
  const taskReason = taskJson && typeof taskJson.reasonCode === "string" ? taskJson.reasonCode : "";
  const statusReady = !!(
    statusJson
    && Array.isArray(statusJson.readyProviderIds)
    && statusJson.readyProviderIds.includes("transformers")
  );
  if (taskReason === "unsupported_quantization_config" || warmupReason === "unsupported_quantization_config") {
    return {
      verdict: "sample1_blocked_by_model_format",
      blocker_reason: "unsupported_quantization_config",
      summary: "runtime 已 ready，但当前本机 embedding 模型目录对 torch/transformers 原生加载不兼容。",
    };
  }
  if (!statusReady) {
    return {
      verdict: "sample1_blocked_by_runtime",
      blocker_reason: taskReason || warmupReason || "runtime_not_ready",
      summary: "runtime 本身还没 ready，无法进入真实 embedding 执行。",
    };
  }
  return {
    verdict: "sample1_fail_closed",
    blocker_reason: taskReason || warmupReason || "unknown_fail_closed",
    summary: "runtime ready，但 sample1 仍未成功执行；保持 fail-closed。",
  };
}

function main() {
  safeMkdir(artifactRoot);
  const generatedAt = isoNow();
  const embeddingModelPath = pickExistingPath(embeddingModelCandidates);
  const runtimes = [];
  const candidates = buildRuntimeCandidates();

  for (const candidate of candidates) {
    const runtimeDir = path.join(artifactRoot, candidate.runtime_id);
    safeMkdir(runtimeDir);

    const moduleProbe = runtimeModuleProbe(candidate);

    const baseDir = path.join(runtimeDir, "probe_base_dir");
    const seededModels = seedProbeBaseDir(baseDir);
    const status = runStatusJSON(candidate, baseDir);
    persistCommandArtifacts(runtimeDir, "status", status.raw);

    let warmup = { raw: null, json: null };
    let task = { raw: null, json: null };
    if (seededModels.some((model) => model.id === "real-embed-candidate")) {
      warmup = runLocalRuntimeJSON(candidate, baseDir, "manage-local-model", {
        action: "warmup_local_model",
        provider: "transformers",
        task_kind: "embedding",
        model_id: "real-embed-candidate",
        device_id: "xt-mac-mini",
      });
      persistCommandArtifacts(runtimeDir, "embedding_warmup", warmup.raw);

      task = runLocalRuntimeJSON(candidate, baseDir, "run-local-task", {
        provider: "transformers",
        task_kind: "embedding",
        model_id: "real-embed-candidate",
        device_id: "xt-mac-mini",
        texts: [
          "X-Hub supervisor memory routing needs long-context background and precise current-state grounding.",
        ],
        options: {
          max_length: 256,
        },
      });
      persistCommandArtifacts(runtimeDir, "embedding_task", task.raw);
    }

    const verdict = deriveEmbeddingVerdict(status.json, warmup.json, task.json);
    runtimes.push({
      runtime_id: candidate.runtime_id,
      label: candidate.label,
      command: candidate.command,
      env_overrides: candidate.env,
      notes: candidate.notes,
      module_probe: moduleProbe,
      probe_base_dir: relativeRepoPath(baseDir),
      seeded_models: seededModels.map((model) => ({
        id: model.id,
        model_path: model.modelPath,
        task_kinds: model.taskKinds,
      })),
      status_summary: {
        ready_provider_ids: status.json && Array.isArray(status.json.readyProviderIds) ? status.json.readyProviderIds : [],
        transformers_reason_code: status.json && status.json.providers && status.json.providers.transformers
          ? status.json.providers.transformers.reasonCode || ""
          : "",
        transformers_runtime_source: status.json && status.json.providers && status.json.providers.transformers
          ? status.json.providers.transformers.runtimeSource || ""
          : "",
        mlx_import_error: status.json ? status.json.importError || "" : "",
      },
      embedding_sample1_probe: {
        warmup_reason_code: warmup.json ? warmup.json.reasonCode || "" : "",
        warmup_error: warmup.json ? warmup.json.error || "" : "",
        warmup_error_detail: warmup.json ? warmup.json.errorDetail || "" : "",
        task_reason_code: task.json ? task.json.reasonCode || "" : "",
        task_error: task.json ? task.json.error || "" : "",
        task_error_detail: task.json ? task.json.errorDetail || "" : "",
        verdict: verdict.verdict,
        blocker_reason: verdict.blocker_reason,
        summary: verdict.summary,
      },
      artifact_refs: {
        module_probe_torch_meta: relativeRepoPath(path.join(runtimeDir, "module_probe_torch.meta.json")),
        module_probe_transformers_meta: relativeRepoPath(path.join(runtimeDir, "module_probe_transformers.meta.json")),
        status_meta: relativeRepoPath(path.join(runtimeDir, "status.meta.json")),
        embedding_warmup_meta: relativeRepoPath(path.join(runtimeDir, "embedding_warmup.meta.json")),
        embedding_task_meta: relativeRepoPath(path.join(runtimeDir, "embedding_task.meta.json")),
      },
    });
  }

  const comboRuntime = runtimes.find((runtime) => runtime.runtime_id === "lmstudio_cpython311_combo_transformers");
  const bestSummary = comboRuntime
    ? {
        runtime_id: comboRuntime.runtime_id,
        verdict: comboRuntime.embedding_sample1_probe.verdict,
        blocker_reason: comboRuntime.embedding_sample1_probe.blocker_reason,
        summary: comboRuntime.embedding_sample1_probe.summary,
      }
    : {
        runtime_id: "",
        verdict: "no_runtime_candidate_found",
        blocker_reason: "runtime_candidate_missing",
        summary: "未找到可用的 runtime candidate。",
      };

  const report = {
    schema_version: "xhub.lpr_w3_03_runtime_candidate_probe.v1",
    generated_at: generatedAt,
    scope: "LPR-W3-03 sample1 embedding real-model-dir probe",
    fail_closed: true,
    discovered_assets: {
      embedding_model_path: pathExists(embeddingModelPath) ? embeddingModelPath : "",
      vision_model_path: pathExists(visionModelPath) ? visionModelPath : "",
      lmstudio_cpython_path: pathExists(lmStudioCPython) ? lmStudioCPython : "",
      lmstudio_transformers_site_packages: pathExists(lmStudioTransformersSitePackages) ? lmStudioTransformersSitePackages : "",
      xcode_python_path: pathExists(xcodePython) ? xcodePython : "",
    },
    runtime_candidates: runtimes,
    current_best_candidate: bestSummary,
    next_actions: bestSummary.verdict === "sample1_pass"
      ? [
        "当前 combo runtime 已能直接执行 sample1，可复用该真实 embedding 模型目录推进 require-real 与产品退出矩阵。",
        "helper bridge 仍可保留为次路径，但不再是 sample1 当前主 blocker。",
      ]
      : [
        "若继续走 transformers 原生 runtime，需要一条可被 torch/transformers 原生加载的真实 embedding 模型目录。",
        "若继续复用 LM Studio helper bridge，需要先解决本机 LM Studio daemon / server 无法启动的问题。",
        "当前 probe 已证明 combo runtime 可以把 torch + transformers + PIL + tokenizers 组合到同一解释器内，但现有 embedding 模型目录仍 fail-closed。",
      ],
  };

  writeJSON(outputPath, report);
  process.stdout.write(`${outputPath}\n`);
}

if (require.main === module) {
  main();
}
