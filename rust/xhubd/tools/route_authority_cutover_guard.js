#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const REPORT_DIR = path.join(ROOT_DIR, 'reports');

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    providerShadowRuns: 3,
    providerCandidateRuns: 3,
    modelRemoteRuns: 1,
    modelLocalRuns: 1,
    concurrency: 1,
    provider: 'openai',
    providerModelId: 'gpt-4o',
    providerMinCompareReports: null,
    remoteModelId: 'gpt-5.5',
    localModelId: 'local.summary',
    timeoutMs: 45000,
    maxGenerateMs: 3000,
    rustHubRoot: ROOT_DIR,
    schedulerGateMode: 'ready',
    allowMemorySkillsProduction: false,
    requireMemorySkillsProduction: false,
    writeReport: true,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--provider-shadow-runs':
        out.providerShadowRuns = parseIntInRange(next, out.providerShadowRuns, 1, 10000);
        i += 1;
        break;
      case '--provider-candidate-runs':
        out.providerCandidateRuns = parseIntInRange(next, out.providerCandidateRuns, 1, 10000);
        i += 1;
        break;
      case '--model-remote-runs':
        out.modelRemoteRuns = parseIntInRange(next, out.modelRemoteRuns, 1, 10000);
        i += 1;
        break;
      case '--model-local-runs':
        out.modelLocalRuns = parseIntInRange(next, out.modelLocalRuns, 1, 10000);
        i += 1;
        break;
      case '--concurrency':
        out.concurrency = parseIntInRange(next, out.concurrency, 1, 64);
        i += 1;
        break;
      case '--provider':
        out.provider = String(next || '').trim() || out.provider;
        i += 1;
        break;
      case '--provider-model-id':
        out.providerModelId = String(next || '').trim() || out.providerModelId;
        i += 1;
        break;
      case '--provider-min-compare-reports':
        out.providerMinCompareReports = parseIntInRange(next, 0, 0, 1000000);
        i += 1;
        break;
      case '--remote-model-id':
        out.remoteModelId = String(next || '').trim() || out.remoteModelId;
        i += 1;
        break;
      case '--local-model-id':
        out.localModelId = String(next || '').trim() || out.localModelId;
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 1000, 300000);
        i += 1;
        break;
      case '--max-generate-ms':
        out.maxGenerateMs = parseIntInRange(next, out.maxGenerateMs, 100, 300000);
        i += 1;
        break;
      case '--rust-hub-root':
        out.rustHubRoot = String(next || '').trim() || out.rustHubRoot;
        i += 1;
        break;
      case '--scheduler-gate-mode':
        out.schedulerGateMode = String(next || '').trim() || out.schedulerGateMode;
        if (!['ready', 'applied', 'skip'].includes(out.schedulerGateMode)) {
          throw new Error(`invalid --scheduler-gate-mode: ${out.schedulerGateMode}`);
        }
        i += 1;
        break;
      case '--allow-memory-skills-production':
        out.allowMemorySkillsProduction = true;
        break;
      case '--require-memory-skills-production':
        out.allowMemorySkillsProduction = true;
        out.requireMemorySkillsProduction = true;
        break;
      case '--no-report':
        out.writeReport = false;
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
  if (out.providerMinCompareReports === null) {
    out.providerMinCompareReports = out.providerShadowRuns;
  }
  return out;
}

function usage() {
  return [
    'route_authority_cutover_guard.js',
    '',
    'Options:',
    '  --provider-shadow-runs <n>       Provider shadow compare runs, default 3',
    '  --provider-candidate-runs <n>    Provider candidate runs, default 3',
    '  --model-remote-runs <n>          Model remote candidate runs, default 1',
    '  --model-local-runs <n>           Model local candidate runs, default 1',
    '  --concurrency <n>                Candidate concurrency, default 1',
    '  --provider <id>                  Provider, default openai',
    '  --provider-model-id <id>         Provider route model, default gpt-4o',
    '  --provider-min-compare-reports <n> Provider readiness minimum reports, default provider-shadow-runs',
    '  --remote-model-id <id>           Remote model route model, default gpt-5.5',
    '  --local-model-id <id>            Local model route model, default local.summary',
    '  --timeout-ms <n>                 Runner timeout, default 45000',
    '  --max-generate-ms <n>            Generate latency budget, default 3000',
    '  --rust-hub-root <p>              Expected active Rust Hub root for scheduler guard',
    '  --scheduler-gate-mode <mode>     ready|applied|skip, default ready',
    '  --allow-memory-skills-production Permit explicit Rust memory writer and skills execution authority',
    '  --require-memory-skills-production Require both Rust memory writer and skills execution authority',
    '  --no-report                      Print only; do not write reports/',
    '  --self-test                      Validate reducer logic',
  ].join('\n');
}

