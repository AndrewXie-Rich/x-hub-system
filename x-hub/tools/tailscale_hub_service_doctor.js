#!/usr/bin/env node
'use strict';

const childProcess = require('node:child_process');
const fs = require('node:fs');
const http = require('node:http');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');

const DEFAULT_GRPC_PORT = 50058;
const DEFAULT_TIMEOUT_MS = 5000;
const TAILSCALE_APP = '/Applications/Tailscale.app';
const HOMEBREW_LAUNCH_AGENT = path.join(os.homedir(), 'Library/LaunchAgents/homebrew.mxcl.tailscale.plist');

function safeString(value) {
  return String(value ?? '').trim();
}

function parseArgs(argv) {
  const out = {
    host: '',
    grpcPort: DEFAULT_GRPC_PORT,
    pairingPort: DEFAULT_GRPC_PORT + 1,
    timeoutMs: DEFAULT_TIMEOUT_MS,
    json: false,
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
        out.grpcPort = parsePort(next, DEFAULT_GRPC_PORT);
        i += 1;
        break;
      case '--pairing-port':
        out.pairingPort = parsePort(next, out.grpcPort + 1);
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = Math.max(250, Math.min(120000, Number.parseInt(String(next || ''), 10) || DEFAULT_TIMEOUT_MS));
        i += 1;
        break;
      case '--json':
        out.json = true;
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

function parseTailscaleIPv4s(text) {
  const matches = safeString(text).match(/\b100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.(?:25[0-5]|2[0-4]\d|1?\d?\d)\.(?:25[0-5]|2[0-4]\d|1?\d?\d)\b/g);
  return uniqueStrings(matches || []);
}

function isTailscaleCliFailure(text) {
  const value = safeString(text).toLowerCase();
  return value.includes('tailscale cli failed to start')
    || value.includes('failed to load preferences')
    || value.includes('failed to connect to local tailscaled');
}

function tailscaleAddressesFromInterfaces() {
  const rows = [];
  for (const [name, addrs] of Object.entries(os.networkInterfaces())) {
    for (const addr of addrs || []) {
      if (addr.family === 'IPv4') {
        const [ip] = parseTailscaleIPv4s(addr.address);
        if (ip) rows.push({ interface: name, family: 'IPv4', address: ip });
      } else if (addr.family === 'IPv6' && /^fd7a:115c:a1e0:/i.test(addr.address)) {
        rows.push({ interface: name, family: 'IPv6', address: addr.address });
      }
    }
  }
  return rows;
}

function commandLinesContaining(needle) {
  const out = execText('/bin/ps', ['ax', '-o', 'pid=,command='], 2000);
  if (!out.ok) return [];
  return out.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.includes(needle));
}

function processPids(lines) {
  return lines.map((line) => line.split(/\s+/, 1)[0]).filter(Boolean);
}

function loginItemNames() {
  const out = execText('/usr/bin/osascript', ['-e', 'tell application "System Events" to get name of login items'], 3000);
  if (!out.ok) return { ok: false, names: [], error: safeString(out.stderr || out.stdout || out.error) };
  return {
    ok: true,
    names: out.stdout.split(/\s*,\s*/).map(safeString).filter(Boolean),
    error: '',
  };
}

function plistValue(key) {
  const plist = path.join(TAILSCALE_APP, 'Contents/Info.plist');
  const out = execText('/usr/bin/plutil', ['-extract', key, 'raw', plist], 1000);
  return out.ok ? safeString(out.stdout) : '';
}

function cliState() {
  const bin = execText('/usr/bin/env', ['which', 'tailscale'], 1000);
  if (!bin.ok || !bin.stdout) return { found: false, path: '', usable: false, ips: [], dns_name: '', magic_dns_enabled: false, status_error: 'tailscale_cli_not_found' };
  const cliPath = bin.stdout.split(/\r?\n/)[0];
  const status = execText(cliPath, ['status'], 3000);
  const statusJson = execText(cliPath, ['status', '--json'], 3000);
  const ip = execText(cliPath, ['ip', '-4'], 3000);
  const statusText = `${status.stdout}\n${status.stderr}\n${status.error}`;
  const ipText = `${ip.stdout}\n${ip.stderr}\n${ip.error}`;
  const usable = status.ok && !isTailscaleCliFailure(statusText);
  let dnsName = '';
  let magicDnsEnabled = false;
  if (statusJson.ok && !isTailscaleCliFailure(statusJson.stdout)) {
    try {
      const parsed = JSON.parse(statusJson.stdout);
      dnsName = safeString(parsed?.Self?.DNSName).replace(/\.$/, '');
      magicDnsEnabled = parsed?.CurrentTailnet?.MagicDNSEnabled === true;
    } catch {}
  }
  return {
    found: true,
    path: cliPath,
    usable,
    ips: ip.ok && !isTailscaleCliFailure(ipText) ? parseTailscaleIPv4s(ip.stdout) : [],
    dns_name: magicDnsEnabled ? dnsName : '',
    magic_dns_enabled: magicDnsEnabled,
    status_error: usable ? '' : safeString(status.stderr || status.stdout || status.error),
  };
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
    const req = http.get(url, { timeout: timeoutMs, headers: { accept: 'application/json' } }, (res) => {
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
          error: parseError,
        });
      });
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', (error) => resolve({ ok: false, status_code: 0, duration_ms: Date.now() - started, json: null, error: safeString(error.code || error.message || error) }));
  });
}

