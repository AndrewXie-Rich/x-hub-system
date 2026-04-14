# M2 W1 Baseline Benchmark Report

- generatedAt: 2026-03-14T13:23:50.697Z
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
- latency p50/p95(ms): 0.041 / 0.245

## Security Regression
- expected match rate: 0.5417
- blocked rate: 0.4792

## Gate Hints
- gate1_correctness: pass
- gate2_performance: pass
- gate3_security: fail
- retrieval_engine: legacy_token_overlap

> Note: this is W1 baseline (measurement first). Thresholds tighten in W2+.
