#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { analyzeRemoteRoute } from './cross_network_remote_route_gate.js';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');

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
    requireMemorySkillsProduction: false,
    allowLoopbackPublicHost: false,
    allowVpnRawHost: false,
    allowPublicRawIp: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--public-base-url':
        out.publicBaseUrl = String(next || '').trim();
        i += 1;
        break;
      case '--access-key-file':
        out.accessKeyFile = path.resolve(next || out.accessKeyFile);
        i += 1;
        break;
      case '--profile':
        out.profile = String(next || '').trim() || out.profile;
        i += 1;
        break;
      case '--hub-label':
        out.hubLabel = String(next || '').trim() || out.hubLabel;
        i += 1;
        break;
      case '--output-dir':
        out.outputDir = path.resolve(next || out.outputDir);
        i += 1;
        break;
      case '--launchd-label':
        out.launchdLabel = String(next || '').trim() || out.launchdLabel;
        i += 1;
        break;
      case '--launchd-runtime-root':
        out.launchdRuntimeRoot = path.resolve(next || out.launchdRuntimeRoot);
        i += 1;
        break;
      case '--watchdog-launchd-label':
        out.watchdogLaunchdLabel = String(next || '').trim() || out.watchdogLaunchdLabel;
        i += 1;
        break;
      case '--launchd-binary-source':
        out.launchdBinarySource = path.resolve(next || out.launchdBinarySource);
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 1000, 300000);
        i += 1;
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

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function usage() {
  return [
    'cross_network_domain_activation_plan.js',
    '',
    'Print a non-mutating activation plan for a real domain or tunnel endpoint.',
    '',
    'Options:',
    '  --public-base-url <url>          Required public domain/tunnel URL',
    '  --access-key-file <path>         Access key file, default secrets/xhubd_domain_access_key',
    '  --hub-label <text>               Label written into the XT pairing bundle',
    '  --output-dir <path>              Pairing output dir, default pairing/',
    '  --launchd-label <label>          Existing daemon label to update, default com.ax.xhubd.local',
    '  --launchd-runtime-root <path>    Existing launchd runtime root, default ~/Library/Application Support/AX/rust-hub/local',
    '  --watchdog-launchd-label <label> Watchdog label, default com.ax.xhubd.local.watchdog',
    '  --launchd-binary-source <path>   xhubd binary copied into runtime, default bin/xhubd',
    '  --timeout-ms <n>                 Domain smoke timeout, default 30000',
    '  --require-memory-skills-production',
    '  --allow-loopback-public-host     Test-only: allow localhost public URL',
    '  --allow-vpn-raw-host             Explicitly allow raw VPN/tailnet/private IP host',
    '  --allow-public-raw-ip            Dev escape hatch for raw public IP host',
    '  --self-test',
  ].join('\n');
}

