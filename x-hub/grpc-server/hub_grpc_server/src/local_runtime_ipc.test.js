import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  isRuntimeProviderReady,
  localProviderForModel,
  readRuntimeStatusSnapshot,
  runtimeModelSupportsTask,
} from './local_runtime_ipc.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function makeTempRuntimeDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-local-runtime-ipc-'));
}

function writeJson(filePath, obj) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(obj), 'utf8');
}

run('readRuntimeStatusSnapshot exposes provider-aware readiness', () => {
  const baseDir = makeTempRuntimeDir();
  writeJson(path.join(baseDir, 'ai_runtime_status.json'), {
    schema_version: 'xhub.local_runtime_status.v2',
    pid: 1234,
    updatedAt: Date.now() / 1000.0,
    mlxOk: false,
    runtimeVersion: '2026-02-21-constitution-trigger-v2',
    providers: {
      mlx: {
        provider: 'mlx',
        ok: false,
        reasonCode: 'import_error',
        importError: 'missing_module:mlx_lm',
        updatedAt: Date.now() / 1000.0,
      },
      transformers: {
        provider: 'transformers',
        ok: true,
        reasonCode: 'ready',
        availableTaskKinds: ['embedding'],
        updatedAt: Date.now() / 1000.0,
      },
    },
  });

  const snapshot = readRuntimeStatusSnapshot(baseDir, 15_000);
  assert.equal(snapshot.ok, true);
  assert.equal(snapshot.is_alive, true);
  assert.deepEqual(snapshot.ready_provider_ids, ['transformers']);
  assert.equal(isRuntimeProviderReady(baseDir, 'transformers', 15_000), true);
  assert.equal(isRuntimeProviderReady(baseDir, 'mlx', 15_000), false);
});

run('runtimeModelSupportsTask filters non text local models and preserves MLX legacy default', () => {
  const baseDir = makeTempRuntimeDir();
  writeJson(path.join(baseDir, 'models_state.json'), {
    updatedAt: Date.now() / 1000.0,
    models: [
      {
        id: 'mlx-qwen',
        name: 'MLX Qwen',
        backend: 'mlx',
        modelPath: '/models/mlx-qwen',
      },
      {
        id: 'hf-embed',
        name: 'HF Embed',
        backend: 'transformers',
        modelPath: '/models/hf-embed',
        taskKinds: ['embedding'],
      },
    ],
  });

  assert.equal(localProviderForModel(baseDir, 'mlx-qwen'), 'mlx');
  assert.equal(localProviderForModel(baseDir, 'hf-embed'), 'transformers');
  assert.equal(runtimeModelSupportsTask(baseDir, 'mlx-qwen', 'text_generate'), true);
  assert.equal(runtimeModelSupportsTask(baseDir, 'hf-embed', 'text_generate'), false);
  assert.equal(runtimeModelSupportsTask(baseDir, 'hf-embed', 'embedding'), true);
});
