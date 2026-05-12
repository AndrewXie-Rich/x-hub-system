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

function timestamp() {
  return new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
}

function defaultReportPath() {
  return path.join(ROOT_DIR, 'reports', `model_route_prep_sustained_${timestamp()}.json`);
}

function parseArgs(argv) {
  const out = {
    cycles: 3,
    remoteRuns: 1,
    localRuns: 1,
    concurrency: 1,
    remoteModelId: 'gpt-5.5',
    localModelId: 'local.summary',
    provider: 'openai',
    timeoutMs: 45000,
    minReadyCycles: 0,
    maxFailedCycles: 0,
    minTotalRemotePrepMatches: 0,
    minTotalLocalPrepMatches: 0,
    maxTotalPrepWarnings: 0,
    maxCycleGenerateMs: 2000,
    reportPath: '',
    cycleReportDir: '',
    expectReady: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--cycles':
        out.cycles = parseIntInRange(next, out.cycles, 1, 10000);
        i += 1;
        break;
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
      case '--min-ready-cycles':
        out.minReadyCycles = parseIntInRange(next, out.minReadyCycles, 0, 1000000);
        i += 1;
        break;
      case '--max-failed-cycles':
        out.maxFailedCycles = parseIntInRange(next, out.maxFailedCycles, 0, 1000000);
        i += 1;
        break;
      case '--min-total-remote-prep-matches':
        out.minTotalRemotePrepMatches = parseIntInRange(next, out.minTotalRemotePrepMatches, 0, 1000000);
        i += 1;
        break;
      case '--min-total-local-prep-matches':
        out.minTotalLocalPrepMatches = parseIntInRange(next, out.minTotalLocalPrepMatches, 0, 1000000);
        i += 1;
        break;
      case '--max-total-prep-warnings':
        out.maxTotalPrepWarnings = parseIntInRange(next, out.maxTotalPrepWarnings, 0, 1000000);
        i += 1;
        break;
      case '--max-cycle-generate-ms':
        out.maxCycleGenerateMs = parseIntInRange(next, out.maxCycleGenerateMs, 100, 300000);
        i += 1;
        break;
      case '--report-path':
        out.reportPath = safeString(next);
        i += 1;
        break;
      case '--cycle-report-dir':
        out.cycleReportDir = safeString(next);
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
  if (!out.reportPath) out.reportPath = defaultReportPath();
  if (!out.cycleReportDir) {
    const base = path.basename(out.reportPath, path.extname(out.reportPath));
    out.cycleReportDir = path.join(path.dirname(out.reportPath), `${base}_cycles`);
  }
  if (out.minReadyCycles <= 0) out.minReadyCycles = out.cycles;
  if (out.minTotalRemotePrepMatches <= 0) {
    out.minTotalRemotePrepMatches = out.cycles * out.remoteRuns;
  }
  if (out.minTotalLocalPrepMatches <= 0) {
    out.minTotalLocalPrepMatches = out.cycles * out.localRuns;
  }
  return out;
}

function usage() {
  return [
    'model_route_prep_sustained_runner.js',
    '',
    'Options:',
    '  --cycles <n>                         Prep trial cycles, default 3',
    '  --remote-runs <n>                    Remote Generate prep batches per cycle, default 1',
    '  --local-runs <n>                     Local Generate prep batches per cycle, default 1',
    '  --concurrency <n>                    Parallel Generate calls per batch, default 1',
    '  --remote-model-id <id>               Remote model ID, default gpt-5.5',
    '  --local-model-id <id>                Local model ID, default local.summary',
    '  --provider <id>                      Remote provider, default openai',
    '  --timeout-ms <n>                     Per-cycle timeout, default 45000',
    '  --min-ready-cycles <n>               Ready cycle threshold, default cycles',
    '  --max-failed-cycles <n>              Failed cycle threshold, default 0',
    '  --min-total-remote-prep-matches <n>  Remote prep match threshold',
    '  --min-total-local-prep-matches <n>   Local prep match threshold',
    '  --max-total-prep-warnings <n>        Prep warning threshold, default 0',
    '  --max-cycle-generate-ms <n>          Per-cycle latency threshold, default 2000',
    '  --report-path <path>                 Persisted sustained report path',
    '  --cycle-report-dir <path>            Per-cycle RHM-026 report directory',
    '  --expect-ready                       Exit non-zero unless sustained readiness is ready',
    '  --dry-run                            Print resolved config',
    '  --self-test                          Run parser/readiness self-test',
  ].join('\n');
}

function publicConfig(config) {
  return {
    cycles: config.cycles,
    remote_runs: config.remoteRuns,
    local_runs: config.localRuns,
    concurrency: config.concurrency,
    remote_model_id: config.remoteModelId,
    local_model_id: config.localModelId,
    provider: config.provider,
    timeout_ms: config.timeoutMs,
    min_ready_cycles: config.minReadyCycles,
    max_failed_cycles: config.maxFailedCycles,
    min_total_remote_prep_matches: config.minTotalRemotePrepMatches,
    min_total_local_prep_matches: config.minTotalLocalPrepMatches,
    max_total_prep_warnings: config.maxTotalPrepWarnings,
    max_cycle_generate_ms: config.maxCycleGenerateMs,
    report_path: config.reportPath,
    cycle_report_dir: config.cycleReportDir,
    expect_ready: config.expectReady,
    rust_hub_root: ROOT_DIR,
  };
}

function runSelfTest() {
  const parsed = parseArgs([
    '--cycles', '2',
    '--remote-runs', '1',
    '--local-runs', '2',
    '--expect-ready',
  ]);
  if (
    parsed.cycles !== 2
    || parsed.minReadyCycles !== 2
    || parsed.minTotalRemotePrepMatches !== 2
    || parsed.minTotalLocalPrepMatches !== 4
    || parsed.expectReady !== true
  ) {
    throw new Error('self-test parser failed');
  }
  const readiness = buildReadiness({
    config: parsed,
    cycles: [
      fakeCycle(1, { remote: 1, local: 2 }),
      fakeCycle(2, { remote: 1, local: 2 }),
    ],
  });
  if (readiness.ready !== true) {
    throw new Error('self-test readiness failed');
  }
}

function fakeCycle(index, counts) {
  return {
    cycle_index: index,
    ok: true,
    exit_code: 0,
    parsed: true,
    report_path: `/tmp/model_route_prep_sustained_self_test_${index}.json`,
    report_exists: true,
    readiness_ready: true,
    remote_prep_match_count: counts.remote,
    local_prep_match_count: counts.local,
    remote_prep_warning_count: 0,
    local_prep_warning_count: 0,
    prep_warning_count: 0,
    remote_node_authority_preserved: true,
    local_node_authority_preserved: true,
    node_authority_preserved: true,
    production_authority_change: false,
    selected_model_authority_enabled: false,
    max_generate_ms: 10,
    stderr: '',
  };
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

function runRunner(fileName, args, timeoutMs) {
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
      maxBuffer: 64 * 1024 * 1024,
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
    exit_code: exitCode,
    parsed: !!payload,
    parse_error: parseError,
    payload,
    stderr: stderr ? stderr.slice(0, 4000) : '',
  };
}

function readJsonSafe(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function cycleReportPath(config, cycleIndex) {
  return path.join(
    config.cycleReportDir,
    `cycle_${String(cycleIndex).padStart(3, '0')}.json`
  );
}

function summarizeCycle({ cycleIndex, result, reportPath }) {
  const payload = result.payload || {};
  const readiness = payload.readiness || {};
  const remote = readiness.remote || {};
  const local = readiness.local || {};
  const report = readJsonSafe(reportPath);
  const reportExists = !!report && fs.existsSync(reportPath);
  const productionAuthorityChange = report?.production_authority_change === true;
  const selectedModelAuthorityEnabled = report?.selected_model_authority_enabled === true;
  const remoteNodeAuthorityPreserved = remote.node_authority_preserved === true;
  const localNodeAuthorityPreserved = local.node_authority_preserved === true;
  const reportNodeAuthorityPreserved = report?.node_remains_model_selection_authority === true
    && report?.bridge_payload_model_authority_remains_node === true
    && report?.local_runtime_ipc_model_authority_remains_node === true;
  const nodeAuthorityPreserved = remoteNodeAuthorityPreserved
    && localNodeAuthorityPreserved
    && reportNodeAuthorityPreserved;
  const remoteWarnings = Number(remote.prep_warning_count || 0);
  const localWarnings = Number(local.prep_warning_count || 0);
  const maxGenerateMs = Math.max(Number(remote.max_generate_ms || 0), Number(local.max_generate_ms || 0));
  const ok = result.exit_code === 0
    && result.parsed === true
    && payload.ok === true
    && readiness.ready === true
    && reportExists
    && !productionAuthorityChange
    && !selectedModelAuthorityEnabled
    && nodeAuthorityPreserved;
  return {
    cycle_index: cycleIndex,
    ok,
    exit_code: result.exit_code,
    parsed: result.parsed,
    parse_error: result.parse_error,
    report_path: reportPath,
    report_exists: reportExists,
    readiness_ready: readiness.ready === true,
    remote_prep_match_count: Number(remote.prep_match_count || 0),
    local_prep_match_count: Number(local.prep_match_count || 0),
    remote_prep_warning_count: remoteWarnings,
    local_prep_warning_count: localWarnings,
    prep_warning_count: remoteWarnings + localWarnings,
    remote_node_authority_preserved: remoteNodeAuthorityPreserved,
    local_node_authority_preserved: localNodeAuthorityPreserved,
    node_authority_preserved: nodeAuthorityPreserved,
    production_authority_change: productionAuthorityChange,
    selected_model_authority_enabled: selectedModelAuthorityEnabled,
    max_generate_ms: maxGenerateMs,
    stderr: result.stderr,
  };
}

function runCycle(config, cycleIndex) {
  const reportPath = path.resolve(cycleReportPath(config, cycleIndex));
  const result = runRunner(
    'model_route_prep_trial_runner.command',
    [
      '--remote-runs', String(config.remoteRuns),
      '--local-runs', String(config.localRuns),
      '--concurrency', String(config.concurrency),
      '--provider', config.provider,
      '--remote-model-id', config.remoteModelId,
      '--local-model-id', config.localModelId,
      '--expect-ready',
      '--min-remote-prep-matches', String(config.remoteRuns),
      '--min-local-prep-matches', String(config.localRuns),
      '--max-prep-warnings', '0',
      '--max-generate-ms', String(config.maxCycleGenerateMs),
      '--timeout-ms', String(config.timeoutMs),
      '--report-path', reportPath,
    ],
    config.timeoutMs + 60000
  );
  return summarizeCycle({ cycleIndex, result, reportPath });
}

function check(name, ok, actual, threshold, detail) {
  return { name, ok: ok === true, actual, threshold, detail };
}

function sum(cycles, key) {
  return cycles.reduce((total, cycle) => total + Number(cycle?.[key] || 0), 0);
}

function buildReadiness({ config, cycles }) {
  const readyCycles = cycles.filter((cycle) => cycle.ok === true).length;
  const failedCycles = cycles.length - readyCycles;
  const totalRemotePrepMatches = sum(cycles, 'remote_prep_match_count');
  const totalLocalPrepMatches = sum(cycles, 'local_prep_match_count');
  const totalPrepWarnings = sum(cycles, 'prep_warning_count');
  const maxGenerateMs = cycles.reduce(
    (max, cycle) => Math.max(max, Number(cycle?.max_generate_ms || 0)),
    0
  );
  const missingReports = cycles.filter((cycle) => cycle.report_exists !== true).length;
  const productionAuthorityChanges = cycles.filter((cycle) => cycle.production_authority_change === true).length;
  const selectedAuthorityEnabled = cycles.filter((cycle) => cycle.selected_model_authority_enabled === true).length;
  const nodeAuthorityFailures = cycles.filter((cycle) => cycle.node_authority_preserved !== true).length;
  const checks = [
    check('cycle_count', cycles.length === config.cycles, cycles.length, config.cycles, 'runner must execute every configured cycle'),
    check('min_ready_cycles', readyCycles >= config.minReadyCycles, readyCycles, config.minReadyCycles, 'ready cycles must satisfy threshold'),
    check('max_failed_cycles', failedCycles <= config.maxFailedCycles, failedCycles, config.maxFailedCycles, 'failed cycles must stay within threshold'),
    check('min_total_remote_prep_matches', totalRemotePrepMatches >= config.minTotalRemotePrepMatches, totalRemotePrepMatches, config.minTotalRemotePrepMatches, 'remote prep matches must satisfy total threshold'),
    check('min_total_local_prep_matches', totalLocalPrepMatches >= config.minTotalLocalPrepMatches, totalLocalPrepMatches, config.minTotalLocalPrepMatches, 'local prep matches must satisfy total threshold'),
    check('max_total_prep_warnings', totalPrepWarnings <= config.maxTotalPrepWarnings, totalPrepWarnings, config.maxTotalPrepWarnings, 'prep warnings must stay within total threshold'),
    check('max_cycle_generate_ms', maxGenerateMs <= config.maxCycleGenerateMs, maxGenerateMs, config.maxCycleGenerateMs, 'each cycle must stay within the latency threshold'),
    check('cycle_reports_present', missingReports === 0, missingReports, 0, 'each cycle must persist its RHM-026 report'),
    check('production_authority_unchanged', productionAuthorityChanges === 0, productionAuthorityChanges, 0, 'prep sustained evidence must not change production authority'),
    check('selected_model_authority_disabled', selectedAuthorityEnabled === 0, selectedAuthorityEnabled, 0, 'prep sustained evidence must not enable Rust selected-model authority'),
    check('node_authority_preserved', nodeAuthorityFailures === 0, nodeAuthorityFailures, 0, 'Node-selected remote/local execution models must remain authoritative'),
  ];
  const ready = checks.every((item) => item.ok === true);
  return {
    schema_version: 'xhub.model_route_prep_sustained_readiness.v1',
    component: 'model_route',
    decision: ready ? 'ready' : 'not_ready',
    ready,
    generated_at_ms: Date.now(),
    thresholds: {
      cycles: config.cycles,
      min_ready_cycles: config.minReadyCycles,
      max_failed_cycles: config.maxFailedCycles,
      min_total_remote_prep_matches: config.minTotalRemotePrepMatches,
      min_total_local_prep_matches: config.minTotalLocalPrepMatches,
      max_total_prep_warnings: config.maxTotalPrepWarnings,
      max_cycle_generate_ms: config.maxCycleGenerateMs,
    },
    aggregate: {
      ready_cycles: readyCycles,
      failed_cycles: failedCycles,
      total_remote_prep_matches: totalRemotePrepMatches,
      total_local_prep_matches: totalLocalPrepMatches,
      total_prep_warnings: totalPrepWarnings,
      max_generate_ms: maxGenerateMs,
      missing_reports: missingReports,
      production_authority_changes: productionAuthorityChanges,
      selected_model_authority_enabled_cycles: selectedAuthorityEnabled,
      node_authority_failures: nodeAuthorityFailures,
    },
    checks,
  };
}

function buildReport({ config, readiness, cycles }) {
  return {
    schema_version: 'xhub.model_route_prep_sustained_report.v1',
    generated_at_ms: Date.now(),
    component: 'model_route',
    production_authority_change: false,
    selected_model_authority_enabled: false,
    authority_mode: 'prep_sustained_diagnostic_only',
    node_remains_model_selection_authority: true,
    bridge_payload_model_authority_remains_node: true,
    local_runtime_ipc_model_authority_remains_node: true,
    config: publicConfig(config),
    readiness,
    cycle_reports: cycles.map((cycle) => cycle.report_path),
    cycles,
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
    console.log('model_route_prep_sustained_runner self-test ok');
    return;
  }
  if (config.dryRun) {
    console.log(JSON.stringify({
      ok: true,
      schema_version: 'xhub.model_route_prep_sustained_runner.dry_run.v1',
      config: publicConfig(config),
    }, null, 2));
    return;
  }

  console.log(JSON.stringify({
    event: 'start',
    schema_version: 'xhub.model_route_prep_sustained_runner.event.v1',
    config: publicConfig(config),
  }));

  const cycles = [];
  for (let index = 1; index <= config.cycles; index += 1) {
    console.log(JSON.stringify({
      event: 'cycle_start',
      schema_version: 'xhub.model_route_prep_sustained_runner.event.v1',
      cycle_index: index,
    }));
    const summary = runCycle(config, index);
    cycles.push(summary);
    console.log(JSON.stringify({
      event: 'cycle_stop',
      schema_version: 'xhub.model_route_prep_sustained_runner.event.v1',
      cycle_index: index,
      ok: summary.ok,
      report_path: summary.report_path,
      remote_prep_match_count: summary.remote_prep_match_count,
      local_prep_match_count: summary.local_prep_match_count,
      prep_warning_count: summary.prep_warning_count,
      node_authority_preserved: summary.node_authority_preserved,
    }));
  }

  const readiness = buildReadiness({ config, cycles });
  const report = buildReport({ config, readiness, cycles });
  const reportPath = writeJsonAtomic(config.reportPath, report);
  const ok = config.expectReady ? readiness.ready === true : true;
  const finalPayload = {
    event: 'stop',
    ok,
    schema_version: 'xhub.model_route_prep_sustained_runner.result.v1',
    report_path: reportPath,
    readiness,
  };
  console.log(JSON.stringify(finalPayload, null, 2));
  if (!ok) process.exitCode = 2;
}

try {
  main();
} catch (error) {
  console.error(`[model_route_prep_sustained_runner] ${error?.stack || error?.message || error}`);
  process.exit(1);
}
