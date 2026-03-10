#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const {
  REQUIRED_INCIDENT_CODES,
  parseEventType,
} = require("./m3_generate_xt_ready_e2e_evidence.js");

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

function readJson(filePath) {
  return JSON.parse(String(fs.readFileSync(filePath, "utf8") || "{}"));
}

function writeText(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, String(content || ""), "utf8");
}

function toIntLike(value, fallback = -1) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.floor(n);
}

function firstInt(values = [], fallback = -1) {
  for (const value of values) {
    const n = toIntLike(value, -1);
    if (n >= 0) return n;
  }
  return fallback;
}

function parseJsonLike(value) {
  if (!value) return {};
  if (value && typeof value === "object") return value;
  const raw = String(value || "").trim();
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

function normalizeConnectorGateSnapshot(input = {}) {
  const src = input && typeof input === "object" ? input : {};

  if (src.snapshot && typeof src.snapshot === "object") {
    return {
      source_used: String(src.source_used || "").trim(),
      snapshot: src.snapshot,
    };
  }

  if (src.response && typeof src.response === "object" && src.response.snapshot && typeof src.response.snapshot === "object") {
    return {
      source_used: String(src.response.source_used || src.source_used || "").trim(),
      snapshot: src.response.snapshot,
    };
  }

  if (src.connector_ingress_gate_snapshot && typeof src.connector_ingress_gate_snapshot === "object") {
    return normalizeConnectorGateSnapshot(src.connector_ingress_gate_snapshot);
  }

  if (src.connector_ingress_gate && typeof src.connector_ingress_gate === "object") {
    return normalizeConnectorGateSnapshot(src.connector_ingress_gate);
  }

  return {
    source_used: "",
    snapshot: null,
  };
}

function normalizeAuditRows(payload = {}) {
  if (Array.isArray(payload)) return payload;
  const obj = payload && typeof payload === "object" ? payload : {};
  if (Array.isArray(obj.events)) return obj.events;
  if (Array.isArray(obj.items)) return obj.items;
  if (Array.isArray(obj.rows)) return obj.rows;
  return [];
}

function deriveSummary(events = [], summary = {}, connectorGateSnapshot = null) {
  const src = summary && typeof summary === "object" ? summary : {};
  const gate = connectorGateSnapshot && typeof connectorGateSnapshot === "object"
    ? connectorGateSnapshot
    : {};
  const gateMetrics = gate.snapshot && typeof gate.snapshot === "object"
    && gate.snapshot.metrics && typeof gate.snapshot.metrics === "object"
    ? gate.snapshot.metrics
    : {};

  const highRiskLaneWithoutGrant = (() => {
    const n = toIntLike(src.high_risk_lane_without_grant, -1);
    if (n >= 0) return n;
    return 0;
  })();

  const unauditedAutoResolution = (() => {
    const n = toIntLike(src.unaudited_auto_resolution, -1);
    if (n >= 0) return n;
    return events.filter((row) =>
      String(row?.event_type || "").endsWith(".handled")
      && !String(row?.audit_ref || "").trim()
    ).length;
  })();

  const highRiskBypassCount = (() => {
    const n = toIntLike(src.high_risk_bypass_count, -1);
    if (n >= 0) return n;
    return events.filter((row) => row?.bypass_high_risk === true).length;
  })();

  const blockedEventMissRate = (() => {
    const raw = Number(src.blocked_event_miss_rate);
    if (Number.isFinite(raw) && raw >= 0) return raw;
    const fromGate = Number(gateMetrics.blocked_event_miss_rate);
    if (Number.isFinite(fromGate) && fromGate >= 0) return fromGate;
    return 0;
  })();

  const nonMessageCoverage = (() => {
    const raw = Number(src.non_message_ingress_policy_coverage);
    if (Number.isFinite(raw) && raw >= 0) return raw;
    const fromGate = Number(gateMetrics.non_message_ingress_policy_coverage);
    if (Number.isFinite(fromGate) && fromGate >= 0) return fromGate;
    return 0;
  })();

  return {
    high_risk_lane_without_grant: highRiskLaneWithoutGrant,
    unaudited_auto_resolution: unauditedAutoResolution,
    high_risk_bypass_count: highRiskBypassCount,
    blocked_event_miss_rate: blockedEventMissRate,
    non_message_ingress_policy_coverage: nonMessageCoverage,
  };
}

function buildIncidentEventsFromAudit(payload = {}, opts = {}) {
  const strict = !!opts.strict;
  const runIdArg = String(opts.run_id || "").trim();
  const source = payload && typeof payload === "object" ? payload : {};
  const auditRows = normalizeAuditRows(source);
  const sourceMeta = source.source && typeof source.source === "object" ? source.source : {};
  const events = [];

  const sorted = auditRows
    .map((row, idx) => ({
      idx,
      row: row && typeof row === "object" ? row : {},
      t: firstInt([
        row?.created_at_ms,
        row?.timestamp_ms,
      ], -1),
    }))
    .sort((a, b) => {
      if (a.t >= 0 && b.t >= 0 && a.t !== b.t) return a.t - b.t;
      if (a.t >= 0 && b.t < 0) return -1;
      if (a.t < 0 && b.t >= 0) return 1;
      return a.idx - b.idx;
    })
    .map((x) => x.row);

  for (const row of sorted) {
    const eventType = String(row?.event_type || "").trim();
    const parsed = parseEventType(eventType);
    if (!parsed.incident_code || !parsed.phase) continue;

    const ext = parseJsonLike(row?.ext_json || row?.ext || row?.payload);
    const laneId = String(
      ext.lane_id
      || ext.parallel_lane_id
      || ext.lane
      || row?.lane_id
      || row?.project_id
      || ""
    ).trim();
    const detectedAtMs = firstInt([ext.detected_at_ms, row?.detected_at_ms], -1);
    const handledAtMs = firstInt([ext.handled_at_ms, row?.handled_at_ms, row?.created_at_ms], -1);
    const ts = firstInt([row?.created_at_ms, row?.timestamp_ms, detectedAtMs, handledAtMs], -1);

    const event = {
      timestamp_ms: ts >= 0 ? ts : undefined,
      event_type: eventType,
      incident_code: parsed.incident_code,
      lane_id: laneId || undefined,
    };

    if (parsed.phase === "handled") {
      event.detected_at_ms = detectedAtMs >= 0 ? detectedAtMs : undefined;
      event.handled_at_ms = handledAtMs >= 0 ? handledAtMs : undefined;
      const denyCode = String(
        row?.error_code
        || row?.deny_code
        || ext.deny_code
        || parsed.incident_code
        || ""
      ).trim();
      event.deny_code = denyCode || parsed.incident_code;
      event.audit_event_type = String(
        ext.audit_event_type
        || row?.audit_event_type
        || "supervisor.incident.handled"
      ).trim();
      event.audit_ref = String(
        ext.audit_ref
        || row?.audit_ref
        || ext.audit_event_id
        || row?.event_id
        || ""
      ).trim();
      if (ext.bypass_high_risk === true) event.bypass_high_risk = true;
    }

    events.push(event);
  }

  if (strict) {
    const missing = [];
    const duplicates = [];
    for (const code of REQUIRED_INCIDENT_CODES) {
      const handledCount = events.filter(
        (row) => String(row?.incident_code || "") === code
          && String(row?.event_type || "").endsWith(".handled")
      ).length;
      if (handledCount <= 0) missing.push(code);
      if (handledCount > 1) duplicates.push(`${code}:${handledCount}`);
    }
    if (missing.length > 0) {
      throw new Error(`missing required incident handled event(s): ${missing.join(", ")}`);
    }
    if (duplicates.length > 0) {
      throw new Error(`duplicate required incident handled event(s): ${duplicates.join(", ")}`);
    }
  }

  const runId = runIdArg || String(source.run_id || "").trim() || `xt_ready_audit_extract_${Date.now()}`;
  const connectorGatePayload = opts.connector_gate_payload
    || source.connector_ingress_gate_snapshot
    || source.connector_ingress_gate
    || null;
  const connectorGate = normalizeConnectorGateSnapshot(connectorGatePayload);
  const summary = deriveSummary(events, source.summary || {}, connectorGate);
  const connectorGateMetrics = connectorGate.snapshot
    && typeof connectorGate.snapshot === "object"
    && connectorGate.snapshot.metrics
    && typeof connectorGate.snapshot.metrics === "object"
    ? connectorGate.snapshot.metrics
    : {};
  const auditSourceKind = String(sourceMeta.kind || source.kind || "").trim();
  const auditGeneratedBy = String(sourceMeta.generated_by || source.generated_by || "").trim();
  const syntheticMarkers = [];
  if (String(auditSourceKind || "").toLowerCase().includes("synthetic")) {
    syntheticMarkers.push(`kind:${auditSourceKind}`);
  }
  if (String(auditGeneratedBy || "").toLowerCase().includes("smoke")) {
    syntheticMarkers.push(`generated_by:${auditGeneratedBy}`);
  }
  const smokeAuditRefCount = events.filter((row) => {
    const eventType = String(row?.event_type || "").trim().toLowerCase();
    if (!eventType.endsWith(".handled")) return false;
    const auditRef = String(row?.audit_ref || "").trim().toLowerCase();
    return auditRef.startsWith("audit-smoke-");
  }).length;
  if (smokeAuditRefCount > 0) {
    syntheticMarkers.push(`audit_ref_prefix:audit-smoke (${smokeAuditRefCount})`);
  }
  const syntheticRuntimeEvidence = syntheticMarkers.length > 0;

  return {
    run_id: runId,
    summary,
    events,
    source: {
      audit_row_total: auditRows.length,
      incident_event_total: events.length,
      connector_gate_snapshot_attached: !!connectorGate.snapshot,
      connector_gate_source_used: connectorGate.source_used || "",
      connector_gate_non_message_ingress_policy_coverage: Number.isFinite(Number(connectorGateMetrics.non_message_ingress_policy_coverage))
        ? Number(connectorGateMetrics.non_message_ingress_policy_coverage)
        : undefined,
      connector_gate_blocked_event_miss_rate: Number.isFinite(Number(connectorGateMetrics.blocked_event_miss_rate))
        ? Number(connectorGateMetrics.blocked_event_miss_rate)
        : undefined,
      audit_source_kind: auditSourceKind || undefined,
      audit_generated_by: auditGeneratedBy || undefined,
      synthetic_runtime_evidence: syntheticRuntimeEvidence,
      synthetic_markers: syntheticMarkers,
    },
  };
}

function runCli(argv = process.argv) {
  const args = parseArgs(argv);
  const inPath = String(args["audit-json"] || "").trim();
  const outPath = String(args["out-json"] || "").trim();
  if (!inPath) throw new Error("missing --audit-json");
  if (!outPath) throw new Error("missing --out-json");

  const payload = readJson(path.resolve(inPath));
  const connectorGatePath = String(args["connector-gate-json"] || "").trim();
  const connectorGatePayload = connectorGatePath ? readJson(path.resolve(connectorGatePath)) : null;
  const strict = String(args.strict || "").trim() !== "";
  const runId = String(args["run-id"] || "").trim();
  const out = buildIncidentEventsFromAudit(payload, {
    strict,
    run_id: runId,
    connector_gate_payload: connectorGatePayload,
  });
  writeText(path.resolve(outPath), `${JSON.stringify(out, null, 2)}\n`);
  console.log(
    `ok - XT-Ready incident events extracted (events=${out.events.length}, strict=${strict ? "yes" : "no"}, connector_gate=${connectorGatePayload ? "yes" : "no"}, out=${outPath})`
  );
  return out;
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
  buildIncidentEventsFromAudit,
  normalizeConnectorGateSnapshot,
  normalizeAuditRows,
  parseJsonLike,
  runCli,
};
