#!/usr/bin/env node
'use strict';

const childProcess = require('node:child_process');
const dns = require('node:dns').promises;
const fs = require('node:fs');
const http = require('node:http');
const https = require('node:https');
const net = require('node:net');
const os = require('node:os');

const DEFAULT_GRPC_PORT = 50058;
const DEFAULT_TIMEOUT_MS = 5000;

function safeString(value) {
  return String(value ?? '').trim();
}

function parseArgs(argv) {
  const out = {
    host: '',
    grpcPort: 0,
    pairingPort: 0,
    timeoutMs: DEFAULT_TIMEOUT_MS,
    json: false,
    noNetwork: false,
    selfTest: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--host':
        out.host = safeString(next);
        i += 1;
        break;
      case '--grpc-port':
        out.grpcPort = parsePort(next, 0);
        i += 1;
        break;
      case '--pairing-port':
        out.pairingPort = parsePort(next, 0);
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = Math.max(250, Math.min(120000, Number.parseInt(String(next || ''), 10) || DEFAULT_TIMEOUT_MS));
        i += 1;
        break;
      case '--json':
        out.json = true;
        break;
      case '--no-network':
        out.noNetwork = true;
        break;
      case '--self-test':
        out.selfTest = true;
        break;
      case '--help':
      case '-h':
        printHelp();
        process.exit(0);
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }
  return out;
}

function parsePort(value, fallback) {
  const n = Number.parseInt(String(value || ''), 10);
  if (!Number.isFinite(n) || n < 1 || n > 65535) return fallback;
  return n;
}

function execText(command, args, timeoutMs = 3000) {
  try {
    return {
      ok: true,
      stdout: childProcess.execFileSync(command, args, {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
        timeout: timeoutMs,
      }).trim(),
      stderr: '',
      error: '',
    };
  } catch (error) {
    return {
      ok: false,
      stdout: safeString(error.stdout),
      stderr: safeString(error.stderr),
      error: safeString(error.message || error),
    };
  }
}

function uniqueStrings(values) {
  return [...new Set(values.map(safeString).filter(Boolean))];
}

function isTailscaleCliFailure(text) {
  const value = safeString(text).toLowerCase();
  return value.includes('tailscale cli failed to start')
    || value.includes('failed to load preferences')
    || value.includes('failed to connect to local tailscaled');
}

function parseTailscaleIPv4s(text) {
  const matches = safeString(text).match(/\b100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.(?:25[0-5]|2[0-4]\d|1?\d?\d)\.(?:25[0-5]|2[0-4]\d|1?\d?\d)\b/g);
  return uniqueStrings(matches || []);
}

function tailscaleIPv4sFromInterfaces() {
  const ips = [];
  for (const addrs of Object.values(os.networkInterfaces())) {
    for (const addr of addrs || []) {
      if (addr.family !== 'IPv4') continue;
      ips.push(...parseTailscaleIPv4s(addr.address));
    }
  }
  return uniqueStrings(ips);
}

function commandLinesContaining(needle) {
  const out = execText('/bin/ps', ['ax', '-o', 'pid=,command='], 2000);
  if (!out.ok) return [];
  return out.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.includes(needle));
}

function readDefault(domain, key) {
  const out = execText('/usr/bin/defaults', ['read', domain, key], 1000);
  return out.ok ? safeString(out.stdout).replace(/^"|"$/g, '') : '';
}

function configuredDefaults() {
  const grpcPort = parsePort(readDefault('com.rel.flowhub', 'relflowhub_grpc_port'), DEFAULT_GRPC_PORT);
  return {
    host: readDefault('com.rel.flowhub', 'relflowhub_grpc_internet_host_override'),
    grpcPort,
    pairingPort: grpcPort + 1,
  };
}

