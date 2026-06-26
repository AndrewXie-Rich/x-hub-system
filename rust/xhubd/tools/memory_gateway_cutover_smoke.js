#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';

const CANONICAL_SERVING_PROFILES = [
  'M0_Heartbeat',
  'M1_Execute',
  'M2_PlanReview',
  'M3_DeepDive',
  'M4_FullScan',
];

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
    servingProfileId: '',
    profileSuite: false,
    modelCallPlanSmoke: true,
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
      case '--serving-profile':
      case '--serving-profile-id':
        out.servingProfileId = normalizedMemoryGatewayProfileId(next);
        if (!out.servingProfileId) {
          throw new Error(`unsupported serving profile: ${next}`);
        }
        i += 1;
        break;
      case '--profile-suite':
      case '--all-profiles':
        out.profileSuite = true;
        break;
      case '--no-model-call-plan-smoke':
      case '--skip-model-call-plan-smoke':
        out.modelCallPlanSmoke = false;
        break;
      case '--self-test':
        out.selfTest = true;
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
    '  --serving-profile <id>    Record/readiness-check one profile, M0..M4',
    '  --profile-suite           Record/readiness-check M0/M1/M2/M3/M4',
    '  --no-model-call-plan-smoke Skip plan-only model-call wrapper smoke',
    '  --self-test               Run in-memory readiness/profile rollup self-test',
  ].join('\n');
}

