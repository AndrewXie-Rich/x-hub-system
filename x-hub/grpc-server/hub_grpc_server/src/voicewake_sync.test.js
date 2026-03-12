import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';
import { voiceWakeStorePath } from './voicewake.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
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
  try {
    return fn();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `hub_voicewake_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x51).toString('base64')}`;

function baseEnv(runtimeBaseDir) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_MEMORY_AT_REST_ENABLED: 'true',
    HUB_MEMORY_KEK_ACTIVE_VERSION: 'kek_v1',
    HUB_MEMORY_KEK_RING_JSON: JSON.stringify({ kek_v1: KEK_V1 }),
    HUB_MEMORY_KEK_FILE: '',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
  };
}

function invokeHubMemoryUnary(impl, methodName, request) {
  let outErr = null;
  let outRes = null;
  impl.HubMemory[methodName](
    {
      request,
      metadata: {
        get() {
          return [];
        },
      },
      getPeer() {
        return 'ipv4:127.0.0.1:50000';
      },
    },
    (err, res) => {
      outErr = err || null;
      outRes = res || null;
    }
  );
  return { err: outErr, res: outRes };
}

function makeClient() {
  return {
    device_id: 'xt-device-1',
    user_id: 'xt-user-1',
    app_id: 'x_terminal',
    project_id: 'voicewake-project',
    session_id: 'voicewake-session',
  };
}

run('voicewake get/set persists normalized triggers and emits changed event', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const emitted = [];
    const bus = new HubEventBus();
    const originalEmit = bus.emitHubEvent.bind(bus);
    bus.emitHubEvent = (event) => {
      emitted.push(event);
      originalEmit(event);
    };

    try {
      const impl = makeServices({ db, bus });
      const client = makeClient();

      const initial = invokeHubMemoryUnary(impl, 'GetVoiceWakeProfile', {
        client,
        desired_wake_mode: 'prompt_phrase_only',
      });
      assert.equal(initial.err, null);
      assert.deepEqual(initial.res?.profile?.trigger_words || [], ['x hub', 'supervisor']);
      assert.equal(String(initial.res?.profile?.wake_mode || ''), 'prompt_phrase_only');

      const updated = invokeHubMemoryUnary(impl, 'SetVoiceWakeProfile', {
        client,
        profile: {
          profile_id: 'default',
          trigger_words: ['  Supervisor  ', 'x hub', 'supervisor', 'mission control'],
          wake_mode: 'wake_phrase',
          audit_ref: 'xt_w3_29_voicewake_push',
        },
      });
      assert.equal(updated.err, null);
      assert.deepEqual(
        updated.res?.profile?.trigger_words || [],
        ['supervisor', 'x hub', 'mission control']
      );
      assert.equal(String(updated.res?.profile?.wake_mode || ''), 'wake_phrase');
      assert.equal(emitted.length, 1);
      assert.deepEqual(
        emitted[0]?.voice_wake_profile_changed?.trigger_words || [],
        ['supervisor', 'x hub', 'mission control']
      );
      assert.equal(String(emitted[0]?.voice_wake_profile_changed?.changed_by_device_id || ''), 'xt-device-1');

      const storePath = voiceWakeStorePath(runtimeBaseDir);
      assert.equal(fs.existsSync(storePath), true);

      const fetchedAgain = invokeHubMemoryUnary(impl, 'GetVoiceWakeProfile', {
        client,
        desired_wake_mode: 'prompt_phrase_only',
      });
      assert.equal(fetchedAgain.err, null);
      assert.deepEqual(
        fetchedAgain.res?.profile?.trigger_words || [],
        ['supervisor', 'x hub', 'mission control']
      );
      assert.equal(String(fetchedAgain.res?.profile?.wake_mode || ''), 'prompt_phrase_only');
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});
