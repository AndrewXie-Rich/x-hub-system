# M2-W5-04 Observability Dashboard Snapshot

- generated_at_ms: 1772196324225
- schema_version: xhub.memory.observability.dashboard.v1
- runtime_event_count: 0

## Latency Panel
- benchmark p95/p99(ms): 0.234 / 0.234
- runtime duration p95/p99(ms): n/a / n/a
- runtime queue_wait p95(ms): n/a
- runtime queue_depth p95: n/a

## Quality Panel
- precision_at_k_avg: 20.00%
- recall_at_k_avg: 100.00%
- mrr_at_k_avg: 100.00%
- adversarial blocked_rate: 47.92%

## Cost Panel
- total_tokens p95: n/a
- total_tokens sum: 0

## Freshness Panel
- index_freshness p95/max(ms): n/a / n/a

## Alerts
- critical: 0
- warn: 1
- no_data: 7
- [warn] pipeline.stage.top_anomaly value=66 threshold=40 stage=gate hint=no_block_pattern

## Pipeline Stage Diagnostics
- top_stage: gate
- anomaly_score: 66
- blocked_count: 0
- deny_count: 22
- top_reason: no_block_pattern
