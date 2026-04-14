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
  readRuntimeModelRecord,
  readRuntimeStatusSnapshot,
  resolveLocalTaskModelRecord,
  resolveLocalTaskRoutingBinding,
  runLocalBench,
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
  const now = Date.now() / 1000.0;
  writeJson(path.join(baseDir, 'ai_runtime_status.json'), {
    schema_version: 'xhub.local_runtime_status.v2',
    pid: 1234,
    updatedAt: now,
    mlxOk: false,
    runtimeVersion: '2026-02-21-constitution-trigger-v2',
    providers: {
      mlx: {
        provider: 'mlx',
        ok: false,
        reasonCode: 'import_error',
        importError: 'missing_module:mlx_lm',
        updatedAt: now,
      },
      transformers: {
        provider: 'transformers',
        ok: true,
        reasonCode: 'partial_ready',
        runtimeSource: 'user_python_venv',
        runtimeSourcePath: '/Users/test/project/.venv/bin/python3',
        runtimeResolutionState: 'user_runtime_fallback',
        runtimeReasonCode: 'ready',
        fallbackUsed: true,
        runtimeHint: 'transformers is running from user Python /Users/test/project/.venv/bin/python3.',
        runtimeMissingRequirements: [],
        runtimeMissingOptionalRequirements: [],
        availableTaskKinds: ['embedding', 'vision_understand'],
        realTaskKinds: ['embedding'],
        fallbackTaskKinds: ['vision_understand'],
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
          oldestWaiterStartedAt: Date.now() / 1000.0,
          oldestWaiterAgeMs: 125,
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
              startedAt: now,
              leaseTtlSec: 120,
              leaseRemainingTtlSec: 120,
              expiresAt: now + 120,
            },
          ],
          contentionCount: 3,
          updatedAt: now,
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
            maxContextLength: 32768,
            effectiveLoadProfile: {
              contextLength: 24576,
              ttl: 600,
              parallel: 2,
              identifier: 'embed-slot-a',
              vision: {
                imageMaxDimension: 2048,
              },
            },
            loadedAt: now,
            lastUsedAt: now,
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
          lastEvictionAt: now,
          lastEvictedInstanceKeys: ['transformers:hf-embed:old'],
          lastEvictedModelIds: ['hf-embed'],
          lastEvictedCount: 1,
          totalEvictedInstanceCount: 1,
          updatedAt: now,
          ownerPid: 2222,
        },
        updatedAt: now,
      },
    },
    providerPacks: [
      {
        schemaVersion: 'xhub.provider_pack_manifest.v1',
        providerId: 'mlx',
        engine: 'mlx-llm',
        version: 'builtin-2026-03-16',
        supportedFormats: ['mlx'],
        supportedDomains: ['text'],
        runtimeRequirements: {
          executionMode: 'builtin_python',
          pythonModules: ['mlx_lm'],
          notes: ['offline_only'],
        },
        minHubVersion: '2026.03',
        installed: true,
        enabled: true,
        packState: 'installed',
        reasonCode: 'builtin_pack_registered',
      },
      {
        schemaVersion: 'xhub.provider_pack_manifest.v1',
        providerId: 'transformers',
        engine: 'hf-transformers',
        version: 'builtin-2026-03-16',
        supportedFormats: ['hf_transformers'],
        supportedDomains: ['embedding', 'audio', 'vision', 'ocr'],
        runtimeRequirements: {
          executionMode: 'builtin_python',
          pythonModules: ['transformers', 'torch', 'tokenizers', 'PIL'],
          notes: ['offline_only', 'processor_required_for_multimodal'],
        },
        minHubVersion: '2026.03',
        installed: true,
        enabled: true,
        packState: 'installed',
        reasonCode: 'builtin_pack_registered',
      },
    ],
    loadedInstances: [
      {
        provider: 'transformers',
        instanceKey: 'transformers:hf-embed:abc123',
        modelId: 'hf-embed',
        taskKinds: ['embedding'],
        loadProfileHash: 'abc123',
        effectiveContextLength: 24576,
        maxContextLength: 32768,
        effectiveLoadProfile: {
          contextLength: 24576,
          ttl: 600,
          parallel: 2,
          identifier: 'embed-slot-a',
          vision: {
            imageMaxDimension: 2048,
          },
        },
        loadedAt: now,
        lastUsedAt: now,
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
        lastEvictionAt: now,
        lastEvictedInstanceKeys: ['transformers:hf-embed:old'],
        lastEvictedModelIds: ['hf-embed'],
        lastEvictedCount: 1,
        totalEvictedInstanceCount: 1,
        updatedAt: now,
        ownerPid: 2222,
      },
    },
    recentBenchResults: [
      {
        ok: true,
        provider: 'transformers',
        taskKind: 'vision_understand',
        modelId: 'hf-vision',
        fixtureProfile: 'vision_single_image',
        fixtureTitle: 'Single Image Vision',
        resultKind: 'task_aware_quick_bench',
        reasonCode: 'ready',
        runtimeSource: 'user_python_venv',
        runtimeSourcePath: '/Users/test/project/.venv/bin/python3',
        runtimeResolutionState: 'user_runtime_fallback',
        runtimeReasonCode: 'ready',
        fallbackUsed: false,
        loadProfileHash: 'vision4096',
        effectiveContextLength: 4096,
        updatedAt: now,
        routeTrace: {
          schemaVersion: 'xhub.image_task.route_trace.v1',
          requestMode: 'single_image',
          selectedTaskKind: 'vision_understand',
          selectionReason: 'explicit_or_default',
          explicitTaskKind: 'vision_understand',
          imageCount: 1,
          resolvedImageCount: 1,
          promptChars: 24,
          executionPath: 'real_runtime',
          imageFiles: ['frame_a.png'],
          resolvedImages: [
            {
              index: 0,
              fileName: 'frame_a.png',
            },
          ],
        },
      },
    ],
  });

  const snapshot = readRuntimeStatusSnapshot(baseDir, 15_000);
  assert.equal(snapshot.ok, true);
  assert.equal(snapshot.is_alive, true);
  assert.deepEqual(snapshot.ready_provider_ids, ['transformers']);
  assert.equal(isRuntimeProviderReady(baseDir, 'transformers', 15_000), true);
  assert.equal(isRuntimeProviderReady(baseDir, 'mlx', 15_000), false);
  assert.equal(snapshot.provider_packs.length, 2);
  assert.equal(snapshot.provider_packs.find((row) => row.provider_id === 'transformers')?.engine, 'hf-transformers');
  assert.deepEqual(
    snapshot.provider_packs.find((row) => row.provider_id === 'transformers')?.runtime_requirements?.python_modules,
    ['transformers', 'torch', 'tokenizers', 'pil']
  );
  assert.equal(snapshot.providers.transformers.pack_id, 'transformers');
  assert.equal(snapshot.providers.transformers.pack_engine, 'hf-transformers');
  assert.equal(snapshot.providers.transformers.pack_version, 'builtin-2026-03-16');
  assert.equal(snapshot.providers.transformers.pack_installed, true);
  assert.equal(snapshot.providers.transformers.pack_enabled, true);
  assert.equal(snapshot.providers.transformers.pack_state, 'installed');
  assert.equal(snapshot.providers.transformers.pack_reason_code, 'builtin_pack_registered');
  assert.equal(snapshot.providers.transformers.runtime_source, 'user_python_venv');
  assert.equal(snapshot.providers.transformers.runtime_source_path, '/Users/test/project/.venv/bin/python3');
  assert.equal(snapshot.providers.transformers.runtime_resolution_state, 'user_runtime_fallback');
  assert.equal(snapshot.providers.transformers.runtime_reason_code, 'ready');
  assert.equal(snapshot.providers.transformers.fallback_used, true);
  assert.equal(snapshot.providers.mlx.pack_id, 'mlx');
  assert.equal(snapshot.providers.mlx.pack_state, 'installed');
  assert.equal(snapshot.providers.transformers.resource_policy.concurrency_limit, 2);
  assert.equal(snapshot.providers.transformers.resource_policy.task_limits.embedding, 2);
  assert.deepEqual(snapshot.providers.transformers.real_task_kinds, ['embedding']);
  assert.deepEqual(snapshot.providers.transformers.fallback_task_kinds, ['vision_understand']);
  assert.equal(snapshot.providers.transformers.scheduler_state.active_task_count, 1);
  assert.equal(snapshot.providers.transformers.scheduler_state.queued_task_count, 2);
  assert.equal(snapshot.providers.transformers.scheduler_state.oldest_waiter_age_ms, 125);
  assert.equal(snapshot.providers.transformers.scheduler_state.active_tasks.length, 1);
  assert.equal(snapshot.providers.transformers.scheduler_state.active_tasks[0].device_id, 'terminal_device');
  assert.equal(snapshot.providers.transformers.scheduler_state.active_tasks[0].load_profile_hash, 'abc123');
  assert.equal(snapshot.providers.transformers.scheduler_state.active_tasks[0].load_config_hash, 'abc123');
  assert.equal(snapshot.providers.transformers.scheduler_state.active_tasks[0].instance_key, 'transformers:hf-embed:abc123');
  assert.equal(snapshot.providers.transformers.scheduler_state.active_tasks[0].effective_context_length, 24576);
  assert.equal(snapshot.providers.transformers.scheduler_state.active_tasks[0].current_context_length, 24576);
  assert.equal(snapshot.providers.transformers.scheduler_state.active_tasks[0].lease_ttl_sec, 120);
  assert.equal(snapshot.providers.transformers.scheduler_state.active_tasks[0].lease_remaining_ttl_sec, 120);
  assert.equal(snapshot.providers.transformers.scheduler_state.active_tasks[0].expires_at_ms, Math.floor((now + 120) * 1000));
  assert.equal(snapshot.providers.transformers.lifecycle_mode, 'warmable');
  assert.deepEqual(snapshot.providers.transformers.supported_lifecycle_actions, ['warmup_local_model', 'unload_local_model', 'evict_local_instance']);
  assert.deepEqual(snapshot.providers.transformers.warmup_task_kinds, ['embedding']);
  assert.equal(snapshot.providers.transformers.residency_scope, 'process_local');
  assert.equal(snapshot.providers.transformers.loaded_instances.length, 1);
  assert.equal(snapshot.providers.transformers.loaded_instances[0].instance_key, 'transformers:hf-embed:abc123');
  assert.equal(snapshot.providers.transformers.loaded_instances[0].provider, 'transformers');
  assert.equal(snapshot.providers.transformers.loaded_instances[0].load_config_hash, 'abc123');
  assert.equal(snapshot.providers.transformers.loaded_instances[0].current_context_length, 24576);
  assert.equal(snapshot.providers.transformers.loaded_instances[0].max_context_length, 32768);
  assert.equal(snapshot.providers.transformers.loaded_instances[0].ttl, 600);
  assert.equal(snapshot.providers.transformers.loaded_instances[0].effective_load_profile.context_length, 24576);
  assert.equal(snapshot.providers.transformers.loaded_instances[0].effective_load_profile.ttl, 600);
  assert.equal(snapshot.providers.transformers.loaded_instances[0].load_config.schema_version, 'xhub.load_config.v1');
  assert.equal(snapshot.providers.transformers.loaded_instances[0].load_config.parallel, 2);
  assert.equal(snapshot.providers.transformers.idle_eviction.policy, 'manual_or_process_exit');
  assert.equal(snapshot.providers.transformers.idle_eviction.last_eviction_reason, 'manual_unload');
  assert.equal(snapshot.loaded_instance_count, 1);
  assert.equal(snapshot.loaded_instances.length, 1);
  assert.equal(snapshot.loaded_instances[0].provider, 'transformers');
  assert.equal(snapshot.loaded_instances[0].load_config.identifier, 'embed-slot-a');
  assert.equal(snapshot.loaded_instances[0].ttl, 600);
  assert.equal(snapshot.idle_eviction_by_provider.transformers.total_evicted_instance_count, 1);
  assert.equal(snapshot.active_tasks.length, 1);
  assert.equal(snapshot.active_tasks[0].provider, 'transformers');
  assert.equal(snapshot.active_tasks[0].lease_ttl_sec, 120);
  assert.equal(snapshot.active_tasks[0].expires_at_ms, Math.floor((now + 120) * 1000));
  assert.equal(snapshot.queue.active_task_count, 1);
  assert.equal(snapshot.queue.queued_task_count, 2);
  assert.equal(snapshot.queue.max_oldest_wait_ms, 125);
  assert.equal(snapshot.fallback_counters.fallback_ready_provider_count, 1);
  assert.equal(snapshot.fallback_counters.task_kind_counts.vision_understand, 1);
  assert.equal(snapshot.recent_bench_results.length, 1);
  assert.equal(snapshot.recent_bench_results[0].route_trace_summary.selected_task_kind, 'vision_understand');
  assert.equal(snapshot.monitor_snapshot.providers.length, 2);
  assert.equal(snapshot.monitor_snapshot.providers.find((row) => row.provider === 'transformers')?.runtime_source, 'user_python_venv');
  assert.equal(snapshot.monitor_snapshot.providers.find((row) => row.provider === 'transformers')?.runtime_resolution_state, 'user_runtime_fallback');
  assert.equal(snapshot.monitor_snapshot.providers.find((row) => row.provider === 'transformers')?.memory_state, 'unknown');
  assert.equal(snapshot.monitor_snapshot.active_tasks[0].lease_ttl_sec, 120);
  assert.equal(snapshot.monitor_snapshot.loaded_instances[0].ttl, 600);
  assert.equal(snapshot.monitor_snapshot.recent_bench_results[0].route_trace_summary.execution_path, 'real_runtime');
  assert.equal(snapshot.last_errors.some((row) => row.provider === 'mlx'), true);
});

