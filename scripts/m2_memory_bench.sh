#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/docs/memory-new/benchmarks/m2-w1}"
DB_PATH="${DB_PATH:-$ROOT_DIR/data/hub.sqlite3}"
SEED="${SEED:-m2_w1_seed}"

mkdir -p "$OUT_DIR"

echo "[m2-bench] generating benchmark seed..."
node "$ROOT_DIR/scripts/m2_generate_benchmark_seed.js" \
  --db "$DB_PATH" \
  --out-dir "$OUT_DIR" \
  --seed "$SEED"

echo "[m2-bench] running benchmark..."
node "$ROOT_DIR/scripts/m2_memory_bench.js" \
  --dataset "$OUT_DIR/bench_baseline.json" \
  --golden "$OUT_DIR/golden_queries.json" \
  --adversarial "$OUT_DIR/adversarial_queries.json" \
  --out "$OUT_DIR/report_baseline_week1.json" \
  --out-md "$OUT_DIR/report_baseline_week1.md"

echo "[m2-bench] done."
echo "[m2-bench] outputs:"
echo "  - $OUT_DIR/bench_baseline.json"
echo "  - $OUT_DIR/golden_queries.json"
echo "  - $OUT_DIR/adversarial_queries.json"
echo "  - $OUT_DIR/report_baseline_week1.json"
echo "  - $OUT_DIR/report_baseline_week1.md"
