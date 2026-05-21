#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const ROLE_TRANSCRIPT_PROJECT_ID = 'role_smoke_project';
const ROLE_TRANSCRIPT_THREAD_KEY = `xterminal_project_${ROLE_TRANSCRIPT_PROJECT_ID}`;
const ROLE_TRANSCRIPT_DISPATCH_ID = 'dispatch_role_smoke_001';
const OBJECT_RETRIEVAL_PROJECT_ID = 'hybrid_smoke_project';

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    timeoutMs: 30000,
    port: 58000 + (process.pid % 1000),
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 1000, 120000);
        i += 1;
        break;
      case '--port':
        out.port = parseIntInRange(next, out.port, 1024, 65535);
        i += 1;
        break;
      case '--help':
      case '-h':
        out.help = true;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }
  return out;
}

function usage() {
  return [
    'memory_retrieval_http_smoke.js',
    '',
    'Options:',
    '  --timeout-ms <ms>    Command timeout, default 30000',
    '  --port <port>        Local xhubd HTTP port',
  ].join('\n');
}

function safeString(value) {
  return String(value ?? '').trim();
}

function safeTail(value) {
  return String(value || '').split(/\r?\n/).slice(-25).join('\n');
}

function assertOk(condition, message, details = {}) {
  if (!condition) {
    const suffix = Object.keys(details).length ? ` ${JSON.stringify(details).slice(0, 600)}` : '';
    throw new Error(`${message}${suffix}`);
  }
}

function writeFixture(memoryDir) {
  fs.mkdirSync(path.join(memoryDir, 'project'), { recursive: true });
  fs.mkdirSync(path.join(memoryDir, 'personal'), { recursive: true });
  fs.writeFileSync(
    path.join(memoryDir, 'project', 'capsule.md'),
    'Use governed Rust Hub memory retrieval for project assembly. Keep supervisor assembly slot based.\n',
    'utf8'
  );
  fs.writeFileSync(
    path.join(memoryDir, 'personal', 'capsule.md'),
    'Personal preference for governed retrieval should not appear in project_code mode.\n',
    'utf8'
  );
  fs.writeFileSync(
    path.join(memoryDir, 'project', 'runtime.json'),
    `${JSON.stringify({
      summary: 'governed retrieval runtime truth',
      detail: 'Rust memory retrieval HTTP path should preserve explainable source refs.',
      api_key: 'sk-memory-http-secret-that-must-not-leak',
    }, null, 2)}\n`,
    'utf8'
  );
}

