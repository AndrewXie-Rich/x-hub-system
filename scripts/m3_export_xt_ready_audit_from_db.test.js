#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { DatabaseSync } = require("node:sqlite");

const {
  exportXtReadyAuditFromDb,
} = require("./m3_export_xt_ready_audit_from_db.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (err) {
    console.error(`not ok - ${name}`);
    throw err;
  }
}

function makeTmpDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "xt_ready_audit_export_"));
}

function seedAuditDb(dbPath) {
  const db = new DatabaseSync(dbPath);
  try {
    db.exec(
      `CREATE TABLE IF NOT EXISTS audit_events (
        event_id TEXT PRIMARY KEY,
        event_type TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        error_code TEXT,
        ext_json TEXT,
        device_id TEXT,
        user_id TEXT,
        app_id TEXT,
        project_id TEXT,
        request_id TEXT
      )`
    );

    const ins = db.prepare(
      `INSERT INTO audit_events(
        event_id, event_type, created_at_ms, error_code, ext_json,
        device_id, user_id, app_id, project_id, request_id
      ) VALUES(?,?,?,?,?,?,?,?,?,?)`
    );

    ins.run(
      "evt-ignore",
      "project.lineage.upserted",
      1000,
      null,
      '{"project_id":"proj-ignore"}',
      "dev-1",
      "user-1",
      "app-1",
      "proj-ignore",
      "req-ignore"
    );
    ins.run(
      "evt-grant-detected",
      "supervisor.incident.grant_pending.detected",
      1100,
      null,
      '{"lane_id":"lane-2"}',
      "dev-1",
      "user-1",
      "app-1",
      "proj-1",
      "req-1"
    );
    ins.run(
      "evt-grant-handled",
      "supervisor.incident.grant_pending.handled",
      1200,
      "grant_pending",
      '{"lane_id":"lane-2","audit_ref":"audit-grant"}',
      "dev-1",
      "user-1",
      "app-1",
      "proj-1",
      "req-2"
    );
  } finally {
    db.close();
  }
}

run("db export only keeps supervisor incident events", () => {
  const tmp = makeTmpDir();
  const dbPath = path.join(tmp, "audit.sqlite3");
  seedAuditDb(dbPath);
  const out = exportXtReadyAuditFromDb({
    db_path: dbPath,
    from_ms: 0,
    to_ms: 9999999999999,
    limit: 100,
  });
  assert.equal(Array.isArray(out.events), true);
  assert.equal(out.events.length, 2);
  assert.deepEqual(
    out.events.map((x) => x.event_type),
    [
      "supervisor.incident.grant_pending.detected",
      "supervisor.incident.grant_pending.handled",
    ]
  );
  assert.equal(String(out.events[1].error_code || ""), "grant_pending");
});

run("db export CLI writes json output", () => {
  const tmp = makeTmpDir();
  const dbPath = path.join(tmp, "audit.sqlite3");
  const outJson = path.join(tmp, "out/xt_ready_audit_export.json");
  seedAuditDb(dbPath);

  const proc = spawnSync(
    process.execPath,
    [
      path.resolve(__dirname, "m3_export_xt_ready_audit_from_db.js"),
      "--db-path",
      dbPath,
      "--out-json",
      outJson,
      "--from-ms",
      "0",
      "--to-ms",
      "9999999999999",
      "--limit",
      "100",
    ],
    { encoding: "utf8" }
  );
  assert.equal(proc.status, 0, proc.stderr || proc.stdout);
  const payload = JSON.parse(String(fs.readFileSync(outJson, "utf8") || "{}"));
  assert.equal(Array.isArray(payload.events), true);
  assert.equal(payload.events.length, 2);
  assert.equal(Number(payload.source.exported_event_total || 0), 2);
});
