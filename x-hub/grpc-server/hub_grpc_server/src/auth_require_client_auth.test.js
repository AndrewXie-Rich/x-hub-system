import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { requireClientAuth } from './auth.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function withEnv(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv)) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return fn();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

function makeTransportCall(token = '', options = {}) {
  const peer = String(options.peer || 'ipv4:127.0.0.1:54321');
  const certRaw = options.cert_raw || null;
  return {
    metadata: {
      get(key) {
        if (String(key || '').toLowerCase() !== 'authorization') return [];
        return token ? [`Bearer ${token}`] : [];
      },
    },
    getPeer() {
      return peer;
    },
    getAuthContext() {
      return certRaw ? { sslPeerCertificate: { raw: certRaw } } : {};
    },
    sendMetadata() {},
    getDeadline() {
      return Date.now() + 1_000;
    },
  };
}

function makeRuntimeBaseDir(label) {
  return fs.mkdtempSync(path.join(os.tmpdir(), `hub_auth_${label}_`));
}

function makeDirectCall() {
  return {
    metadata: {
      get() {
        return [];
      },
    },
    getPeer() {
      return 'ipv4:127.0.0.1:54321';
    },
  };
}

function writeClientsSnapshot(runtimeBaseDir, clients) {
  fs.writeFileSync(
    path.join(runtimeBaseDir, 'hub_grpc_clients.json'),
    JSON.stringify({
      schema_version: 'hub_grpc_clients.v2',
      updated_at_ms: 1,
      clients,
    }, null, 2) + '\n',
    'utf8'
  );
}

run('requireClientAuth denies real grpc transport when no tokens are configured', () => {
  const runtimeBaseDir = makeRuntimeBaseDir('transport');
  withEnv(
    {
      HUB_CLIENT_TOKEN: '',
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      HUB_GRPC_TLS_MODE: '',
      HUB_GRPC_CERT: '',
      HUB_GRPC_KEY: '',
      HUB_GRPC_CA: '',
    },
    () => {
      const auth = requireClientAuth(makeTransportCall());
      assert.equal(auth.ok, false);
      assert.equal(String(auth.reason || ''), 'no_tokens_configured');
      assert.equal(String(auth.code || ''), 'unauthenticated');
    }
  );
  fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
});

run('requireClientAuth preserves direct in-process service invocation for unit tests', () => {
  const runtimeBaseDir = makeRuntimeBaseDir('direct');
  withEnv(
    {
      HUB_CLIENT_TOKEN: '',
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      HUB_GRPC_TLS_MODE: '',
      HUB_GRPC_CERT: '',
      HUB_GRPC_KEY: '',
      HUB_GRPC_CA: '',
    },
    () => {
      const auth = requireClientAuth(makeDirectCall());
      assert.equal(auth.ok, true);
    }
  );
  fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
});

run('requireClientAuth rejects revoked hub access keys with explicit token_revoked reason', () => {
  const runtimeBaseDir = makeRuntimeBaseDir('revoked');
  writeClientsSnapshot(runtimeBaseDir, [{
    access_key_id: 'hak_revoked_1',
    auth_kind: 'hub_access_key',
    device_id: 'client_revoked_1',
    user_id: 'svc_revoked',
    app_id: 'external_terminal',
    name: 'Revoked Key',
    token: 'tok_revoked_1',
    enabled: false,
    created_at_ms: 1,
    revoked_at_ms: 123,
    revoke_reason: 'manual_disable',
    capabilities: ['models'],
    scopes: ['models'],
    allowed_cidrs: ['loopback'],
  }]);
  withEnv(
    {
      HUB_CLIENT_TOKEN: '',
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      HUB_GRPC_TLS_MODE: '',
      HUB_GRPC_CERT: '',
      HUB_GRPC_KEY: '',
      HUB_GRPC_CA: '',
    },
    () => {
      const auth = requireClientAuth(makeTransportCall('tok_revoked_1'));
      assert.equal(auth.ok, false);
      assert.equal(String(auth.reason || ''), 'token_revoked');
      assert.equal(String(auth.code || ''), 'token_revoked');
    }
  );
  fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
});

