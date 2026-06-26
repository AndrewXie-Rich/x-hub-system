#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const PROJECT_ID = 'quality_bench_project';

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    timeoutMs: 30000,
    port: 59000 + (process.pid % 1000),
    profile: 'quick',
    noiseCount: 72,
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
      case '--profile':
        if (!['quick', 'large'].includes(String(next || '').trim())) {
          throw new Error(`invalid --profile: ${next}`);
        }
        out.profile = String(next).trim();
        i += 1;
        break;
      case '--noise-count':
        out.noiseCount = parseIntInRange(next, out.noiseCount, 0, 500);
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
    'memory_hybrid_quality_bench.js',
    '',
    'Options:',
    '  --timeout-ms <ms>    Command timeout, default 30000',
    '  --port <port>        Local xhubd HTTP port',
    '  --profile <name>     quick|large, default quick',
    '  --noise-count <n>    Large-profile distractor objects, default 72',
  ].join('\n');
}

function assertOk(condition, message, details = {}) {
  if (!condition) {
    const suffix = Object.keys(details).length ? ` ${JSON.stringify(details).slice(0, 700)}` : '';
    throw new Error(`${message}${suffix}`);
  }
}

function safeTail(value) {
  return String(value || '').split(/\r?\n/).slice(-25).join('\n');
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
      throw new Error(`cargo build failed before memory quality bench: ${built.stderr}`);
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

function fixtureObjects({ profile = 'quick', noiseCount = 72 } = {}) {
  const base = [
    {
      memory_id: 'mem_quality_decision',
      source_kind: 'decision_track',
      layer: 'l1_canonical',
      title: 'Provider route decision',
      text: 'Decision: route provider and model calls through the Rust memory gateway before provider selection.',
      tags: ['decision', 'provider_route'],
      visibility: 'local_only',
      sensitivity: 'internal',
      pinned: true,
    },
    {
      memory_id: 'mem_quality_blocker',
      source_kind: 'risk',
      layer: 'l2_observations',
      title: 'Remote export blocker',
      text: 'Blocker: remote export must use sanitized references and must not include raw evidence bodies.',
      tags: ['blocker', 'remote_export'],
      visibility: 'local_only',
      sensitivity: 'internal',
    },
    {
      memory_id: 'mem_quality_next_step',
      source_kind: 'next_step',
      layer: 'l3_working_set',
      title: 'Retrieval next step',
      text: 'Next step: rebuild the memory object index and run the route-sensitive retrieval quality bench.',
      tags: ['next_step', 'bench'],
      visibility: 'local_only',
      sensitivity: 'internal',
    },
    {
      memory_id: 'mem_quality_raw_evidence',
      source_kind: 'memory_file',
      layer: 'l4_raw_evidence',
      title: 'Provider timeout raw evidence',
      text: 'Raw evidence log: provider route request failed with timeout during the quality bench.',
      tags: ['raw_evidence', 'timeout'],
      visibility: 'local_only',
      sensitivity: 'internal',
    },
    {
      memory_id: 'mem_quality_remote_guidance',
      source_kind: 'guidance_injection',
      layer: 'l1_canonical',
      title: 'Stable remote guidance',
      text: 'Remote bundle guidance: send compact sanitized references through the stable domain entry only.',
      tags: ['remote_bundle', 'domain'],
      visibility: 'sanitized_remote_ok',
      sensitivity: 'internal',
    },
    {
      memory_id: 'mem_quality_private_note',
      source_kind: 'current_state',
      layer: 'l2_observations',
      title: 'Private escalation note',
      text: 'Private escalation note: local-only operator context for the memory bench.',
      tags: ['private_context'],
      visibility: 'local_only',
      sensitivity: 'private',
    },
  ];
  if (profile !== 'large') {
    return base;
  }
  return [
    ...base,
    ...largeProfileTargetObjects(),
    ...largeProfileNoiseObjects(noiseCount),
  ];
}

function largeProfileTargetObjects() {
  return [
    {
      memory_id: 'mem_quality_cn_domain',
      source_kind: 'decision_track',
      layer: 'l1_canonical',
      title: '中文域名远程入口决策',
      text: 'Decision: 中文 远程 入口 使用 稳定 域名 和 sanitized references，避免 raw evidence 进入远程 bundle。',
      tags: ['cn', 'remote_domain', 'decision'],
      visibility: 'sanitized_remote_ok',
      sensitivity: 'internal',
      pinned: true,
    },
    {
      memory_id: 'mem_quality_review_guidance',
      source_kind: 'recommendation',
      layer: 'l2_observations',
      title: 'Reviewer guidance trace',
      text: 'Recommendation: reviewer notes should appear as redacted retrieval trace evidence, not as prompt body.',
      tags: ['reviewer', 'trace'],
      visibility: 'local_only',
      sensitivity: 'internal',
    },
    {
      memory_id: 'mem_quality_old_state',
      source_kind: 'current_state',
      layer: 'l2_observations',
      title: 'Older retrieval state',
      text: 'Current state: older memory retrieval implementation used only lexical scoring before BM25.',
      tags: ['older_state'],
      visibility: 'local_only',
      sensitivity: 'internal',
    },
  ];
}

function largeProfileNoiseObjects(noiseCount) {
  const layers = ['l1_canonical', 'l2_observations', 'l3_working_set'];
  const sourceKinds = ['project_requirement', 'open_question', 'current_state', 'recommendation'];
  const themes = [
    'provider route inventory snapshot',
    'remote access setup note',
    'memory board presentation draft',
    'scheduler heartbeat observation',
    'model runtime repair note',
    'XT pairing UX followup',
    'domain setup validation record',
    'review workflow context',
  ];
  const rows = [];
  for (let i = 0; i < noiseCount; i += 1) {
    const layer = layers[i % layers.length];
    const sourceKind = sourceKinds[i % sourceKinds.length];
    const theme = themes[i % themes.length];
    rows.push({
      memory_id: `mem_quality_noise_${String(i).padStart(3, '0')}`,
      source_kind: sourceKind,
      layer,
      title: `Noise ${i}: ${theme}`,
      text: [
        `Noise record ${i} for ${theme}.`,
        'It intentionally shares generic route, memory, provider, domain, reviewer, and retrieval words.',
        'It must not outrank the targeted canonical object when the query contains precise intent.',
      ].join(' '),
      tags: ['noise', sourceKind, layer],
      visibility: i % 5 === 0 ? 'sanitized_remote_ok' : 'local_only',
      sensitivity: i % 7 === 0 ? 'private' : 'internal',
    });
  }
  return rows;
}

function benchCases(profile = 'quick') {
  const quickCases = [
    {
      name: 'project_chat_decision',
      route_profile: 'project_chat',
      request: {
        scope: 'project',
        project_id: PROJECT_ID,
        query: 'why route provider through memory gateway before selection',
        max_results: 3,
        explain: true,
      },
      expect_top: 'mem_quality_decision',
      require_selected_trace: true,
    },
    {
      name: 'supervisor_next_step_layer_filter',
      route_profile: 'supervisor_orchestration',
      request: {
        scope: 'project',
        project_id: PROJECT_ID,
        query: 'what next step rebuild index bench',
        requested_layers: ['l3_working_set'],
        max_results: 3,
        explain: true,
      },
      expect_top: 'mem_quality_next_step',
      require_omitted_reason: 'layer_filter',
    },
    {
      name: 'remote_bundle_sanitized_visibility',
      route_profile: 'remote_prompt_bundle',
      request: {
        scope: 'project',
        project_id: PROJECT_ID,
        query: 'stable domain remote bundle sanitized references',
        visibility: 'sanitized_remote_ok',
        sensitivity_max: 'internal',
        max_results: 3,
        explain: true,
      },
      expect_top: 'mem_quality_remote_guidance',
      require_omitted_reason: 'visibility_filter',
    },
    {
      name: 'tool_raw_evidence_opt_in',
      route_profile: 'tool_plan_raw_evidence',
      request: {
        scope: 'project',
        project_id: PROJECT_ID,
        query: 'provider timeout raw evidence',
        requested_layers: ['l4_raw_evidence'],
        max_results: 3,
        explain: true,
      },
      expect_top: 'mem_quality_raw_evidence',
      require_omitted_reason: 'layer_filter',
    },
    {
      name: 'remote_bundle_private_sensitivity_gate',
      route_profile: 'remote_prompt_bundle',
      request: {
        scope: 'project',
        project_id: PROJECT_ID,
        query: 'private escalation operator context',
        sensitivity_max: 'internal',
        max_results: 3,
        explain: true,
      },
      require_omitted_memory: 'mem_quality_private_note',
      require_omitted_reason: 'sensitivity_filter',
    },
  ];
  if (profile !== 'large') {
    return quickCases;
  }
  const largeBaseCases = quickCases.map((testCase) => ({
    ...testCase,
    request: {
      ...testCase.request,
      max_results: 10,
    },
  }));
  return [
    ...largeBaseCases,
    {
      name: 'large_profile_cn_domain_remote_bundle',
      route_profile: 'remote_prompt_bundle',
      request: {
        scope: 'project',
        project_id: PROJECT_ID,
        query: '中文 远程 入口 稳定 域名 sanitized references',
        visibility: 'sanitized_remote_ok',
        sensitivity_max: 'internal',
        max_results: 10,
        explain: true,
      },
      expect_top: 'mem_quality_cn_domain',
      require_selected_trace: true,
      require_omitted_reason: 'visibility_filter',
    },
    {
      name: 'large_profile_review_guidance_trace',
      route_profile: 'supervisor_orchestration',
      request: {
        scope: 'project',
        project_id: PROJECT_ID,
        query: 'reviewer notes redacted retrieval trace evidence',
        requested_layers: ['l2_observations'],
        max_results: 10,
        explain: true,
      },
      expect_top: 'mem_quality_review_guidance',
      require_selected_trace: true,
    },
    {
      name: 'large_profile_source_kind_filter',
      route_profile: 'supervisor_orchestration',
      request: {
        scope: 'project',
        project_id: PROJECT_ID,
        query: 'reviewer notes redacted retrieval trace evidence',
        requested_kinds: ['recommendation'],
        max_results: 10,
        explain: true,
      },
      expect_top: 'mem_quality_review_guidance',
      require_selected_trace: true,
      require_omitted_reason: 'source_kind_filter',
    },
  ];
}

async function createFixture(baseUrl, objects) {
  for (const object of objects) {
    const created = await httpJson('POST', `${baseUrl}/memory/objects`, {
      requester_role: 'chat',
      use_mode: 'project_chat',
      scope: 'project',
      owner_id: PROJECT_ID,
      project_id: PROJECT_ID,
      audit_ref: 'memory-quality-bench',
      ...object,
    }, 1500);
    assertOk(created?.ok === true, `fixture create failed for ${object.memory_id}`, created);
  }
}

function summarizeCase(testCase, response) {
  const results = Array.isArray(response?.results) ? response.results : [];
  const expectedFound = testCase.expect_top
    ? results.some((item) => item?.memory_id === testCase.expect_top)
    : true;
  return {
    name: testCase.name,
    route_profile: testCase.route_profile,
    ok: true,
    top_memory_id: results[0]?.memory_id || '',
    result_count: results.length,
    expected_top: testCase.expect_top || '',
    expected_found: expectedFound,
    empty_expected: testCase.expect_empty === true,
    index_source: response?.retrieval_engine?.index_source || '',
    fts: response?.retrieval_engine?.fts || '',
    bm25_used: response?.retrieval_engine?.bm25_used === true,
    matched_count: Number(response?.retrieval_engine?.matched_count || 0),
    omitted_count: Number(response?.retrieval_trace?.omitted_count || 0),
  };
}

function validateCase(testCase, response) {
  assertOk(response?.schema_version === 'xt.memory_retrieval_result.v1', `${testCase.name}: schema mismatch`, response);
  assertOk(response?.source === 'rust_memory_objects_hybrid_v1', `${testCase.name}: source mismatch`, response);
  assertOk(response?.production_authority_change === false, `${testCase.name}: production authority changed`, response);
  assertOk(response?.retrieval_engine?.index_source === 'rust_hub_memory_object_index', `${testCase.name}: did not use derived index`, response?.retrieval_engine || {});
  assertOk(response?.retrieval_engine?.fts === 'derived_index_bm25_rust', `${testCase.name}: did not use Rust BM25 derived-index scorer`, response?.retrieval_engine || {});
  assertOk(response?.retrieval_engine?.bm25_used === true, `${testCase.name}: bm25_used was not true`, response?.retrieval_engine || {});
  assertOk(response?.retrieval_engine?.semantic_used === false, `${testCase.name}: semantic search should be off`, response?.retrieval_engine || {});
  assertOk(response?.retrieval_engine?.rerank_used === false, `${testCase.name}: rerank should be off`, response?.retrieval_engine || {});
  assertOk(response?.retrieval_trace?.schema_version === 'xhub.memory.retrieval_trace.v1', `${testCase.name}: retrieval trace missing`, response);

  const results = Array.isArray(response?.results) ? response.results : [];
  if (testCase.expect_top) {
    assertOk(results[0]?.memory_id === testCase.expect_top, `${testCase.name}: top result mismatch`, { expected: testCase.expect_top, results });
  }
  if (testCase.expect_empty) {
    assertOk(results.length === 0, `${testCase.name}: expected no results`, { results });
  }
  if (testCase.require_selected_trace) {
    assertOk(response.retrieval_trace.selected?.[0]?.memory_id === testCase.expect_top, `${testCase.name}: selected trace mismatch`, response.retrieval_trace);
  }
  if (testCase.require_omitted_reason) {
    const omitted = Array.isArray(response.retrieval_trace.omitted) ? response.retrieval_trace.omitted : [];
    const hasReason = omitted.some((item) => {
      if (item?.reason_code !== testCase.require_omitted_reason) return false;
      if (testCase.require_omitted_memory) return item?.memory_id === testCase.require_omitted_memory;
      return true;
    });
    assertOk(hasReason, `${testCase.name}: omitted trace did not include ${testCase.require_omitted_reason}`, response.retrieval_trace);
  }
}

async function runBench(baseUrl, { profile, objects }) {
  const reindex = await httpJson('POST', `${baseUrl}/memory/reindex`, {}, 3000);
  assertOk(reindex?.ok === true, 'memory reindex failed before quality bench', reindex);
  assertOk(reindex?.production_authority_change === false, 'memory reindex changed production authority', reindex);
  assertOk(Number(reindex?.index?.row_count || 0) === objects.length, 'memory reindex row count mismatch', reindex);

  const cases = [];
  for (const testCase of benchCases(profile)) {
    const response = await httpJson('POST', `${baseUrl}/memory/retrieve`, testCase.request, 1500);
    validateCase(testCase, response);
    cases.push(summarizeCase(testCase, response));
  }
  return {
    reindex,
    cases,
    metrics: qualityMetrics(cases),
  };
}

function qualityMetrics(cases) {
  const topCases = cases.filter((item) => item.expected_top);
  const precisionAt1 = topCases.length
    ? topCases.filter((item) => item.top_memory_id === item.expected_top).length / topCases.length
    : 1;
  const recallAtK = topCases.length
    ? topCases.filter((item) => item.expected_found).length / topCases.length
    : 1;
  const filterCases = cases.filter((item) => item.omitted_count > 0 || item.empty_expected);
  const filterPassRate = filterCases.length
    ? filterCases.filter((item) => item.ok).length / filterCases.length
    : 1;
  const traceCoverage = cases.length
    ? cases.filter((item) => item.omitted_count > 0 || item.result_count > 0).length / cases.length
    : 1;
  return {
    schema_version: 'xhub.rust_hub.memory_hybrid_quality_metrics.v1',
    precision_at_1: round4(precisionAt1),
    recall_at_k: round4(recallAtK),
    filter_pass_rate: round4(filterPassRate),
    trace_coverage: round4(traceCoverage),
  };
}

function round4(value) {
  return Math.round(Number(value || 0) * 10000) / 10000;
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

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-memory-quality-bench-'));
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

    const objects = fixtureObjects({ profile: args.profile, noiseCount: args.noiseCount });
    await createFixture(baseUrl, objects);
    const bench = await runBench(baseUrl, { profile: args.profile, objects });
    const report = {
      ok: true,
      schema_version: 'xhub.rust_hub.memory_hybrid_quality_bench.v1',
      command: 'memory-hybrid-quality-bench',
      http_base_url: baseUrl,
      profile: args.profile,
      project_id: PROJECT_ID,
      fixture_object_count: objects.length,
      case_count: bench.cases.length,
      passed_count: bench.cases.filter((item) => item.ok).length,
      derived_index_source: 'rust_hub_memory_object_index',
      derived_index_row_count: bench.reindex.index.row_count,
      stale_index_count: bench.reindex.index.stale_count,
      semantic_used: false,
      rerank_used: false,
      bm25_used: true,
      production_authority_change: false,
      metrics: bench.metrics,
      cases: bench.cases,
    };
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
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

try {
  await main();
} catch (error) {
  process.stderr.write(`[memory_hybrid_quality_bench] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
}
