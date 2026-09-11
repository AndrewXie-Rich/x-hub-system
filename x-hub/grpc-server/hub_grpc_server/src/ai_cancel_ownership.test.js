import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { EventEmitter } from 'node:events';

import { writeClientsSnapshot } from './clients.js';
import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';

function makeCall(token, request) {
  const call = new EventEmitter();
  call.request = request;
  call.metadata = { get: (key) => key === 'authorization' ? [`Bearer ${token}`] : [] };
  call.getPeer = () => 'ipv4:127.0.0.1:12345';
  call.sendMetadata = () => {};
  call.writes = [];
  call.write = (value) => call.writes.push(value);
  call.end = () => { call.ended = true; };
  return call;
}

function cancel(services, token, requestId) {
  return new Promise((resolve) => {
    services.HubAI.Cancel(makeCall(token, { request_id: requestId }), (error, response) => resolve({ error, response }));
  });
}

test('AI cancellation requires the authenticated owner and an active unique request', async () => {
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-cancel-ownership-'));
  const environment = {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_AUTH_BASE_DIR: runtimeBaseDir,
    HUB_CLIENTS_BASE_DIR: runtimeBaseDir,
    HUB_GRPC_TLS_MODE: 'tls',
    HUB_MLX_RESPONSE_TIMEOUT_MS: '2000',
    HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS: '2000',
  };
  const previous = Object.fromEntries(Object.keys(environment).map((key) => [key, process.env[key]]));
  Object.assign(process.env, environment);
  const db = new HubDB({ dbPath: path.join(runtimeBaseDir, 'hub.sqlite3') });
  let pending;
  try {
    writeClientsSnapshot(runtimeBaseDir, {
      clients: ['owner', 'other'].map((name) => ({
        device_id: `${name}-device`,
        user_id: 'shared-user',
        token: `${name}-token`,
        capabilities: ['models', 'ai.generate.local'],
      })),
    });
    fs.writeFileSync(path.join(runtimeBaseDir, 'models_state.json'), JSON.stringify({
      updatedAt: Date.now() / 1000,
      models: [{ id: 'test-local', name: 'Test Local', backend: 'mlx', state: 'available', taskKinds: ['text_generate'] }],
    }));
    const services = makeServices({ db, bus: new HubEventBus() });
    const requestId = 'owned-request';
    const cancelFile = path.join(runtimeBaseDir, 'ai_cancels', `cancel_${requestId}.json`);
    const request = {
      request_id: requestId,
      model_id: 'test-local',
      max_tokens: 1,
      messages: [{ role: 'user', content: 'Test cancellation' }],
      client: { device_id: 'forged-device', user_id: 'forged-user', project_id: 'project-owner', app_id: 'cancel-test' },
    };
    const ownerCall = makeCall('owner-token', request);
    pending = services.HubAI.Generate(ownerCall);
    for (let attempt = 0; attempt < 50; attempt += 1) {
      if (fs.existsSync(path.join(runtimeBaseDir, 'ai_requests', `req_${requestId}.json`)) || ownerCall.ended) break;
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    assert.notEqual(ownerCall.ended, true, JSON.stringify(ownerCall.writes));

    const duplicateCall = makeCall('other-token', { ...request, model_id: 'nonexistent-model' });
    await services.HubAI.Generate(duplicateCall);
    assert.equal(duplicateCall.writes[0]?.error?.error?.code, 'request_id_in_use');

    const other = await cancel(services, 'other-token', requestId);
    assert.equal(other.error?.code, 7);
    assert.equal(fs.existsSync(cancelFile), false);

    const unknown = await cancel(services, 'owner-token', 'unknown-request');
    assert.equal(unknown.error?.code, 7);
    assert.equal(fs.existsSync(path.join(runtimeBaseDir, 'ai_cancels', 'cancel_unknown-request.json')), false);

    const appendAudit = db.appendAudit.bind(db);
    db.appendAudit = () => { throw new Error('audit unavailable'); };
    const auditFailure = await cancel(services, 'owner-token', requestId);
    assert.equal(auditFailure.error?.code, 13);
    assert.equal(fs.existsSync(cancelFile), false);
    db.appendAudit = appendAudit;

    const owner = await cancel(services, 'owner-token', requestId);
    assert.equal(owner.error, null);
    assert.equal(owner.response?.ok, true);
    assert.equal(fs.existsSync(cancelFile), true);
    await pending;

    const stale = await cancel(services, 'owner-token', requestId);
    assert.equal(stale.error?.code, 7);
    const audit = db.db.prepare('SELECT device_id, project_id FROM audit_events WHERE event_type = ?').get('ai.cancel.requested');
    assert.equal(audit.device_id, 'owner-device');
    assert.equal(audit.project_id, 'project-owner');
  } finally {
    await pending;
    db.close();
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
  }
});
