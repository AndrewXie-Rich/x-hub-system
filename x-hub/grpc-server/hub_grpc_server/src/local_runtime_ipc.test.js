import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  manageLocalModelLifecycle,
  isRuntimeProviderReady,
  listRuntimeModelRecords,
  localProviderForModel,
  readLocalTaskRoutingSettings,
  readRuntimeStatusSnapshot,
  resolveLocalTaskRoutingBinding,
  runtimeModelSupportsTask,
} from './local_runtime_ipc.js';

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
  return fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-local-runtime-ipc-'));
}

function writeJson(filePath, obj) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(obj), 'utf8');
}

await run('readRuntimeStatusSnapshot exposes provider-aware readiness', () => {
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
        resourcePolicy: {
          preferredDevice: 'cpu',
          memoryFloorMB: 1024,
          dtype: 'float32',
          concurrencyLimit: 2,
          taskLimits: {
            embedding: 2,
          },
          queueingSupported: true,
          queueMode: 'opt_in_wait',
        },
        schedulerState: {
          activeTaskCount: 1,
          queuedTaskCount: 2,
          activeTasks: [
            {
              leaseId: 'lease-1',
              taskKind: 'embedding',
              modelId: 'hf-embed',
              requestId: 'req-1',
              deviceId: 'terminal_device',
              loadProfileHash: 'abc123',
              instanceKey: 'transformers:hf-embed:abc123',
              effectiveContextLength: 24576,
              startedAt: Date.now() / 1000.0,
            },
          ],
          contentionCount: 3,
          updatedAt: Date.now() / 1000.0,
        },
        lifecycleMode: 'warmable',
        supportedLifecycleActions: ['warmup_local_model', 'unload_local_model', 'evict_local_instance'],
        warmupTaskKinds: ['embedding'],
        residencyScope: 'process_local',
        loadedInstances: [
          {
            provider: 'transformers',
            instanceKey: 'transformers:hf-embed:abc123',
            modelId: 'hf-embed',
            taskKinds: ['embedding'],
            loadProfileHash: 'abc123',
            effectiveContextLength: 24576,
            loadedAt: Date.now() / 1000.0,
            lastUsedAt: Date.now() / 1000.0,
            residency: 'resident',
            residencyScope: 'process_local',
            deviceBackend: 'cpu',
          },
        ],
        idleEviction: {
          policy: 'manual_or_process_exit',
          automaticIdleEvictionEnabled: false,
          idleTimeoutSec: 0,
          processScoped: true,
          lastEvictionReason: 'manual_unload',
          lastEvictionAt: Date.now() / 1000.0,
          lastEvictedInstanceKeys: ['transformers:hf-embed:old'],
          lastEvictedModelIds: ['hf-embed'],
          lastEvictedCount: 1,
          totalEvictedInstanceCount: 1,
          updatedAt: Date.now() / 1000.0,
          ownerPid: 2222,
        },
        updatedAt: Date.now() / 1000.0,
      },
    },
    loadedInstances: [
      {
        provider: 'transformers',
        instanceKey: 'transformers:hf-embed:abc123',
        modelId: 'hf-embed',
        taskKinds: ['embedding'],
        loadProfileHash: 'abc123',
        effectiveContextLength: 24576,
        loadedAt: Date.now() / 1000.0,
        lastUsedAt: Date.now() / 1000.0,
        residency: 'resident',
        residencyScope: 'process_local',
        deviceBackend: 'cpu',
      },
    ],
    loadedInstanceCount: 1,
    idleEvictionByProvider: {
      transformers: {
        policy: 'manual_or_process_exit',
        automaticIdleEvictionEnabled: false,
        idleTimeoutSec: 0,
        processScoped: true,
        lastEvictionReason: 'manual_unload',
        lastEvictionAt: Date.now() / 1000.0,
        lastEvictedInstanceKeys: ['transformers:hf-embed:old'],
        lastEvictedModelIds: ['hf-embed'],
        lastEvictedCount: 1,
        totalEvictedInstanceCount: 1,
        updatedAt: Date.now() / 1000.0,
        ownerPid: 2222,
      },
    },
  });

  const snapshot = readRuntimeStatusSnapshot(baseDir, 15_000);
  assert.equal(snapshot.ok, true);
  assert.equal(snapshot.is_alive, true);
  assert.deepEqual(snapshot.ready_provider_ids, ['transformers']);
  assert.equal(isRuntimeProviderReady(baseDir, 'transformers', 15_000), true);
  assert.equal(isRuntimeProviderReady(baseDir, 'mlx', 15_000), false);
  assert.equal(snapshot.providers.transformers.resource_policy.concurrency_limit, 2);
  assert.equal(snapshot.providers.transformers.resource_policy.task_limits.embedding, 2);
  assert.equal(snapshot.providers.transformers.scheduler_state.active_task_count, 1);
  assert.equal(snapshot.providers.transformers.scheduler_state.queued_task_count, 2);
  assert.equal(snapshot.providers.transformers.scheduler_state.active_tasks.length, 1);
  assert.equal(snapshot.providers.transformers.scheduler_state.active_tasks[0].device_id, 'terminal_device');
  assert.equal(snapshot.providers.transformers.scheduler_state.active_tasks[0].load_profile_hash, 'abc123');
  assert.equal(snapshot.providers.transformers.scheduler_state.active_tasks[0].instance_key, 'transformers:hf-embed:abc123');
  assert.equal(snapshot.providers.transformers.scheduler_state.active_tasks[0].effective_context_length, 24576);
  assert.equal(snapshot.providers.transformers.lifecycle_mode, 'warmable');
  assert.deepEqual(snapshot.providers.transformers.supported_lifecycle_actions, ['warmup_local_model', 'unload_local_model', 'evict_local_instance']);
  assert.deepEqual(snapshot.providers.transformers.warmup_task_kinds, ['embedding']);
  assert.equal(snapshot.providers.transformers.residency_scope, 'process_local');
  assert.equal(snapshot.providers.transformers.loaded_instances.length, 1);
  assert.equal(snapshot.providers.transformers.loaded_instances[0].instance_key, 'transformers:hf-embed:abc123');
  assert.equal(snapshot.providers.transformers.loaded_instances[0].provider, 'transformers');
  assert.equal(snapshot.providers.transformers.idle_eviction.policy, 'manual_or_process_exit');
  assert.equal(snapshot.providers.transformers.idle_eviction.last_eviction_reason, 'manual_unload');
  assert.equal(snapshot.loaded_instance_count, 1);
  assert.equal(snapshot.loaded_instances.length, 1);
  assert.equal(snapshot.loaded_instances[0].provider, 'transformers');
  assert.equal(snapshot.idle_eviction_by_provider.transformers.total_evicted_instance_count, 1);
});