function writeRoleTranscriptFixture(dbPath) {
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  const now = Date.now();
  const threadId = 'thread_role_smoke';
  const db = new DatabaseSync(dbPath);
  try {
    db.exec(`
      CREATE TABLE IF NOT EXISTS threads (
        thread_id TEXT PRIMARY KEY,
        thread_key TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        user_id TEXT NOT NULL DEFAULT '',
        app_id TEXT NOT NULL DEFAULT '',
        project_id TEXT NOT NULL DEFAULT '',
        created_at_ms INTEGER NOT NULL DEFAULT 0,
        updated_at_ms INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS turns (
        turn_id TEXT PRIMARY KEY,
        thread_id TEXT NOT NULL,
        request_id TEXT,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        is_private INTEGER NOT NULL DEFAULT 0,
        created_at_ms INTEGER NOT NULL DEFAULT 0,
        role_metadata_json TEXT,
        client_message_id TEXT,
        source_role TEXT,
        target_role TEXT,
        dispatch_id TEXT,
        dispatch_kind TEXT,
        run_id TEXT,
        launch_run_id TEXT,
        reviewer_note_id TEXT,
        status TEXT
      );
    `);
    db.prepare(
      `INSERT INTO threads (
        thread_id, thread_key, device_id, user_id, app_id, project_id, created_at_ms, updated_at_ms
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
    ).run(
      threadId,
      ROLE_TRANSCRIPT_THREAD_KEY,
      'xt_smoke_device',
      'local_user',
      'x-terminal',
      ROLE_TRANSCRIPT_PROJECT_ID,
      now - 3000,
      now
    );
    const insertTurn = db.prepare(
      `INSERT INTO turns (
        turn_id, thread_id, request_id, role, content, is_private, created_at_ms,
        role_metadata_json, client_message_id, source_role, target_role, dispatch_id,
        dispatch_kind, run_id, launch_run_id, reviewer_note_id, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    );
    const rows = [
      {
        turnId: 'turn_role_smoke_dispatch',
        role: 'user',
        content: 'Supervisor assigned the coder a role-aware smoke task.',
        createdAtMs: now - 2000,
        metadata: {
          schema_version: 'xhub.role_turn_metadata.v1',
          client_message_id: 'cmid_role_smoke_dispatch',
          source_role: 'supervisor',
          target_role: 'coder',
          sender_role: 'supervisor',
          project_id: ROLE_TRANSCRIPT_PROJECT_ID,
          thread_key: ROLE_TRANSCRIPT_THREAD_KEY,
          dispatch_id: ROLE_TRANSCRIPT_DISPATCH_ID,
          dispatch_kind: 'supervisor_to_coder',
          run_id: 'run_role_smoke',
          status: 'dispatched',
          observed_at_ms: now - 2000,
        },
      },
      {
        turnId: 'turn_role_smoke_reply',
        role: 'assistant',
        content: 'Coder completed the smoke task on the same dispatch.',
        createdAtMs: now - 1000,
        metadata: {
          schema_version: 'xhub.role_turn_metadata.v1',
          client_message_id: 'cmid_role_smoke_reply',
          source_role: 'coder',
          target_role: 'supervisor',
          sender_role: 'coder',
          project_id: ROLE_TRANSCRIPT_PROJECT_ID,
          thread_key: ROLE_TRANSCRIPT_THREAD_KEY,
          dispatch_id: ROLE_TRANSCRIPT_DISPATCH_ID,
          dispatch_kind: 'coder_reply',
          run_id: 'run_role_smoke',
          status: 'completed',
          observed_at_ms: now - 1000,
        },
      },
      {
        turnId: 'turn_role_smoke_review',
        role: 'user',
        content: 'xhubenc:v1:sealed-reviewer-note-secret',
        createdAtMs: now,
        metadata: {
          schema_version: 'xhub.role_turn_metadata.v1',
          client_message_id: 'cmid_role_smoke_review',
          source_role: 'reviewer',
          target_role: 'coder',
          sender_role: 'reviewer',
          project_id: ROLE_TRANSCRIPT_PROJECT_ID,
          thread_key: ROLE_TRANSCRIPT_THREAD_KEY,
          dispatch_id: ROLE_TRANSCRIPT_DISPATCH_ID,
          dispatch_kind: 'reviewer_note',
          run_id: 'run_role_smoke',
          reviewer_note_id: 'review_role_smoke',
          status: 'observed',
          observed_at_ms: now,
        },
      },
    ];
    for (const row of rows) {
      insertTurn.run(
        row.turnId,
        threadId,
        `request_${row.turnId}`,
        row.role,
        row.content,
        0,
        row.createdAtMs,
        JSON.stringify(row.metadata),
        row.metadata.client_message_id,
        row.metadata.source_role,
        row.metadata.target_role,
        row.metadata.dispatch_id,
        row.metadata.dispatch_kind,
        row.metadata.run_id,
        '',
        row.metadata.reviewer_note_id || '',
        row.metadata.status
      );
    }
  } finally {
    db.close();
  }
}

function startXhubd({ port, dbPath, runtimeDir, memoryDir, skillsDir }) {
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  fs.mkdirSync(runtimeDir, { recursive: true });
  fs.mkdirSync(memoryDir, { recursive: true });
  fs.mkdirSync(skillsDir, { recursive: true });

  const env = {
    ...process.env,
    XHUB_RUST_HUB_ROOT: ROOT_DIR,
    XHUB_RUST_HUB_HOST: '127.0.0.1',
    XHUB_RUST_HUB_HTTP_PORT: String(port),
    HUB_DB_PATH: dbPath,
    HUB_RUNTIME_BASE_DIR: runtimeDir,
    XHUB_RUST_MEMORY_DIR: memoryDir,
    XHUB_RUST_SKILLS_DIR: skillsDir,
  };
  const packagedBin = path.join(ROOT_DIR, 'bin', 'xhubd');
  const debugBin = path.join(ROOT_DIR, 'target', 'debug', 'xhubd');
  let bin = '';
  if (fs.existsSync(packagedBin)) {
    bin = packagedBin;
  } else {
    const built = spawnSyncChecked('cargo', ['build', '--bin', 'xhubd'], { cwd: ROOT_DIR });
    if (built.status !== 0) {
      throw new Error(`cargo build failed before memory HTTP smoke: ${built.stderr}`);
    }
    bin = debugBin;
  }
  const child = spawn(bin, ['serve'], { cwd: ROOT_DIR, env, stdio: ['ignore', 'pipe', 'pipe'] });

  const output = { stdout: '', stderr: '' };
  child.stdout.on('data', (chunk) => { output.stdout += chunk.toString(); });
  child.stderr.on('data', (chunk) => { output.stderr += chunk.toString(); });
  return { child, output };
}

function spawnSyncChecked(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
    ...options,
  });
  return {
    status: Number(result.status ?? 1),
    stdout: String(result.stdout || ''),
    stderr: String(result.stderr || result.error?.message || ''),
  };
}

