use std::collections::BTreeSet;

use serde_json::{json, Value};
use xhub_core::HubConfig;
use xhub_db::{list_memory_objects, MemoryObjectListFilter, MemoryObjectRecord};

use super::super::shared::{
    http_json_error, now_ms_i64, HttpJsonError, MEMORY_RETRIEVAL_TRACE_LIMIT,
    MEMORY_WRITEBACK_CANDIDATE_DIAGNOSTICS_SCHEMA,
};

const WRITEBACK_CANDIDATE_DIAGNOSTICS_SAMPLE_LIMIT: usize = 500;

#[derive(Debug, Clone, Default)]
struct WritebackCandidateDiagnostics {
    candidate_count: usize,
    sample_limit: usize,
    candidate_scan_bounded: bool,
    archived_scan_bounded: bool,
    conflict_candidate_count: usize,
    stale_review_required_count: usize,
    stale_candidate_count: usize,
    planned_archive_count: usize,
    planned_stale_review_required_count: usize,
    active_review_lock_count: usize,
    superseding_candidate_count: usize,
    archived_superseded_count: usize,
    conflict_candidate_ids: Vec<String>,
    stale_review_required_ids: Vec<String>,
    superseding_candidate_ids: Vec<String>,
    archived_superseded_ids: Vec<String>,
}

pub(crate) fn writeback_candidate_diagnostics_value(
    config: &HubConfig,
    filter: &MemoryObjectListFilter,
) -> Result<Value, HttpJsonError> {
    let mut candidate_filter = filter.clone();
    candidate_filter.status = Some("candidate".to_string());
    candidate_filter.limit = WRITEBACK_CANDIDATE_DIAGNOSTICS_SAMPLE_LIMIT;
    let candidates = list_memory_objects(&config.db_path, &candidate_filter).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_writeback_candidate_diagnostics_failed",
            err.to_string(),
        )
    })?;

    let mut archived_filter = filter.clone();
    archived_filter.status = Some("archived".to_string());
    archived_filter.limit = WRITEBACK_CANDIDATE_DIAGNOSTICS_SAMPLE_LIMIT;
    let archived = list_memory_objects(&config.db_path, &archived_filter).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_writeback_candidate_diagnostics_failed",
            err.to_string(),
        )
    })?;

    Ok(writeback_candidate_diagnostics_from_objects(
        &candidates,
        &archived,
        now_ms_i64(),
        WRITEBACK_CANDIDATE_DIAGNOSTICS_SAMPLE_LIMIT,
    ))
}

pub(crate) fn writeback_candidate_diagnostics_readiness_json(config: &HubConfig) -> Value {
    let filter = MemoryObjectListFilter {
        limit: WRITEBACK_CANDIDATE_DIAGNOSTICS_SAMPLE_LIMIT,
        ..Default::default()
    };
    match writeback_candidate_diagnostics_value(config, &filter) {
        Ok(value) => value,
        Err(err) => json!({
            "schema_version": MEMORY_WRITEBACK_CANDIDATE_DIAGNOSTICS_SCHEMA,
            "ready": false,
            "source": "rust_memory_object_store",
            "candidate_count": 0,
            "sample_limit": WRITEBACK_CANDIDATE_DIAGNOSTICS_SAMPLE_LIMIT,
            "bounded": false,
            "candidate_scan_bounded": false,
            "archived_scan_bounded": false,
            "conflict_candidate_count": 0,
            "stale_review_required_count": 0,
            "stale_candidate_count": 0,
            "planned_archive_count": 0,
            "planned_stale_review_required_count": 0,
            "active_review_lock_count": 0,
            "superseding_candidate_count": 0,
            "archived_superseded_count": 0,
            "superseded_candidate_count": 0,
            "queue_pressure": "unknown",
            "noise_score": 0,
            "conflict_candidate_ids": [],
            "stale_review_required_ids": [],
            "superseding_candidate_ids": [],
            "archived_superseded_ids": [],
            "error_code": "memory_writeback_candidate_diagnostics_failed",
            "error": serde_json::from_str::<Value>(&err.body)
                .unwrap_or_else(|_| json!({ "message": err.body })),
            "production_authority_change": false,
        }),
    }
}

