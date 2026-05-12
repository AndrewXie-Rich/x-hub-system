#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    cycles: 3,
    intervalMs: 250,
    timeoutMs: 30000,
    maxEndpointMs: 2000,
    maxCycleMs: 5000,
    port: 57000 + (process.pid % 1000),
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--cycles':
        out.cycles = parseIntInRange(next, out.cycles, 1, 100);
        i += 1;
        break;
      case '--interval-ms':
        out.intervalMs = parseIntInRange(next, out.intervalMs, 0, 60000);
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 1000, 120000);
        i += 1;
        break;
      case '--max-endpoint-ms':
        out.maxEndpointMs = parseIntInRange(next, out.maxEndpointMs, 1, 60000);
        i += 1;
        break;
      case '--max-cycle-ms':
        out.maxCycleMs = parseIntInRange(next, out.maxCycleMs, 1, 120000);
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
    'ops_readiness_gate.js',
    '',
    'Options:',
    '  --cycles <n>        Readiness polling cycles, default 3',
    '  --interval-ms <ms>  Delay between cycles, default 250',
    '  --timeout-ms <ms>   Command timeout, default 30000',
    '  --max-endpoint-ms <ms>  Per-endpoint latency budget, default 2000',
    '  --max-cycle-ms <ms>     Per-cycle latency budget, default 5000',
    '  --port <port>       Local xhubd HTTP port',
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

function writeFixtures({ memoryDir, skillsDir }) {
  fs.mkdirSync(path.join(memoryDir, 'project'), { recursive: true });
  fs.mkdirSync(path.join(memoryDir, 'personal'), { recursive: true });
  fs.mkdirSync(path.join(skillsDir, 'memory-core'), { recursive: true });

  fs.writeFileSync(
    path.join(memoryDir, 'project', 'capsule.md'),
    'Use governed Rust Hub memory retrieval for long running ops readiness. Keep assembly explainable.\n',
    'utf8'
  );
  fs.writeFileSync(
    path.join(memoryDir, 'project', 'runtime.json'),
    `${JSON.stringify({
      summary: 'long running ops readiness memory document',
      detail: 'The ops gate should read memory through the read-only retrieval path.',
      api_key: 'sk-ops-readiness-secret-that-must-not-leak',
    }, null, 2)}\n`,
    'utf8'
  );
  fs.writeFileSync(
    path.join(memoryDir, 'personal', 'capsule.md'),
    'Personal capsule content should stay out of project_code readiness retrieval.\n',
    'utf8'
  );
  fs.writeFileSync(
    path.join(skillsDir, 'memory-core', 'SKILL.md'),
    '# Memory Core\nUse memory capability only through Hub policy gates. Rust must not execute this skill.\n',
    'utf8'
  );
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
    XHUB_RUST_READY_CACHE_TTL_MS: process.env.XHUB_RUST_READY_CACHE_TTL_MS || '250',
  };
  const packagedBin = path.join(ROOT_DIR, 'bin', 'xhubd');
  const debugBin = path.join(ROOT_DIR, 'target', 'debug', 'xhubd');
  let bin = '';
  if (fs.existsSync(packagedBin)) {
    bin = packagedBin;
  } else {
    const built = spawnSyncChecked('cargo', ['build', '--bin', 'xhubd'], { cwd: ROOT_DIR });
    if (built.status !== 0) {
      throw new Error(`cargo build failed before ops readiness gate: ${built.stderr}`);
    }
    bin = debugBin;
  }

  const child = spawn(bin, ['serve'], { cwd: ROOT_DIR, env, stdio: ['ignore', 'pipe', 'pipe'] });
  const output = { stdout: '', stderr: '' };
  child.stdout.on('data', (chunk) => { output.stdout += chunk.toString(); });
  child.stderr.on('data', (chunk) => { output.stderr += chunk.toString(); });
  return { child, output };
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
          reject(new Error(`http_status:${res.statusCode}:${raw.slice(0, 500)}`));
          return;
        }
        try {
          resolve(JSON.parse(raw));
        } catch (error) {
          reject(new Error(`invalid_json:${error.message}:${raw.slice(0, 500)}`));
        }
      });
    });
    req.on('timeout', () => req.destroy(new Error('http_timeout')));
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function timedHttpJson(label, method, url, body = undefined, timeoutMs = 1000) {
  const started = process.hrtime.bigint();
  const value = await httpJson(method, url, body, timeoutMs);
  const elapsedMs = Number((process.hrtime.bigint() - started) / 1000000n);
  return { label, value, elapsedMs };
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
      await sleep(100);
    }
  }
  throw new Error(`xhubd health timeout\nstdout=${safeTail(output.stdout)}\nstderr=${safeTail(output.stderr)}`);
}

