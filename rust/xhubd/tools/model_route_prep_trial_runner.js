#!/usr/bin/env node
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

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

function defaultReportPath() {
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
  return path.join(ROOT_DIR, 'reports', `model_route_prep_trial_${stamp}.json`);
}

function parseArgs(argv) {
  const out = {
    remoteRuns: 1,
    localRuns: 1,
    concurrency: 1,
    remoteModelId: 'gpt-5.5',
    localModelId: 'local.summary',
    provider: 'openai',
    timeoutMs: 45000,
    minRemotePrepMatches: 0,
    minLocalPrepMatches: 0,
    maxPrepWarnings: 0,
    maxGenerateMs: 2000,
    reportPath: '',
    expectReady: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--remote-runs':
        out.remoteRuns = parseIntInRange(next, out.remoteRuns, 1, 10000);
        i += 1;
        break;
      case '--local-runs':
        out.localRuns = parseIntInRange(next, out.localRuns, 1, 10000);
        i += 1;
        break;
      case '--concurrency':
        out.concurrency = parseIntInRange(next, out.concurrency, 1, 64);
        i += 1;
        break;
      case '--remote-model-id':
        out.remoteModelId = safeString(next) || out.remoteModelId;
        i += 1;
        break;
      case '--local-model-id':
        out.localModelId = safeString(next) || out.localModelId;
        i += 1;
        break;
      case '--provider':
        out.provider = safeString(next) || out.provider;
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 1000, 300000);
        i += 1;
        break;
      case '--min-remote-prep-matches':
        out.minRemotePrepMatches = parseIntInRange(next, out.minRemotePrepMatches, 0, 1000000);
        i += 1;
        break;
      case '--min-local-prep-matches':
        out.minLocalPrepMatches = parseIntInRange(next, out.minLocalPrepMatches, 0, 1000000);
        i += 1;
        break;
      case '--max-prep-warnings':
        out.maxPrepWarnings = parseIntInRange(next, out.maxPrepWarnings, 0, 1000000);
        i += 1;
        break;
      case '--max-generate-ms':
        out.maxGenerateMs = parseIntInRange(next, out.maxGenerateMs, 100, 300000);
        i += 1;
        break;
      case '--report-path':
        out.reportPath = safeString(next);
        i += 1;
        break;
      case '--expect-ready':
        out.expectReady = true;
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
  if (out.minRemotePrepMatches <= 0) out.minRemotePrepMatches = out.remoteRuns;
  if (out.minLocalPrepMatches <= 0) out.minLocalPrepMatches = out.localRuns;
  if (!out.reportPath) out.reportPath = defaultReportPath();
  return out;
}

function usage() {
  return [
    'model_route_prep_trial_runner.js',
    '',
    'Options:',
    '  --remote-runs <n>              Remote Generate prep batches, default 1',
    '  --local-runs <n>               Local Generate prep batches, default 1',
    '  --concurrency <n>              Parallel Generate calls per batch, default 1',
    '  --remote-model-id <id>         Remote model ID, default gpt-5.5',
    '  --local-model-id <id>          Local model ID, default local.summary',
    '  --provider <id>                Remote provider, default openai',
    '  --timeout-ms <n>               Per-runner timeout, default 45000',
    '  --min-remote-prep-matches <n>  Remote prep match threshold',
    '  --min-local-prep-matches <n>   Local prep match threshold',
    '  --max-prep-warnings <n>        Prep warning threshold, default 0',
    '  --max-generate-ms <n>          Generate latency threshold, default 2000',
    '  --report-path <path>           Persisted report path',
    '  --expect-ready                 Exit non-zero unless prep trial is ready',
    '  --dry-run                      Print resolved config',
    '  --self-test                    Run parser self-test',
  ].join('\n');
}

function publicConfig(config) {
  return {
    remote_runs: config.remoteRuns,
    local_runs: config.localRuns,
    concurrency: config.concurrency,
    remote_model_id: config.remoteModelId,
    local_model_id: config.localModelId,
    provider: config.provider,
    timeout_ms: config.timeoutMs,
    min_remote_prep_matches: config.minRemotePrepMatches,
    min_local_prep_matches: config.minLocalPrepMatches,
    max_prep_warnings: config.maxPrepWarnings,
    max_generate_ms: config.maxGenerateMs,
    report_path: config.reportPath,
    expect_ready: config.expectReady,
    rust_hub_root: ROOT_DIR,
  };
}

