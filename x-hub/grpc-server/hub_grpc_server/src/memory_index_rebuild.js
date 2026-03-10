import crypto from 'node:crypto';

import { nowMs, uuid } from './util.js';

function safeStr(v) {
  return String(v || '').trim();
}

function sha256Hex(text) {
  return crypto.createHash('sha256').update(String(text || ''), 'utf8').digest('hex');
}

function utf8Bytes(text) {
  return Buffer.byteLength(String(text || ''), 'utf8');
}

function normalizeScopeObj(row) {
  return {
    thread_id: safeStr(row?.thread_id),
    device_id: safeStr(row?.device_id),
    user_id: safeStr(row?.user_id),
    app_id: safeStr(row?.app_id),
    project_id: safeStr(row?.project_id),
  };
}

function classifySensitivity({ sourceTable, key, text, isPrivate }) {
  if (isPrivate) return 'secret';
  const k = safeStr(key).toLowerCase();
  const t = safeStr(text).toLowerCase();
  if (/(token|secret|password|private|credential|payment[_\s-]*pin|api[_\s-]*key)/.test(k)) return 'secret';
  if (/(token|secret|password|private\s*key|api\s*key|payment\s*code|qr\s*code)/.test(t)) return 'secret';
  if (sourceTable === 'canonical_memory') return 'internal';
  return 'public';
}

function countTurnRows(db) {
  const row = db.db
    .prepare(
      `SELECT COUNT(*) AS n
       FROM turns t
       JOIN threads th ON th.thread_id = t.thread_id`
    )
    .get();
  return Math.max(0, Number(row?.n || 0));
}

function countCanonicalRows(db) {
  const row = db.db
    .prepare(`SELECT COUNT(*) AS n FROM canonical_memory`)
    .get();
  return Math.max(0, Number(row?.n || 0));
}

function fetchTurnRowsBatch(db, { limit, offset } = {}) {
  const lim = Math.max(1, Number(limit || 1));
  const off = Math.max(0, Number(offset || 0));
  return db.db
    .prepare(
      `SELECT
         t.turn_id, t.thread_id, t.request_id, t.role, t.content, t.is_private, t.created_at_ms,
         th.device_id, th.user_id, th.app_id, th.project_id
       FROM turns t
       JOIN threads th ON th.thread_id = t.thread_id
       ORDER BY t.created_at_ms ASC, t.turn_id ASC
       LIMIT ? OFFSET ?`
    )
    .all(lim, off);
}

function fetchCanonicalRowsBatch(db, { limit, offset } = {}) {
  const lim = Math.max(1, Number(limit || 1));
  const off = Math.max(0, Number(offset || 0));
  return db.db
    .prepare(
      `SELECT *
       FROM canonical_memory
       ORDER BY updated_at_ms ASC, item_id ASC
       LIMIT ? OFFSET ?`
    )
    .all(lim, off);
}

function buildTurnDoc(db, row) {
  const content = typeof db._decryptTurnContentRow === 'function'
    ? String(db._decryptTurnContentRow(row) || '')
    : String(row?.content || '');
  const role = safeStr(row?.role);
  return {
    doc_id: `turn:${safeStr(row?.turn_id)}`,
    source_table: 'turns',
    source_record_id: safeStr(row?.turn_id),
    scope: normalizeScopeObj(row),
    sensitivity: classifySensitivity({
      sourceTable: 'turns',
      key: role,
      text: content,
      isPrivate: Number(row?.is_private || 0) ? 1 : 0,
    }),
    trust_level: 'trusted',
    title: role || 'turn',
    text_sha256: sha256Hex(content),
    text_bytes: utf8Bytes(content),
    created_at_ms: Math.max(0, Number(row?.created_at_ms || 0)),
  };
}

function buildCanonicalDoc(db, row) {
  const plain = typeof db._decryptCanonicalRow === 'function'
    ? (db._decryptCanonicalRow(row) || row || {})
    : (row || {});
  const key = safeStr(plain?.key);
  const value = safeStr(plain?.value);
  return {
    doc_id: `canonical:${safeStr(plain?.item_id || row?.item_id)}`,
    source_table: 'canonical_memory',
    source_record_id: safeStr(plain?.item_id || row?.item_id),
    scope: normalizeScopeObj({
      thread_id: plain?.thread_id,
      device_id: plain?.device_id,
      user_id: plain?.user_id,
      app_id: plain?.app_id,
      project_id: plain?.project_id,
    }),
    sensitivity: classifySensitivity({
      sourceTable: 'canonical_memory',
      key,
      text: value,
      isPrivate: false,
    }),
    trust_level: 'trusted',
    title: key || 'canonical',
    text_sha256: sha256Hex(value),
    text_bytes: utf8Bytes(value),
    created_at_ms: Math.max(0, Number(plain?.updated_at_ms || row?.updated_at_ms || 0)),
  };
}

