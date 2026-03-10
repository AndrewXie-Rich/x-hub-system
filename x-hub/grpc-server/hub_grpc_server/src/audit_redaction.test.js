import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB, sanitizeAuditExtJsonForStorage } from './db.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run('metadata_only redacts content-like strings and keeps numeric telemetry', () => {
  const out = sanitizeAuditExtJsonForStorage(
    JSON.stringify({
      queue_wait_ms: 1234,
      thread_id: 'thread_abc',
      content_preview: 'hello secret world',
    }),
    { auditLevel: 'metadata_only', allowContentPreview: false, contentPreviewChars: 0 }
  );
  const obj = JSON.parse(out);
  assert.equal(obj.queue_wait_ms, 1234);
  assert.equal(obj.thread_id, 'thread_abc');
  assert.equal(typeof obj.content_preview, 'object');
  assert.equal(obj.content_preview.type, 'string');
  assert.equal(typeof obj.content_preview.sha256, 'string');
  assert.ok(obj.content_preview.sha256.length >= 32);
  assert.equal(obj._audit_redaction.audit_level, 'metadata_only');
  assert.equal(obj._audit_redaction.redaction_mode, 'hash_only');
  assert.ok(obj._audit_redaction.redacted_items >= 1);
});

run('content_redacted can include short preview when break-glass enabled', () => {
  const out = sanitizeAuditExtJsonForStorage(
    { content_preview: 'hello secret world' },
    { auditLevel: 'content_redacted', allowContentPreview: true, contentPreviewChars: 5 }
  );
  const obj = JSON.parse(out);
  assert.equal(obj._audit_redaction.audit_level, 'content_redacted');
  assert.equal(obj._audit_redaction.redaction_mode, 'hash_with_preview');
  assert.equal(obj.content_preview.content_preview, 'hello...');
});

run('full_content keeps ext_json unchanged', () => {
  const source = { note: 'operator text', queue_wait_ms: 88 };
  const out = sanitizeAuditExtJsonForStorage(source, { auditLevel: 'full_content' });
  const obj = JSON.parse(out);
  assert.equal(obj.note, 'operator text');
  assert.equal(obj.queue_wait_ms, 88);
  assert.equal(obj._audit_redaction, undefined);
});

run('non-json raw string is stored as redacted metadata in metadata_only', () => {
  const out = sanitizeAuditExtJsonForStorage('raw free-form text', { auditLevel: 'metadata_only' });
  const obj = JSON.parse(out);
  assert.equal(typeof obj.raw_text, 'object');
  assert.equal(obj.raw_text.type, 'string');
  assert.equal(obj._audit_redaction.audit_level, 'metadata_only');
});

run('content_preview is scrubbed after ttl in break-glass mode', () => {
  process.env.HUB_AUDIT_LEVEL = 'content_redacted';
  process.env.HUB_AUDIT_ALLOW_CONTENT_PREVIEW = 'true';
  process.env.HUB_AUDIT_CONTENT_PREVIEW_CHARS = '8';
  process.env.HUB_AUDIT_CONTENT_PREVIEW_TTL_MS = '1';
  process.env.HUB_AUDIT_CONTENT_PREVIEW_SCRUB_INTERVAL_MS = '10000';

  const dbPath = path.join(os.tmpdir(), `hub_audit_redaction_${Date.now()}_${Math.random().toString(16).slice(2)}.db`);
  const db = new HubDB({ dbPath });
  try {
    const oldTs = Date.now() - 10_000;
    db.appendAudit({
      event_type: 'memory.turns.appended',
      created_at_ms: oldTs,
      device_id: 'dev1',
      app_id: 'app1',
      ok: true,
      ext_json: JSON.stringify({ content_preview: 'very-secret-content', queue_wait_ms: 7 }),
    });

    // Force a scrub pass on the next write.
    db._nextAuditPreviewScrubAtMs = 0;
    db.appendAudit({
      event_type: 'memory.turns.appended',
      device_id: 'dev1',
      app_id: 'app1',
      ok: true,
      ext_json: JSON.stringify({ queue_wait_ms: 8 }),
    });

    const rows = db.listAuditEvents({ device_id: 'dev1' });
    const oldRow = rows.find((r) => Number(r.created_at_ms || 0) === oldTs);
    assert.ok(oldRow);
    const oldExt = JSON.parse(String(oldRow.ext_json || '{}'));
    assert.equal(oldExt.content_preview, undefined);
    assert.equal(oldExt.queue_wait_ms, 7);
    assert.ok(oldExt._audit_redaction.preview_scrubbed_at_ms > 0);
  } finally {
    db.close();
    try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
    try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
    try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
  }
});
