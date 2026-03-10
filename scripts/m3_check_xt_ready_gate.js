#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const DEFAULT_XT_READY_DOC = "docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md";
const DEFAULT_M3_DOC = "docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md";
const DEFAULT_EXEC_PLAN_DOC = "docs/memory-new/xhub-memory-v3-execution-plan.md";
const DEFAULT_WORKING_INDEX_DOC = "docs/WORKING_INDEX.md";
const DEFAULT_X_MEMORY_DOC = "X_MEMORY.md";
const DEFAULT_XT_PARALLEL_DOC = "x-terminal/work-orders/xterminal-parallel-work-orders-v1.md";
const DEFAULT_XT_SUPERVISOR_DOC = "x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md";

const DEFAULT_MAX_TAKEOVER_MS = 2000;
const EXPECTED_INCIDENT_ASSERTIONS = {
  grant_pending: {
    event_type: "supervisor.incident.grant_pending.handled",
    deny_code: "grant_pending",
  },
  awaiting_instruction: {
    event_type: "supervisor.incident.awaiting_instruction.handled",
    deny_code: "awaiting_instruction",
  },
  runtime_error: {
    event_type: "supervisor.incident.runtime_error.handled",
    deny_code: "runtime_error",
  },
};

const DOC_RULES = [
  { key: "xt_ready_doc", pattern: "XT-Ready-G0", reason: "XT-Ready doc includes G0" },
  { key: "xt_ready_doc", pattern: "XT-Ready-G5", reason: "XT-Ready doc includes G5" },
  { key: "xt_ready_doc", pattern: "grant_pending", reason: "XT-Ready doc includes grant_pending" },
  { key: "xt_ready_doc", pattern: "awaiting_instruction", reason: "XT-Ready doc includes awaiting_instruction" },
  { key: "xt_ready_doc", pattern: "runtime_error", reason: "XT-Ready doc includes runtime_error" },
  { key: "xt_ready_doc", pattern: "机器可判定断言", reason: "XT-Ready doc includes machine-check assertion section" },
  { key: "xt_ready_doc", pattern: "scripts/m3_check_xt_ready_gate.js", reason: "XT-Ready doc includes checker command list" },
  { key: "xt_ready_doc", pattern: "scripts/m3_resolve_xt_ready_audit_input.js", reason: "XT-Ready doc includes audit input resolver command" },
  { key: "xt_ready_doc", pattern: "scripts/m3_export_xt_ready_audit_from_db.js", reason: "XT-Ready doc includes local sqlite audit export command" },
  { key: "xt_ready_doc", pattern: "scripts/m3_generate_xt_ready_e2e_evidence.js", reason: "XT-Ready doc includes runtime evidence generator command" },
  { key: "xt_ready_doc", pattern: "scripts/m3_extract_xt_ready_incident_events_from_audit.js", reason: "XT-Ready doc includes audit-to-incident extraction command" },
  { key: "xt_ready_doc", pattern: "scripts/m3_fetch_connector_ingress_gate_snapshot.js", reason: "XT-Ready doc includes connector ingress gate snapshot fetch command" },
  { key: "xt_ready_doc", pattern: "scripts/fixtures/xt_ready_incident_events.sample.json", reason: "XT-Ready doc binds canonical incident replay fixture" },
  { key: "xt_ready_doc", pattern: "scripts/fixtures/xt_ready_audit_events.sample.json", reason: "XT-Ready doc binds sample audit fallback fixture" },
  { key: "m3_doc", pattern: "Gate-M3-XT-Ready", reason: "M3 work-orders bind XT-Ready gate" },
  { key: "exec_plan_doc", pattern: "XT-Ready-G0..G5", reason: "execution plan DoD binds XT-Ready" },
  { key: "exec_plan_doc", pattern: "dispatch_rejected", reason: "execution plan lineage snapshot includes dispatch_rejected" },
  { key: "exec_plan_doc", pattern: "CT-DIS-D007", reason: "execution plan lineage snapshot includes CT-DIS-D007 mapping" },
  { key: "working_index_doc", pattern: "xhub-hub-to-xterminal-capability-gate-v1.md", reason: "WORKING_INDEX links XT-Ready doc" },
  { key: "working_index_doc", pattern: "scripts/m3_resolve_xt_ready_audit_input.js", reason: "WORKING_INDEX links XT-Ready audit input resolver" },
  { key: "working_index_doc", pattern: "scripts/m3_export_xt_ready_audit_from_db.js", reason: "WORKING_INDEX links XT-Ready sqlite audit exporter" },
  { key: "x_memory_doc", pattern: "xhub-hub-to-xterminal-capability-gate-v1.md", reason: "X_MEMORY links XT-Ready doc" },
  { key: "x_memory_doc", pattern: "scripts/m3_resolve_xt_ready_audit_input.js", reason: "X_MEMORY links XT-Ready audit input resolver" },
  { key: "x_memory_doc", pattern: "scripts/m3_export_xt_ready_audit_from_db.js", reason: "X_MEMORY links XT-Ready sqlite audit exporter" },
  { key: "xt_parallel_doc", pattern: "xhub-hub-to-xterminal-capability-gate-v1.md", reason: "x-terminal global work-order binds XT-Ready doc" },
  { key: "xt_supervisor_doc", pattern: "XT-Ready-G0..G5", reason: "supervisor special work-order binds XT-Ready gates" },
];

