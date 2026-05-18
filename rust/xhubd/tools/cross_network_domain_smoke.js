#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import os from 'node:os';

function parseArgs(argv) {
  const out = {
    publicBaseUrl: process.env.XHUB_RUST_HUB_PUBLIC_BASE_URL || '',
    accessKeyFile: process.env.XHUB_RUST_HTTP_ACCESS_KEY_FILE || '',
    timeoutMs: 10000,
    expectAuthRequired: true,
    requireCrossNetworkReady: true,
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
        out.accessKeyFile = String(next || '').trim();
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = Math.max(250, Math.min(120000, Number.parseInt(String(next || ''), 10) || out.timeoutMs));
        i += 1;
        break;
      case '--no-expect-auth-required':
        out.expectAuthRequired = false;
        break;
      case '--no-require-cross-network-ready':
        out.requireCrossNetworkReady = false;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }
  return out;
}

function readAccessKey(filePath) {
  const path = String(filePath || '').trim();
  if (!path) throw new Error('access_key_file_required');
  const key = fs.readFileSync(path, 'utf8').trim();
  if (!key) throw new Error('access_key_file_empty');
  return key;
}

function endpoint(baseUrl, path) {
  return new URL(path, baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`);
}

function parseTailscaleIPv4s(text) {
  const matches = String(text || '').match(/\b100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.(?:25[0-5]|2[0-4]\d|1?\d?\d)\.(?:25[0-5]|2[0-4]\d|1?\d?\d)\b/g);
  return [...new Set(matches || [])];
}

function localTailnetLookupAddress(hostname) {
  if (!String(hostname || '').toLowerCase().endsWith('.ts.net')) return '';
  for (const rows of Object.values(os.networkInterfaces())) {
    for (const row of rows || []) {
      if (row.family === 'IPv4') {
        const [ip] = parseTailscaleIPv4s(row.address);
        if (ip) return ip;
      }
    }
  }
  return '';
}

function requestJson(url, { timeoutMs, accessKey = '', lookupAddress = '' }) {
  return new Promise((resolve) => {
    const client = url.protocol === 'https:' ? https : http;
    const headers = accessKey ? { Authorization: `Bearer ${accessKey}` } : {};
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
      });
      res.on('end', () => {
        let json = null;
        let parseError = '';
        try {
          json = body ? JSON.parse(body) : null;
        } catch (error) {
          parseError = String(error.message || error);
        }
        resolve({
          ok: res.statusCode >= 200 && res.statusCode < 300,
          status_code: res.statusCode,
          json,
          parse_error: parseError,
        });
      });
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', (error) => {
      resolve({ ok: false, status_code: 0, json: null, parse_error: '', error: String(error.message || error) });
    });
  });
}

function redactStep(step) {
  return {
    ok: step.ok === true,
    status_code: Number(step.status_code || 0),
    error: String(step.error || ''),
    parse_error: String(step.parse_error || ''),
    body_ok: step.json?.ok === true,
    ready: step.json?.ready === true,
    cross_network_ready: step.json?.capabilities?.cross_network_ready === true,
    cross_network_auth_gate: step.json?.capabilities?.cross_network_auth_gate === true,
    http_access_key_required: step.json?.network?.http_access_key_required === true,
    http_access_key_configured: step.json?.network?.http_access_key_configured === true,
  };
}

function hasSecretLeak(value) {
  return /Bearer\s+(?!\[REDACTED\])\S+|access_key"\s*:\s*"(?!\[REDACTED\])|[a-f0-9]{64}/i.test(JSON.stringify(value));
}

async function main() {
  const startedAt = Date.now();
  const config = parseArgs(process.argv.slice(2));
  if (!config.publicBaseUrl) throw new Error('public_base_url_required');
  const parsed = new URL(config.publicBaseUrl);
  if (!['http:', 'https:'].includes(parsed.protocol)) throw new Error('public_base_url_must_be_http_or_https');
  const accessKey = readAccessKey(config.accessKeyFile);
  const lookupAddress = localTailnetLookupAddress(parsed.hostname);

  const health = await requestJson(endpoint(config.publicBaseUrl, '/health'), {
    timeoutMs: config.timeoutMs,
    lookupAddress,
  });
  const readyWithoutKey = await requestJson(endpoint(config.publicBaseUrl, '/ready'), {
    timeoutMs: config.timeoutMs,
    lookupAddress,
  });
  const readyWithKey = await requestJson(endpoint(config.publicBaseUrl, '/ready'), {
    timeoutMs: config.timeoutMs,
    accessKey,
    lookupAddress,
  });

  const issues = [];
  if (!health.ok || health.json?.ok !== true) issues.push('health_unavailable');
  if (config.expectAuthRequired && ![401, 403].includes(Number(readyWithoutKey.status_code || 0))) {
    issues.push('unauthorized_ready_not_rejected');
  }
  if (!readyWithKey.ok || readyWithKey.json?.ready !== true) issues.push('authorized_ready_unavailable');
  if (readyWithKey.json?.capabilities?.cross_network_auth_gate !== true) issues.push('cross_network_auth_gate_missing');
  if (config.requireCrossNetworkReady && readyWithKey.json?.capabilities?.cross_network_ready !== true) {
    issues.push('cross_network_ready_false');
  }

  const report = {
    ok: issues.length === 0,
    schema_version: 'xhub.rust_hub.cross_network_domain_smoke.v1',
    command: 'cross-network-domain-smoke',
    generated_at_iso: new Date().toISOString(),
    duration_ms: Date.now() - startedAt,
    public_base_url: config.publicBaseUrl,
    tailnet_dns_lookup_fallback: lookupAddress ? 'local_tailnet_interface' : '',
    expect_auth_required: config.expectAuthRequired,
    require_cross_network_ready: config.requireCrossNetworkReady,
    key_printed: false,
    checks: {
      health: redactStep(health),
      ready_without_key: redactStep(readyWithoutKey),
      ready_with_key: redactStep(readyWithKey),
    },
    production_authority_change: false,
    ui_product_change: false,
    secret_leak: false,
    issues,
  };
  report.secret_leak = hasSecretLeak(report);
  if (report.secret_leak) {
    report.ok = false;
    report.issues.push('secret_leak');
  }
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  process.exit(report.ok ? 0 : 2);
}

main().catch((error) => {
  process.stderr.write(`[cross_network_domain_smoke] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
