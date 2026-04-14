import assert from 'node:assert/strict';
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

function makeRuntimeBaseDir(label) {
  return fs.mkdtempSync(path.join(os.tmpdir(), `hub_auth_corp_${label}_`));
}

function makeTransportCall({ peerIp, token }) {
  return {
    metadata: {
      get(key) {
        if (String(key) === 'authorization') {
          return [`Bearer ${token}`];
        }
        return [];
      },
    },
    getPeer() {
      return `ipv4:${peerIp}:54321`;
    },
    sendMetadata() {},
    getDeadline() {
      return Date.now() + 1_000;
    },
  };
}

run('requireClientAuth allows sibling corporate subnet peers when coarse /16 allowlist is present', () => {
  const runtimeBaseDir = makeRuntimeBaseDir('allow');
  withEnv(
    {
      HUB_CLIENT_TOKEN: 'corp-test-token',
      HUB_ALLOWED_CIDRS: 'private,loopback,17.81.12.0/24,17.81.0.0/16',
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      HUB_GRPC_TLS_MODE: '',
      HUB_GRPC_CERT: '',
      HUB_GRPC_KEY: '',
      HUB_GRPC_CA: '',
    },
    () => {
      const auth = requireClientAuth(makeTransportCall({
        peerIp: '17.81.11.88',
        token: 'corp-test-token',
      }));
      assert.equal(auth.ok, true);
      assert.equal(String(auth.peer_ip || ''), '17.81.11.88');
    }
  );
  fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
});

run('requireClientAuth still denies non-corporate peers outside the coarse /16 allowlist', () => {
  const runtimeBaseDir = makeRuntimeBaseDir('deny');
  withEnv(
    {
      HUB_CLIENT_TOKEN: 'corp-test-token',
      HUB_ALLOWED_CIDRS: 'private,loopback,17.81.12.0/24,17.81.0.0/16',
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      HUB_GRPC_TLS_MODE: '',
      HUB_GRPC_CERT: '',
      HUB_GRPC_KEY: '',
      HUB_GRPC_CA: '',
    },
    () => {
      const auth = requireClientAuth(makeTransportCall({
        peerIp: '17.82.11.88',
        token: 'corp-test-token',
      }));
      assert.equal(auth.ok, false);
      assert.equal(String(auth.reason || ''), 'source_ip_not_allowed');
    }
  );
  fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
});
