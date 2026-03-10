#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

let DatabaseSync = null;
try {
  // Node built-in SQLite (experimental in current toolchain).
  ({ DatabaseSync } = require("node:sqlite"));
} catch {
  DatabaseSync = null;
}

const DEFAULT_THRESHOLDS = Object.freeze({
  window_ms: 24 * 60 * 60 * 1000,
  max_events: 5000,
  noise_control: {
    min_samples: 20,
    critical_margin_ratio: 0.2,
  },
  latency: {
    benchmark_p95_ms_max: 1500,
    benchmark_p99_ms_max: 2500,
    runtime_duration_p95_ms_max: 3000,
    runtime_queue_wait_p95_ms_max: 2000,
    runtime_queue_depth_p95_max: 64,
  },
  quality: {
    precision_at_k_min: 0.15,
    recall_at_k_min: 0.8,
  },
  freshness: {
    index_freshness_p95_ms_max: 5 * 60 * 1000,
    index_freshness_max_ms_max: 15 * 60 * 1000,
  },
  security: {
    adversarial_block_rate_min: 0.45,
    runtime_block_rate_max: 0.2,
    runtime_downgrade_rate_max: 0.3,
  },
  stage: {
    anomaly_score_warn: 40,
    anomaly_score_critical: 80,
  },
});

function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i += 1) {
    const cur = String(argv[i] || "");
    if (!cur.startsWith("--")) continue;
    const key = cur.slice(2);
    const nxt = argv[i + 1];
    if (nxt && !String(nxt).startsWith("--")) {
      out[key] = String(nxt);
      i += 1;
    } else {
      out[key] = "1";
    }
  }
  return out;
}

function readJson(fp) {
  return JSON.parse(fs.readFileSync(fp, "utf8"));
}

function ensureDirFor(fp) {
  fs.mkdirSync(path.dirname(fp), { recursive: true });
}

function toFiniteNumber(v, fallback = null) {
  if (v == null || v === "") return fallback;
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return n;
}

function clamp01(v) {
  const n = toFiniteNumber(v, null);
  if (n == null) return null;
  return Math.max(0, Math.min(1, n));
}

function percentile(values, p) {
  const arr = (Array.isArray(values) ? values : [])
    .map((v) => toFiniteNumber(v, null))
    .filter((v) => v != null)
    .sort((a, b) => a - b);
  if (!arr.length) return null;
  const idx = Math.min(arr.length - 1, Math.max(0, Math.ceil((Number(p || 0) / 100) * arr.length) - 1));
  return arr[idx];
}

function average(values) {
  const arr = (Array.isArray(values) ? values : [])
    .map((v) => toFiniteNumber(v, null))
    .filter((v) => v != null);
  if (!arr.length) return null;
  return arr.reduce((a, b) => a + b, 0) / arr.length;
}

function normalizeDistribution(values = []) {
  const arr = values
    .map((v) => toFiniteNumber(v, null))
    .filter((v) => v != null);
  if (!arr.length) {
    return {
      samples: 0,
      p50: null,
      p95: null,
      p99: null,
      max: null,
      avg: null,
    };
  }
  const sorted = [...arr].sort((a, b) => a - b);
  return {
    samples: sorted.length,
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    p99: percentile(sorted, 99),
    max: sorted[sorted.length - 1],
    avg: average(sorted),
  };
}

function mergeThresholds(base, override) {
  const dst = JSON.parse(JSON.stringify(base || {}));
  if (!override || typeof override !== "object") return dst;
  const walk = (target, src) => {
    for (const [k, v] of Object.entries(src)) {
      if (v && typeof v === "object" && !Array.isArray(v) && target[k] && typeof target[k] === "object") {
        walk(target[k], v);
      } else {
        target[k] = v;
      }
    }
  };
  walk(dst, override);
  return dst;
}

