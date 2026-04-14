#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");

function resolveReportsDir(options = {}) {
  const override = options.reportsDir || process.env.XT_W3_33_REQUIRE_REAL_REPORTS_DIR;
  if (override) {
    return path.resolve(String(override));
  }
  return path.join(repoRoot, "build", "reports");
}

function resolveBundlePath(options = {}) {
  if (options.bundlePath) {
    return path.resolve(String(options.bundlePath));
  }
  return path.join(resolveReportsDir(options), "xt_w3_33_h_require_real_capture_bundle.v1.json");
}

function resolveRequireRealEvidencePath(options = {}) {
  if (options.reportPath) {
    return path.resolve(String(options.reportPath));
  }
  if (options.bundlePath && !options.reportsDir) {
    return path.join(path.dirname(resolveBundlePath(options)), "xt_w3_33_h_require_real_evidence.v1.json");
  }
  return path.join(resolveReportsDir(options), "xt_w3_33_h_require_real_evidence.v1.json");
}

function resolveDecisionBlockerAssistEvidencePath(options = {}) {
  return path.join(resolveReportsDir(options), "xt_w3_33_f_decision_blocker_assist_evidence.v1.json");
}

function resolveMemoryCompactionEvidencePath(options = {}) {
  return path.join(resolveReportsDir(options), "xt_w3_33_g_memory_compaction_evidence.v1.json");
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
      sample_id: "xt_w3_33_rr_01_formal_tech_stack_decision_track_persists",
      precondition: "用户在真实运行里明确批准一套技术栈，并允许 Supervisor 写入正式决策轨。",
      expected_result: "产生正式 tech_stack decision track 事件，并把该决策同步进 spec capsule。",
      what_to_capture: [
        "批准动作或正式确认记录",
        "decision track 产物",
        "spec capsule 同步结果",
      ],
      machine_readable_fields_to_record: [
        "decision_track_written",
        "decision_status",
        "decision_category",
        "decision_audit_ref",
        "spec_capsule_sync",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "decision_track_written", equals: true },
        { field: "decision_status", equals: "approved" },
        { field: "decision_category", equals: "tech_stack" },
        { field: "decision_audit_ref", not_equals: "" },
        { field: "spec_capsule_sync", equals: true },
      ],
    }),
    sampleTemplate({
      sample_id: "xt_w3_33_rr_02_background_preference_does_not_override_decision_track",
      precondition: "用户只表达风格偏好，没有正式冻结 UI 方案。",
      expected_result: "偏好写入 background track，但不会覆盖已存在或待定的正式 decision track。",
      what_to_capture: [
        "背景偏好输入",
        "background preference track 记录",
        "decision track 未被覆盖的对照证据",
      ],
      machine_readable_fields_to_record: [
        "background_track_written",
        "background_category",
        "decision_track_unchanged",
        "background_preference_promoted_to_approved",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "background_track_written", equals: true },
        { field: "background_category", equals: "ui_style" },
        { field: "decision_track_unchanged", equals: true },
        { field: "background_preference_promoted_to_approved", equals: false },
      ],
    }),
    sampleTemplate({
      sample_id: "xt_w3_33_rr_03_role_routing_is_explainable_across_roles",
      precondition: "至少执行一轮 scope_freeze、codegen、review、doc、ops 类任务。",
      expected_result: "planner/coder/reviewer/doc/ops 路由均有 explainability 字段，并能解释为什么选择对应角色。",
      what_to_capture: [
        "不同任务类型的路由结果",
        "route explainability 视图或日志",
        "角色覆盖摘要",
      ],
      machine_readable_fields_to_record: [
        "routed_roles",
        "route_count",
        "all_routes_explainable",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "routed_roles", contains_all: ["planner", "coder", "reviewer", "doc", "ops"] },
        { field: "route_count", min: 5 },
        { field: "all_routes_explainable", equals: true },
      ],
    }),
    sampleTemplate({
      sample_id: "xt_w3_33_rr_04_low_risk_default_proposal_stays_pending",
      precondition: "项目因低风险、可逆的 decision blocker 卡住，并允许触发 timeout escalation。",
      expected_result: "生成默认 proposal，必要时触发 timeout escalation，但 assist 不会静默把决策改成 approved。",
      what_to_capture: [
        "decision blocker assist 输出",
        "timeout escalation 触发证据",
        "approval state 仍为 pending 的记录",
      ],
      machine_readable_fields_to_record: [
        "proposal_generated",
        "timeout_escalation_triggered",
        "governance_mode",
        "approval_state",
        "decision_silently_approved",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "proposal_generated", equals: true },
        { field: "timeout_escalation_triggered", equals: true },
        { field: "governance_mode", equals: "proposal_with_timeout_escalation" },
        { field: "approval_state", equals: "proposal_pending" },
        { field: "decision_silently_approved", equals: false },
      ],
    }),
    sampleTemplate({
      sample_id: "xt_w3_33_rr_05_irreversible_decision_requires_authorization",
      precondition: "项目请求 release scope 变更或其他不可逆操作，且需要用户或 Hub 授权。",
      expected_result: "命中 fail-closed，禁止自动采纳，并保留待审批状态。",
      what_to_capture: [
        "高风险 blocker 上下文",
        "fail-closed 结果",
        "authorization requirement 证据",
      ],
      machine_readable_fields_to_record: [
        "fail_closed",
        "requires_hub_authorization",
        "auto_adopt_allowed",
        "approval_state",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "fail_closed", equals: true },
        { field: "requires_hub_authorization", equals: true },
        { field: "auto_adopt_allowed", equals: false },
        { field: "approval_state", equals: "proposal_pending" },
      ],
    }),
    sampleTemplate({
      sample_id: "xt_w3_33_rr_06_dashboard_surfaces_missing_next_step_stalled_zombie",
      precondition: "至少准备一个 missing_next_step、一个 stalled、一个 zombie 项目。",
      expected_result: "Dashboard 能把三类问题直接浮出为 actionable_today，而不是只展示静态状态。",
      what_to_capture: [
        "portfolio overview / today queue 截图或导出",
        "recommended actions 列表",
        "actionability 计数摘要",
      ],
      machine_readable_fields_to_record: [
        "surface_statuses",
        "actionable_today_present",
        "recommended_actions_count",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "surface_statuses", contains_all: ["missing_next_step", "stalled", "zombie"] },
        { field: "actionable_today_present", equals: true },
        { field: "recommended_actions_count", min: 3 },
      ],
    }),
    sampleTemplate({
      sample_id: "xt_w3_33_rr_07_archive_rollup_keeps_traceability_refs",
      precondition: "对已完成项目执行一次真实的 rollup / archive 流程。",
      expected_result: "compaction 后 decision refs、milestone refs、release/gate evidence refs 仍完整可追溯。",
      what_to_capture: [
        "archive/rollup 前后对照",
        "保留的 decision/milestone 标识",
        "release/gate refs 追溯结果",
      ],
      machine_readable_fields_to_record: [
        "decision_node_loss_after_compaction",
        "release_refs_traceable",
        "gate_refs_traceable",
        "kept_decision_ids_count",
        "kept_milestone_ids_count",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "decision_node_loss_after_compaction", equals: 0 },
        { field: "release_refs_traceable", equals: true },
        { field: "gate_refs_traceable", equals: true },
        { field: "kept_decision_ids_count", min: 1 },
        { field: "kept_milestone_ids_count", min: 1 },
      ],
    }),
  ];
}

function buildDefaultCaptureBundle(options = {}) {
  const generatedAt = String(options.generatedAt || isoNow()).trim() || isoNow();
  const samples = defaultSamples();
  return {
    schema_version: "xhub.xt_w3_33_require_real_capture_bundle.v1",
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
  resolveDecisionBlockerAssistEvidencePath,
  resolveMemoryCompactionEvidencePath,
  resolveRequireRealEvidencePath,
  resolveReportsDir,
  writeJSON,
};