pub(crate) fn writeback_candidate_diagnostics_from_objects(
    candidates: &[MemoryObjectRecord],
    archived: &[MemoryObjectRecord],
    now: i64,
    sample_limit: usize,
) -> Value {
    let mut diagnostics = WritebackCandidateDiagnostics {
        candidate_count: candidates.len(),
        sample_limit,
        candidate_scan_bounded: candidates.len() >= sample_limit,
        archived_scan_bounded: archived.len() >= sample_limit,
        ..Default::default()
    };

    for object in candidates {
        if !writeback_candidate_conflict_ids(object).is_empty()
            || memory_json_any_bool(
                &object.policy_json,
                &[
                    "conflict_resolution_required",
                    "candidate_conflict_required",
                ],
            )
            || memory_json_any_bool(
                &object.provenance_json,
                &[
                    "conflict_resolution_required",
                    "candidate_conflict_required",
                ],
            )
        {
            diagnostics.conflict_candidate_count += 1;
            push_bounded_id(&mut diagnostics.conflict_candidate_ids, &object.memory_id);
        }
        if writeback_candidate_already_marked_stale_review(object) {
            diagnostics.stale_review_required_count += 1;
            push_bounded_id(
                &mut diagnostics.stale_review_required_ids,
                &object.memory_id,
            );
        }
        if writeback_candidate_has_active_review_lock(object) {
            diagnostics.active_review_lock_count += 1;
        }

        let age_ms = now.saturating_sub(object.updated_at_ms.max(object.created_at_ms));
        if age_ms >= writeback_candidate_effective_ttl_ms(object) {
            diagnostics.stale_candidate_count += 1;
            if writeback_candidate_requires_stale_review(object) {
                diagnostics.planned_stale_review_required_count += 1;
            } else {
                diagnostics.planned_archive_count += 1;
            }
        }

        if !writeback_candidate_supersedes_ids(object).is_empty() {
            diagnostics.superseding_candidate_count += 1;
            push_bounded_id(
                &mut diagnostics.superseding_candidate_ids,
                &object.memory_id,
            );
        }
    }

    for object in archived {
        if writeback_candidate_superseded_by(object).is_some() {
            diagnostics.archived_superseded_count += 1;
            push_bounded_id(&mut diagnostics.archived_superseded_ids, &object.memory_id);
        }
    }

    diagnostics.to_json()
}

impl WritebackCandidateDiagnostics {
    fn queue_pressure(&self) -> &'static str {
        if self.conflict_candidate_count > 0 || self.stale_review_required_count > 0 {
            "high"
        } else if self.stale_candidate_count > 0
            || self.superseding_candidate_count > 0
            || self.archived_superseded_count > 0
        {
            "medium"
        } else {
            "low"
        }
    }

    fn noise_score(&self) -> usize {
        self.conflict_candidate_count.saturating_mul(5)
            + self.stale_review_required_count.saturating_mul(4)
            + self.stale_candidate_count.saturating_mul(2)
            + self.archived_superseded_count
            + self.superseding_candidate_count
    }

    fn to_json(&self) -> Value {
        json!({
            "schema_version": MEMORY_WRITEBACK_CANDIDATE_DIAGNOSTICS_SCHEMA,
            "ready": true,
            "source": "rust_memory_object_store",
            "candidate_count": self.candidate_count,
            "sample_limit": self.sample_limit,
            "bounded": self.candidate_scan_bounded || self.archived_scan_bounded,
            "candidate_scan_bounded": self.candidate_scan_bounded,
            "archived_scan_bounded": self.archived_scan_bounded,
            "conflict_candidate_count": self.conflict_candidate_count,
            "stale_review_required_count": self.stale_review_required_count,
            "stale_candidate_count": self.stale_candidate_count,
            "planned_archive_count": self.planned_archive_count,
            "planned_stale_review_required_count": self.planned_stale_review_required_count,
            "active_review_lock_count": self.active_review_lock_count,
            "superseding_candidate_count": self.superseding_candidate_count,
            "archived_superseded_count": self.archived_superseded_count,
            "superseded_candidate_count": self.archived_superseded_count,
            "queue_pressure": self.queue_pressure(),
            "noise_score": self.noise_score(),
            "conflict_candidate_ids": self.conflict_candidate_ids,
            "stale_review_required_ids": self.stale_review_required_ids,
            "superseding_candidate_ids": self.superseding_candidate_ids,
            "archived_superseded_ids": self.archived_superseded_ids,
            "production_authority_change": false,
        })
    }
}

fn push_bounded_id(items: &mut Vec<String>, memory_id: &str) {
    if items.len() < MEMORY_RETRIEVAL_TRACE_LIMIT {
        items.push(memory_id.to_string());
    }
}

