import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { URL, fileURLToPath } from 'node:url';

const MODULE_DIR = path.dirname(fileURLToPath(import.meta.url));

function safeString(value) {
  return String(value ?? '').trim();
}

function parseBoolEnv(value, fallback = false) {
  if (value == null) return fallback;
  const normalized = String(value).trim().toLowerCase();
  if (!normalized) return fallback;
  if (['1', 'true', 'yes', 'y', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(normalized)) return false;
  return fallback;
}

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function resolveRustHubRoot(env = process.env) {
  const explicit = safeString(env.XHUB_RUST_HUB_ROOT);
  if (explicit) return explicit;
  const sourceRoot = safeString(env.XHUB_SYSTEM_ROOT);
  if (sourceRoot) return path.resolve(sourceRoot, '..', 'rust', 'rust hub');
  return path.resolve(MODULE_DIR, '..', '..', '..', '..', '..', 'rust', 'rust hub');
}

export function resolveSchedulerLeaseShadowConfig(env = process.env) {
  const root = resolveRustHubRoot(env);
  const httpHost = safeString(env.XHUB_RUST_HUB_HOST) || '127.0.0.1';
  const httpPort = parseIntInRange(env.XHUB_RUST_HUB_HTTP_PORT, 50151, 1, 65535);
  return {
    enabled: parseBoolEnv(env.XHUB_RUST_SCHEDULER_LEASE_SHADOW, false),
    root,
    runnerPath: safeString(env.XHUB_RUST_HUB_RUNNER)
      || safeString(env.XHUB_RUST_SCHEDULER_BRIDGE_RUNNER)
      || path.join(root, 'tools', 'run_rust_hub.command'),
    timeoutMs: parseIntInRange(env.XHUB_RUST_SCHEDULER_LEASE_SHADOW_TIMEOUT_MS, 5000, 250, 30000),
    httpEnabled: parseBoolEnv(env.XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP, false),
    httpBaseUrl: safeString(env.XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_BASE_URL)
      || `http://${httpHost}:${httpPort}`,
    httpTimeoutMs: parseIntInRange(
      env.XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_TIMEOUT_MS,
      750,
      100,
      60000
    ),
    httpFallbackToCli: parseBoolEnv(
      env.XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_FALLBACK_TO_CLI
        ?? env.XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_FALLBACK_CLI,
      true
    ),
    leaseOwner: safeString(env.XHUB_RUST_SCHEDULER_LEASE_SHADOW_OWNER) || 'node-hub-paid-ai-shadow',
    leaseDurationMs: parseIntInRange(
      env.XHUB_RUST_SCHEDULER_LEASE_SHADOW_DURATION_MS,
      300000,
      1000,
      3600000
    ),
    verbose: parseBoolEnv(env.XHUB_RUST_SCHEDULER_LEASE_SHADOW_VERBOSE, false),
  };
}

export function schedulerShadowRunId(requestId) {
  const raw = safeString(requestId);
  if (!raw) return '';
  const normalized = raw.replace(/[^a-zA-Z0-9_.:-]+/g, '_').slice(0, 180);
  return `node_paid_ai_${normalized}`;
}

export function buildSchedulerLeaseArgs(action, input = {}, config = resolveSchedulerLeaseShadowConfig({})) {
  const requestId = safeString(input.requestId || input.request_id);
  const runId = safeString(input.runId || input.run_id) || schedulerShadowRunId(requestId);
  const scopeKey = safeString(input.scopeKey || input.scope_key) || 'unknown';
  switch (action) {
    case 'enqueue':
      return [
        'scheduler',
        'enqueue',
        '--run-id',
        runId,
        '--request-id',
        requestId,
        '--scope-key',
        scopeKey,
        '--idempotency-key',
        requestId || runId,
        '--task-type',
        'paid_ai',
        '--payload-json',
        JSON.stringify(input.payload && typeof input.payload === 'object' ? input.payload : {}),
        ...optionalFlag('project-id', input.project_id),
        ...optionalFlag('device-id', input.device_id),
      ];
    case 'acquire-run':
      return [
        'scheduler',
        'acquire-run',
        '--run-id',
        runId,
        '--lease-owner',
        config.leaseOwner,
        '--lease-duration-ms',
        String(config.leaseDurationMs),
      ];
    case 'release':
      return [
        'scheduler',
        'release',
        '--run-id',
        runId,
        '--lease-token',
        safeString(input.leaseToken || input.lease_token),
        '--outcome',
        safeString(input.outcome) || 'completed',
      ];
    case 'cancel':
      return [
        'scheduler',
        'cancel',
        '--run-id',
        runId,
        '--reason',
        safeString(input.reason) || 'canceled',
      ];
    default:
      throw new Error(`unknown scheduler lease shadow action: ${action}`);
  }
}

export function buildSchedulerLeaseHttpPayload(action, input = {}, config = resolveSchedulerLeaseShadowConfig({})) {
  const requestId = safeString(input.requestId || input.request_id);
  const runId = safeString(input.runId || input.run_id) || schedulerShadowRunId(requestId);
  const scopeKey = safeString(input.scopeKey || input.scope_key) || 'unknown';

  switch (action) {
    case 'enqueue':
      return {
        run_id: runId,
        request_id: requestId,
        scope_key: scopeKey,
        idempotency_key: requestId || runId,
        task_type: 'paid_ai',
        payload: input.payload && typeof input.payload === 'object' ? input.payload : {},
        ...(safeString(input.project_id) ? { project_id: safeString(input.project_id) } : {}),
        ...(safeString(input.device_id) ? { device_id: safeString(input.device_id) } : {}),
      };
    case 'acquire-run':
      return {
        run_id: runId,
        lease_owner: config.leaseOwner,
        lease_duration_ms: config.leaseDurationMs,
      };
    case 'release':
      return {
        run_id: runId,
        lease_token: safeString(input.leaseToken || input.lease_token),
        outcome: safeString(input.outcome) || 'completed',
      };
    case 'cancel':
      return {
        run_id: runId,
        reason: safeString(input.reason) || 'canceled',
      };
    default:
      throw new Error(`unknown scheduler lease shadow HTTP action: ${action}`);
  }
}

function optionalFlag(name, value) {
  const cleaned = safeString(value);
  return cleaned ? [`--${name}`, cleaned] : [];
}

function parseRunnerJson(stdout) {
  const lines = String(stdout || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  const jsonLine = [...lines].reverse().find((line) => line.startsWith('{'));
  if (!jsonLine) {
    throw new Error('rust_scheduler_shadow_empty_stdout');
  }
  const parsed = JSON.parse(jsonLine);
  if (!parsed || parsed.ok !== true) {
    throw new Error(`rust_scheduler_shadow_not_ok:${jsonLine.slice(0, 200)}`);
  }
  return parsed;
}

async function httpPostJson(url, payload, timeoutMs) {
  const parsedUrl = url instanceof URL ? url : new URL(String(url));
  if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
    throw new Error(`rust_scheduler_shadow_http_unsupported_protocol:${parsedUrl.protocol}`);
  }
  const body = JSON.stringify(payload || {});
  const client = parsedUrl.protocol === 'https:' ? https : http;
  const stdout = await new Promise((resolve, reject) => {
    const req = client.request(parsedUrl, {
      method: 'POST',
      timeout: timeoutMs,
      headers: {
        accept: 'application/json',
        'content-type': 'application/json',
        'content-length': Buffer.byteLength(body),
      },
    }, (res) => {
      let responseBody = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        responseBody += chunk;
        if (responseBody.length > 1024 * 1024) {
          req.destroy(new Error('rust_scheduler_shadow_http_response_too_large'));
        }
      });
      res.on('end', () => {
        const statusCode = Number(res.statusCode || 0);
        if (statusCode < 200 || statusCode >= 300) {
          reject(new Error(`rust_scheduler_shadow_http_status:${statusCode}:${responseBody.slice(0, 240)}`));
          return;
        }
        resolve(responseBody);
      });
    });
    req.on('timeout', () => req.destroy(new Error('rust_scheduler_shadow_http_timeout')));
    req.on('error', reject);
    req.write(body);
    req.end();
  });
  return parseRunnerJson(stdout);
}

