#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';

function safeString(value) {
  return String(value ?? '').trim();
}

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    httpBaseUrl: safeString(process.env.XHUB_RUST_HTTP_BASE_URL || process.env.XHUBD_HTTP_BASE_URL) || 'http://127.0.0.1:50151',
    accessKeyFile: safeString(process.env.XHUB_RUST_HTTP_ACCESS_KEY_FILE || process.env.XHUB_RUST_HUB_ACCESS_KEY_FILE),
    hubBaseDir: safeString(process.env.XHUB_RUST_MEMORY_GATEWAY_CUTOVER_BASE_DIR || process.env.REL_FLOW_HUB_BASE_DIR),
    projectId: 'xt-memory-gateway-cutover-smoke',
    projectRoot: path.join(os.tmpdir(), 'xt-memory-gateway-cutover-smoke'),
    displayName: 'XT Memory Gateway Cutover Smoke',
    samples: 3,
    requiredSamples: 3,
    maxAgeMs: 10 * 60 * 1000,
    timeoutMs: 5000,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--http-base-url':
        out.httpBaseUrl = safeString(next) || out.httpBaseUrl;
        i += 1;
        break;
      case '--access-key-file':
        out.accessKeyFile = safeString(next);
        i += 1;
        break;
      case '--hub-base-dir':
        out.hubBaseDir = safeString(next);
        i += 1;
        break;
      case '--project-id':
        out.projectId = sanitizeToken(safeString(next)) || out.projectId;
        i += 1;
        break;
      case '--project-root':
        out.projectRoot = safeString(next) || out.projectRoot;
        i += 1;
        break;
      case '--display-name':
        out.displayName = safeString(next) || out.displayName;
        i += 1;
        break;
      case '--samples':
        out.samples = parseIntInRange(next, out.samples, 1, 16);
        i += 1;
        break;
      case '--required-samples':
        out.requiredSamples = parseIntInRange(next, out.requiredSamples, 1, 16);
        i += 1;
        break;
      case '--max-age-ms':
        out.maxAgeMs = parseIntInRange(next, out.maxAgeMs, 0, 24 * 60 * 60 * 1000);
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 250, 60000);
        i += 1;
        break;
      case '--help':
      case '-h':
        out.help = true;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }
  out.httpBaseUrl = out.httpBaseUrl.replace(/\/$/, '');
  out.requiredSamples = Math.min(out.requiredSamples, out.samples);
  return out;
}

function usage() {
  return [
    'memory_gateway_cutover_smoke.js',
    '',
    'Options:',
    '  --http-base-url <u>       Live xhubd HTTP base URL, default 127.0.0.1:50151',
    '  --access-key-file <p>     HTTP access key file; defaults to env/runtime candidates',
    '  --hub-base-dir <p>        Base dir for memory_gateway_* evidence files',
    '  --project-id <id>         Smoke project id',
    '  --samples <n>             Fresh parity samples to record, default 3',
    '  --required-samples <n>    Required samples in readiness report, default 3',
    '  --max-age-ms <n>          Freshness window, default 600000',
    '  --timeout-ms <n>          Request timeout, default 5000',
  ].join('\n');
}