function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i += 1) {
    const cur = String(argv[i] || "");
    if (!cur.startsWith("--")) continue;
    const key = cur.slice(2);
    const nxt = argv[i + 1];
    if (nxt && !String(nxt).startsWith("--")) {
      out[key] = String(nxt);
      i += 1;
    } else {
      out[key] = "1";
    }
  }
  return out;
}

function readText(filePath) {
  return String(fs.readFileSync(filePath, "utf8") || "");
}

function readJson(filePath) {
  const raw = readText(filePath);
  return JSON.parse(raw);
}

function writeText(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, String(content || ""), "utf8");
}

function toIntLike(value, fallback = 0) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.floor(n);
}

function resolveDocPaths(args = {}) {
  return {
    xt_ready_doc: path.resolve(args["xt-ready-doc"] || DEFAULT_XT_READY_DOC),
    m3_doc: path.resolve(args["m3-doc"] || DEFAULT_M3_DOC),
    exec_plan_doc: path.resolve(args["exec-plan-doc"] || DEFAULT_EXEC_PLAN_DOC),
    working_index_doc: path.resolve(args["working-index-doc"] || DEFAULT_WORKING_INDEX_DOC),
    x_memory_doc: path.resolve(args["x-memory-doc"] || DEFAULT_X_MEMORY_DOC),
    xt_parallel_doc: path.resolve(args["xt-parallel-doc"] || DEFAULT_XT_PARALLEL_DOC),
    xt_supervisor_doc: path.resolve(args["xt-supervisor-doc"] || DEFAULT_XT_SUPERVISOR_DOC),
  };
}

function checkDocBindings(docPaths = {}) {
  const errors = [];
  const warnings = [];
  const details = [];
  for (const rule of DOC_RULES) {
    const filePath = String(docPaths[rule.key] || "").trim();
    if (!filePath) {
      errors.push(`missing doc path for rule key: ${rule.key}`);
      continue;
    }
    if (!fs.existsSync(filePath)) {
      errors.push(`missing doc file: ${filePath}`);
      continue;
    }
    const text = readText(filePath);
    const hasPattern = text.includes(rule.pattern);
    details.push({
      file: filePath,
      pattern: rule.pattern,
      reason: rule.reason,
      ok: hasPattern,
    });
    if (!hasPattern) {
      errors.push(`doc contract check failed: ${rule.reason} (${path.relative(process.cwd(), filePath)} missing '${rule.pattern}')`);
    }
  }
  if (!details.length) {
    warnings.push("doc contract checker produced no rule details");
  }
  return {
    ok: errors.length === 0,
    errors,
    warnings,
    details,
  };
}