function memorySkillsArgs(config) {
  if (config.requireMemorySkillsProduction) return ['--require-memory-skills-production'];
  if (config.allowMemorySkillsProduction) return ['--allow-memory-skills-production'];
  return [];
}

function runJson(command, args, timeoutMs) {
  let output = '';
  let stderr = '';
  let exitCode = 0;
  try {
    output = execFileSync(command, args, {
      cwd: ROOT_DIR,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: timeoutMs,
      maxBuffer: 32 * 1024 * 1024,
    });
  } catch (error) {
    output = String(error.stdout || '');
    stderr = String(error.stderr || error.message || '').slice(0, 4000);
    exitCode = Number(error.status || 1);
  }
  let payload = null;
  let parseError = '';
  try {
    payload = parseLastJsonObject(output);
  } catch (error) {
    parseError = String(error.message || error);
  }
  return {
    ok: exitCode === 0 && !!payload,
    exit_code: exitCode,
    parsed: !!payload,
    parse_error: parseError,
    stderr,
    payload,
  };
}

function parseLastJsonObject(stdout) {
  const text = String(stdout || '').trim();
  const starts = [];
  for (let i = 0; i < text.length; i += 1) {
    if (text[i] === '{') starts.push(i);
  }
  for (let i = starts.length - 1; i >= 0; i -= 1) {
    try {
      return JSON.parse(text.slice(starts[i]));
    } catch {
      // Continue scanning earlier JSON object starts.
    }
  }
  throw new Error('no parseable JSON object in command output');
}

function collect(config) {
  let schedulerGuard = null;
  let schedulerPlan = null;
  if (config.schedulerGateMode !== 'skip') {
    schedulerGuard = runJson('bash', [
      path.join(SCRIPT_DIR, 'scheduler_production_authority_guard.command'),
      '--no-report',
      '--rust-hub-root',
      config.rustHubRoot,
      ...memorySkillsArgs(config),
    ], 60000);
    if (config.schedulerGateMode === 'ready' && schedulerGuard?.payload?.ok !== true) {
      schedulerPlan = runJson('bash', [
        path.join(SCRIPT_DIR, 'scheduler_production_authority_plan.command'),
        '--run-gates',
        '--expect-ready',
      ], 420000);
    }
  }
  const providerPlan = runJson('bash', [
    path.join(SCRIPT_DIR, 'provider_route_authority_plan_runner.command'),
    '--shadow-runs', String(config.providerShadowRuns),
    '--candidate-runs', String(config.providerCandidateRuns),
    '--concurrency', String(config.concurrency),
    '--provider', config.provider,
    '--model-id', config.providerModelId,
    '--min-compare-reports', String(config.providerMinCompareReports),
    '--max-generate-ms', String(config.maxGenerateMs),
    '--timeout-ms', String(config.timeoutMs),
    '--expect-ready',
  ], config.timeoutMs + 120000);
  const modelPlan = runJson('bash', [
    path.join(SCRIPT_DIR, 'model_route_authority_plan_runner.command'),
    '--remote-runs', String(config.modelRemoteRuns),
    '--local-runs', String(config.modelLocalRuns),
    '--concurrency', String(config.concurrency),
    '--provider', config.provider,
    '--remote-model-id', config.remoteModelId,
    '--local-model-id', config.localModelId,
    '--max-generate-ms', String(config.maxGenerateMs),
    '--timeout-ms', String(config.timeoutMs),
    '--expect-ready',
  ], config.timeoutMs + 120000);
  const productionBlocker = runJson('bash', [
    path.join(SCRIPT_DIR, 'route_authority_production_cutover_blocker.command'),
    '--rust-hub-root',
    config.rustHubRoot,
    '--skip-prep-sustained',
    '--no-report',
  ], 30000);
  return { schedulerGuard, schedulerPlan, providerPlan, modelPlan, productionBlocker };
}

