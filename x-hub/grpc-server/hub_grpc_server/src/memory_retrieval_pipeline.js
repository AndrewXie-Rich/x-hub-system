function tokenizeText(v) {
  const text = String(v || "").toLowerCase();
  const m = text.match(/[a-z0-9\u4e00-\u9fff]+/g);
  return m ? m : [];
}

const DOC_SEARCH_TOKEN_SET_CACHE = new WeakMap();
const DOC_RISK_HINT_CACHE = new WeakMap();

function safeNum(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function safeStr(v) {
  return String(v || "").trim();
}

function normalizeScope(scope) {
  const src = scope && typeof scope === "object" ? scope : {};
  const out = {};
  const keys = ["device_id", "user_id", "project_id", "thread_id"];
  for (const k of keys) {
    const val = safeStr(src[k]);
    if (val) out[k] = val;
  }
  return out;
}

function normalizeSensitivity(v) {
  const s = safeStr(v).toLowerCase();
  if (s === "secret") return "secret";
  if (s === "internal") return "internal";
  return "public";
}

function normalizeTrust(v) {
  const s = safeStr(v).toLowerCase();
  if (s === "untrusted") return "untrusted";
  return "trusted";
}

function round6(v) {
  return Number(safeNum(v, 0).toFixed(6));
}

function normalizeVector(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const value of raw) {
    const n = Number(value);
    if (!Number.isFinite(n)) return [];
    out.push(n);
  }
  return out;
}

function cosineSimilarity(queryVector, docVector) {
  const left = normalizeVector(queryVector);
  const right = normalizeVector(docVector);
  if (!left.length || left.length !== right.length) return 0;
  let dot = 0;
  let leftNorm = 0;
  let rightNorm = 0;
  for (let idx = 0; idx < left.length; idx += 1) {
    dot += left[idx] * right[idx];
    leftNorm += left[idx] * left[idx];
    rightNorm += right[idx] * right[idx];
  }
  const denom = Math.sqrt(leftNorm) * Math.sqrt(rightNorm);
  if (!denom) return 0;
  return Math.max(-1, Math.min(1, dot / denom));
}

function docSearchSource(doc) {
  const tags = Array.isArray(doc?.tags) ? doc.tags.join(" ") : "";
  return `${safeStr(doc?.title)} ${safeStr(doc?.text)} ${safeStr(tags)}`.trim();
}

function getDocSearchTokenSet(doc) {
  if (!doc || typeof doc !== "object") return new Set();
  const source = docSearchSource(doc);
  const cached = DOC_SEARCH_TOKEN_SET_CACHE.get(doc);
  if (cached && cached.source === source) return cached.token_set;
  const tokenSet = new Set(tokenizeText(source));
  DOC_SEARCH_TOKEN_SET_CACHE.set(doc, { source, token_set: tokenSet });
  return tokenSet;
}

function getDocRiskHints(doc) {
  if (!doc || typeof doc !== "object") {
    return { sensitivity: "public", trust: "trusted", credential_like: false };
  }
  const source = docSearchSource(doc);
  const sensitivity = normalizeSensitivity(doc?.sensitivity);
  const trust = normalizeTrust(doc?.trust_level);
  const cache = DOC_RISK_HINT_CACHE.get(doc);
  if (
    cache
    && cache.source === source
    && cache.sensitivity === sensitivity
    && cache.trust === trust
  ) {
    return cache;
  }
  const next = {
    source,
    sensitivity,
    trust,
    credential_like: credentialLikeText(source),
  };
  DOC_RISK_HINT_CACHE.set(doc, next);
  return next;
}

function matchScope(docScope, reqScope) {
  const ds = docScope && typeof docScope === "object" ? docScope : {};
  for (const k of Object.keys(reqScope)) {
    const expected = safeStr(reqScope[k]);
    if (!expected) continue;
    if (safeStr(ds[k]) !== expected) return false;
  }
  return true;
}

