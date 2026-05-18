#!/usr/bin/env node
import { isIP } from 'node:net';
import { pathToFileURL } from 'node:url';

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

function parseArgs(argv) {
  const out = {
    publicBaseUrl: process.env.XHUB_RUST_HUB_PUBLIC_BASE_URL || '',
    remoteHost: process.env.XHUB_RUST_HUB_REMOTE_HOST || '',
    requireHttps: !parseBool(process.env.XHUB_RUST_REMOTE_ROUTE_ALLOW_HTTP, false),
    allowVpnRawHost: parseBool(process.env.XHUB_RUST_REMOTE_ROUTE_ALLOW_VPN_RAW_HOST, false),
    allowPublicRawIp: parseBool(process.env.XHUB_RUST_REMOTE_ROUTE_ALLOW_PUBLIC_RAW_IP, false),
    allowLoopbackPublicHost: false,
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
      case '--remote-host':
        out.remoteHost = safeString(next);
        i += 1;
        break;
      case '--allow-http':
        out.requireHttps = false;
        break;
      case '--allow-vpn-raw-host':
        out.allowVpnRawHost = true;
        break;
      case '--allow-public-raw-ip':
        out.allowPublicRawIp = true;
        break;
      case '--allow-loopback-public-host':
        out.allowLoopbackPublicHost = true;
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
    'cross_network_remote_route_gate.js',
    '',
    'Validate the public/domain remote route semantics before enabling XT off-LAN access.',
    '',
    'Options:',
    '  --public-base-url <url>       Public domain/tunnel URL, preferred',
    '  --remote-host <host>          Host-only fallback when no URL is available',
    '  --allow-vpn-raw-host          Explicitly allow raw VPN/tailnet/private IP hosts',
    '  --allow-public-raw-ip         Dev escape hatch for raw public IP hosts',
    '  --allow-loopback-public-host  Test-only loopback allowance',
    '  --allow-http                  Test/self-host escape hatch; HTTPS is required by default',
    '  --self-test',
  ].join('\n');
}

function normalizeHost(raw) {
  let value = safeString(raw).toLowerCase().replace(/\.$/, '');
  if (!value) return '';
  try {
    if (/^https?:\/\//i.test(value)) {
      value = new URL(value).hostname;
    }
  } catch {}
  value = value.replace(/^\[/, '').replace(/\]$/, '');
  if (value.includes(':') && !value.includes('::')) {
    const parts = value.split(':');
    if (parts.length === 2 && /^\d+$/.test(parts[1])) value = parts[0];
  }
  return value;
}

function classifyIPv4(host) {
  const parts = host.split('.');
  if (parts.length !== 4) return null;
  const octets = parts.map((part) => Number.parseInt(part, 10));
  if (!octets.every((n, idx) => String(n) === parts[idx] && n >= 0 && n <= 255)) return null;
  const [a, b] = octets;
  if (a === 0) return { kind: 'wildcard', scope: 'wildcard_ipv4', raw_ip: true, encrypted_ip_candidate: false };
  if (a === 127) return { kind: 'loopback', scope: 'loopback_ipv4', raw_ip: true, encrypted_ip_candidate: false };
  if (a === 169 && b === 254) return { kind: 'link_local', scope: 'link_local_ipv4', raw_ip: true, encrypted_ip_candidate: false };
  if (a === 100 && b >= 64 && b <= 127) return { kind: 'vpn_raw', scope: 'tailscale_headscale_ip', raw_ip: true, encrypted_ip_candidate: true };
  if (a === 10) return { kind: 'vpn_raw', scope: 'private_or_vpn_ip', raw_ip: true, encrypted_ip_candidate: true };
  if (a === 172 && b >= 16 && b <= 31) return { kind: 'vpn_raw', scope: 'private_or_vpn_ip', raw_ip: true, encrypted_ip_candidate: true };
  if (a === 192 && b === 168) return { kind: 'vpn_raw', scope: 'private_or_vpn_ip', raw_ip: true, encrypted_ip_candidate: true };
  return { kind: 'public_raw_ip', scope: 'public_ipv4', raw_ip: true, encrypted_ip_candidate: false };
}

function classifyIPv6(host) {
  const normalized = host.replace(/%.+$/, '');
  if (normalized === '::1') return { kind: 'loopback', scope: 'loopback_ipv6', raw_ip: true, encrypted_ip_candidate: false };
  if (normalized.startsWith('fe80:')) return { kind: 'link_local', scope: 'link_local_ipv6', raw_ip: true, encrypted_ip_candidate: false };
  if (normalized.startsWith('fc') || normalized.startsWith('fd')) {
    return { kind: 'vpn_raw', scope: 'unique_local_ipv6', raw_ip: true, encrypted_ip_candidate: true };
  }
  return { kind: 'public_raw_ip', scope: 'public_ipv6', raw_ip: true, encrypted_ip_candidate: false };
}

