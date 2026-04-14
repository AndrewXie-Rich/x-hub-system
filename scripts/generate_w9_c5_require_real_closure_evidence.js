#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const {
  readCaptureBundle,
  repoRoot,
  resolveReportsDir,
  resolveRequireRealEvidencePath,
  writeJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");
const {
  buildSummary,
} = require("./lpr_w3_03_require_real_status.js");
const {
  buildRequireRealEvidence,
} = require("./generate_lpr_w3_03_a_require_real_evidence.js");

const README_REF = "docs/memory-new/README-local-provider-runtime-productization-v1.md";
const RUNBOOK_REF = "docs/memory-new/xhub-local-provider-runtime-require-real-runbook-v1.md";
const CHECKLIST_REF = "docs/memory-new/xhub-work-order-8-9-closure-checklist-v1.md";
const CAPABILITY_MATRIX_REF = "docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md";
const STATUS_SCRIPT_REF = "scripts/lpr_w3_03_require_real_status.js";
const QA_SCRIPT_REF = "scripts/generate_lpr_w3_03_a_require_real_evidence.js";
const CLOSURE_SCRIPT_REF = "scripts/generate_w9_c5_require_real_closure_evidence.js";

function isoNow() {
  return new Date().toISOString();
}

function readJSONIfExists(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function readTextIfExists(filePath) {
  try {
    if (!fs.existsSync(filePath)) return "";
    return fs.readFileSync(filePath, "utf8");
  } catch {
    return "";
  }
}

function dedupeStrings(values) {
  const seen = new Set();
  const out = [];
  for (const value of values || []) {
    const trimmed = String(value || "").trim();
    if (!trimmed || seen.has(trimmed)) continue;
    seen.add(trimmed);
    out.push(trimmed);
  }
  return out;
}

function pickFocusSample(bundle) {
  const samples = Array.isArray(bundle?.samples) ? bundle.samples : [];
  return samples.find((sample) => sample && sample.success_boolean !== true) || samples[0] || null;
}

function resolveRef(relativePath) {
  return path.join(repoRoot, relativePath);
}

function resolveOutputPath(options = {}) {
  if (options.outputPath) {
    return path.resolve(String(options.outputPath));
  }
  return path.join(resolveReportsDir(options), "w9_c5_require_real_closure_evidence.v1.json");
}

function detectReadmePendingSignals(text) {
  const lines = String(text || "").split(/\r?\n/);
  return dedupeStrings(
    lines.filter((line) => {
      const normalized = line.toLowerCase();
      if (!normalized.includes("require-real")) return false;
      if (normalized.includes("no longer depends on")) return false;
      if (normalized.includes("ready state")) return false;
      return normalized.includes("pending")
        || normalized.includes("still needs")
        || normalized.includes("fixture runs")
        || normalized.includes("actual local model directories");
    }).map((line) => line.trim())
  );
}

function parseCapabilityMatrixStatus(text) {
  const match = String(text || "").match(/\|\s*Local provider runtime\s*\|[^|]*\|\s*`([^`]+)`\s*\|/);
  return match ? String(match[1] || "").trim() : "";
}

function buildClosureVerdict({ qaGateVerdict, readmePendingSignals, capabilityMatrixStatus }) {
  const blockers = [];
  if (!qaGateVerdict || qaGateVerdict.startsWith("NO_GO(")) {
    blockers.push(`qa_gate=${qaGateVerdict || "missing"}`);
  }
  if (readmePendingSignals.length > 0) {
    blockers.push("readme_still_declares_require_real_pending");
  }
  if (!capabilityMatrixStatus) {
    blockers.push("capability_matrix_local_provider_runtime_status_missing");
  } else if (capabilityMatrixStatus === "implementation-in-progress") {
    blockers.push("capability_matrix_local_provider_runtime_not_elevated");
  }
  return {
    closure_ready: blockers.length === 0,
    blockers,
  };
}

function buildW9C5RequireRealClosureEvidence(options = {}) {
  const generatedAt = String(options.generatedAt || isoNow()).trim() || isoNow();
  const bundle = options.bundle || readCaptureBundle(options);
  const requireRealEvidence = options.requireRealEvidence
    || readJSONIfExists(resolveRequireRealEvidencePath(options))
    || buildRequireRealEvidence(bundle, options.requireRealEvidenceOptions || {});
  const focusSample = options.focusSample || pickFocusSample(bundle);
  const statusSummary = options.statusSummary || buildSummary(bundle, requireRealEvidence, focusSample, false);

  const readmePath = options.readmePath || resolveRef(README_REF);
  const runbookPath = options.runbookPath || resolveRef(RUNBOOK_REF);
  const checklistPath = options.checklistPath || resolveRef(CHECKLIST_REF);
  const capabilityMatrixPath = options.capabilityMatrixPath || resolveRef(CAPABILITY_MATRIX_REF);

  const readmeText = Object.prototype.hasOwnProperty.call(options, "readmeText")
    ? String(options.readmeText || "")
    : readTextIfExists(readmePath);
  const capabilityMatrixText = Object.prototype.hasOwnProperty.call(options, "capabilityMatrixText")
    ? String(options.capabilityMatrixText || "")
    : readTextIfExists(capabilityMatrixPath);

  const readmePendingSignals = detectReadmePendingSignals(readmeText);
  const capabilityMatrixStatus = parseCapabilityMatrixStatus(capabilityMatrixText);
  const verdict = buildClosureVerdict({
    qaGateVerdict: String(requireRealEvidence?.gate_verdict || statusSummary?.qa_gate_verdict || "").trim(),
    readmePendingSignals,
    capabilityMatrixStatus,
  });

  const pendingSamples = Array.isArray(statusSummary?.qa_machine_decision?.pending_samples)
    ? statusSummary.qa_machine_decision.pending_samples
    : [];
  const missingEvidenceSamples = Array.isArray(statusSummary?.qa_machine_decision?.missing_evidence_samples)
    ? statusSummary.qa_machine_decision.missing_evidence_samples
    : [];
  const nextPendingSampleID = String(statusSummary?.next_pending_sample_id || focusSample?.sample_id || "").trim();
  const nextPendingSamplePrepareCommand = String(
    statusSummary?.next_pending_sample?.prepare_command
      || (nextPendingSampleID
        ? `node scripts/prepare_lpr_w3_03_require_real_sample.js --sample-id ${nextPendingSampleID}`
        : "")
  ).trim();

  const nextActions = dedupeStrings([
    ...(Array.isArray(statusSummary?.qa_next_required_artifacts) ? statusSummary.qa_next_required_artifacts : []),
    verdict.blockers.includes("readme_still_declares_require_real_pending")
      ? "only remove README pending wording after real samples and closure evidence both turn ready"
      : "",
    verdict.blockers.includes("capability_matrix_local_provider_runtime_not_elevated")
      ? "only elevate capability matrix after require-real closure evidence turns ready"
      : "",
  ]);

  return {
    schema_version: "xhub.w9_c5_require_real_closure_evidence.v1",
    generated_at: generatedAt,
    status: verdict.closure_ready ? "ready" : "blocked",
    claim_scope: ["W9-C5"],
    claim: verdict.closure_ready
      ? "W9-C5 require-real closure is complete: real samples passed, release-facing docs no longer declare pending smoke, and the capability matrix is ready to elevate."
      : "W9-C5 remains fail-closed until require-real execution, README posture, and capability-matrix posture all align.",
    closure_verdict: {
      closure_ready: verdict.closure_ready,
      qa_gate_verdict: String(requireRealEvidence?.gate_verdict || statusSummary?.qa_gate_verdict || "").trim(),
      qa_release_stance: String(requireRealEvidence?.release_stance || statusSummary?.qa_release_stance || "").trim(),
      blocker_count: verdict.blockers.length,
      blockers: verdict.blockers,
    },
    require_real_execution: {
      bundle_status: String(statusSummary?.bundle_status || bundle?.status || "").trim(),
      total_samples: Number(statusSummary?.total_samples || 0),
      executed_count: Number(statusSummary?.executed_count || 0),
      passed_count: Number(statusSummary?.passed_count || 0),
      failed_count: Number(statusSummary?.failed_count || 0),
      pending_count: Number(statusSummary?.pending_count || 0),
      pending_samples: pendingSamples,
      missing_evidence_samples: missingEvidenceSamples,
      next_pending_sample_id: nextPendingSampleID,
      next_pending_sample_prepare_command: nextPendingSamplePrepareCommand,
    },
    sample1_focus: {
      runtime_ready: !!statusSummary?.qa_machine_decision?.sample1_runtime_ready,
      execution_ready: !!statusSummary?.qa_machine_decision?.sample1_execution_ready,
      overall_recommended_action_id: String(statusSummary?.qa_machine_decision?.sample1_overall_recommended_action_id || "").trim(),
      operator_handoff_state: String(statusSummary?.qa_machine_decision?.sample1_operator_handoff_state || "").trim(),
      operator_handoff_blocker_class: String(statusSummary?.qa_machine_decision?.sample1_operator_handoff_blocker_class || "").trim(),
      current_blockers: Array.isArray(statusSummary?.qa_machine_decision?.sample1_current_blockers)
        ? statusSummary.qa_machine_decision.sample1_current_blockers
        : [],
      runtime_probe: statusSummary?.sample1_runtime_probe || null,
      model_probe: statusSummary?.sample1_model_probe || null,
      helper_probe: statusSummary?.sample1_helper_probe || null,
    },
    governance_posture: {
      readme_require_real_pending: readmePendingSignals.length > 0,
      readme_pending_signals: readmePendingSignals,
      capability_matrix_local_provider_runtime_status: capabilityMatrixStatus,
      capability_matrix_allows_elevation: capabilityMatrixStatus !== ""
        && capabilityMatrixStatus !== "implementation-in-progress",
    },
    next_actions: nextActions,
    upstream_artifacts: {
      require_real_bundle_ref: "build/reports/lpr_w3_03_require_real_capture_bundle.v1.json",
      require_real_evidence_ref: "build/reports/lpr_w3_03_a_require_real_evidence.v1.json",
      runtime_probe_ref: "build/reports/lpr_w3_03_b_runtime_candidate_probe.v1.json",
      model_probe_ref: "build/reports/lpr_w3_03_c_model_native_loadability_probe.v1.json",
      helper_probe_ref: "build/reports/lpr_w3_03_d_helper_bridge_probe.v1.json",
    },
    source_refs: [
      README_REF,
      RUNBOOK_REF,
      CHECKLIST_REF,
      CAPABILITY_MATRIX_REF,
      QA_SCRIPT_REF,
      STATUS_SCRIPT_REF,
      CLOSURE_SCRIPT_REF,
    ],
  };
}

function main() {
  const report = buildW9C5RequireRealClosureEvidence();
  const outputPath = resolveOutputPath();
  writeJSON(outputPath, report);
  process.stdout.write(`${outputPath}\n`);
}

module.exports = {
  buildClosureVerdict,
  buildW9C5RequireRealClosureEvidence,
  detectReadmePendingSignals,
  parseCapabilityMatrixStatus,
  outputPath: resolveOutputPath(),
  resolveOutputPath,
};

if (require.main === module) {
  main();
}
