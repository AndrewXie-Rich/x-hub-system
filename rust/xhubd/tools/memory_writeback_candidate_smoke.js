#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const PROJECT_ID = 'candidate_lifecycle_smoke_project';

function safeString(value) {
  return String(value ?? '').trim();
}

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    timeoutMs: 30000,
    port: 59000 + (process.pid % 1000),
    keepTemp: false,
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
      case '--keep-temp':
        out.keepTemp = true;
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
    'memory_writeback_candidate_smoke.js',
    '',
    'Options:',
    '  --timeout-ms <ms>    Command timeout, default 30000',
    '  --port <port>        Local xhubd HTTP port',
    '  --keep-temp          Keep temp hub root for debugging',
  ].join('\n');
}

function safeTail(value) {
  return String(value || '').split(/\r?\n/).slice(-25).join('\n');
}

function assertOk(condition, message, details = {}) {
  if (!condition) {
    const suffix = Object.keys(details).length ? ` ${JSON.stringify(details).slice(0, 800)}` : '';
    throw new Error(`${message}${suffix}`);
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
  const debugBin = path.join(ROOT_DIR, 'target', 'debug', 'xhubd');
  const built = spawnSyncChecked('cargo', ['build', '--bin', 'xhubd'], { cwd: ROOT_DIR });
  if (built.status !== 0) {
    throw new Error(`cargo build failed before candidate smoke: ${built.stderr}`);
  }
  const child = spawn(debugBin, ['serve'], { cwd: ROOT_DIR, env, stdio: ['ignore', 'pipe', 'pipe'] });
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

function httpJson(method, url, body = undefined, timeoutMs = 1500, allowErrorStatus = false) {
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
        let parsed = {};
        try {
          parsed = JSON.parse(raw || '{}');
        } catch (error) {
          reject(new Error(`invalid_json:${error.message}:${raw.slice(0, 400)}`));
          return;
        }
        const statusCode = Number(res.statusCode || 0);
        if (!allowErrorStatus && (statusCode < 200 || statusCode >= 300)) {
          reject(new Error(`http_status:${statusCode}:${raw.slice(0, 400)}`));
          return;
        }
        resolve({ statusCode, body: parsed });
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

async function createCandidate(baseUrl, memoryId, sourceKind, layer, title, text, timeoutMs, extra = {}) {
  const { body } = await httpJson('POST', `${baseUrl}/memory/writeback/candidates`, {
    memory_id: memoryId,
    requester_role: 'tool',
    use_mode: 'tool_plan',
    scope: 'project',
    owner_id: PROJECT_ID,
    project_id: PROJECT_ID,
    source_kind: sourceKind,
    layer,
    title,
    text,
    sensitivity: 'internal',
    visibility: 'local_only',
    audit_ref: 'candidate-lifecycle-smoke',
    ...extra,
  }, timeoutMs);
  assertOk(body?.ok === true, 'candidate create failed', body);
  assertOk(body?.object?.status === 'candidate', 'created candidate was not pending', body);
  assertOk(body?.production_authority_change === false, 'candidate create changed production authority', body);
  return body;
}

async function retrieveMemoryIds(baseUrl, query, timeoutMs) {
  const { body } = await httpJson('POST', `${baseUrl}/memory/retrieve`, {
    scope: 'project',
    project_id: PROJECT_ID,
    query,
    max_results: 8,
    explain: true,
  }, timeoutMs);
  return {
    body,
    ids: Array.isArray(body?.results) ? body.results.map((item) => safeString(item?.memory_id)).filter(Boolean) : [],
  };
}

async function wait(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-memory-candidate-smoke-'));
  const memoryDir = path.join(tempRoot, 'memory');
  const runtimeDir = path.join(tempRoot, 'runtime');
  const skillsDir = path.join(tempRoot, 'skills');
  const dbPath = path.join(tempRoot, 'data', 'hub.sqlite3');
  const baseUrl = `http://127.0.0.1:${args.port}`;
  let child;

  try {
    const started = startXhubd({
      port: args.port,
      dbPath,
      runtimeDir,
      memoryDir,
      skillsDir,
    });
    child = started.child;
    await waitForHealth(baseUrl, child, started.output, args.timeoutMs);

    const ready = (await httpJson('GET', `${baseUrl}/memory/readiness`, undefined, 1500)).body;
    assertOk(ready?.object_store?.writeback_candidates?.candidate_create_http === true, 'readiness missing candidate create evidence', ready);
    assertOk(ready?.object_store?.writeback_candidates?.candidate_maintenance_http === true, 'readiness missing candidate maintenance evidence', ready);

    await createCandidate(
      baseUrl,
      'mem_candidate_smoke_approve',
      'decision_track',
      'l1_canonical',
      'Candidate smoke approval',
      'Decision: approved candidate smoke object becomes active only after review.',
      1500
    );
    const beforeApprove = await retrieveMemoryIds(baseUrl, 'approved candidate smoke object review', 1500);
    assertOk(!beforeApprove.ids.includes('mem_candidate_smoke_approve'), 'pending candidate appeared in active retrieval', beforeApprove.body);

    const approved = (await httpJson('POST', `${baseUrl}/memory/writeback/candidates/mem_candidate_smoke_approve/approve`, {
      requester_role: 'tool',
      use_mode: 'tool_plan',
      actor: 'candidate_smoke',
      audit_ref: 'candidate-lifecycle-smoke-approve',
    }, 1500)).body;
    assertOk(approved?.status === 'approved', 'candidate approve failed', approved);
    assertOk(approved?.object?.status === 'active', 'approved candidate did not become active', approved);
    assertOk(approved?.production_authority_change === false, 'candidate approve changed production authority', approved);

    const afterApprove = await retrieveMemoryIds(baseUrl, 'approved candidate smoke object review', 1500);
    assertOk(afterApprove.ids.includes('mem_candidate_smoke_approve'), 'approved candidate did not appear in active retrieval', afterApprove.body);

    await createCandidate(
      baseUrl,
      'mem_candidate_smoke_reject',
      'recommendation',
      'l2_observations',
      'Candidate smoke rejection',
      'Recommendation: rejected candidate smoke object must stay out of active retrieval.',
      1500
    );
    const rejected = (await httpJson('POST', `${baseUrl}/memory/writeback/candidates/mem_candidate_smoke_reject/reject`, {
      requester_role: 'tool',
      use_mode: 'tool_plan',
      actor: 'candidate_smoke',
      audit_ref: 'candidate-lifecycle-smoke-reject',
    }, 1500)).body;
    assertOk(rejected?.status === 'rejected', 'candidate reject failed', rejected);
    const afterReject = await retrieveMemoryIds(baseUrl, 'rejected candidate smoke object active retrieval', 1500);
    assertOk(!afterReject.ids.includes('mem_candidate_smoke_reject'), 'rejected candidate appeared in active retrieval', afterReject.body);

    const secret = await httpJson('POST', `${baseUrl}/memory/writeback/candidates`, {
      requester_role: 'tool',
      use_mode: 'tool_plan',
      scope: 'project',
      owner_id: PROJECT_ID,
      project_id: PROJECT_ID,
      source_kind: 'decision_track',
      layer: 'l1_canonical',
      title: 'Secret candidate',
      text: 'Store api key sk-candidate-smoke-secret in memory.',
    }, 1500, true);
    assertOk(secret.statusCode === 403, 'secret-like candidate was not denied', secret.body);
    assertOk(secret.body?.error_code === 'memory_secret_pattern_denied', 'secret-like candidate deny code mismatch', secret.body);

    const extractDryRun = (await httpJson('POST', `${baseUrl}/memory/writeback/candidates/extract?dry_run=1`, {
      project_id: PROJECT_ID,
      audit_ref: 'candidate-lifecycle-smoke-extract-dry-run',
      delta: {
        decisionsAdd: ['Keep extracted smoke deltas pending until explicit review.'],
      },
    }, 1500)).body;
    assertOk(extractDryRun?.dry_run === true, 'extract dry-run was not dry-run', extractDryRun);
    assertOk(Number(extractDryRun?.created_count || 0) === 0, 'extract dry-run created candidates', extractDryRun);

    const extractApply = (await httpJson('POST', `${baseUrl}/memory/writeback/candidates/extract?apply=1`, {
      project_id: PROJECT_ID,
      audit_ref: 'candidate-lifecycle-smoke-extract-apply',
      delta: {
        nextStepsAdd: ['Run candidate lifecycle ops smoke after Rust maintenance lands.'],
      },
    }, 1500)).body;
    assertOk(extractApply?.applied === true, 'extract apply did not apply', extractApply);
    assertOk(Number(extractApply?.created_count || 0) === 1, 'extract apply did not create one candidate', extractApply);
    assertOk(extractApply?.candidate_writeback?.active_write === false, 'extract reported active write', extractApply);

    await createCandidate(
      baseUrl,
      'mem_candidate_smoke_stale_working_set',
      'next_step',
      'l3_working_set',
      'Stale working set candidate',
      'Next step: stale working set smoke candidate should archive during maintenance.',
      1500,
      { ttl_ms: 1 }
    );
    await createCandidate(
      baseUrl,
      'mem_candidate_smoke_stale_canonical',
      'decision_track',
      'l1_canonical',
      'Stale canonical candidate',
      'Decision: stale canonical smoke candidate should require review, not archive.',
      1500,
      { ttl_ms: 1 }
    );
    await wait(15);
    const maintenanceDryRun = (await httpJson('POST', `${baseUrl}/memory/writeback/candidates/maintenance?dry_run=1&project_id=${encodeURIComponent(PROJECT_ID)}&max_age_ms=1`, {}, 1500)).body;
    assertOk(maintenanceDryRun?.dry_run === true, 'maintenance dry-run was not dry-run', maintenanceDryRun);
    assertOk(Number(maintenanceDryRun?.mutation_count || 0) === 0, 'maintenance dry-run mutated', maintenanceDryRun);
    assertOk(Number(maintenanceDryRun?.planned_archive_count || 0) >= 1, 'maintenance dry-run did not plan archive', maintenanceDryRun);
    assertOk(Number(maintenanceDryRun?.planned_stale_review_required_count || 0) >= 1, 'maintenance dry-run did not plan stale review', maintenanceDryRun);

    const maintenanceApply = (await httpJson('POST', `${baseUrl}/memory/writeback/candidates/maintenance?apply=1&project_id=${encodeURIComponent(PROJECT_ID)}&max_age_ms=1`, {
      actor: 'candidate_smoke',
      audit_ref: 'candidate-lifecycle-smoke-maintenance',
    }, 1500)).body;
    assertOk(maintenanceApply?.applied === true, 'maintenance apply did not apply', maintenanceApply);
    assertOk(Number(maintenanceApply?.archived_count || 0) >= 1, 'maintenance did not archive stale working-set candidate', maintenanceApply);
    assertOk(Number(maintenanceApply?.stale_review_required_count || 0) >= 1, 'maintenance did not mark stale canonical candidate', maintenanceApply);
    assertOk(maintenanceApply?.production_authority_change === false, 'maintenance changed production authority', maintenanceApply);
    assertOk(!JSON.stringify(maintenanceApply).includes('sk-candidate-smoke-secret'), 'maintenance report leaked secret text');

    const archived = (await httpJson('GET', `${baseUrl}/memory/objects/mem_candidate_smoke_stale_working_set`, undefined, 1500)).body;
    assertOk(archived?.object?.status === 'archived', 'stale working-set candidate was not archived', archived);
    const staleCanonical = (await httpJson('GET', `${baseUrl}/memory/objects/mem_candidate_smoke_stale_canonical`, undefined, 1500)).body;
    assertOk(staleCanonical?.object?.status === 'candidate', 'canonical stale candidate should remain pending', staleCanonical);
    assertOk(staleCanonical?.object?.policy?.stale_review_required === true, 'canonical stale candidate missing review marker', staleCanonical);

    const finalReadiness = (await httpJson('GET', `${baseUrl}/memory/readiness`, undefined, 1500)).body;
    assertOk(finalReadiness?.object_store?.writeback_candidates?.maintenance?.candidate_maintenance_schema === 'xhub.memory.writeback_candidate_maintenance.v1', 'final readiness missing maintenance schema', finalReadiness);

    const result = {
      ok: true,
      schema_version: 'xhub.rust_hub.memory_writeback_candidate_smoke.v1',
      command: 'memory-writeback-candidate-smoke',
      http_base_url: baseUrl,
      candidate_create_ok: true,
      pending_not_retrieved: true,
      approve_ok: true,
      approved_retrieved: true,
      reject_ok: true,
      rejected_not_retrieved: true,
      extract_dry_run_ok: true,
      extract_apply_candidate_count: Number(extractApply.created_count || 0),
      secret_candidate_fail_closed: true,
      maintenance_dry_run_ok: true,
      maintenance_archive_count: Number(maintenanceApply.archived_count || 0),
      maintenance_stale_review_required_count: Number(maintenanceApply.stale_review_required_count || 0),
      readiness_maintenance_ok: true,
      production_authority_change: false,
      temp_root: args.keepTemp ? tempRoot : '',
    };
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } finally {
    if (child && child.exitCode === null) {
      child.kill('SIGTERM');
      spawnSync('kill', ['-TERM', String(child.pid)], { encoding: 'utf8' });
      await waitForExit(child, 5000);
    }
    if (!args.keepTemp) {
      try {
        fs.rmSync(tempRoot, { recursive: true, force: true });
      } catch {}
    }
  }
}

async function waitForExit(child, timeoutMs) {
  if (!child || !child.pid || child.exitCode !== null) return;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) return;
    await wait(100);
  }
  child.kill('SIGKILL');
}

main().catch((error) => {
  process.stderr.write(`${error?.stack || error}\n`);
  process.exitCode = 1;
});