function scoreLexical(qTokens, docTokenSet) {
  if (!qTokens.length) return 0;
  if (!docTokenSet || !docTokenSet.size) return 0;
  let hit = 0;
  for (const t of qTokens) {
    if (docTokenSet.has(t)) hit += 1;
  }
  return hit / qTokens.length;
}

function queryRiskScore(query) {
  const q = safeStr(query).toLowerCase();
  if (!q) return 0;
  const high = [
    /reveal.*(secret|token|password|key|credential)/,
    /dump.*(secret|credential|token)/,
    /bypass|override|disable\s+dlp/,
    /\b(sk-|ghp_|xox[abprs]-|bearer\s+[a-z0-9\-_\.]+)/,
  ];
  for (const p of high) {
    if (p.test(q)) return 1;
  }
  const medium = [
    /\b(payment|paycode|approve|authorization|grant)\b/,
    /\b(export|remote|extern|upload)\b/,
    /\bprivate|sensitive|confidential\b/,
  ];
  for (const p of medium) {
    if (p.test(q)) return 0.5;
  }
  return 0;
}

function credentialLikeText(v) {
  const text = safeStr(v);
  if (!text) return false;
  const patterns = [
    /\b(sk-|ghp_|xox[abprs]-|bearer\s+[a-z0-9\-_\.]+)/i,
    /\b(api[_\s-]*key|private[_\s-]*key|secret[_\s-]*token|access[_\s-]*token|jwt|otp|payment[_\s-]*pin)\b/i,
    /[0-9a-f]{32,}/i,
  ];
  return patterns.some((p) => p.test(text));
}

function computeRiskPenalty({ doc, queryRisk, remoteMode, enabled, riskHints }) {
  if (!enabled) {
    return {
      risk_penalty: 0,
      risk_level: "low",
      risk_factors: [],
    };
  }
  const factors = [];
  let penalty = 0;
  const sensitivity = normalizeSensitivity(riskHints?.sensitivity || doc?.sensitivity);
  const trust = normalizeTrust(riskHints?.trust || doc?.trust_level);
  const qRisk = safeNum(queryRisk, 0);
  if (sensitivity === "secret") {
    penalty += 0.45;
    factors.push("sensitivity:secret");
  } else if (sensitivity === "internal") {
    penalty += 0.12;
    factors.push("sensitivity:internal");
  }
  if (trust === "untrusted") {
    penalty += 0.2;
    factors.push("trust:untrusted");
  }

  if (riskHints?.credential_like) {
    penalty += 0.3;
    factors.push("content:credential_like");
  }

  if (qRisk >= 1) {
    penalty += 0.1;
    factors.push("query:high_risk");
  } else if (qRisk >= 0.5) {
    penalty += 0.05;
    factors.push("query:medium_risk");
  }

  if (remoteMode && sensitivity !== "public") {
    penalty += 0.1;
    factors.push("channel:remote_non_public");
  }

  penalty = Math.max(0, Math.min(0.95, penalty));
  const level = penalty >= 0.5 ? "high" : penalty >= 0.2 ? "medium" : "low";
  return {
    risk_penalty: round6(penalty),
    risk_level: level,
    risk_factors: factors,
  };
}

function computeRecencyScore(rows) {
  const ts = rows.map((r) => safeNum(r?.doc?.created_at_ms, 0));
  const min = Math.min(...ts);
  const max = Math.max(...ts);
  if (!Number.isFinite(min) || !Number.isFinite(max) || max <= min) {
    return rows.map((r) => ({ ...r, recency_score: 1 }));
  }
  return rows.map((r) => {
    const v = safeNum(r?.doc?.created_at_ms, 0);
    const score = Math.max(0, Math.min(1, (v - min) / (max - min)));
    return { ...r, recency_score: score };
  });
}

function applyInputPolicy(input) {
  const requested = Array.isArray(input?.allowed_sensitivity)
    ? input.allowed_sensitivity.map((s) => normalizeSensitivity(s))
    : ["public", "internal"];
  const allowed = new Set(requested);
  const allowUntrusted = !!input?.allow_untrusted;
  const topK = Math.max(1, Math.min(50, safeNum(input?.top_k, 5)));
  const riskPenaltyEnabled = input?.risk_penalty_enabled !== false;
  return {
    allowedSensitivity: allowed,
    allowUntrusted,
    topK,
    riskPenaltyEnabled,
  };
}

