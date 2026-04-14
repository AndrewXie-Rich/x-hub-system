#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const {
  readCaptureBundle,
  repoRoot,
  resolveHelperProbePath,
  resolveModelProbePath,
  resolveReportsDir,
  resolveRequireRealEvidencePath,
  resolveRuntimeProbePath,
  writeJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");
const {
  buildSample1OperatorHandoff,
  buildSample1UnblockSummary,
  compactSample1HelperProbe,
  compactSample1ModelProbe,
  compactSample1RuntimeProbe,
  selectPreferredSample1Shortlist,
} = require("./lpr_w3_03_require_real_status.js");

const SAMPLE1_OPERATOR_HANDOFF_REF = "build/reports/lpr_w3_03_sample1_operator_handoff.v1.json";
const SAMPLE1_CANDIDATE_SHORTLIST_REF = "build/reports/lpr_w3_03_sample1_candidate_shortlist.v1.json";
const SAMPLE1_CANDIDATE_WIDE_SHORTLIST_REF =
  "build/reports/lpr_w3_03_sample1_candidate_shortlist.wide_scan.v1.json";
const SAMPLE1_HELPER_LOCAL_SERVICE_RECOVERY_REF =
  "build/reports/lpr_w3_03_sample1_helper_local_service_recovery.v1.json";
const SAMPLE1_CANDIDATE_ACCEPTANCE_REF = "build/reports/lpr_w3_03_sample1_candidate_acceptance.v1.json";
const SAMPLE1_CANDIDATE_REGISTRATION_REF = "build/reports/lpr_w3_03_sample1_candidate_registration_packet.v1.json";
const SAMPLE1_CANDIDATE_CATALOG_PATCH_PLAN_REF =
  "build/reports/lpr_w3_03_sample1_candidate_catalog_patch_plan.v1.json";

const PREREQUISITE_EVIDENCE = [
  {
    path: "build/reports/lpr_w2_01_a_embedding_contract_evidence.v1.json",
    label: "embedding contract",
    gates: ["LPR-G2"],
  },
  {
    path: "build/reports/lpr_w2_02_a_asr_contract_evidence.v1.json",
    label: "asr contract",
    gates: ["LPR-G3"],
  },
  {
    path: "build/reports/lpr_w3_01_a_vision_preview_contract_evidence.v1.json",
    label: "vision preview contract",
    gates: ["LPR-G4"],
  },
  {
    path: "build/reports/lpr_w3_05_d_resident_runtime_proxy_evidence.v1.json",
    label: "resident lifecycle proxy",
    gates: ["LPR-G5"],
  },
  {
    path: "build/reports/lpr_w3_06_d_bench_fixture_pack_evidence.v1.json",
    label: "bench fixture pack",
    gates: ["LPR-G5"],
  },
  {
    path: "build/reports/lpr_w3_07_c_monitor_export_evidence.v1.json",
    label: "monitor export",
    gates: ["LPR-G5"],
  },
  {
    path: "build/reports/lpr_w3_08_c_task_resolution_evidence.v1.json",
    label: "task routing resolution",
    gates: ["LPR-G5"],
  },
];

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readJSONIfExists(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    return readJSON(filePath);
  } catch {
    return null;
  }
}

function isoNow() {
  return new Date().toISOString();
}

