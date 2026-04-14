#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");
const { DatabaseSync } = require("node:sqlite");

const {
  REQUIRED_INCIDENT_CODES,
} = require("./m3_generate_xt_ready_e2e_evidence.js");

const DEFAULT_RUNTIME_INCIDENT_REF =
  "x-terminal/.axcoder/reports/xt_ready_incident_events.runtime.json";
const DEFAULT_HUB_PAIRING_LAUNCH_ONLY_REPORT_REF =
  "build/reports/xhub_background_launch_only_smoke_evidence.v1.json";
const DEFAULT_HUB_PAIRING_VERIFY_ONLY_REPORT_REF =
  "build/reports/xhub_pairing_roundtrip_verify_only_smoke_evidence.v1.json";
const DEFAULT_DB_CANDIDATE_REFS = [
  "data/hub.sqlite3",
  "x-hub/grpc-server/hub_grpc_server/data/hub.sqlite3",
  ...(process.env.HOME
    ? [
        path.join(
          process.env.HOME,
          "Library/Containers/com.rel.flowhub/Data/RELFlowHub/hub_grpc/hub.sqlite3"
        ),
      ]
    : []),
];

const REAL_SELECTED_SOURCES = new Set([
  "real_audit_export_env",
  "real_audit_export_build",
  "audit_export",
]);
const PREFERRED_XT_READY_RELEASE_ARTIFACT_CANDIDATES = [
  {
    mode: "require_real_release_chain",
    report_ref: "build/xt_ready_gate_e2e_require_real_report.json",
    source_ref: "build/xt_ready_evidence_source.require_real.json",
    connector_gate_ref: "build/connector_ingress_gate_snapshot.require_real.json",
  },
  {
    mode: "db_real_release_chain",
    report_ref: "build/xt_ready_gate_e2e_db_real_report.json",
    source_ref: "build/xt_ready_evidence_source.db_real.json",
    connector_gate_ref: "build/connector_ingress_gate_snapshot.db_real.json",
  },
  {
    mode: "current_gate",
    report_ref: "build/xt_ready_gate_e2e_report.json",
    source_ref: "build/xt_ready_evidence_source.json",
    connector_gate_ref: "build/connector_ingress_gate_snapshot.json",
  },
];

function requiredHandledEventType(code) {
  return `supervisor.incident.${normalizeString(code).toLowerCase()}.handled`;
}

function requiredHandledEventTypeMap() {
  return Object.fromEntries(
    REQUIRED_INCIDENT_CODES.map((code) => [code, requiredHandledEventType(code)])
  );
}

function incidentCodeFromRequiredEventType(eventType) {
  const raw = normalizeString(eventType).toLowerCase();
  for (const code of REQUIRED_INCIDENT_CODES) {
    if (raw === requiredHandledEventType(code)) return code;
  }
  return "";
}

function normalizeString(value, fallback = "") {
  const trimmed = String(value ?? "").trim();
  return trimmed || fallback;
}

function toIntLike(value, fallback = 0) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.floor(n);
}

function toPosixRelative(baseDir, filePath) {
  const absBase = path.resolve(baseDir);
  const absTarget = path.resolve(filePath);
  const rel = path.relative(absBase, absTarget);
  if (!rel || rel.startsWith("..") || path.isAbsolute(rel)) {
    return absTarget;
  }
  return rel.split(path.sep).join("/");
}

function resolveOptionalPath(rootDir, refOrPath) {
  const raw = normalizeString(refOrPath);
  if (!raw) return "";
  return path.isAbsolute(raw) ? raw : path.resolve(rootDir, raw);
}

function normalizeXtReadyArtifactSelection(rootDir, selection = null) {
  const payload = selection && typeof selection === "object" ? selection : {};
  const mode = normalizeString(payload.mode, "unknown");
  const reportRef = normalizeString(payload.reportRef ?? payload.report_ref);
  const sourceRef = normalizeString(payload.sourceRef ?? payload.source_ref);
  const connectorGateRef = normalizeString(
    payload.connectorGateRef ?? payload.connector_gate_ref
  );
  return {
    mode,
    report_ref: reportRef
      ? toPosixRelative(rootDir, resolveOptionalPath(rootDir, reportRef))
      : "",
    source_ref: sourceRef
      ? toPosixRelative(rootDir, resolveOptionalPath(rootDir, sourceRef))
      : "",
    connector_gate_ref: connectorGateRef
      ? toPosixRelative(rootDir, resolveOptionalPath(rootDir, connectorGateRef))
      : "",
  };
}

function readJsonIfPresent(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return null;
  return JSON.parse(String(fs.readFileSync(filePath, "utf8") || "{}"));
}

function writeText(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, String(content || ""), "utf8");
}

