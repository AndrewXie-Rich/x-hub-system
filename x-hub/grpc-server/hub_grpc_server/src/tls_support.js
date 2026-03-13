import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';

import grpc from '@grpc/grpc-js';

import { resolveRuntimeBaseDir } from './local_runtime_ipc.js';

function safeString(v) {
  return String(v ?? '').trim();
}

function safeLower(v) {
  return safeString(v).toLowerCase();
}

export function tlsModeFromEnv(env = process.env) {
  const raw = safeLower(env.HUB_GRPC_TLS_MODE || env.HUB_TLS_MODE || '');
  if (!raw) return 'insecure';
  if (raw === '0' || raw === 'false' || raw === 'off' || raw === 'disabled') return 'insecure';
  if (raw === 'insecure' || raw === 'plaintext') return 'insecure';
  if (raw === 'tls' || raw === 'ssl') return 'tls';
  if (raw === 'mtls' || raw === 'm_tls' || raw === 'mutual_tls') return 'mtls';
  return 'insecure';
}

export function tlsServerNameFromEnv(env = process.env) {
  // This name is used for the server certificate CN/SAN and as the default
  // gRPC authority override for clients that connect by IP.
  return safeString(env.HUB_GRPC_TLS_SERVER_NAME || env.HUB_TLS_SERVER_NAME || 'axhub') || 'axhub';
}

export function tlsBaseDir(runtimeBaseDir, env = process.env) {
  const explicit = safeString(env.HUB_GRPC_TLS_DIR || env.HUB_TLS_DIR || '');
  if (explicit) return explicit;
  const base = safeString(runtimeBaseDir);
  if (!base) return '';
  return path.join(base, 'hub_grpc_tls');
}

export function tlsPaths(runtimeBaseDir, env = process.env) {
  const dir = tlsBaseDir(runtimeBaseDir, env);
  return {
    dir,
    caKeyPath: path.join(dir, 'ca.key.pem'),
    caCertPath: path.join(dir, 'ca.cert.pem'),
    caSerialPath: path.join(dir, 'ca.cert.srl'),
    serverKeyPath: path.join(dir, 'server.key.pem'),
    serverCertPath: path.join(dir, 'server.cert.pem'),
    serverCsrPath: path.join(dir, 'server.csr.pem'),
    serverExtPath: path.join(dir, 'server.ext'),
    clientsDir: path.join(dir, 'clients'),
  };
}

function writeFileAtomic(outPath, data, mode) {
  const fp = safeString(outPath);
  if (!fp) throw new Error('writeFileAtomic: missing path');
  const dir = path.dirname(fp);
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  const tmp = path.join(dir, `.${path.basename(fp)}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`);
  fs.writeFileSync(tmp, data);
  try {
    if (mode != null) fs.chmodSync(tmp, mode);
  } catch {
    // ignore
  }
  fs.renameSync(tmp, fp);
  try {
    if (mode != null) fs.chmodSync(fp, mode);
  } catch {
    // ignore
  }
}

function readFileBuf(fp) {
  return fs.readFileSync(String(fp || ''));
}

function readFileText(fp) {
  try {
    return fs.readFileSync(String(fp || ''), 'utf8');
  } catch {
    return '';
  }
}

function fileExists(fp) {
  try {
    return fs.existsSync(String(fp || ''));
  } catch {
    return false;
  }
}

function safeUnlink(fp) {
  try {
    fs.unlinkSync(String(fp || ''));
  } catch {
    // ignore
  }
}

function ensureValidSerialFile(fp) {
  const raw = readFileText(fp).trim();
  if (!raw) {
    safeUnlink(fp);
    return;
  }
  // OpenSSL expects a hex serial number (commonly uppercase, but case-insensitive).
  if (!/^[0-9a-fA-F]+$/.test(raw)) {
    safeUnlink(fp);
  }
}

function isCertPemValid(fp) {
  const s = readFileText(fp).trim();
  if (!s) return false;
  return s.includes('-----BEGIN CERTIFICATE-----') && s.includes('-----END CERTIFICATE-----');
}

function isPrivateKeyPemValid(fp) {
  const s = readFileText(fp).trim();
  if (!s) return false;
  return s.includes('-----BEGIN PRIVATE KEY-----') || s.includes('-----BEGIN EC PRIVATE KEY-----') || s.includes('-----BEGIN RSA PRIVATE KEY-----');
}