function runSelfTest() {
  const parsed = parseArgs([
    '--remote-runs', '2',
    '--local-runs', '3',
    '--concurrency', '1',
    '--expect-ready',
  ]);
  if (
    parsed.remoteRuns !== 2
    || parsed.localRuns !== 3
    || parsed.minRemotePrepMatches !== 2
    || parsed.minLocalPrepMatches !== 3
    || parsed.expectReady !== true
  ) {
    throw new Error('self-test parser failed');
  }
  const readiness = buildReadiness({
    config: parsed,
    remoteResult: {
      exit_code: 0,
      parsed: true,
      payload: {
        ok: true,
        generate_ok: true,
        prep_trial: true,
        prep_match_count: 2,
        prep_warning_count: 0,
        node_authority_preserved: true,
        max_generate_ms: 10,
        prep_readiness: { ready: true },
      },
    },
    localResult: {
      exit_code: 0,
      parsed: true,
      payload: {
        ok: true,
        generate_ok: true,
        prep_trial: true,
        prep_match_count: 3,
        prep_warning_count: 0,
        node_authority_preserved: true,
        max_generate_ms: 10,
        prep_readiness: { ready: true },
      },
    },
  });
  if (readiness.ready !== true) {
    throw new Error('self-test readiness failed');
  }
}

function parseLastJsonObject(stdout, expectedEvent = 'stop') {
  const text = String(stdout || '').trim();
  const positions = [];
  for (let i = 0; i < text.length; i += 1) {
    if (text[i] === '{') positions.push(i);
  }
  for (let i = positions.length - 1; i >= 0; i -= 1) {
    const candidate = text.slice(positions[i]).trim();
    try {
      const parsed = JSON.parse(candidate);
      if (!expectedEvent || parsed?.event === expectedEvent) return parsed;
    } catch {
      // keep scanning earlier object starts
    }
  }
  throw new Error('runner output did not contain a parseable final JSON object');
}

function runRunner(label, fileName, args, timeoutMs) {
  const filePath = path.join(SCRIPT_DIR, fileName);
  let stdout = '';
  let stderr = '';
  let exitCode = 0;
  try {
    stdout = execFileSync(filePath, args, {
      encoding: 'utf8',
      timeout: timeoutMs,
      env: process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
      maxBuffer: 32 * 1024 * 1024,
    });
  } catch (error) {
    exitCode = Number(error.status || 1);
    stdout = String(error.stdout || '');
    stderr = String(error.stderr || error.message || '');
  }
  let payload = null;
  let parseError = '';
  try {
    payload = parseLastJsonObject(stdout, 'stop');
  } catch (error) {
    parseError = String(error.message || error);
  }
  return {
    label,
    exit_code: exitCode,
    parsed: !!payload,
    parse_error: parseError,
    payload,
    stderr: stderr ? stderr.slice(0, 4000) : '',
  };
}

function check(name, ok, actual, threshold, detail) {
  return { name, ok: ok === true, actual, threshold, detail };
}

