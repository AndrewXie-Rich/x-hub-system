import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';

import { HubDB } from './db.js';
import {
  cleanupDbArtifacts,
  makeTmp,
  run,
} from './supervisor_memory_candidate_test_lib.js';

run('HubDB migrates old turns table before creating role metadata indexes', () => {
  const dbPath = makeTmp('legacy_turns_schema', '.sqlite3');
  cleanupDbArtifacts(dbPath);

  const legacyDb = new DatabaseSync(dbPath);
  legacyDb.exec(`
    CREATE TABLE turns (
      turn_id TEXT PRIMARY KEY,
      thread_id TEXT NOT NULL,
      request_id TEXT,
      role TEXT NOT NULL,
      content TEXT NOT NULL,
      is_private INTEGER NOT NULL,
      created_at_ms INTEGER NOT NULL
    );
  `);
  legacyDb.close();

  const db = new HubDB({ dbPath });
  try {
    const columnNames = db.db
      .prepare('PRAGMA table_info(turns)')
      .all()
      .map((row) => String(row.name || ''));
    assert.ok(columnNames.includes('dispatch_id'));
    assert.ok(columnNames.includes('source_role'));

    const indexNames = db.db
      .prepare('PRAGMA index_list(turns)')
      .all()
      .map((row) => String(row.name || ''));
    assert.ok(indexNames.includes('idx_turns_dispatch'));
    assert.ok(indexNames.includes('idx_turns_role_time'));
  } finally {
    db.close();
    cleanupDbArtifacts(dbPath);
  }
});
