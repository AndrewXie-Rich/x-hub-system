#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');

function safeString(value) {
  return String(value ?? '').trim();
}

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseBool(value, fallback = false) {
  if (value == null) return fallback;
  const normalized = String(value).trim().toLowerCase();
  if (!normalized) return fallback;
  if (['1', 'true', 'yes', 'y', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(normalized)) return false;
  return fallback;
}

function parseArgs(argv) {
  const out = {
    runs: 10,
    specs: [{ provider: 'openai', modelId: 'gpt-4o' }],
    timeoutMs: 30000,
    intervalMs: 0,
    pollMs: 50,
    reportLimit: 20,
    minCompareReports: 10,
    maxMismatches: 0,
    continueAfterReady: false,
    expectReady: false,
    expectZeroMismatch: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--runs':
        out.runs = parseIntInRange(next, out.runs, 1, 10000);
        i += 1;
        break;
      case '--model-id':
        out.specs = [{ provider: out.specs[0]?.provider || 'openai', modelId: safeString(next) }];
        i += 1;
        break;
      case '--provider':
        out.specs = [{ provider: safeString(next), modelId: out.specs[0]?.modelId || 'gpt-4o' }];
        i += 1;
        break;
      case '--models':
        out.specs = parseModelSpecs(next);
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
      case '--poll-ms':
        out.pollMs = parseIntInRange(next, out.pollMs, 10, 5000);
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
      case '--continue-after-ready':
        out.continueAfterReady = true;
        break;
      case '--expect-ready':
        out.expectReady = true;
        break;
      case '--expect-zero-mismatch':
        out.expectZeroMismatch = true;
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
  if (out.specs.length === 0) {
    throw new Error('at least one model spec is required');
  }
  return out;
}

function parseModelSpecs(raw) {
  return String(raw || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
    .map((item) => {
      const separator = item.indexOf(':');
      if (separator <= 0) {
        return { provider: 'openai', modelId: item };
      }
      return {
        provider: safeString(item.slice(0, separator)),
        modelId: safeString(item.slice(separator + 1)),
      };
    })
    .filter((item) => item.modelId);
}

function usage() {
  return [
    'provider_route_shadow_compare_runner.js',
    '',
    'Options:',
    '  --runs <n>                  Compare iterations, default 10',
    '  --model-id <id>             Single model ID, default gpt-4o',
    '  --provider <id>             Single provider override, default openai',
    '  --models <p:m,p:m>          Model matrix, example openai:gpt-4o,claude:claude-3.5-sonnet',
    '  --min-compare-reports <n>   Readiness minimum reports, default 10',
    '  --max-mismatches <n>        Readiness mismatch threshold, default 0',
    '  --expect-ready              Exit non-zero unless readiness is true',
    '  --expect-zero-mismatch      Exit non-zero if newly added reports mismatch',
    '  --continue-after-ready      Keep running after readiness is reached',
    '  --dry-run                   Print resolved config',
    '  --self-test                 Run parser self-test',
  ].join('\n');
}

function runSelfTest() {
  const parsed = parseArgs([
    '--runs', '3',
    '--models', 'openai:gpt-4o,claude:claude-3.5-sonnet',
    '--expect-ready',
  ]);
  if (parsed.runs !== 3 || parsed.specs.length !== 2 || parsed.expectReady !== true) {
    throw new Error('self-test parser failed');
  }
}

function makeTempDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function cleanupPath(target) {
  try {
    fs.rmSync(target, { recursive: true, force: true });
  } catch {
    // ignore
  }
}

function resolveXHubSystemRoot() {
  const explicit = safeString(process.env.XHUB_SYSTEM_ROOT);
  if (explicit) return explicit;
  const candidates = [
    path.resolve(ROOT_DIR, '..', '..', 'x-hub-system'),
    path.resolve(ROOT_DIR, '..', '..', '..', '..', 'x-hub-system'),
    '/Users/andrew.xie/Documents/AX/x-hub-system',
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src', 'services.js'))) {
      return candidate;
    }
  }
  return candidates[0];
}

function resolveNodeHubSourceDir(sourceRoot = resolveXHubSystemRoot()) {
  const explicit = safeString(process.env.XHUB_NODE_HUB_SRC_DIR || process.env.XHUB_HUB_GRPC_SERVER_SRC_DIR);
  const candidates = [
    explicit,
    path.join(sourceRoot, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src'),
    path.join(sourceRoot, 'hub_grpc_server', 'src'),
    path.resolve(ROOT_DIR, '..', 'hub_grpc_server', 'src'),
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, 'services.js'))) return candidate;
  }
  return candidates[0];
}

