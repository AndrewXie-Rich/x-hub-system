-- Rust Hub baseline metadata tables.
-- These tables are intentionally namespaced. They do not replace the current
-- Node Hub schema until the migration plan explicitly cuts over.

CREATE TABLE IF NOT EXISTS rust_hub_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS rust_hub_shadow_audit (
  event_id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  severity TEXT NOT NULL,
  ok INTEGER NOT NULL,
  detail_json TEXT
);

CREATE TABLE IF NOT EXISTS rust_hub_scheduler_snapshots (
  snapshot_id TEXT PRIMARY KEY,
  created_at_ms INTEGER NOT NULL,
  in_flight_total INTEGER NOT NULL,
  queue_depth INTEGER NOT NULL,
  detail_json TEXT
);

