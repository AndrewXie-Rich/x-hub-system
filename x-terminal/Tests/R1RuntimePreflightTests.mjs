import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { buildProvenance, sourceTree } from '../tools/build_provenance.mjs';
import { parseArguments, probeDiscovery } from '../scripts/r1_runtime_preflight.mjs';

function temporaryDirectory(context) {
  const directory = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'xt-r1-preflight-test-')));
  fs.chmodSync(directory, 0o700);
  context.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}

test('preflight accepts only an isolated profile and a discovery URL', (context) => {
  const profile = temporaryDirectory(context);
  const options = parseArguments([
    '--profile-root', profile,
    '--report', '/tmp/xt-r1-preflight-report.json',
  ]);
  assert.equal(options.pairingURL, 'http://127.0.0.1:50052/pairing/discovery');
  for (const args of [
    ['--profile-root', profile, '--report', '/tmp/report.json', '--pairing-url', 'http://192.0.2.1:50052/pairing/discovery'],
    ['--profile-root', profile, '--report', '/tmp/report.json', '--pairing-url', 'http://127.0.0.1:50052/redirect'],
    ['--profile-root', profile, '--report', '/tmp/report.json', '--pairing-url', 'https://127.0.0.1:50052/pairing/discovery?debug=1'],
    ['--profile-root', profile, '--report', '/tmp/report.json', '--timeout-ms', '20'],
  ]) assert.throws(() => parseArguments(args));
});

test('provenance binds the source tree and binary without storing source content', (context) => {
  const root = temporaryDirectory(context);
  const source = path.join(root, 'source');
  const binary = path.join(root, 'XTerminal');
  fs.mkdirSync(path.join(source, 'Sources'), { recursive: true });
  fs.writeFileSync(path.join(source, 'Package.swift'), 'let package = true\n');
  fs.writeFileSync(path.join(source, 'Sources', 'Main.swift'), 'print("ok")\n');
  fs.writeFileSync(binary, 'binary\n');
  const tree = sourceTree(source);
  const provenance = buildProvenance({ sourceRoot: source, binary, configuration: 'debug' });
  assert.equal(provenance.source.source_tree_sha256, tree.sha256);
  assert.equal(provenance.binary.sha256.length, 64);
  assert.equal(provenance.verification.secrets_included, false);
  assert.equal(JSON.stringify(provenance).includes('print("ok")'), false);
});

test('discovery probe refuses redirects and validates the actual pairing contract', async (context) => {
  const server = http.createServer((request, response) => {
    if (request.url === '/redirect') {
      response.writeHead(302, { location: '/pairing/discovery' });
      response.end();
      return;
    }
    response.setHeader('content-type', 'application/json');
    response.end(JSON.stringify({
      ok: true,
      service: 'pairing',
      version: 'pairing.v1',
      pairing_enabled: true,
      pairing_port: server.address().port,
      grpc_port: 50051,
      hub_instance_id: 'test-hub-instance',
      pairing_profile_epoch: 2,
      route_pack_version: 'v1',
      now_ms: Date.now(),
    }));
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  context.after(() => server.close());
  const port = server.address().port;
  const good = await probeDiscovery(`http://127.0.0.1:${port}/pairing/discovery`, 1_000);
  assert.equal(good.status, 'pass');
  assert.equal(good.payload.pairing_port, port);
  assert.equal(good.payload.hub_instance_id_sha256.length, 64);
  const redirect = await probeDiscovery(`http://127.0.0.1:${port}/redirect`, 1_000);
  assert.deepEqual(redirect, { status: 'blocked', reason_code: 'discovery_redirect_refused' });
});

test('discovery probe enforces an absolute deadline when a peer drips bytes', async (context) => {
  const server = http.createServer((_request, response) => {
    response.writeHead(200, { 'content-type': 'application/json' });
    response.write('{"ok":');
    const interval = setInterval(() => response.write(' '), 20);
    response.on('close', () => clearInterval(interval));
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  context.after(() => server.close());
  const port = server.address().port;
  const result = await probeDiscovery(`http://127.0.0.1:${port}/pairing/discovery`, 100);
  assert.deepEqual(result, { status: 'blocked', reason_code: 'hub_discovery_timeout' });
});