function normalizeHost(raw) {
  let value = safeString(raw);
  if (!value) return '';
  try {
    if (/^https?:\/\//i.test(value)) value = new URL(value).hostname;
  } catch {}
  value = value.replace(/^\[/, '').replace(/\]$/, '');
  if (value.includes(':') && !value.includes('::')) {
    const parts = value.split(':');
    if (parts.length === 2 && /^\d+$/.test(parts[1])) value = parts[0];
  }
  return value.toLowerCase().replace(/\.$/, '');
}

function classifyHost(raw) {
  const host = normalizeHost(raw);
  if (!host) return { kind: 'missing', scope: '', normalized: '', encrypted_ip_candidate: false, label: 'missing' };
  if (host === 'localhost' || host.endsWith('.local')) {
    return { kind: 'lan_only', scope: 'lan_name', normalized: host, encrypted_ip_candidate: false, label: 'LAN-only host' };
  }
  const ipv4 = classifyIPv4(host);
  if (ipv4) {
    return {
      kind: 'raw_ip',
      scope: ipv4.scope,
      normalized: host,
      encrypted_ip_candidate: ipv4.encrypted,
      label: ipv4.label,
    };
  }
  if (host === '::1') {
    return { kind: 'raw_ip', scope: 'loopback', normalized: host, encrypted_ip_candidate: false, label: 'loopback IPv6' };
  }
  if (host.startsWith('fe80:')) {
    return { kind: 'raw_ip', scope: 'link_local', normalized: host, encrypted_ip_candidate: false, label: 'link-local IPv6' };
  }
  if (host.startsWith('fc') || host.startsWith('fd')) {
    return { kind: 'raw_ip', scope: 'unique_local_ipv6', normalized: host, encrypted_ip_candidate: true, label: 'VPN/private IPv6 candidate' };
  }
  if (host.includes(':')) {
    return { kind: 'raw_ip', scope: 'public_ipv6', normalized: host, encrypted_ip_candidate: false, label: 'public IPv6' };
  }
  if (host.includes('.')) {
    const tailnet = host.endsWith('.ts.net') || host.endsWith('.tailscale.net');
    return {
      kind: 'stable_named',
      scope: tailnet ? 'tailnet_dns' : 'dns_name',
      normalized: host,
      encrypted_ip_candidate: tailnet,
      label: tailnet ? 'tailnet/MagicDNS name' : 'stable DNS name',
    };
  }
  return { kind: 'lan_only', scope: 'single_label', normalized: host, encrypted_ip_candidate: false, label: 'single-label LAN host' };
}

function classifyIPv4(host) {
  const parts = host.split('.');
  if (parts.length !== 4) return null;
  const octets = parts.map((part) => Number.parseInt(part, 10));
  if (!octets.every((n, idx) => String(n) === parts[idx] && n >= 0 && n <= 255)) return null;
  const [a, b] = octets;
  if (a === 127) return { scope: 'loopback', encrypted: false, label: 'loopback IP' };
  if (a === 169 && b === 254) return { scope: 'link_local', encrypted: false, label: 'link-local IP' };
  if (a === 100 && b >= 64 && b <= 127) return { scope: 'tailscale_headscale_ip', encrypted: true, label: 'Tailscale/Headscale encrypted IP candidate' };
  if (a === 10) return { scope: 'private_or_vpn_ip', encrypted: true, label: 'private/VPN IP candidate' };
  if (a === 172 && b >= 16 && b <= 31) return { scope: 'private_or_vpn_ip', encrypted: true, label: 'private/VPN IP candidate' };
  if (a === 192 && b === 168) return { scope: 'private_or_vpn_ip', encrypted: true, label: 'private/LAN IP candidate' };
  return { scope: 'public_internet_ip', encrypted: false, label: 'public raw IP' };
}

function localIPv4Addresses() {
  const rows = [];
  for (const [name, addrs] of Object.entries(os.networkInterfaces())) {
    for (const addr of addrs || []) {
      if (addr.family !== 'IPv4' || addr.internal) continue;
      rows.push({ interface: name, address: addr.address });
    }
  }
  return rows;
}

function urlHost(host) {
  return host.includes(':') && !host.startsWith('[') ? `[${host}]` : host;
}

function connectTcp(host, port, timeoutMs) {
  return new Promise((resolve) => {
    const started = Date.now();
    const socket = net.createConnection({ host, port });
    let done = false;
    function finish(ok, error = '') {
      if (done) return;
      done = true;
      socket.destroy();
      resolve({ ok, port, duration_ms: Date.now() - started, error: safeString(error) });
    }
    socket.setTimeout(timeoutMs);
    socket.once('connect', () => finish(true));
    socket.once('timeout', () => finish(false, 'timeout'));
    socket.once('error', (error) => finish(false, error.code || error.message || error));
  });
}

function httpJson(url, timeoutMs) {
  return new Promise((resolve) => {
    const started = Date.now();
    const client = url.startsWith('https://') ? https : http;
    const req = client.get(url, { timeout: timeoutMs, headers: { accept: 'application/json' } }, (res) => {
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
          ok: Number(res.statusCode || 0) >= 200 && Number(res.statusCode || 0) < 300 && !parseError,
          status_code: Number(res.statusCode || 0),
          duration_ms: Date.now() - started,
          json,
          parse_error: parseError,
          error: '',
        });
      });
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', (error) => {
      resolve({ ok: false, status_code: 0, duration_ms: Date.now() - started, json: null, parse_error: '', error: safeString(error.code || error.message || error) });
    });
  });
}