function normalizeString(value) {
  return String(value || "").trim();
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

function resolveEvidenceRefPath(refPath, options = {}) {
  const normalized = String(refPath || "").trim();
  if (!normalized) {
    return path.join(resolveReportsDir(options), "__invalid_missing_path__");
  }
  const prefix = "build/reports/";
  if (normalized.startsWith(prefix)) {
    return path.join(resolveReportsDir(options), normalized.slice(prefix.length));
  }
  return path.join(repoRoot, normalized);
}

function resolveReportRef(filePath) {
  return path.relative(repoRoot, filePath).split(path.sep).join("/");
}

function findSampleById(samples, sampleId) {
  return samples.find((sample) => normalizeString(sample.sample_id) === sampleId) || null;
}

function collectPrerequisites(options = {}) {
  const overrides = options.prerequisitePresence || {};
  return PREREQUISITE_EVIDENCE.map((item) => {
    const present = Object.prototype.hasOwnProperty.call(overrides, item.path)
      ? overrides[item.path] === true
      : fs.existsSync(resolveEvidenceRefPath(item.path, options));
    return {
      ...item,
      present,
    };
  });
}

function buildSample1RequireRealSupport(samples, options = {}) {
  const runtimeProbePath = resolveRuntimeProbePath(options);
  const modelProbePath = resolveModelProbePath(options);
  const helperProbePath = resolveHelperProbePath(options);
  const runtimeProbeReport = options.runtimeProbe === undefined
    ? readJSONIfExists(runtimeProbePath)
    : options.runtimeProbe;
  const modelProbeReport = options.modelProbe === undefined
    ? readJSONIfExists(modelProbePath)
    : options.modelProbe;
  const helperProbeReport = options.helperProbe === undefined
    ? readJSONIfExists(helperProbePath)
    : options.helperProbe;
  const candidateShortlistDefaultReport = options.candidateShortlist === undefined
    ? readJSONIfExists(resolveEvidenceRefPath(SAMPLE1_CANDIDATE_SHORTLIST_REF, options))
    : options.candidateShortlist;
  const candidateShortlistWideReport = options.candidateShortlistWide === undefined
    ? readJSONIfExists(resolveEvidenceRefPath(SAMPLE1_CANDIDATE_WIDE_SHORTLIST_REF, options))
    : options.candidateShortlistWide;
  const candidateShortlistReport = selectPreferredSample1Shortlist(
    candidateShortlistDefaultReport,
    candidateShortlistWideReport
  );
  const helperLocalServiceRecoveryReport = options.helperLocalServiceRecovery === undefined
    ? readJSONIfExists(resolveEvidenceRefPath(SAMPLE1_HELPER_LOCAL_SERVICE_RECOVERY_REF, options))
    : options.helperLocalServiceRecovery;
  const candidateAcceptanceReport = options.candidateAcceptance === undefined
    ? readJSONIfExists(resolveEvidenceRefPath(SAMPLE1_CANDIDATE_ACCEPTANCE_REF, options))
    : options.candidateAcceptance;
  const candidateRegistrationReport = options.candidateRegistration === undefined
    ? readJSONIfExists(resolveEvidenceRefPath(SAMPLE1_CANDIDATE_REGISTRATION_REF, options))
    : options.candidateRegistration;
  const sample1RuntimeProbe = compactSample1RuntimeProbe(runtimeProbeReport);
  const sample1ModelProbe = compactSample1ModelProbe(modelProbeReport);
  const sample1HelperProbe = compactSample1HelperProbe(helperProbeReport);
  const sample1ReferenceSample = findSampleById(samples, "lpr_rr_01_embedding_real_model_dir_executes");
  const sample1UnblockSummary =
    sample1RuntimeProbe || sample1ModelProbe || sample1HelperProbe
      ? buildSample1UnblockSummary({
          runtimeProbe: sample1RuntimeProbe,
          modelProbe: sample1ModelProbe,
          helperProbe: sample1HelperProbe,
          sample: sample1ReferenceSample,
          candidateShortlist: candidateShortlistReport,
          candidateRegistration: candidateRegistrationReport,
        })
      : null;
  const sample1OperatorHandoff = sample1UnblockSummary
    ? buildSample1OperatorHandoff({
        runtimeProbe: sample1RuntimeProbe,
        modelProbe: modelProbeReport,
        helperProbe: sample1HelperProbe,
        sample: sample1ReferenceSample,
        unblockSummary: sample1UnblockSummary,
        candidateShortlist: candidateShortlistReport,
        candidateAcceptance: candidateAcceptanceReport,
        candidateRegistration: candidateRegistrationReport,
        helperLocalServiceRecovery: helperLocalServiceRecoveryReport,
      })
    : null;
  const operatorHandoffPresent = fs.existsSync(resolveEvidenceRefPath(SAMPLE1_OPERATOR_HANDOFF_REF, options));
  const helperLocalServiceRecoveryPresent =
    helperLocalServiceRecoveryReport !== null
      || fs.existsSync(resolveEvidenceRefPath(SAMPLE1_HELPER_LOCAL_SERVICE_RECOVERY_REF, options));
  const candidateAcceptancePresent =
    candidateAcceptanceReport !== null
      || fs.existsSync(resolveEvidenceRefPath(SAMPLE1_CANDIDATE_ACCEPTANCE_REF, options));
  const candidateRegistrationPresent =
    candidateRegistrationReport !== null
      || fs.existsSync(resolveEvidenceRefPath(SAMPLE1_CANDIDATE_REGISTRATION_REF, options));
  const candidateCatalogPatchPlanPresent = fs.existsSync(
    resolveEvidenceRefPath(SAMPLE1_CANDIDATE_CATALOG_PATCH_PLAN_REF, options)
  ) || !!(
    candidateRegistrationReport
    && candidateRegistrationReport.catalog_patch_plan_summary
    && typeof candidateRegistrationReport.catalog_patch_plan_summary === "object"
  );

  return {
    sample_id: sample1ReferenceSample
      ? sample1ReferenceSample.sample_id
      : "lpr_rr_01_embedding_real_model_dir_executes",
    runtime_probe_ref: resolveReportRef(runtimeProbePath),
    model_probe_ref: resolveReportRef(modelProbePath),
    helper_probe_ref: resolveReportRef(helperProbePath),
    runtime_probe_present: !!runtimeProbeReport,
    model_probe_present: !!modelProbeReport,
    helper_probe_present: !!helperProbeReport,
    operator_handoff_ref: SAMPLE1_OPERATOR_HANDOFF_REF,
    operator_handoff_present: operatorHandoffPresent,
    helper_local_service_recovery_ref: SAMPLE1_HELPER_LOCAL_SERVICE_RECOVERY_REF,
    helper_local_service_recovery_present: helperLocalServiceRecoveryPresent,
    candidate_acceptance_ref: SAMPLE1_CANDIDATE_ACCEPTANCE_REF,
    candidate_acceptance_present: candidateAcceptancePresent,
    candidate_registration_ref: SAMPLE1_CANDIDATE_REGISTRATION_REF,
    candidate_registration_present: candidateRegistrationPresent,
    candidate_catalog_patch_plan_ref: SAMPLE1_CANDIDATE_CATALOG_PATCH_PLAN_REF,
    candidate_catalog_patch_plan_present: candidateCatalogPatchPlanPresent,
    runtime_probe: sample1RuntimeProbe,
    model_probe: sample1ModelProbe,
    helper_probe: sample1HelperProbe,
    unblock_summary: sample1UnblockSummary,
    operator_handoff: sample1OperatorHandoff,
    helper_local_service_recovery_packet: helperLocalServiceRecoveryReport,
    candidate_acceptance_packet: candidateAcceptanceReport,
    candidate_registration_packet: candidateRegistrationReport,
  };
}

function buildSample1BlockerNote(sample1Support = null) {
  if (!sample1Support || !sample1Support.unblock_summary) return "";
  const summary = sample1Support.unblock_summary;
  const helperLocalServiceRecovery = sample1Support.helper_local_service_recovery_packet || null;
  const candidateRegistration = sample1Support.candidate_registration_packet || null;
  const parts = [];
  const blockers = Array.isArray(summary.current_blockers) ? summary.current_blockers : [];
  const missingProbeRefs = [
    !sample1Support.runtime_probe_present ? sample1Support.runtime_probe_ref : "",
    !sample1Support.model_probe_present ? sample1Support.model_probe_ref : "",
    !sample1Support.helper_probe_present ? sample1Support.helper_probe_ref : "",
  ].filter(Boolean);

  if (blockers.length > 0) parts.push(`blockers=${blockers.join(" | ")}`);
  if (normalizeString(summary.overall_recommended_action_id)) {
    parts.push(`recommended_action=${summary.overall_recommended_action_id}`);
  }
  if (summary.preferred_route && !summary.preferred_route.ready && normalizeString(summary.preferred_route.next_step)) {
    parts.push(`primary_route_next_step=${summary.preferred_route.next_step}`);
  }
  if (summary.secondary_route && !summary.secondary_route.ready && normalizeString(summary.secondary_route.next_step)) {
    parts.push(`secondary_route_next_step=${summary.secondary_route.next_step}`);
  }
  if (
    candidateRegistration &&
    normalizeString(candidateRegistration.machine_decision?.top_recommended_action?.action_id)
  ) {
    parts.push(`registration_action=${candidateRegistration.machine_decision.top_recommended_action.action_id}`);
  }
  if (
    helperLocalServiceRecovery &&
    normalizeString(helperLocalServiceRecovery.top_recommended_action?.action_id)
  ) {
    parts.push(`helper_action=${helperLocalServiceRecovery.top_recommended_action.action_id}`);
  }
  if (missingProbeRefs.length > 0) {
    parts.push(`missing_probe_support=${missingProbeRefs.join(" | ")}`);
  }

  return parts.length > 0 ? ` 当前 sample1 解阻事实：${parts.join("; ")}。` : "";
}

function buildSample1NextRequiredItems(sample1Support = null) {
  if (!sample1Support || !sample1Support.unblock_summary) return [];
  const summary = sample1Support.unblock_summary;
  const operatorHandoff = sample1Support.operator_handoff || null;
  const helperLocalServiceRecovery = sample1Support.helper_local_service_recovery_packet || null;
  const candidateAcceptance = sample1Support.candidate_acceptance_packet || null;
  const candidateRegistration = sample1Support.candidate_registration_packet || null;
  const items = [
    !sample1Support.runtime_probe_present
      ? `generate sample1 runtime probe: ${sample1Support.runtime_probe_ref}`
      : "",
    !sample1Support.model_probe_present
      ? `generate sample1 model probe: ${sample1Support.model_probe_ref}`
      : "",
    !sample1Support.helper_probe_present
      ? `generate sample1 helper probe: ${sample1Support.helper_probe_ref}`
      : "",
    Array.isArray(summary.current_blockers) && summary.current_blockers.length > 0
      ? `sample1 blockers: ${summary.current_blockers.join(" | ")}`
      : "",
    normalizeString(summary.overall_recommended_action_id)
      ? `sample1 recommended action: ${summary.overall_recommended_action_id}`
      : "",
    normalizeString(summary.overall_recommended_action_summary)
      ? `sample1 recommended action summary: ${summary.overall_recommended_action_summary}`
      : "",
    summary.preferred_route && normalizeString(summary.preferred_route.next_step)
      ? `sample1 primary route next step: ${summary.preferred_route.next_step}`
      : "",
    summary.preferred_route && summary.preferred_route.ready && normalizeString(summary.preferred_route.best_model_path)
      ? `sample1 preferred route ready model path: ${summary.preferred_route.best_model_path}`
      : "",
    summary.secondary_route && normalizeString(summary.secondary_route.next_step)
      ? `sample1 secondary route next step: ${summary.secondary_route.next_step}`
      : "",
    operatorHandoff && normalizeString(operatorHandoff.handoff_state)
      ? `sample1 operator handoff state: ${operatorHandoff.handoff_state}`
      : "",
    operatorHandoff && normalizeString(operatorHandoff.blocker_class)
      ? `sample1 operator handoff blocker_class: ${operatorHandoff.blocker_class}`
      : "",
    !sample1Support.helper_local_service_recovery_present
      ? `generate sample1 helper local-service recovery packet: ${sample1Support.helper_local_service_recovery_ref}`
      : "",
    helperLocalServiceRecovery &&
    normalizeString(helperLocalServiceRecovery.top_recommended_action?.action_id)
      ? `sample1 helper local-service action: ${helperLocalServiceRecovery.top_recommended_action.action_id}`
      : "",
    helperLocalServiceRecovery &&
    normalizeString(helperLocalServiceRecovery.helper_route_contract?.helper_route_ready_verdict)
      ? `sample1 helper local-service gate: ${helperLocalServiceRecovery.helper_route_contract.helper_route_ready_verdict}`
      : "",
    !sample1Support.candidate_acceptance_present
      ? `generate sample1 candidate acceptance packet: ${sample1Support.candidate_acceptance_ref}`
      : "",
    !sample1Support.candidate_registration_present
      ? `generate sample1 candidate registration packet: ${sample1Support.candidate_registration_ref}`
      : "",
    candidateAcceptance && normalizeString(candidateAcceptance.current_machine_state?.top_recommended_action?.action_id)
      ? `sample1 candidate acceptance action: ${candidateAcceptance.current_machine_state.top_recommended_action.action_id}`
      : "",
    candidateAcceptance && normalizeString(candidateAcceptance.acceptance_contract?.required_gate_verdict)
      ? `sample1 candidate acceptance gate: ${candidateAcceptance.acceptance_contract.required_gate_verdict}`
      : "",
    candidateRegistration && normalizeString(candidateRegistration.machine_decision?.top_recommended_action?.action_id)
      ? `sample1 candidate registration action: ${candidateRegistration.machine_decision.top_recommended_action.action_id}`
      : "",
    candidateRegistration && normalizeString(candidateRegistration.candidate_validation?.gate_verdict)
      ? `sample1 candidate registration gate: ${candidateRegistration.candidate_validation.gate_verdict}`
      : "",
    candidateRegistration && candidateRegistration.machine_decision?.catalog_write_allowed_now === false
      ? "sample1 candidate registration catalog write remains blocked until validator PASS"
      : "",
    candidateRegistration && candidateRegistration.catalog_patch_plan_summary
      ? `sample1 candidate catalog patch plan blocked reason: ${normalizeString(candidateRegistration.catalog_patch_plan_summary.blocked_reason || "none")}`
      : "",
    !sample1Support.candidate_catalog_patch_plan_present
      ? `generate sample1 candidate catalog patch plan: ${sample1Support.candidate_catalog_patch_plan_ref}`
      : "",
  ];
  return dedupeStrings(items);
}

function buildRequireRealEvidence(bundle, options = {}) {
  const generatedAt = options.generatedAt || isoNow();
  const timezone = options.timezone || "Asia/Shanghai";
  const samples = Array.isArray(bundle.samples) ? bundle.samples : [];
  const evaluations = samples.map((sample) => ({
    sample,
    evaluation: evaluateSample(sample),
  }));
  const prerequisiteEvidence = collectPrerequisites(options);
  const missingPrerequisites = prerequisiteEvidence.filter((item) => !item.present).map((item) => item.path);
  const pendingSamples = evaluations.filter((row) => !row.evaluation.executed).map((row) => row.sample.sample_id);
  const failedSamples = evaluations.filter((row) => row.evaluation.executed && !row.evaluation.success_boolean).map((row) => row.sample.sample_id);
  const invalidSamples = evaluations.filter((row) => row.evaluation.failed_checks.length > 0).map((row) => row.sample.sample_id);
  const syntheticSamples = evaluations.filter((row) => row.evaluation.synthetic_reasons.length > 0).map((row) => row.sample.sample_id);
  const missingEvidenceSamples = evaluations.filter((row) => !row.evaluation.evidence_present).map((row) => row.sample.sample_id);
  const allExecuted = samples.length > 0 && evaluations.every((row) => row.evaluation.executed);
  const allPassed = samples.length > 0 && evaluations.every((row) => row.evaluation.ok);
  const lifecyclePrereqsReady = prerequisiteEvidence
    .filter((item) => item.gates.includes("LPR-G5"))
    .every((item) => item.present);
  const sample1RequireRealSupport = buildSample1RequireRealSupport(samples, options);
  const sample1UnblockSummary = sample1RequireRealSupport.unblock_summary;
  const sample1OperatorHandoff = sample1RequireRealSupport.operator_handoff;
  const sample1CandidateAcceptance = sample1RequireRealSupport.candidate_acceptance_packet;
  const sample1CandidateRegistration = sample1RequireRealSupport.candidate_registration_packet;
  const sample1BlockerNote = buildSample1BlockerNote(sample1RequireRealSupport);

  let gateVerdict = "NO_GO(require_real_samples_pending)";
  let verdictReason = "LPR-W3-03-A capture bundle 已建立，但仍缺真实本地模型目录 + 真实输入样本的执行回填；在无 performed_at / success_boolean=true / evidence_refs 的情况下必须 fail-closed。";
  let releaseStance = "no_go";
  let gateReadinessG6 = "not_ready(require_real_pending)";

  if (missingPrerequisites.length > 0) {
    gateVerdict = "NO_GO(prerequisite_evidence_missing)";
    verdictReason = `LPR-W3-03-A 缺少前置机读证据：${missingPrerequisites.join(", ")}${sample1BlockerNote}`;
    gateReadinessG6 = "not_ready(prerequisite_evidence_missing)";
  } else if (syntheticSamples.length > 0) {
    gateVerdict = "NO_GO(synthetic_runtime_evidence_not_accepted)";
    verdictReason = `LPR-W3-03-A 样本存在 synthetic/mock 痕迹：${syntheticSamples.join(", ")}${sample1BlockerNote}`;
    gateReadinessG6 = "not_ready(synthetic_runtime_evidence_detected)";
  } else if (pendingSamples.length > 0) {
    gateVerdict = "NO_GO(require_real_samples_pending)";
    verdictReason =
      `LPR-W3-03-A capture bundle 已建立，但仍缺真实本地模型目录 + 真实输入样本的执行回填；在无 performed_at / success_boolean=true / evidence_refs 的情况下必须 fail-closed。${sample1BlockerNote}`;
    gateReadinessG6 = "not_ready(require_real_pending)";
  } else if (failedSamples.length > 0) {
    gateVerdict = "NO_GO(require_real_sample_failed)";
    verdictReason = `LPR-W3-03-A 样本存在失败项：${failedSamples.join(", ")}${sample1BlockerNote}`;
    gateReadinessG6 = "not_ready(require_real_execution_failed)";
  } else if (invalidSamples.length > 0) {
    gateVerdict = "NO_GO(machine_readable_assertions_failed)";
    verdictReason = `LPR-W3-03-A 样本未满足机读断言：${invalidSamples.join(", ")}${sample1BlockerNote}`;
    gateReadinessG6 = "not_ready(machine_assertions_failed)";
  } else if (missingEvidenceSamples.length > 0) {
    gateVerdict = "NO_GO(require_real_evidence_missing)";
    verdictReason = `LPR-W3-03-A 样本缺少 evidence_refs：${missingEvidenceSamples.join(", ")}${sample1BlockerNote}`;
    gateReadinessG6 = "not_ready(evidence_missing)";
  } else if (allExecuted && allPassed) {
    gateVerdict = "PASS(local_provider_runtime_require_real_samples_executed_and_verified)";
    verdictReason = "LPR-W3-03-A 的 embedding / ASR / vision / diagnostics require-real 样本均已执行、通过机读断言验证，且未出现 synthetic 痕迹。";
    releaseStance = "candidate_go";
    gateReadinessG6 = "pass(local_provider_runtime_require_real_samples_executed_and_verified)";
  }

  return {
    schema_version: "xhub.qa_main.lpr_w3_03_a_require_real_evidence.v1",
    generated_at: generatedAt,
    timezone,
    lane: "QA-Main",
    role: "shadow_parallel_qa",
    report_mode: "checklist_delta",
    dispatch_mode: "directed_only_no_broadcast",
    current_slice: "LPR-W3-03-A",
    scope: "Local Provider Runtime require-real closure",
    fail_closed: true,
    require_real: true,
    synthetic_not_accepted: true,
    gate_verdict: gateVerdict,
    verdict_reason: verdictReason,
    release_stance: releaseStance,
    machine_readable_evidence_present: prerequisiteEvidence.filter((item) => item.present).map((item) => item.path),
    prerequisite_evidence: prerequisiteEvidence,
    gate_readiness: {
      "LPR-G2": prerequisiteEvidence.find((item) => item.path === "build/reports/lpr_w2_01_a_embedding_contract_evidence.v1.json")?.present
        ? "candidate_pass(embedding_contract_present)"
        : "not_ready(embedding_contract_missing)",
      "LPR-G3": prerequisiteEvidence.find((item) => item.path === "build/reports/lpr_w2_02_a_asr_contract_evidence.v1.json")?.present
        ? "candidate_pass(asr_contract_present)"
        : "not_ready(asr_contract_missing)",
      "LPR-G4": prerequisiteEvidence.find((item) => item.path === "build/reports/lpr_w3_01_a_vision_preview_contract_evidence.v1.json")?.present
        ? "candidate_pass(vision_contract_present)"
        : "not_ready(vision_contract_missing)",
      "LPR-G5": lifecyclePrereqsReady
        ? "candidate_pass(lifecycle_routing_monitor_bench_prereqs_present)"
        : "not_ready(lifecycle_routing_monitor_bench_prereqs_missing)",
      "LPR-G6": gateReadinessG6,
    },
    shadow_qa_baseline: {
      fail_closed_default: true,
      require_real_min_samples: samples.length,
      real_model_path_required: true,
      real_input_artifact_required: true,
      synthetic_runtime_evidence_must_not_count: true,
      precise_reason_required_for_fail_closed_outcomes: true,
    },
    sample1_require_real_support: sample1RequireRealSupport,
    machine_decision: {
      missing_prerequisite_evidence: missingPrerequisites,
      pending_samples: pendingSamples,
      failed_samples: failedSamples,
      invalid_samples: invalidSamples,
      synthetic_samples: syntheticSamples,
      missing_evidence_samples: missingEvidenceSamples,
      all_samples_executed: allExecuted,
      all_samples_passed: allPassed,
      sample1_probe_artifacts_present: {
        runtime_probe: sample1RequireRealSupport.runtime_probe_present,
        model_probe: sample1RequireRealSupport.model_probe_present,
        helper_probe: sample1RequireRealSupport.helper_probe_present,
      },
      sample1_current_blockers: sample1UnblockSummary
        ? dedupeStrings(sample1UnblockSummary.current_blockers)
        : [],
      sample1_runtime_ready: sample1UnblockSummary
        ? sample1UnblockSummary.runtime_ready === true
        : false,
      sample1_execution_ready: sample1UnblockSummary
        ? sample1UnblockSummary.execution_ready === true
        : false,
      sample1_overall_recommended_action_id: sample1UnblockSummary
        ? sample1UnblockSummary.overall_recommended_action_id
        : "",
      sample1_overall_recommended_action_summary: sample1UnblockSummary
        ? sample1UnblockSummary.overall_recommended_action_summary
        : "",
      sample1_preferred_route: sample1UnblockSummary
        ? sample1UnblockSummary.preferred_route
        : null,
      sample1_secondary_route: sample1UnblockSummary
        ? sample1UnblockSummary.secondary_route
        : null,
      sample1_operator_handoff: sample1OperatorHandoff || null,
      sample1_operator_handoff_state: sample1OperatorHandoff
        ? normalizeString(sample1OperatorHandoff.handoff_state)
        : "",
      sample1_operator_handoff_blocker_class: sample1OperatorHandoff
        ? normalizeString(sample1OperatorHandoff.blocker_class)
        : "",
      sample1_candidate_acceptance_present: sample1RequireRealSupport.candidate_acceptance_present,
      sample1_candidate_acceptance: sample1CandidateAcceptance
        ? {
            current_machine_state: sample1CandidateAcceptance.current_machine_state || null,
            acceptance_contract: sample1CandidateAcceptance.acceptance_contract
              ? {
                  expected_provider: sample1CandidateAcceptance.acceptance_contract.expected_provider,
                  expected_task_kind: sample1CandidateAcceptance.acceptance_contract.expected_task_kind,
                  accepted_task_kind_statuses: sample1CandidateAcceptance.acceptance_contract.accepted_task_kind_statuses,
                  required_gate_verdict: sample1CandidateAcceptance.acceptance_contract.required_gate_verdict,
                  required_loadability_verdict: sample1CandidateAcceptance.acceptance_contract.required_loadability_verdict,
                }
              : null,
            current_no_go_example: sample1CandidateAcceptance.current_no_go_example || null,
            artifact_refs: sample1CandidateAcceptance.artifact_refs || null,
          }
        : null,
      sample1_candidate_registration_present: sample1RequireRealSupport.candidate_registration_present,
      sample1_candidate_registration: sample1CandidateRegistration
        ? {
            requested_model_path: sample1CandidateRegistration.requested_model_path || "",
            normalized_model_dir: sample1CandidateRegistration.normalized_model_dir || "",
            acceptance_contract: sample1CandidateRegistration.acceptance_contract
              ? {
                  required_gate_verdict: sample1CandidateRegistration.acceptance_contract.required_gate_verdict,
                  required_loadability_verdict: sample1CandidateRegistration.acceptance_contract.required_loadability_verdict,
                  expected_provider: sample1CandidateRegistration.acceptance_contract.expected_provider,
                  expected_task_kind: sample1CandidateRegistration.acceptance_contract.expected_task_kind,
                }
              : null,
            candidate_validation: sample1CandidateRegistration.candidate_validation
              ? {
                  gate_verdict: sample1CandidateRegistration.candidate_validation.gate_verdict,
                  loadability_blocker: sample1CandidateRegistration.candidate_validation.loadability_blocker,
                }
              : null,
            proposed_catalog_entry_payload: sample1CandidateRegistration.proposed_catalog_entry_payload
              ? {
                  id: sample1CandidateRegistration.proposed_catalog_entry_payload.id,
                  name: sample1CandidateRegistration.proposed_catalog_entry_payload.name,
                  backend: sample1CandidateRegistration.proposed_catalog_entry_payload.backend,
                  modelPath: sample1CandidateRegistration.proposed_catalog_entry_payload.modelPath,
                  taskKinds: sample1CandidateRegistration.proposed_catalog_entry_payload.taskKinds,
                }
              : null,
            target_catalog_paths: Array.isArray(sample1CandidateRegistration.target_catalog_paths)
              ? sample1CandidateRegistration.target_catalog_paths.map((item) => ({
                  catalog_path: item.catalog_path,
                  present: item.present === true,
                  exact_model_dir_registered: item.exact_model_dir_registered === true,
                  proposed_model_id_conflict: item.proposed_model_id_conflict === true,
                  recommended_action: item.recommended_action,
                }))
              : [],
            catalog_patch_plan_summary: sample1CandidateRegistration.catalog_patch_plan_summary
              ? {
                  artifact_ref: sample1CandidateRegistration.catalog_patch_plan_summary.artifact_ref || "",
                  manual_patch_scope:
                    sample1CandidateRegistration.catalog_patch_plan_summary.manual_patch_scope || "",
                  manual_patch_allowed_now:
                    sample1CandidateRegistration.catalog_patch_plan_summary.manual_patch_allowed_now === true,
                  blocked_reason:
                    sample1CandidateRegistration.catalog_patch_plan_summary.blocked_reason || "",
                  eligible_target_base_count:
                    sample1CandidateRegistration.catalog_patch_plan_summary.eligible_target_base_count || 0,
                  blocked_target_base_count:
                    sample1CandidateRegistration.catalog_patch_plan_summary.blocked_target_base_count || 0,
                }
              : null,
            machine_decision: sample1CandidateRegistration.machine_decision
              ? {
                  catalog_write_allowed_now:
                    sample1CandidateRegistration.machine_decision.catalog_write_allowed_now === true,
                  validation_pass_required_before_catalog_write:
                    sample1CandidateRegistration.machine_decision.validation_pass_required_before_catalog_write !== false,
                  already_registered_in_catalog:
                    sample1CandidateRegistration.machine_decision.already_registered_in_catalog === true,
                  catalog_patch_plan_required_before_manual_write:
                    sample1CandidateRegistration.machine_decision.catalog_patch_plan_required_before_manual_write !== false,
                  top_recommended_action:
                    sample1CandidateRegistration.machine_decision.top_recommended_action || null,
                }
              : null,
          }
        : null,
    },
    missing_require_real_samples: pendingSamples,
    next_required_artifacts: dedupeStrings([
      ...missingPrerequisites.map((item) => `missing prerequisite evidence: ${item}`),
      ...pendingSamples.map((item) => `execute real sample: ${item}`),
      ...missingEvidenceSamples.map((item) => `evidence_refs missing for ${item}`),
      ...buildSample1NextRequiredItems(sample1RequireRealSupport),
    ]),
    hard_lines: [
      "synthetic_mock_smoke_or_manual_story_must_not_count_as_require_real",
      "real_model_path_and_real_input_artifact_ref_must_be_recorded_for_each_sample",
      "fail_closed_without_precise_reason_code_or_diagnostics_ref_is_immediate_NO_GO",
      "doctor_and_release_export_must_reuse_same_runtime_truth_as_monitor_snapshot",
      "W3 require-real may preserve preview_or_fail_closed reality but must not fake green beyond current product truth",
    ],
    next_owner_lane: allExecuted && allPassed ? "QA-Main" : "Hub-L5",
    evidence_refs: dedupeStrings([
      "build/reports/lpr_w3_03_require_real_capture_bundle.v1.json",
      "build/reports/lpr_w2_01_a_embedding_contract_evidence.v1.json",
      "build/reports/lpr_w2_02_a_asr_contract_evidence.v1.json",
      "build/reports/lpr_w3_01_a_vision_preview_contract_evidence.v1.json",
      "build/reports/lpr_w3_05_d_resident_runtime_proxy_evidence.v1.json",
      "build/reports/lpr_w3_06_d_bench_fixture_pack_evidence.v1.json",
      "build/reports/lpr_w3_07_c_monitor_export_evidence.v1.json",
      "build/reports/lpr_w3_08_c_task_resolution_evidence.v1.json",
      sample1RequireRealSupport.runtime_probe_ref,
      sample1RequireRealSupport.model_probe_ref,
      sample1RequireRealSupport.helper_probe_ref,
      ...(sample1RequireRealSupport.operator_handoff_present
        ? [sample1RequireRealSupport.operator_handoff_ref]
        : []),
      ...(sample1RequireRealSupport.helper_local_service_recovery_present
        ? [sample1RequireRealSupport.helper_local_service_recovery_ref]
        : []),
      ...(sample1RequireRealSupport.candidate_acceptance_present
        ? [sample1RequireRealSupport.candidate_acceptance_ref]
        : []),
      ...(sample1RequireRealSupport.candidate_registration_present
        ? [sample1RequireRealSupport.candidate_registration_ref]
        : []),
      ...(sample1RequireRealSupport.candidate_catalog_patch_plan_present
        ? [sample1RequireRealSupport.candidate_catalog_patch_plan_ref]
        : []),
      "docs/memory-new/xhub-local-provider-runtime-require-real-runbook-v1.md",
      "scripts/generate_lpr_w3_03_a_require_real_evidence.js",
      "scripts/generate_lpr_w3_03_sample1_candidate_acceptance.js",
      "scripts/generate_lpr_w3_03_sample1_candidate_catalog_patch_plan.js",
      "scripts/generate_lpr_w3_03_sample1_helper_local_service_recovery.js",
      "scripts/generate_lpr_w3_03_sample1_candidate_registration_packet.js",
      "scripts/generate_lpr_w3_03_sample1_operator_handoff.js",
      "scripts/update_lpr_w3_03_require_real_capture_bundle.js",
      "scripts/lpr_w3_03_require_real_status.js",
    ]),
    consumed_capture_bundle_path: "build/reports/lpr_w3_03_require_real_capture_bundle.v1.json",
    consumed_capture_bundle: {
      path: "build/reports/lpr_w3_03_require_real_capture_bundle.v1.json",
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
        sample_summaries: evaluations.map((row) => sampleSummary(row.sample, row.evaluation)),
      },
    },
  };
}

function main() {
  const bundle = readCaptureBundle();
  const report = buildRequireRealEvidence(bundle);
  const outputPath = resolveRequireRealEvidencePath();
  writeJSON(outputPath, report);
  process.stdout.write(`${outputPath}\n`);
}

module.exports = {
  PREREQUISITE_EVIDENCE,
  buildSample1RequireRealSupport,
  buildRequireRealEvidence,
  evaluateCheck,
  evaluateSample,
  outputPath: resolveRequireRealEvidencePath(),
  readJSON,
  resolveEvidenceRefPath,
  sampleSummary,
  syntheticEvidenceReasons,
  writeJSON,
};

if (require.main === module) {
  main();
}