export function classifyRemoteHost(rawHost) {
  const host = normalizeHost(rawHost);
  if (!host) {
    return {
      kind: 'missing',
      scope: '',
      normalized: '',
      raw_ip: false,
      encrypted_ip_candidate: false,
      stable_named_entry: false,
      label: 'missing',
    };
  }
  if (host === '*' || host === '0.0.0.0' || host === '::') {
    return {
      kind: 'wildcard',
      scope: 'wildcard',
      normalized: host,
      raw_ip: true,
      encrypted_ip_candidate: false,
      stable_named_entry: false,
      label: 'wildcard bind address',
    };
  }
  const ipFamily = isIP(host);
  if (ipFamily === 4) {
    return {
      ...classifyIPv4(host),
      normalized: host,
      stable_named_entry: false,
      label: 'IPv4 host',
    };
  }
  if (ipFamily === 6) {
    return {
      ...classifyIPv6(host),
      normalized: host,
      stable_named_entry: false,
      label: 'IPv6 host',
    };
  }
  if (host === 'localhost' || host.endsWith('.local')) {
    return {
      kind: 'lan_only',
      scope: host === 'localhost' ? 'localhost_name' : 'mdns_lan_name',
      normalized: host,
      raw_ip: false,
      encrypted_ip_candidate: false,
      stable_named_entry: false,
      label: 'LAN-only name',
    };
  }
  if (!host.includes('.')) {
    return {
      kind: 'lan_only',
      scope: 'single_label_lan_name',
      normalized: host,
      raw_ip: false,
      encrypted_ip_candidate: false,
      stable_named_entry: false,
      label: 'single-label LAN name',
    };
  }
  const tailnet = host.endsWith('.ts.net') || host.endsWith('.tailscale.net');
  return {
    kind: 'stable_named',
    scope: tailnet ? 'tailnet_dns' : 'dns_name',
    normalized: host,
    raw_ip: false,
    encrypted_ip_candidate: tailnet,
    stable_named_entry: true,
    label: tailnet ? 'tailnet DNS name' : 'stable DNS name',
  };
}

function parseTarget(config) {
  const rawUrl = safeString(config.publicBaseUrl);
  if (rawUrl) {
    try {
      const parsed = new URL(rawUrl);
      return {
        ok: true,
        source: 'public_base_url',
        raw: rawUrl,
        scheme: parsed.protocol.replace(/:$/, ''),
        host: parsed.hostname,
        path: parsed.pathname || '/',
        parse_error: '',
      };
    } catch (error) {
      return {
        ok: false,
        source: 'public_base_url',
        raw: rawUrl,
        scheme: '',
        host: '',
        path: '',
        parse_error: safeString(error.message || error),
      };
    }
  }
  const host = normalizeHost(config.remoteHost);
  return {
    ok: host !== '',
    source: 'remote_host',
    raw: safeString(config.remoteHost),
    scheme: '',
    host,
    path: '',
    parse_error: host ? '' : 'remote_host_missing',
  };
}

function routeProfileFor(classification) {
  if (classification.kind === 'stable_named' && classification.scope === 'tailnet_dns') {
    return {
      route_kind: 'tailnet_dns',
      remote_transport: 'vpn_direct',
      security_profile: 'vpn_strict_access_key',
      official_entry_model: 'named_tailnet_entry',
    };
  }
  if (classification.kind === 'stable_named') {
    return {
      route_kind: 'stable_domain_or_tunnel',
      remote_transport: 'domain_tunnel_or_reverse_proxy',
      security_profile: 'https_access_key_gate',
      official_entry_model: 'named_domain_entry',
    };
  }
  if (classification.kind === 'vpn_raw') {
    return {
      route_kind: 'vpn_raw_host',
      remote_transport: 'vpn_direct',
      security_profile: 'vpn_strict_access_key',
      official_entry_model: 'explicit_self_hosted_vpn_host',
    };
  }
  if (classification.kind === 'public_raw_ip') {
    return {
      route_kind: 'unsafe_public_raw_ip',
      remote_transport: 'public_direct',
      security_profile: 'unsafe_public_dev_mode',
      official_entry_model: 'not_recommended',
    };
  }
  if (classification.kind === 'lan_only') {
    return {
      route_kind: 'lan_only',
      remote_transport: 'lan_only',
      security_profile: 'not_remote_ready',
      official_entry_model: 'not_remote_ready',
    };
  }
  return {
    route_kind: classification.kind,
    remote_transport: 'unavailable',
    security_profile: 'not_remote_ready',
    official_entry_model: 'not_remote_ready',
  };
}