function normalizeRuntimeSourceMeta(payload = {}) {
  const src = payload && typeof payload === "object" ? payload.source : null;
  if (src && typeof src === "object") {
    return {
      source_value: normalizeString(src.value),
      source_kind: normalizeString(src.kind),
      generated_by: normalizeString(src.generated_by),
    };
  }
  return {
    source_value: normalizeString(src),
    source_kind: "",
    generated_by: "",
  };
}

function analyzeRuntimeIncidentPayload(payload = null) {
  if (!payload || typeof payload !== "object") {
    return {
      present: false,
      event_total: 0,
      handled_required_total: 0,
      handled_counts: Object.fromEntries(
        REQUIRED_INCIDENT_CODES.map((code) => [code, 0])
      ),
      missing_required_handled_codes: REQUIRED_INCIDENT_CODES.slice(),
      duplicate_required_handled_codes: [],
      handled_missing_audit_ref_codes: REQUIRED_INCIDENT_CODES.slice(),
      synthetic_markers: [],
      strict_ready: false,
      source: {
        source_value: "",
        source_kind: "",
        generated_by: "",
      },
    };
  }

  const events = Array.isArray(payload.events) ? payload.events : [];
  const source = normalizeRuntimeSourceMeta(payload);
  const handledByCode = new Map();
  const handledCounts = Object.fromEntries(
    REQUIRED_INCIDENT_CODES.map((code) => [code, 0])
  );
  const syntheticMarkers = [];

  for (const event of events) {
    const row = event && typeof event === "object" ? event : {};
    const code = normalizeString(row.incident_code).toLowerCase();
    const eventType = normalizeString(row.event_type).toLowerCase();
    if (!REQUIRED_INCIDENT_CODES.includes(code)) continue;
    if (!eventType.endsWith(".handled")) continue;
    handledCounts[code] += 1;
    const rows = handledByCode.get(code) || [];
    rows.push(row);
    handledByCode.set(code, rows);
  }

  const missingRequiredHandledCodes = REQUIRED_INCIDENT_CODES.filter(
    (code) => Number(handledCounts[code] || 0) <= 0
  );
  const duplicateRequiredHandledCodes = REQUIRED_INCIDENT_CODES
    .filter((code) => Number(handledCounts[code] || 0) > 1)
    .map((code) => `${code}:${handledCounts[code]}`);
  const handledMissingAuditRefCodes = REQUIRED_INCIDENT_CODES.filter((code) => {
    const rows = handledByCode.get(code) || [];
    if (rows.length <= 0) return false;
    return !rows.some((row) => normalizeString(row.audit_ref).length > 0);
  });

  if (normalizeString(source.source_kind).toLowerCase().includes("synthetic")) {
    syntheticMarkers.push(`source.kind=${source.source_kind}`);
  }
  if (normalizeString(source.generated_by).toLowerCase().includes("smoke")) {
    syntheticMarkers.push(`source.generated_by=${source.generated_by}`);
  }
  for (const code of REQUIRED_INCIDENT_CODES) {
    const rows = handledByCode.get(code) || [];
    for (const row of rows) {
      const auditRef = normalizeString(row.audit_ref);
      if (/^audit-smoke-/i.test(auditRef)) {
        syntheticMarkers.push(`audit_ref:${code}:${auditRef}`);
      }
    }
  }

  return {
    present: true,
    event_total: events.length,
    handled_required_total: REQUIRED_INCIDENT_CODES.reduce(
      (sum, code) => sum + Number(handledCounts[code] || 0),
      0
    ),
    handled_counts: handledCounts,
    missing_required_handled_codes: missingRequiredHandledCodes,
    duplicate_required_handled_codes: duplicateRequiredHandledCodes,
    handled_missing_audit_ref_codes: handledMissingAuditRefCodes,
    synthetic_markers: Array.from(new Set(syntheticMarkers)),
    strict_ready:
      missingRequiredHandledCodes.length === 0 &&
      duplicateRequiredHandledCodes.length === 0 &&
      handledMissingAuditRefCodes.length === 0 &&
      syntheticMarkers.length === 0,
    source,
  };
}

function analyzeEvidenceSourcePayload(payload = null) {
  if (!payload || typeof payload !== "object") {
    return {
      present: false,
      selected_source: "",
      require_real_audit: false,
      selected_source_is_real: false,
    };
  }
  const selectedSource = normalizeString(payload.selected_source);
  const requireRealAudit =
    payload.require_real_audit === true ||
    payload.require_real_audit_source === true;
  return {
    present: true,
    selected_source: selectedSource,
    require_real_audit: requireRealAudit,
    selected_source_is_real: REAL_SELECTED_SOURCES.has(selectedSource),
  };
}

