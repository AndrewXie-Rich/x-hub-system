import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { EventEmitter } from 'node:events';

import { HubDB } from './db.js';
import { writeClientsSnapshot, invalidateClientsCache } from './clients.js';
import { reserveDelegatedGenerationBudget } from './access_key_budget.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';

function budgetFixture(context, { daily = 100, childDaily = daily, single = 1000 } = {}) {
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-delegated-budget-'));
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
  const fixture = {
    runtimeBaseDir,
    day: new Date().toISOString().slice(0, 10),
    db: new HubDB({ dbPath: path.join(runtimeBaseDir, 'hub.sqlite3') }),
    pending: [],
    calls: [],
  };
  context.after(async () => {
    for (const call of fixture.calls) {
      if (!call.ended) call.emit('cancelled');
    }
    await Promise.allSettled(fixture.pending);
    fixture.db.close();
    invalidateClientsCache();
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
  });
  const expires = Date.now() + 86_400_000;
  const profile = (deviceId, dailyLimit) => ({
    schema_version: 'hub.paired_terminal_trust_profile.v1',
    device_id: deviceId,
    capabilities: ['models', 'ai.generate.local'],
    paid_model_policy: { mode: 'off', allowed_model_ids: [] },
    network_policy: { default_web_fetch_enabled: false },
    budget_policy: { daily_token_limit: dailyLimit, single_request_token_limit: single },
    mode: 'standard',
    allowed_project_ids: [],
    allowed_workspace_roots: [],
    xt_binding_required: false,
  });
  fixture.snapshot = {
    clients: [
      {
        access_key_id: 'hak_parent', auth_kind: 'hub_access_key', device_id: 'parent-device', user_id: 'owner',
        app_id: 'x_terminal', token: 'parent-token', enabled: true, scopes: ['models', 'ai.generate.local', 'hub_access_keys.manage'],
        capabilities: ['models', 'ai.generate.local'], allowed_cidrs: ['any'], expires_at_ms: expires,
        policy_mode: 'new_profile', approved_trust_profile: profile('parent-device', daily),
      },
      {
        access_key_id: 'hak_child', auth_kind: 'hub_access_key', device_id: 'child-device', user_id: 'owner',
        app_id: 'external_terminal', token: 'child-token', enabled: true, scopes: ['models', 'ai.generate.local'],
        capabilities: ['models', 'ai.generate.local'], allowed_cidrs: ['any'], expires_at_ms: expires,
        created_by_user_id: 'owner', managed_by_access_key_id: 'hak_parent', managed_by_device_id: 'parent-device',
        policy_mode: 'new_profile', approved_trust_profile: profile('child-device', childDaily),
      },
    ],
  };
  fixture.save = () => {
    writeClientsSnapshot(runtimeBaseDir, fixture.snapshot);
    invalidateClientsCache();
  };
  fixture.save();
  fs.writeFileSync(path.join(runtimeBaseDir, 'models_state.json'), JSON.stringify({
    updatedAt: Date.now() / 1000,
    models: [{ id: 'test-local', name: 'Test Local', backend: 'mlx', state: 'available', taskKinds: ['text_generate'] }],
  }));
  fixture.createServices = (options = {}) => makeServices({
    db: fixture.db,
    bus: new HubEventBus(),
    rustLocalMlExecutionBridge: { config: { enabled: false } },
    ...options,
  });
  fixture.reserve = (overrides = {}) => reserveDelegatedGenerationBudget({
    db: fixture.db, runtimeBaseDir, auth: { access_key_id: 'hak_child' }, prompt: 'hello', maxTokens: 1, ...overrides,
  });
  fixture.used = (scope) => fixture.db.getQuotaUsageDaily(scope, fixture.day);
  fixture.rows = () => fixture.db.db.prepare('SELECT scope, day, token_used FROM quota_usage_daily ORDER BY scope, day').all();
  return fixture;
}

