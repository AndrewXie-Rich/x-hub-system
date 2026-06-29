import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCHEMA_VERSION = 'xhub.external_terminal_ai_only_remote_smoke.v1';

const DEFAULT_DENIED_PATHS = Object.freeze([
  '/admin/clients/access-keys?auth_kind=hub_access_key',
  '/xt/clients/access-keys',
  '/skills/catalog',
  '/memory/retrieve',
  '/memory/working-set',
  '/ready',
]);

function safeString(value) {
  return String(value ?? '').trim();
}

function boolFlag(args, name) {
  return args.includes(name);
}

function argValue(args, name, fallback = '') {
  const index = args.indexOf(name);
  if (index >= 0 && index + 1 < args.length) return safeString(args[index + 1]);
  return safeString(fallback);
}

function argValues(args, name) {
  const out = [];
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === name && i + 1 < args.length) out.push(safeString(args[i + 1]));
  }
  return out.filter(Boolean);
}

function stripTrailingSlash(value) {
  return safeString(value).replace(/\/+$/, '');
}

function rootBaseUrl(baseUrl) {
  const raw = stripTrailingSlash(baseUrl);
  if (!raw) return '';
  return raw.replace(/\/v1$/i, '');
}

function endpoint(baseUrl, routePath) {
  const base = rootBaseUrl(baseUrl);
  const route = safeString(routePath).startsWith('/') ? safeString(routePath) : `/${safeString(routePath)}`;
  return `${base}${route}`;
}

function loadTokenFromArgs(args) {
  const explicit = safeString(
    argValue(args, '--token')
    || process.env.OPENAI_API_KEY
    || process.env.HUB_CLIENT_TOKEN
    || process.env.AXHUB_CLIENT_TOKEN
  );
  if (explicit) return explicit;

  const tokenFile = safeString(argValue(args, '--token-file') || process.env.AXHUB_CLIENT_TOKEN_FILE);
  if (!tokenFile) return '';
  return fs.readFileSync(tokenFile, 'utf8').trim();
}

function requestJson({
  method = 'GET',
  url,
  token = '',
  body = null,
  timeoutMs = 4_000,
} = {}) {
  const target = new URL(String(url || ''));
  const transport = target.protocol === 'https:' ? https : http;
  const payload = body == null ? '' : JSON.stringify(body);
  const headers = {
    accept: 'application/json',
  };
  if (token) headers.authorization = `Bearer ${token}`;
  if (payload) {
    headers['content-type'] = 'application/json; charset=utf-8';
    headers['content-length'] = String(Buffer.byteLength(payload));
  }

  return new Promise((resolve, reject) => {
    const req = transport.request({
      method,
      hostname: target.hostname,
      port: target.port || (target.protocol === 'https:' ? '443' : '80'),
      path: `${target.pathname}${target.search}`,
      headers,
      timeout: timeoutMs,
    }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        let json = null;
        try {
          json = text ? JSON.parse(text) : null;
        } catch {
          json = null;
        }
        resolve({
          status: Number(res.statusCode || 0),
          headers: res.headers || {},
          json,
          text,
        });
      });
    });
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('request_timeout')));
    if (payload) req.write(payload);
    req.end();
  });
}

function responseErrorSummary(response) {
  const err = response?.json?.error && typeof response.json.error === 'object'
    ? response.json.error
    : {};
  return {
    status: Number(response?.status || 0),
    code: safeString(err.code || response?.json?.code),
    message: safeString(err.message || response?.json?.message).slice(0, 240),
  };
}

function pickModelId(modelsJson) {
  const rows = Array.isArray(modelsJson?.data) ? modelsJson.data : [];
  const ids = rows
    .map((row) => ({
      id: safeString(row?.id),
      ownedBy: safeString(row?.owned_by || row?.ownedBy).toLowerCase(),
      requiresGrant: row?.requires_grant === true,
    }))
    .filter((row) => row.id && !row.requiresGrant);
  const local = ids.find((row) => {
    const text = `${row.id} ${row.ownedBy}`.toLowerCase();
    return text.includes('local')
      || text.includes('lmstudio')
      || text.includes('mlx')
      || text.includes('llama')
      || text.includes('qwen');
  });
  return safeString(local?.id || ids[0]?.id);
}

function deniedStatusOk(status) {
  return [401, 403, 404, 405].includes(Number(status || 0));
}

function compactDeniedResults(results) {
  const out = {};
  for (const row of results) {
    out[row.path] = {
      status: Number(row.response?.status || 0),
      code: safeString(row.response?.json?.error?.code || row.response?.json?.code),
    };
  }
  return out;
}

