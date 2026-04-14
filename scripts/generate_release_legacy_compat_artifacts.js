#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const {
  checkInternalPassLines,
} = require("./m3_check_internal_pass_lines.js");

const ROOT = path.resolve(__dirname, "..");
const COMPAT_GENERATOR = "scripts/generate_release_legacy_compat_artifacts.js";
const MAINLINE_CHAIN = ["XT-W3-23", "XT-W3-24", "XT-W3-25"];
const PREFERRED_XT_READY_ARTIFACTS = [
  {
    mode: "require_real_release_chain",
    reportRef: "build/xt_ready_gate_e2e_require_real_report.json",
    sourceRefs: [
      "build/xt_ready_evidence_source.require_real.json",
      "build/xt_ready_evidence_source.json",
    ],
    connectorRefs: [
      "build/connector_ingress_gate_snapshot.require_real.json",
      "build/connector_ingress_gate_snapshot.json",
    ],
  },
  {
    mode: "db_real_release_chain",
    reportRef: "build/xt_ready_gate_e2e_db_real_report.json",
    sourceRefs: [
      "build/xt_ready_evidence_source.db_real.json",
      "build/xt_ready_evidence_source.require_real.json",
      "build/xt_ready_evidence_source.json",
    ],
    connectorRefs: [
      "build/connector_ingress_gate_snapshot.db_real.json",
      "build/connector_ingress_gate_snapshot.require_real.json",
      "build/connector_ingress_gate_snapshot.json",
    ],
  },
  {
    mode: "current_gate",
    reportRef: "build/xt_ready_gate_e2e_report.json",
    sourceRefs: [
      "build/xt_ready_evidence_source.json",
    ],
    connectorRefs: [
      "build/connector_ingress_gate_snapshot.json",
    ],
  },
];

function isoNow() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

function abs(relPath) {
  return path.join(ROOT, relPath);
}

function exists(relPath) {
  return fs.existsSync(abs(relPath));
}

function readText(relPath) {
  return fs.readFileSync(abs(relPath), "utf8");
}

function readJson(relPath) {
  return JSON.parse(readText(relPath));
}

function readJsonIfExists(relPath) {
  if (!exists(relPath)) return null;
  try {
    return readJson(relPath);
  } catch {
    return null;
  }
}

function writeJson(relPath, payload) {
  const out = abs(relPath);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
}

function normalizeString(value, fallback = "") {
  const trimmed = String(value ?? "").trim();
  return trimmed || fallback;
}

function normalizeBoolean(value) {
  return value === true;
}

function parseArgs(argv) {
  const out = { force: false };
  for (let i = 2; i < argv.length; i += 1) {
    const token = normalizeString(argv[i]);
    if (token === "--force") out.force = true;
    else if (token === "--help" || token === "-h") printUsage(0);
    else throw new Error(`unknown arg: ${token}`);
  }
  return out;
}