await run('readRuntimeStatusSnapshot derives provider pack inventory from provider status when top-level packs are absent', () => {
  const baseDir = makeTempRuntimeDir();
  writeJson(path.join(baseDir, 'ai_runtime_status.json'), {
    schema_version: 'xhub.local_runtime_status.v2',
    pid: 2234,
    updatedAt: Date.now() / 1000.0,
    runtimeVersion: '2026-03-23-provider-runtime-inventory-v1',
    providers: {
      transformers: {
        provider: 'transformers',
        ok: false,
        reasonCode: 'missing_runtime',
        packId: 'transformers',
        packEngine: 'hf-transformers',
        packVersion: 'builtin-2026-03-16',
        packInstalled: true,
        packEnabled: true,
        packState: 'installed',
        packReasonCode: 'builtin_pack_registered',
        runtimeSource: 'hub_py_deps',
        runtimeSourcePath: '/Users/test/runtime/ai_runtime',
        runtimeResolutionState: 'runtime_missing',
        runtimeReasonCode: 'missing_runtime',
        fallbackUsed: false,
        runtimeHint: 'transformers runtime is missing required dependencies (python_module:torch).',
        runtimeMissingRequirements: ['python_module:torch'],
        updatedAt: Date.now() / 1000.0,
      },
    },
  });

  const snapshot = readRuntimeStatusSnapshot(baseDir, 15_000);
  assert.equal(snapshot.ok, true);
  assert.equal(snapshot.provider_packs.length, 2);
  const derived = snapshot.provider_packs.find((row) => row.provider_id === 'transformers');
  const legacy = snapshot.provider_packs.find((row) => row.provider_id === 'mlx');
  assert.equal(derived?.engine, 'hf-transformers');
  assert.equal(derived?.version, 'builtin-2026-03-16');
  assert.equal(derived?.installed, true);
  assert.equal(derived?.enabled, true);
  assert.equal(derived?.pack_state, 'installed');
  assert.equal(derived?.reason_code, 'builtin_pack_registered');
  assert.deepEqual(derived?.runtime_requirements?.notes, ['derived_from_provider_status']);
  assert.equal(legacy?.pack_state, 'legacy_unreported');
  assert.equal(legacy?.reason_code, 'runtime_status_missing_provider_pack_inventory');
});

