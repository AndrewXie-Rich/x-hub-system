import { resolveRuntimeBaseDir } from './mlx_runtime_ipc.js';
import { loadClients, findClientByToken } from './clients.js';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { tlsModeFromEnv } from './tls_support.js';

function bearerTokenFromMetadata(call) {
  const md = call?.metadata;
  if (!md) return '';
  const vals = md.get('authorization') || [];
  const raw = (vals[0] || '').toString();
  const s = raw.trim();
  if (!s) return '';
  const lower = s.toLowerCase();
  if (lower.startsWith('bearer ')) return s.slice('bearer '.length).trim();
  return s;
}

function peerIpFromCall(call) {
  try {
    const raw = typeof call?.getPeer === 'function' ? call.getPeer() : '';
    let s = String(raw || '').trim();
    if (!s) return '';
    if (s.startsWith('ipv4:')) s = s.slice('ipv4:'.length);
    else if (s.startsWith('ipv6:')) s = s.slice('ipv6:'.length);

    // Common shapes:
    // - "127.0.0.1:12345"
    // - "[::1]:12345"
    // - "::1:12345" (unbracketed)
    if (s.startsWith('[')) {
      const end = s.indexOf(']');
      if (end > 1) return s.slice(1, end);
    }
    const last = s.lastIndexOf(':');
    if (last > 0) return s.slice(0, last);
    return s;
  } catch {
    return '';
  }
}

function ipv4ToInt(ip) {
  const s = String(ip || '').trim();
  const parts = s.split('.');
  if (parts.length !== 4) return null;
  let out = 0;
  for (const p of parts) {
    if (!/^\d+$/.test(p)) return null;
    const n = Number.parseInt(p, 10);
    if (n < 0 || n > 255) return null;
    out = (out << 8) | n;
  }
  // Force unsigned.
  return out >>> 0;
}

function isPrivateIPv4(ip) {
  const n = ipv4ToInt(ip);
  if (n == null) return false;
  const u = n >>> 0;
  // 10.0.0.0/8
  if (((u & 0xff000000) >>> 0) === 0x0a000000) return true;
  // 172.16.0.0/12
  if (((u & 0xfff00000) >>> 0) === 0xac100000) return true;
  // 192.168.0.0/16
  if (((u & 0xffff0000) >>> 0) === 0xc0a80000) return true;
  // 100.64.0.0/10 (RFC 6598) - commonly used by Tailscale/Headscale tailnet IPs.
  // While not RFC1918, it is not globally routable on the public Internet.
  if (((u & 0xffc00000) >>> 0) === 0x64400000) return true;
  return false;
}

function isLoopbackIp(ip) {
  const s = String(ip || '').trim();
  if (!s) return false;
  if (s === '::1') return true;
  const n = ipv4ToInt(s);
  if (n == null) return false;
  // 127.0.0.0/8
  return (((n >>> 0) & 0xff000000) >>> 0) === 0x7f000000;
}

function parseAllowedCidrsEnv(v) {
  const s = String(v || '').trim();
  if (!s) return [];
  return s
    .split(',')
    .map((x) => String(x || '').trim())
    .filter(Boolean);
}

function ipv4InCidr(ip, cidrText) {
  const cidr = String(cidrText || '').trim();
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
  const ip = String(peerIp || '').trim();
  const rules = Array.isArray(allowedRules) ? allowedRules : [];
  if (!rules.length) return true;
  if (!ip) return false;

  for (const raw of rules) {
    const r = String(raw || '').trim();
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
    // Exact IP match (IPv4 or IPv6 literal).
    if (r === ip) return true;
    // CIDR (IPv4 only in MVP).
    if (r.includes('/')) {
      if (ipv4InCidr(ip, r)) return true;
      continue;
    }
    // Treat bare IPv4 as /32.
    if (ipv4InCidr(ip, `${r}/32`)) return true;
  }
  return false;
}

function peerCertSha256FromCall(call) {
  try {
    const ctx = typeof call?.getAuthContext === 'function' ? call.getAuthContext() : null;
    const cert = ctx?.sslPeerCertificate;
    const raw = cert?.raw;
    if (!raw || !Buffer.isBuffer(raw) || raw.length === 0) return '';
    return crypto.createHash('sha256').update(raw).digest('hex');
  } catch {
    return '';
  }
}

