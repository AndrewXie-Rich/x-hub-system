import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { nowMs, uuid } from './util.js';
import { resolveRuntimeBaseDir } from './local_runtime_ipc.js';
import { pushHubNotification } from './hub_ipc.js';
import {
  ensureHubTlsMaterial,
  readHubCaCertPem,
  readIssuedClientCertPem,
  signClientCertFromCsr,
  tlsModeFromEnv,
  tlsServerNameFromEnv,
} from './tls_support.js';
import {
  buildNonMessageIngressGateSnapshot,
  buildNonMessageIngressGateSnapshotFromAuditRows,
  buildNonMessageIngressScanStats,
  evaluateConnectorIngressWithAudit,
} from './connector_ingress_authorizer.js';
import { createConnectorReconnectOrchestrator } from './connector_reconnect_orchestrator.js';
import { createConnectorTargetOrderingGuard } from './connector_target_ordering_guard.js';
import { createConnectorDeliveryReceiptCompensator } from './connector_delivery_receipt_compensator.js';

function safeString(v) {
  return String(v ?? '').trim();
}

function safeShellValue(v) {
  // For copy-pasteable shell snippets (connect_env). Avoid newlines/NUL.
  return String(v ?? '')
    .replaceAll('\u0000', '')
    .replace(/\r|\n/g, ' ')
    .trim();
}

function shellQuoteSingle(v) {
  const s = safeShellValue(v);
  // POSIX shell single-quote escaping: close -> escaped quote -> reopen.
  return `'${s.replaceAll("'", "'\\''")}'`;
}

function safeStringArray(v) {
  if (v == null) return [];
  if (Array.isArray(v)) return v.map((s) => safeString(s)).filter(Boolean);
  const s = safeString(v);
  if (!s) return [];
  return s
    .split(',')
    .map((x) => safeString(x))
    .filter(Boolean);
}

function jsonResponse(res, status, obj) {
  const body = JSON.stringify(obj ?? {});
  res.writeHead(Number(status || 200), {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  });
  res.end(body);
}

function textResponse(res, status, text, headers = {}) {
  const body = String(text ?? '');
  res.writeHead(Number(status || 200), {
    'content-type': 'text/plain; charset=utf-8',
    'cache-control': 'no-store',
    ...headers,
  });
  res.end(body);
}

function sha256Hex(text) {
  return crypto.createHash('sha256').update(String(text || ''), 'utf8').digest('hex');
}

function sha256FileHex(filePath) {
  const buf = fs.readFileSync(String(filePath || ''));
  return crypto.createHash('sha256').update(buf).digest('hex');
}

function peerIpFromReq(req) {
  try {
    let ip = safeString(req?.socket?.remoteAddress);
    if (!ip) return '';
    if (ip.startsWith('::ffff:')) ip = ip.slice('::ffff:'.length);
    if (ip === '::1') return '::1';
    return ip;
  } catch {
    return '';
  }
}

function ipv4ToInt(ip) {
  const s = safeString(ip);
  const parts = s.split('.');
  if (parts.length !== 4) return null;
  let out = 0;
  for (const p of parts) {
    if (!/^\d+$/.test(p)) return null;
    const n = Number.parseInt(p, 10);
    if (n < 0 || n > 255) return null;
    out = (out << 8) | n;
  }
  return out >>> 0;
}

function isPrivateIPv4(ip) {
  const n = ipv4ToInt(ip);
  if (n == null) return false;
  const u = n >>> 0;
  if (((u & 0xff000000) >>> 0) === 0x0a000000) return true; // 10.0.0.0/8
  if (((u & 0xfff00000) >>> 0) === 0xac100000) return true; // 172.16.0.0/12
  if (((u & 0xffff0000) >>> 0) === 0xc0a80000) return true; // 192.168.0.0/16
  if (((u & 0xffc00000) >>> 0) === 0x64400000) return true; // 100.64.0.0/10 (RFC 6598), commonly used by Tailscale
  return false;
}

function isLoopbackIp(ip) {
  const s = safeString(ip);
  if (!s) return false;
  if (s === '::1') return true;
  const n = ipv4ToInt(s);
  if (n == null) return false;
  return (((n >>> 0) & 0xff000000) >>> 0) === 0x7f000000; // 127.0.0.0/8
}

function ipv4InCidr(ip, cidrText) {
  const cidr = safeString(cidrText);
  if (!cidr) return false;
  const [baseIp, maskText] = cidr.split('/');
  const maskBits = maskText == null || maskText === '' ? 32 : Number.parseInt(String(maskText), 10);
  if (!Number.isFinite(maskBits) || maskBits < 0 || maskBits > 32) return false;
  const ipN = ipv4ToInt(ip);
  const baseN = ipv4ToInt(baseIp);
  if (ipN == null || baseN == null) return false;
  const mask = maskBits === 0 ? 0 : ((0xffffffff << (32 - maskBits)) >>> 0);
  return (((ipN & mask) >>> 0) === ((baseN & mask) >>> 0));
}

function peerAllowedByRules(peerIp, allowedRules) {
  const ip = safeString(peerIp);
  const rules = Array.isArray(allowedRules) ? allowedRules : [];
  if (!rules.length) return true;
  if (!ip) return false;

  for (const raw of rules) {
    const r = safeString(raw);
    if (!r) continue;
    const lower = r.toLowerCase();
    if (lower === 'any' || lower === '*') return true;
    if (lower === 'loopback' || lower === 'localhost') {
      if (isLoopbackIp(ip)) return true;
      continue;
    }
    if (lower === 'private') {
      if (isPrivateIPv4(ip)) return true;
      continue;
    }
    if (r === ip) return true;
    if (r.includes('/')) {
      if (ipv4InCidr(ip, r)) return true;
      continue;
    }
    if (ipv4InCidr(ip, `${r}/32`)) return true;
  }
  return false;
}