await run('readRuntimeStatusSnapshot backfills disabled provider pack truth fail-closed', () => {
  const baseDir = makeTempRuntimeDir();
  writeJson(path.join(baseDir, 'ai_runtime_status.json'), {
    schema_version: 'xhub.local_runtime_status.v2',
    pid: 1235,
    updatedAt: Date.now() / 1000.0,
    runtimeVersion: '2026-03-16-provider-pack-registry-v1',
    providers: {
      transformers: {
        provider: 'transformers',
        ok: false,
        reasonCode: 'provider_pack_disabled',
        availableTaskKinds: [],
        unavailableTaskKinds: ['embedding', 'vision_understand'],
        updatedAt: Date.now() / 1000.0,
      },
    },
    providerPacks: [
      {
        schemaVersion: 'xhub.provider_pack_manifest.v1',
        providerId: 'transformers',
        engine: 'hf-transformers',
        version: 'operator-pinned-2026-03-16',
        supportedFormats: ['hf_transformers'],
        supportedDomains: ['embedding', 'audio', 'vision', 'ocr'],
        runtimeRequirements: {
          executionMode: 'builtin_python',
          pythonModules: ['transformers'],
        },
        minHubVersion: '2026.03',
        installed: true,
        enabled: false,
        packState: 'disabled',
        reasonCode: 'provider_pack_disabled',
      },
    ],
  });

  const snapshot = readRuntimeStatusSnapshot(baseDir, 15_000);
  assert.equal(snapshot.providers.transformers.ok, false);
  assert.equal(snapshot.providers.transformers.reason_code, 'provider_pack_disabled');
  assert.equal(snapshot.providers.transformers.pack_enabled, false);
  assert.equal(snapshot.providers.transformers.pack_state, 'disabled');
  assert.equal(snapshot.providers.transformers.pack_version, 'operator-pinned-2026-03-16');
  assert.deepEqual(snapshot.providers.transformers.unavailable_task_kinds, ['embedding', 'vision_understand']);
  const transformersPack = snapshot.provider_packs.find((row) => row.provider_id === 'transformers');
  const legacyPack = snapshot.provider_packs.find((row) => row.provider_id === 'mlx');
  assert.equal(transformersPack?.enabled, false);
  assert.equal(transformersPack?.pack_state, 'disabled');
  assert.equal(legacyPack?.pack_state, 'legacy_unreported');
  assert.equal(snapshot.ready_provider_ids.length, 0);
});