function textRequest(url, timeoutMs) {
  return new Promise((resolve) => {
    const client = url.startsWith('https://') ? https : http;
    const req = client.get(url, { timeout: timeoutMs }, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        body += chunk;
        if (body.length > 4096) req.destroy(new Error('response_too_large'));
      });
      res.on('end', () => resolve({ ok: res.statusCode >= 200 && res.statusCode < 300, body: body.trim(), error: '' }));
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', (error) => resolve({ ok: false, body: '', error: safeString(error.code || error.message || error) }));
  });
}

async function resolveDns(host) {
  if (!host || classifyHost(host).kind !== 'stable_named') return { a: [], aaaa: [], ns: [], error: '' };
  const out = { a: [], aaaa: [], ns: [], error: '' };
  try {
    out.a = await dns.resolve4(host);
  } catch (error) {
    out.error = safeString(error.code || error.message || error);
  }
  try {
    out.aaaa = await dns.resolve6(host);
  } catch {}
  try {
    out.ns = await dns.resolveNs(apexCandidate(host));
  } catch {}
  return out;
}

function apexCandidate(host) {
  const parts = host.split('.').filter(Boolean);
  return parts.length >= 2 ? parts.slice(-2).join('.') : host;
}

async function tailscaleState() {
  const bin = execText('/usr/bin/env', ['which', 'tailscale'], 1000);
  const appPath = '/Applications/Tailscale.app';
  const appInstalled = fs.existsSync(appPath);
  const appProcesses = commandLinesContaining('/Applications/Tailscale.app/Contents/MacOS/Tailscale');
  const extensionProcesses = commandLinesContaining('io.tailscale.ipn.macsys.network-extension');
  if ((!bin.ok || !bin.stdout) && !appInstalled) {
    return { installed: false, path: '', running: false, ips: [], status_ok: false, error: 'tailscale_not_installed', service_hint: '' };
  }
  const path = bin.ok && bin.stdout ? bin.stdout.split('\n')[0] : `${appPath}/Contents/MacOS/Tailscale`;
  const status = execText(path, ['status'], 3000);
  const ip = execText(path, ['ip', '-4'], 3000);
  const statusText = safeString(`${status.stdout}\n${status.stderr}\n${status.error}`);
  const ipText = safeString(`${ip.stdout}\n${ip.stderr}\n${ip.error}`);
  const cliUsable = status.ok && !isTailscaleCliFailure(statusText);
  const cliIps = ip.ok && !isTailscaleCliFailure(ipText) ? parseTailscaleIPv4s(ip.stdout) : [];
  const interfaceIps = tailscaleIPv4sFromInterfaces();
  const logPath = '/opt/homebrew/var/log/tailscaled.log';
  let serviceHint = '';
  try {
    const tail = fs.readFileSync(logPath, 'utf8').split(/\r?\n/).slice(-120).join('\n');
    if (tail.includes('tailscaled requires root')) {
      serviceHint = 'homebrew_user_launchagent_requires_root_or_userspace_networking';
    }
  } catch {}
  if (!serviceHint && appInstalled && interfaceIps.length > 0 && !cliUsable) {
    serviceHint = 'official_macos_app_active_cli_unavailable';
  } else if (!serviceHint && appInstalled && appProcesses.length > 0 && interfaceIps.length === 0) {
    serviceHint = 'official_macos_app_running_but_no_tailscale_ip';
  }
  const ips = uniqueStrings([...cliIps, ...interfaceIps]);
  const running = cliUsable || ips.length > 0;
  return {
    installed: true,
    path,
    running,
    ips,
    status_ok: cliUsable,
    error: cliUsable ? '' : safeString(status.stderr || status.stdout || status.error),
    service_hint: serviceHint,
    macos_app: {
      installed: appInstalled,
      app_process_running: appProcesses.length > 0,
      network_extension_running: extensionProcesses.length > 0,
    },
  };
}