function analyzeXtReadyGatePayload(payload = null) {
  if (!payload || typeof payload !== "object") {
    return {
      present: false,
      ok: false,
      require_real_audit_source: false,
      strict_ready: false,
    };
  }
  const ok = payload.ok === true;
  const requireRealAuditSource = payload.require_real_audit_source === true;
  return {
    present: true,
    ok,
    require_real_audit_source: requireRealAuditSource,
    strict_ready: ok && requireRealAuditSource,
  };
}

function analyzeConnectorGatePayload(payload = null) {
  if (!payload || typeof payload !== "object") {
    return {
      present: false,
      source_used: "",
      snapshot_pass: false,
      snapshot_audit_pass: false,
      snapshot_audit_incident_codes: [],
      strict_ready: false,
    };
  }
  const sourceUsed = normalizeString(payload.source_used).toLowerCase();
  const snapshotPass = payload.snapshot?.pass === true;
  const snapshotAuditPass = payload.snapshot_audit?.pass === true;
  const snapshotAuditIncidentCodes = Array.isArray(
    payload.snapshot_audit?.incident_codes
  )
    ? payload.snapshot_audit.incident_codes
        .map((item) => normalizeString(item))
        .filter(Boolean)
    : [];
  return {
    present: true,
    source_used: sourceUsed,
    snapshot_pass: snapshotPass,
    snapshot_audit_pass: snapshotAuditPass,
    snapshot_audit_incident_codes: snapshotAuditIncidentCodes,
    strict_ready: sourceUsed === "audit" && snapshotPass,
  };
}

function analyzeHubPairingSmokePayload(payload = null) {
  if (!payload || typeof payload !== "object") {
    return {
      present: false,
      mode: "",
      ok: false,
      launch_action: "",
      discovery_ok: false,
      discovery_status: 0,
      pairing_enabled: false,
      pairing_port: 0,
      internet_host_hint: "",
      admin_token_resolved: false,
      post_status: 0,
      pending_list_contains_request: false,
      cleanup_status: "",
      cleanup_verified: false,
      error_count: 0,
    };
  }
  const launch = payload.launch && typeof payload.launch === "object"
    ? payload.launch
    : {};
  const discovery = payload.discovery && typeof payload.discovery === "object"
    ? payload.discovery
    : {};
  const discoveryResponse =
    discovery.response && typeof discovery.response === "object"
      ? discovery.response
      : {};
  const adminToken =
    payload.adminToken && typeof payload.adminToken === "object"
      ? payload.adminToken
      : {};
  const pairing = payload.pairing && typeof payload.pairing === "object"
    ? payload.pairing
    : {};
  const errors = Array.isArray(payload.errors) ? payload.errors : [];
  return {
    present: true,
    mode: normalizeString(payload.mode),
    ok: payload.ok === true,
    launch_action: normalizeString(launch.action),
    discovery_ok: discovery.ok === true,
    discovery_status: toIntLike(discovery.status, 0),
    pairing_enabled: discoveryResponse.pairing_enabled === true,
    pairing_port: toIntLike(discoveryResponse.pairing_port, 0),
    internet_host_hint: normalizeString(discoveryResponse.internet_host_hint),
    admin_token_resolved: adminToken.resolved === true,
    post_status: toIntLike(pairing.postStatus, 0),
    pending_list_contains_request: pairing.pendingListContainsRequest === true,
    cleanup_status: normalizeString(pairing.cleanupStatus),
    cleanup_verified: pairing.cleanupVerified === true,
    error_count: errors.length,
  };
}

