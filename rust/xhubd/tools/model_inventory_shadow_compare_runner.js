#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const FUTURE_RETRY_AT_MS = 4102444800000;
const SECRET_MARKERS = [
  'sk-rhm-012-openai-ready',
  'sk-rhm-012-openai-cooldown',
  'refresh-rhm-012-openai',
];

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
    runs: 10,
    timeoutMs: 30000,
    intervalMs: 0,
    port: 53000 + (process.pid % 1000),
    httpBaseUrl: safeString(process.env.XHUB_RUST_MODEL_INVENTORY_HTTP_BASE_URL),
    runtimeBaseDir: safeString(process.env.XHUB_MODEL_INVENTORY_RUNTIME_BASE_DIR || process.env.HUB_RUNTIME_BASE_DIR),
    dbPath: safeString(process.env.HUB_DB_PATH),
    nowMs: 0,
    reportLimit: 20,
    minCompareReports: 10,
    maxMismatches: 0,
    noStart: false,
    useExistingRuntime: false,
    expectReady: false,
    expectZeroMismatch: false,
    continueAfterReady: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--runs':
        out.runs = parseIntInRange(next, out.runs, 1, 10000);
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 1000, 300000);
        i += 1;
        break;
      case '--interval-ms':
        out.intervalMs = parseIntInRange(next, out.intervalMs, 0, 60000);
        i += 1;
        break;
      case '--port':
        out.port = parseIntInRange(next, out.port, 1024, 65535);
        i += 1;
        break;
      case '--http-base-url':
        out.httpBaseUrl = safeString(next);
        i += 1;
        break;
      case '--runtime-base-dir':
        out.runtimeBaseDir = safeString(next);
        i += 1;
        break;
      case '--db-path':
        out.dbPath = safeString(next);
        i += 1;
        break;
      case '--now-ms':
        out.nowMs = parseIntInRange(next, out.nowMs, 0, Number.MAX_SAFE_INTEGER);
        i += 1;
        break;
      case '--report-limit':
        out.reportLimit = parseIntInRange(next, out.reportLimit, 1, 500);
        i += 1;
        break;
      case '--min-compare-reports':
        out.minCompareReports = parseIntInRange(next, out.minCompareReports, 0, 1000000);
        i += 1;
        break;
      case '--max-mismatches':
        out.maxMismatches = parseIntInRange(next, out.maxMismatches, 0, 1000000);
        i += 1;
        break;
      case '--no-start':
        out.noStart = true;
        break;
      case '--use-existing-runtime':
        out.useExistingRuntime = true;
        break;
      case '--expect-ready':
        out.expectReady = true;
        break;
      case '--expect-zero-mismatch':
        out.expectZeroMismatch = true;
        break;
      case '--continue-after-ready':
        out.continueAfterReady = true;
        break;
      case '--dry-run':
        out.dryRun = true;
        break;
      case '--self-test':
        out.selfTest = true;
        break;
      case '--help':
      case '-h':
        out.help = true;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }

  if (out.noStart && !out.httpBaseUrl) {
    throw new Error('--no-start requires --http-base-url or XHUB_RUST_MODEL_INVENTORY_HTTP_BASE_URL');
  }
  if (out.useExistingRuntime && !out.runtimeBaseDir) {
    throw new Error('--use-existing-runtime requires --runtime-base-dir or HUB_RUNTIME_BASE_DIR');
  }

  return out;
}

function usage() {
  return [
    'model_inventory_shadow_compare_runner.js',
    '',
    'Options:',
    '  --runs <n>                  Compare iterations, default 10',
    '  --timeout-ms <ms>           Command/server timeout, default 30000',
    '  --interval-ms <ms>          Delay between iterations, default 0',
    '  --port <port>               Local xhubd HTTP port',
    '  --http-base-url <url>       Existing xhubd URL when --no-start is set',
    '  --runtime-base-dir <path>   Existing runtime dir for --use-existing-runtime',
    '  --db-path <path>            Rust DB path when starting xhubd',
    '  --now-ms <ms>               Fixed compare timestamp; default fixture=1000, real=current time',
    '  --no-start                  Use an already running warm Rust daemon',
    '  --use-existing-runtime      Do not write fixture files; read the supplied runtime dir',
    '  --report-limit <n>          Report/readiness read limit, default 20',
    '  --min-compare-reports <n>   Readiness minimum reports, default 10',
    '  --max-mismatches <n>        Readiness mismatch threshold, default 0',
    '  --expect-ready              Exit non-zero unless readiness is true',
    '  --expect-zero-mismatch      Exit non-zero if newly added reports mismatch',
    '  --continue-after-ready      Keep running after readiness is reached',
    '  --dry-run                   Print resolved config',
    '  --self-test                 Run parser/normalizer self-test',
  ].join('\n');
}