fn writeback_candidate_effective_ttl_ms(object: &MemoryObjectRecord) -> i64 {
    if let Some(value) = object.ttl_ms.filter(|value| *value > 0) {
        return value;
    }
    const DAY_MS: i64 = 24 * 60 * 60 * 1000;
    if object.layer == "l3_working_set"
        || matches!(object.source_kind.as_str(), "current_state" | "next_step")
    {
        7 * DAY_MS
    } else if object.layer == "l2_observations"
        || matches!(
            object.source_kind.as_str(),
            "risk" | "open_question" | "recommendation"
        )
    {
        14 * DAY_MS
    } else {
        30 * DAY_MS
    }
}

fn writeback_candidate_requires_stale_review(object: &MemoryObjectRecord) -> bool {
    object.pinned
        || object.scope == "user"
        || object.layer == "l0_constitution"
        || object.layer == "l1_canonical"
        || object.visibility != "local_only"
        || matches!(
            object.source_kind.as_str(),
            "project_goal"
                | "project_requirement"
                | "decision_track"
                | "guidance_injection"
                | "personal_capsule"
        )
}

fn writeback_candidate_has_active_review_lock(object: &MemoryObjectRecord) -> bool {
    memory_json_any_bool(
        &object.policy_json,
        &["active_review_lock", "review_lock", "candidate_review_lock"],
    ) || memory_json_any_bool(
        &object.provenance_json,
        &["active_review_lock", "review_lock", "candidate_review_lock"],
    )
}

fn writeback_candidate_already_marked_stale_review(object: &MemoryObjectRecord) -> bool {
    memory_json_any_bool(
        &object.policy_json,
        &["stale_review_required", "candidate_stale_review_required"],
    ) || memory_json_any_bool(
        &object.provenance_json,
        &["stale_review_required", "candidate_stale_review_required"],
    )
}

fn memory_json_any_bool(raw_json: &str, keys: &[&str]) -> bool {
    let Ok(value) = serde_json::from_str::<Value>(raw_json) else {
        return false;
    };
    keys.iter()
        .any(|key| value.get(*key).and_then(Value::as_bool).unwrap_or(false))
}

fn memory_json_string_array_any(raw_json: &str, keys: &[&str]) -> Vec<String> {
    let Ok(value) = serde_json::from_str::<Value>(raw_json) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for key in keys {
        match value.get(*key) {
            Some(Value::Array(items)) => {
                out.extend(
                    items
                        .iter()
                        .filter_map(Value::as_str)
                        .map(|item| item.trim().to_string())
                        .filter(|item| !item.is_empty()),
                );
            }
            Some(Value::String(item)) if !item.trim().is_empty() => {
                out.push(item.trim().to_string());
            }
            _ => {}
        }
    }
    unique_strings(out)
}

fn memory_json_any_string(raw_json: &str, keys: &[&str]) -> Option<String> {
    let Ok(value) = serde_json::from_str::<Value>(raw_json) else {
        return None;
    };
    keys.iter().find_map(|key| {
        value
            .get(*key)
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|item| !item.is_empty())
            .map(str::to_string)
    })
}

fn unique_strings(values: Vec<String>) -> Vec<String> {
    let mut seen = BTreeSet::new();
    let mut out = Vec::new();
    for value in values {
        let value = value.trim().to_string();
        if value.is_empty() || !seen.insert(value.clone()) {
            continue;
        }
        out.push(value);
    }
    out
}

fn writeback_candidate_conflict_ids(object: &MemoryObjectRecord) -> Vec<String> {
    unique_strings(
        memory_json_string_array_any(&object.policy_json, &["conflict_with"])
            .into_iter()
            .chain(memory_json_string_array_any(
                &object.provenance_json,
                &["conflict_with"],
            ))
            .collect(),
    )
}

fn writeback_candidate_supersedes_ids(object: &MemoryObjectRecord) -> Vec<String> {
    unique_strings(
        memory_json_string_array_any(&object.policy_json, &["supersedes"])
            .into_iter()
            .chain(memory_json_string_array_any(
                &object.provenance_json,
                &["supersedes"],
            ))
            .collect(),
    )
}

fn writeback_candidate_superseded_by(object: &MemoryObjectRecord) -> Option<String> {
    memory_json_any_string(&object.policy_json, &["superseded_by"])
        .or_else(|| memory_json_any_string(&object.provenance_json, &["superseded_by"]))
}
