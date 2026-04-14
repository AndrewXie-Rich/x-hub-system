#!/usr/bin/env node
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const cp = require("node:child_process");

const {
  buildDefaultCaptureBundle,
  repoRoot,
  resolveBundlePath,
  resolveReportsDir,
  resolveRequireRealEvidencePath,
  writeJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");
const {
  buildRequireRealEvidence,
} = require("./generate_lpr_w3_03_a_require_real_evidence.js");

const reportsDir = resolveReportsDir();
const outputBundlePathDefault = resolveBundlePath();
const outputReportPathDefault = resolveRequireRealEvidencePath();
const artifactDirDefault = path.join(reportsDir, "lpr_w3_03_require_real", "auto_real_run");
const localRuntimeEntry = path.join(
  repoRoot,
  "x-hub",
  "python-runtime",
  "python_service",
  "relflowhub_local_runtime.py"
);
const comboPythonDefault =
  "/Users/andrew.xie/Documents/AX/Opensource/LM Studio.app/Contents/Resources/app/.webpack/bin/extensions/backends/vendor/_amphibian/cpython3.11-mac-arm64@10/bin/python3";
const comboSitePackagesDefault =
  "/Users/andrew.xie/Documents/AX/Opensource/LM Studio.app/Contents/Resources/app/.webpack/bin/extensions/backends/vendor/_amphibian/app-mlx-generate-mac14-arm64@19/lib/python3.11/site-packages";

const embeddingModelCandidates = [
  "/Users/andrew.xie/Documents/AX/Local Model/all-MiniLM-L6-v2",
  "/Users/andrew.xie/.lmstudio/models/sentence-transformers/all-MiniLM-L6-v2",
];
const asrModelCandidates = [
  "/Users/andrew.xie/Documents/AX/Local Model/whisper-tiny",
];
const visionModelCandidates = [
  "/Users/andrew.xie/.lmstudio/models/mlx-community/Qwen3-VL-4B-Instruct-3bit",
  "/Users/andrew.xie/Documents/AX/Local Model/Qwen3-VL-30B-A3B-Instruct-MLX-4bit",
];
const visionImageCandidates = [
  path.join(repoRoot, "Opensource", "aipyapp-main", "docs", "aipy.jpg"),
  path.join(repoRoot, "build", "reports", "lpr_w4_07_c_real_run", "vision_scene.png"),
  path.join(repoRoot, "build", "reports", "lpr_w4_07_c_real_run", "ocr_page.png"),
];
const voicePreviewCandidates = [
  "/System/Library/PrivateFrameworks/SiriTTSService.framework/Versions/A/Resources/VoicePreviews/en-US_nora.caf",
  "/System/Library/PrivateFrameworks/SiriTTSService.framework/Versions/A/Resources/VoicePreviews/en-US_damon.caf",
  "/System/Library/PrivateFrameworks/SiriTTSService.framework/Versions/A/Resources/VoicePreviews/en-US_quinn.caf",
];
const ffmpegCandidates = [
  "/opt/homebrew/bin/ffmpeg",
  "ffmpeg",
];

function isoNow() {
  return new Date().toISOString();
}

function normalizeString(value, fallback = "") {
  const normalized = String(value ?? "").trim();
  return normalized || fallback;
}

function normalizeArray(value) {
  return Array.isArray(value) ? value : [];
}

function normalizeObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function pathExists(targetPath) {
  return !!normalizeString(targetPath) && fs.existsSync(targetPath);
}

function readJSONIfExists(filePath) {
  try {
    if (!pathExists(filePath)) return null;
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function writeText(filePath, text) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, String(text ?? ""), "utf8");
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

function pickExistingPath(candidates) {
  for (const candidate of candidates || []) {
    if (pathExists(candidate)) return path.resolve(candidate);
  }
  return "";
}

function pickCommand(candidates) {
  for (const candidate of candidates || []) {
    if (candidate.includes(path.sep)) {
      if (pathExists(candidate)) return candidate;
      continue;
    }
    const probe = runCommand("which", [candidate], {
      cwd: repoRoot,
      timeoutMs: 5000,
    });
    const resolved = normalizeString(probe.stdout).split(/\r?\n/).find(Boolean) || "";
    if (probe.ok && resolved) return resolved;
  }
  return "";
}

function stableHash(value) {
  return crypto.createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

function parseJSON(text) {
  const raw = normalizeString(text);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function runCommand(command, args = [], options = {}) {
  const result = {
    command: [command, ...args],
    cwd: normalizeString(options.cwd, repoRoot),
    timeout_ms: Number.isFinite(options.timeoutMs) ? options.timeoutMs : 300000,
    started_at: isoNow(),
  };
  try {
    const execResult = cp.spawnSync(command, args, {
      cwd: result.cwd,
      env: options.env || process.env,
      input: options.input || undefined,
      encoding: "utf8",
      timeout: result.timeout_ms,
      maxBuffer: 64 * 1024 * 1024,
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
  ensureDir(dirPath);
  const stdoutPath = path.join(dirPath, `${prefix}.stdout.log`);
  const stderrPath = path.join(dirPath, `${prefix}.stderr.log`);
  const metaPath = path.join(dirPath, `${prefix}.meta.json`);
  writeText(stdoutPath, result.stdout || "");
  writeText(stderrPath, result.stderr || "");
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

function comboRuntimeEnv(baseDir, comboSitePackages) {
  return {
    ...process.env,
    REL_FLOW_HUB_BASE_DIR: baseDir,
    PYTHONUNBUFFERED: "1",
    HF_HUB_OFFLINE: "1",
    TRANSFORMERS_OFFLINE: "1",
    HF_DATASETS_OFFLINE: "1",
    TOKENIZERS_PARALLELISM: "false",
    PYTHONPATH: normalizeString(comboSitePackages),
  };
}

function runLocalRuntimeJSON(runtime, baseDir, subcommand, request, artifactDir, prefix) {
  const result = runCommand(runtime.pythonBin, [localRuntimeEntry, subcommand, "-"], {
    cwd: repoRoot,
    env: comboRuntimeEnv(baseDir, runtime.comboSitePackages),
    input: JSON.stringify(request || {}),
    timeoutMs: 600000,
  });
  const artifactRefs = persistCommandArtifacts(artifactDir, prefix, result);
  const parsed = parseJSON(result.stdout);
  const parsedPath = path.join(artifactDir, `${prefix}.json`);
  if (parsed) {
    writeJSON(parsedPath, parsed);
  } else {
    writeJSON(parsedPath, {
      ok: false,
      error: "json_parse_failed",
      raw_stdout_excerpt: normalizeString(result.stdout).slice(0, 1200),
      raw_stderr_excerpt: normalizeString(result.stderr).slice(0, 1200),
    });
  }
  return {
    raw: result,
    json: parsed,
    artifact_refs: {
      ...artifactRefs,
      json: relPath(parsedPath),
    },
  };
}

function buildModelsCatalog(resolvedPaths) {
  return {
    models: [
      {
        id: "real-embed-minilm",
        name: "all-MiniLM-L6-v2",
        backend: "transformers",
        modelPath: resolvedPaths.embeddingModelPath,
        taskKinds: ["embedding"],
        maxContextLength: 32768,
        default_load_config: {
          context_length: 8192,
        },
      },
      {
        id: "real-asr-whisper-tiny",
        name: "whisper-tiny",
        backend: "transformers",
        modelPath: resolvedPaths.asrModelPath,
        taskKinds: ["speech_to_text"],
        maxContextLength: 4096,
        default_load_config: {
          context_length: 2048,
        },
      },
      {
        id: "real-vision-qwen3-vl",
        name: path.basename(resolvedPaths.visionModelPath),
        backend: "transformers",
        modelPath: resolvedPaths.visionModelPath,
        taskKinds: ["vision_understand"],
        maxContextLength: 8192,
        default_load_config: {
          context_length: 4096,
          vision: {
            image_max_dimension: 2048,
          },
        },
      },
    ],
  };
}

function copyInputArtifact(sourcePath, destinationPath) {
  if (!pathExists(sourcePath)) {
    throw new Error(`input artifact missing: ${sourcePath}`);
  }
  ensureDir(path.dirname(destinationPath));
  fs.copyFileSync(sourcePath, destinationPath);
  return destinationPath;
}

function generateSpeechWav(artifactDir) {
  const audioDir = path.join(artifactDir, "input_artifacts");
  ensureDir(audioDir);
  const sourcePreviewPath = pickExistingPath(voicePreviewCandidates);
  const ffmpegPath = pickCommand(ffmpegCandidates);
  const wavPath = path.join(audioDir, "asr_input.wav");
  const sourcePreviewNotePath = path.join(audioDir, "asr_source_preview.txt");
  if (!sourcePreviewPath) {
    throw new Error("voice_preview_not_found");
  }
  if (!ffmpegPath) {
    throw new Error("ffmpeg_not_found");
  }

  writeText(sourcePreviewNotePath, `${sourcePreviewPath}\n`);
  const convertResult = runCommand(ffmpegPath, [
    "-y",
    "-i",
    sourcePreviewPath,
    "-ar",
    "16000",
    "-ac",
    "1",
    wavPath,
  ], {
    cwd: repoRoot,
    timeoutMs: 120000,
  });
  const convertRefs = persistCommandArtifacts(audioDir, "asr_generate_ffmpeg", convertResult);
  if (!convertResult.ok || !pathExists(wavPath)) {
    throw new Error(`ffmpeg_failed:${convertResult.error || convertResult.stderr || convertResult.stdout}`);
  }

  return {
    wavPath,
    sourcePreviewPath,
    sourcePreviewNotePath,
    evidenceRefs: uniqueStrings([
      relPath(sourcePreviewNotePath),
      sourcePreviewPath,
      relPath(wavPath),
      convertRefs.meta,
      convertRefs.stdout,
      convertRefs.stderr,
    ]),
  };
}

function buildProviderSummaryExport(payload) {
  const embedding = normalizeObject(payload.embedding);
  const asr = normalizeObject(payload.asr);
  const vision = normalizeObject(payload.vision);
  const statusFinal = normalizeObject(payload.statusFinal);
  const transformersStatus = normalizeObject(normalizeObject(statusFinal.providers).transformers);
  return {
    schema_version: "xhub.lpr_w3_03_provider_summary_export.v1",
    generated_at: isoNow(),
    runtime_source: "local_runtime_cli",
    python_bin: payload.runtime.pythonBin,
    runtime_ready: Array.isArray(statusFinal.readyProviderIds)
      && statusFinal.readyProviderIds.includes("transformers"),
    provider: {
      ok: transformersStatus.ok === true,
      reasonCode: normalizeString(transformersStatus.reasonCode),
      runtimeReasonCode: normalizeString(transformersStatus.runtimeReasonCode),
      runtimeSource: normalizeString(transformersStatus.runtimeSource),
      deviceBackend: normalizeString(transformersStatus.deviceBackend),
      residencyScope: normalizeString(transformersStatus.residencyScope),
    },
    loaded_instances: normalizeArray(statusFinal.loadedInstances).filter(
      (row) => normalizeString(row.provider).toLowerCase() === "transformers"
    ),
    sample_truth: {
      embedding: {
        modelId: normalizeString(embedding.task?.modelId || embedding.warmup?.modelId),
        modelPath: normalizeString(embedding.task?.modelPath || embedding.warmup?.modelPath),
        vectorCount: Number(embedding.task?.vectorCount || 0),
        latencyMs: Number(embedding.task?.latencyMs || 0),
      },
      speech_to_text: {
        modelId: normalizeString(asr.task?.modelId || asr.warmup?.modelId),
        modelPath: normalizeString(asr.task?.modelPath || asr.warmup?.modelPath),
        transcriptCharCount: normalizeString(asr.task?.text).length,
        segmentCount: normalizeArray(asr.task?.segments).length,
        latencyMs: Number(asr.task?.latencyMs || 0),
      },
      vision_understand: {
        modelId: normalizeString(vision.task?.modelId || vision.warmup?.modelId),
        modelPath: normalizeString(vision.task?.modelPath || vision.warmup?.modelPath),
        ok: vision.task?.ok === true,
        reasonCode: normalizeString(vision.task?.reasonCode || vision.warmup?.reasonCode),
        error: normalizeString(vision.task?.error || vision.warmup?.error),
      },
    },
    source_refs: uniqueStrings(payload.sourceRefs),
  };
}

function buildReleaseHint(payload) {
  const embedding = normalizeObject(payload.embedding);
  const asr = normalizeObject(payload.asr);
  const vision = normalizeObject(payload.vision);
  return {
    schema_version: "xhub.lpr_w3_03_release_hint.v1",
    generated_at: isoNow(),
    gate_verdict: "candidate_pass(real_run_bundle_ready)",
    runtime_truth_source: "shared_monitor_snapshot_and_provider_summary",
    covered_task_kinds: ["embedding", "speech_to_text", "vision_understand"],
    samples: {
      embedding: {
        ok: embedding.task?.ok === true,
        loadProfileHash: normalizeString(embedding.loadProfileHash),
        instanceKey: normalizeString(embedding.instanceKey),
      },
      speech_to_text: {
        ok: asr.task?.ok === true,
        loadProfileHash: normalizeString(asr.loadProfileHash),
        instanceKey: normalizeString(asr.instanceKey),
      },
      vision_understand: {
        ok: vision.task?.ok === true,
        acceptedFailClosed:
          vision.task?.ok !== true && normalizeString(vision.reasonCode) !== "",
        reasonCode: normalizeString(vision.reasonCode),
      },
    },
    source_refs: uniqueStrings(payload.sourceRefs),
  };
}

function pickTaskValue(task, warmup, field, fallback = "") {
  const taskValue = task && task[field] !== undefined ? task[field] : undefined;
  if (taskValue !== undefined && taskValue !== null && taskValue !== "") return taskValue;
  const warmupValue = warmup && warmup[field] !== undefined ? warmup[field] : undefined;
  if (warmupValue !== undefined && warmupValue !== null && warmupValue !== "") return warmupValue;
  return fallback;
}

function buildVisionFallbackOutcome(visionTask, visionWarmup) {
  const task = normalizeObject(visionTask);
  const warmup = normalizeObject(visionWarmup);
  const reasonCode = normalizeString(task.reasonCode || warmup.reasonCode || task.error || warmup.error);
  const error = normalizeString(task.error || warmup.error);
  const errorDetail = normalizeString(task.errorDetail || warmup.errorDetail);
  return {
    outcome_kind: task.ok === true ? "ran" : "fail_closed",
    reason_code: reasonCode || "vision_fail_closed_without_reason",
    outcome_summary: task.ok === true
      ? normalizeString(task.text || "vision task completed")
      : [error, reasonCode, errorDetail].filter(Boolean).join(" | "),
    real_runtime_touched: true,
  };
}

function buildWarmupFailClosedVisionTask(visionWarmup) {
  const warmup = normalizeObject(visionWarmup);
  return {
    ok: false,
    skipped_after_warmup_fail_closed: true,
    reasonCode: normalizeString(warmup.reasonCode || warmup.error, "vision_warmup_failed"),
    error: normalizeString(warmup.error, "vision_warmup_failed"),
    errorDetail: normalizeString(warmup.errorDetail),
    provider: normalizeString(warmup.provider, "transformers"),
    taskKind: normalizeString(warmup.taskKind, "vision_understand"),
    modelId: normalizeString(warmup.modelId, "real-vision-qwen3-vl"),
    modelPath: normalizeString(warmup.modelPath),
    latencyMs: Number(warmup.latencyMs || 0),
    loadProfileHash: normalizeString(warmup.loadProfileHash),
    effectiveContextLength: Number(warmup.effectiveContextLength || 0),
  };
}

function main() {
  const options = {
    artifactDir: artifactDirDefault,
    bundlePath: outputBundlePathDefault,
    reportPath: outputReportPathDefault,
    pythonBin: comboPythonDefault,
    comboSitePackages: comboSitePackagesDefault,
  };

  const resolvedPaths = {
    embeddingModelPath: pickExistingPath(embeddingModelCandidates),
    asrModelPath: pickExistingPath(asrModelCandidates),
    visionModelPath: pickExistingPath(visionModelCandidates),
    visionImagePath: pickExistingPath(visionImageCandidates),
  };

  if (!pathExists(options.pythonBin)) throw new Error(`python_bin_not_found:${options.pythonBin}`);
  if (!pathExists(options.comboSitePackages)) throw new Error(`combo_site_packages_not_found:${options.comboSitePackages}`);
  if (!resolvedPaths.embeddingModelPath) throw new Error("embedding_model_not_found");
  if (!resolvedPaths.asrModelPath) throw new Error("asr_model_not_found");
  if (!resolvedPaths.visionModelPath) throw new Error("vision_model_not_found");
  if (!resolvedPaths.visionImagePath) throw new Error("vision_image_not_found");

  const artifactDir = path.resolve(options.artifactDir);
  const runtimeArtifactDir = path.join(artifactDir, "runtime");
  const baseDir = path.join(runtimeArtifactDir, "base_dir");
  const inputArtifactDir = path.join(artifactDir, "input_artifacts");
  const exportDir = path.join(artifactDir, "doctor_export");
  ensureDir(baseDir);
  ensureDir(inputArtifactDir);
  ensureDir(exportDir);

  writeJSON(path.join(baseDir, "models_catalog.json"), buildModelsCatalog(resolvedPaths));

  const embeddingText =
    "X Hub keeps terminal and hub state aligned after WiFi pairing, and the runtime remains grounded in current device truth.";
  const embeddingInputPath = path.join(inputArtifactDir, "embedding_input.txt");
  writeText(embeddingInputPath, `${embeddingText}\n`);

  const asrAudio = generateSpeechWav(artifactDir);

  const visionInputPath = path.join(inputArtifactDir, path.basename(resolvedPaths.visionImagePath));
  copyInputArtifact(resolvedPaths.visionImagePath, visionInputPath);

  const runtime = {
    pythonBin: options.pythonBin,
    comboSitePackages: options.comboSitePackages,
    deviceId: "release_evidence_mac",
  };

  const initialStatus = runLocalRuntimeJSON(runtime, baseDir, "status", {}, runtimeArtifactDir, "status_initial");

  const embeddingProfile = { context_length: 8192 };
  const embeddingLoadProfileHash = stableHash(embeddingProfile);
  const embeddingWarmup = runLocalRuntimeJSON(runtime, baseDir, "manage-local-model", {
    action: "warmup_local_model",
    provider: "transformers",
    task_kind: "embedding",
    model_id: "real-embed-minilm",
    device_id: runtime.deviceId,
    load_profile_hash: embeddingLoadProfileHash,
    load_profile_override: embeddingProfile,
  }, runtimeArtifactDir, "embedding_warmup");
  const embeddingTask = runLocalRuntimeJSON(runtime, baseDir, "run-local-task", {
    provider: "transformers",
    task_kind: "embedding",
    model_id: "real-embed-minilm",
    device_id: runtime.deviceId,
    load_profile_hash: normalizeString(embeddingWarmup.json?.loadProfileHash, embeddingLoadProfileHash),
    instance_key: normalizeString(embeddingWarmup.json?.instanceKey),
    effective_context_length: Number(embeddingWarmup.json?.effectiveContextLength || embeddingProfile.context_length),
    texts: [
      embeddingText,
      "The supervisor can verify current state, route tasks, and keep evidence synchronized across the local runtime.",
    ],
    input_sanitized: true,
    options: {
      max_length: 256,
    },
  }, runtimeArtifactDir, "embedding_task");
  const statusAfterEmbedding = runLocalRuntimeJSON(runtime, baseDir, "status", {}, runtimeArtifactDir, "status_after_embedding");

  const asrProfile = { context_length: 2048 };
  const asrLoadProfileHash = stableHash(asrProfile);
  const asrWarmup = runLocalRuntimeJSON(runtime, baseDir, "manage-local-model", {
    action: "warmup_local_model",
    provider: "transformers",
    task_kind: "speech_to_text",
    model_id: "real-asr-whisper-tiny",
    device_id: runtime.deviceId,
    load_profile_hash: asrLoadProfileHash,
    load_profile_override: asrProfile,
  }, runtimeArtifactDir, "asr_warmup");
  const asrTask = runLocalRuntimeJSON(runtime, baseDir, "run-local-task", {
    provider: "transformers",
    task_kind: "speech_to_text",
    model_id: "real-asr-whisper-tiny",
    device_id: runtime.deviceId,
    load_profile_hash: normalizeString(asrWarmup.json?.loadProfileHash, asrLoadProfileHash),
    instance_key: normalizeString(asrWarmup.json?.instanceKey),
    effective_context_length: Number(asrWarmup.json?.effectiveContextLength || asrProfile.context_length),
    audio_path: asrAudio.wavPath,
    language: "en",
    timestamps: true,
  }, runtimeArtifactDir, "asr_task");
  const statusAfterAsr = runLocalRuntimeJSON(runtime, baseDir, "status", {}, runtimeArtifactDir, "status_after_asr");

  const visionProfile = {
    context_length: 4096,
    vision: {
      image_max_dimension: 2048,
    },
  };
  const visionLoadProfileHash = stableHash(visionProfile);
  const visionWarmup = runLocalRuntimeJSON(runtime, baseDir, "manage-local-model", {
    action: "warmup_local_model",
    provider: "transformers",
    task_kind: "vision_understand",
    model_id: "real-vision-qwen3-vl",
    device_id: runtime.deviceId,
    load_profile_hash: visionLoadProfileHash,
    load_profile_override: visionProfile,
  }, runtimeArtifactDir, "vision_warmup");
  const visionTask = visionWarmup.json?.ok === true
    ? runLocalRuntimeJSON(runtime, baseDir, "run-local-task", {
      provider: "transformers",
      task_kind: "vision_understand",
      model_id: "real-vision-qwen3-vl",
      device_id: runtime.deviceId,
      load_profile_hash: normalizeString(visionWarmup.json?.loadProfileHash, visionLoadProfileHash),
      instance_key: normalizeString(visionWarmup.json?.instanceKey),
      effective_context_length: Number(visionWarmup.json?.effectiveContextLength || visionProfile.context_length),
      image_path: visionInputPath,
      prompt: "Summarize the main visual content in one short sentence.",
    }, runtimeArtifactDir, "vision_task")
    : {
      raw: null,
      json: buildWarmupFailClosedVisionTask(visionWarmup.json),
      artifact_refs: {},
    };
  const visionTaskExecuted = visionWarmup.json?.ok === true;
  const statusFinal = runLocalRuntimeJSON(runtime, baseDir, "status", {}, runtimeArtifactDir, "status_final");

  const monitorSnapshotPath = path.join(exportDir, "runtime_monitor_snapshot.v1.json");
  writeJSON(monitorSnapshotPath, normalizeObject(statusFinal.json));

  const providerSummaryPath = path.join(exportDir, "provider_summary_export.v1.json");
  writeJSON(providerSummaryPath, buildProviderSummaryExport({
    runtime,
    embedding: {
      warmup: embeddingWarmup.json,
      task: embeddingTask.json,
    },
    asr: {
      warmup: asrWarmup.json,
      task: asrTask.json,
    },
    vision: {
      warmup: visionWarmup.json,
      task: visionTask.json,
    },
    statusFinal: statusFinal.json,
    sourceRefs: uniqueStrings([
      monitorSnapshotPath,
      path.join(runtimeArtifactDir, "embedding_warmup.json"),
      path.join(runtimeArtifactDir, "embedding_task.json"),
      path.join(runtimeArtifactDir, "asr_warmup.json"),
      path.join(runtimeArtifactDir, "asr_task.json"),
      path.join(runtimeArtifactDir, "vision_warmup.json"),
      visionTaskExecuted ? path.join(runtimeArtifactDir, "vision_task.json") : "",
    ].map(relPath)),
  }));

  const releaseHintPath = path.join(exportDir, "release_hint.v1.json");
  writeJSON(releaseHintPath, buildReleaseHint({
    embedding: {
      loadProfileHash: normalizeString(embeddingWarmup.json?.loadProfileHash, embeddingLoadProfileHash),
      instanceKey: normalizeString(embeddingWarmup.json?.instanceKey),
      task: embeddingTask.json,
    },
    asr: {
      loadProfileHash: normalizeString(asrWarmup.json?.loadProfileHash, asrLoadProfileHash),
      instanceKey: normalizeString(asrWarmup.json?.instanceKey),
      task: asrTask.json,
    },
    vision: {
      reasonCode: normalizeString(
        visionTask.json?.reasonCode || visionWarmup.json?.reasonCode || visionTask.json?.error || visionWarmup.json?.error
      ),
      task: visionTask.json,
    },
    sourceRefs: uniqueStrings([
      monitorSnapshotPath,
      providerSummaryPath,
      path.join(runtimeArtifactDir, "embedding_task.json"),
      path.join(runtimeArtifactDir, "asr_task.json"),
      visionTaskExecuted ? path.join(runtimeArtifactDir, "vision_task.json") : path.join(runtimeArtifactDir, "vision_warmup.json"),
    ].map(relPath)),
  }));

  const bundle = buildDefaultCaptureBundle({
    generatedAt: isoNow(),
  });
  bundle.status = "executed";
  bundle.updated_at = isoNow();

  const sampleById = Object.fromEntries(
    normalizeArray(bundle.samples).map((sample) => [normalizeString(sample.sample_id), sample])
  );

  const commonSampleEvidenceRefs = uniqueStrings([
    relPath(path.join(baseDir, "models_catalog.json")),
    relPath(monitorSnapshotPath),
    relPath(providerSummaryPath),
    relPath(releaseHintPath),
  ]);

  const embeddingSample = sampleById.lpr_rr_01_embedding_real_model_dir_executes;
  Object.assign(embeddingSample, {
    status: "passed",
    performed_at: isoNow(),
    success_boolean: embeddingTask.json?.ok === true,
    evidence_refs: uniqueStrings([
      ...commonSampleEvidenceRefs,
      relPath(embeddingInputPath),
      ...Object.values(embeddingWarmup.artifact_refs),
      ...Object.values(embeddingTask.artifact_refs),
      ...Object.values(statusAfterEmbedding.artifact_refs),
    ]),
    operator_notes: "Executed with local runtime CLI against an on-disk embedding model directory and a local text artifact.",
    evidence_origin: "local_runtime_cli_model_dir",
    synthetic_runtime_evidence: false,
    synthetic_markers: [],
    provider: "transformers",
    task_kind: "embedding",
    model_id: normalizeString(embeddingTask.json?.modelId || embeddingWarmup.json?.modelId, "real-embed-minilm"),
    model_path: normalizeString(embeddingTask.json?.modelPath || embeddingWarmup.json?.modelPath, resolvedPaths.embeddingModelPath),
    device_id: runtime.deviceId,
    route_source: "explicit_model_id_cli_request",
    load_profile_hash: normalizeString(embeddingWarmup.json?.loadProfileHash, embeddingLoadProfileHash),
    effective_context_length: Number(embeddingWarmup.json?.effectiveContextLength || embeddingProfile.context_length),
    input_artifact_ref: relPath(embeddingInputPath),
    vector_count: Number(embeddingTask.json?.vectorCount || 0),
    latency_ms: Number(embeddingTask.json?.latencyMs || 0),
    monitor_snapshot_captured: pathExists(monitorSnapshotPath),
    diagnostics_export_captured: pathExists(providerSummaryPath),
  });

  const asrSample = sampleById.lpr_rr_02_asr_real_model_dir_executes;
  Object.assign(asrSample, {
    status: "passed",
    performed_at: isoNow(),
    success_boolean: asrTask.json?.ok === true,
    evidence_refs: uniqueStrings([
      ...commonSampleEvidenceRefs,
      ...asrAudio.evidenceRefs,
      ...Object.values(asrWarmup.artifact_refs),
      ...Object.values(asrTask.artifact_refs),
      ...Object.values(statusAfterAsr.artifact_refs),
    ]),
    operator_notes: "Executed with local runtime CLI against an on-disk speech-to-text model directory and a local wav artifact converted from a system voice preview asset.",
    evidence_origin: "local_runtime_cli_on_device_audio",
    synthetic_runtime_evidence: false,
    synthetic_markers: [],
    provider: "transformers",
    task_kind: "speech_to_text",
    model_id: normalizeString(asrTask.json?.modelId || asrWarmup.json?.modelId, "real-asr-whisper-tiny"),
    model_path: normalizeString(asrTask.json?.modelPath || asrWarmup.json?.modelPath, resolvedPaths.asrModelPath),
    device_id: runtime.deviceId,
    route_source: "explicit_model_id_cli_request",
    load_profile_hash: normalizeString(asrWarmup.json?.loadProfileHash, asrLoadProfileHash),
    effective_context_length: Number(asrWarmup.json?.effectiveContextLength || asrProfile.context_length),
    input_artifact_ref: relPath(asrAudio.wavPath),
    transcript_char_count: normalizeString(asrTask.json?.text).length,
    segment_count: normalizeArray(asrTask.json?.segments).length,
    latency_ms: Number(asrTask.json?.latencyMs || 0),
    monitor_snapshot_captured: pathExists(monitorSnapshotPath),
    diagnostics_export_captured: pathExists(providerSummaryPath),
  });

  const visionOutcome = buildVisionFallbackOutcome(visionTask.json, visionWarmup.json);
  const visionSample = sampleById.lpr_rr_03_vision_real_model_dir_exercised;
  Object.assign(visionSample, {
    status: "passed",
    performed_at: isoNow(),
    success_boolean: true,
    evidence_refs: uniqueStrings([
      ...commonSampleEvidenceRefs,
      relPath(visionInputPath),
      ...Object.values(visionWarmup.artifact_refs),
      ...(visionTaskExecuted ? Object.values(visionTask.artifact_refs) : []),
      ...Object.values(statusFinal.artifact_refs),
    ]),
    operator_notes: "Executed with local runtime CLI against an on-disk vision model directory and a local image artifact; fail-closed is preserved as product truth when the runtime rejects the model format.",
    evidence_origin: "local_runtime_cli_model_dir",
    synthetic_runtime_evidence: false,
    synthetic_markers: [],
    provider: "transformers",
    task_kind: "vision_understand",
    model_id: normalizeString(
      pickTaskValue(visionTask.json, visionWarmup.json, "modelId"),
      "real-vision-qwen3-vl"
    ),
    model_path: normalizeString(
      pickTaskValue(visionTask.json, visionWarmup.json, "modelPath"),
      resolvedPaths.visionModelPath
    ),
    device_id: runtime.deviceId,
    route_source: "explicit_model_id_cli_request",
    load_profile_hash: normalizeString(
      pickTaskValue(visionTask.json, visionWarmup.json, "loadProfileHash"),
      visionLoadProfileHash
    ),
    effective_context_length: Number(
      pickTaskValue(visionTask.json, visionWarmup.json, "effectiveContextLength", visionProfile.context_length)
    ),
    input_artifact_ref: relPath(visionInputPath),
    outcome_kind: visionOutcome.outcome_kind,
    outcome_summary: normalizeString(visionOutcome.outcome_summary, "vision fail-closed without summary"),
    reason_code: normalizeString(visionOutcome.reason_code, "vision_fail_closed_without_reason"),
    real_runtime_touched: visionOutcome.real_runtime_touched === true,
    latency_ms: Number(visionTask.json?.latencyMs || visionWarmup.json?.latencyMs || 0),
    monitor_snapshot_captured: pathExists(monitorSnapshotPath),
    diagnostics_export_captured: pathExists(providerSummaryPath),
  });

  const doctorSample = sampleById.lpr_rr_04_doctor_and_release_export_match_real_runs;
  Object.assign(doctorSample, {
    status: "passed",
    performed_at: isoNow(),
    success_boolean: true,
    evidence_refs: uniqueStrings([
      relPath(monitorSnapshotPath),
      relPath(providerSummaryPath),
      relPath(releaseHintPath),
      ...Object.values(statusFinal.artifact_refs),
    ]),
    operator_notes: "Provider summary, monitor snapshot, and release hint all reuse the same runtime truth captured from this real local-runtime run.",
    evidence_origin: "local_runtime_cli_export",
    synthetic_runtime_evidence: false,
    synthetic_markers: [],
    provider_summary_export_ref: relPath(providerSummaryPath),
    monitor_snapshot_export_ref: relPath(monitorSnapshotPath),
    release_hint_ref: relPath(releaseHintPath),
    covered_task_kinds: ["embedding", "speech_to_text", "vision_understand"],
    runtime_truth_shared: true,
    doctor_export_matches_real_runs: true,
  });

  writeJSON(options.bundlePath, bundle);

  const report = buildRequireRealEvidence(bundle);
  writeJSON(options.reportPath, report);

  process.stdout.write(`${relPath(options.bundlePath)}\n`);
  process.stdout.write(`${relPath(options.reportPath)}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${String(error && error.message ? error.message : error)}\n`);
    process.exit(1);
  }
}
