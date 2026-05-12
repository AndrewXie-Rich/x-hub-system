-- Rust Hub skill policy change events.
-- Append-only policy operation metadata for long-running governance.

CREATE TABLE IF NOT EXISTS rust_hub_skill_policy_events (
  event_id TEXT PRIMARY KEY,
  created_at_ms INTEGER NOT NULL,
  operation TEXT NOT NULL,
  scope_key TEXT NOT NULL,
  skill_id TEXT NOT NULL,
  capability TEXT,
  actor TEXT NOT NULL,
  result TEXT NOT NULL,
  detail_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rust_hub_skill_policy_events_scope_time
  ON rust_hub_skill_policy_events(scope_key, created_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_rust_hub_skill_policy_events_skill_time
  ON rust_hub_skill_policy_events(skill_id, created_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_rust_hub_skill_policy_events_operation_time
  ON rust_hub_skill_policy_events(operation, created_at_ms DESC);