async function buildReport(args) {
  const defaults = configuredDefaults();
  const host = normalizeHost(args.host || process.env.XHUB_REMOTE_HOST || defaults.host);
  const grpcPort = args.grpcPort || parsePort(process.env.XHUB_GRPC_PORT, defaults.grpcPort || DEFAULT_GRPC_PORT);
  const pairingPort = args.pairingPort || parsePort(process.env.XHUB_PAIRING_PORT, defaults.pairingPort || grpcPort + 1);
  const classification = classifyHost(host);
  const lanAddresses = localIPv4Addresses();
  const publicIp = args.noNetwork ? { ok: false, body: '', error: 'network_skipped' } : await textRequest('https://ifconfig.me/ip', args.timeoutMs);
  const dnsInfo = args.noNetwork ? { a: [], aaaa: [], ns: [], error: 'network_skipped' } : await resolveDns(host);
  const tailscale = await tailscaleState();

  const localTargets = [
    { name: 'loopback', host: '127.0.0.1' },
    ...lanAddresses.map((row) => ({ name: row.interface, host: row.address })),
  ];
  const local = [];
  for (const target of localTargets) {
    local.push({
      name: target.name,
      host: target.host,
      grpc: await connectTcp(target.host, grpcPort, args.timeoutMs),
      pairing: await connectTcp(target.host, pairingPort, args.timeoutMs),
    });
  }

  const remote = host && !args.noNetwork ? {
    grpc: await connectTcp(host, grpcPort, args.timeoutMs),
    pairing: await connectTcp(host, pairingPort, args.timeoutMs),
    discovery: await httpJson(`http://${urlHost(host)}:${pairingPort}/pairing/discovery`, args.timeoutMs),
  } : {
    grpc: { ok: false, port: grpcPort, duration_ms: 0, error: host ? 'network_skipped' : 'host_missing' },
    pairing: { ok: false, port: pairingPort, duration_ms: 0, error: host ? 'network_skipped' : 'host_missing' },
    discovery: { ok: false, status_code: 0, duration_ms: 0, json: null, parse_error: '', error: host ? 'network_skipped' : 'host_missing' },
  };

  const issues = collectIssues({
    host,
    grpcPort,
    pairingPort,
    classification,
    publicIp,
    dnsInfo,
    local,
    remote,
    tailscale,
  });
  const recommendations = collectRecommendations({
    host,
    grpcPort,
    pairingPort,
    classification,
    publicIp,
    dnsInfo,
    remote,
    tailscale,
  });

  return {
    ok: issues.filter((issue) => issue.severity === 'blocker').length === 0,
    schema_version: 'xhub.remote_route_doctor.v1',
    generated_at_iso: new Date().toISOString(),
    target: { host, grpc_port: grpcPort, pairing_port: pairingPort },
    host_classification: classification,
    public_ip: { ok: publicIp.ok, address: publicIp.body, error: publicIp.error },
    dns: dnsInfo,
    local,
    remote: redactDiscovery(remote),
    tailscale,
    issues,
    recommendations,
  };
}

