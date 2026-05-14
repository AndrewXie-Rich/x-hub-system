#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const REPORT_DIR = path.join(ROOT_DIR, 'reports');
const DEFAULT_XHUB_SRC = '/Users/andrew.xie/Documents/AX/x-hub-system/x-hub/grpc-server/hub_grpc_server/src';
const PRODUCTION_SWITCH_CONTRACT_VERSION = 'xhub.route_authority.production_switch_contract.v1';
const PROVIDER_PRODUCTION_SWITCH_KEYS = [
  'XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CUTOVER',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_APPLY',
];
const MODEL_PRODUCTION_SWITCH_KEYS = [
  'XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_CUTOVER',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_APPLY',
];
const PROVIDER_PREP_SWITCH_KEYS = [
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE',
];
const MODEL_PREP_SWITCH_KEYS = [
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE',
];

function parseArgs(argv) {
  const out = {
    rustHubRoot: ROOT_DIR,
    xhubSrc: DEFAULT_XHUB_SRC,
    runPrepSustained: true,
    writeReport: true,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--rust-hub-root':
        out.rustHubRoot = String(next || '').trim() || out.rustHubRoot;
        i += 1;
        break;
      case '--xhub-src':
        out.xhubSrc = String(next || '').trim() || out.xhubSrc;
        i += 1;
        break;
      case '--skip-prep-sustained':
        out.runPrepSustained = false;
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
  return out;
}

function usage() {
  return [
    'route_authority_production_cutover_blocker.js',
    '',
    'Options:',
    '  --rust-hub-root <p>       Expected active Rust Hub root',
    '  --xhub-src <p>            Node Hub src directory',
    '  --skip-prep-sustained     Do not run one-cycle RHM-077 prep sustained guard',
    '  --no-report               Print only; do not write reports/',
    '  --self-test               Validate blocker reducer logic',
  ].join('\n');
}

function readSource(config) {
  const providerPath = path.join(config.xhubSrc, 'rust_provider_route_authority_bridge.js');
  const modelPath = path.join(config.xhubSrc, 'rust_model_route_authority_bridge.js');
  return {
    provider_path: providerPath,
    model_path: modelPath,
    provider_exists: fs.existsSync(providerPath),
    model_exists: fs.existsSync(modelPath),
    provider_text: fs.existsSync(providerPath) ? fs.readFileSync(providerPath, 'utf8') : '',
    model_text: fs.existsSync(modelPath) ? fs.readFileSync(modelPath, 'utf8') : '',
  };
}

function detectSwitches(text, keys) {
  return keys.filter((key) => text.includes(key));
}

function getLaunchctlEnv(key) {
  try {
    return execFileSync('launchctl', ['getenv', key], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
  } catch {
    return '';
  }
}

function collectLaunchctlProductionKeys() {
  return [...PROVIDER_PRODUCTION_SWITCH_KEYS, ...MODEL_PRODUCTION_SWITCH_KEYS]
    .filter((key) => getLaunchctlEnv(key) !== '');
}

function runJson(command, args, timeoutMs) {
  let stdout = '';
  let stderr = '';
  let exitCode = 0;
  try {
    stdout = execFileSync(command, args, {
      cwd: ROOT_DIR,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: timeoutMs,
      maxBuffer: 32 * 1024 * 1024,
    });
  } catch (error) {
    stdout = String(error.stdout || '');
    stderr = String(error.stderr || error.message || '').slice(0, 4000);
    exitCode = Number(error.status || 1);
  }
  let payload = null;
  let parseError = '';
  try {
    payload = JSON.parse(stdout);
  } catch {
    try {
      payload = parseLastJsonObject(stdout);
    } catch (error) {
      parseError = String(error.message || error);
    }
  }
  return { exit_code: exitCode, parsed: !!payload, parse_error: parseError, stderr, payload };
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
      // Continue scanning.
    }
  }
  throw new Error('no parseable JSON object in command output');
}

