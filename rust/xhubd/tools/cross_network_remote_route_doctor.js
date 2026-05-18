#!/usr/bin/env node
import dns from 'node:dns/promises';
import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import os from 'node:os';
import { pathToFileURL } from 'node:url';
import { analyzeRemoteRoute } from './cross_network_remote_route_gate.js';

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

function parseArgs(argv) {
  const out = {
    publicBaseUrl: process.env.XHUB_RUST_HUB_PUBLIC_BASE_URL || '',
    remoteHost: process.env.XHUB_RUST_HUB_REMOTE_HOST || '',
    accessKeyFile: process.env.XHUB_RUST_HTTP_ACCESS_KEY_FILE || '',
    timeoutMs: 10000,
    noNetwork: false,
    requireHttps: !parseBool(process.env.XHUB_RUST_REMOTE_ROUTE_ALLOW_HTTP, false),
    allowVpnRawHost: parseBool(process.env.XHUB_RUST_REMOTE_ROUTE_ALLOW_VPN_RAW_HOST, false),
    allowPublicRawIp: parseBool(process.env.XHUB_RUST_REMOTE_ROUTE_ALLOW_PUBLIC_RAW_IP, false),
    allowLoopbackPublicHost: false,
    requireLiveHttp: false,
    requireAuthReady: false,
    expectAuthRequired: true,
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
      case '--access-key-file':
        out.accessKeyFile = safeString(next);
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 250, 120000);
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
      case '--no-expect-auth-required':
        out.expectAuthRequired = false;
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
    'cross_network_remote_route_doctor.js',
    '',
    'Diagnose a planned or live XT off-LAN Rust Hub route without mutating state.',
    '',
    'Options:',
    '  --public-base-url <url>       Public domain/tunnel URL',
    '  --remote-host <host>          Host-only fallback when no URL is available',
    '  --access-key-file <path>      Optional key file for authenticated /ready probe',
    '  --timeout-ms <n>              HTTP/DNS timeout budget, default 10000',
    '  --no-network                  Skip DNS and HTTP probes',
    '  --require-live-http           Fail when /health is unreachable',
    '  --require-auth-ready          Require authenticated /ready=true',
    '  --no-expect-auth-required     Do not require unauthenticated /ready rejection',
    '  --allow-vpn-raw-host          Explicitly allow raw VPN/tailnet/private IP hosts',
    '  --allow-public-raw-ip         Dev escape hatch for raw public IP hosts',
    '  --allow-loopback-public-host  Test-only loopback allowance',
    '  --allow-http                  Test/self-host escape hatch; HTTPS is required by default',
    '  --self-test',
  ].join('\n');
}