function collectIssues(ctx) {
  const issues = [];
  const add = (severity, code, detail) => issues.push({ severity, code, detail });
  if (!ctx.host) add('blocker', 'external_host_missing', 'Set a DNS name, tailnet name, or VPN/encrypted IP as the Hub external address.');
  const anyLocalPairing = ctx.local.some((row) => row.pairing.ok);
  const anyLocalGrpc = ctx.local.some((row) => row.grpc.ok);
  if (!anyLocalPairing) add('blocker', 'local_pairing_port_not_listening', `No local interface accepts TCP ${ctx.pairingPort}.`);
  if (!anyLocalGrpc) add('blocker', 'local_grpc_port_not_listening', `No local interface accepts TCP ${ctx.grpcPort}.`);
  if (ctx.host && ctx.remote.pairing.ok !== true) add('blocker', 'remote_pairing_port_unreachable', `${ctx.host}:${ctx.pairingPort} is not reachable (${ctx.remote.pairing.error || 'connect_failed'}).`);
  if (ctx.host && ctx.remote.grpc.ok !== true) add('blocker', 'remote_grpc_port_unreachable', `${ctx.host}:${ctx.grpcPort} is not reachable (${ctx.remote.grpc.error || 'connect_failed'}).`);
  if (ctx.host && ctx.remote.discovery.ok !== true) add('blocker', 'remote_pairing_discovery_unavailable', `/pairing/discovery failed on ${ctx.host}:${ctx.pairingPort} (${ctx.remote.discovery.error || ctx.remote.discovery.status_code || 'unavailable'}).`);
  if (ctx.classification.kind === 'stable_named' && ctx.dnsInfo.a.length === 0 && ctx.dnsInfo.aaaa.length === 0) {
    add('blocker', 'dns_has_no_address_records', `${ctx.host} has no A/AAAA records visible from this machine.`);
  }
  if (ctx.classification.kind === 'stable_named'
      && ctx.publicIp.ok
      && ctx.dnsInfo.a.length > 0
      && !ctx.dnsInfo.a.includes(ctx.publicIp.body)
      && ctx.remote.pairing.ok !== true
      && ctx.remote.grpc.ok !== true) {
    add('blocker', 'dns_does_not_point_to_current_hub_ip', `${ctx.host} resolves to ${ctx.dnsInfo.a.join(', ')}, but this Hub currently exits as ${ctx.publicIp.body}.`);
  }
  if (ctx.tailscale.installed && !ctx.tailscale.running && ctx.tailscale.service_hint) {
    add('warning', 'tailscale_service_not_running', ctx.tailscale.service_hint);
  }
  if (ctx.classification.kind === 'raw_ip' && ctx.classification.scope === 'public_internet_ip') {
    add('warning', 'raw_public_ip_is_brittle', 'A public raw IP can change and is not a good long-term XT route.');
  }
  return issues;
}