export async function runExternalTerminalAiOnlyRemoteSmoke({
  baseUrl,
  token,
  includeChat = false,
  includeResponses = false,
  model = '',
  timeoutMs = 4_000,
  chatTimeoutMs = 30_000,
  deniedPaths = DEFAULT_DENIED_PATHS,
} = {}) {
  const rootBase = rootBaseUrl(baseUrl);
  const clientToken = safeString(token);
  if (!rootBase) throw new Error('base_url_required');
  if (!clientToken) throw new Error('client_token_required');

  const checks = [];
  let selectedModel = safeString(model);
  let modelCount = 0;
  let modelIdsSample = [];

  const models = await requestJson({
    url: endpoint(rootBase, '/v1/models'),
    token: clientToken,
    timeoutMs,
  });
  assert.equal(
    models.status,
    200,
    `models_status_${models.status}:${JSON.stringify(responseErrorSummary(models))}`
  );
  assert.equal(safeString(models.json?.object), 'list');
  const modelRows = Array.isArray(models.json?.data) ? models.json.data : [];
  modelCount = modelRows.length;
  modelIdsSample = modelRows.map((row) => safeString(row?.id)).filter(Boolean).slice(0, 5);
  assert.equal(
    modelRows.some((row) => row?.requires_grant === true),
    false,
    'ai_only_models_include_requires_grant'
  );
  checks.push('models_allowed');

  const deniedResults = [];
  for (const deniedPath of deniedPaths) {
    const response = await requestJson({
      url: endpoint(rootBase, deniedPath),
      token: clientToken,
      timeoutMs,
    });
    assert.ok(
      deniedStatusOk(response.status),
      `denied_path_unexpected_status:${deniedPath}:${response.status}`
    );
    deniedResults.push({ path: deniedPath, response });
  }
  checks.push('non_ai_surfaces_denied');

  if (includeChat) {
    selectedModel = selectedModel || pickModelId(models.json);
    assert.ok(selectedModel, 'chat_model_missing');
    const completion = await requestJson({
      method: 'POST',
      url: endpoint(rootBase, '/v1/chat/completions'),
      token: clientToken,
      timeoutMs: chatTimeoutMs,
      body: {
        model: selectedModel,
        messages: [{ role: 'user', content: 'Say OK in one short word.' }],
        max_tokens: 4,
      },
    });
    assert.equal(
      completion.status,
      200,
      `chat_status_${completion.status}:model=${selectedModel}:${JSON.stringify(responseErrorSummary(completion))}`
    );
    checks.push('chat_completion_allowed');
  } else {
    checks.push('chat_completion_skipped_by_default');
  }

  if (includeResponses) {
    selectedModel = selectedModel || pickModelId(models.json);
    assert.ok(selectedModel, 'responses_model_missing');
    const response = await requestJson({
      method: 'POST',
      url: endpoint(rootBase, '/v1/responses'),
      token: clientToken,
      timeoutMs: chatTimeoutMs,
      body: {
        model: selectedModel,
        input: 'Say OK in one short word.',
        max_output_tokens: 4,
      },
    });
    assert.equal(
      response.status,
      200,
      `responses_status_${response.status}:model=${selectedModel}:${JSON.stringify(responseErrorSummary(response))}`
    );
    checks.push('responses_allowed');
  } else {
    checks.push('responses_skipped_by_default');
  }

  return {
    ok: true,
    schema_version: SCHEMA_VERSION,
    base_url: rootBase,
    openai_base_url: `${rootBase}/v1`,
    token_redacted: '[redacted]',
    selected_model: selectedModel,
    model_count: modelCount,
    model_ids_sample: modelIdsSample,
    denied_results: compactDeniedResults(deniedResults),
    checks,
    include_chat: includeChat,
    include_responses: includeResponses,
  };
}

async function main() {
  const args = process.argv.slice(2);
  const baseUrl = stripTrailingSlash(
    argValue(args, '--base-url')
    || process.env.OPENAI_BASE_URL
    || process.env.HUB_EXTERNAL_TERMINAL_BASE_URL
    || process.env.HUB_EXTERNAL_TERMINAL_PROBE_BASE_URL
    || process.env.HUB_PAIRING_BASE_URL
    || 'http://127.0.0.1:50071'
  );
  const token = loadTokenFromArgs(args);
  const extraDeniedPaths = argValues(args, '--deny-path');
  const timeoutMs = Math.max(250, Math.min(120_000, Number.parseInt(argValue(args, '--timeout-ms', '4000'), 10) || 4_000));
  const chatTimeoutMs = Math.max(250, Math.min(120_000, Number.parseInt(argValue(args, '--chat-timeout-ms', '30000'), 10) || 30_000));

  const report = await runExternalTerminalAiOnlyRemoteSmoke({
    baseUrl,
    token,
    includeChat: boolFlag(args, '--include-chat'),
    includeResponses: boolFlag(args, '--include-responses'),
    model: argValue(args, '--model'),
    timeoutMs,
    chatTimeoutMs,
    deniedPaths: extraDeniedPaths.length ? extraDeniedPaths : DEFAULT_DENIED_PATHS,
  });
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
}

const isMain = process.argv[1]
  && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isMain) {
  main().catch((error) => {
    process.stderr.write(`${JSON.stringify({
      ok: false,
      schema_version: SCHEMA_VERSION,
      error: safeString(error?.message || error),
    }, null, 2)}\n`);
    process.exitCode = 1;
  });
}