function appendRebuildAudit(db, payload) {
  try {
    if (typeof db?.appendAudit !== 'function') return;
    const ok = !!payload?.ok;
    db.appendAudit({
      event_type: ok ? 'memory.index.rebuild.completed' : 'memory.index.rebuild.failed',
      severity: ok ? 'info' : 'error',
      created_at_ms: Math.max(0, Number(payload?.finished_at_ms || nowMs())),
      device_id: 'hub',
      app_id: 'hub.memory.index',
      ok,
      error_code: ok ? null : (safeStr(payload?.error_code) || 'memory_index_rebuild_failed'),
      error_message: ok ? null : (safeStr(payload?.error_message) || 'memory index rebuild failed'),
      ext_json: JSON.stringify({
        generation_id: safeStr(payload?.generation_id),
        previous_active_generation_id: safeStr(payload?.previous_active_generation_id),
        active_generation_id: safeStr(payload?.active_generation_id),
        snapshot_from_seq: Math.max(0, Number(payload?.snapshot_from_seq || 0)),
        snapshot_to_seq: Math.max(0, Number(payload?.snapshot_to_seq || 0)),
        docs_total: Math.max(0, Number(payload?.docs_total || 0)),
        turns_total: Math.max(0, Number(payload?.turns_total || 0)),
        canonical_total: Math.max(0, Number(payload?.canonical_total || 0)),
        duration_ms: Math.max(0, Number(payload?.duration_ms || 0)),
        batch_size: Math.max(0, Number(payload?.batch_size || 0)),
        source: safeStr(payload?.source || 'manual'),
      }),
    });
  } catch {
    // Best-effort only.
  }
}

function resolveRebuildSnapshot(db, { source, started_at_ms, turn_limit, canonical_limit, batch_size } = {}) {
  const sourceSafe = safeStr(source || 'manual') || 'manual';
  const startedAt = Math.max(0, Number(started_at_ms || nowMs()));
  const activeBefore = db.getActiveMemorySearchIndexGeneration?.() || null;
  const prevActiveGenerationId = safeStr(activeBefore?.generation_id);
  const prevToSeq = Math.max(0, Number(activeBefore?.snapshot_to_seq || 0));
  const snapshotToSeq = Math.max(0, Number(db.getMemoryIndexChangelogMaxSeq?.() || 0));
  const snapshotFromSeq = prevToSeq > 0 ? (prevToSeq + 1) : 0;

  const turnTotalAll = countTurnRows(db);
  const canonicalTotalAll = countCanonicalRows(db);
  const turnLimitSafe = Math.max(0, Number(turn_limit || 0));
  const canonicalLimitSafe = Math.max(0, Number(canonical_limit || 0));
  const turnsTotal = turnLimitSafe > 0 ? Math.min(turnTotalAll, turnLimitSafe) : turnTotalAll;
  const canonicalTotal = canonicalLimitSafe > 0 ? Math.min(canonicalTotalAll, canonicalLimitSafe) : canonicalTotalAll;
  const docsTotal = turnsTotal + canonicalTotal;
  const batchSize = Math.max(50, Math.min(5000, Number(batch_size || 500)));
  const estimatedBatches = Math.ceil(turnsTotal / batchSize) + Math.ceil(canonicalTotal / batchSize);

  return {
    source: sourceSafe,
    started_at_ms: startedAt,
    previous_active_generation_id: prevActiveGenerationId || null,
    active_generation_id: prevActiveGenerationId || null,
    snapshot_from_seq: snapshotFromSeq,
    snapshot_to_seq: snapshotToSeq,
    turns_total: turnsTotal,
    canonical_total: canonicalTotal,
    docs_total: docsTotal,
    batch_size: batchSize,
    estimated_batches: estimatedBatches,
  };
}

export function listActiveMemorySearchIndexDocs({ db, limit } = {}) {
  if (!db || typeof db.getActiveMemorySearchIndexGeneration !== 'function') {
    throw new Error('missing db adapter');
  }
  const active = db.getActiveMemorySearchIndexGeneration();
  if (!active) return { generation: null, docs: [] };
  const docs = db.listMemorySearchIndexGenerationDocs({
    generation_id: String(active.generation_id || ''),
    limit: Math.max(1, Math.min(5000, Number(limit || 200))),
    offset: 0,
  });
  return { generation: active, docs };
}