function probeDbCandidate(absPath) {
  const resolved = path.resolve(absPath);
  const result = {
    abs_path: resolved,
    present: fs.existsSync(resolved),
    total_audit_event_count: 0,
    supervisor_incident_event_count: 0,
    latest_supervisor_incident_at_ms: 0,
    required_handled_counts: Object.fromEntries(
      REQUIRED_INCIDENT_CODES.map((code) => [code, 0])
    ),
    missing_required_handled_codes: REQUIRED_INCIDENT_CODES.slice(),
    duplicate_required_handled_codes: [],
    strict_ready_full_export: false,
    strict_ready_mode: "none",
    best_window: null,
    readable: false,
    error_code: "",
  };
  if (!result.present) return result;

  let db;
  try {
    db = new DatabaseSync(resolved);
    result.readable = true;
    result.total_audit_event_count = toIntLike(
      db.prepare("SELECT COUNT(*) AS count FROM audit_events").get()?.count,
      0
    );
    result.supervisor_incident_event_count = toIntLike(
      db
        .prepare(
          "SELECT COUNT(*) AS count FROM audit_events WHERE event_type LIKE 'supervisor.incident.%'"
        )
        .get()?.count,
      0
    );
    result.latest_supervisor_incident_at_ms = toIntLike(
      db
        .prepare(
          "SELECT COALESCE(MAX(created_at_ms), 0) AS latest FROM audit_events WHERE event_type LIKE 'supervisor.incident.%'"
        )
        .get()?.latest,
      0
    );
    const handledTypeMap = requiredHandledEventTypeMap();
    const requiredRows = db
      .prepare(
        `SELECT event_type, created_at_ms
         FROM audit_events
         WHERE event_type IN (?, ?, ?)
         ORDER BY created_at_ms ASC`
      )
      .all(
        handledTypeMap.grant_pending,
        handledTypeMap.awaiting_instruction,
        handledTypeMap.runtime_error
      );
    for (const row of requiredRows) {
      const code = incidentCodeFromRequiredEventType(row?.event_type);
      if (!code) continue;
      result.required_handled_counts[code] += 1;
    }
    result.missing_required_handled_codes = REQUIRED_INCIDENT_CODES.filter(
      (code) => Number(result.required_handled_counts[code] || 0) <= 0
    );
    result.duplicate_required_handled_codes = REQUIRED_INCIDENT_CODES
      .filter((code) => Number(result.required_handled_counts[code] || 0) > 1)
      .map((code) => `${code}:${result.required_handled_counts[code]}`);
    result.strict_ready_full_export =
      result.missing_required_handled_codes.length === 0 &&
      result.duplicate_required_handled_codes.length === 0;
    result.best_window = findBestRequiredIncidentWindow(requiredRows);
    if (result.strict_ready_full_export) {
      result.strict_ready_mode = "full_export";
    } else if (result.best_window?.strict_ready === true) {
      result.strict_ready_mode = "windowed_export";
    }
  } catch (error) {
    result.error_code = normalizeString(error?.message, "db_probe_failed");
  } finally {
    try {
      db?.close();
    } catch {
      // ignore close errors
    }
  }
  return result;
}

function findBestRequiredIncidentWindow(rows = []) {
  const normalized = rows
    .map((row, idx) => ({
      idx,
      code: incidentCodeFromRequiredEventType(row?.event_type),
      created_at_ms: toIntLike(row?.created_at_ms, -1),
    }))
    .filter((row) => row.code && row.created_at_ms >= 0)
    .sort((a, b) => {
      if (a.created_at_ms !== b.created_at_ms) {
        return a.created_at_ms - b.created_at_ms;
      }
      return a.idx - b.idx;
    });

  if (normalized.length <= 0) return null;

  const counts = Object.fromEntries(
    REQUIRED_INCIDENT_CODES.map((code) => [code, 0])
  );
  let left = 0;
  let best = null;

  const coversAllCodes = () =>
    REQUIRED_INCIDENT_CODES.every((code) => Number(counts[code] || 0) > 0);

  const buildWindow = (startIndex, endIndex) => {
    const windowCounts = Object.fromEntries(
      REQUIRED_INCIDENT_CODES.map((code) => [code, 0])
    );
    for (let i = startIndex; i <= endIndex; i += 1) {
      windowCounts[normalized[i].code] += 1;
    }
    const fromMs = normalized[startIndex].created_at_ms;
    const toMs = normalized[endIndex].created_at_ms;
    const strictReady = REQUIRED_INCIDENT_CODES.every(
      (code) => Number(windowCounts[code] || 0) === 1
    );
    return {
      from_ms: fromMs,
      to_ms: toMs,
      width_ms: Math.max(0, toMs - fromMs),
      counts_by_code: windowCounts,
      strict_ready: strictReady,
    };
  };

  const shouldReplace = (candidate, current) => {
    if (!current) return true;
    if (candidate.strict_ready !== current.strict_ready) {
      return candidate.strict_ready;
    }
    if (candidate.width_ms !== current.width_ms) {
      return candidate.width_ms < current.width_ms;
    }
    return candidate.to_ms > current.to_ms;
  };

  for (let right = 0; right < normalized.length; right += 1) {
    counts[normalized[right].code] += 1;
    while (coversAllCodes() && left <= right) {
      const candidate = buildWindow(left, right);
      if (shouldReplace(candidate, best)) {
        best = candidate;
      }
      counts[normalized[left].code] -= 1;
      left += 1;
    }
  }

  return best;
}

