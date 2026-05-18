#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { analyzeRemoteRoute } from './cross_network_remote_route_gate.js';

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
    provider: 'auto',
    publicBaseUrl: process.env.XHUB_RUST_HUB_PUBLIC_BASE_URL || '',
    accessKeyFile: process.env.XHUB_RUST_HTTP_ACCESS_KEY_FILE || defaultAccessKeyFile(),
    httpBaseUrl: 'http://127.0.0.1:50151',
    timeoutMs: 30000,
    requireMemorySkillsProduction: false,
    noExternalDetect: false,
    selfTest: false,
    help: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--provider':
        out.provider = safeString(next || out.provider).toLowerCase();
        i += 1;
        break;
      case '--public-base-url':
        out.publicBaseUrl = safeString(next);
        i += 1;
        break;
      case '--access-key-file':
        out.accessKeyFile = path.resolve(next || out.accessKeyFile);
        i += 1;
        break;
      case '--http-base-url':
        out.httpBaseUrl = safeString(next) || out.httpBaseUrl;
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 250, 300000);
        i += 1;
        break;
      case '--require-memory-skills-production':
        out.requireMemorySkillsProduction = true;
        break;
      case '--no-external-detect':
        out.noExternalDetect = true;
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
    'cross_network_provider_candidate_plan.js',
    '',
    'Print a non-mutating provider candidate plan for XT cross-network Rust Hub access.',
    '',
    'Options:',
    '  --provider <auto|tailscale|cloudflare|reverse-proxy>',
    '  --public-base-url <url>          Final HTTPS domain/tunnel URL when already chosen',
    '  --access-key-file <path>         Access key file path used by generated commands',
    '  --http-base-url <url>            Local Rust Hub HTTP URL, default http://127.0.0.1:50151',
    '  --timeout-ms <n>                 Generated smoke timeout, default 30000',
    '  --require-memory-skills-production',
    '  --no-external-detect             Skip local provider CLI probes',
    '  --self-test',
  ].join('\n');
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function commandLine(parts) {
  return parts.map(shellQuote).join(' ');
}

function commandExists(name) {
  const paths = safeString(process.env.PATH).split(path.delimiter).filter(Boolean);
  for (const dir of paths) {
    const candidate = path.join(dir, name);
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return true;
    } catch {}
  }
  return false;
}

function defaultAccessKeyFile() {
  const packaged = path.join(ROOT_DIR, 'secrets', 'xhubd_domain_access_key');
  if (fs.existsSync(packaged)) return packaged;
  const sourceRepo = path.resolve(ROOT_DIR, '..', '..', 'secrets', 'xhubd_domain_access_key');
  if (fs.existsSync(sourceRepo)) return sourceRepo;
  return packaged;
}

function runCommand(command, args, timeoutMs) {
  const child = spawnSync(command, args, {
    encoding: 'utf8',
    timeout: Math.max(1000, timeoutMs),
    maxBuffer: 2 * 1024 * 1024,
  });
  return {
    ok: child.status === 0,
    exit_code: child.status ?? 0,
    signal: child.signal || '',
    stdout: child.stdout || '',
    stderr: child.stderr || '',
    error: child.error ? safeString(child.error.message || child.error) : '',
  };
}

function parseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function trimDot(value) {
  return safeString(value).replace(/\.$/, '');
}

function detectTailscale(config, overrides = {}) {
  const installed = overrides.commandExists ? overrides.commandExists('tailscale') : commandExists('tailscale');
  if (!installed || (config.noExternalDetect && !overrides.tailscaleStatus)) {
    return {
      installed,
      probed: false,
      status_ok: false,
      backend_state: '',
      version: '',
      dns_name: '',
      magic_dns_suffix: '',
      magic_dns_enabled: false,
      tailscale_ips: [],
      health: [],
      error: config.noExternalDetect ? 'external_detect_skipped' : '',
    };
  }
  const result = overrides.tailscaleStatus
    ? { ok: true, stdout: JSON.stringify(overrides.tailscaleStatus), stderr: '', exit_code: 0, signal: '', error: '' }
    : runCommand('tailscale', ['status', '--json'], config.timeoutMs);
  const json = parseJson(result.stdout);
  return {
    installed,
    probed: true,
    status_ok: result.ok && !!json,
    backend_state: safeString(json?.BackendState),
    version: safeString(json?.Version),
    dns_name: trimDot(json?.Self?.DNSName),
    host_name: safeString(json?.Self?.HostName),
    magic_dns_suffix: safeString(json?.CurrentTailnet?.MagicDNSSuffix || json?.MagicDNSSuffix),
    magic_dns_enabled: json?.CurrentTailnet?.MagicDNSEnabled === true,
    current_tailnet_name: safeString(json?.CurrentTailnet?.Name),
    tailscale_ips: Array.isArray(json?.TailscaleIPs) ? json.TailscaleIPs.map(safeString).filter(Boolean) : [],
    health: Array.isArray(json?.Health) ? json.Health.map(safeString).filter(Boolean) : [],
    error: result.ok && json
      ? ''
      : safeString(result.stderr || result.stdout || result.error || `exit=${result.exit_code}` || 'tailscale_status_json_parse_failed'),
  };
}

