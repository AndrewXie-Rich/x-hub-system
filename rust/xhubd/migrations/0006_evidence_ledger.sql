-- Rust Hub unified evidence ledger.
-- This is append-only cross-subsystem evidence used to explain route, lease,
-- doctor, skill, memory, quota, scheduler, heartbeat, and repair decisions.

CREATE TABLE IF NOT EXISTS rust_hub_evidence_ledger (
  evidence_id TEXT PRIMARY KEY,
  created_at_ms INTEGER NOT NULL,
  component TEXT NOT NULL,
  authority_mode TEXT NOT NULL,
  project_id TEXT,
  run_id TEXT,
  output_verdict TEXT NOT NULL,
  reason_json TEXT NOT NULL,
  parent_evidence_json TEXT NOT NULL,
  input_ref_json TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  expires_at_ms INTEGER
);

CREATE INDEX IF NOT EXISTS idx_rust_hub_evidence_component_time
  ON rust_hub_evidence_ledger(component, created_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_rust_hub_evidence_run_time
  ON rust_hub_evidence_ledger(run_id, created_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_rust_hub_evidence_project_time
  ON rust_hub_evidence_ledger(project_id, created_at_ms DESC);