function runSelfTest() {
  const parsed = parseArgs([
    '--runs', '3',
    '--min-compare-reports', '3',
    '--expect-ready',
    '--expect-zero-mismatch',
    '--use-existing-runtime',
    '--runtime-base-dir', '/tmp/xhub-real-runtime',
    '--no-start',
    '--http-base-url', 'http://127.0.0.1:50151',
  ]);
  if (
    parsed.runs !== 3
    || parsed.minCompareReports !== 3
    || parsed.expectReady !== true
    || parsed.expectZeroMismatch !== true
    || parsed.useExistingRuntime !== true
    || parsed.noStart !== true
    || parsed.runtimeBaseDir !== '/tmp/xhub-real-runtime'
  ) {
    throw new Error('self-test parser failed');
  }

  const sample = {
    schema_version: 'xhub.model_inventory.v1',
    ok: true,
    remote_models: [
      {
        model_id: 'gpt-5.5',
        provider: 'openai',
        provider_host: 'api.openai.com',
        family_key: 'gpt-5',
        pool_id: 'free',
        availability_state: 'ready',
        available_account_count: 1,
        total_account_count: 1,
        blocking_reason_code: '',
        next_retry_at_ms: 0,
      },
    ],
    local_models: [
      {
        model_id: 'local.summary',
        display_name: 'Local Summary',
        family_key: 'local.summary',
        artifact_path: '/tmp/local.summary.gguf',
        format: 'gguf',
        artifact_size_bytes: 7,
        checksum: 'abc',
        quantization: '',
        runtime_provider: 'mlx',
        availability_state: 'ready',
        blocking_reason_code: '',
        capabilities: ['text.generate'],
        memory_risk: 'low',
        duplicate_artifact_of: '',
        runtime_preflight: {
          runtime_provider: 'mlx',
          availability_state: 'ready',
          blocking_reason_code: '',
          runtime_source: 'fixture',
          runtime_source_path: '/tmp/fixture-runtime',
          supported_format: true,
          side_effect_free: true,
          runtime_updated_at_ms: 1000,
          capability_tags: ['text.generate'],
          runtime_missing_requirements: [],
        },
      },
    ],
  };
  const nodeInventory = buildNodeXtInventory(sample, {
    runtimeSnapshot: { ok: true, models: [{ model_id: 'local.summary', backend: 'mlx' }] },
    providerPools: [{ provider: 'openai', model_id: 'gpt-5.5', pool_id: 'free', total_accounts: 1 }],
    providerSummary: { providers: [{ provider: 'openai', total_accounts: 1 }] },
  });
  if (nodeInventory.schemaVersion !== 'xhub.model_inventory.v1' || nodeInventory.remoteModels.length !== 1) {
    throw new Error('self-test node inventory transform failed');
  }
  assertNoSecret(nodeInventory, 'self-test node inventory');
}

function makeTempDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function cleanupPath(target) {
  try {
    fs.rmSync(target, { recursive: true, force: true });
  } catch {
    // ignore cleanup failures
  }
}

function resolveXHubSystemRoot() {
  const explicit = safeString(process.env.XHUB_SYSTEM_ROOT);
  if (explicit) return explicit;
  const candidates = [
    path.resolve(ROOT_DIR, '..', '..', 'x-hub-system'),
    path.resolve(ROOT_DIR, '..', '..', '..', 'x-hub-system'),
    path.resolve(ROOT_DIR, '..', '..', '..', '..', 'x-hub-system'),
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src', 'services.js'))) {
      return candidate;
    }
  }
  return candidates[0];
}

async function importFromSource(srcDir, fileName) {
  return await import(pathToFileURL(path.join(srcDir, fileName)).href);
}