function detectCloudflared(config, overrides = {}) {
  const installed = overrides.commandExists ? overrides.commandExists('cloudflared') : commandExists('cloudflared');
  if (!installed || config.noExternalDetect) {
    return {
      installed,
      probed: false,
      version_ok: false,
      version: '',
      error: config.noExternalDetect ? 'external_detect_skipped' : '',
    };
  }
  const result = runCommand('cloudflared', ['--version'], config.timeoutMs);
  return {
    installed,
    probed: true,
    version_ok: result.ok,
    version: safeString(result.stdout || result.stderr).split('\n')[0] || '',
    error: result.ok ? '' : safeString(result.stderr || result.error || `exit=${result.exit_code}`),
  };
}

function tool(name) {
  return path.join(ROOT_DIR, 'tools', name);
}

function bundleArgs(config, publicBaseUrl, strict = false) {
  const args = [
    '--public-base-url',
    publicBaseUrl,
    '--access-key-file',
    config.accessKeyFile,
    '--timeout-ms',
    String(config.timeoutMs),
  ];
  if (strict) {
    args.push('--require-live-http', '--require-auth-ready');
  } else {
    args.push('--no-network');
  }
  if (config.requireMemorySkillsProduction) args.push('--require-memory-skills-production');
  return args;
}

function activationPlanArgs(config, publicBaseUrl) {
  const args = [
    '--public-base-url',
    publicBaseUrl,
    '--access-key-file',
    config.accessKeyFile,
    '--timeout-ms',
    String(config.timeoutMs),
  ];
  if (config.requireMemorySkillsProduction) args.push('--require-memory-skills-production');
  return args;
}

function generatedDomainCommands(config, publicBaseUrl) {
  return {
    readiness_bundle_planning: commandLine([
      'bash',
      tool('cross_network_domain_readiness_bundle.command'),
      ...bundleArgs(config, publicBaseUrl, false),
    ]),
    activation_plan: commandLine([
      'bash',
      tool('cross_network_domain_activation_plan.command'),
      ...activationPlanArgs(config, publicBaseUrl),
    ]),
    readiness_bundle_strict_live: commandLine([
      'bash',
      tool('cross_network_domain_readiness_bundle.command'),
      ...bundleArgs(config, publicBaseUrl, true),
    ]),
    domain_smoke_after_activation: commandLine([
      'bash',
      tool('cross_network_domain_smoke.command'),
      '--public-base-url',
      publicBaseUrl,
      '--access-key-file',
      config.accessKeyFile,
      '--timeout-ms',
      String(config.timeoutMs),
    ]),
  };
}

function candidate(provider, attrs) {
  const publicBaseUrl = safeString(attrs.public_base_url);
  return {
    provider,
    candidate: attrs.candidate,
    scope: attrs.scope,
    installed: attrs.installed === true,
    detected_ready: attrs.detected_ready === true,
    public_base_url: publicBaseUrl,
    route_gate: publicBaseUrl
      ? analyzeRemoteRoute({
        publicBaseUrl,
        requireHttps: true,
        allowVpnRawHost: false,
        allowPublicRawIp: false,
      })
      : null,
    setup_mutates: attrs.setup_mutates === true,
    setup_commands: attrs.setup_commands || [],
    generated_commands: publicBaseUrl ? generatedDomainCommands(attrs.config, publicBaseUrl) : {},
    notes: attrs.notes || [],
  };
}

function providerAllowed(config, provider) {
  return config.provider === 'auto' || config.provider === provider;
}