function sanitizeToken(value) {
  return safeString(value)
    .replace(/[^A-Za-z0-9_.:-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 120);
}

function readAccessKey(config) {
  const direct = safeString(process.env.XHUB_RUST_HTTP_ACCESS_KEY || process.env.XHUB_RUST_HUB_ACCESS_KEY);
  if (direct) return direct;
  const candidates = [
    config.accessKeyFile,
    ...runtimeRoots().flatMap((root) => [
      path.join(root, 'config', 'xhubd_http_access_key'),
      path.join(root, 'config', 'xhubd_domain_access_key'),
      path.join(root, 'config', 'xhubd_lan_access_key'),
      path.join(root, 'secrets', 'xhubd_http_access_key'),
      path.join(root, 'secrets', 'xhubd_domain_access_key'),
      path.join(root, 'secrets', 'xhubd_lan_access_key'),
    ]),
  ].filter(Boolean);
  for (const candidate of candidates) {
    try {
      const value = safeString(fs.readFileSync(candidate, 'utf8'));
      if (value) return value;
    } catch {}
  }
  return '';
}

function runtimeRoots() {
  const base = path.join(os.homedir(), 'Library', 'Application Support', 'AX', 'rust-hub');
  return ['domain', 'local', 'lan'].map((name) => path.join(base, name));
}

function httpJson(method, url, body, timeoutMs, accessKey, okStatuses = [200]) {
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? '' : JSON.stringify(body);
    const parsed = new URL(url);
    const headers = {
      accept: 'application/json',
      ...(accessKey ? { authorization: `Bearer ${accessKey}`, 'x-xhub-access-key': accessKey } : {}),
      ...(payload ? {
        'content-type': 'application/json',
        'content-length': Buffer.byteLength(payload),
      } : {}),
    };
    const req = http.request({
      method,
      hostname: parsed.hostname,
      port: parsed.port,
      path: `${parsed.pathname}${parsed.search}`,
      timeout: timeoutMs,
      headers,
    }, (res) => {
      let raw = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { raw += chunk; });
      res.on('end', () => {
        let parsedBody = {};
        try {
          parsedBody = raw ? JSON.parse(raw) : {};
        } catch (error) {
          reject(new Error(`invalid JSON from ${url}: ${error.message}`));
          return;
        }
        if (!okStatuses.includes(Number(res.statusCode))) {
          reject(new Error(`unexpected HTTP ${res.statusCode} from ${url}: ${JSON.stringify(parsedBody).slice(0, 1200)}`));
          return;
        }
        resolve(parsedBody);
      });
    });
    req.on('timeout', () => req.destroy(new Error(`timeout after ${timeoutMs}ms: ${url}`)));
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

function baseDirFromReady(ready) {
  const memoryDir = safeString(ready?.memory?.memory_dir);
  if (memoryDir.endsWith(path.join('data', 'memory'))) {
    return path.dirname(path.dirname(memoryDir));
  }
  const dbPath = safeString(ready?.storage?.db_path || ready?.db_path);
  if (dbPath.endsWith(path.join('data', 'hub.sqlite3'))) {
    return path.dirname(path.dirname(dbPath));
  }
  return '';
}

function defaultHubBaseDir(ready, explicit) {
  if (explicit) return explicit;
  const fromReady = baseDirFromReady(ready);
  if (fromReady) return fromReady;
  for (const root of runtimeRoots()) {
    if (fs.existsSync(root)) return root;
  }
  return path.join(os.homedir(), 'Library', 'Group Containers', 'group.rel.flowhub');
}

function fnv1a64(text) {
  let hash = 0xcbf29ce484222325n;
  const prime = 0x100000001b3n;
  for (const byte of Buffer.from(String(text), 'utf8')) {
    hash ^= BigInt(byte);
    hash = BigInt.asUintN(64, hash * prime);
  }
  return hash.toString(16).padStart(16, '0');
}

function collapsedSearchText(text) {
  return String(text ?? '').split(/\s+/).filter(Boolean).join(' ').trim().toLowerCase();
}

function anchorText(text) {
  const collapsed = collapsedSearchText(text);
  return collapsed ? collapsed.slice(0, 160) : '';
}

function rustAnchors(prepare) {
  const slots = Array.isArray(prepare?.slots) ? prepare.slots : [];
  const seen = new Set();
  const anchors = [];
  for (const slot of slots) {
    for (const object of Array.isArray(slot.objects) ? slot.objects : []) {
      const anchor = anchorText(object?.text);
      if (anchor && !seen.has(anchor)) {
        seen.add(anchor);
        anchors.push(anchor);
      }
    }
  }
  return anchors;
}

function productText(anchors) {
  return [
    '[MEMORY_V1]',
    '[L1_CANONICAL]',
    anchors.goal,
    '[/L1_CANONICAL]',
    '',
    '[L2_OBSERVATIONS]',
    anchors.risks,
    '[/L2_OBSERVATIONS]',
    '',
    '[L3_WORKING_SET]',
    anchors.nextSteps,
    '[/L3_WORKING_SET]',
    '[/MEMORY_V1]',
  ].join('\n');
}

function shadowResult({ prepare, product, projectId }) {
  const rustContext = safeString(prepare?.context_text);
  const productSearch = collapsedSearchText(product);
  const anchors = rustAnchors(prepare);
  const matched = anchors.filter((anchor) => productSearch.includes(anchor));
  const missing = anchors.filter((anchor) => !productSearch.includes(anchor));
  const rustOk = prepare?.ok === true;
  const parityOk = rustOk && missing.length === 0;
  return {
    schema_version: 'xt.rust_memory_gateway_shadow_compare.v1',
    ok: rustOk,
    parity_ok: parityOk,
    source: 'rust_memory_gateway_shadow_compare',
    mode: 'shadow_compare_no_product_cutover',
    production_authority_change: prepare?.production_authority_change === true,
    requester_role: 'chat',
    use_mode: 'project_chat',
    project_id: projectId,
    product_source: 'memory_gateway_cutover_smoke_fixture',
    rust_source: safeString(prepare?.source),
    product_text_chars: product.length,
    rust_context_chars: rustContext.length,
    product_text_hash: fnv1a64(product),
    rust_context_hash: fnv1a64(rustContext),
    rust_object_count: Number(prepare?.object_count ?? 0),
    rust_effective_layers: Array.isArray(prepare?.effective_layers) ? prepare.effective_layers : [],
    matched_rust_anchors: matched,
    missing_rust_anchors: missing,
    rust_deny_code: safeString(prepare?.deny_code || prepare?.reason_code || prepare?.error_code),
    reason_code: parityOk ? null : (rustOk ? 'rust_memory_gateway_shadow_drift' : 'rust_memory_gateway_denied'),
    detail: safeString(prepare?.message),
    recorded_at_ms: Date.now(),
  };
}

function atomicWriteJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const tmp = `${filePath}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(tmp, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
  fs.renameSync(tmp, filePath);
}

function readJSON(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return fallback;
  }
}

function writeShadowEvidence(baseDir, result) {
  const statusPath = path.join(baseDir, 'memory_gateway_shadow_compare_status.json');
  const historyPath = path.join(baseDir, 'memory_gateway_shadow_compare_history.json');
  const existing = readJSON(historyPath, null);
  const items = [result, ...(Array.isArray(existing?.items) ? existing.items : [])];
  const seen = new Set();
  const deduped = [];
  for (const item of items) {
    const key = [
      item.requester_role,
      item.use_mode,
      item.project_id || '',
      item.recorded_at_ms,
      item.product_text_hash,
      item.rust_context_hash,
    ].join('|');
    if (!seen.has(key)) {
      seen.add(key);
      deduped.push(item);
    }
    if (deduped.length >= 64) break;
  }
  const history = {
    schema_version: 'xt.rust_memory_gateway_shadow_compare_history.v1',
    generated_at_ms: Date.now(),
    item_limit: 64,
    items: deduped,
  };
  atomicWriteJSON(statusPath, result);
  atomicWriteJSON(historyPath, history);
  return { statusPath, historyPath, history };
}

function buildReadiness({ baseDir, projectId, requiredSamples, maxAgeMs }) {
  const now = Date.now();
  const statusPath = path.join(baseDir, 'memory_gateway_shadow_compare_status.json');
  const historyPath = path.join(baseDir, 'memory_gateway_shadow_compare_history.json');
  const reportPath = path.join(baseDir, 'memory_gateway_cutover_readiness.json');
  const history = readJSON(historyPath, { items: [] });
  let samples = Array.isArray(history?.items) ? history.items : [];
  if (samples.length === 0) {
    const status = readJSON(statusPath, null);
    if (status) samples = [status];
  }
  samples = samples.slice().sort((a, b) => Number(b.recorded_at_ms || 0) - Number(a.recorded_at_ms || 0));
  const matching = samples.filter((item) => item.requester_role === 'chat' && item.use_mode === 'project_chat' && safeString(item.project_id) === projectId);
  const fresh = matching.filter((item) => {
    if (maxAgeMs <= 0) return true;
    const age = now - Number(item.recorded_at_ms || 0);
    return age >= 0 && age <= maxAgeMs;
  });
  const considered = fresh.slice(0, requiredSamples);
  const passing = considered.filter((item) => item.ok === true && item.parity_ok === true && item.production_authority_change !== true && item.rust_source === 'rust_memory_gateway_prepare');
  const issues = [];
  if (samples.length === 0) {
    issues.push({ code: 'memory_gateway_cutover_evidence_missing', blocking: true, detail: 'No memory gateway shadow compare status or history has been recorded.' });
  }
  if (samples.length > 0 && matching.length === 0) {
    issues.push({ code: 'memory_gateway_cutover_scope_missing', blocking: true, detail: 'No shadow compare samples matched requester_role/use_mode/project_id.' });
  }
  if (matching.length > 0 && fresh.length === 0) {
    issues.push({ code: 'memory_gateway_cutover_evidence_stale', blocking: true, detail: `Matching shadow compare samples are older than max_age_ms=${maxAgeMs}.` });
  }
  if (fresh.length < requiredSamples) {
    issues.push({ code: 'memory_gateway_cutover_insufficient_samples', blocking: true, detail: `Need ${requiredSamples} fresh matching parity samples; found ${fresh.length}.` });
  }
  const authorityViolationCount = considered.filter((item) => item.production_authority_change === true).length;
  const parityFailureCount = considered.filter((item) => item.ok !== true || item.parity_ok !== true).length;
  const rustSourceMismatchCount = considered.filter((item) => item.rust_source !== 'rust_memory_gateway_prepare').length;
  if (authorityViolationCount > 0) {
    issues.push({ code: 'memory_gateway_cutover_authority_violation', blocking: true, detail: 'At least one considered sample reported production_authority_change=true.' });
  }
  if (parityFailureCount > 0) {
    issues.push({ code: 'memory_gateway_cutover_parity_failure', blocking: true, detail: 'At least one considered sample was not ok/parity_ok.' });
  }
  if (rustSourceMismatchCount > 0) {
    issues.push({ code: 'memory_gateway_cutover_source_mismatch', blocking: true, detail: 'At least one considered sample did not come from rust_memory_gateway_prepare.' });
  }
  const ready = issues.every((issue) => issue.blocking !== true) && considered.length === requiredSamples && passing.length === requiredSamples;
  const report = {
    schema_version: 'xt.rust_memory_gateway_cutover_readiness.v1',
    ok: ready,
    ready_for_require: ready,
    source: 'rust_memory_gateway_shadow_compare_history',
    generated_at_ms: now,
    requester_role: 'chat',
    use_mode: 'project_chat',
    project_id: projectId,
    required_sample_count: requiredSamples,
    max_age_ms: maxAgeMs,
    total_sample_count: samples.length,
    matching_sample_count: matching.length,
    fresh_matching_sample_count: fresh.length,
    considered_sample_count: considered.length,
    passing_sample_count: passing.length,
    stale_matching_sample_count: matching.length - fresh.length,
    authority_violation_count: authorityViolationCount,
    parity_failure_count: parityFailureCount,
    rust_source_mismatch_count: rustSourceMismatchCount,
    latest_recorded_at_ms: matching[0]?.recorded_at_ms ?? null,
    oldest_considered_at_ms: considered[considered.length - 1]?.recorded_at_ms ?? null,
    require_env_key: 'XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE',
    status_path: statusPath,
    history_path: historyPath,
    report_path: reportPath,
    issues,
  };
  atomicWriteJSON(reportPath, report);
  return report;
}

async function sleep(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }
  const accessKey = readAccessKey(args);
  const ready = await httpJson('GET', `${args.httpBaseUrl}/ready`, undefined, args.timeoutMs, accessKey);
  const hubBaseDir = defaultHubBaseDir(ready, args.hubBaseDir);
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
  const anchors = {
    goal: `Rust memory gateway cutover smoke goal ${stamp}: preserve fast governed project chat memory.`,
    risks: `Rust memory gateway cutover smoke risk ${stamp}: fail closed on authority or parity drift.`,
    nextSteps: `Rust memory gateway cutover smoke next step ${stamp}: require gate only after fresh parity evidence.`,
  };
  const syncBody = {
    type: 'project_canonical_memory',
    req_id: `memory_gateway_cutover_smoke_${stamp}`,
    audit_ref: `memory_gateway_cutover_smoke:${stamp}`,
    project_canonical_memory: {
      project_id: args.projectId,
      project_root: args.projectRoot,
      display_name: args.displayName,
      updated_at: Date.now() / 1000,
      items: [
        { key: 'goal', value: anchors.goal },
        { key: 'risks', value: anchors.risks },
        { key: 'next_steps', value: anchors.nextSteps },
      ],
    },
  };
  const sync = await httpJson('POST', `${args.httpBaseUrl}/memory/project-canonical-sync?apply=1`, syncBody, args.timeoutMs, accessKey);
  if (sync?.ok !== true || sync?.applied !== true || Number(sync?.blocking_count || 0) !== 0) {
    throw new Error(`project canonical sync failed: ${JSON.stringify(sync).slice(0, 1200)}`);
  }

  const product = productText(anchors);
  let lastResult = null;
  let evidencePaths = null;
  for (let i = 0; i < args.samples; i += 1) {
    const prepareBody = {
      requester_role: 'chat',
      use_mode: 'project_chat',
      scope: 'project',
      project_id: args.projectId,
      latest_user: 'memory gateway cutover smoke',
      remote_export_requested: false,
      requested_layers: ['l1_canonical', 'l2_observations', 'l3_working_set'],
      requested_source_kinds: [],
      max_items: 24,
      max_snippet_chars: 420,
    };
    const prepare = await httpJson('POST', `${args.httpBaseUrl}/memory/gateway/prepare`, prepareBody, args.timeoutMs, accessKey);
    const result = shadowResult({ prepare, product, projectId: args.projectId });
    lastResult = result;
    evidencePaths = writeShadowEvidence(hubBaseDir, result);
    if (!result.ok || !result.parity_ok) {
      break;
    }
    if (i + 1 < args.samples) await sleep(25);
  }
  const readiness = buildReadiness({
    baseDir: hubBaseDir,
    projectId: args.projectId,
    requiredSamples: args.requiredSamples,
    maxAgeMs: args.maxAgeMs,
  });
  const output = {
    ok: readiness.ready_for_require === true,
    schema_version: 'xhub.rust_hub.memory_gateway_cutover_smoke.v1',
    command: 'memory-gateway-cutover-smoke',
    http_base_url: args.httpBaseUrl,
    http_access_key_configured: Boolean(accessKey),
    hub_base_dir: hubBaseDir,
    project_id: args.projectId,
    samples_requested: args.samples,
    required_samples: args.requiredSamples,
    last_shadow_parity_ok: lastResult?.parity_ok === true,
    last_rust_object_count: Number(lastResult?.rust_object_count || 0),
    status_path: evidencePaths?.statusPath || path.join(hubBaseDir, 'memory_gateway_shadow_compare_status.json'),
    history_path: evidencePaths?.historyPath || path.join(hubBaseDir, 'memory_gateway_shadow_compare_history.json'),
    report_path: readiness.report_path,
    ready_for_require: readiness.ready_for_require === true,
    issue_codes: readiness.issues.map((issue) => issue.code),
    production_authority_change: false,
    secret_leak: false,
  };
  console.log(JSON.stringify(output, null, 2));
  if (!output.ok) process.exit(1);
}

main().catch((error) => {
  process.stderr.write(`[memory_gateway_cutover_smoke] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
