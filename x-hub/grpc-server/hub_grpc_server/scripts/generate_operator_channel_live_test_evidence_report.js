#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  buildOperatorChannelLiveTestEvidenceReport,
  operatorChannelLiveTestProviderRow,
} from '../src/operator_channel_live_test_evidence.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const value = Number(input);
  return Number.isFinite(value) ? Math.max(0, Math.trunc(value)) : fallback;
}

function helpText() {
  return [
    'Usage:',
    '  node scripts/generate_operator_channel_live_test_evidence_report.js \\',
    '    --provider slack|telegram|feishu|whatsapp_cloud_api \\',
    '    [--ticket-id ticket_123] \\',
    '    [--verdict passed|failed|partial|pending] \\',
    '    [--summary "what happened"] \\',
    '    [--performed-at 2026-03-15T10:00:00Z] \\',
    '    [--evidence-ref path/to/capture.png]... \\',
    '    [--next-step "next action"] \\',
    '    [--output x-terminal/build/reports/custom.json] \\',
    '    [--base-url http://127.0.0.1:50052] \\',
    '    [--pairing-port 50052] \\',
    '    [--admin-token token]',
    '',
    'Defaults:',
    '  --admin-token uses HUB_ADMIN_TOKEN',
    '  --pairing-port uses HUB_PAIRING_PORT or HUB_PORT+1',
    '  --output defaults to x-terminal/build/reports/xt_w3_24_s_<provider>_live_test_evidence.v1.json',
  ].join('\n');
}

export function parseArgs(argv) {
  const out = {
    evidence_refs: [],
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = safeString(argv[index]);
    const next = argv[index + 1];
    switch (arg) {
    case '--help':
    case '-h':
      out.help = true;
      break;
    case '--provider':
      out.provider = safeString(next);
      index += 1;
      break;
    case '--ticket-id':
      out.ticket_id = safeString(next);
      index += 1;
      break;
    case '--verdict':
      out.verdict = safeString(next);
      index += 1;
      break;
    case '--summary':
      out.summary = safeString(next);
      index += 1;
      break;
    case '--performed-at':
      out.performed_at = safeString(next);
      index += 1;
      break;
    case '--evidence-ref':
      out.evidence_refs.push(safeString(next));
      index += 1;
      break;
    case '--next-step':
      out.next_step = safeString(next);
      index += 1;
      break;
    case '--output':
      out.output = safeString(next);
      index += 1;
      break;
    case '--base-url':
      out.base_url = safeString(next);
      index += 1;
      break;
    case '--pairing-port':
      out.pairing_port = safeInt(next, 0);
      index += 1;
      break;
    case '--admin-token':
      out.admin_token = safeString(next);
      index += 1;
      break;
    default:
      if (arg) throw new Error(`unknown_argument:${arg}`);
    }
  }
  return out;
}

export function repoRootDir() {
  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  return path.resolve(scriptDir, '../../../..');
}

export function defaultOutputPath(provider) {
  return path.join(
    repoRootDir(),
    'x-terminal',
    'build',
    'reports',
    `xt_w3_24_s_${safeString(provider).replace(/[^a-z0-9_]+/gi, '_').toLowerCase()}_live_test_evidence.v1.json`
  );
}

export function resolveBaseUrl(args, env = process.env) {
  const explicitBase = safeString(args.base_url);
  if (explicitBase) return explicitBase;
  const envPairingPort = safeInt(env.HUB_PAIRING_PORT, 0);
  const envHubPort = safeInt(env.HUB_PORT, 50051);
  const pairingPort = safeInt(args.pairing_port, 0) || envPairingPort || (envHubPort + 1);
  return `http://127.0.0.1:${pairingPort}`;
}

export async function requestJson(baseUrl, pathname, adminToken, fetchImpl = globalThis.fetch) {
  const response = await fetchImpl(new URL(pathname, baseUrl), {
    method: 'GET',
    headers: {
      accept: 'application/json',
      authorization: `Bearer ${adminToken}`,
    },
  });
  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = null;
  }
  if (!response.ok || !json?.ok) {
    const code = safeString(json?.error?.code || `http_${response.status}`);
    const message = safeString(json?.error?.message || text || 'request_failed');
    throw new Error(`${code}:${message}`);
  }
  return json;
}

function errorCodeFromMessage(error) {
  const text = safeString(error?.message || error);
  if (!text) return '';
  const idx = text.indexOf(':');
  return idx >= 0 ? safeString(text.slice(0, idx)) : text;
}

function shouldFallbackToLegacySnapshotAssembly(error) {
  const code = errorCodeFromMessage(error);
  return code === 'not_found' || code === 'http_404';
}