function buildReport(config, overrides = {}) {
  const startedAt = Date.now();
  const tailscale = detectTailscale(config, overrides);
  const cloudflared = detectCloudflared(config, overrides);
  const selectedUrl = safeString(config.publicBaseUrl);
  const tailscaleUrl = tailscale.dns_name ? `https://${tailscale.dns_name}` : '';
  const candidates = [];

  if (providerAllowed(config, 'reverse-proxy')) {
    candidates.push(candidate('reverse-proxy', {
      config,
      candidate: selectedUrl ? 'provided_stable_https_entry' : 'waiting_for_user_domain',
      scope: 'public_internet_or_private_wan',
      installed: true,
      detected_ready: selectedUrl !== '',
      public_base_url: selectedUrl,
      setup_mutates: true,
      setup_commands: selectedUrl
        ? [
          'Configure your HTTPS reverse proxy or managed tunnel to forward this hostname to http://127.0.0.1:50151.',
        ]
        : [
          'Choose a stable HTTPS hostname, then rerun with --public-base-url https://hub.your-domain.com.',
        ],
      notes: [
        'Best fit when XT devices are not guaranteed to be on the same tailnet.',
        'The Rust daemon remains loopback-bound; the proxy/tunnel fronts it over HTTPS.',
      ],
    }));
  }

  if (providerAllowed(config, 'tailscale')) {
    candidates.push(candidate('tailscale', {
      config,
      candidate: 'tailnet_serve_same_tailnet',
      scope: 'same_tailnet_devices',
      installed: tailscale.installed,
      detected_ready: tailscale.status_ok && tailscale.backend_state === 'Running' && tailscaleUrl !== '',
      public_base_url: tailscaleUrl,
      setup_mutates: true,
      setup_commands: [
        commandLine(['tailscale', 'serve', '--bg', '50151']),
        commandLine(['tailscale', 'serve', 'status', '--json']),
      ],
      notes: [
        'Works when Hub and XT devices are signed into the same tailnet.',
        'This does not expose Hub to the public internet; use Funnel or another HTTPS tunnel for non-tailnet devices.',
      ],
    }));
    candidates.push(candidate('tailscale', {
      config,
      candidate: 'tailscale_funnel_public_https',
      scope: 'public_internet_if_funnel_enabled',
      installed: tailscale.installed,
      detected_ready: tailscale.status_ok && tailscale.backend_state === 'Running' && tailscaleUrl !== '',
      public_base_url: tailscaleUrl,
      setup_mutates: true,
      setup_commands: [
        commandLine(['tailscale', 'funnel', '--bg', '50151']),
        commandLine(['tailscale', 'funnel', 'status', '--json']),
      ],
      notes: [
        'Use only if this tailnet has Funnel enabled and you accept public HTTPS reachability.',
        'Rust Hub still requires the access key for /ready and operational APIs after domain activation.',
      ],
    }));
  }

  if (providerAllowed(config, 'cloudflare')) {
    candidates.push(candidate('cloudflare', {
      config,
      candidate: selectedUrl ? 'cloudflare_tunnel_user_hostname' : 'waiting_for_cloudflare_hostname',
      scope: 'public_internet_managed_tunnel',
      installed: cloudflared.installed,
      detected_ready: cloudflared.installed && selectedUrl !== '',
      public_base_url: selectedUrl,
      setup_mutates: true,
      setup_commands: selectedUrl
        ? [
          'Create or reuse a Cloudflare Tunnel that forwards the chosen hostname to http://127.0.0.1:50151.',
          'Run the tunnel under launchd or another process manager before strict live smoke.',
        ]
        : [
          'Install/configure cloudflared, choose the final HTTPS hostname, then rerun with --public-base-url.',
        ],
      notes: [
        'Best fit for a user-owned domain and XT devices that are not on the same tailnet.',
      ],
    }));
  }

  const usable = candidates.filter((item) => item.public_base_url && item.route_gate?.ok === true);
  const ready = usable.filter((item) => item.detected_ready);
  const issues = [];
  if (!['auto', 'tailscale', 'cloudflare', 'reverse-proxy'].includes(config.provider)) {
    issues.push({ severity: 'blocker', code: 'provider_invalid', detail: `provider=${config.provider}` });
  }
  if (!selectedUrl && ready.length === 0) {
    issues.push({
      severity: 'warning',
      code: 'final_public_base_url_not_selected',
      detail: 'No explicit final domain/tunnel URL is configured yet. Use a generated tailnet URL or pass --public-base-url.',
    });
  }
  if (providerAllowed(config, 'cloudflare') && !cloudflared.installed && config.provider === 'cloudflare') {
    issues.push({ severity: 'warning', code: 'cloudflared_not_installed', detail: 'cloudflared was not found on PATH.' });
  }
  if (providerAllowed(config, 'tailscale') && !tailscale.installed && config.provider === 'tailscale') {
    issues.push({ severity: 'warning', code: 'tailscale_not_installed', detail: 'tailscale was not found on PATH.' });
  }
  const blockers = issues.filter((issue) => issue.severity === 'blocker');
  const recommended = ready[0] || usable[0] || candidates[0] || null;
  const report = {
    ok: blockers.length === 0,
    schema_version: 'xhub.rust_hub.cross_network_provider_candidate_plan.v1',
    command: 'cross-network-provider-candidate-plan',
    generated_at_iso: new Date().toISOString(),
    duration_ms: Date.now() - startedAt,
    root_dir: ROOT_DIR,
    provider: config.provider,
    public_base_url_input: selectedUrl,
    http_base_url: config.httpBaseUrl,
    access_key_file: {
      path: config.accessKeyFile,
      exists: fs.existsSync(config.accessKeyFile),
      key_printed: false,
    },
    local_detection: {
      tailscale,
      cloudflared,
    },
    candidates,
    recommendation: recommended ? {
      provider: recommended.provider,
      candidate: recommended.candidate,
      public_base_url: recommended.public_base_url,
      scope: recommended.scope,
      detected_ready: recommended.detected_ready,
      reason: recommended.detected_ready
        ? 'provider_detected_with_stable_url_candidate'
        : 'best_available_candidate_waiting_for_setup_or_final_url',
    } : null,
    readiness: {
      provider_candidate_count: candidates.length,
      usable_route_candidate_count: usable.length,
      detected_ready_candidate_count: ready.length,
      can_run_no_network_bundle_now: usable.length > 0,
      can_run_strict_live_bundle_now: ready.length > 0,
      activation_ready: false,
    },
    next_actions: recommended?.public_base_url ? [
      'Run the recommended readiness_bundle_planning command.',
      'Apply the provider setup command outside this planner only after reviewing the route scope.',
      'Run readiness_bundle_strict_live and domain_smoke_after_activation after the provider route is live.',
    ] : [
      'Choose a final HTTPS domain, tunnel hostname, or tailnet DNS endpoint.',
      'Rerun this planner with --public-base-url once the final user-facing URL is known.',
    ],
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
    ui_product_change: false,
    key_printed: false,
    secret_leak: false,
    issues,
  };
  report.secret_leak = /Bearer\s+(?!\[REDACTED\])\S+|access_key"\s*:\s*"(?!\[REDACTED\])|[a-f0-9]{64}/i.test(JSON.stringify(report));
  if (report.secret_leak) {
    report.ok = false;
    report.issues.push({ severity: 'blocker', code: 'secret_leak', detail: 'Report contained secret-looking material.' });
  }
  return report;
}

