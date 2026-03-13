function safeNum(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function safeStr(v) {
  return String(v || '').trim();
}

function round6(v) {
  return Number(safeNum(v, 0).toFixed(6));
}

function parseIntInRange(v, fallback, minValue, maxValue) {
  const raw = Number(v);
  if (!Number.isFinite(raw)) return Math.max(minValue, Math.min(maxValue, Math.floor(fallback)));
  const n = Math.floor(raw);
  return Math.max(minValue, Math.min(maxValue, n));
}

function normalizeStageTraceRow(row) {
  const r = row && typeof row === 'object' ? row : {};
  return {
    stage: safeStr(r.stage),
    in_count: safeNum(r.in_count, 0),
    out_count: safeNum(r.out_count, 0),
    blocked: !!r.blocked,
    reason: safeStr(r.reason),
  };
}

function normalizeExplainItem(row, defaultRank = 1) {
  const r = row && typeof row === 'object' ? row : {};
  const riskFactors = Array.isArray(r.risk_factors)
    ? r.risk_factors.map((x) => safeStr(x)).filter(Boolean).slice(0, 4)
    : [];
  return {
    rank: Math.max(1, safeNum(r.rank, defaultRank)),
    id: safeStr(r.id),
    title: safeStr(r.title),
    sensitivity: safeStr(r.sensitivity) || 'public',
    trust_level: safeStr(r.trust_level) || 'trusted',
    final_score: round6(r.final_score),
    components: {
      vector_score: round6(r.vector_score),
      text_score: round6(r.lexical_score),
      recency_score: round6(r.recency_score),
      mmr_score: 0,
      relevance_score: round6(r.relevance_score),
      risk_penalty: round6(r.risk_penalty),
    },
    risk_level: safeStr(r.risk_level) || 'low',
    risk_factors: riskFactors,
  };
}

export function buildMemoryScoreExplainPayload({ retrieval, limit = 3, include_trace = false } = {}) {
  const out = retrieval && typeof retrieval === 'object' ? retrieval : {};
  const rows = Array.isArray(out.results) ? out.results : [];
  const lim = parseIntInRange(limit, 3, 1, 10);
  const normalized = rows.slice(0, lim).map((row, idx) => normalizeExplainItem(row, idx + 1));
  const weights = out.weights && typeof out.weights === 'object'
    ? {
        vector: round6(out.weights.vector),
        text: round6(out.weights.text),
        recency: round6(out.weights.recency),
        mmr: round6(out.weights.mmr),
        risk: round6(out.weights.risk || 1),
      }
    : {
        vector: 0,
        text: 0.85,
        recency: 0.15,
        mmr: 0,
        risk: 1,
      };
  const traceRows = include_trace
    ? (Array.isArray(out.pipeline_stage_trace) ? out.pipeline_stage_trace : [])
      .slice(0, 8)
      .map((row) => normalizeStageTraceRow(row))
    : [];

  return {
    schema_version: 'xhub.memory.score_explain.v1',
    formula: safeStr(out.formula) || 'final=relevance-risk_penalty; relevance=0.85*text+0.15*recency; vector=0; mmr=0',
    weights,
    blocked: !!out.blocked,
    deny_reason: safeStr(out.deny_reason),
    result_total: rows.length,
    explain_limit: lim,
    items: normalized,
    stage_trace: traceRows,
  };
}
