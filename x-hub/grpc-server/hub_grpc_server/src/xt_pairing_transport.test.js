import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import test from 'node:test';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

import { startPairingHTTPServer } from './pairing_http.js';
import { ensureHubTlsMaterial } from './tls_support.js';
import { resolveHubProtoPath } from './proto_path.js';
import { HubDB } from './db.js';

const execute = promisify(execFile);
const serverRoot = fileURLToPath(new URL('..', import.meta.url));
const repoRoot = path.resolve(serverRoot, '../../..');
const terminalRoot = path.join(repoRoot, 'x-terminal');

async function listen(server, port = 0) {
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', resolve);
  });
  return server.address().port;
}

async function freePort() {
  const server = net.createServer();
  const port = await listen(server);
  await new Promise((resolve) => server.close(resolve));
  return port;
}

function readEnv(file) {
  return Object.fromEntries(fs.readFileSync(file, 'utf8').split('\n').flatMap((line) => {
    const match = line.match(/^(?:export )?([A-Z_]+)='(.*)'$/);
    return match ? [[match[1], match[2].replaceAll("'\\''", "'")]] : [];
  }));
}

test('native XT HTTPS pairing, trust failures, heartbeat, model generation and reconnect', { timeout: 180_000, skip: process.platform !== 'darwin' }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xt-secure-pairing-'));
  const runtime = path.join(root, 'hub');
  const state = path.join(root, 'xt');
  fs.mkdirSync(runtime);
  fs.mkdirSync(state);
  const previousEnvironment = { ...process.env };
  for (const key of Object.keys(process.env)) {
    if (/^(HUB_|XHUB_|AXHUB|XTERMINAL_)/.test(key)) delete process.env[key];
  }
  const port = await freePort();
  const environment = {
    HUB_RUNTIME_BASE_DIR: runtime,
    HUB_AUTH_BASE_DIR: runtime,
    HUB_CLIENTS_BASE_DIR: runtime,
    HUB_MEMORY_KEK_FILE: path.join(runtime, 'memory-kek.json'),
    HUB_GRPC_TLS_DIR: path.join(runtime, 'tls'),
    HUB_GRPC_TLS_MODE: 'tls',
    HUB_GRPC_TLS_SERVER_NAME: 'axhub',
    HUB_HOST: '127.0.0.1',
    HUB_PAIRING_ENABLE: '1',
    HUB_PAIRING_HOST: '127.0.0.1',
    HUB_PAIRING_PORT: String(port),
    HUB_PAIRING_TLS_MODE: 'tls',
    HUB_PAIRING_ALLOWED_CIDRS: 'loopback',
    HUB_PAIRING_FIRST_PAIR_ALLOWED_CIDRS: 'loopback',
    HUB_ADMIN_TOKEN: 'fixture-only-admin',
  };
  Object.assign(process.env, environment);
  let stopPairing;
  let database;
  let rpcServer;
  let redirectServer;
  let wrongHostServer;
  let contractServer;
  let plaintextServer;
  try {
    const binary = path.join(root, 'native-transport');
    await execute('xcrun', ['swiftc', '-parse-as-library', '-D', 'XT_PAIRING_TRANSPORT_REGRESSION_MAIN',
      '-module-cache-path', path.join(root, 'module-cache'),
      ...['HubPairingTransport.swift', 'HubGRPCClientSupport.swift', 'HubAccessKeysClient.swift', 'HubContractClient.swift',
        'XTProcessPaths.swift', 'XTHubProfiles.swift', 'HubPairingCoordinatorRemoteCoreScriptSources.swift']
        .map((name) => path.join(terminalRoot, 'Sources/Hub', name)),
      path.join(terminalRoot, 'Tests/HubPairingTransportRegression.swift'), '-o', binary], { timeout: 90_000 });
    const native = async (args) => (await execute(binary, args, { timeout: 15_000 })).stdout.trim();
    assert.match(await native(['policy']), /PASS/);

    const material = ensureHubTlsMaterial(runtime, { env: process.env });
    const ca = fs.readFileSync(material.paths.caCertPath);
    const serverKey = fs.readFileSync(material.paths.serverKeyPath);
    const serverCert = fs.readFileSync(material.paths.serverCertPath);
    let expectedToken = '';
    let generationCount = 0;
    const proto = grpc.loadPackageDefinition(protoLoader.loadSync(resolveHubProtoPath(process.env), {
      keepCase: true, longs: String, enums: String, defaults: true, oneofs: true,
    })).ax.hub.v1;
    const authenticated = (call) => call.metadata.get('authorization')[0] === `Bearer ${expectedToken}` && expectedToken;
    const models = [{ model_id: 'fixture-local', name: 'Fixture Local', kind: 'MODEL_KIND_LOCAL', visibility: 'MODEL_VISIBILITY_AVAILABLE' }];
    const startRPC = async (rpcPort = 0) => {
      const server = new grpc.Server();
      server.addService(proto.HubModels.service, {
        ListModels(call, callback) {
          if (!authenticated(call)) return callback({ code: grpc.status.UNAUTHENTICATED, message: 'fixture token required' });
          callback(null, { models });
        },
      });
      server.addService(proto.HubAI.service, {
        Generate(call) {
          if (!authenticated(call)) return call.destroy({ code: grpc.status.UNAUTHENTICATED, message: 'fixture token required' });
          generationCount += 1;
          call.write({ start: { request_id: call.request.request_id, model_id: 'fixture-local' } });
          call.write({ delta: { text: 'secure fixture response', seq: 1 } });
          call.write({ done: { ok: true, reason: 'eos', actual_model_id: 'fixture-local', execution_path: 'fixture', usage: { total_tokens: 3 } } });
          call.end();
        },
      });
      const bound = await new Promise((resolve, reject) => server.bindAsync(`127.0.0.1:${rpcPort}`,
        grpc.ServerCredentials.createSsl(null, [{ private_key: serverKey, cert_chain: serverCert }], false),
        (error, value) => error ? reject(error) : resolve(value)));
      rpcServer = server;
      return bound;
    };
    const grpcPort = await startRPC();
    process.env.HUB_PORT = String(grpcPort);
    contractServer = http.createServer((request, response) => {
      response.setHeader('Content-Type', 'application/json');
      response.end(JSON.stringify({ schema_version: 'xhub.rust_hub.xt_contract.v1', ok: true,
        hub_product: {}, transport_security: {}, xt_update_rule: {},
        capabilities: { remote_entry: {}, models: {}, provider_route: {}, memory: {}, skills: {}, grants: {}, audit: {} },
      }));
    });
    process.env.XHUB_RUST_HUB_HTTP_BASE_URL = `http://127.0.0.1:${await listen(contractServer)}`;
    database = new HubDB({ dbPath: path.join(runtime, 'hub.sqlite') });
    stopPairing = startPairingHTTPServer({ db: database });
    const httpsBase = `https://127.0.0.1:${port}`;
    const controlRequest = (requestPath, method = 'GET', body) => new Promise((resolve, reject) => {
      const request = https.request(`${httpsBase}${requestPath}`, {
        method, ca, agent: false, headers: { authorization: 'Bearer fixture-only-admin', 'content-type': 'application/json' },
      }, (response) => {
        let text = '';
        response.on('data', (chunk) => { text += chunk; });
        response.on('end', () => resolve({ status: response.statusCode, json: JSON.parse(text) }));
      });
      request.on('error', reject);
      request.setTimeout(3000, () => request.destroy(new Error('fixture request timeout')));
      request.end(body === undefined ? undefined : JSON.stringify(body));
    });
    const transportFile = path.join(state, 'pairing-transport.env');
    fs.writeFileSync(transportFile, `export HUB_PAIRING_SCHEME='https'\nexport HUB_PAIRING_CA_CERT_PATH='${material.paths.caCertPath}'\n`);
    const request = async (url, profile = state, token) => native(['request', url, profile, ...(token ? [token] : [])]);
    const discovery = JSON.parse(await request(`${httpsBase}/pairing/discovery`));
    assert.equal(discovery.status, 200);
    assert.equal(JSON.parse(discovery.body).grpc_port, grpcPort);
    assert.equal(await request(`http://192.0.2.1:${port}/clients/presence`, state, 'never-send'), 'REQUEST_REJECTED');
    const untrusted = path.join(root, 'untrusted');
    fs.mkdirSync(untrusted);
    assert.equal(await request(`${httpsBase}/health`, untrusted), 'REQUEST_REJECTED');
    const malformed = path.join(root, 'malformed');
    fs.mkdirSync(malformed);
    fs.writeFileSync(path.join(malformed, 'bad.pem'), 'not a certificate');
    fs.writeFileSync(path.join(malformed, 'pairing-transport.env'), `HUB_PAIRING_CA_CERT_PATH='${malformed}/bad.pem'\n`);
    assert.equal(await request(`${httpsBase}/health`, malformed), 'REQUEST_REJECTED');
    fs.writeFileSync(path.join(malformed, 'pairing-transport.env'), `HUB_PAIRING_CA_CERT_PATH='${root}/missing.pem'\n`);
    assert.equal(await request(`${httpsBase}/health`, malformed), 'REQUEST_REJECTED');

    plaintextServer = http.createServer((request, response) => response.end('{}'));
    const plaintextPort = await listen(plaintextServer);
    assert.equal(JSON.parse(await request(`http://127.0.0.1:${plaintextPort}/health`, untrusted)).status, 200);
    assert.equal(await request(`http://127.0.0.1:${plaintextPort}/health`, state), 'REQUEST_REJECTED');

    let redirectedRequests = 0;
    redirectServer = https.createServer({ key: serverKey, cert: serverCert }, (request, response) => {
      if (request.url === '/sink') redirectedRequests += 1;
      response.writeHead(307, { Location: request.url === '/downgrade'
        ? `http://127.0.0.1:${plaintextPort}/sink`
        : `https://127.0.0.1:${redirectServer.address().port}/sink` });
      response.end();
    });
    const redirectPort = await listen(redirectServer);
    const redirect = JSON.parse(await request(`https://127.0.0.1:${redirectPort}/start`, state, 'never-forward'));
    assert.equal(redirect.status, 307);
    assert.equal(redirectedRequests, 0);
    assert.equal(JSON.parse(await request(`https://127.0.0.1:${redirectPort}/downgrade`, state, 'never-forward')).status, 307);
    const wrongKey = path.join(root, 'wrong.key.pem');
    const wrongCSR = path.join(root, 'wrong.csr.pem');
    const wrongCert = path.join(root, 'wrong.cert.pem');
    const wrongExt = path.join(root, 'wrong.ext');
    fs.writeFileSync(wrongExt, 'subjectAltName=DNS:not-the-hub.invalid\nextendedKeyUsage=serverAuth\n');
    await execute('openssl', ['req', '-new', '-newkey', 'rsa:2048', '-nodes', '-keyout', wrongKey, '-out', wrongCSR, '-subj', '/CN=not-the-hub.invalid']);
    await execute('openssl', ['x509', '-req', '-sha256', '-in', wrongCSR, '-CA', material.paths.caCertPath, '-CAkey', material.paths.caKeyPath,
      '-set_serial', '1009', '-days', '1', '-extfile', wrongExt, '-out', wrongCert]);
    wrongHostServer = https.createServer({ key: fs.readFileSync(wrongKey), cert: fs.readFileSync(wrongCert) }, (request, response) => response.end('wrong host'));
    const wrongPort = await listen(wrongHostServer);
    assert.equal(await request(`https://127.0.0.1:${wrongPort}/health`), 'REQUEST_REJECTED');

    const cliEnv = { ...process.env, AXHUBCTL_STATE_DIR: state };
    const cli = async (args) => (await execute('/bin/sh', [path.join(serverRoot, 'assets/axhubctl'), ...args], { env: cliEnv, timeout: 15_000 })).stdout;
    assert.equal((await cli(['transport-policy'])).trim(), 'pairing_https_required_v1');
    await cli(['knock', '--hub', '127.0.0.1', '--pairing-port', String(port), '--grpc-port', String(grpcPort), '--app-id', 'x_terminal', '--device-name', 'XT fixture']);
    const pairing = readEnv(path.join(state, 'pairing.env'));
    const approval = await controlRequest(`/admin/pairing/requests/${pairing.AXHUB_PAIRING_REQUEST_ID}/approve`, 'POST', {
      capabilities: ['models', 'ai.generate.local', 'hub_access_keys.manage'],
    });
    assert.equal(approval.status, 200);
    await cli(['wait', '--timeout-sec', '3']);
    const paired = readEnv(path.join(state, 'hub.env'));
    assert.equal(paired.HUB_GRPC_TLS_MODE, 'tls');
    expectedToken = paired.HUB_CLIENT_TOKEN;
    assert.ok(expectedToken);
    const presence = JSON.parse(await request(`${httpsBase}/clients/presence`, state, expectedToken));
    assert.equal(presence.status, 200);
    assert.equal(JSON.parse(presence.body).device_id, paired.HUB_DEVICE_ID);
    assert.notEqual(JSON.parse(await request(`${httpsBase}/clients/presence`, state, 'invalid-token')).status, 200);
    assert.match(await native(['access', state]), /PASS/);
    assert.match(await native(['contract', state]), /PASS/);

    const generateScript = path.join(root, 'generate.mjs');
    await native(['generator', generateScript]);
    fs.symlinkSync(path.join(serverRoot, 'node_modules'), path.join(root, 'node_modules'));
    const modelEnv = { ...cliEnv, ...paired, XTERMINAL_GEN_MODEL_ID: 'fixture-local', XTERMINAL_GEN_PROMPT_B64: Buffer.from('fixture prompt').toString('base64') };
    const generate = async (overrides = {}) => (await execute(process.execPath, [generateScript], { cwd: serverRoot, env: { ...modelEnv, ...overrides }, timeout: 15_000 })).stdout;
    const generation = JSON.parse((await generate()).trim().split('\n').at(-1));
    assert.equal(generation.ok, true);
    assert.equal(generation.text, 'secure fixture response');
    await assert.rejects(generate({ HUB_GRPC_TLS_CA_CERT_PATH: path.join(root, 'missing-ca.pem') }));
    await assert.rejects(generate({ HUB_GRPC_TLS_MODE: 'typo' }));
    await assert.rejects(generate({ HUB_GRPC_TLS_MODE: 'insecure', HUB_HOST: '192.0.2.1' }));
    const missingKit = path.join(root, 'missing-kit');
    fs.mkdirSync(path.join(missingKit, 'src'), { recursive: true });
    fs.mkdirSync(path.join(missingKit, 'protocol'), { recursive: true });
    fs.copyFileSync(path.join(repoRoot, 'protocol/hub_protocol_v1.proto'), path.join(missingKit, 'protocol/hub_protocol_v1.proto'));
    await assert.rejects(execute(process.execPath, [generateScript], { cwd: missingKit, env: modelEnv, timeout: 5000 }), (error) => {
      assert.match(error.stdout, /grpc_credentials_helper_missing/);
      return true;
    });
    fs.writeFileSync(path.join(missingKit, 'src/client_credentials.js'), "exports.makeClientCredentials = () => ({ mode: 'insecure', creds: {} });\n");
    await assert.rejects(execute(process.execPath, [generateScript], { cwd: missingKit, env: modelEnv, timeout: 5000 }), (error) => {
      assert.match(error.stdout, /grpc_credentials_mode_mismatch/);
      return true;
    });
    assert.equal(generationCount, 1);
    const clientKit = path.join(root, 'client-kit');
    fs.mkdirSync(clientKit);
    fs.symlinkSync(serverRoot, path.join(clientKit, 'hub_grpc_server'));
    cliEnv.AXHUBCTL_CLIENT_KIT_DIR = clientKit;
    cliEnv.AXHUBCTL_NODE_BIN = process.execPath;
    assert.match(await cli(['connect', '--hub', '127.0.0.1']), /Connected \(grpc\)/);
    rpcServer.forceShutdown();
    await startRPC(grpcPort);
    assert.match(await cli(['connect', '--hub', '127.0.0.1']), /Connected \(grpc\)/);
    assert.equal(JSON.parse((await generate()).trim().split('\n').at(-1)).ok, true);
    assert.equal(generationCount, 2);
    stopPairing();
    await new Promise((resolve) => setTimeout(resolve, 30));
    stopPairing = startPairingHTTPServer({ db: database });
    assert.equal(JSON.parse(await request(`${httpsBase}/clients/presence`, state, expectedToken)).status, 200);
    assert.match(fs.readFileSync(transportFile, 'utf8'), /HUB_PAIRING_CA_CERT_PATH=/);
    console.log('PASS real native TLS + Hub approval + persisted trust + authenticated heartbeat + generated gRPC script + restart/reconnect (fixture model only)');
  } finally {
    stopPairing?.();
    rpcServer?.forceShutdown();
    for (const server of [redirectServer, wrongHostServer, contractServer, plaintextServer]) {
      server?.closeAllConnections();
      if (server?.listening) await new Promise((resolve) => server.close(resolve));
    }
    database?.close();
    for (const key of Object.keys(process.env)) if (!(key in previousEnvironment)) delete process.env[key];
    Object.assign(process.env, previousEnvironment);
    await new Promise((resolve) => setTimeout(resolve, 30));
    fs.rmSync(root, { recursive: true, force: true });
  }
});
