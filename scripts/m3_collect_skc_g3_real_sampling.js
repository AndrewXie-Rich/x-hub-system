#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");
const { DatabaseSync } = require("node:sqlite");

const IMPORT_EVENT_TYPE = "skills.package.imported";
const PIN_EVENT_TYPE = "skills.pin.updated";
const AGENT_TOOL_EXECUTED_EVENT_TYPE = "agent.tool.executed";
const RUN_ACCEPT_EVENT_TYPES = new Set([
  "skills.runner.run.accepted",
  "skills.run.accepted",
  "skills.execution.accepted",
  "skills.execute.accepted",
]);

function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i += 1) {
    const token = String(argv[i] || "");
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (next && !String(next).startsWith("--")) {
      out[key] = String(next);
      i += 1;
    } else {
      out[key] = "1";
    }
  }
  return out;
}

function writeText(filePath, text) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, String(text || ""), "utf8");
}

function toInt(value, fallback = 0) {
  const num = Number(value);
  if (!Number.isFinite(num)) return fallback;
  return Math.floor(num);
}

function percentile(values = [], q = 0.95) {
  if (!Array.isArray(values) || values.length === 0) return null;
  const sorted = values
    .map((x) => Number(x))
    .filter((x) => Number.isFinite(x) && x >= 0)
    .sort((a, b) => a - b);
  if (sorted.length === 0) return null;
  const idx = Math.max(0, Math.min(sorted.length - 1, Math.ceil(sorted.length * q) - 1));
  return sorted[idx];
}

function parseExtJson(raw) {
  if (raw == null) return {};
  const text = String(raw || "").trim();
  if (!text) return {};
  try {
    const obj = JSON.parse(text);
    if (obj && typeof obj === "object" && !Array.isArray(obj)) return obj;
  } catch {
    // ignore parse errors; caller handles fail-closed interpretation
  }
  return {};
}

function safeString(value) {
  const s = String(value == null ? "" : value).trim();
  return s;
}

function toBoolean(value) {
  if (value === true || value === false) return value;
  if (value === 1 || value === "1") return true;
  if (value === 0 || value === "0") return false;
  return null;
}

function resolveSkillIdFromRow(row, ext = {}) {
  const candidates = [
    ext.skill_id,
    ext.skillId,
    ext.skill?.skill_id,
    ext.skill?.id,
    ext.manifest?.skill_id,
    ext.manifest?.id,
  ];
  for (const item of candidates) {
    const s = safeString(item);
    if (s) return s;
  }
  return "";
}

function resolveSkillIdFromAgentToolExecuted(ext = {}) {
  const binding = ext?.skill_execution_gate_binding;
  const skillId = safeString(binding?.skill_id);
  if (skillId) return skillId;
  return "";
}

function parseRunAcceptFromAgentToolExecuted(row, ext = {}) {
  const rowOk = toBoolean(row?.ok);
  if (rowOk !== true) {
    return { accepted: false, reject_reason: "row_ok_false" };
  }
  if (toBoolean(ext?.skill_execution_gate_checked) !== true) {
    return { accepted: false, reject_reason: "skill_execution_gate_unchecked" };
  }
  const extDenyCode = safeString(ext?.deny_code);
  const rowErrorCode = safeString(row?.error_code);
  if (extDenyCode || rowErrorCode) {
    return { accepted: false, reject_reason: "deny_code_present" };
  }
  const skillId = resolveSkillIdFromAgentToolExecuted(ext);
  if (!skillId) {
    return { accepted: false, reject_reason: "missing_skill_id_binding" };
  }
  return {
    accepted: true,
    skill_id: skillId,
    source: "agent.tool.executed",
  };
}

function parseRunAcceptEvent(row, ext = {}) {
  const eventType = safeString(row?.event_type);
  if (RUN_ACCEPT_EVENT_TYPES.has(eventType)) {
    return {
      accepted: true,
      skill_id: resolveSkillIdFromRow(row, ext) || null,
      source: "legacy",
      event_type: eventType,
    };
  }
  if (eventType === AGENT_TOOL_EXECUTED_EVENT_TYPE) {
    return parseRunAcceptFromAgentToolExecuted(row, ext);
  }
  return { accepted: false, reject_reason: "not_run_accept_event" };
}

