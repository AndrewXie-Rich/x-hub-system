import path from 'node:path';

import { HubDB } from './db.js';
import { planMemorySearchIndexRebuild, rebuildMemorySearchIndexAtomic } from './memory_index_rebuild.js';

function parseArgs(argv) {
  const out = {
    db_path: String(process.env.HUB_DB_PATH || './data/hub.sqlite3').trim() || './data/hub.sqlite3',
    source: 'cli.rebuild-index',
    dry_run: false,
    json: false,
    turn_limit: 0,
    canonical_limit: 0,
    batch_size: 500,
    fail_after_pointer_update: false,
    help: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const a = String(argv[i] || '').trim();
    if (!a) continue;
    if (a === '--help' || a === '-h') {
      out.help = true;
      continue;
    }
    if (a === '--dry-run') {
      out.dry_run = true;
      continue;
    }
    if (a === '--json') {
      out.json = true;
      continue;
    }
    if (a === '--fail-after-pointer-update') {
      out.fail_after_pointer_update = true;
      continue;
    }
    if (!a.startsWith('--')) continue;
    const key = a.slice(2);
    const next = (i + 1 < argv.length && !String(argv[i + 1] || '').startsWith('--'))
      ? String(argv[i + 1] || '')
      : '';
    if (next) i += 1;
    if (key === 'db-path') out.db_path = next || out.db_path;
    else if (key === 'source') out.source = next || out.source;
    else if (key === 'turn-limit') out.turn_limit = Number(next || out.turn_limit);
    else if (key === 'canonical-limit') out.canonical_limit = Number(next || out.canonical_limit);
    else if (key === 'batch-size') out.batch_size = Number(next || out.batch_size);
  }
  out.turn_limit = Math.max(0, Number.isFinite(out.turn_limit) ? Math.floor(out.turn_limit) : 0);
  out.canonical_limit = Math.max(0, Number.isFinite(out.canonical_limit) ? Math.floor(out.canonical_limit) : 0);
  out.batch_size = Math.max(50, Math.min(5000, Number.isFinite(out.batch_size) ? Math.floor(out.batch_size) : 500));
  out.source = String(out.source || '').trim() || 'cli.rebuild-index';
  out.db_path = String(out.db_path || '').trim() || './data/hub.sqlite3';
  return out;
}

function printUsage() {
  // eslint-disable-next-line no-console
  console.log(
    [
      'Usage:',
      '  npm run rebuild-index -- [--db-path ./data/hub.sqlite3] [--source cli.rebuild-index] [--batch-size 500]',
      '  npm run rebuild-index -- --dry-run [--json]',
      '',
      'Flags:',
      '  --dry-run                   only estimate snapshot/counts, no write/swap',
      '  --json                      print machine-readable JSON',
      '  --turn-limit <n>            optional cap for turns scan',
      '  --canonical-limit <n>       optional cap for canonical scan',
      '  --batch-size <n>            rebuild batch size (50..5000, default 500)',
      '  --fail-after-pointer-update test-only; simulate swap failure',
    ].join('\n')
  );
}

function printHumanSummary(result, cfg) {
  const absDb = path.resolve(process.cwd(), cfg.db_path);
  // eslint-disable-next-line no-console
  console.log(`db_path=${absDb}`);
  // eslint-disable-next-line no-console
  console.log(`source=${String(result?.source || cfg.source)}`);
  // eslint-disable-next-line no-console
  console.log(`dry_run=${result?.dry_run ? 'true' : 'false'}`);
  // eslint-disable-next-line no-console
  console.log(`ok=${result?.ok ? 'true' : 'false'} stage=${String(result?.stage || '')}`);
  // eslint-disable-next-line no-console
  console.log(
    `snapshot_seq=${Number(result?.snapshot_from_seq || 0)}..${Number(result?.snapshot_to_seq || 0)} ` +
    `docs=${Number(result?.docs_total || 0)} turns=${Number(result?.turns_total || 0)} canonical=${Number(result?.canonical_total || 0)}`
  );
  // eslint-disable-next-line no-console
  console.log(
    `generation=${String(result?.generation_id || '<none>')} ` +
    `active=${String(result?.active_generation_id || '<none>')} ` +
    `prev_active=${String(result?.previous_active_generation_id || '<none>')}`
  );
  // eslint-disable-next-line no-console
  console.log(
    `batch_size=${Number(result?.batch_size || cfg.batch_size || 0)} ` +
    `duration_ms=${Number(result?.duration_ms || 0)}`
  );
  if (!result?.ok) {
    // eslint-disable-next-line no-console
    console.log(`error_code=${String(result?.error_code || '')} error_message=${String(result?.error_message || '')}`);
  }
}

async function main() {
  const cfg = parseArgs(process.argv.slice(2));
  if (cfg.help) {
    printUsage();
    return;
  }

  let db = null;
  try {
    db = new HubDB({ dbPath: cfg.db_path });
    const result = cfg.dry_run
      ? planMemorySearchIndexRebuild({
          db,
          source: cfg.source,
          turn_limit: cfg.turn_limit,
          canonical_limit: cfg.canonical_limit,
          batch_size: cfg.batch_size,
        })
      : rebuildMemorySearchIndexAtomic({
          db,
          source: cfg.source,
          turn_limit: cfg.turn_limit,
          canonical_limit: cfg.canonical_limit,
          batch_size: cfg.batch_size,
          fail_after_pointer_update: cfg.fail_after_pointer_update,
        });

    if (cfg.json) {
      // eslint-disable-next-line no-console
      console.log(JSON.stringify(result, null, 2));
    } else {
      printHumanSummary(result, cfg);
    }
    if (!result?.ok) process.exitCode = 2;
  } catch (err) {
    const msg = String(err?.message || err || 'unknown_error');
    if (cfg.json) {
      // eslint-disable-next-line no-console
      console.log(JSON.stringify({ ok: false, error_code: 'rebuild_index_cli_failed', error_message: msg }, null, 2));
    } else {
      // eslint-disable-next-line no-console
      console.error(`rebuild-index failed: ${msg}`);
    }
    process.exitCode = 1;
  } finally {
    try { db?.close(); } catch { /* ignore */ }
  }
}

main();