function httpJson(method, url, body = undefined, timeoutMs = 1000) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? undefined : Buffer.from(JSON.stringify(body));
    const req = http.request(url, {
      method,
      timeout: timeoutMs,
      headers: {
        accept: 'application/json',
        ...(data ? { 'content-type': 'application/json', 'content-length': String(data.length) } : {}),
      },
    }, (res) => {
      let raw = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { raw += chunk; });
      res.on('end', () => {
        if ((res.statusCode || 0) < 200 || (res.statusCode || 0) >= 300) {
          reject(new Error(`http_status:${res.statusCode}:${raw.slice(0, 400)}`));
          return;
        }
        try {
          resolve(JSON.parse(raw));
        } catch (error) {
          reject(new Error(`invalid_json:${error.message}:${raw.slice(0, 400)}`));
        }
      });
    });
    req.on('timeout', () => req.destroy(new Error('http_timeout')));
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function waitForHealth(baseUrl, child, output, timeoutMs) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    if (child.exitCode !== null) {
      throw new Error(`xhubd exited before health was ready: ${child.exitCode}\nstdout=${safeTail(output.stdout)}\nstderr=${safeTail(output.stderr)}`);
    }
    try {
      await httpJson('GET', `${baseUrl}/health`, undefined, 750);
      return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  throw new Error(`xhubd health timeout\nstdout=${safeTail(output.stdout)}\nstderr=${safeTail(output.stderr)}`);
}

