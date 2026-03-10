#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const REQUIRED_INCIDENT_CODES = [
  "grant_pending",
  "awaiting_instruction",
  "runtime_error",
];

const EXPECTED_EVENT_TYPES = {
  grant_pending: "supervisor.incident.grant_pending.handled",
  awaiting_instruction: "supervisor.incident.awaiting_instruction.handled",
  runtime_error: "supervisor.incident.runtime_error.handled",
};

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

function normalizeIncidentCode(value = "") {
  const raw = String(value || "").trim().toLowerCase();
  if (!raw) return "";
  if (REQUIRED_INCIDENT_CODES.includes(raw)) return raw;
  return "";
}

function parseEventType(type = "") {
  const raw = String(type || "").trim();
  const match = /^supervisor\.incident\.([a-z_]+)\.(detected|handled)$/i.exec(raw);
  if (!match) return { incident_code: "", phase: "" };
  const incident_code = normalizeIncidentCode(match[1]);
  const phase = String(match[2] || "").toLowerCase();
  return { incident_code, phase };
}

function eventTimestampMs(event = {}) {
  const candidates = [
    event.timestamp_ms,
    event.created_at_ms,
    event.detected_at_ms,
    event.handled_at_ms,
  ];
  for (const item of candidates) {
    const n = toIntLike(item, -1);
    if (n >= 0) return n;
  }
  return -1;
}

function stableSortEvents(events = []) {
  const arr = Array.isArray(events) ? events.slice() : [];
  return arr
    .map((event, idx) => ({
      idx,
      event: event && typeof event === "object" ? event : {},
      t: eventTimestampMs(event),
    }))
    .sort((a, b) => {
      const at = a.t;
      const bt = b.t;
      if (at >= 0 && bt >= 0 && at !== bt) return at - bt;
      if (at >= 0 && bt < 0) return -1;
      if (at < 0 && bt >= 0) return 1;
      return a.idx - b.idx;
    })
    .map((x) => x.event);
}

function deriveSourceMetadata(source = {}) {
  const src = source && typeof source === "object" ? source : {};
  const connectorGateSnapshotAttached = src.connector_gate_snapshot_attached === true;
  const connectorGateSourceUsed = String(src.connector_gate_source_used || "").trim();
  const auditSourceKind = String(src.audit_source_kind || "").trim();
  const auditGeneratedBy = String(src.audit_generated_by || "").trim();
  const syntheticRuntimeEvidence = src.synthetic_runtime_evidence === true;
  const syntheticMarkers = Array.isArray(src.synthetic_markers)
    ? src.synthetic_markers.map((x) => String(x || "").trim()).filter(Boolean)
    : [];

  const maybeNumber = (value) => {
    const n = Number(value);
    return Number.isFinite(n) ? n : undefined;
  };

  const out = {
    connector_gate_snapshot_attached: connectorGateSnapshotAttached,
    connector_gate_source_used: connectorGateSourceUsed,
    audit_source_kind: auditSourceKind,
    audit_generated_by: auditGeneratedBy,
    synthetic_runtime_evidence: syntheticRuntimeEvidence,
    synthetic_markers: syntheticMarkers,
  };

  const coverage = maybeNumber(src.connector_gate_non_message_ingress_policy_coverage);
  if (coverage !== undefined) out.connector_gate_non_message_ingress_policy_coverage = coverage;
  const missRate = maybeNumber(src.connector_gate_blocked_event_miss_rate);
  if (missRate !== undefined) out.connector_gate_blocked_event_miss_rate = missRate;
  return out;
}

