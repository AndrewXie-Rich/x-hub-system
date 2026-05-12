#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFile, execFileSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');

async function main(argv) {
  const flags = parseFlags(argv);
  if (flags.has('help') || flags.has('h')) {
    process.stdout.write(helpText());
    return 0;
  }
  if (flags.has('self-test')) {
    await runSelfTest();
    process.stdout.write('scheduler_authority_runner self-test ok\n');
    return 0;
  }

  const config = resolveConfig(flags);
  if (flags.has('dry-run')) {
    process.stdout.write(JSON.stringify({
      schema_version: 'xhub.scheduler_authority_runner.dry_run.v1',
      ok: true,
      config: publicConfig(config),
    }, null, 2) + '\n');
    return 0;
  }

  const previousEnv = captureEnv([
    'HUB_RUNTIME_BASE_DIR',
    'HUB_BRIDGE_BASE_DIR',
    'HUB_CLIENT_TOKEN',
    'HUB_AUDIT_LEVEL',
    'HUB_MEMORY_AT_REST_ENABLED',
    'HUB_MEMORY_RETENTION_ENABLED',
    'HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS',
    'HUB_BRIDGE_AI_TIMEOUT_SEC',
    'HUB_PAID_AI_QUEUE_TIMEOUT_MS',
    'HUB_DB_PATH',
    'XHUB_RUST_HUB_ROOT',
    'XHUB_RUST_HUB_RUNNER',
    'XHUB_RUST_SCHEDULER_AUTHORITY',
    'XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY',
    'XHUB_RUST_SCHEDULER_AUTHORITY_FALLBACK_ON_ERROR',
    'XHUB_RUST_SCHEDULER_AUTHORITY_TIMEOUT_MS',
    'XHUB_RUST_SCHEDULER_AUTHORITY_POLL_MS',
    'XHUB_RUST_SCHEDULER_AUTHORITY_READINESS_CACHE_MS',
    'XHUB_RUST_SCHEDULER_AUTHORITY_LEASE_DURATION_MS',
    'XHUB_RUST_SCHEDULER_AUTHORITY_MIN_COMPARE_REPORTS',
    'XHUB_RUST_SCHEDULER_AUTHORITY_MAX_MISMATCHES',
    'XHUB_RUST_SCHEDULER_AUTHORITY_MIN_LEASE_SHADOW_RUNS',
    'XHUB_RUST_SCHEDULER_AUTHORITY_MAX_STALE_ACTIVE',
    'XHUB_RUST_SCHEDULER_AUTHORITY_MAX_ORPHANED_LEASES',
    'XHUB_RUST_SCHEDULER_AUTHORITY_ALLOW_ACTIVE_RUNS',
    'XHUB_RUST_SCHEDULER_STATUS_READ',
    'XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY',
  ]);

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub_authority_runner_'));
  const runtimeBaseDir = path.join(tempRoot, 'runtime');
  const bridgeBaseDir = path.join(tempRoot, 'bridge');
  const nodeDbPath = path.join(tempRoot, 'node_hub.sqlite3');
  const rustDbPath = config.rustDbPath || path.join(tempRoot, 'rust_hub.sqlite3');
  let fakeBridge = null;
  let db = null;

  try {
    fs.mkdirSync(runtimeBaseDir, { recursive: true });
    fs.mkdirSync(bridgeBaseDir, { recursive: true });

    process.env.HUB_RUNTIME_BASE_DIR = runtimeBaseDir;
    process.env.HUB_BRIDGE_BASE_DIR = bridgeBaseDir;
    process.env.HUB_CLIENT_TOKEN = '';
    process.env.HUB_AUDIT_LEVEL = 'metadata_only';
    process.env.HUB_MEMORY_AT_REST_ENABLED = 'false';
    process.env.HUB_MEMORY_RETENTION_ENABLED = 'false';
    process.env.HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS = '50';
    process.env.HUB_BRIDGE_AI_TIMEOUT_SEC = String(config.bridgeTimeoutSec);
    process.env.HUB_PAID_AI_QUEUE_TIMEOUT_MS = String(config.queueTimeoutMs);
    if (!config.useExistingRustDb || config.rustDbPath) {
      process.env.HUB_DB_PATH = rustDbPath;
    }
    process.env.XHUB_RUST_HUB_ROOT = config.rustHubRoot;
    process.env.XHUB_RUST_HUB_RUNNER = config.runner;
    process.env.XHUB_RUST_SCHEDULER_AUTHORITY = '1';
    process.env.XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY = '1';
    process.env.XHUB_RUST_SCHEDULER_AUTHORITY_FALLBACK_ON_ERROR = '0';
    process.env.XHUB_RUST_SCHEDULER_AUTHORITY_TIMEOUT_MS = String(config.timeoutMs);
    process.env.XHUB_RUST_SCHEDULER_AUTHORITY_POLL_MS = String(config.pollMs);
    process.env.XHUB_RUST_SCHEDULER_AUTHORITY_READINESS_CACHE_MS = '0';
    process.env.XHUB_RUST_SCHEDULER_AUTHORITY_LEASE_DURATION_MS = String(config.leaseDurationMs);
    process.env.XHUB_RUST_SCHEDULER_AUTHORITY_MIN_COMPARE_REPORTS = String(config.minCompareReports);
    process.env.XHUB_RUST_SCHEDULER_AUTHORITY_MAX_MISMATCHES = String(config.maxMismatches);
    process.env.XHUB_RUST_SCHEDULER_AUTHORITY_MIN_LEASE_SHADOW_RUNS = String(config.minLeaseShadowRuns);
    process.env.XHUB_RUST_SCHEDULER_AUTHORITY_MAX_STALE_ACTIVE = String(config.maxStaleActive);
    process.env.XHUB_RUST_SCHEDULER_AUTHORITY_MAX_ORPHANED_LEASES = String(config.maxOrphanedLeases);
    process.env.XHUB_RUST_SCHEDULER_AUTHORITY_ALLOW_ACTIVE_RUNS = config.allowActiveRuns ? '1' : '0';
    process.env.XHUB_RUST_SCHEDULER_STATUS_READ = '1';
    process.env.XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY = '1';

    const src = path.join(config.xhubSystemRoot, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src');
    const [{ HubDB }, { HubEventBus }, { makeServices }] = await Promise.all([
      import(pathToFileURL(path.join(src, 'db.js')).href),
      import(pathToFileURL(path.join(src, 'event_bus.js')).href),
      import(pathToFileURL(path.join(src, 'services.js')).href),
    ]);

    db = new HubDB({ dbPath: nodeDbPath });
    seedPaidModel(db, config.modelId);
    const clientEntry = makeClientEntry(config);
    writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
    fakeBridge = startFakeBridge({
      bridgeBaseDir,
      responseText: config.bridgeResponseText,
      pollMs: config.bridgePollMs,
      responseDelayMs: config.bridgeResponseDelayMs,
    });

    const impl = makeServices({ db, bus: new HubEventBus() });
    const runIdPrefix = `node_paid_ai_authority_${config.requestPrefix}`;
    const before = readLeaseShadowReport(config.runner, {
      runIdPrefix,
      limit: config.reportLimit,
      staleAfterMs: config.staleAfterMs,
    });
    const iterations = [];

    emitEvent('start', {
      config: publicConfig(config),
      runtime_base_dir: runtimeBaseDir,
      bridge_base_dir: bridgeBaseDir,
      rust_db_path: rustDbPath,
      lease_shadow_before: before,
    });

    for (let index = 0; index < config.runs; index += 1) {
      if (config.scenario !== 'normal') {
        const item = await runQueuedTerminalScenario({
          impl,
          clientEntry,
          config,
          runIndex: index + 1,
          runner: config.runner,
          runIdPrefix,
          fakeBridge,
        });
        iterations.push(item);
        emitEvent('iteration', item);

        if (item.scenario_ok !== true) {
          throw new Error(`scenario ${config.scenario} failed for batch ${index + 1}: ${JSON.stringify(item)}`);
        }
        if (config.expectClean && item.scheduler_clean !== true) {
          throw new Error(`Rust scheduler not clean after batch ${index + 1}: ${JSON.stringify(item.scheduler_status_after || {})}`);
        }
        continue;
      }

      const requestIds = Array.from({ length: config.concurrency }, (_, requestIndex) => {
        if (config.concurrency === 1) return `${config.requestPrefix}_${index + 1}`;
        return `${config.requestPrefix}_${index + 1}_${requestIndex + 1}`;
      });

      const sampler = config.concurrency > 1 || config.expectQueued
        ? startStatusSampler({
            runner: config.runner,
            intervalMs: config.statusSampleMs,
            timeoutMs: config.statusSampleTimeoutMs,
          })
        : null;

      const settled = await Promise.all(requestIds.map(async (requestId, requestIndex) => {
        const call = makeGenerateCall({
          token: clientEntry.token,
          request: makeGenerateRequest({
            requestId,
            requestIndex,
            clientEntry,
            config,
          }),
        });
        try {
          await impl.HubAI.Generate(call);
          return {
            request_id: requestId,
            ok: true,
            generate: summarizeGenerateCall(call),
          };
        } catch (error) {
          return {
            request_id: requestId,
            ok: false,
            error_message: String(error?.stack || error?.message || error),
            generate: summarizeGenerateCall(call),
          };
        }
      }));

      if (sampler) await sampler.stop();
      const sampleSummary = summarizeStatusSamples(sampler?.samples || []);

      let latestReport = null;
      for (const requestId of requestIds) {
        latestReport = await waitForAuthorityRunCompleted({
          runner: config.runner,
          runIdPrefix,
          requestId,
          timeoutMs: config.timeoutMs,
          pollMs: config.pollMs,
          staleAfterMs: config.staleAfterMs,
          limit: config.reportLimit,
        });
      }
      const authorityRows = new Map(
        (Array.isArray(latestReport?.recent) ? latestReport.recent : [])
          .map((row) => [String(row?.request_id || ''), row])
          .filter((row) => row[0])
      );
      const requestResults = settled.map((result) => ({
        ...result,
        authority_run: authorityRows.get(String(result.request_id || '')) || null,
      }));
      const status = readSchedulerStatus(config.runner);
      const clean = schedulerStatusClean(status);
      const queuedObserved = sampleSummary.max_queue_depth > 0;
      const item = {
        run_index: index + 1,
        request_count: requestIds.length,
        request_ids: requestIds,
        queued_observed: queuedObserved,
        status_samples: sampleSummary,
        requests: requestResults,
        scheduler_clean: clean,
        bridge_requests_seen: fakeBridge.requests.length,
      };
      iterations.push(item);
      emitEvent('iteration', item);

      const failed = requestResults.filter((result) => !result.ok || !result.generate?.done_ok);
      if (config.expectSuccess && failed.length > 0) {
        throw new Error(`Generate did not complete ok for ${failed.map((item) => item.request_id).join(',')}`);
      }
      if (config.expectQueued && !queuedObserved) {
        throw new Error(`Rust scheduler queue was not observed for batch ${index + 1}: ${JSON.stringify(sampleSummary)}`);
      }
      if (config.expectClean && !clean) {
        throw new Error(`Rust scheduler not clean after batch ${index + 1}: ${JSON.stringify(status)}`);
      }
    }

    const after = readLeaseShadowReport(config.runner, {
      runIdPrefix,
      limit: config.reportLimit,
      staleAfterMs: config.staleAfterMs,
    });
    const finalStatus = readSchedulerStatus(config.runner);
    const ok = iterations.every((item) => item.scenario_ok !== false)
      && (!config.expectSuccess || iterations.every((item) => batchGenerateOk(item)))
      && (!config.expectClean || schedulerStatusClean(finalStatus));
    const finalPayload = {
      ok,
      lease_shadow_after: after,
      scheduler_status_after: finalStatus,
      bridge_requests: fakeBridge.requests,
      iterations,
    };
    emitEvent('stop', finalPayload);
    return ok ? 0 : 2;
  } finally {
    if (fakeBridge) fakeBridge.stop();
    if (db) {
      try {
        db.close();
      } catch {
        // ignore
      }
    }
    restoreEnv(previousEnv);
    if (!config.keepTemp) {
      try {
        fs.rmSync(tempRoot, { recursive: true, force: true });
      } catch {
        // ignore
      }
    }
  }
}

function seedPaidModel(db, modelId) {
  db.db.prepare(
    `INSERT OR REPLACE INTO models(model_id,name,kind,backend,context_length,requires_grant,enabled,updated_at_ms)
     VALUES(?,?,?,?,?,?,?,?)`
  ).run(
    String(modelId || '').trim(),
    'Authority Runner Paid Model',
    'paid_online',
    'openai',
    128000,
    1,
    1,
    Date.now()
  );
}

function makeClientEntry(config) {
  const capabilities = ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'];
  return {
    device_id: config.deviceId,
    user_id: config.userId,
    name: 'Rust Scheduler Authority Runner',
    token: `tok_authority_${process.pid}_${Date.now()}_${Math.random().toString(16).slice(2)}`,
    enabled: true,
    capabilities,
    policy_mode: 'new_profile',
    approved_trust_profile: {
      schema_version: 'hub.paired_terminal_trust_profile.v1',
      device_id: config.deviceId,
      device_name: 'Rust Scheduler Authority Runner',
      trust_mode: 'trusted_daily',
      mode: 'standard',
      state: 'off',
      capabilities,
      allowed_project_ids: [],
      allowed_workspace_roots: [],
      xt_binding_required: false,
      auto_grant_profile: '',
      device_permission_owner_ref: '',
      paid_model_policy: {
        schema_version: 'hub.paired_terminal_paid_model_policy.v1',
        mode: 'custom_selected_models',
        allowed_model_ids: [config.modelId],
      },
      network_policy: {
        default_web_fetch_enabled: true,
      },
      budget_policy: {
        daily_token_limit: 50000,
        single_request_token_limit: 5000,
      },
      audit_ref: 'audit-rust-scheduler-authority-runner',
    },
  };
}

function writeClientsSnapshot(runtimeBaseDir, clients) {
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  writeJsonAtomic(path.join(runtimeBaseDir, 'hub_grpc_clients.json'), {
    schema_version: 'hub_grpc_clients.v2',
    updated_at_ms: Date.now(),
    clients,
  }, 2);
}

function makeGenerateCall({ request, token }) {
  const writes = [];
  const handlers = new Map();
  let ended = false;
  return {
    request,
    writes,
    get ended() {
      return ended;
    },
    metadata: {
      get(key) {
        if (String(key || '').toLowerCase() === 'authorization') {
          return token ? [`Bearer ${token}`] : [];
        }
        return [];
      },
    },
    getPeer() {
      return 'ipv4:127.0.0.1:54321';
    },
    write(payload) {
      writes.push(payload);
    },
    end() {
      ended = true;
    },
    on(event, handler) {
      const key = String(event || '');
      if (!key || typeof handler !== 'function') return this;
      const list = handlers.get(key) || [];
      list.push(handler);
      handlers.set(key, list);
      return this;
    },
    emit(event, ...args) {
      const list = handlers.get(String(event || '')) || [];
      for (const handler of list) {
        try {
          handler(...args);
        } catch {
          // ignore handler errors in test calls
        }
      }
      return this;
    },
  };
}

function startGenerateTask({ impl, clientEntry, config, requestId, requestIndex }) {
  const call = makeGenerateCall({
    token: clientEntry.token,
    request: makeGenerateRequest({
      requestId,
      requestIndex,
      clientEntry,
      config,
    }),
  });
  const promise = (async () => {
    try {
      await impl.HubAI.Generate(call);
      return {
        request_id: requestId,
        ok: true,
        generate: summarizeGenerateCall(call),
      };
    } catch (error) {
      return {
        request_id: requestId,
        ok: false,
        error_message: String(error?.stack || error?.message || error),
        generate: summarizeGenerateCall(call),
      };
    }
  })();
  return { requestId, call, promise };
}

function makeGenerateRequest({ requestId, requestIndex, clientEntry, config }) {
  return {
    request_id: requestId,
    model_id: config.modelId,
    max_tokens: config.maxTokens,
    temperature: 0.1,
    top_p: 0.95,
    messages: [
      {
        role: 'user',
        content: `hello from rust scheduler authority runner ${requestIndex + 1}`,
      },
    ],
    client: {
      device_id: clientEntry.device_id,
      user_id: clientEntry.user_id,
      app_id: config.appId,
      project_id: config.projectId,
    },
  };
}

async function runQueuedTerminalScenario({
  impl,
  clientEntry,
  config,
  runIndex,
  runner,
  runIdPrefix,
  fakeBridge,
}) {
  const requestIds = Array.from({ length: 3 }, (_, requestIndex) => (
    `${config.requestPrefix}_${runIndex}_${requestIndex + 1}`
  ));
  const sampler = startStatusSampler({
    runner,
    intervalMs: config.statusSampleMs,
    timeoutMs: config.statusSampleTimeoutMs,
  });
  const tasks = [];
  try {
    tasks.push(startGenerateTask({
      impl,
      clientEntry,
      config,
      requestId: requestIds[0],
      requestIndex: 0,
    }));
    tasks.push(startGenerateTask({
      impl,
      clientEntry,
      config,
      requestId: requestIds[1],
      requestIndex: 1,
    }));

    await waitForStatusCondition({
      runner,
      timeoutMs: config.timeoutMs,
      pollMs: config.pollMs,
      label: 'first two authority leases',
      predicate: (status) => safeInt(status?.in_flight_total) >= 2,
    });

    const queuedTask = startGenerateTask({
      impl,
      clientEntry,
      config,
      requestId: requestIds[2],
      requestIndex: 2,
    });
    tasks.push(queuedTask);

    await waitForAuthorityRunStatus({
      runner,
      runIdPrefix,
      requestId: requestIds[2],
      expectedStatus: 'queued',
      timeoutMs: config.timeoutMs,
      pollMs: config.pollMs,
      staleAfterMs: config.staleAfterMs,
      limit: config.reportLimit,
    });

    if (config.scenario === 'queued-cancel') {
      queuedTask.call.emit('cancelled');
    }

    const settled = await Promise.all(tasks.map((task) => task.promise));
    await sampler.stop();
    const sampleSummary = summarizeStatusSamples(sampler.samples);

    const expectedQueuedStatus = 'canceled';
    const expectedGenerate = config.scenario === 'queued-timeout'
      ? { error_code: 'hub_ai_queue_timeout' }
      : { done_reason: 'canceled' };
    let latestReport = null;
    for (let index = 0; index < requestIds.length; index += 1) {
      latestReport = await waitForAuthorityRunStatus({
        runner,
        runIdPrefix,
        requestId: requestIds[index],
        expectedStatus: index < 2 ? 'completed' : expectedQueuedStatus,
        timeoutMs: config.timeoutMs,
        pollMs: config.pollMs,
        staleAfterMs: config.staleAfterMs,
        limit: config.reportLimit,
      });
    }
    const authorityRows = new Map(
      (Array.isArray(latestReport?.recent) ? latestReport.recent : [])
        .map((row) => [String(row?.request_id || ''), row])
        .filter((row) => row[0])
    );
    const requestResults = settled.map((result) => ({
      ...result,
      authority_run: authorityRows.get(String(result.request_id || '')) || null,
    }));
    const blockersOk = requestResults.slice(0, 2).every((result) => (
      result.ok === true
      && result.generate?.done_ok === true
      && result.authority_run?.status === 'completed'
    ));
    const queued = requestResults[2] || {};
    const queuedAuthorityOk = queued.authority_run?.status === expectedQueuedStatus;
    const queuedGenerateOk = config.scenario === 'queued-timeout'
      ? queued.generate?.error_code === expectedGenerate.error_code
      : queued.generate?.done_ok === false && queued.generate?.done_reason === expectedGenerate.done_reason;
    const finalStatus = readSchedulerStatus(runner);
    const clean = schedulerStatusClean(finalStatus);
    const queuedObserved = sampleSummary.max_queue_depth > 0;
    return {
      run_index: runIndex,
      scenario: config.scenario,
      request_count: requestIds.length,
      request_ids: requestIds,
      queued_observed: queuedObserved,
      status_samples: sampleSummary,
      requests: requestResults,
      expected_queued_status: expectedQueuedStatus,
      expected_queued_generate: expectedGenerate,
      scenario_ok: blockersOk && queuedAuthorityOk && queuedGenerateOk && queuedObserved && clean,
      scheduler_clean: clean,
      scheduler_status_after: finalStatus,
      bridge_requests_seen: fakeBridge.requests.length,
    };
  } finally {
    await sampler.stop();
  }
}

function summarizeGenerateCall(call) {
  const writes = Array.isArray(call?.writes) ? call.writes : [];
  const done = [...writes].reverse().find((item) => item?.done)?.done || null;
  const error = [...writes].reverse().find((item) => item?.error)?.error || null;
  const deltas = writes.filter((item) => item?.delta);
  const start = writes.find((item) => item?.start)?.start || null;
  return {
    ended: call?.ended === true,
    write_count: writes.length,
    start_seen: !!start,
    delta_count: deltas.length,
    delta_text: deltas.map((item) => String(item?.delta?.text || '')).join(''),
    done_ok: done?.ok === true,
    done_reason: String(done?.reason || ''),
    done_model_id: String(done?.actual_model_id || ''),
    done_execution_path: String(done?.execution_path || ''),
    done_runtime_provider: String(done?.runtime_provider || ''),
    error_code: String(error?.error?.code || error?.code || ''),
  };
}

function startFakeBridge({ bridgeBaseDir, responseText, pollMs, responseDelayMs = 0 }) {
  const paths = bridgePaths(bridgeBaseDir);
  fs.mkdirSync(paths.reqDir, { recursive: true });
  fs.mkdirSync(paths.respDir, { recursive: true });
  fs.mkdirSync(paths.commandsDir, { recursive: true });

  const seen = new Set();
  const requests = [];
  const pendingTimers = new Set();
  const status = () => {
    writeJsonAtomic(paths.statusPath, {
      schema_version: 'xhub.bridge.status.v1',
      pid: process.pid,
      updatedAt: Date.now() / 1000,
      enabledUntil: Date.now() / 1000 + 3600,
    }, 2);
  };
  const scan = () => {
    let files = [];
    try {
      files = fs.readdirSync(paths.reqDir);
    } catch {
      return;
    }
    for (const file of files) {
      if (!file.startsWith('req_') || !file.endsWith('.json')) continue;
      const filePath = path.join(paths.reqDir, file);
      const req = readJsonSafe(filePath);
      const reqId = String(req?.req_id || req?.request_id || '').trim();
      if (!reqId || seen.has(reqId)) continue;
      seen.add(reqId);
      const record = {
        req_id: reqId,
        type: String(req?.type || ''),
        model_id: String(req?.model_id || ''),
        prompt_bytes: Buffer.byteLength(String(req?.prompt || ''), 'utf8'),
        max_tokens: safeInt(req?.max_tokens),
        received_at_ms: Date.now(),
        response_written_at_ms: 0,
      };
      requests.push(record);
      if (String(req?.type || '') !== 'ai_generate') continue;
      const writeResponse = () => {
        record.response_written_at_ms = Date.now();
        writeJsonAtomic(path.join(paths.respDir, `resp_${reqId}.json`), {
          ok: true,
          status: 200,
          text: responseText,
          usage: {
            prompt_tokens: 8,
            completion_tokens: 6,
            total_tokens: 14,
          },
        }, 2);
      };
      const delayMs = safeInt(responseDelayMs);
      if (delayMs > 0) {
        const timer = setTimeout(() => {
          pendingTimers.delete(timer);
          writeResponse();
        }, delayMs);
        pendingTimers.add(timer);
        if (typeof timer.unref === 'function') timer.unref();
      } else {
        writeResponse();
      }
    }
  };

  status();
  const statusTimer = setInterval(status, 500);
  const scanTimer = setInterval(scan, Math.max(10, Number(pollMs || 20)));
  if (typeof statusTimer.unref === 'function') statusTimer.unref();
  if (typeof scanTimer.unref === 'function') scanTimer.unref();

  return {
    requests,
    stop() {
      clearInterval(statusTimer);
      clearInterval(scanTimer);
      for (const timer of pendingTimers) clearTimeout(timer);
      pendingTimers.clear();
    },
  };
}

function bridgePaths(baseDir) {
  return {
    base: baseDir,
    statusPath: path.join(baseDir, 'bridge_status.json'),
    commandsDir: path.join(baseDir, 'bridge_commands'),
    reqDir: path.join(baseDir, 'bridge_requests'),
    respDir: path.join(baseDir, 'bridge_responses'),
  };
}

async function waitForAuthorityRunCompleted({
  runner,
  runIdPrefix,
  requestId,
  timeoutMs,
  pollMs,
  staleAfterMs,
  limit,
}) {
  const started = Date.now();
  let latest = readLeaseShadowReport(runner, { runIdPrefix, staleAfterMs, limit });
  while (Date.now() - started <= timeoutMs) {
    const row = (Array.isArray(latest?.recent) ? latest.recent : [])
      .find((item) => String(item?.request_id || '') === String(requestId || ''));
    if (row && String(row.status || '') === 'completed') return latest;
    await sleep(pollMs);
    latest = readLeaseShadowReport(runner, { runIdPrefix, staleAfterMs, limit });
  }
  throw new Error(`authority run ${requestId} did not complete within ${timeoutMs}ms`);
}

async function waitForAuthorityRunStatus({
  runner,
  runIdPrefix,
  requestId,
  expectedStatus,
  timeoutMs,
  pollMs,
  staleAfterMs,
  limit,
}) {
  const started = Date.now();
  let latest = readLeaseShadowReport(runner, { runIdPrefix, staleAfterMs, limit });
  while (Date.now() - started <= timeoutMs) {
    const row = (Array.isArray(latest?.recent) ? latest.recent : [])
      .find((item) => String(item?.request_id || '') === String(requestId || ''));
    if (row && String(row.status || '') === String(expectedStatus || '')) return latest;
    await sleep(pollMs);
    latest = readLeaseShadowReport(runner, { runIdPrefix, staleAfterMs, limit });
  }
  const latestRow = (Array.isArray(latest?.recent) ? latest.recent : [])
    .find((item) => String(item?.request_id || '') === String(requestId || ''));
  throw new Error(`authority run ${requestId} did not reach ${expectedStatus} within ${timeoutMs}ms; latest_status=${safeString(latestRow?.status)} latest_event=${safeString(latestRow?.last_event_type)} report=${JSON.stringify(latest || {}).slice(0, 1200)}`);
}

function readLeaseShadowReport(runner, { runIdPrefix, staleAfterMs, limit }) {
  return readRunnerJson(runner, [
    'scheduler',
    'lease-shadow-report',
    '--run-id-prefix',
    runIdPrefix,
    '--stale-after-ms',
    String(staleAfterMs),
    '--limit',
    String(limit),
  ]);
}

function readSchedulerStatus(runner) {
  return readRunnerJson(runner, [
    'scheduler',
    'status',
    '--include-queue-items',
    '--queue-items-limit',
    '20',
  ]);
}

function startStatusSampler({ runner, intervalMs, timeoutMs }) {
  let stopped = false;
  const samples = [];
  const loop = (async () => {
    while (!stopped) {
      const started = Date.now();
      try {
        const status = await readSchedulerStatusAsync(runner, timeoutMs);
        samples.push({
          at_ms: Date.now(),
          ok: true,
          in_flight_total: safeInt(status?.in_flight_total),
          queue_depth: safeInt(status?.queue_depth),
          oldest_queued_ms: safeInt(status?.oldest_queued_ms),
        });
      } catch (error) {
        samples.push({
          at_ms: Date.now(),
          ok: false,
          error_message: String(error?.message || error),
        });
      }
      const elapsed = Date.now() - started;
      await sleep(Math.max(10, Number(intervalMs || 100) - elapsed));
    }
  })();
  return {
    samples,
    async stop() {
      stopped = true;
      await loop.catch(() => {});
    },
  };
}

async function readSchedulerStatusAsync(runner, timeoutMs) {
  return await readRunnerJsonAsync(runner, [
    'scheduler',
    'status',
    '--include-queue-items',
    '--queue-items-limit',
    '20',
  ], timeoutMs);
}

async function waitForStatusCondition({ runner, timeoutMs, pollMs, predicate, label }) {
  const started = Date.now();
  let latest = await readSchedulerStatusAsync(runner, timeoutMs);
  while (Date.now() - started <= timeoutMs) {
    if (predicate(latest)) return latest;
    await sleep(pollMs);
    latest = await readSchedulerStatusAsync(runner, timeoutMs);
  }
  throw new Error(`scheduler status condition timed out: ${label || 'condition'}`);
}

function summarizeStatusSamples(samples) {
  const arr = Array.isArray(samples) ? samples : [];
  const okSamples = arr.filter((sample) => sample?.ok === true);
  return {
    sample_count: arr.length,
    ok_sample_count: okSamples.length,
    error_sample_count: arr.length - okSamples.length,
    max_in_flight_total: okSamples.reduce((max, sample) => Math.max(max, safeInt(sample.in_flight_total)), 0),
    max_queue_depth: okSamples.reduce((max, sample) => Math.max(max, safeInt(sample.queue_depth)), 0),
    max_oldest_queued_ms: okSamples.reduce((max, sample) => Math.max(max, safeInt(sample.oldest_queued_ms)), 0),
  };
}

function readRunnerJson(runner, args) {
  const stdout = execFileSync(runner, args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  return JSON.parse(stdout);
}

async function readRunnerJsonAsync(runner, args, timeoutMs) {
  const stdout = await new Promise((resolve, reject) => {
    execFile(runner, args, {
      encoding: 'utf8',
      timeout: Math.max(1000, Number(timeoutMs || 5000)),
      maxBuffer: 1024 * 1024,
    }, (error, out, stderr) => {
      if (error) {
        error.stderr = stderr;
        reject(error);
        return;
      }
      resolve(String(out || ''));
    });
  });
  return JSON.parse(stdout);
}

function schedulerStatusClean(status) {
  return safeInt(status?.in_flight_total) === 0 && safeInt(status?.queue_depth) === 0;
}

function batchGenerateOk(item) {
  if (Array.isArray(item?.requests)) {
    return item.requests.every((request) => request?.ok === true && request?.generate?.done_ok === true);
  }
  return item?.generate?.done_ok === true;
}

function resolveConfig(flags) {
  const rustHubRoot = path.resolve(flags.get('rust-hub-root') || path.join(__dirname, '..'));
  const xhubSystemRoot = path.resolve(flags.get('xhub-system-root') || findXHubSystemRoot(rustHubRoot));
  const runner = path.resolve(flags.get('runner') || path.join(rustHubRoot, 'tools', 'run_rust_hub.command'));
  const scenario = normalizeScenario(flags.get('scenario') || 'normal');
  const requestPrefix = normalizeSafeId(
    flags.get('request-prefix')
      || `authority_runner_${process.pid}_${Date.now()}_${Math.random().toString(16).slice(2)}`
  );
  const concurrency = parseIntFlag(flags, 'concurrency', scenario === 'normal' ? 1 : 3, 1);
  if (scenario !== 'normal' && concurrency < 3) {
    throw new Error(`--concurrency must be at least 3 for --scenario ${scenario}`);
  }
  const queueTimeoutMs = parseIntFlag(flags, 'queue-timeout-ms', scenario === 'queued-timeout' ? 1000 : 20000, 1000);
  const bridgeResponseDelayMs = flags.has('bridge-response-delay-ms')
    ? parseIntFlag(flags, 'bridge-response-delay-ms', 0, 0)
    : (scenario === 'queued-timeout'
      ? Math.max(3000, queueTimeoutMs + 1500)
      : (concurrency > 2 ? 1500 : 0));
  return {
    rustHubRoot,
    xhubSystemRoot,
    runner,
    scenario,
    rustDbPath: flags.has('rust-db-path') ? path.resolve(flags.get('rust-db-path')) : '',
    useExistingRustDb: flagEnabled(flags, 'use-existing-rust-db'),
    runs: parseIntFlag(flags, 'runs', 1, 1),
    concurrency,
    queueTimeoutMs,
    timeoutMs: parseIntFlag(flags, 'timeout-ms', 30000, 1000),
    pollMs: parseIntFlag(flags, 'poll-ms', 100, 10),
    statusSampleMs: parseIntFlag(flags, 'status-sample-ms', 100, 10),
    statusSampleTimeoutMs: parseIntFlag(flags, 'status-sample-timeout-ms', 10000, 1000),
    bridgePollMs: parseIntFlag(flags, 'bridge-poll-ms', 20, 10),
    bridgeResponseDelayMs,
    bridgeTimeoutSec: parseIntFlag(flags, 'bridge-timeout-sec', 5, 5),
    leaseDurationMs: parseIntFlag(flags, 'lease-duration-ms', 300000, 1000),
    staleAfterMs: parseIntFlag(flags, 'stale-after-ms', 300000, 1),
    reportLimit: parseIntFlag(flags, 'report-limit', 20, 1),
    minCompareReports: parseIntFlag(flags, 'min-compare-reports', 0, 0),
    maxMismatches: parseIntFlag(flags, 'max-mismatches', 0, 0),
    minLeaseShadowRuns: parseIntFlag(flags, 'min-lease-shadow-runs', 0, 0),
    maxStaleActive: parseIntFlag(flags, 'max-stale-active', 0, 0),
    maxOrphanedLeases: parseIntFlag(flags, 'max-orphaned-leases', 0, 0),
    modelId: String(flags.get('model-id') || 'openai/gpt-5.4').trim(),
    maxTokens: parseIntFlag(flags, 'max-tokens', 24, 1),
    projectId: String(flags.get('project-id') || 'authority-runner-project').trim(),
    deviceId: String(flags.get('device-id') || 'authority-runner-device').trim(),
    userId: String(flags.get('user-id') || 'authority-runner-user').trim(),
    appId: String(flags.get('app-id') || 'xhub-authority-runner').trim(),
    bridgeResponseText: String(flags.get('bridge-response-text') || 'rust scheduler authority runner ok').trim(),
    requestPrefix,
    expectSuccess: scenario === 'normal' && !flagEnabled(flags, 'allow-failure'),
    expectClean: !flagEnabled(flags, 'allow-dirty-scheduler'),
    expectQueued: scenario !== 'normal' || flagEnabled(flags, 'expect-queued'),
    allowActiveRuns: !flagEnabled(flags, 'disallow-active-runs'),
    keepTemp: flagEnabled(flags, 'keep-temp'),
  };
}

function publicConfig(config) {
  return {
    rust_hub_root: config.rustHubRoot,
    xhub_system_root: config.xhubSystemRoot,
    runner: config.runner,
    scenario: config.scenario,
    rust_db_path: config.rustDbPath || '(temp)',
    use_existing_rust_db: config.useExistingRustDb,
    runs: config.runs,
    concurrency: config.concurrency,
    queue_timeout_ms: config.queueTimeoutMs,
    timeout_ms: config.timeoutMs,
    poll_ms: config.pollMs,
    status_sample_ms: config.statusSampleMs,
    bridge_timeout_sec: config.bridgeTimeoutSec,
    bridge_response_delay_ms: config.bridgeResponseDelayMs,
    lease_duration_ms: config.leaseDurationMs,
    min_compare_reports: config.minCompareReports,
    min_lease_shadow_runs: config.minLeaseShadowRuns,
    model_id: config.modelId,
    project_id: config.projectId,
    device_id: config.deviceId,
    request_prefix: config.requestPrefix,
    expect_success: config.expectSuccess,
    expect_clean: config.expectClean,
    expect_queued: config.expectQueued,
    allow_active_runs: config.allowActiveRuns,
    keep_temp: config.keepTemp,
  };
}

function parseFlags(argv) {
  const flags = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) throw new Error(`unexpected positional argument: ${token}`);
    const body = token.slice(2);
    if (!body) throw new Error('empty flag is not supported');
    const eq = body.indexOf('=');
    if (eq >= 0) {
      flags.set(body.slice(0, eq), body.slice(eq + 1));
      continue;
    }
    const next = argv[index + 1];
    if (next != null && !next.startsWith('--')) {
      flags.set(body, next);
      index += 1;
    } else {
      flags.set(body, 'true');
    }
  }
  return flags;
}