function opensslBin(env = process.env) {
  const explicit = safeString(env.HUB_OPENSSL_BIN || env.OPENSSL_BIN || '');
  if (explicit) return explicit;
  return 'openssl';
}

function runOpenSSL(args, { input, cwd, env } = {}) {
  const bin = opensslBin(env);
  const res = spawnSync(bin, Array.isArray(args) ? args : [], {
    input: input != null ? Buffer.from(String(input), 'utf8') : undefined,
    cwd: cwd ? String(cwd) : undefined,
    env: env || process.env,
    stdio: ['pipe', 'pipe', 'pipe'],
    maxBuffer: 1024 * 1024 * 8,
  });
  if (res.error) {
    throw new Error(`openssl failed to start: ${String(res.error?.message || res.error)}`);
  }
  const code = Number(res.status || 0);
  if (code !== 0) {
    const stderr = (res.stderr || '').toString('utf8').trim();
    const stdout = (res.stdout || '').toString('utf8').trim();
    const msg = stderr || stdout || `exit=${code}`;
    throw new Error(`openssl ${args.join(' ')} failed: ${msg}`);
  }
  return {
    stdout: (res.stdout || '').toString('utf8'),
    stderr: (res.stderr || '').toString('utf8'),
  };
}

function normalizeSanIps(text) {
  const s = safeString(text);
  if (!s) return [];
  const parts = s
    .split(',')
    .map((x) => safeString(x))
    .filter(Boolean);
  const out = [];
  const seen = new Set();
  for (const p of parts) {
    if (seen.has(p)) continue;
    // Keep it permissive; openssl will validate.
    seen.add(p);
    out.push(p);
  }
  return out;
}

function renderServerExt({ serverName, sanIps }) {
  // Minimal v3 extensions for a gRPC server cert.
  // - We include a stable DNS name so clients can use authority override even when connecting by IP.
  // - We include loopback IPs and optional LAN IPs when provided.
  const dns = [serverName, 'localhost'].filter(Boolean);
  const ips = ['127.0.0.1', '::1', ...sanIps].filter(Boolean);

  const lines = [];
  lines.push('[v3_req]');
  lines.push('basicConstraints = CA:FALSE');
  // ECDSA uses digitalSignature; include keyEncipherment for compatibility.
  lines.push('keyUsage = critical, digitalSignature, keyEncipherment');
  lines.push('extendedKeyUsage = serverAuth');
  lines.push('subjectAltName = @alt_names');
  lines.push('');
  lines.push('[alt_names]');
  let n = 1;
  for (const d of dns) {
    lines.push(`DNS.${n} = ${d}`);
    n += 1;
  }
  n = 1;
  for (const ip of ips) {
    lines.push(`IP.${n} = ${ip}`);
    n += 1;
  }
  lines.push('');
  return lines.join('\n');
}

function renderClientExt({ deviceId }) {
  const did = safeString(deviceId);
  const lines = [];
  lines.push('[v3_req]');
  lines.push('basicConstraints = CA:FALSE');
  lines.push('keyUsage = critical, digitalSignature');
  lines.push('extendedKeyUsage = clientAuth');
  if (did) {
    // Not used for auth; for debug/audit only.
    lines.push(`subjectAltName = URI:axhub://device/${did}`);
  }
  lines.push('');
  return lines.join('\n');
}

function ensureTlsDir(p) {
  const dir = safeString(p);
  if (!dir) return;
  try {
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  } catch {
    // ignore
  }
}

function ensureKeyPerms(fp) {
  try {
    fs.chmodSync(fp, 0o600);
  } catch {
    // ignore
  }
}

