import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { buildMemoryEmbeddingDocText, prepareLocalMemoryEmbeddings } from './local_embeddings.js';

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

function makeTempRuntimeDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-local-embed-'));
}

function writeJson(filePath, obj) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(obj), 'utf8');
}

function seedRuntimeState(baseDir) {
  writeJson(path.join(baseDir, 'models_state.json'), {
    updatedAt: Date.now() / 1000.0,
    models: [
      {
        id: 'hf-embed',
        name: 'HF Embed',
        backend: 'transformers',
        modelPath: '/models/hf-embed',
        taskKinds: ['embedding'],
        inputModalities: ['text'],
        outputModalities: ['embedding'],
      },
    ],
  });
}

await run('prepareLocalMemoryEmbeddings falls back when ai.embed.local is denied', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  const out = await prepareLocalMemoryEmbeddings({
    runtimeBaseDir,
    query: 'water purchase',
    documents: [
      {
        id: 'doc-1',
        title: 'water note',
        text: 'buy bottled water',
        sensitivity: 'public',
        trust_level: 'trusted',
        created_at_ms: 1000,
      },
    ],
    capabilityAllowed: false,
    capabilityDenyCode: 'permission_denied',
  });

  assert.equal(out.ok, false);
  assert.equal(out.deny_code, 'capability_blocked');
  assert.equal(out.raw_deny_code, 'permission_denied');
  assert.equal(out.fallback_mode, 'lexical_only');
});

await run('prepareLocalMemoryEmbeddings denies when kill-switch disables ai.embed.local', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  const out = await prepareLocalMemoryEmbeddings({
    runtimeBaseDir,
    query: 'water purchase',
    documents: [
      {
        id: 'doc-1',
        title: 'water note',
        text: 'buy bottled water',
        sensitivity: 'public',
        trust_level: 'trusted',
        created_at_ms: 1000,
      },
    ],
    killSwitch: {
      disabled_local_capabilities: ['ai.embed.local'],
      reason: 'incident',
    },
  });

  assert.equal(out.ok, false);
  assert.equal(out.deny_code, 'capability_blocked');
  assert.equal(out.raw_deny_code, 'kill_switch_capability:ai.embed.local');
  assert.equal(out.fallback_mode, 'lexical_only');
});

await run('prepareLocalMemoryEmbeddings returns vectors and reuses cache across identical inputs', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  let executorCalls = 0;

  const executor = async ({ request }) => {
    executorCalls += 1;
    const texts = Array.isArray(request?.texts) ? request.texts : [];
    assert.equal(String(request?.device_id || ''), 'terminal_device');
    return {
      ok: true,
      provider: 'transformers',
      dims: 3,
      latencyMs: 7,
      vectors: texts.map((text) => {
        if (String(text).includes('purchase')) return [1, 0, 0];
        if (String(text).includes('meeting')) return [0, 1, 0];
        return [0.5, 0.5, 0];
      }),
    };
  };

  const input = {
    runtimeBaseDir,
    requestId: 'req-local-embed',
    deviceId: 'terminal_device',
    query: 'water purchase',
    documents: [
      {
        id: 'doc-1',
        title: 'water note',
        text: 'buy bottled water and email ops@example.com',
        sensitivity: 'public',
        trust_level: 'trusted',
        created_at_ms: 2000,
      },
      {
        id: 'doc-2',
        title: 'calendar',
        text: 'schedule meeting room',
        sensitivity: 'public',
        trust_level: 'trusted',
        created_at_ms: 1000,
      },
    ],
    capabilityAllowed: true,
    allowedSensitivity: ['public', 'internal'],
    allowUntrusted: false,
    executor,
  };

  const first = await prepareLocalMemoryEmbeddings(input);
  const second = await prepareLocalMemoryEmbeddings(input);

  assert.equal(first.ok, true);
  assert.equal(first.model_id, 'hf-embed');
  assert.equal(first.embedded_document_count, 2);
  assert.equal(first.documents.length, 2);
  assert.deepEqual(first.query_embedding, [1, 0, 0]);
  assert.ok(first.sanitized_change_count >= 1);
  assert.equal(buildMemoryEmbeddingDocText(input.documents[0]).includes('ops@example.com'), true);

  assert.equal(second.ok, true);
  assert.equal(second.cache_hit_count >= 3, true);
  assert.equal(executorCalls, 1);
});
