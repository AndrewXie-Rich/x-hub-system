# M2 W2 Risk-Aware Ranking Benchmark

- generatedAt: 2026-02-26
- purpose: M2-W2-02 (`final_score = relevance - risk_penalty`) same-suite comparison

## Re-run

```bash
cd x-hub-system
M2_BENCH_USE_PIPELINE=1 \
M2_BENCH_COMPARE=1 \
OUT_DIR=./docs/memory-new/benchmarks/m2-w2-risk \
./scripts/m2_memory_bench.sh
```

## Snapshot

- retrieval_engine: `memory_retrieval_pipeline_v2_risk`
- precision delta vs legacy: `0`
- recall delta vs legacy: `0` (target `>= -0.05` met)
- p95 latency ratio vs legacy: `0.4317` (target `< 1.8` met)
- top1 changed rate vs legacy: `0`

## Tuning Note

- compare mode now uses full sensitivity candidate set (`public/internal/secret`) to isolate ranking effect from scope/sensitivity hard-filter effect.
