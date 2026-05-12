# RHM-116 Ready Hot Path Stutter Guard

## Purpose

Live stability checkpoints caught real `/ready` slow requests during sustained
post-cutover polling. The slow path was caused by a short readiness cache TTL
and a cache mutex that could be held while expensive readiness work performed
SQLite, skill catalog, and file-system checks.

RHM-116 hardens the `/ready` hot path:

- default `XHUB_RUST_READY_CACHE_TTL_MS` is raised from 250ms to 5000ms;
- the readiness cache no longer holds the cache mutex while recomputing the
  readiness body;
- cache refresh writes back with `try_lock`, so readers do not queue behind a
  long readiness recompute;
- `/health` remains uncached and independent.

## Runtime Effect

High-frequency live soak polling should now reuse a hot readiness body and avoid
multi-second `/ready` stalls caused by lock contention or repeated readiness I/O.

## Verified

- `cargo fmt`: ok.
- `cargo test -p xhubd readiness_cache_returns_hot_body_without_recompute`: ok.
- `cargo test -p xhubd http_metrics`: ok.
- `cargo test -p xhubd`: ok.
- `node --check tools/production_live_stability_gate.js`: ok.
- `node --check tools/production_live_stability_session.js`: ok.