function deriveSummaryFromEvents(events = [], summary = {}, incidents = []) {
  const src = summary && typeof summary === "object" ? summary : {};

  const inferCounter = (explicit, fallbackFn) => {
    const n = toIntLike(explicit, -1);
    if (n >= 0) return n;
    return Math.max(0, Math.floor(fallbackFn()));
  };

  const highRiskLaneWithoutGrant = inferCounter(src.high_risk_lane_without_grant, () =>
    events.filter((row) => String(row?.event_type || "").includes("high_risk_without_grant")).length
  );

  const unauditedAutoResolution = inferCounter(src.unaudited_auto_resolution, () =>
    incidents.filter((row) => !String(row?.audit_ref || "").trim()).length
  );

  const highRiskBypassCount = inferCounter(src.high_risk_bypass_count, () =>
    events.filter((row) => row?.bypass_high_risk === true || String(row?.event_type || "").includes("high_risk_bypass")).length
  );

  const blockedMissRateRaw = Number(src.blocked_event_miss_rate);
  const blockedEventMissRate = Number.isFinite(blockedMissRateRaw) && blockedMissRateRaw >= 0
    ? blockedMissRateRaw
    : 0;

  const nonMessageCoverageRaw = Number(src.non_message_ingress_policy_coverage);
  const nonMessageIngressPolicyCoverage = Number.isFinite(nonMessageCoverageRaw) && nonMessageCoverageRaw >= 0
    ? nonMessageCoverageRaw
    : 0;

  return {
    high_risk_lane_without_grant: highRiskLaneWithoutGrant,
    unaudited_auto_resolution: unauditedAutoResolution,
    high_risk_bypass_count: highRiskBypassCount,
    blocked_event_miss_rate: blockedEventMissRate,
    non_message_ingress_policy_coverage: nonMessageIngressPolicyCoverage,
  };
}

function chooseBestIncident(rows = []) {
  const arr = Array.isArray(rows) ? rows : [];
  if (!arr.length) return null;
  const scored = arr
    .map((row) => {
      const code = String(row?.incident_code || "");
      const expectedEvent = String(EXPECTED_EVENT_TYPES[code] || "");
      const eventType = String(row?.event_type || "");
      const denyCode = String(row?.deny_code || "");
      const auditRef = String(row?.audit_ref || "");
      const latency = toIntLike(row?.takeover_latency_ms, -1);
      const handledAt = toIntLike(row?.handled_at_ms, -1);
      const score =
        (eventType === expectedEvent ? 1 : 0) +
        (denyCode === code ? 1 : 0) +
        (auditRef ? 1 : 0) +
        (latency >= 0 ? 1 : 0);
      return {
        row,
        score,
        handledAt,
      };
    })
    .sort((a, b) => {
      if (a.score !== b.score) return b.score - a.score;
      if (a.handledAt >= 0 && b.handledAt >= 0 && a.handledAt !== b.handledAt) return a.handledAt - b.handledAt;
      return 0;
    });
  return scored[0]?.row || null;
}

