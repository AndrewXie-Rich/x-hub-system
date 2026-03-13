import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { listRuntimeModelRecords } from './local_runtime_ipc.js';
import { buildLocalTaskFailure, evaluateLocalTaskPolicyGate } from './local_task_policy.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const LOCAL_RUNTIME_SCRIPT = path.resolve(__dirname, '../../../python-runtime/python_service/relflowhub_local_runtime.py');

const EMBED_TASK_KIND = 'embedding';
const EMBED_PROVIDER = 'transformers';
const MAX_BATCH_TEXTS = 32;
const MAX_TEXT_CHARS = 4096;
const MAX_TOTAL_TEXT_CHARS = 32768;
const MAX_EMBED_DOCS = 64;
const EMBEDDING_CACHE_LIMIT = 2048;

const SECRET_REPLACEMENTS = Object.freeze([
  [/<private>[\s\S]*?<\/private>/ig, '[redacted_private]'],
  [/\[private\]/ig, '[redacted_private]'],
  [/\b(sk-|ghp_|xox[abprs]-|bearer\s+[a-z0-9\-_\.]+)/ig, '[redacted_secret]'],
  [/\b(api[_\s-]*key|private[_\s-]*key|secret[_\s-]*token|access[_\s-]*token|jwt|otp)\b/ig, '[redacted_secret_type]'],
  [/\b(password|passcode|payment[_\s-]*(pin|code)|authorization[_\s-]*code)\b/ig, '[redacted_sensitive_term]'],
  [/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/ig, '[redacted_email]'],
  [/\+?\d[\d\s().-]{7,}\d/g, '[redacted_phone]'],
  [/[0-9a-f]{32,}/ig, '[redacted_hex]'],
]);

const EMBEDDING_CACHE = new Map();

function safeString(value) {
  return String(value ?? '').trim();
}