function endpoint(baseUrl, pathname) {
  return new URL(pathname, baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`);
}

function withTimeout(promise, timeoutMs, fallback) {
  let timer;
  return Promise.race([
    promise.finally(() => clearTimeout(timer)),
    new Promise((resolve) => {
      timer = setTimeout(() => resolve(fallback), timeoutMs);
    }),
  ]);
}

async function resolveDns(host, timeoutMs, noNetwork) {
  if (noNetwork) return { skipped: true, a: [], aaaa: [], error: 'network_skipped' };
  if (!host || /^[0-9.]+$/.test(host) || host.includes(':')) {
    return { skipped: true, a: [], aaaa: [], error: 'dns_not_needed_for_ip_or_missing_host' };
  }
  const out = { skipped: false, a: [], aaaa: [], error: '' };
  const resolved = await withTimeout((async () => {
    try {
      out.a = await dns.resolve4(host);
    } catch (error) {
      out.error = safeString(error.code || error.message || error);
    }
    try {
      out.aaaa = await dns.resolve6(host);
    } catch {}
    return out;
  })(), timeoutMs, { skipped: false, a: [], aaaa: [], error: 'dns_timeout' });
  return resolved;
}

function requestJson(url, { timeoutMs, accessKey = '', lookupAddress = '' }) {
  return new Promise((resolve) => {
    const started = Date.now();
    const client = url.protocol === 'https:' ? https : http;
    const headers = { accept: 'application/json' };
    if (accessKey) headers.Authorization = `Bearer ${accessKey}`;
    const requestUrl = new URL(url.href);
    const options = { timeout: timeoutMs, headers };
    if (lookupAddress) {
      headers.Host = url.host;
      options.servername = url.hostname;
      requestUrl.hostname = lookupAddress;
    }
    const req = client.get(requestUrl, options, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        body += chunk;
        if (body.length > 1024 * 1024) req.destroy(new Error('response_too_large'));
      });
      res.on('end', () => {
        let json = null;
        let parseError = '';
        try {
          json = body ? JSON.parse(body) : null;
        } catch (error) {
          parseError = safeString(error.message || error);
        }
        resolve({
          ok: Number(res.statusCode || 0) >= 200 && Number(res.statusCode || 0) < 300,
          status_code: Number(res.statusCode || 0),
          duration_ms: Date.now() - started,
          json,
          parse_error: parseError,
          error: '',
        });
      });
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', (error) => resolve({
      ok: false,
      status_code: 0,
      duration_ms: Date.now() - started,
      json: null,
      parse_error: '',
      error: safeString(error.code || error.message || error),
    }));
  });
}

function readAccessKey(filePath) {
  const path = safeString(filePath);
  if (!path) return { configured: false, readable: false, empty: true, path: '', key: '', error: 'access_key_file_not_configured' };
  try {
    const key = fs.readFileSync(path, 'utf8').trim();
    return { configured: true, readable: true, empty: key.length === 0, path, key, error: key ? '' : 'access_key_file_empty' };
  } catch (error) {
    return { configured: true, readable: false, empty: true, path, key: '', error: safeString(error.code || error.message || error) };
  }
}

function redactHttp(step) {
  return {
    skipped: step?.skipped === true,
    ok: step?.ok === true,
    status_code: Number(step?.status_code || 0),
    duration_ms: Number(step?.duration_ms || 0),
    error: safeString(step?.error || ''),
    parse_error: safeString(step?.parse_error || ''),
    body_ok: step?.json?.ok === true,
    ready: step?.json?.ready === true,
    cross_network_ready: step?.json?.capabilities?.cross_network_ready === true,
    domain_public_endpoint_ready: step?.json?.capabilities?.domain_public_endpoint_ready === true,
    cross_network_auth_gate: step?.json?.capabilities?.cross_network_auth_gate === true,
    http_access_key_required: step?.json?.network?.http_access_key_required === true,
    http_access_key_configured: step?.json?.network?.http_access_key_configured === true,
    public_endpoint_ready: step?.json?.network?.public_endpoint_ready === true,
  };
}

function parseTailscaleIPv4s(text) {
  const matches = safeString(text).match(/\b100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.(?:25[0-5]|2[0-4]\d|1?\d?\d)\.(?:25[0-5]|2[0-4]\d|1?\d?\d)\b/g);
  return [...new Set(matches || [])];
}

function localTailnetState() {
  const addresses = [];
  for (const [name, rows] of Object.entries(os.networkInterfaces())) {
    for (const row of rows || []) {
      if (row.family === 'IPv4') {
        for (const ip of parseTailscaleIPv4s(row.address)) {
          addresses.push({ interface: name, family: 'IPv4', address: ip });
        }
      } else if (row.family === 'IPv6' && /^fd7a:115c:a1e0:/i.test(row.address)) {
        addresses.push({ interface: name, family: 'IPv6', address: row.address });
      }
    }
  }
  return {
    tailnet_interface_present: addresses.length > 0,
    addresses,
  };
}

function tailnetLookupAddress(route, tailnet) {
  if (route.host_classification.scope !== 'tailnet_dns') return '';
  const v4 = tailnet.addresses.find((item) => item.family === 'IPv4')?.address || '';
  const v6 = tailnet.addresses.find((item) => item.family === 'IPv6')?.address || '';
  return v4 || v6;
}

function withTailnetDnsFallback(dnsInfo, route, tailnet) {
  const lookupAddress = tailnetLookupAddress(route, tailnet);
  if (!lookupAddress || dnsInfo.skipped || dnsInfo.a.length || dnsInfo.aaaa.length) return dnsInfo;
  return {
    ...dnsInfo,
    a: lookupAddress.includes(':') ? [] : [lookupAddress],
    aaaa: lookupAddress.includes(':') ? [lookupAddress] : [],
    error: '',
    fallback: 'local_tailnet_interface',
  };
}

async function buildReport(config) {
  const startedAt = Date.now();
  const route = analyzeRemoteRoute({
    publicBaseUrl: config.publicBaseUrl,
    remoteHost: config.remoteHost,
    requireHttps: config.requireHttps,
    allowVpnRawHost: config.allowVpnRawHost,
    allowPublicRawIp: config.allowPublicRawIp,
    allowLoopbackPublicHost: config.allowLoopbackPublicHost,
  });
  const publicBaseUrl = safeString(config.publicBaseUrl || route.target.raw);
  const host = safeString(route.host_classification.normalized);
  const tailnet = localTailnetState();
  const dnsInfo = withTailnetDnsFallback(
    await resolveDns(host, config.timeoutMs, config.noNetwork),
    route,
    tailnet,
  );
  const keyState = readAccessKey(config.accessKeyFile);
  const lookupAddress = tailnetLookupAddress(route, tailnet);
  const checks = {
    health: { skipped: true },
    ready_without_key: { skipped: true },
    ready_with_key: { skipped: true },
  };

  if (!config.noNetwork && publicBaseUrl && route.target.ok) {
    checks.health = await requestJson(endpoint(publicBaseUrl, '/health'), {
      timeoutMs: config.timeoutMs,
      lookupAddress,
    });
    checks.ready_without_key = await requestJson(endpoint(publicBaseUrl, '/ready'), {
      timeoutMs: config.timeoutMs,
      lookupAddress,
    });
    if (keyState.readable && !keyState.empty) {
      checks.ready_with_key = await requestJson(endpoint(publicBaseUrl, '/ready'), {
        timeoutMs: config.timeoutMs,
        accessKey: keyState.key,
        lookupAddress,
      });
    }
  }

  const issues = route.issues.map((issue) => ({
    severity: issue.severity,
    code: `route_gate_${issue.code}`,
    detail: issue.detail,
  }));
  const add = (severity, code, detail) => issues.push({ severity, code, detail });

  if (!dnsInfo.skipped
      && route.host_classification.kind === 'stable_named'
      && dnsInfo.a.length === 0
      && dnsInfo.aaaa.length === 0) {
    add(config.requireLiveHttp ? 'blocker' : 'warning', 'dns_has_no_address_records', dnsInfo.error || `${host} has no A/AAAA records.`);
  }
  if ((route.host_classification.scope === 'tailnet_dns' || route.host_classification.scope === 'tailscale_headscale_ip')
      && !tailnet.tailnet_interface_present) {
    add('warning', 'local_tailnet_interface_missing', 'No local Tailscale/Headscale interface address was observed on this machine.');
  }
  if (config.requireLiveHttp && checks.health.ok !== true) {
    add('blocker', 'health_unavailable', checks.health.error || `status=${checks.health.status_code || 0}`);
  }
  if (!config.noNetwork && checks.health.ok === true && checks.health.json?.ok !== true) {
    add(config.requireLiveHttp ? 'blocker' : 'warning', 'health_body_not_ok', 'Public /health responded but did not return ok=true.');
  }
  if (!config.noNetwork
      && config.expectAuthRequired
      && checks.ready_without_key.status_code
      && ![401, 403].includes(Number(checks.ready_without_key.status_code || 0))) {
    add('blocker', 'unauthenticated_ready_not_rejected', `status=${checks.ready_without_key.status_code}`);
  }
  if (config.requireAuthReady && (!keyState.readable || keyState.empty)) {
    add('blocker', 'access_key_file_unavailable', keyState.error || 'access key file missing or empty');
  }
  if (config.requireAuthReady && checks.ready_with_key.ok !== true) {
    add('blocker', 'authenticated_ready_unavailable', checks.ready_with_key.error || `status=${checks.ready_with_key.status_code || 0}`);
  }
  if (config.requireAuthReady && checks.ready_with_key.json?.ready !== true) {
    add('blocker', 'authenticated_ready_false', 'Authenticated /ready did not return ready=true.');
  }
  if (config.requireAuthReady && checks.ready_with_key.json?.capabilities?.cross_network_ready !== true) {
    add('blocker', 'authenticated_ready_cross_network_not_ready', 'Authenticated /ready did not report capabilities.cross_network_ready=true.');
  }
  if (config.requireAuthReady
      && checks.ready_with_key.json?.network
      && safeString(checks.ready_with_key.json.network.public_base_url) !== publicBaseUrl) {
    add('blocker', 'authenticated_ready_public_base_url_mismatch', `ready public_base_url=${checks.ready_with_key.json.network.public_base_url || ''}`);
  }
  if (config.requireAuthReady
      && route.host_classification.scope === 'tailnet_dns'
      && checks.ready_with_key.json?.capabilities?.domain_public_endpoint_ready !== true) {
    add('blocker', 'authenticated_ready_domain_public_endpoint_not_ready', 'Authenticated /ready did not report capabilities.domain_public_endpoint_ready=true.');
  }

  const blockers = issues.filter((issue) => issue.severity === 'blocker');
  const report = {
    ok: blockers.length === 0,
    schema_version: 'xhub.rust_hub.cross_network_remote_route_doctor.v1',
    command: 'cross-network-remote-route-doctor',
    generated_at_iso: new Date().toISOString(),
    duration_ms: Date.now() - startedAt,
    public_base_url: publicBaseUrl,
    no_network: config.noNetwork,
    require_live_http: config.requireLiveHttp,
    require_auth_ready: config.requireAuthReady,
    expect_auth_required: config.expectAuthRequired,
    route_gate: {
      ok: route.ok,
      target: route.target,
      host_classification: route.host_classification,
      route_profile: route.route_profile,
      security_checks: route.security_checks,
      issues: route.issues,
    },
    dns: dnsInfo,
    tailnet,
    access_key_file: {
      configured: keyState.configured,
      readable: keyState.readable,
      empty: keyState.empty,
      path: keyState.path,
      error: keyState.error,
      key_printed: false,
    },
    http_checks: {
      health: redactHttp(checks.health),
      ready_without_key: redactHttp(checks.ready_without_key),
      ready_with_key: redactHttp(checks.ready_with_key),
    },
    recommendations: [
      ...route.recommendations,
      'Run cross_network_domain_smoke.command after activation to strictly prove public /health, unauthorized /ready rejection, and authenticated /ready.',
    ],
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
    ui_product_change: false,
    key_printed: false,
    secret_leak: false,
    issues,
  };
  report.secret_leak = hasSecretLeak(report);
  if (report.secret_leak) {
    report.ok = false;
    report.issues.push({ severity: 'blocker', code: 'secret_leak', detail: 'Report contained secret-looking material.' });
  }
  return report;
}

function hasSecretLeak(value) {
  return /Bearer\s+(?!\[REDACTED\])\S+|access_key"\s*:\s*"(?!\[REDACTED\])|[a-f0-9]{64}/i.test(JSON.stringify(value));
}

async function runSelfTest() {
  const stable = await buildReport({ ...parseArgs(['--public-base-url', 'https://hub.example.test', '--no-network']) });
  if (!stable.ok || stable.route_gate.host_classification.scope !== 'dns_name') {
    throw new Error('stable HTTPS DNS no-network doctor should pass');
  }
  const publicIp = await buildReport({ ...parseArgs(['--public-base-url', 'https://17.81.11.116', '--no-network']) });
  if (publicIp.ok || !publicIp.issues.some((issue) => issue.code === 'route_gate_public_raw_ip_forbidden')) {
    throw new Error('raw public IP should be blocked by doctor');
  }
  const vpn = await buildReport({ ...parseArgs(['--public-base-url', 'https://100.96.10.8', '--allow-vpn-raw-host', '--no-network']) });
  if (!vpn.ok || vpn.route_gate.route_profile.route_kind !== 'vpn_raw_host') {
    throw new Error('explicit raw VPN host should pass no-network doctor');
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
    process.stdout.write('cross_network_remote_route_doctor self-test ok\n');
    return;
  }
  const report = await buildReport(config);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  process.exit(report.ok ? 0 : 2);
}

const invokedAsMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (invokedAsMain) {
  main().catch((error) => {
    process.stderr.write(`[cross_network_remote_route_doctor] ${error?.stack || error?.message || error}\n`);
    process.exit(1);
  });
}
