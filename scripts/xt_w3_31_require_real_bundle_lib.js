#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");

function resolveReportsDir(options = {}) {
  const override = options.reportsDir || process.env.XT_W3_31_REQUIRE_REAL_REPORTS_DIR;
  if (override) {
    return path.resolve(String(override));
  }
  return path.join(repoRoot, "build", "reports");
}

function resolveBundlePath(options = {}) {
  if (options.bundlePath) {
    return path.resolve(String(options.bundlePath));
  }
  return path.join(resolveReportsDir(options), "xt_w3_31_require_real_capture_bundle.v1.json");
}

function resolveRequireRealEvidencePath(options = {}) {
  if (options.reportPath) {
    return path.resolve(String(options.reportPath));
  }
  if (options.bundlePath && !options.reportsDir) {
    return path.join(path.dirname(resolveBundlePath(options)), "xt_w3_31_h_require_real_evidence.v1.json");
  }
  return path.join(resolveReportsDir(options), "xt_w3_31_h_require_real_evidence.v1.json");
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
      sample_id: "xt_spf_rr_01_new_project_visible_within_3s",
      expected_result_summary: "new_project_visible_within_3s",
      precondition: "Hub + XT 已真实配对，且可创建一个新的真实项目。",
      expected_result: "新建真实项目后，Supervisor portfolio 在 3 秒内出现该项目卡片。",
      what_to_capture: [
        "项目创建时间截图或日志",
        "Supervisor 出现该项目卡片的截图",
        "可证明首显时间的录屏、日志或导出",
      ],
      machine_readable_fields_to_record: [
        "project_id",
        "project_name",
        "jurisdiction_role",
        "observed_result",
        "first_visible_latency_ms",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "project_id", not_equals: "" },
        { field: "project_name", not_equals: "" },
        { field: "jurisdiction_role", equals: "owner" },
        { field: "observed_result", not_equals: "" },
        { field: "first_visible_latency_ms", max: 3000 },
      ],
    }),
    sampleTemplate({
      sample_id: "xt_spf_rr_02_blocked_project_emits_brief",
      expected_result_summary: "blocked_project_emits_brief",
      precondition: "至少有一个真实项目能进入 blocked 状态，并被 Supervisor 管辖。",
      expected_result: "项目进入 blocked 后，Supervisor 以 brief_card 级别收到通知，且卡片 current_action/top_blocker 同步更新。",
      what_to_capture: [
        "项目进入 blocked 的真实证据",
        "Supervisor brief 通知截图",
        "项目卡片 current_action / top_blocker 更新截图",
      ],
      machine_readable_fields_to_record: [
        "project_id",
        "blocked_event_seen",
        "brief_notification_emitted",
        "notification_severity",
        "current_action_synced",
        "top_blocker_synced",
        "observed_result",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "project_id", not_equals: "" },
        { field: "blocked_event_seen", equals: true },
        { field: "brief_notification_emitted", equals: true },
        { field: "notification_severity", equals: "brief_card" },
        { field: "current_action_synced", equals: true },
        { field: "top_blocker_synced", equals: true },
        { field: "observed_result", not_equals: "" },
      ],
    }),
    sampleTemplate({
      sample_id: "xt_spf_rr_03_awaiting_authorization_emits_interrupt",
      expected_result_summary: "awaiting_authorization_emits_interrupt",
      precondition: "至少有一个真实项目会进入 awaiting_authorization 的高风险动作路径。",
      expected_result: "进入 awaiting_authorization 后，Supervisor 收到 authorization_required 级别 interrupt，并看得见 why_it_matters 与 next_action。",
      what_to_capture: [
        "项目侧授权前置状态",
        "Supervisor interrupt 截图",
        "why_it_matters / next_action 截图或日志",
      ],
      machine_readable_fields_to_record: [
        "project_id",
        "authorization_state",
        "interrupt_notification_emitted",
        "notification_severity",
        "why_it_matters_present",
        "next_action_present",
        "observed_result",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "project_id", not_equals: "" },
        { field: "authorization_state", equals: "awaiting_authorization" },
        { field: "interrupt_notification_emitted", equals: true },
        { field: "notification_severity", equals: "authorization_required" },
        { field: "why_it_matters_present", equals: true },
        { field: "next_action_present", equals: true },
        { field: "observed_result", not_equals: "" },
      ],
    }),
    sampleTemplate({
      sample_id: "xt_spf_rr_04_completed_project_transitions_cleanly",
      expected_result_summary: "completed_project_transitions_cleanly",
      precondition: "至少有一个真实项目能从进行中进入 completed。",
      expected_result: "项目完成后卡片转 completed，且不残留旧 blocker 或 stale current_action。",
      what_to_capture: [
        "项目完成证据",
        "Supervisor 完成态截图",
        "action feed 或 audit 中 completed 事件证据",
      ],
      machine_readable_fields_to_record: [
        "project_id",
        "project_state",
        "current_action_cleared",
        "top_blocker_cleared",
        "completed_event_logged",
        "observed_result",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "project_id", not_equals: "" },
        { field: "project_state", equals: "completed" },
        { field: "current_action_cleared", equals: true },
        { field: "top_blocker_cleared", equals: true },
        { field: "completed_event_logged", equals: true },
        { field: "observed_result", not_equals: "" },
      ],
    }),
    sampleTemplate({
      sample_id: "xt_spf_rr_05_three_project_burst_has_no_duplicate_interrupt_flood",
      expected_result_summary: "three_project_burst_has_no_duplicate_interrupt_flood",
      precondition: "至少准备三个真实项目，并能在短时间内产生高频状态更新。",
      expected_result: "三项目 burst 下没有 duplicate interrupt flood，且 missed critical event 维持为 0。",
      what_to_capture: [
        "burst 过程录屏或时间戳截图",
        "通知状态线前后对比",
        "delivered / suppressed 计数导出",
      ],
      machine_readable_fields_to_record: [
        "burst_project_count",
        "delivered_interrupt_count",
        "suppressed_interrupt_count",
        "duplicate_interrupt_notification_rate",
        "duplicate_interrupt_flood_detected",
        "missed_critical_event_count",
        "observed_result",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "burst_project_count", min: 3 },
        { field: "duplicate_interrupt_flood_detected", equals: false },
        { field: "missed_critical_event_count", equals: 0 },
        { field: "duplicate_interrupt_notification_rate", max: 0.02 },
        { field: "observed_result", not_equals: "" },
      ],
    }),
    sampleTemplate({
      sample_id: "xt_spf_rr_06_observer_cannot_drilldown_owner_only_project",
      expected_result_summary: "observer_cannot_drilldown_owner_only_project",
      precondition: "准备一个 owner-only 项目，并以 observer jurisdiction 打开 Supervisor。",
      expected_result: "observer 无法 drill-down 到 owner-only 项目，也不会泄露 raw evidence。",
      what_to_capture: [
        "observer 身份或 jurisdiction 截图",
        "deny UI 截图",
        "无 raw evidence 泄露的证明",
      ],
      machine_readable_fields_to_record: [
        "jurisdiction_role",
        "drilldown_denied",
        "owner_only_project_opened",
        "raw_evidence_exposed",
        "deny_reason",
        "observed_result",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "jurisdiction_role", equals: "observer" },
        { field: "drilldown_denied", equals: true },
        { field: "owner_only_project_opened", equals: false },
        { field: "raw_evidence_exposed", equals: false },
        { field: "deny_reason", not_equals: "" },
        { field: "observed_result", not_equals: "" },
      ],
    }),
    sampleTemplate({
      sample_id: "xt_spf_rr_07_stale_capsule_not_promoted_as_fresh",
      expected_result_summary: "stale_capsule_not_promoted_as_fresh",
      precondition: "准备一个会超过 TTL 的真实项目 capsule，并在过期前后分别观察其 freshness。",
      expected_result: "超过 TTL 的 capsule 显示 stale/ttl_cached，不会被 UI 误标成 fresh/latest。",
      what_to_capture: [
        "等待 TTL 前后的同一项目截图",
        "freshness 字段或 UI 标记",
        "可选 drill-down stale 标记截图",
      ],
      machine_readable_fields_to_record: [
        "project_id",
        "memory_freshness",
        "stale_indicator_visible",
        "stale_presented_as_fresh",
        "observed_result",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "project_id", not_equals: "" },
        { field: "memory_freshness", one_of: ["stale", "ttl_cached"] },
        { field: "stale_indicator_visible", equals: true },
        { field: "stale_presented_as_fresh", equals: false },
        { field: "observed_result", not_equals: "" },
      ],
    }),
  ];
}

function buildDefaultCaptureBundle(options = {}) {
  const generatedAt = String(options.generatedAt || isoNow()).trim() || isoNow();
  const samples = defaultSamples();
  return {
    schema_version: "xhub.xt_w3_31_require_real_capture_bundle.v1",
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
  writeJSON,
};