async function importFromSource(srcDir, fileName) {
  return await import(pathToFileURL(path.join(srcDir, fileName)).href);
}

function makeTransportCall(request = {}, token = '') {
  return {
    request,
    metadata: {
      get(key) {
        if (String(key || '').toLowerCase() !== 'authorization') return [];
        return token ? [`Bearer ${token}`] : [];
      },
    },
    getPeer() {
      return 'ipv4:127.0.0.1:54321';
    },
  };
}

async function invokeUnary(method, call) {
  return await new Promise((resolve) => {
    method(call, (err, res) => resolve({ err, res }));
  });
}

function withEnv(tempEnv, fn) {
  const previous = new Map();
  const restore = () => {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  };
  for (const [key, value] of Object.entries(tempEnv)) {
    previous.set(key, process.env[key]);
    if (value == null) delete process.env[key];
    else process.env[key] = String(value);
  }
  try {
    const result = fn();
    if (result && typeof result.then === 'function') {
      return result.finally(restore);
    }
    restore();
    return result;
  } catch (error) {
    restore();
    throw error;
  }
}

function parseJsonLine(stdout) {
  const line = String(stdout || '')
    .split(/\r?\n/)
    .map((item) => item.trim())
    .filter(Boolean)
    .reverse()
    .find((item) => item.startsWith('{'));
  if (!line) throw new Error('missing JSON output');
  return JSON.parse(line);
}

function readRunnerJson(runnerPath, args, env, timeoutMs) {
  return parseJsonLine(execFileSync(runnerPath, args, {
    encoding: 'utf8',
    env,
    timeout: timeoutMs,
  }));
}

function readReports(runnerPath, env, reportLimit, timeoutMs) {
  return readRunnerJson(runnerPath, ['provider', 'reports', '--limit', String(reportLimit)], env, timeoutMs);
}

function readReadiness(runnerPath, env, config) {
  return readRunnerJson(runnerPath, [
    'provider',
    'readiness',
    '--min-compare-reports',
    String(config.minCompareReports),
    '--max-mismatches',
    String(config.maxMismatches),
    '--limit',
    String(config.reportLimit),
  ], env, config.timeoutMs);
}

function diffReports(before, after) {
  return {
    total: Math.max(0, Number(after?.total || 0) - Number(before?.total || 0)),
    matched: Math.max(0, Number(after?.matched || 0) - Number(before?.matched || 0)),
    mismatched: Math.max(0, Number(after?.mismatched || 0) - Number(before?.mismatched || 0)),
  };
}