function reduce(collected, config) {
  const schedulerPayload = collected.schedulerGuard?.payload || {};
  const schedulerPlanPayload = collected.schedulerPlan?.payload || {};
  const providerPayload = collected.providerPlan?.payload || {};
  const modelPayload = collected.modelPlan?.payload || {};
  const blockerPayload = collected.productionBlocker?.payload || {};
  const providerReady = providerPayload?.plan?.ready === true;
  const modelReady = modelPayload?.plan?.ready === true;
  const schedulerAppliedOk = schedulerPayload?.ok === true;
  const schedulerPlanReady = schedulerPlanPayload?.ready_for_scheduler_authority_apply === true;
  const schedulerOk = config.schedulerGateMode === 'skip'
    || schedulerAppliedOk
    || (config.schedulerGateMode === 'ready' && schedulerPlanReady);
  const blockerList = Array.isArray(blockerPayload?.blockers) ? blockerPayload.blockers : [];
  const hardBlockers = blockerList.filter((blocker) => ![
    'manual_human_cutover_approval_required_after_long_soak',
  ].includes(String(blocker)));
  const productionBlockerOk = blockerPayload?.ok === true
    && blockerPayload?.production_apply_allowed === false
    && blockerPayload?.production_authority_change === false
    && blockerPayload?.production_cutover_implemented === true
    && blockerPayload?.provider_route_production_switch_detected === true
    && blockerPayload?.model_route_production_switch_detected === true
    && hardBlockers.length === 0;
  const issues = [];
  if (config.schedulerGateMode !== 'skip' && !collected.schedulerGuard?.parsed) issues.push('scheduler_guard_output_not_parseable');
  if (
    config.schedulerGateMode === 'ready'
    && !schedulerAppliedOk
    && !collected.schedulerPlan?.parsed
  ) {
    issues.push('scheduler_production_authority_plan_output_not_parseable');
  }
  if (!collected.providerPlan?.parsed) issues.push('provider_route_authority_plan_output_not_parseable');
  if (!collected.modelPlan?.parsed) issues.push('model_route_authority_plan_output_not_parseable');
  if (!collected.productionBlocker?.parsed) issues.push('route_authority_production_blocker_output_not_parseable');
  if (!schedulerOk) issues.push(config.schedulerGateMode === 'applied'
    ? 'scheduler_production_authority_guard_failed'
    : 'scheduler_production_authority_not_ready');
  if (!providerReady) issues.push('provider_route_authority_plan_not_ready');
  if (!modelReady) issues.push('model_route_authority_plan_not_ready');
  if (!productionBlockerOk) issues.push('route_authority_production_blocker_not_safe');
  if (providerPayload?.plan?.production_authority_change !== false) issues.push('provider_plan_attempted_production_change');
  if (modelPayload?.plan?.production_authority_change !== false) issues.push('model_plan_attempted_production_change');
  return {
    ok: issues.length === 0,
    schema_version: 'xhub.route_authority_cutover_guard.v1',
    generated_at: new Date().toISOString(),
    config: {
      provider_shadow_runs: config.providerShadowRuns,
      provider_candidate_runs: config.providerCandidateRuns,
      model_remote_runs: config.modelRemoteRuns,
      model_local_runs: config.modelLocalRuns,
      concurrency: config.concurrency,
      provider: config.provider,
      provider_model_id: config.providerModelId,
      provider_min_compare_reports: config.providerMinCompareReports,
      remote_model_id: config.remoteModelId,
      local_model_id: config.localModelId,
      max_generate_ms: config.maxGenerateMs,
      rust_hub_root: config.rustHubRoot,
      scheduler_gate_mode: config.schedulerGateMode,
    },
    scheduler_production_authority_ok: schedulerOk,
    scheduler_production_authority_applied_ok: schedulerAppliedOk,
    scheduler_production_authority_plan_ready: schedulerPlanReady,
    provider_route_ready_for_manual_prep_trial: providerReady,
    model_route_ready_for_manual_prep_trial: modelReady,
    production_cutover_blocker_ok: productionBlockerOk,
    production_apply_allowed: false,
    safe_prep_only: blockerPayload?.safe_prep_only === true,
    provider_route_production_switch_detected: blockerPayload?.provider_route_production_switch_detected === true,
    model_route_production_switch_detected: blockerPayload?.model_route_production_switch_detected === true,
    production_authority_change: false,
    provider_route_authority_target: false,
    model_route_authority_target: false,
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    ui_product_change: Boolean(schedulerPayload?.ui_product_change),
    secret_leak: false,
    provider_plan_exit_code: Number(collected.providerPlan?.exit_code ?? -1),
    model_plan_exit_code: Number(collected.modelPlan?.exit_code ?? -1),
    scheduler_guard_exit_code: Number(collected.schedulerGuard?.exit_code ?? -1),
    scheduler_plan_exit_code: Number(collected.schedulerPlan?.exit_code ?? -1),
    production_blocker_exit_code: Number(collected.productionBlocker?.exit_code ?? -1),
    production_cutover_implemented: blockerPayload?.production_cutover_implemented === true,
    launchctl_provider_model_production_keys_present: Array.isArray(blockerPayload?.launchctl_provider_model_production_keys_present)
      ? blockerPayload.launchctl_provider_model_production_keys_present.map(String)
      : [],
    production_blockers: blockerList.map(String),
    production_hard_blockers: hardBlockers.map(String),
    provider_plan_decision: String(providerPayload?.plan?.decision || ''),
    model_plan_decision: String(modelPayload?.plan?.decision || ''),
    production_blocker_schema_version: String(blockerPayload?.schema_version || ''),
    provider_required_env_count: Number(providerPayload?.plan?.required_env_for_manual_prep_trial?.length || 0),
    model_required_env_count: Number(modelPayload?.plan?.required_env_for_manual_prep_trial?.length || 0),
    provider_parse_error: String(collected.providerPlan?.parse_error || ''),
    model_parse_error: String(collected.modelPlan?.parse_error || ''),
    scheduler_guard_parse_error: String(collected.schedulerGuard?.parse_error || ''),
    scheduler_plan_parse_error: String(collected.schedulerPlan?.parse_error || ''),
    production_blocker_parse_error: String(collected.productionBlocker?.parse_error || ''),
    issues,
  };
}

