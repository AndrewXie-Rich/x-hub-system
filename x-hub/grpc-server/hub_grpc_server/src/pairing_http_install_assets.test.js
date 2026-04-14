import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';

import { startPairingHTTPServer } from './pairing_http.js';

function runAsync(name, fn) {
  return fn().then(
    () => process.stdout.write(`ok - ${name}\n`),
    (err) => {
      process.stderr.write(`not ok - ${name}\n`);
      throw err;
    }
  );
}

async function withEnvAsync(tempEnv, fn) {
  const prev = new Map();
  for (const key of Object.keys(tempEnv || {})) {
    prev.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return await fn();
  } finally {
    for (const [key, val] of prev.entries()) {
      if (val == null) delete process.env[key];
      else process.env[key] = val;
    }
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, Number(ms || 0))));
}

function sha256Hex(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

function requestRaw({
  method = 'GET',
  url,
  headers = {},
  timeout_ms = 2_000,
} = {}) {
  const target = new URL(String(url || ''));
  return new Promise((resolve, reject) => {
    const req = http.request({
      method: String(method || 'GET').toUpperCase(),
      hostname: target.hostname,
      port: Number(target.port || 80),
      path: `${target.pathname}${target.search}`,
      headers,
      timeout: Math.max(100, Number(timeout_ms || 0)),
    }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      res.on('end', () => {
        const body = Buffer.concat(chunks);
        resolve({
          status: Number(res.statusCode || 0),
          headers: res.headers || {},
          body,
          text: body.toString('utf8'),
        });
      });
    });
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('request_timeout')));
    req.end();
  });
}

async function waitForHealth(baseUrl, timeoutMs = 2_000) {
  const deadline = Date.now() + Math.max(200, Number(timeoutMs || 0));
  while (Date.now() < deadline) {
    try {
      const out = await requestRaw({ url: `${baseUrl}/health`, timeout_ms: 300 });
      if (out.status === 200) return;
    } catch {
      // retry
    }
    await sleep(25);
  }
  throw new Error('pairing_server_not_ready');
}

async function withPairingServer(env, fn) {
  const port = 56000 + Math.floor(Math.random() * 6000);
  const baseUrl = `http://127.0.0.1:${port}`;
  await withEnvAsync({
    HUB_PAIRING_ENABLE: '1',
    HUB_PAIRING_HOST: '127.0.0.1',
    HUB_PAIRING_PORT: String(port),
    HUB_HOST: '127.0.0.1',
    HUB_PORT: '50051',
    HUB_PAIRING_ALLOWED_CIDRS: 'any',
    ...env,
  }, async () => {
    const stop = startPairingHTTPServer({ db: { appendAudit() {} } });
    try {
      await waitForHealth(baseUrl, 3_000);
      await fn({ baseUrl });
    } finally {
      try {
        stop?.();
      } catch {
        // ignore
      }
      await sleep(40);
    }
  });
}

await runAsync('client kit install asset metadata refreshes after the tgz changes', async () => {
  const runtimeDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pairing_http_install_assets_'));
  const assetPath = path.join(runtimeDir, 'axhub_client_kit.tgz');
  const firstBytes = Buffer.from('client-kit-v1-abcd');
  const secondBytes = Buffer.from('client-kit-v2-wxyz');
  assert.equal(firstBytes.length, secondBytes.length);
  fs.writeFileSync(assetPath, firstBytes);

  await withPairingServer({
    HUB_PAIRING_CLIENT_KIT_ASSET_PATH: assetPath,
  }, async ({ baseUrl }) => {
    const firstManifest = await requestRaw({ url: `${baseUrl}/install/axhub_client_kit.json` });
    assert.equal(firstManifest.status, 200);
    const firstManifestJson = JSON.parse(firstManifest.text);
    assert.equal(String(firstManifestJson.sha256 || ''), sha256Hex(firstBytes));

    const firstDownload = await requestRaw({ url: `${baseUrl}/install/axhub_client_kit.tgz` });
    assert.equal(firstDownload.status, 200);
    assert.equal(sha256Hex(firstDownload.body), sha256Hex(firstBytes));

    await sleep(25);
    fs.writeFileSync(assetPath, secondBytes);

    const secondManifest = await requestRaw({ url: `${baseUrl}/install/axhub_client_kit.json` });
    assert.equal(secondManifest.status, 200);
    const secondManifestJson = JSON.parse(secondManifest.text);
    assert.equal(String(secondManifestJson.sha256 || ''), sha256Hex(secondBytes));
    assert.notEqual(String(secondManifestJson.sha256 || ''), String(firstManifestJson.sha256 || ''));

    const secondShaText = await requestRaw({ url: `${baseUrl}/install/axhub_client_kit.tgz.sha256` });
    assert.equal(secondShaText.status, 200);
    assert.ok(secondShaText.text.startsWith(`${sha256Hex(secondBytes)}  axhub_client_kit.tgz`));

    const secondDownload = await requestRaw({ url: `${baseUrl}/install/axhub_client_kit.tgz` });
    assert.equal(secondDownload.status, 200);
    assert.equal(sha256Hex(secondDownload.body), sha256Hex(secondBytes));
  });
});
