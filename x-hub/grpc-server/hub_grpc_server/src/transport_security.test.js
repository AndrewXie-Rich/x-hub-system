import assert from 'node:assert/strict';
import fs from 'node:fs';
import https from 'node:https';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { spawnSync } from 'node:child_process';

import { startPairingHTTPServer } from './pairing_http.js';
import { makeClientCredentials } from './client_credentials.js';
import { tlsModeFromEnv, tlsPaths } from './tls_support.js';
import { grpcTransportFromEnv, isLoopbackHost, pairingTransportFromEnv } from './transport_security.js';

test('TLS is the default and invalid modes never downgrade to plaintext', () => {
  assert.equal(tlsModeFromEnv({}), 'tls');
  assert.equal(tlsModeFromEnv({ HUB_GRPC_TLS_MODE: '  ' }), 'tls');
  assert.equal(tlsModeFromEnv({ HUB_TLS_MODE: 'mtls' }), 'mtls');
  assert.equal(tlsModeFromEnv({ HUB_GRPC_TLS_MODE: 'insecure' }), 'insecure');
  assert.throws(() => tlsModeFromEnv({ HUB_GRPC_TLS_MODE: 'mtls-typo' }), /Invalid/);
});

test('gRPC only permits explicit plaintext on numeric loopback addresses', () => {
  assert.deepEqual(grpcTransportFromEnv({}), { host: '::', mode: 'tls' });
  assert.deepEqual(grpcTransportFromEnv({ HUB_GRPC_TLS_MODE: 'insecure' }), { host: '127.0.0.1', mode: 'insecure' });
  for (const host of ['127.0.0.1', '127.2.3.4', '::1']) {
    assert.equal(isLoopbackHost(host), true);
    assert.equal(grpcTransportFromEnv({ HUB_GRPC_TLS_MODE: 'insecure', HUB_HOST: host }).host, host);
  }
  for (const host of ['::', '0.0.0.0', '192.168.1.2', '100.64.0.1', 'localhost', '[::1', '127.0.0.999']) {
    assert.throws(() => grpcTransportFromEnv({ HUB_GRPC_TLS_MODE: 'insecure', HUB_HOST: host }), /loopback/);
    assert.throws(() => makeClientCredentials({ HUB_GRPC_TLS_MODE: 'insecure', HUB_HOST: host }), /loopback/);
  }
});

test('pairing HTTP remains loopback-only even behind spoofed public scheme configuration', () => {
  const local = pairingTransportFromEnv({ HUB_HOST: '::' });
  assert.equal(local.host, '127.0.0.1');
  assert.equal(local.scheme, 'http');
  for (const host of ['::', '0.0.0.0', '192.168.1.2']) {
    assert.throws(() => pairingTransportFromEnv({ HUB_PAIRING_HOST: host, HUB_PAIRING_PUBLIC_SCHEME: 'https' }), /loopback/);
  }
  assert.throws(() => pairingTransportFromEnv({ HUB_PAIRING_TLS_CERT_PATH: '/missing' }), /both/);
  assert.throws(() => pairingTransportFromEnv({ HUB_PAIRING_TLS_MODE: 'typo' }), /Invalid/);
  assert.throws(() => pairingTransportFromEnv({ HUB_PAIRING_TLS_CERT_PATH: '/missing', HUB_PAIRING_TLS_KEY_PATH: '/missing' }), /ENOENT/);
});

