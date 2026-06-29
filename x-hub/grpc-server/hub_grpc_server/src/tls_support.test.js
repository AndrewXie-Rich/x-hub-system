import assert from 'node:assert/strict';
import path from 'node:path';

import { tlsBaseDir } from './tls_support.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

run('tlsBaseDir stores TLS material in auth base before runtime base', () => {
  const selected = tlsBaseDir('/tmp/xhub-runtime-base', {
    HUB_AUTH_BASE_DIR: '/tmp/xhub-auth-base',
  });

  assert.equal(selected, path.join('/tmp/xhub-auth-base', 'hub_grpc_tls'));
});

run('tlsBaseDir accepts clients base as auth-compatible fallback', () => {
  const selected = tlsBaseDir('/tmp/xhub-runtime-base', {
    HUB_CLIENTS_BASE_DIR: '/tmp/xhub-clients-base',
  });

  assert.equal(selected, path.join('/tmp/xhub-clients-base', 'hub_grpc_tls'));
});

run('tlsBaseDir keeps explicit TLS dir highest priority', () => {
  const selected = tlsBaseDir('/tmp/xhub-runtime-base', {
    HUB_GRPC_TLS_DIR: '/tmp/xhub-explicit-tls',
    HUB_AUTH_BASE_DIR: '/tmp/xhub-auth-base',
  });

  assert.equal(selected, '/tmp/xhub-explicit-tls');
});
