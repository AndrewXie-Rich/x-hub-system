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
  buildStaticMarkers,
  chooseReadyRuntime,
  classifyLoadability,
  collectModelDiscoveryInputs,
  directoryLooksLikeModel,
  normalizeCatalogModelDir,
  pathExists,
  resolveKnownModelDiscoveryForPath,
  runNativeLoadabilityProbe,
  slugForModel,
} = require("./generate_lpr_w3_03_c_model_native_loadability_probe.js");

const reportsDir = resolveReportsDir();
const outputPathDefault = path.join(reportsDir, "lpr_w4_07_b_mlx_vlm_require_real_evidence.v1.json");
const artifactRoot = path.join(reportsDir, "lpr_w4_07_b_mlx_vlm_require_real");
const helperBinaryPathDefault = path.join(os.homedir(), ".lmstudio", "bin", "lms");
const helperSettingsPathDefault = path.join(os.homedir(), ".lmstudio", "settings.json");

function isoNow() {
  return new Date().toISOString();
}

function normalizeString(value) {
  return String(value || "").trim();
}

function relPath(targetPath) {
  return path.relative(repoRoot, targetPath).split(path.sep).join("/");
}

function safeMkdir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function readJSONIfExists(filePath) {
  try {
    if (!filePath || !fs.existsSync(filePath)) return null;
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
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

function detectPositiveSignal(text, options = {}) {
  const normalized = normalizeString(text);
  if (!normalized) return false;
  const negativePatterns = Array.isArray(options.negativePatterns) ? options.negativePatterns : [];
  const positivePatterns = Array.isArray(options.positivePatterns) ? options.positivePatterns : [];
  if (negativePatterns.some((pattern) => pattern.test(normalized))) return false;
  return positivePatterns.some((pattern) => pattern.test(normalized));
}

function detectDaemonRunningSignal(text) {
  return detectPositiveSignal(text, {
    negativePatterns: [/not running/i, /daemon is down/i, /failed to start/i],
    positivePatterns: [/is running/i, /daemon is running/i, /listening/i, /\bready\b/i],
  });
}

function detectServerRunningSignal(text) {
  return detectPositiveSignal(text, {
    negativePatterns: [/server is not running/i, /\bnot running\b/i, /failed to start/i],
    positivePatterns: [/server is running/i, /listening on/i, /accepting requests/i],
  });
}

function extractAppBundlePathFromRuntimeCommand(runtimeCommand) {
  const normalized = normalizeString(runtimeCommand);
  if (!normalized) return "";
  const markerIndex = normalized.indexOf(".app/Contents/");
  if (markerIndex < 0) return "";
  return path.resolve(`${normalized.slice(0, markerIndex)}.app`);
}

function runCommand(command, args, options = {}) {
  const result = {
    command: [command, ...(args || [])],
    cwd: options.cwd || repoRoot,
    timeout_ms: Number.isFinite(options.timeoutMs) ? options.timeoutMs : 15000,
    started_at: isoNow(),
  };
  try {
    const execResult = cp.spawnSync(command, args || [], {
      cwd: result.cwd,
      env: options.env || process.env,
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
  fs.writeFileSync(path.join(dirPath, `${prefix}.stdout.log`), String(result.stdout || ""), "utf8");
  fs.writeFileSync(path.join(dirPath, `${prefix}.stderr.log`), String(result.stderr || ""), "utf8");
  writeJSON(path.join(dirPath, `${prefix}.meta.json`), {
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
}

function inspectAppBundleHealth(artifactDir, options = {}) {
  const appBundlePath =
    normalizeString(options.appBundlePath) || extractAppBundlePathFromRuntimeCommand(options.runtimeCommand);
  const bundlePresent = pathExists(appBundlePath);

  let codesignStatus = null;
  let xattrStatus = null;
  if (bundlePresent) {
    codesignStatus = runCommand("codesign", ["--verify", "--deep", "--strict", "--verbose=2", appBundlePath], {
      timeoutMs: 10000,
    });
    xattrStatus = runCommand("xattr", ["-l", appBundlePath], { timeoutMs: 5000 });
    persistCommandArtifacts(artifactDir, "helper_app_bundle_codesign", codesignStatus);
    persistCommandArtifacts(artifactDir, "helper_app_bundle_xattr", xattrStatus);
  }

  const codesignText = [codesignStatus && codesignStatus.stdout, codesignStatus && codesignStatus.stderr]
    .filter(Boolean)
    .join("\n");
  let signatureReasonCode = "";
  if (appBundlePath && !bundlePresent) {
    signatureReasonCode = "app_bundle_missing";
  } else if (bundlePresent && codesignStatus && !codesignStatus.ok) {
    if (/invalid signature|code or signature have been modified/i.test(codesignText)) {
      signatureReasonCode = "app_bundle_invalid_signature";
    } else if (/not signed at all|code object is not signed/i.test(codesignText)) {
      signatureReasonCode = "app_bundle_unsigned";
    } else {
      signatureReasonCode = "app_bundle_signature_check_failed";
    }
  }

  const xattrText = [xattrStatus && xattrStatus.stdout, xattrStatus && xattrStatus.stderr].filter(Boolean).join("\n");
  const xattrKeys = dedupeStrings(
    xattrText
      .split(/\r?\n/)
      .map((line) => line.split(":")[0])
      .map((line) => normalizeString(line))
  );
  const quarantinePresent = xattrKeys.includes("com.apple.quarantine");

  return {
    app_bundle_path: appBundlePath,
    bundle_present: bundlePresent,
    inferred_from_runtime_command: !!(appBundlePath && normalizeString(options.runtimeCommand)),
    signature: {
      checked: bundlePresent,
      ok: bundlePresent ? !!(codesignStatus && codesignStatus.ok) : false,
      reason_code: signatureReasonCode,
      output_excerpt: normalizeString(codesignText).slice(0, 400),
    },
    quarantine: {
      checked: bundlePresent,
      present: quarantinePresent,
      keys: xattrKeys,
      output_excerpt: normalizeString(xattrText).slice(0, 400),
    },
    artifact_refs: {
      helper_app_bundle_codesign_meta: bundlePresent ? relPath(path.join(artifactDir, "helper_app_bundle_codesign.meta.json")) : "",
      helper_app_bundle_xattr_meta: bundlePresent ? relPath(path.join(artifactDir, "helper_app_bundle_xattr.meta.json")) : "",
    },
  };
}

function defaultCandidateModelPaths() {
  return [
    "/Users/andrew.xie/Documents/AX/Local Model/GLM-4.6V-Flash-MLX-4bit",
    "/Users/andrew.xie/Documents/AX/Local Model/Qwen3-VL-30B-A3B-Instruct-MLX-4bit",
    path.join(os.homedir(), ".lmstudio", "models", "mlx-community", "GLM-4.6V-Flash-MLX-4bit"),
    path.join(os.homedir(), ".lmstudio", "models", "mlx-community", "Qwen3-VL-30B-A3B-Instruct-MLX-4bit"),
  ];
}

function resolveRequestedModelPath(explicitPath) {
  const normalizedExplicit = normalizeString(explicitPath);
  if (normalizedExplicit) {
    return path.resolve(normalizedExplicit);
  }
  const discovered = defaultCandidateModelPaths().find((candidate) => pathExists(candidate));
  return discovered ? path.resolve(discovered) : path.resolve(defaultCandidateModelPaths()[0]);
}

function detectModelDirIssues(staticMarkers, modelDirExists, modelDirLooksLikeModel) {
  if (!modelDirExists) {
    return {
      ready: false,
      reason_code: "model_path_not_found",
      summary: "The requested MLX VLM model directory does not exist on disk.",
      detail_codes: ["model_path_not_found"],
    };
  }
  if (!modelDirLooksLikeModel) {
    return {
      ready: false,
      reason_code: "model_dir_not_recognized",
      summary: "The requested path exists but does not look like a local model directory.",
      detail_codes: ["model_dir_not_recognized"],
    };
  }

  const fileMarkers =
    staticMarkers && typeof staticMarkers === "object" && staticMarkers.file_markers
      ? staticMarkers.file_markers
      : {};
  const topLevelFiles = Array.isArray(fileMarkers.top_level_files) ? fileMarkers.top_level_files : [];
  const hasPartialDownload = topLevelFiles.some((name) => /\.part$/i.test(String(name || "")));
  if (hasPartialDownload) {
    return {
      ready: false,
      reason_code: "model_dir_incomplete_download",
      summary: "The model directory still contains partial download artifacts and is not ready for require-real execution.",
      detail_codes: ["partial_download_artifact_present"],
    };
  }

  return {
    ready: true,
    reason_code: "",
    summary: "The model directory looks locally complete enough for a require-real attempt.",
    detail_codes: [],
  };
}

function summarizeLoadability(loadability) {
  if (!loadability || typeof loadability !== "object") {
    return {
      verdict: "not_probed",
      blocker_reason: "native_probe_not_executed",
      reasons: ["native_probe_not_executed"],
    };
  }
  return {
    verdict: normalizeString(loadability.verdict) || "unknown",
    blocker_reason: normalizeString(loadability.blocker_reason),
    reasons: dedupeStrings(loadability.reasons || []),
    auto_config_ok: loadability.auto_config_ok === true,
    auto_tokenizer_ok: loadability.auto_tokenizer_ok === true,
    auto_model_ok: loadability.auto_model_ok === true,
    auto_model_for_causal_lm_ok: loadability.auto_model_for_causal_lm_ok === true,
  };
}

function evaluateHelperBridgeReadiness(input) {
  const binaryPresent = input.binaryPresent === true;
  const enableLocalService = input.enableLocalService === true;
  const appFirstLoad = input.appFirstLoad === true;
  const daemonText = normalizeString(input.daemonText);
  const serverText = normalizeString(input.serverText);
  const daemonRunning = detectDaemonRunningSignal(daemonText);
  const serverRunning = detectServerRunningSignal(serverText);
  const appBundle = input.appBundle && typeof input.appBundle === "object" ? input.appBundle : {};
  const signatureReasonCode =
    appBundle.signature && typeof appBundle.signature === "object" ? normalizeString(appBundle.signature.reason_code) : "";
  const quarantinePresent = !!(
    appBundle.quarantine &&
    typeof appBundle.quarantine === "object" &&
    appBundle.quarantine.present === true
  );

  let reasonCode = "";
  let summary = "";
  let recommendedNextStep = "";
  if (!binaryPresent) {
    reasonCode = "helper_binary_missing";
    summary = "LM Studio helper binary is missing, so mlx_vlm cannot use the helper bridge.";
    recommendedNextStep = "install_or_restore_lm_studio_helper_binary";
  } else if (!enableLocalService) {
    reasonCode = "helper_local_service_disabled";
    summary = "LM Studio Local Service is disabled in settings, so the helper bridge cannot be used for mlx_vlm require-real.";
    recommendedNextStep = "enable_lm_studio_local_service_then_rerun_require_real_probe";
  } else if (signatureReasonCode === "app_bundle_invalid_signature") {
    reasonCode = "helper_app_bundle_invalid_signature";
    summary =
      "LM Studio app bundle referenced by the selected runtime has an invalid code signature, so the helper local service cannot be trusted to start.";
    recommendedNextStep = "restore_or_reinstall_lm_studio_app_bundle_then_rerun_require_real_probe";
  } else if (signatureReasonCode === "app_bundle_unsigned") {
    reasonCode = "helper_app_bundle_unsigned";
    summary =
      "LM Studio app bundle referenced by the selected runtime is not properly signed, so the helper local service cannot be trusted to start.";
    recommendedNextStep = "restore_or_reinstall_lm_studio_app_bundle_then_rerun_require_real_probe";
  } else if (appFirstLoad && !serverRunning) {
    reasonCode = "helper_app_first_launch_pending";
    summary =
      "LM Studio still reports first-launch state in settings, so the helper local service is not yet operator-ready for mlx_vlm require-real.";
    recommendedNextStep = "complete_lm_studio_first_launch_then_restart_local_service_and_rerun_require_real_probe";
  } else if (daemonRunning && !serverRunning) {
    reasonCode = "helper_server_startup_stalled";
    summary =
      "LM Studio daemon looks partially awake, but the helper local server still is not running, so mlx_vlm cannot complete a real helper-bridge cycle.";
    recommendedNextStep = "repair_lm_studio_local_service_startup_then_rerun_require_real_probe";
  } else if (!serverRunning) {
    reasonCode = "helper_server_not_running";
    summary = "LM Studio helper server is not running, so mlx_vlm cannot complete a real helper-bridge load/bench cycle.";
    recommendedNextStep = "start_lm_studio_local_service_then_rerun_require_real_probe";
  } else {
    summary = "LM Studio helper bridge looks runnable for a real mlx_vlm execution attempt.";
    recommendedNextStep = "attempt_real_mlx_vlm_load_and_bench";
  }

  return {
    daemon_running: daemonRunning,
    server_running: serverRunning,
    reason_code: reasonCode,
    summary,
    recommended_next_step: recommendedNextStep,
    detail_codes: dedupeStrings([
      appFirstLoad ? "app_first_load_pending" : "",
      quarantinePresent ? "app_bundle_quarantined" : "",
      signatureReasonCode,
      daemonRunning && !serverRunning ? "daemon_running_but_server_not_ready" : "",
    ]),
  };
}

function probeHelperBridge(artifactDir, options = {}) {
  const helperBinaryPath = normalizeString(options.helperBinaryPath) || helperBinaryPathDefault;
  const settingsPath = normalizeString(options.settingsPath) || helperSettingsPathDefault;
  const settings = readJSONIfExists(settingsPath) || {};
  const binaryPresent = pathExists(helperBinaryPath);
  const enableLocalService = settings.enableLocalService === true;
  const cliInstalled = settings.cliInstalled === true;
  const appFirstLoad = settings.appFirstLoad === true;

  let daemonStatus = {
    ok: false,
    exit_code: null,
    stdout: "",
    stderr: "",
    timed_out: false,
    error: binaryPresent ? "" : "helper_binary_missing",
    command: [],
    cwd: repoRoot,
    timeout_ms: 8000,
    started_at: isoNow(),
    finished_at: isoNow(),
  };
  let serverStatus = { ...daemonStatus };

  if (binaryPresent) {
    daemonStatus = runCommand(helperBinaryPath, ["daemon", "status"], { timeoutMs: 8000 });
    serverStatus = runCommand(helperBinaryPath, ["server", "status"], { timeoutMs: 8000 });
    persistCommandArtifacts(artifactDir, "helper_daemon_status", daemonStatus);
    persistCommandArtifacts(artifactDir, "helper_server_status", serverStatus);
  }

  const daemonText = [daemonStatus.stdout, daemonStatus.stderr].filter(Boolean).join("\n");
  const serverText = [serverStatus.stdout, serverStatus.stderr].filter(Boolean).join("\n");
  const appBundle = inspectAppBundleHealth(artifactDir, {
    runtimeCommand: options.runtimeCommand,
  });
  const readiness = evaluateHelperBridgeReadiness({
    binaryPresent,
    enableLocalService,
    appFirstLoad,
    daemonText,
    serverText,
    appBundle,
  });

  return {
    helper_binary_path: binaryPresent ? helperBinaryPath : "",
    settings_path: pathExists(settingsPath) ? settingsPath : "",
    binary_present: binaryPresent,
    settings_summary: {
      enable_local_service: enableLocalService,
      cli_installed: cliInstalled,
      app_first_load: appFirstLoad,
      downloads_folder: normalizeString(settings.downloadsFolder),
    },
    daemon_status: {
      ok: daemonStatus.ok,
      exit_code: daemonStatus.exit_code,
      timed_out: daemonStatus.timed_out,
      output_excerpt: normalizeString(daemonText).slice(0, 400),
    },
    server_status: {
      ok: serverStatus.ok,
      exit_code: serverStatus.exit_code,
      timed_out: serverStatus.timed_out,
      output_excerpt: normalizeString(serverText).slice(0, 400),
      running: readiness.server_running,
    },
    app_bundle: appBundle,
    ready_candidate: binaryPresent && enableLocalService && readiness.server_running,
    reason_code: readiness.reason_code,
    summary: readiness.summary,
    recommended_next_step: readiness.recommended_next_step,
    detail_codes: readiness.detail_codes,
    artifact_refs: {
      helper_daemon_status_meta: binaryPresent ? relPath(path.join(artifactDir, "helper_daemon_status.meta.json")) : "",
      helper_server_status_meta: binaryPresent ? relPath(path.join(artifactDir, "helper_server_status.meta.json")) : "",
      ...appBundle.artifact_refs,
    },
    detected_runtime_signals: {
      daemon_running_signal: readiness.daemon_running,
      server_running_signal: readiness.server_running,
    },
  };
}

function evaluateExecutionCapture(capture, normalizedModelDir) {
  if (!capture || typeof capture !== "object") {
    return {
      present: false,
      ready: false,
      reason_code: "real_execution_capture_missing",
      summary: "No real execution capture has been attached yet, so require-real cannot close.",
      detail_codes: ["real_execution_capture_missing"],
    };
  }

  const provider = normalizeString(capture.provider);
  const taskKind = normalizeString(capture.task_kind);
  const captureModelPath = normalizeCatalogModelDir(normalizeString(capture.model_path) || normalizedModelDir);
  const evidenceRefs = Array.isArray(capture.evidence_refs) ? capture.evidence_refs.filter((item) => normalizeString(item)) : [];

  if (!normalizeString(capture.performed_at)) {
    return {
      present: true,
      ready: false,
      reason_code: "capture_performed_at_missing",
      summary: "The capture payload is present but does not record when the real run happened.",
      detail_codes: ["capture_performed_at_missing"],
    };
  }
  if (provider !== "mlx_vlm") {
    return {
      present: true,
      ready: false,
      reason_code: "capture_provider_mismatch",
      summary: "The capture payload is not tagged as mlx_vlm.",
      detail_codes: ["capture_provider_mismatch"],
    };
  }
  if (!["vision_understand", "ocr"].includes(taskKind)) {
    return {
      present: true,
      ready: false,
      reason_code: "capture_task_kind_invalid",
      summary: "The capture payload does not record a mlx_vlm vision/OCR task kind.",
      detail_codes: ["capture_task_kind_invalid"],
    };
  }
  if (normalizedModelDir && captureModelPath && captureModelPath !== normalizedModelDir) {
    return {
      present: true,
      ready: false,
      reason_code: "capture_model_path_mismatch",
      summary: "The capture payload points to a different model directory than the requested mlx_vlm candidate.",
      detail_codes: ["capture_model_path_mismatch"],
    };
  }
  if (!(capture.warmup && capture.warmup.ok === true)) {
    return {
      present: true,
      ready: false,
      reason_code: "real_warmup_missing",
      summary: "The capture payload does not contain a successful real warmup/load step.",
      detail_codes: ["real_warmup_missing"],
    };
  }
  if (!(capture.task && capture.task.ok === true && capture.task.real_runtime_touched === true)) {
    return {
      present: true,
      ready: false,
      reason_code: "real_task_execution_missing",
      summary: "The capture payload does not prove that a real mlx_vlm task execution touched the runtime.",
      detail_codes: ["real_task_execution_missing"],
    };
  }
  if (!(capture.bench && capture.bench.ok === true)) {
    return {
      present: true,
      ready: false,
      reason_code: "real_bench_missing",
      summary: "The capture payload does not contain a successful real quick bench result.",
      detail_codes: ["real_bench_missing"],
    };
  }
  if (!(capture.monitor && capture.monitor.snapshot_captured === true)) {
    return {
      present: true,
      ready: false,
      reason_code: "monitor_snapshot_missing",
      summary: "The capture payload does not contain a runtime monitor snapshot/export.",
      detail_codes: ["monitor_snapshot_missing"],
    };
  }
  if (evidenceRefs.length === 0) {
    return {
      present: true,
      ready: false,
      reason_code: "capture_evidence_refs_missing",
      summary: "The capture payload is missing evidence refs for the real run.",
      detail_codes: ["capture_evidence_refs_missing"],
    };
  }

  return {
    present: true,
    ready: true,
    reason_code: "",
    summary: "The attached capture payload contains real warmup, task, bench, and monitor evidence for mlx_vlm.",
    detail_codes: [],
  };
}

function buildMLXVLMRequireRealReport(input) {
  const generatedAt = normalizeString(input.generatedAt) || isoNow();
  const helperProbe = input.helperProbe || {};
  const modelAssessment = input.modelAssessment || {};
  const loadabilitySummary = summarizeLoadability(input.loadability);
  const captureAssessment = evaluateExecutionCapture(input.capture, input.normalizedModelDir);
  const helperPreflightReady = helperProbe.ready_candidate === true;
  const helperClosureReady = helperPreflightReady || captureAssessment.ready === true;

  const blockers = [];
  if (normalizeString(helperProbe.reason_code) && !captureAssessment.ready) {
    blockers.push({
      layer: "helper_bridge",
      reason_code: normalizeString(helperProbe.reason_code),
      summary: normalizeString(helperProbe.summary),
    });
  }
  if (normalizeString(modelAssessment.reason_code)) {
    blockers.push({
      layer: "model_directory",
      reason_code: normalizeString(modelAssessment.reason_code),
      summary: normalizeString(modelAssessment.summary),
    });
  }
  if (normalizeString(captureAssessment.reason_code)) {
    blockers.push({
      layer: "require_real_capture",
      reason_code: normalizeString(captureAssessment.reason_code),
      summary: normalizeString(captureAssessment.summary),
    });
  }

  const primaryBlocker = blockers[0] || null;
  const gateVerdict = primaryBlocker
    ? "NO_GO(mlx_vlm_require_real_blocked)"
    : "PASS(mlx_vlm_require_real_closure_ready)";
  const modelDirReady = modelAssessment.ready === true;
  const helperReady = helperClosureReady;
  const captureReady = captureAssessment.ready === true;
  const helperReasonCode = normalizeString(helperProbe.reason_code);

  const nextRequiredArtifacts = dedupeStrings([
    !helperPreflightReady && !captureReady && helperReasonCode === "helper_app_bundle_invalid_signature"
      ? "Valid LM Studio app bundle signature for the selected runtime"
      : "",
    !helperPreflightReady && !captureReady && helperReasonCode === "helper_app_first_launch_pending"
      ? "Completed LM Studio first-launch state (`appFirstLoad=false`)"
      : "",
    !helperPreflightReady && !captureReady ? "LM Studio Local Service ready signal (`lms server status` green)" : "",
    !modelDirReady ? "Complete local MLX vision model directory without partial-download artifacts" : "",
    !captureReady ? "Real warmup/task/bench/monitor capture bundle for mlx_vlm" : "",
  ]);

  const nextActions = dedupeStrings([
    !captureReady ? normalizeString(helperProbe.recommended_next_step) : "",
    !modelDirReady ? "complete_or_replace_the_local_mlx_vlm_model_dir_then_rerun_generator" : "",
    !captureReady && helperReady && modelDirReady
      ? "run_real_mlx_vlm_warmup_task_bench_and_monitor_then_attach_capture_json"
      : "",
    `node scripts/generate_lpr_w4_07_b_mlx_vlm_require_real_evidence.js --model-path '${normalizeString(
      input.normalizedModelDir || input.requestedModelPath
    )}'`,
  ]);

  return {
    schema_version: "xhub.lpr_w4_07_b_mlx_vlm_require_real_evidence.v1",
    generated_at: generatedAt,
    updated_at: generatedAt,
    work_order_id: "LPR-W4-07-C",
    historical_script_id: "LPR-W4-07-B",
    scope: "Blocker-aware require-real evidence for mlx_vlm load / task / bench / monitor closure.",
    fail_closed: true,
    target: {
      provider: "mlx_vlm",
      expected_task_kinds: ["vision_understand", "ocr"],
      requested_model_path: normalizeString(input.requestedModelPath),
      normalized_model_dir: normalizeString(input.normalizedModelDir),
      model_dir_exists: input.modelDirExists === true,
      model_dir_looks_like_model: input.modelDirLooksLikeModel === true,
    },
    runtime_resolution: {
      runtime_ready: !!(input.runtimeSelection && input.runtimeSelection.best),
      selected_runtime_id:
        input.runtimeSelection && input.runtimeSelection.best
          ? normalizeString(input.runtimeSelection.best.candidate.runtime_id)
          : "",
      selected_runtime_label:
        input.runtimeSelection && input.runtimeSelection.best
          ? normalizeString(input.runtimeSelection.best.candidate.label)
          : "",
      selected_runtime_command:
        input.runtimeSelection && input.runtimeSelection.best
          ? normalizeString(input.runtimeSelection.best.candidate.command)
          : "",
      runtime_probe_count:
        input.runtimeSelection && Array.isArray(input.runtimeSelection.probes)
          ? input.runtimeSelection.probes.length
          : 0,
    },
    helper_bridge: helperProbe,
    model_directory: {
      assessment: modelAssessment,
      static_markers: input.staticMarkers || null,
      discovery_sources:
        input.discoveredMeta && Array.isArray(input.discoveredMeta.discovery_sources)
          ? input.discoveredMeta.discovery_sources
          : [],
      catalog_entry_refs:
        input.discoveredMeta && Array.isArray(input.discoveredMeta.catalog_entry_refs)
          ? input.discoveredMeta.catalog_entry_refs
          : [],
    },
    native_route_probe: loadabilitySummary,
    execution_capture: {
      assessment: captureAssessment,
      payload: input.capture || null,
    },
    machine_decision: {
      gate_verdict: gateVerdict,
      primary_blocker_layer: primaryBlocker ? primaryBlocker.layer : "",
      primary_blocker_reason_code: primaryBlocker ? primaryBlocker.reason_code : "",
      primary_blocker_summary: primaryBlocker ? primaryBlocker.summary : "",
      blocking_layers: blockers,
      helper_bridge_ready: helperReady,
      model_directory_ready: modelDirReady,
      execution_ready: helperReady && modelDirReady,
      require_real_evidence_complete: helperReady && modelDirReady && captureReady,
      recommended_route: "helper_binary_bridge",
    },
    verdict_reason: primaryBlocker
      ? `mlx_vlm require-real remains blocked at ${primaryBlocker.layer}:${primaryBlocker.reason_code}.`
      : captureReady
        ? "mlx_vlm require-real capture is complete; real execution supersedes stale helper preflight blockers."
        : "mlx_vlm require-real capture is complete and ready for closure review.",
    next_required_artifacts: nextRequiredArtifacts,
    next_actions: nextActions,
    artifact_refs: input.artifactRefs || {},
    command_refs: [
      `node scripts/generate_lpr_w4_07_b_mlx_vlm_require_real_evidence.js --model-path '${normalizeString(
        input.normalizedModelDir || input.requestedModelPath
      )}'`,
      normalizeString(input.capturePath)
        ? `node scripts/generate_lpr_w4_07_b_mlx_vlm_require_real_evidence.js --model-path '${normalizeString(
            input.normalizedModelDir || input.requestedModelPath
          )}' --capture-json '${normalizeString(input.capturePath)}'`
        : "",
      `"${helperBinaryPathDefault}" server status`,
    ].filter(Boolean),
  };
}

function parseArgs(argv) {
  const out = {
    modelPath: "",
    captureJson: "",
    outJson: outputPathDefault,
  };
  const args = Array.isArray(argv) ? argv.slice(2) : [];
  for (let index = 0; index < args.length; index += 1) {
    const token = args[index];
    if (token === "--model-path") {
      out.modelPath = args[index + 1] || "";
      index += 1;
      continue;
    }
    if (token === "--capture-json") {
      out.captureJson = args[index + 1] || "";
      index += 1;
      continue;
    }
    if (token === "--out-json") {
      out.outJson = args[index + 1] || out.outJson;
      index += 1;
      continue;
    }
    if (token === "--help" || token === "-h") {
      process.stdout.write(
        [
          "Usage:",
          "  node scripts/generate_lpr_w4_07_b_mlx_vlm_require_real_evidence.js \\",
          "    [--model-path /absolute/path/to/mlx_vlm_model_dir] \\",
          "    [--capture-json /absolute/path/to/real_capture.json] \\",
          "    [--out-json build/reports/lpr_w4_07_b_mlx_vlm_require_real_evidence.v1.json]",
          "",
        ].join("\n")
      );
      process.exit(0);
    }
  }
  return out;
}

function main() {
  const args = parseArgs(process.argv);
  const requestedModelPath = resolveRequestedModelPath(args.modelPath);
  const normalizedModelDir = normalizeCatalogModelDir(requestedModelPath) || requestedModelPath;
  const modelDirExists = pathExists(normalizedModelDir);
  const modelDirLooksLikeModel = modelDirExists && directoryLooksLikeModel(normalizedModelDir);
  const discoveryInputs = collectModelDiscoveryInputs();
  const discoveredMeta = modelDirLooksLikeModel
    ? resolveKnownModelDiscoveryForPath(normalizedModelDir, discoveryInputs)
    : {
        discovery_sources: [],
        catalog_entry_refs: [],
      };
  const staticMarkers = modelDirLooksLikeModel
    ? buildStaticMarkers(normalizedModelDir, discoveredMeta)
    : null;
  const modelAssessment = detectModelDirIssues(staticMarkers, modelDirExists, modelDirLooksLikeModel);
  const runtimeSelection = chooseReadyRuntime();
  const artifactDir = path.join(artifactRoot, slugForModel(normalizedModelDir));
  safeMkdir(artifactDir);

  let loadability = null;
  const artifactRefs = {};
  if (modelDirLooksLikeModel && runtimeSelection.best) {
    const loadProbe = runNativeLoadabilityProbe(runtimeSelection.best, normalizedModelDir, artifactDir);
    loadability = classifyLoadability(staticMarkers, loadProbe);
    artifactRefs.native_loadability_meta = relPath(path.join(artifactDir, "native_loadability.meta.json"));
    artifactRefs.native_loadability_stdout = relPath(path.join(artifactDir, "native_loadability.stdout.log"));
    artifactRefs.native_loadability_stderr = relPath(path.join(artifactDir, "native_loadability.stderr.log"));
  }

  const helperProbe = probeHelperBridge(artifactDir, {
    runtimeCommand:
      runtimeSelection && runtimeSelection.best ? normalizeString(runtimeSelection.best.candidate.command) : "",
  });
  const capture = readJSONIfExists(args.captureJson);
  const report = buildMLXVLMRequireRealReport({
    generatedAt: isoNow(),
    requestedModelPath,
    normalizedModelDir,
    modelDirExists,
    modelDirLooksLikeModel,
    discoveredMeta,
    staticMarkers,
    modelAssessment,
    runtimeSelection,
    loadability,
    helperProbe,
    capture,
    capturePath: args.captureJson,
    artifactRefs: {
      ...artifactRefs,
      ...helperProbe.artifact_refs,
    },
  });

  safeMkdir(path.dirname(args.outJson));
  writeJSON(args.outJson, report);
  process.stdout.write(`${args.outJson}\n`);
}

module.exports = {
  buildMLXVLMRequireRealReport,
  detectModelDirIssues,
  evaluateHelperBridgeReadiness,
  evaluateExecutionCapture,
  extractAppBundlePathFromRuntimeCommand,
  parseArgs,
  probeHelperBridge,
  summarizeLoadability,
};

if (require.main === module) {
  main();
}