function collectRecommendations(ctx) {
  const lines = [];
  const ns = ctx.dnsInfo.ns.join(', ').toLowerCase();
  if (ctx.classification.kind === 'stable_named') {
    lines.push(`Use ${ctx.host} as the Hub external address only after both TCP ports are reachable: pairing ${ctx.pairingPort}, gRPC ${ctx.grpcPort}.`);
    if (ctx.classification.scope !== 'tailnet_dns'
        && ctx.publicIp.ok
        && ctx.dnsInfo.a.length > 0
        && !ctx.dnsInfo.a.includes(ctx.publicIp.body)) {
      lines.push(`DNS direct option: update the A record for ${ctx.host} to ${ctx.publicIp.body}, then verify from an XT network with: nc -vz ${ctx.host} ${ctx.pairingPort} && nc -vz ${ctx.host} ${ctx.grpcPort}.`);
    }
    if (ns.includes('cloudflare')) {
      lines.push('Cloudflare note: ordinary orange-cloud proxy does not forward raw TCP gRPC/pairing ports. Use DNS-only for direct TCP, Cloudflare Spectrum/raw TCP, or a VPN/tunnel that both Hub and XT join.');
    }
    if (ctx.classification.scope === 'tailnet_dns') {
      lines.push('Tailnet DNS option: make sure both Hub and XT are logged into the same Tailscale/Headscale network, then use the MagicDNS name instead of a public A record.');
    }
  } else if (ctx.classification.encrypted_ip_candidate) {
    lines.push(`Encrypted/VPN IP option: ${ctx.host} can be used only if every XT device joins the same VPN/tailnet and can reach TCP ${ctx.pairingPort}/${ctx.grpcPort}.`);
    lines.push('In Hub Settings > LAN/gRPC > Advanced Settings, put this VPN/tailnet IP in External Address. In XT, use the invite link/setup pack or enter the same host and ports.');
  } else if (ctx.classification.kind === 'raw_ip') {
    lines.push('Raw public IP option is only temporary. Prefer a stable DNS name, MagicDNS tailnet name, or VPN/relay endpoint.');
  } else {
    if (ctx.classification.kind === 'missing' && ctx.tailscale.running && ctx.tailscale.ips.length > 0) {
      lines.push(`No-domain private network option: this machine has Tailscale/Headscale IP ${ctx.tailscale.ips[0]}. Put that value in Hub Settings > LAN/gRPC > Advanced Settings > External Address, then rerun this doctor with --host ${ctx.tailscale.ips[0]}.`);
    }
    lines.push('First choose an external route: stable DNS name, MagicDNS/tailnet name, or VPN encrypted IP. Then rerun this doctor with --host <value>.');
  }
  if (ctx.tailscale.installed && !ctx.tailscale.running) {
    lines.push('Tailscale repair: install/use the official macOS Tailscale app or run tailscaled as a system service. The current Homebrew user LaunchAgent cannot create the tunnel because tailscaled requires root.');
  }
  lines.push(`After the route is reachable, copy the Hub secure remote setup pack or invite link so XT stores host=${ctx.host || '<external_host>'}, pairing_port=${ctx.pairingPort}, grpc_port=${ctx.grpcPort}.`);
  return lines;
}

function redactDiscovery(remote) {
  const discovery = remote.discovery?.json || null;
  return {
    grpc: remote.grpc,
    pairing: remote.pairing,
    discovery: {
      ok: remote.discovery?.ok === true,
      status_code: Number(remote.discovery?.status_code || 0),
      duration_ms: Number(remote.discovery?.duration_ms || 0),
      error: safeString(remote.discovery?.error || remote.discovery?.parse_error || ''),
      payload: discovery ? {
        ok: discovery.ok === true,
        service: safeString(discovery.service),
        hub_host_hint: safeString(discovery.hub_host_hint),
        internet_host_hint: safeString(discovery.internet_host_hint),
        grpc_port: Number(discovery.grpc_port || 0),
        pairing_port: Number(discovery.pairing_port || 0),
        tls_mode: safeString(discovery.tls_mode),
        hub_instance_id_present: safeString(discovery.hub_instance_id) !== '',
      } : null,
    },
  };
}