function analyzeDbCandidates(rootDir, candidateRefs = DEFAULT_DB_CANDIDATE_REFS) {
  const candidates = candidateRefs.map((ref) => {
    const absPath = resolveOptionalPath(rootDir, ref);
    return {
      ref: toPosixRelative(rootDir, absPath),
      ...probeDbCandidate(absPath),
    };
  });

  const selected =
    candidates
      .slice()
      .sort((a, b) => {
        const aWindowReady = a.best_window?.strict_ready === true ? 1 : 0;
        const bWindowReady = b.best_window?.strict_ready === true ? 1 : 0;
        if (aWindowReady !== bWindowReady) {
          return bWindowReady - aWindowReady;
        }
        if (a.strict_ready_full_export !== b.strict_ready_full_export) {
          return a.strict_ready_full_export ? -1 : 1;
        }
        if (a.missing_required_handled_codes.length !== b.missing_required_handled_codes.length) {
          return a.missing_required_handled_codes.length - b.missing_required_handled_codes.length;
        }
        if (a.duplicate_required_handled_codes.length !== b.duplicate_required_handled_codes.length) {
          return a.duplicate_required_handled_codes.length - b.duplicate_required_handled_codes.length;
        }
        if (a.supervisor_incident_event_count !== b.supervisor_incident_event_count) {
          return b.supervisor_incident_event_count - a.supervisor_incident_event_count;
        }
        if (a.total_audit_event_count !== b.total_audit_event_count) {
          return b.total_audit_event_count - a.total_audit_event_count;
        }
        return a.ref.localeCompare(b.ref);
      })[0] || null;

  return {
    candidates,
    selected_ref: selected?.ref || "",
    selected_supervisor_incident_event_count:
      selected?.supervisor_incident_event_count || 0,
    selected_missing_required_handled_codes:
      selected?.missing_required_handled_codes || [],
    selected_duplicate_required_handled_codes:
      selected?.duplicate_required_handled_codes || [],
    selected_strict_ready_mode: selected?.strict_ready_mode || "none",
    selected_best_window: selected?.best_window || null,
    strict_ready:
      selected?.strict_ready_full_export === true ||
      selected?.best_window?.strict_ready === true,
  };
}