function inferTakeoverLatencyMs(incident = {}) {
  const explicit = Number(incident.takeover_latency_ms);
  if (Number.isFinite(explicit) && explicit >= 0) return Math.floor(explicit);
  const detectedAt = Number(incident.detected_at_ms);
  const handledAt = Number(incident.handled_at_ms);
  if (Number.isFinite(detectedAt) && Number.isFinite(handledAt) && handledAt >= detectedAt) {
    return Math.floor(handledAt - detectedAt);
  }
  return -1;
}

function checkE2EEvidence(evidence = {}, opts = {}) {
  const errors = [];
  const warnings = [];
  const maxTakeoverMs = Math.max(100, toIntLike(opts.max_takeover_ms, DEFAULT_MAX_TAKEOVER_MS));
  const exactRequiredIncidents = !!opts.exact_required_incidents;
  const requireRealAuditSource = !!opts.require_real_audit_source;
  const payload = evidence && typeof evidence === "object" ? evidence : {};
  const incidents = Array.isArray(payload.incidents) ? payload.incidents : [];
  const summary = payload.summary && typeof payload.summary === "object" ? payload.summary : {};
  const source = payload.source && typeof payload.source === "object" ? payload.source : {};
  const schemaVersion = String(payload.schema_version || "").trim();
  const requiredIncidentCodes = Object.keys(EXPECTED_INCIDENT_ASSERTIONS);
  const unknownIncidentCodes = new Set();

  if (!schemaVersion) {
    warnings.push("e2e evidence schema_version is empty");
  } else if (schemaVersion !== "xt_ready_e2e.v1") {
    warnings.push(`unexpected e2e schema_version: ${schemaVersion}`);
  }
  if (incidents.length === 0) {
    errors.push("e2e evidence incidents is empty");
  }

  const details = [];
  const sourceAuditKind = String(source.audit_source_kind || "").trim().toLowerCase();
  const sourceGeneratedBy = String(source.audit_generated_by || "").trim().toLowerCase();
  const sourceSyntheticRuntimeEvidence = source.synthetic_runtime_evidence === true;
  const sourceSyntheticMarkers = Array.isArray(source.synthetic_markers)
    ? source.synthetic_markers.map((x) => String(x || "").trim()).filter(Boolean)
    : [];
  incidents.forEach((row, idx) => {
    const incidentCode = String(row?.incident_code || "").trim();
    if (!incidentCode) {
      errors.push(`incident row #${idx} missing incident_code`);
      return;
    }
    if (!Object.prototype.hasOwnProperty.call(EXPECTED_INCIDENT_ASSERTIONS, incidentCode)) {
      unknownIncidentCodes.add(incidentCode);
    }
  });

  if (unknownIncidentCodes.size > 0) {
    const joined = Array.from(unknownIncidentCodes).sort().join(", ");
    if (exactRequiredIncidents) {
      errors.push(`e2e evidence includes unsupported incident_code(s): ${joined}`);
    } else {
      warnings.push(`e2e evidence includes unsupported incident_code(s): ${joined}`);
    }
  }

  for (const [incidentCode, expected] of Object.entries(EXPECTED_INCIDENT_ASSERTIONS)) {
    const rows = incidents.filter((row) => String(row?.incident_code || "").trim() === incidentCode);
    if (rows.length <= 0) {
      errors.push(`e2e evidence missing required incident_code: ${incidentCode}`);
      continue;
    }
    if (exactRequiredIncidents && rows.length !== 1) {
      errors.push(`e2e evidence incident_code ${incidentCode} must appear exactly once in strict mode, got ${rows.length}`);
    }
    for (const row of rows) {
      const eventType = String(row?.event_type || "").trim();
      const denyCode = String(row?.deny_code || "").trim();
      const auditRef = String(row?.audit_ref || "").trim();
      const auditEventType = String(row?.audit_event_type || "").trim();
      const laneId = String(row?.lane_id || "").trim();
      const latencyMs = inferTakeoverLatencyMs(row);
      const itemErrors = [];

      if (eventType !== expected.event_type) {
        itemErrors.push(`incident ${incidentCode} lane=${laneId || "~"} event_type mismatch: expected '${expected.event_type}', got '${eventType || "~"}'`);
      }
      if (denyCode !== expected.deny_code) {
        itemErrors.push(`incident ${incidentCode} lane=${laneId || "~"} deny_code mismatch: expected '${expected.deny_code}', got '${denyCode || "~"}'`);
      }
      if (!auditEventType) {
        itemErrors.push(`incident ${incidentCode} lane=${laneId || "~"} missing audit_event_type`);
      }
      if (!auditRef) {
        itemErrors.push(`incident ${incidentCode} lane=${laneId || "~"} missing audit_ref`);
      } else if (requireRealAuditSource && /^audit-smoke-/i.test(auditRef)) {
        itemErrors.push(`incident ${incidentCode} lane=${laneId || "~"} uses synthetic audit_ref '${auditRef}'`);
      }
      if (!Number.isFinite(latencyMs) || latencyMs < 0) {
        itemErrors.push(`incident ${incidentCode} lane=${laneId || "~"} missing takeover latency`);
      } else if (latencyMs > maxTakeoverMs) {
        itemErrors.push(`incident ${incidentCode} lane=${laneId || "~"} takeover latency ${latencyMs}ms > ${maxTakeoverMs}ms`);
      }
      if (row && row.bypass_high_risk === true) {
        itemErrors.push(`incident ${incidentCode} lane=${laneId || "~"} marked bypass_high_risk=true`);
      }

      details.push({
        incident_code: incidentCode,
        lane_id: laneId,
        event_type: eventType,
        deny_code: denyCode,
        audit_event_type: auditEventType,
        has_audit_ref: !!auditRef,
        takeover_latency_ms: latencyMs,
        ok: itemErrors.length === 0,
      });
      for (const msg of itemErrors) errors.push(msg);
    }
  }

  if (exactRequiredIncidents && incidents.length !== requiredIncidentCodes.length) {
    errors.push(
      `strict e2e expects exactly ${requiredIncidentCodes.length} incidents, got ${incidents.length}`
    );
  }

  const highRiskWithoutGrant = toIntLike(summary.high_risk_lane_without_grant, 0);
  if (highRiskWithoutGrant !== 0) {
    errors.push(`summary.high_risk_lane_without_grant must be 0, got ${highRiskWithoutGrant}`);
  }
  const unauditedAutoResolution = toIntLike(summary.unaudited_auto_resolution, 0);
  if (unauditedAutoResolution !== 0) {
    errors.push(`summary.unaudited_auto_resolution must be 0, got ${unauditedAutoResolution}`);
  }
  const bypassCount = toIntLike(summary.high_risk_bypass_count, 0);
  if (bypassCount !== 0) {
    errors.push(`summary.high_risk_bypass_count must be 0, got ${bypassCount}`);
  }
  const blockedLeakRate = Number(summary.blocked_event_miss_rate || 0);
  if (Number.isFinite(blockedLeakRate) && blockedLeakRate >= 0.01) {
    errors.push(`summary.blocked_event_miss_rate must be < 0.01, got ${blockedLeakRate}`);
  }
  const nonMessageCoverage = Number(summary.non_message_ingress_policy_coverage);
  if (!Number.isFinite(nonMessageCoverage) || nonMessageCoverage < 1) {
    errors.push(`summary.non_message_ingress_policy_coverage must be >= 1, got ${summary.non_message_ingress_policy_coverage}`);
  }

  if (requireRealAuditSource) {
    const gateSnapshotAttached = source.connector_gate_snapshot_attached === true;
    const gateSourceUsed = String(source.connector_gate_source_used || "").trim().toLowerCase();
    if (!gateSnapshotAttached) {
      errors.push("require-real-audit-source enabled but e2e evidence source.connector_gate_snapshot_attached is not true");
    }
    if (gateSourceUsed !== "audit") {
      errors.push(
        `require-real-audit-source enabled but e2e evidence source.connector_gate_source_used is '${gateSourceUsed || "~"}' (expected 'audit')`
      );
    }
    if (sourceSyntheticRuntimeEvidence) {
      errors.push("require-real-audit-source enabled but e2e evidence source.synthetic_runtime_evidence is true");
    }
    if (sourceAuditKind.includes("synthetic")) {
      errors.push(
        `require-real-audit-source enabled but e2e evidence source.audit_source_kind is '${sourceAuditKind}'`
      );
    }
    if (sourceGeneratedBy.includes("smoke")) {
      errors.push(
        `require-real-audit-source enabled but e2e evidence source.audit_generated_by is '${sourceGeneratedBy}'`
      );
    }
    if (sourceSyntheticMarkers.length > 0) {
      errors.push(
        `require-real-audit-source enabled but e2e evidence source.synthetic_markers is not empty: ${sourceSyntheticMarkers.join(", ")}`
      );
    }
  }

  return {
    ok: errors.length === 0,
    errors,
    warnings,
    details,
    summary: {
      schema_version: schemaVersion,
      incident_total: incidents.length,
      required_incident_total: requiredIncidentCodes.length,
      exact_required_incidents: exactRequiredIncidents,
      require_real_audit_source: requireRealAuditSource,
      max_takeover_ms: maxTakeoverMs,
      validation_passed: errors.length === 0,
    },
  };
}

