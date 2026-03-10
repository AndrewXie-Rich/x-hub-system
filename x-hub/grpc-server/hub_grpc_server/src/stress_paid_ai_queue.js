import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';

import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

import { makeClientCredentials } from './client_credentials.js';
import { resolveRuntimeBaseDir } from './mlx_runtime_ipc.js';
import { resolveHubProtoPath } from './proto_path.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

function metadataFromEnv() {
  const token = String(process.env.HUB_CLIENT_TOKEN || '').trim();
  const md = new grpc.Metadata();
  if (token) md.set('authorization', `Bearer ${token}`);
  return md;
}

function loadJsonSafe(filePath) {
  try {
    const raw = fs.readFileSync(String(filePath || ''), 'utf8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function writeJsonAtomic(filePath, obj) {
  const out = String(filePath || '').trim();
  if (!out) return false;
  const dir = path.dirname(out);
  try {
    fs.mkdirSync(dir, { recursive: true });
  } catch {
    // ignore
  }
  const tmp = `${out}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`;
  try {
    fs.writeFileSync(tmp, JSON.stringify(obj, null, 2) + '\n', 'utf8');
    fs.renameSync(tmp, out);
    return true;
  } catch {
    try {
      fs.unlinkSync(tmp);
    } catch {
      // ignore
    }
    return false;
  }
}

function autoPickClientToken() {
  const fromEnv = String(process.env.HUB_CLIENT_TOKEN || '').trim();
  if (fromEnv) {
    return {
      source: 'env',
      token: fromEnv,
      device_id: String(process.env.HUB_DEVICE_ID || '').trim(),
      capabilities: null,
      clients_path: '',
    };
  }

  const base = resolveRuntimeBaseDir();
  const clientsPath = path.join(base, 'hub_grpc_clients.json');
  const obj = loadJsonSafe(clientsPath);
  const clients = Array.isArray(obj?.clients) ? obj.clients : [];
  const enabled = clients.filter((c) => c && c.enabled !== false);
  if (enabled.length === 0) {
    return { source: 'none', token: '', device_id: '', capabilities: null, clients_path: clientsPath };
  }

  const byPaid = enabled.find((c) => {
    const caps = Array.isArray(c?.capabilities) ? c.capabilities.map((x) => String(x || '').trim()) : [];
    return caps.includes('ai.generate.paid');
  });
  const pick = byPaid || enabled[0];
  const token = String(pick?.token || '').trim();
  const deviceId = String(pick?.device_id || '').trim();
  const caps = Array.isArray(pick?.capabilities) ? pick.capabilities.map((x) => String(x || '').trim()).filter(Boolean) : [];

  if (!token) {
    return { source: 'none', token: '', device_id: '', capabilities: null, clients_path: clientsPath };
  }

  process.env.HUB_CLIENT_TOKEN = token;
  if (!String(process.env.HUB_DEVICE_ID || '').trim() && deviceId) {
    process.env.HUB_DEVICE_ID = deviceId;
  }

  return {
    source: 'clients_file',
    token,
    device_id: deviceId,
    capabilities: caps,
    clients_path: clientsPath,
  };
}

function parseArgs(argv) {
  const out = {
    projects: Number.parseInt(process.env.STRESS_PROJECTS || '8', 10),
    model: String(process.env.STRESS_MODEL_ID || '').trim(),
    label: String(process.env.STRESS_LABEL || '').trim(),
    prompt: String(process.env.STRESS_PROMPT || 'Reply with one short line that starts with OK.').trim(),
    maxTokens: Number.parseInt(process.env.STRESS_MAX_TOKENS || '64', 10),
    temperature: Number.parseFloat(process.env.STRESS_TEMPERATURE || '0.2'),
    topP: Number.parseFloat(process.env.STRESS_TOP_P || '0.95'),
    requestTimeoutMs: Number.parseInt(process.env.STRESS_REQUEST_TIMEOUT_MS || '180000', 10),
    projectPrefix: String(process.env.STRESS_PROJECT_PREFIX || 'stress-project').trim(),
    noAutoGrant: false,
    grantTtlSec: Number.parseInt(process.env.STRESS_GRANT_TTL_SEC || '1800', 10),
    grantTokenCap: Number.parseInt(process.env.STRESS_GRANT_TOKEN_CAP || '2000', 10),
    dbPath: String(process.env.HUB_DB_PATH || '').trim(),
    json: false,
    jsonOut: String(process.env.STRESS_JSON_OUT || '').trim(),
  };

  const args = [...argv];
  while (args.length) {
    const arg = String(args.shift() || '').trim();
    if (!arg) continue;
    if (arg === '--projects' || arg === '-n') out.projects = Number.parseInt(String(args.shift() || ''), 10);
    else if (arg === '--model' || arg === '-m') out.model = String(args.shift() || '').trim();
    else if (arg === '--label') out.label = String(args.shift() || '').trim();
    else if (arg === '--prompt' || arg === '-p') out.prompt = String(args.shift() || '').trim();
    else if (arg === '--max-tokens') out.maxTokens = Number.parseInt(String(args.shift() || ''), 10);
    else if (arg === '--temperature') out.temperature = Number.parseFloat(String(args.shift() || ''));
    else if (arg === '--top-p') out.topP = Number.parseFloat(String(args.shift() || ''));
    else if (arg === '--request-timeout-ms') out.requestTimeoutMs = Number.parseInt(String(args.shift() || ''), 10);
    else if (arg === '--project-prefix') out.projectPrefix = String(args.shift() || '').trim();
    else if (arg === '--grant-ttl-sec') out.grantTtlSec = Number.parseInt(String(args.shift() || ''), 10);
    else if (arg === '--grant-token-cap') out.grantTokenCap = Number.parseInt(String(args.shift() || ''), 10);
    else if (arg === '--db-path') out.dbPath = String(args.shift() || '').trim();
    else if (arg === '--json') out.json = true;
    else if (arg === '--json-out') out.jsonOut = String(args.shift() || '').trim();
    else if (arg === '--no-auto-grant') out.noAutoGrant = true;
    else if (arg === '--help' || arg === '-h') out.help = true;
  }

  if (!Number.isFinite(out.projects) || out.projects <= 0) out.projects = 8;
  out.projects = Math.max(1, Math.min(40, Math.floor(out.projects)));

  if (!Number.isFinite(out.maxTokens) || out.maxTokens <= 0) out.maxTokens = 64;
  out.maxTokens = Math.max(8, Math.min(1024, Math.floor(out.maxTokens)));

  if (!Number.isFinite(out.temperature) || out.temperature < 0) out.temperature = 0.2;
  if (!Number.isFinite(out.topP) || out.topP <= 0) out.topP = 0.95;
  if (!Number.isFinite(out.requestTimeoutMs) || out.requestTimeoutMs < 3000) out.requestTimeoutMs = 180000;
  if (!Number.isFinite(out.grantTtlSec) || out.grantTtlSec <= 0) out.grantTtlSec = 1800;
  if (!Number.isFinite(out.grantTokenCap) || out.grantTokenCap < 0) out.grantTokenCap = 2000;
  if (!out.projectPrefix) out.projectPrefix = 'stress-project';
  if (!out.prompt) out.prompt = 'Reply with one short line that starts with OK.';

  if (!out.dbPath) {
    out.dbPath = path.resolve(__dirname, '..', 'data', 'hub.sqlite3');
  }

  return out;
}

function printUsage() {
  // eslint-disable-next-line no-console
  console.log(
    [
      'Usage:',
      '  node src/stress_paid_ai_queue.js --projects 8',
      '',
      'Goal:',
      '  Launch concurrent HubAI.Generate requests across 6~10 projects',
      '  and print queue wait stats from audit ext_json.queue_wait_ms.',
      '',
      'Options:',
      '  --projects, -n <num>         Number of projects (default: 8)',
      '  --model, -m <model_id>       Paid model id (default: auto pick paid model)',
      '  --label <text>               Scenario label for report/json',
      '  --request-timeout-ms <ms>    Timeout per request (default: 180000)',
      '  --db-path <path>             Hub sqlite path (default: ./data/hub.sqlite3)',
      '  --json                       Print final summary JSON to stdout',
      '  --json-out <path>            Write final summary JSON to file',
      '  --no-auto-grant              Skip RequestGrant preflight',
      '',
      'Env:',
      '  HUB_HOST/HUB_PORT/HUB_CLIENT_TOKEN/HUB_DEVICE_ID/HUB_USER_ID/HUB_APP_ID',
      '  HUB_GRPC_TLS_MODE + TLS vars when needed',
      '',
      'Examples:',
      '  npm run stress-paid -- --projects 8',
      '  node src/stress_paid_ai_queue.js -n 10 --model openai/gpt-5.2-codex',
    ].join('\n')
  );
}

function resolveModelSelection(input, models) {
  const raw = String(input || '').trim();
  if (!raw) return { ok: false, id: '', reason: 'empty' };

  const ms = Array.isArray(models) ? models : [];
  const byId = new Map(ms.map((m) => [String(m?.model_id || '').trim(), m]));
  if (byId.has(raw)) return { ok: true, id: raw, info: byId.get(raw) };

  const suffixMatches = ms.filter((m) => {
    const id = String(m?.model_id || '').trim();
    if (!id) return false;
    return id === raw || id.endsWith(`/${raw}`);
  });
  if (suffixMatches.length === 1) {
    const id = String(suffixMatches[0]?.model_id || '').trim();
    if (id) return { ok: true, id, info: suffixMatches[0] };
  }

  return { ok: false, id: '', reason: suffixMatches.length > 1 ? 'ambiguous' : 'not_found' };
}

function modelRequiresGrant(modelInfo) {
  if (!modelInfo) return false;
  if (modelInfo.requires_grant === true) return true;
  const kind = String(modelInfo.kind || '').trim().toUpperCase();
  return kind === 'MODEL_KIND_PAID_ONLINE';
}

function choosePaidModel(models, requested) {
  const ms = Array.isArray(models) ? models : [];
  if (requested) {
    const resolved = resolveModelSelection(requested, ms);
    if (!resolved.ok) return { ok: false, reason: `model_not_found:${requested}` };
    return { ok: true, model: resolved.info || { model_id: resolved.id } };
  }
  const paid = ms.find((m) => modelRequiresGrant(m));
  if (paid) return { ok: true, model: paid };
  return { ok: false, reason: 'no_paid_model' };
}

function makeClientIdentityBase() {
  return {
    device_id: String(process.env.HUB_DEVICE_ID || 'x_terminal_stress_device').trim(),
    user_id: String(process.env.HUB_USER_ID || '').trim(),
    app_id: String(process.env.HUB_APP_ID || 'x_terminal').trim(),
    project_id: '',
    session_id: '',
  };
}

function listModels(modelsClient, md, client) {
  return new Promise((resolve, reject) => {
    modelsClient.ListModels({ client }, md, (err, out) => {
      if (err) reject(err);
      else resolve(Array.isArray(out?.models) ? out.models : []);
    });
  });
}

function requestGrant(grantsClient, md, client, modelId, ttlSec, tokenCap) {
  const reqId = `grant_stress_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const createdAtMs = Date.now();
  return new Promise((resolve, reject) => {
    grantsClient.RequestGrant(
      {
        request_id: reqId,
        client,
        capability: 'CAPABILITY_AI_GENERATE_PAID',
        model_id: modelId,
        reason: 'stress test',
        requested_ttl_sec: Math.max(10, Math.floor(Number(ttlSec || 0))),
        requested_token_cap: Math.max(0, Math.floor(Number(tokenCap || 0))),
        created_at_ms: createdAtMs,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

function runGenerate(aiClient, md, req, timeoutMs) {
  const startedAt = Date.now();
  const stream = aiClient.Generate(req, md);
  let doneObj = null;
  let errObj = null;
  let deltaChars = 0;
  let settled = false;

  return new Promise((resolve) => {
    const finish = (extra = {}) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({
        request_id: req.request_id,
        project_id: req.client?.project_id || '',
        done: doneObj,
        error: errObj,
        delta_chars: deltaChars,
        wall_ms: Math.max(0, Date.now() - startedAt),
        ...extra,
      });
    };

    const timer = setTimeout(() => {
      try {
        stream.cancel();
      } catch {
        // ignore
      }
      finish({ timeout: true });
    }, Math.max(3000, Math.floor(Number(timeoutMs || 0))));

    stream.on('data', (ev) => {
      const which = String(ev?.ev || '').trim();
      const delta = ev?.delta || (which === 'delta' ? ev?.delta : null);
      const done = ev?.done || (which === 'done' ? ev?.done : null);
      const err = ev?.error || (which === 'error' ? ev?.error : null);
      if (delta && typeof delta.text === 'string') deltaChars += delta.text.length;
      if (done) doneObj = done;
      if (err) errObj = err;
    });

    stream.on('error', (e) => {
      const code = typeof e?.code === 'number' ? `grpc_${e.code}` : 'grpc_error';
      errObj = { error: { code, message: String(e?.message || e || 'grpc_error'), retryable: true } };
      finish();
    });

    stream.on('end', () => finish());
  });
}

function parseQueueWaitMs(extJson) {
  if (!extJson) return null;
  try {
    const obj = JSON.parse(String(extJson));
    const v = Number(obj?.queue_wait_ms);
    if (!Number.isFinite(v) || v < 0) return null;
    return v;
  } catch {
    return null;
  }
}

function percentile(values, p) {
  if (!Array.isArray(values) || values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const idx = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[idx];
}

function summarizeMs(values) {
  const vs = Array.isArray(values) ? values.filter((x) => Number.isFinite(x) && x >= 0) : [];
  if (!vs.length) return null;
  const sum = vs.reduce((acc, x) => acc + x, 0);
  return {
    count: vs.length,
    min: Math.min(...vs),
    avg: Math.round(sum / vs.length),
    p50: percentile(vs, 50),
    p90: percentile(vs, 90),
    max: Math.max(...vs),
  };
}

function fetchAuditByRequestIds(dbPath, requestIds) {
  if (!Array.isArray(requestIds) || requestIds.length === 0) return new Map();
  const db = new DatabaseSync(dbPath, { readonly: true });
  try {
    const placeholders = requestIds.map(() => '?').join(',');
    const stmt = db.prepare(
      `SELECT request_id, project_id, event_type, ok, error_code, error_message, created_at_ms, duration_ms, ext_json
       FROM audit_events
       WHERE request_id IN (${placeholders})
         AND event_type LIKE 'ai.generate.%'
       ORDER BY created_at_ms DESC`
    );
    const rows = stmt.all(...requestIds);
    const out = new Map();
    for (const row of rows) {
      const rid = String(row?.request_id || '').trim();
      if (!rid || out.has(rid)) continue;
      out.set(rid, {
        request_id: rid,
        project_id: String(row?.project_id || '').trim(),
        event_type: String(row?.event_type || '').trim(),
        ok: !!row?.ok,
        error_code: String(row?.error_code || '').trim(),
        error_message: String(row?.error_message || '').trim(),
        created_at_ms: Number(row?.created_at_ms || 0),
        duration_ms: Number(row?.duration_ms || 0),
        queue_wait_ms: parseQueueWaitMs(row?.ext_json),
      });
    }
    return out;
  } finally {
    db.close();
  }
}

function padRight(v, width) {
  const s = String(v || '');
  if (s.length >= width) return s.slice(0, width);
  return s + ' '.repeat(width - s.length);
}

function printPerProjectRows(rows) {
  // eslint-disable-next-line no-console
  console.log('\nPer-project results:');
  const headers = [
    padRight('project', 18),
    padRight('status', 12),
    padRight('queue_ms', 9),
    padRight('wall_ms', 8),
    padRight('audit', 22),
    'request_id',
  ].join('  ');
  // eslint-disable-next-line no-console
  console.log(headers);
  // eslint-disable-next-line no-console
  console.log('-'.repeat(Math.min(130, headers.length + 16)));

  for (const row of rows) {
    const queueMs = row.queue_wait_ms == null ? '-' : String(Math.round(row.queue_wait_ms));
    const line = [
      padRight(row.project_id, 18),
      padRight(row.status, 12),
      padRight(queueMs, 9),
      padRight(Math.round(row.wall_ms || 0), 8),
      padRight(row.audit_event_type || '-', 22),
      String(row.request_id || ''),
    ].join('  ');
    // eslint-disable-next-line no-console
    console.log(line);
  }
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    printUsage();
    process.exit(0);
  }

  const host = String(process.env.HUB_HOST || '127.0.0.1').trim();
  const portRaw = Number.parseInt(String(process.env.HUB_PORT || '50051'), 10);
  const port = Number.isFinite(portRaw) ? portRaw : 50051;
  const addr = `${host}:${port}`;

  const proto = loadProto(resolveHubProtoPath(process.env));
  if (!proto?.HubModels || !proto?.HubAI || !proto?.HubGrants) {
    throw new Error('failed to load HubModels/HubAI/HubGrants services from proto');
  }

  const authPick = autoPickClientToken();
  if (!String(process.env.HUB_CLIENT_TOKEN || '').trim()) {
    const hint = authPick?.clients_path
      ? `set HUB_CLIENT_TOKEN or add token in ${authPick.clients_path}`
      : 'set HUB_CLIENT_TOKEN';
    throw new Error(`Missing/invalid client token (${hint})`);
  }

  const md = metadataFromEnv();
  const { creds, options } = makeClientCredentials(process.env);
  const modelsClient = new proto.HubModels(addr, creds, options);
  const aiClient = new proto.HubAI(addr, creds, options);
  const grantsClient = new proto.HubGrants(addr, creds, options);

  const runId = `stress_${Date.now()}`;
  const baseClient = makeClientIdentityBase();
  const projects = [];
  for (let i = 0; i < opts.projects; i += 1) {
    projects.push(`${opts.projectPrefix}-${String(i + 1).padStart(2, '0')}`);
  }

  const models = await listModels(modelsClient, md, baseClient);
  const selected = choosePaidModel(models, opts.model);
  if (!selected.ok) {
    throw new Error(
      selected.reason === 'no_paid_model'
        ? 'No paid model found. Use --model <paid_model_id> or enable a MODEL_KIND_PAID_ONLINE model.'
        : `Failed to resolve model: ${selected.reason}`
    );
  }

  const model = selected.model || {};
  const modelId = String(model.model_id || '').trim();
  if (!modelId) throw new Error('invalid model_id');
  const requiresGrant = modelRequiresGrant(model);

  // eslint-disable-next-line no-console
  console.log(`[stress] hub=${addr} run_id=${runId}`);
  if (authPick.source === 'clients_file') {
    // eslint-disable-next-line no-console
    console.log(`[stress] auth=auto clients_file device=${authPick.device_id || 'unknown'}`);
  } else if (authPick.source === 'env') {
    // eslint-disable-next-line no-console
    console.log(`[stress] auth=env device=${String(process.env.HUB_DEVICE_ID || '').trim() || 'unknown'}`);
  }
  // eslint-disable-next-line no-console
  console.log(`[stress] model=${modelId} kind=${String(model.kind || '')} requires_grant=${requiresGrant}`);
  // eslint-disable-next-line no-console
  console.log(`[stress] projects=${projects.length} (recommended: 6~10)`);
  if (projects.length < 6 || projects.length > 10) {
    // eslint-disable-next-line no-console
    console.log('[stress] note: this run is outside the suggested 6~10 project range.');
  }

  if (requiresGrant && Array.isArray(authPick?.capabilities) && authPick.capabilities.length > 0) {
    if (!authPick.capabilities.includes('ai.generate.paid')) {
      throw new Error(
        `Selected client token (device=${authPick.device_id || 'unknown'}) does not include capability ai.generate.paid. ` +
          `Update hub_grpc_clients.json and add ai.generate.paid for this device, then rerun.`
      );
    }
  }

  if (requiresGrant && !opts.noAutoGrant) {
    const grantResults = await Promise.all(
      projects.map(async (projectId) => {
        const client = { ...baseClient, project_id: projectId, session_id: runId };
        try {
          const out = await requestGrant(grantsClient, md, client, modelId, opts.grantTtlSec, opts.grantTokenCap);
          return {
            project_id: projectId,
            decision: String(out?.decision || '').trim() || 'UNKNOWN',
          };
        } catch (e) {
          return {
            project_id: projectId,
            decision: `ERROR:${String(e?.message || e || 'grant_failed')}`,
          };
        }
      })
    );

    const decisionCounts = new Map();
    for (const item of grantResults) {
      decisionCounts.set(item.decision, (decisionCounts.get(item.decision) || 0) + 1);
    }
    const text = [...decisionCounts.entries()].map(([k, v]) => `${k}=${v}`).join(', ');
    // eslint-disable-next-line no-console
    console.log(`[stress] grant preflight: ${text || 'none'}`);
  }

  const runStartedAt = Date.now();
  // eslint-disable-next-line no-console
  console.log('[stress] launching concurrent generate requests...');

  const generatePromises = projects.map((projectId, idx) => {
    const requestId = `${runId}_${String(idx + 1).padStart(2, '0')}`;
    return runGenerate(
      aiClient,
      md,
      {
        request_id: requestId,
        client: { ...baseClient, project_id: projectId, session_id: runId },
        model_id: modelId,
        messages: [{ role: 'user', content: `${opts.prompt} [project=${projectId}]` }],
        max_tokens: opts.maxTokens,
        temperature: opts.temperature,
        top_p: opts.topP,
        stream: true,
        created_at_ms: Date.now(),
      },
      opts.requestTimeoutMs
    );
  });

  const generateResults = await Promise.all(generatePromises);
  const runFinishedAt = Date.now();

  const requestIds = generateResults.map((x) => x.request_id);
  let auditByRequest = new Map();
  try {
    auditByRequest = fetchAuditByRequestIds(opts.dbPath, requestIds);
  } catch (e) {
    // eslint-disable-next-line no-console
    console.log(`[stress] warning: failed to read audit db (${opts.dbPath}): ${String(e?.message || e)}`);
  }

  const rows = generateResults.map((res) => {
    const doneOk = res?.done?.ok === true;
    const errCode = String(res?.error?.error?.code || '').trim();
    const status = res?.timeout ? 'timeout' : doneOk ? 'ok' : errCode ? `error:${errCode}` : 'failed';
    const audit = auditByRequest.get(res.request_id) || null;
    return {
      request_id: res.request_id,
      project_id: String(res.project_id || '').trim(),
      status,
      wall_ms: Number(res.wall_ms || 0),
      queue_wait_ms: audit?.queue_wait_ms ?? null,
      audit_event_type: audit?.event_type || '',
      audit_ok: audit ? !!audit.ok : null,
      audit_error_code: audit?.error_code || '',
    };
  });

  const okCount = rows.filter((r) => r.status === 'ok').length;
  const failCount = rows.length - okCount;
  const queueValues = rows.map((r) => r.queue_wait_ms).filter((v) => Number.isFinite(v));
  const queueStats = summarizeMs(queueValues);
  const wallStats = summarizeMs(rows.map((r) => r.wall_ms));

  // eslint-disable-next-line no-console
  console.log(`[stress] finished in ${runFinishedAt - runStartedAt} ms | ok=${okCount} failed=${failCount}`);
  printPerProjectRows(rows);

  // eslint-disable-next-line no-console
  console.log('\nQueue wait stats (from audit ext_json.queue_wait_ms):');
  if (!queueStats) {
    // eslint-disable-next-line no-console
    console.log('- no queue_wait_ms found in audit rows for this run');
  } else {
    const withWait = queueValues.filter((v) => v > 0).length;
    // eslint-disable-next-line no-console
    console.log(`- count=${queueStats.count} with_wait=${withWait} min=${queueStats.min} avg=${queueStats.avg} p50=${queueStats.p50} p90=${queueStats.p90} max=${queueStats.max}`);
  }

  // eslint-disable-next-line no-console
  console.log('Wall time stats (client observed):');
  if (!wallStats) {
    // eslint-disable-next-line no-console
    console.log('- no wall time data');
  } else {
    // eslint-disable-next-line no-console
    console.log(`- count=${wallStats.count} min=${wallStats.min} avg=${wallStats.avg} p50=${wallStats.p50} p90=${wallStats.p90} max=${wallStats.max}`);
  }

  const queueCovered = rows.filter((r) => Number.isFinite(r.queue_wait_ms)).length;
  if (queueCovered !== rows.length) {
    // eslint-disable-next-line no-console
    console.log(`- audit queue_wait coverage=${queueCovered}/${rows.length}`);
  }

  const summary = {
    schema_version: 'stress_paid_ai_queue.v1',
    run_id: runId,
    label: opts.label || '',
    created_at_ms: runStartedAt,
    finished_at_ms: runFinishedAt,
    duration_ms: Math.max(0, runFinishedAt - runStartedAt),
    hub: {
      host,
      port,
      addr,
    },
    auth: {
      source: authPick.source,
      device_id: authPick.device_id || '',
    },
    model: {
      model_id: modelId,
      kind: String(model.kind || ''),
      requires_grant: requiresGrant,
    },
    concurrency: {
      projects: projects.length,
      global: Number(process.env.HUB_PAID_AI_GLOBAL_CONCURRENCY || 0) || null,
      per_project: Number(process.env.HUB_PAID_AI_PER_PROJECT_CONCURRENCY || 0) || null,
      queue_timeout_ms: Number(process.env.HUB_PAID_AI_QUEUE_TIMEOUT_MS || 0) || null,
      queue_limit: Number(process.env.HUB_PAID_AI_QUEUE_LIMIT || 0) || null,
    },
    result: {
      ok: okCount,
      failed: failCount,
      total: rows.length,
    },
    queue_wait_ms: {
      ...(queueStats || {}),
      with_wait: queueValues.filter((v) => v > 0).length,
      coverage: { with_queue_wait: queueCovered, total: rows.length },
    },
    wall_ms: wallStats || null,
    rows,
  };

  if (opts.jsonOut) {
    const ok = writeJsonAtomic(opts.jsonOut, summary);
    if (!ok) {
      // eslint-disable-next-line no-console
      console.log(`[stress] warning: failed to write json report: ${opts.jsonOut}`);
    } else {
      // eslint-disable-next-line no-console
      console.log(`[stress] json report: ${opts.jsonOut}`);
    }
  }

  if (opts.json) {
    // eslint-disable-next-line no-console
    console.log(JSON.stringify(summary, null, 2));
  }

  modelsClient.close();
  grantsClient.close();
  aiClient.close();

  if (failCount > 0) {
    process.exitCode = 2;
  }
}

main().catch((e) => {
  // eslint-disable-next-line no-console
  console.error('stress-paid failed:', e?.message || e);
  process.exit(1);
});
