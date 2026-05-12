-- Rust Hub skill policy gates.
-- These tables are authority-neutral until a later execution cutover. They
-- store pin/grant evidence and preflight audit previews only.

CREATE TABLE IF NOT EXISTS rust_hub_skill_pins (
  scope_key TEXT NOT NULL,
  skill_id TEXT NOT NULL,
  pinned_by TEXT NOT NULL,
  pinned_at_ms INTEGER NOT NULL,
  revoked_at_ms INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (scope_key, skill_id)
);

CREATE INDEX IF NOT EXISTS idx_rust_hub_skill_pins_scope
  ON rust_hub_skill_pins(scope_key, revoked_at_ms);

CREATE TABLE IF NOT EXISTS rust_hub_skill_capability_grants (
  scope_key TEXT NOT NULL,
  skill_id TEXT NOT NULL,
  capability TEXT NOT NULL,
  granted_by TEXT NOT NULL,
  granted_at_ms INTEGER NOT NULL,
  revoked_at_ms INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (scope_key, skill_id, capability)
);

CREATE INDEX IF NOT EXISTS idx_rust_hub_skill_grants_scope
  ON rust_hub_skill_capability_grants(scope_key, skill_id, revoked_at_ms);

CREATE TABLE IF NOT EXISTS rust_hub_skill_preflight_audit (
  event_id TEXT PRIMARY KEY,
  created_at_ms INTEGER NOT NULL,
  scope_key TEXT NOT NULL,
  request_id TEXT,
  audit_ref TEXT,
  skill_id TEXT NOT NULL,
  decision TEXT NOT NULL,
  ok INTEGER NOT NULL,
  reason_json TEXT NOT NULL,
  detail_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rust_hub_skill_preflight_scope_time
  ON rust_hub_skill_preflight_audit(scope_key, created_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_rust_hub_skill_preflight_skill_time
  ON rust_hub_skill_preflight_audit(skill_id, created_at_ms DESC);
