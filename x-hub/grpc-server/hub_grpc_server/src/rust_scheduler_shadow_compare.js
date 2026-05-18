import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

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
  if (sourceRoot) {
    return path.resolve(sourceRoot, '..', 'rust', 'rust hub');
  }
  return path.resolve(MODULE_DIR, '..', '..', '..', '..', '..', 'rust', 'rust hub');
}

export function resolveSchedulerShadowCompareConfig(env = process.env) {
  const enabled = parseBoolEnv(env.XHUB_RUST_SCHEDULER_SHADOW_COMPARE, false);
  const root = resolveRustHubRoot(env);
  const scriptPath = safeString(env.XHUB_RUST_SCHEDULER_SHADOW_COMPARE_SCRIPT)
    || path.join(root, 'tools', 'node_scheduler_shadow_compare.js');
  const runnerPath = safeString(env.XHUB_RUST_HUB_RUNNER)
    || path.join(root, 'tools', 'run_rust_hub.command');

  return {
    enabled,
    scriptPath,
    runnerPath,
    throttleMs: parseIntInRange(env.XHUB_RUST_SCHEDULER_SHADOW_COMPARE_THROTTLE_MS, 5000, 250, 60000),
    timeoutMs: parseIntInRange(env.XHUB_RUST_SCHEDULER_SHADOW_COMPARE_TIMEOUT_MS, 5000, 500, 60000),
    verbose: parseBoolEnv(env.XHUB_RUST_SCHEDULER_SHADOW_COMPARE_VERBOSE, false),
  };
}

export function buildSchedulerShadowCompareArgs(snapshot, config) {
  return [
    config.scriptPath,
    '--runner',
    config.runnerPath,
    '--snapshot-json',
    JSON.stringify({ paid_ai: normalizePaidAISchedulerSnapshot(snapshot) }),
  ];
}

export function normalizePaidAISchedulerSnapshot(snapshot = {}) {
  return {
    in_flight_total: nonNegativeInt(snapshot.in_flight_total),
    queue_depth: nonNegativeInt(snapshot.queue_depth),
    oldest_queued_ms: nonNegativeInt(snapshot.oldest_queued_ms),
  };
}

function nonNegativeInt(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return 0;
  return Math.max(0, Math.floor(number));
}

export function createSchedulerShadowComparer({
  env = process.env,
  spawnImpl = spawn,
  logger = console,
  now = () => Date.now(),
  existsSync = fs.existsSync,
} = {}) {
  const config = resolveSchedulerShadowCompareConfig(env);
  let lastStartedAtMs = 0;
  let inFlight = false;
  let warnedMissing = false;

  function maybeCompare(snapshot) {
    if (!config.enabled) return false;
    const current = now();
    if (inFlight || current - lastStartedAtMs < config.throttleMs) return false;
    if (!existsSync(config.scriptPath) || !existsSync(config.runnerPath)) {
      if (!warnedMissing) {
        warnedMissing = true;
        logger.warn?.(
          `[hub_grpc] rust scheduler shadow compare disabled: missing script=${config.scriptPath} runner=${config.runnerPath}`
        );
      }
      return false;
    }

    const args = buildSchedulerShadowCompareArgs(snapshot, config);
    inFlight = true;
    lastStartedAtMs = current;
    let child;
    try {
      child = spawnImpl(process.execPath, args, {
        cwd: path.dirname(config.scriptPath),
        stdio: ['ignore', 'pipe', 'pipe'],
      });
    } catch (error) {
      inFlight = false;
      logger.warn?.(`[hub_grpc] rust scheduler shadow compare spawn failed: ${error.message}`);
      return false;
    }

    let stdout = '';
    let stderr = '';
    child.stdout?.on?.('data', (chunk) => {
      stdout += String(chunk || '');
    });
    child.stderr?.on?.('data', (chunk) => {
      stderr += String(chunk || '');
    });

    const timer = setTimeout(() => {
      try {
        child.kill('SIGKILL');
      } catch {
        // ignore
      }
    }, config.timeoutMs);
    timer.unref?.();

    child.on?.('close', (code) => {
      clearTimeout(timer);
      inFlight = false;
      if (code !== 0) {
        logger.warn?.(
          `[hub_grpc] rust scheduler shadow compare exited code=${code} stderr=${stderr.trim()}`
        );
        return;
      }
      if (config.verbose) {
        logger.log?.(`[hub_grpc] rust scheduler shadow compare ${stdout.trim()}`);
      }
    });
    child.on?.('error', (error) => {
      clearTimeout(timer);
      inFlight = false;
      logger.warn?.(`[hub_grpc] rust scheduler shadow compare error: ${error.message}`);
    });
    return true;
  }

  return {
    config,
    maybeCompare,
  };
}
