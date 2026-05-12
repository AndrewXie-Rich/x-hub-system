-- Rust Hub shadow-compare evidence.
-- Reports are append-only evidence used before any production authority cutover.

CREATE TABLE IF NOT EXISTS rust_hub_shadow_compare_reports (
  report_id TEXT PRIMARY KEY,
  component TEXT NOT NULL,
  compared_at_ms INTEGER NOT NULL,
  match_result TEXT NOT NULL,
  rust_status_json TEXT NOT NULL,
  node_status_json TEXT NOT NULL,
  mismatch_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rust_hub_shadow_compare_component_time
  ON rust_hub_shadow_compare_reports(component, compared_at_ms DESC);