function readJsonSafe(filePath) {
  try {
    const raw = fs.readFileSync(String(filePath || ''), 'utf8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function writeJsonAtomic(dirPath, fileName, obj) {
  const dir = safeString(dirPath);
  if (!dir) return false;
  try {
    fs.mkdirSync(dir, { recursive: true });
  } catch {
    // ignore
  }
  const outPath = path.join(dir, fileName);
  const tmp = path.join(dir, `.${fileName}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`);
  try {
    // hub_grpc_clients.json includes bearer tokens; keep it owner-readable only.
    fs.writeFileSync(tmp, JSON.stringify(obj, null, 2) + '\n', { encoding: 'utf8', mode: 0o600 });
    fs.renameSync(tmp, outPath);
    try {
      fs.chmodSync(outPath, 0o600);
    } catch {
      // ignore
    }
    return true;
  } catch {
    try {
      fs.unlinkSync(tmp);
    } catch {
      // ignore
    }
    return false;
  }
}

function connectorIngressReceiptsFileName() {
  return 'connector_ingress_receipts_status.json';
}

function normalizeConnectorIngressReceiptRow(row = {}) {
  const receipt_id = safeString(row.receipt_id);
  if (!receipt_id) return null;
  return {
    receipt_id,
    request_id: safeString(row.request_id),
    project_id: safeString(row.project_id),
    connector: safeString(row.connector).toLowerCase(),
    target_id: safeString(row.target_id),
    ingress_type: safeString(row.ingress_type).toLowerCase(),
    channel_scope: safeString(row.channel_scope).toLowerCase(),
    source_id: safeString(row.source_id),
    message_id: safeString(row.message_id),
    dedupe_key: safeString(row.dedupe_key),
    received_at_ms: Math.max(0, Number(row.received_at_ms || 0)),
    event_sequence: Math.max(0, Number(row.event_sequence || 0)),
    delivery_state: safeString(row.delivery_state).toLowerCase(),
    runtime_state: safeString(row.runtime_state).toLowerCase(),
  };
}

function appendConnectorIngressReceiptSnapshot(runtimeBaseDir, row = {}) {
  const base = safeString(runtimeBaseDir || resolveRuntimeBaseDir());
  if (!base) return false;

  const normalized = normalizeConnectorIngressReceiptRow(row);
  if (!normalized) return false;

  const existing = readJsonSafe(path.join(base, connectorIngressReceiptsFileName()));
  const items = Array.isArray(existing?.items)
    ? existing.items.map(normalizeConnectorIngressReceiptRow).filter(Boolean)
    : [];
  const deduped = new Map(items.map((item) => [item.receipt_id, item]));
  deduped.set(normalized.receipt_id, normalized);

  const limitRaw = Number.parseInt(safeString(process.env.HUB_CONNECTOR_INGRESS_RECEIPTS_MAX || '240'), 10);
  const maxItems = Math.max(16, Math.min(2000, Number.isFinite(limitRaw) ? limitRaw : 240));
  const merged = Array.from(deduped.values())
    .sort((left, right) => {
      const lts = Math.max(0, Number(left?.received_at_ms || 0));
      const rts = Math.max(0, Number(right?.received_at_ms || 0));
      if (lts !== rts) return rts - lts;
      return safeString(left?.receipt_id).localeCompare(safeString(right?.receipt_id));
    })
    .slice(0, maxItems);

  return writeJsonAtomic(base, connectorIngressReceiptsFileName(), {
    schema_version: 'connector_ingress_receipts_status.v1',
    updated_at_ms: Math.max(normalized.received_at_ms, Date.now()),
    items: merged,
  });
}

function clientsConfigPath(runtimeBaseDir) {
  const base = safeString(runtimeBaseDir);
  if (!base) return '';
  return path.join(base, 'hub_grpc_clients.json');
}

function defaultClientCaps() {
  // Keep in sync with HubGRPCClientsStore.defaultCapabilities() (Swift).
  return ['models', 'events', 'memory', 'skills', 'ai.generate.local'];
}

function defaultAllowedCidrs() {
  // Default to the Hub's LAN allowlist if configured.
  //
  // When the Hub app launches the embedded gRPC server, it sets HUB_ALLOWED_CIDRS
  // to a safe LAN boundary (private + loopback + detected interface subnets).
  //
  // We use that as the default `allowed_cidrs` for newly approved devices so they
  // inherit the same source-IP boundary as the server itself.
  const fromEnv = safeStringArray(process.env.HUB_ALLOWED_CIDRS || process.env.HUB_PAIRING_ALLOWED_CIDRS || '');
  if (fromEnv.length) return fromEnv;
  return ['private', 'loopback'];
}

const PAID_MODEL_SELECTION_MODES = new Set(['off', 'all_paid_models', 'custom_selected_models']);
const POLICY_MODES = new Set(['new_profile', 'legacy_grant']);
const DEFAULT_PAIRING_DAILY_TOKEN_LIMIT = 500000;
const DEFAULT_PAIRING_SINGLE_REQUEST_TOKEN_LIMIT = 12000;

function uniqueStrings(values) {
  const out = [];
  const seen = new Set();
  for (const raw of Array.isArray(values) ? values : []) {
    const cleaned = safeString(raw);
    if (!cleaned || seen.has(cleaned)) continue;
    seen.add(cleaned);
    out.push(cleaned);
  }
  return out;
}

function normalizedPaidModelSelectionMode(value, fallback = 'off') {
  const mode = safeString(value).toLowerCase();
  return PAID_MODEL_SELECTION_MODES.has(mode) ? mode : fallback;
}

function normalizedPolicyMode(value, fallback = 'legacy_grant') {
  const mode = safeString(value).toLowerCase();
  return POLICY_MODES.has(mode) ? mode : fallback;
}

function parseDailyTokenLimit(value, fallback = DEFAULT_PAIRING_DAILY_TOKEN_LIMIT) {
  if (value == null || value === '') return fallback;
  const num = Number(value);
  if (!Number.isInteger(num) || num <= 0) return null;
  return num;
}

function derivePolicyCapabilities(capabilities, { paid_model_selection_mode = 'off', default_web_fetch_enabled = false } = {}) {
  const base = uniqueStrings((Array.isArray(capabilities) && capabilities.length ? capabilities : defaultClientCaps()))
    .filter((item) => item !== 'ai.generate.paid' && item !== 'web.fetch');
  if (paid_model_selection_mode !== 'off') base.push('ai.generate.paid');
  if (default_web_fetch_enabled) base.push('web.fetch');
  return uniqueStrings(base);
}

function buildApprovedTrustProfile({
  device_id,
  device_name,
  capabilities,
  paid_model_selection_mode,
  allowed_paid_models,
  default_web_fetch_enabled,
  daily_token_limit,
  audit_ref,
} = {}) {
  const mode = normalizedPaidModelSelectionMode(paid_model_selection_mode, 'off');
  return {
    schema_version: 'hub.paired_terminal_trust_profile.v1',
    device_id: safeString(device_id),
    device_name: safeString(device_name),
    trust_mode: 'trusted_daily',
    capabilities: derivePolicyCapabilities(capabilities, {
      paid_model_selection_mode: mode,
      default_web_fetch_enabled: default_web_fetch_enabled === true,
    }),
    paid_model_policy: {
      schema_version: 'hub.paired_terminal_paid_model_policy.v1',
      mode,
      allowed_model_ids: mode === 'custom_selected_models' ? uniqueStrings(allowed_paid_models) : [],
    },
    network_policy: {
      default_web_fetch_enabled: default_web_fetch_enabled === true,
    },
    budget_policy: {
      daily_token_limit: Math.max(1, Number(daily_token_limit || DEFAULT_PAIRING_DAILY_TOKEN_LIMIT) || DEFAULT_PAIRING_DAILY_TOKEN_LIMIT),
      single_request_token_limit: DEFAULT_PAIRING_SINGLE_REQUEST_TOKEN_LIMIT,
    },
    audit_ref: safeString(audit_ref),
  };
}

function parseApprovedTrustProfile(raw) {
  if (!raw) return null;
  try {
    const obj = JSON.parse(String(raw));
    return obj && typeof obj === 'object' ? obj : null;
  } catch {
    return null;
  }
}

function readClientsSnapshot(runtimeBaseDir) {
  const fp = clientsConfigPath(runtimeBaseDir);
  const obj = readJsonSafe(fp);
  if (!obj || typeof obj !== 'object') {
    return { schema_version: 'hub_grpc_clients.v1', updated_at_ms: 0, clients: [] };
  }
  const clients = Array.isArray(obj.clients) ? obj.clients : Array.isArray(obj.devices) ? obj.devices : [];
  return {
    schema_version: safeString(obj.schema_version) || 'hub_grpc_clients.v1',
    updated_at_ms: Number(obj.updated_at_ms || 0) || 0,
    clients: Array.isArray(clients) ? clients : [],
  };
}

function upsertClientInSnapshot(snap, entry) {
  const out = snap && typeof snap === 'object' ? { ...snap } : { schema_version: 'hub_grpc_clients.v1', updated_at_ms: 0, clients: [] };
  out.schema_version = safeString(out.schema_version) || 'hub_grpc_clients.v1';
  if (!Array.isArray(out.clients)) out.clients = [];
  const did = safeString(entry?.device_id);
  if (!did) return out;

  let replaced = false;
  out.clients = out.clients.map((c) => {
    const curDid = safeString(c?.device_id ?? c?.id);
    if (curDid && curDid === did) {
      replaced = true;
      return { ...(c && typeof c === 'object' ? c : {}), ...entry };
    }
    return c;
  });
  if (!replaced) out.clients.push(entry);
  out.updated_at_ms = nowMs();
  return out;
}

function writeClientsSnapshot(runtimeBaseDir, snap) {
  const base = safeString(runtimeBaseDir);
  if (!base) return false;
  return writeJsonAtomic(base, 'hub_grpc_clients.json', snap);
}

function generateClientToken() {
  const bytes = crypto.randomBytes(32);
  // URL-safe base64 (no padding).
  const b64 = bytes
    .toString('base64')
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '');
  return `axhub_client_${b64}`;
}

function generateDeviceId() {
  const id = crypto.randomUUID().replaceAll('-', '').toLowerCase();
  return `dev_${id.slice(0, 12)}`;
}

function base64EncodeUtf8(s) {
  try {
    return Buffer.from(String(s || ''), 'utf8').toString('base64');
  } catch {
    return '';
  }
}

function base64DecodeUtf8(s) {
  try {
    return Buffer.from(String(s || ''), 'base64').toString('utf8');
  } catch {
    return '';
  }
}

function bearerTokenFromReq(req) {
  const raw = safeString(req?.headers?.authorization);
  if (!raw) return '';
  const lower = raw.toLowerCase();
  if (lower.startsWith('bearer ')) return raw.slice('bearer '.length).trim();
  return raw;
}

function requireHttpAdmin(req) {
  const expected = safeString(process.env.HUB_ADMIN_TOKEN);
  if (!expected) {
    return { ok: false, status: 503, code: 'admin_token_not_configured', message: 'Admin token is not configured on this Hub' };
  }

  const tok = bearerTokenFromReq(req);
  if (!tok || tok !== expected) return { ok: false, status: 401, code: 'unauthenticated', message: 'Missing/invalid admin token' };

  const peerIp = peerIpFromReq(req);
  const allowRemote = safeString(process.env.HUB_ADMIN_ALLOW_REMOTE) === '1';
  const adminAllowed = safeStringArray(process.env.HUB_ADMIN_ALLOWED_CIDRS || '');
  if (!allowRemote) {
    if (adminAllowed.length) {
      if (!peerAllowedByRules(peerIp, adminAllowed)) {
        return { ok: false, status: 403, code: 'permission_denied', message: 'Admin source IP is not allowed' };
      }
    } else if (!isLoopbackIp(peerIp)) {
      return { ok: false, status: 403, code: 'permission_denied', message: 'Admin endpoints are local-only' };
    }
  }
  return { ok: true };
}

function parseQuery(urlObj) {
  const out = {};
  try {
    for (const [k, v] of urlObj.searchParams.entries()) {
      out[String(k || '')] = String(v || '');
    }
  } catch {
    // ignore
  }
  return out;
}

function readBodyJson(req, { maxBytes }) {
  const lim = Math.max(256, Math.min(1024 * 256, Number(maxBytes || 0) || 1024 * 64)); // default 64KB
  return new Promise((resolve) => {
    let settled = false;
    let size = 0;
    let body = '';
    let overflowed = false;
    const finish = (out) => {
      if (settled) return;
      settled = true;
      resolve(out);
    };
    req.on('data', (chunk) => {
      if (settled) return;
      try {
        const s = chunk.toString('utf8');
        size += Buffer.byteLength(s, 'utf8');
        if (size > lim) {
          // Mark overflow and keep draining stream without buffering.
          overflowed = true;
          return;
        }
        if (!overflowed) body += s;
      } catch {
        finish({ ok: false, error: 'bad_body' });
      }
    });
    req.on('end', () => {
      if (settled) return;
      if (overflowed) return finish({ ok: false, error: 'body_too_large' });
      if (!body) return finish({ ok: true, json: {} });
      try {
        const obj = JSON.parse(body);
        finish({ ok: true, json: obj && typeof obj === 'object' ? obj : {} });
      } catch {
        finish({ ok: false, error: 'bad_json' });
      }
    });
    req.on('error', () => finish({ ok: false, error: 'bad_body' }));
  });
}

function boundedInt(raw, { fallback, min, max }) {
  const n = Number.parseInt(String(raw ?? ''), 10);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

function parsePositiveInt(raw) {
  const n = Number.parseInt(String(raw ?? ''), 10);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return n;
}

function ratio(numerator, denominator) {
  if (!Number.isFinite(numerator) || !Number.isFinite(denominator) || denominator <= 0) return 0;
  const r = numerator / denominator;
  if (!Number.isFinite(r) || r <= 0) return 0;
  if (r >= 1) return 1;
  return Number(r.toFixed(6));
}

function rateLimitFromRetryMs(retryAfterMs) {
  const n = Math.max(0, Number(retryAfterMs || 0));
  return Math.ceil(n / 1000);
}

function sourceKeyFromReq(req, queryObj, peerIp) {
  const q = queryObj && typeof queryObj === 'object' ? queryObj : {};
  const headerKey =
    safeString(req?.headers?.['x-source-key'])
    || safeString(req?.headers?.['x-webhook-source-key'])
    || safeString(req?.headers?.['x-source'])
    || safeString(req?.headers?.['x-forwarded-for']);
  return safeString(headerKey || q.source_key || peerIp || 'unknown');
}

function connectionKeyFromReq(req, peerIp, sourceKey) {
  const ip = safeString(req?.socket?.remoteAddress || peerIp || '');
  const remotePort = Math.max(0, Number(req?.socket?.remotePort || 0));
  const localPort = Math.max(0, Number(req?.socket?.localPort || 0));
  const source = safeString(sourceKey || '');
  if (ip && remotePort > 0 && localPort > 0) return `${ip}:${remotePort}->${localPort}`;
  if (ip && remotePort > 0) return `${ip}:${remotePort}`;
  if (ip) return ip;
  return source || 'unknown_connection';
}

function readEnvJsonObject(raw) {
  const text = safeString(raw);
  if (!text) return {};
  try {
    const out = JSON.parse(text);
    return out && typeof out === 'object' ? out : {};
  } catch {
    return {};
  }
}

function combineStringList(...inputs) {
  const out = new Set();
  for (const input of inputs) {
    const arr = safeStringArray(input);
    for (const item of arr) out.add(item);
  }
  return Array.from(out);
}

function connectorIngressPolicyFromEnv(env = process.env) {
  const e = env && typeof env === 'object' ? env : {};
  const fromJson = readEnvJsonObject(e.HUB_CONNECTOR_INGRESS_POLICY_JSON);
  return {
    dm_allow_from: combineStringList(fromJson.dm_allow_from, e.HUB_CONNECTOR_DM_ALLOW_FROM),
    dm_pairing_allow_from: combineStringList(
      fromJson.dm_pairing_allow_from,
      e.HUB_CONNECTOR_DM_PAIRING_ALLOW_FROM,
      e.HUB_CONNECTOR_DM_PAIRING_ALLOWLIST
    ),
    group_allow_from: combineStringList(fromJson.group_allow_from, e.HUB_CONNECTOR_GROUP_ALLOW_FROM),
    webhook_allow_from: combineStringList(fromJson.webhook_allow_from, e.HUB_CONNECTOR_WEBHOOK_ALLOW_FROM),
  };
}

function normalizeIngressTypeFromEvent(input) {
  const raw = safeString(input).toLowerCase();
  if (!raw) return '';
  if (raw === 'message' || raw.startsWith('message.')) return 'message';
  if (raw === 'reaction' || raw.startsWith('reaction') || raw.includes('reaction')) return 'reaction';
  if (raw === 'pin' || raw.startsWith('pin') || raw.includes('pin')) return 'pin';
  if (
    raw === 'member'
    || raw.startsWith('member')
    || raw.includes('member')
    || raw.includes('join')
    || raw.includes('leave')
  ) return 'member';
  if (raw === 'webhook' || raw.startsWith('webhook')) return 'webhook';
  return '';
}

function normalizeChannelScopeFromEvent(input, fallback = 'group') {
  const raw = safeString(input).toLowerCase();
  if (raw === 'dm' || raw === 'direct' || raw === 'direct_message') return 'dm';
  if (raw === 'group' || raw === 'channel' || raw === 'room') return 'group';
  return fallback === 'dm' ? 'dm' : 'group';
}

function senderIdFromEventBody(obj = {}) {
  const body = obj && typeof obj === 'object' ? obj : {};
  const payload = body.payload && typeof body.payload === 'object' ? body.payload : null;
  const candidates = payload ? [body, payload] : [body];
  for (const sample of candidates) {
    if (!sample || typeof sample !== 'object') continue;
    if (sample.sender && typeof sample.sender === 'object') {
      const nested = safeString(sample.sender.id || sample.sender.user_id || sample.sender.member_id);
      if (nested) return nested;
    }
    if (sample.user && typeof sample.user === 'object') {
      const nested = safeString(sample.user.id || sample.user.user_id || sample.user.member_id);
      if (nested) return nested;
    }
    const direct = safeString(
      sample.sender_id
      || sample.actor_id
      || sample.member_id
      || sample.user_id
      || sample.author_id
    );
    if (direct) return direct;
  }
  return '';
}

function connectorIngressEventFromBody({
  connector,
  target_id,
  body,
  replay_key,
  fallbackIngressType = 'message',
} = {}) {
  const obj = body && typeof body === 'object' ? body : {};
  const payload = obj.payload && typeof obj.payload === 'object' ? obj.payload : {};
  const hintedIngressType = normalizeIngressTypeFromEvent(
    obj.ingress_type
    || obj.event_type
    || obj.action
    || obj.type
    || payload.ingress_type
    || payload.event_type
    || payload.action
    || payload.type
  );
  const ingress_type = hintedIngressType || normalizeIngressTypeFromEvent(fallbackIngressType);
  const channelHint = safeString(
    obj.channel_id || obj.room_id || obj.target_id
    || payload.channel_id || payload.room_id || payload.target_id
    || target_id
  ).toLowerCase();
  const scopeFallback = channelHint.startsWith('dm') || channelHint.startsWith('im') ? 'dm' : 'group';
  const channel_scope = normalizeChannelScopeFromEvent(
    obj.channel_scope || obj.scope || obj.channel_type
    || payload.channel_scope || payload.scope || payload.channel_type,
    scopeFallback
  );
  return {
    ingress_type,
    channel_scope,
    sender_id: senderIdFromEventBody(obj),
    channel_id: safeString(obj.channel_id || obj.room_id || obj.thread_id || payload.channel_id || payload.room_id || payload.thread_id || target_id),
    message_id: safeString(obj.message_id || obj.event_id || replay_key || obj.id || payload.message_id || payload.event_id || payload.id),
    event_sequence: parsePositiveInt(
      obj.event_sequence
      || obj.sequence
      || obj.seq
      || payload.event_sequence
      || payload.sequence
      || payload.seq
    ),
    source_id: safeString(obj.source_id || obj.webhook_source_id || payload.source_id || payload.webhook_source_id || `${safeString(connector)}:${safeString(target_id)}`),
    signature_valid: obj.signature_valid !== false && payload.signature_valid !== false,
    replay_detected: obj.replay_detected === true || payload.replay_detected === true,
  };
}

export function createPreauthSurfaceGuard(options = {}) {
  const opts = options && typeof options === 'object' ? options : {};
  const clock = typeof opts.nowFn === 'function' ? opts.nowFn : nowMs;
  const state = new Map(); // source_key -> { count, reset_at_ms, last_seen_ms }
  const stats = {
    total: 0,
    rejected: 0,
    fail_closed: 0,
  };

  const windowMs = boundedInt(opts.window_ms, { fallback: 60_000, min: 1_000, max: 10 * 60_000 });
  const maxPerWindow = boundedInt(opts.max_per_window, { fallback: 12, min: 1, max: 1_000 });
  const maxStateKeys = boundedInt(opts.max_state_keys, { fallback: 2_048, min: 16, max: 100_000 });
  const staleWindowMs = boundedInt(
    opts.stale_window_ms,
    { fallback: Math.max(windowMs * 3, 120_000), min: windowMs, max: 24 * 60 * 60 * 1000 }
  );

  function prune(now) {
    const ts = Math.max(0, Number(now || clock()) || 0);
    for (const [key, item] of state.entries()) {
      const resetAtMs = Math.max(0, Number(item?.reset_at_ms || 0));
      const lastSeenMs = Math.max(0, Number(item?.last_seen_ms || 0));
      const staleRef = Math.max(resetAtMs, lastSeenMs);
      if (!staleRef || (ts - staleRef) >= staleWindowMs) state.delete(key);
    }
  }

  function snapshot() {
    const total = Math.max(0, Number(stats.total || 0));
    const rejected = Math.max(0, Number(stats.rejected || 0));
    const failClosed = Math.max(0, Number(stats.fail_closed || 0));
    return {
      total,
      rejected,
      fail_closed: failClosed,
      preauth_reject_rate: ratio(rejected, total),
      state_keys: state.size,
      max_state_keys: maxStateKeys,
      stale_window_ms: staleWindowMs,
      window_ms: windowMs,
      max_per_window: maxPerWindow,
    };
  }

  function check({ source_key, now_ms } = {}) {
    stats.total += 1;
    try {
      const now = Math.max(0, Number(now_ms || clock()) || 0);
      prune(now);
      const key = safeString(source_key) || 'unknown';
      let cur = state.get(key);
      if (!cur) {
        if (state.size >= maxStateKeys) {
          stats.rejected += 1;
          return {
            ok: false,
            deny_code: 'preauth_state_overflow',
            retry_after_ms: staleWindowMs,
            source_key: key,
          };
        }
        cur = {
          count: 0,
          reset_at_ms: now + windowMs,
          last_seen_ms: now,
        };
      } else {
        const resetAtMs = Math.max(0, Number(cur.reset_at_ms || 0));
        if (!resetAtMs || now >= resetAtMs) {
          cur.count = 0;
          cur.reset_at_ms = now + windowMs;
        }
        cur.last_seen_ms = now;
      }

      if (cur.count >= maxPerWindow) {
        state.set(key, cur);
        stats.rejected += 1;
        return {
          ok: false,
          deny_code: 'rate_limited',
          retry_after_ms: Math.max(1_000, Math.max(0, Number(cur.reset_at_ms || 0) - now)),
          source_key: key,
        };
      }

      cur.count += 1;
      cur.last_seen_ms = now;
      if (!Number(cur.reset_at_ms || 0)) cur.reset_at_ms = now + windowMs;
      state.set(key, cur);
      return {
        ok: true,
        source_key: key,
        remaining: Math.max(0, maxPerWindow - cur.count),
      };
    } catch {
      stats.rejected += 1;
      stats.fail_closed += 1;
      return {
        ok: false,
        deny_code: 'preauth_fail_closed',
        retry_after_ms: staleWindowMs,
        source_key: safeString(source_key) || 'unknown',
      };
    }
  }

  return {
    check,
    snapshot,
    prune,
  };
}

export function createUnauthorizedFloodBreaker(options = {}) {
  const opts = options && typeof options === 'object' ? options : {};
  const clock = typeof opts.nowFn === 'function' ? opts.nowFn : nowMs;
  const state = new Map(); // connection_key -> { unauthorized_count, window_started_ms, penalty_until_ms, last_seen_ms, last_deny_code }
  const stats = {
    checks: 0,
    dropped: 0,
    unauthorized: 0,
    penalties: 0,
    fail_closed: 0,
    sampled_drop_logs: 0,
  };

  const windowMs = boundedInt(opts.window_ms, { fallback: 30_000, min: 1_000, max: 10 * 60_000 });
  const maxUnauthorizedPerWindow = boundedInt(opts.max_unauthorized_per_window, { fallback: 8, min: 1, max: 10_000 });
  const penaltyMs = boundedInt(opts.penalty_ms, { fallback: 15_000, min: 1_000, max: 10 * 60_000 });
  const maxStateKeys = boundedInt(opts.max_state_keys, { fallback: 4_096, min: 16, max: 100_000 });
  const staleWindowMs = boundedInt(
    opts.stale_window_ms,
    { fallback: Math.max(windowMs * 4, 120_000), min: windowMs, max: 24 * 60 * 60 * 1000 }
  );
  const auditSampleEvery = boundedInt(opts.audit_sample_every, { fallback: 5, min: 1, max: 10_000 });

  function prune(now) {
    const ts = Math.max(0, Number(now || clock()) || 0);
    for (const [key, item] of state.entries()) {
      const lastSeenMs = Math.max(0, Number(item?.last_seen_ms || 0));
      const penaltyUntilMs = Math.max(0, Number(item?.penalty_until_ms || 0));
      const staleRef = Math.max(lastSeenMs, penaltyUntilMs);
      if (!staleRef || (ts - staleRef) >= staleWindowMs) state.delete(key);
    }
  }

  function dropAuditSampled() {
    if (auditSampleEvery <= 1) return true;
    const dropped = Math.max(0, Number(stats.dropped || 0));
    return (dropped % auditSampleEvery) === 1;
  }

  function ensureStateCapacity() {
    if (state.size < maxStateKeys) return;
    let oldestKey = '';
    let oldestSeen = Number.POSITIVE_INFINITY;
    for (const [key, item] of state.entries()) {
      const seen = Math.max(0, Number(item?.last_seen_ms || 0));
      if (seen < oldestSeen) {
        oldestSeen = seen;
        oldestKey = key;
      }
    }
    if (oldestKey) state.delete(oldestKey);
  }

  function snapshot() {
    return {
      checks: Math.max(0, Number(stats.checks || 0)),
      dropped: Math.max(0, Number(stats.dropped || 0)),
      unauthorized: Math.max(0, Number(stats.unauthorized || 0)),
      penalties: Math.max(0, Number(stats.penalties || 0)),
      fail_closed: Math.max(0, Number(stats.fail_closed || 0)),
      sampled_drop_logs: Math.max(0, Number(stats.sampled_drop_logs || 0)),
      unauthorized_flood_drop_count: Math.max(0, Number(stats.dropped || 0)),
      state_keys: state.size,
      max_state_keys: maxStateKeys,
      window_ms: windowMs,
      penalty_ms: penaltyMs,
      stale_window_ms: staleWindowMs,
      max_unauthorized_per_window: maxUnauthorizedPerWindow,
      audit_sample_every: auditSampleEvery,
    };
  }

  function check({ connection_key, now_ms } = {}) {
    stats.checks += 1;
    const key = safeString(connection_key) || 'unknown_connection';
    try {
      const now = Math.max(0, Number(now_ms || clock()) || 0);
      prune(now);
      let cur = state.get(key);
      if (!cur) {
        ensureStateCapacity();
        cur = {
          unauthorized_count: 0,
          window_started_ms: now,
          penalty_until_ms: 0,
          last_seen_ms: now,
          last_deny_code: '',
        };
      }
      cur.last_seen_ms = now;
      state.set(key, cur);

      const penaltyUntilMs = Math.max(0, Number(cur.penalty_until_ms || 0));
      if (penaltyUntilMs > now) {
        stats.dropped += 1;
        const sampled = dropAuditSampled();
        if (sampled) stats.sampled_drop_logs += 1;
        return {
          ok: false,
          deny_code: 'unauthorized_flood_dropped',
          retry_after_ms: Math.max(1_000, penaltyUntilMs - now),
          connection_key: key,
          audit_sampled: sampled,
          last_deny_code: safeString(cur.last_deny_code || ''),
        };
      }

      return {
        ok: true,
        connection_key: key,
      };
    } catch {
      stats.dropped += 1;
      stats.fail_closed += 1;
      return {
        ok: false,
        deny_code: 'unauthorized_flood_fail_closed',
        retry_after_ms: windowMs,
        connection_key: key,
        audit_sampled: true,
        last_deny_code: '',
      };
    }
  }

  function recordUnauthorized({ connection_key, deny_code, now_ms } = {}) {
    stats.unauthorized += 1;
    const key = safeString(connection_key) || 'unknown_connection';
    try {
      const now = Math.max(0, Number(now_ms || clock()) || 0);
      prune(now);
      let cur = state.get(key);
      if (!cur) {
        ensureStateCapacity();
        cur = {
          unauthorized_count: 0,
          window_started_ms: now,
          penalty_until_ms: 0,
          last_seen_ms: now,
          last_deny_code: '',
        };
      }

      if ((now - Math.max(0, Number(cur.window_started_ms || 0))) >= windowMs) {
        cur.unauthorized_count = 0;
        cur.window_started_ms = now;
      }

      cur.unauthorized_count = Math.max(0, Number(cur.unauthorized_count || 0)) + 1;
      cur.last_seen_ms = now;
      cur.last_deny_code = safeString(deny_code || '');

      let triggered = false;
      if (cur.unauthorized_count >= maxUnauthorizedPerWindow) {
        cur.penalty_until_ms = Math.max(now + penaltyMs, Math.max(0, Number(cur.penalty_until_ms || 0)));
        cur.unauthorized_count = 0;
        cur.window_started_ms = now;
        triggered = true;
        stats.penalties += 1;
      }

      state.set(key, cur);
      return {
        ok: true,
        triggered,
        connection_key: key,
        penalty_until_ms: Math.max(0, Number(cur.penalty_until_ms || 0)),
      };
    } catch {
      stats.fail_closed += 1;
      return {
        ok: false,
        triggered: true,
        connection_key: key,
        penalty_until_ms: 0,
      };
    }
  }

  return {
    check,
    recordUnauthorized,
    snapshot,
    prune,
  };
}

export function createWebhookReplayGuard(options = {}) {
  const opts = options && typeof options === 'object' ? options : {};
  const clock = typeof opts.nowFn === 'function' ? opts.nowFn : nowMs;
  const db = opts.db && typeof opts.db === 'object' ? opts.db : null;
  const hasPersistentStore = !!(
    db
    && typeof db.claimConnectorWebhookReplay === 'function'
    && typeof db.pruneConnectorWebhookReplayGuard === 'function'
    && typeof db.getConnectorWebhookReplayGuardStats === 'function'
  );
  const seen = new Map(); // replay_key_hash -> { expire_at_ms, last_seen_ms }
  const stats = {
    total: 0,
    blocked: 0,
    fail_closed: 0,
  };
  let replayKeysEstimate = 0;

  const ttlMs = boundedInt(opts.ttl_ms, { fallback: 10 * 60 * 1000, min: 1_000, max: 7 * 24 * 60 * 60 * 1000 });
  const maxKeys = boundedInt(opts.max_keys, { fallback: 20_000, min: 64, max: 1_000_000 });
  const staleWindowMs = boundedInt(opts.stale_window_ms, { fallback: Math.max(ttlMs * 2, 120_000), min: ttlMs, max: 14 * 24 * 60 * 60 * 1000 });

  function prune(now) {
    const ts = Math.max(0, Number(now || clock()) || 0);
    if (hasPersistentStore) {
      const pruned = db.pruneConnectorWebhookReplayGuard({
        now_ms: ts,
        stale_window_ms: staleWindowMs,
      });
      replayKeysEstimate = Math.max(0, Number(pruned?.entries || replayKeysEstimate || 0));
      return;
    }
    for (const [key, item] of seen.entries()) {
      const expireAt = Math.max(0, Number(item?.expire_at_ms || 0));
      const lastSeenMs = Math.max(0, Number(item?.last_seen_ms || 0));
      if (expireAt <= ts || (lastSeenMs > 0 && (ts - lastSeenMs) >= staleWindowMs)) {
        seen.delete(key);
      }
    }
  }

  function snapshot() {
    const total = Math.max(0, Number(stats.total || 0));
    const blocked = Math.max(0, Number(stats.blocked || 0));
    let replayKeys = seen.size;
    if (hasPersistentStore) {
      const storeStats = db.getConnectorWebhookReplayGuardStats();
      replayKeysEstimate = Math.max(0, Number(storeStats?.entries || replayKeysEstimate || 0));
      replayKeys = replayKeysEstimate;
    }
    return {
      total,
      blocked,
      fail_closed: Math.max(0, Number(stats.fail_closed || 0)),
      webhook_replay_block_rate: ratio(blocked, total),
      replay_keys: replayKeys,
      max_keys: maxKeys,
      ttl_ms: ttlMs,
      stale_window_ms: staleWindowMs,
    };
  }

  function claim({
    connector,
    target_id,
    replay_key,
    signature,
    now_ms,
  } = {}) {
    stats.total += 1;
    const c = safeString(connector).toLowerCase();
    const t = safeString(target_id);
    const replayKey = safeString(replay_key);
    const sig = safeString(signature);

    try {
      const now = Math.max(0, Number(now_ms || clock()) || 0);
      if (!c || !t || !replayKey) {
        stats.blocked += 1;
        return {
          ok: false,
          deny_code: 'invalid_replay_key',
          replay_key_hash: '',
        };
      }

      prune(now);
      const replayKeyHash = sha256Hex(`${c}:${t}:${replayKey}:${sig}`);
      if (hasPersistentStore) {
        const persisted = db.claimConnectorWebhookReplay({
          connector: c,
          target_id: t,
          replay_key_hash: replayKeyHash,
          first_seen_at_ms: now,
          expire_at_ms: now + ttlMs,
          max_entries: maxKeys,
          stale_window_ms: staleWindowMs,
        });
        replayKeysEstimate = Math.max(0, Number(persisted?.entries || replayKeysEstimate || 0));
        if (!persisted?.ok) {
          stats.blocked += 1;
          return {
            ok: false,
            deny_code: String(persisted?.deny_code || 'replay_guard_error'),
            replay_key_hash: replayKeyHash,
          };
        }
        return {
          ok: true,
          replay_key_hash: replayKeyHash,
          expire_at_ms: Math.max(0, Number(persisted?.expire_at_ms || (now + ttlMs))),
        };
      }

      const existing = seen.get(replayKeyHash);
      if (existing && Number(existing.expire_at_ms || 0) > now) {
        stats.blocked += 1;
        return {
          ok: false,
          deny_code: 'replay_detected',
          replay_key_hash: replayKeyHash,
        };
      }

      if (!existing && seen.size >= maxKeys) {
        stats.blocked += 1;
        return {
          ok: false,
          deny_code: 'replay_store_overflow',
          replay_key_hash: replayKeyHash,
        };
      }

      seen.set(replayKeyHash, {
        expire_at_ms: now + ttlMs,
        last_seen_ms: now,
      });
      return {
        ok: true,
        replay_key_hash: replayKeyHash,
        expire_at_ms: now + ttlMs,
      };
    } catch {
      stats.blocked += 1;
      stats.fail_closed += 1;
      return {
        ok: false,
        deny_code: 'replay_guard_error',
        replay_key_hash: '',
      };
    }
  }

  return {
    claim,
    snapshot,
    prune,
  };
}

let axhubctlAssetCache = null;
function loadAxhubctlAsset() {
  if (axhubctlAssetCache) return axhubctlAssetCache;
  try {
    const here = path.dirname(fileURLToPath(import.meta.url));
    const assetPath = path.resolve(here, '..', 'assets', 'axhubctl');
    if (!fs.existsSync(assetPath)) return null;
    const content = fs.readFileSync(assetPath, 'utf8');
    const sha256 = sha256FileHex(assetPath);
    axhubctlAssetCache = { path: assetPath, content, sha256 };
    return axhubctlAssetCache;
  } catch {
    return null;
  }
}

let axhubClientKitAssetCache = null;
function loadAxhubClientKitAsset() {
  // NOTE: This asset is usually injected into the .app bundle by tools/build_hub_app.command.
  // Repo/dev runs may not have it.
  if (axhubClientKitAssetCache) return axhubClientKitAssetCache;
  try {
    const here = path.dirname(fileURLToPath(import.meta.url));
    const assetPath = path.resolve(here, '..', 'assets', 'axhub_client_kit.tgz');
    if (!fs.existsSync(assetPath)) return null;
    const sha256 = sha256FileHex(assetPath);
    let size_bytes = 0;
    try {
      size_bytes = Number(fs.statSync(assetPath)?.size || 0) || 0;
    } catch {
      size_bytes = 0;
    }
    axhubClientKitAssetCache = { path: assetPath, sha256, size_bytes };
    return axhubClientKitAssetCache;
  } catch {
    return null;
  }
}

function publicBaseFromReq(req, { hostFallback, portFallback, schemeFallback }) {
  const xfProto = safeString(req?.headers?.['x-forwarded-proto']);
  const xfHost = safeString(req?.headers?.['x-forwarded-host']);
  const host = xfHost || safeString(req?.headers?.host) || safeString(hostFallback);
  const scheme = xfProto || safeString(schemeFallback) || 'http';
  if (!host) {
    // Last resort: construct from configured host/port (may be 0.0.0.0 which is not client-usable).
    const h2 = safeString(hostFallback);
    const p2 = Number(portFallback || 0) > 0 ? Number(portFallback) : 0;
    if (!h2 || !p2) return '';
    return `${scheme}://${h2}:${p2}`;
  }
  return `${scheme}://${host}`;
}

function positiveIntOrZero(v) {
  const n = Number.parseInt(String(v ?? ''), 10);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return n;
}

function hostHintFromReq(req, { hostFallback, peerIp }) {
  const hostHeader = safeString(req?.headers?.host);
  if (hostHeader) {
    // Accept "[ipv6]:port", "host:port", or plain host.
    if (hostHeader.startsWith('[') && hostHeader.includes(']')) {
      return safeString(hostHeader.slice(1, hostHeader.indexOf(']')));
    }
    const idx = hostHeader.indexOf(':');
    if (idx > 0) return safeString(hostHeader.slice(0, idx));
    return hostHeader;
  }
  const fallback = safeString(hostFallback);
  if (fallback && fallback !== '0.0.0.0' && fallback !== '::') return fallback;
  if (isPrivateIPv4(peerIp) || isLoopbackIp(peerIp)) return safeString(peerIp);
  return '';
}

export function startPairingHTTPServer({
  db,
  preauthGuard,
  unauthorizedFloodBreaker,
  connectorRuntimeOrchestrator,
  connectorTargetOrderingGuard,
  connectorDeliveryReceiptCompensator,
  webhookReplayGuard,
} = {}) {
  const enabled = safeString(process.env.HUB_PAIRING_ENABLE || '1');
  if (enabled === '0' || enabled.toLowerCase() === 'false') {
    // eslint-disable-next-line no-console
    console.log('[hub_pairing] disabled (HUB_PAIRING_ENABLE=0)');
    return () => {};
  }

  const host = safeString(process.env.HUB_PAIRING_HOST) || safeString(process.env.HUB_HOST) || '0.0.0.0';
  const grpcPort = Number(process.env.HUB_PORT || 50051);
  const port = Number(process.env.HUB_PAIRING_PORT || (Number.isFinite(grpcPort) ? grpcPort + 1 : 50052));
  const schemeFallback = safeString(process.env.HUB_PAIRING_PUBLIC_SCHEME || '') || 'http';
  const hostFallback = safeString(process.env.HUB_PAIRING_PUBLIC_HOST || '') || safeString(process.env.HUB_HOST || '');

  const allowedCidrs = safeStringArray(process.env.HUB_PAIRING_ALLOWED_CIDRS || 'private,loopback');
  const preauthBodyMaxBytes = boundedInt(process.env.HUB_PREAUTH_BODY_MAX_BYTES, {
    fallback: 64 * 1024,
    min: 256,
    max: 1024 * 256,
  });
  const internalPreauthGuard = preauthGuard && typeof preauthGuard?.check === 'function'
    ? preauthGuard
    : createPreauthSurfaceGuard({
      window_ms: boundedInt(process.env.HUB_PREAUTH_WINDOW_MS, { fallback: 60_000, min: 1_000, max: 10 * 60_000 }),
      max_per_window: boundedInt(process.env.HUB_PAIRING_RL_PER_MIN, { fallback: 12, min: 1, max: 1_000 }),
      max_state_keys: boundedInt(process.env.HUB_PREAUTH_MAX_STATE_KEYS, { fallback: 2_048, min: 16, max: 100_000 }),
      stale_window_ms: boundedInt(process.env.HUB_PREAUTH_STALE_WINDOW_MS, { fallback: 180_000, min: 60_000, max: 24 * 60 * 60 * 1000 }),
    });
  const internalUnauthorizedFloodBreaker = unauthorizedFloodBreaker
    && typeof unauthorizedFloodBreaker?.check === 'function'
    && typeof unauthorizedFloodBreaker?.recordUnauthorized === 'function'
    ? unauthorizedFloodBreaker
    : createUnauthorizedFloodBreaker({
      window_ms: boundedInt(process.env.HUB_UNAUTHORIZED_FLOOD_WINDOW_MS, { fallback: 30_000, min: 1_000, max: 10 * 60 * 1000 }),
      max_unauthorized_per_window: boundedInt(process.env.HUB_UNAUTHORIZED_FLOOD_MAX_PER_WINDOW, { fallback: 8, min: 1, max: 10_000 }),
      penalty_ms: boundedInt(process.env.HUB_UNAUTHORIZED_FLOOD_PENALTY_MS, { fallback: 15_000, min: 1_000, max: 10 * 60 * 1000 }),
      max_state_keys: boundedInt(process.env.HUB_UNAUTHORIZED_FLOOD_MAX_STATE_KEYS, { fallback: 4_096, min: 16, max: 100_000 }),
      stale_window_ms: boundedInt(process.env.HUB_UNAUTHORIZED_FLOOD_STALE_WINDOW_MS, { fallback: 300_000, min: 30_000, max: 24 * 60 * 60 * 1000 }),
      audit_sample_every: boundedInt(process.env.HUB_UNAUTHORIZED_FLOOD_AUDIT_SAMPLE_EVERY, { fallback: 5, min: 1, max: 10_000 }),
    });
  const internalConnectorRuntimeOrchestrator = connectorRuntimeOrchestrator
    && typeof connectorRuntimeOrchestrator?.applySignal === 'function'
    && typeof connectorRuntimeOrchestrator?.snapshot === 'function'
    && typeof connectorRuntimeOrchestrator?.getTarget === 'function'
    ? connectorRuntimeOrchestrator
    : createConnectorReconnectOrchestrator({
      stale_window_ms: boundedInt(process.env.HUB_CONNECTOR_RUNTIME_STALE_WINDOW_MS, { fallback: 15 * 60 * 1000, min: 60 * 1000, max: 7 * 24 * 60 * 60 * 1000 }),
      max_targets: boundedInt(process.env.HUB_CONNECTOR_RUNTIME_MAX_TARGETS, { fallback: 2_048, min: 16, max: 100_000 }),
      reconnect_backoff_base_ms: boundedInt(process.env.HUB_CONNECTOR_RECONNECT_BACKOFF_BASE_MS, { fallback: 1_000, min: 100, max: 60_000 }),
      reconnect_backoff_max_ms: boundedInt(process.env.HUB_CONNECTOR_RECONNECT_BACKOFF_MAX_MS, { fallback: 30_000, min: 1_000, max: 10 * 60 * 1000 }),
      reconnect_samples_max: boundedInt(process.env.HUB_CONNECTOR_RECONNECT_SAMPLES_MAX, { fallback: 2_048, min: 32, max: 100_000 }),
    });
  const internalConnectorTargetOrderingGuard = connectorTargetOrderingGuard
    && typeof connectorTargetOrderingGuard?.begin === 'function'
    && typeof connectorTargetOrderingGuard?.complete === 'function'
    && typeof connectorTargetOrderingGuard?.snapshot === 'function'
    && typeof connectorTargetOrderingGuard?.getTarget === 'function'
    ? connectorTargetOrderingGuard
    : createConnectorTargetOrderingGuard({
      lock_ttl_ms: boundedInt(process.env.HUB_CONNECTOR_TARGET_LOCK_TTL_MS, { fallback: 30_000, min: 1_000, max: 10 * 60 * 1000 }),
      seen_ttl_ms: boundedInt(process.env.HUB_CONNECTOR_ORDERING_SEEN_TTL_MS, { fallback: 10 * 60 * 1000, min: 10_000, max: 24 * 60 * 60 * 1000 }),
      stale_window_ms: boundedInt(process.env.HUB_CONNECTOR_ORDERING_STALE_WINDOW_MS, { fallback: 15 * 60 * 1000, min: 60 * 1000, max: 7 * 24 * 60 * 60 * 1000 }),
      max_targets: boundedInt(process.env.HUB_CONNECTOR_ORDERING_MAX_TARGETS, { fallback: 2_048, min: 16, max: 100_000 }),
      max_seen_per_target: boundedInt(process.env.HUB_CONNECTOR_ORDERING_MAX_SEEN_PER_TARGET, { fallback: 2_048, min: 16, max: 100_000 }),
    });
  const internalConnectorDeliveryReceiptCompensator = connectorDeliveryReceiptCompensator
    && typeof connectorDeliveryReceiptCompensator?.prepare === 'function'
    && typeof connectorDeliveryReceiptCompensator?.commit === 'function'
    && typeof connectorDeliveryReceiptCompensator?.undo === 'function'
    && typeof connectorDeliveryReceiptCompensator?.runCompensation === 'function'
    && typeof connectorDeliveryReceiptCompensator?.snapshot === 'function'
    && typeof connectorDeliveryReceiptCompensator?.getTarget === 'function'
    ? connectorDeliveryReceiptCompensator
    : createConnectorDeliveryReceiptCompensator({
      stale_window_ms: boundedInt(process.env.HUB_CONNECTOR_RECEIPT_STALE_WINDOW_MS, { fallback: 6 * 60 * 60 * 1000, min: 60 * 1000, max: 14 * 24 * 60 * 60 * 1000 }),
      max_entries: boundedInt(process.env.HUB_CONNECTOR_RECEIPT_MAX_ENTRIES, { fallback: 10_000, min: 64, max: 1_000_000 }),
      default_commit_timeout_ms: boundedInt(process.env.HUB_CONNECTOR_RECEIPT_COMMIT_TIMEOUT_MS, { fallback: 30_000, min: 1_000, max: 24 * 60 * 60 * 1000 }),
      max_compensation_batch: boundedInt(process.env.HUB_CONNECTOR_RECEIPT_COMPENSATION_MAX_JOBS, { fallback: 128, min: 1, max: 10_000 }),
      compensation_retry_ms: boundedInt(process.env.HUB_CONNECTOR_RECEIPT_COMPENSATION_RETRY_MS, { fallback: 5_000, min: 500, max: 10 * 60 * 1000 }),
    });
  const internalWebhookReplayGuard = webhookReplayGuard && typeof webhookReplayGuard?.claim === 'function'
    ? webhookReplayGuard
    : createWebhookReplayGuard({
      db,
      ttl_ms: boundedInt(process.env.HUB_WEBHOOK_REPLAY_TTL_MS, { fallback: 10 * 60 * 1000, min: 1_000, max: 7 * 24 * 60 * 60 * 1000 }),
      max_keys: boundedInt(process.env.HUB_WEBHOOK_REPLAY_MAX_KEYS, { fallback: 20_000, min: 64, max: 1_000_000 }),
      stale_window_ms: boundedInt(process.env.HUB_WEBHOOK_REPLAY_STALE_WINDOW_MS, { fallback: 20 * 60 * 1000, min: 10 * 60 * 1000, max: 14 * 24 * 60 * 60 * 1000 }),
    });
  const connectorIngressPolicy = connectorIngressPolicyFromEnv(process.env);
  const ingressScanMaxEvents = boundedInt(process.env.HUB_CONNECTOR_INGRESS_SCAN_MAX_EVENTS, {
    fallback: 2_000,
    min: 64,
    max: 100_000,
  });
  const ingressScanEntries = [];

  function recordIngressScan(entry) {
    const item = entry && typeof entry === 'object' ? entry : null;
    if (item) {
      ingressScanEntries.push({
        ingress_type: safeString(item.ingress_type),
        policy_checked: item.policy_checked !== false,
        allowed: !!item.allowed,
        blocked: item.blocked === true || item.allowed === false || !!safeString(item.deny_code),
        deny_code: safeString(item.deny_code),
        audit_logged: item.audit_logged !== false,
      });
      if (ingressScanEntries.length > ingressScanMaxEvents) {
        ingressScanEntries.splice(0, ingressScanEntries.length - ingressScanMaxEvents);
      }
    }
    return buildNonMessageIngressScanStats(ingressScanEntries);
  }

  function gateEvidenceFields(stats) {
    const snapshot = buildNonMessageIngressGateSnapshot({ stats });
    return {
      non_message_ingress_gate_schema_version: safeString(snapshot?.schema_version || ''),
      non_message_ingress_gate_measured_at_ms: Math.max(0, Number(snapshot?.measured_at_ms || 0)),
      non_message_ingress_gate_pass: snapshot?.pass === true,
      non_message_ingress_gate_incident_codes: Array.isArray(snapshot?.incident_codes)
        ? snapshot.incident_codes.map((code) => safeString(code)).filter(Boolean)
        : [],
      non_message_ingress_gate_thresholds: snapshot && typeof snapshot.thresholds === 'object'
        ? {
            non_message_ingress_policy_coverage_min: Number(snapshot.thresholds.non_message_ingress_policy_coverage_min || 0),
            blocked_event_miss_rate_max_exclusive: Number(snapshot.thresholds.blocked_event_miss_rate_max_exclusive || 0),
          }
        : {},
      non_message_ingress_gate_checks: Array.isArray(snapshot?.checks)
        ? snapshot.checks.map((check) => ({
            key: safeString(check?.key || ''),
            pass: check?.pass === true,
            comparator: safeString(check?.comparator || ''),
            expected: Number(check?.expected || 0),
            actual: Number(check?.actual || 0),
          }))
        : [],
      non_message_ingress_gate_metrics: snapshot && typeof snapshot.metrics === 'object'
        ? {
            ingress_total: Number(snapshot.metrics.ingress_total || 0),
            non_message_ingress_total: Number(snapshot.metrics.non_message_ingress_total || 0),
            non_message_ingress_policy_checked: Number(snapshot.metrics.non_message_ingress_policy_checked || 0),
            non_message_ingress_policy_coverage: Number(snapshot.metrics.non_message_ingress_policy_coverage || 0),
            blocked_event_total: Number(snapshot.metrics.blocked_event_total || 0),
            blocked_event_audited: Number(snapshot.metrics.blocked_event_audited || 0),
            blocked_event_miss_total: Number(snapshot.metrics.blocked_event_miss_total || 0),
            blocked_event_miss_rate: Number(snapshot.metrics.blocked_event_miss_rate || 0),
          }
        : {},
    };
  }

  function safeGuardSnapshot(guard, fallback) {
    try {
      if (guard && typeof guard.snapshot === 'function') return guard.snapshot();
    } catch {
      // ignore and fallback
    }
    return fallback;
  }

  function parseAuditRowsLimit(raw) {
    return boundedInt(raw, { fallback: 200, min: 1, max: 200 });
  }

  function listConnectorIngressAuditRows(filters = {}) {
    if (!db || typeof db.listAuditEvents !== 'function') return [];
    const f = filters && typeof filters === 'object' ? filters : {};
    const rows = db.listAuditEvents({
      since_ms: Math.max(0, Number(f.since_ms || 0)),
      until_ms: Math.max(0, Number(f.until_ms || 0)),
      device_id: safeString(f.device_id || ''),
      user_id: safeString(f.user_id || ''),
      project_id: safeString(f.project_id || ''),
      request_id: safeString(f.request_id || ''),
    });
    const limit = parseAuditRowsLimit(f.limit);
    const out = [];
    for (const row of Array.isArray(rows) ? rows : []) {
      const eventType = safeString(row?.event_type).toLowerCase();
      if (eventType !== 'connector.ingress.allowed' && eventType !== 'connector.ingress.denied') continue;
      out.push(row);
      if (out.length >= limit) break;
    }
    return out;
  }

  function appendIngressAudit({
    event_type,
    severity,
    ok,
    deny_code,
    error_message,
    ext,
  } = {}) {
    if (!db || typeof db.appendAudit !== 'function') return;
    const preauthMetrics = safeGuardSnapshot(internalPreauthGuard, {
      total: 0,
      rejected: 0,
      fail_closed: 0,
      preauth_reject_rate: 0,
      state_keys: 0,
      max_state_keys: 0,
      stale_window_ms: 0,
      window_ms: 0,
      max_per_window: 0,
    });
    const replayMetrics = safeGuardSnapshot(internalWebhookReplayGuard, {
      total: 0,
      blocked: 0,
      fail_closed: 0,
      webhook_replay_block_rate: 0,
      replay_keys: 0,
      max_keys: 0,
      ttl_ms: 0,
      stale_window_ms: 0,
    });
    const unauthorizedFloodMetrics = safeGuardSnapshot(internalUnauthorizedFloodBreaker, {
      checks: 0,
      dropped: 0,
      unauthorized: 0,
      penalties: 0,
      fail_closed: 0,
      sampled_drop_logs: 0,
      unauthorized_flood_drop_count: 0,
      state_keys: 0,
      max_state_keys: 0,
      window_ms: 0,
      penalty_ms: 0,
      stale_window_ms: 0,
      max_unauthorized_per_window: 0,
      audit_sample_every: 1,
    });
    const connectorRuntimeMetrics = safeGuardSnapshot(internalConnectorRuntimeOrchestrator, {
      targets: 0,
      signals: 0,
      denied: 0,
      fail_closed: 0,
      state_corrupt_incidents: 0,
      fallback_entries: 0,
      reconnect_attempts: 0,
      connector_reconnect_ms_p95: 0,
      reconnect_sample_count: 0,
      by_state: {
        idle: 0,
        connecting: 0,
        ready: 0,
        degraded_polling: 0,
        recovering: 0,
      },
    });
    const orderingMetrics = safeGuardSnapshot(internalConnectorTargetOrderingGuard, {
      targets: 0,
      in_flight_targets: 0,
      begin_total: 0,
      begin_rejected: 0,
      complete_total: 0,
      complete_rejected: 0,
      accepted: 0,
      lock_conflict_count: 0,
      out_of_order_reject_count: 0,
      duplicate_reject_count: 0,
      state_corrupt_incidents: 0,
      fail_closed: 0,
    });
    const receiptMetrics = safeGuardSnapshot(internalConnectorDeliveryReceiptCompensator, {
      entries: 0,
      targets: 0,
      prepare_total: 0,
      prepare_rejected: 0,
      commit_total: 0,
      commit_rejected: 0,
      undo_total: 0,
      undo_rejected: 0,
      timeout_undo_promoted: 0,
      compensation_runs: 0,
      compensation_rejected: 0,
      compensated_total: 0,
      compensation_failures: 0,
      overflow_denied: 0,
      state_corrupt_incidents: 0,
      fail_closed: 0,
      compensation_pending_count: 0,
      by_state: {
        prepared: 0,
        committed: 0,
        undo_pending: 0,
        compensated: 0,
      },
    });
    try {
      db.appendAudit({
        event_type: String(event_type || 'pairing.ingress'),
        created_at_ms: nowMs(),
        severity: String(severity || (ok ? 'info' : 'warn')),
        device_id: 'pairing-http',
        user_id: null,
        app_id: 'pairing-http',
        project_id: null,
        session_id: null,
        request_id: null,
        capability: 'events',
        model_id: null,
        ok: !!ok,
        error_code: deny_code ? String(deny_code) : null,
        error_message: deny_code ? String(error_message || deny_code) : null,
        ext_json: JSON.stringify({
          preauth_reject_rate: Number(preauthMetrics.preauth_reject_rate || 0),
          webhook_replay_block_rate: Number(replayMetrics.webhook_replay_block_rate || 0),
          preauth_total: Number(preauthMetrics.total || 0),
          preauth_rejected: Number(preauthMetrics.rejected || 0),
          preauth_state_keys: Number(preauthMetrics.state_keys || 0),
          webhook_replay_total: Number(replayMetrics.total || 0),
          webhook_replay_blocked: Number(replayMetrics.blocked || 0),
          webhook_replay_keys: Number(replayMetrics.replay_keys || 0),
          unauthorized_flood_drop_count: Number(unauthorizedFloodMetrics.unauthorized_flood_drop_count || 0),
          unauthorized_flood_checks: Number(unauthorizedFloodMetrics.checks || 0),
          unauthorized_flood_unauthorized: Number(unauthorizedFloodMetrics.unauthorized || 0),
          unauthorized_flood_penalties: Number(unauthorizedFloodMetrics.penalties || 0),
          connector_runtime_targets: Number(connectorRuntimeMetrics.targets || 0),
          connector_runtime_denied: Number(connectorRuntimeMetrics.denied || 0),
          connector_runtime_state_corrupt_incidents: Number(connectorRuntimeMetrics.state_corrupt_incidents || 0),
          connector_reconnect_ms_p95: Number(connectorRuntimeMetrics.connector_reconnect_ms_p95 || 0),
          connector_ordering_targets: Number(orderingMetrics.targets || 0),
          connector_target_lock_conflict_count: Number(orderingMetrics.lock_conflict_count || 0),
          connector_out_of_order_reject_count: Number(orderingMetrics.out_of_order_reject_count || 0),
          connector_duplicate_event_reject_count: Number(orderingMetrics.duplicate_reject_count || 0),
          connector_receipt_entries: Number(receiptMetrics.entries || 0),
          connector_receipt_prepare_total: Number(receiptMetrics.prepare_total || 0),
          connector_receipt_commit_total: Number(receiptMetrics.commit_total || 0),
          connector_receipt_undo_total: Number(receiptMetrics.undo_total || 0),
          connector_compensation_pending_count: Number(receiptMetrics.compensation_pending_count || 0),
          connector_compensated_total: Number(receiptMetrics.compensated_total || 0),
          connector_receipt_fail_closed: Number(receiptMetrics.fail_closed || 0),
          ...(ext && typeof ext === 'object' ? ext : {}),
        }),
      });
    } catch {
      // audit sink failures do not flip request outcome
    }
  }

  function callPreauthGuard(sourceKey) {
    try {
      const out = internalPreauthGuard.check({
        source_key: sourceKey,
        now_ms: nowMs(),
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'preauth_fail_closed',
        retry_after_ms: 60_000,
        source_key: safeString(sourceKey),
      };
    } catch {
      return {
        ok: false,
        deny_code: 'preauth_fail_closed',
        retry_after_ms: 60_000,
        source_key: safeString(sourceKey),
      };
    }
  }

  function callUnauthorizedFloodGuard(connectionKey) {
    try {
      const out = internalUnauthorizedFloodBreaker.check({
        connection_key: connectionKey,
        now_ms: nowMs(),
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'unauthorized_flood_fail_closed',
        retry_after_ms: 30_000,
        connection_key: safeString(connectionKey),
        audit_sampled: true,
        last_deny_code: '',
      };
    } catch {
      return {
        ok: false,
        deny_code: 'unauthorized_flood_fail_closed',
        retry_after_ms: 30_000,
        connection_key: safeString(connectionKey),
        audit_sampled: true,
        last_deny_code: '',
      };
    }
  }

  function noteUnauthorizedDeny(connectionKey, denyCode, statusCode) {
    const code = Math.max(0, Number(statusCode || 0));
    if (code !== 401 && code !== 403) return;
    try {
      internalUnauthorizedFloodBreaker.recordUnauthorized({
        connection_key: connectionKey,
        deny_code: denyCode,
        now_ms: nowMs(),
      });
    } catch {
      // ignore: request already denied; breaker failures are handled on check path.
    }
  }

  function callConnectorRuntimeSignal({
    connector,
    target_id,
    signal,
    error_code,
    now_ms,
  } = {}) {
    try {
      const out = internalConnectorRuntimeOrchestrator.applySignal({
        connector,
        target_id,
        signal,
        error_code,
        now_ms: Number(now_ms || 0) > 0 ? Number(now_ms) : nowMs(),
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'orchestrator_fail_closed',
        state: 'idle',
        retry_after_ms: 1_000,
        action: 'none',
      };
    } catch {
      return {
        ok: false,
        deny_code: 'orchestrator_fail_closed',
        state: 'idle',
        retry_after_ms: 1_000,
        action: 'none',
      };
    }
  }

  function callConnectorOrderingBegin({
    connector,
    target_id,
    event_id,
    event_sequence,
    now_ms,
  } = {}) {
    try {
      const out = internalConnectorTargetOrderingGuard.begin({
        connector,
        target_id,
        event_id,
        event_sequence,
        now_ms: Number(now_ms || 0) > 0 ? Number(now_ms) : nowMs(),
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'ordering_guard_error',
        retry_after_ms: 1_000,
      };
    } catch {
      return {
        ok: false,
        deny_code: 'ordering_guard_error',
        retry_after_ms: 1_000,
      };
    }
  }

  function callConnectorOrderingComplete({
    connector,
    target_id,
    lock_token,
    success,
    event_id,
    event_sequence,
    now_ms,
  } = {}) {
    try {
      const out = internalConnectorTargetOrderingGuard.complete({
        connector,
        target_id,
        lock_token,
        success: success === true,
        event_id,
        event_sequence,
        now_ms: Number(now_ms || 0) > 0 ? Number(now_ms) : nowMs(),
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'ordering_guard_error',
      };
    } catch {
      return {
        ok: false,
        deny_code: 'ordering_guard_error',
      };
    }
  }

  function callConnectorReceiptPrepare({
    connector,
    target_id,
    idempotency_key,
    event_id,
    event_sequence,
    now_ms,
  } = {}) {
    try {
      const out = internalConnectorDeliveryReceiptCompensator.prepare({
        connector,
        target_id,
        idempotency_key,
        event_id,
        event_sequence,
        now_ms: Number(now_ms || 0) > 0 ? Number(now_ms) : nowMs(),
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'receipt_guard_error',
      };
    } catch {
      return {
        ok: false,
        deny_code: 'receipt_guard_error',
      };
    }
  }

  function callConnectorReceiptCommit({
    connector,
    target_id,
    idempotency_key,
    provider_receipt,
    event_id,
    event_sequence,
    now_ms,
  } = {}) {
    try {
      const out = internalConnectorDeliveryReceiptCompensator.commit({
        connector,
        target_id,
        idempotency_key,
        provider_receipt,
        event_id,
        event_sequence,
        now_ms: Number(now_ms || 0) > 0 ? Number(now_ms) : nowMs(),
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'receipt_guard_error',
      };
    } catch {
      return {
        ok: false,
        deny_code: 'receipt_guard_error',
      };
    }
  }

  function callConnectorReceiptUndo({
    connector,
    target_id,
    idempotency_key,
    reason,
    compensate_after_ms,
    now_ms,
  } = {}) {
    try {
      const out = internalConnectorDeliveryReceiptCompensator.undo({
        connector,
        target_id,
        idempotency_key,
        reason,
        compensate_after_ms,
        now_ms: Number(now_ms || 0) > 0 ? Number(now_ms) : nowMs(),
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'receipt_guard_error',
      };
    } catch {
      return {
        ok: false,
        deny_code: 'receipt_guard_error',
      };
    }
  }

  function callConnectorReceiptCompensationTick({
    now_ms,
    max_jobs,
  } = {}) {
    try {
      const out = internalConnectorDeliveryReceiptCompensator.runCompensation({
        now_ms: Number(now_ms || 0) > 0 ? Number(now_ms) : nowMs(),
        max_jobs,
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'compensation_worker_error',
      };
    } catch {
      return {
        ok: false,
        deny_code: 'compensation_worker_error',
      };
    }
  }

  const server = http.createServer(async (req, res) => {
    const method = safeString(req?.method || 'GET').toUpperCase();
    const rawUrl = safeString(req?.url || '/');
    let urlObj;
    try {
      // Dummy base: required for URL parsing.
      urlObj = new URL(rawUrl, `http://${host}:${port}`);
    } catch {
      jsonResponse(res, 400, { ok: false, error: { code: 'bad_url', message: 'bad_url', retryable: false } });
      return;
    }

    const pathname = safeString(urlObj.pathname) || '/';
    const q = parseQuery(urlObj);
    const peerIp = peerIpFromReq(req);

    // Global allowlist for pairing port (defense-in-depth).
    if (allowedCidrs.length && !peerAllowedByRules(peerIp, allowedCidrs)) {
      jsonResponse(res, 403, {
        ok: false,
        error: {
          code: 'forbidden',
          message: 'source_ip_not_allowed',
          retryable: false,
          peer_ip: peerIp || '',
          allowed_cidrs: allowedCidrs,
          hint: 'Use the Hub LAN/VPN IP (not a public IP), or update HUB_PAIRING_ALLOWED_CIDRS on the Hub.',
        },
      });
      return;
    }

    // -------------------- Install assets (unauth) --------------------

    if (method === 'GET' && (pathname === '/install/axhubctl' || pathname === '/install/axhubctl.sh')) {
      const asset = loadAxhubctlAsset();
      if (!asset) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'axhubctl_not_found', retryable: false } });
        return;
      }
      res.writeHead(200, {
        'content-type': 'text/plain; charset=utf-8',
        'cache-control': 'no-store',
        'content-disposition': 'attachment; filename="axhubctl"',
        'x-content-sha256': asset.sha256,
      });
      res.end(asset.content);
      return;
    }

    if (method === 'GET' && pathname === '/install/axhubctl.sha256') {
      const asset = loadAxhubctlAsset();
      if (!asset) {
        textResponse(res, 404, 'not_found\n');
        return;
      }
      textResponse(res, 200, `${asset.sha256}  axhubctl\n`);
      return;
    }

    if (method === 'GET' && pathname === '/install/axhubctl.json') {
      const asset = loadAxhubctlAsset();
      if (!asset) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'axhubctl_not_found', retryable: false } });
        return;
      }
      const base = publicBaseFromReq(req, { hostFallback, portFallback: port, schemeFallback });
      const url = base ? `${base}/install/axhubctl` : '/install/axhubctl';
      jsonResponse(res, 200, { ok: true, name: 'axhubctl', sha256: asset.sha256, url });
      return;
    }

    if (method === 'GET' && pathname === '/install/axhub_client_kit.tgz') {
      const asset = loadAxhubClientKitAsset();
      if (!asset) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'axhub_client_kit_not_found', retryable: false } });
        return;
      }
      res.writeHead(200, {
        'content-type': 'application/gzip',
        'cache-control': 'no-store',
        'content-disposition': 'attachment; filename="axhub_client_kit.tgz"',
        'x-content-sha256': asset.sha256,
        ...(asset.size_bytes ? { 'content-length': String(asset.size_bytes) } : {}),
      });
      const rs = fs.createReadStream(asset.path);
      rs.on('error', () => {
        try {
          res.destroy();
        } catch {
          // ignore
        }
      });
      rs.pipe(res);
      return;
    }

    if (method === 'GET' && pathname === '/install/axhub_client_kit.tgz.sha256') {
      const asset = loadAxhubClientKitAsset();
      if (!asset) {
        textResponse(res, 404, 'not_found\n');
        return;
      }
      textResponse(res, 200, `${asset.sha256}  axhub_client_kit.tgz\n`);
      return;
    }

    if (method === 'GET' && pathname === '/install/axhub_client_kit.json') {
      const asset = loadAxhubClientKitAsset();
      if (!asset) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'axhub_client_kit_not_found', retryable: false } });
        return;
      }
      const base = publicBaseFromReq(req, { hostFallback, portFallback: port, schemeFallback });
      const url = base ? `${base}/install/axhub_client_kit.tgz` : '/install/axhub_client_kit.tgz';
      jsonResponse(res, 200, { ok: true, name: 'axhub_client_kit.tgz', sha256: asset.sha256, url, size_bytes: asset.size_bytes });
      return;
    }

    // Discovery metadata for one-click bootstrap (LAN first, then remote).
    if (method === 'GET' && pathname === '/pairing/discovery') {
      const tlsMode = tlsModeFromEnv(process.env);
      const tlsServerName = tlsMode === 'insecure' ? '' : tlsServerNameFromEnv(process.env);
      const payload = {
        ok: true,
        service: 'pairing',
        version: 'pairing.v1',
        now_ms: nowMs(),
        pairing_enabled: true,
        hub_host_hint: hostHintFromReq(req, { hostFallback, peerIp }),
        grpc_port: Number(grpcPort || 0) || 50051,
        pairing_port: Number(port || 0) || 50052,
        tls_mode: tlsMode,
        tls_server_name: tlsServerName,
      };
      const pairingWindowSec = positiveIntOrZero(process.env.HUB_PAIRING_WINDOW_SEC);
      if (pairingWindowSec > 0) payload.pairing_window_sec = pairingWindowSec;
      if (safeString(process.env.HUB_PAIRING_DISCOVERY_INCLUDE_RUNTIME) === '1') {
        payload.runtime_base_dir = resolveRuntimeBaseDir();
      }
      jsonResponse(res, 200, payload);
      return;
    }

    // Health.
    if (method === 'GET' && pathname === '/health') {
      jsonResponse(res, 200, { ok: true, service: 'pairing', now_ms: nowMs() });
      return;
    }

    // -------------------- Connector webhook ingress (pre-auth) --------------------

    if (method === 'POST' && pathname.startsWith('/webhook/connectors/')) {
      const tail = pathname.slice('/webhook/connectors/'.length);
      const parts = tail.split('/').filter(Boolean);
      const connector = safeString(parts[0]).toLowerCase();
      const target_id = safeString(parts[1]);
      if (!connector || !target_id) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }

      const sourceKey = sourceKeyFromReq(req, q, peerIp);
      const connectionKey = connectionKeyFromReq(req, peerIp, sourceKey);
      const floodGate = callUnauthorizedFloodGuard(connectionKey);
      if (!floodGate?.ok) {
        const denyCode = safeString(floodGate?.deny_code) || 'unauthorized_flood_fail_closed';
        const failClosed = denyCode === 'unauthorized_flood_fail_closed';
        if (floodGate.audit_sampled !== false) {
          appendIngressAudit({
            event_type: 'connector.webhook.rejected',
            severity: failClosed ? 'error' : 'warn',
            ok: false,
            deny_code: denyCode,
            error_message: denyCode,
            ext: {
              op: 'connector_webhook_ingress',
              connector,
              target_id,
              source_key: safeString(sourceKey),
              connection_key: safeString(floodGate.connection_key || connectionKey),
              last_unauthorized_deny_code: safeString(floodGate.last_deny_code || ''),
              peer_ip: peerIp || '',
              retry_after_ms: Math.max(0, Number(floodGate?.retry_after_ms || 0)),
            },
          });
        }
        if (failClosed) {
          jsonResponse(res, 503, { ok: false, error: { code: denyCode, message: denyCode, retryable: true } });
          return;
        }
        res.writeHead(429, {
          'content-type': 'application/json; charset=utf-8',
          'retry-after': String(rateLimitFromRetryMs(floodGate?.retry_after_ms)),
        });
        res.end(JSON.stringify({
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: true,
          },
        }));
        return;
      }
      const limit = callPreauthGuard(sourceKey);
      if (!limit?.ok) {
        const denyCode = safeString(limit?.deny_code) || 'preauth_fail_closed';
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: denyCode === 'preauth_fail_closed' ? 'error' : 'warn',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            peer_ip: peerIp || '',
            retry_after_ms: Math.max(0, Number(limit?.retry_after_ms || 0)),
          },
        });
        if (denyCode === 'preauth_fail_closed') {
          jsonResponse(res, 503, { ok: false, error: { code: denyCode, message: denyCode, retryable: true } });
          return;
        }
        res.writeHead(429, {
          'content-type': 'application/json; charset=utf-8',
          'retry-after': String(rateLimitFromRetryMs(limit?.retry_after_ms)),
        });
        res.end(JSON.stringify({
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: true,
          },
        }));
        return;
      }

      const body = await readBodyJson(req, { maxBytes: preauthBodyMaxBytes });
      if (!body.ok) {
        jsonResponse(res, 400, {
          ok: false,
          error: { code: body.error, message: body.error, retryable: false },
        });
        return;
      }
      const obj = body.json || {};
      const replay_key = safeString(req?.headers?.['x-replay-key'])
        || safeString(req?.headers?.['x-idempotency-key'])
        || safeString(obj.replay_key || obj.event_id || obj.idempotency_key);
      const signature = safeString(req?.headers?.['x-signature'])
        || safeString(req?.headers?.['x-hub-signature'])
        || safeString(obj.signature);

      let replayClaim;
      try {
        replayClaim = internalWebhookReplayGuard.claim({
          connector,
          target_id,
          replay_key,
          signature,
          now_ms: nowMs(),
        });
      } catch {
        replayClaim = { ok: false, deny_code: 'replay_guard_error', replay_key_hash: '' };
      }

      if (!replayClaim?.ok) {
        const denyCode = safeString(replayClaim?.deny_code) || 'replay_guard_error';
        const failClosed = denyCode === 'replay_guard_error';
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: failClosed ? 'error' : 'warn',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            replay_key_hash: safeString(replayClaim?.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            peer_ip: peerIp || '',
          },
        });
        if (failClosed) {
          jsonResponse(res, 503, { ok: false, error: { code: denyCode, message: denyCode, retryable: true } });
          return;
        }
        jsonResponse(res, 409, { ok: false, error: { code: denyCode, message: denyCode, retryable: false } });
        return;
      }

      const ingressRequestId = safeString(obj.request_id || replay_key || obj.event_id) || `connector_ingress_${uuid()}`;
      const webhookSourceId = safeString(obj.source_id || obj.webhook_source_id || `${connector}:${target_id}`);
      const authzClient = {
        device_id: 'pairing-http',
        app_id: `connector:${connector}`,
        project_id: target_id,
      };
      const statusForDenyCode = (denyCode) => {
        const dc = safeString(denyCode);
        if (dc === 'invalid_event' || dc === 'ingress_type_unsupported') return 400;
        if (dc === 'webhook_replay_detected') return 409;
        if (dc === 'audit_write_failed') return 503;
        return 403;
      };
      const statusForOrderingDenyCode = (denyCode) => {
        const dc = safeString(denyCode);
        if (dc === 'invalid_request') return 400;
        if (dc === 'target_locked') return 429;
        if (dc === 'out_of_order_event' || dc === 'duplicate_event') return 409;
        return 503;
      };
      const statusForReceiptDenyCode = (denyCode) => {
        const dc = safeString(denyCode);
        if (dc === 'invalid_request') return 400;
        if (dc === 'terminal_not_allowed' || dc === 'commit_timeout') return 409;
        return 503;
      };

      const transportAuthz = evaluateConnectorIngressWithAudit({
        db,
        event: {
          ingress_type: 'webhook',
          channel_scope: 'group',
          source_id: webhookSourceId,
          message_id: ingressRequestId,
          signature_valid: obj.signature_valid !== false,
          replay_detected: false,
        },
        policy: connectorIngressPolicy,
        client: authzClient,
        request_id: ingressRequestId,
      });
      if (transportAuthz.allowed && transportAuthz.audit_logged === false) {
        const denyCode = 'audit_write_failed';
        const transportAuditFailStats = recordIngressScan({
          ingress_type: 'webhook',
          policy_checked: true,
          allowed: false,
          blocked: true,
          deny_code: denyCode,
          audit_logged: true,
        });
        const transportAuditFailEvidence = gateEvidenceFields(transportAuditFailStats);
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: 'error',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            source_id: webhookSourceId,
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            ingress_type: 'webhook',
            policy_checked: transportAuthz.policy_checked !== false,
            blocked_event_miss_rate: Number(transportAuditFailStats.blocked_event_miss_rate || 0),
            non_message_ingress_policy_coverage: Number(transportAuditFailStats.non_message_ingress_policy_coverage || 0),
            ...transportAuditFailEvidence,
            peer_ip: peerIp || '',
          },
        });
        jsonResponse(res, statusForDenyCode(denyCode), {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: true,
          },
        });
        return;
      }
      if (!transportAuthz.allowed) {
        const transportStats = recordIngressScan(transportAuthz);
        const transportEvidence = gateEvidenceFields(transportStats);
        const denyCode = safeString(transportAuthz.deny_code || 'authz_denied') || 'authz_denied';
        const denyStatus = statusForDenyCode(denyCode);
        noteUnauthorizedDeny(connectionKey, denyCode, denyStatus);
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: 'warn',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            connection_key: safeString(connectionKey),
            source_id: webhookSourceId,
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            ingress_type: 'webhook',
            policy_checked: transportAuthz.policy_checked !== false,
            blocked_event_miss_rate: Number(transportStats.blocked_event_miss_rate || 0),
            non_message_ingress_policy_coverage: Number(transportStats.non_message_ingress_policy_coverage || 0),
            ...transportEvidence,
            peer_ip: peerIp || '',
          },
        });
        jsonResponse(res, denyStatus, {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: false,
          },
        });
        return;
      }

      const ingressEvent = connectorIngressEventFromBody({
        connector,
        target_id,
        body: obj,
        replay_key,
        fallbackIngressType: 'webhook',
      });
      const payloadAuthz = evaluateConnectorIngressWithAudit({
        db,
        event: {
          ...ingressEvent,
          source_id: safeString(ingressEvent.source_id || webhookSourceId),
          signature_valid: obj.signature_valid !== false,
          replay_detected: false,
        },
        policy: connectorIngressPolicy,
        client: {
          ...authzClient,
          user_id: safeString(ingressEvent.sender_id) || null,
        },
        request_id: ingressRequestId,
      });
      if (payloadAuthz.allowed && payloadAuthz.audit_logged === false) {
        const denyCode = 'audit_write_failed';
        const payloadAuditFailStats = recordIngressScan({
          ingress_type: safeString(ingressEvent.ingress_type || 'webhook'),
          policy_checked: true,
          allowed: false,
          blocked: true,
          deny_code: denyCode,
          audit_logged: true,
        });
        const payloadAuditFailEvidence = gateEvidenceFields(payloadAuditFailStats);
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: 'error',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            source_id: safeString(ingressEvent.source_id || webhookSourceId),
            ingress_type: safeString(ingressEvent.ingress_type || ''),
            channel_scope: safeString(ingressEvent.channel_scope || ''),
            sender_id: safeString(ingressEvent.sender_id || ''),
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            policy_checked: payloadAuthz.policy_checked !== false,
            blocked_event_miss_rate: Number(payloadAuditFailStats.blocked_event_miss_rate || 0),
            non_message_ingress_policy_coverage: Number(payloadAuditFailStats.non_message_ingress_policy_coverage || 0),
            ...payloadAuditFailEvidence,
            peer_ip: peerIp || '',
          },
        });
        jsonResponse(res, statusForDenyCode(denyCode), {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: true,
          },
        });
        return;
      }
      const payloadStats = recordIngressScan(payloadAuthz);
      if (!payloadAuthz.allowed) {
        const payloadEvidence = gateEvidenceFields(payloadStats);
        const denyCode = safeString(payloadAuthz.deny_code || 'authz_denied') || 'authz_denied';
        const denyStatus = statusForDenyCode(denyCode);
        noteUnauthorizedDeny(connectionKey, denyCode, denyStatus);
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: 'warn',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            connection_key: safeString(connectionKey),
            source_id: safeString(ingressEvent.source_id || webhookSourceId),
            ingress_type: safeString(ingressEvent.ingress_type || ''),
            channel_scope: safeString(ingressEvent.channel_scope || ''),
            sender_id: safeString(ingressEvent.sender_id || ''),
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            policy_checked: payloadAuthz.policy_checked !== false,
            blocked_event_miss_rate: Number(payloadStats.blocked_event_miss_rate || 0),
            non_message_ingress_policy_coverage: Number(payloadStats.non_message_ingress_policy_coverage || 0),
            ...payloadEvidence,
            peer_ip: peerIp || '',
          },
        });
        jsonResponse(res, denyStatus, {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: false,
          },
        });
        return;
      }
      const deliveryIdempotencyKey = safeString(
        req?.headers?.['x-idempotency-key']
        || obj.idempotency_key
        || ingressEvent.message_id
        || replay_key
      );
      const orderingBegin = callConnectorOrderingBegin({
        connector,
        target_id,
        event_id: safeString(ingressEvent.message_id || replay_key),
        event_sequence: Number(ingressEvent.event_sequence || 0),
      });
      if (!orderingBegin?.ok) {
        const denyCode = safeString(orderingBegin?.deny_code || 'ordering_guard_error');
        const denyStatus = statusForOrderingDenyCode(denyCode);
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: denyStatus >= 500 ? 'error' : 'warn',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            connection_key: safeString(connectionKey),
            source_id: safeString(ingressEvent.source_id || webhookSourceId),
            ingress_type: safeString(ingressEvent.ingress_type || ''),
            channel_scope: safeString(ingressEvent.channel_scope || ''),
            sender_id: safeString(ingressEvent.sender_id || ''),
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            event_id: safeString(ingressEvent.message_id || replay_key),
            event_sequence: Math.max(0, Number(ingressEvent.event_sequence || 0)),
            ordering_retry_after_ms: Math.max(0, Number(orderingBegin?.retry_after_ms || 0)),
            peer_ip: peerIp || '',
          },
        });
        if (denyStatus === 429) {
          res.writeHead(429, {
            'content-type': 'application/json; charset=utf-8',
            'retry-after': String(rateLimitFromRetryMs(orderingBegin?.retry_after_ms)),
          });
          res.end(JSON.stringify({
            ok: false,
            error: {
              code: denyCode,
              message: denyCode,
              retryable: true,
            },
          }));
          return;
        }
        jsonResponse(res, denyStatus, {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: denyStatus >= 500,
          },
        });
        return;
      }
      const receiptPrepare = callConnectorReceiptPrepare({
        connector,
        target_id,
        idempotency_key: deliveryIdempotencyKey,
        event_id: safeString(ingressEvent.message_id || replay_key),
        event_sequence: Number(ingressEvent.event_sequence || 0),
      });
      if (!receiptPrepare?.ok) {
        callConnectorOrderingComplete({
          connector,
          target_id,
          lock_token: safeString(orderingBegin.lock_token || ''),
          success: false,
          event_id: safeString(ingressEvent.message_id || replay_key),
          event_sequence: Number(ingressEvent.event_sequence || 0),
        });
        const denyCode = safeString(receiptPrepare?.deny_code || 'receipt_guard_error');
        const denyStatus = statusForReceiptDenyCode(denyCode);
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: denyStatus >= 500 ? 'error' : 'warn',
          ok: false,
          deny_code: 'connector_delivery_receipt_error',
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            connection_key: safeString(connectionKey),
            source_id: safeString(ingressEvent.source_id || webhookSourceId),
            ingress_type: safeString(ingressEvent.ingress_type || ''),
            channel_scope: safeString(ingressEvent.channel_scope || ''),
            sender_id: safeString(ingressEvent.sender_id || ''),
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            delivery_idempotency_key: deliveryIdempotencyKey,
            receipt_deny_code: denyCode,
            event_id: safeString(ingressEvent.message_id || replay_key),
            event_sequence: Math.max(0, Number(ingressEvent.event_sequence || 0)),
            peer_ip: peerIp || '',
          },
        });
        jsonResponse(res, denyStatus, {
          ok: false,
          error: {
            code: 'connector_delivery_receipt_error',
            message: 'connector_delivery_receipt_error',
            retryable: denyStatus >= 500,
          },
        });
        return;
      }
      const runtimeSignal = callConnectorRuntimeSignal({
        connector,
        target_id,
        signal: 'polling_ok',
      });
      if (!runtimeSignal?.ok) {
        const receiptUndo = callConnectorReceiptUndo({
          connector,
          target_id,
          idempotency_key: deliveryIdempotencyKey,
          reason: 'runtime_orchestrator_error',
          compensate_after_ms: 0,
        });
        callConnectorOrderingComplete({
          connector,
          target_id,
          lock_token: safeString(orderingBegin.lock_token || ''),
          success: false,
          event_id: safeString(ingressEvent.message_id || replay_key),
          event_sequence: Number(ingressEvent.event_sequence || 0),
        });
        const denyCode = 'connector_runtime_orchestrator_error';
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: 'error',
          ok: false,
          deny_code: denyCode,
          error_message: String(runtimeSignal?.deny_code || denyCode),
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            connection_key: safeString(connectionKey),
            source_id: safeString(ingressEvent.source_id || webhookSourceId),
            ingress_type: safeString(ingressEvent.ingress_type || ''),
            channel_scope: safeString(ingressEvent.channel_scope || ''),
            sender_id: safeString(ingressEvent.sender_id || ''),
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            delivery_idempotency_key: deliveryIdempotencyKey,
            receipt_undo_deny_code: safeString(receiptUndo?.deny_code || ''),
            receipt_delivery_state: safeString(receiptUndo?.delivery_state || receiptPrepare?.delivery_state || ''),
            orchestrator_deny_code: safeString(runtimeSignal?.deny_code || ''),
            orchestrator_state: safeString(runtimeSignal?.state || ''),
            orchestrator_retry_after_ms: Math.max(0, Number(runtimeSignal?.retry_after_ms || 0)),
            peer_ip: peerIp || '',
          },
        });
        jsonResponse(res, 503, {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: true,
          },
        });
        return;
      }
      const orderingComplete = callConnectorOrderingComplete({
        connector,
        target_id,
        lock_token: safeString(orderingBegin.lock_token || ''),
        success: true,
        event_id: safeString(ingressEvent.message_id || replay_key),
        event_sequence: Number(ingressEvent.event_sequence || 0),
      });
      if (!orderingComplete?.ok) {
        const receiptUndo = callConnectorReceiptUndo({
          connector,
          target_id,
          idempotency_key: deliveryIdempotencyKey,
          reason: 'ordering_guard_error',
          compensate_after_ms: 0,
        });
        const denyCode = 'connector_ordering_guard_error';
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: 'error',
          ok: false,
          deny_code: denyCode,
          error_message: String(orderingComplete?.deny_code || denyCode),
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            connection_key: safeString(connectionKey),
            source_id: safeString(ingressEvent.source_id || webhookSourceId),
            ingress_type: safeString(ingressEvent.ingress_type || ''),
            channel_scope: safeString(ingressEvent.channel_scope || ''),
            sender_id: safeString(ingressEvent.sender_id || ''),
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            delivery_idempotency_key: deliveryIdempotencyKey,
            receipt_undo_deny_code: safeString(receiptUndo?.deny_code || ''),
            receipt_delivery_state: safeString(receiptUndo?.delivery_state || receiptPrepare?.delivery_state || ''),
            ordering_deny_code: safeString(orderingComplete?.deny_code || ''),
            event_id: safeString(ingressEvent.message_id || replay_key),
            event_sequence: Math.max(0, Number(ingressEvent.event_sequence || 0)),
            peer_ip: peerIp || '',
          },
        });
        jsonResponse(res, 503, {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: true,
          },
        });
        return;
      }
      const receiptCommit = callConnectorReceiptCommit({
        connector,
        target_id,
        idempotency_key: deliveryIdempotencyKey,
        provider_receipt: safeString(obj.provider_receipt || obj.delivery_receipt || ''),
        event_id: safeString(ingressEvent.message_id || replay_key),
        event_sequence: Number(ingressEvent.event_sequence || 0),
      });
      if (!receiptCommit?.ok) {
        const receiptUndo = callConnectorReceiptUndo({
          connector,
          target_id,
          idempotency_key: deliveryIdempotencyKey,
          reason: 'receipt_commit_rejected',
          compensate_after_ms: 0,
        });
        const denyCode = safeString(receiptCommit?.deny_code || 'receipt_guard_error');
        const denyStatus = statusForReceiptDenyCode(denyCode);
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: denyStatus >= 500 ? 'error' : 'warn',
          ok: false,
          deny_code: 'connector_delivery_receipt_error',
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            connection_key: safeString(connectionKey),
            source_id: safeString(ingressEvent.source_id || webhookSourceId),
            ingress_type: safeString(ingressEvent.ingress_type || ''),
            channel_scope: safeString(ingressEvent.channel_scope || ''),
            sender_id: safeString(ingressEvent.sender_id || ''),
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            delivery_idempotency_key: deliveryIdempotencyKey,
            receipt_commit_deny_code: denyCode,
            receipt_undo_deny_code: safeString(receiptUndo?.deny_code || ''),
            receipt_delivery_state: safeString(receiptUndo?.delivery_state || ''),
            event_id: safeString(ingressEvent.message_id || replay_key),
            event_sequence: Math.max(0, Number(ingressEvent.event_sequence || 0)),
            peer_ip: peerIp || '',
          },
        });
        jsonResponse(res, denyStatus, {
          ok: false,
          error: {
            code: 'connector_delivery_receipt_error',
            message: 'connector_delivery_receipt_error',
            retryable: denyStatus >= 500,
          },
        });
        return;
      }
      const payloadEvidence = gateEvidenceFields(payloadStats);

      appendIngressAudit({
        event_type: 'connector.webhook.received',
        severity: 'info',
        ok: true,
        deny_code: '',
        error_message: '',
        ext: {
          op: 'connector_webhook_ingress',
          connector,
          target_id,
          source_key: safeString(limit?.source_key || sourceKey),
          replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
          signature_present: !!signature,
          source_id: safeString(ingressEvent.source_id || webhookSourceId),
          delivery_idempotency_key: deliveryIdempotencyKey,
          delivery_state: safeString(receiptCommit.delivery_state || ''),
          receipt_prepare_idempotent: receiptPrepare?.idempotent === true,
          receipt_commit_idempotent: receiptCommit?.idempotent === true,
          receipt_compensation_due_at_ms: Math.max(0, Number(receiptCommit.compensation_due_at_ms || receiptPrepare.compensation_due_at_ms || 0)),
          ingress_type: safeString(ingressEvent.ingress_type || ''),
          channel_scope: safeString(ingressEvent.channel_scope || ''),
          sender_id: safeString(ingressEvent.sender_id || ''),
          runtime_state: safeString(runtimeSignal.state || ''),
          runtime_action: safeString(runtimeSignal.action || ''),
          runtime_retry_after_ms: Math.max(0, Number(runtimeSignal.retry_after_ms || 0)),
          ordering_last_sequence: Math.max(0, Number(orderingComplete.last_sequence || 0)),
          ordering_seen_event_count: Math.max(0, Number(orderingComplete.seen_event_count || 0)),
          policy_checked: payloadAuthz.policy_checked !== false,
          blocked_event_miss_rate: Number(payloadStats.blocked_event_miss_rate || 0),
          non_message_ingress_policy_coverage: Number(payloadStats.non_message_ingress_policy_coverage || 0),
          ...payloadEvidence,
          body_size_hint_bytes: Buffer.byteLength(JSON.stringify(obj || {}), 'utf8'),
          peer_ip: peerIp || '',
        },
      });
      appendConnectorIngressReceiptSnapshot(resolveRuntimeBaseDir(), {
        receipt_id: `connector_ingress_${crypto.createHash('sha256')
          .update([
            safeString(target_id),
            safeString(connector),
            safeString(replayClaim.replay_key_hash || deliveryIdempotencyKey || ingressRequestId),
          ].join('|'))
          .digest('hex')
          .slice(0, 24)}`,
        request_id: ingressRequestId,
        project_id: safeString(authzClient.project_id || target_id),
        connector,
        target_id,
        ingress_type: safeString(ingressEvent.ingress_type || 'webhook'),
        channel_scope: safeString(ingressEvent.channel_scope || ''),
        source_id: safeString(ingressEvent.source_id || webhookSourceId),
        message_id: safeString(ingressEvent.message_id || replay_key || ingressRequestId),
        dedupe_key: safeString(replayClaim.replay_key_hash || deliveryIdempotencyKey || ingressRequestId),
        received_at_ms: nowMs(),
        event_sequence: Math.max(0, Number(ingressEvent.event_sequence || 0)),
        delivery_state: safeString(receiptCommit.delivery_state || ''),
        runtime_state: safeString(runtimeSignal.state || ''),
      });

      jsonResponse(res, 202, {
        ok: true,
        accepted: true,
        connector,
        target_id,
        ingress_type: safeString(ingressEvent.ingress_type || ''),
        replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
        delivery_state: safeString(receiptCommit.delivery_state || ''),
        runtime_state: safeString(runtimeSignal.state || ''),
        runtime_action: safeString(runtimeSignal.action || ''),
        ordering_last_sequence: Math.max(0, Number(orderingComplete.last_sequence || 0)),
        received_at_ms: nowMs(),
      });
      return;
    }

    // -------------------- Unauthenticated pairing --------------------

    if (method === 'POST' && pathname === '/pairing/requests') {
      const sourceKey = sourceKeyFromReq(req, q, peerIp);
      const limit = callPreauthGuard(sourceKey);
      if (!limit?.ok) {
        const denyCode = safeString(limit?.deny_code) || 'preauth_fail_closed';
        appendIngressAudit({
          event_type: 'pairing.preauth.rejected',
          severity: denyCode === 'preauth_fail_closed' ? 'error' : 'warn',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'pairing_request_ingress',
            source_key: safeString(limit?.source_key || sourceKey),
            peer_ip: peerIp || '',
            retry_after_ms: Math.max(0, Number(limit?.retry_after_ms || 0)),
          },
        });
        if (denyCode === 'preauth_fail_closed') {
          jsonResponse(res, 503, { ok: false, error: { code: denyCode, message: denyCode, retryable: true } });
          return;
        }
        res.writeHead(429, {
          'content-type': 'application/json; charset=utf-8',
          'retry-after': String(rateLimitFromRetryMs(limit?.retry_after_ms)),
        });
        res.end(JSON.stringify({
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: true,
          },
        }));
        return;
      }

      const body = await readBodyJson(req, { maxBytes: preauthBodyMaxBytes });
      if (!body.ok) {
        jsonResponse(res, 400, { ok: false, error: { code: body.error, message: body.error, retryable: false } });
        return;
      }
      const obj = body.json || {};

      const app_id = safeString(obj.app_id);
      if (!app_id) {
        jsonResponse(res, 400, { ok: false, error: { code: 'missing_app_id', message: 'missing_app_id', retryable: false } });
        return;
      }

      // Pairing secret (client-generated). This is used to prevent token leakage via request-id guessing.
      const pairing_secret = safeString(obj.pairing_secret);
      if (!pairing_secret || pairing_secret.length < 12) {
        jsonResponse(res, 400, { ok: false, error: { code: 'missing_pairing_secret', message: 'missing_pairing_secret', retryable: false } });
        return;
      }

      const created_at_ms = Number(obj.created_at_ms || 0) || nowMs();
      const request_id = obj.request_id ? safeString(obj.request_id) : '';
      const claimed_device_id = obj.device_id ? safeString(obj.device_id) : '';
      const user_id = obj.user_id ? safeString(obj.user_id) : '';
      const device_name = obj.device_name ? safeString(obj.device_name) : '';
      const device_info = obj.device_info && typeof obj.device_info === 'object' ? obj.device_info : null;
      const tls_csr_pem_raw = obj.tls_csr_pem ? safeString(obj.tls_csr_pem) : '';
      const tls_csr_b64 = obj.tls_csr_b64 ? safeString(obj.tls_csr_b64) : '';
      const tls_csr_pem = tls_csr_pem_raw || (tls_csr_b64 ? base64DecodeUtf8(tls_csr_b64) : '');
      const device_info2 = (() => {
        // Store TLS CSR (if present) in device_info_json so admin approval can issue a client cert.
        const cur = device_info && typeof device_info === 'object' ? { ...device_info } : {};
        if (tls_csr_pem && tls_csr_pem.includes('BEGIN CERTIFICATE REQUEST')) {
          const tls = cur.tls && typeof cur.tls === 'object' ? { ...cur.tls } : {};
          tls.csr_pem = tls_csr_pem;
          tls.csr_sha256 = sha256Hex(tls_csr_pem);
          cur.tls = tls;
        }
        return cur;
      })();
      const requested_scopes = Array.isArray(obj.requested_scopes) ? obj.requested_scopes.map((s) => safeString(s)).filter(Boolean) : [];

      let row;
      try {
        row = db.createPairingRequest({
          pairing_secret_hash: sha256Hex(pairing_secret),
          request_id: request_id || null,
          claimed_device_id: claimed_device_id || null,
          user_id: user_id || null,
          app_id,
          device_name: device_name || null,
          device_info_json: device_info2 && Object.keys(device_info2).length ? JSON.stringify(device_info2) : null,
          requested_scopes_json: requested_scopes.length ? JSON.stringify(requested_scopes) : null,
          peer_ip: peerIp || null,
          created_at_ms,
        });
      } catch (e) {
        jsonResponse(res, 500, { ok: false, error: { code: 'internal', message: 'internal', retryable: true } });
        return;
      }

      try {
        const runtimeBaseDir = resolveRuntimeBaseDir();
        pushHubNotification(runtimeBaseDir, {
          source: 'Hub',
          title: 'Pairing Request',
          body: `${device_name || claimed_device_id || 'Unknown device'} (${app_id}) requested access from ${peerIp || 'unknown ip'}`,
          dedupe_key: `pairing_request:${String(row?.pairing_request_id || '')}`,
          action_url: null,
          unread: true,
        });
      } catch {
        // ignore
      }

      jsonResponse(res, 201, {
        ok: true,
        pairing_request_id: String(row?.pairing_request_id || ''),
        status: String(row?.status || 'pending'),
        created_at_ms: Number(row?.created_at_ms || created_at_ms),
      });
      return;
    }

    if (method === 'GET' && pathname.startsWith('/pairing/requests/')) {
      const pairing_request_id = safeString(pathname.slice('/pairing/requests/'.length));
      if (!pairing_request_id) {
        jsonResponse(res, 400, { ok: false, error: { code: 'bad_request', message: 'bad_request', retryable: false } });
        return;
      }
      const secret = safeString(req?.headers?.['x-pairing-secret'] ?? q.secret);
      if (!secret) {
        jsonResponse(res, 401, { ok: false, error: { code: 'unauthenticated', message: 'missing_pairing_secret', retryable: false } });
        return;
      }
      const row = db.getPairingRequest(pairing_request_id);
      if (!row) {
        // Hide existence to reduce enumeration.
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }
      const expectedHash = safeString(row.pairing_secret_hash);
      if (!expectedHash || expectedHash !== sha256Hex(secret)) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }

      const status = safeString(row.status) || 'pending';
      const out = {
        ok: true,
        pairing_request_id,
        status,
        created_at_ms: Number(row.created_at_ms || 0) || 0,
        decided_at_ms: Number(row.decided_at_ms || 0) || 0,
        deny_reason: row.deny_reason ? String(row.deny_reason) : '',
        approved: null,
      };
      if (status === 'approved') {
        let caps = [];
        let cidrs = [];
        try {
          caps = JSON.parse(String(row.approved_capabilities_json || '[]'));
        } catch {
          caps = [];
        }
        try {
          cidrs = JSON.parse(String(row.approved_allowed_cidrs_json || '[]'));
        } catch {
          cidrs = [];
        }
        const boundUserId = safeString(row.user_id) || safeString(row.approved_device_id);
        const approvedTrustProfile = parseApprovedTrustProfile(row.approved_trust_profile_json);
        out.approved = {
          device_id: safeString(row.approved_device_id),
          user_id: boundUserId,
          client_token: safeString(row.approved_client_token),
          capabilities: Array.isArray(caps) ? caps.map((s) => safeString(s)).filter(Boolean) : [],
          allowed_cidrs: Array.isArray(cidrs) ? cidrs.map((s) => safeString(s)).filter(Boolean) : [],
          policy_mode: normalizedPolicyMode(row.policy_mode, approvedTrustProfile ? 'new_profile' : 'legacy_grant'),
          approved_trust_profile: approvedTrustProfile,
        };

        // TLS bootstrap material (optional):
        // - Provide the Hub CA cert so clients can verify the server cert.
        // - Provide the issued client cert (mTLS mode only).
        const tlsMode = tlsModeFromEnv(process.env);
        if (tlsMode !== 'insecure') {
          const runtimeBaseDir = resolveRuntimeBaseDir();
          // Ensure CA/server cert exist if TLS is enabled.
          try {
            ensureHubTlsMaterial(runtimeBaseDir, { env: process.env });
          } catch {
            // ignore; still allow pairing to complete (client may connect in insecure mode).
          }
          const caPem = readHubCaCertPem(runtimeBaseDir, { env: process.env });
          const serverName = tlsServerNameFromEnv(process.env);
          const did = safeString(row.approved_device_id);
          const clientPem = tlsMode === 'mtls' ? readIssuedClientCertPem(runtimeBaseDir, did, { env: process.env }) : '';

          out.tls = {
            mode: tlsMode,
            server_name: serverName,
            ca_cert_b64: caPem ? base64EncodeUtf8(caPem) : '',
            client_cert_b64: clientPem ? base64EncodeUtf8(clientPem) : '',
          };
        }

        // Convenience for terminals that are bootstrapping without a full client app.
        const hostHeader = safeString(req?.headers?.host);
        const hubHostGuess = hostHeader.includes(':') ? hostHeader.split(':')[0] : hostHeader;
        if (hubHostGuess) {
          out.connect = {
            hub_host: hubHostGuess,
            hub_port: Number(grpcPort || 0) || 50051,
          };
          const tlsMode = tlsModeFromEnv(process.env);
          const serverName = tlsMode !== 'insecure' ? tlsServerNameFromEnv(process.env) : '';
          const tlsEnv =
            tlsMode === 'insecure'
              ? ''
              : `HUB_GRPC_TLS_MODE=${shellQuoteSingle(tlsMode)}\nHUB_GRPC_TLS_SERVER_NAME=${shellQuoteSingle(serverName)}\nHUB_GRPC_TLS_CA_CERT_PATH=$HOME/.axhub/tls/ca.cert.pem\n` +
                (tlsMode === 'mtls'
                  ? `HUB_GRPC_TLS_CLIENT_CERT_PATH=$HOME/.axhub/tls/client.cert.pem\nHUB_GRPC_TLS_CLIENT_KEY_PATH=$HOME/.axhub/tls/client.key.pem\n`
                  : '');

          out.connect_env =
            `HUB_HOST=${shellQuoteSingle(hubHostGuess)}\n` +
            `HUB_PORT=${Number(grpcPort || 0) || 50051}\n` +
            `HUB_CLIENT_TOKEN=${shellQuoteSingle(row.approved_client_token)}\n` +
            `HUB_DEVICE_ID=${shellQuoteSingle(row.approved_device_id)}\n` +
            `HUB_USER_ID=${shellQuoteSingle(boundUserId)}\n` +
            tlsEnv;
        }

        // Provide install info so a brand new Terminal device can bootstrap `axhubctl`
        // without installing the full Hub app.
        const asset = loadAxhubctlAsset();
        if (asset) {
          const base = publicBaseFromReq(req, { hostFallback, portFallback: port, schemeFallback });
          const url = base ? `${base}/install/axhubctl` : '/install/axhubctl';
          const sha = asset.sha256;
          out.install = {
            axhubctl_url: url,
            axhubctl_sha256: sha,
            // Recommended: download -> verify -> chmod (avoid curl|sh).
            command_sh: [
              `AXHUBCTL_URL='${url}'`,
              `AXHUBCTL_SHA256='${sha}'`,
              'mkdir -p ~/.local/bin',
              'curl -fsSL "$AXHUBCTL_URL" -o ~/.local/bin/axhubctl',
              '(command -v shasum >/dev/null 2>&1 && echo "$AXHUBCTL_SHA256  ~/.local/bin/axhubctl" | shasum -a 256 -c -) || (command -v sha256sum >/dev/null 2>&1 && echo "$AXHUBCTL_SHA256  ~/.local/bin/axhubctl" | sha256sum -c -)',
              'chmod +x ~/.local/bin/axhubctl',
              'echo "Installed: ~/.local/bin/axhubctl (ensure ~/.local/bin is in PATH)"',
            ].join('\n'),
          };
        }
        try {
          if (!Number(row.token_claimed_at_ms || 0)) {
            db.markPairingTokenClaimed(pairing_request_id, nowMs());
          }
        } catch {
          // ignore
        }
      }
      jsonResponse(res, 200, out);
      return;
    }

    // -------------------- Admin pairing --------------------

    if (pathname === '/admin/pairing/connector-ingress/gate-snapshot' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      const source = safeString(q.source || 'auto').toLowerCase();
      if (source !== 'auto' && source !== 'audit' && source !== 'scan') {
        jsonResponse(res, 400, { ok: false, error: { code: 'invalid_request', message: 'invalid source (expected auto|audit|scan)', retryable: false } });
        return;
      }

      const scanStats = buildNonMessageIngressScanStats(ingressScanEntries);
      const scanSnapshot = buildNonMessageIngressGateSnapshot({ stats: scanStats });
      const auditRows = source === 'scan'
        ? []
        : listConnectorIngressAuditRows({
            since_ms: Math.max(0, Number(q.since_ms || 0)),
            until_ms: Math.max(0, Number(q.until_ms || 0)),
            device_id: safeString(q.device_id || ''),
            user_id: safeString(q.user_id || ''),
            project_id: safeString(q.project_id || ''),
            request_id: safeString(q.request_id || ''),
            limit: parseAuditRowsLimit(q.limit),
          });
      const auditSnapshot = buildNonMessageIngressGateSnapshotFromAuditRows(auditRows);
      const sourceUsed = (() => {
        if (source === 'audit' || source === 'scan') return source;
        return auditRows.length > 0 ? 'audit' : 'scan';
      })();
      const snapshot = sourceUsed === 'audit' ? auditSnapshot : scanSnapshot;
      jsonResponse(res, 200, {
        ok: true,
        source_used: sourceUsed,
        data_ready: sourceUsed === 'scan' ? ingressScanEntries.length > 0 : auditRows.length > 0,
        audit_row_count: auditRows.length,
        scan_entry_count: ingressScanEntries.length,
        snapshot,
        snapshot_scan: scanSnapshot,
        snapshot_audit: auditSnapshot,
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-runtime/snapshot' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const snapshot = safeGuardSnapshot(internalConnectorRuntimeOrchestrator, {
        targets: 0,
        signals: 0,
        denied: 0,
        fail_closed: 0,
        state_corrupt_incidents: 0,
        fallback_entries: 0,
        reconnect_attempts: 0,
        connector_reconnect_ms_p95: 0,
        reconnect_sample_count: 0,
        by_state: {
          idle: 0,
          connecting: 0,
          ready: 0,
          degraded_polling: 0,
          recovering: 0,
        },
      });
      jsonResponse(res, 200, {
        ok: true,
        snapshot,
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-runtime/target' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const connector = safeString(q.connector).toLowerCase();
      const target_id = safeString(q.target_id);
      if (!connector || !target_id) {
        jsonResponse(res, 400, { ok: false, error: { code: 'invalid_request', message: 'missing connector or target_id', retryable: false } });
        return;
      }
      let target = null;
      try {
        target = internalConnectorRuntimeOrchestrator.getTarget({
          connector,
          target_id,
        });
      } catch {
        target = null;
      }
      jsonResponse(res, 200, {
        ok: true,
        connector,
        target_id,
        target: target || null,
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-runtime/signal' && method === 'POST') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const body = await readBodyJson(req, { maxBytes: 64 * 1024 });
      if (!body.ok) {
        jsonResponse(res, 400, { ok: false, error: { code: body.error, message: body.error, retryable: false } });
        return;
      }
      const obj = body.json || {};
      const connector = safeString(obj.connector).toLowerCase();
      const target_id = safeString(obj.target_id);
      const signal = safeString(obj.signal);
      const error_code = safeString(obj.error_code || '');
      const nowOverride = Math.max(0, Number(obj.now_ms || 0));
      if (!connector || !target_id || !signal) {
        jsonResponse(res, 400, { ok: false, error: { code: 'invalid_request', message: 'missing connector/target_id/signal', retryable: false } });
        return;
      }

      const out = callConnectorRuntimeSignal({
        connector,
        target_id,
        signal,
        error_code,
        now_ms: nowOverride > 0 ? nowOverride : undefined,
      });
      if (!out?.ok) {
        const denyCode = safeString(out?.deny_code || 'state_corrupt');
        const statusCode = denyCode === 'invalid_request'
          ? 400
          : (denyCode === 'state_corrupt' ? 409 : 503);
        appendIngressAudit({
          event_type: 'connector.runtime.signal.rejected',
          severity: statusCode >= 500 ? 'error' : 'warn',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_runtime_signal',
            connector,
            target_id,
            signal,
            error_code,
            now_ms: nowOverride > 0 ? nowOverride : 0,
            state: safeString(out.state || ''),
            retry_after_ms: Math.max(0, Number(out.retry_after_ms || 0)),
          },
        });
        jsonResponse(res, statusCode, {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: statusCode >= 500,
          },
          state: safeString(out.state || ''),
          retry_after_ms: Math.max(0, Number(out.retry_after_ms || 0)),
        });
        return;
      }

      appendIngressAudit({
        event_type: 'connector.runtime.signal.accepted',
        severity: 'info',
        ok: true,
        deny_code: '',
        error_message: '',
        ext: {
          op: 'connector_runtime_signal',
          connector,
          target_id,
          signal,
          error_code,
          now_ms: nowOverride > 0 ? nowOverride : 0,
          state: safeString(out.state || ''),
          action: safeString(out.action || ''),
          retry_after_ms: Math.max(0, Number(out.retry_after_ms || 0)),
        },
      });
      jsonResponse(res, 200, {
        ok: true,
        connector,
        target_id,
        signal,
        state: safeString(out.state || ''),
        action: safeString(out.action || ''),
        retry_after_ms: Math.max(0, Number(out.retry_after_ms || 0)),
        next_reconnect_at_ms: Math.max(0, Number(out.next_reconnect_at_ms || 0)),
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-ordering/snapshot' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const snapshot = safeGuardSnapshot(internalConnectorTargetOrderingGuard, {
        targets: 0,
        in_flight_targets: 0,
        begin_total: 0,
        begin_rejected: 0,
        complete_total: 0,
        complete_rejected: 0,
        accepted: 0,
        lock_conflict_count: 0,
        out_of_order_reject_count: 0,
        duplicate_reject_count: 0,
        state_corrupt_incidents: 0,
        fail_closed: 0,
      });
      jsonResponse(res, 200, {
        ok: true,
        snapshot,
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-ordering/target' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const connector = safeString(q.connector).toLowerCase();
      const target_id = safeString(q.target_id);
      if (!connector || !target_id) {
        jsonResponse(res, 400, { ok: false, error: { code: 'invalid_request', message: 'missing connector or target_id', retryable: false } });
        return;
      }
      let target = null;
      try {
        target = internalConnectorTargetOrderingGuard.getTarget({
          connector,
          target_id,
        });
      } catch {
        target = null;
      }
      jsonResponse(res, 200, {
        ok: true,
        connector,
        target_id,
        target: target || null,
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-receipt/snapshot' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const snapshot = safeGuardSnapshot(internalConnectorDeliveryReceiptCompensator, {
        entries: 0,
        targets: 0,
        prepare_total: 0,
        prepare_rejected: 0,
        commit_total: 0,
        commit_rejected: 0,
        undo_total: 0,
        undo_rejected: 0,
        timeout_undo_promoted: 0,
        compensation_runs: 0,
        compensation_rejected: 0,
        compensated_total: 0,
        compensation_failures: 0,
        overflow_denied: 0,
        state_corrupt_incidents: 0,
        fail_closed: 0,
        compensation_pending_count: 0,
        by_state: {
          prepared: 0,
          committed: 0,
          undo_pending: 0,
          compensated: 0,
        },
      });
      jsonResponse(res, 200, {
        ok: true,
        snapshot,
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-receipt/target' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const connector = safeString(q.connector).toLowerCase();
      const target_id = safeString(q.target_id);
      if (!connector || !target_id) {
        jsonResponse(res, 400, { ok: false, error: { code: 'invalid_request', message: 'missing connector or target_id', retryable: false } });
        return;
      }
      let target = null;
      try {
        target = internalConnectorDeliveryReceiptCompensator.getTarget({
          connector,
          target_id,
          limit: Math.max(1, Number(q.limit || 50)),
        });
      } catch {
        target = null;
      }
      jsonResponse(res, 200, {
        ok: true,
        connector,
        target_id,
        target: target || null,
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-receipt/item' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const connector = safeString(q.connector).toLowerCase();
      const target_id = safeString(q.target_id);
      const idempotency_key = safeString(q.idempotency_key);
      if (!connector || !target_id || !idempotency_key) {
        jsonResponse(res, 400, { ok: false, error: { code: 'invalid_request', message: 'missing connector/target_id/idempotency_key', retryable: false } });
        return;
      }
      let receipt = null;
      try {
        receipt = internalConnectorDeliveryReceiptCompensator.getReceipt({
          connector,
          target_id,
          idempotency_key,
        });
      } catch {
        receipt = null;
      }
      jsonResponse(res, 200, {
        ok: true,
        connector,
        target_id,
        idempotency_key,
        receipt: receipt || null,
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-receipt/compensate' && method === 'POST') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const body = await readBodyJson(req, { maxBytes: 64 * 1024 });
      if (!body.ok) {
        jsonResponse(res, 400, { ok: false, error: { code: body.error, message: body.error, retryable: false } });
        return;
      }
      const obj = body.json || {};
      const nowOverride = Math.max(0, Number(obj.now_ms || 0));
      const maxJobs = Math.max(1, Number(obj.max_jobs || 0) || 0);
      const out = callConnectorReceiptCompensationTick({
        now_ms: nowOverride > 0 ? nowOverride : undefined,
        max_jobs: maxJobs > 0 ? maxJobs : undefined,
      });
      if (!out?.ok) {
        const denyCode = safeString(out?.deny_code || 'compensation_worker_error');
        appendIngressAudit({
          event_type: 'connector.receipt.compensation.rejected',
          severity: 'error',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_receipt_compensate',
            now_ms: nowOverride > 0 ? nowOverride : 0,
            max_jobs: maxJobs > 0 ? maxJobs : 0,
          },
        });
        jsonResponse(res, 503, {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: true,
          },
        });
        return;
      }
      appendIngressAudit({
        event_type: 'connector.receipt.compensation.accepted',
        severity: 'info',
        ok: true,
        deny_code: '',
        error_message: '',
        ext: {
          op: 'connector_receipt_compensate',
          now_ms: nowOverride > 0 ? nowOverride : 0,
          max_jobs: maxJobs > 0 ? maxJobs : 0,
          promoted_timeout_undo: Math.max(0, Number(out.promoted_timeout_undo || 0)),
          scanned_due: Math.max(0, Number(out.scanned_due || 0)),
          processed: Math.max(0, Number(out.processed || 0)),
          compensated: Math.max(0, Number(out.compensated || 0)),
          failed: Math.max(0, Number(out.failed || 0)),
          pending_compensation: Math.max(0, Number(out.pending_compensation || 0)),
        },
      });
      jsonResponse(res, 200, {
        ok: true,
        promoted_timeout_undo: Math.max(0, Number(out.promoted_timeout_undo || 0)),
        scanned_due: Math.max(0, Number(out.scanned_due || 0)),
        processed: Math.max(0, Number(out.processed || 0)),
        compensated: Math.max(0, Number(out.compensated || 0)),
        failed: Math.max(0, Number(out.failed || 0)),
        pending_compensation: Math.max(0, Number(out.pending_compensation || 0)),
      });
      return;
    }

    if (pathname === '/admin/pairing/requests' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const status = safeString(q.status) || 'pending';
      const lim = Number(q.limit || 200);
      let rows = [];
      try {
        rows = db.listPairingRequests({ status, limit: lim });
      } catch {
        rows = [];
      }

      const requests = rows.map((r) => {
        let info = null;
        let scopes = [];
        try {
          info = r.device_info_json ? JSON.parse(String(r.device_info_json)) : null;
        } catch {
          info = null;
        }
        try {
          scopes = r.requested_scopes_json ? JSON.parse(String(r.requested_scopes_json)) : [];
        } catch {
          scopes = [];
        }
        const approvedTrustProfile = parseApprovedTrustProfile(r.approved_trust_profile_json);
        return {
          pairing_request_id: safeString(r.pairing_request_id),
          request_id: safeString(r.request_id),
          status: safeString(r.status),
          app_id: safeString(r.app_id),
          claimed_device_id: safeString(r.claimed_device_id),
          user_id: safeString(r.user_id),
          device_name: safeString(r.device_name),
          peer_ip: safeString(r.peer_ip),
          created_at_ms: Number(r.created_at_ms || 0) || 0,
          decided_at_ms: Number(r.decided_at_ms || 0) || 0,
          deny_reason: safeString(r.deny_reason),
          device_info: info,
          requested_scopes: Array.isArray(scopes) ? scopes.map((s) => safeString(s)).filter(Boolean) : [],
          approved_device_id: safeString(r.approved_device_id),
          policy_mode: normalizedPolicyMode(r.policy_mode, approvedTrustProfile ? 'new_profile' : 'legacy_grant'),
          approved_trust_profile: approvedTrustProfile,
        };
      });

      jsonResponse(res, 200, { ok: true, requests });
      return;
    }

    if (pathname.startsWith('/admin/pairing/requests/') && method === 'POST') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      const tail = pathname.slice('/admin/pairing/requests/'.length);
      const parts = tail.split('/').filter(Boolean);
      const pairing_request_id = safeString(parts[0]);
      const action = safeString(parts[1]);
      if (!pairing_request_id || (action !== 'approve' && action !== 'deny')) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }

      const body = await readBodyJson(req, { maxBytes: 64 * 1024 });
      if (!body.ok) {
        jsonResponse(res, 400, { ok: false, error: { code: body.error, message: body.error, retryable: false } });
        return;
      }
      const obj = body.json || {};

      if (action === 'deny') {
        const deny_reason = obj.deny_reason ? safeString(obj.deny_reason) : '';
        let row;
        try {
          row = db.denyPairingRequest(pairing_request_id, { deny_reason: deny_reason || null, decided_at_ms: nowMs() });
        } catch {
          row = null;
        }
        if (!row) {
          jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
          return;
        }
        jsonResponse(res, 200, { ok: true, pairing_request_id, status: 'denied' });
        return;
      }

      // approve
      const rowBeforeApprove = db.getPairingRequest(pairing_request_id);
      if (!rowBeforeApprove) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }

      const raw_policy_mode = obj.policy_mode == null ? '' : safeString(obj.policy_mode).toLowerCase();
      if (raw_policy_mode && !POLICY_MODES.has(raw_policy_mode)) {
        jsonResponse(res, 400, { ok: false, error: { code: 'policy_mode_invalid', message: 'policy_mode_invalid', retryable: false } });
        return;
      }
      const requested_policy_mode = raw_policy_mode || 'new_profile';
      const raw_paid_model_selection_mode = obj.paid_model_selection_mode == null ? '' : safeString(obj.paid_model_selection_mode).toLowerCase();
      const requested_paid_model_selection_mode = raw_paid_model_selection_mode || 'off';
      const requested_allowed_paid_models = uniqueStrings(safeStringArray(obj.allowed_paid_models));
      const requested_default_web_fetch_enabled = obj.default_web_fetch_enabled == null ? true : obj.default_web_fetch_enabled === true;
      const requested_daily_token_limit = parseDailyTokenLimit(obj.daily_token_limit, DEFAULT_PAIRING_DAILY_TOKEN_LIMIT);
      if (requested_policy_mode === 'new_profile') {
        if (raw_paid_model_selection_mode && !PAID_MODEL_SELECTION_MODES.has(raw_paid_model_selection_mode)) {
          jsonResponse(res, 400, { ok: false, error: { code: 'paid_model_selection_mode_invalid', message: 'paid_model_selection_mode_invalid', retryable: false } });
          return;
        }
        if (requested_paid_model_selection_mode === 'custom_selected_models' && requested_allowed_paid_models.length === 0) {
          jsonResponse(res, 400, { ok: false, error: { code: 'custom_selected_models_empty', message: 'custom_selected_models_empty', retryable: false } });
          return;
        }
        if (requested_daily_token_limit == null) {
          jsonResponse(res, 400, { ok: false, error: { code: 'daily_token_limit_invalid', message: 'daily_token_limit_invalid', retryable: false } });
          return;
        }
      }

      const device_name = uniqueStrings([
        obj.device_name,
        rowBeforeApprove.device_name,
        rowBeforeApprove.claimed_device_id,
        rowBeforeApprove.app_id,
      ])[0] || '';
      if (!device_name) {
        jsonResponse(res, 400, { ok: false, error: { code: 'device_name_required', message: 'device_name_required', retryable: false } });
        return;
      }

      const capabilities = safeStringArray(obj.capabilities);
      const allowed_cidrs = safeStringArray(obj.allowed_cidrs);
      const reqUserId = safeString(rowBeforeApprove.user_id);
      const approved_device_id = generateDeviceId();
      const approved_client_token = generateClientToken();
      const requestedUserId = obj.user_id ? safeString(obj.user_id) : '';
      const boundUserId = requestedUserId || reqUserId || approved_device_id;

      const baseCapList = capabilities.length ? capabilities : defaultClientCaps();
      const approvedTrustProfile = requested_policy_mode === 'new_profile'
        ? buildApprovedTrustProfile({
            device_id: approved_device_id,
            device_name,
            capabilities: baseCapList,
            paid_model_selection_mode: requested_paid_model_selection_mode,
            allowed_paid_models: requested_allowed_paid_models,
            default_web_fetch_enabled: requested_default_web_fetch_enabled,
            daily_token_limit: requested_daily_token_limit,
            audit_ref: pairing_request_id,
          })
        : null;
      const capList = approvedTrustProfile
        ? uniqueStrings(approvedTrustProfile.capabilities)
        : uniqueStrings(baseCapList.length ? baseCapList : defaultClientCaps());
      const cidrList = allowed_cidrs.length ? uniqueStrings(allowed_cidrs) : defaultAllowedCidrs();

      const tlsMode = tlsModeFromEnv(process.env);
      let cert_sha256 = '';
      if (tlsMode === 'mtls') {
        const row0 = db.getPairingRequest(pairing_request_id);
        if (!row0) {
          jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
          return;
        }
        let info = null;
        try {
          info = row0?.device_info_json ? JSON.parse(String(row0.device_info_json)) : null;
        } catch {
          info = null;
        }
        const csrPem = safeString(info?.tls?.csr_pem || info?.tls_csr_pem || obj.tls_csr_pem || '');
        const csrB64 = safeString(obj.tls_csr_b64 || '');
        const csrPem2 = csrPem || (csrB64 ? base64DecodeUtf8(csrB64) : '');
        if (!csrPem2 || !csrPem2.includes('BEGIN CERTIFICATE REQUEST')) {
          jsonResponse(res, 400, { ok: false, error: { code: 'missing_tls_csr', message: 'missing_tls_csr', retryable: false } });
          return;
        }
        const runtimeBaseDir = resolveRuntimeBaseDir();
        try {
          ensureHubTlsMaterial(runtimeBaseDir, { env: process.env });
        } catch {
          jsonResponse(res, 500, { ok: false, error: { code: 'tls_init_failed', message: 'tls_init_failed', retryable: true } });
          return;
        }
        try {
          const signed = signClientCertFromCsr(runtimeBaseDir, { deviceId: approved_device_id, csrPem: csrPem2, env: process.env });
          cert_sha256 = safeString(signed?.cert_sha256).toLowerCase();
        } catch {
          jsonResponse(res, 500, { ok: false, error: { code: 'tls_sign_failed', message: 'tls_sign_failed', retryable: true } });
          return;
        }
      }

      const runtimeBaseDir = resolveRuntimeBaseDir();
      const snap0 = readClientsSnapshot(runtimeBaseDir);
      const entry = {
        device_id: approved_device_id,
        user_id: boundUserId || approved_device_id,
        name: device_name,
        token: approved_client_token,
        enabled: true,
        created_at_ms: nowMs(),
        capabilities: capList,
        allowed_cidrs: cidrList,
        policy_mode: requested_policy_mode,
        ...(approvedTrustProfile ? { approved_trust_profile: approvedTrustProfile } : {}),
        ...(cert_sha256 ? { cert_sha256 } : {}),
      };
      const snap1 = upsertClientInSnapshot(snap0, entry);
      if (!writeClientsSnapshot(runtimeBaseDir, snap1)) {
        jsonResponse(res, 500, { ok: false, error: { code: 'write_failed', message: 'write_failed', retryable: true } });
        return;
      }

      let row;
      try {
        row = db.approvePairingRequest(pairing_request_id, {
          decided_at_ms: nowMs(),
          user_id: boundUserId,
          approved_device_id,
          approved_client_token,
          device_name,
          approved_capabilities_json: JSON.stringify(capList),
          approved_allowed_cidrs_json: JSON.stringify(cidrList),
          policy_mode: requested_policy_mode,
          approved_trust_profile_json: approvedTrustProfile ? JSON.stringify(approvedTrustProfile) : null,
        });
      } catch {
        row = null;
      }
      if (!row) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }

      jsonResponse(res, 200, {
        ok: true,
        pairing_request_id,
        status: 'approved',
        device_id: approved_device_id,
        client_token: approved_client_token,
        policy_mode: requested_policy_mode,
        approved_trust_profile: approvedTrustProfile,
      });
      return;
    }

    jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
  });

  server.on('clientError', (_err, socket) => {
    try {
      socket.end('HTTP/1.1 400 Bad Request\r\n\r\n');
    } catch {
      // ignore
    }
  });

  server.on('error', (err) => {
    // Never crash the main gRPC server because pairing port is unavailable.
    // eslint-disable-next-line no-console
    console.log(`[hub_pairing] listen failed on ${host}:${port}: ${String(err?.message || err)}`);
  });

  server.listen(port, host);
  // eslint-disable-next-line no-console
  console.log(`[hub_pairing] listening on ${host}:${port} allowed=${allowedCidrs.join(',') || '(any)'}`);

  return () => {
    try {
      server.close();
    } catch {
      // ignore
    }
  };
}