function assertNoLeaks(value, label) {
  const raw = JSON.stringify(value);
  assertOk(!raw.includes('Personal preference'), `${label} leaked personal capsule`);
  assertOk(!raw.includes('sk-memory-http-secret-that-must-not-leak'), `${label} leaked secret`);
  assertOk(!raw.includes('sealed-reviewer-note-secret'), `${label} leaked encrypted reviewer note`);
  assertOk(!/"api_key"\s*:/.test(raw), `${label} leaked api_key field`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-memory-http-smoke-'));
  const memoryDir = path.join(tempRoot, 'memory');
  const runtimeDir = path.join(tempRoot, 'runtime');
  const skillsDir = path.join(tempRoot, 'skills');
  const dbPath = path.join(tempRoot, 'data', 'hub.sqlite3');
  const baseUrl = `http://127.0.0.1:${args.port}`;
  let child;

  try {
    writeFixture(memoryDir);
    writeRoleTranscriptFixture(dbPath);
    const started = startXhubd({
      port: args.port,
      dbPath,
      runtimeDir,
      memoryDir,
      skillsDir,
    });
    child = started.child;
    await waitForHealth(baseUrl, child, started.output, args.timeoutMs);

    const ready = await httpJson('GET', `${baseUrl}/ready`, undefined, 1500);
    assertOk(ready?.capabilities?.memory_retrieval_http === true, 'daemon readiness did not expose memory_retrieval_http', ready);
    assertOk(ready?.capabilities?.memory_role_transcript_projection_http === true, 'daemon readiness did not expose memory_role_transcript_projection_http', ready);
    assertOk(ready?.memory?.retrieval_shadow_http === true, 'daemon memory readiness did not expose retrieval_shadow_http', ready?.memory || {});
    assertOk(ready?.memory?.role_transcript_projection_http === true, 'daemon memory readiness did not expose role_transcript_projection_http', ready?.memory || {});
    assertOk(ready?.memory?.role_transcript_projection_authority === 'shadow_read_only', 'daemon role transcript projection authority was not shadow_read_only', ready?.memory || {});
    assertOk(ready?.memory?.canonical_writer_in_rust === false, 'daemon reported Rust writer authority unexpectedly', ready?.memory || {});

    const memoryReadiness = await httpJson('GET', `${baseUrl}/memory/readiness`, undefined, 1500);
    assertOk(memoryReadiness?.readiness?.ready === true, 'memory readiness was not ready', memoryReadiness);
    assertOk(Number(memoryReadiness?.readiness?.indexed_document_count || 0) >= 3, 'memory readiness did not index fixture docs', memoryReadiness);
    assertOk(memoryReadiness?.readiness?.writer_authority_in_rust === false, 'memory readiness reported writer authority in Rust', memoryReadiness);

    const createdObject = await httpJson('POST', `${baseUrl}/memory/objects`, {
      memory_id: 'mem_hybrid_smoke_decision',
      requester_role: 'chat',
      use_mode: 'project_chat',
      scope: 'project',
      owner_id: OBJECT_RETRIEVAL_PROJECT_ID,
      project_id: OBJECT_RETRIEVAL_PROJECT_ID,
      source_kind: 'decision_track',
      layer: 'l1_canonical',
      title: 'Hybrid retrieval decision',
      text: 'Decision: use Rust memory object retrieval before provider route selection.',
      tags: ['memory', 'decision'],
      audit_ref: 'memory-http-smoke',
    }, 1500);
    assertOk(createdObject?.ok === true, 'memory object create failed before hybrid retrieval smoke', createdObject);

    const objectRetrieve = await httpJson('POST', `${baseUrl}/memory/retrieve`, {
      scope: 'project',
      project_id: OBJECT_RETRIEVAL_PROJECT_ID,
      query: 'why decision memory retrieval provider route',
      max_results: 3,
      explain: true,
    }, 1500);
    assertOk(objectRetrieve?.source === 'rust_memory_objects_hybrid_v1', 'hybrid object retrieval source mismatch', objectRetrieve);
    assertOk(objectRetrieve?.retrieval_engine?.schema_version === 'xhub.memory.hybrid_retrieval.v1', 'hybrid object retrieval engine schema mismatch', objectRetrieve);
    assertOk(objectRetrieve?.retrieval_engine?.index_source === 'rust_hub_memory_object_index', 'hybrid object retrieval did not use derived memory index', objectRetrieve);
    assertOk(objectRetrieve?.retrieval_engine?.index_ready === true, 'hybrid object retrieval index was not ready', objectRetrieve);
    assertOk(Number(objectRetrieve?.retrieval_engine?.index_row_count || 0) >= 1, 'hybrid object retrieval index row count was empty', objectRetrieve);
    assertOk(objectRetrieve?.retrieval_engine?.stale_index_count === 0, 'hybrid object retrieval index was stale', objectRetrieve);
    assertOk(objectRetrieve?.retrieval_engine?.index_rebuilt === true, 'hybrid object retrieval did not rebuild missing derived index', objectRetrieve);
    assertOk(objectRetrieve?.retrieval_engine?.semantic_used === false, 'hybrid object retrieval unexpectedly used semantic search', objectRetrieve);
    assertOk(objectRetrieve?.production_authority_change === false, 'hybrid object retrieval changed production authority', objectRetrieve);
    assertOk(Array.isArray(objectRetrieve.results) && objectRetrieve.results[0]?.memory_id === 'mem_hybrid_smoke_decision', 'hybrid object retrieval missed fixture object', objectRetrieve);
    assertOk(objectRetrieve.results[0]?.explain?.policy_filter === 'project_active_non_secret', 'hybrid object retrieval explain missing policy filter', objectRetrieve.results[0] || {});
    assertOk(objectRetrieve?.retrieval_trace?.schema_version === 'xhub.memory.retrieval_trace.v1', 'hybrid object retrieval trace schema missing', objectRetrieve);
    assertOk(objectRetrieve?.retrieval_trace?.selected?.[0]?.memory_id === 'mem_hybrid_smoke_decision', 'hybrid object retrieval selected trace missed fixture object', objectRetrieve?.retrieval_trace || {});
    assertNoLeaks(objectRetrieve, 'hybrid object retrieval');

    const searchParams = new URLSearchParams({
      query: 'governed retrieval project assembly',
      max_results: '5',
      max_snippet_chars: '240',
    });
    const search = await httpJson('GET', `${baseUrl}/memory/search?${searchParams.toString()}`, undefined, 1500);
    assertOk(search.schema_version === 'xt.memory_retrieval_result.v1', 'memory search schema mismatch', search);
    assertOk(search.source === 'rust_hub_memory_shadow_v1', 'memory search source mismatch', search);
    assertOk(Array.isArray(search.results) && search.results.length >= 1, 'memory search returned no results', search);
    assertNoLeaks(search, 'memory search');

    const ref = safeString(search.results[0]?.ref);
    assertOk(ref.startsWith('memory://rust/local/'), 'memory search returned invalid ref', search.results[0] || {});
    const byRef = await httpJson('POST', `${baseUrl}/memory/retrieve`, {
      retrieval_kind: 'get_ref',
      explicit_refs: [ref],
      max_results: 1,
      max_snippet_chars: 240,
    }, 1500);
    assertOk(Array.isArray(byRef.results) && byRef.results.length === 1, 'memory get_ref returned wrong count', byRef);
    assertOk(byRef.results[0]?.ref === ref, 'memory get_ref returned wrong ref', byRef);
    assertNoLeaks(byRef, 'memory get_ref');

    const deniedParams = new URLSearchParams({ query: 'show api key' });
    const denied = await httpJson('GET', `${baseUrl}/memory/search?${deniedParams.toString()}`, undefined, 1500);
    assertOk(denied.status === 'denied', 'secret query was not denied', denied);
    assertOk(denied.deny_code === 'query_secret_pattern_denied', 'secret query deny_code mismatch', denied);

    const roleTranscriptParams = new URLSearchParams({
      project_id: ROLE_TRANSCRIPT_PROJECT_ID,
      thread_key: ROLE_TRANSCRIPT_THREAD_KEY,
      limit: '10',
      include_content: 'true',
    });
    const roleTranscript = await httpJson('GET', `${baseUrl}/memory/project-role-transcript?${roleTranscriptParams.toString()}`, undefined, 1500);
    assertOk(roleTranscript?.ok === true, 'role transcript projection was not ok', roleTranscript);
    assertOk(roleTranscript.schema_version === 'xhub.project_role_transcript_projection.v1', 'role transcript schema mismatch', roleTranscript);
    assertOk(roleTranscript.authority === 'shadow_read_only', 'role transcript authority mismatch', roleTranscript);
    assertOk(roleTranscript.production_authority_change === false, 'role transcript changed production authority', roleTranscript);
    assertOk(roleTranscript.project_id === ROLE_TRANSCRIPT_PROJECT_ID, 'role transcript project_id mismatch', roleTranscript);
    assertOk(Array.isArray(roleTranscript.recent_lines) && roleTranscript.recent_lines.length === 3, 'role transcript returned wrong line count', roleTranscript);
    assertOk(roleTranscript.latest_supervisor_dispatch?.turn_metadata?.source_role === 'supervisor', 'role transcript missed supervisor dispatch metadata', roleTranscript.latest_supervisor_dispatch || {});
    assertOk(roleTranscript.latest_coder_reply?.turn_metadata?.dispatch_id === ROLE_TRANSCRIPT_DISPATCH_ID, 'role transcript missed coder reply dispatch_id', roleTranscript.latest_coder_reply || {});
    assertOk(roleTranscript.latest_reviewer_note?.turn_metadata?.source_role === 'reviewer', 'role transcript missed reviewer note metadata', roleTranscript.latest_reviewer_note || {});
    assertOk(roleTranscript.latest_reviewer_note?.content_redacted === true, 'role transcript did not redact encrypted reviewer content', roleTranscript.latest_reviewer_note || {});
    assertNoLeaks(roleTranscript, 'role transcript projection');

    const result = {
      ok: true,
      schema_version: 'xhub.rust_hub.memory_retrieval_http_smoke.v1',
      command: 'memory-retrieval-http-smoke',
      http_base_url: baseUrl,
      readiness_ready: memoryReadiness.readiness.ready,
      indexed_document_count: memoryReadiness.readiness.indexed_document_count,
      search_result_count: search.results.length,
      first_ref: ref,
      get_ref_ok: true,
      writer_authority_in_rust: false,
      project_code_personal_leak: false,
      secret_leak: false,
      secret_query_denied: true,
      role_transcript_projection_ok: true,
      role_transcript_line_count: roleTranscript.recent_lines.length,
      object_hybrid_retrieval_ok: true,
      object_hybrid_source: objectRetrieve.source,
      object_hybrid_index_source: objectRetrieve.retrieval_engine.index_source,
      object_hybrid_index_rebuilt: objectRetrieve.retrieval_engine.index_rebuilt,
      object_hybrid_trace_ok: true,
    };
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } finally {
    if (child && child.exitCode === null) {
      child.kill('SIGTERM');
      spawnSync('kill', ['-TERM', String(child.pid)], { encoding: 'utf8' });
      await waitForExit(child, 5000);
    }
    try {
      fs.rmSync(tempRoot, { recursive: true, force: true });
    } catch {}
  }
}

async function waitForExit(child, timeoutMs) {
  if (!child || !child.pid || child.exitCode !== null) return;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (child.exitCode !== null || !pidAlive(child.pid)) return;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  if (child.exitCode === null && pidAlive(child.pid)) {
    child.kill('SIGKILL');
    spawnSync('kill', ['-KILL', String(child.pid)], { encoding: 'utf8' });
    for (let i = 0; i < 50; i += 1) {
      if (child.exitCode !== null || !pidAlive(child.pid)) return;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
}

function pidAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

try {
  await main();
} catch (error) {
  process.stderr.write(`[memory_retrieval_http_smoke] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
}
