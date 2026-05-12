#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const { createRequire } = require('node:module');
const { spawn, execFile, execFileSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');

async function main(argv) {
  const flags = parseFlags(argv);
  if (flags.has('help') || flags.has('h')) {
    process.stdout.write(helpText());
    return 0;
  }
  if (flags.has('self-test')) {
    await runSelfTest();
    process.stdout.write('node_hub_authority_live_runner self-test ok\n');
    return 0;
  }

  const config = await resolveConfig(flags);
  if (flags.has('dry-run')) {
    process.stdout.write(JSON.stringify({
      schema_version: 'xhub.node_hub_authority_live_runner.dry_run.v1',
      ok: true,
      config: publicConfig(config),
    }, null, 2) + '\n');
    return 0;
  }

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub_node_authority_live_'));
  const runtimeBaseDir = path.join(tempRoot, 'runtime');
  const bridgeBaseDir = path.join(tempRoot, 'bridge');
  const sharedDbPath = config.dbPath || path.join(tempRoot, 'hub.sqlite3');
  let fakeBridge = null;
  let child = null;
  let childExit = null;
  let stopRequested = false;

  const stop = () => {
    stopRequested = true;
    if (child && !child.killed) {
      try {
        child.kill('SIGTERM');
      } catch {
        // ignore
      }
    }
  };
  process.once('SIGINT', stop);
  process.once('SIGTERM', stop);

  try {
    fs.mkdirSync(runtimeBaseDir, { recursive: true });
    fs.mkdirSync(bridgeBaseDir, { recursive: true });
    fs.mkdirSync(path.dirname(sharedDbPath), { recursive: true });

    await seedNodeHubDb(config, sharedDbPath);
    const clientEntry = makeClientEntry(config);
    writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
    fakeBridge = startFakeBridge({
      bridgeBaseDir,
      responseText: config.bridgeResponseText,
      pollMs: config.bridgePollMs,
      responseDelayMs: config.bridgeResponseDelayMs,
    });

    const nodeEnv = buildNodeHubEnv({
      config,
      runtimeBaseDir,
      bridgeBaseDir,
      sharedDbPath,
    });
    const rustRunnerEnv = buildRustRunnerEnv(config, nodeEnv);
    const runIdPrefix = `node_paid_ai_authority_${config.requestPrefix}`;
    const before = readLeaseShadowReport(config.runner, {
      runIdPrefix,
      staleAfterMs: config.staleAfterMs,
      limit: config.reportLimit,
      env: rustRunnerEnv,
    });

    emitEvent('start', {
      config: publicConfig(config),
      runtime_base_dir: runtimeBaseDir,
      bridge_base_dir: bridgeBaseDir,
      shared_db_path: sharedDbPath,
      lease_shadow_before: before,
    });

    child = startNodeHub(config, nodeEnv, (status) => {
      childExit = status;
    });
    await waitForPort({
      host: config.hubHost,
      port: config.hubPort,
      timeoutMs: config.startTimeoutMs,
    });
    emitEvent('node_hub_ready', {
      node_pid: child.pid || 0,
      hub_host: config.hubHost,
      hub_port: config.hubPort,
    });

    const { proto, grpc } = loadGrpcClientDeps(config);
    const aiClient = new proto.HubAI(
      `${config.hubHost}:${config.hubPort}`,
      grpc.credentials.createInsecure(),
      grpcSizeOptions(config.grpcMaxMessageMb)
    );

    const iterations = [];
    for (let index = 0; index < config.runs; index += 1) {
      if (childExit && !stopRequested) {
        throw new Error(`Node Hub exited before run ${index + 1}: ${JSON.stringify(childExit)}`);
      }

      if (config.scenario !== 'normal') {
        const item = await runQueuedTerminalScenario({
          aiClient,
          grpc,
          clientEntry,
          config,
          runIndex: index + 1,
          runner: config.runner,
          runIdPrefix,
          fakeBridge,
          nodeEnv,
          rustRunnerEnv,
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
            env: rustRunnerEnv,
          })
        : null;

      const settled = await Promise.all(requestIds.map((requestId, requestIndex) => {
        return runGenerateStream({
          aiClient,
          grpc,
          token: clientEntry.token,
          request: makeGenerateRequest({
            requestId,
            requestIndex,
            clientEntry,
            config,
          }),
          timeoutMs: config.timeoutMs,
        });
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
          env: rustRunnerEnv,
        });
      }
      const authorityRows = new Map(
        (Array.isArray(latestReport?.recent) ? latestReport.recent : [])
          .map((row) => [String(row?.request_id || ''), row])
          .filter((row) => row[0])
      );
      const requests = settled.map((result) => ({
        ...result,
        authority_run: authorityRows.get(String(result.request_id || '')) || null,
      }));
      const status = readSchedulerStatus(config.runner, rustRunnerEnv);
      const schedulerClean = schedulerStatusClean(status);
      const queuedObserved = sampleSummary.max_queue_depth > 0;
      const item = {
        run_index: index + 1,
        request_count: requestIds.length,
        request_ids: requestIds,
        queued_observed: queuedObserved,
        status_samples: sampleSummary,
        requests,
        scheduler_clean: schedulerClean,
        bridge_requests_seen: fakeBridge.requests.length,
      };
      iterations.push(item);
      emitEvent('iteration', item);

      const failed = requests.filter((result) => !result.ok || !result.generate?.done_ok);
      if (config.expectSuccess && failed.length > 0) {
        throw new Error(`Generate did not complete ok for ${failed.map((item) => item.request_id).join(',')}`);
      }
      if (config.expectQueued && !queuedObserved) {
        throw new Error(`Rust scheduler queue was not observed for run ${index + 1}: ${JSON.stringify(sampleSummary)}`);
      }
      if (config.expectClean && !schedulerClean) {
        throw new Error(`Rust scheduler not clean after run ${index + 1}: ${JSON.stringify(status)}`);
      }
    }

    const after = readLeaseShadowReport(config.runner, {
      runIdPrefix,
      staleAfterMs: config.staleAfterMs,
      limit: config.reportLimit,
      env: rustRunnerEnv,
    });
    const finalStatus = readSchedulerStatus(config.runner, rustRunnerEnv);
    const ok = !stopRequested
      && (!config.expectClean || schedulerStatusClean(finalStatus))
      && (config.scenario === 'normal'
        ? (!config.expectSuccess || iterations.every((item) => batchGenerateOk(item)))
        : iterations.every((item) => item.scenario_ok === true))
      && (!config.expectQueued || iterations.every((item) => item.queued_observed === true));

    emitEvent('stop', {
      ok,
      node_hub_exit: childExit,
      lease_shadow_after: after,
      scheduler_status_after: finalStatus,
      bridge_requests: fakeBridge.requests,
      iterations,
    });
    return ok ? 0 : 2;
  } finally {
    process.removeListener('SIGINT', stop);
    process.removeListener('SIGTERM', stop);
    if (child && !child.killed) {
      await terminateChild(child);
    }
    if (fakeBridge) fakeBridge.stop();
    if (!config.keepTemp) {
      try {
        fs.rmSync(tempRoot, { recursive: true, force: true });
      } catch {
        // ignore
      }
    }
  }
}

async function seedNodeHubDb(config, dbPath) {
  const dbModule = await import(pathToFileURL(path.join(config.nodeHubDir, 'src', 'db.js')).href);
  const db = new dbModule.HubDB({ dbPath });
  try {
    db.db.prepare(
      `INSERT OR REPLACE INTO models(model_id,name,kind,backend,context_length,requires_grant,enabled,updated_at_ms)
       VALUES(?,?,?,?,?,?,?,?)`
    ).run(
      config.modelId,
      'Authority Live Runner Paid Model',
      'paid_online',
      'openai',
      128000,
      1,
      1,
      Date.now()
    );
  } finally {
    db.close?.();
  }
}

function buildNodeHubEnv({ config, runtimeBaseDir, bridgeBaseDir, sharedDbPath }) {
  const env = {
    ...process.env,
    HUB_HOST: config.hubHost,
    HUB_PORT: String(config.hubPort),
    HUB_DB_PATH: sharedDbPath,
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_BRIDGE_BASE_DIR: bridgeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_PAIRING_ENABLE: '0',
    HUB_AUDIT_LEVEL: 'metadata_only',
    HUB_MEMORY_AT_REST_ENABLED: 'false',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
    HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS: '50',
    HUB_BRIDGE_AI_TIMEOUT_SEC: String(config.bridgeTimeoutSec),
    HUB_PAID_AI_QUEUE_TIMEOUT_MS: String(config.queueTimeoutMs),
    HUB_GRPC_TLS_MODE: 'insecure',
    XHUB_RUST_HUB_ROOT: config.rustHubRoot,
    XHUB_RUST_HUB_RUNNER: config.runner,
    XHUB_RUST_SCHEDULER_AUTHORITY: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_FALLBACK_ON_ERROR: '0',
    XHUB_RUST_SCHEDULER_AUTHORITY_TIMEOUT_MS: String(config.timeoutMs),
    XHUB_RUST_SCHEDULER_AUTHORITY_POLL_MS: String(config.pollMs),
    XHUB_RUST_SCHEDULER_AUTHORITY_READINESS_CACHE_MS: '0',
    XHUB_RUST_SCHEDULER_AUTHORITY_LEASE_DURATION_MS: String(config.leaseDurationMs),
    XHUB_RUST_SCHEDULER_AUTHORITY_MIN_COMPARE_REPORTS: String(config.minCompareReports),
    XHUB_RUST_SCHEDULER_AUTHORITY_MAX_MISMATCHES: String(config.maxMismatches),
    XHUB_RUST_SCHEDULER_AUTHORITY_MIN_LEASE_SHADOW_RUNS: String(config.minLeaseShadowRuns),
    XHUB_RUST_SCHEDULER_AUTHORITY_MAX_STALE_ACTIVE: String(config.maxStaleActive),
    XHUB_RUST_SCHEDULER_AUTHORITY_MAX_ORPHANED_LEASES: String(config.maxOrphanedLeases),
    XHUB_RUST_SCHEDULER_AUTHORITY_ALLOW_ACTIVE_RUNS: config.allowActiveRuns ? '1' : '0',
    XHUB_RUST_SCHEDULER_STATUS_READ: '1',
    XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY: '1',
  };
  if (config.useExistingRustDb) {
    env.XHUB_RUST_SCHEDULER_AUTHORITY_DB_PATH = config.rustSchedulerDbPath;
  }
  return env;
}

function buildRustRunnerEnv(config, baseEnv = process.env) {
  if (!config.useExistingRustDb) return baseEnv;
  return {
    ...baseEnv,
    HUB_DB_PATH: config.rustSchedulerDbPath,
  };
}

function startNodeHub(config, nodeEnv, onExit = () => {}) {
  const serverPath = path.join(config.nodeHubDir, 'src', 'server.js');
  if (!fs.existsSync(serverPath)) {
    throw new Error(`Node Hub server not found: ${serverPath}`);
  }
  const child = spawn(config.nodeBin, ['src/server.js'], {
    cwd: config.nodeHubDir,
    env: nodeEnv,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  pipePrefixed(child.stdout, 'node_hub_stdout');
  pipePrefixed(child.stderr, 'node_hub_stderr');
  child.on('exit', (code, signal) => {
    const status = {
      code: code == null ? null : code,
      signal: signal || '',
    };
    onExit(status);
    emitEvent('node_hub_exit', status);
  });
  child.on('error', (error) => {
    const status = {
      code: null,
      signal: '',
      error: error.message,
    };
    onExit(status);
    emitEvent('node_hub_error', { message: error.message });
  });
  return child;
}

function pipePrefixed(stream, event) {
  let buffer = '';
  stream?.on?.('data', (chunk) => {
    buffer += String(chunk || '');
    for (;;) {
      const index = buffer.indexOf('\n');
      if (index < 0) break;
      const line = buffer.slice(0, index).trimEnd();
      buffer = buffer.slice(index + 1);
      if (line) emitEvent(event, { line });
    }
  });
}

async function terminateChild(child) {
  if (!child || child.killed) return;
  const exited = new Promise((resolve) => {
    child.once('exit', resolve);
  });
  try {
    child.kill('SIGTERM');
  } catch {
    return;
  }
  const timeout = sleep(3000).then(() => 'timeout');
  const result = await Promise.race([exited, timeout]);
  if (result === 'timeout' && !child.killed) {
    try {
      child.kill('SIGKILL');
    } catch {
      // ignore
    }
  }
}

function loadGrpcClientDeps(config) {
  const requireFromNodeHub = createRequire(path.join(config.nodeHubDir, 'package.json'));
  const grpc = requireFromNodeHub('@grpc/grpc-js');
  const protoLoader = requireFromNodeHub('@grpc/proto-loader');
  const packageDef = protoLoader.loadSync(config.protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  const proto = loaded?.ax?.hub?.v1;
  if (!proto?.HubAI) throw new Error('failed to load proto HubAI client');
  return { grpc, proto };
}

function grpcSizeOptions(maxMessageMb) {
  const bytes = Math.max(4, Math.min(256, Number(maxMessageMb || 32))) * 1024 * 1024;
  return {
    'grpc.max_receive_message_length': bytes,
    'grpc.max_send_message_length': bytes,
  };
}

function metadataForToken(grpc, token) {
  const md = new grpc.Metadata();
  if (token) md.set('authorization', `Bearer ${token}`);
  return md;
}

function runGenerateStream(args) {
  return startGenerateStreamTask(args).promise;
}

function startGenerateStreamTask({ aiClient, grpc, token, request, timeoutMs }) {
  const requestId = String(request?.request_id || '');
  const task = {
    requestId,
    stream: null,
    promise: null,
    cancel() {
      try {
        task.stream?.cancel?.();
      } catch {
        // ignore
      }
    },
  };
  task.promise = new Promise((resolve) => {
    const md = metadataForToken(grpc, token);
    const stream = aiClient.Generate(request, md);
    task.stream = stream;
    const events = [];
    let settled = false;
    const finish = (payload) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({
        request_id: requestId,
        ...payload,
        generate: summarizeGenerateEvents(events),
      });
    };
    const timer = setTimeout(() => {
      try {
        stream.cancel();
      } catch {
        // ignore
      }
      finish({
        ok: false,
        error_message: `timeout after ${timeoutMs}ms`,
      });
    }, Math.max(1000, Number(timeoutMs || 30000)));
    if (typeof timer.unref === 'function') timer.unref();
    stream.on('data', (event) => {
      events.push(event);
    });
    stream.on('end', () => {
      finish({ ok: true });
    });
    stream.on('error', (error) => {
      finish({
        ok: false,
        error_message: String(error?.message || error),
      });
    });
  });
  return task;
}

async function runQueuedTerminalScenario({
  aiClient,
  grpc,
  clientEntry,
  config,
  runIndex,
  runner,
  runIdPrefix,
  fakeBridge,
  nodeEnv,
  rustRunnerEnv,
}) {
  const requestIds = Array.from({ length: 3 }, (_, requestIndex) => (
    `${config.requestPrefix}_${runIndex}_${requestIndex + 1}`
  ));
  const sampler = startStatusSampler({
    runner,
    intervalMs: config.statusSampleMs,
    timeoutMs: config.statusSampleTimeoutMs,
    env: rustRunnerEnv,
  });
  const tasks = [];
  try {
    tasks.push(startGenerateStreamTask({
      aiClient,
      grpc,
      token: clientEntry.token,
      request: makeGenerateRequest({
        requestId: requestIds[0],
        requestIndex: 0,
        clientEntry,
        config,
      }),
      timeoutMs: config.timeoutMs,
    }));
    tasks.push(startGenerateStreamTask({
      aiClient,
      grpc,
      token: clientEntry.token,
      request: makeGenerateRequest({
        requestId: requestIds[1],
        requestIndex: 1,
        clientEntry,
        config,
      }),
      timeoutMs: config.timeoutMs,
    }));

    await waitForStatusCondition({
      runner,
      timeoutMs: config.timeoutMs,
      pollMs: config.pollMs,
      env: rustRunnerEnv,
      label: 'first two live authority leases',
      predicate: (status) => safeInt(status?.in_flight_total) >= 2,
    });

    const queuedTask = startGenerateStreamTask({
      aiClient,
      grpc,
      token: clientEntry.token,
      request: makeGenerateRequest({
        requestId: requestIds[2],
        requestIndex: 2,
        clientEntry,
        config,
      }),
      timeoutMs: config.timeoutMs,
    });
    tasks.push(queuedTask);

    await waitForStatusCondition({
      runner,
      timeoutMs: config.timeoutMs,
      pollMs: config.pollMs,
      env: rustRunnerEnv,
      label: 'queued live authority run',
      predicate: (status) => safeInt(status?.queue_depth) >= 1,
    });

    if (config.scenario === 'queued-cancel') {
      queuedTask.cancel();
    }

    const settled = await Promise.all(tasks.map((task) => task.promise));
    await sampler.stop();
    const sampleSummary = summarizeStatusSamples(sampler.samples);

    const expectedQueuedStatus = 'canceled';
    const expectedGenerate = config.scenario === 'queued-timeout'
      ? { error_code: 'hub_ai_queue_timeout' }
      : { client_cancelled: true };
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
        env: rustRunnerEnv,
      });
    }
    const authorityRows = new Map(
      (Array.isArray(latestReport?.recent) ? latestReport.recent : [])
        .map((row) => [String(row?.request_id || ''), row])
        .filter((row) => row[0])
    );
    const requests = settled.map((result) => ({
      ...result,
      authority_run: authorityRows.get(String(result.request_id || '')) || null,
    }));
    const blockersOk = requests.slice(0, 2).every((result) => (
      result.ok === true
      && result.generate?.done_ok === true
      && result.authority_run?.status === 'completed'
    ));
    const queued = requests[2] || {};
    const queuedAuthorityOk = queued.authority_run?.status === expectedQueuedStatus;
    const queuedGenerateOk = config.scenario === 'queued-timeout'
      ? queued.generate?.error_code === expectedGenerate.error_code
      : (
        queued.ok === false
        || queued.generate?.done_reason === 'canceled'
        || queued.generate?.error_code === 'canceled'
      );
    const finalStatus = readSchedulerStatus(runner, rustRunnerEnv);
    const clean = schedulerStatusClean(finalStatus);
    const queuedObserved = sampleSummary.max_queue_depth > 0;
    return {
      run_index: runIndex,
      scenario: config.scenario,
      request_count: requestIds.length,
      request_ids: requestIds,
      queued_observed: queuedObserved,
      status_samples: sampleSummary,
      requests,
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

function makeClientEntry(config) {
  const capabilities = ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'];
  return {
    device_id: config.deviceId,
    user_id: config.userId,
    name: 'Rust Scheduler Authority Live Runner',
    token: `tok_authority_live_${process.pid}_${Date.now()}_${Math.random().toString(16).slice(2)}`,
    enabled: true,
    capabilities,
    policy_mode: 'new_profile',
    approved_trust_profile: {
      schema_version: 'hub.paired_terminal_trust_profile.v1',
      device_id: config.deviceId,
      device_name: 'Rust Scheduler Authority Live Runner',
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
      audit_ref: 'audit-rust-scheduler-authority-live-runner',
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

function makeGenerateRequest({ requestId, requestIndex, clientEntry, config }) {
  return {
    request_id: requestId,
    model_id: config.modelId,
    max_tokens: config.maxTokens,
    temperature: 0.1,
    top_p: 0.95,
    stream: true,
    created_at_ms: Date.now(),
    messages: [
      {
        role: 'user',
        content: `hello from rust scheduler live authority runner ${requestIndex + 1}`,
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

function summarizeGenerateEvents(events) {
  const writes = Array.isArray(events) ? events : [];
  const done = [...writes].reverse().find((item) => item?.done)?.done || null;
  const error = [...writes].reverse().find((item) => item?.error)?.error || null;
  const deltas = writes.filter((item) => item?.delta);
  const start = writes.find((item) => item?.start)?.start || null;
  return {
    event_count: writes.length,
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
  env,
}) {
  const started = Date.now();
  let latest = readLeaseShadowReport(runner, { runIdPrefix, staleAfterMs, limit, env });
  while (Date.now() - started <= timeoutMs) {
    const row = (Array.isArray(latest?.recent) ? latest.recent : [])
      .find((item) => String(item?.request_id || '') === String(requestId || ''));
    if (row && String(row.status || '') === 'completed') return latest;
    await sleep(pollMs);
    latest = readLeaseShadowReport(runner, { runIdPrefix, staleAfterMs, limit, env });
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
  env,
}) {
  const started = Date.now();
  let latest = readLeaseShadowReport(runner, { runIdPrefix, staleAfterMs, limit, env });
  while (Date.now() - started <= timeoutMs) {
    const row = (Array.isArray(latest?.recent) ? latest.recent : [])
      .find((item) => String(item?.request_id || '') === String(requestId || ''));
    if (row && String(row.status || '') === String(expectedStatus || '')) return latest;
    await sleep(pollMs);
    latest = readLeaseShadowReport(runner, { runIdPrefix, staleAfterMs, limit, env });
  }
  throw new Error(`authority run ${requestId} did not reach ${expectedStatus} within ${timeoutMs}ms`);
}

function readLeaseShadowReport(runner, { runIdPrefix, staleAfterMs, limit, env }) {
  return readRunnerJson(runner, [
    'scheduler',
    'lease-shadow-report',
    '--run-id-prefix',
    runIdPrefix,
    '--stale-after-ms',
    String(staleAfterMs),
    '--limit',
    String(limit),
  ], env);
}

function readSchedulerStatus(runner, env) {
  return readRunnerJson(runner, [
    'scheduler',
    'status',
    '--include-queue-items',
    '--queue-items-limit',
    '20',
  ], env);
}

function startStatusSampler({ runner, intervalMs, timeoutMs, env }) {
  let stopped = false;
  const samples = [];
  const loop = (async () => {
    while (!stopped) {
      const started = Date.now();
      try {
        const status = await readSchedulerStatusAsync(runner, timeoutMs, env);
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

async function readSchedulerStatusAsync(runner, timeoutMs, env) {
  return await readRunnerJsonAsync(runner, [
    'scheduler',
    'status',
    '--include-queue-items',
    '--queue-items-limit',
    '20',
  ], timeoutMs, env);
}

async function waitForStatusCondition({ runner, timeoutMs, pollMs, env, predicate, label }) {
  const started = Date.now();
  let latest = await readSchedulerStatusAsync(runner, timeoutMs, env);
  while (Date.now() - started <= timeoutMs) {
    if (predicate(latest)) return latest;
    await sleep(pollMs);
    latest = await readSchedulerStatusAsync(runner, timeoutMs, env);
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

function readRunnerJson(runner, args, env) {
  const stdout = execFileSync(runner, args, {
    encoding: 'utf8',
    env: env || process.env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  return JSON.parse(stdout);
}

async function readRunnerJsonAsync(runner, args, timeoutMs, env) {
  const stdout = await new Promise((resolve, reject) => {
    execFile(runner, args, {
      encoding: 'utf8',
      env: env || process.env,
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

async function waitForPort({ host, port, timeoutMs }) {
  const started = Date.now();
  while (Date.now() - started <= timeoutMs) {
    if (await canConnect({ host, port })) return true;
    await sleep(100);
  }
  throw new Error(`Node Hub did not accept gRPC connections at ${host}:${port} within ${timeoutMs}ms`);
}

function canConnect({ host, port }) {
  return new Promise((resolve) => {
    const socket = net.connect({ host, port });
    const done = (ok) => {
      socket.removeAllListeners();
      try {
        socket.destroy();
      } catch {
        // ignore
      }
      resolve(ok);
    };
    socket.setTimeout(250);
    socket.once('connect', () => done(true));
    socket.once('timeout', () => done(false));
    socket.once('error', () => done(false));
  });
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

async function resolveConfig(flags) {
  const rustHubRoot = path.resolve(flags.get('rust-hub-root') || path.join(__dirname, '..'));
  const xhubSystemRoot = path.resolve(flags.get('xhub-system-root') || findXHubSystemRoot(rustHubRoot));
  const nodeHubDir = path.resolve(
    flags.get('node-hub-dir')
      || path.join(xhubSystemRoot, 'x-hub', 'grpc-server', 'hub_grpc_server')
  );
  const runner = path.resolve(flags.get('runner') || path.join(rustHubRoot, 'tools', 'run_rust_hub.command'));
  const protoPath = path.resolve(flags.get('proto-path') || path.join(xhubSystemRoot, 'protocol', 'hub_protocol_v1.proto'));
  const nodeBin = path.resolve(flags.get('node-bin') || process.execPath);
  const hubHost = String(flags.get('hub-host') || '127.0.0.1').trim();
  const hubPort = flags.has('hub-port')
    ? parseIntFlag(flags, 'hub-port', 0, 1)
    : pickLikelyFreePort();
  const scenario = normalizeScenario(flags.get('scenario') || 'normal');
  const requestedConcurrency = parseIntFlag(flags, 'concurrency', scenario === 'normal' ? 1 : 3, 1);
  const concurrency = scenario === 'normal' ? requestedConcurrency : Math.max(3, requestedConcurrency);
  const queueTimeoutMs = parseIntFlag(flags, 'queue-timeout-ms', scenario === 'queued-timeout' ? 1000 : 20000, 1000);
  const bridgeResponseDelayMs = flags.has('bridge-response-delay-ms')
    ? parseIntFlag(flags, 'bridge-response-delay-ms', 0, 0)
    : (scenario === 'queued-timeout'
      ? Math.max(3000, queueTimeoutMs + 1500)
      : scenario === 'queued-cancel'
        ? 3000
      : (concurrency > 2 ? 1500 : 0));
  const requestPrefix = normalizeSafeId(
    flags.get('request-prefix')
      || `node_authority_live_${process.pid}_${Date.now()}_${Math.random().toString(16).slice(2)}`
  );
  return {
    rustHubRoot,
    xhubSystemRoot,
    nodeHubDir,
    runner,
    protoPath,
    nodeBin,
    hubHost,
    hubPort,
    scenario,
    dbPath: flags.has('db-path') ? path.resolve(flags.get('db-path')) : '',
    useExistingRustDb: flagEnabled(flags, 'use-existing-rust-db'),
    rustSchedulerDbPath: flags.has('rust-scheduler-db-path')
      ? path.resolve(flags.get('rust-scheduler-db-path'))
      : path.join(rustHubRoot, 'data', 'hub.sqlite3'),
    runs: parseIntFlag(flags, 'runs', 1, 1),
    concurrency,
    queueTimeoutMs,
    timeoutMs: parseIntFlag(flags, 'timeout-ms', 45000, 1000),
    startTimeoutMs: parseIntFlag(flags, 'start-timeout-ms', 10000, 1000),
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
    projectId: String(flags.get('project-id') || 'authority-live-project').trim(),
    deviceId: String(flags.get('device-id') || 'authority-live-device').trim(),
    userId: String(flags.get('user-id') || 'authority-live-user').trim(),
    appId: String(flags.get('app-id') || 'xhub-authority-live-runner').trim(),
    bridgeResponseText: String(flags.get('bridge-response-text') || 'rust scheduler authority live runner ok').trim(),
    grpcMaxMessageMb: parseIntFlag(flags, 'grpc-max-message-mb', 32, 4),
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
    node_hub_dir: config.nodeHubDir,
    runner: config.runner,
    proto_path: config.protoPath,
    node_bin: config.nodeBin,
    hub_host: config.hubHost,
    hub_port: config.hubPort,
    scenario: config.scenario,
    db_path: config.dbPath || '(temp)',
    use_existing_rust_db: config.useExistingRustDb,
    rust_scheduler_db_path: config.useExistingRustDb ? config.rustSchedulerDbPath : '',
    runs: config.runs,
    concurrency: config.concurrency,
    queue_timeout_ms: config.queueTimeoutMs,
    timeout_ms: config.timeoutMs,
    start_timeout_ms: config.startTimeoutMs,
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

function pickLikelyFreePort() {
  return 55000 + ((process.pid + Date.now()) % 4000);
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

function normalizeScenario(value) {
  const scenario = String(value || '').trim().toLowerCase() || 'normal';
  if (['normal', 'queued-cancel', 'queued-timeout'].includes(scenario)) return scenario;
  throw new Error(`unsupported --scenario ${scenario}`);
}

function findXHubSystemRoot(startDir) {
  let current = path.resolve(startDir);
  for (;;) {
    const candidate = path.join(current, 'x-hub-system');
    if (fs.existsSync(path.join(candidate, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src', 'server.js'))) {
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

function emitEvent(event, payload = {}) {
  process.stdout.write(JSON.stringify({
    schema_version: 'xhub.node_hub_authority_live_runner.v1',
    event,
    at_ms: Date.now(),
    ...payload,
  }) + '\n');
}

async function runSelfTest() {
  const flags = parseFlags([
    '--runs',
    '2',
    '--timeout-ms=5000',
    '--scenario',
    'queued-timeout',
    '--concurrency',
    '3',
    '--expect-queued',
    '--request-prefix',
    'abc 123',
  ]);
  const config = await resolveConfig(flags);
  assert.equal(config.scenario, 'queued-timeout');
  assert.equal(config.runs, 2);
  assert.equal(config.concurrency, 3);
  assert.equal(config.queueTimeoutMs, 1000);
  assert.equal(config.timeoutMs, 5000);
  assert.equal(config.expectQueued, true);
  assert.equal(config.expectSuccess, false);
  assert.equal(config.requestPrefix, 'abc_123');
  assert.ok(config.hubPort > 0);
  assert.equal(schedulerStatusClean({ in_flight_total: '0', queue_depth: 0 }), true);
  assert.equal(schedulerStatusClean({ in_flight_total: '1', queue_depth: 0 }), false);
  assert.equal(summarizeGenerateEvents([
    { start: {} },
    { delta: { text: 'ok' } },
    { done: { ok: true, actual_model_id: 'm', execution_path: 'remote_model' } },
  ]).done_ok, true);
}

function helpText() {
  return `Usage:
  node tools/node_hub_authority_live_runner.js [options]

Options:
  --rust-hub-root <path>        Rust Hub root, default parent of this tools dir
  --xhub-system-root <path>     x-hub-system root, auto-detected
  --node-hub-dir <path>         Existing Node Hub grpc-server dir
  --runner <path>               Rust Hub runner command
  --proto-path <path>           Hub proto path, default x-hub-system/protocol
  --node-bin <path>             Node binary, default current process
  --hub-host <host>             Node Hub bind/connect host, default 127.0.0.1
  --hub-port <n>                Node Hub port, default free local port
  --db-path <path>              Shared Node/Rust DB path, default temp DB
  --use-existing-rust-db        Keep Node DB separate and point Rust authority at the default Rust DB
  --rust-scheduler-db-path <p>  Rust authority DB path when --use-existing-rust-db is set
  --scenario <name>             normal, queued-cancel, or queued-timeout
  --runs <n>                    Generate batches, default 1
  --concurrency <n>             Concurrent Generate calls per batch, default 1
  --queue-timeout-ms <n>        Hub paid AI queue timeout, default 20000 or 1000 for queued-timeout
  --timeout-ms <n>              Generate/report wait timeout, default 45000
  --start-timeout-ms <n>        Node Hub start wait timeout, default 10000
  --poll-ms <n>                 Authority/report polling interval, default 100
  --status-sample-ms <n>        Scheduler status sample interval, default 100
  --bridge-timeout-sec <n>      Hub Bridge AI timeout, default 5
  --bridge-response-delay-ms <n> Fake Bridge response delay, default 1500 when concurrency > 2
  --min-compare-reports <n>     Authority readiness threshold, default 0
  --min-lease-shadow-runs <n>   Authority readiness threshold, default 0
  --model-id <id>               Paid model id to seed/request, default openai/gpt-5.4
  --request-prefix <id>         Stable request prefix for report filtering
  --expect-queued               Fail unless a Rust scheduler queued state is observed
  --disallow-active-runs        Require readiness to fail while active authority runs exist
  --allow-failure               Do not fail when Generate returns done.ok=false
  --allow-dirty-scheduler       Do not fail when Rust scheduler is not clean after release
  --keep-temp                   Keep temp runtime/Bridge/DB files
  --dry-run                     Print resolved config
  --self-test                   Run local parser/summary tests
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