function buildReadiness({ config, remoteResult, localResult }) {
  const remote = remoteResult.payload || {};
  const local = localResult.payload || {};
  const maxGenerateMs = Math.max(Number(remote.max_generate_ms || 0), Number(local.max_generate_ms || 0));
  const remoteWarnings = Number(remote.prep_warning_count || 0);
  const localWarnings = Number(local.prep_warning_count || 0);
  const checks = [
    check('remote_prep_runner_ok', remoteResult.exit_code === 0 && remoteResult.parsed === true && remote.ok === true, remoteResult.exit_code, 0, 'remote prep runner must exit cleanly'),
    check('remote_prep_trial_mode', remote.prep_trial === true, remote.prep_trial === true ? 1 : 0, 1, 'remote runner must execute prep-trial mode'),
    check('remote_prep_readiness', remote.prep_readiness?.ready === true, remote.prep_readiness?.ready === true ? 1 : 0, 1, 'remote prep readiness must be ready'),
    check('remote_prep_min_matches', Number(remote.prep_match_count || 0) >= config.minRemotePrepMatches, Number(remote.prep_match_count || 0), config.minRemotePrepMatches, 'remote prep matches must satisfy threshold'),
    check('remote_node_authority_preserved', remote.node_authority_preserved === true, remote.node_authority_preserved === true ? 1 : 0, 1, 'remote Bridge payload model/provider must remain Node-selected'),
    check('local_prep_runner_ok', localResult.exit_code === 0 && localResult.parsed === true && local.ok === true, localResult.exit_code, 0, 'local prep runner must exit cleanly'),
    check('local_prep_trial_mode', local.prep_trial === true, local.prep_trial === true ? 1 : 0, 1, 'local runner must execute prep-trial mode'),
    check('local_prep_readiness', local.prep_readiness?.ready === true, local.prep_readiness?.ready === true ? 1 : 0, 1, 'local prep readiness must be ready'),
    check('local_prep_min_matches', Number(local.prep_match_count || 0) >= config.minLocalPrepMatches, Number(local.prep_match_count || 0), config.minLocalPrepMatches, 'local prep matches must satisfy threshold'),
    check('local_node_authority_preserved', local.node_authority_preserved === true, local.node_authority_preserved === true ? 1 : 0, 1, 'local runtime IPC model must remain Node-selected'),
    check('prep_warning_max', remoteWarnings + localWarnings <= config.maxPrepWarnings, remoteWarnings + localWarnings, config.maxPrepWarnings, 'prep trial must stay within warning threshold'),
    check('combined_generate_latency_max_ms', maxGenerateMs <= config.maxGenerateMs, maxGenerateMs, config.maxGenerateMs, 'remote and local Generate latency must stay within threshold'),
    check('production_authority_disabled', true, 0, 0, 'prep trial does not enable production selected-model authority'),
  ];
  const ready = checks.every((item) => item.ok === true);
  return {
    schema_version: 'xhub.model_route_prep_trial_readiness.v1',
    component: 'model_route',
    decision: ready ? 'ready' : 'not_ready',
    ready,
    generated_at_ms: Date.now(),
    thresholds: {
      min_remote_prep_matches: config.minRemotePrepMatches,
      min_local_prep_matches: config.minLocalPrepMatches,
      max_prep_warnings: config.maxPrepWarnings,
      max_generate_ms: config.maxGenerateMs,
    },
    remote: {
      prep_ready: remote.prep_readiness?.ready === true,
      prep_match_count: Number(remote.prep_match_count || 0),
      prep_warning_count: remoteWarnings,
      node_authority_preserved: remote.node_authority_preserved === true,
      max_generate_ms: Number(remote.max_generate_ms || 0),
    },
    local: {
      prep_ready: local.prep_readiness?.ready === true,
      prep_match_count: Number(local.prep_match_count || 0),
      prep_warning_count: localWarnings,
      node_authority_preserved: local.node_authority_preserved === true,
      max_generate_ms: Number(local.max_generate_ms || 0),
    },
    checks,
  };
}

