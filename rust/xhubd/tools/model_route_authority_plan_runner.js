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

function defaultPlanPath() {
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
  return path.join(ROOT_DIR, 'reports', `model_route_authority_plan_${stamp}.json`);
}

function parseArgs(argv) {
  const out = {
    remoteRuns: 2,
    localRuns: 2,
    concurrency: 1,
    remoteModelId: 'gpt-5.5',
    localModelId: 'local.summary',
    provider: 'openai',
    timeoutMs: 45000,
    minRemoteCandidateAudits: 0,
    minLocalCandidateAudits: 0,
    maxCandidateMismatches: 0,
    maxCandidateFallbacks: 0,
    maxGenerateMs: 2000,
    minCompareReports: 0,
    maxMismatches: 0,
    reportPath: '',
    planPath: '',
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
      case '--min-remote-candidate-audits':
        out.minRemoteCandidateAudits = parseIntInRange(next, out.minRemoteCandidateAudits, 0, 1000000);
        i += 1;
        break;
      case '--min-local-candidate-audits':
        out.minLocalCandidateAudits = parseIntInRange(next, out.minLocalCandidateAudits, 0, 1000000);
        i += 1;
        break;
      case '--max-candidate-mismatches':
        out.maxCandidateMismatches = parseIntInRange(next, out.maxCandidateMismatches, 0, 1000000);
        i += 1;
        break;
      case '--max-candidate-fallbacks':
        out.maxCandidateFallbacks = parseIntInRange(next, out.maxCandidateFallbacks, 0, 1000000);
        i += 1;
        break;
      case '--max-generate-ms':
        out.maxGenerateMs = parseIntInRange(next, out.maxGenerateMs, 100, 300000);
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
      case '--report-path':
        out.reportPath = safeString(next);
        i += 1;
        break;
      case '--plan-path':
        out.planPath = safeString(next);
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
  if (out.minRemoteCandidateAudits <= 0) {
    out.minRemoteCandidateAudits = out.remoteRuns * out.concurrency;
  }
  if (out.minLocalCandidateAudits <= 0) {
    out.minLocalCandidateAudits = out.localRuns * out.concurrency;
  }
  if (!out.planPath) out.planPath = defaultPlanPath();
  return out;
}

function usage() {
  return [
    'model_route_authority_plan_runner.js',
    '',
    'Options:',
    '  --remote-runs <n>                 Remote Generate batches, default 2',
    '  --local-runs <n>                  Local Generate batches, default 2',
    '  --concurrency <n>                 Parallel Generate calls per batch, default 1',
    '  --remote-model-id <id>            Remote model ID, default gpt-5.5',
    '  --local-model-id <id>             Local model ID, default local.summary',
    '  --provider <id>                   Remote provider, default openai',
    '  --timeout-ms <n>                  Per-runner timeout, default 45000',
    '  --min-remote-candidate-audits <n> Remote candidate audit threshold',
    '  --min-local-candidate-audits <n>  Local candidate audit threshold',
    '  --max-candidate-mismatches <n>    Model/route-kind mismatch threshold, default 0',
    '  --max-candidate-fallbacks <n>     Candidate fallback threshold, default 0',
    '  --max-generate-ms <n>             Generate latency threshold, default 2000',
    '  --min-compare-reports <n>         Model readiness report threshold for prep env, default 0',
    '  --max-mismatches <n>              Model readiness mismatch threshold for prep env, default 0',
    '  --report-path <path>              Candidate evidence report path',
    '  --plan-path <path>                Persisted authority plan path',
    '  --expect-ready                    Exit non-zero unless dry-run plan is ready',
    '  --dry-run                         Print resolved config',
    '  --self-test                       Run parser self-test',
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
    min_remote_candidate_audits: config.minRemoteCandidateAudits,
    min_local_candidate_audits: config.minLocalCandidateAudits,
    max_candidate_mismatches: config.maxCandidateMismatches,
    max_candidate_fallbacks: config.maxCandidateFallbacks,
    max_generate_ms: config.maxGenerateMs,
    min_compare_reports: config.minCompareReports,
    max_mismatches: config.maxMismatches,
    report_path: config.reportPath,
    plan_path: config.planPath,
    expect_ready: config.expectReady,
    rust_hub_root: ROOT_DIR,
  };
}

function runSelfTest() {
  const parsed = parseArgs([
    '--remote-runs', '3',
    '--local-runs', '4',
    '--concurrency', '2',
    '--expect-ready',
  ]);
  if (
    parsed.remoteRuns !== 3
    || parsed.localRuns !== 4
    || parsed.concurrency !== 2
    || parsed.minRemoteCandidateAudits !== 6
    || parsed.minLocalCandidateAudits !== 8
    || parsed.expectReady !== true
  ) {
    throw new Error('self-test parser failed');
  }
  const plan = buildAuthorityPlan({
    config: parsed,
    evidenceResult: {
      exit_code: 0,
      parsed: true,
      payload: {
        ok: true,
        report_path: fileURLToPath(import.meta.url),
        readiness: {
          ready: true,
          decision: 'ready',
          schema_version: 'xhub.model_route_candidate_evidence_readiness.v1',
          remote: { readiness_ready: true, total: 6, model_mismatch: 0, route_kind_mismatch: 0, fallback: 0, secret_leak: 0 },
          local: { readiness_ready: true, total: 8, model_mismatch: 0, route_kind_mismatch: 0, fallback: 0, secret_leak: 0 },
          checks: [],
        },
      },
      stderr: '',
      parse_error: '',
    },
  });
  if (plan.ready !== true || plan.production_authority_change !== false) {
    throw new Error('self-test plan failed');
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

function runCandidateEvidence(config) {
  const filePath = path.join(SCRIPT_DIR, 'model_route_candidate_evidence_runner.command');
  const args = [
    '--remote-runs', String(config.remoteRuns),
    '--local-runs', String(config.localRuns),
    '--concurrency', String(config.concurrency),
    '--remote-model-id', config.remoteModelId,
    '--local-model-id', config.localModelId,
    '--provider', config.provider,
    '--expect-ready',
    '--min-remote-candidate-audits', String(config.minRemoteCandidateAudits),
    '--min-local-candidate-audits', String(config.minLocalCandidateAudits),
    '--max-candidate-mismatches', String(config.maxCandidateMismatches),
    '--max-candidate-fallbacks', String(config.maxCandidateFallbacks),
    '--max-generate-ms', String(config.maxGenerateMs),
    '--timeout-ms', String(config.timeoutMs),
  ];
  if (config.reportPath) {
    args.push('--report-path', config.reportPath);
  }

  let stdout = '';
  let stderr = '';
  let exitCode = 0;
  try {
    stdout = execFileSync(filePath, args, {
      encoding: 'utf8',
      timeout: config.timeoutMs + 90000,
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

function envRow(name, value, reason) {
  return { name, value, reason };
}

function fileExists(filePath) {
  try {
    return !!filePath && fs.existsSync(filePath);
  } catch {
    return false;
  }
}

function buildAuthorityPlan({ config, evidenceResult }) {
  const payload = evidenceResult.payload || {};
  const readiness = payload.readiness || {};
  const remote = readiness.remote || {};
  const local = readiness.local || {};
  const evidenceReady = readiness.ready === true;
  const runnerOk = evidenceResult.exit_code === 0 && evidenceResult.parsed === true && payload.ok === true;
  const reportPath = safeString(payload.report_path || config.reportPath);
  const checks = [
    check(
      'candidate_evidence_runner_ok',
      runnerOk,
      evidenceResult.exit_code,
      0,
      'combined remote/local candidate evidence runner must complete and parse'
    ),
    check(
      'candidate_evidence_ready',
      evidenceReady,
      evidenceReady ? 1 : 0,
      1,
      'combined remote/local candidate evidence readiness must be ready'
    ),
    check(
      'candidate_evidence_report_exists',
      fileExists(reportPath),
      fileExists(reportPath) ? 1 : 0,
      1,
      'authority planning must point at a persisted candidate evidence report'
    ),
    check(
      'remote_candidate_ready',
      remote.readiness_ready === true,
      remote.readiness_ready === true ? 1 : 0,
      1,
      'remote model route candidate path must be ready'
    ),
    check(
      'local_candidate_ready',
      local.readiness_ready === true,
      local.readiness_ready === true ? 1 : 0,
      1,
      'local model route candidate path must be ready'
    ),
    check(
      'production_authority_disabled',
      true,
      0,
      0,
      'this plan is dry-run only and does not enable production selected-model authority'
    ),
    check(
      'node_match_gate_required',
      true,
      1,
      1,
      'any prep trial must keep Node/Rust selected model and route-kind matching fail-closed'
    ),
  ];
  const ready = checks.every((item) => item.ok === true);
  const requiredEnv = [
    envRow('XHUB_RUST_HUB_ROOT', ROOT_DIR, 'point Node Hub bridges at this Rust Hub package'),
    envRow('XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP', '1', 'enable readiness-gated Rust model route prep checks only'),
    envRow('XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE', '1', 'continue Generate candidate audit evidence during prep'),
    envRow('XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP_THROTTLE_MS', '1000', 'throttle repeated prep checks for the same task/model/runtime route'),
    envRow('XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP_MAX_IN_FLIGHT', '2', 'cap concurrent Rust prep checks from the Node service hook'),
    envRow('XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP', '1', 'prefer warm xhubd /model/route and /model/readiness when available'),
    envRow('XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_BASE_URL', 'http://127.0.0.1:50151', 'default local xhubd serve HTTP endpoint for model route checks'),
    envRow('XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_TIMEOUT_MS', '750', 'keep daemon route attempts short so Node can fall back quickly'),
    envRow('XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI', '1', 'fall back to the existing CLI route path if the daemon is unavailable'),
    envRow('XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_READY', '1', 'fail closed unless model route readiness is ready'),
    envRow('XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH', '1', 'fallback unless Rust selected model and route kind match Node'),
    envRow('XHUB_RUST_MODEL_ROUTE_AUTHORITY_FALLBACK_ON_ERROR', '1', 'keep Node-selected execution on any Rust route error during prep'),
    envRow('XHUB_RUST_MODEL_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS', String(config.minCompareReports), 'model readiness report threshold for the prep trial'),
    envRow('XHUB_RUST_MODEL_ROUTE_AUTHORITY_MAX_MISMATCHES', String(config.maxMismatches), 'model readiness mismatch threshold for the prep trial'),
    envRow('XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS', '250', 'reuse identical candidate route checks briefly to reduce Generate hot-path Rust calls'),
    envRow('XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE_CACHE_MAX_ENTRIES', '128', 'bound the candidate route cache size in the Node bridge'),
  ];
  const rollbackEnv = [
    'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP',
    'XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE',
    'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP_THROTTLE_MS',
    'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP_MAX_IN_FLIGHT',
    'XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP',
    'XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_BASE_URL',
    'XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_TIMEOUT_MS',
    'XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI',
    'XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_READY',
    'XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH',
    'XHUB_RUST_MODEL_ROUTE_AUTHORITY_FALLBACK_ON_ERROR',
    'XHUB_RUST_MODEL_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS',
    'XHUB_RUST_MODEL_ROUTE_AUTHORITY_MAX_MISMATCHES',
    'XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS',
    'XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE_CACHE_MAX_ENTRIES',
    'XHUB_RUST_MODEL_ROUTE_AUTHORITY_VERBOSE',
  ];
  return {
    schema_version: 'xhub.model_route_selected_model_authority_dry_run_plan.v1',
    component: 'model_route',
    mode: 'dry_run_only',
    decision: ready ? 'ready_for_manual_prep_trial' : 'not_ready',
    ready,
    generated_at_ms: Date.now(),
    remote_model_id: config.remoteModelId,
    local_model_id: config.localModelId,
    provider: config.provider,
    production_authority_change: false,
    node_remains_model_selection_authority: true,
    bridge_payload_model_authority_remains_node: true,
    local_runtime_ipc_model_authority_remains_node: true,
    production_cutover_implemented: false,
    rust_can_prepare_model_route_decision: ready,
    selected_model_authority_enabled: false,
    evidence_report_path: reportPath,
    readiness_summary: {
      runner_ok: runnerOk,
      ready: evidenceReady,
      decision: safeString(readiness.decision),
      schema_version: safeString(readiness.schema_version),
      remote: remote || null,
      local: local || null,
    },
    required_env_for_manual_prep_trial: ready ? requiredEnv : [],
    env_to_unset_for_rollback: rollbackEnv,
    blocked_until_explicit_future_cutover: [
      'do not let Rust selected_model_id override Node actual_model_id',
      'do not change Bridge payload model_id for remote paid execution',
      'do not change local runtime ai_requests model_id',
      'do not remove Node/Rust selected model and route-kind match gate',
      'do not treat prep or candidate mode as production model selection authority',
      'do not persist or expose provider secrets in Rust model route evidence',
    ],
    manual_validation_commands: [
      `bash "${path.join(ROOT_DIR, 'tools', 'model_route_candidate_evidence_runner.command')}" --remote-runs ${config.remoteRuns} --local-runs ${config.localRuns} --concurrency ${config.concurrency} --expect-ready`,
      `bash "${path.join(ROOT_DIR, 'tools', 'model_route_generate_candidate_runner.command')}" --runs ${config.remoteRuns} --concurrency ${config.concurrency} --expect-ready --min-candidate-audits ${config.minRemoteCandidateAudits}`,
      `bash "${path.join(ROOT_DIR, 'tools', 'model_route_local_candidate_runner.command')}" --runs ${config.localRuns} --concurrency ${config.concurrency} --expect-ready --min-candidate-audits ${config.minLocalCandidateAudits}`,
    ],
    checks,
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
    console.log('model_route_authority_plan_runner self-test ok');
    return;
  }
  if (config.dryRun) {
    console.log(JSON.stringify({
      ok: true,
      schema_version: 'xhub.model_route_authority_plan_runner.dry_run.v1',
      config: publicConfig(config),
    }, null, 2));
    return;
  }

  console.log(JSON.stringify({
    event: 'start',
    schema_version: 'xhub.model_route_authority_plan_runner.event.v1',
    config: publicConfig(config),
  }));

  const evidenceResult = runCandidateEvidence(config);
  const plan = buildAuthorityPlan({ config, evidenceResult });
  const planPath = writeJsonAtomic(config.planPath, plan);
  const ok = config.expectReady ? plan.ready === true : true;
  const finalPayload = {
    event: 'stop',
    ok,
    schema_version: 'xhub.model_route_authority_plan_runner.result.v1',
    plan_path: planPath,
    plan,
    candidate_evidence_runner: {
      exit_code: evidenceResult.exit_code,
      parsed: evidenceResult.parsed,
      parse_error: evidenceResult.parse_error,
      stderr: evidenceResult.stderr,
      report_path: safeString(evidenceResult.payload?.report_path),
    },
  };
  console.log(JSON.stringify(finalPayload, null, 2));
  if (!ok) process.exitCode = 2;
}

try {
  main();
} catch (error) {
  console.error(`[model_route_authority_plan_runner] ${error?.stack || error?.message || error}`);
  process.exit(1);
}
