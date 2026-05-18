import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import { URL } from 'node:url';

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

function nonNegativeInt(value, fallback = 0) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(0, Math.floor(number));
}

function readAccessKey(env = process.env) {
  const direct = safeString(env.XHUB_RUST_HTTP_ACCESS_KEY || env.XHUB_RUST_HUB_ACCESS_KEY);
  if (direct) return direct;
  const filePath = safeString(env.XHUB_RUST_HTTP_ACCESS_KEY_FILE || env.XHUB_RUST_HUB_ACCESS_KEY_FILE);
  if (!filePath) return '';
  try {
    return safeString(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return '';
  }
}

export function resolveRustLocalMlExecutionConfig(env = process.env) {
  const enabled = parseBoolEnv(
    env.XHUB_RUST_ML_EXECUTION_AUTHORITY
      ?? env.XHUB_RUST_LOCAL_ML_EXECUTION_AUTHORITY
      ?? env.XHUB_ENABLE_RUST_ML_EXECUTION,
    false
  );
  const httpHost = safeString(env.XHUB_RUST_HUB_HOST) || '127.0.0.1';
  const httpPort = parseIntInRange(env.XHUB_RUST_HUB_HTTP_PORT, 50151, 1, 65535);
  return {
    enabled,
    fallbackOnError: parseBoolEnv(env.XHUB_RUST_ML_EXECUTION_FALLBACK_ON_ERROR, false),
    httpBaseUrl: safeString(env.XHUB_RUST_ML_EXECUTION_HTTP_BASE_URL)
      || safeString(env.XHUB_RUST_HUB_HTTP_BASE_URL)
      || `http://${httpHost}:${httpPort}`,
    timeoutMs: parseIntInRange(env.XHUB_RUST_ML_EXECUTION_TIMEOUT_MS, 180_000, 1_000, 600_000),
    accessKey: readAccessKey(env),
    verbose: parseBoolEnv(env.XHUB_RUST_ML_EXECUTION_VERBOSE, false),
  };
}

function httpPostJson(url, payload, { timeoutMs = 60_000, accessKey = '' } = {}) {
  const parsedUrl = url instanceof URL ? url : new URL(String(url));
  const client = parsedUrl.protocol === 'https:' ? https : http;
  if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
    throw new Error(`rust_local_ml_execution_http_unsupported_protocol:${parsedUrl.protocol}`);
  }
  const body = JSON.stringify(payload || {});
  const headers = {
    accept: 'application/json',
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(body),
  };
  if (accessKey) {
    headers.authorization = `Bearer ${accessKey}`;
    headers['x-xhub-access-key'] = accessKey;
  }
  return new Promise((resolve, reject) => {
    const req = client.request(parsedUrl, {
      method: 'POST',
      timeout: timeoutMs,
      headers,
    }, (res) => {
      let responseBody = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        responseBody += String(chunk || '');
        if (responseBody.length > 4 * 1024 * 1024) {
          req.destroy(new Error('rust_local_ml_execution_http_response_too_large'));
        }
      });
      res.on('end', () => {
        if (Number(res.statusCode || 0) < 200 || Number(res.statusCode || 0) >= 300) {
          reject(new Error(`rust_local_ml_execution_http_status:${res.statusCode || 0}:${responseBody.slice(0, 240)}`));
          return;
        }
        try {
          resolve(JSON.parse(responseBody || '{}'));
        } catch (error) {
          reject(new Error(`rust_local_ml_execution_http_invalid_json:${error.message || error}`));
        }
      });
    });
    req.on('timeout', () => {
      req.destroy(new Error('rust_local_ml_execution_http_timeout'));
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function resultText(result = {}) {
  const direct = safeString(result.text || result.output_text || result.outputText);
  if (direct) return direct;
  const output = result.output && typeof result.output === 'object' ? result.output : {};
  const outputText = safeString(output.text || output.output_text || output.outputText);
  if (outputText) return outputText;
  const choices = Array.isArray(result.choices) ? result.choices : [];
  const first = choices[0] && typeof choices[0] === 'object' ? choices[0] : {};
  return safeString(
    first.text
      || first.message?.content
      || first.delta?.content
      || ''
  );
}

function resultUsage(result = {}) {
  const usage = result.usage && typeof result.usage === 'object' ? result.usage : {};
  const promptTokens = nonNegativeInt(
    result.promptTokens
      ?? result.prompt_tokens
      ?? usage.promptTokens
      ?? usage.prompt_tokens,
    0
  );
  const completionTokens = nonNegativeInt(
    result.generationTokens
      ?? result.generation_tokens
      ?? result.completionTokens
      ?? result.completion_tokens
      ?? usage.generationTokens
      ?? usage.generation_tokens
      ?? usage.completionTokens
      ?? usage.completion_tokens,
    0
  );
  const totalTokens = nonNegativeInt(
    result.totalTokens
      ?? result.total_tokens
      ?? usage.totalTokens
      ?? usage.total_tokens,
    promptTokens + completionTokens
  );
  return {
    prompt_tokens: promptTokens,
    completion_tokens: completionTokens,
    total_tokens: totalTokens || promptTokens + completionTokens,
    cost_usd_estimate: 0,
  };
}

export function normalizeRustLocalMlExecutionResult(out = {}) {
  const result = out?.result && typeof out.result === 'object' ? out.result : {};
  return {
    ok: out?.ok === true && result.ok !== false,
    used: true,
    schemaVersion: safeString(out?.schema_version),
    requestId: safeString(out?.request_id),
    runtimeBaseDir: safeString(out?.runtime_base_dir),
    auditRef: safeString(out?.audit_ref),
    errorCode: safeString(out?.error_code || result.reasonCode || result.reason_code || result.error),
    errorMessage: safeString(out?.error_message || result.errorDetail || result.error || out?.error_code),
    provider: safeString(result.provider),
    taskKind: safeString(result.taskKind || result.task_kind),
    modelId: safeString(result.modelId || result.model_id),
    text: resultText(result),
    usage: resultUsage(result),
    latencyMs: nonNegativeInt(result.latencyMs || result.latency_ms || out?.duration_ms, 0),
    raw: out,
    result,
  };
}

export function createRustLocalMlExecutionBridge({
  env = process.env,
  httpPostJsonImpl = httpPostJson,
  logger = console,
} = {}) {
  const config = resolveRustLocalMlExecutionConfig(env);

  function executeUrl() {
    return new URL('/local-ml/execute', config.httpBaseUrl);
  }

  async function executeLocalTask({
    runtimeBaseDir = '',
    request = {},
    requestId = '',
    timeoutMs = 0,
  } = {}) {
    if (!config.enabled) {
      return {
        ok: false,
        used: false,
        fallback: true,
        error_code: 'rust_local_ml_execution_disabled',
      };
    }
    const payload = {
      schema_version: 'xhub.node_to_rust.local_ml_execution_request.v1',
      command: 'run-local-task',
      request_id: safeString(requestId || request?.request_id || request?.requestId),
      runtime_base_dir: safeString(runtimeBaseDir),
      timeout_ms: nonNegativeInt(timeoutMs, config.timeoutMs) || config.timeoutMs,
      request,
    };
    try {
      const out = await httpPostJsonImpl(executeUrl(), payload, {
        timeoutMs: Math.max(1000, nonNegativeInt(timeoutMs, config.timeoutMs) || config.timeoutMs),
        accessKey: config.accessKey,
      });
      const normalized = normalizeRustLocalMlExecutionResult(out);
      if (config.verbose) {
        logger.log?.(`[hub_grpc] rust local ML execution ${normalized.ok ? 'ok' : 'failed'} request=${payload.request_id || ''}`);
      }
      return normalized;
    } catch (error) {
      const errorCode = 'rust_local_ml_execution_http_failed';
      if (config.verbose || !config.fallbackOnError) {
        logger.warn?.(`[hub_grpc] rust local ML execution failed: ${error.message || error}`);
      }
      return {
        ok: false,
        used: true,
        fallback: config.fallbackOnError,
        errorCode,
        error_code: errorCode,
        errorMessage: String(error.message || error),
        error_message: String(error.message || error),
        raw: null,
        result: null,
      };
    }
  }

  return {
    config,
    executeLocalTask,
  };
}
