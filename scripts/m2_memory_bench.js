#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");

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

function tokenize(v) {
  const text = String(v || "").toLowerCase();
  const m = text.match(/[a-z0-9\u4e00-\u9fff]+/g);
  return m ? m : [];
}

function median(sorted) {
  if (!sorted.length) return 0;
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

function percentile(sorted, p) {
  if (!sorted.length) return 0;
  const idx = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[idx];
}

function round4(v) {
  return Number(Number(v || 0).toFixed(4));
}

function scoreDoc(qTokens, doc) {
  const dTokens = new Set(tokenize(`${doc.title || ""} ${doc.text || ""} ${(doc.tags || []).join(" ")}`));
  if (!qTokens.length || !dTokens.size) return 0;
  let overlap = 0;
  for (const t of qTokens) {
    if (dTokens.has(t)) overlap += 1;
  }
  return overlap / qTokens.length;
}

function filterByScope(doc, scope) {
  if (!scope || typeof scope !== "object") return true;
  const ds = doc.scope || {};
  for (const k of Object.keys(scope)) {
    const expected = String(scope[k] || "").trim();
    if (!expected) continue;
    if (String(ds[k] || "") !== expected) return false;
  }
  return true;
}

function searchDocsLegacy(docs, queryObj) {
  const qTokens = tokenize(queryObj.query || "");
  const list = [];
  for (const doc of docs) {
    if (!filterByScope(doc, queryObj.scope)) continue;
    const score = scoreDoc(qTokens, doc);
    if (score <= 0) continue;
    list.push({ id: doc.id, score, created_at_ms: Number(doc.created_at_ms || 0) });
  }
  list.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    return (Number(b.created_at_ms || 0) - Number(a.created_at_ms || 0));
  });
  return {
    blocked: false,
    deny_reason: "",
    pipeline_stage_trace: [],
    results: list.slice(0, Number(queryObj.top_k || 5)),
    engine: "legacy_token_overlap",
  };
}

function searchDocsViaPipeline(runPipeline, docs, queryObj, pipelineOptions = {}) {
  const allowedSensitivity = Array.isArray(pipelineOptions?.allowed_sensitivity) && pipelineOptions.allowed_sensitivity.length
    ? pipelineOptions.allowed_sensitivity
    : ["public", "internal", "secret"];
  const allowUntrusted = pipelineOptions?.allow_untrusted == null ? true : !!pipelineOptions.allow_untrusted;
  const traceEnabled = pipelineOptions?.trace_enabled == null ? false : !!pipelineOptions.trace_enabled;
  const out = runPipeline({
    documents: docs,
    query: String(queryObj.query || ""),
    scope: queryObj.scope && typeof queryObj.scope === "object" ? queryObj.scope : {},
    top_k: Number(queryObj.top_k || 5),
    allowed_sensitivity: allowedSensitivity,
    allow_untrusted: allowUntrusted,
    trace_enabled: traceEnabled,
    remote_mode: false,
    ...pipelineOptions,
  });
  const results = Array.isArray(out?.results)
    ? out.results.map((r) => ({
      id: String(r?.id || ""),
      score: Number(r?.final_score || 0),
      relevance_score: Number(r?.relevance_score || 0),
      risk_penalty: Number(r?.risk_penalty || 0),
      risk_level: String(r?.risk_level || ""),
      risk_factors: Array.isArray(r?.risk_factors) ? r.risk_factors : [],
      created_at_ms: Number(r?.created_at_ms || 0),
    }))
    : [];
  return {
    blocked: !!out?.blocked,
    deny_reason: String(out?.deny_reason || ""),
    pipeline_stage_trace: Array.isArray(out?.pipeline_stage_trace) ? out.pipeline_stage_trace : [],
    results,
    engine: String(pipelineOptions?.engine_name || "memory_retrieval_pipeline_v2"),
  };
}

function searchDocs(docs, queryObj, runPipeline, pipelineOptions = {}) {
  if (typeof runPipeline === "function") {
    try {
      return searchDocsViaPipeline(runPipeline, docs, queryObj, pipelineOptions);
    } catch {
      return searchDocsLegacy(docs, queryObj);
    }
  }
  return searchDocsLegacy(docs, queryObj);
}