async function buildReport(args) {
  const appInstalled = fs.existsSync(TAILSCALE_APP);
  const appProcesses = commandLinesContaining('/Applications/Tailscale.app/Contents/MacOS/Tailscale');
  const extensionProcesses = commandLinesContaining('io.tailscale.ipn.macsys.network-extension');
  const loginItems = loginItemNames();
  const cli = cliState();
  const interfaceAddresses = tailscaleAddressesFromInterfaces();
  const ipv4s = uniqueStrings([
    ...cli.ips,
    ...interfaceAddresses.filter((row) => row.family === 'IPv4').map((row) => row.address),
  ]);
  const targetHost = args.host || cli.dns_name || ipv4s[0] || '';
  const remote = targetHost ? {
    pairing: await connectTcp(targetHost, args.pairingPort, args.timeoutMs),
    grpc: await connectTcp(targetHost, args.grpcPort, args.timeoutMs),
    discovery: await httpJson(`http://${urlHost(targetHost)}:${args.pairingPort}/pairing/discovery`, args.timeoutMs),
  } : {
    pairing: { ok: false, port: args.pairingPort, duration_ms: 0, error: 'host_missing' },
    grpc: { ok: false, port: args.grpcPort, duration_ms: 0, error: 'host_missing' },
    discovery: { ok: false, status_code: 0, duration_ms: 0, json: null, error: 'host_missing' },
  };
  const state = {
    app: {
      installed: appInstalled,
      version: appInstalled ? plistValue('CFBundleShortVersionString') : '',
      bundle_id: appInstalled ? plistValue('CFBundleIdentifier') : '',
      app_pids: processPids(appProcesses),
      network_extension_pids: processPids(extensionProcesses),
      login_item_enabled: loginItems.names.includes('Tailscale'),
      login_items_readable: loginItems.ok,
      login_items_error: loginItems.error,
    },
    cli,
    homebrew_user_launch_agent_present: fs.existsSync(HOMEBREW_LAUNCH_AGENT),
    interface_addresses: interfaceAddresses,
    tailscale_ipv4s: ipv4s,
    target: {
      host: targetHost,
      grpc_port: args.grpcPort,
      pairing_port: args.pairingPort,
    },
    remote: {
      pairing: remote.pairing,
      grpc: remote.grpc,
      discovery: {
        ok: remote.discovery.ok,
        status_code: remote.discovery.status_code,
        duration_ms: remote.discovery.duration_ms,
        error: remote.discovery.error,
        payload: remote.discovery.json ? {
          ok: remote.discovery.json.ok === true,
          hub_host_hint: safeString(remote.discovery.json.hub_host_hint),
          internet_host_hint: safeString(remote.discovery.json.internet_host_hint),
          grpc_port: Number(remote.discovery.json.grpc_port || 0),
          pairing_port: Number(remote.discovery.json.pairing_port || 0),
          tls_mode: safeString(remote.discovery.json.tls_mode),
        } : null,
      },
    },
  };
  const issues = collectIssues(state);
  return {
    ok: issues.filter((issue) => issue.severity === 'blocker').length === 0,
    schema_version: 'xhub.tailscale_hub_service_doctor.v1',
    generated_at_iso: new Date().toISOString(),
    ...state,
    issues,
    recommendations: collectRecommendations(state),
  };
}

