#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const {
  readCaptureBundle,
  resolveBundlePath,
  resolveRequireRealEvidencePath,
} = require("./xt_w3_24_n_whatsapp_cloud_require_real_bundle_lib.js");

const repoRoot = path.resolve(__dirname, "..");

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function isoNow() {
  return new Date().toISOString();
}

function dedupeStrings(values) {
  const seen = new Set();
  const out = [];
  for (const value of values) {
    const trimmed = String(value || "").trim();
    if (!trimmed || seen.has(trimmed)) continue;
    seen.add(trimmed);
    out.push(trimmed);
  }
  return out;
}

function isExecuted(sample) {
  return typeof sample.performed_at === "string" && sample.performed_at.trim() !== "";
}

function hasEvidence(sample) {
  return Array.isArray(sample.evidence_refs) && sample.evidence_refs.length > 0;
}

function isSuccessful(sample) {
  return sample.success_boolean === true;
}

function getByPath(value, dottedPath) {
  const parts = String(dottedPath || "").split(".").filter(Boolean);
  let current = value;
  for (const part of parts) {
    if (current === null || current === undefined) return undefined;
    current = current[part];
  }
  return current;
}

function arraysEqual(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

function evaluateCheck(sample, check) {
  const field = String(check.field || "").trim();
  const actual = getByPath(sample, field);
  if ("equals" in check && !arraysEqual(actual, check.equals)) {
    return `${field} expected ${JSON.stringify(check.equals)} got ${JSON.stringify(actual)}`;
  }
  if ("not_equals" in check && arraysEqual(actual, check.not_equals)) {
    return `${field} must not equal ${JSON.stringify(check.not_equals)}`;
  }
  if (Array.isArray(check.one_of) && !check.one_of.some((value) => arraysEqual(actual, value))) {
    return `${field} expected one_of ${JSON.stringify(check.one_of)} got ${JSON.stringify(actual)}`;
  }
  if (typeof check.min === "number" && !(typeof actual === "number" && actual >= check.min)) {
    return `${field} expected >= ${check.min} got ${JSON.stringify(actual)}`;
  }
  if (typeof check.max === "number" && !(typeof actual === "number" && actual <= check.max)) {
    return `${field} expected <= ${check.max} got ${JSON.stringify(actual)}`;
  }
  if (Array.isArray(check.contains_all)) {
    const haystack = Array.isArray(actual) ? actual : [];
    const missing = check.contains_all.filter((value) => !haystack.includes(value));
    if (missing.length > 0) {
      return `${field} missing ${missing.join(",")}`;
    }
  }
  return "";
}

function syntheticEvidenceReasons(sample) {
  const reasons = [];
  const origin = String(sample.evidence_origin || "").trim().toLowerCase();
  const notes = String(sample.operator_notes || "").trim().toLowerCase();
  const markers = Array.isArray(sample.synthetic_markers) ? sample.synthetic_markers : [];
  if (sample.synthetic_runtime_evidence === true) {
    reasons.push("synthetic_runtime_evidence=true");
  }
  if (markers.length > 0) {
    reasons.push(`synthetic_markers=${markers.join(",")}`);
  }
  for (const text of [origin, notes]) {
    if (!text) continue;
    if (["sample_fixture", "synthetic", "mock", "storybook", "static_story", "offline_story"].some((token) => text.includes(token))) {
      reasons.push(`synthetic_origin=${text}`);
      break;
    }
  }
  return dedupeStrings(reasons);
}

function evaluateSample(sample) {
  const reasons = [];
  const failedChecks = [];
  const syntheticReasons = syntheticEvidenceReasons(sample);
  const requiredChecks = Array.isArray(sample.required_checks) ? sample.required_checks : [];
  const executed = isExecuted(sample);
  const evidencePresent = hasEvidence(sample);
  const successBoolean = isSuccessful(sample);

  if (!executed) reasons.push("performed_at_missing");
  if (!evidencePresent) reasons.push("evidence_refs_missing");
  if (!successBoolean) reasons.push("success_boolean_not_true");
  if (syntheticReasons.length > 0) reasons.push(...syntheticReasons);

  if (executed && evidencePresent && successBoolean) {
    for (const check of requiredChecks) {
      const message = evaluateCheck(sample, check);
      if (message) failedChecks.push(message);
    }
  }
  if (failedChecks.length > 0) reasons.push(...failedChecks.map((message) => `required_check_failed:${message}`));

  return {
    sample_id: sample.sample_id,
    executed,
    evidence_present: evidencePresent,
    success_boolean: successBoolean,
    synthetic_reasons: syntheticReasons,
    failed_checks: failedChecks,
    ok: reasons.length === 0,
    reasons,
  };
}

function sampleSummary(sample, evaluation) {
  return {
    sample_id: sample.sample_id,
    status: sample.status,
    performed_at: sample.performed_at || "",
    success_boolean: sample.success_boolean,
    evidence_refs: Array.isArray(sample.evidence_refs) ? sample.evidence_refs : [],
    synthetic_reasons: evaluation.synthetic_reasons,
    failed_checks: evaluation.failed_checks,
  };
}

function buildRequireRealReport(bundle, options = {}) {
  const generatedAt = options.generatedAt || isoNow();
  const timezone = options.timezone || "Asia/Shanghai";
  const resolvedBundlePath = resolveBundlePath(options);
  const samples = Array.isArray(bundle.samples) ? bundle.samples : [];
  const evaluations = samples.map((sample) => ({
    sample,
    evaluation: evaluateSample(sample),
  }));
  const pendingSamples = evaluations.filter((row) => !row.evaluation.executed).map((row) => row.sample.sample_id);
  const failedSamples = evaluations.filter((row) => row.evaluation.executed && !row.evaluation.success_boolean).map((row) => row.sample.sample_id);
  const invalidSamples = evaluations.filter((row) => row.evaluation.failed_checks.length > 0).map((row) => row.sample.sample_id);
  const syntheticSamples = evaluations.filter((row) => row.evaluation.synthetic_reasons.length > 0).map((row) => row.sample.sample_id);
  const missingEvidenceSamples = evaluations.filter((row) => !row.evaluation.evidence_present).map((row) => row.sample.sample_id);
  const allExecuted = samples.length > 0 && evaluations.every((row) => row.evaluation.executed);
  const allPassed = samples.length > 0 && evaluations.every((row) => row.evaluation.ok);

  let gateVerdict = "NO_GO(require_real_samples_pending)";
  let verdictReason = "XT-W3-24-N WhatsApp Cloud capture bundle 已建立，但仍缺真实 Meta/Hub/XT 执行样本；在无 performed_at / success_boolean=true / evidence_refs 的情况下必须 fail-closed。";
  let releaseStance = "no_go";
  let gateReadinessG4 = "not_ready(whatsapp_cloud_require_real_pending)";
  let gateReadinessG6 = "not_ready(whatsapp_cloud_require_real_pending)";
  let whatsappCloudStage = "p1_release_blocked_require_real_pending";

  if (syntheticSamples.length > 0) {
    gateVerdict = "NO_GO(synthetic_runtime_evidence_not_accepted)";
    verdictReason = `XT-W3-24-N 样本存在 synthetic/mock 痕迹：${syntheticSamples.join(", ")}`;
    gateReadinessG4 = "not_ready(synthetic_runtime_evidence_detected)";
    gateReadinessG6 = "not_ready(synthetic_runtime_evidence_detected)";
  } else if (pendingSamples.length > 0) {
    gateVerdict = "NO_GO(require_real_samples_pending)";
    verdictReason = "XT-W3-24-N WhatsApp Cloud capture bundle 已建立，但仍缺真实 Meta/Hub/XT 执行样本；在无 performed_at / success_boolean=true / evidence_refs 的情况下必须 fail-closed。";
    gateReadinessG4 = "not_ready(whatsapp_cloud_require_real_pending)";
    gateReadinessG6 = "not_ready(whatsapp_cloud_require_real_pending)";
  } else if (failedSamples.length > 0) {
    gateVerdict = "NO_GO(require_real_sample_failed)";
    verdictReason = `XT-W3-24-N 样本存在失败项：${failedSamples.join(", ")}`;
    gateReadinessG4 = "not_ready(require_real_execution_failed)";
    gateReadinessG6 = "not_ready(require_real_execution_failed)";
  } else if (invalidSamples.length > 0) {
    gateVerdict = "NO_GO(machine_readable_assertions_failed)";
    verdictReason = `XT-W3-24-N 样本未满足机读断言：${invalidSamples.join(", ")}`;
    gateReadinessG4 = "not_ready(machine_assertions_failed)";
    gateReadinessG6 = "not_ready(machine_assertions_failed)";
  } else if (missingEvidenceSamples.length > 0) {
    gateVerdict = "NO_GO(require_real_evidence_missing)";
    verdictReason = `XT-W3-24-N 样本缺少 evidence_refs：${missingEvidenceSamples.join(", ")}`;
    gateReadinessG4 = "not_ready(evidence_missing)";
    gateReadinessG6 = "not_ready(evidence_missing)";
  } else if (allExecuted && allPassed) {
    gateVerdict = "PASS(whatsapp_cloud_require_real_samples_executed_and_verified)";
    verdictReason = "XT-W3-24-N WhatsApp Cloud 所有 require-real 样本均已执行、通过机读断言验证，且未出现 synthetic 痕迹。";
    releaseStance = "candidate_go";
    gateReadinessG4 = "candidate_pass(whatsapp_cloud_structured_action_grant_audit_verified)";
    gateReadinessG6 = "candidate_pass(whatsapp_cloud_require_real_verified_personal_qr_still_planned)";
    whatsappCloudStage = "candidate_pass_require_real_verified";
  }

  return {
    schema_version: "xhub.qa_main.xt_w3_24_n_action_grant_whatsapp_evidence.v1",
    generated_at: generatedAt,
    timezone,
    lane: "QA-Main",
    role: "shadow_parallel_qa",
    report_mode: "checklist_delta",
    dispatch_mode: "directed_only_no_broadcast",
    current_slice: "XT-W3-24-N",
    scope: "XT-W3-24-N structured action / grant / audit plane + WhatsApp Cloud require-real",
    fail_closed: true,
    require_real: true,
    synthetic_not_accepted: true,
    gate_verdict: gateVerdict,
    verdict_reason: verdictReason,
    release_stance: releaseStance,
    machine_readable_evidence_present: [
      "build/reports/xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.v1.json",
      "build/reports/xt_w3_24_n_action_grant_whatsapp_evidence.v1.json",
    ],
    governed_action_chain: [
      "structured_action",
      "gate",
      "route",
      "hub_execute",
      "audit",
    ],
    channel_release_freeze: [
      {
        provider: "whatsapp_cloud_api",
        execution_path: "hub_connector",
        require_real_evidence: true,
        release_stage_current: whatsappCloudStage,
        counted_toward_current_report: true,
      },
      {
        provider: "whatsapp_personal_qr",
        execution_path: "trusted_automation_local",
        require_real_evidence: true,
        release_stage_current: "planned_not_release_blocking",
        counted_toward_current_report: false,
      },
    ],
    shadow_checklist: [
      {
        item: "XT-CHAN-OP-G4",
        title: "structured action / grant / audit plane",
        required_gate: "XT-CHAN-OP-G4",
        required_machine_readable_evidence: "build/reports/xt_w3_24_n_action_grant_whatsapp_evidence.v1.json",
        current_status: allPassed
          ? "candidate_pass_whatsapp_cloud_require_real_verified"
          : "capture_bundle_ready_waiting_real_execution",
      },
      {
        item: "XT-CHAN-OP-G6",
        title: "WhatsApp hybrid release freeze",
        required_gate: "XT-CHAN-OP-G6",
        required_machine_readable_evidence: "build/reports/xt_w3_24_n_action_grant_whatsapp_evidence.v1.json",
        current_status: allPassed
          ? "whatsapp_cloud_candidate_pass_personal_qr_still_planned"
          : "whatsapp_cloud_release_blocked_require_real_pending",
      },
    ],
    gate_readiness: {
      "XT-CHAN-OP-G4": gateReadinessG4,
      "XT-CHAN-OP-G6": gateReadinessG6,
    },
    machine_decision: {
      total_samples: samples.length,
      all_samples_executed: allExecuted,
      all_samples_passed: allPassed,
      pending_samples: pendingSamples,
      failed_samples: failedSamples,
      invalid_samples: invalidSamples,
      missing_evidence_samples: missingEvidenceSamples,
      synthetic_samples: syntheticSamples,
    },
    missing_require_real_samples: pendingSamples,
    next_required_artifacts: dedupeStrings(evaluations.flatMap((row) =>
      row.evaluation.reasons.map((reason) => `${row.sample.sample_id}:${reason}`)
    )),
    hard_lines: [
      "hub_first_only_no_direct_xt_im_bypass",
      "hub_raw_ip_must_not_be_exposed_by_default",
      "connector_token_must_remain_narrower_than_admin_token",
      "high_risk_action_must_follow_structured_action_gate_route_hub_execute_audit",
      "whatsapp_personal_qr_must_not_count_toward_whatsapp_cloud_release",
      "synthetic_mock_story_or_fixture_must_not_count_as_require_real_pass",
    ],
    next_owner_lane: allPassed ? "QA-Main" : "XT-L2",
    evidence_refs: [
      "build/reports/xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.v1.json",
      "x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md",
      "x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-hub-security-impact-gate-v1.md",
      "x-hub/grpc-server/hub_grpc_server/README.md",
      "x-hub/grpc-server/hub_grpc_server/src/channel_registry.js",
      "x-hub/grpc-server/hub_grpc_server/src/channel_command_gate.js",
      "x-hub/grpc-server/hub_grpc_server/src/channel_adapters/whatsapp_cloud_api/WhatsAppCloudOperatorWorkerRuntime.js",
      "scripts/generate_xt_w3_24_n_whatsapp_cloud_require_real_report.js",
    ],
    consumed_capture_bundle_path: "build/reports/xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.v1.json",
    consumed_capture_bundle: {
      path: "build/reports/xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.v1.json",
      consumed_at: generatedAt,
      bundle_status: bundle.status || "",
      bundle_generated_at: bundle.generated_at || "",
      execution_order: Array.isArray(bundle.execution_order) ? bundle.execution_order : [],
      stop_on_first_defect: !!bundle.stop_on_first_defect,
      validation: {
        total_samples: samples.length,
        executed_samples: evaluations.filter((row) => row.evaluation.executed).map((row) => row.sample.sample_id),
        pending_samples: pendingSamples,
        failed_samples: failedSamples,
        invalid_samples: invalidSamples,
        synthetic_samples: syntheticSamples,
        sample_summaries: evaluations.map((row) => sampleSummary(row.sample, row.evaluation)),
      },
    },
    shadow_inputs: {
      consumed_capture_bundle_path: path.relative(repoRoot, resolvedBundlePath),
      generated_from: "scripts/generate_xt_w3_24_n_whatsapp_cloud_require_real_report.js",
    },
  };
}

function main() {
  const bundle = readCaptureBundle();
  const output = buildRequireRealReport(bundle);
  const outputPath = resolveRequireRealEvidencePath();
  writeJSON(outputPath, output);
  process.stdout.write(`${outputPath}\n`);
}

module.exports = {
  buildRequireRealReport,
  evaluateCheck,
  evaluateSample,
  readJSON,
  sampleSummary,
  syntheticEvidenceReasons,
  writeJSON,
};

if (require.main === module) {
  main();
}
