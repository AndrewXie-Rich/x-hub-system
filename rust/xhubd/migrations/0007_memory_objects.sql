-- Rust Hub universal memory object store.
-- This is the durable local-first memory object/event substrate used by the
-- Universal Memory Layer. Policy remains fail-closed at the Rust Hub boundary.

CREATE TABLE IF NOT EXISTS rust_hub_memory_objects (
  memory_id TEXT PRIMARY KEY,
  schema_version TEXT NOT NULL,
  scope TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  run_id TEXT,
  project_id TEXT,
  agent_id TEXT,
  source_kind TEXT NOT NULL,
  layer TEXT NOT NULL,
  title TEXT NOT NULL,
  text TEXT NOT NULL,
  summary TEXT NOT NULL,
  tags_json TEXT NOT NULL,
  sensitivity TEXT NOT NULL,
  visibility TEXT NOT NULL,
  status TEXT NOT NULL,
  pinned INTEGER NOT NULL DEFAULT 0,
  immutable INTEGER NOT NULL DEFAULT 0,
  ttl_ms INTEGER,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  last_accessed_at_ms INTEGER NOT NULL,
  version INTEGER NOT NULL,
  provenance_json TEXT NOT NULL,
  policy_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rust_hub_memory_objects_scope_owner
  ON rust_hub_memory_objects(scope, owner_id, status, updated_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_rust_hub_memory_objects_project
  ON rust_hub_memory_objects(project_id, status, updated_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_rust_hub_memory_objects_agent
  ON rust_hub_memory_objects(agent_id, status, updated_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_rust_hub_memory_objects_layer
  ON rust_hub_memory_objects(layer, source_kind, status, updated_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_rust_hub_memory_objects_sensitivity
  ON rust_hub_memory_objects(sensitivity, visibility, status);

CREATE TABLE IF NOT EXISTS rust_hub_memory_events (
  event_id TEXT PRIMARY KEY,
  memory_id TEXT NOT NULL,
  operation TEXT NOT NULL,
  actor TEXT NOT NULL,
  reason TEXT NOT NULL,
  before_version INTEGER,
  after_version INTEGER,
  before_json TEXT,
  after_json TEXT,
  policy_decision TEXT NOT NULL,
  deny_code TEXT NOT NULL,
  audit_ref TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  FOREIGN KEY(memory_id) REFERENCES rust_hub_memory_objects(memory_id)
);

CREATE INDEX IF NOT EXISTS idx_rust_hub_memory_events_memory_time
  ON rust_hub_memory_events(memory_id, created_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_rust_hub_memory_events_operation_time
  ON rust_hub_memory_events(operation, created_at_ms DESC);