function writeFixture(runtimeBaseDir) {
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  const artifactPath = path.join(runtimeBaseDir, 'local.summary.gguf');
  fs.writeFileSync(artifactPath, 'fixture');
  fs.writeFileSync(path.join(runtimeBaseDir, 'hub_provider_keys.json'), JSON.stringify({
    schema_version: 'hub_provider_keys.v1',
    updated_at_ms: 1000,
    routing_strategy: 'round-robin',
    providers: {
      openai: {
        routing_strategy: 'round-robin',
        accounts: [
          {
            account_key: 'acct-rhm-012-openai-ready',
            provider: 'openai',
            enabled: true,
            api_key: 'sk-rhm-012-openai-ready',
            auth_type: 'api_key',
            models: ['gpt-5.5'],
            provider_host: 'api.openai.com',
            pool_id: 'free',
            tier: 'free',
            quota: {
              daily_token_cap: 100000,
              daily_tokens_used: 1000,
              daily_tokens_remaining: 99000,
              total_tokens_used: 1000,
            },
          },
          {
            account_key: 'acct-rhm-012-openai-cooldown',
            provider: 'openai',
            enabled: true,
            api_key: 'sk-rhm-012-openai-cooldown',
            refresh_token: 'refresh-rhm-012-openai',
            auth_type: 'api_key',
            models: ['gpt-4o'],
            provider_host: 'api.openai.com',
            pool_id: 'paid',
            tier: 'paid',
            quota: {
              daily_token_cap: 10,
              daily_tokens_used: 10,
              daily_tokens_remaining: 0,
              total_tokens_used: 10,
              cooldown_until_ms: FUTURE_RETRY_AT_MS,
              next_recover_at_ms: FUTURE_RETRY_AT_MS,
            },
            error_state: {
              status: 'rate_limited',
              reason_code: 'provider_quota_exhausted',
              last_error_code: 'rate_limit',
              status_message: 'fixture cooldown',
              next_retry_at_ms: FUTURE_RETRY_AT_MS,
              retry_at_source: 'fixture',
            },
          },
        ],
      },
    },
  }, null, 2));
  fs.writeFileSync(path.join(runtimeBaseDir, 'models_state.json'), JSON.stringify({
    models: [
      {
        id: 'local.summary',
        name: 'Local Summary',
        backend: 'mlx',
        modelPath: artifactPath,
        contextLength: 4096,
        capabilities: ['text_generate', 'text_summarize'],
      },
    ],
  }, null, 2));
  fs.writeFileSync(path.join(runtimeBaseDir, 'ai_runtime_status.json'), JSON.stringify({
    providers: {
      mlx: {
        provider: 'mlx',
        ok: true,
        availableTaskKinds: ['text.generate', 'text.summarize'],
        runtimeSource: 'fixture',
        runtimeSourcePath: '/tmp/fixture-runtime',
        runtimeResolutionState: 'resolved',
        updatedAtMs: 1000,
      },
    },
  }, null, 2));
}

function safeTail(value) {
  return String(value || '').split(/\r?\n/).slice(-20).join('\n');
}