function publicConfig(config) {
  return {
    runs: config.runs,
    specs: config.specs,
    timeout_ms: config.timeoutMs,
    interval_ms: config.intervalMs,
    report_limit: config.reportLimit,
    min_compare_reports: config.minCompareReports,
    max_mismatches: config.maxMismatches,
    expect_ready: config.expectReady,
    expect_zero_mismatch: config.expectZeroMismatch,
    rust_hub_root: ROOT_DIR,
  };
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    console.log(usage());
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    console.log('provider_route_shadow_compare_runner self-test ok');
    return;
  }
  if (config.dryRun) {
    console.log(JSON.stringify({
      ok: true,
      schema_version: 'xhub.provider_route_shadow_compare_runner.dry_run.v1',
      config: publicConfig(config),
    }, null, 2));
    return;
  }

  const sourceRoot = resolveXHubSystemRoot();
  const srcDir = resolveNodeHubSourceDir(sourceRoot);
  if (!fs.existsSync(path.join(srcDir, 'services.js'))) {
    throw new Error(`Node Hub source not found: ${srcDir}`);
  }

  const [
    { HubDB },
    { HubEventBus },
    { makeServices },
    { addProviderKey, invalidateProviderKeyCache },
    { createProviderRouteShadowComparer },
    { createProviderRouteAuthorityBridge },
  ] = await Promise.all([
    importFromSource(srcDir, 'db.js'),
    importFromSource(srcDir, 'event_bus.js'),
    importFromSource(srcDir, 'services.js'),
    importFromSource(srcDir, 'provider_key_store.js'),
    importFromSource(srcDir, 'rust_provider_route_shadow_compare.js'),
    importFromSource(srcDir, 'rust_provider_route_authority_bridge.js'),
  ]);

  const runtimeBaseDir = makeTempDir('xhub-provider-route-runner-runtime-');
  const dbDir = makeTempDir('xhub-provider-route-runner-db-');
  const nodeDbPath = path.join(dbDir, 'node_hub.sqlite3');
  const rustDbPath = path.join(dbDir, 'rust_hub.sqlite3');
  const runnerPath = path.join(ROOT_DIR, 'tools', 'run_rust_hub.command');
  const runnerEnv = {
    ...process.env,
    HUB_DB_PATH: rustDbPath,
    XHUB_RUST_HUB_ROOT: ROOT_DIR,
  };
  const logs = [];
  const warnings = [];
  const compareAttempts = [];

  invalidateProviderKeyCache();

  try {
    await withEnv({
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      HUB_CLIENT_TOKEN: 'client-secret',
      HUB_GRPC_TLS_MODE: '',
      HUB_GRPC_CERT: '',
      HUB_GRPC_KEY: '',
      HUB_GRPC_CA: '',
      HUB_DB_PATH: rustDbPath,
      XHUB_RUST_HUB_ROOT: ROOT_DIR,
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE: '1',
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_VERBOSE: '1',
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_THROTTLE_MS: '0',
    }, async () => {
      const db = new HubDB({ dbPath: nodeDbPath });
      try {
        for (const [index, spec] of config.specs.entries()) {
          const addResult = addProviderKey(runtimeBaseDir, {
            provider: spec.provider,
            api_key: `sk-provider-route-runner-${index + 1}`,
            auth_type: 'api_key',
            models: [spec.modelId],
            priority: 10 - index,
          });
          if (!addResult.ok) {
            throw new Error(`addProviderKey failed for ${spec.provider}:${spec.modelId}: ${addResult.error || 'unknown_error'}`);
          }
          spec.accountKey = addResult.account_key;
        }

        const comparer = createProviderRouteShadowComparer({
          logger: {
            log: (line) => logs.push(String(line || '')),
            warn: (line) => warnings.push(String(line || '')),
          },
        });
        const impl = makeServices({
          db,
          bus: new HubEventBus(),
          providerRouteShadowComparer: {
            maybeCompare(input) {
              const started = comparer.maybeCompare(input);
              compareAttempts.push({
                started,
                provider: safeString(input?.provider || input?.nodeDecision?.requested_provider),
                model_id: safeString(input?.modelId || input?.nodeDecision?.requested_model_id),
                at_ms: Date.now(),
              });
              return started;
            },
          },
        });

        const reportsBefore = readReports(runnerPath, runnerEnv, config.reportLimit, config.timeoutMs);
        let latestReports = reportsBefore;
        let latestReadiness = readReadiness(runnerPath, runnerEnv, config);
        const iterations = [];

        console.log(JSON.stringify({
          event: 'start',
          schema_version: 'xhub.provider_route_shadow_compare_runner.event.v1',
          config: publicConfig(config),
          reports_before: reportsBefore,
          readiness_before: latestReadiness,
        }));

        for (let index = 0; index < config.runs; index += 1) {
          const spec = config.specs[index % config.specs.length];
          const previousTotal = Number(latestReports?.total || 0);
          const beforeLogCount = logs.length;
          const beforeWarningCount = warnings.length;
          const selectedAccountKey = await invokeRouteUntilCompareStarted({
            impl,
            spec,
            compareAttempts,
            timeoutMs: config.timeoutMs,
            pollMs: config.pollMs,
          });
          await waitForCompareCompletion({
            logs,
            warnings,
            beforeLogCount,
            beforeWarningCount,
            timeoutMs: config.timeoutMs,
            pollMs: config.pollMs,
          });
          latestReports = readReports(runnerPath, runnerEnv, config.reportLimit, config.timeoutMs);
          if (Number(latestReports?.total || 0) <= previousTotal) {
            throw new Error(`provider route report total did not increase after compare completion`);
          }
          latestReadiness = readReadiness(runnerPath, runnerEnv, config);
          const item = {
            run_index: index + 1,
            provider: spec.provider,
            model_id: spec.modelId,
            selected_account_key: selectedAccountKey,
            report_total: Number(latestReports?.total || 0),
            report_mismatched: Number(latestReports?.mismatched || 0),
            readiness_ready: latestReadiness?.ready === true,
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
        let authorityPrep = null;
        if (latestReadiness?.ready === true) {
          const spec = config.specs[0];
          const authorityPrepWarnings = [];
          const authorityBridge = createProviderRouteAuthorityBridge({
            env: {
              ...process.env,
              XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: '1',
              XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '1',
              XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS: String(config.minCompareReports),
              XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MAX_MISMATCHES: String(config.maxMismatches),
              XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REPORT_LIMIT: String(config.reportLimit),
              XHUB_RUST_HUB_ROOT: ROOT_DIR,
              HUB_DB_PATH: rustDbPath,
            },
            logger: {
              log: (line) => logs.push(String(line || '')),
              warn: (line) => authorityPrepWarnings.push(String(line || '')),
            },
          });
          const routed = await authorityBridge.route({
            runtimeBaseDir,
            modelId: spec.modelId,
            provider: spec.provider,
            nodeAccountKey: spec.accountKey,
          });
          const mismatchProbe = await authorityBridge.route({
            runtimeBaseDir,
            modelId: spec.modelId,
            provider: spec.provider,
            nodeAccountKey: `${spec.accountKey}:mismatch`,
          });
          authorityPrep = {
            ok: routed.ok === true,
            used: routed.used === true,
            fallback: routed.fallback === true,
            selected: routed.selected === true,
            selected_account_key: safeString(routed.selectedAccountKey),
            node_match_required: true,
            error_code: safeString(routed.error_code),
            mismatch_probe: {
              ok: mismatchProbe.ok === true,
              used: mismatchProbe.used === true,
              fallback: mismatchProbe.fallback === true,
              mismatch: mismatchProbe.mismatch === true,
              selected: mismatchProbe.selected === true,
              selected_account_key: safeString(mismatchProbe.selectedAccountKey),
              error_code: safeString(mismatchProbe.error_code),
              warnings: authorityPrepWarnings,
            },
          };
          if (authorityPrep.selected_account_key !== spec.accountKey) {
            throw new Error(
              `authority prep selected unexpected account for ${spec.modelId}: ${authorityPrep.selected_account_key}`
            );
          }
          if (
            authorityPrep.mismatch_probe.fallback !== true
            || authorityPrep.mismatch_probe.mismatch !== true
            || authorityPrep.mismatch_probe.error_code !== 'rust_provider_route_authority_account_mismatch'
          ) {
            throw new Error(
              `authority prep mismatch gate did not fallback for ${spec.modelId}: ${JSON.stringify(authorityPrep.mismatch_probe)}`
            );
          }
          const serviceHook = await verifyAuthorityPrepServiceHook({
            makeServices,
            HubEventBus,
            db,
            spec,
            runtimeBaseDir,
            authorityBridge,
            timeoutMs: config.timeoutMs,
            pollMs: config.pollMs,
          });
          authorityPrep.service_hook = serviceHook;
        }
        const ok = (!config.expectReady || latestReadiness?.ready === true)
          && (!config.expectZeroMismatch || reportsAdded.mismatched === 0)
          && warnings.length === 0;
        const finalPayload = {
          event: 'stop',
          ok,
          schema_version: 'xhub.provider_route_shadow_compare_runner.result.v1',
          reports_added: reportsAdded,
          reports_after: latestReports,
          readiness_after: latestReadiness,
          authority_prep: authorityPrep,
          iterations,
          warnings,
          runtime_base_dir: runtimeBaseDir,
          rust_db_path: rustDbPath,
        };
        console.log(JSON.stringify(finalPayload, null, 2));
        if (!ok) process.exitCode = 2;
      } finally {
        db.close();
      }
    });
  } finally {
    cleanupPath(runtimeBaseDir);
    cleanupPath(dbDir);
  }
}

async function invokeRouteUntilCompareStarted({
  impl,
  spec,
  compareAttempts,
  timeoutMs,
  pollMs,
}) {
  const deadline = Date.now() + timeoutMs;
  let lastSelectedAccountKey = '';
  while (Date.now() < deadline) {
    const beforeAttempts = compareAttempts.length;
    const response = await invokeUnary(
      impl.HubProviderKeys.GetProviderKeyRouteDecision,
      makeTransportCall({
        model_id: spec.modelId,
        provider: spec.provider,
      }, 'client-secret')
    );
    if (response.err) {
      throw response.err;
    }
    lastSelectedAccountKey = safeString(response.res?.decision?.selected_account_key);
    if (lastSelectedAccountKey !== spec.accountKey) {
      throw new Error(`unexpected selected account for ${spec.modelId}: ${lastSelectedAccountKey}`);
    }
    const newAttempts = compareAttempts.slice(beforeAttempts);
    if (newAttempts.some((attempt) => attempt.started === true)) {
      return lastSelectedAccountKey;
    }
    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }
  throw new Error(`provider route shadow compare did not start within ${timeoutMs}ms for ${spec.modelId}`);
}

async function waitForCompareCompletion({
  logs,
  warnings,
  beforeLogCount,
  beforeWarningCount,
  timeoutMs,
  pollMs,
}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (logs.length > beforeLogCount || warnings.length > beforeWarningCount) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }
  throw new Error(`provider route shadow compare did not complete within ${timeoutMs}ms`);
}

