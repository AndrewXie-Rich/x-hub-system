# M2 W1 Baseline Benchmark Report

- generatedAt: 2026-02-26T06:36:36.910Z
- dataset: `docs/memory-new/benchmarks/m2-w1/bench_baseline.json`
- golden: `docs/memory-new/benchmarks/m2-w1/golden_queries.json`
- adversarial: `docs/memory-new/benchmarks/m2-w1/adversarial_queries.json`

## Corpus
- documents: 11
- source_mode: synthetic_seeded

## Golden Metrics
- precision@k(avg): 0.2
- recall@k(avg): 1
- mrr@k(avg): 1
- latency p50/p95(ms): 0.037 / 0.234

## Security Regression
- expected match rate: 0.5417
- blocked rate: 0.4792

## Gate Hints
- gate1_correctness: pass
- gate2_performance: pass
- gate3_security: fail
- retrieval_engine: legacy_token_overlap

> Note: this is W1 baseline (measurement first). Thresholds tighten in W2+.
