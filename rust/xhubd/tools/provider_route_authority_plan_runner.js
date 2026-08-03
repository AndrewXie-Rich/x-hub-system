#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const MIN_PROVIDER_SHADOW_COMPARE_REPORTS = 10;
const INNER_FAILURE_SCHEMA = 'xhub.route_authority.inner_failure.v1';

function safeString(value) {
  return String(value ?? '').trim();
}

function redactDiagnosticText(value) {
  const original = String(value ?? '');
  const redacted = original
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, 'Bearer [REDACTED]')
    .replace(/(X-XHub-Access-Key\s*[:=]\s*)[A-Za-z0-9._~+/=-]+/gi, '$1[REDACTED]')
    .replace(/(XHUB_[A-Z0-9_]*ACCESS_KEY\s*=\s*)[^\s]+/gi, '$1[REDACTED]')
    .replace(/("?(?:api_key|access_key|token|secret)"?\s*[:=]\s*")([^"\n]+)(")/gi, '$1[REDACTED]$3')
    .replace(/([?&](?:api_key|access_key|access_token|token|key)=)[^&\s]+/gi, '$1[REDACTED]')
    .replace(/\bsk-[A-Za-z0-9][A-Za-z0-9_-]{12,}\b/g, 'sk-[REDACTED]')
    .replace(/\b[a-f0-9]{48,128}\b/gi, '[REDACTED_HEX]');
  return { text: redacted, redaction_applied: redacted !== original };
}

function boundedDiagnostic(value, maxChars = 2000, maxLines = 20) {
  const redacted = redactDiagnosticText(value);
  const lines = redacted.text.split(/\r?\n/).slice(-maxLines).join('\n');
  return {
    text: lines.slice(-maxChars),
    redaction_applied: redacted.redaction_applied,
  };
}

function innerFailureKind(exitCode, parsed, decision) {
  if (exitCode !== 0 && exitCode !== 2) return 'execution_failed';
  if (!parsed) return 'output_not_parseable';
  if (exitCode === 2 || decision === 'not_ready') return 'not_ready';
  return 'contract_failed';
}

function innerFailure({
  component,
  stage,
  parentStage,
  exitCode,
  parsed,
  decision,
  parseError,
  stderr,
  failedChecks,
}) {
  const parseDiagnostic = boundedDiagnostic(parseError, 500, 5);
  const stderrDiagnostic = boundedDiagnostic(stderr, 2000, 20);
  return {
    schema_version: INNER_FAILURE_SCHEMA,
    component: safeString(component).slice(0, 64),
    stage: safeString(stage).slice(0, 128),
    parent_stage: safeString(parentStage).slice(0, 128),
    kind: innerFailureKind(Number(exitCode ?? -1), parsed === true, safeString(decision)),
    exit_code: Number(exitCode ?? -1),
    parsed: parsed === true,
    decision: safeString(decision).slice(0, 128),
    parse_error: parseDiagnostic.text,
    stderr_tail: stderrDiagnostic.text,
    failed_checks: Array.isArray(failedChecks)
      ? failedChecks.map((value) => safeString(value).slice(0, 128)).filter(Boolean).slice(0, 32)
      : [],
    diagnostic_redaction_applied: parseDiagnostic.redaction_applied || stderrDiagnostic.redaction_applied,
  };
}

function failedReadinessChecks(readiness, prefix = '') {
  const checks = Array.isArray(readiness?.checks) ? readiness.checks : [];
  return checks
    .filter((item) => item?.ok !== true && (!prefix || safeString(item?.name).startsWith(prefix)))
    .map((item) => safeString(item?.name))
    .filter(Boolean);
}

