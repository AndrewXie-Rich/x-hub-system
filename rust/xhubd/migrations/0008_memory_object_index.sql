-- Derived, rebuildable retrieval index for Rust Hub memory objects.
-- This table is not memory truth. It can be dropped and rebuilt from
-- rust_hub_memory_objects at any time.

CREATE TABLE IF NOT EXISTS rust_hub_memory_object_index (
  memory_id TEXT PRIMARY KEY,
  object_version INTEGER NOT NULL,
  object_created_at_ms INTEGER NOT NULL,
  object_updated_at_ms INTEGER NOT NULL,
  scope TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  run_id TEXT,
  project_id TEXT,
  agent_id TEXT,
  source_kind TEXT NOT NULL,
  layer TEXT NOT NULL,
  title TEXT NOT NULL,
  summary TEXT NOT NULL,
  text TEXT NOT NULL,
  searchable_text TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  sensitivity TEXT NOT NULL,
  visibility TEXT NOT NULL,
  pinned INTEGER NOT NULL DEFAULT 0,
  has_code INTEGER NOT NULL DEFAULT 0,
  has_todo INTEGER NOT NULL DEFAULT 0,
  has_error INTEGER NOT NULL DEFAULT 0,
  has_decision INTEGER NOT NULL DEFAULT 0,
  has_approval INTEGER NOT NULL DEFAULT 0,
  has_blocker INTEGER NOT NULL DEFAULT 0,
  has_link INTEGER NOT NULL DEFAULT 0,
  indexed_at_ms INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rust_hub_memory_object_index_project
  ON rust_hub_memory_object_index(project_id, scope, layer, source_kind);

CREATE INDEX IF NOT EXISTS idx_rust_hub_memory_object_index_owner
  ON rust_hub_memory_object_index(scope, owner_id, layer, source_kind);

CREATE INDEX IF NOT EXISTS idx_rust_hub_memory_object_index_sensitivity
  ON rust_hub_memory_object_index(sensitivity, visibility);

CREATE INDEX IF NOT EXISTS idx_rust_hub_memory_object_index_updated
  ON rust_hub_memory_object_index(object_updated_at_ms DESC, memory_id DESC);