export function buildLiveTestEvidenceEndpointPath(args = {}) {
  const params = new URLSearchParams();
  params.set('provider', safeString(args.provider).toLowerCase());
  if (safeString(args.ticket_id)) params.set('ticket_id', safeString(args.ticket_id));
  if (safeString(args.verdict)) params.set('verdict', safeString(args.verdict));
  if (safeString(args.summary)) params.set('summary', safeString(args.summary));
  if (safeString(args.performed_at)) params.set('performed_at', safeString(args.performed_at));
  if (safeString(args.next_step)) params.set('next_step', safeString(args.next_step));
  for (const ref of Array.isArray(args.evidence_refs) ? args.evidence_refs : []) {
    const value = safeString(ref);
    if (value) params.append('evidence_ref', value);
  }
  return `/admin/operator-channels/live-test/evidence?${params.toString()}`;
}

export async function requestServerSideLiveTestEvidence(baseUrl, args, adminToken, fetchImpl = globalThis.fetch) {
  const json = await requestJson(
    baseUrl,
    buildLiveTestEvidenceEndpointPath(args),
    adminToken,
    fetchImpl
  );
  return json?.report && typeof json.report === 'object' ? json.report : null;
}

export function relativePathForReport(filePath) {
  const root = repoRootDir();
  const absolute = path.resolve(filePath);
  if (!absolute.startsWith(root)) return absolute;
  return path.relative(root, absolute);
}

export async function generateOperatorChannelLiveTestEvidenceReport(args, {
  env = process.env,
  fetchImpl = globalThis.fetch,
  fileSystem = fs,
} = {}) {
  const provider = safeString(args.provider).toLowerCase();
  if (!provider) {
    throw new Error('provider_required');
  }
  const adminToken = safeString(args.admin_token || env.HUB_ADMIN_TOKEN);
  if (!adminToken) {
    throw new Error('admin_token_required');
  }

  const baseUrl = resolveBaseUrl(args, env);
  const outputPath = path.resolve(args.output || defaultOutputPath(provider));
  let report = null;

  try {
    report = await requestServerSideLiveTestEvidence(baseUrl, args, adminToken, fetchImpl);
  } catch (error) {
    if (!shouldFallbackToLegacySnapshotAssembly(error)) throw error;
  }

  if (!report) {
    const [readinessSnapshot, runtimeSnapshot] = await Promise.all([
      requestJson(baseUrl, '/admin/operator-channels/readiness', adminToken, fetchImpl),
      requestJson(baseUrl, '/admin/operator-channels/runtime-status', adminToken, fetchImpl),
    ]);
    const ticketDetail = args.ticket_id
      ? await requestJson(
        baseUrl,
        `/admin/operator-channels/onboarding/tickets/${encodeURIComponent(args.ticket_id)}`,
        adminToken,
        fetchImpl
      )
      : null;

    const readiness = operatorChannelLiveTestProviderRow(readinessSnapshot, provider);
    const runtimeStatus = operatorChannelLiveTestProviderRow(runtimeSnapshot, provider);
    report = buildOperatorChannelLiveTestEvidenceReport({
      provider,
      verdict: args.verdict,
      summary: args.summary,
      performedAt: args.performed_at,
      evidenceRefs: args.evidence_refs,
      readiness,
      runtimeStatus,
      ticketDetail,
      adminBaseUrl: baseUrl,
      outputPath: relativePathForReport(outputPath),
      requiredNextStep: args.next_step,
    });
  } else {
    report = {
      ...report,
      admin_base_url: safeString(report.admin_base_url || baseUrl) || baseUrl,
      machine_readable_evidence_path: relativePathForReport(outputPath),
    };
  }

  fileSystem.mkdirSync(path.dirname(outputPath), { recursive: true });
  fileSystem.writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  return {
    outputPath,
    report,
  };
}

export async function main(argv = process.argv.slice(2), {
  env = process.env,
  fetchImpl = globalThis.fetch,
  fileSystem = fs,
  stdout = process.stdout,
} = {}) {
  const args = parseArgs(argv);
  if (args.help) {
    stdout.write(`${helpText()}\n`);
    return;
  }
  const { outputPath, report } = await generateOperatorChannelLiveTestEvidenceReport(args, {
    env,
    fetchImpl,
    fileSystem,
  });
  stdout.write(
    [
      `provider=${report.provider}`,
      `derived_status=${report.derived_status}`,
      `operator_verdict=${report.operator_verdict}`,
      `output=${outputPath}`,
      `required_next_step=${report.required_next_step}`,
    ].join('\n') + '\n'
  );
  return {
    outputPath,
    report,
  };
}

const isDirectRun = safeString(process.argv[1]) && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isDirectRun) {
  main().catch((error) => {
    process.stderr.write(`${safeString(error?.message || error || 'generate_operator_channel_live_test_evidence_failed')}\n`);
    process.exitCode = 1;
  });
}
