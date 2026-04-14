#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildMLXVLMRequireRealReport,
  detectModelDirIssues,
  evaluateHelperBridgeReadiness,
  evaluateExecutionCapture,
  extractAppBundlePathFromRuntimeCommand,
} = require("./generate_lpr_w4_07_b_mlx_vlm_require_real_evidence.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("model dir assessment blocks incomplete downloads fail-closed", () => {
  const assessment = detectModelDirIssues(
    {
      file_markers: {
        top_level_files: [
          "config.json",
          "tokenizer.json",
          "downloading_model-00001-of-00004.safetensors.part",
        ],
      },
    },
    true,
    true
  );

  assert.equal(assessment.ready, false);
  assert.equal(assessment.reason_code, "model_dir_incomplete_download");
});

run("execution capture requires warmup task bench and monitor evidence", () => {
  const assessment = evaluateExecutionCapture(
    {
      performed_at: "2026-03-24T12:00:00Z",
      provider: "mlx_vlm",
      task_kind: "vision_understand",
      model_path: "/models/qwen3-vl",
      warmup: { ok: true },
      task: { ok: true, real_runtime_touched: true },
      bench: { ok: false },
      monitor: { snapshot_captured: false },
      evidence_refs: [],
    },
    "/models/qwen3-vl"
  );

  assert.equal(assessment.ready, false);
  assert.equal(assessment.reason_code, "real_bench_missing");
});

run("runtime command can be mapped back to LM Studio app bundle", () => {
  const appBundlePath = extractAppBundlePathFromRuntimeCommand(
    "/Users/andrew.xie/Documents/AX/Opensource/LM Studio.app/Contents/Resources/app/.webpack/bin/extensions/backends/vendor/_amphibian/cpython3.11-mac-arm64@10/bin/python3"
  );

  assert.equal(appBundlePath, "/Users/andrew.xie/Documents/AX/Opensource/LM Studio.app");
});

run("helper readiness fails closed on invalid app signature and does not misread not-running text", () => {
  const readiness = evaluateHelperBridgeReadiness({
    binaryPresent: true,
    enableLocalService: true,
    appFirstLoad: true,
    daemonText: "LM Studio is not running",
    serverText: "The server is not running.",
    appBundle: {
      signature: {
        reason_code: "app_bundle_invalid_signature",
      },
      quarantine: {
        present: true,
      },
    },
  });

  assert.equal(readiness.daemon_running, false);
  assert.equal(readiness.server_running, false);
  assert.equal(readiness.reason_code, "helper_app_bundle_invalid_signature");
  assert.ok(readiness.detail_codes.includes("app_bundle_invalid_signature"));
  assert.ok(readiness.detail_codes.includes("app_bundle_quarantined"));
  assert.ok(readiness.detail_codes.includes("app_first_load_pending"));
});

run("mlx_vlm require-real report fails closed on helper bridge and model blockers", () => {
  const report = buildMLXVLMRequireRealReport({
    generatedAt: "2026-03-24T12:00:00Z",
    requestedModelPath: "/models/qwen3-vl",
    normalizedModelDir: "/models/qwen3-vl",
    modelDirExists: true,
    modelDirLooksLikeModel: true,
    modelAssessment: {
      ready: false,
      reason_code: "model_dir_incomplete_download",
      summary: "The model directory still contains partial download artifacts.",
    },
    runtimeSelection: {
      best: {
        candidate: {
          runtime_id: "lmstudio_cpython311_combo_transformers",
          label: "LM Studio combo runtime",
          command: "/python3",
        },
      },
      probes: [{ ready: true }],
    },
    loadability: {
      verdict: "partially_loadable_metadata_only",
      blocker_reason: "unsupported_quantization_config",
      reasons: ["quantization_config_missing_quant_method"],
      auto_config_ok: true,
      auto_tokenizer_ok: true,
      auto_model_ok: false,
      auto_model_for_causal_lm_ok: false,
    },
    helperProbe: {
      ready_candidate: false,
      reason_code: "helper_local_service_disabled",
      summary: "LM Studio Local Service is disabled.",
      recommended_next_step: "enable_lm_studio_local_service_then_rerun_require_real_probe",
    },
    capture: null,
  });

  assert.equal(report.machine_decision.gate_verdict, "NO_GO(mlx_vlm_require_real_blocked)");
  assert.equal(report.machine_decision.primary_blocker_layer, "helper_bridge");
  assert.equal(report.machine_decision.primary_blocker_reason_code, "helper_local_service_disabled");
  assert.equal(report.machine_decision.execution_ready, false);
  assert.equal(report.native_route_probe.blocker_reason, "unsupported_quantization_config");
  assert.ok(report.next_required_artifacts.includes("LM Studio Local Service ready signal (`lms server status` green)"));
});