export function planMemorySearchIndexRebuild(opts = {}) {
  const db = opts?.db;
  if (!db) throw new Error('missing db adapter');
  const snap = resolveRebuildSnapshot(db, {
    source: opts?.source,
    started_at_ms: opts?.started_at_ms,
    turn_limit: opts?.turn_limit,
    canonical_limit: opts?.canonical_limit,
    batch_size: opts?.batch_size,
  });
  const finishedAt = nowMs();
  return {
    ok: true,
    dry_run: true,
    stage: 'plan',
    generation_id: null,
    ...snap,
    finished_at_ms: finishedAt,
    duration_ms: Math.max(0, finishedAt - Math.max(0, Number(snap.started_at_ms || finishedAt))),
  };
}

export function rebuildMemorySearchIndexAtomic(opts = {}) {
  const db = opts?.db;
  if (!db) throw new Error('missing db adapter');
  if (
    typeof db.ensureMemorySearchIndexBaselineActive !== 'function'
    || typeof db.createMemorySearchIndexGeneration !== 'function'
    || typeof db.swapActiveMemorySearchIndexGeneration !== 'function'
    || typeof db.clearMemorySearchIndexGenerationDocs !== 'function'
    || typeof db.appendMemorySearchIndexGenerationDocs !== 'function'
  ) {
    throw new Error('db adapter missing rebuild APIs');
  }

  const source = safeStr(opts?.source || 'manual') || 'manual';
  const generationId = safeStr(opts?.generation_id) || `midxg_${uuid()}`;
  const startedAt = Math.max(0, Number(opts?.started_at_ms || nowMs()));
  const failAfterPointerUpdate = !!opts?.fail_after_pointer_update;
  const batchSize = Math.max(50, Math.min(5000, Number(opts?.batch_size || 500)));

  const baseline = db.ensureMemorySearchIndexBaselineActive({ source: 'bootstrap' });
  const activeBefore = db.getActiveMemorySearchIndexGeneration() || baseline;
  const snap = resolveRebuildSnapshot(db, {
    source,
    started_at_ms: startedAt,
    turn_limit: opts?.turn_limit,
    canonical_limit: opts?.canonical_limit,
    batch_size: batchSize,
  });

  const prevActiveGenerationId = safeStr(activeBefore?.generation_id) || safeStr(snap.previous_active_generation_id);
  const snapshotToSeq = Math.max(0, Number(snap.snapshot_to_seq || 0));
  const snapshotFromSeq = Math.max(0, Number(snap.snapshot_from_seq || 0));
  const turnTarget = Math.max(0, Number(snap.turns_total || 0));
  const canonicalTarget = Math.max(0, Number(snap.canonical_total || 0));

  db.createMemorySearchIndexGeneration({
    generation_id: generationId,
    status: 'building',
    source,
    snapshot_from_seq: snapshotFromSeq,
    snapshot_to_seq: snapshotToSeq,
    docs_total: 0,
    turns_total: 0,
    canonical_total: 0,
    started_at_ms: startedAt,
    meta: {
      mode: 'atomic_rebuild_swap',
      batch_size: batchSize,
      fail_after_pointer_update: failAfterPointerUpdate,
    },
  });

  let docsTotal = 0;
  let turnsTotal = 0;
  let canonicalTotal = 0;
  try {
    db.clearMemorySearchIndexGenerationDocs({ generation_id: generationId });

    let turnOffset = 0;
    while (turnsTotal < turnTarget) {
      const fetchSize = Math.min(batchSize, Math.max(0, turnTarget - turnsTotal));
      if (fetchSize <= 0) break;
      const rows = fetchTurnRowsBatch(db, { limit: fetchSize, offset: turnOffset });
      if (!rows.length) break;
      const docs = [];
      for (const row of rows) {
        const d = buildTurnDoc(db, row);
        if (!safeStr(d.doc_id) || !safeStr(d.source_record_id)) continue;
        docs.push(d);
      }
      docsTotal += db.appendMemorySearchIndexGenerationDocs({
        generation_id: generationId,
        docs,
      });
      turnsTotal += rows.length;
      turnOffset += rows.length;
    }

    let canonicalOffset = 0;
    while (canonicalTotal < canonicalTarget) {
      const fetchSize = Math.min(batchSize, Math.max(0, canonicalTarget - canonicalTotal));
      if (fetchSize <= 0) break;
      const rows = fetchCanonicalRowsBatch(db, { limit: fetchSize, offset: canonicalOffset });
      if (!rows.length) break;
      const docs = [];
      for (const row of rows) {
        const d = buildCanonicalDoc(db, row);
        if (!safeStr(d.doc_id) || !safeStr(d.source_record_id)) continue;
        docs.push(d);
      }
      docsTotal += db.appendMemorySearchIndexGenerationDocs({
        generation_id: generationId,
        docs,
      });
      canonicalTotal += rows.length;
      canonicalOffset += rows.length;
    }

    db.updateMemorySearchIndexGeneration({
      generation_id: generationId,
      status: 'ready',
      docs_total: docsTotal,
      turns_total: turnsTotal,
      canonical_total: canonicalTotal,
      updated_at_ms: nowMs(),
    });
  } catch (err) {
    const finishedAt = nowMs();
    const duration = Math.max(0, finishedAt - startedAt);
    const message = safeStr(err?.message || err || 'build_failed');
    db.updateMemorySearchIndexGeneration({
      generation_id: generationId,
      status: 'failed',
      docs_total: docsTotal,
      turns_total: turnsTotal,
      canonical_total: canonicalTotal,
      finished_at_ms: finishedAt,
      duration_ms: duration,
      error_code: 'rebuild_failed',
      error_message: message,
      updated_at_ms: finishedAt,
    });
    const activeAfter = db.getActiveMemorySearchIndexGeneration();
    const out = {
      ok: false,
      stage: 'rebuild',
      generation_id: generationId,
      source,
      previous_active_generation_id: prevActiveGenerationId || null,
      active_generation_id: safeStr(activeAfter?.generation_id) || null,
      snapshot_from_seq: snapshotFromSeq,
      snapshot_to_seq: snapshotToSeq,
      docs_total: docsTotal,
      turns_total: turnsTotal,
      canonical_total: canonicalTotal,
      batch_size: batchSize,
      started_at_ms: startedAt,
      finished_at_ms: finishedAt,
      duration_ms: duration,
      error_code: 'rebuild_failed',
      error_message: message,
    };
    appendRebuildAudit(db, out);
    return out;
  }

  try {
    db.swapActiveMemorySearchIndexGeneration({
      generation_id: generationId,
      swapped_at_ms: nowMs(),
      fail_after_pointer_update: failAfterPointerUpdate,
    });
    const finishedAt = nowMs();
    const duration = Math.max(0, finishedAt - startedAt);
    db.updateMemorySearchIndexGeneration({
      generation_id: generationId,
      status: 'active',
      docs_total: docsTotal,
      turns_total: turnsTotal,
      canonical_total: canonicalTotal,
      finished_at_ms: finishedAt,
      duration_ms: duration,
      error_code: null,
      error_message: null,
      updated_at_ms: finishedAt,
    });
    const activeAfter = db.getActiveMemorySearchIndexGeneration();
    const out = {
      ok: true,
      stage: 'swap',
      generation_id: generationId,
      source,
      previous_active_generation_id: prevActiveGenerationId || null,
      active_generation_id: safeStr(activeAfter?.generation_id) || generationId,
      snapshot_from_seq: snapshotFromSeq,
      snapshot_to_seq: snapshotToSeq,
      docs_total: docsTotal,
      turns_total: turnsTotal,
      canonical_total: canonicalTotal,
      batch_size: batchSize,
      started_at_ms: startedAt,
      finished_at_ms: finishedAt,
      duration_ms: duration,
    };
    appendRebuildAudit(db, out);
    return out;
  } catch (err) {
    const finishedAt = nowMs();
    const duration = Math.max(0, finishedAt - startedAt);
    const message = safeStr(err?.message || err || 'swap_failed');
    db.updateMemorySearchIndexGeneration({
      generation_id: generationId,
      status: 'failed',
      docs_total: docsTotal,
      turns_total: turnsTotal,
      canonical_total: canonicalTotal,
      finished_at_ms: finishedAt,
      duration_ms: duration,
      error_code: 'swap_failed',
      error_message: message,
      updated_at_ms: finishedAt,
    });
    const activeAfter = db.getActiveMemorySearchIndexGeneration();
    const out = {
      ok: false,
      stage: 'swap',
      generation_id: generationId,
      source,
      previous_active_generation_id: prevActiveGenerationId || null,
      active_generation_id: safeStr(activeAfter?.generation_id) || null,
      snapshot_from_seq: snapshotFromSeq,
      snapshot_to_seq: snapshotToSeq,
      docs_total: docsTotal,
      turns_total: turnsTotal,
      canonical_total: canonicalTotal,
      batch_size: batchSize,
      started_at_ms: startedAt,
      finished_at_ms: finishedAt,
      duration_ms: duration,
      error_code: 'swap_failed',
      error_message: message,
    };
    appendRebuildAudit(db, out);
    return out;
  }
}