function evaluateGolden(docs, golden, runPipeline, pipelineOptions = {}) {
  const qs = Array.isArray(golden.queries) ? golden.queries : [];
  const out = [];
  const lat = [];
  let pSum = 0;
  let rSum = 0;
  let mrrSum = 0;
  for (const q of qs) {
    const start = process.hrtime.bigint();
    const search = searchDocs(docs, q, runPipeline, pipelineOptions);
    const results = Array.isArray(search?.results) ? search.results : [];
    const elapsedMs = Number(process.hrtime.bigint() - start) / 1e6;
    lat.push(elapsedMs);
    const rel = new Set((q.relevant_ids || []).map((x) => String(x)));
    let hit = 0;
    let firstRank = 0;
    for (let i = 0; i < results.length; i += 1) {
      if (rel.has(String(results[i].id))) {
        hit += 1;
        if (!firstRank) firstRank = i + 1;
      }
    }
    const k = Math.max(1, Number(q.top_k || golden.k_default || 5));
    const precision = hit / k;
    const recall = rel.size ? hit / rel.size : 1;
    const mrr = firstRank ? (1 / firstRank) : 0;
    pSum += precision;
    rSum += recall;
    mrrSum += mrr;
    out.push({
      id: q.id,
      query: q.query,
      top_k: k,
      relevant: Array.from(rel),
      blocked: !!search.blocked,
      deny_reason: String(search.deny_reason || ""),
      pipeline_stage_trace: Array.isArray(search.pipeline_stage_trace) ? search.pipeline_stage_trace : [],
      search_engine: String(search.engine || "legacy_token_overlap"),
      results,
      precision_at_k: Number(precision.toFixed(4)),
      recall_at_k: Number(recall.toFixed(4)),
      mrr_at_k: Number(mrr.toFixed(4)),
      latency_ms: Number(elapsedMs.toFixed(3)),
    });
  }
  const latSorted = [...lat].sort((a, b) => a - b);
  const n = Math.max(1, qs.length);
  return {
    per_query: out,
    summary: {
      queries: qs.length,
      precision_at_k_avg: Number((pSum / n).toFixed(4)),
      recall_at_k_avg: Number((rSum / n).toFixed(4)),
      mrr_at_k_avg: Number((mrrSum / n).toFixed(4)),
      latency_ms: {
        p50: Number(percentile(latSorted, 50).toFixed(3)),
        p95: Number(percentile(latSorted, 95).toFixed(3)),
        max: Number((latSorted[latSorted.length - 1] || 0).toFixed(3)),
        avg: Number((lat.reduce((a, b) => a + b, 0) / (lat.length || 1)).toFixed(3)),
        median: Number(median(latSorted).toFixed(3)),
      },
    },
  };
}

function compareEngineSummaries({ baseline, candidate }) {
  const b = baseline || {};
  const c = candidate || {};
  const bp95 = Number(b?.latency_ms?.p95 || 0);
  const cp95 = Number(c?.latency_ms?.p95 || 0);
  return {
    precision_delta: round4(Number(c.precision_at_k_avg || 0) - Number(b.precision_at_k_avg || 0)),
    recall_delta: round4(Number(c.recall_at_k_avg || 0) - Number(b.recall_at_k_avg || 0)),
    mrr_delta: round4(Number(c.mrr_at_k_avg || 0) - Number(b.mrr_at_k_avg || 0)),
    p95_latency_delta_ms: round4(cp95 - bp95),
    p95_latency_ratio: bp95 > 0 ? round4(cp95 / bp95) : 0,
  };
}

function compareTop1Shift({ baselinePerQuery, candidatePerQuery }) {
  const bRows = Array.isArray(baselinePerQuery) ? baselinePerQuery : [];
  const cRows = Array.isArray(candidatePerQuery) ? candidatePerQuery : [];
  const cMap = new Map(cRows.map((x) => [String(x?.id || ""), x]));
  let total = 0;
  let changed = 0;
  for (const b of bRows) {
    const id = String(b?.id || "");
    if (!id) continue;
    const c = cMap.get(id);
    if (!c) continue;
    total += 1;
    const bTop1 = String((b?.results && b.results[0] && b.results[0].id) || "");
    const cTop1 = String((c?.results && c.results[0] && c.results[0].id) || "");
    if (bTop1 !== cTop1) changed += 1;
  }
  return {
    query_count: total,
    top1_changed_count: changed,
    top1_changed_rate: total > 0 ? round4(changed / total) : 0,
  };
}

function decidePolicy(query) {
  const q = String(query || "").toLowerCase();
  const blockPatterns = [
    /ignore\s+(all\s+)?(previous|prior|above)\s+instructions?/,
    /reveal.*(secret|token|password|private\s*key|api\s*key)/,
    /\b(sk-|ghp_|xox[abprs]-|bearer\s+[a-z0-9\-_\.]+)/,
    /\b(jwt|otp|iban|credit\s*card|payment\s*pin)\b/,
    /\b(replay|resend|duplicate|stale|expired|nonce)\b/,
    /rm\s+-rf/,
    /disable\s+dlp|bypass\s+gate|override\s+secret_mode/,
  ];
  for (const p of blockPatterns) {
    if (p.test(q)) return { action: "block", reason: p.source };
  }
  return { action: "allow", reason: "no_block_pattern" };
}