function printUsage(exitCode) {
  const usage = [
    "usage:",
    "  node scripts/generate_release_legacy_compat_artifacts.js",
    "  node scripts/generate_release_legacy_compat_artifacts.js --force",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(usage);
  else process.stderr.write(usage);
  process.exit(exitCode);
}

function extractDecisionFromXtGateReport(markdown = "") {
  const match = String(markdown || "").match(/- decision:\s*([A-Z_]+)/);
  return match ? String(match[1] || "").trim() : "";
}

function extractXtGateStatuses(markdown = "") {
  const statuses = {};
  for (let i = 0; i <= 5; i += 1) {
    const gate = `XT-G${i}`;
    if (new RegExp(`PASS:\\s*${gate}\\b`, "i").test(markdown)) {
      statuses[`xt_g${i}_status`] = "PASS";
      continue;
    }
    if (new RegExp(`FAIL:\\s*${gate}\\b`, "i").test(markdown)) {
      statuses[`xt_g${i}_status`] = "FAIL";
    }
  }
  return statuses;
}

function pickCoverage(xtIndex) {
  const coverage = (xtIndex && xtIndex.coverage && typeof xtIndex.coverage === "object")
    ? xtIndex.coverage
    : {};
  const selected = {};
  for (const key of ["XT-W3-08", "CRK-W1-08", "CM-W5-20", "XT-W2-17", "XT-W2-18", "XT-W2-19"]) {
    if (Object.prototype.hasOwnProperty.call(coverage, key)) selected[key] = coverage[key];
  }
  return selected;
}

function buildCompatMetadata(targetArtifact, sourceRefs = []) {
  return {
    compat_generated: true,
    compat_generated_by: COMPAT_GENERATOR,
    compat_generated_at: isoNow(),
    compat_target_artifact: targetArtifact,
    compat_source_refs: Array.from(new Set(sourceRefs.filter(Boolean))),
  };
}

function selectPreferredXtReadyArtifacts() {
  for (const candidate of PREFERRED_XT_READY_ARTIFACTS) {
    if (!exists(candidate.reportRef)) continue;
    const sourceRef = candidate.sourceRefs.find((ref) => exists(ref)) || null;
    const connectorRef = candidate.connectorRefs.find((ref) => exists(ref)) || null;
    return {
      mode: candidate.mode,
      reportRef: candidate.reportRef,
      sourceRef,
      connectorRef,
      report: readJsonIfExists(candidate.reportRef),
      source: sourceRef ? readJsonIfExists(sourceRef) : null,
      connector: connectorRef ? readJsonIfExists(connectorRef) : null,
    };
  }
  return {
    mode: "missing",
    reportRef: null,
    sourceRef: null,
    connectorRef: null,
    report: null,
    source: null,
    connector: null,
  };
}

function isCompatManaged(payload) {
  return !!(payload && payload.compat_generated === true && payload.compat_generated_by === COMPAT_GENERATOR);
}

function ensureArtifact(relPath, buildPayload, options = {}) {
  const { force = false } = options;
  const existing = readJsonIfExists(relPath);
  if (existing && !force && !isCompatManaged(existing)) {
    return {
      ref: relPath,
      action: "preserved_existing",
      payload: existing,
    };
  }
  const payload = buildPayload();
  writeJson(relPath, payload);
  return {
    ref: relPath,
    action: existing ? "refreshed_compat" : "created_compat",
    payload,
  };
}

function buildReleaseDecisionPayload(inputs) {
  const xtIndex = inputs.xtReportIndex || {};
  const xtGateDecision = inputs.xtGateDecision;
  const releaseDecision = normalizeString(xtIndex.release_decision).toUpperCase();
  const releaseReady = releaseDecision === "GO";
  const sourceRefs = [
    "x-terminal/.axcoder/reports/xt-report-index.json",
    "x-terminal/.axcoder/reports/xt-gate-report.md",
  ];
  return {
    schema_version: "xhub.xt_w3_release_ready_decision.compat.v1",
    generated_at: isoNow(),
    scope_boundary: {
      validated_mainline_only: true,
      mainline_chain: MAINLINE_CHAIN,
      no_scope_expansion: true,
      no_unverified_claims: true,
    },
    release_ready: releaseReady,
    release_decision: releaseDecision,
    xt_gate_report_decision: xtGateDecision,
    mainline_release_profile: "compat_backfill_from_current_xt_gate_truth",
    smoke_summary: xtIndex.summary || null,
    coverage: pickCoverage(xtIndex),
    non_scope_note:
      "Legacy XT release decision artifact is compat-backfilled from current XT gate truth. Scope remains frozen to XT-W3-23/24/25 mainline, and any non-mainline or require-real gaps remain fail-closed elsewhere.",
    notes: [
      "This artifact exists to satisfy legacy release consumers while the current source-of-truth lives in x-terminal/.axcoder reports.",
      "release_ready only mirrors current XT gate GO/NO-GO and does not relax require-real or audit-source constraints.",
    ],
    evidence_refs: sourceRefs,
    ...buildCompatMetadata("build/reports/xt_w3_release_ready_decision.v1.json", sourceRefs),
  };
}

function buildXtReadyEvidenceSourcePayload(inputs) {
  const preferredXtReadySource = inputs.xtReadySource || null;
  const preferredXtReadyReportRef = inputs.xtReadyArtifacts?.reportRef || null;
  const preferredXtReadySourceRef = inputs.xtReadyArtifacts?.sourceRef || null;
  if (preferredXtReadySource && preferredXtReadySourceRef) {
    const sourceRefs = [
      preferredXtReadyReportRef,
      preferredXtReadySourceRef,
    ].filter(Boolean);
    return {
      ...preferredXtReadySource,
      require_real_audit: normalizeBoolean(
        preferredXtReadySource.require_real_audit ??
          inputs.xtReadyGate?.require_real_audit_source
      ),
      selection_reason:
        normalizeString(preferredXtReadySource.selection_reason) ||
        "Compat exporter preserved the preferred XT-ready evidence source from current source truth.",
      selected_at_ms: preferredXtReadySource.selected_at_ms ?? Date.now(),
      ...buildCompatMetadata("build/xt_ready_evidence_source.json", sourceRefs),
    };
  }

  const runtimeIncidentRef = "x-terminal/.axcoder/reports/xt_ready_incident_events.runtime.json";
  const sampleAuditRef = "scripts/fixtures/xt_ready_audit_events.sample.json";
  const runtimeIncidentPresent = exists(runtimeIncidentRef);
  const selectedSource = runtimeIncidentPresent
    ? "compat_runtime_incident_report"
    : "sample_fixture";
  const selectedAuditJson = runtimeIncidentPresent
    ? `./${runtimeIncidentRef}`
    : `./${sampleAuditRef}`;
  const sourceRefs = runtimeIncidentPresent
    ? [runtimeIncidentRef, preferredXtReadyReportRef || "build/xt_ready_gate_e2e_report.json"]
    : [preferredXtReadyReportRef || "build/xt_ready_gate_e2e_report.json", sampleAuditRef];
  return {
    schema_version: "xt_ready_audit_input_selection.v1",
    env_var: "XT_READY_AUDIT_EXPORT_JSON",
    require_real_audit: normalizeBoolean(inputs.xtReadyGate?.require_real_audit_source),
    selected_source: selectedSource,
    selected_audit_json: selectedAuditJson,
    selected_audit_json_resolved: runtimeIncidentPresent
      ? abs(runtimeIncidentRef)
      : abs(sampleAuditRef),
    candidates: [
      {
        source: "compat_runtime_incident_report",
        candidate_path: `./${runtimeIncidentRef}`,
        resolved_path: abs(runtimeIncidentRef),
        exists: runtimeIncidentPresent,
      },
      {
        source: "sample_fixture",
        candidate_path: `./${sampleAuditRef}`,
        resolved_path: abs(sampleAuditRef),
        exists: exists(sampleAuditRef),
      },
    ],
    selection_reason: runtimeIncidentPresent
      ? "Current XT-Ready report lacks strict require-real source binding, so compat exporter records the available runtime incident report without claiming audit-grade release provenance."
      : "No runtime incident report was present; compat exporter falls back to the canonical sample fixture and preserves fail-closed semantics.",
    selected_at_ms: Date.now(),
    ...buildCompatMetadata("build/xt_ready_evidence_source.json", sourceRefs),
  };
}

function buildConnectorSnapshotPayload(inputs) {
  const preferredConnectorSnapshot = inputs.xtReadyArtifacts?.connector || null;
  const preferredConnectorRef = inputs.xtReadyArtifacts?.connectorRef || null;
  if (preferredConnectorSnapshot && preferredConnectorRef) {
    return {
      ...preferredConnectorSnapshot,
      ...buildCompatMetadata("build/connector_ingress_gate_snapshot.json", [
        preferredConnectorRef,
      ]),
    };
  }

  const runtimeSummary = inputs.runtimeIncidents?.summary || {};
  const doctor = inputs.doctorReport?.doctor || {};
  const coverage = Number(
    runtimeSummary.non_message_ingress_policy_coverage
      ?? doctor.non_message_ingress_policy_coverage
      ?? 0
  );
  const blockedMissRate = Number(runtimeSummary.blocked_event_miss_rate ?? 1);
  const pass = coverage >= 1 && blockedMissRate < 0.01;
  const incidentCodes = [];
  if (coverage < 1) incidentCodes.push("non_message_ingress_policy_coverage_low");
  if (blockedMissRate >= 0.01) incidentCodes.push("blocked_event_miss_rate_high");
  const sourceRefs = [
    "x-terminal/.axcoder/reports/doctor-report.json",
    "x-terminal/.axcoder/reports/xt_ready_incident_events.runtime.json",
  ].filter((ref) => exists(ref));
  return {
    schema_version: "xt_ready_connector_ingress_gate_fetch.v1",
    fetched_at_ms: Date.now(),
    request: {
      base_url: "compat://current-source-truth",
      route_path: "/admin/pairing/connector-ingress/gate-snapshot",
      source: "compat_scan",
      url: "compat://current-source-truth/admin/pairing/connector-ingress/gate-snapshot?source=compat_scan",
    },
    source_used: "scan",
    data_ready: sourceRefs.length > 0,
    audit_row_count: 0,
    scan_entry_count: sourceRefs.length,
    blocked_event_miss_rate: blockedMissRate,
    snapshot: {
      schema_version: "xhub.connector.non_message_ingress_gate.v1",
      measured_at_ms: Date.now(),
      pass,
      incident_codes: incidentCodes,
      thresholds: {
        non_message_ingress_policy_coverage_min: 1,
        blocked_event_miss_rate_max_exclusive: 0.01,
      },
      checks: [
        {
          key: "non_message_ingress_policy_coverage",
          pass: coverage >= 1,
          comparator: ">=",
          expected: 1,
          actual: coverage,
        },
        {
          key: "blocked_event_miss_rate",
          pass: blockedMissRate < 0.01,
          comparator: "<",
          expected: 0.01,
          actual: blockedMissRate,
        },
      ],
      metrics: {
        non_message_ingress_policy_coverage: coverage,
        blocked_event_miss_rate: blockedMissRate,
      },
    },
    snapshot_audit: {
      schema_version: "xhub.connector.non_message_ingress_gate.v1",
      pass: false,
      incident_codes: ["audit_source_not_present"],
      metrics: {
        non_message_ingress_policy_coverage: coverage,
        blocked_event_miss_rate: blockedMissRate,
      },
    },
    snapshot_scan: {
      schema_version: "xhub.connector.non_message_ingress_gate.v1",
      pass,
      incident_codes: incidentCodes,
      metrics: {
        non_message_ingress_policy_coverage: coverage,
        blocked_event_miss_rate: blockedMissRate,
      },
    },
    summary: {
      non_message_ingress_policy_coverage: coverage,
      blocked_event_miss_rate: blockedMissRate,
    },
    ...buildCompatMetadata("build/connector_ingress_gate_snapshot.json", sourceRefs),
  };
}

function buildRequireRealProvenancePayload(inputs, releaseDecisionPayload, xtReadySourcePayload, connectorPayload) {
  const requireReal = inputs.requireRealEvidence || {};
  const xtReadyGate = inputs.xtReadyGate || {};
  const xtReadyReportRef = inputs.xtReadyArtifacts?.reportRef || "build/xt_ready_gate_e2e_report.json";
  const connectorRef =
    inputs.xtReadyArtifacts?.connectorRef ||
    "build/connector_ingress_gate_snapshot.json";
  const strictXtReadyRequireRealPass =
    xtReadyGate.ok === true &&
    xtReadyGate.require_real_audit_source === true &&
    normalizeString(xtReadySourcePayload.selected_source) !== "sample_fixture" &&
    normalizeString(connectorPayload.source_used).toLowerCase() === "audit" &&
    connectorPayload.snapshot?.pass === true;
  const requireRealReleaseStance = normalizeString(requireReal.release_stance).toLowerCase();
  const requireRealSatisfied =
    requireRealReleaseStance === "candidate_go" ||
    requireRealReleaseStance === "release_ready" ||
    requireRealReleaseStance === "go";
  const unifiedReleaseReadyProvenancePass =
    releaseDecisionPayload.release_ready === true &&
    strictXtReadyRequireRealPass &&
    requireRealSatisfied;
  const blockers = [];
  if (!requireRealSatisfied) blockers.push("lpr_require_real_not_ready");
  if (!(xtReadyGate.ok === true)) blockers.push("xt_ready_gate_not_green");
  if (!(xtReadyGate.require_real_audit_source === true)) blockers.push("xt_ready_require_real_audit_not_strict");
  if (normalizeString(xtReadySourcePayload.selected_source) === "sample_fixture") {
    blockers.push("xt_ready_selected_source_is_sample_fixture");
  }
  if (normalizeString(connectorPayload.source_used).toLowerCase() !== "audit") {
    blockers.push("connector_gate_not_audit_source");
  }
  if (!(connectorPayload.snapshot?.pass === true)) blockers.push("connector_gate_not_green");
  const releaseStance = unifiedReleaseReadyProvenancePass ? "release_ready" : "no_go";
  const sourceRefs = [
    "build/reports/lpr_w3_03_a_require_real_evidence.v1.json",
    xtReadyReportRef,
    ...(Array.isArray(xtReadySourcePayload.compat_source_refs)
      ? xtReadySourcePayload.compat_source_refs
      : ["build/xt_ready_evidence_source.json"]),
    connectorRef,
    "x-terminal/.axcoder/reports/xt-report-index.json",
  ].filter((ref) => exists(ref));
  return {
    schema_version: "xhub.xt_w3_require_real_provenance.compat.v2",
    generated_at: isoNow(),
    summary: {
      strict_xt_ready_require_real_pass: strictXtReadyRequireRealPass,
      unified_release_ready_provenance_pass: unifiedReleaseReadyProvenancePass,
      release_stance: releaseStance,
      require_real_release_stance: normalizeString(requireReal.release_stance, "missing"),
      blocker_count: blockers.length,
      blockers,
    },
    require_real_truth: {
      gate_verdict: normalizeString(requireReal.gate_verdict, "missing"),
      release_stance: normalizeString(requireReal.release_stance, "missing"),
      verdict_reason: normalizeString(requireReal.verdict_reason, ""),
      pending_samples: Array.isArray(requireReal.machine_decision?.pending_samples)
        ? requireReal.machine_decision.pending_samples
        : [],
      missing_evidence_samples: Array.isArray(requireReal.machine_decision?.missing_evidence_samples)
        ? requireReal.machine_decision.missing_evidence_samples
        : [],
    },
    xt_ready_truth: {
      ok: xtReadyGate.ok === true,
      require_real_audit_source: xtReadyGate.require_real_audit_source === true,
      selected_source: xtReadySourcePayload.selected_source,
      selected_audit_json: xtReadySourcePayload.selected_audit_json,
      connector_source_used: connectorPayload.source_used,
      connector_pass: connectorPayload.snapshot?.pass === true,
    },
    notes: [
      "Compat provenance preserves current fail-closed truth and does not claim release_ready unless XT gate, audit source, connector gate, and LPR require-real all align.",
    ],
    evidence_refs: sourceRefs,
    ...buildCompatMetadata("build/reports/xt_w3_require_real_provenance.v2.json", sourceRefs),
  };
}

function buildRollbackPayload() {
  const rollbackLast = readJsonIfExists("x-terminal/.axcoder/reports/xt-rollback-last.json") || {};
  const rollbackVerify = readJsonIfExists("x-terminal/.axcoder/reports/xt-rollback-verify.json") || {};
  const rollbackReady =
    normalizeString(rollbackLast.status).toLowerCase() === "pass" &&
    Number(rollbackLast.copied_previous_to_current) === 1;
  const sourceRefs = [
    "x-terminal/.axcoder/reports/xt-rollback-last.json",
    "x-terminal/.axcoder/reports/xt-rollback-verify.json",
  ].filter((ref) => exists(ref));
  return {
    schema_version: "xhub.xt_w3_25_competitive_rollback.compat.v1",
    generated_at: isoNow(),
    rollback_ready: rollbackReady,
    rollback_scope: "xt_w3_25_validated_mainline_only",
    rollback_mode: normalizeString(rollbackLast.mode, "missing"),
    current_release_id: normalizeString(rollbackLast.release_id, "missing"),
    copied_previous_to_current: Number(rollbackLast.copied_previous_to_current) || 0,
    verify_status: normalizeString(rollbackVerify.status, "missing"),
    verify_mode: normalizeString(rollbackVerify.mode, "missing"),
    notes: [
      "Compat rollback artifact mirrors current XT rollback reports and stays fail-closed if apply-mode rollback proof is absent.",
    ],
    evidence_refs: sourceRefs,
    ...buildCompatMetadata("build/reports/xt_w3_25_competitive_rollback.v1.json", sourceRefs),
  };
}

function buildSourceContractCompatArtifact({
  targetArtifact,
  workstreamId,
  title,
  expectedSchemaVersion,
  gateVector,
  sourceRefs,
  notes,
}) {
  return {
    schema_version: "xhub.release_source_contract_compat_artifact.v1",
    generated_at: isoNow(),
    workstream_id: workstreamId,
    title,
    expected_schema_version: expectedSchemaVersion,
    status: "compat_backfill(source_contract_present_runtime_capture_missing)",
    fail_closed: true,
    gate_vector: gateVector,
    notes,
    evidence_refs: sourceRefs,
    ...buildCompatMetadata(targetArtifact, sourceRefs),
  };
}

function buildDirectBindingArtifact({
  targetArtifact,
  workstreamId,
  title,
  workOrderRef,
  releaseDecisionPayload,
  provenancePayload,
}) {
  const sourceRefs = [
    "build/reports/xt_w3_release_ready_decision.v1.json",
    "build/reports/xt_w3_require_real_provenance.v2.json",
    workOrderRef,
  ];
  const releaseStance = normalizeString(provenancePayload.summary?.release_stance, "no_go");
  const bindingStatus =
    releaseDecisionPayload.release_ready === true && releaseStance === "release_ready"
      ? "pass(validated_mainline_release_ready_bound_to_require_real_provenance)"
      : "blocked(require_real_or_release_binding_pending)";
  return {
    schema_version: "xhub.release_direct_require_real_binding.compat.v1",
    generated_at: isoNow(),
    workstream_id: workstreamId,
    title,
    binding_status: bindingStatus,
    release_ready: releaseDecisionPayload.release_ready === true,
    require_real_release_stance: releaseStance,
    notes: [
      "Compat direct-binding artifact links legacy XT slice expectations to the current release decision and require-real provenance bundle.",
    ],
    evidence_refs: sourceRefs,
    ...buildCompatMetadata(targetArtifact, sourceRefs),
  };
}

function buildInternalPassMetricsPayload(inputs) {
  const metrics = {
    schema_version: "xhub_internal_pass_metrics.v1",
    generated_at: isoNow(),
    require_real: true,
    forbid_synthetic: true,
    compatibility_mode: true,
    metric_sources: [],
  };

  const xtGateStatuses = extractXtGateStatuses(inputs.xtGateMarkdown);
  for (const [key, value] of Object.entries(xtGateStatuses)) {
    metrics[key] = value;
    metrics.metric_sources.push({
      metric: key,
      source: "x-terminal/.axcoder/reports/xt-gate-report.md",
    });
  }

  if (inputs.xtReadyGate?.ok === true) {
    for (let i = 0; i <= 5; i += 1) {
      const key = `xt_ready_g${i}_status`;
      metrics[key] = "PASS";
      metrics.metric_sources.push({
        metric: key,
        source: inputs.xtReadyArtifacts?.reportRef || "build/xt_ready_gate_e2e_report.json",
      });
    }
  }

  const doctorCoverage = Number(inputs.doctorReport?.doctor?.non_message_ingress_policy_coverage ?? NaN);
  if (Number.isFinite(doctorCoverage)) {
    metrics.non_message_ingress_policy_coverage = doctorCoverage <= 1 ? doctorCoverage * 100 : doctorCoverage;
    metrics.metric_sources.push({
      metric: "non_message_ingress_policy_coverage",
      source: "x-terminal/.axcoder/reports/doctor-report.json",
    });
  }

  const blockedEventMissRate = Number(inputs.connectorSnapshot?.summary?.blocked_event_miss_rate ?? NaN);
  if (Number.isFinite(blockedEventMissRate)) {
    metrics.blocked_event_miss_rate = blockedEventMissRate;
    metrics.metric_sources.push({
      metric: "blocked_event_miss_rate",
      source: "build/connector_ingress_gate_snapshot.json",
    });
  }

  const runtimeSummary = inputs.runtimeIncidents?.summary || {};
  for (const key of [
    "high_risk_lane_without_grant",
    "high_risk_bypass_count",
    "unaudited_auto_resolution",
  ]) {
    const value = Number(runtimeSummary[key]);
    if (!Number.isFinite(value)) continue;
    metrics[key] = value;
    metrics.metric_sources.push({
      metric: key,
      source: "x-terminal/.axcoder/reports/xt_ready_incident_events.runtime.json",
    });
  }

  const overflow = readJsonIfExists("x-terminal/.axcoder/reports/xt-overflow-fairness-report.json");
  const origin = readJsonIfExists("x-terminal/.axcoder/reports/xt-origin-fallback-report.json");
  const cleanup = readJsonIfExists("x-terminal/.axcoder/reports/xt-dispatch-cleanup-report.json");
  if (Number.isFinite(Number(overflow?.kpi_snapshot?.parent_fork_overflow_silent_fail))) {
    metrics.parent_fork_overflow_silent_fail = Number(overflow.kpi_snapshot.parent_fork_overflow_silent_fail);
    metrics.metric_sources.push({
      metric: "parent_fork_overflow_silent_fail",
      source: "x-terminal/.axcoder/reports/xt-overflow-fairness-report.json",
    });
  }
  if (Number.isFinite(Number(origin?.kpi_snapshot?.route_origin_fallback_violations))) {
    metrics.route_origin_fallback_violations = Number(origin.kpi_snapshot.route_origin_fallback_violations);
    metrics.metric_sources.push({
      metric: "route_origin_fallback_violations",
      source: "x-terminal/.axcoder/reports/xt-origin-fallback-report.json",
    });
  }
  if (Number.isFinite(Number(cleanup?.kpi_snapshot?.dispatch_idle_stuck_incidents))) {
    metrics.dispatch_idle_stuck_incidents = Number(cleanup.kpi_snapshot.dispatch_idle_stuck_incidents);
    metrics.metric_sources.push({
      metric: "dispatch_idle_stuck_incidents",
      source: "x-terminal/.axcoder/reports/xt-dispatch-cleanup-report.json",
    });
  }

  metrics.notes = [
    "Compat internal-pass metrics intentionally materialize only machine-readable values already present in current reports.",
    "Unknown or missing metrics stay absent so the pass-lines checker remains fail-closed.",
  ];
  return {
    ...metrics,
    ...buildCompatMetadata("build/internal_pass_metrics.json", metrics.metric_sources.map((item) => item.source)),
  };
}

function buildInternalPassSamplesPayload() {
  const dbRef = "x-hub/grpc-server/hub_grpc_server/data/hub.sqlite3";
  const sourceRefs = exists(dbRef) ? [dbRef] : [];
  return {
    schema_version: "xhub_internal_pass_samples.v1",
    generated_at: isoNow(),
    require_real: true,
    forbid_synthetic: true,
    compatibility_mode: true,
    source_db_path: abs(dbRef),
    source_refs: sourceRefs,
    extraction_error:
      "compat_exporter_did_not_compute_real_sample_counts; preserve fail-closed until real internal pass sampling is regenerated",
    ...buildCompatMetadata("build/internal_pass_samples.json", sourceRefs),
  };
}

function buildInternalPassReports(inputs = {}) {
  const xtReadyGateReportRef = inputs.xtReadyArtifacts?.reportRef || "build/xt_ready_gate_e2e_report.json";
  const basePaths = {
    xt_report_index: abs("x-terminal/.axcoder/reports/xt-report-index.json"),
    xt_gate_report: abs("x-terminal/.axcoder/reports/xt-gate-report.md"),
    xt_overflow_report: abs("x-terminal/.axcoder/reports/xt-overflow-fairness-report.json"),
    xt_origin_report: abs("x-terminal/.axcoder/reports/xt-origin-fallback-report.json"),
    xt_cleanup_report: abs("x-terminal/.axcoder/reports/xt-dispatch-cleanup-report.json"),
    doctor_report: abs("x-terminal/.axcoder/reports/doctor-report.json"),
    secrets_dry_run_report: abs("x-terminal/.axcoder/reports/secrets-dry-run-report.json"),
    xt_rollback_last_report: abs("x-terminal/.axcoder/reports/xt-rollback-last.json"),
    xt_ready_gate_report: abs(xtReadyGateReportRef),
    xt_ready_evidence_source: abs("build/xt_ready_evidence_source.json"),
    connector_gate_snapshot: abs("build/connector_ingress_gate_snapshot.json"),
    metrics_json: abs("build/internal_pass_metrics.json"),
    sample_summary_json: abs("build/internal_pass_samples.json"),
  };
  const report = checkInternalPassLines({
    paths: basePaths,
    requireRealAudit: true,
    windowLabel: "compat_backfill_current_repo_state",
  });
  const reportWithCompat = {
    ...report,
    compatibility_mode: true,
    ...buildCompatMetadata(
      "build/hub_l5_release_internal_pass_lines_report.json",
      [
        "x-terminal/.axcoder/reports/xt-report-index.json",
        "x-terminal/.axcoder/reports/xt-gate-report.md",
        xtReadyGateReportRef,
        "build/xt_ready_evidence_source.json",
        "build/connector_ingress_gate_snapshot.json",
        "build/internal_pass_metrics.json",
        "build/internal_pass_samples.json",
      ],
    ),
  };
  return reportWithCompat;
}

function run(argv = process.argv) {
  const options = parseArgs(argv);

  const inputs = {
    xtReportIndex: readJsonIfExists("x-terminal/.axcoder/reports/xt-report-index.json"),
    xtGateMarkdown: exists("x-terminal/.axcoder/reports/xt-gate-report.md")
      ? readText("x-terminal/.axcoder/reports/xt-gate-report.md")
      : "",
    requireRealEvidence: readJsonIfExists("build/reports/lpr_w3_03_a_require_real_evidence.v1.json"),
    runtimeIncidents: readJsonIfExists("x-terminal/.axcoder/reports/xt_ready_incident_events.runtime.json"),
    doctorReport: readJsonIfExists("x-terminal/.axcoder/reports/doctor-report.json"),
  };
  inputs.xtReadyArtifacts = selectPreferredXtReadyArtifacts();
  inputs.xtReadyGate = inputs.xtReadyArtifacts.report;
  inputs.xtReadySource = inputs.xtReadyArtifacts.source;
  inputs.xtGateDecision = extractDecisionFromXtGateReport(inputs.xtGateMarkdown);

  const artifacts = [];

  const releaseDecisionArtifact = ensureArtifact(
    "build/reports/xt_w3_release_ready_decision.v1.json",
    () => buildReleaseDecisionPayload(inputs),
    options,
  );
  artifacts.push(releaseDecisionArtifact);

  const xtReadySourceArtifact = ensureArtifact(
    "build/xt_ready_evidence_source.json",
    () => buildXtReadyEvidenceSourcePayload(inputs),
    options,
  );
  artifacts.push(xtReadySourceArtifact);

  const connectorArtifact = ensureArtifact(
    "build/connector_ingress_gate_snapshot.json",
    () => buildConnectorSnapshotPayload(inputs),
    options,
  );
  artifacts.push(connectorArtifact);

  const provenanceArtifact = ensureArtifact(
    "build/reports/xt_w3_require_real_provenance.v2.json",
    () => buildRequireRealProvenancePayload(
      inputs,
      releaseDecisionArtifact.payload,
      xtReadySourceArtifact.payload,
      connectorArtifact.payload,
    ),
    options,
  );
  artifacts.push(provenanceArtifact);

  const rollbackArtifact = ensureArtifact(
    "build/reports/xt_w3_25_competitive_rollback.v1.json",
    () => buildRollbackPayload(),
    options,
  );
  artifacts.push(rollbackArtifact);

  artifacts.push(
    ensureArtifact(
      "build/reports/xt_w3_23_direct_require_real_provenance_binding.v1.json",
      () => buildDirectBindingArtifact({
        targetArtifact: "build/reports/xt_w3_23_direct_require_real_provenance_binding.v1.json",
        workstreamId: "XT-W3-23",
        title: "XT-W3-23 direct require-real provenance binding",
        workOrderRef: "x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md",
        releaseDecisionPayload: releaseDecisionArtifact.payload,
        provenancePayload: provenanceArtifact.payload,
      }),
      options,
    ),
  );

  artifacts.push(
    ensureArtifact(
      "build/reports/xt_w3_24_direct_require_real_provenance_binding.v1.json",
      () => buildDirectBindingArtifact({
        targetArtifact: "build/reports/xt_w3_24_direct_require_real_provenance_binding.v1.json",
        workstreamId: "XT-W3-24",
        title: "XT-W3-24 direct require-real provenance binding",
        workOrderRef: "x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md",
        releaseDecisionPayload: releaseDecisionArtifact.payload,
        provenancePayload: provenanceArtifact.payload,
      }),
      options,
    ),
  );

  artifacts.push(
    ensureArtifact(
      "build/reports/xt_w3_24_e_onboard_bootstrap_evidence.v1.json",
      () => buildSourceContractCompatArtifact({
        targetArtifact: "build/reports/xt_w3_24_e_onboard_bootstrap_evidence.v1.json",
        workstreamId: "XT-W3-24-E",
        title: "XT-W3-24 onboard bootstrap evidence",
        expectedSchemaVersion: "xt.onboard_bootstrap_evidence.v1",
        gateVector: ["XT-CHAN-G1", "XT-CHAN-G5"],
        sourceRefs: [
          "x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md",
          "x-terminal/Sources/Supervisor/MultichannelGatewayProductization.swift",
          "x-terminal/Tests/SupervisorMultichannelGatewayProductizationTests.swift",
        ],
        notes: [
          "Current repo still contains source/test contracts for XT-W3-24 onboarding bootstrap, but the historical captured JSON was missing.",
          "Compat backfill keeps release consumers unblocked without claiming regenerated runtime capture.",
        ],
      }),
      options,
    ),
  );

  artifacts.push(
    ensureArtifact(
      "build/reports/xt_w3_24_f_channel_hub_boundary_evidence.v1.json",
      () => buildSourceContractCompatArtifact({
        targetArtifact: "build/reports/xt_w3_24_f_channel_hub_boundary_evidence.v1.json",
        workstreamId: "XT-W3-24-F",
        title: "XT-W3-24 channel hub boundary evidence",
        expectedSchemaVersion: "xt.channel_hub_boundary_evidence.v1",
        gateVector: ["XT-CHAN-G2", "XT-CHAN-G5", "XT-MEM-G2", "SI-G1", "SI-G2", "SI-G4"],
        sourceRefs: [
          "x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md",
          "x-terminal/Sources/Supervisor/MultichannelGatewayProductization.swift",
          "x-terminal/Tests/SupervisorMultichannelGatewayProductizationTests.swift",
          "docs/xhub-client-modes-and-connectors-v1.md",
        ],
        notes: [
          "Boundary consumers only require a machine-readable artifact ref at this stage.",
          "Fail-closed release gates are still enforced by XT-Ready, require-real provenance, and Hub boundary checks.",
        ],
      }),
      options,
    ),
  );

  artifacts.push(
    ensureArtifact(
      "build/reports/xt_w3_25_e_bootstrap_templates_evidence.v1.json",
      () => buildSourceContractCompatArtifact({
        targetArtifact: "build/reports/xt_w3_25_e_bootstrap_templates_evidence.v1.json",
        workstreamId: "XT-W3-25-E",
        title: "XT-W3-25 bootstrap templates evidence",
        expectedSchemaVersion: "xt.automation_bootstrap_templates_evidence.v1",
        gateVector: ["XT-AUTO-G1", "XT-AUTO-G4"],
        sourceRefs: [
          "x-terminal/work-orders/xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md",
          "x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift",
          "x-terminal/Tests/SupervisorAutomationProductGapClosureTests.swift",
        ],
        notes: [
          "Historical bootstrap-templates capture was absent, so compat exporter pins the source/test contract instead of inventing runtime results.",
        ],
      }),
      options,
    ),
  );

  artifacts.push(
    ensureArtifact(
      "build/internal_pass_metrics.json",
      () => buildInternalPassMetricsPayload({
        ...inputs,
        connectorSnapshot: connectorArtifact.payload,
      }),
      options,
    ),
  );

  artifacts.push(
    ensureArtifact(
      "build/internal_pass_samples.json",
      () => buildInternalPassSamplesPayload(),
      options,
    ),
  );

  const internalPassReport = buildInternalPassReports(inputs);
  artifacts.push(
    ensureArtifact(
      "build/hub_l5_release_internal_pass_lines_report.json",
      () => internalPassReport,
      options,
    ),
  );
  artifacts.push(
    ensureArtifact(
      "build/reports/xt_w3_internal_pass_lines_release_ready.v1.json",
      () => ({
        ...internalPassReport,
        ...buildCompatMetadata(
          "build/reports/xt_w3_internal_pass_lines_release_ready.v1.json",
          internalPassReport.compat_source_refs || [],
        ),
      }),
      options,
    ),
  );

  const manifest = {
    schema_version: "xhub.release_legacy_compat_pack.v1",
    generated_at: isoNow(),
    compatibility_mode: true,
    mainline_chain: MAINLINE_CHAIN,
    outputs: artifacts.map((item) => ({
      ref: item.ref,
      action: item.action,
    })),
    release_summary: {
      release_ready: releaseDecisionArtifact.payload.release_ready === true,
      provenance_release_stance: provenanceArtifact.payload.summary?.release_stance || "missing",
      xt_ready_selected_source: xtReadySourceArtifact.payload.selected_source || "missing",
      connector_source_used: connectorArtifact.payload.source_used || "missing",
      rollback_ready: rollbackArtifact.payload.rollback_ready === true,
      internal_pass_release_decision: internalPassReport.release_decision,
    },
  };
  writeJson("build/reports/release_legacy_compat_pack.v1.json", manifest);

  console.log("ok - wrote legacy release compatibility artifacts");
  for (const output of manifest.outputs) {
    console.log(` - ${output.ref} (${output.action})`);
  }
  console.log(" - build/reports/release_legacy_compat_pack.v1.json (created_compat)");
  return { artifacts, manifest };
}

if (require.main === module) {
  try {
    run(process.argv);
  } catch (error) {
    console.error(`error: ${error.message}`);
    process.exit(1);
  }
}

module.exports = {
  COMPAT_GENERATOR,
  MAINLINE_CHAIN,
  buildConnectorSnapshotPayload,
  buildInternalPassMetricsPayload,
  buildInternalPassReports,
  buildInternalPassSamplesPayload,
  buildReleaseDecisionPayload,
  buildRequireRealProvenancePayload,
  buildRollbackPayload,
  buildXtReadyEvidenceSourcePayload,
  extractDecisionFromXtGateReport,
  extractXtGateStatuses,
  isCompatManaged,
  run,
};