function reportPath() {
  const stamp = new Date().toISOString().replaceAll('-', '').replaceAll(':', '').replace(/\.\d{3}Z$/, 'Z');
  return path.join(REPORT_DIR, `route_authority_cutover_guard_${stamp}.json`);
}

function runSelfTest() {
  const result = reduce({
    schedulerGuard: { parsed: true, payload: { ok: true, ui_product_change: false } },
    schedulerPlan: null,
    providerPlan: { parsed: true, exit_code: 0, payload: { plan: { ready: true, production_authority_change: false, decision: 'ready_for_manual_prep_trial', required_env_for_manual_prep_trial: [1] } } },
    modelPlan: { parsed: true, exit_code: 0, payload: { plan: { ready: true, production_authority_change: false, decision: 'ready_for_manual_prep_trial', required_env_for_manual_prep_trial: [1] } } },
    productionBlocker: { parsed: true, exit_code: 0, payload: { ok: true, production_apply_allowed: false, production_authority_change: false, safe_prep_only: true } },
  }, parseArgs([]));
  if (result.ok) throw new Error('legacy safe-prep-only blocker payload must not pass without production switch contract');
  const productionContractResult = reduce({
    schedulerGuard: { parsed: true, payload: { ok: true, ui_product_change: false } },
    schedulerPlan: null,
    providerPlan: { parsed: true, exit_code: 0, payload: { plan: { ready: true, production_authority_change: false, decision: 'ready_for_manual_prep_trial', required_env_for_manual_prep_trial: [1] } } },
    modelPlan: { parsed: true, exit_code: 0, payload: { plan: { ready: true, production_authority_change: false, decision: 'ready_for_manual_prep_trial', required_env_for_manual_prep_trial: [1] } } },
    productionBlocker: {
      parsed: true,
      exit_code: 0,
      payload: {
        ok: true,
        production_apply_allowed: false,
        production_authority_change: false,
        production_cutover_implemented: true,
        provider_route_production_switch_detected: true,
        model_route_production_switch_detected: true,
        blockers: ['manual_human_cutover_approval_required_after_long_soak'],
      },
    },
  }, parseArgs([]));
  if (!productionContractResult.ok) {
    throw new Error(`expected production switch contract prep ok: ${productionContractResult.issues.join(',')}`);
  }
  const fallbackResult = reduce({
    schedulerGuard: { parsed: true, exit_code: 2, payload: { ok: false, ui_product_change: false } },
    schedulerPlan: { parsed: true, exit_code: 0, payload: { ready_for_scheduler_authority_apply: true } },
    providerPlan: { parsed: true, exit_code: 0, payload: { plan: { ready: true, production_authority_change: false, decision: 'ready_for_manual_prep_trial', required_env_for_manual_prep_trial: [1] } } },
    modelPlan: { parsed: true, exit_code: 0, payload: { plan: { ready: true, production_authority_change: false, decision: 'ready_for_manual_prep_trial', required_env_for_manual_prep_trial: [1] } } },
    productionBlocker: {
      parsed: true,
      exit_code: 0,
      payload: {
        ok: true,
        production_apply_allowed: false,
        production_authority_change: false,
        production_cutover_implemented: true,
        provider_route_production_switch_detected: true,
        model_route_production_switch_detected: true,
        blockers: ['manual_human_cutover_approval_required_after_long_soak'],
      },
    },
  }, parseArgs([]));
  if (!fallbackResult.ok || fallbackResult.scheduler_production_authority_plan_ready !== true) {
    throw new Error(`expected scheduler ready fallback ok: ${fallbackResult.issues.join(',')}`);
  }
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    process.stdout.write('route_authority_cutover_guard self-test ok\n');
    return;
  }
  const result = reduce(collect(config), config);
  if (config.writeReport) {
    fs.mkdirSync(REPORT_DIR, { recursive: true });
    const pathOut = reportPath();
    fs.writeFileSync(pathOut, `${JSON.stringify(result, null, 2)}\n`);
    result.report_path = pathOut;
  }
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (!result.ok) process.exit(2);
}

main().catch((error) => {
  process.stderr.write(`[route_authority_cutover_guard] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