function startGenerate(fixture, services, token, requestId, overrides = {}) {
  const call = new EventEmitter();
  call.request = {
    request_id: requestId,
    model_id: 'test-local',
    max_tokens: 1,
    messages: [{ role: 'user', content: 'hello' }],
    created_at_ms: Date.parse('2000-01-01T00:00:00.000Z'),
    client: { device_id: 'forged-device', user_id: 'forged-user', app_id: 'budget-test' },
    ...overrides,
  };
  call.metadata = { get: (key) => key === 'authorization' ? [`Bearer ${token}`] : [] };
  call.getPeer = () => 'ipv4:127.0.0.1:12345';
  call.sendMetadata = () => {};
  call.writes = [];
  call.write = (value) => call.writes.push(value);
  call.end = () => { call.ended = true; };
  call.on('error', (error) => { call.authError = error; });
  fixture.calls.push(call);
  const pending = services.HubAI.Generate(call);
  fixture.pending.push(pending);
  return { call, pending, requestId };
}

function requestPath(fixture, run) {
  return path.join(fixture.runtimeBaseDir, 'ai_requests', `req_${run.requestId}.json`);
}

async function awaitDispatch(fixture, run) {
  const deadline = Date.now() + 1500;
  while (!fs.existsSync(requestPath(fixture, run)) && !run.call.ended && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  assert.equal(fs.existsSync(requestPath(fixture, run)), true, JSON.stringify(run.call.writes));
  return JSON.parse(fs.readFileSync(requestPath(fixture, run), 'utf8'));
}

async function completeGenerate(fixture, run, { ok = true, reason = 'eos' } = {}) {
  await awaitDispatch(fixture, run);
  const events = [
    { type: 'start', model_id: 'test-local' },
    ...(ok ? [{ type: 'delta', text: 'ok', seq: 1 }] : []),
    { type: 'done', ok, reason, prompt_tokens: 5, completion_tokens: 1 },
  ];
  fs.writeFileSync(path.join(fixture.runtimeBaseDir, 'ai_responses', `resp_${run.requestId}.jsonl`),
    events.map((event) => JSON.stringify(event)).join('\n') + '\n');
  await run.pending;
  assert.equal(run.call.ended, true);
  const done = run.call.writes.find((event) => event.done)?.done;
  assert.equal(done?.ok, ok, JSON.stringify(run.call.writes));
  return done;
}

function assertBudgetDenied(fixture, run, code = 'delegation_quota_exceeded') {
  assert.equal(run.call.ended, true, JSON.stringify(run.call.writes));
  assert.equal(run.call.writes.find((event) => event.error)?.error?.error?.code, code, JSON.stringify(run.call.writes));
  assert.equal(fs.existsSync(requestPath(fixture, run)), false);
}

test('delegated reservations validate output limits and UTF-8 input before writing usage', (context) => {
  const fixture = budgetFixture(context, { single: 100 });
  for (const maxTokens of [0, -1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER, '1']) {
    assert.deepEqual(fixture.reserve({ maxTokens }), { ok: false, code: 'delegation_quota_exceeded' });
  }
  assert.deepEqual(fixture.reserve({ prompt: '中'.repeat(12) }), { ok: false, code: 'delegation_quota_exceeded' });
  assert.equal(fixture.rows().length, 0);
  assert.equal(fixture.reserve({ prompt: '中'.repeat(11) }).reserved, 98);
  assert.deepEqual(fixture.reserve({ auth: { access_key_id: 'hak_parent' } }), { ok: false, code: 'delegation_quota_exceeded' });
});

test('both quota limits roll back together across database connections', (context) => {
  const fixture = budgetFixture(context);
  const secondDb = new HubDB({ dbPath: path.join(fixture.runtimeBaseDir, 'hub.sqlite3') });
  context.after(() => secondDb.close());
  const reservation = {
    day: fixture.day, group_scope: 'delegation:parent', group_cap: 100,
    key_scope: 'delegation-key:first', key_cap: 50, amount: 40,
  };
  assert.equal(fixture.db.tryReserveDelegatedQuotaDaily(reservation).ok, true);
  const initial = fixture.rows();
  assert.equal(secondDb.tryReserveDelegatedQuotaDaily({ ...reservation, amount: 20 }).code, 'delegation_quota_exceeded');
  assert.deepEqual(fixture.rows(), initial);
  assert.equal(secondDb.tryReserveDelegatedQuotaDaily({ ...reservation, key_scope: 'delegation-key:second', key_cap: 100, amount: 61 }).code, 'delegation_quota_exceeded');
  assert.deepEqual(fixture.rows(), initial);
  assert.equal(secondDb.tryReserveDelegatedQuotaDaily({ ...reservation, key_scope: 'delegation-key:second', key_cap: 100, amount: 60 }).ok, true);
  assert.equal(fixture.used('delegation:parent'), 100);
  assert.equal(fixture.used('delegation-key:first'), 40);
  assert.equal(fixture.used('delegation-key:second'), 60);
});

test('legacy usage is a baseline, not an additional charge for completed reserved calls', (context) => {
  const fixture = budgetFixture(context, { daily: 240, childDaily: 200 });
  fixture.db.addQuotaUsageDaily('device:parent-device', fixture.day, 30);
  fixture.db.addQuotaUsageDaily('device:child-device', fixture.day, 20);
  assert.equal(fixture.reserve().reserved, 70);
  assert.equal(fixture.used('delegation:hak_parent'), 120);
  assert.equal(fixture.used('delegation-key:hak_child'), 90);
  fixture.db.addQuotaUsageDaily('device:child-device', fixture.day, 6);
  assert.equal(fixture.reserve().reserved, 70);
  assert.equal(fixture.used('delegation:hak_parent'), 190);
  assert.equal(fixture.used('delegation-key:hak_child'), 160);
  const before = fixture.rows();
  assert.equal(fixture.reserve().code, 'delegation_quota_exceeded');
  assert.deepEqual(fixture.rows(), before);
});

test('quota storage failures roll back partial writes and fail closed at Generate', async (context) => {
  const fixture = budgetFixture(context);
  fixture.db.db.exec(`CREATE TRIGGER reject_delegated_key_write BEFORE INSERT ON quota_usage_daily
    WHEN NEW.scope LIKE 'delegation-key:%' BEGIN SELECT RAISE(ABORT, 'fixture_storage_failure'); END`);
  assert.equal(fixture.reserve().code, 'delegation_budget_unavailable');
  assert.equal(fixture.rows().length, 0);
  const run = startGenerate(fixture, fixture.createServices(), 'child-token', 'storage-failure');
  await run.pending;
  assertBudgetDenied(fixture, run, 'delegation_budget_unavailable');
  assert.equal(fixture.rows().length, 0);
});

test('actual Generate records authenticated usage on the server day without double charging reservations', async (context) => {
  const fixture = budgetFixture(context, { daily: 152 });
  const services = fixture.createServices();
  const childRun = startGenerate(fixture, services, 'child-token', 'successful-child');
  const request = await awaitDispatch(fixture, childRun);
  const reserved = Buffer.byteLength(request.prompt, 'utf8') + request.max_tokens + 64;
  assert.equal(reserved, 76);
  assert.equal((await completeGenerate(fixture, childRun)).usage.total_tokens, 6);
  assert.equal(fixture.used('delegation:hak_parent'), reserved);
  assert.equal(fixture.used('device:child-device'), 6);
  assert.equal(fixture.used('device:forged-device'), 0);
  assert.equal(fixture.db.getQuotaUsageDaily('device:child-device', '2000-01-01'), 0);
  const audit = fixture.db.db.prepare('SELECT device_id, user_id, total_tokens FROM audit_events WHERE request_id = ? AND event_type = ?')
    .get(childRun.requestId, 'ai.generate.completed');
  assert.equal(audit.device_id, 'child-device');
  assert.equal(audit.user_id, 'owner');
  assert.equal(audit.total_tokens, 6);

  const parentRun = startGenerate(fixture, services, 'parent-token', 'successful-parent');
  await completeGenerate(fixture, parentRun);
  assert.equal(fixture.used('delegation:hak_parent'), 152);
  assert.equal(fixture.used('device:parent-device'), 6);
  const exceeded = startGenerate(fixture, services, 'child-token', 'third-denied');
  await exceeded.pending;
  assertBudgetDenied(fixture, exceeded);
  assert.equal(fixture.used('delegation:hak_parent'), 152);
});

test('in-flight parent and child Generate calls cannot both spend the remaining group budget', async (context) => {
  const fixture = budgetFixture(context);
  const services = fixture.createServices();
  const childRun = startGenerate(fixture, services, 'child-token', 'concurrent-child');
  await awaitDispatch(fixture, childRun);
  assert.notEqual(childRun.call.ended, true);
  const parentRun = startGenerate(fixture, services, 'parent-token', 'concurrent-parent');
  await parentRun.pending;
  assertBudgetDenied(fixture, parentRun);
  assert.equal(fixture.used('delegation:hak_parent'), 76);
  assert.equal(fixture.used('device:child-device'), 0);
  await completeGenerate(fixture, childRun);
});

test('rotation, replacement children, and reopened services cannot reset the shared daily budget', async (context) => {
  const fixture = budgetFixture(context);
  let services = fixture.createServices();
  const first = startGenerate(fixture, services, 'child-token', 'before-restart');
  await completeGenerate(fixture, first);
  fixture.snapshot.clients[1].token = 'rotated-child-token';
  fixture.save();
  fixture.db.close();
  fixture.db = new HubDB({ dbPath: path.join(fixture.runtimeBaseDir, 'hub.sqlite3') });
  services = fixture.createServices();
  const rotated = startGenerate(fixture, services, 'rotated-child-token', 'after-rotation');
  await rotated.pending;
  assertBudgetDenied(fixture, rotated);
  const oldToken = startGenerate(fixture, services, 'child-token', 'old-token');
  await oldToken.pending;
  assert.equal(oldToken.call.ended, true);
  assert.deepEqual(oldToken.call.writes, []);
  assert.equal(fs.existsSync(requestPath(fixture, oldToken)), false);
  fixture.snapshot.clients[1].access_key_id = 'hak_replacement';
  fixture.snapshot.clients[1].device_id = 'replacement-device';
  fixture.snapshot.clients[1].approved_trust_profile.device_id = 'replacement-device';
  fixture.snapshot.clients[1].token = 'replacement-token';
  fixture.save();
  const replacement = startGenerate(fixture, services, 'replacement-token', 'replacement-child');
  await replacement.pending;
  assertBudgetDenied(fixture, replacement);
  assert.equal(fixture.used('delegation:hak_parent'), 76);
  assert.equal(fixture.used('delegation-key:hak_replacement'), 0);
});

test('failed and canceled Generate calls retain dispatched reservations', async (context) => {
  for (const outcome of ['failed', 'canceled']) {
    await context.test(outcome, async (childContext) => {
      const fixture = budgetFixture(childContext);
      const services = fixture.createServices();
      const run = startGenerate(fixture, services, 'child-token', `retained-${outcome}`);
      await awaitDispatch(fixture, run);
      if (outcome === 'canceled') {
        run.call.emit('cancelled');
        await run.pending;
        assert.equal(run.call.writes.find((event) => event.done)?.done?.reason, 'canceled');
      } else {
        await completeGenerate(fixture, run, { ok: false, reason: 'fixture_failure' });
      }
      assert.equal(fixture.used('delegation:hak_parent'), 76);
      assert.equal(fixture.used('device:child-device'), 0);
      const denied = startGenerate(fixture, services, 'parent-token', `retry-${outcome}`);
      await denied.pending;
      assertBudgetDenied(fixture, denied);
    });
  }
});

test('Rust local dispatch uses the same reservation and preserves actual usage', async (context) => {
  const fixture = budgetFixture(context);
  const requests = [];
  const services = fixture.createServices({
    rustLocalMlExecutionBridge: {
      config: { enabled: true },
      async executeLocalTask({ request }) {
        requests.push(request);
        return { ok: true, text: 'ok', usage: { prompt_tokens: 5, completion_tokens: 1 } };
      },
    },
  });
  const first = startGenerate(fixture, services, 'child-token', 'rust-success');
  await first.pending;
  assert.equal(first.call.writes.find((event) => event.done)?.done?.ok, true, JSON.stringify(first.call.writes));
  assert.equal(fixture.used('delegation:hak_parent'), 76);
  assert.equal(fixture.used('device:child-device'), 6);
  const second = startGenerate(fixture, services, 'parent-token', 'rust-denied');
  await second.pending;
  assertBudgetDenied(fixture, second);
  assert.equal(requests.length, 1);
});
