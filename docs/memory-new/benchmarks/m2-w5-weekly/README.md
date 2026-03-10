# M2 W5-05 Weekly Regression Report Artifacts

- generatedAt: 2026-02-27
- purpose: M2-W5-05 周回归自动生成（趋势图 + 退化 TODO）

## Files

- `weekly_regression_history.jsonl`: 周回归历史快照（供趋势图与周对比使用）
- `weekly_regression_report.json`: 机器可读周报（baseline/current delta、checks、alerts、todos）
- `weekly_regression_report.md`: 人类可读周报（含趋势图与自动 TODO）

## Generate Weekly Report

```bash
cd x-hub-system
node ./scripts/m2_generate_weekly_regression_report.js \
  --current ./docs/memory-new/benchmarks/m2-w1/report_baseline_week1.json \
  --baseline ./docs/memory-new/benchmarks/m2-w1/report_baseline_week1.json \
  --thresholds ./docs/memory-new/benchmarks/m2-w1/regression_thresholds.json \
  --dashboard ./docs/memory-new/benchmarks/m2-w5-observability/dashboard_snapshot.json \
  --history ./docs/memory-new/benchmarks/m2-w5-weekly/weekly_regression_history.jsonl \
  --out-json ./docs/memory-new/benchmarks/m2-w5-weekly/weekly_regression_report.json \
  --out-md ./docs/memory-new/benchmarks/m2-w5-weekly/weekly_regression_report.md
```

## CI Usage (no history mutation)

```bash
cd x-hub-system
OUT_DIR=/tmp/m2-bench-current
node ./scripts/m2_generate_weekly_regression_report.js \
  --current "$OUT_DIR/report_baseline_week1.json" \
  --baseline ./docs/memory-new/benchmarks/m2-w1/report_baseline_week1.json \
  --thresholds ./docs/memory-new/benchmarks/m2-w1/regression_thresholds.json \
  --dashboard "$OUT_DIR/observability_dashboard.json" \
  --history ./docs/memory-new/benchmarks/m2-w5-weekly/weekly_regression_history.jsonl \
  --out-json "$OUT_DIR/weekly_regression_report.json" \
  --out-md "$OUT_DIR/weekly_regression_report.md" \
  --append-history 0
```
