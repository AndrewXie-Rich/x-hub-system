import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';
import { startPairingHTTPServer } from './pairing_http.js';
import { invalidateProviderKeyCache } from './provider_key_store.js';

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

function withEnv(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv)) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  const restore = () => {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  };
  try {
    const result = fn();
    if (result && typeof result.then === 'function') {
      return result.finally(restore);
    }
    restore();
    return result;
  } catch (error) {
    restore();
    throw error;
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, Number(ms || 0))));
}

function makeTempDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
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

await run('provider key admin HTTP starts OAuth and returns pollable status through Hub service', async () => {
  const runtimeBaseDir = makeTempDir('xhub-provider-key-admin-http-runtime-');
  const dbPath = path.join(makeTempDir('xhub-provider-key-admin-http-db-'), 'hub.sqlite3');
  const port = 57000 + Math.floor(Math.random() * 4000);
  const baseUrl = `http://127.0.0.1:${port}`;
  invalidateProviderKeyCache();

  await withEnv({
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_PAIRING_ENABLE: '1',
    HUB_PAIRING_HOST: '127.0.0.1',
    HUB_PAIRING_PORT: String(port),
    HUB_PAIRING_ALLOWED_CIDRS: 'any',
    HUB_HOST: '127.0.0.1',
    HUB_PORT: '50051',
    HUB_CLIENT_TOKEN: 'client-secret',
    HUB_ADMIN_TOKEN: 'admin-provider-key-http',
    HUB_GRPC_TLS_MODE: '',
    HUB_GRPC_CERT: '',
    HUB_GRPC_KEY: '',
    HUB_GRPC_CA: '',
  }, async () => {
    const db = new HubDB({ dbPath });
    const hubServices = makeServices({ db, bus: new HubEventBus() });
    const stop = startPairingHTTPServer({ db, hubServices });
    try {
      await waitForHealth(baseUrl, 3_000);
      const adminHeaders = {
        authorization: 'Bearer admin-provider-key-http',
      };

      const denied = await requestJson({
        method: 'POST',
        url: `${baseUrl}/admin/provider-keys/oauth/start`,
        body: { provider: 'codex' },
      });
      assert.equal(denied.status, 401);

      const started = await requestJson({
        method: 'POST',
        url: `${baseUrl}/admin/provider-keys/oauth/start`,
        headers: adminHeaders,
        body: { provider: 'openai' },
      });
      assert.equal(started.status, 200);
      assert.equal(started.json?.ok, true);
      assert.equal(started.json?.provider, 'codex');
      assert.match(String(started.json?.auth_url || ''), /^https:\/\/auth\.openai\.com\/oauth\/authorize\?/);
      assert.equal(started.json?.redirect_uri, 'http://localhost:1455/auth/callback');
      assert.match(String(started.json?.state || ''), /^[A-Za-z0-9_-]{20,}$/);

      const status = await requestJson({
        url: `${baseUrl}/admin/provider-keys/oauth/status?state=${encodeURIComponent(started.json.state)}`,
        headers: adminHeaders,
      });
      assert.equal(status.status, 200);
      assert.equal(status.json?.status, 'pending');

      const callback = await requestJson({
        method: 'POST',
        url: `${baseUrl}/admin/provider-keys/oauth/callback`,
        headers: adminHeaders,
        body: {
          provider: 'codex',
          state: started.json.state,
          redirect_url: `http://localhost:1455/auth/callback?state=${encodeURIComponent(started.json.state)}&error=access_denied`,
        },
      });
      assert.equal(callback.status, 400);
      assert.equal(callback.json?.ok, false);
      assert.equal(callback.json?.error, 'access_denied');

      const statusAfter = await requestJson({
        url: `${baseUrl}/admin/provider-keys/oauth/status?state=${encodeURIComponent(started.json.state)}`,
        headers: adminHeaders,
      });
      assert.equal(statusAfter.status, 200);
      assert.equal(statusAfter.json?.status, 'error');
      assert.equal(statusAfter.json?.error, 'access_denied');
    } finally {
      try { stop?.(); } catch {}
      db.close();
      await sleep(40);
    }
  });

  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
  try { fs.rmSync(path.dirname(dbPath), { recursive: true, force: true }); } catch {}
});