function buildXtReadyE2EEvidence(payload = {}, opts = {}) {
  const strict = !!opts.strict;
  const runIdArg = String(opts.run_id || "").trim();
  const source = payload && typeof payload === "object" ? payload : {};
  const eventsRaw = Array.isArray(source.events)
    ? source.events
    : (Array.isArray(source) ? source : []);
  const events = stableSortEvents(eventsRaw);

  const detectMap = new Map();
  const groupedHandled = new Map();

  for (const event of events) {
    const row = event && typeof event === "object" ? event : {};
    const parsed = parseEventType(row.event_type || "");
    const incidentCode = normalizeIncidentCode(row.incident_code || parsed.incident_code || "");
    if (!incidentCode) continue;

    const laneId = String(row.lane_id || "").trim();
    const phase = String(row.phase || parsed.phase || "").trim().toLowerCase();
    const ts = eventTimestampMs(row);

    if (phase === "detected") {
      const key = `${incidentCode}|${laneId}`;
      const prev = toIntLike(detectMap.get(key), -1);
      if (ts >= 0 && (prev < 0 || ts < prev)) detectMap.set(key, ts);
      continue;
    }

    if (phase !== "handled") continue;

    const detectedAtMs = (() => {
      const fromRow = toIntLike(row.detected_at_ms, -1);
      if (fromRow >= 0) return fromRow;
      const key = `${incidentCode}|${laneId}`;
      const fromLane = toIntLike(detectMap.get(key), -1);
      if (fromLane >= 0) return fromLane;
      const fromCode = toIntLike(detectMap.get(`${incidentCode}|`), -1);
      if (fromCode >= 0) return fromCode;
      return -1;
    })();

    const handledAtMs = (() => {
      const fromRow = toIntLike(row.handled_at_ms, -1);
      if (fromRow >= 0) return fromRow;
      return ts;
    })();

    const takeoverLatencyMs = (() => {
      const direct = toIntLike(row.takeover_latency_ms, -1);
      if (direct >= 0) return direct;
      if (detectedAtMs >= 0 && handledAtMs >= detectedAtMs) return handledAtMs - detectedAtMs;
      return -1;
    })();

    const incident = {
      incident_code: incidentCode,
      lane_id: laneId || String(row.parallel_lane_id || "").trim() || "",
      detected_at_ms: detectedAtMs >= 0 ? detectedAtMs : undefined,
      handled_at_ms: handledAtMs >= 0 ? handledAtMs : undefined,
      takeover_latency_ms: takeoverLatencyMs >= 0 ? takeoverLatencyMs : undefined,
      event_type: String(row.event_type || "").trim() || String(EXPECTED_EVENT_TYPES[incidentCode] || ""),
      deny_code: String(row.deny_code || "").trim() || incidentCode,
      audit_event_type: String(row.audit_event_type || "").trim() || "supervisor.incident.handled",
      audit_ref: String(row.audit_ref || row.audit_event_id || "").trim(),
    };

    if (!groupedHandled.has(incidentCode)) groupedHandled.set(incidentCode, []);
    groupedHandled.get(incidentCode).push(incident);
  }

  const incidents = [];
  const missingIncidentCodes = [];
  const duplicateIncidentCodes = [];
  for (const incidentCode of REQUIRED_INCIDENT_CODES) {
    const candidates = groupedHandled.get(incidentCode) || [];
    if (strict && candidates.length > 1) {
      duplicateIncidentCodes.push(`${incidentCode}:${candidates.length}`);
    }
    const best = chooseBestIncident(candidates);
    if (!best) {
      missingIncidentCodes.push(incidentCode);
      continue;
    }
    incidents.push(best);
  }

  if (strict && missingIncidentCodes.length > 0) {
    throw new Error(`missing required incident(s): ${missingIncidentCodes.join(", ")}`);
  }
  if (strict && duplicateIncidentCodes.length > 0) {
    throw new Error(
      `duplicate required incident(s) in strict mode: ${duplicateIncidentCodes.join(", ")}`
    );
  }

  const summary = deriveSummaryFromEvents(events, source.summary || {}, incidents);
  const sourceMeta = deriveSourceMetadata(source.source || {});

  const runId = runIdArg
    || String(source.run_id || "").trim()
    || `xt_ready_e2e_${Date.now()}`;

  return {
    schema_version: "xt_ready_e2e.v1",
    run_id: runId,
    summary,
    source: sourceMeta,
    incidents,
  };
}

function runCli(argv = process.argv) {
  const args = parseArgs(argv);
  const inPath = String(args["events-json"] || "").trim();
  const outPath = String(args["out-json"] || "").trim();
  if (!inPath) throw new Error("missing --events-json");
  if (!outPath) throw new Error("missing --out-json");

  const payload = readJson(path.resolve(inPath));
  const strict = String(args.strict || "").trim() !== "";
  const runId = String(args["run-id"] || "").trim();
  const evidence = buildXtReadyE2EEvidence(payload, {
    strict,
    run_id: runId,
  });
  writeText(path.resolve(outPath), `${JSON.stringify(evidence, null, 2)}\n`);

  console.log(
    `ok - XT-Ready E2E evidence built (incidents=${evidence.incidents.length}, strict=${strict ? "yes" : "no"}, out=${outPath})`
  );
  return evidence;
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
  REQUIRED_INCIDENT_CODES,
  EXPECTED_EVENT_TYPES,
  buildXtReadyE2EEvidence,
  deriveSourceMetadata,
  parseEventType,
  runCli,
};