run('requireClientAuth updates last_used metadata for ready hub access keys', () => {
  const runtimeBaseDir = makeRuntimeBaseDir('usage_touch');
  writeClientsSnapshot(runtimeBaseDir, [{
    access_key_id: 'hak_ready_1',
    auth_kind: 'hub_access_key',
    device_id: 'client_ready_1',
    user_id: 'svc_ready',
    app_id: 'external_terminal',
    name: 'Ready Key',
    token: 'tok_ready_1',
    enabled: true,
    created_at_ms: 1,
    capabilities: ['models', 'ai.generate.local'],
    scopes: ['models', 'ai.generate.local'],
    allowed_cidrs: ['loopback'],
  }]);
  withEnv(
    {
      HUB_CLIENT_TOKEN: '',
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      HUB_GRPC_TLS_MODE: '',
      HUB_GRPC_CERT: '',
      HUB_GRPC_KEY: '',
      HUB_GRPC_CA: '',
    },
    () => {
      const auth = requireClientAuth(makeTransportCall('tok_ready_1'));
      assert.equal(auth.ok, true);
      assert.equal(String(auth.access_key_id || ''), 'hak_ready_1');
      assert.equal(String(auth.auth_kind || ''), 'hub_access_key');
      const persisted = JSON.parse(fs.readFileSync(path.join(runtimeBaseDir, 'hub_grpc_clients.json'), 'utf8'));
      assert.ok(Number(persisted.clients?.[0]?.last_used_at_ms || 0) > 0);
      assert.equal(String(persisted.clients?.[0]?.last_used_transport || ''), 'grpc');
      assert.equal(String(persisted.clients?.[0]?.last_used_peer_ip || ''), '127.0.0.1');
    }
  );
  fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
});

run('requireClientAuth lets mTLS paired clients roam outside their first LAN CIDR', () => {
  const runtimeBaseDir = makeRuntimeBaseDir('paired_roaming');
  const certRaw = Buffer.from('paired-client-cert-v1');
  writeClientsSnapshot(runtimeBaseDir, [{
    access_key_id: 'paired_xt_1',
    auth_kind: 'paired_client',
    device_id: 'xt_roaming_1',
    user_id: 'user_roaming',
    app_id: 'x_terminal',
    name: 'Roaming XT',
    token: 'tok_roaming_1',
    enabled: true,
    created_at_ms: 1,
    capabilities: ['models'],
    scopes: ['models'],
    allowed_cidrs: ['192.168.10.0/24'],
    cert_sha256: crypto.createHash('sha256').update(certRaw).digest('hex'),
  }]);
  withEnv(
    {
      HUB_CLIENT_TOKEN: '',
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      HUB_GRPC_TLS_MODE: 'mtls',
      HUB_GRPC_MTLS_REQUIRE_CERT_PIN: '1',
      HUB_GRPC_PAIRED_CLIENT_ROAMING: '1',
      HUB_GRPC_CERT: '',
      HUB_GRPC_KEY: '',
      HUB_GRPC_CA: '',
    },
    () => {
      const auth = requireClientAuth(makeTransportCall('tok_roaming_1', {
        peer: 'ipv4:17.81.11.23:54321',
        cert_raw: certRaw,
      }));
      assert.equal(auth.ok, true);
      assert.equal(String(auth.auth_kind || ''), 'paired_client');
    }
  );
  fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
});

