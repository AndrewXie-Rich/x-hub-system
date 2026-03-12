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

function makeTransportCall() {
  return {
    metadata: {
      get() {
        return [];
      },
    },
    getPeer() {
      return 'ipv4:127.0.0.1:54321';
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
