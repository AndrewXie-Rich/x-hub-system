import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  resolveHubIdentity,
  resolveHubInternetHostHint,
} from './hub_identity.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

function withEnv(tempEnv, fn) {
  const prev = new Map();
  for (const key of Object.keys(tempEnv || {})) {
    prev.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return fn();
  } finally {
    for (const [key, val] of prev.entries()) {
      if (val == null) delete process.env[key];
      else process.env[key] = val;
    }
  }
}

function makeTmpDir(label) {
  return fs.mkdtempSync(path.join(os.tmpdir(), `${label}_`));
}

run('hub_identity persists a stable hub instance id and derived LAN discovery name', () => {
  const runtimeBaseDir = makeTmpDir('hub_identity_runtime');
  try {
    const first = resolveHubIdentity({ runtimeBaseDir });
    const second = resolveHubIdentity({ runtimeBaseDir });

    assert.equal(String(first.schema_version || ''), 'xhub.hub_identity.v1');
    assert.match(String(first.hub_instance_id || ''), /^hub_[a-f0-9]{20}$/);
    assert.match(String(first.lan_discovery_name || ''), /^axhub-[a-z0-9-]+$/);
    assert.equal(String(second.hub_instance_id || ''), String(first.hub_instance_id || ''));
    assert.equal(String(second.lan_discovery_name || ''), String(first.lan_discovery_name || ''));

    const persisted = JSON.parse(fs.readFileSync(path.join(runtimeBaseDir, 'hub_identity.json'), 'utf8'));
    assert.equal(String(persisted.hub_instance_id || ''), String(first.hub_instance_id || ''));
    assert.equal(String(persisted.lan_discovery_name || ''), String(first.lan_discovery_name || ''));
  } finally {
    try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
  }
});

run('hub_identity honors explicit env overrides without requiring persisted defaults', () => {
  const runtimeBaseDir = makeTmpDir('hub_identity_env');
  try {
    const out = withEnv({
      HUB_INSTANCE_ID: 'hub_ops_edge_01',
      HUB_LAN_DISCOVERY_NAME: 'axhub-edge-bj',
    }, () => resolveHubIdentity({ runtimeBaseDir }));

    assert.equal(String(out.hub_instance_id || ''), 'hub_ops_edge_01');
    assert.equal(String(out.lan_discovery_name || ''), 'axhub-edge-bj');
  } finally {
    try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
  }
});

run('hub_identity keeps LAN discovery separate from internet host and can infer remote host from tunnel config', () => {
  const runtimeBaseDir = makeTmpDir('hub_identity_tunnel');
  const stateDir = makeTmpDir('hub_identity_state');
  try {
    fs.writeFileSync(
      path.join(stateDir, 'tunnel_config.env'),
      [
        "export AXHUB_TUNNEL_LOCAL_HOST='127.0.0.1'",
        "export AXHUB_TUNNEL_LOCAL_PORT='50051'",
        "export AXHUB_TUNNEL_REMOTE_HOST='hub.tailnet.example'",
        "export AXHUB_TUNNEL_REMOTE_PORT='50051'",
        '',
      ].join('\n'),
      'utf8',
    );

    const identity = resolveHubIdentity({ runtimeBaseDir });
    const internetHostHint = withEnv({
      AXHUB_STATE_DIR: stateDir,
      HUB_PAIRING_PUBLIC_HOST: '',
      HUB_INTERNET_HOST: '',
      AXHUB_INTERNET_HOST: '',
    }, () => resolveHubInternetHostHint({ runtimeBaseDir }));

    assert.match(String(identity.lan_discovery_name || ''), /^axhub-[a-z0-9-]+$/);
    assert.equal(String(internetHostHint || ''), 'hub.tailnet.example');
    assert.notEqual(String(internetHostHint || ''), String(identity.lan_discovery_name || ''));
  } finally {
    try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
    try { fs.rmSync(stateDir, { recursive: true, force: true }); } catch {}
  }
});
