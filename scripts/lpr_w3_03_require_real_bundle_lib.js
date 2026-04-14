#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");

function resolveReportsDir(options = {}) {
  const override = options.reportsDir || process.env.LPR_W3_03_REQUIRE_REAL_REPORTS_DIR;
  if (override) {
    return path.resolve(String(override));
  }
  return path.join(repoRoot, "build", "reports");
}

function resolveBundlePath(options = {}) {
  if (options.bundlePath) {
    return path.resolve(String(options.bundlePath));
  }
  return path.join(resolveReportsDir(options), "lpr_w3_03_require_real_capture_bundle.v1.json");
}

function resolveRequireRealEvidencePath(options = {}) {
  if (options.reportPath) {
    return path.resolve(String(options.reportPath));
  }
  if (options.bundlePath && !options.reportsDir) {
    return path.join(path.dirname(resolveBundlePath(options)), "lpr_w3_03_a_require_real_evidence.v1.json");
  }
  return path.join(resolveReportsDir(options), "lpr_w3_03_a_require_real_evidence.v1.json");
}

function resolveRuntimeProbePath(options = {}) {
  return path.join(resolveReportsDir(options), "lpr_w3_03_b_runtime_candidate_probe.v1.json");
}

function resolveModelProbePath(options = {}) {
  return path.join(resolveReportsDir(options), "lpr_w3_03_c_model_native_loadability_probe.v1.json");
}

function resolveHelperProbePath(options = {}) {
  return path.join(resolveReportsDir(options), "lpr_w3_03_d_helper_bridge_probe.v1.json");
}

const reportsDir = resolveReportsDir();
const bundlePath = resolveBundlePath();

function isoNow() {
  return new Date().toISOString();
}

function sampleTemplate(overrides) {
  return {
    status: "pending",
    performed_at: "",
    success_boolean: null,
    evidence_refs: [],
    operator_notes: "",
    evidence_origin: "",
    synthetic_runtime_evidence: false,
    synthetic_markers: [],
    ...overrides,
  };
}