function buildReport({ config, readiness, remoteResult, localResult }) {
  return {
    schema_version: 'xhub.model_route_prep_trial_report.v1',
    generated_at_ms: Date.now(),
    component: 'model_route',
    production_authority_change: false,
    selected_model_authority_enabled: false,
    authority_mode: 'prep_trial_only',
    node_remains_model_selection_authority: true,
    bridge_payload_model_authority_remains_node: true,
    local_runtime_ipc_model_authority_remains_node: true,
    config: publicConfig(config),
    readiness,
    runners: {
      remote: {
        label: remoteResult.label,
        exit_code: remoteResult.exit_code,
        parsed: remoteResult.parsed,
        parse_error: remoteResult.parse_error,
        stderr: remoteResult.stderr,
      },
      local: {
        label: localResult.label,
        exit_code: localResult.exit_code,
        parsed: localResult.parsed,
        parse_error: localResult.parse_error,
        stderr: localResult.stderr,
      },
    },
    evidence: {
      remote: {
        schema_version: remoteResult.payload?.schema_version || '',
        ok: remoteResult.payload?.ok === true,
        prep_trial: remoteResult.payload?.prep_trial === true,
        prep_readiness: remoteResult.payload?.prep_readiness || null,
        prep_match_count: Number(remoteResult.payload?.prep_match_count || 0),
        prep_warning_count: Number(remoteResult.payload?.prep_warning_count || 0),
        node_authority_preserved: remoteResult.payload?.node_authority_preserved === true,
        max_generate_ms: Number(remoteResult.payload?.max_generate_ms || 0),
      },
      local: {
        schema_version: localResult.payload?.schema_version || '',
        ok: localResult.payload?.ok === true,
        prep_trial: localResult.payload?.prep_trial === true,
        prep_readiness: localResult.payload?.prep_readiness || null,
        prep_match_count: Number(localResult.payload?.prep_match_count || 0),
        prep_warning_count: Number(localResult.payload?.prep_warning_count || 0),
        node_authority_preserved: localResult.payload?.node_authority_preserved === true,
        max_generate_ms: Number(localResult.payload?.max_generate_ms || 0),
      },
    },
  };
}

function writeJsonAtomic(filePath, obj) {
  const target = path.resolve(String(filePath || ''));
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const tmp = `${target}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`;
  fs.writeFileSync(tmp, `${JSON.stringify(obj, null, 2)}\n`, 'utf8');
  fs.renameSync(tmp, target);
  return target;
}

function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    console.log(usage());
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    console.log('model_route_prep_trial_runner self-test ok');
    return;
  }
  if (config.dryRun) {
    console.log(JSON.stringify({
      ok: true,
      schema_version: 'xhub.model_route_prep_trial_runner.dry_run.v1',
      config: publicConfig(config),
    }, null, 2));
    return;
  }

  console.log(JSON.stringify({
    event: 'start',
    schema_version: 'xhub.model_route_prep_trial_runner.event.v1',
    config: publicConfig(config),
  }));

  const remoteResult = runRunner(
    'remote_model_route_prep_trial',
    'model_route_generate_candidate_runner.command',
    [
      '--prep-trial',
      '--runs', String(config.remoteRuns),
      '--concurrency', String(config.concurrency),
      '--provider', config.provider,
      '--model-id', config.remoteModelId,
      '--expect-ready',
      '--min-prep-matches', String(config.minRemotePrepMatches),
      '--max-generate-ms', String(config.maxGenerateMs),
      '--timeout-ms', String(config.timeoutMs),
    ],
    config.timeoutMs + 30000
  );

  const localResult = runRunner(
    'local_model_route_prep_trial',
    'model_route_local_candidate_runner.command',
    [
      '--prep-trial',
      '--runs', String(config.localRuns),
      '--concurrency', String(config.concurrency),
      '--model-id', config.localModelId,
      '--expect-ready',
      '--min-prep-matches', String(config.minLocalPrepMatches),
      '--max-generate-ms', String(config.maxGenerateMs),
      '--timeout-ms', String(config.timeoutMs),
    ],
    config.timeoutMs + 30000
  );

  const readiness = buildReadiness({ config, remoteResult, localResult });
  const report = buildReport({ config, readiness, remoteResult, localResult });
  const reportPath = writeJsonAtomic(config.reportPath, report);
  const ok = config.expectReady ? readiness.ready === true : true;
  const finalPayload = {
    event: 'stop',
    ok,
    schema_version: 'xhub.model_route_prep_trial_runner.result.v1',
    report_path: reportPath,
    readiness,
    remote_runner: {
      exit_code: remoteResult.exit_code,
      parsed: remoteResult.parsed,
      parse_error: remoteResult.parse_error,
      stderr: remoteResult.stderr,
    },
    local_runner: {
      exit_code: localResult.exit_code,
      parsed: localResult.parsed,
      parse_error: localResult.parse_error,
      stderr: localResult.stderr,
    },
  };
  console.log(JSON.stringify(finalPayload, null, 2));
  if (!ok) process.exitCode = 2;
}

try {
  main();
} catch (error) {
  console.error(`[model_route_prep_trial_runner] ${error?.stack || error?.message || error}`);
  process.exit(1);
}