test('axhubctl uses verified HTTPS and refuses plaintext network downloads', () => {
  const script = fs.readFileSync(new URL('../assets/axhubctl', import.meta.url), 'utf8');
  const helpers = script.slice(0, script.indexOf('\nrun_self()'));
  const invoke = (command, environment = {}) => spawnSync('/bin/sh', ['-c', `${helpers}\n${command}`], {
    env: { PATH: process.env.PATH, ...environment },
    encoding: 'utf8',
  });
  assert.equal(invoke('pairing_url hub.example 50052 /health').stdout.trim(), 'https://hub.example:50052/health');
  assert.equal(invoke('pairing_url 2001:db8::10 50052 /health').stdout.trim(), 'https://[2001:db8::10]:50052/health');
  assert.equal(invoke('pairing_url "[2001:db8::10]" 50052 /health').stdout.trim(), 'https://[2001:db8::10]:50052/health');
  assert.equal(invoke('pairing_url 127.0.0.1 50052 /health').stdout.trim(), 'http://127.0.0.1:50052/health');
  assert.equal(invoke('pairing_url ::1 50052 /health').stdout.trim(), 'http://[::1]:50052/health');
  assert.equal(invoke('pairing_url 127.0.0.1 50052 /health', { HUB_PAIRING_SCHEME: 'https' }).stdout.trim(), 'https://127.0.0.1:50052/health');
  assert.notEqual(invoke('pairing_url hub.example 50052 /health', { HUB_PAIRING_SCHEME: 'http' }).status, 0);
  const denied = invoke('pairing_curl http://hub.example:50052/pairing/requests');
  assert.notEqual(denied.status, 0);
  assert.match(denied.stderr, /refusing plaintext/);
  for (const url of ['http://127.0.0.1:80@other.invalid/secret', 'http://localhost:80.other.invalid/secret']) {
    const invalidAuthority = invoke(`pairing_curl '${url}'`);
    assert.notEqual(invalidAuthority.status, 0);
    assert.match(invalidAuthority.stderr, /invalid loopback authority/);
  }
  for (const host of ['127.0.0.1:80@other.invalid', 'https://other.invalid/path', 'other.invalid?next=secret']) {
    const invalidHost = invoke(`pairing_url '${host}' 50052 /health`);
    assert.notEqual(invalidHost.status, 0);
    assert.match(invalidHost.stderr, /invalid pairing host authority/);
  }
  const args = invoke('curl() { printf "%s\\n" "$@"; }; pairing_curl -fsS https://hub.example:50052/health', {
    HUB_PAIRING_CA_CERT_PATH: '/trusted/ca.pem',
  });
  assert.equal(args.status, 0);
  assert.match(args.stdout, /--cacert\n\/trusted\/ca.pem/);
  assert.match(args.stdout, /--proto-redir\n=https/);
  assert.match(args.stdout, /^-q\n/);
  assert.match(args.stdout, /--noproxy\n127.0.0.1,localhost,::1/);
  const relativeCA = invoke('pairing_curl https://hub.example:50052/health', { HUB_PAIRING_CA_CERT_PATH: 'relative.pem' });
  assert.notEqual(relativeCA.status, 0);
  assert.match(relativeCA.stderr, /absolute path/);
});

async function freePort() {
  const server = net.createServer();
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const port = server.address().port;
  await new Promise((resolve) => server.close(resolve));
  return port;
}

function getHTTPS(port, requestPath, ca) {
  return new Promise((resolve, reject) => {
    const request = https.get({ host: '127.0.0.1', port, path: requestPath, ca, servername: 'axhub', agent: false }, (response) => {
      let body = '';
      response.on('data', (chunk) => { body += chunk; });
      response.on('end', () => resolve({ status: response.statusCode, body }));
    });
    request.on('error', reject);
    request.setTimeout(2000, () => request.destroy(new Error('HTTPS request timeout')));
  });
}

test('pairing HTTPS validates the Hub certificate and retains endpoint authentication', async () => {
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-https-test-'));
  const port = await freePort();
  const environment = {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_AUTH_BASE_DIR: runtimeBaseDir,
    HUB_CLIENTS_BASE_DIR: runtimeBaseDir,
    HUB_GRPC_TLS_DIR: path.join(runtimeBaseDir, 'tls'),
    HUB_GRPC_TLS_MODE: 'tls',
    HUB_PAIRING_ENABLE: '1',
    HUB_PAIRING_HOST: '127.0.0.1',
    HUB_PAIRING_PORT: String(port),
    HUB_PAIRING_TLS_MODE: 'tls',
    HUB_PAIRING_TLS_CERT_PATH: '',
    HUB_PAIRING_TLS_KEY_PATH: '',
    HUB_PAIRING_PUBLIC_SCHEME: '',
    HUB_ADMIN_TOKEN: 'test-admin',
  };
  const previous = Object.fromEntries(Object.keys(environment).map((key) => [key, process.env[key]]));
  Object.assign(process.env, environment);
  let stop;
  try {
    stop = startPairingHTTPServer({ db: { appendAudit() {} } });
    const ca = fs.readFileSync(tlsPaths(runtimeBaseDir).caCertPath);
    const healthy = await getHTTPS(port, '/health', ca);
    assert.equal(healthy.status, 200);
    assert.equal(JSON.parse(healthy.body).ok, true);
    await assert.rejects(getHTTPS(port, '/health'), /certificate|issuer/i);
    const unauthorized = await getHTTPS(port, '/admin/provider-keys/oauth/status', ca);
    assert.equal(unauthorized.status, 401);
    const explicit = pairingTransportFromEnv({
      HUB_PAIRING_HOST: '::',
      HUB_PAIRING_TLS_CERT_PATH: tlsPaths(runtimeBaseDir).serverCertPath,
      HUB_PAIRING_TLS_KEY_PATH: tlsPaths(runtimeBaseDir).serverKeyPath,
    });
    assert.equal(explicit.scheme, 'https');
    assert.equal(explicit.host, '::');
  } finally {
    stop?.();
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
  }
});