function buildXtReadyReleaseDiagnostics({
  rootDir,
  xtReadyGate = null,
  xtReadySource = null,
  connectorGate = null,
  xtReadyArtifact = null,
  runtimeIncidentPayload = null,
  runtimeIncidentRef = DEFAULT_RUNTIME_INCIDENT_REF,
  hubPairingLaunchOnlyPayload = null,
  hubPairingLaunchOnlyRef = DEFAULT_HUB_PAIRING_LAUNCH_ONLY_REPORT_REF,
  hubPairingVerifyOnlyPayload = null,
  hubPairingVerifyOnlyRef = DEFAULT_HUB_PAIRING_VERIFY_ONLY_REPORT_REF,
  dbCandidateRefs = DEFAULT_DB_CANDIDATE_REFS,
} = {}) {
  const repoRoot = path.resolve(rootDir || path.resolve(__dirname, ".."));
  const runtimeAbsPath = resolveOptionalPath(repoRoot, runtimeIncidentRef);
  const hubPairingLaunchOnlyAbsPath = resolveOptionalPath(
    repoRoot,
    hubPairingLaunchOnlyRef
  );
  const hubPairingVerifyOnlyAbsPath = resolveOptionalPath(
    repoRoot,
    hubPairingVerifyOnlyRef
  );
  const runtimePayload =
    runtimeIncidentPayload || readJsonIfPresent(runtimeAbsPath) || null;
  const hubPairingLaunchPayload =
    hubPairingLaunchOnlyPayload ||
    readJsonIfPresent(hubPairingLaunchOnlyAbsPath) ||
    null;
  const hubPairingVerifyPayload =
    hubPairingVerifyOnlyPayload ||
    readJsonIfPresent(hubPairingVerifyOnlyAbsPath) ||
    null;

  const xtReadyGateProbe = analyzeXtReadyGatePayload(xtReadyGate);
  const evidenceSourceProbe = analyzeEvidenceSourcePayload(xtReadySource);
  const connectorGateProbe = analyzeConnectorGatePayload(connectorGate);
  const runtimeProbe = analyzeRuntimeIncidentPayload(runtimePayload);
  const hubPairingLaunchProbe =
    analyzeHubPairingSmokePayload(hubPairingLaunchPayload);
  const hubPairingVerifyProbe =
    analyzeHubPairingSmokePayload(hubPairingVerifyPayload);
  const dbProbe = analyzeDbCandidates(repoRoot, dbCandidateRefs);
  const xtReadyArtifactSelection = normalizeXtReadyArtifactSelection(
    repoRoot,
    xtReadyArtifact
  );

  const currentReleaseStrictReady =
    xtReadyGateProbe.strict_ready &&
    evidenceSourceProbe.selected_source_is_real &&
    connectorGateProbe.strict_ready;

  const blockers = [];
  const pushBlocker = (code, detail, phase) => {
    blockers.push({ code, detail, phase });
  };

  if (!xtReadyGateProbe.present) {
    pushBlocker(
      "xt_ready_gate_report_missing",
      "Preferred XT-ready gate report is missing.",
      "current_release"
    );
  } else {
    if (!xtReadyGateProbe.ok) {
      pushBlocker(
        "xt_ready_gate_not_green",
        "Current XT-ready gate report is not green.",
        "current_release"
      );
    }
    if (!xtReadyGateProbe.require_real_audit_source) {
      pushBlocker(
        "xt_ready_require_real_audit_not_strict",
        "Current XT-ready gate report does not require a real audit source.",
        "current_release"
      );
    }
  }

  if (!evidenceSourceProbe.present) {
    pushBlocker(
      "xt_ready_evidence_source_missing",
      "Current XT-ready evidence source file is missing.",
      "current_release"
    );
  } else if (!evidenceSourceProbe.selected_source_is_real) {
    pushBlocker(
      "xt_ready_selected_source_not_real",
      `selected_source=${evidenceSourceProbe.selected_source || "~"}`,
      "current_release"
    );
  }

  if (!connectorGateProbe.present) {
    pushBlocker(
      "connector_gate_snapshot_missing",
      "Current connector ingress gate snapshot is missing.",
      "current_release"
    );
  } else {
    if (connectorGateProbe.source_used !== "audit") {
      pushBlocker(
        "connector_gate_source_not_audit",
        `source_used=${connectorGateProbe.source_used || "~"}`,
        "current_release"
      );
    }
    if (!connectorGateProbe.snapshot_pass) {
      pushBlocker(
        "connector_gate_not_green",
        `snapshot.pass=${connectorGateProbe.snapshot_pass ? "true" : "false"}`,
        "current_release"
      );
    }
    if (
      connectorGateProbe.source_used !== "audit" &&
      !connectorGateProbe.snapshot_audit_pass
    ) {
      pushBlocker(
        "connector_gate_audit_snapshot_not_green",
        `snapshot_audit.incident_codes=${connectorGateProbe.snapshot_audit_incident_codes.join(",") || "~"}`,
        "current_release"
      );
    }
  }

  if (!currentReleaseStrictReady) {
    if (!dbProbe.strict_ready) {
      if (!runtimeProbe.present) {
        pushBlocker(
          "runtime_incident_export_missing",
          `ref=${toPosixRelative(repoRoot, runtimeAbsPath)}`,
          "recovery_candidate"
        );
      } else {
        if (runtimeProbe.missing_required_handled_codes.length > 0) {
          pushBlocker(
            "runtime_missing_required_incidents",
            runtimeProbe.missing_required_handled_codes.join(","),
            "recovery_candidate"
          );
        }
        if (runtimeProbe.duplicate_required_handled_codes.length > 0) {
          pushBlocker(
            "runtime_duplicate_required_incidents",
            runtimeProbe.duplicate_required_handled_codes.join(","),
            "recovery_candidate"
          );
        }
        if (runtimeProbe.handled_missing_audit_ref_codes.length > 0) {
          pushBlocker(
            "runtime_missing_audit_ref",
            runtimeProbe.handled_missing_audit_ref_codes.join(","),
            "recovery_candidate"
          );
        }
        if (runtimeProbe.synthetic_markers.length > 0) {
          pushBlocker(
            "runtime_synthetic_evidence_rejected",
            runtimeProbe.synthetic_markers.join(", "),
            "recovery_candidate"
          );
        }
      }
      if (dbProbe.selected_missing_required_handled_codes.length > 0) {
        pushBlocker(
          "db_missing_required_incidents",
          dbProbe.selected_missing_required_handled_codes.join(","),
          "recovery_candidate"
        );
      }
      if (dbProbe.selected_duplicate_required_handled_codes.length > 0) {
        pushBlocker(
          "db_duplicate_required_incidents",
          dbProbe.selected_duplicate_required_handled_codes.join(","),
          "recovery_candidate"
        );
      }
      pushBlocker(
        "no_require_real_input_ready_now",
        "Neither runtime incident export nor Hub audit DB currently provides a strict-ready incident set.",
        "recovery_candidate"
      );
    }
  }

  const nextActions = [];
  if (!currentReleaseStrictReady) {
    if (
      dbProbe.strict_ready &&
      dbProbe.selected_strict_ready_mode === "windowed_export" &&
      dbProbe.selected_best_window
    ) {
      const window = dbProbe.selected_best_window;
      nextActions.push({
        action_id: "rerun_db_windowed_export",
        why:
          "A strict-ready triad exists in the selected Hub DB, but it needs a narrowed export window to avoid historical duplicate incidents.",
        command_refs: [
          `node ./scripts/m3_export_xt_ready_audit_from_db.js --db-path "${dbProbe.selected_ref}" --from-ms ${window.from_ms} --to-ms ${window.to_ms} --out-json ./build/xt_ready_audit_export.db_window.json`,
        ],
        success_condition:
          "Windowed DB export contains exactly one handled grant_pending / awaiting_instruction / runtime_error incident.",
      });
    } else if (dbProbe.strict_ready) {
      nextActions.push({
        action_id: "rerun_xt_ready_require_real_chain_from_db",
        why:
          "The selected Hub DB already satisfies the strict incident contract.",
        command_refs: [
          `node ./scripts/m3_export_xt_ready_audit_from_db.js --db-path "${dbProbe.selected_ref}" --out-json ./build/xt_ready_audit_export.json`,
        ],
        success_condition:
          "DB export remains strict-ready and can feed the XT-ready require-real chain directly.",
      });
    }
    if (!dbProbe.strict_ready && !runtimeProbe.strict_ready) {
      nextActions.push({
        action_id: "capture_runtime_incidents",
        why:
          "Current runtime export still cannot satisfy strict XT-ready incident coverage.",
        command_refs: [
          "/xt-ready incidents status",
          "/xt-ready incidents export",
        ],
        success_condition:
          "Runtime export contains exactly one handled grant_pending / awaiting_instruction / runtime_error event, each with audit_ref.",
      });
    }
    if (!connectorGateProbe.strict_ready) {
      nextActions.push({
        action_id: "fetch_connector_audit_snapshot",
        why:
          "Current connector gate is still scan-based or audit snapshot is not green.",
        command_refs: [
          "node ./scripts/m3_fetch_connector_ingress_gate_snapshot.js --source audit --out-json ./build/connector_ingress_gate_snapshot.require_real.json",
        ],
        success_condition:
          "Connector gate snapshot reports source_used=audit and snapshot.pass=true.",
      });
    }
    if (!dbProbe.strict_ready) {
      const selectedDbRef = dbProbe.selected_ref || "data/hub.sqlite3";
      nextActions.push({
        action_id: "persist_supervisor_incidents_to_hub_db",
        why:
          "Hub audit DB still lacks supervisor.incident.* rows for a DB-backed require-real replay.",
        command_refs: [
          `node ./scripts/m3_export_xt_ready_audit_from_db.js --db-path ${selectedDbRef} --out-json ./build/xt_ready_audit_export.json`,
        ],
        success_condition:
          "Hub audit export includes supervisor.incident.* rows with handled events.",
      });
    }
    if (connectorGateProbe.strict_ready && (runtimeProbe.strict_ready || dbProbe.strict_ready)) {
      nextActions.unshift({
        action_id: "rerun_xt_ready_require_real_chain",
        why:
          "Raw prerequisites are ready; the strict XT-ready release artifacts just need to be regenerated.",
        command_refs: [
          "bash ./xt_ready_require_real_run.sh",
        ],
        success_condition:
          "build/xt_ready_gate_e2e_require_real_report.json is regenerated with ok=true and require_real_audit_source=true.",
      });
    }
  }

  const recommendedNextPath = currentReleaseStrictReady
    ? "already_strict_ready"
    : !connectorGateProbe.strict_ready
      ? "fetch_connector_audit_snapshot"
      : nextActions[0]?.action_id || "inspect_xt_ready_release_gap";

  return {
    schema_version: "xhub.xt_ready_release_diagnostics.v1",
    generated_at: new Date().toISOString(),
    status: currentReleaseStrictReady
      ? "pass(strict_xt_ready_release_inputs_ready)"
      : "blocked(strict_xt_ready_release_gap)",
    summary: {
      current_release_strict_ready: currentReleaseStrictReady,
      blocker_count: blockers.length,
      blocker_codes: blockers.map((item) => item.code),
      recommended_next_path: recommendedNextPath,
      xt_ready_artifact_mode: xtReadyArtifactSelection.mode,
      xt_ready_gate_ref: xtReadyArtifactSelection.report_ref,
      xt_ready_source_ref: xtReadyArtifactSelection.source_ref,
      connector_gate_ref: xtReadyArtifactSelection.connector_gate_ref,
      xt_ready_gate_ok: xtReadyGateProbe.ok,
      xt_ready_require_real_audit_source:
        xtReadyGateProbe.require_real_audit_source,
      selected_audit_source: evidenceSourceProbe.selected_source,
      connector_gate_source_used: connectorGateProbe.source_used,
      connector_gate_pass: connectorGateProbe.snapshot_pass,
      runtime_candidate_ready: runtimeProbe.strict_ready,
      runtime_missing_required_incidents:
        runtimeProbe.missing_required_handled_codes,
      db_candidate_ready: dbProbe.strict_ready,
      db_selected_ref: dbProbe.selected_ref,
      db_selected_strict_ready_mode: dbProbe.selected_strict_ready_mode,
      db_selected_supervisor_incident_event_count:
        dbProbe.selected_supervisor_incident_event_count,
      hub_pairing_launch_only_ok: hubPairingLaunchProbe.ok,
      hub_pairing_verify_only_ok: hubPairingVerifyProbe.ok,
      hub_pairing_verify_cleanup_verified:
        hubPairingVerifyProbe.cleanup_verified,
    },
    current_release: {
      artifact_selection: xtReadyArtifactSelection,
      xt_ready_gate: xtReadyGateProbe,
      evidence_source: evidenceSourceProbe,
      connector_gate: connectorGateProbe,
    },
    preferred_xt_ready_release_artifacts:
      PREFERRED_XT_READY_RELEASE_ARTIFACT_CANDIDATES,
    recovery_candidates: {
      runtime_incidents: {
        ref: toPosixRelative(repoRoot, runtimeAbsPath),
        ...runtimeProbe,
      },
      hub_audit_db: dbProbe,
    },
    support: {
      hub_pairing_roundtrip: {
        launch_only: {
          ref: toPosixRelative(repoRoot, hubPairingLaunchOnlyAbsPath),
          ...hubPairingLaunchProbe,
        },
        verify_only: {
          ref: toPosixRelative(repoRoot, hubPairingVerifyOnlyAbsPath),
          ...hubPairingVerifyProbe,
        },
      },
    },
    blockers,
    next_actions: nextActions,
    evidence_refs: [
      "build/xt_ready_gate_e2e_require_real_report.json",
      "build/xt_ready_gate_e2e_db_real_report.json",
      "build/xt_ready_gate_e2e_report.json",
      "build/xt_ready_evidence_source.require_real.json",
      "build/xt_ready_evidence_source.db_real.json",
      "build/xt_ready_evidence_source.json",
      "build/connector_ingress_gate_snapshot.require_real.json",
      "build/connector_ingress_gate_snapshot.db_real.json",
      "build/connector_ingress_gate_snapshot.json",
      DEFAULT_HUB_PAIRING_LAUNCH_ONLY_REPORT_REF,
      DEFAULT_HUB_PAIRING_VERIFY_ONLY_REPORT_REF,
      DEFAULT_RUNTIME_INCIDENT_REF,
      "data/hub.sqlite3",
    ],
  };
}

