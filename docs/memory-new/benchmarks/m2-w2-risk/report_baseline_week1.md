# M2 W1 Baseline Benchmark Report

- generatedAt: 2026-02-26T06:40:38.253Z
- dataset: `docs/memory-new/benchmarks/m2-w2-risk/bench_baseline.json`
- golden: `docs/memory-new/benchmarks/m2-w2-risk/golden_queries.json`
- adversarial: `docs/memory-new/benchmarks/m2-w2-risk/adversarial_queries.json`

## Corpus
- documents: 11
- source_mode: synthetic_seeded

## Golden Metrics
- precision@k(avg): 0.2
- recall@k(avg): 1
- mrr@k(avg): 1
- latency p50/p95(ms): 0.051 / 0.098

## Engine Compare (Same Suite)
- baseline_engine: legacy_token_overlap
- candidate_engine: memory_retrieval_pipeline_v2_risk
- precision delta: 0
- recall delta: 0
- mrr delta: 0
- p95 latency ratio: 0.4317
- top1 changed rate: 0

## Security Regression
- expected match rate: 0.5417
- blocked rate: 0.4792

## Gate Hints
- gate1_correctness: pass
- gate2_performance: pass
- gate3_security: fail
- retrieval_engine: memory_retrieval_pipeline_v2_risk

> Note: this is W1 baseline (measurement first). Thresholds tighten in W2+.