function safeNum(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function normalizeSensitivity(value) {
  const text = safeString(value).toLowerCase();
  if (text === 'secret') return 'secret';
  if (text === 'internal') return 'internal';
  return 'public';
}

function normalizeTrust(value) {
  const text = safeString(value).toLowerCase();
  if (text === 'untrusted') return 'untrusted';
  return 'trusted';
}

function sha256Hex(text) {
  return crypto.createHash('sha256').update(String(text || ''), 'utf8').digest('hex');
}

function chunkArray(items, size) {
  const out = [];
  const rows = Array.isArray(items) ? items : [];
  const width = Math.max(1, Number(size || 1));
  for (let idx = 0; idx < rows.length; idx += width) {
    out.push(rows.slice(idx, idx + width));
  }
  return out;
}

function pruneEmbeddingCache() {
  while (EMBEDDING_CACHE.size > EMBEDDING_CACHE_LIMIT) {
    const firstKey = EMBEDDING_CACHE.keys().next().value;
    if (!firstKey) break;
    EMBEDDING_CACHE.delete(firstKey);
  }
}

function embeddingCacheKey(modelId, text) {
  return `${safeString(modelId)}:${sha256Hex(text)}`;
}

function vectorDims(vector) {
  return Array.isArray(vector) ? vector.length : 0;
}

function sanitizeEmbeddingText(input) {
  const raw = String(input ?? '');
  let text = raw;
  const findings = [];
  for (const [pattern, replacement] of SECRET_REPLACEMENTS) {
    const next = text.replace(pattern, replacement);
    if (next === text) continue;
    findings.push(pattern.source);
    text = next;
  }
  const compact = text.replace(/\s+/g, ' ').trim();
  return {
    raw,
    text: compact,
    changed: compact !== raw.trim(),
    findings,
    raw_chars: raw.length,
    sanitized_chars: compact.length,
  };
}

export function buildMemoryEmbeddingDocText(doc) {
  const tags = Array.isArray(doc?.tags) ? doc.tags.join(' ') : '';
  return `${safeString(doc?.title)} ${safeString(doc?.text)} ${safeString(tags)}`.trim();
}

function defaultSelectDocs(documents) {
  const rows = Array.isArray(documents) ? documents.slice() : [];
  rows.sort((a, b) => safeNum(b?.created_at_ms, 0) - safeNum(a?.created_at_ms, 0));
  return rows;
}

function filterEmbeddingEligibleDocs(documents, { allowedSensitivity, allowUntrusted } = {}) {
  const allowed = allowedSensitivity instanceof Set
    ? allowedSensitivity
    : new Set(Array.isArray(allowedSensitivity) ? allowedSensitivity.map((item) => normalizeSensitivity(item)) : ['public', 'internal']);
  return (Array.isArray(documents) ? documents : []).filter((doc) => {
    const sensitivity = normalizeSensitivity(doc?.sensitivity);
    const trust = normalizeTrust(doc?.trust_level);
    if (!allowed.has(sensitivity)) return false;
    if (!allowUntrusted && trust === 'untrusted') return false;
    return true;
  });
}

function defaultRuntimeTaskExecutor({ runtimeBaseDir, request, timeoutMs = 30_000 } = {}) {
  const baseDir = safeString(runtimeBaseDir);
  const payload = JSON.stringify(request || {});
  return new Promise((resolve, reject) => {
    const child = spawn(
      'python3',
      [LOCAL_RUNTIME_SCRIPT, 'run-local-task', '-'],
      {
        env: {
          ...process.env,
          REL_FLOW_HUB_BASE_DIR: baseDir,
        },
        stdio: ['pipe', 'pipe', 'pipe'],
      }
    );

    let stdout = '';
    let stderr = '';
    let settled = false;
    const timeout = setTimeout(() => {
      if (settled) return;
      settled = true;
      try {
        child.kill('SIGKILL');
      } catch {
        // ignore
      }
      reject(new Error('local_embedding_timeout'));
    }, Math.max(1000, Number(timeoutMs || 30_000)));

    child.stdout.on('data', (chunk) => {
      stdout += String(chunk || '');
    });
    child.stderr.on('data', (chunk) => {
      stderr += String(chunk || '');
    });
    child.on('error', (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(error);
    });
    child.on('close', (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      if (code !== 0) {
        reject(new Error(safeString(stderr) || `local_embedding_runtime_exit_${code}`));
        return;
      }
      try {
        resolve(JSON.parse(String(stdout || '{}')));
      } catch {
        reject(new Error(safeString(stdout) || safeString(stderr) || 'local_embedding_invalid_json'));
      }
    });

    try {
      child.stdin.write(payload, 'utf8');
      child.stdin.end();
    } catch (error) {
      if (!settled) {
        settled = true;
        clearTimeout(timeout);
        reject(error);
      }
    }
  });
}

function resolveLocalEmbeddingModel(runtimeBaseDir, preferredModelId = '') {
  const preferred = safeString(preferredModelId);
  const records = listRuntimeModelRecords(runtimeBaseDir);
  if (preferred) {
    const exact = records.find((record) =>
      safeString(record?.model_id) === preferred
      && safeString(record?.backend).toLowerCase() === 'transformers'
      && Array.isArray(record?.task_kinds)
      && record.task_kinds.includes(EMBED_TASK_KIND)
      && safeString(record?.model_path)
    );
    if (exact) return exact;
  }
  return records.find((record) =>
    safeString(record?.backend).toLowerCase() === 'transformers'
    && Array.isArray(record?.task_kinds)
    && record.task_kinds.includes(EMBED_TASK_KIND)
    && safeString(record?.model_path)
  ) || null;
}

async function requestEmbeddingVectors({
  runtimeBaseDir,
  requestId,
  model,
  items,
  executor,
} = {}) {
  const taskExecutor = typeof executor === 'function' ? executor : defaultRuntimeTaskExecutor;
  const rows = Array.isArray(items) ? items : [];
  const modelId = safeString(model?.model_id);
  const modelPath = safeString(model?.model_path);

  const results = new Array(rows.length).fill(null);
  const missing = [];
  let cacheHitCount = 0;

  for (let idx = 0; idx < rows.length; idx += 1) {
    const row = rows[idx] || {};
    const cacheKey = embeddingCacheKey(modelId, row.text);
    const cached = EMBEDDING_CACHE.get(cacheKey);
    if (cached && Array.isArray(cached.vector) && vectorDims(cached.vector) > 0) {
      results[idx] = cached.vector;
      cacheHitCount += 1;
      continue;
    }
    missing.push({ ...row, idx, cacheKey });
  }

  let dims = 0;
  let providerLatencyMs = 0;
  let provider = safeString(model?.backend).toLowerCase() || 'transformers';
  for (const batch of chunkArray(missing, MAX_BATCH_TEXTS)) {
    if (!batch.length) continue;
    const response = await taskExecutor({
      runtimeBaseDir,
      timeoutMs: 30_000,
      request: {
        provider,
        task_kind: EMBED_TASK_KIND,
        model_id: modelId,
        model_path: modelPath,
        task_kinds: Array.isArray(model?.task_kinds) ? model.task_kinds : [EMBED_TASK_KIND],
        request_id: safeString(requestId),
        input_sanitized: true,
        texts: batch.map((row) => row.text),
      },
    });
    if (!response || typeof response !== 'object' || response.ok !== true) {
      return {
        ok: false,
        deny_code: safeString(response?.error) || 'local_embedding_runtime_failed',
        message: safeString(response?.errorDetail || response?.error || 'local_embedding_runtime_failed'),
        attempted: true,
        provider,
        model_id: modelId,
      };
    }
    const vectors = Array.isArray(response.vectors) ? response.vectors : [];
    if (vectors.length !== batch.length) {
      return {
        ok: false,
        deny_code: 'local_embedding_vector_count_mismatch',
        message: 'local_embedding_vector_count_mismatch',
        attempted: true,
        provider,
        model_id: modelId,
      };
    }
    provider = safeString(response.provider) || provider;
    providerLatencyMs += Math.max(0, safeNum(response.latencyMs, 0));
    dims = Math.max(dims, safeNum(response.dims, 0));
    for (let idx = 0; idx < batch.length; idx += 1) {
      const row = batch[idx];
      const vector = Array.isArray(vectors[idx]) ? vectors[idx].map((value) => Number(value)) : [];
      if (!vector.length) {
        return {
          ok: false,
          deny_code: 'local_embedding_vector_invalid',
          message: 'local_embedding_vector_invalid',
          attempted: true,
          provider,
          model_id: modelId,
        };
      }
      results[row.idx] = vector;
      EMBEDDING_CACHE.set(row.cacheKey, {
        vector,
        dims: vector.length,
        created_at_ms: Date.now(),
      });
      pruneEmbeddingCache();
    }
  }

  const vectors = results.map((row) => Array.isArray(row) ? row : []);
  dims = Math.max(dims, ...vectors.map((vector) => vectorDims(vector)));
  return {
    ok: true,
    provider,
    model_id: modelId,
    dims,
    vectors,
    cache_hit_count: cacheHitCount,
    cache_miss_count: missing.length,
    latency_ms: providerLatencyMs,
    attempted: missing.length > 0,
  };
}

export async function prepareLocalMemoryEmbeddings({
  runtimeBaseDir,
  requestId = '',
  preferredModelId = '',
  query = '',
  documents = [],
  allowedSensitivity = ['public', 'internal'],
  allowUntrusted = false,
  capabilityAllowed = true,
  capabilityDenyCode = '',
  killSwitch = null,
  executor = null,
} = {}) {
  const startedAtMs = Date.now();
  const baseDir = safeString(runtimeBaseDir);
  const fail = ({
    rawDenyCode,
    message = '',
    blockedBy = '',
    ruleIds = [],
    latencyMs = 0,
    extra = {},
  } = {}) => ({
    ...buildLocalTaskFailure({
      taskKind: EMBED_TASK_KIND,
      provider: EMBED_PROVIDER,
      rawDenyCode,
      message,
      blockedBy,
      ruleIds,
    }),
    fallback_mode: 'lexical_only',
    latency_ms: Math.max(0, Number(latencyMs || 0)),
    ...extra,
  });
  if (!baseDir) {
    return fail({ rawDenyCode: 'runtime_base_dir_missing' });
  }
  const policyGate = evaluateLocalTaskPolicyGate({
    taskKind: EMBED_TASK_KIND,
    provider: EMBED_PROVIDER,
    capabilityAllowed,
    capabilityDenyCode,
    killSwitch,
  });
  if (!policyGate.ok) {
    return {
      ...policyGate,
      fallback_mode: 'lexical_only',
      latency_ms: 0,
    };
  }

  const queryText = sanitizeEmbeddingText(query);
  if (!queryText.text) {
    return fail({ rawDenyCode: 'embedding_query_empty' });
  }
  if (queryText.sanitized_chars > MAX_TEXT_CHARS) {
    return fail({
      rawDenyCode: 'embedding_query_too_large',
      blockedBy: 'input',
    });
  }

  const model = resolveLocalEmbeddingModel(baseDir, preferredModelId);
  if (!model) {
    return fail({
      rawDenyCode: 'local_embedding_model_unavailable',
      blockedBy: 'provider',
    });
  }

  const eligibleDocs = filterEmbeddingEligibleDocs(defaultSelectDocs(documents), {
    allowedSensitivity,
    allowUntrusted,
  });
  const selectedDocs = [];
  let totalChars = queryText.sanitized_chars;
  let truncatedDocumentCount = 0;
  let sanitizedChangeCount = queryText.changed ? 1 : 0;
  let sanitizedFindingCount = queryText.findings.length;
  for (const doc of eligibleDocs) {
    if (selectedDocs.length >= MAX_EMBED_DOCS) {
      truncatedDocumentCount += 1;
      continue;
    }
    const sanitized = sanitizeEmbeddingText(buildMemoryEmbeddingDocText(doc));
    if (!sanitized.text) {
      truncatedDocumentCount += 1;
      continue;
    }
    if (sanitized.sanitized_chars > MAX_TEXT_CHARS) {
      truncatedDocumentCount += 1;
      continue;
    }
    if ((totalChars + sanitized.sanitized_chars) > MAX_TOTAL_TEXT_CHARS) {
      truncatedDocumentCount += 1;
      continue;
    }
    totalChars += sanitized.sanitized_chars;
    if (sanitized.changed) sanitizedChangeCount += 1;
    sanitizedFindingCount += sanitized.findings.length;
    selectedDocs.push({
      id: safeString(doc?.id),
      text: sanitized.text,
    });
  }

  if (!selectedDocs.length) {
    return fail({
      rawDenyCode: 'local_embedding_docs_unavailable',
      blockedBy: 'policy',
      latencyMs: Math.max(0, Date.now() - startedAtMs),
      extra: {
        provider: 'transformers',
        model_id: safeString(model?.model_id),
        eligible_document_count: eligibleDocs.length,
        truncated_document_count: truncatedDocumentCount,
        sanitized_change_count: sanitizedChangeCount,
        sanitized_finding_count: sanitizedFindingCount,
      },
    });
  }

  const vectorResponse = await requestEmbeddingVectors({
    runtimeBaseDir: baseDir,
    requestId: safeString(requestId),
    model,
    items: [
      { kind: 'query', text: queryText.text },
      ...selectedDocs.map((doc) => ({ kind: 'doc', id: doc.id, text: doc.text })),
    ],
    executor,
  });
  if (!vectorResponse.ok) {
    return fail({
      rawDenyCode: safeString(vectorResponse.deny_code) || 'local_embedding_runtime_failed',
      message: safeString(vectorResponse.message) || safeString(vectorResponse.deny_code) || 'local_embedding_runtime_failed',
      blockedBy: 'provider',
      latencyMs: Math.max(0, Date.now() - startedAtMs),
      extra: {
        provider: safeString(vectorResponse.provider) || 'transformers',
        model_id: safeString(vectorResponse.model_id) || safeString(model?.model_id),
        attempted: !!vectorResponse.attempted,
        eligible_document_count: eligibleDocs.length,
        truncated_document_count: truncatedDocumentCount,
        sanitized_change_count: sanitizedChangeCount,
        sanitized_finding_count: sanitizedFindingCount,
      },
    });
  }

  const vectors = Array.isArray(vectorResponse.vectors) ? vectorResponse.vectors : [];
  const queryVector = Array.isArray(vectors[0]) ? vectors[0] : [];
  const docVectors = vectors.slice(1);
  const embeddedDocs = [];
  for (let idx = 0; idx < selectedDocs.length; idx += 1) {
    const vector = Array.isArray(docVectors[idx]) ? docVectors[idx] : [];
    if (!vector.length) continue;
    embeddedDocs.push({
      id: selectedDocs[idx].id,
      embedding_vector: vector,
    });
  }

  return {
    ok: true,
    task_kind: EMBED_TASK_KIND,
    capability: policyGate.capability,
    fallback_mode: '',
    latency_ms: Math.max(0, Date.now() - startedAtMs),
    provider: safeString(vectorResponse.provider) || 'transformers',
    model_id: safeString(vectorResponse.model_id) || safeString(model?.model_id),
    dims: Math.max(0, safeNum(vectorResponse.dims, vectorDims(queryVector))),
    query_embedding: queryVector,
    documents: embeddedDocs,
    vector_count: embeddedDocs.length + (queryVector.length ? 1 : 0),
    eligible_document_count: eligibleDocs.length,
    embedded_document_count: embeddedDocs.length,
    truncated_document_count: truncatedDocumentCount,
    cache_hit_count: Math.max(0, safeNum(vectorResponse.cache_hit_count, 0)),
    cache_miss_count: Math.max(0, safeNum(vectorResponse.cache_miss_count, 0)),
    sanitized_change_count: sanitizedChangeCount,
    sanitized_finding_count: sanitizedFindingCount,
    attempted: !!vectorResponse.attempted,
  };
}