export function ensureHubTlsMaterial(runtimeBaseDir, { env } = {}) {
  const base = safeString(runtimeBaseDir) || safeString(resolveRuntimeBaseDir());
  const p = tlsPaths(base, env);
  ensureTlsDir(p.dir);

  // Defaults: auto-generate on first run (Hub local machine).
  const autoGen = safeLower((env || process.env).HUB_GRPC_TLS_AUTO_GEN || '1') !== '0';
  if (!autoGen) return { ok: true, generated: false, paths: p };

  const caBroken =
    !fileExists(p.caKeyPath) ||
    !fileExists(p.caCertPath) ||
    !isPrivateKeyPemValid(p.caKeyPath) ||
    !isCertPemValid(p.caCertPath);

  let caRegenerated = false;
  if (caBroken) {
    // Remove partial/corrupt files to avoid reusing broken material.
    safeUnlink(p.caKeyPath);
    safeUnlink(p.caCertPath);
    safeUnlink(p.caSerialPath);
    safeUnlink(`${p.caCertPath}.srl`);
    safeUnlink(path.join(p.dir, 'ca.srl'));

    // New CA: generate EC key + self-signed cert.
    runOpenSSL(
      [
        'genpkey',
        '-algorithm',
        'EC',
        '-pkeyopt',
        'ec_paramgen_curve:prime256v1',
        '-pkeyopt',
        'ec_param_enc:named_curve',
        '-out',
        p.caKeyPath,
      ],
      { env }
    );
    ensureKeyPerms(p.caKeyPath);
    const subj = `/CN=AXHub CA ${os.hostname()}`;
    runOpenSSL(['req', '-x509', '-new', '-key', p.caKeyPath, '-sha256', '-days', '3650', '-out', p.caCertPath, '-subj', subj], { env });
    try {
      fs.chmodSync(p.caCertPath, 0o644);
    } catch {
      // ignore
    }
    caRegenerated = true;
  }

  const serverBroken =
    caRegenerated ||
    !fileExists(p.serverKeyPath) ||
    !fileExists(p.serverCertPath) ||
    !isPrivateKeyPemValid(p.serverKeyPath) ||
    !isCertPemValid(p.serverCertPath);

  if (serverBroken) {
    safeUnlink(p.serverKeyPath);
    safeUnlink(p.serverCertPath);
    safeUnlink(p.serverCsrPath);
    safeUnlink(p.serverExtPath);
    ensureValidSerialFile(p.caSerialPath);

    const serverName = tlsServerNameFromEnv(env || process.env);
    const sanIps = normalizeSanIps((env || process.env).HUB_GRPC_TLS_SERVER_SAN_IPS || '');

    runOpenSSL(
      [
        'genpkey',
        '-algorithm',
        'EC',
        '-pkeyopt',
        'ec_paramgen_curve:prime256v1',
        '-pkeyopt',
        'ec_param_enc:named_curve',
        '-out',
        p.serverKeyPath,
      ],
      { env }
    );
    ensureKeyPerms(p.serverKeyPath);
    runOpenSSL(['req', '-new', '-key', p.serverKeyPath, '-out', p.serverCsrPath, '-subj', `/CN=${serverName}`], { env });

    writeFileAtomic(p.serverExtPath, renderServerExt({ serverName, sanIps }), 0o644);
    runOpenSSL(
      [
        'x509',
        '-req',
        '-in',
        p.serverCsrPath,
        '-CA',
        p.caCertPath,
        '-CAkey',
        p.caKeyPath,
        '-CAserial',
        p.caSerialPath,
        '-CAcreateserial',
        '-out',
        p.serverCertPath,
        '-days',
        '825', // ~27 months (Apple-ish baseline); rotateable.
        '-sha256',
        '-extfile',
        p.serverExtPath,
        '-extensions',
        'v3_req',
      ],
      { env }
    );
    try {
      fs.chmodSync(p.serverCertPath, 0o644);
    } catch {
      // ignore
    }
    try {
      fs.unlinkSync(p.serverCsrPath);
    } catch {
      // ignore
    }
  }

  ensureTlsDir(p.clientsDir);

  return { ok: true, generated: true, paths: p };
}

function pemBodyToDer(pem) {
  const s = safeString(pem);
  if (!s) return Buffer.alloc(0);
  const b64 = s
    .replaceAll('-----BEGIN CERTIFICATE-----', '')
    .replaceAll('-----END CERTIFICATE-----', '')
    .replaceAll('\r', '')
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean)
    .join('');
  return Buffer.from(b64, 'base64');
}

