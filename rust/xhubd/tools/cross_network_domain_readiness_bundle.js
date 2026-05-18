#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');

function safeString(value) {
  return String(value ?? '').trim();
}

function parseBool(value, fallback = false) {
  if (value == null) return fallback;
  const normalized = safeString(value).toLowerCase();
  if (!normalized) return fallback;
  if (['1', 'true', 'yes', 'y', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(normalized)) return false;
  return fallback;
}

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function defaultBinarySource() {
  const packaged = path.join(ROOT_DIR, 'bin', 'xhubd');
  if (fs.existsSync(packaged)) return packaged;
  const release = path.join(ROOT_DIR, 'target', 'release', 'xhubd');
  if (fs.existsSync(release)) return release;
  return packaged;
}

function defaultAccessKeyFile() {
  const packaged = path.join(ROOT_DIR, 'secrets', 'xhubd_domain_access_key');
  if (fs.existsSync(packaged)) return packaged;
  const sourceRepo = path.resolve(ROOT_DIR, '..', '..', 'secrets', 'xhubd_domain_access_key');
  if (fs.existsSync(sourceRepo)) return sourceRepo;
  return packaged;
}

function parseArgs(argv) {
  const out = {
    publicBaseUrl: process.env.XHUB_RUST_HUB_PUBLIC_BASE_URL || '',
    accessKeyFile: process.env.XHUB_RUST_HTTP_ACCESS_KEY_FILE || defaultAccessKeyFile(),
    profile: 'domain',
    hubLabel: 'AX Rust Hub',
    outputDir: path.join(ROOT_DIR, 'pairing'),
    launchdLabel: 'com.ax.xhubd.local',
    launchdRuntimeRoot: path.join(os.homedir(), 'Library', 'Application Support', 'AX', 'rust-hub', 'local'),
    watchdogLaunchdLabel: 'com.ax.xhubd.local.watchdog',
    launchdBinarySource: defaultBinarySource(),
    timeoutMs: 30000,
    noNetwork: false,
    requireLiveHttp: false,
    requireAuthReady: false,
    requireMemorySkillsProduction: false,
    allowLoopbackPublicHost: false,
    allowVpnRawHost: parseBool(process.env.XHUB_RUST_REMOTE_ROUTE_ALLOW_VPN_RAW_HOST, false),
    allowPublicRawIp: parseBool(process.env.XHUB_RUST_REMOTE_ROUTE_ALLOW_PUBLIC_RAW_IP, false),
    selfTest: false,
    help: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--public-base-url':
        out.publicBaseUrl = safeString(next);
        i += 1;
        break;
      case '--access-key-file':
        out.accessKeyFile = path.resolve(next || out.accessKeyFile);
        i += 1;
        break;
      case '--profile':
        out.profile = safeString(next) || out.profile;
        i += 1;
        break;
      case '--hub-label':
        out.hubLabel = safeString(next) || out.hubLabel;
        i += 1;
        break;
      case '--output-dir':
        out.outputDir = path.resolve(next || out.outputDir);
        i += 1;
        break;
      case '--launchd-label':
        out.launchdLabel = safeString(next) || out.launchdLabel;
        i += 1;
        break;
      case '--launchd-runtime-root':
        out.launchdRuntimeRoot = path.resolve(next || out.launchdRuntimeRoot);
        i += 1;
        break;
      case '--watchdog-launchd-label':
        out.watchdogLaunchdLabel = safeString(next) || out.watchdogLaunchdLabel;
        i += 1;
        break;
      case '--launchd-binary-source':
        out.launchdBinarySource = path.resolve(next || out.launchdBinarySource);
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 250, 300000);
        i += 1;
        break;
      case '--no-network':
        out.noNetwork = true;
        break;
      case '--require-live-http':
        out.requireLiveHttp = true;
        break;
      case '--require-auth-ready':
        out.requireAuthReady = true;
        out.requireLiveHttp = true;
        break;
      case '--require-memory-skills-production':
        out.requireMemorySkillsProduction = true;
        break;
      case '--allow-loopback-public-host':
        out.allowLoopbackPublicHost = true;
        break;
      case '--allow-vpn-raw-host':
        out.allowVpnRawHost = true;
        break;
      case '--allow-public-raw-ip':
        out.allowPublicRawIp = true;
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
    'cross_network_domain_readiness_bundle.js',
    '',
    'Build a non-mutating readiness bundle for real XT off-LAN domain/tunnel activation.',
    '',
    'Options:',
    '  --public-base-url <url>          Required public domain/tunnel URL',
    '  --access-key-file <path>         Access key file path used by planned smoke commands',
    '  --no-network                     Skip DNS/HTTP probes in the embedded remote doctor',
    '  --require-live-http              Require public /health in the embedded remote doctor',
    '  --require-auth-ready             Require authenticated /ready in the embedded remote doctor',
    '  --hub-label <text>               Label for planned XT pairing export',
    '  --output-dir <path>              Planned pairing output dir, default pairing/',
    '  --launchd-label <label>          Existing daemon label to update, default com.ax.xhubd.local',
    '  --launchd-runtime-root <path>    Existing launchd runtime root',
    '  --watchdog-launchd-label <label> Watchdog label, default com.ax.xhubd.local.watchdog',
    '  --launchd-binary-source <path>   xhubd binary copied into runtime, default bin/xhubd',
    '  --timeout-ms <n>                 Probe/smoke timeout, default 30000',
    '  --require-memory-skills-production',
    '  --allow-loopback-public-host     Test-only: allow localhost public URL',
    '  --allow-vpn-raw-host             Explicitly allow raw VPN/tailnet/private IP host',
    '  --allow-public-raw-ip            Dev escape hatch for raw public IP host',
    '  --self-test',
  ].join('\n');
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function commandLine(parts) {
  return parts.map(shellQuote).join(' ');
}

function toolCommand(name) {
  return path.join(ROOT_DIR, 'tools', `${name}.command`);
}

function toolJs(name) {
  return path.join(ROOT_DIR, 'tools', `${name}.js`);
}

function routeArgs(config) {
  const args = ['--public-base-url', config.publicBaseUrl];
  if (config.allowLoopbackPublicHost) args.push('--allow-loopback-public-host');
  if (config.allowVpnRawHost) args.push('--allow-vpn-raw-host');
  if (config.allowPublicRawIp) args.push('--allow-public-raw-ip');
  return args;
}

function doctorArgs(config) {
  const args = [
    '--public-base-url',
    config.publicBaseUrl,
    '--access-key-file',
    config.accessKeyFile,
    '--timeout-ms',
    String(config.timeoutMs),
  ];
  if (config.noNetwork) args.push('--no-network');
  if (config.requireLiveHttp) args.push('--require-live-http');
  if (config.requireAuthReady) args.push('--require-auth-ready');
  if (config.allowLoopbackPublicHost) args.push('--allow-loopback-public-host');
  if (config.allowVpnRawHost) args.push('--allow-vpn-raw-host');
  if (config.allowPublicRawIp) args.push('--allow-public-raw-ip');
  return args;
}

function activationPlanArgs(config) {
  const args = [
    '--public-base-url',
    config.publicBaseUrl,
    '--access-key-file',
    config.accessKeyFile,
    '--profile',
    config.profile,
    '--hub-label',
    config.hubLabel,
    '--output-dir',
    config.outputDir,
    '--launchd-label',
    config.launchdLabel,
    '--launchd-runtime-root',
    config.launchdRuntimeRoot,
    '--watchdog-launchd-label',
    config.watchdogLaunchdLabel,
    '--launchd-binary-source',
    config.launchdBinarySource,
    '--timeout-ms',
    String(config.timeoutMs),
  ];
  if (config.requireMemorySkillsProduction) args.push('--require-memory-skills-production');
  if (config.allowLoopbackPublicHost) args.push('--allow-loopback-public-host');
  if (config.allowVpnRawHost) args.push('--allow-vpn-raw-host');
  if (config.allowPublicRawIp) args.push('--allow-public-raw-ip');
  return args;
}

function smokeCommand(config) {
  return commandLine([
    'bash',
    toolCommand('cross_network_domain_smoke'),
    '--public-base-url',
    config.publicBaseUrl,
    '--access-key-file',
    config.accessKeyFile,
    '--timeout-ms',
    String(config.timeoutMs),
  ]);
}

function hasSecretLeakValue(value) {
  return /Bearer\s+(?!\[REDACTED\])\S+|access_key"\s*:\s*"(?!\[REDACTED\])|[a-f0-9]{64}/i.test(JSON.stringify(value));
}

function hasSecretLeakText(value) {
  return /Bearer\s+(?!\[REDACTED\])\S+|access_key"\s*:\s*"(?!\[REDACTED\])|[a-f0-9]{64}/i.test(String(value || ''));
}

function redactText(value) {
  return String(value || '')
    .replace(/Bearer\s+\S+/g, 'Bearer [REDACTED]')
    .replace(/\b[a-f0-9]{64}\b/gi, '[REDACTED_64_HEX]');
}

function parseJsonOutput(stdout) {
  const text = safeString(stdout);
  if (!text) return { json: null, error: 'stdout_empty' };
  try {
    return { json: JSON.parse(text), error: '' };
  } catch {}
  const first = text.indexOf('{');
  const last = text.lastIndexOf('}');
  if (first >= 0 && last > first) {
    try {
      return { json: JSON.parse(text.slice(first, last + 1)), error: '' };
    } catch (error) {
      return { json: null, error: safeString(error.message || error) };
    }
  }
  return { json: null, error: 'json_object_not_found' };
}

function runJsonTool(name, args, timeoutMs) {
  const startedAt = Date.now();
  const script = toolJs(name);
  let exitCode = 0;
  let signal = '';
  let stdout = '';
  let stderr = '';
  try {
    stdout = execFileSync(process.execPath, [script, ...args], {
      cwd: ROOT_DIR,
      encoding: 'utf8',
      timeout: Math.max(1000, timeoutMs + 5000),
      maxBuffer: 20 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (error) {
    exitCode = Number.isFinite(error?.status) ? Number(error.status) : 1;
    signal = safeString(error?.signal || '');
    stdout = error?.stdout ? String(error.stdout) : '';
    stderr = error?.stderr ? String(error.stderr) : safeString(error?.message || error);
  }
  const rawSecretLeak = hasSecretLeakText(stdout) || hasSecretLeakText(stderr);
  const parsed = parseJsonOutput(stdout);
  const parsedSecretLeak = parsed.json ? hasSecretLeakValue(parsed.json) : false;
  const includeReport = parsed.json && !parsedSecretLeak;
  return {
    ok: exitCode === 0 && parsed.json?.ok === true && !rawSecretLeak && !parsedSecretLeak,
    tool: name,
    command: commandLine(['node', script, ...args]),
    exit_code: exitCode,
    signal,
    duration_ms: Date.now() - startedAt,
    parsed: parsed.json !== null,
    parse_error: parsed.error,
    stderr_tail: redactText(stderr).slice(-2000),
    report: includeReport ? parsed.json : null,
    report_redacted_due_to_secret_leak: parsedSecretLeak,
    secret_leak: rawSecretLeak || parsedSecretLeak,
  };
}

function normalizeChildIssues(name, run) {
  const issues = [];
  const add = (severity, code, detail) => issues.push({
    severity,
    code: `${name}_${code}`,
    detail,
  });
  if (run.secret_leak) add('blocker', 'secret_leak', `${name} output contained secret-looking material.`);
  if (!run.parsed) {
    add('blocker', 'json_parse_failed', run.parse_error || `${name} did not emit JSON.`);
    return issues;
  }
  if (run.exit_code !== 0 && run.report?.ok !== false) {
    add('blocker', 'exit_nonzero', `exit_code=${run.exit_code}`);
  }
  const childIssues = Array.isArray(run.report?.issues) ? run.report.issues : [];
  for (const issue of childIssues) {
    if (typeof issue === 'string') {
      add('blocker', issue, issue);
    } else {
      add(
        issue.severity || 'blocker',
        issue.code || 'issue',
        issue.detail || JSON.stringify(issue),
      );
    }
  }
  return issues;
}

async function buildReport(config) {
  const startedAt = Date.now();
  const routeGate = runJsonTool('cross_network_remote_route_gate', routeArgs(config), config.timeoutMs);
  const remoteDoctor = runJsonTool('cross_network_remote_route_doctor', doctorArgs(config), config.timeoutMs);
  const activationPlan = runJsonTool('cross_network_domain_activation_plan', activationPlanArgs(config), config.timeoutMs);
  const issues = [
    ...normalizeChildIssues('route_gate', routeGate),
    ...normalizeChildIssues('remote_doctor', remoteDoctor),
    ...normalizeChildIssues('activation_plan', activationPlan),
  ];
  const blockers = issues.filter((issue) => issue.severity === 'blocker');
  const allChildrenOk = routeGate.ok && remoteDoctor.ok && activationPlan.ok;
  const report = {
    ok: blockers.length === 0 && allChildrenOk,
    schema_version: 'xhub.rust_hub.cross_network_domain_readiness_bundle.v1',
    command: 'cross-network-domain-readiness-bundle',
    generated_at_iso: new Date().toISOString(),
    duration_ms: Date.now() - startedAt,
    root_dir: ROOT_DIR,
    public_base_url: config.publicBaseUrl,
    mode: config.noNetwork ? 'planning_no_network' : 'diagnostic_network',
    require_live_http: config.requireLiveHttp,
    require_auth_ready: config.requireAuthReady,
    require_memory_skills_production: config.requireMemorySkillsProduction,
    allow_vpn_raw_host: config.allowVpnRawHost,
    allow_public_raw_ip: config.allowPublicRawIp,
    access_key_file: {
      path: config.accessKeyFile,
      exists: fs.existsSync(config.accessKeyFile),
      key_printed: false,
    },
    launchd_binary_source: config.launchdBinarySource,
    launchd_binary_source_exists: fs.existsSync(config.launchdBinarySource),
    checks: {
      route_gate: routeGate,
      remote_doctor: remoteDoctor,
      activation_plan: activationPlan,
    },
    generated_commands: {
      route_gate: commandLine(['bash', toolCommand('cross_network_remote_route_gate'), ...routeArgs(config)]),
      remote_doctor: commandLine(['bash', toolCommand('cross_network_remote_route_doctor'), ...doctorArgs(config)]),
      activation_plan: commandLine(['bash', toolCommand('cross_network_domain_activation_plan'), ...activationPlanArgs(config)]),
      strict_domain_smoke_after_activation: smokeCommand(config),
    },
    readiness: {
      route_semantics_ok: routeGate.report?.ok === true,
      remote_doctor_ok: remoteDoctor.report?.ok === true,
      activation_plan_ok: activationPlan.report?.ok === true,
      smoke_command_generated: true,
      planning_ready: blockers.length === 0 && allChildrenOk,
      strict_live_ready: !config.noNetwork && config.requireLiveHttp && config.requireAuthReady && blockers.length === 0 && allChildrenOk,
    },
    next_actions: [
      'Run the generated activation_plan command before mutating launchd or pairing files.',
      'After activation, run strict_domain_smoke_after_activation from a network path that resolves the final XT URL.',
      'Export the XT pairing bundle only after unauthenticated /ready is rejected and authenticated /ready returns ready=true.',
    ],
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
    ui_product_change: false,
    key_printed: false,
    secret_leak: false,
    issues,
  };
  report.secret_leak = hasSecretLeakValue(report);
  if (report.secret_leak) {
    report.ok = false;
    report.issues.push({
      severity: 'blocker',
      code: 'bundle_secret_leak',
      detail: 'Readiness bundle contained secret-looking material.',
    });
  }
  return report;
}

async function runSelfTest() {
  const stable = await buildReport(parseArgs([
    '--public-base-url',
    'https://hub.example.test',
    '--access-key-file',
    '/tmp/xhub-readiness-bundle-key',
    '--launchd-binary-source',
    '/bin/echo',
    '--no-network',
  ]));
  if (!stable.ok || stable.readiness.planning_ready !== true) {
    throw new Error(`expected stable no-network readiness bundle to pass: ${JSON.stringify(stable.issues)}`);
  }
  if (!stable.generated_commands.strict_domain_smoke_after_activation.includes('cross_network_domain_smoke.command')) {
    throw new Error('domain smoke command missing');
  }
  const publicIp = await buildReport(parseArgs([
    '--public-base-url',
    'https://17.81.11.116',
    '--access-key-file',
    '/tmp/xhub-readiness-bundle-key',
    '--launchd-binary-source',
    '/bin/echo',
    '--no-network',
  ]));
  if (publicIp.ok || !publicIp.issues.some((issue) => issue.code.includes('public_raw_ip_forbidden'))) {
    throw new Error('raw public IP should fail readiness bundle');
  }
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (config.selfTest) {
    await runSelfTest();
    process.stdout.write('cross_network_domain_readiness_bundle self-test ok\n');
    return;
  }
  const report = await buildReport(config);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  process.exitCode = report.ok ? 0 : 2;
}

const invokedAsMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (invokedAsMain) {
  main().catch((error) => {
    process.stderr.write(`[cross_network_domain_readiness_bundle] ${error?.stack || error?.message || error}\n`);
    process.exit(1);
  });
}