function findMatchedPinEvent(imp, pins = []) {
  if (!imp) return null;
  const importTs = toInt(imp.created_at_ms, 0);
  // Strict first: request_id + skill_id match.
  if (imp.request_id) {
    const byRequest = pins.find((pin) => {
      if (pin.request_id !== imp.request_id) return false;
      if (pin.created_at_ms < importTs) return false;
      if (imp.skill_id && pin.skill_id && pin.skill_id !== imp.skill_id) return false;
      return true;
    });
    if (byRequest) return byRequest;
  }
  // Fallback: skill_id match in time order.
  if (imp.skill_id) {
    const bySkill = pins.find((pin) => {
      if (pin.skill_id !== imp.skill_id) return false;
      if (pin.created_at_ms < importTs) return false;
      return true;
    });
    if (bySkill) return bySkill;
  }
  return null;
}

function extractImportOutcome(row, ext = {}, matchedPin = null) {
  const hasExplicitUpload = typeof ext.upload_ok === "boolean";
  const hasExplicitPin = typeof ext.pin_ok === "boolean";
  const hasExplicitOk = typeof ext.ok === "boolean";
  const rowOk = toBoolean(row?.ok);
  const errorCode = safeString(row?.error_code);

  // Backward-compatible parsing:
  // 1) explicit ext_json booleans (legacy probes)
  // 2) contract path: audit row ok=true + matched skills.pin.updated(ok=true)
  const uploadOk = hasExplicitUpload ? ext.upload_ok === true : rowOk === true;
  const pinOk = hasExplicitPin ? ext.pin_ok === true : toBoolean(matchedPin?.ok) === true;
  const genericOk = hasExplicitOk ? ext.ok === true : rowOk === true;
  const explicitlySuccessful = uploadOk && pinOk;
  const successful = explicitlySuccessful || genericOk;
  const explicitEnough = (hasExplicitUpload && hasExplicitPin) || (rowOk !== null && matchedPin !== null);

  return {
    successful: successful && !errorCode,
    explicitEnough,
    uploadOk,
    pinOk,
    genericOk,
    errorCode,
  };
}