export function sha256Hex(buf) {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

export function certPemSha256Hex(certPem) {
  const der = pemBodyToDer(certPem);
  if (!der.length) return '';
  return sha256Hex(der);
}

export function signClientCertFromCsr(runtimeBaseDir, { deviceId, csrPem, days = 825, env } = {}) {
  const base = safeString(runtimeBaseDir) || safeString(resolveRuntimeBaseDir());
  const did = safeString(deviceId);
  const csr = String(csrPem || '');
  if (!did) throw new Error('missing deviceId');
  if (!csr.trim().includes('BEGIN CERTIFICATE REQUEST')) throw new Error('missing/invalid csrPem');

  const ensured = ensureHubTlsMaterial(base, { env });
  const p = ensured.paths;
  ensureTlsDir(p.clientsDir);

  const outCertPath = path.join(p.clientsDir, `${did}.cert.pem`);
  const tmpDir = fs.mkdtempSync(path.join(p.clientsDir, `.tmp_${process.pid}_`));
  const csrPath = path.join(tmpDir, 'client.csr.pem');
  const extPath = path.join(tmpDir, 'client.ext');
  const outPath = path.join(tmpDir, 'client.cert.pem');

  // Write CSR/ext to tmp, sign, then atomically move to final path.
  fs.writeFileSync(csrPath, csr, { encoding: 'utf8', mode: 0o600 });
  fs.writeFileSync(extPath, renderClientExt({ deviceId: did }), { encoding: 'utf8', mode: 0o644 });
  ensureValidSerialFile(p.caSerialPath);

  runOpenSSL(
    [
      'x509',
      '-req',
      '-in',
      csrPath,
      '-CA',
      p.caCertPath,
      '-CAkey',
      p.caKeyPath,
      '-CAserial',
      p.caSerialPath,
      '-CAcreateserial',
      '-out',
      outPath,
      '-days',
      String(Math.max(1, Number(days || 0) || 825)),
      '-sha256',
      '-extfile',
      extPath,
      '-extensions',
      'v3_req',
    ],
    { env }
  );

  const certPem = fs.readFileSync(outPath, 'utf8');
  writeFileAtomic(outCertPath, certPem, 0o644);

  // Cleanup.
  try {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  } catch {
    // ignore
  }

  const cert_sha256 = certPemSha256Hex(certPem);
  return { ok: true, cert_pem: certPem, cert_sha256, cert_path: outCertPath, ca_cert_path: p.caCertPath };
}

export function readHubCaCertPem(runtimeBaseDir, { env } = {}) {
  const base = safeString(runtimeBaseDir) || safeString(resolveRuntimeBaseDir());
  const p = tlsPaths(base, env);
  if (!fileExists(p.caCertPath)) return '';
  try {
    return fs.readFileSync(p.caCertPath, 'utf8');
  } catch {
    return '';
  }
}

export function readIssuedClientCertPem(runtimeBaseDir, deviceId, { env } = {}) {
  const base = safeString(runtimeBaseDir) || safeString(resolveRuntimeBaseDir());
  const did = safeString(deviceId);
  if (!did) return '';
  const p = tlsPaths(base, env);
  const fp = path.join(p.clientsDir, `${did}.cert.pem`);
  if (!fileExists(fp)) return '';
  try {
    return fs.readFileSync(fp, 'utf8');
  } catch {
    return '';
  }
}

export function makeServerCredentials({ runtimeBaseDir, env } = {}) {
  const base = safeString(runtimeBaseDir) || safeString(resolveRuntimeBaseDir());
  const mode = tlsModeFromEnv(env || process.env);
  if (mode === 'insecure') {
    return { mode, creds: grpc.ServerCredentials.createInsecure() };
  }

  const ensured = ensureHubTlsMaterial(base, { env });
  const p = ensured.paths;

  const serverKey = readFileBuf(p.serverKeyPath);
  const serverCert = readFileBuf(p.serverCertPath);

  if (mode === 'tls') {
    return {
      mode,
      creds: grpc.ServerCredentials.createSsl(null, [{ private_key: serverKey, cert_chain: serverCert }], false),
    };
  }

  // mtls
  const caCert = readFileBuf(p.caCertPath);
  return {
    mode,
    creds: grpc.ServerCredentials.createSsl(caCert, [{ private_key: serverKey, cert_chain: serverCert }], true),
  };
}