function evaluateAdversarial(adversarial) {
  const qs = Array.isArray(adversarial.queries) ? adversarial.queries : [];
  const per = [];
  let matched = 0;
  let blocked = 0;
  for (const q of qs) {
    const decision = decidePolicy(q.query);
    const expected = String(q.expected_action || "allow");
    const ok = decision.action === expected;
    if (ok) matched += 1;
    if (decision.action === "block") blocked += 1;
    per.push({
      id: q.id,
      category: q.category,
      expected_action: expected,
      actual_action: decision.action,
      ok,
      reason: decision.reason,
      query: q.query,
    });
  }
  const total = Math.max(1, qs.length);
  return {
    per_query: per,
    summary: {
      queries: qs.length,
      expected_match_count: matched,
      expected_match_rate: Number((matched / total).toFixed(4)),
      blocked_count: blocked,
      blocked_rate: Number((blocked / total).toFixed(4)),
    },
  };
}

function toMarkdownSummary(report, relPaths) {
  const g = report.metrics.golden;
  const a = report.metrics.adversarial;
  const cmp = report.comparison || null;
  const cmpLines = [];
  if (cmp && cmp.enabled) {
    cmpLines.push("## Engine Compare (Same Suite)");
    cmpLines.push(`- baseline_engine: ${cmp.baseline_engine}`);
    cmpLines.push(`- candidate_engine: ${cmp.candidate_engine}`);
    cmpLines.push(`- precision delta: ${cmp.delta.precision_delta}`);
    cmpLines.push(`- recall delta: ${cmp.delta.recall_delta}`);
    cmpLines.push(`- mrr delta: ${cmp.delta.mrr_delta}`);
    cmpLines.push(`- p95 latency ratio: ${cmp.delta.p95_latency_ratio}`);
    cmpLines.push(`- top1 changed rate: ${cmp.top1_shift.top1_changed_rate}`);
    cmpLines.push("");
  }
  return [
    "# M2 W1 Baseline Benchmark Report",
    "",
    `- generatedAt: ${new Date(report.generated_at_ms).toISOString()}`,
    `- dataset: \`${relPaths.dataset}\``,
    `- golden: \`${relPaths.golden}\``,
    `- adversarial: \`${relPaths.adversarial}\``,
    "",
    "## Corpus",
    `- documents: ${report.corpus.documents}`,
    `- source_mode: ${report.corpus.source_mode}`,
    "",
    "## Golden Metrics",
    `- precision@k(avg): ${g.precision_at_k_avg}`,
    `- recall@k(avg): ${g.recall_at_k_avg}`,
    `- mrr@k(avg): ${g.mrr_at_k_avg}`,
    `- latency p50/p95(ms): ${g.latency_ms.p50} / ${g.latency_ms.p95}`,
    "",
    ...cmpLines,
    "## Security Regression",
    `- expected match rate: ${a.expected_match_rate}`,
    `- blocked rate: ${a.blocked_rate}`,
    "",
    "## Gate Hints",
    `- gate1_correctness: ${report.gate_hints.gate1_correctness ? "pass" : "fail"}`,
    `- gate2_performance: ${report.gate_hints.gate2_performance ? "pass" : "fail"}`,
    `- gate3_security: ${report.gate_hints.gate3_security ? "pass" : "fail"}`,
    `- retrieval_engine: ${report.corpus.retrieval_engine}`,
    "",
    "> Note: this is W1 baseline (measurement first). Thresholds tighten in W2+.",
    "",
  ].join("\n");
}

async function loadPipeline(repoRoot) {
  const modulePath = path.join(repoRoot, "x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js");
  const mod = await import(pathToFileURL(modulePath).href);
  if (!mod || typeof mod.runMemoryRetrievalPipeline !== "function") {
    throw new Error("memory_retrieval_pipeline_missing_export");
  }
  return mod.runMemoryRetrievalPipeline;
}