run('requireClientAuth lets pinned mTLS paired clients roam outside the global LAN CIDR', () => {
  const runtimeBaseDir = makeRuntimeBaseDir('paired_global_roaming');
  const certRaw = Buffer.from('paired-client-cert-global-v1');
  writeClientsSnapshot(runtimeBaseDir, [{
    access_key_id: 'paired_xt_global_1',
    auth_kind: 'paired_client',
    device_id: 'xt_global_roaming_1',
    user_id: 'user_roaming',
    app_id: 'x_terminal',
    name: 'Roaming XT',
    token: 'tok_global_roaming_1',
    enabled: true,
    created_at_ms: 1,
    capabilities: ['models'],
    scopes: ['models'],
    allowed_cidrs: ['192.168.10.0/24'],
    cert_sha256: crypto.createHash('sha256').update(certRaw).digest('hex'),
  }]);
  withEnv(
    {
      HUB_CLIENT_TOKEN: '',
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      HUB_ALLOWED_CIDRS: 'private,loopback,192.168.10.0/24',
      HUB_GRPC_TLS_MODE: 'mtls',
      HUB_GRPC_MTLS_REQUIRE_CERT_PIN: '1',
      HUB_GRPC_PAIRED_CLIENT_ROAMING: '1',
      HUB_GRPC_CERT: '',
      HUB_GRPC_KEY: '',
      HUB_GRPC_CA: '',
    },
    () => {
      const auth = requireClientAuth(makeTransportCall('tok_global_roaming_1', {
        peer: 'ipv4:17.81.11.23:54321',
        cert_raw: certRaw,
      }));
      assert.equal(auth.ok, true);
      assert.equal(String(auth.auth_kind || ''), 'paired_client');
    }
  );
  fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
});

run('requireClientAuth keeps the global LAN CIDR gate for non-paired access keys', () => {
  const runtimeBaseDir = makeRuntimeBaseDir('access_key_global_ip_bind');
  writeClientsSnapshot(runtimeBaseDir, [{
    access_key_id: 'hak_global_ip_bound_1',
    auth_kind: 'hub_access_key',
    device_id: 'svc_global_ip_bound_1',
    user_id: 'svc_ip_bound',
    app_id: 'external_terminal',
    name: 'IP Bound Key',
    token: 'tok_global_ip_bound_1',
    enabled: true,
    created_at_ms: 1,
    capabilities: ['models'],
    scopes: ['models'],
    allowed_cidrs: ['any'],
  }]);
  withEnv(
    {
      HUB_CLIENT_TOKEN: '',
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      HUB_ALLOWED_CIDRS: 'private,loopback,192.168.10.0/24',
      HUB_GRPC_TLS_MODE: 'mtls',
      HUB_GRPC_CERT: '',
      HUB_GRPC_KEY: '',
      HUB_GRPC_CA: '',
    },
    () => {
      const auth = requireClientAuth(makeTransportCall('tok_global_ip_bound_1', {
        peer: 'ipv4:17.81.11.23:54321',
        cert_raw: Buffer.from('unpaired-access-key-cert'),
      }));
      assert.equal(auth.ok, false);
      assert.equal(String(auth.reason || ''), 'source_ip_not_allowed');
    }
  );
  fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
});

run('requireClientAuth keeps source IP binding for non-paired access keys', () => {
  const runtimeBaseDir = makeRuntimeBaseDir('access_key_ip_bind');
  writeClientsSnapshot(runtimeBaseDir, [{
    access_key_id: 'hak_ip_bound_1',
    auth_kind: 'hub_access_key',
    device_id: 'svc_ip_bound_1',
    user_id: 'svc_ip_bound',
    app_id: 'external_terminal',
    name: 'IP Bound Key',
    token: 'tok_ip_bound_1',
    enabled: true,
    created_at_ms: 1,
    capabilities: ['models'],
    scopes: ['models'],
    allowed_cidrs: ['192.168.10.0/24'],
  }]);
  withEnv(
    {
      HUB_CLIENT_TOKEN: '',
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      HUB_GRPC_TLS_MODE: '',
      HUB_GRPC_CERT: '',
      HUB_GRPC_KEY: '',
      HUB_GRPC_CA: '',
    },
    () => {
      const auth = requireClientAuth(makeTransportCall('tok_ip_bound_1', {
        peer: 'ipv4:17.81.11.23:54321',
      }));
      assert.equal(auth.ok, false);
      assert.equal(String(auth.reason || ''), 'source_ip_not_allowed');
    }
  );
  fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
});