function mockTailscaleStatus() {
  return {
    Version: '1.98.1',
    BackendState: 'Running',
    TailscaleIPs: ['100.96.10.8'],
    Self: {
      DNSName: 'mini.tail000.ts.net.',
      HostName: 'mini',
    },
    CurrentTailnet: {
      Name: 'test-tailnet',
      MagicDNSSuffix: 'tail000.ts.net',
      MagicDNSEnabled: true,
    },
    Health: [],
  };
}

function runSelfTest() {
  const report = buildReport(parseArgs(['--provider', 'tailscale', '--no-external-detect']), {
    commandExists: (name) => name === 'tailscale',
    tailscaleStatus: mockTailscaleStatus(),
  });
  if (!report.ok || report.candidates.length !== 2) throw new Error('expected tailscale candidates');
  if (report.readiness.usable_route_candidate_count !== 2) throw new Error('expected usable tailnet URL candidates');
  if (!report.candidates.every((item) => item.public_base_url === 'https://mini.tail000.ts.net')) {
    throw new Error('expected normalized tailnet URL');
  }
  const custom = buildReport(parseArgs(['--provider', 'reverse-proxy', '--public-base-url', 'https://hub.example.test']), {
    commandExists: () => false,
  });
  if (!custom.ok || custom.readiness.usable_route_candidate_count !== 1) {
    throw new Error('expected custom reverse proxy candidate');
  }
}

function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    process.stdout.write('cross_network_provider_candidate_plan self-test ok\n');
    return;
  }
  const report = buildReport(config);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  process.exitCode = report.ok ? 0 : 2;
}

const invokedAsMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (invokedAsMain) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`[cross_network_provider_candidate_plan] ${error?.stack || error?.message || error}\n`);
    process.exit(1);
  }
}
