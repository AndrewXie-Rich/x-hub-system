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
use super::write::diagnostics::writeback_candidate_diagnostics_readiness_json;

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
    let candidate_diagnostics = writeback_candidate_diagnostics_readiness_json(config);
    readiness_json_from_snapshot_inner(
        snapshot,
        Some(summary),
        Some(index_summary),
        Some(candidate_diagnostics),
    )
}

fn readiness_json_from_snapshot_inner(
    snapshot: &MemoryIndexSnapshot,
    object_summary: Option<xhub_db::MemoryObjectStoreSummary>,
    index_summary: Option<MemoryObjectIndexSummary>,
    candidate_diagnostics: Option<Value>,
) -> Result<String, String> {
    let mut status = readiness_from_snapshot(snapshot);
    status.writer_authority_in_rust = memory_writer_authority_enabled();
    let object_store_ready = object_summary.is_some();
    let summary = object_summary.unwrap_or_default();
    let index = index_summary.unwrap_or_default();
    let index_coverage_complete = index.indexed_object_count == index.active_indexable_object_count;
    let index_timestamp_current = index.active_indexable_object_count == 0
        || (index.latest_indexed_at_ms > 0
            && index.latest_indexed_at_ms >= index.latest_indexable_object_updated_at_ms);
    let mut index_blocker_codes = Vec::<&str>::new();
    if !index.schema_ready {
        index_blocker_codes.push("memory_object_index_schema_unavailable");
    }
    if index.stale_index_count > 0 {
        index_blocker_codes.push("memory_object_index_stale");
    }
    if !index_coverage_complete {
        index_blocker_codes.push("memory_object_index_coverage_incomplete");
    }
    if !index_timestamp_current {
        index_blocker_codes.push("memory_object_index_timestamp_behind_source");
    }
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
            "memory_index_schema_ready": index.schema_ready,
            "memory_index_row_count": index.index_row_count,
            "memory_index_indexed_object_count": index.indexed_object_count,
            "memory_index_stale_count": index.stale_index_count,
            "memory_index_active_indexable_object_count": index.active_indexable_object_count,
            "memory_index_latest_indexed_at_ms": index.latest_indexed_at_ms,
            "memory_index_latest_source_updated_at_ms": index.latest_indexable_object_updated_at_ms,
            "memory_index_generation": {
                "source": "rust_hub_memory_object_index",
                "ready": index.index_ready,
                "schema_ready": index.schema_ready,
                "row_count": index.index_row_count,
                "indexed_object_count": index.indexed_object_count,
                "active_indexable_object_count": index.active_indexable_object_count,
                "coverage_complete": index_coverage_complete,
                "stale_count": index.stale_index_count,
                "latest_indexed_at_ms": index.latest_indexed_at_ms,
                "latest_source_updated_at_ms": index.latest_indexable_object_updated_at_ms,
                "timestamp_current": index_timestamp_current,
                "blocker_codes": index_blocker_codes,
            },
            "writeback_candidates": {
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "ready": object_store_ready,
                "candidate_object_count": summary.candidate_object_count,
                "candidate_create_http": true,
                "candidate_list_http": true,
                "candidate_approve_reject_http": true,
                "candidate_diagnostics_http": true,
                "candidate_maintenance_http": false,
                "secret_candidate_fail_closed": true,
                "authority": "rust_policy_gated_candidate_queue",
                "maintenance": {
                    "maintenance_ready": false,
                    "candidate_maintenance_http": false,
                    "candidate_maintenance_cli": false,
                    "reason_code": "memory_writeback_candidate_maintenance_not_implemented",
                    "production_authority_change": false,
                },
                "diagnostics": candidate_diagnostics.unwrap_or_else(|| json!({
                    "schema_version": super::shared::MEMORY_WRITEBACK_CANDIDATE_DIAGNOSTICS_SCHEMA,
                    "ready": false,
                    "source": "rust_memory_object_store",
                    "candidate_count": summary.candidate_object_count,
                    "queue_pressure": "unknown",
                    "noise_score": 0,
                    "error_code": "memory_writeback_candidate_diagnostics_unavailable",
                    "production_authority_change": false,
                })),
                "production_authority_change": false,
            },
            "semantic_index_enabled": false,
        },
    })
    .to_string())
}

pub(crate) fn memory_object_index_summary_to_json(summary: &MemoryObjectIndexSummary) -> Value {
    let coverage_complete = summary.indexed_object_count == summary.active_indexable_object_count;
    let timestamp_current = summary.active_indexable_object_count == 0
        || (summary.latest_indexed_at_ms > 0
            && summary.latest_indexed_at_ms >= summary.latest_indexable_object_updated_at_ms);
    json!({
        "source": "rust_hub_memory_object_index",
        "ready": summary.index_ready,
        "schema_ready": summary.schema_ready,
        "row_count": summary.index_row_count,
        "indexed_object_count": summary.indexed_object_count,
        "active_indexable_object_count": summary.active_indexable_object_count,
        "coverage_complete": coverage_complete,
        "stale_count": summary.stale_index_count,
        "latest_indexed_at_ms": summary.latest_indexed_at_ms,
        "latest_source_updated_at_ms": summary.latest_indexable_object_updated_at_ms,
        "timestamp_current": timestamp_current,
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