run("mlx_vlm require-real report can mark closure ready when preflight and capture are complete", () => {
  const report = buildMLXVLMRequireRealReport({
    generatedAt: "2026-03-24T12:00:00Z",
    requestedModelPath: "/models/qwen3-vl",
    normalizedModelDir: "/models/qwen3-vl",
    modelDirExists: true,
    modelDirLooksLikeModel: true,
    modelAssessment: {
      ready: true,
      reason_code: "",
      summary: "The model directory is locally complete.",
    },
    runtimeSelection: {
      best: {
        candidate: {
          runtime_id: "lmstudio_cpython311_combo_transformers",
          label: "LM Studio combo runtime",
          command: "/python3",
        },
      },
      probes: [{ ready: true }],
    },
    loadability: {
      verdict: "partially_loadable_metadata_only",
      blocker_reason: "unsupported_quantization_config",
      reasons: ["quantization_config_missing_quant_method"],
      auto_config_ok: true,
      auto_tokenizer_ok: true,
      auto_model_ok: false,
      auto_model_for_causal_lm_ok: false,
    },
    helperProbe: {
      ready_candidate: true,
      reason_code: "",
      summary: "Helper bridge is ready.",
      recommended_next_step: "attempt_real_mlx_vlm_load_and_bench",
    },
    capture: {
      performed_at: "2026-03-24T12:05:00Z",
      provider: "mlx_vlm",
      task_kind: "vision_understand",
      model_path: "/models/qwen3-vl",
      warmup: { ok: true },
      task: { ok: true, real_runtime_touched: true },
      bench: { ok: true },
      monitor: { snapshot_captured: true },
      evidence_refs: ["build/reports/mmlx/task.json", "build/reports/mmlx/bench.json"],
    },
  });

  assert.equal(report.machine_decision.gate_verdict, "PASS(mlx_vlm_require_real_closure_ready)");
  assert.equal(report.machine_decision.require_real_evidence_complete, true);
  assert.equal(report.machine_decision.primary_blocker_reason_code, "");
});

run("mlx_vlm require-real report lets real capture override stale helper preflight blockers", () => {
  const report = buildMLXVLMRequireRealReport({
    generatedAt: "2026-03-27T13:00:00Z",
    requestedModelPath: "/models/qwen3-vl",
    normalizedModelDir: "/models/qwen3-vl",
    modelDirExists: true,
    modelDirLooksLikeModel: true,
    modelAssessment: {
      ready: true,
      reason_code: "",
      summary: "The model directory is locally complete.",
    },
    runtimeSelection: {
      best: {
        candidate: {
          runtime_id: "lmstudio_cpython311_combo_transformers",
          label: "LM Studio combo runtime",
          command: "/python3",
        },
      },
      probes: [{ ready: true }],
    },
    loadability: {
      verdict: "partially_loadable_metadata_only",
      blocker_reason: "unsupported_quantization_config",
      reasons: ["quantization_config_missing_quant_method"],
      auto_config_ok: true,
      auto_tokenizer_ok: true,
      auto_model_ok: false,
      auto_model_for_causal_lm_ok: false,
    },
    helperProbe: {
      ready_candidate: false,
      reason_code: "helper_app_bundle_invalid_signature",
      summary: "LM Studio app bundle has an invalid code signature.",
      recommended_next_step: "restore_or_reinstall_lm_studio_app_bundle_then_rerun_require_real_probe",
    },
    capture: {
      performed_at: "2026-03-27T13:05:00Z",
      provider: "mlx_vlm",
      task_kind: "vision_understand",
      model_path: "/models/qwen3-vl",
      warmup: { ok: true },
      task: { ok: true, real_runtime_touched: true },
      bench: { ok: true },
      monitor: { snapshot_captured: true },
      evidence_refs: ["build/reports/mlx_vlm/capture_bundle.json"],
    },
  });

  assert.equal(report.machine_decision.gate_verdict, "PASS(mlx_vlm_require_real_closure_ready)");
  assert.equal(report.machine_decision.helper_bridge_ready, true);
  assert.equal(report.machine_decision.primary_blocker_reason_code, "");
  assert.ok(!report.next_required_artifacts.includes("Valid LM Studio app bundle signature for the selected runtime"));
});

run("mlx_vlm require-real report surfaces app signature blocker artifacts when helper bridge is unhealthy", () => {
  const report = buildMLXVLMRequireRealReport({
    generatedAt: "2026-03-24T12:00:00Z",
    requestedModelPath: "/models/qwen3-vl",
    normalizedModelDir: "/models/qwen3-vl",
    modelDirExists: true,
    modelDirLooksLikeModel: true,
    modelAssessment: {
      ready: false,
      reason_code: "model_dir_incomplete_download",
      summary: "The model directory still contains partial download artifacts.",
    },
    runtimeSelection: {
      best: {
        candidate: {
          runtime_id: "lmstudio_cpython311_combo_transformers",
          label: "LM Studio combo runtime",
          command: "/Users/andrew.xie/Documents/AX/Opensource/LM Studio.app/Contents/Resources/app/.webpack/bin/python3",
        },
      },
      probes: [{ ready: true }],
    },
    loadability: {
      verdict: "partially_loadable_metadata_only",
      blocker_reason: "unsupported_quantization_config",
      reasons: ["quantization_config_missing_quant_method"],
      auto_config_ok: true,
      auto_tokenizer_ok: true,
      auto_model_ok: false,
      auto_model_for_causal_lm_ok: false,
    },
    helperProbe: {
      ready_candidate: false,
      reason_code: "helper_app_bundle_invalid_signature",
      summary: "LM Studio app bundle has an invalid code signature.",
      recommended_next_step: "restore_or_reinstall_lm_studio_app_bundle_then_rerun_require_real_probe",
      app_bundle: {
        app_bundle_path: "/Users/andrew.xie/Documents/AX/Opensource/LM Studio.app",
        bundle_present: true,
        signature: {
          checked: true,
          ok: false,
          reason_code: "app_bundle_invalid_signature",
          output_excerpt: "invalid signature (code or signature have been modified)",
        },
        quarantine: {
          checked: true,
          present: true,
          keys: ["com.apple.macl", "com.apple.quarantine"],
          output_excerpt: "com.apple.quarantine: 0183;...",
        },
      },
      detail_codes: ["app_bundle_invalid_signature", "app_bundle_quarantined", "app_first_load_pending"],
      artifact_refs: {},
    },
    capture: null,
  });

  assert.equal(report.machine_decision.primary_blocker_reason_code, "helper_app_bundle_invalid_signature");
  assert.ok(report.next_required_artifacts.includes("Valid LM Studio app bundle signature for the selected runtime"));
});
