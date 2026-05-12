#!/usr/bin/env node
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

function parseArgs(argv) {
  const out = {
    shadowRuns: 3,
    candidateRuns: 3,
    concurrency: 1,
    provider: 'openai',
    modelId: 'gpt-4o',
    timeoutMs: 30000,
    minCompareReports: 3,
    maxMismatches: 0,
    minCandidateAudits: 0,
    maxCandidateMismatches: 0,
    maxCandidateFallbacks: 0,
    maxGenerateMs: 3000,
    expectReady: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--shadow-runs':
        out.shadowRuns = parseIntInRange(next, out.shadowRuns, 1, 10000);
        i += 1;
        break;
      case '--candidate-runs':
        out.candidateRuns = parseIntInRange(next, out.candidateRuns, 1, 10000);
        i += 1;
        break;
      case '--concurrency':
        out.concurrency = parseIntInRange(next, out.concurrency, 1, 64);
        i += 1;
        break;
      case '--provider':
        out.provider = safeString(next) || out.provider;
        i += 1;
        break;
      case '--model-id':
        out.modelId = safeString(next) || out.modelId;
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 1000, 300000);
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
      case '--min-candidate-audits':
        out.minCandidateAudits = parseIntInRange(next, out.minCandidateAudits, 0, 1000000);
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
  if (out.minCandidateAudits <= 0) {
    out.minCandidateAudits = out.candidateRuns * out.concurrency;
  }
  return out;
}

function usage() {
  return [
    'provider_route_cutover_readiness_runner.js',
    '',
    'Options:',
    '  --shadow-runs <n>              Provider shadow compare iterations, default 3',
    '  --candidate-runs <n>           Generate candidate audit batches, default 3',
    '  --concurrency <n>              Generate concurrency per candidate batch, default 1',
    '  --provider <id>                Provider, default openai',
    '  --model-id <id>                Model ID, default gpt-4o',
    '  --min-compare-reports <n>      Provider readiness minimum reports, default 3',
    '  --max-mismatches <n>           Provider readiness mismatch threshold, default 0',
    '  --min-candidate-audits <n>     Candidate readiness minimum audits, default candidate-runs * concurrency',
    '  --max-candidate-mismatches <n> Candidate account mismatch threshold, default 0',
    '  --max-candidate-fallbacks <n>  Candidate fallback threshold, default 0',
    '  --max-generate-ms <n>          Generate hot-path latency gate, default 3000',
    '  --expect-ready                 Exit non-zero unless combined readiness is ready',
    '  --dry-run                      Print resolved config',
    '  --self-test                    Run parser self-test',
  ].join('\n');
}

function publicConfig(config) {
  return {
    shadow_runs: config.shadowRuns,
    candidate_runs: config.candidateRuns,
    concurrency: config.concurrency,
    provider: config.provider,
    model_id: config.modelId,
    timeout_ms: config.timeoutMs,
    min_compare_reports: config.minCompareReports,
    max_mismatches: config.maxMismatches,
    min_candidate_audits: config.minCandidateAudits,
    max_candidate_mismatches: config.maxCandidateMismatches,
    max_candidate_fallbacks: config.maxCandidateFallbacks,
    max_generate_ms: config.maxGenerateMs,
    expect_ready: config.expectReady,
    rust_hub_root: ROOT_DIR,
  };
}