function gateDecision({ query, remoteMode, candidates }) {
  const q = safeStr(query).toLowerCase();
  const blockPatterns = [
    /ignore\s+(all\s+)?(previous|prior|above)\s+instructions?/,
    /reveal.*(secret|token|password|private\s*key|api\s*key)/,
    /dump.*(secret|credential|token)/,
    /\b(sk-|ghp_|xox[abprs]-|bearer\s+[a-z0-9\-_\.]+)/,
    /disable\s+dlp|bypass\s+gate/,
  ];
  for (const p of blockPatterns) {
    if (p.test(q)) return { blocked: true, reason: `query_pattern:${p.source}` };
  }

  const hasSecret = candidates.some((r) => normalizeSensitivity(r?.doc?.sensitivity) === "secret");
  if (remoteMode && hasSecret) {
    return { blocked: true, reason: "remote_secret_denied" };
  }
  return { blocked: false, reason: "allow" };
}

export const PIPELINE_STAGES = Object.freeze([
  "scope_filter",
  "sensitivity_trust_filter",
  "retrieval",
  "rerank",
  "gate",
]);

export function runMemoryRetrievalPipeline(input = {}) {
  const docs = Array.isArray(input.documents) ? input.documents : [];
  const query = safeStr(input.query);
  const queryTokens = tokenizeText(query);
  const queryEmbedding = normalizeVector(input.query_embedding || input.queryEmbedding);
  const queryRisk = queryRiskScore(query);
  const reqScope = normalizeScope(input.scope);
  const policy = applyInputPolicy(input);
  const remoteMode = !!input.remote_mode;
  const traceEnabled = input?.trace_enabled !== false;
  const trace = [];

  // stage 1: scope filter
  const scoped = docs.filter((d) => matchScope(d?.scope, reqScope));
  if (traceEnabled) {
    trace.push({
      stage: "scope_filter",
      in_count: docs.length,
      out_count: scoped.length,
      scope: reqScope,
    });
  }

  // stage 2: sensitivity/trust filter
  const sensTrusted = scoped.filter((d) => {
    const sensitivity = normalizeSensitivity(d?.sensitivity);
    const trust = normalizeTrust(d?.trust_level);
    if (!policy.allowedSensitivity.has(sensitivity)) return false;
    if (!policy.allowUntrusted && trust === "untrusted") return false;
    return true;
  });
  if (traceEnabled) {
    trace.push({
      stage: "sensitivity_trust_filter",
      in_count: scoped.length,
      out_count: sensTrusted.length,
      allowed_sensitivity: Array.from(policy.allowedSensitivity),
      allow_untrusted: policy.allowUntrusted,
    });
  }

  // stage 3: retrieval
  const retrieved = [];
  for (const doc of sensTrusted) {
    const docTokenSet = getDocSearchTokenSet(doc);
    const lexical = scoreLexical(queryTokens, docTokenSet);
    const vectorScore = Math.max(0, cosineSimilarity(queryEmbedding, doc?.embedding_vector || doc?.embedding || doc?.vector));
    const hasVector = vectorScore > 0;
    if (lexical <= 0 && !hasVector) continue;
    retrieved.push({
      doc,
      lexical_score: lexical,
      vector_score: round6(vectorScore),
      has_vector: hasVector,
      risk_hints: getDocRiskHints(doc),
    });
  }
  const anyVectorSignal = retrieved.some((row) => row.has_vector);
  if (traceEnabled) {
    trace.push({
      stage: "retrieval",
      in_count: sensTrusted.length,
      out_count: retrieved.length,
      method: anyVectorSignal ? "hybrid_lexical_vector_v1" : "lexical_overlap_v1",
    });
  }

  // stage 4: rerank
  const withRecency = computeRecencyScore(retrieved);
  const reranked = withRecency
    .map((r) => {
      const hasVector = !!r.has_vector;
      const weights = hasVector
        ? { vector: 0.35, text: 0.5, recency: 0.15 }
        : { vector: 0, text: 0.85, recency: 0.15 };
      const relevanceScore =
        (weights.vector * safeNum(r.vector_score, 0))
        + (weights.text * safeNum(r.lexical_score, 0))
        + (weights.recency * safeNum(r.recency_score, 0));
      const risk = computeRiskPenalty({
        doc: r?.doc,
        queryRisk,
        remoteMode,
        enabled: policy.riskPenaltyEnabled,
        riskHints: r?.risk_hints,
      });
      const finalScore = relevanceScore - safeNum(risk.risk_penalty, 0);
      return {
        ...r,
        weights,
        relevance_score: round6(relevanceScore),
        risk_penalty: round6(risk.risk_penalty),
        risk_level: String(risk.risk_level || "low"),
        risk_factors: Array.isArray(risk.risk_factors) ? risk.risk_factors : [],
        final_score: round6(finalScore),
      };
    })
    .sort((a, b) => {
      if (safeNum(b.final_score, 0) !== safeNum(a.final_score, 0)) {
        return safeNum(b.final_score, 0) - safeNum(a.final_score, 0);
      }
      return safeNum(b?.doc?.created_at_ms, 0) - safeNum(a?.doc?.created_at_ms, 0);
    });
  if (traceEnabled) {
    trace.push({
      stage: "rerank",
      in_count: retrieved.length,
      out_count: reranked.length,
      formula: anyVectorSignal
        ? "final=relevance-risk_penalty, relevance=0.35*vector+0.5*lexical+0.15*recency"
        : "final=relevance-risk_penalty, relevance=0.85*lexical+0.15*recency",
      risk_penalty_enabled: policy.riskPenaltyEnabled,
    });
  }

  // stage 5: gate
  const gate = gateDecision({
    query,
    remoteMode,
    candidates: reranked,
  });
  if (traceEnabled) {
    trace.push({
      stage: "gate",
      in_count: reranked.length,
      out_count: gate.blocked ? 0 : Math.min(policy.topK, reranked.length),
      blocked: gate.blocked,
      reason: gate.reason,
    });
  }

  if (gate.blocked) {
    return {
      blocked: true,
      deny_reason: gate.reason,
      pipeline_stage_trace: traceEnabled ? trace : [],
      results: [],
    };
  }

  const top = reranked.slice(0, policy.topK).map((r, idx) => ({
    rank: idx + 1,
    id: safeStr(r?.doc?.id),
    title: safeStr(r?.doc?.title),
    scope: r?.doc?.scope && typeof r.doc.scope === "object" ? r.doc.scope : {},
    sensitivity: normalizeSensitivity(r?.doc?.sensitivity),
    trust_level: normalizeTrust(r?.doc?.trust_level),
    vector_score: round6(r.vector_score),
    lexical_score: Number(safeNum(r.lexical_score, 0).toFixed(6)),
    recency_score: Number(safeNum(r.recency_score, 0).toFixed(6)),
    relevance_score: round6(r.relevance_score),
    risk_penalty: round6(r.risk_penalty),
    risk_level: String(r.risk_level || "low"),
    risk_factors: Array.isArray(r.risk_factors) ? r.risk_factors : [],
    final_score: Number(safeNum(r.final_score, 0).toFixed(6)),
    created_at_ms: safeNum(r?.doc?.created_at_ms, 0),
  }));

  return {
    blocked: false,
    deny_reason: "",
    formula: anyVectorSignal
      ? "final=relevance-risk_penalty; relevance=0.35*vector+0.5*text+0.15*recency; mmr=0"
      : "final=relevance-risk_penalty; relevance=0.85*text+0.15*recency; vector=0; mmr=0",
    weights: {
      vector: anyVectorSignal ? 0.35 : 0,
      text: anyVectorSignal ? 0.5 : 0.85,
      recency: 0.15,
      mmr: 0,
      risk: 1,
    },
    pipeline_stage_trace: traceEnabled ? trace : [],
    results: top,
  };
}