function isPlaceholder(raw) {
  return /replace_with|example\.com/i.test(safeString(raw));
}

function collectIssues(config, target, classification) {
  const issues = [];
  const add = (severity, code, detail) => issues.push({ severity, code, detail });
  if (!target.raw) {
    add('blocker', 'remote_entry_missing', 'Set --public-base-url to a stable DNS, tailnet DNS, or explicit VPN/tunnel endpoint.');
    return issues;
  }
  if (!target.ok) {
    add('blocker', 'public_base_url_invalid', target.parse_error || 'invalid_url');
    return issues;
  }
  if (target.source === 'public_base_url' && !['http', 'https'].includes(target.scheme)) {
    add('blocker', 'public_base_url_must_be_http_or_https', `scheme=${target.scheme}`);
  }
  if (target.source === 'public_base_url' && config.requireHttps && target.scheme !== 'https') {
    add('blocker', 'https_required_for_remote_route', 'Real XT off-LAN routes must use HTTPS unless a test/self-host escape hatch is explicit.');
  }
  if (isPlaceholder(target.raw)) {
    add('blocker', 'public_base_url_placeholder', 'Replace example/placeholder host before activation.');
  }
  switch (classification.kind) {
    case 'missing':
      add('blocker', 'remote_host_missing', 'Remote host is empty.');
      break;
    case 'wildcard':
      add('blocker', 'remote_host_wildcard', 'Wildcard bind addresses are not valid XT remote route identities.');
      break;
    case 'loopback':
      if (!config.allowLoopbackPublicHost) {
        add('blocker', 'remote_host_loopback', 'Loopback is valid for local daemon management only, not off-LAN XT access.');
      }
      break;
    case 'lan_only':
      add('blocker', 'remote_host_lan_only', 'LAN-only names cannot be marked remote_ready.');
      break;
    case 'link_local':
      add('blocker', 'remote_host_link_local', 'Link-local hosts cannot be stable across networks.');
      break;
    case 'vpn_raw':
      if (!config.allowVpnRawHost) {
        add('blocker', 'vpn_raw_host_requires_explicit_allowance', 'Raw VPN/private/tailnet IP requires --allow-vpn-raw-host and must not be presented as a domain route.');
      }
      break;
    case 'public_raw_ip':
      if (!config.allowPublicRawIp) {
        add('blocker', 'public_raw_ip_forbidden', 'Raw public IP is brittle and not the default official remote access path.');
      }
      break;
    default:
      break;
  }
  return issues;
}

function recommendationsFor(classification) {
  if (classification.kind === 'stable_named' && classification.scope === 'tailnet_dns') {
    return [
      'Use this tailnet DNS name only when Hub and XT devices join the same Tailscale/Headscale network.',
      'Keep the Rust Hub public endpoint access-key gate enabled for /ready and operational APIs.',
    ];
  }
  if (classification.kind === 'stable_named') {
    return [
      'Use this named HTTPS endpoint behind a tunnel, reverse proxy, or future relay; avoid raw public Hub sockets.',
      'Export a pairing bundle only after the domain smoke proves unauthenticated /ready is rejected and authenticated /ready is ready.',
    ];
  }
  if (classification.kind === 'vpn_raw') {
    return [
      'Prefer MagicDNS/tailnet DNS over raw VPN IP for long-term XT settings.',
      'If a raw VPN IP is unavoidable, pass --allow-vpn-raw-host and document the VPN/tailnet dependency in the setup pack.',
    ];
  }
  return [
    'Choose a stable DNS name, tailnet DNS name, or managed tunnel endpoint before marking cross-network remote_ready.',
  ];
}