function runSelfTest() {
  const parsed = parseArgs([
    '--shadow-runs', '4',
    '--candidate-runs', '2',
    '--concurrency', '3',
    '--expect-ready',
  ]);
  if (
    parsed.shadowRuns !== 4
    || parsed.candidateRuns !== 2
    || parsed.concurrency !== 3
    || parsed.minCandidateAudits !== 6
    || parsed.expectReady !== true
  ) {
    throw new Error('self-test parser failed');
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
      maxBuffer: 16 * 1024 * 1024,
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

function buildCombinedReadiness({ config, shadowResult, candidateResult }) {
  const shadow = shadowResult.payload || {};
  const candidate = candidateResult.payload || {};
  const shadowReadiness = shadow.readiness_after || {};
  const reportsAdded = shadow.reports_added || {};
  const authorityPrep = shadow.authority_prep || {};
  const mismatchProbe = authorityPrep.mismatch_probe || {};
  const serviceHook = authorityPrep.service_hook || {};
  const candidateReadiness = candidate.candidate_readiness || {};
  const candidateAudit = candidate.candidate_audit_stats || candidateReadiness.audit || {};

  const checks = [
    check(
      'provider_shadow_runner_ok',
      shadowResult.exit_code === 0 && shadow.ok === true,
      shadowResult.exit_code,
      0,
      'provider shadow compare runner must exit cleanly'
    ),
    check(
      'provider_shadow_readiness',
      shadowReadiness.ready === true,
      shadowReadiness.ready === true ? 1 : 0,
      1,
      'provider route shadow readiness must be ready'
    ),
    check(
      'provider_shadow_min_reports',
      Number(reportsAdded.total || 0) >= config.minCompareReports,
      Number(reportsAdded.total || 0),
      config.minCompareReports,
      'provider shadow compare must add enough evidence'
    ),
    check(
      'provider_shadow_mismatches',
      Number(reportsAdded.mismatched || 0) <= config.maxMismatches,
      Number(reportsAdded.mismatched || 0),
      config.maxMismatches,
      'provider shadow compare mismatches must stay within threshold'
    ),
    check(
      'provider_authority_prep_same_account',
      authorityPrep.selected === true && authorityPrep.fallback !== true,
      authorityPrep.selected_account_key || '',
      'selected',
      'readiness-gated authority prep must select the same account'
    ),
    check(
      'provider_authority_mismatch_gate',
      mismatchProbe.fallback === true
        && mismatchProbe.mismatch === true
        && mismatchProbe.error_code === 'rust_provider_route_authority_account_mismatch',
      mismatchProbe.error_code || '',
      'rust_provider_route_authority_account_mismatch',
      'authority prep must fail closed on Node/Rust account mismatch'
    ),
    check(
      'provider_authority_service_hook',
      serviceHook.response_preserved === true
        && serviceHook.selected === true
        && serviceHook.fallback !== true
        && Number(serviceHook.completed || 0) >= 1
        && Number(serviceHook.failed || 0) === 0,
      serviceHook.selected_account_key || '',
      'selected',
      'GetProviderKeyRouteDecision service hook must trigger prep without changing the Node response'
    ),
    check(
      'candidate_runner_ok',
      candidateResult.exit_code === 0 && candidate.ok === true,
      candidateResult.exit_code,
      0,
      'Generate candidate audit runner must exit cleanly'
    ),
    check(
      'candidate_readiness',
      candidateReadiness.ready === true,
      candidateReadiness.ready === true ? 1 : 0,
      1,
      'Generate candidate audit readiness must be ready'
    ),
    check(
      'candidate_min_audits',
      Number(candidateAudit.total || 0) >= config.minCandidateAudits,
      Number(candidateAudit.total || 0),
      config.minCandidateAudits,
      'candidate audit must cover enough Generate requests'
    ),
    check(
      'candidate_account_mismatches',
      Number(candidateAudit.account_mismatch || 0) <= config.maxCandidateMismatches,
      Number(candidateAudit.account_mismatch || 0),
      config.maxCandidateMismatches,
      'candidate Node/Rust account mismatches must stay within threshold'
    ),
    check(
      'candidate_fallbacks',
      Number(candidateAudit.fallback || 0) <= config.maxCandidateFallbacks,
      Number(candidateAudit.fallback || 0),
      config.maxCandidateFallbacks,
      'candidate Rust route fallbacks must stay within threshold'
    ),
    check(
      'candidate_secret_leak',
      Number(candidateAudit.secret_leak || 0) === 0,
      Number(candidateAudit.secret_leak || 0),
      0,
      'candidate audit ext must not include provider secrets'
    ),
    check(
      'generate_latency_max_ms',
      Number(candidate.max_generate_ms || 0) <= config.maxGenerateMs,
      Number(candidate.max_generate_ms || 0),
      config.maxGenerateMs,
      'Generate hot-path latency must stay within threshold'
    ),
  ];

  const ready = checks.every((item) => item.ok === true);
  return {
    schema_version: 'xhub.provider_route_cutover_readiness.v1',
    component: 'provider_route',
    decision: ready ? 'ready' : 'not_ready',
    ready,
    generated_at_ms: Date.now(),
    thresholds: {
      min_compare_reports: config.minCompareReports,
      max_mismatches: config.maxMismatches,
      min_candidate_audits: config.minCandidateAudits,
      max_candidate_mismatches: config.maxCandidateMismatches,
      max_candidate_fallbacks: config.maxCandidateFallbacks,
      max_generate_ms: config.maxGenerateMs,
    },
    provider_shadow: {
      reports_added: reportsAdded,
      readiness_ready: shadowReadiness.ready === true,
      authority_prep_selected: authorityPrep.selected === true,
      authority_prep_fallback: authorityPrep.fallback === true,
      mismatch_gate_ok: checks.find((item) => item.name === 'provider_authority_mismatch_gate')?.ok === true,
      service_hook_ok: checks.find((item) => item.name === 'provider_authority_service_hook')?.ok === true,
    },
    candidate_audit: {
      readiness_ready: candidateReadiness.ready === true,
      total: Number(candidateAudit.total || 0),
      account_mismatch: Number(candidateAudit.account_mismatch || 0),
      fallback: Number(candidateAudit.fallback || 0),
      secret_leak: Number(candidateAudit.secret_leak || 0),
      max_generate_ms: Number(candidate.max_generate_ms || 0),
    },
    checks,
  };
}

function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    console.log(usage());
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    console.log('provider_route_cutover_readiness_runner self-test ok');
    return;
  }
  if (config.dryRun) {
    console.log(JSON.stringify({
      ok: true,
      schema_version: 'xhub.provider_route_cutover_readiness_runner.dry_run.v1',
      config: publicConfig(config),
    }, null, 2));
    return;
  }

  console.log(JSON.stringify({
    event: 'start',
    schema_version: 'xhub.provider_route_cutover_readiness_runner.event.v1',
    config: publicConfig(config),
  }));

  const shadowResult = runRunner(
    'provider_shadow_compare',
    'provider_route_shadow_compare_runner.command',
    [
      '--runs', String(config.shadowRuns),
      '--provider', config.provider,
      '--model-id', config.modelId,
      '--min-compare-reports', String(config.minCompareReports),
      '--max-mismatches', String(config.maxMismatches),
      '--expect-ready',
      '--expect-zero-mismatch',
      '--continue-after-ready',
      '--timeout-ms', String(config.timeoutMs),
    ],
    config.timeoutMs + 30000
  );

  const candidateResult = runRunner(
    'provider_candidate_audit',
    'provider_route_generate_observe_runner.command',
    [
      '--runs', String(config.candidateRuns),
      '--concurrency', String(config.concurrency),
      '--provider', config.provider,
      '--model-id', config.modelId,
      '--enable-candidate-audit',
      '--expect-candidate-ready',
      '--min-candidate-audits', String(config.minCandidateAudits),
      '--max-candidate-mismatches', String(config.maxCandidateMismatches),
      '--max-candidate-fallbacks', String(config.maxCandidateFallbacks),
      '--observe-throttle-ms', '0',
      '--observe-max-in-flight', String(Math.max(2, Math.min(16, config.concurrency * 2))),
      '--max-generate-ms', String(config.maxGenerateMs),
      '--timeout-ms', String(config.timeoutMs),
    ],
    config.timeoutMs + 30000
  );

  const readiness = buildCombinedReadiness({ config, shadowResult, candidateResult });
  const ok = config.expectReady ? readiness.ready === true : true;
  const finalPayload = {
    event: 'stop',
    ok,
    schema_version: 'xhub.provider_route_cutover_readiness_runner.result.v1',
    readiness,
    provider_shadow_runner: {
      exit_code: shadowResult.exit_code,
      parsed: shadowResult.parsed,
      parse_error: shadowResult.parse_error,
      stderr: shadowResult.stderr,
    },
    candidate_audit_runner: {
      exit_code: candidateResult.exit_code,
      parsed: candidateResult.parsed,
      parse_error: candidateResult.parse_error,
      stderr: candidateResult.stderr,
    },
  };
  console.log(JSON.stringify(finalPayload, null, 2));
  if (!ok) process.exitCode = 2;
}

try {
  main();
} catch (error) {
  console.error(`[provider_route_cutover_readiness_runner] ${error?.stack || error?.message || error}`);
  process.exit(1);
}