function defaultBinarySource() {
  const packaged = path.join(ROOT_DIR, 'bin', 'xhubd');
  if (fs.existsSync(packaged)) return packaged;
  const release = path.join(ROOT_DIR, 'target', 'release', 'xhubd');
  if (fs.existsSync(release)) return release;
  return packaged;
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function commandLine(parts) {
  return parts.map(shellQuote).join(' ');
}

function isLoopbackHost(host) {
  const normalized = String(host || '').trim().toLowerCase();
  return normalized === 'localhost'
    || normalized === '::1'
    || normalized === '[::1]'
    || normalized.startsWith('127.')
    || normalized === '0.0.0.0';
}

function isWildcardHost(host) {
  const normalized = String(host || '').trim();
  return normalized === '0.0.0.0' || normalized === '::' || normalized === '*';
}

function validatePublicBaseUrl(config) {
  const issues = [];
  let parsed = null;
  const raw = String(config.publicBaseUrl || '').trim();
  if (!raw) {
    issues.push('public_base_url_required');
  } else if (/replace_with|example\.com/i.test(raw)) {
    issues.push('public_base_url_placeholder');
  } else {
    try {
      parsed = new URL(raw);
    } catch {
      issues.push('public_base_url_invalid');
    }
  }
  if (parsed) {
    if (!['http:', 'https:'].includes(parsed.protocol)) issues.push('public_base_url_must_be_http_or_https');
    if (!parsed.hostname || isWildcardHost(parsed.hostname)) issues.push('public_base_url_host_invalid');
    if (!config.allowLoopbackPublicHost && isLoopbackHost(parsed.hostname)) issues.push('public_base_url_loopback');
    if (parsed.protocol !== 'https:' && !config.allowLoopbackPublicHost) issues.push('public_base_url_https_required');
  }
  return { ok: issues.length === 0, parsed, issues };
}

function commonArgs(config) {
  const publicHost = publicHostFromBaseUrl(config.publicBaseUrl);
  const args = [
    '--profile', config.profile,
    '--public-base-url', config.publicBaseUrl,
    '--public-endpoint',
    '--access-key-file', config.accessKeyFile,
    '--launchd-label', config.launchdLabel,
    '--launchd-runtime-root', config.launchdRuntimeRoot,
    '--watchdog-launchd-label', config.watchdogLaunchdLabel,
  ];
  if (publicHost) args.push('--public-host', publicHost);
  if (config.allowLoopbackPublicHost) args.push('--allow-loopback-public-host');
  if (config.requireMemorySkillsProduction) args.push('--require-memory-skills-production');
  return args;
}

function publicHostFromBaseUrl(raw) {
  try {
    return safeString(new URL(safeString(raw)).hostname);
  } catch {
    return '';
  }
}

function remoteRouteGateArgs(config) {
  const args = ['--public-base-url', config.publicBaseUrl];
  if (config.allowLoopbackPublicHost) args.push('--allow-loopback-public-host');
  if (config.allowVpnRawHost) args.push('--allow-vpn-raw-host');
  if (config.allowPublicRawIp) args.push('--allow-public-raw-ip');
  return args;
}

function tool(name) {
  return path.join(ROOT_DIR, 'tools', name);
}

function buildPlan(config) {
  const common = commonArgs(config);
  const remoteGate = remoteRouteGateArgs(config);
  const readinessCommon = config.requireMemorySkillsProduction
    ? common
    : [...common, '--allow-memory-skills-production'];
  const installCommon = [
    ...common,
    '--launchd-binary-source', config.launchdBinarySource,
  ];
  const smokeCommand = commandLine([
    'bash',
    tool('cross_network_domain_smoke.command'),
    '--public-base-url',
    config.publicBaseUrl,
    '--access-key-file',
    config.accessKeyFile,
    '--timeout-ms',
    String(config.timeoutMs),
  ]);
  const pairingCommand = commandLine([
    'bash',
    tool('cross_network_pairing_export.command'),
    ...common,
    '--output-dir',
    config.outputDir,
    '--hub-label',
    config.hubLabel,
  ]);
  return {
    steps: [
      {
        name: 'initialize_or_repair_access_key_file',
        mutates: true,
        command: commandLine(['bash', tool('xhubd_daemon.command'), 'access-key-init', ...common]),
        notes: 'Creates or chmods the key file; stdout never contains the key.',
      },
      {
        name: 'remote_route_semantics_gate',
        mutates: false,
        command: commandLine(['bash', tool('cross_network_remote_route_gate.command'), ...remoteGate]),
        notes: 'Blocks LAN-only names, loopback, raw public IP defaults, and ambiguous raw VPN hosts before domain activation.',
      },
      {
        name: 'readiness_preflight',
        mutates: false,
        command: commandLine(['bash', tool('cross_network_readiness_gate.command'), ...readinessCommon]),
      },
      {
        name: 'daemon_launchd_dry_run',
        mutates: false,
        command: commandLine(['bash', tool('xhubd_daemon.command'), 'launchd-install', ...installCommon, '--dry-run']),
      },
      {
        name: 'install_or_update_existing_daemon',
        mutates: true,
        command: commandLine(['bash', tool('xhubd_daemon.command'), 'launchd-install', ...installCommon, '--replace-running', '--wait-ms', String(config.timeoutMs)]),
        notes: 'Updates the existing local daemon label to public-endpoint mode while still binding localhost for tunnel fronting.',
      },
      {
        name: 'install_watchdog_timer',
        mutates: true,
        command: commandLine(['bash', tool('xhubd_daemon.command'), 'watchdog-install', ...common]),
      },
      {
        name: 'strict_installed_gate',
        mutates: false,
        command: commandLine([
          'bash',
          tool('cross_network_installed_gate.command'),
          ...readinessCommon,
          '--require-cross-network-remote-route-smoke',
          '--cross-network-remote-route-smoke-timeout-ms',
          String(config.timeoutMs),
        ]),
      },
      {
        name: 'export_xt_pairing_bundle',
        mutates: true,
        command: pairingCommand,
        notes: 'Writes a 0600 pairing JSON containing the access key. Do not paste it into logs.',
      },
      {
        name: 'domain_smoke_from_public_url',
        mutates: false,
        command: smokeCommand,
      },
    ],
    rollback_steps: [
      {
        name: 'return_daemon_to_local_profile',
        mutates: true,
        command: commandLine([
          'bash',
          tool('xhubd_daemon.command'),
          'launchd-install',
          '--profile',
          'local',
          '--launchd-label',
          config.launchdLabel,
          '--launchd-runtime-root',
          config.launchdRuntimeRoot,
          '--launchd-binary-source',
          config.launchdBinarySource,
          '--replace-running',
          '--wait-ms',
          String(config.timeoutMs),
        ]),
      },
      {
        name: 'uninstall_watchdog_timer',
        mutates: true,
        command: commandLine(['bash', tool('xhubd_daemon.command'), 'watchdog-uninstall', ...common]),
      },
      {
        name: 'local_daemon_ops_gate',
        mutates: false,
        command: commandLine([
          'bash',
          tool('daemon_ops_gate.command'),
          '--max-slow-requests',
          '0',
          '--allow-memory-skills-production',
        ]),
      },
    ],
  };
}

function runSelfTest() {
  const config = parseArgs(['--public-base-url', 'https://hub.example.test', '--access-key-file', '/tmp/xhub-key']);
  const validation = validatePublicBaseUrl(config);
  if (!validation.ok) throw new Error(`expected valid URL: ${validation.issues.join(',')}`);
  const plan = buildPlan(config);
  if (plan.steps.length !== 9) throw new Error('expected nine activation steps');
  if (!plan.steps.some((step) => step.command.includes('cross_network_remote_route_gate.command'))) {
    throw new Error('remote route semantics gate missing');
  }
  if (!plan.steps.some((step) => step.name === 'strict_installed_gate'
      && step.command.includes('--require-cross-network-remote-route-smoke'))) {
    throw new Error('strict installed gate must require remote route smoke');
  }
  if (!plan.steps.some((step) => step.command.includes('cross_network_pairing_export.command'))) {
    throw new Error('pairing export missing');
  }
  const placeholder = validatePublicBaseUrl({ ...config, publicBaseUrl: 'https://hub.example.com' });
  if (placeholder.ok) throw new Error('example.com must be rejected for real activation plan');
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    process.stdout.write('cross_network_domain_activation_plan self-test ok\n');
    return;
  }
  const validation = validatePublicBaseUrl(config);
  const remoteRoute = analyzeRemoteRoute({
    publicBaseUrl: config.publicBaseUrl,
    requireHttps: true,
    allowLoopbackPublicHost: config.allowLoopbackPublicHost,
    allowVpnRawHost: config.allowVpnRawHost,
    allowPublicRawIp: config.allowPublicRawIp,
  });
  const binaryExists = fs.existsSync(config.launchdBinarySource);
  const remoteRouteBlockers = remoteRoute.issues
    .filter((issue) => issue.severity === 'blocker')
    .map((issue) => `remote_route_${issue.code}`);
  const issues = [...validation.issues, ...remoteRouteBlockers];
  if (!binaryExists) issues.push('launchd_binary_source_missing');
  const plan = buildPlan(config);
  const report = {
    ok: issues.length === 0,
    schema_version: 'xhub.rust_hub.cross_network_domain_activation_plan.v1',
    command: 'cross-network-domain-activation-plan',
    generated_at_iso: new Date().toISOString(),
    root_dir: ROOT_DIR,
    profile: config.profile,
    public_base_url: config.publicBaseUrl,
    public_endpoint: true,
    launchd_label: config.launchdLabel,
    launchd_runtime_root: config.launchdRuntimeRoot,
    watchdog_launchd_label: config.watchdogLaunchdLabel,
    launchd_binary_source: config.launchdBinarySource,
    launchd_binary_source_exists: binaryExists,
    access_key_file: config.accessKeyFile,
    access_key_file_exists: fs.existsSync(config.accessKeyFile),
    pairing_output_dir: config.outputDir,
    require_memory_skills_production: config.requireMemorySkillsProduction,
    allow_vpn_raw_host: config.allowVpnRawHost,
    allow_public_raw_ip: config.allowPublicRawIp,
    remote_route_gate: {
      ok: remoteRoute.ok,
      target: remoteRoute.target,
      host_classification: remoteRoute.host_classification,
      route_profile: remoteRoute.route_profile,
      security_checks: remoteRoute.security_checks,
      issues: remoteRoute.issues,
      recommendations: remoteRoute.recommendations,
    },
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
    ui_product_change: false,
    key_printed: false,
    secret_leak: false,
    issues,
    ...plan,
  };
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  process.exitCode = report.ok ? 0 : 2;
}

main().catch((error) => {
  process.stderr.write(`[cross_network_domain_activation_plan] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