function safeParseExt(extLike) {
  if (!extLike) return {};
  if (typeof extLike === "object") return extLike;
  const raw = String(extLike || "").trim();
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

function normalizeAuditEvents(rawRows = []) {
  const rows = Array.isArray(rawRows) ? rawRows : [];
  const out = [];
  for (const row of rows) {
    const ext = safeParseExt(row?.ext_json || row?.ext || row?.payload);
    const metrics = ext?.metrics && typeof ext.metrics === "object"
      ? ext.metrics
      : (row?.metrics && typeof row.metrics === "object" ? row.metrics : null);
    out.push({
      created_at_ms: Math.max(0, Number(row?.created_at_ms || 0)),
      event_type: String(row?.event_type || metrics?.event_kind || "").trim(),
      error_code: String(row?.error_code || "").trim(),
      ok: row?.ok == null ? null : !!row.ok,
      ext,
      metrics: metrics && typeof metrics === "object" ? metrics : null,
    });
  }
  return out;
}

function loadAuditEventsFromDb(dbPath, { sinceMs, untilMs, maxEvents }) {
  if (!dbPath || !DatabaseSync) return [];
  if (!fs.existsSync(dbPath)) return [];
  const db = new DatabaseSync(dbPath);
  try {
    const sql = `
      SELECT created_at_ms, event_type, error_code, ok, ext_json
      FROM audit_events
      WHERE created_at_ms >= ? AND created_at_ms <= ?
      ORDER BY created_at_ms DESC
      LIMIT ?
    `;
    return db.prepare(sql).all(
      Math.max(0, Number(sinceMs || 0)),
      Math.max(0, Number(untilMs || Date.now())),
      Math.max(1, Number(maxEvents || 5000))
    );
  } finally {
    try {
      db.close();
    } catch {
      // ignore
    }
  }
}

function inferStageFromReason(reasonLike) {
  const reason = String(reasonLike || "").toLowerCase();
  if (!reason) return "unknown";
  if (/scope|thread_not_found|permission_denied/.test(reason)) return "scope_filter";
  if (/sensitivity|trust|remote_secret/.test(reason)) return "sensitivity_trust_filter";
  if (/retrieval|index/.test(reason)) return "retrieval";
  if (/rerank|risk|score/.test(reason)) return "rerank";
  if (/gate|query_pattern|credential|secret_mode|allow_class|remote_export|blocked|deny/.test(reason)) return "gate";
  return "gate";
}

function collectRuntimeMetrics(events = []) {
  const rows = Array.isArray(events) ? events : [];
  const durationMs = [];
  const queueWaitMs = [];
  const queueDepth = [];
  const resultCount = [];
  const promptTokens = [];
  const completionTokens = [];
  const totalTokens = [];
  const indexFreshnessMs = [];

  let aiGenerateCount = 0;
  let runtimeBlockedCount = 0;
  let runtimeDowngradedCount = 0;

  for (const ev of rows) {
    const metrics = ev?.metrics && typeof ev.metrics === "object" ? ev.metrics : null;
    if (!metrics) continue;
    const eventKind = String(metrics?.event_kind || ev?.event_type || "").toLowerCase();
    const latency = metrics?.latency && typeof metrics.latency === "object" ? metrics.latency : {};
    const quality = metrics?.quality && typeof metrics.quality === "object" ? metrics.quality : {};
    const cost = metrics?.cost && typeof metrics.cost === "object" ? metrics.cost : {};
    const freshness = metrics?.freshness && typeof metrics.freshness === "object" ? metrics.freshness : {};
    const security = metrics?.security && typeof metrics.security === "object" ? metrics.security : {};

    const d = toFiniteNumber(latency.duration_ms, null);
    if (d != null) durationMs.push(d);
    const qw = toFiniteNumber(latency.queue_wait_ms, null);
    if (qw != null) queueWaitMs.push(qw);
    const qd = toFiniteNumber(ev?.ext?.queue_depth, null);
    if (qd != null) queueDepth.push(qd);

    const rc = toFiniteNumber(quality.result_count, null);
    if (rc != null) resultCount.push(rc);
    const pt = toFiniteNumber(cost.prompt_tokens, null);
    if (pt != null) promptTokens.push(pt);
    const ct = toFiniteNumber(cost.completion_tokens, null);
    if (ct != null) completionTokens.push(ct);
    const tt = toFiniteNumber(cost.total_tokens, null);
    if (tt != null) totalTokens.push(tt);
    const fr = toFiniteNumber(freshness.index_freshness_ms, null);
    if (fr != null) indexFreshnessMs.push(fr);

    if (eventKind.startsWith("ai.generate")) {
      aiGenerateCount += 1;
      if (security.blocked === true) runtimeBlockedCount += 1;
      if (security.downgraded === true) runtimeDowngradedCount += 1;
    }
  }

  return {
    latency: {
      duration_ms: normalizeDistribution(durationMs),
      queue_wait_ms: normalizeDistribution(queueWaitMs),
      queue_depth: normalizeDistribution(queueDepth),
    },
    quality: {
      result_count: normalizeDistribution(resultCount),
    },
    cost: {
      prompt_tokens: normalizeDistribution(promptTokens),
      completion_tokens: normalizeDistribution(completionTokens),
      total_tokens: normalizeDistribution(totalTokens),
      totals: {
        prompt_tokens: promptTokens.reduce((a, b) => a + b, 0),
        completion_tokens: completionTokens.reduce((a, b) => a + b, 0),
        total_tokens: totalTokens.reduce((a, b) => a + b, 0),
      },
    },
    freshness: {
      index_freshness_ms: normalizeDistribution(indexFreshnessMs),
    },
    security: {
      ai_generate_events: aiGenerateCount,
      blocked_count: runtimeBlockedCount,
      downgraded_count: runtimeDowngradedCount,
      blocked_rate: aiGenerateCount > 0 ? runtimeBlockedCount / aiGenerateCount : null,
      downgraded_rate: aiGenerateCount > 0 ? runtimeDowngradedCount / aiGenerateCount : null,
    },
  };
}

function collectBenchmarkMetrics(report = {}) {
  const metrics = report?.metrics && typeof report.metrics === "object" ? report.metrics : {};
  const golden = metrics?.golden && typeof metrics.golden === "object" ? metrics.golden : {};
  const adversarial = metrics?.adversarial && typeof metrics.adversarial === "object" ? metrics.adversarial : {};
  const goldenRows = Array.isArray(report?.details?.golden) ? report.details.golden : [];
  const goldenLatencies = goldenRows
    .map((r) => toFiniteNumber(r?.latency_ms, null))
    .filter((v) => v != null);
  const latencyBench = {
    samples: goldenLatencies.length,
    p50: toFiniteNumber(golden?.latency_ms?.p50, null),
    p95: toFiniteNumber(golden?.latency_ms?.p95, null),
    p99: percentile(goldenLatencies, 99),
    max: toFiniteNumber(golden?.latency_ms?.max, null),
    avg: toFiniteNumber(golden?.latency_ms?.avg, null),
  };
  return {
    golden: {
      queries: Number(golden?.queries || goldenRows.length || 0),
      precision_at_k_avg: clamp01(golden?.precision_at_k_avg),
      recall_at_k_avg: clamp01(golden?.recall_at_k_avg),
      mrr_at_k_avg: clamp01(golden?.mrr_at_k_avg),
      latency_ms: latencyBench,
    },
    adversarial: {
      queries: Number(adversarial?.queries || 0),
      expected_match_count: Number(adversarial?.expected_match_count || 0),
      expected_match_rate: clamp01(adversarial?.expected_match_rate),
      blocked_count: Number(adversarial?.blocked_count || 0),
      blocked_rate: clamp01(adversarial?.blocked_rate),
    },
  };
}

function collectPipelineStages(report = {}, events = []) {
  const stageMap = new Map();
  const addStage = (name) => {
    const stage = String(name || "unknown").trim().toLowerCase() || "unknown";
    if (!stageMap.has(stage)) {
      stageMap.set(stage, {
        stage,
        trace_samples: 0,
        in_total: 0,
        out_total: 0,
        blocked_count: 0,
        deny_count: 0,
        reasons: {},
      });
    }
    return stageMap.get(stage);
  };

  const goldenRows = Array.isArray(report?.details?.golden) ? report.details.golden : [];
  for (const row of goldenRows) {
    const trace = Array.isArray(row?.pipeline_stage_trace) ? row.pipeline_stage_trace : [];
    for (const entry of trace) {
      const st = addStage(entry?.stage || "unknown");
      st.trace_samples += 1;
      st.in_total += Math.max(0, Number(entry?.in_count || 0));
      st.out_total += Math.max(0, Number(entry?.out_count || 0));
      if (entry?.blocked) st.blocked_count += 1;
      const reason = String(entry?.reason || "").trim();
      if (reason) st.reasons[reason] = Number(st.reasons[reason] || 0) + 1;
    }
  }

  const adversarialRows = Array.isArray(report?.details?.adversarial) ? report.details.adversarial : [];
  for (const row of adversarialRows) {
    if (row?.ok === true) continue;
    const stage = inferStageFromReason(row?.reason || "");
    const st = addStage(stage);
    st.deny_count += 1;
    const reason = String(row?.reason || "unknown").trim() || "unknown";
    st.reasons[reason] = Number(st.reasons[reason] || 0) + 1;
  }

  const evs = Array.isArray(events) ? events : [];
  for (const ev of evs) {
    const metrics = ev?.metrics || {};
    const security = metrics?.security || {};
    if (security?.blocked !== true) continue;
    const reason = String(security?.deny_code || ev?.error_code || "").trim();
    const stage = inferStageFromReason(reason);
    const st = addStage(stage);
    st.deny_count += 1;
    if (reason) st.reasons[reason] = Number(st.reasons[reason] || 0) + 1;
  }

  const stages = Array.from(stageMap.values()).map((row) => {
    const inTotal = Number(row.in_total || 0);
    const outTotal = Number(row.out_total || 0);
    const dropRatio = inTotal > 0 ? Math.max(0, Math.min(1, (inTotal - outTotal) / inTotal)) : 0;
    const topReasons = Object.entries(row.reasons || {})
      .sort((a, b) => Number(b[1] || 0) - Number(a[1] || 0))
      .slice(0, 3)
      .map(([reason, count]) => ({ reason, count: Number(count || 0) }));
    const anomalyScore = (
      (Number(row.blocked_count || 0) * 5)
      + (Number(row.deny_count || 0) * 3)
      + Math.round(dropRatio * 100)
    );
    return {
      stage: row.stage,
      trace_samples: Number(row.trace_samples || 0),
      blocked_count: Number(row.blocked_count || 0),
      deny_count: Number(row.deny_count || 0),
      in_total: inTotal,
      out_total: outTotal,
      avg_drop_ratio: dropRatio,
      anomaly_score: anomalyScore,
      top_reasons: topReasons,
    };
  });

  stages.sort((a, b) => {
    if (Number(b.anomaly_score || 0) !== Number(a.anomaly_score || 0)) {
      return Number(b.anomaly_score || 0) - Number(a.anomaly_score || 0);
    }
    return String(a.stage).localeCompare(String(b.stage));
  });

  return {
    stages,
    top_anomalies: stages.slice(0, 5),
  };
}

function evaluateThreshold({
  id,
  panel,
  metric,
  value,
  threshold,
  comparison,
  samples,
  minSamples,
  criticalMarginRatio,
  stage,
  hint,
}) {
  const out = {
    id: String(id || ""),
    panel: String(panel || ""),
    metric: String(metric || ""),
    status: "no_data",
    severity: "none",
    value: value == null ? null : Number(value),
    threshold: threshold == null ? null : Number(threshold),
    comparison: String(comparison || "max"),
    samples: Number(samples || 0),
    stage_hint: String(stage || ""),
    hint: String(hint || ""),
    breached: false,
    suppressed_by_noise: false,
  };

  const val = toFiniteNumber(value, null);
  const thr = toFiniteNumber(threshold, null);
  if (val == null || thr == null) return out;

  const cmp = String(comparison || "max").toLowerCase();
  let breached = false;
  let margin = 0;
  if (cmp === "min") {
    breached = val < thr;
    margin = thr > 0 ? Math.max(0, (thr - val) / thr) : 0;
  } else {
    breached = val > thr;
    margin = thr > 0 ? Math.max(0, (val - thr) / thr) : (val > thr ? 1 : 0);
  }
  out.breached = breached;
  if (!breached) {
    out.status = "pass";
    out.severity = "none";
    return out;
  }

  const sampleCount = Math.max(0, Number(samples || 0));
  const minS = Math.max(1, Number(minSamples || 1));
  if (sampleCount < minS) {
    out.status = "warn";
    out.severity = "warn";
    out.suppressed_by_noise = true;
    out.hint = out.hint || `suppressed_by_noise:min_samples=${minS}`;
    return out;
  }

  const criticalRatio = Math.max(0, Number(criticalMarginRatio || 0.2));
  if (margin >= criticalRatio) {
    out.status = "critical";
    out.severity = "critical";
    return out;
  }
  out.status = "warn";
  out.severity = "warn";
  return out;
}

function buildAlerts({ thresholds, panels, pipelineStages }) {
  const nc = thresholds?.noise_control || {};
  const minSamples = Math.max(1, Number(nc.min_samples || 20));
  const criticalMarginRatio = Math.max(0, Number(nc.critical_margin_ratio || 0.2));

  const alerts = [];
  const add = (item) => alerts.push(item);
  const latencyBench = panels?.latency?.benchmark || {};
  const latencyRuntime = panels?.latency?.runtime || {};
  const qualityBench = panels?.quality?.benchmark || {};
  const securityPanel = panels?.security || {};
  const freshnessPanel = panels?.freshness?.runtime || {};

  add(evaluateThreshold({
    id: "latency.benchmark.p95",
    panel: "latency",
    metric: "benchmark_p95_ms",
    value: latencyBench?.p95,
    threshold: thresholds?.latency?.benchmark_p95_ms_max,
    comparison: "max",
    samples: latencyBench?.samples,
    minSamples,
    criticalMarginRatio,
    hint: "golden benchmark p95 should stay under threshold",
  }));
  add(evaluateThreshold({
    id: "latency.benchmark.p99",
    panel: "latency",
    metric: "benchmark_p99_ms",
    value: latencyBench?.p99,
    threshold: thresholds?.latency?.benchmark_p99_ms_max,
    comparison: "max",
    samples: latencyBench?.samples,
    minSamples,
    criticalMarginRatio,
    hint: "golden benchmark p99 should stay under threshold",
  }));
  add(evaluateThreshold({
    id: "latency.runtime.duration.p95",
    panel: "latency",
    metric: "runtime_duration_p95_ms",
    value: latencyRuntime?.duration_ms?.p95,
    threshold: thresholds?.latency?.runtime_duration_p95_ms_max,
    comparison: "max",
    samples: latencyRuntime?.duration_ms?.samples,
    minSamples,
    criticalMarginRatio,
    hint: "runtime ai.generate duration p95",
  }));
  add(evaluateThreshold({
    id: "queue.wait.p95",
    panel: "latency",
    metric: "runtime_queue_wait_p95_ms",
    value: latencyRuntime?.queue_wait_ms?.p95,
    threshold: thresholds?.latency?.runtime_queue_wait_p95_ms_max,
    comparison: "max",
    samples: latencyRuntime?.queue_wait_ms?.samples,
    minSamples,
    criticalMarginRatio,
    stage: "queue",
    hint: "runtime queue wait p95",
  }));
  add(evaluateThreshold({
    id: "queue.depth.p95",
    panel: "latency",
    metric: "runtime_queue_depth_p95",
    value: latencyRuntime?.queue_depth?.p95,
    threshold: thresholds?.latency?.runtime_queue_depth_p95_max,
    comparison: "max",
    samples: latencyRuntime?.queue_depth?.samples,
    minSamples,
    criticalMarginRatio,
    stage: "queue",
    hint: "runtime queue depth p95",
  }));
  add(evaluateThreshold({
    id: "quality.precision",
    panel: "quality",
    metric: "precision_at_k_avg",
    value: qualityBench?.precision_at_k_avg,
    threshold: thresholds?.quality?.precision_at_k_min,
    comparison: "min",
    samples: qualityBench?.queries,
    minSamples: 1,
    criticalMarginRatio,
    hint: "golden precision_at_k_avg",
  }));
  add(evaluateThreshold({
    id: "quality.recall",
    panel: "quality",
    metric: "recall_at_k_avg",
    value: qualityBench?.recall_at_k_avg,
    threshold: thresholds?.quality?.recall_at_k_min,
    comparison: "min",
    samples: qualityBench?.queries,
    minSamples: 1,
    criticalMarginRatio,
    hint: "golden recall_at_k_avg",
  }));
  add(evaluateThreshold({
    id: "freshness.index.p95",
    panel: "freshness",
    metric: "index_freshness_p95_ms",
    value: freshnessPanel?.index_freshness_ms?.p95,
    threshold: thresholds?.freshness?.index_freshness_p95_ms_max,
    comparison: "max",
    samples: freshnessPanel?.index_freshness_ms?.samples,
    minSamples,
    criticalMarginRatio,
    hint: "runtime index freshness p95",
  }));
  add(evaluateThreshold({
    id: "freshness.index.max",
    panel: "freshness",
    metric: "index_freshness_max_ms",
    value: freshnessPanel?.index_freshness_ms?.max,
    threshold: thresholds?.freshness?.index_freshness_max_ms_max,
    comparison: "max",
    samples: freshnessPanel?.index_freshness_ms?.samples,
    minSamples,
    criticalMarginRatio,
    hint: "runtime index freshness max",
  }));
  add(evaluateThreshold({
    id: "security.adversarial.block_rate",
    panel: "security",
    metric: "adversarial_block_rate",
    value: securityPanel?.benchmark?.adversarial_block_rate,
    threshold: thresholds?.security?.adversarial_block_rate_min,
    comparison: "min",
    samples: securityPanel?.benchmark?.adversarial_queries,
    minSamples: 1,
    criticalMarginRatio,
    stage: "gate",
    hint: "adversarial blocked rate should stay high",
  }));
  add(evaluateThreshold({
    id: "security.runtime.block_rate",
    panel: "security",
    metric: "runtime_block_rate",
    value: securityPanel?.runtime?.blocked_rate,
    threshold: thresholds?.security?.runtime_block_rate_max,
    comparison: "max",
    samples: securityPanel?.runtime?.ai_generate_events,
    minSamples,
    criticalMarginRatio,
    stage: "gate",
    hint: "runtime blocked rate should remain stable",
  }));
  add(evaluateThreshold({
    id: "security.runtime.downgrade_rate",
    panel: "security",
    metric: "runtime_downgrade_rate",
    value: securityPanel?.runtime?.downgraded_rate,
    threshold: thresholds?.security?.runtime_downgrade_rate_max,
    comparison: "max",
    samples: securityPanel?.runtime?.ai_generate_events,
    minSamples,
    criticalMarginRatio,
    stage: "gate",
    hint: "runtime downgrade rate should remain stable",
  }));

  const topStage = Array.isArray(pipelineStages?.top_anomalies) ? pipelineStages.top_anomalies[0] : null;
  if (topStage) {
    const stageCfg = thresholds?.stage || {};
    const warnScore = Number(stageCfg?.anomaly_score_warn || 12);
    const criticalScore = Number(stageCfg?.anomaly_score_critical || 20);
    const status = topStage.anomaly_score >= criticalScore
      ? "critical"
      : topStage.anomaly_score >= warnScore
        ? "warn"
        : "pass";
    alerts.push({
      id: "pipeline.stage.top_anomaly",
      panel: "pipeline",
      metric: "top_stage_anomaly_score",
      status,
      severity: status === "critical" ? "critical" : status === "warn" ? "warn" : "none",
      value: Number(topStage.anomaly_score || 0),
      threshold: Number(warnScore),
      comparison: "max",
      samples: Number(topStage.trace_samples || 0),
      stage_hint: String(topStage.stage || ""),
      hint: topStage?.top_reasons?.[0]?.reason || "",
      breached: status !== "pass",
      suppressed_by_noise: false,
    });
  }

  const summary = {
    pass: alerts.filter((a) => a.status === "pass").length,
    warn: alerts.filter((a) => a.status === "warn").length,
    critical: alerts.filter((a) => a.status === "critical").length,
    no_data: alerts.filter((a) => a.status === "no_data").length,
    total: alerts.length,
  };
  return { summary, items: alerts };
}

function buildDashboard({
  report = {},
  rawEvents = [],
  thresholds = {},
  nowMs = Date.now(),
  reportPath = "",
  dbPath = "",
  windowMs = 0,
} = {}) {
  const mergedThresholds = mergeThresholds(DEFAULT_THRESHOLDS, thresholds || {});
  const events = normalizeAuditEvents(rawEvents);
  const benchmark = collectBenchmarkMetrics(report || {});
  const runtime = collectRuntimeMetrics(events);
  const pipelineStages = collectPipelineStages(report || {}, events);

  const panels = {
    latency: {
      benchmark: benchmark?.golden?.latency_ms || {},
      runtime: runtime?.latency || {},
    },
    quality: {
      benchmark: {
        queries: Number(benchmark?.golden?.queries || 0),
        precision_at_k_avg: benchmark?.golden?.precision_at_k_avg ?? null,
        recall_at_k_avg: benchmark?.golden?.recall_at_k_avg ?? null,
        mrr_at_k_avg: benchmark?.golden?.mrr_at_k_avg ?? null,
      },
      runtime: runtime?.quality || {},
    },
    cost: {
      runtime: runtime?.cost || {},
    },
    freshness: {
      runtime: runtime?.freshness || {},
    },
    security: {
      benchmark: {
        adversarial_queries: Number(benchmark?.adversarial?.queries || 0),
        adversarial_block_rate: benchmark?.adversarial?.blocked_rate ?? null,
        adversarial_blocked_count: Number(benchmark?.adversarial?.blocked_count || 0),
      },
      runtime: runtime?.security || {},
    },
  };

  const alerts = buildAlerts({
    thresholds: mergedThresholds,
    panels,
    pipelineStages,
  });

  return {
    schema_version: "xhub.memory.observability.dashboard.v1",
    generated_at_ms: Number(nowMs || Date.now()),
    sources: {
      report_path: String(reportPath || ""),
      db_path: String(dbPath || ""),
      window_ms: Number(windowMs || mergedThresholds.window_ms || 0),
      runtime_event_count: events.length,
    },
    thresholds: mergedThresholds,
    panels,
    pipeline_stages: pipelineStages,
    alerts,
  };
}

function fmtNum(v, digits = 3) {
  const n = toFiniteNumber(v, null);
  if (n == null) return "n/a";
  return Number(n.toFixed(digits)).toString();
}

function fmtPct(v) {
  const n = clamp01(v);
  if (n == null) return "n/a";
  return `${(n * 100).toFixed(2)}%`;
}

function renderDashboardMarkdown(dashboard = {}) {
  const p = dashboard?.panels || {};
  const alerts = dashboard?.alerts || {};
  const topStage = Array.isArray(dashboard?.pipeline_stages?.top_anomalies)
    ? dashboard.pipeline_stages.top_anomalies[0]
    : null;

  const lines = [];
  lines.push("# M2-W5-04 Observability Dashboard Snapshot");
  lines.push("");
  lines.push(`- generated_at_ms: ${Number(dashboard?.generated_at_ms || 0)}`);
  lines.push(`- schema_version: ${String(dashboard?.schema_version || "")}`);
  lines.push(`- runtime_event_count: ${Number(dashboard?.sources?.runtime_event_count || 0)}`);
  lines.push("");

  lines.push("## Latency Panel");
  lines.push(`- benchmark p95/p99(ms): ${fmtNum(p?.latency?.benchmark?.p95)} / ${fmtNum(p?.latency?.benchmark?.p99)}`);
  lines.push(`- runtime duration p95/p99(ms): ${fmtNum(p?.latency?.runtime?.duration_ms?.p95)} / ${fmtNum(p?.latency?.runtime?.duration_ms?.p99)}`);
  lines.push(`- runtime queue_wait p95(ms): ${fmtNum(p?.latency?.runtime?.queue_wait_ms?.p95)}`);
  lines.push(`- runtime queue_depth p95: ${fmtNum(p?.latency?.runtime?.queue_depth?.p95)}`);
  lines.push("");

  lines.push("## Quality Panel");
  lines.push(`- precision_at_k_avg: ${fmtPct(p?.quality?.benchmark?.precision_at_k_avg)}`);
  lines.push(`- recall_at_k_avg: ${fmtPct(p?.quality?.benchmark?.recall_at_k_avg)}`);
  lines.push(`- mrr_at_k_avg: ${fmtPct(p?.quality?.benchmark?.mrr_at_k_avg)}`);
  lines.push(`- adversarial blocked_rate: ${fmtPct(p?.security?.benchmark?.adversarial_block_rate)}`);
  lines.push("");

  lines.push("## Cost Panel");
  lines.push(`- total_tokens p95: ${fmtNum(p?.cost?.runtime?.total_tokens?.p95, 0)}`);
  lines.push(`- total_tokens sum: ${fmtNum(p?.cost?.runtime?.totals?.total_tokens, 0)}`);
  lines.push("");

  lines.push("## Freshness Panel");
  lines.push(`- index_freshness p95/max(ms): ${fmtNum(p?.freshness?.runtime?.index_freshness_ms?.p95)} / ${fmtNum(p?.freshness?.runtime?.index_freshness_ms?.max)}`);
  lines.push("");

  lines.push("## Alerts");
  lines.push(`- critical: ${Number(alerts?.summary?.critical || 0)}`);
  lines.push(`- warn: ${Number(alerts?.summary?.warn || 0)}`);
  lines.push(`- no_data: ${Number(alerts?.summary?.no_data || 0)}`);
  const topAlerts = Array.isArray(alerts?.items)
    ? alerts.items.filter((a) => a.status === "critical" || a.status === "warn").slice(0, 5)
    : [];
  if (!topAlerts.length) {
    lines.push("- top_alerts: none");
  } else {
    for (const item of topAlerts) {
      lines.push(`- [${item.status}] ${item.id} value=${fmtNum(item.value)} threshold=${fmtNum(item.threshold)} stage=${item.stage_hint || "n/a"} hint=${item.hint || ""}`);
    }
  }
  lines.push("");

  lines.push("## Pipeline Stage Diagnostics");
  if (!topStage) {
    lines.push("- stage_anomalies: n/a");
  } else {
    lines.push(`- top_stage: ${topStage.stage}`);
    lines.push(`- anomaly_score: ${Number(topStage.anomaly_score || 0)}`);
    lines.push(`- blocked_count: ${Number(topStage.blocked_count || 0)}`);
    lines.push(`- deny_count: ${Number(topStage.deny_count || 0)}`);
    if (Array.isArray(topStage.top_reasons) && topStage.top_reasons[0]) {
      lines.push(`- top_reason: ${topStage.top_reasons[0].reason}`);
    }
  }
  return `${lines.join("\n")}\n`;
}

function fail(msg, details = {}) {
  console.error(JSON.stringify({ ok: false, error: String(msg || "failed"), ...details }, null, 2));
  process.exit(2);
}

function main() {
  const args = parseArgs(process.argv);
  const repoRoot = path.resolve(__dirname, "..");
  const reportPath = path.resolve(
    args.report || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w1/report_baseline_week1.json")
  );
  const thresholdPath = path.resolve(
    args.thresholds || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w5-observability/observability_thresholds.json")
  );
  const dbPath = path.resolve(args.db || path.join(repoRoot, "data/hub.sqlite3"));
  const outJsonPath = path.resolve(
    args["out-json"] || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w5-observability/dashboard_snapshot.json")
  );
  const outMdPath = path.resolve(
    args["out-md"] || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w5-observability/dashboard_snapshot.md")
  );
  const eventsJsonPath = args["events-json"] ? path.resolve(String(args["events-json"])) : "";

  if (!fs.existsSync(reportPath)) fail("report_not_found", { report: reportPath });
  const report = readJson(reportPath);
  const thresholds = fs.existsSync(thresholdPath) ? readJson(thresholdPath) : {};
  const mergedThresholds = mergeThresholds(DEFAULT_THRESHOLDS, thresholds);

  const nowMs = Math.max(0, Number(args["now-ms"] || Date.now()));
  const windowMs = Math.max(1000, Number(args["window-ms"] || mergedThresholds.window_ms || DEFAULT_THRESHOLDS.window_ms));
  const sinceMs = nowMs - windowMs;
  const untilMs = nowMs;
  const maxEvents = Math.max(1, Number(args["max-events"] || mergedThresholds.max_events || DEFAULT_THRESHOLDS.max_events));

  let rawEvents = [];
  if (eventsJsonPath) {
    if (!fs.existsSync(eventsJsonPath)) fail("events_json_not_found", { events_json: eventsJsonPath });
    rawEvents = readJson(eventsJsonPath);
  } else {
    rawEvents = loadAuditEventsFromDb(dbPath, { sinceMs, untilMs, maxEvents });
  }

  const dashboard = buildDashboard({
    report,
    rawEvents,
    thresholds: mergedThresholds,
    nowMs,
    reportPath: path.relative(repoRoot, reportPath),
    dbPath: eventsJsonPath ? "" : path.relative(repoRoot, dbPath),
    windowMs,
  });
  const markdown = renderDashboardMarkdown(dashboard);

  ensureDirFor(outJsonPath);
  fs.writeFileSync(outJsonPath, JSON.stringify(dashboard, null, 2));
  ensureDirFor(outMdPath);
  fs.writeFileSync(outMdPath, markdown);

  const out = {
    ok: true,
    report: path.relative(repoRoot, reportPath),
    thresholds: fs.existsSync(thresholdPath) ? path.relative(repoRoot, thresholdPath) : "",
    out_json: path.relative(repoRoot, outJsonPath),
    out_md: path.relative(repoRoot, outMdPath),
    alerts: dashboard?.alerts?.summary || {},
    runtime_event_count: Number(dashboard?.sources?.runtime_event_count || 0),
  };
  console.log(JSON.stringify(out, null, 2));
}

if (require.main === module) {
  try {
    main();
  } catch (err) {
    fail(err?.message || err || "m2_observability_dashboard_failed");
  }
}

module.exports = {
  DEFAULT_THRESHOLDS,
  buildDashboard,
  collectPipelineStages,
  collectRuntimeMetrics,
  evaluateThreshold,
  mergeThresholds,
  normalizeAuditEvents,
  renderDashboardMarkdown,
};