function checkEvidenceSource(evidenceSource = {}, opts = {}) {
  const errors = [];
  const warnings = [];
  const allowedSources = new Set([
    "real_audit_export_env",
    "real_audit_export_build",
    "sample_fixture",
  ]);
  const requireRealAuditSource = !!opts.require_real_audit_source;
  const payload = evidenceSource && typeof evidenceSource === "object" ? evidenceSource : {};
  const selectedSource = String(payload.selected_source || "").trim();
  const selectedAuditJson = String(payload.selected_audit_json || "").trim();
  const selectedAuditJsonResolved = String(payload.selected_audit_json_resolved || "").trim();
  const selectedAuditPath = path.resolve(selectedAuditJson || selectedAuditJsonResolved || ".");
  const selectedPathExists = selectedAuditJson || selectedAuditJsonResolved
    ? fs.existsSync(selectedAuditPath)
    : false;

  if (!selectedSource) {
    errors.push("evidence source missing selected_source");
  } else if (!allowedSources.has(selectedSource)) {
    errors.push(`evidence source has unsupported selected_source: ${selectedSource}`);
  }

  if (!selectedAuditJson && !selectedAuditJsonResolved) {
    errors.push("evidence source missing selected_audit_json");
  } else if (!selectedPathExists) {
    errors.push(`evidence source selected audit json does not exist: ${selectedAuditJson || selectedAuditJsonResolved}`);
  }

  if (requireRealAuditSource && selectedSource === "sample_fixture") {
    errors.push("require-real-audit-source enabled but evidence source selected sample_fixture");
  }

  return {
    ok: errors.length === 0,
    errors,
    warnings,
    details: {
      selected_source: selectedSource,
      selected_audit_json: selectedAuditJson || selectedAuditJsonResolved,
      selected_path_exists: selectedPathExists,
      require_real_audit_source: requireRealAuditSource,
    },
  };
}