function safeString(v) {
  return String(v ?? '').trim();
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
    fs.writeFileSync(tmp, JSON.stringify(obj, null, 2) + '\n', { encoding: 'utf8' });
    fs.renameSync(tmp, outPath);
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

function deniedAttemptsPath(runtimeBaseDir) {
  const base = safeString(runtimeBaseDir);
  if (!base) return '';
  return path.join(base, 'grpc_denied_attempts.json');
}

function loadDeniedAttempts(runtimeBaseDir) {
  const fp = deniedAttemptsPath(runtimeBaseDir);
  const obj = readJsonSafe(fp);
  if (!obj || typeof obj !== 'object') {
    return { schema_version: 'grpc_denied_attempts.v1', updated_at_ms: 0, attempts: [] };
  }
  const attempts = Array.isArray(obj.attempts) ? obj.attempts : [];
  return {
    schema_version: safeString(obj.schema_version) || 'grpc_denied_attempts.v1',
    updated_at_ms: Number(obj.updated_at_ms || 0) || 0,
    attempts: Array.isArray(attempts) ? attempts : [],
  };
}

function recordDeniedAttemptBestEffort(fields) {
  // Export a small snapshot for the Hub UI so operators can quickly fix allowlist issues
  // (e.g. add the peer IP/VPN subnet into Allowed CIDRs for a paired device).
  try {
    const base = resolveRuntimeBaseDir();
    if (!base) return;

    const now = Date.now();
    const snap = loadDeniedAttempts(base);
    const maxAttempts = 50;

    const peer_ip = safeString(fields?.peer_ip);
    const device_id = safeString(fields?.device_id);
    const client_name = safeString(fields?.client_name);
    const reason = safeString(fields?.reason);
    const message = safeString(fields?.message);
    const tls_mode = safeString(fields?.tls_mode);
    const expected_allowed_cidrs = Array.isArray(fields?.expected_allowed_cidrs)
      ? fields.expected_allowed_cidrs.map((s) => safeString(s)).filter(Boolean)
      : [];

    const key = `${device_id}|${peer_ip}|${reason}`.toLowerCase();
    if (!key.replace(/\|/g, '').trim()) return;

    let attempts = Array.isArray(snap.attempts) ? snap.attempts : [];
    let found = false;
    attempts = attempts.map((a) => {
      const aPeer = safeString(a?.peer_ip);
      const aDid = safeString(a?.device_id);
      const aReason = safeString(a?.reason);
      const aKey = `${aDid}|${aPeer}|${aReason}`.toLowerCase();
      if (aKey !== key) return a;
      found = true;
      const prevCount = Number(a?.count || 0) || 0;
      return {
        ...(a && typeof a === 'object' ? a : {}),
        device_id,
        client_name,
        peer_ip,
        reason,
        message,
        tls_mode,
        expected_allowed_cidrs,
        first_seen_at_ms: Number(a?.first_seen_at_ms || 0) || now,
        last_seen_at_ms: now,
        count: prevCount + 1,
      };
    });

    if (!found) {
      attempts.push({
        device_id,
        client_name,
        peer_ip,
        reason,
        message,
        tls_mode,
        expected_allowed_cidrs,
        first_seen_at_ms: now,
        last_seen_at_ms: now,
        count: 1,
      });
    }

    attempts.sort((a, b) => {
      const am = Number(a?.last_seen_at_ms || 0) || 0;
      const bm = Number(b?.last_seen_at_ms || 0) || 0;
      return bm - am;
    });
    if (attempts.length > maxAttempts) attempts = attempts.slice(0, maxAttempts);

    const out = {
      schema_version: 'grpc_denied_attempts.v1',
      updated_at_ms: now,
      attempts,
    };
    writeJsonAtomic(base, 'grpc_denied_attempts.json', out);
  } catch {
    // ignore
  }
}

export function requireClientAuth(call) {
  const tok = bearerTokenFromMetadata(call);
  const peerIp = peerIpFromCall(call);
  const peerCertSha256 = peerCertSha256FromCall(call);
  const tlsMode = tlsModeFromEnv(process.env);

  const deny = (reason, message, extra = {}) => {
    recordDeniedAttemptBestEffort({
      reason,
      message,
      peer_ip: peerIp,
      tls_mode: tlsMode,
      device_id: extra?.device_id || '',
      client_name: extra?.client_name || '',
      expected_allowed_cidrs: extra?.expected_allowed_cidrs || [],
    });
    return {
      ok: false,
      code: 'unauthenticated',
      reason,
      message,
      peer_ip: peerIp,
      peer_cert_sha256: peerCertSha256,
    };
  };

  // If mTLS is enabled, a peer certificate must be present.
  // Note: grpc-js exposes it via call.getAuthContext().sslPeerCertificate.
  if (tlsMode === 'mtls' && !peerCertSha256) {
    return deny('missing_client_cert', 'Missing/invalid client certificate');
  }

  // Optional global gate (defense-in-depth): restrict all clients to specific CIDRs.
  // Useful when running a LAN-only server that should never accept connections from non-local addresses.
  const globalAllowed = parseAllowedCidrsEnv(process.env.HUB_ALLOWED_CIDRS || '');
  if (globalAllowed.length && !peerAllowedByRules(peerIp, globalAllowed)) {
    return deny('source_ip_not_allowed', 'Client source IP is not allowed', { expected_allowed_cidrs: globalAllowed });
  }

  // Preferred (v1): per-device client allowlist loaded from runtime base dir.
  // This makes quotas/policies meaningful because device_id is no longer user-controlled.
  try {
    const base = resolveRuntimeBaseDir();
    const clients = loadClients(base);
    if (clients.length > 0) {
      const c = findClientByToken(base, tok);
      if (c) {
        const device_id = String(c.device_id || '').trim();
        // Backward compatible default: if user_id is not configured, treat the device_id
        // as the user identity (single-device == single-user).
        const user_id = String(c.user_id || '').trim() || device_id;
        const client_name = String(c.name || '').trim();

        // Optional per-device source IP bind.
        if (Array.isArray(c.allowed_cidrs) && c.allowed_cidrs.length > 0) {
          if (!peerAllowedByRules(peerIp, c.allowed_cidrs)) {
            return deny('source_ip_not_allowed', 'Client source IP is not allowed', {
              device_id,
              client_name,
              expected_allowed_cidrs: c.allowed_cidrs,
            });
          }
        }

        // Optional mTLS certificate pin (defense-in-depth): bind the token to a specific client cert.
        const expectedCertSha = String(c.cert_sha256 || '').trim().toLowerCase();
        const requirePin = String(process.env.HUB_GRPC_MTLS_REQUIRE_CERT_PIN || '1').trim() !== '0';
        if (tlsMode === 'mtls') {
          if (requirePin && !expectedCertSha) {
            return deny('client_cert_pin_missing', 'Client cert pin is not configured for this token', { device_id, client_name });
          }
          if (expectedCertSha && expectedCertSha !== String(peerCertSha256 || '').trim().toLowerCase()) {
            return deny('client_cert_pin_mismatch', 'Client certificate does not match pinned certificate', { device_id, client_name });
          }
        }

        return {
          ok: true,
          device_id,
          user_id,
          client_name,
          capabilities: Array.isArray(c.capabilities) ? c.capabilities : [],
          peer_ip: peerIp,
          peer_cert_sha256: peerCertSha256,
        };
      }
      return deny('invalid_token', 'Missing/invalid client token');
    }
    // No clients configured -> fall back to legacy env auth.
  } catch {
    // ignore; fall through
  }

  // Legacy: single static token via env.
  const expected = (process.env.HUB_CLIENT_TOKEN || '').trim();
  if (!expected) {
    // In mTLS mode we still require an app-layer token boundary, otherwise *any* client
    // with a cert signed by the Hub CA could connect.
    if (tlsMode === 'mtls') {
      return deny('no_tokens_configured', 'No client tokens configured (set HUB_CLIENT_TOKEN or hub_grpc_clients.json)');
    }
    return { ok: true, device_id: '', client_name: '' };
  }
  if (!tok || tok !== expected) {
    return deny('invalid_token', 'Missing/invalid client token');
  }
  return { ok: true, device_id: '', client_name: '', capabilities: [], peer_ip: peerIp, peer_cert_sha256: peerCertSha256 };
}

export function requireAdminAuth(call) {
  const expected = (process.env.HUB_ADMIN_TOKEN || '').trim();
  if (!expected) return { ok: false, code: 'permission_denied', message: 'Admin token is not configured on this Hub' };
  const tok = bearerTokenFromMetadata(call);
  if (tok !== expected) {
    return { ok: false, code: 'permission_denied', message: 'Missing/invalid admin token' };
  }

  // Default: admin RPCs are local-only (Hub UI / local scripts). This reduces the blast radius
  // if the gRPC port is accidentally exposed beyond the intended transport (LAN/VPN/tunnel).
  const peerIp = peerIpFromCall(call);
  const allowRemote = String(process.env.HUB_ADMIN_ALLOW_REMOTE || '').trim() === '1';
  const adminAllowed = parseAllowedCidrsEnv(process.env.HUB_ADMIN_ALLOWED_CIDRS || '');
  if (!allowRemote) {
    // Allow explicit CIDR allowlist as an alternative to "loopback only".
    if (adminAllowed.length) {
      if (!peerAllowedByRules(peerIp, adminAllowed)) {
        return { ok: false, code: 'permission_denied', message: 'Admin source IP is not allowed' };
      }
    } else if (!isLoopbackIp(peerIp)) {
      return { ok: false, code: 'permission_denied', message: 'Admin RPCs are local-only (set HUB_ADMIN_ALLOW_REMOTE=1 to override)' };
    }
  }

  return { ok: true };
}
