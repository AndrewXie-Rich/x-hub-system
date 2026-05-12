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
  return path.join(ROOT_DIR, 'reports', `model_route_candidate_evidence_${stamp}.json`);
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
  if (out.minRemoteCandidateAudits <= 0) {
    out.minRemoteCandidateAudits = out.remoteRuns * out.concurrency;
  }
  if (out.minLocalCandidateAudits <= 0) {
    out.minLocalCandidateAudits = out.localRuns * out.concurrency;
  }
  if (!out.reportPath) out.reportPath = defaultReportPath();
  return out;
}

function usage() {
  return [
    'model_route_candidate_evidence_runner.js',
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
    '  --report-path <path>              Persisted report path',
    '  --expect-ready                    Exit non-zero unless combined readiness is ready',
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
    report_path: config.reportPath,
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
  const readiness = buildCombinedReadiness({
    config: parsed,
    remoteResult: {
      exit_code: 0,
      parsed: true,
      payload: {
        ok: true,
        max_generate_ms: 10,
        candidate_audit_stats: { total: 6, model_mismatch: 0, route_kind_mismatch: 0, fallback: 0, secret_leak: 0 },
        candidate_readiness: { ready: true },
      },
    },
    localResult: {
      exit_code: 0,
      parsed: true,
      payload: {
        ok: true,
        max_generate_ms: 10,
        candidate_audit_stats: { total: 8, model_mismatch: 0, route_kind_mismatch: 0, fallback: 0, secret_leak: 0 },
        candidate_readiness: { ready: true },
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

function auditStats(payload) {
  return payload?.candidate_audit_stats || payload?.candidate_readiness?.audit || {};
}

function buildCombinedReadiness({ config, remoteResult, localResult }) {
  const remote = remoteResult.payload || {};
  const local = localResult.payload || {};
  const remoteAudit = auditStats(remote);
  const localAudit = auditStats(local);
  const remoteMismatch = Number(remoteAudit.model_mismatch || 0) + Number(remoteAudit.route_kind_mismatch || 0);
  const localMismatch = Number(localAudit.model_mismatch || 0) + Number(localAudit.route_kind_mismatch || 0);
  const remoteFallback = Number(remoteAudit.fallback || 0);
  const localFallback = Number(localAudit.fallback || 0);
  const remoteSecretLeak = Number(remoteAudit.secret_leak || 0);
  const localSecretLeak = Number(localAudit.secret_leak || 0);
  const maxGenerateMs = Math.max(Number(remote.max_generate_ms || 0), Number(local.max_generate_ms || 0));

  const checks = [
    check(
      'remote_candidate_runner_ok',
      remoteResult.exit_code === 0 && remoteResult.parsed === true && remote.ok === true,
      remoteResult.exit_code,
      0,
      'remote candidate runner must exit cleanly'
    ),
    check(
      'remote_candidate_readiness',
      remote.candidate_readiness?.ready === true,
      remote.candidate_readiness?.ready === true ? 1 : 0,
      1,
      'remote candidate readiness must be ready'
    ),
    check(
      'remote_candidate_min_audits',
      Number(remoteAudit.total || 0) >= config.minRemoteCandidateAudits,
      Number(remoteAudit.total || 0),
      config.minRemoteCandidateAudits,
      'remote candidate audits must cover the configured Generate requests'
    ),
    check(
      'remote_candidate_mismatch',
      remoteMismatch <= config.maxCandidateMismatches,
      remoteMismatch,
      config.maxCandidateMismatches,
      'remote selected model and route-kind mismatches must stay within threshold'
    ),
    check(
      'remote_candidate_fallback',
      remoteFallback <= config.maxCandidateFallbacks,
      remoteFallback,
      config.maxCandidateFallbacks,
      'remote Rust candidate fallbacks must stay within threshold'
    ),
    check(
      'remote_candidate_secret_leak',
      remoteSecretLeak === 0,
      remoteSecretLeak,
      0,
      'remote candidate audit must not include provider secrets'
    ),
    check(
      'local_candidate_runner_ok',
      localResult.exit_code === 0 && localResult.parsed === true && local.ok === true,
      localResult.exit_code,
      0,
      'local candidate runner must exit cleanly'
    ),
    check(
      'local_candidate_readiness',
      local.candidate_readiness?.ready === true,
      local.candidate_readiness?.ready === true ? 1 : 0,
      1,
      'local candidate readiness must be ready'
    ),
    check(
      'local_candidate_min_audits',
      Number(localAudit.total || 0) >= config.minLocalCandidateAudits,
      Number(localAudit.total || 0),
      config.minLocalCandidateAudits,
      'local candidate audits must cover the configured Generate requests'
    ),
    check(
      'local_candidate_mismatch',
      localMismatch <= config.maxCandidateMismatches,
      localMismatch,
      config.maxCandidateMismatches,
      'local selected model and route-kind mismatches must stay within threshold'
    ),
    check(
      'local_candidate_fallback',
      localFallback <= config.maxCandidateFallbacks,
      localFallback,
      config.maxCandidateFallbacks,
      'local Rust candidate fallbacks must stay within threshold'
    ),
    check(
      'local_candidate_secret_leak',
      localSecretLeak === 0,
      localSecretLeak,
      0,
      'local candidate audit must not include secret-shaped material'
    ),
    check(
      'combined_generate_latency_max_ms',
      maxGenerateMs <= config.maxGenerateMs,
      maxGenerateMs,
      config.maxGenerateMs,
      'remote and local Generate latency must stay within threshold'
    ),
  ];
  const ready = checks.every((item) => item.ok === true);
  return {
    schema_version: 'xhub.model_route_candidate_evidence_readiness.v1',
    component: 'model_route',
    decision: ready ? 'ready' : 'not_ready',
    ready,
    generated_at_ms: Date.now(),
    thresholds: {
      min_remote_candidate_audits: config.minRemoteCandidateAudits,
      min_local_candidate_audits: config.minLocalCandidateAudits,
      max_candidate_mismatches: config.maxCandidateMismatches,
      max_candidate_fallbacks: config.maxCandidateFallbacks,
      max_generate_ms: config.maxGenerateMs,
    },
    remote: {
      readiness_ready: remote.candidate_readiness?.ready === true,
      total: Number(remoteAudit.total || 0),
      model_mismatch: Number(remoteAudit.model_mismatch || 0),
      route_kind_mismatch: Number(remoteAudit.route_kind_mismatch || 0),
      fallback: remoteFallback,
      secret_leak: remoteSecretLeak,
      max_generate_ms: Number(remote.max_generate_ms || 0),
    },
    local: {
      readiness_ready: local.candidate_readiness?.ready === true,
      total: Number(localAudit.total || 0),
      model_mismatch: Number(localAudit.model_mismatch || 0),
      route_kind_mismatch: Number(localAudit.route_kind_mismatch || 0),
      fallback: localFallback,
      secret_leak: localSecretLeak,
      max_generate_ms: Number(local.max_generate_ms || 0),
    },
    checks,
  };
}

function buildReport({ config, readiness, remoteResult, localResult }) {
  return {
    schema_version: 'xhub.model_route_candidate_evidence_report.v1',
    generated_at_ms: Date.now(),
    component: 'model_route',
    production_authority_change: false,
    authority_mode: 'candidate_audit_only',
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
        candidate_audit_stats: auditStats(remoteResult.payload),
        candidate_readiness: remoteResult.payload?.candidate_readiness || null,
        max_generate_ms: Number(remoteResult.payload?.max_generate_ms || 0),
      },
      local: {
        schema_version: localResult.payload?.schema_version || '',
        ok: localResult.payload?.ok === true,
        candidate_audit_stats: auditStats(localResult.payload),
        candidate_readiness: localResult.payload?.candidate_readiness || null,
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
    console.log('model_route_candidate_evidence_runner self-test ok');
    return;
  }
  if (config.dryRun) {
    console.log(JSON.stringify({
      ok: true,
      schema_version: 'xhub.model_route_candidate_evidence_runner.dry_run.v1',
      config: publicConfig(config),
    }, null, 2));
    return;
  }

  console.log(JSON.stringify({
    event: 'start',
    schema_version: 'xhub.model_route_candidate_evidence_runner.event.v1',
    config: publicConfig(config),
  }));

  const remoteResult = runRunner(
    'remote_model_route_candidate',
    'model_route_generate_candidate_runner.command',
    [
      '--runs', String(config.remoteRuns),
      '--concurrency', String(config.concurrency),
      '--provider', config.provider,
      '--model-id', config.remoteModelId,
      '--expect-ready',
      '--min-candidate-audits', String(config.minRemoteCandidateAudits),
      '--max-candidate-mismatches', String(config.maxCandidateMismatches),
      '--max-candidate-fallbacks', String(config.maxCandidateFallbacks),
      '--max-generate-ms', String(config.maxGenerateMs),
      '--timeout-ms', String(config.timeoutMs),
    ],
    config.timeoutMs + 30000
  );

  const localResult = runRunner(
    'local_model_route_candidate',
    'model_route_local_candidate_runner.command',
    [
      '--runs', String(config.localRuns),
      '--concurrency', String(config.concurrency),
      '--model-id', config.localModelId,
      '--expect-ready',
      '--min-candidate-audits', String(config.minLocalCandidateAudits),
      '--max-candidate-mismatches', String(config.maxCandidateMismatches),
      '--max-candidate-fallbacks', String(config.maxCandidateFallbacks),
      '--max-generate-ms', String(config.maxGenerateMs),
      '--timeout-ms', String(config.timeoutMs),
    ],
    config.timeoutMs + 30000
  );

  const readiness = buildCombinedReadiness({ config, remoteResult, localResult });
  const report = buildReport({ config, readiness, remoteResult, localResult });
  const reportPath = writeJsonAtomic(config.reportPath, report);
  const ok = config.expectReady ? readiness.ready === true : true;
  const finalPayload = {
    event: 'stop',
    ok,
    schema_version: 'xhub.model_route_candidate_evidence_runner.result.v1',
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
  console.error(`[model_route_candidate_evidence_runner] ${error?.stack || error?.message || error}`);
  process.exit(1);
}