await run('runLocalBench normalizes quick bench payloads from local runtime', async () => {
  const out = await runLocalBench({
    runtimeBaseDir: makeTempRuntimeDir(),
    request: {
      model_id: 'hf-embed',
      task_kind: 'embedding',
      fixture_profile: 'embed_small_docs',
    },
    executor: async ({ command, request }) => {
      assert.equal(command, 'run-local-bench');
      assert.equal(String(request?.fixture_profile || ''), 'embed_small_docs');
      return {
        ok: true,
        provider: 'transformers',
        taskKind: 'embedding',
        modelId: 'hf-embed',
        fixtureProfile: 'embed_small_docs',
        fixtureTitle: 'Small Document Batch',
        resultKind: 'task_aware_quick_bench',
        reasonCode: 'ready',
        runtimeSource: 'user_python_venv',
        runtimeSourcePath: '/Users/test/project/.venv/bin/python3',
        runtimeResolutionState: 'user_runtime_fallback',
        runtimeReasonCode: 'ready',
        fallbackUsed: true,
        runtimeHint: 'transformers is running from user Python /Users/test/project/.venv/bin/python3.',
        runtimeMissingRequirements: [],
        runtimeMissingOptionalRequirements: ['python_module:pil'],
        routeTrace: {
          schemaVersion: 'xhub.image_task.route_trace.v1',
          requestMode: 'single_image',
          selectedTaskKind: 'vision_understand',
          selectionReason: 'explicit_or_default',
          explicitTaskKind: 'vision_understand',
          imageCount: 1,
          resolvedImageCount: 1,
          promptChars: 18,
          executionPath: 'real_runtime',
          fallbackMode: '',
          imageFiles: ['route_trace_fixture.png'],
        },
        verdict: 'Balanced',
        fallbackMode: '',
        coldStartMs: 420,
        latencyMs: 92,
        peakMemoryBytes: 1048576,
        throughputValue: 32.5,
        throughputUnit: 'items_per_sec',
        loadProfileHash: 'ctx8192',
        effectiveContextLength: 8192,
        effectiveLoadProfile: {
          contextLength: 8192,
          ttl: 300,
          parallel: 1,
        },
        notes: ['dims=384', 'text_count=3'],
        updatedAt: Date.now() / 1000.0,
      };
    },
  });

  assert.equal(out.ok, true);
  assert.equal(out.provider, 'transformers');
  assert.equal(out.task_kind, 'embedding');
  assert.equal(out.fixture_profile, 'embed_small_docs');
  assert.equal(out.fixture_title, 'Small Document Batch');
  assert.equal(out.verdict, 'Balanced');
  assert.equal(out.runtime_source, 'user_python_venv');
  assert.equal(out.runtime_source_path, '/Users/test/project/.venv/bin/python3');
  assert.equal(out.runtime_resolution_state, 'user_runtime_fallback');
  assert.equal(out.runtime_reason_code, 'ready');
  assert.equal(out.fallback_used, true);
  assert.equal(out.runtime_hint, 'transformers is running from user Python /Users/test/project/.venv/bin/python3.');
  assert.deepEqual(out.runtime_missing_requirements, []);
  assert.deepEqual(out.runtime_missing_optional_requirements, ['python_module:pil']);
  assert.equal(out.cold_start_ms, 420);
  assert.equal(out.latency_ms, 92);
  assert.equal(out.peak_memory_bytes, 1048576);
  assert.equal(out.throughput_value, 32.5);
  assert.equal(out.throughput_unit, 'items_per_sec');
  assert.equal(out.load_profile_hash, 'ctx8192');
  assert.equal(out.load_config_hash, 'ctx8192');
  assert.equal(out.effective_context_length, 8192);
  assert.equal(out.current_context_length, 8192);
  assert.equal(out.load_config.context_length, 8192);
  assert.equal(out.load_config.ttl, 300);
  assert.deepEqual(out.notes, ['dims=384', 'text_count=3']);
  assert.equal(out.route_trace?.selectedTaskKind, 'vision_understand');
  assert.equal(out.route_trace_summary?.selected_task_kind, 'vision_understand');
  assert.equal(out.route_trace_summary?.execution_path, 'real_runtime');
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

await run('localProviderForModel prefers explicit runtime provider override for local records', () => {
  const baseDir = makeTempRuntimeDir();
  writeJson(path.join(baseDir, 'models_state.json'), {
    updatedAt: Date.now() / 1000.0,
    models: [
      {
        id: 'glm4v-mlx-helper',
        name: 'GLM4V MLX Helper',
        backend: 'mlx',
        runtimeProviderId: 'mlx_vlm',
        modelPath: '/models/glm4v-mlx-helper',
        taskKinds: ['vision_understand', 'ocr'],
      },
    ],
  });

  const record = readRuntimeModelRecord(baseDir, 'glm4v-mlx-helper');

  assert.equal(record.runtime_provider_id, 'mlx_vlm');
  assert.equal(localProviderForModel(baseDir, 'glm4v-mlx-helper'), 'mlx_vlm');
  assert.equal(localProviderForModel({
    backend: 'mlx',
    runtimeProviderId: 'mlx_vlm',
  }), 'mlx_vlm');
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
        contextLength: 8192,
        maxContextLength: 32768,
        default_load_config: {
          contextLength: 16384,
          ttl: 900,
          parallel: 4,
          identifier: 'embed-main',
          vision: {
            imageMaxDimension: 3072,
          },
        },
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
  assert.equal(rows[0].default_context_length, 16384);
  assert.equal(rows[0].max_context_length, 32768);
  assert.equal(rows[0].default_load_profile.context_length, 16384);
  assert.equal(rows[0].default_load_config.schema_version, 'xhub.load_config.v1');
  assert.equal(rows[0].default_load_config.parallel, 4);
  assert.equal(rows[0].default_load_profile.parallel, 4);
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

await run('resolveLocalTaskModelRecord returns routed compatible local model records', () => {
  const baseDir = makeTempRuntimeDir();
  writeJson(path.join(baseDir, 'models_state.json'), {
    updatedAt: Date.now() / 1000.0,
    models: [
      {
        id: 'hf-embed-default',
        name: 'HF Embed Default',
        backend: 'transformers',
        modelPath: '/models/hf-embed-default',
        taskKinds: ['embedding'],
      },
      {
        id: 'hf-embed-device',
        name: 'HF Embed Device',
        backend: 'transformers',
        modelPath: '/models/hf-embed-device',
        taskKinds: ['embedding'],
      },
    ],
  });
  writeJson(path.join(baseDir, 'routing_settings.json'), {
    hubDefaultModelIdByTaskKind: {
      embedding: 'hf-embed-default',
    },
    devicePreferredModelIdByTaskKind: {
      terminal_device: {
        embedding: 'hf-embed-device',
      },
    },
  });

  const selection = resolveLocalTaskModelRecord({
    runtimeBaseDir: baseDir,
    taskKind: 'embedding',
    deviceId: 'terminal_device',
    providerId: 'transformers',
  });

  assert.equal(selection.ok, true);
  assert.equal(selection.route_source, 'device_override');
  assert.equal(selection.resolved_model_id, 'hf-embed-device');
  assert.equal(selection.model.model_id, 'hf-embed-device');
});

await run('resolveLocalTaskModelRecord fails closed when routed model is incompatible', () => {
  const baseDir = makeTempRuntimeDir();
  writeJson(path.join(baseDir, 'models_state.json'), {
    updatedAt: Date.now() / 1000.0,
    models: [
      {
        id: 'hf-vision',
        name: 'HF Vision',
        backend: 'transformers',
        modelPath: '/models/hf-vision',
        taskKinds: ['vision_understand'],
      },
    ],
  });
  writeJson(path.join(baseDir, 'routing_settings.json'), {
    hubDefaultModelIdByTaskKind: {
      embedding: 'hf-vision',
    },
  });

  const selection = resolveLocalTaskModelRecord({
    runtimeBaseDir: baseDir,
    taskKind: 'embedding',
    providerId: 'transformers',
  });

  assert.equal(selection.ok, false);
  assert.equal(selection.route_source, 'hub_default');
  assert.equal(selection.resolved_model_id, 'hf-vision');
  assert.equal(selection.reason_code, 'routed_model_task_mismatch');
});