function collect(config) {
  const source = readSource(config);
  const productionSessionTool = path.join(SCRIPT_DIR, 'route_authority_production_session.command');
  const prep = config.runPrepSustained
    ? runJson('bash', [
      path.join(SCRIPT_DIR, 'route_authority_prep_sustained_guard.command'),
      '--cycles', '1',
      '--interval-ms', '0',
      '--timeout-ms', '45000',
      '--rust-hub-root', config.rustHubRoot,
      '--no-report',
    ], 180000)
    : { exit_code: 0, parsed: true, payload: { ok: true, skipped: true } };
  return {
    source,
    prep,
    production_session_tool_path: productionSessionTool,
    production_session_tool_exists: fs.existsSync(productionSessionTool),
    launchctl_production_keys_present: collectLaunchctlProductionKeys(),
  };
}

function reduce(collected, config) {
  const providerProductionMatches = detectSwitches(
    collected.source.provider_text,
    PROVIDER_PRODUCTION_SWITCH_KEYS
  );
  const modelProductionMatches = detectSwitches(
    collected.source.model_text,
    MODEL_PRODUCTION_SWITCH_KEYS
  );
  const providerPrepMatches = detectSwitches(
    collected.source.provider_text,
    PROVIDER_PREP_SWITCH_KEYS
  );
  const modelPrepMatches = detectSwitches(
    collected.source.model_text,
    MODEL_PREP_SWITCH_KEYS
  );
  const providerProductionSwitch = providerProductionMatches.length > 0;
  const modelProductionSwitch = modelProductionMatches.length > 0;
  const prepOnly = providerPrepMatches.length > 0
    && modelPrepMatches.length > 0
    && !providerProductionSwitch
    && !modelProductionSwitch;
  const prepOk = collected.prep?.payload?.ok === true;
  const productionSessionToolExists = collected.production_session_tool_exists === true;
  const launchctlProductionKeysPresent = Array.isArray(collected.launchctl_production_keys_present)
    ? collected.launchctl_production_keys_present
    : [];
  const blockers = [];
  if (!collected.source.provider_exists) blockers.push('provider_authority_bridge_source_missing');
  if (!collected.source.model_exists) blockers.push('model_authority_bridge_source_missing');
  if (!providerProductionSwitch) blockers.push('provider_route_production_authority_switch_not_implemented');
  if (!modelProductionSwitch) blockers.push('model_route_production_authority_switch_not_implemented');
  if (!prepOk) blockers.push('prep_sustained_guard_not_clean');
  if (launchctlProductionKeysPresent.length) blockers.push('launchctl_provider_model_production_env_present');
  if (!productionSessionToolExists) {
    blockers.push('production_apply_tool_not_implemented_by_design');
    blockers.push('rollback_tool_for_provider_model_production_authority_not_implemented');
  }
  blockers.push('manual_human_cutover_approval_required_after_long_soak');

  return {
    ok: true,
    schema_version: 'xhub.route_authority_production_cutover_blocker.v1',
    generated_at: new Date().toISOString(),
    rust_hub_root: config.rustHubRoot,
    xhub_src: config.xhubSrc,
    production_apply_allowed: false,
    production_cutover_implemented: providerProductionSwitch && modelProductionSwitch && productionSessionToolExists,
    production_session_tool_path: collected.production_session_tool_path || '',
    production_session_tool_exists: productionSessionToolExists,
    production_switch_contract_version: PRODUCTION_SWITCH_CONTRACT_VERSION,
    expected_provider_production_keys: PROVIDER_PRODUCTION_SWITCH_KEYS,
    expected_model_production_keys: MODEL_PRODUCTION_SWITCH_KEYS,
    provider_route_production_switch_matches: providerProductionMatches,
    model_route_production_switch_matches: modelProductionMatches,
    launchctl_provider_model_production_keys_present: launchctlProductionKeysPresent,
    provider_route_prep_switch_matches: providerPrepMatches,
    model_route_prep_switch_matches: modelPrepMatches,
    provider_route_production_switch_detected: providerProductionSwitch,
    model_route_production_switch_detected: modelProductionSwitch,
    prep_switches_detected: providerPrepMatches.length > 0 && modelPrepMatches.length > 0,
    candidate_switches_detected: providerPrepMatches.includes('XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE')
      && modelPrepMatches.includes('XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE'),
    safe_prep_only: prepOnly && launchctlProductionKeysPresent.length === 0,
    prep_sustained_guard_ok: prepOk,
    prep_sustained_guard_exit_code: Number(collected.prep?.exit_code ?? -1),
    prep_sustained_guard_parsed: Boolean(collected.prep?.parsed),
    blockers,
    required_before_production_apply: [
      'run fresh provider/model prep sustained soak with at least 3 successful cycles and daemon slow requests at 0',
      'validate route_authority_production_session --apply --dry-run with the fresh prep sustained report',
      'keep require-ready and require-node-match fail-closed gates mandatory',
      'after real apply and X-Hub relaunch, pass route_authority_production_runtime_guard',
      'verify no provider keys, tokens, request bodies, or detail_json in reports',
      'pass UI compatibility gate with no SwiftUI product changes',
      'require explicit human confirmation before production apply',
    ],
    production_authority_change: false,
    provider_route_authority_target: false,
    model_route_authority_target: false,
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    ui_product_change: false,
    secret_leak: false,
  };
}

