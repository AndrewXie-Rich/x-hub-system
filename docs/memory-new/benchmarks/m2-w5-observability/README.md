# M2 W5-04 Observability Dashboard Artifacts

- generatedAt: 2026-02-27
- purpose: M2-W5-04 仪表盘与告警阈值收口（`Now-18`）

## Files

- `observability_thresholds.json`: 告警阈值与噪声抑制规则（p95/p99/queue/freshness/security）
- `dashboard_snapshot.json`: 机器可读仪表盘快照（四类面板 + pipeline stage 异常定位 + alerts）
- `dashboard_snapshot.md`: 人类可读快照摘要

## Generate Dashboard Snapshot

```bash
cd x-hub-system
node ./scripts/m2_build_observability_dashboard.js \
  --report ./docs/memory-new/benchmarks/m2-w1/report_baseline_week1.json \
  --thresholds ./docs/memory-new/benchmarks/m2-w5-observability/observability_thresholds.json \
  --out-json ./docs/memory-new/benchmarks/m2-w5-observability/dashboard_snapshot.json \
  --out-md ./docs/memory-new/benchmarks/m2-w5-observability/dashboard_snapshot.md
```

Use an explicit DB/window for runtime metrics:

```bash
cd x-hub-system
node ./scripts/m2_build_observability_dashboard.js \
  --db ./data/hub.sqlite3 \
  --window-ms 86400000 \
  --report ./docs/memory-new/benchmarks/m2-w1/report_baseline_week1.json \
  --thresholds ./docs/memory-new/benchmarks/m2-w5-observability/observability_thresholds.json \
  --out-json /tmp/m2-observability/dashboard.json \
  --out-md /tmp/m2-observability/dashboard.md
```

## Alert Gate

```bash
cd x-hub-system
node ./scripts/m2_check_observability_alerts.js \
  --dashboard ./docs/memory-new/benchmarks/m2-w5-observability/dashboard_snapshot.json \
  --max-critical 0
```

Optional strict mode:

```bash
cd x-hub-system
node ./scripts/m2_check_observability_alerts.js \
  --dashboard /tmp/m2-observability/dashboard.json \
  --max-critical 0 \
  --max-warn 2 \
  --ignore-suppressed-warn 0
```
