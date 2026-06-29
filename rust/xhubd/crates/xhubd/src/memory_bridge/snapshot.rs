use std::path::PathBuf;

use serde_json::{json, Value};
use xhub_core::HubConfig;
use xhub_db::{
    read_memory_object_index_summary, read_memory_object_store_summary, MemoryObjectIndexSummary,
};
use xhub_memory::{readiness_from_snapshot, scan_memory_snapshot, MemoryIndexSnapshot};

use super::shared::{
    memory_dir_from_env, memory_writer_authority_enabled, FlagArgs, MEMORY_OBJECT_SCHEMA,
    MEMORY_WRITEBACK_CANDIDATE_SCHEMA, SCHEMA_VERSION,
};

pub(crate) fn readiness_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let memory_dir = flags
        .optional("memory-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| memory_dir_from_env(config));
    readiness_json_from_dir(config, memory_dir)
}

pub fn readiness_json_from_dir(config: &HubConfig, memory_dir: PathBuf) -> Result<String, String> {
    let snapshot = scan_memory_snapshot(&memory_dir);
    readiness_json_from_snapshot_with_config(config, &snapshot)
}

pub fn readiness_json_from_snapshot_with_config(
    config: &HubConfig,
    snapshot: &MemoryIndexSnapshot,
) -> Result<String, String> {
    let summary = read_memory_object_store_summary(&config.db_path)
        .map_err(|err| format!("memory object store summary failed: {err}"))?;
    let index_summary = read_memory_object_index_summary(&config.db_path)
        .map_err(|err| format!("memory object index summary failed: {err}"))?;
    readiness_json_from_snapshot_inner(snapshot, Some(summary), Some(index_summary))
}

fn readiness_json_from_snapshot_inner(
    snapshot: &MemoryIndexSnapshot,
    object_summary: Option<xhub_db::MemoryObjectStoreSummary>,
    index_summary: Option<MemoryObjectIndexSummary>,
) -> Result<String, String> {
    let mut status = readiness_from_snapshot(snapshot);
    status.writer_authority_in_rust = memory_writer_authority_enabled();
    let object_store_ready = object_summary.is_some();
    let summary = object_summary.unwrap_or_default();
    let index = index_summary.unwrap_or_default();
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "readiness",
        "readiness": status,
        "object_store": {
            "schema_version": MEMORY_OBJECT_SCHEMA,
            "ready": object_store_ready,
            "object_count": summary.object_count,
            "active_object_count": summary.active_object_count,
            "candidate_object_count": summary.candidate_object_count,
            "deleted_tombstone_count": summary.deleted_tombstone_count,
            "event_count": summary.event_count,
            "latest_object_updated_at_ms": summary.latest_object_updated_at_ms,
            "latest_event_created_at_ms": summary.latest_event_created_at_ms,
            "policy_gate_ready": true,
            "crud_create_get_list_history_http": true,
            "memory_index_ready": index.index_ready,
            "memory_index_row_count": index.index_row_count,
            "memory_index_stale_count": index.stale_index_count,
            "memory_index_active_indexable_object_count": index.active_indexable_object_count,
            "memory_index_latest_indexed_at_ms": index.latest_indexed_at_ms,
            "memory_index_generation": {
                "source": "rust_hub_memory_object_index",
                "row_count": index.index_row_count,
                "stale_count": index.stale_index_count,
                "latest_indexed_at_ms": index.latest_indexed_at_ms,
            },
            "writeback_candidates": {
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "ready": object_store_ready,
                "candidate_object_count": summary.candidate_object_count,
                "candidate_create_http": true,
                "candidate_list_http": true,
                "candidate_approve_reject_http": true,
                "secret_candidate_fail_closed": true,
                "authority": "rust_policy_gated_candidate_queue",
                "production_authority_change": false,
            },
            "semantic_index_enabled": false,
        },
    })
    .to_string())
}

pub(crate) fn memory_object_index_summary_to_json(summary: &MemoryObjectIndexSummary) -> Value {
    json!({
        "source": "rust_hub_memory_object_index",
        "ready": summary.index_ready,
        "row_count": summary.index_row_count,
        "active_indexable_object_count": summary.active_indexable_object_count,
        "stale_count": summary.stale_index_count,
        "latest_indexed_at_ms": summary.latest_indexed_at_ms,
    })
}

pub(crate) fn memory_object_index_rebuild_report_to_json(
    report: &xhub_db::MemoryObjectIndexRebuildReport,
) -> Value {
    json!({
        "schema_version": &report.schema_version,
        "rebuilt": report.rebuilt,
        "indexed_count": report.indexed_count,
        "skipped_secret_count": report.skipped_secret_count,
        "skipped_inactive_count": report.skipped_inactive_count,
        "stale_before_count": report.stale_before_count,
        "stale_after_count": report.stale_after_count,
        "generated_at_ms": report.generated_at_ms,
    })
}

pub fn snapshot_from_dir(memory_dir: PathBuf) -> MemoryIndexSnapshot {
    scan_memory_snapshot(&memory_dir)
}
