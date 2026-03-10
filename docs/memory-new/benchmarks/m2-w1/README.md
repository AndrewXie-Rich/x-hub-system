# M2 W1 Benchmark Artifacts

- generatedAt: 2026-02-26
- purpose: M2-W1 baseline measurement (`Now-2` / `Now-3`)

## Files

- `bench_baseline.json`: benchmark corpus (anonymized; synthetic fallback if DB empty)
- `golden_queries.json`: golden query set with relevant IDs
- `adversarial_queries.json`: security adversarial query set
- `report_baseline_week1.json`: machine-readable benchmark report
- `report_baseline_week1.md`: human-readable weekly summary

## Re-run

```bash
cd x-hub-system
./scripts/m2_memory_bench.sh
```

Optional overrides:

```bash
OUT_DIR=./docs/memory-new/benchmarks/m2-w1 \
DB_PATH=./data/hub.sqlite3 \
SEED=m2_w1_seed \
./scripts/m2_memory_bench.sh
```

Run with W2 pipeline engine preview:

```bash
M2_BENCH_USE_PIPELINE=1 \
OUT_DIR=/tmp/m2-bench-pipeline \
./scripts/m2_memory_bench.sh
```

Run with W2 risk-aware ranking and same-suite compare:

```bash
M2_BENCH_USE_PIPELINE=1 \
M2_BENCH_COMPARE=1 \
OUT_DIR=/tmp/m2-bench-risk \
./scripts/m2_memory_bench.sh
```

Compare output fields are written into report JSON:

- `comparison.delta` (risk vs legacy)
- `comparison.delta_vs_no_risk` (risk vs pipeline-no-risk)
- `comparison.top1_shift` / `comparison.top1_shift_vs_no_risk`

## Regression Gate (M2-W1-06)

Run current report in isolated output dir, then compare against baseline:

```bash
cd x-hub-system
OUT_DIR=/tmp/m2-bench-current ./scripts/m2_memory_bench.sh
node ./scripts/m2_check_bench_regression.js \
  --current /tmp/m2-bench-current/report_baseline_week1.json \
  --thresholds ./docs/memory-new/benchmarks/m2-w1/regression_thresholds.json
```

## Controlled Baseline Promotion (M2-W1-06)

Use explicit approval + ticket + owner; by default promotion is blocked on regression check:

```bash
cd x-hub-system
M2_BASELINE_UPDATE_APPROVED=1 node ./scripts/m2_promote_bench_baseline.js \
  --from-json /tmp/m2-bench-current/report_baseline_week1.json \
  --from-md /tmp/m2-bench-current/report_baseline_week1.md \
  --ticket M2-W1-06 \
  --owner hub-memory
```

Force promotion (requires explicit flag):

```bash
cd x-hub-system
M2_BASELINE_UPDATE_APPROVED=1 node ./scripts/m2_promote_bench_baseline.js \
  --from-json /tmp/m2-bench-current/report_baseline_week1.json \
  --ticket M2-W1-06 \
  --owner hub-memory \
  --allow-regression=1
```

Promotion history appends to:

- `docs/memory-new/benchmarks/m2-w1/baseline_promotions.jsonl`

## Current baseline snapshot

- `gate1_correctness=pass`
- `gate2_performance=pass`
- `gate3_security=fail` (expected for W1 baseline; W2/W5 will harden policy hit rate)
