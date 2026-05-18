import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';

async function run(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function makeTmpDbPath() {
  return path.join(
    os.tmpdir(),
    `rust_scheduler_shadow_compare_service_${process.pid}_${Date.now()}_${Math.random()
      .toString(16)
      .slice(2)}.sqlite3`
  );
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

function withEnv(tempEnv, fn) {
  const previous = new Map();
  const restore = () => {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  };
  for (const [key, value] of Object.entries(tempEnv)) {
    previous.set(key, process.env[key]);
    if (value == null) delete process.env[key];
    else process.env[key] = String(value);
  }
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

function makeDirectCall(request = {}) {
  return {
    request,
    metadata: {
      get() {
        return [];
      },
    },
    getPeer() {
      return 'ipv4:127.0.0.1:55111';
    },
  };
}

async function invokeUnary(fn, request) {
  return await new Promise((resolve, reject) => {
    fn(makeDirectCall(request), (err, out) => {
      if (err) {
        reject(err);
        return;
      }
      resolve(out || null);
    });
  });
}

await run('GetSchedulerStatus triggers opt-in Rust scheduler shadow comparer after response', async () => {
  const dbPath = makeTmpDbPath();
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'rust_scheduler_shadow_runtime_'));
  const calls = [];
  await withEnv({
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
  }, async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({
        db,
        bus: new HubEventBus(),
        schedulerShadowComparer: {
          maybeCompare(snapshot) {
            calls.push(snapshot);
            return true;
          },
        },
      });

      const response = await invokeUnary(impl.HubRuntime.GetSchedulerStatus, {
        include_queue_items: true,
        queue_items_limit: 10,
      });

      assert.equal(response.paid_ai.queue_depth, 0);
      assert.equal(response.paid_ai.in_flight_total, 0);
      assert.equal(calls.length, 1);
      assert.equal(calls[0].queue_depth, 0);
      assert.equal(calls[0].in_flight_total, 0);
    } finally {
      db.close();
    }
  });
  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await run('GetSchedulerStatus can opt into Rust status bridge while comparing Node snapshot', async () => {
  const dbPath = makeTmpDbPath();
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'rust_scheduler_bridge_runtime_'));
  const compareCalls = [];
  const bridgeCalls = [];
  await withEnv({
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
  }, async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({
        db,
        bus: new HubEventBus(),
        schedulerStatusBridge: {
          maybeReadStatus(input) {
            bridgeCalls.push(input);
            return {
              ok: true,
              used: true,
              paid_ai: {
                ...input.fallback,
                updated_at_ms: 1234,
                in_flight_total: 2,
                queue_depth: 3,
                oldest_queued_ms: 4,
                queue_items: [
                  {
                    request_id: 'rust-req',
                    scope_key: 'project:rust',
                    enqueued_at_ms: 100,
                    queued_ms: 4,
                  },
                ],
              },
            };
          },
        },
        schedulerShadowComparer: {
          maybeCompare(snapshot) {
            compareCalls.push(snapshot);
            return true;
          },
        },
      });

      const response = await invokeUnary(impl.HubRuntime.GetSchedulerStatus, {
        include_queue_items: true,
        queue_items_limit: 10,
      });

      assert.equal(response.paid_ai.queue_depth, 3);
      assert.equal(response.paid_ai.in_flight_total, 2);
      assert.equal(response.paid_ai.queue_items[0].request_id, 'rust-req');
      assert.equal(bridgeCalls.length, 1);
      assert.equal(compareCalls.length, 1);
      assert.equal(compareCalls[0].queue_depth, 0);
      assert.equal(compareCalls[0].in_flight_total, 0);
    } finally {
      db.close();
    }
  });
  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await run('GetSchedulerStatus awaits async Rust status bridge before responding', async () => {
  const dbPath = makeTmpDbPath();
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'rust_scheduler_async_bridge_runtime_'));
  let resolveBridge = null;
  let callbackCalled = false;
  await withEnv({
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
  }, async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({
        db,
        bus: new HubEventBus(),
        schedulerStatusBridge: {
          maybeReadStatus(input) {
            return new Promise((resolve) => {
              resolveBridge = () => resolve({
                ok: true,
                used: true,
                paid_ai: {
                  ...input.fallback,
                  updated_at_ms: 5678,
                  in_flight_total: 0,
                  queue_depth: 4,
                  oldest_queued_ms: 9,
                },
              });
            });
          },
        },
        schedulerShadowComparer: {
          maybeCompare() {
            return true;
          },
        },
      });

      const pending = new Promise((resolve, reject) => {
        impl.HubRuntime.GetSchedulerStatus(makeDirectCall({}), (err, out) => {
          callbackCalled = true;
          if (err) reject(err);
          else resolve(out);
        });
      });

      assert.equal(callbackCalled, false);
      resolveBridge();
      const response = await pending;

      assert.equal(callbackCalled, true);
      assert.equal(response.paid_ai.queue_depth, 4);
      assert.equal(response.paid_ai.oldest_queued_ms, 9);
    } finally {
      db.close();
    }
  });
  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});