function sanitizeToken(value) {
  return safeString(value)
    .replace(/[^A-Za-z0-9_.:-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 120);
}

function normalizedMemoryGatewayProfileId(value) {
  const raw = safeString(value);
  if (!raw) return '';
  const key = raw.toLowerCase().replace(/[\s-]+/g, '_');
  const profiles = {
    m0: 'M0_Heartbeat',
    heartbeat: 'M0_Heartbeat',
    m0_heartbeat: 'M0_Heartbeat',
    m1: 'M1_Execute',
    execute: 'M1_Execute',
    m1_execute: 'M1_Execute',
    m2: 'M2_PlanReview',
    plan_review: 'M2_PlanReview',
    planreview: 'M2_PlanReview',
    m2_plan_review: 'M2_PlanReview',
    m2_planreview: 'M2_PlanReview',
    m3: 'M3_DeepDive',
    deep_dive: 'M3_DeepDive',
    deepdive: 'M3_DeepDive',
    m3_deep_dive: 'M3_DeepDive',
    m3_deepdive: 'M3_DeepDive',
    m4: 'M4_FullScan',
    full_scan: 'M4_FullScan',
    fullscan: 'M4_FullScan',
    m4_full_scan: 'M4_FullScan',
    m4_fullscan: 'M4_FullScan',
  };
  return profiles[key] || '';
}

function uniqueStrings(values) {
  const out = [];
  const seen = new Set();
  for (const value of values) {
    const normalized = safeString(value);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    out.push(normalized);
  }
  return out;
}

function normalizedObjectCounts(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  const out = {};
  const entries = Object.entries(value)
    .map(([key, count]) => [sanitizeToken(key), Number(count)])
    .filter(([key, count]) => key && Number.isFinite(count) && count > 0)
    .sort(([left], [right]) => left.localeCompare(right))
    .slice(0, 32);
  for (const [key, count] of entries) {
    out[key] = Math.max(0, Math.min(1_000_000, Math.trunc(count)));
  }
  return out;
}

function boundedCount(value) {
  const count = Number(value || 0);
  if (!Number.isFinite(count)) return 0;
  return Math.max(0, Math.min(1_000_000, Math.trunc(count)));
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

function countChunkIdentityRefs(value) {
  return arrayValue(value).filter((item) => {
    if (!item || typeof item !== 'object' || Array.isArray(item)) return false;
    return Boolean(safeString(item.chunk_ref) || safeString(item.chunk_id));
  }).length;
}

function summarizeChunkEvidenceFromPlan(plan) {
  const prepare = plan?.prepare && typeof plan.prepare === 'object' && !Array.isArray(plan.prepare)
    ? plan.prepare
    : {};
  const memoryContext = plan?.memory_context && typeof plan.memory_context === 'object' && !Array.isArray(plan.memory_context)
    ? plan.memory_context
    : {};
  const selectedRefs = arrayValue(memoryContext.selected_refs).length > 0
    ? arrayValue(memoryContext.selected_refs)
    : arrayValue(prepare.selected_refs);
  const omittedRefs = arrayValue(memoryContext.omitted_refs).length > 0
    ? arrayValue(memoryContext.omitted_refs)
    : arrayValue(prepare.omitted_refs);
  return {
    selected_chunk_count: boundedCount(prepare.selected_chunk_count || selectedRefs.length),
    selected_chunk_ref_count: boundedCount(countChunkIdentityRefs(selectedRefs)),
    omitted_ref_count: boundedCount(memoryContext.omitted_ref_count || prepare.omitted_ref_count || omittedRefs.length),
    omitted_chunk_ref_count: boundedCount(countChunkIdentityRefs(omittedRefs)),
    index_granularity: safeString(memoryContext.index_granularity || prepare.index_granularity),
    index_source: safeString(prepare.index_source),
    chunk_identity_schema: safeString(memoryContext.chunk_identity_schema || prepare.chunk_identity_schema),
    chunk_expand_via_get_ref: memoryContext.chunk_expand_via_get_ref === true
      || prepare.chunk_expand_via_get_ref === true,
  };
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

function profilesToRun(args) {
  if (args.profileSuite) return CANONICAL_SERVING_PROFILES;
  if (args.servingProfileId) return [args.servingProfileId];
  return [''];
}

function buildPrepareBody({ args, profile, latestUser }) {
  const body = {
    requester_role: 'chat',
    use_mode: 'project_chat',
    scope: 'project',
    project_id: args.projectId,
    latest_user: latestUser,
    remote_export_requested: false,
  };
  if (profile) {
    body.serving_profile_id = profile;
  } else {
    body.requested_layers = ['l1_canonical', 'l2_observations', 'l3_working_set'];
    body.requested_source_kinds = [];
    body.max_items = 24;
    body.max_snippet_chars = 420;
  }
  return body;
}


function safeErrorSummary(error) {
  return safeString(error?.message || error)
    .replace(/"prompt"\s*:\s*"[^"]*"/gi, '"prompt":"[REDACTED]"')
    .replace(/"content"\s*:\s*"[^"]*"/gi, '"content":"[REDACTED]"')
    .slice(0, 300);
}

function summarizeModelCallPlan(plan) {
  const prepare = plan?.prepare && typeof plan.prepare === 'object' && !Array.isArray(plan.prepare)
    ? plan.prepare
    : {};
  const chunkEvidence = summarizeChunkEvidenceFromPlan(plan);
  return {
    schema_version: safeString(plan?.schema_version),
    ok: plan?.ok === true,
    status: safeString(plan?.status),
    source: safeString(plan?.source),
    mode: safeString(plan?.mode),
    authority: safeString(plan?.authority),
    would_call_model: plan?.would_call_model === true,
    model_call_executed: plan?.model_call_executed === true,
    execution_blocker: safeString(plan?.execution_blocker),
    production_authority_change: plan?.production_authority_change === true,
    duration_ms: Number(plan?.duration_ms || 0),
    context_text_included: plan?.memory_context?.context_text_included === true,
    context_char_count: Number(plan?.memory_context?.context_char_count || 0),
    selected_ref_count: Number(plan?.memory_context?.selected_ref_count || 0),
    selected_chunk_count: chunkEvidence.selected_chunk_count,
    selected_chunk_ref_count: chunkEvidence.selected_chunk_ref_count,
    omitted_ref_count: chunkEvidence.omitted_ref_count,
    omitted_chunk_ref_count: chunkEvidence.omitted_chunk_ref_count,
    index_granularity: chunkEvidence.index_granularity,
    index_source: chunkEvidence.index_source,
    chunk_identity_schema: chunkEvidence.chunk_identity_schema,
    chunk_expand_via_get_ref: chunkEvidence.chunk_expand_via_get_ref,
    prompt_text_included: plan?.model_request?.prompt?.text_included === true,
    prompt_present: plan?.model_request?.prompt?.prompt_present === true,
    prompt_char_count: Number(plan?.model_request?.prompt?.prompt_char_count || 0),
    message_count: Number(plan?.model_request?.prompt?.message_count || 0),
    omitted_reason_counts: normalizedObjectCounts(prepare.omitted_reason_counts || plan?.omitted_reason_counts),
    route_intent: safeString(plan?.model_request?.route_intent),
    provider_id: safeString(plan?.model_request?.provider_id),
    model_id: safeString(plan?.model_request?.model_id),
    local_ml_execute_http_not_invoked: plan?.guards?.local_ml_execute_http_not_invoked === true,
    provider_route_not_mutated: plan?.guards?.provider_route_not_mutated === true,
    node_not_authority: plan?.guards?.node_not_authority === true,
    context_text_redacted_from_plan: plan?.guards?.context_text_redacted_from_plan === true,
  };
}

function summarizeModelCallExecuteDenial(denial) {
  return {
    schema_version: safeString(denial?.schema_version),
    ok: denial?.ok === true,
    status: safeString(denial?.status),
    error_code: safeString(denial?.error_code),
    would_call_model: denial?.would_call_model === true,
    model_call_executed: denial?.model_call_executed === true,
    production_authority_change: denial?.production_authority_change === true,
  };
}

function summarizeModelCallExecutionGate(gate) {
  const blockers = Array.isArray(gate?.blockers)
    ? gate.blockers.map((value) => safeString(value)).filter(Boolean).slice(0, 16)
    : [];
  return {
    schema_version: safeString(gate?.schema_version),
    ok: gate?.ok === true,
    status: safeString(gate?.status),
    source: safeString(gate?.source),
    mode: safeString(gate?.mode),
    authority: safeString(gate?.authority),
    ready_for_execution: gate?.ready_for_execution === true,
    execution_requested: gate?.execution_requested === true,
    execution_admission_authority_in_rust: gate?.execution_admission_authority_in_rust === true,
    execution_admission_enabled: gate?.execution_admission_enabled === true,
    execution_admission_ready: gate?.execution_admission_ready === true,
    execution_authority_in_rust: gate?.execution_authority_in_rust === true,
    execution_enabled: gate?.execution_enabled === true,
    would_call_model: gate?.would_call_model === true,
    model_call_executed: gate?.model_call_executed === true,
    production_authority_change: gate?.production_authority_change === true,
    context_text_included: gate?.plan?.context_text_included === true,
    prompt_text_included: gate?.plan?.prompt_text_included === true,
    route_specified: gate?.route_authority?.route_specified === true,
    provider_route_authority_in_rust: gate?.route_authority?.provider_route_authority_in_rust === true,
    model_route_authority_in_rust: gate?.route_authority?.model_route_authority_in_rust === true,
    local_ml_execute_http_not_invoked: gate?.guards?.local_ml_execute_http_not_invoked === true,
    provider_route_not_mutated: gate?.guards?.provider_route_not_mutated === true,
    node_not_authority: gate?.guards?.node_not_authority === true,
    blockers,
  };
}

function summarizeModelCallExecute(execute) {
  const blockers = Array.isArray(execute?.blockers)
    ? execute.blockers.map((value) => safeString(value)).filter(Boolean).slice(0, 16)
    : [];
  return {
    schema_version: safeString(execute?.schema_version),
    ok: execute?.ok === true,
    status: safeString(execute?.status),
    source: safeString(execute?.source),
    mode: safeString(execute?.mode),
    authority: safeString(execute?.authority),
    ready_for_execution: execute?.ready_for_execution === true,
    execution_authority_in_rust: execute?.execution_authority_in_rust === true,
    execution_enabled: execute?.execution_enabled === true,
    execution_requested: execute?.execution_requested === true,
    would_call_model: execute?.would_call_model === true,
    model_call_invoked: execute?.model_call_invoked === true,
    model_call_executed: execute?.model_call_executed === true,
    production_authority_change: execute?.production_authority_change === true,
    local_ml_execute_http_invoked: execute?.guards?.local_ml_execute_http_invoked === true,
    context_text_included: execute?.guards?.context_text_redacted_from_execute !== true,
    prompt_text_included: execute?.guards?.prompt_text_redacted_from_execute !== true,
    provider_route_not_mutated: execute?.guards?.provider_route_not_mutated === true,
    node_not_authority: execute?.guards?.node_not_authority === true,
    executor: safeString(execute?.executor?.executor),
    local_executor_enabled: execute?.executor?.local_executor_enabled === true,
    local_executor_apply_enabled: execute?.executor?.local_executor_apply_enabled === true,
    local_route_allowed: execute?.executor?.local_route_allowed === true,
    blocker_count: blockers.length,
    blockers,
  };
}

function buildModelCallPlanProbe({ plan, denial, executionGate = null, execute = null, error = '' }) {
  const planSummary = summarizeModelCallPlan(plan);
  const denialSummary = summarizeModelCallExecuteDenial(denial);
  const executionGateSummary = summarizeModelCallExecutionGate(executionGate);
  const executeSummary = summarizeModelCallExecute(execute);
  const issueCodes = [];
  if (error) issueCodes.push('memory_gateway_model_call_plan_request_failed');
  if (planSummary.schema_version !== 'xhub.memory.gateway_model_call_plan.v1') {
    issueCodes.push('memory_gateway_model_call_plan_schema_mismatch');
  }
  if (planSummary.ok !== true || planSummary.status !== 'planned') {
    issueCodes.push('memory_gateway_model_call_plan_not_planned');
  }
  if (planSummary.source !== 'rust_memory_gateway_model_call_plan') {
    issueCodes.push('memory_gateway_model_call_plan_source_mismatch');
  }
  if (planSummary.mode !== 'plan_only_no_model_call' || planSummary.authority !== 'rust_memory_gateway_plan_only') {
    issueCodes.push('memory_gateway_model_call_plan_authority_mismatch');
  }
  if (planSummary.would_call_model !== false || planSummary.model_call_executed !== false) {
    issueCodes.push('memory_gateway_model_call_plan_executed_unexpectedly');
  }
  if (planSummary.production_authority_change === true) {
    issueCodes.push('memory_gateway_model_call_plan_authority_violation');
  }
  if (planSummary.context_text_included === true || planSummary.prompt_text_included === true) {
    issueCodes.push('memory_gateway_model_call_plan_text_leak');
  }
  if (planSummary.local_ml_execute_http_not_invoked !== true || planSummary.provider_route_not_mutated !== true) {
    issueCodes.push('memory_gateway_model_call_plan_execution_guard_missing');
  }
  if (denialSummary.schema_version !== 'xhub.memory.gateway_model_call_plan.v1') {
    issueCodes.push('memory_gateway_model_call_execute_denial_schema_mismatch');
  }
  if (denialSummary.error_code !== 'memory_gateway_model_call_execute_not_enabled') {
    issueCodes.push('memory_gateway_model_call_execute_denial_missing');
  }
  if (denialSummary.model_call_executed !== false || denialSummary.would_call_model !== false) {
    issueCodes.push('memory_gateway_model_call_execute_denial_executed_unexpectedly');
  }
  if (denialSummary.production_authority_change === true) {
    issueCodes.push('memory_gateway_model_call_execute_denial_authority_violation');
  }
  if (executionGateSummary.schema_version !== 'xhub.memory.gateway_model_call_execution_gate.v1') {
    issueCodes.push('memory_gateway_model_call_execution_gate_schema_mismatch');
  }
  if (executionGateSummary.source !== 'rust_memory_gateway_model_call_execution_gate') {
    issueCodes.push('memory_gateway_model_call_execution_gate_source_mismatch');
  }
  if (executionGateSummary.ready_for_execution === true
    && executionGateSummary.execution_admission_authority_in_rust !== true) {
    issueCodes.push('memory_gateway_model_call_execution_gate_admission_mismatch');
  }
  if (executionGateSummary.model_call_executed !== false || executionGateSummary.would_call_model !== false) {
    issueCodes.push('memory_gateway_model_call_execution_gate_executed_unexpectedly');
  }
  if (executionGateSummary.production_authority_change === true) {
    issueCodes.push('memory_gateway_model_call_execution_gate_authority_violation');
  }
  if (executionGateSummary.context_text_included === true || executionGateSummary.prompt_text_included === true) {
    issueCodes.push('memory_gateway_model_call_execution_gate_text_leak');
  }
  if (executionGateSummary.local_ml_execute_http_not_invoked !== true
    || executionGateSummary.provider_route_not_mutated !== true) {
    issueCodes.push('memory_gateway_model_call_execution_gate_execution_guard_missing');
  }
  if (executeSummary.schema_version !== 'xhub.memory.gateway_model_call_execute.v1') {
    issueCodes.push('memory_gateway_model_call_execute_schema_mismatch');
  }
  if (executeSummary.source !== 'rust_memory_gateway_model_call_execute') {
    issueCodes.push('memory_gateway_model_call_execute_source_mismatch');
  }
  if (executeSummary.model_call_invoked !== false
    || executeSummary.model_call_executed !== false
    || executeSummary.would_call_model !== false
    || executeSummary.local_ml_execute_http_invoked !== false) {
    issueCodes.push('memory_gateway_model_call_execute_invoked_unexpectedly');
  }
  if (executeSummary.production_authority_change === true) {
    issueCodes.push('memory_gateway_model_call_execute_authority_violation');
  }
  if (executeSummary.context_text_included === true || executeSummary.prompt_text_included === true) {
    issueCodes.push('memory_gateway_model_call_execute_text_leak');
  }
  if (executeSummary.provider_route_not_mutated !== true || executeSummary.node_not_authority !== true) {
    issueCodes.push('memory_gateway_model_call_execute_guard_missing');
  }
  return {
    schema_version: 'xhub.rust_hub.memory_gateway_model_call_plan_smoke.v1',
    enabled: true,
    ok: issueCodes.length === 0,
    endpoint: 'POST /memory/gateway/model-call-plan',
    aliases: ['POST /memory/gateway/generate-plan', 'POST /memory/model-call-plan'],
    plan: planSummary,
    execute_denial: denialSummary,
    execution_gate: executionGateSummary,
    execute: executeSummary,
    execution_blocked: denialSummary.error_code === 'memory_gateway_model_call_execute_not_enabled'
      && denialSummary.model_call_executed === false
      && denialSummary.would_call_model === false,
    execution_gate_ready_for_execution: executionGateSummary.ready_for_execution === true,
    execution_admission_authority_in_rust: executionGateSummary.execution_admission_authority_in_rust === true,
    execute_blocked: executeSummary.status === 'blocked'
      && executeSummary.model_call_invoked === false
      && executeSummary.model_call_executed === false
      && executeSummary.would_call_model === false,
    issue_codes: issueCodes,
    error,
  };
}

function skippedModelCallPlanProbe() {
  return {
    schema_version: 'xhub.rust_hub.memory_gateway_model_call_plan_smoke.v1',
    enabled: false,
    ok: true,
    skipped: true,
    reason: 'model_call_plan_smoke_skipped',
    endpoint: 'POST /memory/gateway/model-call-plan',
    issue_codes: [],
  };
}

async function runModelCallPlanSmoke(args, accessKey, stamp) {
  const planBody = {
    request_id: `memory_gateway_model_call_plan_smoke_${stamp}`,
    audit_ref: `memory_gateway_model_call_plan_smoke:${stamp}`,
    requester_role: 'chat',
    use_mode: 'project_chat',
    scope: 'project',
    project_id: args.projectId,
    serving_profile_id: 'M1_Execute',
    prompt: `Memory gateway model-call plan smoke ${stamp}.`,
    provider_id: 'local',
    model_id: 'memory-gateway-smoke-model',
    task_kind: 'text_generate',
  };
  const denialBody = {
    request_id: `memory_gateway_model_call_execute_denial_smoke_${stamp}`,
    audit_ref: `memory_gateway_model_call_execute_denial_smoke:${stamp}`,
    requester_role: 'chat',
    use_mode: 'project_chat',
    scope: 'project',
    project_id: args.projectId,
    prompt: `Memory gateway model-call execute denial smoke ${stamp}.`,
    execute: true,
  };
  const executionGateBody = {
    request_id: `memory_gateway_model_call_execution_gate_smoke_${stamp}`,
    audit_ref: `memory_gateway_model_call_execution_gate_smoke:${stamp}`,
    requester_role: 'chat',
    use_mode: 'project_chat',
    scope: 'project',
    project_id: args.projectId,
    serving_profile_id: 'M1_Execute',
    prompt: `Memory gateway model-call execution gate smoke ${stamp}.`,
    provider_id: 'local',
    model_id: 'memory-gateway-smoke-model',
    task_kind: 'text_generate',
    execute: true,
  };
  const executeBody = {
    request_id: `memory_gateway_model_call_execute_endpoint_smoke_${stamp}`,
    audit_ref: `memory_gateway_model_call_execute_endpoint_smoke:${stamp}`,
    requester_role: 'chat',
    use_mode: 'project_chat',
    scope: 'project',
    project_id: args.projectId,
    serving_profile_id: 'M1_Execute',
    prompt: `Memory gateway model-call execute endpoint smoke ${stamp}.`,
    provider_id: 'openai',
    model_id: 'memory-gateway-smoke-remote-model',
    task_kind: 'text_generate',
    execute: true,
  };
  try {
    const plan = await httpJson(
      'POST',
      `${args.httpBaseUrl}/memory/gateway/model-call-plan`,
      planBody,
      args.timeoutMs,
      accessKey,
    );
    const denial = await httpJson(
      'POST',
      `${args.httpBaseUrl}/memory/gateway/model-call-plan`,
      denialBody,
      args.timeoutMs,
      accessKey,
      [403],
    );
    const executionGate = await httpJson(
      'POST',
      `${args.httpBaseUrl}/memory/gateway/model-call-execution-gate`,
      executionGateBody,
      args.timeoutMs,
      accessKey,
    );
    const execute = await httpJson(
      'POST',
      `${args.httpBaseUrl}/memory/gateway/model-call-execute`,
      executeBody,
      args.timeoutMs,
      accessKey,
    );
    return buildModelCallPlanProbe({ plan, denial, executionGate, execute });
  } catch (error) {
    return buildModelCallPlanProbe({ plan: null, denial: null, error: safeErrorSummary(error) });
  }
}

function shadowResult({ prepare, product, projectId, requesterRole, useMode, servingProfileId }) {
  const rustContext = safeString(prepare?.context_text);
  const productSearch = collapsedSearchText(product);
  const anchors = rustAnchors(prepare);
  const matched = anchors.filter((anchor) => productSearch.includes(anchor));
  const missing = anchors.filter((anchor) => !productSearch.includes(anchor));
  const rustOk = prepare?.ok === true;
  const parityOk = rustOk && missing.length === 0;
  const selectedProfile = normalizedMemoryGatewayProfileId(prepare?.selected_profile)
    || normalizedMemoryGatewayProfileId(prepare?.serving_profile_id)
    || normalizedMemoryGatewayProfileId(servingProfileId);
  const effectiveProfile = normalizedMemoryGatewayProfileId(prepare?.effective_profile)
    || selectedProfile;
  return {
    schema_version: 'xt.rust_memory_gateway_shadow_compare.v1',
    ok: rustOk,
    parity_ok: parityOk,
    source: 'rust_memory_gateway_shadow_compare',
    mode: 'shadow_compare_no_product_cutover',
    production_authority_change: prepare?.production_authority_change === true,
    requester_role: safeString(prepare?.requester_role) || requesterRole,
    use_mode: safeString(prepare?.use_mode) || useMode,
    serving_profile_id: normalizedMemoryGatewayProfileId(prepare?.serving_profile_id)
      || selectedProfile,
    selected_profile: selectedProfile,
    effective_profile: effectiveProfile,
    profile_reason: safeString(prepare?.profile_reason),
    expanded: prepare?.expanded === true,
    expansion_reason: safeString(prepare?.expansion_reason),
    project_id: projectId,
    product_source: 'memory_gateway_cutover_smoke_fixture',
    rust_source: safeString(prepare?.source),
    product_text_chars: product.length,
    rust_context_chars: rustContext.length,
    product_text_hash: fnv1a64(product),
    rust_context_hash: fnv1a64(rustContext),
    rust_object_count: Number(prepare?.object_count ?? 0),
    rust_selected_count: Number(prepare?.selected_count ?? prepare?.object_count ?? 0),
    rust_omitted_count: Number(prepare?.omitted_count ?? 0),
    rust_denied_count: Number(prepare?.denied_count ?? 0),
    rust_effective_layers: Array.isArray(prepare?.effective_layers) ? prepare.effective_layers : [],
    raw_evidence_allowed: prepare?.raw_evidence_allowed === true,
    remote_export_requested: prepare?.remote_export_requested === true,
    remote_export_filtered_count: Number(prepare?.remote_export_filtered_count ?? 0),
    fallback_disabled: prepare?.fallback_disabled === true,
    fallback_reason: safeString(prepare?.fallback_reason),
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
      item.serving_profile_id || '',
      item.selected_profile || '',
      item.effective_profile || '',
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

function shadowSamplePasses(sample) {
  return sample?.ok === true
    && sample?.parity_ok === true
    && sample?.production_authority_change !== true
    && safeString(sample?.rust_source) === 'rust_memory_gateway_prepare';
}

function shadowSampleProfile(sample) {
  return normalizedMemoryGatewayProfileId(sample?.serving_profile_id)
    || normalizedMemoryGatewayProfileId(sample?.selected_profile)
    || normalizedMemoryGatewayProfileId(sample?.effective_profile)
    || 'unknown';
}

function shadowSampleFresh(sample, now, maxAgeMs) {
  if (maxAgeMs <= 0) return true;
  const age = now - Number(sample?.recorded_at_ms || 0);
  return age >= 0 && age <= maxAgeMs;
}

function summarizeProfileReadiness({ samples, requiredSamples, maxAgeMs, now, requiredProfiles }) {
  const byProfile = new Map();
  for (const profile of requiredProfiles) {
    byProfile.set(profile, {
      serving_profile_id: profile,
      total_sample_count: 0,
      fresh_sample_count: 0,
      passing_sample_count: 0,
      authority_violation_count: 0,
      fresh_authority_violation_count: 0,
      parity_failure_count: 0,
      fresh_parity_failure_count: 0,
      rust_source_mismatch_count: 0,
      fresh_rust_source_mismatch_count: 0,
      downgrade_count: 0,
      deny_count: 0,
      latest_recorded_at_ms: null,
      ready_for_require: false,
    });
  }
  for (const sample of samples) {
    const profile = shadowSampleProfile(sample);
    if (!byProfile.has(profile)) {
      byProfile.set(profile, {
        serving_profile_id: profile,
        total_sample_count: 0,
        fresh_sample_count: 0,
        passing_sample_count: 0,
        authority_violation_count: 0,
        fresh_authority_violation_count: 0,
        parity_failure_count: 0,
        fresh_parity_failure_count: 0,
        rust_source_mismatch_count: 0,
        fresh_rust_source_mismatch_count: 0,
        downgrade_count: 0,
        deny_count: 0,
        latest_recorded_at_ms: null,
        ready_for_require: false,
      });
    }
    const bucket = byProfile.get(profile);
    const fresh = shadowSampleFresh(sample, now, maxAgeMs);
    const recordedAtMs = Number(sample?.recorded_at_ms || 0);
    const selectedProfile = normalizedMemoryGatewayProfileId(sample?.selected_profile);
    const effectiveProfile = normalizedMemoryGatewayProfileId(sample?.effective_profile);
    bucket.total_sample_count += 1;
    if (fresh) bucket.fresh_sample_count += 1;
    if (fresh && shadowSamplePasses(sample)) bucket.passing_sample_count += 1;
    if (sample?.production_authority_change === true) bucket.authority_violation_count += 1;
    if (fresh && sample?.production_authority_change === true) bucket.fresh_authority_violation_count += 1;
    if (sample?.ok !== true || sample?.parity_ok !== true) bucket.parity_failure_count += 1;
    if (fresh && (sample?.ok !== true || sample?.parity_ok !== true)) bucket.fresh_parity_failure_count += 1;
    if (safeString(sample?.rust_source) && safeString(sample?.rust_source) !== 'rust_memory_gateway_prepare') {
      bucket.rust_source_mismatch_count += 1;
      if (fresh) bucket.fresh_rust_source_mismatch_count += 1;
    }
    if (selectedProfile && effectiveProfile && selectedProfile !== effectiveProfile) bucket.downgrade_count += 1;
    if (safeString(sample?.rust_deny_code)) bucket.deny_count += 1;
    if (recordedAtMs > 0 && (bucket.latest_recorded_at_ms === null || recordedAtMs > bucket.latest_recorded_at_ms)) {
      bucket.latest_recorded_at_ms = recordedAtMs;
    }
  }
  return Array.from(byProfile.values())
    .map((bucket) => ({
      ...bucket,
      ready_for_require: bucket.passing_sample_count >= requiredSamples
        && bucket.fresh_authority_violation_count === 0
        && bucket.fresh_parity_failure_count === 0
        && bucket.fresh_rust_source_mismatch_count === 0,
    }))
    .sort((a, b) => a.serving_profile_id.localeCompare(b.serving_profile_id));
}

function buildReadiness({
  baseDir,
  projectId,
  requesterRole = 'chat',
  useMode = 'project_chat',
  servingProfileId = '',
  requiredProfiles = [],
  requiredSamples,
  maxAgeMs,
  nowMs,
  modelCallPlanProbe = null,
}) {
  const now = Number(nowMs || Date.now());
  const statusPath = path.join(baseDir, 'memory_gateway_shadow_compare_status.json');
  const historyPath = path.join(baseDir, 'memory_gateway_shadow_compare_history.json');
  const reportPath = path.join(baseDir, 'memory_gateway_cutover_readiness.json');
  const history = readJSON(historyPath, { items: [] });
  let samples = Array.isArray(history?.items) ? history.items : [];
  let profileReadinessSource = samples.length > 0 ? historyPath : '';
  if (samples.length === 0) {
    const status = readJSON(statusPath, null);
    if (status) {
      samples = [status];
      profileReadinessSource = statusPath;
    }
  }
  samples = samples.slice().sort((a, b) => Number(b.recorded_at_ms || 0) - Number(a.recorded_at_ms || 0));
  const expectedServingProfileId = normalizedMemoryGatewayProfileId(servingProfileId);
  const requiredProfileSet = uniqueStrings(requiredProfiles.map((profile) => normalizedMemoryGatewayProfileId(profile)));
  const profileScope = expectedServingProfileId ? [expectedServingProfileId] : requiredProfileSet;
  const scoped = samples.filter((item) => item.requester_role === requesterRole && item.use_mode === useMode && safeString(item.project_id) === projectId);
  const profileReadiness = summarizeProfileReadiness({
    samples: scoped,
    requiredSamples,
    maxAgeMs,
    now,
    requiredProfiles: requiredProfileSet,
  });
  const matching = scoped.filter((item) => profileScope.length === 0 || profileScope.includes(shadowSampleProfile(item)));
  const fresh = matching.filter((item) => shadowSampleFresh(item, now, maxAgeMs));
  const considered = profileScope.length > 0
    ? profileScope.flatMap((profile) => fresh.filter((item) => shadowSampleProfile(item) === profile).slice(0, requiredSamples))
    : fresh.slice(0, requiredSamples);
  const requiredPassingCount = Math.max(1, requiredSamples) * Math.max(1, profileScope.length || 1);
  const passing = considered.filter((item) => shadowSamplePasses(item));
  const issues = [];
  if (samples.length === 0) {
    issues.push({ code: 'memory_gateway_cutover_evidence_missing', blocking: true, detail: 'No memory gateway shadow compare status or history has been recorded.' });
  }
  if (samples.length > 0 && scoped.length === 0) {
    issues.push({ code: 'memory_gateway_cutover_scope_missing', blocking: true, detail: 'No shadow compare samples matched requester_role/use_mode/project_id.' });
  }
  if (scoped.length > 0 && matching.length === 0) {
    issues.push({ code: 'memory_gateway_cutover_profile_missing', blocking: true, detail: 'No shadow compare samples matched required serving_profile_id.' });
  }
  if (matching.length > 0 && fresh.length === 0) {
    issues.push({ code: 'memory_gateway_cutover_evidence_stale', blocking: true, detail: `Matching shadow compare samples are older than max_age_ms=${maxAgeMs}.` });
  }
  if (profileScope.length > 0) {
    for (const profile of profileScope) {
      const profileMatching = matching.filter((item) => shadowSampleProfile(item) === profile);
      const profileFresh = fresh.filter((item) => shadowSampleProfile(item) === profile);
      if (profileMatching.length === 0) {
        issues.push({ code: 'memory_gateway_cutover_profile_missing', blocking: true, detail: `No shadow compare samples matched serving_profile_id=${profile}.` });
      } else if (profileFresh.length === 0) {
        issues.push({ code: 'memory_gateway_cutover_evidence_stale', blocking: true, detail: `Samples for serving_profile_id=${profile} are older than max_age_ms=${maxAgeMs}.` });
      }
      if (profileFresh.length < requiredSamples) {
        issues.push({ code: 'memory_gateway_cutover_insufficient_samples', blocking: true, detail: `Need ${requiredSamples} fresh matching parity samples for serving_profile_id=${profile}; found ${profileFresh.length}.` });
      }
    }
  } else if (fresh.length < requiredSamples) {
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
  const modelCallPlan = modelCallPlanProbe || skippedModelCallPlanProbe();
  if (modelCallPlan.enabled === true && modelCallPlan.ok !== true) {
    issues.push({
      code: 'memory_gateway_model_call_plan_smoke_failed',
      blocking: true,
      detail: uniqueStrings(modelCallPlan.issue_codes || []).join(', ').slice(0, 300),
    });
  }
  const profileReady = profileScope.length === 0 || profileScope.every((profile) => {
    const bucket = profileReadiness.find((item) => item.serving_profile_id === profile);
    return bucket?.ready_for_require === true;
  });
  const ready = issues.every((issue) => issue.blocking !== true)
    && considered.length === requiredPassingCount
    && passing.length === requiredPassingCount
    && profileReady;
  const report = {
    schema_version: 'xt.rust_memory_gateway_cutover_readiness.v1',
    ok: ready,
    ready_for_require: ready,
    source: 'rust_memory_gateway_shadow_compare_history',
    generated_at_ms: now,
    requester_role: requesterRole,
    use_mode: useMode,
    serving_profile_id: expectedServingProfileId || null,
    selected_profile: expectedServingProfileId || null,
    effective_profile: expectedServingProfileId || null,
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
    profile_readiness_source: profileReadinessSource,
    profile_readiness_sample_count: scoped.length,
    profile_downgrade_count: profileReadiness.reduce((sum, item) => sum + Number(item.downgrade_count || 0), 0),
    rust_deny_count: profileReadiness.reduce((sum, item) => sum + Number(item.deny_count || 0), 0),
    profile_readiness: profileReadiness,
    model_call_plan_smoke_enabled: modelCallPlan.enabled === true,
    model_call_plan_ready: modelCallPlan.enabled === true ? modelCallPlan.ok === true : null,
    model_call_plan_required: modelCallPlan.enabled === true,
    model_call_plan_schema: safeString(modelCallPlan.plan?.schema_version),
    model_call_plan_authority: safeString(modelCallPlan.plan?.authority),
    model_call_plan_mode: safeString(modelCallPlan.plan?.mode),
    model_call_plan_execution_blocked: modelCallPlan.execution_blocked === true,
    model_call_plan_would_call_model: modelCallPlan.plan?.would_call_model === true,
    model_call_plan_model_call_executed: modelCallPlan.plan?.model_call_executed === true,
    model_call_plan_context_text_included: modelCallPlan.plan?.context_text_included === true,
    model_call_plan_prompt_text_included: modelCallPlan.plan?.prompt_text_included === true,
    model_call_plan_omitted_reason_counts: normalizedObjectCounts(modelCallPlan.plan?.omitted_reason_counts),
    model_call_plan_selected_chunk_count: boundedCount(modelCallPlan.plan?.selected_chunk_count),
    model_call_plan_selected_chunk_ref_count: boundedCount(modelCallPlan.plan?.selected_chunk_ref_count),
    model_call_plan_omitted_ref_count: boundedCount(modelCallPlan.plan?.omitted_ref_count),
    model_call_plan_omitted_chunk_ref_count: boundedCount(modelCallPlan.plan?.omitted_chunk_ref_count),
    model_call_plan_index_granularity: safeString(modelCallPlan.plan?.index_granularity),
    model_call_plan_index_source: safeString(modelCallPlan.plan?.index_source),
    model_call_plan_chunk_identity_schema: safeString(modelCallPlan.plan?.chunk_identity_schema),
    model_call_plan_chunk_expand_via_get_ref: modelCallPlan.plan?.chunk_expand_via_get_ref === true,
    model_call_execution_gate_ready_for_execution: modelCallPlan.execution_gate_ready_for_execution === true,
    model_call_execution_admission_authority_in_rust: modelCallPlan.execution_admission_authority_in_rust === true,
    model_call_execution_gate_status: safeString(modelCallPlan.execution_gate?.status),
    model_call_execution_gate_mode: safeString(modelCallPlan.execution_gate?.mode),
    model_call_execution_gate_authority: safeString(modelCallPlan.execution_gate?.authority),
    model_call_execution_gate_blocker_count: Array.isArray(modelCallPlan.execution_gate?.blockers)
      ? modelCallPlan.execution_gate.blockers.length
      : 0,
    model_call_execution_gate_model_call_executed: modelCallPlan.execution_gate?.model_call_executed === true,
    model_call_execution_gate_would_call_model: modelCallPlan.execution_gate?.would_call_model === true,
    model_call_execution_gate_context_text_included: modelCallPlan.execution_gate?.context_text_included === true,
    model_call_execution_gate_prompt_text_included: modelCallPlan.execution_gate?.prompt_text_included === true,
    model_call_execute_blocked: modelCallPlan.execute_blocked === true,
    model_call_execute_status: safeString(modelCallPlan.execute?.status),
    model_call_execute_mode: safeString(modelCallPlan.execute?.mode),
    model_call_execute_authority: safeString(modelCallPlan.execute?.authority),
    model_call_execute_executor: safeString(modelCallPlan.execute?.executor),
    model_call_execute_blocker_count: boundedCount(modelCallPlan.execute?.blocker_count),
    model_call_execute_model_call_invoked: modelCallPlan.execute?.model_call_invoked === true,
    model_call_execute_model_call_executed: modelCallPlan.execute?.model_call_executed === true,
    model_call_execute_would_call_model: modelCallPlan.execute?.would_call_model === true,
    model_call_execute_local_ml_invoked: modelCallPlan.execute?.local_ml_execute_http_invoked === true,
    model_call_execute_context_text_included: modelCallPlan.execute?.context_text_included === true,
    model_call_execute_prompt_text_included: modelCallPlan.execute?.prompt_text_included === true,
    model_call_plan_issue_codes: uniqueStrings(modelCallPlan.issue_codes || []),
    model_call_plan_smoke: modelCallPlan,
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

function selfTestSample({ profile, projectId, recordedAtMs, suffix }) {
  return {
    schema_version: 'xt.rust_memory_gateway_shadow_compare.v1',
    ok: true,
    parity_ok: true,
    source: 'rust_memory_gateway_shadow_compare',
    mode: 'shadow_compare_no_product_cutover',
    production_authority_change: false,
    requester_role: 'chat',
    use_mode: 'project_chat',
    serving_profile_id: profile,
    selected_profile: profile,
    effective_profile: profile,
    project_id: projectId,
    product_source: 'memory_gateway_cutover_smoke_self_test',
    rust_source: 'rust_memory_gateway_prepare',
    product_text_chars: 1,
    rust_context_chars: 1,
    product_text_hash: `product_${suffix}`,
    rust_context_hash: `rust_${suffix}`,
    rust_object_count: 1,
    rust_selected_count: 1,
    rust_omitted_count: 0,
    rust_denied_count: 0,
    rust_effective_layers: ['l1_canonical'],
    matched_rust_anchors: [],
    missing_rust_anchors: [],
    rust_deny_code: '',
    reason_code: null,
    detail: '',
    recorded_at_ms: recordedAtMs,
  };
}

function runSelfTest() {
  const now = Date.now();
  const projectId = 'memory-gateway-cutover-smoke-self-test';
  const baseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'memory-gateway-cutover-smoke-self-test-'));
  const items = [];
  for (const profile of CANONICAL_SERVING_PROFILES) {
    items.push(selfTestSample({ profile, projectId, recordedAtMs: now - 10, suffix: `${profile}_a` }));
    items.push(selfTestSample({ profile, projectId, recordedAtMs: now - 20, suffix: `${profile}_b` }));
  }
  const modelCallPlanProbe = {
    schema_version: 'xhub.rust_hub.memory_gateway_model_call_plan_smoke.v1',
    enabled: true,
    ok: true,
    execution_blocked: true,
    issue_codes: [],
    plan: {
      schema_version: 'xhub.memory.gateway_model_call_plan.v1',
      ok: true,
      status: 'planned',
      source: 'rust_memory_gateway_model_call_plan',
      mode: 'plan_only_no_model_call',
      authority: 'rust_memory_gateway_plan_only',
      would_call_model: false,
      model_call_executed: false,
      context_text_included: false,
      prompt_text_included: false,
      omitted_reason_counts: { budget_limit: 1 },
      selected_chunk_count: 2,
      selected_chunk_ref_count: 2,
      omitted_ref_count: 1,
      omitted_chunk_ref_count: 1,
      index_granularity: 'object_chunk',
      index_source: 'derived_index',
      chunk_identity_schema: 'xhub.memory.object_chunk_identity.v1',
      chunk_expand_via_get_ref: true,
    },
    execution_gate: {
      schema_version: 'xhub.memory.gateway_model_call_execution_gate.v1',
      ok: true,
      status: 'blocked',
      source: 'rust_memory_gateway_model_call_execution_gate',
      mode: 'gate_only_no_model_call',
      authority: 'rust_memory_gateway_execution_gate_only',
      ready_for_execution: false,
      execution_requested: true,
      execution_admission_authority_in_rust: false,
      execution_admission_enabled: false,
      execution_admission_ready: false,
      execution_authority_in_rust: false,
      execution_enabled: false,
      would_call_model: false,
      model_call_executed: false,
      production_authority_change: false,
      context_text_included: false,
      prompt_text_included: false,
      route_specified: true,
      provider_route_authority_in_rust: false,
      model_route_authority_in_rust: false,
      local_ml_execute_http_not_invoked: true,
      provider_route_not_mutated: true,
      node_not_authority: true,
      blockers: ['memory_gateway_model_call_execution_not_enabled'],
    },
    execute: {
      schema_version: 'xhub.memory.gateway_model_call_execute.v1',
      ok: true,
      status: 'blocked',
      source: 'rust_memory_gateway_model_call_execute',
      mode: 'execute_guard_no_model_call',
      authority: 'rust_memory_gateway_execute_guarded',
      ready_for_execution: false,
      execution_authority_in_rust: false,
      execution_enabled: false,
      execution_requested: true,
      would_call_model: false,
      model_call_invoked: false,
      model_call_executed: false,
      production_authority_change: false,
      local_ml_execute_http_invoked: false,
      context_text_included: false,
      prompt_text_included: false,
      provider_route_not_mutated: true,
      node_not_authority: true,
      executor: 'local_ml',
      local_executor_enabled: false,
      local_executor_apply_enabled: false,
      local_route_allowed: false,
      blocker_count: 1,
      blockers: ['memory_gateway_model_call_non_local_executor_not_supported'],
    },
  };
  atomicWriteJSON(path.join(baseDir, 'memory_gateway_shadow_compare_history.json'), {
    schema_version: 'xt.rust_memory_gateway_shadow_compare_history.v1',
    generated_at_ms: now,
    item_limit: 64,
    items,
  });
  const suite = buildReadiness({
    baseDir,
    projectId,
    requesterRole: 'chat',
    useMode: 'project_chat',
    requiredProfiles: CANONICAL_SERVING_PROFILES,
    requiredSamples: 2,
    maxAgeMs: 60000,
    nowMs: now,
    modelCallPlanProbe,
  });
  if (suite.ready_for_require !== true) {
    throw new Error(`profile suite readiness self-test failed: ${JSON.stringify(suite.issues)}`);
  }
  if (suite.profile_readiness.filter((item) => item.ready_for_require === true).length !== CANONICAL_SERVING_PROFILES.length) {
    throw new Error('profile suite readiness self-test did not mark every canonical profile ready');
  }
  if (suite.model_call_plan_selected_chunk_count !== 2
    || suite.model_call_plan_omitted_ref_count !== 1
    || suite.model_call_plan_index_granularity !== 'object_chunk'
    || suite.model_call_plan_chunk_expand_via_get_ref !== true) {
    throw new Error('model-call-plan chunk evidence self-test failed');
  }
  const suiteText = JSON.stringify(suite);
  if (suiteText.includes('memory://rust/object/') || suiteText.includes('#object-')) {
    throw new Error('model-call-plan chunk evidence self-test leaked refs');
  }

  const missingBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'memory-gateway-cutover-smoke-self-test-missing-'));
  atomicWriteJSON(path.join(missingBaseDir, 'memory_gateway_shadow_compare_history.json'), {
    schema_version: 'xt.rust_memory_gateway_shadow_compare_history.v1',
    generated_at_ms: now,
    item_limit: 64,
    items: [selfTestSample({ profile: 'M1_Execute', projectId, recordedAtMs: now - 10, suffix: 'single' })],
  });
  const missing = buildReadiness({
    baseDir: missingBaseDir,
    projectId,
    requesterRole: 'chat',
    useMode: 'project_chat',
    servingProfileId: 'M2_PlanReview',
    requiredSamples: 1,
    maxAgeMs: 60000,
    nowMs: now,
  });
  if (missing.ready_for_require === true || !missing.issues.some((issue) => issue.code === 'memory_gateway_cutover_profile_missing')) {
    throw new Error('profile missing readiness self-test failed');
  }

  console.log(JSON.stringify({
    ok: true,
    schema_version: 'xhub.rust_hub.memory_gateway_cutover_smoke_self_test.v1',
    profile_suite_ready: suite.ready_for_require,
    profile_readiness_count: suite.profile_readiness.length,
    model_call_plan_selected_chunk_count: suite.model_call_plan_selected_chunk_count,
    model_call_plan_omitted_ref_count: suite.model_call_plan_omitted_ref_count,
    model_call_plan_index_granularity: suite.model_call_plan_index_granularity,
    missing_profile_issue_codes: missing.issues.map((issue) => issue.code),
  }, null, 2));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }
  if (args.selfTest) {
    runSelfTest();
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
  const requestedProfiles = profilesToRun(args);
  for (const profile of requestedProfiles) {
    for (let i = 0; i < args.samples; i += 1) {
      const profileLabel = profile || 'derived';
      const prepareBody = buildPrepareBody({
        args,
        profile,
        latestUser: `memory gateway cutover smoke ${profileLabel}`,
      });
      const prepare = await httpJson('POST', `${args.httpBaseUrl}/memory/gateway/prepare`, prepareBody, args.timeoutMs, accessKey);
      const result = shadowResult({
        prepare,
        product,
        projectId: args.projectId,
        requesterRole: prepareBody.requester_role,
        useMode: prepareBody.use_mode,
        servingProfileId: profile,
      });
      lastResult = result;
      evidencePaths = writeShadowEvidence(hubBaseDir, result);
      if (!result.ok || !result.parity_ok) {
        break;
      }
      if (i + 1 < args.samples) await sleep(25);
    }
  }
  const modelCallPlanProbe = args.modelCallPlanSmoke
    ? await runModelCallPlanSmoke(args, accessKey, stamp)
    : skippedModelCallPlanProbe();
  const readiness = buildReadiness({
    baseDir: hubBaseDir,
    projectId: args.projectId,
    requesterRole: 'chat',
    useMode: 'project_chat',
    servingProfileId: args.profileSuite ? '' : (args.servingProfileId || 'M1_Execute'),
    requiredProfiles: args.profileSuite ? CANONICAL_SERVING_PROFILES : [],
    requiredSamples: args.requiredSamples,
    maxAgeMs: args.maxAgeMs,
    modelCallPlanProbe,
  });
  const output = {
    ok: readiness.ready_for_require === true,
    schema_version: 'xhub.rust_hub.memory_gateway_cutover_smoke.v1',
    command: 'memory-gateway-cutover-smoke',
    http_base_url: args.httpBaseUrl,
    http_access_key_configured: Boolean(accessKey),
    hub_base_dir: hubBaseDir,
    project_id: args.projectId,
    profile_suite: args.profileSuite === true,
    serving_profile_id: args.profileSuite ? null : (args.servingProfileId || 'M1_Execute'),
    profiles_requested: requestedProfiles.map((profile) => profile || 'derived'),
    samples_requested: args.samples,
    required_samples: args.requiredSamples,
    last_shadow_parity_ok: lastResult?.parity_ok === true,
    last_serving_profile_id: lastResult?.serving_profile_id || null,
    last_selected_profile: lastResult?.selected_profile || null,
    last_effective_profile: lastResult?.effective_profile || null,
    last_rust_object_count: Number(lastResult?.rust_object_count || 0),
    status_path: evidencePaths?.statusPath || path.join(hubBaseDir, 'memory_gateway_shadow_compare_status.json'),
    history_path: evidencePaths?.historyPath || path.join(hubBaseDir, 'memory_gateway_shadow_compare_history.json'),
    report_path: readiness.report_path,
    ready_for_require: readiness.ready_for_require === true,
    profile_readiness_sample_count: readiness.profile_readiness_sample_count,
    profile_downgrade_count: readiness.profile_downgrade_count,
    rust_deny_count: readiness.rust_deny_count,
    profile_readiness: readiness.profile_readiness,
    model_call_plan_smoke_enabled: readiness.model_call_plan_smoke_enabled,
    model_call_plan_ready: readiness.model_call_plan_ready,
    model_call_plan_execution_blocked: readiness.model_call_plan_execution_blocked,
    model_call_plan_omitted_reason_counts: normalizedObjectCounts(readiness.model_call_plan_omitted_reason_counts),
    model_call_plan_selected_chunk_count: boundedCount(readiness.model_call_plan_selected_chunk_count),
    model_call_plan_selected_chunk_ref_count: boundedCount(readiness.model_call_plan_selected_chunk_ref_count),
    model_call_plan_omitted_ref_count: boundedCount(readiness.model_call_plan_omitted_ref_count),
    model_call_plan_omitted_chunk_ref_count: boundedCount(readiness.model_call_plan_omitted_chunk_ref_count),
    model_call_plan_index_granularity: safeString(readiness.model_call_plan_index_granularity),
    model_call_plan_index_source: safeString(readiness.model_call_plan_index_source),
    model_call_plan_chunk_identity_schema: safeString(readiness.model_call_plan_chunk_identity_schema),
    model_call_plan_chunk_expand_via_get_ref: readiness.model_call_plan_chunk_expand_via_get_ref === true,
    model_call_execution_gate_ready_for_execution: readiness.model_call_execution_gate_ready_for_execution === true,
    model_call_execution_admission_authority_in_rust: readiness.model_call_execution_admission_authority_in_rust === true,
    model_call_execution_gate_status: safeString(readiness.model_call_execution_gate_status),
    model_call_execution_gate_mode: safeString(readiness.model_call_execution_gate_mode),
    model_call_execution_gate_authority: safeString(readiness.model_call_execution_gate_authority),
    model_call_execution_gate_blocker_count: boundedCount(readiness.model_call_execution_gate_blocker_count),
    model_call_execute_blocked: readiness.model_call_execute_blocked === true,
    model_call_execute_status: safeString(readiness.model_call_execute_status),
    model_call_execute_mode: safeString(readiness.model_call_execute_mode),
    model_call_execute_authority: safeString(readiness.model_call_execute_authority),
    model_call_execute_executor: safeString(readiness.model_call_execute_executor),
    model_call_execute_blocker_count: boundedCount(readiness.model_call_execute_blocker_count),
    model_call_plan_issue_codes: readiness.model_call_plan_issue_codes,
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