async function main() {
  const args = parseArgs(process.argv);
  const repoRoot = path.resolve(__dirname, "..");
  const datasetPath = path.resolve(args.dataset || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w1/bench_baseline.json"));
  const goldenPath = path.resolve(args.golden || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w1/golden_queries.json"));
  const adversarialPath = path.resolve(args.adversarial || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w1/adversarial_queries.json"));
  const outPath = path.resolve(args.out || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w1/report_baseline_week1.json"));
  const outMdPath = path.resolve(args["out-md"] || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w1/report_baseline_week1.md"));

  const dataset = readJson(datasetPath);
  const golden = readJson(goldenPath);
  const adversarial = readJson(adversarialPath);
  const docs = Array.isArray(dataset.documents) ? dataset.documents : [];
  let runPipeline = null;
  let retrievalEngine = "legacy_token_overlap";
  const usePipeline = String(args["use-pipeline"] || process.env.M2_BENCH_USE_PIPELINE || "").trim() === "1";
  const compareEnabled = String(args.compare || process.env.M2_BENCH_COMPARE || (usePipeline ? "1" : "")).trim() === "1";
  if (usePipeline) {
    try {
      runPipeline = await loadPipeline(repoRoot);
      retrievalEngine = "memory_retrieval_pipeline_v1";
    } catch {
      runPipeline = null;
      retrievalEngine = "legacy_token_overlap";
    }
  }

  const goldenEvalLegacy = evaluateGolden(docs, golden, null, {});
  let goldenEvalNoRisk = null;
  let goldenEvalRisk = null;
  if (typeof runPipeline === "function") {
    goldenEvalNoRisk = evaluateGolden(docs, golden, runPipeline, {
      risk_penalty_enabled: false,
      engine_name: "memory_retrieval_pipeline_v2_no_risk",
      allowed_sensitivity: ["public", "internal", "secret"],
      allow_untrusted: true,
    });
    goldenEvalRisk = evaluateGolden(docs, golden, runPipeline, {
      risk_penalty_enabled: true,
      engine_name: "memory_retrieval_pipeline_v2_risk",
      allowed_sensitivity: ["public", "internal", "secret"],
      allow_untrusted: true,
    });
  }

  const goldenEval = usePipeline && goldenEvalRisk ? goldenEvalRisk : goldenEvalLegacy;
  if (usePipeline && goldenEvalRisk) retrievalEngine = "memory_retrieval_pipeline_v2_risk";
  const advEval = evaluateAdversarial(adversarial);

  const comparison = {
    enabled: false,
  };
  if (compareEnabled && goldenEvalRisk && goldenEvalLegacy) {
    comparison.enabled = true;
    comparison.baseline_engine = "legacy_token_overlap";
    comparison.candidate_engine = "memory_retrieval_pipeline_v2_risk";
    comparison.delta = compareEngineSummaries({
      baseline: goldenEvalLegacy.summary,
      candidate: goldenEvalRisk.summary,
    });
    comparison.top1_shift = compareTop1Shift({
      baselinePerQuery: goldenEvalLegacy.per_query,
      candidatePerQuery: goldenEvalRisk.per_query,
    });
    if (goldenEvalNoRisk) {
      comparison.no_risk_engine = "memory_retrieval_pipeline_v2_no_risk";
      comparison.delta_vs_no_risk = compareEngineSummaries({
        baseline: goldenEvalNoRisk.summary,
        candidate: goldenEvalRisk.summary,
      });
      comparison.top1_shift_vs_no_risk = compareTop1Shift({
        baselinePerQuery: goldenEvalNoRisk.per_query,
        candidatePerQuery: goldenEvalRisk.per_query,
      });
    }
  }

  const report = {
    schema_version: "xhub.memory.bench_report.v1",
    generated_at_ms: Date.now(),
    corpus: {
      documents: docs.length,
      source_mode: dataset.source_mode || "unknown",
      retrieval_engine: retrievalEngine,
    },
    metrics: {
      golden: goldenEval.summary,
      adversarial: advEval.summary,
    },
    comparison,
    gate_hints: {
      gate1_correctness: goldenEval.summary.recall_at_k_avg >= 0.6,
      gate2_performance: goldenEval.summary.latency_ms.p95 <= 30,
      gate3_security: advEval.summary.expected_match_rate >= 0.95,
    },
    details: {
      golden: goldenEval.per_query,
      adversarial: advEval.per_query,
    },
  };
  if (comparison.enabled && goldenEvalLegacy) {
    report.details.compare_legacy = goldenEvalLegacy.per_query;
  }
  if (comparison.enabled && goldenEvalNoRisk) {
    report.details.compare_no_risk = goldenEvalNoRisk.per_query;
  }

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  fs.writeFileSync(
    outMdPath,
    toMarkdownSummary(report, {
      dataset: path.relative(repoRoot, datasetPath),
      golden: path.relative(repoRoot, goldenPath),
      adversarial: path.relative(repoRoot, adversarialPath),
    }),
    "utf8"
  );

  console.log(
    JSON.stringify(
      {
        ok: true,
        out: path.relative(repoRoot, outPath),
        out_md: path.relative(repoRoot, outMdPath),
        documents: docs.length,
        golden_queries: (golden.queries || []).length,
        adversarial_queries: (adversarial.queries || []).length,
        retrieval_engine: retrievalEngine,
        comparison_enabled: comparison.enabled,
        comparison_delta: comparison.enabled ? comparison.delta : null,
        metrics: report.metrics,
        gate_hints: report.gate_hints,
      },
      null,
      2
    )
  );
}

main().catch((err) => {
  console.error(
    JSON.stringify(
      {
        ok: false,
        error: String(err?.message || err || "m2_memory_bench_failed"),
      },
      null,
      2
    )
  );
  process.exit(2);
});