function compactXtReadyReleaseDiagnostics(report = null) {
  if (!report || typeof report !== "object") return null;
  return {
    status: normalizeString(report.status, "missing"),
    summary: report.summary || null,
    blockers: Array.isArray(report.blockers)
      ? report.blockers.map((item) => ({
          code: normalizeString(item?.code, "missing"),
          detail: normalizeString(item?.detail, ""),
          phase: normalizeString(item?.phase, "unknown"),
        }))
      : [],
    next_actions: Array.isArray(report.next_actions)
      ? report.next_actions.map((item) => ({
          action_id: normalizeString(item?.action_id, "missing"),
          why: normalizeString(item?.why, ""),
          success_condition: normalizeString(item?.success_condition, ""),
          command_refs: Array.isArray(item?.command_refs)
            ? item.command_refs.map((entry) => normalizeString(entry)).filter(Boolean)
            : [],
        }))
      : [],
    recovery_candidates: report.recovery_candidates || null,
    support: report.support || null,
  };
}

function writeXtReadyReleaseDiagnostics(rootDir, report) {
  const outPath = path.resolve(
    rootDir,
    "build/reports/xt_ready_release_diagnostics.v1.json"
  );
  writeText(outPath, `${JSON.stringify(report, null, 2)}\n`);
  return outPath;
}

module.exports = {
  DEFAULT_DB_CANDIDATE_REFS,
  DEFAULT_HUB_PAIRING_LAUNCH_ONLY_REPORT_REF,
  DEFAULT_HUB_PAIRING_VERIFY_ONLY_REPORT_REF,
  DEFAULT_RUNTIME_INCIDENT_REF,
  PREFERRED_XT_READY_RELEASE_ARTIFACT_CANDIDATES,
  REAL_SELECTED_SOURCES,
  analyzeConnectorGatePayload,
  analyzeHubPairingSmokePayload,
  analyzeDbCandidates,
  analyzeEvidenceSourcePayload,
  analyzeRuntimeIncidentPayload,
  analyzeXtReadyGatePayload,
  buildXtReadyReleaseDiagnostics,
  compactXtReadyReleaseDiagnostics,
  writeXtReadyReleaseDiagnostics,
};