export function createSchedulerLeaseShadowBridge({
  env = process.env,
  execFileImpl = execFile,
  httpPostJsonImpl = httpPostJson,
  existsSync = fs.existsSync,
  logger = console,
} = {}) {
  const config = resolveSchedulerLeaseShadowConfig(env);
  const runs = new Map();
  const warned = new Set();
  let chain = Promise.resolve();

  function warnOnce(key, line) {
    if (warned.has(key)) return;
    warned.add(key);
    logger.warn?.(line);
  }

  function canRun() {
    if (!config.enabled) return false;
    if (!config.httpEnabled && !existsSync(config.runnerPath)) {
      warnOnce(
        'missing_runner',
        `[hub_grpc] rust scheduler lease shadow disabled: missing runner=${config.runnerPath}`
      );
      return false;
    }
    return true;
  }

  function schedulerCommandHttpUrl(action) {
    const pathByAction = {
      enqueue: '/scheduler/enqueue',
      'acquire-run': '/scheduler/acquire-run',
      release: '/scheduler/release',
      cancel: '/scheduler/cancel',
    };
    return new URL(pathByAction[action] || `/scheduler/${action}`, config.httpBaseUrl);
  }

  function stateFor(requestId) {
    const rid = safeString(requestId);
    if (!rid) return null;
    const existing = runs.get(rid);
    if (existing) return existing;
    const created = {
      requestId: rid,
      runId: schedulerShadowRunId(rid),
      leaseToken: '',
      done: false,
    };
    runs.set(rid, created);
    return created;
  }

  function schedule(label, task) {
    if (!canRun()) return false;
    chain = chain
      .then(task, task)
      .catch((error) => {
        warnOnce(
          `op_failed_${label}`,
          `[hub_grpc] rust scheduler lease shadow ${label} failed: ${error.message || error}`
        );
      });
    return true;
  }

  async function execCliJson(args) {
    const stdout = await new Promise((resolve, reject) => {
      execFileImpl(config.runnerPath, args, {
        encoding: 'utf8',
        timeout: config.timeoutMs,
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
    return parseRunnerJson(stdout);
  }

  async function execJson(action, input = {}) {
    if (config.httpEnabled) {
      try {
        const out = await httpPostJsonImpl(
          schedulerCommandHttpUrl(action),
          buildSchedulerLeaseHttpPayload(action, input, config),
          config.httpTimeoutMs
        );
        if (config.verbose) {
          logger.log?.(`[hub_grpc] rust scheduler lease shadow HTTP ${action} ok`);
        }
        return out;
      } catch (error) {
        warnOnce(
          `http_${action}_failed`,
          `[hub_grpc] rust scheduler lease shadow HTTP ${action} failed; ${config.httpFallbackToCli ? 'falling back to CLI' : 'CLI fallback disabled'}: ${error.message || error}`
        );
        if (!config.httpFallbackToCli) {
          throw error;
        }
        if (!existsSync(config.runnerPath)) {
          throw new Error('rust_scheduler_shadow_cli_fallback_runner_missing');
        }
      }
    }
    return execCliJson(buildSchedulerLeaseArgs(action, input, config));
  }

  function mirrorEnqueue(input = {}) {
    const state = stateFor(input.requestId || input.request_id);
    if (!state) return false;
    return schedule('enqueue', async () => {
      if (state.done) return;
      const out = await execJson('enqueue', {
        ...input,
        requestId: state.requestId,
        runId: state.runId,
      });
      state.runId = safeString(out?.run?.run_id) || state.runId;
      if (config.verbose) {
        logger.log?.(`[hub_grpc] rust scheduler lease shadow enqueue request_id=${state.requestId}`);
      }
    });
  }

  function mirrorAcquire(input = {}) {
    const state = stateFor(input.requestId || input.request_id);
    if (!state) return false;
    return schedule('acquire-run', async () => {
      if (state.done) return;
      const out = await execJson('acquire-run', {
        ...input,
        requestId: state.requestId,
        runId: state.runId,
      });
      if (out.leased !== true) {
        throw new Error(`rust_scheduler_shadow_not_leased:${state.runId}`);
      }
      state.leaseToken = safeString(out.lease_token);
      if (config.verbose) {
        logger.log?.(`[hub_grpc] rust scheduler lease shadow acquire request_id=${state.requestId}`);
      }
    });
  }

  function mirrorImmediateAcquire(input = {}) {
    const enqueued = mirrorEnqueue(input);
    const acquired = mirrorAcquire(input);
    return enqueued || acquired;
  }

  function mirrorRelease(input = {}) {
    const state = stateFor(input.requestId || input.request_id);
    if (!state) return false;
    return schedule('release', async () => {
      if (state.done) return;
      if (!state.leaseToken) {
        throw new Error(`missing_shadow_lease_token:${state.runId}`);
      }
      await execJson('release', {
        ...input,
        requestId: state.requestId,
        runId: state.runId,
        leaseToken: state.leaseToken,
      });
      state.done = true;
      runs.delete(state.requestId);
      if (config.verbose) {
        logger.log?.(`[hub_grpc] rust scheduler lease shadow release request_id=${state.requestId}`);
      }
    });
  }

  function mirrorCancel(input = {}) {
    const state = stateFor(input.requestId || input.request_id);
    if (!state) return false;
    return schedule('cancel', async () => {
      if (state.done) return;
      await execJson('cancel', {
        ...input,
        requestId: state.requestId,
        runId: state.runId,
      });
      state.done = true;
      runs.delete(state.requestId);
      if (config.verbose) {
        logger.log?.(`[hub_grpc] rust scheduler lease shadow cancel request_id=${state.requestId}`);
      }
    });
  }

  return {
    config,
    mirrorEnqueue,
    mirrorAcquire,
    mirrorImmediateAcquire,
    mirrorRelease,
    mirrorCancel,
    flush: () => chain,
    _state: runs,
  };
}
