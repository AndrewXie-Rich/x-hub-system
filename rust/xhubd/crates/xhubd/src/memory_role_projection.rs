use serde_json::{json, Map, Value};
use xhub_core::{now_ms, HubConfig};
use xhub_db::{
    read_project_role_transcript_rows, ProjectRoleThreadRow, ProjectRoleTranscriptQuery,
    ProjectRoleTranscriptRows, ProjectRoleTurnRow,
};

pub const PROJECT_ROLE_TRANSCRIPT_PROJECTION_SCHEMA: &str =
    "xhub.project_role_transcript_projection.v1";
pub const ROLE_TURN_METADATA_SCHEMA: &str = "xhub.role_turn_metadata.v1";

const RUNTIME_SOURCE: &str = "rust_sqlite_turns_shadow";
const ENCRYPTED_RECORD_PREFIX: &str = "xhubenc:v1:";
const SOURCE_ROLES: &[&str] = &[
    "user",
    "supervisor",
    "coder",
    "reviewer",
    "tool",
    "hub",
    "system",
];

pub fn projection_json_from_parts(
    config: &HubConfig,
    device_id: Option<String>,
    app_id: Option<String>,
    project_id: String,
    thread_key: String,
    limit: usize,
    include_content: bool,
) -> Result<String, String> {
    let rows = read_project_role_transcript_rows(
        &config.db_path,
        ProjectRoleTranscriptQuery {
            device_id,
            app_id,
            project_id,
            thread_key,
            limit,
        },
    )
    .map_err(|err| format!("project role transcript read failed: {err}"))?;
    let out = projection_value_from_rows(rows, include_content)?;
    serde_json::to_string(&out)
        .map_err(|err| format!("project role transcript serialize failed: {err}"))
}

fn projection_value_from_rows(
    rows: ProjectRoleTranscriptRows,
    include_content: bool,
) -> Result<Value, String> {
    let Some(thread) = rows.thread.as_ref() else {
        return Ok(json!({
            "ok": true,
            "schema_version": PROJECT_ROLE_TRANSCRIPT_PROJECTION_SCHEMA,
            "source": "hub_memory_turns",
            "runtime_source": RUNTIME_SOURCE,
            "project_id": "",
            "thread_id": "",
            "thread_key": "",
            "status": "empty",
            "recent_lines": [],
            "generated_at_ms": now_ms_i64(),
            "authority": "shadow_read_only",
            "production_authority_change": false,
            "include_content": include_content,
        }));
    };

    let mut newest_lines = Vec::new();
    for row in rows.turns_newest_first.iter() {
        newest_lines.push(project_line_from_turn(row, thread, include_content)?);
    }
    let mut recent_lines = newest_lines.clone();
    recent_lines.reverse();

    let latest_supervisor_dispatch = newest_lines
        .iter()
        .find(|line| {
            line.dispatch_kind() == "supervisor_to_coder" || line.role.as_str() == "supervisor"
        })
        .cloned();
    let latest_coder_reply = newest_lines
        .iter()
        .find(|line| line.dispatch_kind() == "coder_reply" || line.role.as_str() == "coder")
        .cloned();
    let latest_reviewer_note = newest_lines
        .iter()
        .find(|line| line.dispatch_kind() == "reviewer_note" || line.role.as_str() == "reviewer")
        .cloned();
    let latest_status = newest_lines
        .iter()
        .find(|line| line.dispatch_kind() != "heartbeat" && !line.status().is_empty())
        .map(ProjectRoleTranscriptLine::status)
        .unwrap_or_default();
    let status = if matches!(
        latest_status.as_str(),
        "awaiting_authorization" | "failed" | "running"
    ) {
        latest_status
    } else if latest_coder_reply.is_some() {
        "latest_coder_reply_observed".to_string()
    } else if latest_supervisor_dispatch.is_some() {
        "dispatch_observed".to_string()
    } else {
        "observed".to_string()
    };

    Ok(json!({
        "ok": true,
        "schema_version": PROJECT_ROLE_TRANSCRIPT_PROJECTION_SCHEMA,
        "source": "hub_memory_turns",
        "runtime_source": RUNTIME_SOURCE,
        "project_id": thread.project_id,
        "thread_id": thread.thread_id,
        "thread_key": thread.thread_key,
        "status": status,
        "latest_supervisor_dispatch": latest_supervisor_dispatch.map(|line| line.into_value()).unwrap_or(Value::Null),
        "latest_coder_reply": latest_coder_reply.map(|line| line.into_value()).unwrap_or(Value::Null),
        "latest_reviewer_note": latest_reviewer_note.map(|line| line.into_value()).unwrap_or(Value::Null),
        "recent_lines": recent_lines
            .into_iter()
            .map(ProjectRoleTranscriptLine::into_value)
            .collect::<Vec<Value>>(),
        "generated_at_ms": now_ms_i64(),
        "authority": "shadow_read_only",
        "production_authority_change": false,
        "include_content": include_content,
    }))
}

