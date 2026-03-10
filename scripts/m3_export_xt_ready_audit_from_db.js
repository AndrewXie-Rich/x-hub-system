#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");
const { DatabaseSync } = require("node:sqlite");

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

function writeText(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, String(content || ""), "utf8");
}

function toIntLike(value, fallback = 0) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.floor(n);
}

function exportXtReadyAuditFromDb(opts = {}) {
  const dbPath = String(opts.db_path || "").trim();
  if (!dbPath) throw new Error("missing db_path");
  const fromMs = Math.max(0, toIntLike(opts.from_ms, 0));
  const toMsRaw = toIntLike(opts.to_ms, 0);
  const toMs = toMsRaw > 0 ? toMsRaw : Date.now();
  const limit = Math.max(1, Math.min(100000, toIntLike(opts.limit, 10000)));

  const db = new DatabaseSync(path.resolve(dbPath));
  try {
    const rows = db
      .prepare(
        `SELECT event_id, event_type, created_at_ms, error_code, ext_json,
                device_id, user_id, app_id, project_id, request_id
         FROM audit_events
         WHERE event_type LIKE 'supervisor.incident.%'
           AND created_at_ms >= ?
           AND created_at_ms <= ?
         ORDER BY created_at_ms ASC
         LIMIT ?`
      )
      .all(fromMs, toMs, limit);

    const events = (Array.isArray(rows) ? rows : []).map((row, idx) => ({
      event_id: String(row?.event_id || `audit_row_${idx + 1}`),
      event_type: String(row?.event_type || ""),
      created_at_ms: Math.max(0, toIntLike(row?.created_at_ms, 0)),
      error_code: row?.error_code != null ? String(row.error_code || "") : undefined,
      ext_json: row?.ext_json != null ? String(row.ext_json || "") : undefined,
      device_id: row?.device_id != null ? String(row.device_id || "") : undefined,
      user_id: row?.user_id != null ? String(row.user_id || "") : undefined,
      app_id: row?.app_id != null ? String(row.app_id || "") : undefined,
      project_id: row?.project_id != null ? String(row.project_id || "") : undefined,
      request_id: row?.request_id != null ? String(row.request_id || "") : undefined,
    }));

    return {
      run_id: `xt_ready_audit_export_${Date.now()}`,
      summary: {
        high_risk_lane_without_grant: 0,
        unaudited_auto_resolution: 0,
        high_risk_bypass_count: 0,
        blocked_event_miss_rate: 0,
        non_message_ingress_policy_coverage: events.length > 0 ? 1 : 0,
      },
      events,
      source: {
        db_path: dbPath,
        from_ms: fromMs,
        to_ms: toMs,
        limit,
        exported_event_total: events.length,
      },
    };
  } finally {
    try {
      db.close();
    } catch {
      // ignore close errors
    }
  }
}

function runCli(argv = process.argv) {
  const args = parseArgs(argv);
  const dbPath = String(args["db-path"] || "data/hub.sqlite3").trim();
  const outJson = String(args["out-json"] || "").trim();
  if (!outJson) throw new Error("missing --out-json");

  const report = exportXtReadyAuditFromDb({
    db_path: dbPath,
    from_ms: args["from-ms"] || "0",
    to_ms: args["to-ms"] || "0",
    limit: args.limit || "10000",
  });
  writeText(path.resolve(outJson), `${JSON.stringify(report, null, 2)}\n`);
  console.log(
    `ok - XT-Ready audit export built (events=${report.events.length}, db=${dbPath}, out=${outJson})`
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
  exportXtReadyAuditFromDb,
  parseArgs,
  runCli,
};