await run('runtimeModelSupportsTask filters non text local models and preserves MLX legacy default', () => {
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

await run('listRuntimeModelRecords exposes normalized task and modality metadata', () => {
  const baseDir = makeTempRuntimeDir();
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
        modelFormat: 'huggingface',
      },
    ],
  });

  const rows = listRuntimeModelRecords(baseDir);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].model_id, 'hf-embed');
  assert.deepEqual(rows[0].task_kinds, ['embedding']);
  assert.deepEqual(rows[0].input_modalities, ['text']);
  assert.deepEqual(rows[0].output_modalities, ['embedding']);
  assert.equal(rows[0].model_format, 'huggingface');
});

await run('manageLocalModelLifecycle delegates lifecycle actions to the runtime command executor', async () => {
  let captured = null;
  const result = await manageLocalModelLifecycle({
    runtimeBaseDir: '/tmp/xhub-runtime',
    action: 'warmup_local_model',
    request: {
      provider: 'transformers',
      model_id: 'hf-embed',
      task_kind: 'embedding',
    },
    executor: async (args) => {
      captured = args;
      return {
        ok: true,
        action: 'warmup_local_model',
        provider: 'transformers',
        modelId: 'hf-embed',
      };
    },
  });

  assert.equal(captured.command, 'manage-local-model');
  assert.equal(captured.runtimeBaseDir, '/tmp/xhub-runtime');
  assert.equal(captured.request.action, 'warmup_local_model');
  assert.equal(captured.request.provider, 'transformers');
  assert.equal(result.ok, true);
  assert.equal(result.action, 'warmup_local_model');
});

await run('readLocalTaskRoutingSettings decodes schema v2 hub defaults and device overrides', () => {
  const baseDir = makeTempRuntimeDir();
  writeJson(path.join(baseDir, 'routing_settings.json'), {
    type: 'routing_settings',
    schemaVersion: 'xhub.routing_settings.v2',
    updatedAt: Date.now() / 1000.0,
    hubDefaultModelIdByTaskKind: {
      text_generate: 'mlx-qwen',
      embedding: 'hf-embed',
    },
    devicePreferredModelIdByTaskKind: {
      terminal_device: {
        embedding: 'hf-embed-device',
      },
    },
  });

  const snapshot = readLocalTaskRoutingSettings(baseDir);
  assert.equal(snapshot.schema_version, 'xhub.routing_settings.v2');
  assert.equal(snapshot.hub_default_model_id_by_task_kind.embedding, 'hf-embed');
  assert.equal(snapshot.device_preferred_model_id_by_task_kind.terminal_device.embedding, 'hf-embed-device');
});

await run('resolveLocalTaskRoutingBinding reports request override, device override, hub default, and auto selected', () => {
  const baseDir = makeTempRuntimeDir();
  writeJson(path.join(baseDir, 'routing_settings.json'), {
    preferredModelIdByTask: {
      text_generate: 'mlx-qwen',
      embedding: 'hf-embed',
    },
    devicePreferredModelIdByTaskKind: {
      terminal_device: {
        embedding: 'hf-embed-device',
      },
    },
  });

  const requestOverride = resolveLocalTaskRoutingBinding({
    runtimeBaseDir: baseDir,
    taskKind: 'embedding',
    preferredModelId: 'hf-embed-request',
  });
  assert.equal(requestOverride.model_id, 'hf-embed-request');
  assert.equal(requestOverride.source, 'request_override');

  const deviceOverride = resolveLocalTaskRoutingBinding({
    runtimeBaseDir: baseDir,
    taskKind: 'embedding',
    deviceId: 'terminal_device',
  });
  assert.equal(deviceOverride.model_id, 'hf-embed-device');
  assert.equal(deviceOverride.source, 'device_override');

  const hubDefault = resolveLocalTaskRoutingBinding({
    runtimeBaseDir: baseDir,
    taskKind: 'text_generate',
    deviceId: 'terminal_device',
  });
  assert.equal(hubDefault.model_id, 'mlx-qwen');
  assert.equal(hubDefault.source, 'hub_default');

  const autoSelected = resolveLocalTaskRoutingBinding({
    runtimeBaseDir: baseDir,
    taskKind: 'speech_to_text',
  });
  assert.equal(autoSelected.model_id, '');
  assert.equal(autoSelected.source, 'auto_selected');
});
