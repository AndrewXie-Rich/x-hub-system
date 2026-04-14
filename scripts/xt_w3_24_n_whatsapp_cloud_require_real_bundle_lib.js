#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");

function resolveReportsDir(options = {}) {
  const override = options.reportsDir || process.env.XT_W3_24_N_REQUIRE_REAL_REPORTS_DIR;
  if (override) {
    return path.resolve(String(override));
  }
  return path.join(repoRoot, "build", "reports");
}

function resolveBundlePath(options = {}) {
  if (options.bundlePath) {
    return path.resolve(String(options.bundlePath));
  }
  return path.join(resolveReportsDir(options), "xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.v1.json");
}

function resolveRequireRealEvidencePath(options = {}) {
  if (options.reportPath) {
    return path.resolve(String(options.reportPath));
  }
  if (options.bundlePath && !options.reportsDir) {
    return path.join(path.dirname(resolveBundlePath(options)), "xt_w3_24_n_action_grant_whatsapp_evidence.v1.json");
  }
  return path.join(resolveReportsDir(options), "xt_w3_24_n_action_grant_whatsapp_evidence.v1.json");
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
      sample_id: "xt_w3_24_n_rr_01_status_query_is_hub_only_and_audited",
      expected_result_summary: "status_query_is_hub_only_and_audited",
      precondition: "真实 WhatsApp Cloud operator 线程已绑定到真实项目，且可发送一次真实状态查询。",
      expected_result: "supervisor.status.get 走 Hub-only status 路径返回真实回复，不触发 XT/device side effect，且审计链完整。",
      what_to_capture: [
        "WhatsApp Cloud 真实入站消息",
        "Hub 返回给该线程的真实状态回复",
        "route/audit snapshot 或等价导出",
      ],
      machine_readable_fields_to_record: [
        "provider",
        "structured_action_name",
        "route_mode",
        "project_binding_enforced",
        "provider_reply_mode",
        "side_effect_executed",
        "audit_chain_complete",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "provider", equals: "whatsapp_cloud_api" },
        { field: "structured_action_name", equals: "supervisor.status.get" },
        { field: "route_mode", equals: "hub_only_status" },
        { field: "project_binding_enforced", equals: true },
        { field: "provider_reply_mode", one_of: ["text_only", "interactive_text"] },
        { field: "side_effect_executed", equals: false },
        { field: "audit_chain_complete", equals: true },
      ],
    }),
    sampleTemplate({
      sample_id: "xt_w3_24_n_rr_02_deploy_execute_stays_pending_until_grant_approval",
      expected_result_summary: "deploy_execute_stays_pending_until_grant_approval",
      precondition: "真实 WhatsApp Cloud operator 线程对真实项目发起一次 deploy.execute，且事前没有 grant 通过。",
      expected_result: "请求进入 governed pending_grant 状态；在明确 grant.approve 前不得产生高风险 side effect。",
      what_to_capture: [
        "高风险 deploy.execute 真实入站消息",
        "pending grant 证据",
        "action/audit 状态或 route snapshot",
      ],
      machine_readable_fields_to_record: [
        "provider",
        "structured_action_name",
        "project_binding_enforced",
        "governance_mode",
        "grant_state",
        "side_effect_executed",
        "audit_chain_complete",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "provider", equals: "whatsapp_cloud_api" },
        { field: "structured_action_name", equals: "deploy.execute" },
        { field: "project_binding_enforced", equals: true },
        { field: "governance_mode", equals: "pending_grant" },
        { field: "grant_state", equals: "pending" },
        { field: "side_effect_executed", equals: false },
        { field: "audit_chain_complete", equals: true },
      ],
    }),
    sampleTemplate({
      sample_id: "xt_w3_24_n_rr_03_deploy_plan_routes_project_first_to_preferred_xt",
      expected_result_summary: "deploy_plan_routes_project_first_to_preferred_xt",
      precondition: "真实项目已绑定首选 XT 设备，且 WhatsApp Cloud 线程可发起 deploy.plan。",
      expected_result: "deploy.plan 保持 project-first，经 Hub 路由到首选 XT，结果为 prepared/queued，且不会直接产生 side effect。",
      what_to_capture: [
        "deploy.plan 真实入站消息",
        "route 结果或 XT queue snapshot",
        "prepared/queued 回复与审计导出",
      ],
      machine_readable_fields_to_record: [
        "provider",
        "structured_action_name",
        "project_binding_enforced",
        "route_mode",
        "resolved_device_id",
        "execution_disposition",
        "side_effect_executed",
        "audit_chain_complete",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "provider", equals: "whatsapp_cloud_api" },
        { field: "structured_action_name", equals: "deploy.plan" },
        { field: "project_binding_enforced", equals: true },
        { field: "route_mode", equals: "hub_to_xt" },
        { field: "resolved_device_id", not_equals: "" },
        { field: "execution_disposition", one_of: ["prepared", "queued"] },
        { field: "side_effect_executed", equals: false },
        { field: "audit_chain_complete", equals: true },
      ],
    }),
    sampleTemplate({
      sample_id: "xt_w3_24_n_rr_04_grant_approve_requires_pending_scope_match",
      expected_result_summary: "grant_approve_requires_pending_scope_match",
      precondition: "真实线程中已经有一个 pending grant，且该 grant 属于当前项目 scope。",
      expected_result: "grant.approve 只能消费同 scope 的 pending grant，保留 action 审计引用并完成批准动作审计。",
      what_to_capture: [
        "grant.approve 真实入站消息",
        "pending grant 与 scope 对应关系证据",
        "批准结果与 action audit 导出",
      ],
      machine_readable_fields_to_record: [
        "provider",
        "structured_action_name",
        "pending_grant_owned_by_scope",
        "grant_scope_matched",
        "grant_decision",
        "action_audit_ref",
        "audit_chain_complete",
        "evidence_origin",
        "synthetic_runtime_evidence",
        "synthetic_markers",
      ],
      required_checks: [
        { field: "provider", equals: "whatsapp_cloud_api" },
        { field: "structured_action_name", equals: "grant.approve" },
        { field: "pending_grant_owned_by_scope", equals: true },
        { field: "grant_scope_matched", equals: true },
        { field: "grant_decision", equals: "approved" },
        { field: "action_audit_ref", not_equals: "" },
        { field: "audit_chain_complete", equals: true },
      ],
    }),
  ];
}

function buildDefaultCaptureBundle(options = {}) {
  const generatedAt = String(options.generatedAt || isoNow()).trim() || isoNow();
  const samples = defaultSamples();
  return {
    schema_version: "xhub.xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.v1",
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