function normalizeScenario(value) {
  const scenario = String(value || '').trim().toLowerCase() || 'normal';
  if (['normal', 'queued-cancel', 'queued-timeout'].includes(scenario)) return scenario;
  throw new Error(`unsupported --scenario ${scenario}`);
}

function parseIntFlag(flags, key, fallback, min = 1) {
  if (!flags.has(key)) return fallback;
  const value = Number.parseInt(flags.get(key), 10);
  if (!Number.isFinite(value)) throw new Error(`--${key} must be an integer`);
  return Math.max(min, value);
}

function flagEnabled(flags, key) {
  if (!flags.has(key)) return false;
  const value = String(flags.get(key) || '').trim().toLowerCase();
  return !['', '0', 'false', 'no', 'off'].includes(value);
}

function findXHubSystemRoot(startDir) {
  let current = path.resolve(startDir);
  for (;;) {
    const candidate = path.join(current, 'x-hub-system');
    if (fs.existsSync(path.join(candidate, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src', 'services.js'))) {
      return candidate;
    }
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
  throw new Error('Unable to locate x-hub-system. Pass --xhub-system-root <path>.');
}

function normalizeSafeId(value) {
  const cleaned = String(value || '').trim().replace(/[^a-zA-Z0-9_.:-]+/g, '_');
  if (!cleaned) throw new Error('request prefix cannot be empty');
  return cleaned.slice(0, 120);
}

function emitEvent(event, payload = {}) {
  process.stdout.write(JSON.stringify({
    schema_version: 'xhub.scheduler_authority_runner.v1',
    event,
    at_ms: Date.now(),
    ...payload,
  }) + '\n');
}

function captureEnv(keys) {
  return new Map(keys.map((key) => [key, process.env[key]]));
}

function restoreEnv(previous) {
  for (const [key, value] of previous.entries()) {
    if (value == null) delete process.env[key];
    else process.env[key] = value;
  }
}

function readJsonSafe(filePath) {
  try {
    return JSON.parse(fs.readFileSync(String(filePath || ''), 'utf8'));
  } catch {
    return null;
  }
}

function writeJsonAtomic(filePath, obj, spaces = 0) {
  const out = String(filePath || '').trim();
  const dir = path.dirname(out);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = `${out}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`;
  fs.writeFileSync(tmp, JSON.stringify(obj, null, spaces) + (spaces ? '\n' : ''), 'utf8');
  fs.renameSync(tmp, out);
}

function safeInt(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return 0;
  return Math.max(0, Math.floor(number));
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function runSelfTest() {
  const flags = parseFlags([
    '--runs',
    '2',
    '--timeout-ms=5000',
    '--allow-failure',
    '--scenario',
    'queued-cancel',
    '--concurrency',
    '3',
    '--expect-queued',
    '--request-prefix',
    'abc 123',
  ]);
  const config = resolveConfig(flags);
  assert.equal(config.scenario, 'queued-cancel');
  assert.equal(config.runs, 2);
  assert.equal(config.concurrency, 3);
  assert.equal(config.queueTimeoutMs, 20000);
  assert.equal(config.timeoutMs, 5000);
  assert.equal(config.expectSuccess, false);
  assert.equal(config.expectQueued, true);
  assert.equal(config.allowActiveRuns, true);
  assert.ok(config.bridgeResponseDelayMs > 0);
  assert.equal(config.requestPrefix, 'abc_123');
  assert.equal(schedulerStatusClean({ in_flight_total: '0', queue_depth: 0 }), true);
  assert.equal(schedulerStatusClean({ in_flight_total: '1', queue_depth: 0 }), false);

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub_authority_runner_self_'));
  try {
    const fake = startFakeBridge({
      bridgeBaseDir: tmp,
      responseText: 'ok',
      pollMs: 10,
      responseDelayMs: 10,
    });
    const p = bridgePaths(tmp);
    writeJsonAtomic(path.join(p.reqDir, 'req_self.json'), {
      type: 'ai_generate',
      req_id: 'self',
      model_id: 'openai/gpt-5.4',
      prompt: 'hello',
      max_tokens: 1,
    }, 2);
    await sleep(50);
    const resp = readJsonSafe(path.join(p.respDir, 'resp_self.json'));
    fake.stop();
    assert.equal(resp?.ok, true);
    assert.equal(fake.requests.length, 1);
    assert.equal(summarizeStatusSamples([
      { ok: true, in_flight_total: 2, queue_depth: 1, oldest_queued_ms: 5 },
      { ok: false },
    ]).max_queue_depth, 1);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

function helpText() {
  return `Usage:
  node tools/scheduler_authority_runner.js [options]

Options:
  --rust-hub-root <path>        Rust Hub root, default parent of this tools dir
  --xhub-system-root <path>     x-hub-system root, auto-detected
  --runner <path>               Rust Hub runner command
  --rust-db-path <path>         Rust scheduler DB path, default temp DB
  --use-existing-rust-db        Do not override HUB_DB_PATH
  --scenario <name>             normal, queued-cancel, or queued-timeout
  --runs <n>                    Generate runs, default 1
  --concurrency <n>             Concurrent Generate calls per run, default 1
  --queue-timeout-ms <n>        Hub paid AI queue timeout, default 20000 or 1000 for queued-timeout
  --timeout-ms <n>              Authority/report wait timeout, default 30000
  --poll-ms <n>                 Authority/report polling interval, default 100
  --status-sample-ms <n>        Non-blocking scheduler status sample interval, default 100
  --bridge-timeout-sec <n>      Hub Bridge AI timeout, default 5
  --bridge-response-delay-ms <n> Fake Bridge response delay, default 1500 when concurrency > 2
  --min-compare-reports <n>     Authority readiness threshold, default 0
  --min-lease-shadow-runs <n>   Authority readiness threshold, default 0
  --model-id <id>               Paid model id to seed/request, default openai/gpt-5.4
  --request-prefix <id>         Stable request prefix for report filtering
  --expect-queued               Fail unless a Rust scheduler queued state is observed
  --allow-active-runs           Kept for compatibility; active runs are allowed by default
  --disallow-active-runs        Require readiness to fail while active authority runs exist
  --allow-failure               Do not fail when Generate returns done.ok=false
  --allow-dirty-scheduler       Do not fail when Rust scheduler is not clean after release
  --keep-temp                   Keep temp runtime/Bridge/DB files
  --dry-run                     Print resolved config
  --self-test                   Run local parser/fake-Bridge tests
`;
}

if (require.main === module) {
  main(process.argv.slice(2))
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error) => {
      process.stderr.write(`${error.stack || error.message}\n`);
      process.exitCode = 1;
    });
}