#[derive(Debug, Clone, PartialEq)]
struct ProjectRoleTranscriptLine {
    turn_id: String,
    role: String,
    content: String,
    turn_metadata: Option<Value>,
    created_at_ms: i64,
    content_encrypted: bool,
    content_redacted: bool,
}

impl ProjectRoleTranscriptLine {
    fn dispatch_kind(&self) -> String {
        metadata_string(self.turn_metadata.as_ref(), "dispatch_kind")
    }

    fn status(&self) -> String {
        metadata_string(self.turn_metadata.as_ref(), "status")
    }

    fn into_value(self) -> Value {
        let mut map = Map::new();
        map.insert("turn_id".to_string(), Value::String(self.turn_id));
        map.insert("role".to_string(), Value::String(self.role));
        map.insert("content".to_string(), Value::String(self.content));
        if let Some(metadata) = self.turn_metadata {
            map.insert("turn_metadata".to_string(), metadata);
        }
        map.insert(
            "created_at_ms".to_string(),
            Value::Number(serde_json::Number::from(self.created_at_ms)),
        );
        if self.content_encrypted {
            map.insert("content_encrypted".to_string(), Value::Bool(true));
        }
        if self.content_redacted {
            map.insert("content_redacted".to_string(), Value::Bool(true));
        }
        Value::Object(map)
    }
}

