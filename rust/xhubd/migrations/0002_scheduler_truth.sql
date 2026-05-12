-- Rust Hub scheduler truth tables.
-- These tables are still namespaced while Rust Hub runs side-by-side with the
-- Node Hub. They are safe to create in a standalone Rust Hub DB.

CREATE TABLE IF NOT EXISTS rust_hub_run_queue (
  run_id TEXT PRIMARY KEY,
  request_id TEXT NOT NULL,
  scope_key TEXT NOT NULL,
  project_id TEXT,
  device_id TEXT,
  task_type TEXT NOT NULL,
  status TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 0,
  idempotency_key TEXT NOT NULL,
  not_before_ms INTEGER NOT NULL DEFAULT 0,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  payload_json TEXT NOT NULL DEFAULT '{}',
  last_error_code TEXT,
  last_error_message TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_rust_hub_run_queue_idempotency
  ON rust_hub_run_queue(scope_key, idempotency_key);

CREATE INDEX IF NOT EXISTS idx_rust_hub_run_queue_sched
  ON rust_hub_run_queue(status, not_before_ms, priority DESC, created_at_ms);

CREATE TABLE IF NOT EXISTS rust_hub_run_leases (
  run_id TEXT PRIMARY KEY,
  lease_owner TEXT NOT NULL,
  lease_token TEXT NOT NULL,
  lease_expires_at_ms INTEGER NOT NULL,
  heartbeat_at_ms INTEGER NOT NULL,
  acquired_at_ms INTEGER NOT NULL,
  attempt INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_rust_hub_run_leases_expiry
  ON rust_hub_run_leases(lease_expires_at_ms);

CREATE TABLE IF NOT EXISTS rust_hub_scheduler_events (
  event_id TEXT PRIMARY KEY,
  run_id TEXT,
  event_type TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  scope_key TEXT,
  detail_json TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_rust_hub_scheduler_events_time
  ON rust_hub_scheduler_events(created_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_rust_hub_scheduler_events_run
  ON rust_hub_scheduler_events(run_id, created_at_ms DESC);

CREATE TABLE IF NOT EXISTS rust_hub_scheduler_scope_counters (
  scope_key TEXT PRIMARY KEY,
  in_flight INTEGER NOT NULL DEFAULT 0,
  queued INTEGER NOT NULL DEFAULT 0,
  oldest_queued_at_ms INTEGER NOT NULL DEFAULT 0,
  updated_at_ms INTEGER NOT NULL
);