async function stopChild(child) {
  if (!child || !child.pid || child.exitCode !== null) return;
  child.kill('SIGTERM');
  spawnSync('kill', ['-TERM', String(child.pid)], { encoding: 'utf8' });
  await waitForExit(child, 5000);
}

async function waitForExit(child, timeoutMs) {
  if (!child || !child.pid || child.exitCode !== null) return;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (child.exitCode !== null || !pidAlive(child.pid)) return;
    await sleep(100);
  }
  if (child.exitCode === null && pidAlive(child.pid)) {
    child.kill('SIGKILL');
    spawnSync('kill', ['-KILL', String(child.pid)], { encoding: 'utf8' });
    for (let i = 0; i < 50; i += 1) {
      if (child.exitCode !== null || !pidAlive(child.pid)) return;
      await sleep(100);
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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function assertNoLeaks(value, label) {
  const raw = JSON.stringify(value);
  assertOk(!raw.includes('sk-ops-readiness-secret-that-must-not-leak'), `${label} leaked secret`);
  assertOk(!raw.includes('Personal capsule content'), `${label} leaked personal capsule`);
  assertOk(!/"api_key"\s*:/.test(raw), `${label} leaked api_key field`);
  assertOk(!/"detail_json"\s*:/.test(raw), `${label} leaked detail_json field`);
}

function runUiCompatibilityGate() {
  const commandPath = path.join(ROOT_DIR, 'tools', 'ui_compatibility_no_product_ui_change_gate.command');
  if (!fs.existsSync(commandPath)) {
    return {
      ok: false,
      skipped: false,
      error: 'ui_compatibility_gate_missing',
    };
  }
  const result = spawnSync('bash', [commandPath], {
    cwd: ROOT_DIR,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
  });
  if (result.status !== 0) {
    return {
      ok: false,
      skipped: false,
      error: 'ui_compatibility_gate_failed',
      stderr_tail: safeTail(result.stderr),
    };
  }
  try {
    const parsed = JSON.parse(result.stdout);
    return {
      ok: parsed?.ok === true
        && parsed?.product_ui_change === false
        && parsed?.swift_ui_files_touched === false
        && parsed?.rust_browser_product_ui === false,
      product_ui_change: parsed?.product_ui_change === true,
      swift_ui_files_touched: parsed?.swift_ui_files_touched === true,
      rust_browser_product_ui: parsed?.rust_browser_product_ui === true,
    };
  } catch (error) {
    return {
      ok: false,
      skipped: false,
      error: `ui_compatibility_gate_invalid_json:${error.message}`,
    };
  }
}

async function seedSkillPolicy(baseUrl) {
  const pin = await httpJson('POST', `${baseUrl}/skills/pin`, {
    scope_key: 'project:ops-readiness',
    skill_id: 'memory-core',
    actor: 'ops-readiness-gate',
  }, 1500);
  assertOk(pin?.ok === true, 'ops gate skill pin failed', pin);

  const grant = await httpJson('POST', `${baseUrl}/skills/grant`, {
    scope_key: 'project:ops-readiness',
    skill_id: 'memory-core',
    capability: 'memory',
    actor: 'ops-readiness-gate',
  }, 1500);
  assertOk(grant?.ok === true, 'ops gate skill grant failed', grant);

  const preflight = await httpJson('POST', `${baseUrl}/skills/preflight`, {
    scope_key: 'project:ops-readiness',
    skill_id: 'memory-core',
    requested_capabilities: ['memory'],
    request_id: 'ops-readiness-preflight',
    audit_ref: 'ops-readiness-gate',
  }, 1500);
  assertOk(preflight?.preflight?.allowed === true, 'ops gate preflight was not allowed after pin/grant', preflight);
  assertOk(preflight?.preflight?.execution_authority_in_rust === false, 'ops gate preflight reported execution authority', preflight);
  assertNoLeaks(preflight, 'ops preflight');
}

function assertLatency(hit, budgetMs) {
  assertOk(hit.elapsedMs <= budgetMs, `${hit.label} exceeded latency budget`, {
    elapsed_ms: hit.elapsedMs,
    budget_ms: budgetMs,
  });
}

async function checkCycle(baseUrl, cycleIndex, budgets) {
  const cycleStarted = process.hrtime.bigint();
  const endpointLatencies = [];

  const readyHit = await timedHttpJson('ready', 'GET', `${baseUrl}/ready`, undefined, 1500);
  assertLatency(readyHit, budgets.maxEndpointMs);
  endpointLatencies.push({ endpoint: readyHit.label, elapsed_ms: readyHit.elapsedMs });
  const ready = readyHit.value;
  assertOk(ready?.ready === true, 'daemon /ready was not ready', ready);
  assertOk(ready?.capabilities?.readiness_cache_http === true, 'readiness cache capability missing', ready);
  assertOk(ready?.capabilities?.memory_snapshot_cache_http === true, 'memory snapshot cache capability missing', ready);
  assertOk(ready?.capabilities?.skills_catalog_cache_http === true, 'skills catalog cache capability missing', ready);
  assertOk(ready?.capabilities?.http_backpressure === true, 'HTTP backpressure capability missing', ready);
  assertOk(ready?.capabilities?.http_metrics === true, 'HTTP metrics capability missing', ready);
  assertOk(Number(ready?.performance?.readiness_cache_ttl_ms || 0) >= 1, 'readiness cache ttl was not enabled', ready?.performance || {});
  assertOk(Number(ready?.performance?.memory_snapshot_cache_ttl_ms || 0) >= 1, 'memory snapshot cache ttl was not enabled', ready?.performance || {});
  assertOk(Number(ready?.performance?.skills_catalog_cache_ttl_ms || 0) >= 1, 'skills catalog cache ttl was not enabled', ready?.performance || {});
  assertOk(Number(ready?.performance?.http_max_in_flight || 0) >= 1, 'HTTP max in-flight was not configured', ready?.performance || {});
  assertOk(Number(ready?.performance?.http_slow_ms || 0) >= 1, 'HTTP slow threshold was not configured', ready?.performance || {});
  assertOk(ready?.network?.loopback_bind === true, 'ops gate expected loopback bind', ready?.network || {});
  assertOk(ready?.capabilities?.cross_network_auth_gate === true, 'cross-network auth gate missing', ready);
  assertOk(ready?.capabilities?.memory_retrieval_http === true, 'memory HTTP capability missing', ready);
  assertOk(ready?.capabilities?.skills_policy_store_readiness_http === true, 'skills policy store readiness capability missing', ready);
  assertOk(ready?.skills?.execution_authority_in_rust === false, 'skills execution authority unexpectedly enabled', ready?.skills || {});
  assertOk(ready?.memory?.canonical_writer_in_rust === false, 'memory writer authority unexpectedly enabled', ready?.memory || {});

  const cachedReadyHit = await timedHttpJson('ready_cached', 'GET', `${baseUrl}/ready`, undefined, 1500);
  assertLatency(cachedReadyHit, budgets.maxEndpointMs);
  endpointLatencies.push({ endpoint: cachedReadyHit.label, elapsed_ms: cachedReadyHit.elapsedMs });
  const cachedReady = cachedReadyHit.value;
  assertOk(cachedReady?.generated_at_ms === ready?.generated_at_ms, 'second /ready call did not hit readiness cache', {
    first_generated_at_ms: ready?.generated_at_ms,
    second_generated_at_ms: cachedReady?.generated_at_ms,
  });

  const memoryReadinessHit = await timedHttpJson('memory_readiness', 'GET', `${baseUrl}/memory/readiness`, undefined, 1500);
  assertLatency(memoryReadinessHit, budgets.maxEndpointMs);
  endpointLatencies.push({ endpoint: memoryReadinessHit.label, elapsed_ms: memoryReadinessHit.elapsedMs });
  const memoryReadiness = memoryReadinessHit.value;
  assertOk(memoryReadiness?.readiness?.ready === true, 'memory readiness was not ready', memoryReadiness);
  assertOk(memoryReadiness?.readiness?.writer_authority_in_rust === false, 'memory writer authority unexpectedly enabled', memoryReadiness);

  const memoryReadinessCachedHit = await timedHttpJson('memory_readiness_cached', 'GET', `${baseUrl}/memory/readiness`, undefined, 1500);
  assertLatency(memoryReadinessCachedHit, budgets.maxEndpointMs);
  endpointLatencies.push({ endpoint: memoryReadinessCachedHit.label, elapsed_ms: memoryReadinessCachedHit.elapsedMs });
  assertOk(JSON.stringify(memoryReadinessCachedHit.value) === JSON.stringify(memoryReadiness), 'second memory readiness call changed within snapshot cache ttl');

  const searchParams = new URLSearchParams({
    query: 'long running ops readiness memory',
    max_results: '3',
    max_snippet_chars: '220',
  });
  const searchHit = await timedHttpJson('memory_search', 'GET', `${baseUrl}/memory/search?${searchParams.toString()}`, undefined, 1500);
  assertLatency(searchHit, budgets.maxEndpointMs);
  endpointLatencies.push({ endpoint: searchHit.label, elapsed_ms: searchHit.elapsedMs });
  const search = searchHit.value;
  assertOk(search?.schema_version === 'xt.memory_retrieval_result.v1', 'memory search schema mismatch', search);
  assertOk(Array.isArray(search?.results) && search.results.length >= 1, 'memory search returned no results', search);
  assertNoLeaks(search, 'ops memory search');

  const deniedParams = new URLSearchParams({ query: 'show api key' });
  const deniedHit = await timedHttpJson('memory_secret_query', 'GET', `${baseUrl}/memory/search?${deniedParams.toString()}`, undefined, 1500);
  assertLatency(deniedHit, budgets.maxEndpointMs);
  endpointLatencies.push({ endpoint: deniedHit.label, elapsed_ms: deniedHit.elapsedMs });
  const denied = deniedHit.value;
  assertOk(denied?.status === 'denied', 'secret memory query was not denied', denied);
  assertNoLeaks(denied, 'ops denied memory search');

  const skillsReadinessHit = await timedHttpJson('skills_readiness', 'GET', `${baseUrl}/skills/readiness`, undefined, 1500);
  assertLatency(skillsReadinessHit, budgets.maxEndpointMs);
  endpointLatencies.push({ endpoint: skillsReadinessHit.label, elapsed_ms: skillsReadinessHit.elapsedMs });
  const skillsReadiness = skillsReadinessHit.value;
  assertOk(skillsReadiness?.readiness?.ready === true, 'skills readiness was not ready', skillsReadiness);
  assertOk(skillsReadiness?.readiness?.execution_authority_in_rust === false, 'skills readiness reported execution authority', skillsReadiness);
  assertOk(skillsReadiness?.readiness?.requires_pin_or_grant === true, 'skills readiness did not require pin/grant', skillsReadiness);

  const skillsReadinessCachedHit = await timedHttpJson('skills_readiness_cached', 'GET', `${baseUrl}/skills/readiness`, undefined, 1500);
  assertLatency(skillsReadinessCachedHit, budgets.maxEndpointMs);
  endpointLatencies.push({ endpoint: skillsReadinessCachedHit.label, elapsed_ms: skillsReadinessCachedHit.elapsedMs });
  assertOk(JSON.stringify(skillsReadinessCachedHit.value) === JSON.stringify(skillsReadiness), 'second skills readiness call changed within catalog cache ttl');

  const policyParams = new URLSearchParams({
    max_preflight_audit_rows: '1000',
    max_policy_event_rows: '1000',
  });
  const policyReadinessHit = await timedHttpJson('skills_policy_readiness', 'GET', `${baseUrl}/skills/policy-readiness?${policyParams.toString()}`, undefined, 1500);
  assertLatency(policyReadinessHit, budgets.maxEndpointMs);
  endpointLatencies.push({ endpoint: policyReadinessHit.label, elapsed_ms: policyReadinessHit.elapsedMs });
  const policyReadiness = policyReadinessHit.value;
  assertOk(policyReadiness?.policy_readiness?.schema_version === 'xhub.skills_policy_store_readiness.v1', 'policy readiness schema mismatch', policyReadiness);
  assertOk(policyReadiness?.policy_readiness?.ready === true, 'policy readiness was not ready', policyReadiness);
  assertOk(policyReadiness?.policy_readiness?.execution_authority_in_rust === false, 'policy readiness reported execution authority', policyReadiness);
  assertOk(Number(policyReadiness?.policy_readiness?.active_pin_count || 0) >= 1, 'policy readiness missing active pin', policyReadiness);
  assertOk(Number(policyReadiness?.policy_readiness?.active_grant_count || 0) >= 1, 'policy readiness missing active grant', policyReadiness);
  assertOk(Number(policyReadiness?.policy_readiness?.preflight_audit_count || 0) >= 1, 'policy readiness missing preflight audit row', policyReadiness);
  assertNoLeaks(policyReadiness, 'ops policy readiness');

  const metricsHit = await timedHttpJson('http_metrics', 'GET', `${baseUrl}/runtime/http-metrics`, undefined, 1500);
  assertLatency(metricsHit, budgets.maxEndpointMs);
  endpointLatencies.push({ endpoint: metricsHit.label, elapsed_ms: metricsHit.elapsedMs });
  const metrics = metricsHit.value;
  assertOk(metrics?.schema_version === 'xhub.rust_hub.http_metrics.v1', 'HTTP metrics schema mismatch', metrics);
  assertOk(Number(metrics?.total_requests || 0) >= 1, 'HTTP metrics did not record requests', metrics);
  assertOk(Number(metrics?.slow_threshold_ms || 0) >= 1, 'HTTP metrics slow threshold missing', metrics);
  assertOk(Array.isArray(metrics?.routes), 'HTTP metrics routes missing', metrics);
  assertOk(metrics.routes.some((row) => row.route === '/ready'), 'HTTP metrics missing /ready route', metrics);
  assertOk(metrics?.production_authority_change === false, 'HTTP metrics reported production authority change', metrics);
  assertOk(metrics?.detail_json_included === false, 'HTTP metrics reported detail json included', metrics);
  assertNoLeaks(metrics, 'ops http metrics');

  const cycleElapsedMs = Number((process.hrtime.bigint() - cycleStarted) / 1000000n);
  assertOk(cycleElapsedMs <= budgets.maxCycleMs, 'ops readiness cycle exceeded latency budget', {
    elapsed_ms: cycleElapsedMs,
    budget_ms: budgets.maxCycleMs,
  });

  return {
    cycle: cycleIndex,
    ready: true,
    cycle_elapsed_ms: cycleElapsedMs,
    max_endpoint_elapsed_ms: Math.max(...endpointLatencies.map((item) => item.elapsed_ms)),
    endpoint_latencies: endpointLatencies,
    memory_indexed_document_count: Number(memoryReadiness?.readiness?.indexed_document_count || 0),
    memory_search_result_count: search.results.length,
    skills_accepted_count: Number(skillsReadiness?.readiness?.accepted_skill_count || 0),
    active_pin_count: Number(policyReadiness?.policy_readiness?.active_pin_count || 0),
    active_grant_count: Number(policyReadiness?.policy_readiness?.active_grant_count || 0),
    preflight_audit_count: Number(policyReadiness?.policy_readiness?.preflight_audit_count || 0),
    policy_event_count: Number(policyReadiness?.policy_readiness?.policy_event_count || 0),
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-ops-readiness-gate-'));
  const runtimeDir = path.join(tempRoot, 'runtime');
  const memoryDir = path.join(tempRoot, 'memory');
  const skillsDir = path.join(tempRoot, 'skills');
  const dbPath = path.join(tempRoot, 'data', 'hub.sqlite3');
  const baseUrl = `http://127.0.0.1:${args.port}`;
  let child;

  try {
    writeFixtures({ memoryDir, skillsDir });
    const started = startXhubd({
      port: args.port,
      dbPath,
      runtimeDir,
      memoryDir,
      skillsDir,
    });
    child = started.child;
    await waitForHealth(baseUrl, child, started.output, args.timeoutMs);
    await seedSkillPolicy(baseUrl);

    const cycles = [];
    for (let i = 0; i < args.cycles; i += 1) {
      cycles.push(await checkCycle(baseUrl, i + 1, {
        maxEndpointMs: args.maxEndpointMs,
        maxCycleMs: args.maxCycleMs,
      }));
      if (i + 1 < args.cycles && args.intervalMs > 0) {
        await sleep(args.intervalMs);
      }
    }

    const uiGate = runUiCompatibilityGate();
    assertOk(uiGate.ok === true, 'UI compatibility gate failed during ops readiness gate', uiGate);

    const result = {
      ok: true,
      schema_version: 'xhub.rust_hub.ops_readiness_gate.v1',
      command: 'ops-readiness-gate',
      http_base_url: baseUrl,
      cycles_requested: args.cycles,
      cycles_completed: cycles.length,
      max_endpoint_ms: args.maxEndpointMs,
      max_cycle_ms: args.maxCycleMs,
      max_observed_endpoint_ms: Math.max(...cycles.map((cycle) => cycle.max_endpoint_elapsed_ms)),
      max_observed_cycle_ms: Math.max(...cycles.map((cycle) => cycle.cycle_elapsed_ms)),
      readiness_ready: true,
      readiness_cache_verified: true,
      memory_snapshot_cache_verified: true,
      skills_catalog_cache_verified: true,
      http_backpressure_enabled: true,
      http_metrics_ready: true,
      memory_ready: true,
      skills_ready: true,
      policy_store_readiness_ready: true,
      ui_product_change: false,
      swift_ui_files_touched: false,
      rust_browser_product_ui: false,
      node_remains_authority: true,
      memory_writer_authority_in_rust: false,
      skills_execution_authority_in_rust: false,
      cross_network_auth_gate: true,
      secret_leak: false,
      cycle_summaries: cycles,
    };
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } finally {
    await stopChild(child);
    try {
      fs.rmSync(tempRoot, { recursive: true, force: true });
    } catch {}
  }
}

try {
  await main();
} catch (error) {
  process.stderr.write(`[ops_readiness_gate] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
}