fn project_line_from_turn(
    row: &ProjectRoleTurnRow,
    thread: &ProjectRoleThreadRow,
    include_content: bool,
) -> Result<ProjectRoleTranscriptLine, String> {
    let metadata = role_metadata_value(row)?;
    if let Some(project_id) = metadata
        .as_ref()
        .and_then(|value| value.get("project_id"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        if project_id != thread.project_id {
            return Err("role_metadata_project_mismatch".to_string());
        }
    }
    let content_encrypted = row
        .content
        .trim_start()
        .starts_with(ENCRYPTED_RECORD_PREFIX);
    let content_redacted = include_content && content_encrypted;
    let content = if include_content && !content_encrypted {
        row.content.clone()
    } else {
        String::new()
    };
    Ok(ProjectRoleTranscriptLine {
        turn_id: row.turn_id.clone(),
        role: projected_role(row, metadata.as_ref()),
        content,
        turn_metadata: metadata,
        created_at_ms: row.created_at_ms.max(0),
        content_encrypted,
        content_redacted,
    })
}

fn role_metadata_value(row: &ProjectRoleTurnRow) -> Result<Option<Value>, String> {
    let raw = row.role_metadata_json.trim();
    if !raw.is_empty() {
        let mut value = serde_json::from_str::<Value>(raw)
            .map_err(|err| format!("invalid_role_metadata_json: {err}"))?;
        if !value.is_object() {
            return Ok(None);
        }
        ensure_metadata_schema(&mut value);
        return Ok(Some(value).filter(metadata_has_signal));
    }

    let mut map = Map::new();
    insert_string(
        &mut map,
        "client_message_id",
        row.client_message_id.as_str(),
    );
    insert_string(&mut map, "source_role", row.source_role.as_str());
    insert_string(&mut map, "target_role", row.target_role.as_str());
    insert_string(&mut map, "sender_role", row.source_role.as_str());
    insert_string(&mut map, "dispatch_id", row.dispatch_id.as_str());
    insert_string(&mut map, "dispatch_kind", row.dispatch_kind.as_str());
    insert_string(&mut map, "run_id", row.run_id.as_str());
    insert_string(&mut map, "launch_run_id", row.launch_run_id.as_str());
    insert_string(&mut map, "reviewer_note_id", row.reviewer_note_id.as_str());
    insert_string(&mut map, "status", row.status.as_str());
    if map.is_empty() {
        return Ok(None);
    }
    map.insert(
        "schema_version".to_string(),
        Value::String(ROLE_TURN_METADATA_SCHEMA.to_string()),
    );
    Ok(Some(Value::Object(map)))
}

fn ensure_metadata_schema(value: &mut Value) {
    if let Some(obj) = value.as_object_mut() {
        let schema = obj
            .get("schema_version")
            .and_then(Value::as_str)
            .map(str::trim)
            .unwrap_or("");
        if schema.is_empty() {
            obj.insert(
                "schema_version".to_string(),
                Value::String(ROLE_TURN_METADATA_SCHEMA.to_string()),
            );
        }
    }
}

fn projected_role(row: &ProjectRoleTurnRow, metadata: Option<&Value>) -> String {
    let source_role = metadata_string(metadata, "source_role");
    if SOURCE_ROLES.contains(&source_role.as_str()) {
        return source_role;
    }
    match row.role.trim().to_ascii_lowercase().as_str() {
        "assistant" => "coder".to_string(),
        "user" | "tool" | "system" => row.role.trim().to_ascii_lowercase(),
        other if !other.is_empty() => other.to_string(),
        _ => "user".to_string(),
    }
}

fn metadata_has_signal(value: &Value) -> bool {
    let Some(obj) = value.as_object() else {
        return false;
    };
    obj.iter().any(|(key, value)| {
        if key == "schema_version" {
            return false;
        }
        match value {
            Value::String(text) => !text.trim().is_empty(),
            Value::Array(items) => !items.is_empty(),
            Value::Number(number) => number.as_i64().unwrap_or(0) > 0,
            Value::Bool(flag) => *flag,
            Value::Object(map) => !map.is_empty(),
            Value::Null => false,
        }
    })
}

fn metadata_string(metadata: Option<&Value>, key: &str) -> String {
    metadata
        .and_then(|value| value.get(key))
        .and_then(Value::as_str)
        .map(|value| value.trim().to_ascii_lowercase())
        .filter(|value| !value.is_empty())
        .unwrap_or_default()
}

fn insert_string(map: &mut Map<String, Value>, key: &str, value: &str) {
    let trimmed = value.trim();
    if !trimmed.is_empty() {
        map.insert(key.to_string(), Value::String(trimmed.to_string()));
    }
}

fn now_ms_i64() -> i64 {
    now_ms().min(i64::MAX as u128) as i64
}

#[cfg(test)]
mod tests {
    use super::*;

    fn thread() -> ProjectRoleThreadRow {
        ProjectRoleThreadRow {
            thread_id: "thread-1".to_string(),
            thread_key: "xterminal_project_project-1".to_string(),
            device_id: "dev-1".to_string(),
            user_id: "user-1".to_string(),
            app_id: "x_terminal".to_string(),
            project_id: "project-1".to_string(),
        }
    }

    fn turn(role: &str, content: &str, metadata: Value, created_at_ms: i64) -> ProjectRoleTurnRow {
        ProjectRoleTurnRow {
            turn_id: format!("turn-{created_at_ms}"),
            thread_id: "thread-1".to_string(),
            request_id: "request-1".to_string(),
            role: role.to_string(),
            content: content.to_string(),
            created_at_ms,
            role_metadata_json: metadata.to_string(),
            client_message_id: String::new(),
            source_role: String::new(),
            target_role: String::new(),
            dispatch_id: String::new(),
            dispatch_kind: String::new(),
            run_id: String::new(),
            launch_run_id: String::new(),
            reviewer_note_id: String::new(),
            status: String::new(),
        }
    }

    #[test]
    fn projection_prefers_role_metadata_and_keeps_chronological_recent_lines() {
        let rows = ProjectRoleTranscriptRows {
            thread: Some(thread()),
            turns_newest_first: vec![
                turn(
                    "assistant",
                    "coder reply",
                    json!({
                        "schema_version": ROLE_TURN_METADATA_SCHEMA,
                        "source_role": "coder",
                        "target_role": "supervisor",
                        "project_id": "project-1",
                        "dispatch_id": "dispatch-1",
                        "dispatch_kind": "coder_reply",
                        "status": "completed"
                    }),
                    2,
                ),
                turn(
                    "user",
                    "supervisor dispatch",
                    json!({
                        "schema_version": ROLE_TURN_METADATA_SCHEMA,
                        "source_role": "supervisor",
                        "target_role": "coder",
                        "project_id": "project-1",
                        "dispatch_id": "dispatch-1",
                        "dispatch_kind": "supervisor_to_coder",
                        "status": "dispatched"
                    }),
                    1,
                ),
            ],
        };

        let value = projection_value_from_rows(rows, true).expect("projection should build");

        assert_eq!(
            value["schema_version"],
            PROJECT_ROLE_TRANSCRIPT_PROJECTION_SCHEMA
        );
        assert_eq!(value["status"], "latest_coder_reply_observed");
        assert_eq!(
            value["latest_supervisor_dispatch"]["turn_metadata"]["source_role"],
            "supervisor"
        );
        assert_eq!(value["latest_coder_reply"]["role"], "coder");
        assert_eq!(value["recent_lines"][0]["role"], "supervisor");
        assert_eq!(value["recent_lines"][1]["role"], "coder");
        assert_eq!(value["recent_lines"][1]["content"], "coder reply");
    }

    #[test]
    fn projection_redacts_encrypted_content_without_losing_metadata() {
        let rows = ProjectRoleTranscriptRows {
            thread: Some(thread()),
            turns_newest_first: vec![turn(
                "system",
                "xhubenc:v1:{sealed}",
                json!({
                    "schema_version": ROLE_TURN_METADATA_SCHEMA,
                    "source_role": "hub",
                    "target_role": "all",
                    "project_id": "project-1",
                    "dispatch_kind": "heartbeat",
                    "status": "observed"
                }),
                3,
            )],
        };

        let value = projection_value_from_rows(rows, true).expect("projection should build");

        assert_eq!(value["recent_lines"][0]["role"], "hub");
        assert_eq!(value["recent_lines"][0]["content"], "");
        assert_eq!(value["recent_lines"][0]["content_encrypted"], true);
        assert_eq!(
            value["recent_lines"][0]["turn_metadata"]["dispatch_kind"],
            "heartbeat"
        );
    }

    #[test]
    fn projection_fails_closed_on_metadata_project_mismatch() {
        let rows = ProjectRoleTranscriptRows {
            thread: Some(thread()),
            turns_newest_first: vec![turn(
                "user",
                "mismatch",
                json!({
                    "schema_version": ROLE_TURN_METADATA_SCHEMA,
                    "source_role": "supervisor",
                    "project_id": "project-2",
                    "dispatch_kind": "supervisor_to_coder"
                }),
                4,
            )],
        };

        let err = projection_value_from_rows(rows, true).expect_err("mismatch should fail");
        assert_eq!(err, "role_metadata_project_mismatch");
    }
}