function defaultSamples() {
  return [
    sampleTemplate({
      sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
      precondition: "至少存在一条真实本地 embedding 模型目录，且使用真实文本输入工件。",
      expected_result: "真实 embedding 模型目录完成一次真实本地执行，不接受 synthetic/mock/storyboard 代替。",
      what_to_capture: [
        "Hub 模型卡片或导入结果",
        "真实输入文本工件",
        "runtime monitor / diagnostics export",
        "route / load-profile 证据",
      ],
      machine_readable_fields_to_record: [
        "provider",
        "task_kind",
        "model_id",
        "model_path",
        "device_id",
        "route_source",
        "load_profile_hash",
        "effective_context_length",
        "input_artifact_ref",
        "vector_count",
        "latency_ms",
        "monitor_snapshot_captured",
        "diagnostics_export_captured",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "provider", equals: "transformers" },
        { field: "task_kind", equals: "embedding" },
        { field: "model_path", not_equals: "" },
        { field: "device_id", not_equals: "" },
        { field: "route_source", not_equals: "" },
        { field: "load_profile_hash", not_equals: "" },
        { field: "effective_context_length", min: 1 },
        { field: "input_artifact_ref", not_equals: "" },
        { field: "vector_count", min: 1 },
        { field: "monitor_snapshot_captured", equals: true },
        { field: "diagnostics_export_captured", equals: true },
      ],
    }),
    sampleTemplate({
      sample_id: "lpr_rr_02_asr_real_model_dir_executes",
      precondition: "至少存在一条真实本地 ASR 模型目录，且使用真实音频工件。",
      expected_result: "真实 ASR 模型目录完成一次真实音频转写，并留下 transcript 摘要与运行态证据。",
      what_to_capture: [
        "Hub 模型卡片或导入结果",
        "真实音频工件副本",
        "transcript 结果摘要",
        "runtime monitor / diagnostics export",
      ],
      machine_readable_fields_to_record: [
        "provider",
        "task_kind",
        "model_id",
        "model_path",
        "device_id",
        "route_source",
        "load_profile_hash",
        "effective_context_length",
        "input_artifact_ref",
        "transcript_char_count",
        "segment_count",
        "latency_ms",
        "monitor_snapshot_captured",
        "diagnostics_export_captured",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "provider", equals: "transformers" },
        { field: "task_kind", equals: "speech_to_text" },
        { field: "model_path", not_equals: "" },
        { field: "device_id", not_equals: "" },
        { field: "route_source", not_equals: "" },
        { field: "load_profile_hash", not_equals: "" },
        { field: "effective_context_length", min: 1 },
        { field: "input_artifact_ref", not_equals: "" },
        { field: "transcript_char_count", min: 1 },
        { field: "segment_count", min: 1 },
        { field: "monitor_snapshot_captured", equals: true },
        { field: "diagnostics_export_captured", equals: true },
      ],
    }),
    sampleTemplate({
      sample_id: "lpr_rr_03_vision_real_model_dir_exercised",
      precondition: "至少存在一条真实本地 vision 模型目录，或至少能把真实图像路径跑到明确 fail-closed 结果。",
      expected_result: "真实 vision 图像路径被实际演练；W3 阶段允许 ran 或 fail_closed，但必须保留精确 root-cause。",
      what_to_capture: [
        "Hub 模型卡片或导入结果",
        "真实图像工件副本",
        "bench/task 结果摘要",
        "runtime monitor / diagnostics export",
      ],
      machine_readable_fields_to_record: [
        "provider",
        "task_kind",
        "model_id",
        "model_path",
        "device_id",
        "route_source",
        "load_profile_hash",
        "effective_context_length",
        "input_artifact_ref",
        "outcome_kind",
        "outcome_summary",
        "reason_code",
        "real_runtime_touched",
        "latency_ms",
        "monitor_snapshot_captured",
        "diagnostics_export_captured",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "provider", equals: "transformers" },
        { field: "task_kind", one_of: ["vision_understand", "ocr"] },
        { field: "model_path", not_equals: "" },
        { field: "device_id", not_equals: "" },
        { field: "route_source", not_equals: "" },
        { field: "load_profile_hash", not_equals: "" },
        { field: "effective_context_length", min: 1 },
        { field: "input_artifact_ref", not_equals: "" },
        { field: "outcome_kind", one_of: ["ran", "fail_closed"] },
        { field: "outcome_summary", not_equals: "" },
        { field: "reason_code", not_equals: "" },
        { field: "real_runtime_touched", equals: true },
        { field: "monitor_snapshot_captured", equals: true },
        { field: "diagnostics_export_captured", equals: true },
      ],
    }),
    sampleTemplate({
      sample_id: "lpr_rr_04_doctor_and_release_export_match_real_runs",
      precondition: "前三个真实样本至少已有运行态证据可比对。",
      expected_result: "doctor / operator summary / export 复用与前三个真实样本同一份运行态真相，不发生口径漂移。",
      what_to_capture: [
        "provider summary / diagnostics export",
        "runtime monitor snapshot export",
        "一份 release hint 或 support summary（推荐 `build/reports/xhub_local_service_operator_recovery_report.v1.json`）",
      ],
      machine_readable_fields_to_record: [
        "provider_summary_export_ref",
        "monitor_snapshot_export_ref",
        "release_hint_ref",
        "covered_task_kinds",
        "runtime_truth_shared",
        "doctor_export_matches_real_runs",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "provider_summary_export_ref", not_equals: "" },
        { field: "monitor_snapshot_export_ref", not_equals: "" },
        { field: "release_hint_ref", not_equals: "" },
        { field: "covered_task_kinds", contains_all: ["embedding", "speech_to_text", "vision_understand"] },
        { field: "runtime_truth_shared", equals: true },
        { field: "doctor_export_matches_real_runs", equals: true },
      ],
    }),
  ];
}

function buildDefaultCaptureBundle(options = {}) {
  const generatedAt = String(options.generatedAt || isoNow()).trim() || isoNow();
  const samples = defaultSamples();
  return {
    schema_version: "xhub.lpr_w3_03_require_real_capture_bundle.v1",
    generated_at: generatedAt,
    updated_at: generatedAt,
    status: "ready_for_execution",
    stop_on_first_defect: true,
    execution_order: samples.map((sample) => sample.sample_id),
    samples,
  };
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function ensureCaptureBundleFile(options = {}) {
  const targetBundlePath = resolveBundlePath(options);
  if (!fs.existsSync(targetBundlePath)) {
    writeJSON(targetBundlePath, buildDefaultCaptureBundle(options));
    return { created: true, bundlePath: targetBundlePath };
  }
  return { created: false, bundlePath: targetBundlePath };
}

function readCaptureBundle(options = {}) {
  const state = ensureCaptureBundleFile(options);
  return JSON.parse(fs.readFileSync(state.bundlePath, "utf8"));
}

module.exports = {
  buildDefaultCaptureBundle,
  bundlePath,
  ensureCaptureBundleFile,
  readCaptureBundle,
  repoRoot,
  reportsDir,
  resolveBundlePath,
  resolveReportsDir,
  resolveRequireRealEvidencePath,
  resolveRuntimeProbePath,
  resolveModelProbePath,
  resolveHelperProbePath,
  writeJSON,
};