function collectSkcG3RealSampling(opts = {}) {
  const dbPath = safeString(opts.db_path);
  if (!dbPath) throw new Error("missing db_path");

  const fromMs = Math.max(0, toInt(opts.from_ms, 0));
  const toMsRaw = toInt(opts.to_ms, 0);
  const toMs = toMsRaw > 0 ? toMsRaw : Date.now();
  const maxRows = Math.max(1, Math.min(500000, toInt(opts.limit, 200000)));

  const db = new DatabaseSync(path.resolve(dbPath));
  try {
    const rows = db
      .prepare(
        `SELECT event_id, event_type, created_at_ms, ok, error_code, ext_json, request_id
         FROM audit_events
         WHERE created_at_ms >= ?
           AND created_at_ms <= ?
           AND (
             event_type = ?
             OR event_type = ?
             OR event_type = ?
             OR event_type LIKE 'skills.%'
             OR event_type LIKE 'skill.%'
           )
         ORDER BY created_at_ms ASC
         LIMIT ?`
      )
      .all(fromMs, toMs, IMPORT_EVENT_TYPE, PIN_EVENT_TYPE, AGENT_TOOL_EXECUTED_EVENT_TYPE, maxRows);
    const imports = [];
    const pins = [];
    const runs = [];
    const runAcceptBreakdown = {
      legacy_events_seen: 0,
      legacy_events_accepted: 0,
      legacy_events_missing_skill_id: 0,
      agent_tool_events_seen: 0,
      agent_tool_events_accepted: 0,
      agent_tool_events_rejected: {
        row_ok_false: 0,
        skill_execution_gate_unchecked: 0,
        deny_code_present: 0,
        missing_skill_id_binding: 0,
        unknown: 0,
      },
    };
    for (const row of Array.isArray(rows) ? rows : []) {
      const eventType = safeString(row?.event_type);
      const ext = parseExtJson(row?.ext_json);
      if (eventType === IMPORT_EVENT_TYPE) {
        imports.push({
          event_id: safeString(row?.event_id),
          created_at_ms: toInt(row?.created_at_ms, 0),
          skill_id: resolveSkillIdFromRow(row, ext) || null,
          request_id: safeString(row?.request_id) || null,
          row_ok: toBoolean(row?.ok),
          error_code: safeString(row?.error_code) || null,
          ext_json: ext,
        });
      }
      if (eventType === PIN_EVENT_TYPE) {
        pins.push({
          event_id: safeString(row?.event_id),
          created_at_ms: toInt(row?.created_at_ms, 0),
          skill_id: resolveSkillIdFromRow(row, ext) || null,
          request_id: safeString(row?.request_id) || null,
          ok: toBoolean(row?.ok),
        });
      }
      if (RUN_ACCEPT_EVENT_TYPES.has(eventType)) {
        runAcceptBreakdown.legacy_events_seen += 1;
      } else if (eventType === AGENT_TOOL_EXECUTED_EVENT_TYPE) {
        runAcceptBreakdown.agent_tool_events_seen += 1;
      }

      const runAccept = parseRunAcceptEvent(row, ext);
      if (runAccept.accepted) {
        if (eventType === AGENT_TOOL_EXECUTED_EVENT_TYPE) {
          runAcceptBreakdown.agent_tool_events_accepted += 1;
        } else if (RUN_ACCEPT_EVENT_TYPES.has(eventType)) {
          if (runAccept.skill_id) {
            runAcceptBreakdown.legacy_events_accepted += 1;
          } else {
            runAcceptBreakdown.legacy_events_missing_skill_id += 1;
          }
        }
        runs.push({
          event_id: safeString(row?.event_id),
          created_at_ms: toInt(row?.created_at_ms, 0),
          event_type: eventType,
          skill_id: runAccept.skill_id || null,
          request_id: safeString(row?.request_id) || null,
          source: runAccept.source || "legacy",
        });
      } else if (eventType === AGENT_TOOL_EXECUTED_EVENT_TYPE) {
        const reason = safeString(runAccept.reject_reason) || "unknown";
        if (Object.prototype.hasOwnProperty.call(runAcceptBreakdown.agent_tool_events_rejected, reason)) {
          runAcceptBreakdown.agent_tool_events_rejected[reason] += 1;
        } else {
          runAcceptBreakdown.agent_tool_events_rejected.unknown += 1;
        }
      }
    }

    for (const imp of imports) {
      const matchedPin = findMatchedPinEvent(imp, pins);
      const outcome = extractImportOutcome(
        { ok: imp.row_ok, error_code: imp.error_code },
        imp.ext_json || {},
        matchedPin
      );
      imp.matched_pin_event_id = matchedPin ? matchedPin.event_id : null;
      imp.explicit_enough = outcome.explicitEnough;
      imp.successful = outcome.successful;
      imp.upload_ok = outcome.uploadOk;
      imp.pin_ok = outcome.pinOk;
      imp.generic_ok = outcome.genericOk;
      delete imp.ext_json;
    }

    const explicitImportRows = imports.filter((it) => it.explicit_enough);
    const successfulImports = explicitImportRows.filter((it) => it.successful);
    const importSuccessRate =
      explicitImportRows.length > 0 ? successfulImports.length / explicitImportRows.length : null;

    const firstRunBySkill = new Map();
    for (const run of runs) {
      if (!run.skill_id) continue;
      const prev = firstRunBySkill.get(run.skill_id);
      if (!prev || run.created_at_ms < prev.created_at_ms) {
        firstRunBySkill.set(run.skill_id, run);
      }
    }

    const latencies = [];
    for (const imp of successfulImports) {
      if (!imp.skill_id) continue;
      const firstRun = firstRunBySkill.get(imp.skill_id);
      if (!firstRun) continue;
      if (firstRun.created_at_ms < imp.created_at_ms) continue;
      latencies.push(firstRun.created_at_ms - imp.created_at_ms);
    }
    const importToFirstRunP95 = percentile(latencies, 0.95);

    const threshold = {
      openclaw_skill_import_success_rate_gte: 0.98,
      import_to_first_run_p95_ms_lte: 12000,
    };
    const importMetricPass =
      importSuccessRate != null && Number(importSuccessRate) >= threshold.openclaw_skill_import_success_rate_gte;
    const firstRunMetricPass =
      importToFirstRunP95 != null && Number(importToFirstRunP95) <= threshold.import_to_first_run_p95_ms_lte;

    const sampleReady =
      explicitImportRows.length >= 30 &&
      successfulImports.length >= 30 &&
      latencies.length >= 30;

    const gateStatus = sampleReady && importMetricPass && firstRunMetricPass
      ? "PASS"
      : "INSUFFICIENT_EVIDENCE";

    const reasons = [];
    if (!sampleReady) {
      reasons.push(
        `sample_not_enough(explicit_imports=${explicitImportRows.length}, successful_imports=${successfulImports.length}, latencies=${latencies.length})`
      );
    }
    if (sampleReady && !importMetricPass) {
      reasons.push(`import_success_below_threshold(${importSuccessRate} < ${threshold.openclaw_skill_import_success_rate_gte})`);
    }
    if (sampleReady && !firstRunMetricPass) {
      reasons.push(`import_to_first_run_p95_exceeded(${importToFirstRunP95} > ${threshold.import_to_first_run_p95_ms_lte})`);
    }

    return {
      schema_version: "skc_g3_real_sampling.v1",
      generated_at: new Date().toISOString(),
      source: {
        db_path: path.resolve(dbPath),
        from_ms: fromMs,
        to_ms: toMs,
        max_rows: maxRows,
      },
      thresholds: threshold,
      sampling: {
        rows_scanned: rows.length,
        import_rows_total: imports.length,
        pin_rows_total: pins.length,
        import_rows_explicit: explicitImportRows.length,
        successful_import_rows: successfulImports.length,
        first_run_accept_rows: runs.length,
        matched_latency_rows: latencies.length,
        run_accept_breakdown: runAcceptBreakdown,
      },
      kpi_snapshot: {
        openclaw_skill_import_success_rate: importSuccessRate,
        import_to_first_run_p95_ms: importToFirstRunP95,
      },
      gate: {
        "SKC-G3": gateStatus,
      },
      fail_closed_reason: reasons,
      notes: [
        "require_real=true",
        "sample fixture is never used for SKC-G3 real sampling",
      ],
    };
  } finally {
    try {
      db.close();
    } catch {
      // ignore close failures
    }
  }
}

function runCli(argv = process.argv) {
  const args = parseArgs(argv);
  const dbPath = safeString(args["db-path"] || "./data/hub.sqlite3");
  const outJson = safeString(args["out-json"]);
  if (!outJson) throw new Error("missing --out-json");
  const report = collectSkcG3RealSampling({
    db_path: dbPath,
    from_ms: args["from-ms"] || "0",
    to_ms: args["to-ms"] || "0",
    limit: args.limit || "200000",
  });
  writeText(path.resolve(outJson), `${JSON.stringify(report, null, 2)}\n`);
  console.log(
    `ok - SKC-G3 real sampling collected (gate=${report.gate["SKC-G3"]}, imports=${report.sampling.import_rows_explicit}, latencies=${report.sampling.matched_latency_rows}, out=${outJson})`
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
  AGENT_TOOL_EXECUTED_EVENT_TYPE,
  RUN_ACCEPT_EVENT_TYPES,
  collectSkcG3RealSampling,
  parseArgs,
  parseRunAcceptEvent,
  runCli,
};
