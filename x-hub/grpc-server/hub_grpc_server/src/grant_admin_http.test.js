import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';
import { startPairingHTTPServer } from './pairing_http.js';

function run(name, fn) {
  try {
    const maybePromise = fn();
    if (maybePromise && typeof maybePromise.then === 'function') {
      return maybePromise.then(() => {
        process.stdout.write(`ok - ${name}\n`);
      }).catch((error) => {
        process.stderr.write(`not ok - ${name}\n`);
        throw error;
      });
    }
    process.stdout.write(`ok - ${name}\n`);
    return Promise.resolve();
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, Number(ms || 0))));
}

async function withEnv(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv || {})) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return await fn();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

function requestJson({
  method = 'GET',
  url,
  headers = {},
  body,
  timeoutMs = 2_000,
} = {}) {
  const target = new URL(String(url || ''));
  const bodyText = body === undefined ? '' : JSON.stringify(body);
  return new Promise((resolve, reject) => {
    const req = http.request({
      method: String(method || 'GET').toUpperCase(),
      hostname: target.hostname,
      port: Number(target.port || 80),
      path: `${target.pathname}${target.search}`,
      headers: {
        ...(bodyText ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(bodyText) } : {}),
        ...headers,
      },
      timeout: Math.max(100, Number(timeoutMs || 0)),
    }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        let json = null;
        try {
          json = text ? JSON.parse(text) : null;
        } catch {
          json = null;
        }
        resolve({
          status: Number(res.statusCode || 0),
          text,
          json,
        });
      });
    });
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('request_timeout')));
    if (bodyText) req.write(bodyText);
    req.end();
  });
}

async function waitForHealth(baseUrl, timeoutMs = 2_000) {
  const deadline = Date.now() + Math.max(200, Number(timeoutMs || 0));
  while (Date.now() < deadline) {
    try {
      const out = await requestJson({ url: `${baseUrl}/health`, timeoutMs: 300 });
      if (out.status === 200) return;
    } catch {
      // retry
    }
    await sleep(25);
  }
  throw new Error('pairing_server_not_ready');
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch {}
}

async function withGrantAdminServer(fn) {
  const dbDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-grant-admin-http-db-'));
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-grant-admin-http-runtime-'));
  const dbPath = path.join(dbDir, 'hub.sqlite3');
  const port = 57000 + Math.floor(Math.random() * 4000);
  const baseUrl = `http://127.0.0.1:${port}`;
  const db = new HubDB({ dbPath });
  const hubServices = makeServices({ db, bus: new HubEventBus() });

  await withEnv({
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_PAIRING_ENABLE: '1',
    HUB_PAIRING_HOST: '127.0.0.1',
    HUB_PAIRING_PORT: String(port),
    HUB_PAIRING_ALLOWED_CIDRS: 'any',
    HUB_HOST: '127.0.0.1',
    HUB_PORT: '50051',
    HUB_CLIENT_TOKEN: 'client-secret',
    HUB_ADMIN_TOKEN: 'admin-grant-http',
    HUB_GRPC_TLS_MODE: '',
    HUB_GRPC_CERT: '',
    HUB_GRPC_KEY: '',
    HUB_GRPC_CA: '',
  }, async () => {
    const stop = startPairingHTTPServer({ db, hubServices });
    try {
      await waitForHealth(baseUrl, 3_000);
      await fn({ baseUrl, db });
    } finally {
      try { stop?.(); } catch {}
      db.close();
      await sleep(40);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
      try { fs.rmSync(dbDir, { recursive: true, force: true }); } catch {}
      cleanupDbArtifacts(dbPath);
    }
  });
}

await run('grant admin HTTP requires admin token and lists pending grants', async () => {
  await withGrantAdminServer(async ({ baseUrl, db }) => {
    const created = db.createGrantRequest({
      request_id: 'req_1',
      device_id: 'dev_1',
      user_id: 'user_1',
      app_id: 'x_terminal',
      project_id: 'project_1',
      capability: 'skills.execute',
      model_id: null,
      reason: 'XT requested skill preflight approval',
      requested_ttl_sec: 900,
      requested_token_cap: 0,
    });

    const denied = await requestJson({
      url: `${baseUrl}/admin/grant-requests?status=pending`,
    });
    assert.equal(denied.status, 401);
    assert.equal(String(denied.json?.error?.code || ''), 'unauthenticated');

    const listed = await requestJson({
      url: `${baseUrl}/admin/grant-requests?status=pending&project_id=project_1`,
      headers: { authorization: 'Bearer admin-grant-http' },
    });
    assert.equal(listed.status, 200);
    assert.equal(listed.json?.ok, true);
    assert.equal(listed.json?.requests?.length, 1);
    assert.equal(listed.json.requests[0].grant_request_id, created.grant_request_id);
    assert.equal(listed.json.requests[0].capability, 'skills.execute');
    assert.equal(listed.json.requests[0].client.device_id, 'dev_1');
  });
});

await run('grant admin HTTP approve and deny delegate to Hub grant authority', async () => {
  await withGrantAdminServer(async ({ baseUrl, db }) => {
    const approveTarget = db.createGrantRequest({
      request_id: 'req_approve',
      device_id: 'dev_approve',
      user_id: 'user_1',
      app_id: 'x_terminal',
      project_id: 'project_1',
      capability: 'skills.execute',
      model_id: null,
      reason: 'approve this skill lease',
      requested_ttl_sec: 1200,
      requested_token_cap: 0,
    });
    const denyTarget = db.createGrantRequest({
      request_id: 'req_deny',
      device_id: 'dev_deny',
      user_id: 'user_1',
      app_id: 'x_terminal',
      project_id: 'project_1',
      capability: 'web.fetch',
      model_id: null,
      reason: 'deny this fetch lease',
      requested_ttl_sec: 1200,
      requested_token_cap: 0,
    });
    const headers = { authorization: 'Bearer admin-grant-http' };

    const approved = await requestJson({
      method: 'POST',
      url: `${baseUrl}/admin/grant-requests/${approveTarget.grant_request_id}/approve`,
      headers,
      body: { ttl_sec: 600, note: 'approved from Hub Inbox' },
    });
    assert.equal(approved.status, 200);
    assert.equal(approved.json?.ok, true);
    assert.equal(approved.json?.status, 'approved');
    assert.equal(approved.json?.grant?.status, 'active');
    assert.equal(db.getGrantRequest(approveTarget.grant_request_id).status, 'approved');

    const denied = await requestJson({
      method: 'POST',
      url: `${baseUrl}/admin/grant-requests/${denyTarget.grant_request_id}/deny`,
      headers,
      body: { reason: 'too risky' },
    });
    assert.equal(denied.status, 200);
    assert.equal(denied.json?.ok, true);
    assert.equal(denied.json?.status, 'denied');
    const deniedRow = db.getGrantRequest(denyTarget.grant_request_id);
    assert.equal(deniedRow.status, 'denied');
    assert.equal(deniedRow.deny_reason, 'too risky');

    const listed = await requestJson({
      url: `${baseUrl}/admin/grant-requests?status=pending&project_id=project_1`,
      headers,
    });
    assert.equal(listed.status, 200);
    assert.equal(listed.json?.requests?.length, 0);
  });
});