async function verifyAuthorityPrepServiceHook({
  makeServices,
  HubEventBus,
  db,
  spec,
  runtimeBaseDir,
  authorityBridge,
  timeoutMs,
  pollMs,
}) {
  const servicePrep = {
    started: 0,
    completed: 0,
    failed: 0,
    node_account_key: '',
    selected_account_key: '',
    fallback: false,
    selected: false,
    error_code: '',
  };
  const serviceImpl = makeServices({
    db,
    bus: new HubEventBus(),
    providerRouteShadowComparer: {
      maybeCompare() {
        return false;
      },
    },
    providerRouteAuthorityBridge: {
      config: { prepEnabled: true },
      prepRoute(input) {
        servicePrep.started += 1;
        servicePrep.node_account_key = safeString(input?.nodeAccountKey || input?.node_account_key);
        authorityBridge.route(input)
          .then((out) => {
            servicePrep.completed += 1;
            servicePrep.selected = out?.selected === true;
            servicePrep.fallback = out?.fallback === true;
            servicePrep.selected_account_key = safeString(out?.selectedAccountKey);
            servicePrep.error_code = safeString(out?.error_code);
            return out;
          })
          .catch((error) => {
            servicePrep.completed += 1;
            servicePrep.failed += 1;
            servicePrep.error_code = safeString(error?.message || error);
          });
        return true;
      },
    },
  });

  const response = await invokeUnary(
    serviceImpl.HubProviderKeys.GetProviderKeyRouteDecision,
    makeTransportCall({
      model_id: spec.modelId,
      provider: spec.provider,
    }, 'client-secret')
  );
  if (response.err) {
    throw response.err;
  }
  const responseSelected = safeString(response.res?.decision?.selected_account_key);
  if (responseSelected !== spec.accountKey) {
    throw new Error(`authority prep service hook changed Node response for ${spec.modelId}: ${responseSelected}`);
  }

  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (servicePrep.completed >= 1) break;
    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }
  if (servicePrep.completed < 1) {
    throw new Error(`authority prep service hook did not complete within ${timeoutMs}ms for ${spec.modelId}`);
  }
  if (
    servicePrep.failed > 0
    || servicePrep.selected !== true
    || servicePrep.fallback === true
    || servicePrep.selected_account_key !== spec.accountKey
    || servicePrep.node_account_key !== spec.accountKey
  ) {
    throw new Error(`authority prep service hook failed: ${JSON.stringify(servicePrep)}`);
  }
  return {
    started: servicePrep.started,
    completed: servicePrep.completed,
    failed: servicePrep.failed,
    response_preserved: responseSelected === spec.accountKey,
    response_selected_account_key: responseSelected,
    node_account_key: servicePrep.node_account_key,
    selected: servicePrep.selected,
    fallback: servicePrep.fallback,
    selected_account_key: servicePrep.selected_account_key,
    error_code: servicePrep.error_code,
  };
}

main().catch((error) => {
  console.error(`[provider_route_shadow_compare_runner] ${error?.stack || error?.message || error}`);
  process.exit(1);
});
