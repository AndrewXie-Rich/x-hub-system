import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  resolveDefaultXHubAppPath,
  resolveHubProtocolPath,
  resolveNodeHubSourceDir,
  resolveXHubSystemRoot,
  tryResolveXHubSystemRoot,
} from './xhub_system_paths.js';

function touch(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, 'fixture\n');
}

function makeSourceTree(root) {
  touch(path.join(root, 'rust', 'xhubd', 'Cargo.toml'));
  touch(path.join(root, 'rust', 'xhubd', 'tools', 'package_rust_hub.command'));
  touch(path.join(root, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src', 'services.js'));
  touch(path.join(root, 'x-terminal', 'Package.swift'));
  touch(path.join(root, 'protocol', 'hub_protocol_v1.proto'));
  return root;
}

function makeBundle(appPath) {
  const toolsDir = path.join(appPath, 'Contents', 'Resources', 'rust-hub', 'tools');
  const nodeSourceDir = path.join(appPath, 'Contents', 'Resources', 'hub_grpc_server', 'src');
  touch(path.join(toolsDir, 'xhub_system_paths.js'));
  touch(path.join(nodeSourceDir, 'services.js'));
  touch(path.join(appPath, 'Contents', 'Resources', 'protocol', 'hub_protocol_v1.proto'));
  return { toolsDir, nodeSourceDir };
}

const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-system-paths-test-'));
test.after(() => fs.rmSync(scratch, { recursive: true, force: true }));

test('discovers a canonical source tree under an arbitrary user path', () => {
  const root = makeSourceTree(path.join(
    scratch,
    'Users',
    'portable.user',
    'Documents',
    'AX',
    'x-hub-system',
  ));
  const toolsDir = path.join(root, 'rust', 'xhubd', 'tools');
  assert.equal(resolveXHubSystemRoot({ env: {}, startDir: toolsDir }), root);
  assert.equal(
    resolveNodeHubSourceDir({ env: {}, startDir: toolsDir }),
    path.join(root, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src'),
  );
});

test('discovers a relocated source tree without relying on its directory name', () => {
  const root = makeSourceTree(path.join(scratch, 'relocated', 'renamed-system-source'));
  assert.equal(
    resolveXHubSystemRoot({
      env: {},
      startDir: path.join(root, 'rust', 'xhubd', 'tools'),
    }),
    root,
  );
});

test('uses Node Hub source from the same X-Hub.app bundle', () => {
  const appPath = path.join(scratch, 'bundle', 'X-Hub.app');
  const { toolsDir, nodeSourceDir } = makeBundle(appPath);
  assert.equal(resolveNodeHubSourceDir({ env: {}, startDir: toolsDir }), nodeSourceDir);
  assert.equal(resolveDefaultXHubAppPath({ env: {}, startDir: toolsDir }), appPath);
  assert.equal(
    resolveHubProtocolPath({ env: {}, startDir: toolsDir }),
    path.join(appPath, 'Contents', 'Resources', 'protocol', 'hub_protocol_v1.proto'),
  );
});

test('rejects an explicit system root that does not contain canonical markers', () => {
  const invalidRoot = path.join(scratch, 'invalid-root');
  fs.mkdirSync(invalidRoot, { recursive: true });
  assert.throws(
    () => resolveXHubSystemRoot({
      env: { XHUB_SYSTEM_ROOT: invalidRoot },
      startDir: scratch,
    }),
    /invalid X-Hub system root.*missing markers/,
  );
});

test('validates explicit Node Hub source overrides and rejects conflicts', () => {
  const validSource = path.join(scratch, 'explicit-node-source');
  const invalidSource = path.join(scratch, 'invalid-node-source');
  touch(path.join(validSource, 'services.js'));
  fs.mkdirSync(invalidSource, { recursive: true });
  assert.equal(
    resolveNodeHubSourceDir({
      env: { XHUB_NODE_HUB_SRC_DIR: validSource },
      startDir: scratch,
    }),
    validSource,
  );
  assert.throws(
    () => resolveNodeHubSourceDir({
      env: { XHUB_HUB_GRPC_SERVER_SRC_DIR: invalidSource },
      startDir: scratch,
    }),
    /invalid Node Hub source directory.*missing markers/,
  );
  assert.throws(
    () => resolveNodeHubSourceDir({
      env: {
        XHUB_NODE_HUB_SRC_DIR: validSource,
        XHUB_HUB_GRPC_SERVER_SRC_DIR: invalidSource,
      },
      startDir: scratch,
    }),
    /conflicting Node Hub source overrides/,
  );
});

test('derives source-build and installed-app defaults without a username fallback', () => {
  const root = makeSourceTree(path.join(scratch, 'app-default-source'));
  assert.equal(
    resolveDefaultXHubAppPath({
      env: {},
      startDir: path.join(root, 'rust', 'xhubd', 'tools'),
    }),
    path.join(root, 'build', 'X-Hub.app'),
  );
  assert.equal(
    resolveDefaultXHubAppPath({
      env: {},
      startDir: path.join(scratch, 'outside-any-source', 'tools'),
    }),
    '/Applications/X-Hub.app',
  );
  assert.equal(
    tryResolveXHubSystemRoot({
      env: {},
      startDir: path.join(scratch, 'outside-any-source', 'tools'),
    }),
    '',
  );
});

test('resolves the protocol from a standalone packaged Rust Hub layout', () => {
  const packageRoot = path.join(scratch, 'packaged', 'rust-hub-portable');
  const toolsDir = path.join(packageRoot, 'tools');
  const protocolPath = path.join(packageRoot, 'assets', 'proto', 'hub_protocol_v1.proto');
  touch(path.join(toolsDir, 'xhub_system_paths.js'));
  touch(protocolPath);
  assert.equal(resolveHubProtocolPath({ env: {}, startDir: toolsDir }), protocolPath);
});

test('the Rust Hub package includes the shared path resolver', () => {
  const packageScript = fs.readFileSync(
    path.join(path.dirname(fileURLToPath(import.meta.url)), 'package_rust_hub.command'),
    'utf8',
  );
  assert.match(
    packageScript,
    /cp "\$ROOT_DIR\/tools\/xhub_system_paths\.js" "\$DIST_DIR\/tools\/xhub_system_paths\.js"/,
  );
});