function renderText(report) {
  const lines = [];
  const verdict = report.ok ? 'ready' : 'blocked';
  lines.push(`X-Hub Remote Route Doctor: ${verdict}`);
  lines.push(`Target: host=${report.target.host || '(missing)'} pairing=${report.target.pairing_port} grpc=${report.target.grpc_port}`);
  lines.push(`Host kind: ${report.host_classification.kind} ${report.host_classification.scope ? `(${report.host_classification.scope})` : ''}`);
  lines.push(`Public IP: ${report.public_ip.ok ? report.public_ip.address : `unavailable (${report.public_ip.error})`}`);
  if (report.dns.a.length || report.dns.aaaa.length || report.dns.error) {
    lines.push(`DNS A: ${report.dns.a.length ? report.dns.a.join(', ') : '(none)'}`);
    if (report.dns.aaaa.length) lines.push(`DNS AAAA: ${report.dns.aaaa.join(', ')}`);
    if (report.dns.ns.length) lines.push(`DNS NS: ${report.dns.ns.join(', ')}`);
    if (report.dns.error) lines.push(`DNS error: ${report.dns.error}`);
  }
  lines.push('');
  lines.push('Local listeners:');
  for (const row of report.local) {
    lines.push(`- ${row.name} ${row.host}: pairing=${row.pairing.ok ? 'ok' : row.pairing.error} grpc=${row.grpc.ok ? 'ok' : row.grpc.error}`);
  }
  lines.push('');
  lines.push('Remote route:');
  lines.push(`- pairing TCP: ${report.remote.pairing.ok ? 'ok' : report.remote.pairing.error}`);
  lines.push(`- gRPC TCP: ${report.remote.grpc.ok ? 'ok' : report.remote.grpc.error}`);
  lines.push(`- discovery: ${report.remote.discovery.ok ? 'ok' : (report.remote.discovery.error || report.remote.discovery.status_code || 'failed')}`);
  if (report.remote.discovery.payload) {
    lines.push(`- discovery hint: hub=${report.remote.discovery.payload.hub_host_hint || '-'} internet=${report.remote.discovery.payload.internet_host_hint || '-'}`);
  }
  lines.push('');
  lines.push(`Tailscale: ${report.tailscale.installed ? (report.tailscale.running ? `running ${report.tailscale.ips.join(', ')}` : `installed but not running (${report.tailscale.service_hint || report.tailscale.error})`) : 'not installed'}`);
  if (report.issues.length) {
    lines.push('');
    lines.push('Issues:');
    for (const issue of report.issues) lines.push(`- ${issue.severity}: ${issue.code} - ${issue.detail}`);
  }
  lines.push('');
  lines.push('Setup guidance:');
  for (const rec of report.recommendations) lines.push(`- ${rec}`);
  return `${lines.join('\n')}\n`;
}

function printHelp() {
  process.stdout.write(`Usage: hub_remote_route_doctor.command [--host <host>] [--grpc-port <n>] [--pairing-port <n>] [--json]\n\nChecks a Hub remote route for XT across DNS, VPN/encrypted IP, local ports, remote ports, pairing discovery, and Tailscale state.\n\nExamples:\n  tools/hub_remote_route_doctor.command --host hub.your-domain.example --grpc-port 50058 --pairing-port 50059\n  tools/hub_remote_route_doctor.command --host 100.96.10.8 --grpc-port 50058 --pairing-port 50059\n`);
}

async function selfTest() {
  const cases = [
    ['hub.tailnet.example', 'stable_named', 'dns_name', false],
    ['mini.tail000.ts.net', 'stable_named', 'tailnet_dns', true],
    ['100.96.10.8', 'raw_ip', 'tailscale_headscale_ip', true],
    ['192.168.10.9', 'raw_ip', 'private_or_vpn_ip', true],
    ['17.81.11.116', 'raw_ip', 'public_internet_ip', false],
    ['hub.local', 'lan_only', 'lan_name', false],
  ];
  for (const [input, kind, scope, encrypted] of cases) {
    const got = classifyHost(input);
    if (got.kind !== kind || got.scope !== scope || got.encrypted_ip_candidate !== encrypted) {
      throw new Error(`classifyHost(${input}) expected ${kind}/${scope}/${encrypted}, got ${JSON.stringify(got)}`);
    }
  }
  const missing = classifyHost('');
  if (missing.kind !== 'missing') {
    throw new Error(`self-test expected missing host classification, got ${JSON.stringify(missing)}`);
  }
  process.stdout.write('hub_remote_route_doctor self-test: ok\n');
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.selfTest) {
    await selfTest();
    return;
  }
  const report = await buildReport(args);
  if (args.json) {
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  } else {
    process.stdout.write(renderText(report));
  }
  process.exitCode = report.ok ? 0 : 2;
}

main().catch((error) => {
  process.stderr.write(`[hub_remote_route_doctor] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