function checkXtReadyGate({
  docPaths = {},
  e2eEvidence = null,
  evidenceSource = null,
  strictE2E = false,
  requireRealAuditSource = false,
  maxTakeoverMs = DEFAULT_MAX_TAKEOVER_MS,
} = {}) {
  const errors = [];
  const warnings = [];

  const docReport = checkDocBindings(docPaths);
  for (const msg of docReport.errors) errors.push(msg);
  for (const msg of docReport.warnings) warnings.push(msg);

  let e2eReport = null;
  if (e2eEvidence != null) {
    e2eReport = checkE2EEvidence(e2eEvidence, {
      max_takeover_ms: maxTakeoverMs,
      exact_required_incidents: strictE2E,
      require_real_audit_source: requireRealAuditSource,
    });
    for (const msg of e2eReport.errors) errors.push(msg);
    for (const msg of e2eReport.warnings) warnings.push(msg);
  } else if (strictE2E) {
    errors.push("strict E2E enabled but missing --e2e-evidence file");
  } else {
    warnings.push("missing --e2e-evidence: only doc contract checks were executed");
  }

  let evidenceSourceReport = null;
  if (evidenceSource != null) {
    evidenceSourceReport = checkEvidenceSource(evidenceSource, {
      require_real_audit_source: requireRealAuditSource,
    });
    for (const msg of evidenceSourceReport.errors) errors.push(msg);
    for (const msg of evidenceSourceReport.warnings) warnings.push(msg);
  } else if (requireRealAuditSource) {
    errors.push("require-real-audit-source enabled but missing --evidence-source file");
  }

  return {
    ok: errors.length === 0,
    errors,
    warnings,
    strict_e2e: !!strictE2E,
    require_real_audit_source: !!requireRealAuditSource,
    doc_report: docReport,
    e2e_report: e2eReport,
    evidence_source_report: evidenceSourceReport,
    summary: {
      doc_rule_total: DOC_RULES.length,
      doc_rule_passed: docReport.details.filter((x) => !!x.ok).length,
      e2e_checked: !!e2eReport,
      evidence_source_checked: !!evidenceSourceReport,
      validation_passed: errors.length === 0,
    },
  };
}