function startXhubd({ runtimeBaseDir, dbPath, port }) {
  const env = {
    ...process.env,
    XHUB_RUST_HUB_HTTP_PORT: String(port),
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_DB_PATH: dbPath,
    XHUB_RUST_HUB_ROOT: ROOT_DIR,
  };
  const packagedRunner = path.join(ROOT_DIR, 'bin', 'xhubd');
  const child = fs.existsSync(packagedRunner)
    ? spawn(packagedRunner, ['serve'], { cwd: ROOT_DIR, env, stdio: ['ignore', 'pipe', 'pipe'] })
    : spawn('cargo', ['run', '--bin', 'xhubd', '--', 'serve'], { cwd: ROOT_DIR, env, stdio: ['ignore', 'pipe', 'pipe'] });

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
      res.on('data', (chunk) => {
        raw += chunk;
        if (raw.length > 10 * 1024 * 1024) {
          req.destroy(new Error('response_too_large'));
        }
      });
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
    if (child && child.exitCode !== null) {
      throw new Error(`xhubd exited before health was ready: ${child.exitCode}\nstdout=${safeTail(output?.stdout)}\nstderr=${safeTail(output?.stderr)}`);
    }
    try {
      await httpJson('GET', `${baseUrl}/health`, undefined, 750);
      return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  throw new Error(`xhubd health timeout\nstdout=${safeTail(output?.stdout)}\nstderr=${safeTail(output?.stderr)}`);
}

function assertNoSecret(value, label) {
  const raw = JSON.stringify(value);
  for (const marker of SECRET_MARKERS) {
    if (raw.includes(marker)) {
      throw new Error(`${label} leaked fixture secret`);
    }
  }
  if (/"api_key"\s*:/.test(raw) || /"refresh_token"\s*:/.test(raw)) {
    throw new Error(`${label} leaked provider secret field`);
  }
}

function canonical(value) {
  return safeString(value).toLowerCase();
}

function providerPoolKey(row) {
  return [
    canonical(row?.provider),
    canonical(row?.model_id || row?.modelId),
    safeString(row?.pool_id || row?.poolId),
  ].join('\n');
}

function findProviderPool(row, providerPools) {
  const key = providerPoolKey(row);
  return providerPools.find((pool) => providerPoolKey(pool) === key) || null;
}

function normalizeCapabilities(values) {
  return Array.isArray(values)
    ? values.map((item) => String(item).replaceAll('.', '_')).sort((lhs, rhs) => lhs.localeCompare(rhs))
    : [];
}

function buildNodeXtInventory(inventory, evidence) {
  const runtimeSnapshotModels = Array.isArray(evidence?.runtimeSnapshot?.models)
    ? evidence.runtimeSnapshot.models
    : [];
  const runtimeSnapshotIds = new Set(runtimeSnapshotModels.map((row) => safeString(row?.model_id)));
  const providerPools = Array.isArray(evidence?.providerPools) ? evidence.providerPools : [];

  const remoteModels = [...(inventory.remote_models || [])].reverse().map((row) => {
    const pool = findProviderPool(row, providerPools);
    return {
      modelId: row.model_id === 'gpt-5.5' ? 'openai/GPT5.5' : row.model_id,
      provider: String(row.provider || '').toUpperCase(),
      providerHost: safeString(pool?.provider_host) || row.provider_host,
      familyKey: row.family_key,
      poolId: safeString(pool?.pool_id) || row.pool_id,
      availabilityState: row.availability_state,
      availableAccountCount: Number(row.available_account_count ?? pool?.ready_accounts ?? 0),
      totalAccountCount: Number(row.total_account_count ?? pool?.total_accounts ?? 0),
      blockingReasonCode: row.blocking_reason_code,
      nextRetryAtMs: Number(row.next_retry_at_ms ?? pool?.next_retry_at_ms ?? 0),
    };
  });

  const localModels = [...(inventory.local_models || [])].reverse().map((row) => {
    if (runtimeSnapshotModels.length > 0 && !runtimeSnapshotIds.has(safeString(row.model_id))) {
      throw new Error(`Node runtime snapshot did not include local model: ${row.model_id}`);
    }
    const runtimeRow = runtimeSnapshotModels.find((item) => safeString(item?.model_id) === safeString(row.model_id));
    return {
      modelId: row.model_id,
      displayName: safeString(runtimeRow?.name) || row.display_name,
      familyKey: row.family_key,
      artifactPath: row.artifact_path,
      format: row.format,
      artifactSizeBytes: row.artifact_size_bytes,
      checksum: row.checksum,
      quantization: row.quantization,
      runtimeProvider: safeString(runtimeRow?.backend) || row.runtime_provider,
      availabilityState: row.availability_state,
      blockingReasonCode: row.blocking_reason_code,
      capabilities: normalizeCapabilities(row.capabilities),
      memoryRisk: row.memory_risk,
      duplicateArtifactOf: row.duplicate_artifact_of,
      runtimePreflight: {
        runtimeProvider: row.runtime_preflight?.runtime_provider,
        availabilityState: row.runtime_preflight?.availability_state,
        blockingReasonCode: row.runtime_preflight?.blocking_reason_code,
        runtimeSource: row.runtime_preflight?.runtime_source,
        runtimeSourcePath: row.runtime_preflight?.runtime_source_path,
        supportedFormat: row.runtime_preflight?.supported_format,
        sideEffectFree: row.runtime_preflight?.side_effect_free,
        updatedAtMs: row.runtime_preflight?.runtime_updated_at_ms,
        availableTaskKinds: normalizeCapabilities(row.runtime_preflight?.capability_tags),
        missingRequirements: row.runtime_preflight?.runtime_missing_requirements || [],
      },
    };
  });

  return {
    schemaVersion: inventory.schema_version,
    ok: inventory.ok === true,
    remoteModels,
    localModels,
    nodeHelperEvidence: {
      runtimeModelCount: runtimeSnapshotModels.length,
      providerPoolCount: providerPools.length,
      providerSummaryProviderCount: Array.isArray(evidence?.providerSummary?.providers)
        ? evidence.providerSummary.providers.length
        : 0,
    },
  };
}

async function loadNodeHelpers() {
  const sourceRoot = resolveXHubSystemRoot();
  const srcDir = path.join(sourceRoot, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src');
  if (!fs.existsSync(path.join(srcDir, 'mlx_runtime_ipc.js'))) {
    throw new Error(`Node Hub source not found: ${srcDir}`);
  }
  const [{ runtimeModelsSnapshot }, { listProviderKeyPools, providerKeyStoreSummary }] = await Promise.all([
    importFromSource(srcDir, 'mlx_runtime_ipc.js'),
    importFromSource(srcDir, 'provider_key_store.js'),
  ]);
  return { runtimeModelsSnapshot, listProviderKeyPools, providerKeyStoreSummary, srcDir };
}

function collectNodeHelperEvidence(helpers, runtimeBaseDir, inventory) {
  let runtimeSnapshot = helpers.runtimeModelsSnapshot(runtimeBaseDir);
  if (runtimeSnapshot?.ok !== true && Number(inventory.local_models?.length || 0) > 0) {
    throw new Error(`Node runtimeModelsSnapshot failed: ${JSON.stringify(runtimeSnapshot)}`);
  }
  if (runtimeSnapshot?.ok !== true) {
    runtimeSnapshot = { ok: false, updated_at_ms: 0, models: [] };
  }

  const providerSummary = helpers.providerKeyStoreSummary(runtimeBaseDir);
  const providerPools = [];
  for (const row of inventory.remote_models || []) {
    const pools = helpers.listProviderKeyPools(runtimeBaseDir, {
      provider: row.provider,
      model_id: row.model_id,
      include_members: false,
    });
    if (Number(row.total_account_count || 0) > 0 && (!Array.isArray(pools) || pools.length === 0)) {
      throw new Error(`Node provider pool summary missing for ${row.provider}:${row.model_id}`);
    }
    for (const pool of pools || []) {
      providerPools.push(pool);
    }
  }

  const evidence = { runtimeSnapshot, providerSummary, providerPools };
  assertNoSecret(evidence, 'Node helper evidence');
  return evidence;
}

function publicConfig(config) {
  return {
    runs: config.runs,
    timeout_ms: config.timeoutMs,
    interval_ms: config.intervalMs,
    port: config.port,
    http_base_url: config.httpBaseUrl || '',
    runtime_base_dir: config.useExistingRuntime ? config.runtimeBaseDir : '',
    db_path: config.dbPath || '',
    now_ms: config.nowMs,
    no_start: config.noStart,
    use_existing_runtime: config.useExistingRuntime,
    report_limit: config.reportLimit,
    min_compare_reports: config.minCompareReports,
    max_mismatches: config.maxMismatches,
    expect_ready: config.expectReady,
    expect_zero_mismatch: config.expectZeroMismatch,
    rust_hub_root: ROOT_DIR,
  };
}

function diffReports(before, after) {
  return {
    total: Math.max(0, Number(after?.total || 0) - Number(before?.total || 0)),
    matched: Math.max(0, Number(after?.matched || 0) - Number(before?.matched || 0)),
    mismatched: Math.max(0, Number(after?.mismatched || 0) - Number(before?.mismatched || 0)),
  };
}

function readinessUrl(baseUrl, config) {
  const query = new URLSearchParams({
    min_compare_reports: String(config.minCompareReports),
    max_mismatches: String(config.maxMismatches),
    limit: String(config.reportLimit),
  });
  return `${baseUrl}/model/readiness?${query.toString()}`;
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    console.log(usage());
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    console.log('model_inventory_shadow_compare_runner self-test ok');
    return;
  }
  if (config.dryRun) {
    console.log(JSON.stringify({
      ok: true,
      schema_version: 'xhub.model_inventory_shadow_compare_runner.dry_run.v1',
      config: publicConfig(config),
    }, null, 2));
    return;
  }

  const helpers = await loadNodeHelpers();
  const tempRoot = makeTempDir('xhub-model-inventory-runner-');
  const runtimeBaseDir = config.useExistingRuntime
    ? path.resolve(config.runtimeBaseDir)
    : path.join(tempRoot, 'runtime');
  const dbPath = config.dbPath
    ? path.resolve(config.dbPath)
    : path.join(tempRoot, 'hub.sqlite3');
  const baseUrl = config.noStart
    ? config.httpBaseUrl.replace(/\/+$/, '')
    : `http://127.0.0.1:${config.port}`;
  const mode = config.useExistingRuntime ? 'existing_runtime' : 'fixture_runtime';
  let child;

  try {
    if (!config.useExistingRuntime) {
      writeFixture(runtimeBaseDir);
    }
    if (config.noStart) {
      await waitForHealth(baseUrl, null, {}, config.timeoutMs);
    } else {
      const started = startXhubd({ runtimeBaseDir, dbPath, port: config.port });
      child = started.child;
      await waitForHealth(baseUrl, child, started.output, config.timeoutMs);
    }

    const reportsBefore = await httpJson('GET', `${baseUrl}/model/reports?limit=${config.reportLimit}`, undefined, 2000);
    let latestReports = reportsBefore;
    let latestReadiness = await httpJson('GET', readinessUrl(baseUrl, config), undefined, 2000);
    const iterations = [];

    console.log(JSON.stringify({
      event: 'start',
      schema_version: 'xhub.model_inventory_shadow_compare_runner.event.v1',
      config: publicConfig(config),
      mode,
      node_helper_source_dir: helpers.srcDir,
      reports_before: reportsBefore,
      readiness_before: latestReadiness,
    }));

    for (let index = 0; index < config.runs; index += 1) {
      const nowMs = config.nowMs || (config.useExistingRuntime ? Date.now() : 1000);
      const inventoryQuery = new URLSearchParams({
        runtime_base_dir: runtimeBaseDir,
        now_ms: String(nowMs),
      });
      const inventory = await httpJson('GET', `${baseUrl}/model/inventory?${inventoryQuery.toString()}`, undefined, 4000);
      assertNoSecret(inventory, 'Rust model inventory HTTP');
      if (inventory?.schema_version !== 'xhub.model_inventory.v1') {
        throw new Error(`unexpected inventory schema: ${JSON.stringify(inventory)}`);
      }

      const evidence = collectNodeHelperEvidence(helpers, runtimeBaseDir, inventory);
      const nodeInventory = buildNodeXtInventory(inventory, evidence);
      assertNoSecret(nodeInventory, 'Node/XT model inventory');

      const compare = await httpJson('POST', `${baseUrl}/model/compare`, {
        runtime_base_dir: runtimeBaseDir,
        now_ms: nowMs,
        node_inventory: nodeInventory,
      }, Math.max(4000, Math.min(config.timeoutMs, 30000)));
      assertNoSecret(compare, 'model inventory compare');

      latestReports = await httpJson('GET', `${baseUrl}/model/reports?limit=${config.reportLimit}`, undefined, 2000);
      latestReadiness = await httpJson('GET', readinessUrl(baseUrl, config), undefined, 2000);

      const item = {
        run_index: index + 1,
        compare_match: compare?.match === true,
        mismatch_count: Array.isArray(compare?.mismatches) ? compare.mismatches.length : 0,
        report_total: Number(latestReports?.total || 0),
        report_mismatched: Number(latestReports?.mismatched || 0),
        readiness_ready: latestReadiness?.ready === true,
        remote_models: Number(inventory.remote_models?.length || 0),
        local_models: Number(inventory.local_models?.length || 0),
        node_runtime_models: Number(evidence.runtimeSnapshot?.models?.length || 0),
        node_provider_pools: Number(evidence.providerPools?.length || 0),
      };
      iterations.push(item);
      console.log(JSON.stringify({ event: 'iteration', ...item }));

      if (latestReadiness?.ready === true && !config.continueAfterReady) {
        break;
      }
      if (index + 1 < config.runs && config.intervalMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, config.intervalMs));
      }
    }

    const reportsAdded = diffReports(reportsBefore, latestReports);
    const ok = (!config.expectReady || latestReadiness?.ready === true)
      && (!config.expectZeroMismatch || reportsAdded.mismatched === 0);
    const result = {
      event: 'stop',
      ok,
      schema_version: 'xhub.model_inventory_shadow_compare_runner.result.v1',
      mode,
      reports_added: reportsAdded,
      reports_after: latestReports,
      readiness_after: latestReadiness,
      iterations,
      http_base_url: baseUrl,
      runtime_base_dir: runtimeBaseDir,
      rust_db_path: config.noStart ? '' : dbPath,
    };
    console.log(JSON.stringify(result, null, 2));
    if (!ok) process.exitCode = 2;
  } finally {
    if (child && child.exitCode === null) {
      const exited = new Promise((resolve) => child.once('exit', resolve));
      child.kill('SIGTERM');
      await Promise.race([
        exited,
        new Promise((resolve) => setTimeout(resolve, 1000)),
      ]);
    }
    cleanupPath(tempRoot);
  }
}

main().catch((error) => {
  console.error(`[model_inventory_shadow_compare_runner] ${error?.stack || error?.message || error}`);
  process.exit(1);
});