function collectIssues(state) {
  const issues = [];
  const add = (severity, code, detail) => issues.push({ severity, code, detail });
  if (!state.app.installed) add('blocker', 'tailscale_app_missing', 'Install the official macOS Tailscale app.');
  if (state.app.installed && !state.app.login_item_enabled) add('blocker', 'tailscale_login_item_missing', 'Add Tailscale to macOS Login Items for reboot persistence.');
  if (state.app.app_pids.length === 0) add('blocker', 'tailscale_app_not_running', 'Start /Applications/Tailscale.app.');
  if (state.app.network_extension_pids.length === 0) add('blocker', 'tailscale_network_extension_not_running', 'Enable the Tailscale Network Extension in System Settings.');
  if (state.tailscale_ipv4s.length === 0) add('blocker', 'tailscale_ipv4_missing', 'No 100.64.0.0/10 Tailscale IPv4 is assigned.');
  if (!state.target.host) add('blocker', 'tailscale_target_host_missing', 'No Tailscale host was supplied or discovered.');
  if (state.target.host && !state.remote.pairing.ok) add('blocker', 'hub_pairing_unreachable_over_tailscale', `${state.target.host}:${state.target.pairing_port} failed (${state.remote.pairing.error || 'connect_failed'}).`);
  if (state.target.host && !state.remote.grpc.ok) add('blocker', 'hub_grpc_unreachable_over_tailscale', `${state.target.host}:${state.target.grpc_port} failed (${state.remote.grpc.error || 'connect_failed'}).`);
  if (state.target.host && !state.remote.discovery.ok) add('blocker', 'hub_pairing_discovery_unavailable_over_tailscale', `/pairing/discovery failed (${state.remote.discovery.error || state.remote.discovery.status_code || 'unavailable'}).`);
  if (state.homebrew_user_launch_agent_present) add('warning', 'homebrew_user_launchagent_present', 'The Homebrew user LaunchAgent can fail on macOS because tailscaled requires root.');
  if (state.cli.found && !state.cli.usable && state.tailscale_ipv4s.length > 0) add('warning', 'tailscale_cli_unavailable_but_app_active', state.cli.status_error || 'The app tunnel is active, but the CLI could not read app preferences.');
  return issues;
}

function collectRecommendations(state) {
  const host = state.target.host || '<100.x-or-magic-dns>';
  return [
    `Set Hub Settings > LAN/gRPC > Advanced Settings > External Address to ${host}.`,
    `Give XT the secure remote setup pack or invite link so it stores host=${host}, pairing_port=${state.target.pairing_port}, grpc_port=${state.target.grpc_port}.`,
    'For another person, repeat this doctor with --host <their-magic-dns-or-100.x-ip> after their XT joins the same Tailscale tailnet.',
  ];
}

function renderText(report) {
  const lines = [];
  lines.push(`X-Hub Tailscale Service Doctor: ${report.ok ? 'ready' : 'blocked'}`);
  lines.push(`Tailscale app: ${report.app.installed ? `installed ${report.app.version || '(unknown version)'}` : 'missing'}, login item=${report.app.login_item_enabled ? 'yes' : 'no'}`);
  lines.push(`Processes: app=${report.app.app_pids.length ? report.app.app_pids.join(',') : 'not running'} network-extension=${report.app.network_extension_pids.length ? report.app.network_extension_pids.join(',') : 'not running'}`);
  lines.push(`Homebrew user LaunchAgent: ${report.homebrew_user_launch_agent_present ? 'present' : 'absent'}`);
  lines.push(`Tailscale addresses: ${report.interface_addresses.length ? report.interface_addresses.map((row) => `${row.interface}/${row.family}=${row.address}`).join(', ') : '(none)'}`);
  lines.push(`CLI: ${report.cli.found ? `${report.cli.path} ${report.cli.usable ? 'usable' : 'unavailable'}${report.cli.dns_name ? ` magic-dns=${report.cli.dns_name}` : ''}` : 'not found'}`);
  lines.push('');
  lines.push(`Hub over Tailscale: host=${report.target.host || '(missing)'} pairing=${report.remote.pairing.ok ? 'ok' : report.remote.pairing.error} grpc=${report.remote.grpc.ok ? 'ok' : report.remote.grpc.error} discovery=${report.remote.discovery.ok ? 'ok' : (report.remote.discovery.error || report.remote.discovery.status_code || 'failed')}`);
  if (report.remote.discovery.payload) {
    lines.push(`Discovery hint: hub=${report.remote.discovery.payload.hub_host_hint || '-'} internet=${report.remote.discovery.payload.internet_host_hint || '-'} tls=${report.remote.discovery.payload.tls_mode || '-'}`);
  }
  if (report.issues.length) {
    lines.push('');
    lines.push('Issues:');
    for (const issue of report.issues) lines.push(`- ${issue.severity}: ${issue.code} - ${issue.detail}`);
  }
  lines.push('');
  lines.push('Next settings:');
  for (const rec of report.recommendations) lines.push(`- ${rec}`);
  return `${lines.join('\n')}\n`;
}

function printHelp() {
  process.stdout.write(`Usage: tailscale_hub_service_doctor.command [--host <100.x-or-magic-dns>] [--grpc-port <n>] [--pairing-port <n>] [--json]\n\nChecks the official macOS Tailscale app service path, login item, network extension, Tailscale IP, and Hub pairing/gRPC reachability over Tailscale.\n`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const report = await buildReport(args);
  process.stdout.write(args.json ? `${JSON.stringify(report, null, 2)}\n` : renderText(report));
  process.exitCode = report.ok ? 0 : 2;
}

main().catch((error) => {
  process.stderr.write(`[tailscale_hub_service_doctor] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
