# M2-W3-05 Reliability Drill Report (Gate-4)

- version: v1
- date: 2026-02-26
- owner: Hub Memory / Security
- scope: restart recovery, corruption recovery, concurrent-write recovery

## 1) Drill Harness

- test file: `x-hub/grpc-server/hub_grpc_server/src/memory_index_reliability_drill.test.js`
- local run:
  - `cd x-hub/grpc-server/hub_grpc_server`
  - `node src/memory_index_reliability_drill.test.js`
- CI gate:
  - `.github/workflows/m2-memory-bench.yml`
  - step: `Run W3-05 reliability drills (restart/corruption/concurrency)`

## 2) Scenarios and Pass Criteria

1. Restart recovery
- scenario: consumer processes partial changelog, process restarts, new writes arrive, consumer resumes from checkpoint, then rebuild swaps successfully.
- pass: checkpoint catches up to latest seq; rebuild remains swappable post-restart.

2. Corruption recovery
- scenario: active index pointer is corrupted to non-existent generation, active docs are cleared, then rebuild runs.
- pass: system self-heals to valid active generation; `last_rebuild_status=active`; `last_error=null`.

3. Concurrent-write recovery
- scenario: new writes are injected while rebuild is in progress.
- pass: rebuild completes on a stable snapshot, and post-snapshot delta is consumed to latest seq by checkpointed consumer.

## 3) Acceptance Mapping (M2-W3-05)

- 三类故障均可恢复: pass
- 无数据越权泄露: pass
- 回滚路径可执行: pass

## 4) Notes

- Existing W3-03 swap rollback validation remains in:
  - `x-hub/grpc-server/hub_grpc_server/src/memory_index_rebuild.test.js`
- Existing W3-02 restart-resume/idempotency validation remains in:
  - `x-hub/grpc-server/hub_grpc_server/src/memory_index_consumer.test.js`