function reportPath() {
  const stamp = new Date().toISOString().replaceAll('-', '').replaceAll(':', '').replace(/\.\d{3}Z$/, 'Z');
  return path.join(REPORT_DIR, `route_authority_production_cutover_blocker_${stamp}.json`);
}

function runSelfTest() {
  const result = reduce({
    source: {
      provider_exists: true,
      model_exists: true,
      provider_text: 'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP',
      model_text: 'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP',
    },
    prep: { exit_code: 0, parsed: true, payload: { ok: true } },
    launchctl_production_keys_present: [],
  }, parseArgs(['--skip-prep-sustained']));
  if (result.production_apply_allowed !== false) throw new Error('production apply must stay blocked');
  if (!result.blockers.includes('provider_route_production_authority_switch_not_implemented')) {
    throw new Error('provider blocker missing');
  }
  if (result.safe_prep_only !== true) throw new Error('prep/candidate keys must be safe prep only');
  const productionResult = reduce({
    source: {
      provider_exists: true,
      model_exists: true,
      provider_text: 'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY',
      model_text: 'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY',
    },
    prep: { exit_code: 0, parsed: true, payload: { ok: true } },
    launchctl_production_keys_present: [],
  }, parseArgs(['--skip-prep-sustained']));
  if (productionResult.safe_prep_only !== false) throw new Error('production keys must not be safe prep only');
  if (productionResult.provider_route_production_switch_detected !== true) {
    throw new Error('provider production switch was not detected');
  }
  if (productionResult.model_route_production_switch_detected !== true) {
    throw new Error('model production switch was not detected');
  }
  const toolResult = reduce({
    source: {
      provider_exists: true,
      model_exists: true,
      provider_text: 'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY',
      model_text: 'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY',
    },
    prep: { exit_code: 0, parsed: true, payload: { ok: true } },
    production_session_tool_exists: true,
    production_session_tool_path: '/tmp/tool',
    launchctl_production_keys_present: [],
  }, parseArgs(['--skip-prep-sustained']));
  if (toolResult.production_cutover_implemented !== true) throw new Error('production cutover should be implemented');
  if (toolResult.blockers.includes('production_apply_tool_not_implemented_by_design')) {
    throw new Error('apply tool blocker should clear when production tool exists');
  }
  const envPolluted = reduce({
    source: {
      provider_exists: true,
      model_exists: true,
      provider_text: 'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP',
      model_text: 'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP',
    },
    prep: { exit_code: 0, parsed: true, payload: { ok: true } },
    launchctl_production_keys_present: ['XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION'],
  }, parseArgs(['--skip-prep-sustained']));
  if (envPolluted.safe_prep_only !== false) throw new Error('production env must not be safe prep only');
  if (!envPolluted.blockers.includes('launchctl_provider_model_production_env_present')) {
    throw new Error('production env blocker missing');
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
    process.stdout.write('route_authority_production_cutover_blocker self-test ok\n');
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
}

main().catch((error) => {
  process.stderr.write(`[route_authority_production_cutover_blocker] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