function runCli(argv = process.argv) {
  const args = parseArgs(argv);
  const docPaths = resolveDocPaths(args);
  const strictE2E = String(args["strict-e2e"] || "").trim() !== "";
  const requireRealAuditSource = String(args["require-real-audit-source"] || "").trim() !== "";
  const maxTakeoverMs = Math.max(100, toIntLike(args["max-takeover-ms"], DEFAULT_MAX_TAKEOVER_MS));
  const e2eEvidencePath = String(args["e2e-evidence"] || "").trim();
  const evidenceSourcePath = String(args["evidence-source"] || "").trim();
  const outJsonPath = String(args["out-json"] || "").trim();
  const e2eEvidence = e2eEvidencePath ? readJson(path.resolve(e2eEvidencePath)) : null;
  const evidenceSource = evidenceSourcePath ? readJson(path.resolve(evidenceSourcePath)) : null;

  const report = checkXtReadyGate({
    docPaths,
    e2eEvidence,
    evidenceSource,
    strictE2E,
    requireRealAuditSource,
    maxTakeoverMs,
  });

  if (outJsonPath) {
    writeText(path.resolve(outJsonPath), `${JSON.stringify(report, null, 2)}\n`);
  }

  if (!report.ok) {
    throw new Error(`XT-Ready gate check failed: ${report.errors.join(" | ")}`);
  }

  for (const warning of report.warnings) {
    console.warn(`warn - ${warning}`);
  }

  console.log(
    `ok - XT-Ready gate passed (doc_rules=${report.summary.doc_rule_passed}/${report.summary.doc_rule_total}, e2e_checked=${report.summary.e2e_checked ? "yes" : "no"}, strict_e2e=${report.strict_e2e ? "yes" : "no"})`
  );
  return report;
}

if (require.main === module) {
  try {
    runCli(process.argv);
  } catch (err) {
    console.error(`error: ${err.message}`);
    process.exit(1);
  }
}

module.exports = {
  DOC_RULES,
  EXPECTED_INCIDENT_ASSERTIONS,
  checkDocBindings,
  checkEvidenceSource,
  checkE2EEvidence,
  checkXtReadyGate,
  inferTakeoverLatencyMs,
  parseArgs,
  resolveDocPaths,
  runCli,
};