function collectProviderInnerFailures(readinessResult) {
  const payload = readinessResult?.payload || {};
  const readiness = payload?.readiness || {};
  const failures = [];
  const childStages = [
    ['provider_shadow_runner', 'provider_shadow'],
    ['candidate_audit_runner', 'candidate_'],
  ];
  for (const [stage, checkPrefix] of childStages) {
    const child = payload?.[stage];
    if (!child) continue;
    const exitCode = Number(child?.exit_code ?? -1);
    const parsed = child?.parsed === true;
    if (exitCode === 0 && parsed) continue;
    failures.push(innerFailure({
      component: 'provider_route',
      stage,
      parentStage: 'provider_cutover_readiness_runner',
      exitCode,
      parsed,
      decision: safeString(readiness?.decision) || 'not_ready',
      parseError: child?.parse_error,
      stderr: child?.stderr || child?.stderr_tail,
      failedChecks: failedReadinessChecks(readiness, checkPrefix),
    }));
  }
  const runnerExitCode = Number(readinessResult?.exit_code ?? -1);
  const runnerParsed = readinessResult?.parsed === true;
  if ((!runnerParsed || runnerExitCode !== 0 || readiness?.ready !== true) && failures.length === 0) {
    failures.push(innerFailure({
      component: 'provider_route',
      stage: 'provider_cutover_readiness_runner',
      parentStage: 'provider_route_authority_plan_runner',
      exitCode: runnerExitCode,
      parsed: runnerParsed,
      decision: safeString(readiness?.decision) || 'not_ready',
      parseError: readinessResult?.parse_error,
      stderr: readinessResult?.stderr,
      failedChecks: failedReadinessChecks(readiness),
    }));
  }
  return failures;
}

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    shadowRuns: MIN_PROVIDER_SHADOW_COMPARE_REPORTS,
    candidateRuns: 3,
    concurrency: 1,
    provider: 'openai',
    modelId: 'gpt-4o',
    timeoutMs: 30000,
    minCompareReports: MIN_PROVIDER_SHADOW_COMPARE_REPORTS,
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
        out.shadowRuns = parseIntInRange(
          next,
          out.shadowRuns,
          MIN_PROVIDER_SHADOW_COMPARE_REPORTS,
          10000,
        );
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
        out.minCompareReports = parseIntInRange(
          next,
          out.minCompareReports,
          MIN_PROVIDER_SHADOW_COMPARE_REPORTS,
          1000000,
        );
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
    'provider_route_authority_plan_runner.js',
    '',
    'Options:',
    '  --shadow-runs <n>              Provider shadow compare iterations, default/minimum 10',
    '  --candidate-runs <n>           Generate candidate audit batches, default 3',
    '  --concurrency <n>              Generate concurrency per candidate batch, default 1',
    '  --provider <id>                Provider, default openai',
    '  --model-id <id>                Model ID, default gpt-4o',
    '  --min-compare-reports <n>      Provider readiness minimum reports, default/minimum 10',
    '  --max-mismatches <n>           Provider readiness mismatch threshold, default 0',
    '  --min-candidate-audits <n>     Candidate readiness minimum audits, default candidate-runs * concurrency',
    '  --max-candidate-mismatches <n> Candidate account mismatch threshold, default 0',
    '  --max-candidate-fallbacks <n>  Candidate fallback threshold, default 0',
    '  --max-generate-ms <n>          Generate hot-path latency gate, default 3000',
    '  --expect-ready                 Exit non-zero unless dry-run authority plan is ready',
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
  const defaults = parseArgs([]);
  if (defaults.shadowRuns !== MIN_PROVIDER_SHADOW_COMPARE_REPORTS) {
    throw new Error('provider shadow run default failed');
  }
  if (defaults.minCompareReports !== MIN_PROVIDER_SHADOW_COMPARE_REPORTS) {
    throw new Error('provider compare threshold default failed');
  }
  const parsed = parseArgs([
    '--shadow-runs', '5',
    '--candidate-runs', '2',
    '--concurrency', '2',
    '--min-compare-reports', '3',
    '--max-generate-ms', '2500',
    '--expect-ready',
  ]);
  if (
    parsed.shadowRuns !== MIN_PROVIDER_SHADOW_COMPARE_REPORTS
    || parsed.candidateRuns !== 2
    || parsed.concurrency !== 2
    || parsed.minCompareReports !== MIN_PROVIDER_SHADOW_COMPARE_REPORTS
    || parsed.minCandidateAudits !== 4
    || parsed.maxGenerateMs !== 2500
    || parsed.expectReady !== true
  ) {
    throw new Error('self-test parser failed');
  }
  const plan = buildAuthorityPlan({
    config: parsed,
    readinessResult: {
      exit_code: 0,
      parsed: true,
      payload: {
        ok: true,
        readiness: {
          ready: true,
          decision: 'ready',
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
  if (!Array.isArray(plan.inner_failures) || plan.inner_failures.length !== 0) {
    throw new Error('self-test ready plan must not report inner failures');
  }
  const secret = 'sk-provider-inner-failure-secret-1234567890';
  const failedPlan = buildAuthorityPlan({
    config: parsed,
    readinessResult: {
      exit_code: 2,
      parsed: true,
      payload: {
        ok: false,
        readiness: {
          ready: false,
          decision: 'not_ready',
          checks: [{ name: 'provider_shadow_runner_ok', ok: false }],
        },
        provider_shadow_runner: {
          exit_code: 1,
          parsed: false,
          parse_error: 'runner output did not contain a parseable final JSON object',
          stderr: `Error [ERR_MODULE_NOT_FOUND]: missing js-yaml Bearer ${secret}`,
        },
      },
      stderr: '',
      parse_error: '',
    },
  });
  const failure = failedPlan.inner_failures?.[0];
  if (
    failedPlan.ready !== false
    || failure?.stage !== 'provider_shadow_runner'
    || failure?.kind !== 'execution_failed'
    || !failure?.stderr_tail.includes('ERR_MODULE_NOT_FOUND')
    || failure?.stderr_tail.includes(secret)
    || failure?.diagnostic_redaction_applied !== true
  ) {
    throw new Error('self-test provider inner failure propagation or redaction failed');
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

function runCutoverReadiness(config) {
  const filePath = path.join(SCRIPT_DIR, 'provider_route_cutover_readiness_runner.command');
  const args = [
    '--shadow-runs', String(config.shadowRuns),
    '--candidate-runs', String(config.candidateRuns),
    '--concurrency', String(config.concurrency),
    '--provider', config.provider,
    '--model-id', config.modelId,
    '--min-compare-reports', String(config.minCompareReports),
    '--max-mismatches', String(config.maxMismatches),
    '--min-candidate-audits', String(config.minCandidateAudits),
    '--max-candidate-mismatches', String(config.maxCandidateMismatches),
    '--max-candidate-fallbacks', String(config.maxCandidateFallbacks),
    '--max-generate-ms', String(config.maxGenerateMs),
    '--timeout-ms', String(config.timeoutMs),
  ];
  let stdout = '';
  let stderr = '';
  let exitCode = 0;
  try {
    stdout = execFileSync(filePath, args, {
      encoding: 'utf8',
      timeout: config.timeoutMs + 90000,
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
    exit_code: exitCode,
    parsed: !!payload,
    parse_error: parseError,
    payload,
    stderr,
  };
}

function check(name, ok, actual, threshold, detail) {
  return { name, ok: ok === true, actual, threshold, detail };
}

function envRow(name, value, reason) {
  return { name, value, reason };
}

function buildAuthorityPlan({ config, readinessResult }) {
  const readinessPayload = readinessResult.payload || {};
  const readiness = readinessPayload.readiness || {};
  const readinessReady = readiness.ready === true;
  const runnerOk = readinessResult.exit_code === 0 && readinessResult.parsed === true;
  const checks = [
    check(
      'cutover_readiness_runner_ok',
      runnerOk,
      readinessResult.exit_code,
      0,
      'combined provider cutover readiness runner must complete and parse'
    ),
    check(
      'cutover_readiness_ready',
      readinessReady,
      readinessReady ? 1 : 0,
      1,
      'combined provider cutover readiness must be ready before any authority prep trial'
    ),
    check(
      'production_authority_disabled',
      true,
      0,
      0,
      'this plan is dry-run only and does not enable production provider route authority'
    ),
    check(
      'node_match_gate_required',
      true,
      1,
      1,
      'any authority prep trial must keep Node/Rust selected account matching fail-closed'
    ),
  ];
  const ready = checks.every((item) => item.ok === true);
  const innerFailures = collectProviderInnerFailures(readinessResult);
  const requiredEnv = [
    envRow('XHUB_RUST_HUB_ROOT', ROOT_DIR, 'point Node Hub bridges at this Rust Hub package'),
    envRow('XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP', '1', 'enable readiness-gated Rust route calculation for prep calls only'),
    envRow('XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_THROTTLE_MS', '1000', 'throttle repeated prep service-hook checks for the same provider/model/runtime route'),
    envRow('XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_MAX_IN_FLIGHT', '2', 'cap concurrent Rust prep route checks from the Node service hook'),
    envRow('XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP', '1', 'prefer a warm xhubd /provider/route daemon when available'),
    envRow('XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL', 'http://127.0.0.1:50151', 'default local xhubd serve HTTP endpoint for provider route checks'),
    envRow('XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_TIMEOUT_MS', '750', 'keep daemon route attempts short so Node can fall back quickly'),
    envRow('XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI', '1', 'fall back to the existing CLI route path if the daemon is unavailable'),
    envRow('XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY', '1', 'fail closed unless provider route readiness is ready'),
    envRow('XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH', '1', 'fallback if Rust selects a different account than Node'),
    envRow('XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS', String(config.minCompareReports), 'keep the same shadow evidence threshold used by this plan'),
    envRow('XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MAX_MISMATCHES', String(config.maxMismatches), 'keep the same mismatch threshold used by this plan'),
    envRow('XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE', '1', 'continue Generate hot-path candidate audit evidence while testing prep'),
    envRow('XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS', '250', 'reuse identical candidate route checks briefly to reduce Generate hot-path Rust CLI churn'),
    envRow('XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MAX_ENTRIES', '128', 'bound the candidate route cache size in the Node bridge'),
  ];
  const rollbackEnv = [
    'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP',
    'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_THROTTLE_MS',
    'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_MAX_IN_FLIGHT',
    'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP',
    'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL',
    'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_TIMEOUT_MS',
    'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI',
    'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE',
    'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS',
    'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MAX_ENTRIES',
    'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE',
    'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY',
    'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH',
  ];
  return {
    schema_version: 'xhub.provider_route_authority_dry_run_plan.v1',
    component: 'provider_route',
    mode: 'dry_run_only',
    decision: ready ? 'ready_for_manual_prep_trial' : 'not_ready',
    ready,
    generated_at_ms: Date.now(),
    provider: config.provider,
    model_id: config.modelId,
    production_authority_change: false,
    node_remains_provider_authority: true,
    production_cutover_implemented: false,
    rust_can_prepare_route_decision: ready,
    readiness_summary: {
      runner_ok: runnerOk,
      ready: readinessReady,
      decision: safeString(readiness.decision),
      schema_version: safeString(readiness.schema_version),
      provider_shadow: readiness.provider_shadow || null,
      candidate_audit: readiness.candidate_audit || null,
    },
    inner_failures: innerFailures,
    inner_failure_count: innerFailures.length,
    required_env_for_manual_prep_trial: ready ? requiredEnv : [],
    env_to_unset_for_rollback: rollbackEnv,
    blocked_until_explicit_future_cutover: [
      'do not make Rust provider route output construct Bridge provider_key payloads',
      'do not remove Node-selected account match gate',
      'do not treat authority prep as production routing authority',
      'do not persist or expose provider API keys in Rust candidate/prep outputs',
    ],
    manual_validation_commands: [
      `bash "${path.join(ROOT_DIR, 'tools', 'provider_route_cutover_readiness_runner.command')}" --shadow-runs ${config.shadowRuns} --candidate-runs ${config.candidateRuns} --expect-ready`,
      `bash "${path.join(ROOT_DIR, 'tools', 'provider_route_generate_observe_runner.command')}" --runs ${config.candidateRuns} --concurrency ${config.concurrency} --enable-candidate-audit --expect-candidate-ready --min-candidate-audits ${config.minCandidateAudits}`,
    ],
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
    console.log('provider_route_authority_plan_runner self-test ok');
    return;
  }
  if (config.dryRun) {
    console.log(JSON.stringify({
      ok: true,
      schema_version: 'xhub.provider_route_authority_plan_runner.dry_run.v1',
      config: publicConfig(config),
    }, null, 2));
    return;
  }

  console.log(JSON.stringify({
    event: 'start',
    schema_version: 'xhub.provider_route_authority_plan_runner.event.v1',
    config: publicConfig(config),
  }));

  const readinessResult = runCutoverReadiness(config);
  const plan = buildAuthorityPlan({ config, readinessResult });
  const ok = config.expectReady ? plan.ready === true : true;
  const readinessStderr = boundedDiagnostic(readinessResult.stderr, 2000, 20);
  const readinessParseError = boundedDiagnostic(readinessResult.parse_error, 500, 5);
  const finalPayload = {
    event: 'stop',
    ok,
    schema_version: 'xhub.provider_route_authority_plan_runner.result.v1',
    plan,
    inner_failures: plan.inner_failures,
    inner_failure_count: plan.inner_failure_count,
    cutover_readiness_runner: {
      exit_code: readinessResult.exit_code,
      parsed: readinessResult.parsed,
      parse_error: readinessParseError.text,
      stderr: readinessStderr.text,
      stderr_tail: readinessStderr.text,
      diagnostic_redaction_applied: readinessParseError.redaction_applied
        || readinessStderr.redaction_applied,
    },
  };
  console.log(JSON.stringify(finalPayload, null, 2));
  if (!ok) process.exitCode = 2;
}

try {
  main();
} catch (error) {
  console.error(`[provider_route_authority_plan_runner] ${error?.stack || error?.message || error}`);
  process.exit(1);
}