export function analyzeRemoteRoute(input = {}) {
  const config = {
    publicBaseUrl: safeString(input.publicBaseUrl),
    remoteHost: safeString(input.remoteHost),
    requireHttps: input.requireHttps !== false,
    allowVpnRawHost: input.allowVpnRawHost === true,
    allowPublicRawIp: input.allowPublicRawIp === true,
    allowLoopbackPublicHost: input.allowLoopbackPublicHost === true,
  };
  const target = parseTarget(config);
  const classification = classifyRemoteHost(target.host || config.remoteHost);
  const routeProfile = routeProfileFor(classification);
  const issues = collectIssues(config, target, classification);
  const blockers = issues.filter((issue) => issue.severity === 'blocker');
  const stableOrAllowedVpn = classification.kind === 'stable_named'
    || (classification.kind === 'vpn_raw' && config.allowVpnRawHost);
  return {
    ok: blockers.length === 0,
    target,
    host_classification: classification,
    route_profile: {
      ...routeProfile,
      remote_host: classification.normalized,
      remote_ready_candidate: blockers.length === 0 && stableOrAllowedVpn,
      cross_network_pairing_ready_semantics: blockers.length === 0 ? 'remote_ready_candidate_after_smoke' : 'blocked_until_fixed',
    },
    security_checks: {
      remote_host_present: classification.kind !== 'missing',
      stable_named_entry: classification.stable_named_entry === true,
      vpn_or_tunnel_semantics: classification.kind === 'stable_named' || classification.kind === 'vpn_raw',
      raw_public_ip_default_allowed: false,
      ready_requires_access_key: true,
      health_unauthenticated_only: true,
      remote_admin_enabled: false,
      file_ipc_counts_as_remote_ready: false,
      official_relay_default_ready: false,
    },
    recommendations: recommendationsFor(classification),
    issues,
  };
}

function hasSecretLeak(value) {
  return /Bearer\s+(?!\[REDACTED\])\S+|access_key"\s*:\s*"(?!\[REDACTED\])|[a-f0-9]{64}/i.test(JSON.stringify(value));
}

function runSelfTest() {
  const goodDns = analyzeRemoteRoute({ publicBaseUrl: 'https://hub.example.test' });
  if (!goodDns.ok || goodDns.host_classification.scope !== 'dns_name') throw new Error('stable DNS should pass');
  const tailnet = analyzeRemoteRoute({ publicBaseUrl: 'https://mini.tail000.ts.net' });
  if (!tailnet.ok || tailnet.host_classification.scope !== 'tailnet_dns') throw new Error('tailnet DNS should pass');
  const vpnRawBlocked = analyzeRemoteRoute({ publicBaseUrl: 'https://100.96.10.8' });
  if (vpnRawBlocked.ok || !vpnRawBlocked.issues.some((issue) => issue.code === 'vpn_raw_host_requires_explicit_allowance')) {
    throw new Error('raw VPN host must require explicit allowance');
  }
  const vpnRawAllowed = analyzeRemoteRoute({ publicBaseUrl: 'https://100.96.10.8', allowVpnRawHost: true });
  if (!vpnRawAllowed.ok || vpnRawAllowed.route_profile.route_kind !== 'vpn_raw_host') throw new Error('allowed raw VPN host should pass');
  const publicIp = analyzeRemoteRoute({ publicBaseUrl: 'https://17.81.11.116' });
  if (publicIp.ok || !publicIp.issues.some((issue) => issue.code === 'public_raw_ip_forbidden')) {
    throw new Error('raw public IP must be blocked');
  }
  const lanName = analyzeRemoteRoute({ publicBaseUrl: 'https://hub.local' });
  if (lanName.ok || !lanName.issues.some((issue) => issue.code === 'remote_host_lan_only')) throw new Error('LAN-only name must be blocked');
  const http = analyzeRemoteRoute({ publicBaseUrl: 'http://hub.example.test' });
  if (http.ok || !http.issues.some((issue) => issue.code === 'https_required_for_remote_route')) throw new Error('HTTP should be blocked by default');
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    process.stdout.write('cross_network_remote_route_gate self-test ok\n');
    return;
  }
  const analysis = analyzeRemoteRoute(config);
  const report = {
    ok: analysis.ok,
    schema_version: 'xhub.rust_hub.cross_network_remote_route_gate.v1',
    command: 'cross-network-remote-route-gate',
    generated_at_iso: new Date().toISOString(),
    public_base_url: safeString(config.publicBaseUrl),
    remote_host_input: safeString(config.remoteHost),
    require_https: config.requireHttps,
    allow_vpn_raw_host: config.allowVpnRawHost,
    allow_public_raw_ip: config.allowPublicRawIp,
    allow_loopback_public_host: config.allowLoopbackPublicHost,
    ...analysis,
    key_printed: false,
    production_authority_change: false,
    ui_product_change: false,
    secret_leak: false,
  };
  report.secret_leak = hasSecretLeak(report);
  if (report.secret_leak) {
    report.ok = false;
    report.issues.push({ severity: 'blocker', code: 'secret_leak', detail: 'Report contained secret-looking material.' });
  }
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  process.exit(report.ok ? 0 : 2);
}

const invokedAsMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (invokedAsMain) {
  main().catch((error) => {
    process.stderr.write(`[cross_network_remote_route_gate] ${error?.stack || error?.message || error}\n`);
    process.exit(1);
  });
}
