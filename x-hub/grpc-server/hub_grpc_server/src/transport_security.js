import fs from 'node:fs';
import net from 'node:net';

import { ensureHubTlsMaterial, tlsModeFromEnv } from './tls_support.js';
import { resolveRuntimeBaseDir } from './local_runtime_ipc.js';

export function isLoopbackHost(value) {
  const host = String(value || '').trim().toLowerCase();
  if (host === '::1') return true;
  return net.isIP(host) === 4 && host.split('.')[0] === '127';
}

export function grpcTransportFromEnv(env = process.env) {
  const mode = tlsModeFromEnv(env);
  let host = String(env.HUB_HOST || '').trim() || (mode === 'insecure' ? '127.0.0.1' : '::');
  if (host === '0.0.0.0' && String(env.HUB_IPV6_DUALSTACK || '1').trim() !== '0') host = '::';
  if (mode === 'insecure' && !isLoopbackHost(host)) {
    throw new Error('Insecure gRPC requires a loopback HUB_HOST; use TLS/mTLS for network access');
  }
  return { host, mode };
}

export function pairingTransportFromEnv(env = process.env) {
  let certPath = String(env.HUB_PAIRING_TLS_CERT_PATH || '').trim();
  let keyPath = String(env.HUB_PAIRING_TLS_KEY_PATH || '').trim();
  if (Boolean(certPath) !== Boolean(keyPath)) {
    throw new Error('Pairing HTTPS requires both HUB_PAIRING_TLS_CERT_PATH and HUB_PAIRING_TLS_KEY_PATH');
  }
  const tlsMode = String(env.HUB_PAIRING_TLS_MODE || '').trim().toLowerCase();
  if (tlsMode && tlsMode !== 'tls') {
    throw new Error('Invalid HUB_PAIRING_TLS_MODE: expected tls or unset for loopback HTTP');
  }
  if (tlsMode === 'tls' && !certPath) {
    const material = ensureHubTlsMaterial(String(env.HUB_RUNTIME_BASE_DIR || '').trim() || resolveRuntimeBaseDir(), { env });
    certPath = material.paths.serverCertPath;
    keyPath = material.paths.serverKeyPath;
  }
  const scheme = certPath ? 'https' : 'http';
  let host = String(env.HUB_PAIRING_HOST || '').trim() || (certPath ? String(env.HUB_HOST || '::').trim() : '127.0.0.1');
  if (host === '0.0.0.0' && String(env.HUB_IPV6_DUALSTACK || '1').trim() !== '0') host = '::';
  if (scheme === 'http' && !isLoopbackHost(host)) {
    throw new Error('Plaintext pairing requires a loopback HUB_PAIRING_HOST; configure HTTPS for network pairing');
  }
  return {
    host,
    scheme,
    tlsOptions: certPath ? { cert: fs.readFileSync(certPath), key: fs.readFileSync(keyPath), minVersion: 'TLSv1.2' } : null,
  };
}
