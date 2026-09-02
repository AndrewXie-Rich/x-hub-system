use std::path::Path;

use rusqlite::{params, Connection, OpenFlags, OptionalExtension};

#[derive(Debug, Clone)]
pub struct Migration {
    pub id: &'static str,
    pub file_name: &'static str,
    pub description: &'static str,
    pub sql: &'static str,
}

pub fn baseline_migrations() -> Vec<Migration> {
    vec![
        Migration {
            id: "0001",
            file_name: "0001_runtime_baseline.sql",
            description: "Rust Hub shadow metadata tables",
            sql: include_str!("../../../migrations/0001_runtime_baseline.sql"),
        },
        Migration {
            id: "0002",
            file_name: "0002_scheduler_truth.sql",
            description: "Rust Hub scheduler truth tables",
            sql: include_str!("../../../migrations/0002_scheduler_truth.sql"),
        },
        Migration {
            id: "0003",
            file_name: "0003_shadow_compare_reports.sql",
            description: "Rust Hub shadow-compare evidence reports",
            sql: include_str!("../../../migrations/0003_shadow_compare_reports.sql"),
        },
        Migration {
            id: "0004",
            file_name: "0004_skill_policy.sql",
            description: "Rust Hub skill policy pin/grant/audit tables",
            sql: include_str!("../../../migrations/0004_skill_policy.sql"),
        },
        Migration {
            id: "0005",
            file_name: "0005_skill_policy_events.sql",
            description: "Rust Hub skill policy change event tables",
            sql: include_str!("../../../migrations/0005_skill_policy_events.sql"),
        },
        Migration {
            id: "0006",
            file_name: "0006_evidence_ledger.sql",
            description: "Rust Hub unified evidence ledger",
            sql: include_str!("../../../migrations/0006_evidence_ledger.sql"),
        },
        Migration {
            id: "0007",
            file_name: "0007_memory_objects.sql",
            description: "Rust Hub universal memory object store",
            sql: include_str!("../../../migrations/0007_memory_objects.sql"),
        },
        Migration {
            id: "0008",
            file_name: "0008_memory_object_index.sql",
            description: "Rust Hub derived memory object retrieval index",
            sql: include_str!("../../../migrations/0008_memory_object_index.sql"),
        },
        Migration {
            id: "0009",
            file_name: "0009_memory_object_index_chunks.sql",
            description: "Rust Hub chunked memory object retrieval index",
            sql: include_str!("../../../migrations/0009_memory_object_index_chunks.sql"),
        },
    ]
}

pub fn recommended_sqlite_pragmas() -> &'static [&'static str] {
    &[
        "PRAGMA journal_mode = WAL",
        "PRAGMA synchronous = NORMAL",
        "PRAGMA busy_timeout = 2000",
        "PRAGMA foreign_keys = ON",
    ]
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MigrationReport {
    pub migration_id: String,
    pub file_name: String,
    pub applied: bool,
}

pub fn apply_baseline_migrations(db_path: &Path) -> Result<Vec<MigrationReport>, rusqlite::Error> {
    if let Some(parent) = db_path.parent() {
        std::fs::create_dir_all(parent).map_err(|err| {
            rusqlite::Error::ToSqlConversionFailure(Box::new(std::io::Error::new(
                err.kind(),
                format!("create db dir failed: {err}"),
            )))
        })?;
    }

    let mut conn = Connection::open(db_path)?;
    conn.execute_batch(
        "PRAGMA journal_mode = WAL;
         PRAGMA synchronous = NORMAL;
         PRAGMA busy_timeout = 2000;
         PRAGMA foreign_keys = ON;",
    )?;
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS rust_hub_schema_migrations (
           migration_id TEXT PRIMARY KEY,
           file_name TEXT NOT NULL,
           description TEXT NOT NULL,
           applied_at_ms INTEGER NOT NULL
         );",
    )?;

    let mut reports = Vec::new();
    for migration in baseline_migrations() {
        let already_applied: Option<String> = conn
            .query_row(
                "SELECT migration_id FROM rust_hub_schema_migrations WHERE migration_id = ?1",
                params![migration.id],
                |row| row.get(0),
            )
            .optional()?;

        if already_applied.is_some() {
            reports.push(MigrationReport {
                migration_id: migration.id.to_string(),
                file_name: migration.file_name.to_string(),
                applied: false,
            });
            continue;
        }

        let tx = conn.transaction()?;
        tx.execute_batch(migration.sql)?;
        let inserted = tx.execute(
            "INSERT OR IGNORE INTO rust_hub_schema_migrations
             (migration_id, file_name, description, applied_at_ms)
             VALUES (?1, ?2, ?3, unixepoch('subsec') * 1000)",
            params![migration.id, migration.file_name, migration.description],
        )?;
        tx.commit()?;

        reports.push(MigrationReport {
            migration_id: migration.id.to_string(),
            file_name: migration.file_name.to_string(),
            applied: inserted > 0,
        });
    }

    Ok(reports)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SchedulerSnapshotRow {
    pub created_at_ms: i64,
    pub in_flight_total: i32,
    pub queue_depth: i32,
    pub detail_json: String,
}

pub fn read_latest_scheduler_snapshot(
    db_path: &Path,
) -> Result<Option<SchedulerSnapshotRow>, rusqlite::Error> {
    if !db_path.is_file() {
        return Ok(None);
    }

    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    let mut stmt = match conn.prepare(
        "SELECT created_at_ms, in_flight_total, queue_depth, COALESCE(detail_json, '')
         FROM rust_hub_scheduler_snapshots
         ORDER BY created_at_ms DESC
         LIMIT 1",
    ) {
        Ok(stmt) => stmt,
        Err(rusqlite::Error::SqliteFailure(_, Some(message)))
            if message.contains("no such table") =>
        {
            return Ok(None);
        }
        Err(err) => return Err(err),
    };

    let mut rows = stmt.query([])?;
    if let Some(row) = rows.next()? {
        return Ok(Some(SchedulerSnapshotRow {
            created_at_ms: row.get(0)?,
            in_flight_total: row.get(1)?,
            queue_depth: row.get(2)?,
            detail_json: row.get(3)?,
        }));
    }

    Ok(None)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProjectRoleThreadRow {
    pub thread_id: String,
    pub thread_key: String,
    pub device_id: String,
    pub user_id: String,
    pub app_id: String,
    pub project_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProjectRoleTurnRow {
    pub turn_id: String,
    pub thread_id: String,
    pub request_id: String,
    pub role: String,
    pub content: String,
    pub created_at_ms: i64,
    pub role_metadata_json: String,
    pub client_message_id: String,
    pub source_role: String,
    pub target_role: String,
    pub dispatch_id: String,
    pub dispatch_kind: String,
    pub run_id: String,
    pub launch_run_id: String,
    pub reviewer_note_id: String,
    pub status: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProjectRoleTranscriptRows {
    pub thread: Option<ProjectRoleThreadRow>,
    pub turns_newest_first: Vec<ProjectRoleTurnRow>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProjectRoleTranscriptQuery {
    pub device_id: Option<String>,
    pub app_id: Option<String>,
    pub project_id: String,
    pub thread_key: String,
    pub limit: usize,
}

pub fn read_project_role_transcript_rows(
    db_path: &Path,
    query: ProjectRoleTranscriptQuery,
) -> Result<ProjectRoleTranscriptRows, rusqlite::Error> {
    if !db_path.is_file() {
        return Ok(ProjectRoleTranscriptRows {
            thread: None,
            turns_newest_first: Vec::new(),
        });
    }

    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    conn.execute_batch("PRAGMA busy_timeout = 2000;")?;
    let thread = match find_project_role_thread_row(&conn, &query) {
        Ok(thread) => thread,
        Err(err) if sqlite_missing_schema(&err) => None,
        Err(err) => return Err(err),
    };
    let Some(thread) = thread else {
        return Ok(ProjectRoleTranscriptRows {
            thread: None,
            turns_newest_first: Vec::new(),
        });
    };
    let turns_newest_first = match list_project_role_turn_rows(
        &conn,
        thread.thread_id.as_str(),
        query.limit.clamp(1, 500),
        true,
    ) {
        Ok(rows) => rows,
        Err(err) if sqlite_missing_schema(&err) => {
            list_project_role_turn_rows(&conn, thread.thread_id.as_str(), query.limit, false)?
        }
        Err(err) => return Err(err),
    };
    Ok(ProjectRoleTranscriptRows {
        thread: Some(thread),
        turns_newest_first,
    })
}

fn find_project_role_thread_row(
    conn: &Connection,
    query: &ProjectRoleTranscriptQuery,
) -> Result<Option<ProjectRoleThreadRow>, rusqlite::Error> {
    let project_id = query.project_id.trim();
    let thread_key = query.thread_key.trim();
    let device_id = query.device_id.as_deref().unwrap_or("").trim();
    let app_id = query.app_id.as_deref().unwrap_or("").trim();
    if project_id.is_empty() || thread_key.is_empty() {
        return Ok(None);
    }

    if !device_id.is_empty() && !app_id.is_empty() {
        return conn
            .query_row(
                "SELECT thread_id, thread_key, device_id, user_id, app_id, project_id
                 FROM threads
                 WHERE device_id = ?1 AND app_id = ?2 AND project_id = ?3 AND thread_key = ?4
                 ORDER BY updated_at_ms DESC
                 LIMIT 1",
                params![device_id, app_id, project_id, thread_key],
                project_role_thread_from_sql,
            )
            .optional();
    }
    if !device_id.is_empty() {
        return conn
            .query_row(
                "SELECT thread_id, thread_key, device_id, user_id, app_id, project_id
                 FROM threads
                 WHERE device_id = ?1 AND project_id = ?2 AND thread_key = ?3
                 ORDER BY updated_at_ms DESC
                 LIMIT 1",
                params![device_id, project_id, thread_key],
                project_role_thread_from_sql,
            )
            .optional();
    }
    if !app_id.is_empty() {
        return conn
            .query_row(
                "SELECT thread_id, thread_key, device_id, user_id, app_id, project_id
                 FROM threads
                 WHERE app_id = ?1 AND project_id = ?2 AND thread_key = ?3
                 ORDER BY updated_at_ms DESC
                 LIMIT 1",
                params![app_id, project_id, thread_key],
                project_role_thread_from_sql,
            )
            .optional();
    }
    conn.query_row(
        "SELECT thread_id, thread_key, device_id, user_id, app_id, project_id
         FROM threads
         WHERE project_id = ?1 AND thread_key = ?2
         ORDER BY updated_at_ms DESC
         LIMIT 1",
        params![project_id, thread_key],
        project_role_thread_from_sql,
    )
    .optional()
}

fn list_project_role_turn_rows(
    conn: &Connection,
    thread_id: &str,
    limit: usize,
    include_role_metadata_columns: bool,
) -> Result<Vec<ProjectRoleTurnRow>, rusqlite::Error> {
    if include_role_metadata_columns {
        let mut stmt = conn.prepare(
            "SELECT turn_id, thread_id, COALESCE(request_id, ''), role, content, created_at_ms,
                    COALESCE(role_metadata_json, ''), COALESCE(client_message_id, ''),
                    COALESCE(source_role, ''), COALESCE(target_role, ''),
                    COALESCE(dispatch_id, ''), COALESCE(dispatch_kind, ''),
                    COALESCE(run_id, ''), COALESCE(launch_run_id, ''),
                    COALESCE(reviewer_note_id, ''), COALESCE(status, '')
             FROM turns
             WHERE thread_id = ?1
             ORDER BY created_at_ms DESC
             LIMIT ?2",
        )?;
        let iter = stmt.query_map(params![thread_id, limit as i64], project_role_turn_from_sql)?;
        return iter.collect();
    }

    let mut stmt = conn.prepare(
        "SELECT turn_id, thread_id, COALESCE(request_id, ''), role, content, created_at_ms
         FROM turns
         WHERE thread_id = ?1
         ORDER BY created_at_ms DESC
         LIMIT ?2",
    )?;
    let iter = stmt.query_map(params![thread_id, limit as i64], |row| {
        Ok(ProjectRoleTurnRow {
            turn_id: row.get(0)?,
            thread_id: row.get(1)?,
            request_id: row.get(2)?,
            role: row.get(3)?,
            content: row.get(4)?,
            created_at_ms: row.get(5)?,
            role_metadata_json: String::new(),
            client_message_id: String::new(),
            source_role: String::new(),
            target_role: String::new(),
            dispatch_id: String::new(),
            dispatch_kind: String::new(),
            run_id: String::new(),
            launch_run_id: String::new(),
            reviewer_note_id: String::new(),
            status: String::new(),
        })
    })?;
    iter.collect()
}

fn project_role_thread_from_sql(
    row: &rusqlite::Row<'_>,
) -> Result<ProjectRoleThreadRow, rusqlite::Error> {
    Ok(ProjectRoleThreadRow {
        thread_id: row.get(0)?,
        thread_key: row.get(1)?,
        device_id: row.get(2)?,
        user_id: row.get(3)?,
        app_id: row.get(4)?,
        project_id: row.get(5)?,
    })
}

fn project_role_turn_from_sql(
    row: &rusqlite::Row<'_>,
) -> Result<ProjectRoleTurnRow, rusqlite::Error> {
    Ok(ProjectRoleTurnRow {
        turn_id: row.get(0)?,
        thread_id: row.get(1)?,
        request_id: row.get(2)?,
        role: row.get(3)?,
        content: row.get(4)?,
        created_at_ms: row.get(5)?,
        role_metadata_json: row.get(6)?,
        client_message_id: row.get(7)?,
        source_role: row.get(8)?,
        target_role: row.get(9)?,
        dispatch_id: row.get(10)?,
        dispatch_kind: row.get(11)?,
        run_id: row.get(12)?,
        launch_run_id: row.get(13)?,
        reviewer_note_id: row.get(14)?,
        status: row.get(15)?,
    })
}

fn sqlite_missing_schema(err: &rusqlite::Error) -> bool {
    match err {
        rusqlite::Error::SqliteFailure(_, Some(message)) => {
            message.contains("no such table") || message.contains("no such column")
        }
        _ => false,
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShadowCompareReport {
    pub report_id: String,
    pub component: String,
    pub compared_at_ms: i64,
    pub match_result: String,
    pub rust_status_json: String,
    pub node_status_json: String,
    pub mismatch_json: String,
}

pub fn write_shadow_compare_report(
    db_path: &Path,
    report: &ShadowCompareReport,
) -> Result<(), rusqlite::Error> {
    if let Some(parent) = db_path.parent() {
        std::fs::create_dir_all(parent).map_err(|err| {
            rusqlite::Error::ToSqlConversionFailure(Box::new(std::io::Error::new(
                err.kind(),
                format!("create db dir failed: {err}"),
            )))
        })?;
    }

    let conn = Connection::open(db_path)?;
    conn.execute_batch(
        "PRAGMA journal_mode = WAL;
         PRAGMA synchronous = NORMAL;
         PRAGMA busy_timeout = 2000;
         PRAGMA foreign_keys = ON;",
    )?;
    conn.execute(
        "INSERT INTO rust_hub_shadow_compare_reports
         (report_id, component, compared_at_ms, match_result,
          rust_status_json, node_status_json, mismatch_json)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![
            report.report_id,
            report.component,
            report.compared_at_ms,
            report.match_result,
            report.rust_status_json,
            report.node_status_json,
            report.mismatch_json,
        ],
    )?;
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShadowCompareReportRow {
    pub report_id: String,
    pub component: String,
    pub compared_at_ms: i64,
    pub match_result: String,
    pub mismatch_json: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShadowCompareReportSummary {
    pub component: String,
    pub total: i64,
    pub matched: i64,
    pub mismatched: i64,
    pub latest_compared_at_ms: i64,
    pub rows: Vec<ShadowCompareReportRow>,
}

pub fn read_shadow_compare_report_summary(
    db_path: &Path,
    component: &str,
    limit: usize,
) -> Result<ShadowCompareReportSummary, rusqlite::Error> {
    let component = component.trim();
    if !db_path.is_file() {
        return Ok(empty_shadow_compare_summary(component));
    }

    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;

    let totals = conn
        .query_row(
            "SELECT
               COUNT(*) AS total,
               COALESCE(SUM(CASE WHEN match_result = 'match' THEN 1 ELSE 0 END), 0) AS matched,
               COALESCE(SUM(CASE WHEN match_result <> 'match' THEN 1 ELSE 0 END), 0) AS mismatched,
               COALESCE(MAX(compared_at_ms), 0) AS latest_compared_at_ms
             FROM rust_hub_shadow_compare_reports
             WHERE component = ?1",
            params![component],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, i64>(3)?,
                ))
            },
        )
        .optional();

    let (total, matched, mismatched, latest_compared_at_ms) = match totals {
        Ok(Some(value)) => value,
        Ok(None) => (0, 0, 0, 0),
        Err(rusqlite::Error::SqliteFailure(_, Some(message)))
            if message.contains("no such table") =>
        {
            return Ok(empty_shadow_compare_summary(component));
        }
        Err(err) => return Err(err),
    };

    let mut stmt = conn.prepare(
        "SELECT report_id, component, compared_at_ms, match_result, mismatch_json
         FROM rust_hub_shadow_compare_reports
         WHERE component = ?1
         ORDER BY compared_at_ms DESC
         LIMIT ?2",
    )?;
    let rows_iter = stmt.query_map(params![component, limit.clamp(1, 500) as i64], |row| {
        Ok(ShadowCompareReportRow {
            report_id: row.get(0)?,
            component: row.get(1)?,
            compared_at_ms: row.get(2)?,
            match_result: row.get(3)?,
            mismatch_json: row.get(4)?,
        })
    })?;
    let mut rows = Vec::new();
    for row in rows_iter {
        rows.push(row?);
    }

    Ok(ShadowCompareReportSummary {
        component: component.to_string(),
        total,
        matched,
        mismatched,
        latest_compared_at_ms,
        rows,
    })
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillPinRecord {
    pub scope_key: String,
    pub skill_id: String,
    pub pinned_by: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillGrantRecord {
    pub scope_key: String,
    pub skill_id: String,
    pub capability: String,
    pub granted_by: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillPolicyBinding {
    pub scope_key: String,
    pub skill_id: String,
    pub pinned: bool,
    pub granted_capabilities: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillPreflightAuditRecord {
    pub event_id: String,
    pub scope_key: String,
    pub request_id: String,
    pub audit_ref: String,
    pub skill_id: String,
    pub decision: String,
    pub ok: bool,
    pub reason_json: String,
    pub detail_json: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillPreflightAuditRow {
    pub event_id: String,
    pub created_at_ms: i64,
    pub scope_key: String,
    pub request_id: String,
    pub audit_ref: String,
    pub skill_id: String,
    pub decision: String,
    pub ok: bool,
    pub reason_json: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillPreflightAuditSummary {
    pub scope_key: Option<String>,
    pub skill_id: Option<String>,
    pub total: i64,
    pub allowed: i64,
    pub denied: i64,
    pub latest_created_at_ms: i64,
    pub rows: Vec<SkillPreflightAuditRow>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillPreflightAuditPruneReport {
    pub max_rows: i64,
    pub deleted_rows: i64,
    pub remaining_rows: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillPolicyRevocationReport {
    pub scope_key: String,
    pub skill_id: String,
    pub capability: Option<String>,
    pub revoked_rows: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillPolicyEventRecord {
    pub event_id: String,
    pub operation: String,
    pub scope_key: String,
    pub skill_id: String,
    pub capability: Option<String>,
    pub actor: String,
    pub result: String,
    pub detail_json: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillPolicyEventRow {
    pub event_id: String,
    pub created_at_ms: i64,
    pub operation: String,
    pub scope_key: String,
    pub skill_id: String,
    pub capability: Option<String>,
    pub actor: String,
    pub result: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillPolicyEventSummary {
    pub scope_key: Option<String>,
    pub skill_id: Option<String>,
    pub total: i64,
    pub latest_created_at_ms: i64,
    pub rows: Vec<SkillPolicyEventRow>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillPolicyEventPruneReport {
    pub max_rows: i64,
    pub deleted_rows: i64,
    pub remaining_rows: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillPolicyStoreSummary {
    pub active_pin_count: i64,
    pub active_grant_count: i64,
    pub preflight_audit_count: i64,
    pub policy_event_count: i64,
    pub latest_preflight_audit_ms: i64,
    pub latest_policy_event_ms: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EvidenceLedgerRecord {
    pub evidence_id: String,
    pub created_at_ms: i64,
    pub component: String,
    pub authority_mode: String,
    pub project_id: Option<String>,
    pub run_id: Option<String>,
    pub output_verdict: String,
    pub reason_json: String,
    pub parent_evidence_json: String,
    pub input_ref_json: String,
    pub payload_json: String,
    pub expires_at_ms: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EvidenceLedgerRow {
    pub evidence_id: String,
    pub created_at_ms: i64,
    pub component: String,
    pub authority_mode: String,
    pub project_id: Option<String>,
    pub run_id: Option<String>,
    pub output_verdict: String,
    pub reason_json: String,
    pub parent_evidence_json: String,
    pub input_ref_json: String,
    pub payload_json: String,
    pub expires_at_ms: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EvidenceLedgerSummary {
    pub component: Option<String>,
    pub project_id: Option<String>,
    pub run_id: Option<String>,
    pub total: i64,
    pub latest_created_at_ms: i64,
    pub rows: Vec<EvidenceLedgerRow>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MemoryObjectRecord {
    pub memory_id: String,
    pub schema_version: String,
    pub scope: String,
    pub owner_id: String,
    pub run_id: Option<String>,
    pub project_id: Option<String>,
    pub agent_id: Option<String>,
    pub source_kind: String,
    pub layer: String,
    pub title: String,
    pub text: String,
    pub summary: String,
    pub tags_json: String,
    pub sensitivity: String,
    pub visibility: String,
    pub status: String,
    pub pinned: bool,
    pub immutable: bool,
    pub ttl_ms: Option<i64>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub last_accessed_at_ms: i64,
    pub version: i64,
    pub provenance_json: String,
    pub policy_json: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MemoryEventRecord {
    pub event_id: String,
    pub memory_id: String,
    pub operation: String,
    pub actor: String,
    pub reason: String,
    pub before_version: Option<i64>,
    pub after_version: Option<i64>,
    pub before_json: Option<String>,
    pub after_json: Option<String>,
    pub policy_decision: String,
    pub deny_code: String,
    pub audit_ref: String,
    pub created_at_ms: i64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct MemoryObjectListFilter {
    pub scope: Option<String>,
    pub owner_id: Option<String>,
    pub project_id: Option<String>,
    pub agent_id: Option<String>,
    pub source_kind: Option<String>,
    pub layer: Option<String>,
    pub status: Option<String>,
    pub sensitivity: Option<String>,
    pub visibility: Option<String>,
    pub limit: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MemoryObjectStoreSummary {
    pub object_count: i64,
    pub active_object_count: i64,
    pub candidate_object_count: i64,
    pub deleted_tombstone_count: i64,
    pub event_count: i64,
    pub latest_object_updated_at_ms: i64,
    pub latest_event_created_at_ms: i64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct MemoryObjectIndexFilter {
    pub scope: Option<String>,
    pub owner_id: Option<String>,
    pub project_id: Option<String>,
    pub agent_id: Option<String>,
    pub source_kind: Option<String>,
    pub layer: Option<String>,
    pub sensitivity: Option<String>,
    pub visibility: Option<String>,
    pub limit: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MemoryObjectIndexRecord {
    pub memory_id: String,
    pub chunk_id: String,
    pub chunk_ordinal: i64,
    pub chunk_start_line: i64,
    pub chunk_end_line: i64,
    pub object_version: i64,
    pub object_created_at_ms: i64,
    pub object_updated_at_ms: i64,
    pub scope: String,
    pub owner_id: String,
    pub run_id: Option<String>,
    pub project_id: Option<String>,
    pub agent_id: Option<String>,
    pub source_kind: String,
    pub layer: String,
    pub title: String,
    pub summary: String,
    pub text: String,
    pub searchable_text: String,
    pub content_hash: String,
    pub sensitivity: String,
    pub visibility: String,
    pub pinned: bool,
    pub has_code: bool,
    pub has_todo: bool,
    pub has_error: bool,
    pub has_decision: bool,
    pub has_approval: bool,
    pub has_blocker: bool,
    pub has_link: bool,
    pub indexed_at_ms: i64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct MemoryObjectIndexSummary {
    pub index_ready: bool,
    pub index_row_count: i64,
    pub active_indexable_object_count: i64,
    pub stale_index_count: i64,
    pub latest_indexed_at_ms: i64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct MemoryObjectIndexRebuildReport {
    pub schema_version: String,
    pub rebuilt: bool,
    pub indexed_count: i64,
    pub skipped_secret_count: i64,
    pub skipped_inactive_count: i64,
    pub stale_before_count: i64,
    pub stale_after_count: i64,
    pub generated_at_ms: i64,
}

pub fn upsert_skill_pin(db_path: &Path, record: &SkillPinRecord) -> Result<(), rusqlite::Error> {
    let conn = open_rw_with_pragmas(db_path)?;
    conn.execute(
        "INSERT INTO rust_hub_skill_pins
         (scope_key, skill_id, pinned_by, pinned_at_ms, revoked_at_ms)
         VALUES (?1, ?2, ?3, unixepoch('subsec') * 1000, 0)
         ON CONFLICT(scope_key, skill_id) DO UPDATE SET
           pinned_by = excluded.pinned_by,
           pinned_at_ms = excluded.pinned_at_ms,
           revoked_at_ms = 0",
        params![record.scope_key, record.skill_id, record.pinned_by],
    )?;
    Ok(())
}

pub fn revoke_skill_pin(
    db_path: &Path,
    scope_key: &str,
    skill_id: &str,
) -> Result<SkillPolicyRevocationReport, rusqlite::Error> {
    let conn = open_rw_with_pragmas(db_path)?;
    let revoked_rows = conn.execute(
        "UPDATE rust_hub_skill_pins
         SET revoked_at_ms = unixepoch('subsec') * 1000
         WHERE scope_key = ?1 AND skill_id = ?2 AND revoked_at_ms = 0",
        params![scope_key, skill_id],
    )? as i64;
    Ok(SkillPolicyRevocationReport {
        scope_key: scope_key.to_string(),
        skill_id: skill_id.to_string(),
        capability: None,
        revoked_rows,
    })
}

pub fn upsert_skill_grant(
    db_path: &Path,
    record: &SkillGrantRecord,
) -> Result<(), rusqlite::Error> {
    let conn = open_rw_with_pragmas(db_path)?;
    conn.execute(
        "INSERT INTO rust_hub_skill_capability_grants
         (scope_key, skill_id, capability, granted_by, granted_at_ms, revoked_at_ms)
         VALUES (?1, ?2, ?3, ?4, unixepoch('subsec') * 1000, 0)
         ON CONFLICT(scope_key, skill_id, capability) DO UPDATE SET
           granted_by = excluded.granted_by,
           granted_at_ms = excluded.granted_at_ms,
           revoked_at_ms = 0",
        params![
            record.scope_key,
            record.skill_id,
            record.capability,
            record.granted_by
        ],
    )?;
    Ok(())
}

pub fn revoke_skill_grant(
    db_path: &Path,
    scope_key: &str,
    skill_id: &str,
    capability: &str,
) -> Result<SkillPolicyRevocationReport, rusqlite::Error> {
    let conn = open_rw_with_pragmas(db_path)?;
    let revoked_rows = conn.execute(
        "UPDATE rust_hub_skill_capability_grants
         SET revoked_at_ms = unixepoch('subsec') * 1000
         WHERE scope_key = ?1 AND skill_id = ?2 AND capability = ?3 AND revoked_at_ms = 0",
        params![scope_key, skill_id, capability],
    )? as i64;
    Ok(SkillPolicyRevocationReport {
        scope_key: scope_key.to_string(),
        skill_id: skill_id.to_string(),
        capability: Some(capability.to_string()),
        revoked_rows,
    })
}

pub fn read_skill_policy_binding(
    db_path: &Path,
    scope_key: &str,
    skill_id: &str,
) -> Result<SkillPolicyBinding, rusqlite::Error> {
    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    conn.execute_batch("PRAGMA busy_timeout = 2000;")?;
    let pinned = match conn
        .query_row(
            "SELECT 1
             FROM rust_hub_skill_pins
             WHERE scope_key = ?1 AND skill_id = ?2 AND revoked_at_ms = 0
             LIMIT 1",
            params![scope_key, skill_id],
            |_| Ok(true),
        )
        .optional()
    {
        Ok(Some(value)) => value,
        Ok(None) => false,
        Err(rusqlite::Error::SqliteFailure(_, Some(message)))
            if message.contains("no such table") =>
        {
            false
        }
        Err(err) => return Err(err),
    };

    let mut granted_capabilities = Vec::new();
    let mut stmt = match conn.prepare(
        "SELECT capability
         FROM rust_hub_skill_capability_grants
         WHERE scope_key = ?1 AND skill_id = ?2 AND revoked_at_ms = 0
         ORDER BY capability",
    ) {
        Ok(stmt) => stmt,
        Err(rusqlite::Error::SqliteFailure(_, Some(message)))
            if message.contains("no such table") =>
        {
            return Ok(SkillPolicyBinding {
                scope_key: scope_key.to_string(),
                skill_id: skill_id.to_string(),
                pinned,
                granted_capabilities,
            });
        }
        Err(err) => return Err(err),
    };
    let rows = stmt.query_map(params![scope_key, skill_id], |row| row.get::<_, String>(0))?;
    for row in rows {
        granted_capabilities.push(row?);
    }
    Ok(SkillPolicyBinding {
        scope_key: scope_key.to_string(),
        skill_id: skill_id.to_string(),
        pinned,
        granted_capabilities,
    })
}

pub fn read_skill_policy_store_summary(
    db_path: &Path,
) -> Result<SkillPolicyStoreSummary, rusqlite::Error> {
    if !db_path.is_file() {
        return Ok(SkillPolicyStoreSummary::default());
    }

    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    conn.execute_batch("PRAGMA busy_timeout = 2000;")?;

    Ok(SkillPolicyStoreSummary {
        active_pin_count: query_i64_or_zero(
            &conn,
            "SELECT COUNT(*) FROM rust_hub_skill_pins WHERE revoked_at_ms = 0",
        )?,
        active_grant_count: query_i64_or_zero(
            &conn,
            "SELECT COUNT(*) FROM rust_hub_skill_capability_grants WHERE revoked_at_ms = 0",
        )?,
        preflight_audit_count: query_i64_or_zero(
            &conn,
            "SELECT COUNT(*) FROM rust_hub_skill_preflight_audit",
        )?,
        policy_event_count: query_i64_or_zero(
            &conn,
            "SELECT COUNT(*) FROM rust_hub_skill_policy_events",
        )?,
        latest_preflight_audit_ms: query_i64_or_zero(
            &conn,
            "SELECT COALESCE(MAX(created_at_ms), 0) FROM rust_hub_skill_preflight_audit",
        )?,
        latest_policy_event_ms: query_i64_or_zero(
            &conn,
            "SELECT COALESCE(MAX(created_at_ms), 0) FROM rust_hub_skill_policy_events",
        )?,
    })
}

pub fn write_skill_preflight_audit(
    db_path: &Path,
    record: &SkillPreflightAuditRecord,
) -> Result<(), rusqlite::Error> {
    let conn = open_rw_with_pragmas(db_path)?;
    conn.execute(
        "INSERT INTO rust_hub_skill_preflight_audit
         (event_id, created_at_ms, scope_key, request_id, audit_ref, skill_id,
          decision, ok, reason_json, detail_json)
         VALUES (?1, unixepoch('subsec') * 1000, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
        params![
            record.event_id,
            record.scope_key,
            record.request_id,
            record.audit_ref,
            record.skill_id,
            record.decision,
            if record.ok { 1 } else { 0 },
            record.reason_json,
            record.detail_json,
        ],
    )?;
    Ok(())
}

pub fn write_skill_policy_event(
    db_path: &Path,
    record: &SkillPolicyEventRecord,
) -> Result<(), rusqlite::Error> {
    let conn = open_rw_with_pragmas(db_path)?;
    conn.execute(
        "INSERT INTO rust_hub_skill_policy_events
         (event_id, created_at_ms, operation, scope_key, skill_id, capability,
          actor, result, detail_json)
         VALUES (?1, unixepoch('subsec') * 1000, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        params![
            record.event_id,
            record.operation,
            record.scope_key,
            record.skill_id,
            record.capability,
            record.actor,
            record.result,
            record.detail_json,
        ],
    )?;
    Ok(())
}

pub fn read_skill_policy_event_summary(
    db_path: &Path,
    scope_key: Option<&str>,
    skill_id: Option<&str>,
    limit: usize,
) -> Result<SkillPolicyEventSummary, rusqlite::Error> {
    let scope_key = normalize_optional_filter(scope_key);
    let skill_id = normalize_optional_filter(skill_id);
    if !db_path.is_file() {
        return Ok(empty_skill_policy_event_summary(scope_key, skill_id));
    }

    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    conn.execute_batch("PRAGMA busy_timeout = 2000;")?;

    let totals = match (scope_key.as_deref(), skill_id.as_deref()) {
        (Some(scope), Some(skill)) => conn
            .query_row(
                "SELECT COUNT(*), COALESCE(MAX(created_at_ms), 0)
                 FROM rust_hub_skill_policy_events
                 WHERE scope_key = ?1 AND skill_id = ?2",
                params![scope, skill],
                |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?)),
            )
            .optional(),
        (Some(scope), None) => conn
            .query_row(
                "SELECT COUNT(*), COALESCE(MAX(created_at_ms), 0)
                 FROM rust_hub_skill_policy_events
                 WHERE scope_key = ?1",
                params![scope],
                |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?)),
            )
            .optional(),
        (None, Some(skill)) => conn
            .query_row(
                "SELECT COUNT(*), COALESCE(MAX(created_at_ms), 0)
                 FROM rust_hub_skill_policy_events
                 WHERE skill_id = ?1",
                params![skill],
                |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?)),
            )
            .optional(),
        (None, None) => conn
            .query_row(
                "SELECT COUNT(*), COALESCE(MAX(created_at_ms), 0)
                 FROM rust_hub_skill_policy_events",
                [],
                |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?)),
            )
            .optional(),
    };

    let (total, latest_created_at_ms) = match totals {
        Ok(Some(value)) => value,
        Ok(None) => (0, 0),
        Err(err) if is_no_such_table(&err) => {
            return Ok(empty_skill_policy_event_summary(scope_key, skill_id));
        }
        Err(err) => return Err(err),
    };

    let limit = limit.clamp(1, 500) as i64;
    let mut rows = Vec::new();
    match (scope_key.as_deref(), skill_id.as_deref()) {
        (Some(scope), Some(skill)) => {
            let mut stmt = conn.prepare(
                "SELECT event_id, created_at_ms, operation, scope_key, skill_id,
                        capability, actor, result
                 FROM rust_hub_skill_policy_events
                 WHERE scope_key = ?1 AND skill_id = ?2
                 ORDER BY created_at_ms DESC, event_id DESC
                 LIMIT ?3",
            )?;
            let iter = stmt.query_map(params![scope, skill, limit], policy_event_row_from_sql)?;
            for row in iter {
                rows.push(row?);
            }
        }
        (Some(scope), None) => {
            let mut stmt = conn.prepare(
                "SELECT event_id, created_at_ms, operation, scope_key, skill_id,
                        capability, actor, result
                 FROM rust_hub_skill_policy_events
                 WHERE scope_key = ?1
                 ORDER BY created_at_ms DESC, event_id DESC
                 LIMIT ?2",
            )?;
            let iter = stmt.query_map(params![scope, limit], policy_event_row_from_sql)?;
            for row in iter {
                rows.push(row?);
            }
        }
        (None, Some(skill)) => {
            let mut stmt = conn.prepare(
                "SELECT event_id, created_at_ms, operation, scope_key, skill_id,
                        capability, actor, result
                 FROM rust_hub_skill_policy_events
                 WHERE skill_id = ?1
                 ORDER BY created_at_ms DESC, event_id DESC
                 LIMIT ?2",
            )?;
            let iter = stmt.query_map(params![skill, limit], policy_event_row_from_sql)?;
            for row in iter {
                rows.push(row?);
            }
        }
        (None, None) => {
            let mut stmt = conn.prepare(
                "SELECT event_id, created_at_ms, operation, scope_key, skill_id,
                        capability, actor, result
                 FROM rust_hub_skill_policy_events
                 ORDER BY created_at_ms DESC, event_id DESC
                 LIMIT ?1",
            )?;
            let iter = stmt.query_map(params![limit], policy_event_row_from_sql)?;
            for row in iter {
                rows.push(row?);
            }
        }
    }

    Ok(SkillPolicyEventSummary {
        scope_key,
        skill_id,
        total,
        latest_created_at_ms,
        rows,
    })
}

pub fn prune_skill_policy_events_by_max_rows(
    db_path: &Path,
    max_rows: usize,
) -> Result<SkillPolicyEventPruneReport, rusqlite::Error> {
    let max_rows = max_rows.clamp(1, 1_000_000) as i64;
    let conn = open_rw_with_pragmas(db_path)?;
    let existing = match conn.query_row(
        "SELECT COUNT(*) FROM rust_hub_skill_policy_events",
        [],
        |row| row.get::<_, i64>(0),
    ) {
        Ok(count) => count,
        Err(err) if is_no_such_table(&err) => {
            return Ok(SkillPolicyEventPruneReport {
                max_rows,
                deleted_rows: 0,
                remaining_rows: 0,
            });
        }
        Err(err) => return Err(err),
    };

    let deleted_rows = if existing > max_rows {
        conn.execute(
            "DELETE FROM rust_hub_skill_policy_events
             WHERE event_id NOT IN (
               SELECT event_id
               FROM rust_hub_skill_policy_events
               ORDER BY created_at_ms DESC, event_id DESC
               LIMIT ?1
             )",
            params![max_rows],
        )? as i64
    } else {
        0
    };
    let remaining_rows = conn.query_row(
        "SELECT COUNT(*) FROM rust_hub_skill_policy_events",
        [],
        |row| row.get::<_, i64>(0),
    )?;

    Ok(SkillPolicyEventPruneReport {
        max_rows,
        deleted_rows,
        remaining_rows,
    })
}

pub fn read_skill_preflight_audit_summary(
    db_path: &Path,
    scope_key: Option<&str>,
    skill_id: Option<&str>,
    limit: usize,
) -> Result<SkillPreflightAuditSummary, rusqlite::Error> {
    let scope_key = normalize_optional_filter(scope_key);
    let skill_id = normalize_optional_filter(skill_id);
    if !db_path.is_file() {
        return Ok(empty_skill_preflight_audit_summary(scope_key, skill_id));
    }

    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    conn.execute_batch("PRAGMA busy_timeout = 2000;")?;

    let totals = match (scope_key.as_deref(), skill_id.as_deref()) {
        (Some(scope), Some(skill)) => conn
            .query_row(
                "SELECT
                   COUNT(*),
                   COALESCE(SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END), 0),
                   COALESCE(SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END), 0),
                   COALESCE(MAX(created_at_ms), 0)
                 FROM rust_hub_skill_preflight_audit
                 WHERE scope_key = ?1 AND skill_id = ?2",
                params![scope, skill],
                |row| {
                    Ok((
                        row.get::<_, i64>(0)?,
                        row.get::<_, i64>(1)?,
                        row.get::<_, i64>(2)?,
                        row.get::<_, i64>(3)?,
                    ))
                },
            )
            .optional(),
        (Some(scope), None) => conn
            .query_row(
                "SELECT
                   COUNT(*),
                   COALESCE(SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END), 0),
                   COALESCE(SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END), 0),
                   COALESCE(MAX(created_at_ms), 0)
                 FROM rust_hub_skill_preflight_audit
                 WHERE scope_key = ?1",
                params![scope],
                |row| {
                    Ok((
                        row.get::<_, i64>(0)?,
                        row.get::<_, i64>(1)?,
                        row.get::<_, i64>(2)?,
                        row.get::<_, i64>(3)?,
                    ))
                },
            )
            .optional(),
        (None, Some(skill)) => conn
            .query_row(
                "SELECT
                   COUNT(*),
                   COALESCE(SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END), 0),
                   COALESCE(SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END), 0),
                   COALESCE(MAX(created_at_ms), 0)
                 FROM rust_hub_skill_preflight_audit
                 WHERE skill_id = ?1",
                params![skill],
                |row| {
                    Ok((
                        row.get::<_, i64>(0)?,
                        row.get::<_, i64>(1)?,
                        row.get::<_, i64>(2)?,
                        row.get::<_, i64>(3)?,
                    ))
                },
            )
            .optional(),
        (None, None) => conn
            .query_row(
                "SELECT
                   COUNT(*),
                   COALESCE(SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END), 0),
                   COALESCE(SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END), 0),
                   COALESCE(MAX(created_at_ms), 0)
                 FROM rust_hub_skill_preflight_audit",
                [],
                |row| {
                    Ok((
                        row.get::<_, i64>(0)?,
                        row.get::<_, i64>(1)?,
                        row.get::<_, i64>(2)?,
                        row.get::<_, i64>(3)?,
                    ))
                },
            )
            .optional(),
    };

    let (total, allowed, denied, latest_created_at_ms) = match totals {
        Ok(Some(value)) => value,
        Ok(None) => (0, 0, 0, 0),
        Err(err) if is_no_such_table(&err) => {
            return Ok(empty_skill_preflight_audit_summary(scope_key, skill_id));
        }
        Err(err) => return Err(err),
    };

    let limit = limit.clamp(1, 500) as i64;
    let mut rows = Vec::new();
    match (scope_key.as_deref(), skill_id.as_deref()) {
        (Some(scope), Some(skill)) => {
            let mut stmt = conn.prepare(
                "SELECT event_id, created_at_ms, scope_key, COALESCE(request_id, ''),
                        COALESCE(audit_ref, ''), skill_id, decision, ok, reason_json
                 FROM rust_hub_skill_preflight_audit
                 WHERE scope_key = ?1 AND skill_id = ?2
                 ORDER BY created_at_ms DESC, event_id DESC
                 LIMIT ?3",
            )?;
            let iter = stmt.query_map(params![scope, skill, limit], audit_row_from_sql)?;
            for row in iter {
                rows.push(row?);
            }
        }
        (Some(scope), None) => {
            let mut stmt = conn.prepare(
                "SELECT event_id, created_at_ms, scope_key, COALESCE(request_id, ''),
                        COALESCE(audit_ref, ''), skill_id, decision, ok, reason_json
                 FROM rust_hub_skill_preflight_audit
                 WHERE scope_key = ?1
                 ORDER BY created_at_ms DESC, event_id DESC
                 LIMIT ?2",
            )?;
            let iter = stmt.query_map(params![scope, limit], audit_row_from_sql)?;
            for row in iter {
                rows.push(row?);
            }
        }
        (None, Some(skill)) => {
            let mut stmt = conn.prepare(
                "SELECT event_id, created_at_ms, scope_key, COALESCE(request_id, ''),
                        COALESCE(audit_ref, ''), skill_id, decision, ok, reason_json
                 FROM rust_hub_skill_preflight_audit
                 WHERE skill_id = ?1
                 ORDER BY created_at_ms DESC, event_id DESC
                 LIMIT ?2",
            )?;
            let iter = stmt.query_map(params![skill, limit], audit_row_from_sql)?;
            for row in iter {
                rows.push(row?);
            }
        }
        (None, None) => {
            let mut stmt = conn.prepare(
                "SELECT event_id, created_at_ms, scope_key, COALESCE(request_id, ''),
                        COALESCE(audit_ref, ''), skill_id, decision, ok, reason_json
                 FROM rust_hub_skill_preflight_audit
                 ORDER BY created_at_ms DESC, event_id DESC
                 LIMIT ?1",
            )?;
            let iter = stmt.query_map(params![limit], audit_row_from_sql)?;
            for row in iter {
                rows.push(row?);
            }
        }
    }

    Ok(SkillPreflightAuditSummary {
        scope_key,
        skill_id,
        total,
        allowed,
        denied,
        latest_created_at_ms,
        rows,
    })
}

pub fn prune_skill_preflight_audit_by_max_rows(
    db_path: &Path,
    max_rows: usize,
) -> Result<SkillPreflightAuditPruneReport, rusqlite::Error> {
    let max_rows = max_rows.clamp(1, 1_000_000) as i64;
    let conn = open_rw_with_pragmas(db_path)?;
    let existing = match conn.query_row(
        "SELECT COUNT(*) FROM rust_hub_skill_preflight_audit",
        [],
        |row| row.get::<_, i64>(0),
    ) {
        Ok(count) => count,
        Err(err) if is_no_such_table(&err) => {
            return Ok(SkillPreflightAuditPruneReport {
                max_rows,
                deleted_rows: 0,
                remaining_rows: 0,
            });
        }
        Err(err) => return Err(err),
    };

    let deleted_rows = if existing > max_rows {
        conn.execute(
            "DELETE FROM rust_hub_skill_preflight_audit
             WHERE event_id NOT IN (
               SELECT event_id
               FROM rust_hub_skill_preflight_audit
               ORDER BY created_at_ms DESC, event_id DESC
               LIMIT ?1
             )",
            params![max_rows],
        )? as i64
    } else {
        0
    };
    let remaining_rows = conn.query_row(
        "SELECT COUNT(*) FROM rust_hub_skill_preflight_audit",
        [],
        |row| row.get::<_, i64>(0),
    )?;

    Ok(SkillPreflightAuditPruneReport {
        max_rows,
        deleted_rows,
        remaining_rows,
    })
}

pub fn write_evidence_record(
    db_path: &Path,
    record: &EvidenceLedgerRecord,
) -> Result<(), rusqlite::Error> {
    let conn = open_rw_with_pragmas(db_path)?;
    conn.execute(
        "INSERT INTO rust_hub_evidence_ledger
         (evidence_id, created_at_ms, component, authority_mode, project_id, run_id,
          output_verdict, reason_json, parent_evidence_json, input_ref_json, payload_json,
          expires_at_ms)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)",
        params![
            record.evidence_id,
            record.created_at_ms,
            record.component,
            record.authority_mode,
            record.project_id,
            record.run_id,
            record.output_verdict,
            record.reason_json,
            record.parent_evidence_json,
            record.input_ref_json,
            record.payload_json,
            record.expires_at_ms,
        ],
    )?;
    Ok(())
}

pub fn read_evidence_ledger_summary(
    db_path: &Path,
    component: Option<&str>,
    project_id: Option<&str>,
    run_id: Option<&str>,
    limit: usize,
) -> Result<EvidenceLedgerSummary, rusqlite::Error> {
    let component = normalize_optional_filter(component);
    let project_id = normalize_optional_filter(project_id);
    let run_id = normalize_optional_filter(run_id);
    if !db_path.is_file() {
        return Ok(empty_evidence_ledger_summary(component, project_id, run_id));
    }

    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    conn.execute_batch("PRAGMA busy_timeout = 2000;")?;

    let mut where_parts = Vec::new();
    let mut params_vec = Vec::<String>::new();
    if let Some(value) = component.as_ref() {
        where_parts.push("component = ?");
        params_vec.push(value.clone());
    }
    if let Some(value) = project_id.as_ref() {
        where_parts.push("project_id = ?");
        params_vec.push(value.clone());
    }
    if let Some(value) = run_id.as_ref() {
        where_parts.push("run_id = ?");
        params_vec.push(value.clone());
    }
    let where_sql = if where_parts.is_empty() {
        String::new()
    } else {
        format!(" WHERE {}", where_parts.join(" AND "))
    };

    let totals_sql = format!(
        "SELECT COUNT(*), COALESCE(MAX(created_at_ms), 0)
         FROM rust_hub_evidence_ledger{}",
        where_sql
    );
    let totals = conn
        .query_row(
            totals_sql.as_str(),
            rusqlite::params_from_iter(params_vec.iter()),
            |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?)),
        )
        .optional();
    let (total, latest_created_at_ms) = match totals {
        Ok(Some(value)) => value,
        Ok(None) => (0, 0),
        Err(err) if is_no_such_table(&err) => {
            return Ok(empty_evidence_ledger_summary(component, project_id, run_id));
        }
        Err(err) => return Err(err),
    };

    let rows_sql = format!(
        "SELECT evidence_id, created_at_ms, component, authority_mode, project_id, run_id,
                output_verdict, reason_json, parent_evidence_json, input_ref_json, payload_json,
                expires_at_ms
         FROM rust_hub_evidence_ledger{}
         ORDER BY created_at_ms DESC, evidence_id DESC
         LIMIT ?",
        where_sql
    );
    let limit = limit.clamp(1, 500) as i64;
    let mut row_params = params_vec.iter().collect::<Vec<_>>();
    let limit_string = limit.to_string();
    row_params.push(&limit_string);
    let mut stmt = conn.prepare(rows_sql.as_str())?;
    let iter = stmt.query_map(
        rusqlite::params_from_iter(row_params),
        evidence_row_from_sql,
    )?;
    let mut rows = Vec::new();
    for row in iter {
        rows.push(row?);
    }

    Ok(EvidenceLedgerSummary {
        component,
        project_id,
        run_id,
        total,
        latest_created_at_ms,
        rows,
    })
}

pub fn create_memory_object_with_event(
    db_path: &Path,
    object: &MemoryObjectRecord,
    event: &MemoryEventRecord,
) -> Result<(), rusqlite::Error> {
    let mut conn = open_rw_with_pragmas(db_path)?;
    let tx = conn.transaction()?;
    tx.execute(
        "INSERT INTO rust_hub_memory_objects
         (memory_id, schema_version, scope, owner_id, run_id, project_id, agent_id,
          source_kind, layer, title, text, summary, tags_json, sensitivity, visibility,
          status, pinned, immutable, ttl_ms, created_at_ms, updated_at_ms,
          last_accessed_at_ms, version, provenance_json, policy_json)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7,
                 ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15,
                 ?16, ?17, ?18, ?19, ?20, ?21,
                 ?22, ?23, ?24, ?25)",
        params![
            object.memory_id,
            object.schema_version,
            object.scope,
            object.owner_id,
            object.run_id,
            object.project_id,
            object.agent_id,
            object.source_kind,
            object.layer,
            object.title,
            object.text,
            object.summary,
            object.tags_json,
            object.sensitivity,
            object.visibility,
            object.status,
            bool_to_i64(object.pinned),
            bool_to_i64(object.immutable),
            object.ttl_ms,
            object.created_at_ms,
            object.updated_at_ms,
            object.last_accessed_at_ms,
            object.version,
            object.provenance_json,
            object.policy_json,
        ],
    )?;
    insert_memory_event(&tx, event)?;
    tx.commit()?;
    Ok(())
}

pub fn update_memory_object_with_event(
    db_path: &Path,
    object: &MemoryObjectRecord,
    event: &MemoryEventRecord,
) -> Result<(), rusqlite::Error> {
    let mut conn = open_rw_with_pragmas(db_path)?;
    let tx = conn.transaction()?;
    let changed = tx.execute(
        "UPDATE rust_hub_memory_objects
         SET schema_version = ?2,
             scope = ?3,
             owner_id = ?4,
             run_id = ?5,
             project_id = ?6,
             agent_id = ?7,
             source_kind = ?8,
             layer = ?9,
             title = ?10,
             text = ?11,
             summary = ?12,
             tags_json = ?13,
             sensitivity = ?14,
             visibility = ?15,
             status = ?16,
             pinned = ?17,
             immutable = ?18,
             ttl_ms = ?19,
             created_at_ms = ?20,
             updated_at_ms = ?21,
             last_accessed_at_ms = ?22,
             version = ?23,
             provenance_json = ?24,
             policy_json = ?25
         WHERE memory_id = ?1",
        params![
            object.memory_id,
            object.schema_version,
            object.scope,
            object.owner_id,
            object.run_id,
            object.project_id,
            object.agent_id,
            object.source_kind,
            object.layer,
            object.title,
            object.text,
            object.summary,
            object.tags_json,
            object.sensitivity,
            object.visibility,
            object.status,
            bool_to_i64(object.pinned),
            bool_to_i64(object.immutable),
            object.ttl_ms,
            object.created_at_ms,
            object.updated_at_ms,
            object.last_accessed_at_ms,
            object.version,
            object.provenance_json,
            object.policy_json,
        ],
    )?;
    if changed == 0 {
        return Err(rusqlite::Error::QueryReturnedNoRows);
    }
    insert_memory_event(&tx, event)?;
    tx.commit()?;
    Ok(())
}

pub fn read_memory_object(
    db_path: &Path,
    memory_id: &str,
) -> Result<Option<MemoryObjectRecord>, rusqlite::Error> {
    if !db_path.is_file() {
        return Ok(None);
    }
    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    conn.execute_batch("PRAGMA busy_timeout = 2000;")?;
    match conn
        .query_row(
            "SELECT memory_id, schema_version, scope, owner_id, run_id, project_id, agent_id,
                    source_kind, layer, title, text, summary, tags_json, sensitivity, visibility,
                    status, pinned, immutable, ttl_ms, created_at_ms, updated_at_ms,
                    last_accessed_at_ms, version, provenance_json, policy_json
             FROM rust_hub_memory_objects
             WHERE memory_id = ?1",
            params![memory_id],
            memory_object_row_from_sql,
        )
        .optional()
    {
        Ok(value) => Ok(value),
        Err(err) if is_no_such_table(&err) => Ok(None),
        Err(err) => Err(err),
    }
}

pub fn list_memory_objects(
    db_path: &Path,
    filter: &MemoryObjectListFilter,
) -> Result<Vec<MemoryObjectRecord>, rusqlite::Error> {
    if !db_path.is_file() {
        return Ok(Vec::new());
    }
    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    conn.execute_batch("PRAGMA busy_timeout = 2000;")?;

    let mut where_parts = Vec::new();
    let mut params_vec = Vec::<String>::new();
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "scope",
        filter.scope.as_ref(),
    );
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "owner_id",
        filter.owner_id.as_ref(),
    );
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "project_id",
        filter.project_id.as_ref(),
    );
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "agent_id",
        filter.agent_id.as_ref(),
    );
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "source_kind",
        filter.source_kind.as_ref(),
    );
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "layer",
        filter.layer.as_ref(),
    );
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "status",
        filter.status.as_ref(),
    );
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "sensitivity",
        filter.sensitivity.as_ref(),
    );
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "visibility",
        filter.visibility.as_ref(),
    );

    let where_sql = if where_parts.is_empty() {
        String::new()
    } else {
        format!(" WHERE {}", where_parts.join(" AND "))
    };
    let sql = format!(
        "SELECT memory_id, schema_version, scope, owner_id, run_id, project_id, agent_id,
                source_kind, layer, title, text, summary, tags_json, sensitivity, visibility,
                status, pinned, immutable, ttl_ms, created_at_ms, updated_at_ms,
                last_accessed_at_ms, version, provenance_json, policy_json
         FROM rust_hub_memory_objects{}
         ORDER BY pinned DESC, updated_at_ms DESC, memory_id DESC
         LIMIT ?",
        where_sql
    );
    let limit = filter.limit.clamp(1, 500).to_string();
    let mut row_params = params_vec.iter().collect::<Vec<_>>();
    row_params.push(&limit);
    let mut stmt = match conn.prepare(sql.as_str()) {
        Ok(stmt) => stmt,
        Err(err) if is_no_such_table(&err) => return Ok(Vec::new()),
        Err(err) => return Err(err),
    };
    let iter = stmt.query_map(
        rusqlite::params_from_iter(row_params),
        memory_object_row_from_sql,
    )?;
    let mut rows = Vec::new();
    for row in iter {
        rows.push(row?);
    }
    Ok(rows)
}

pub fn read_memory_object_history(
    db_path: &Path,
    memory_id: &str,
    limit: usize,
) -> Result<Vec<MemoryEventRecord>, rusqlite::Error> {
    if !db_path.is_file() {
        return Ok(Vec::new());
    }
    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    conn.execute_batch("PRAGMA busy_timeout = 2000;")?;
    let limit = limit.clamp(1, 500).to_string();
    let mut stmt = match conn.prepare(
        "SELECT event_id, memory_id, operation, actor, reason, before_version,
                after_version, before_json, after_json, policy_decision, deny_code,
                audit_ref, created_at_ms
         FROM rust_hub_memory_events
         WHERE memory_id = ?1
         ORDER BY created_at_ms DESC, event_id DESC
         LIMIT ?2",
    ) {
        Ok(stmt) => stmt,
        Err(err) if is_no_such_table(&err) => return Ok(Vec::new()),
        Err(err) => return Err(err),
    };
    let iter = stmt.query_map(params![memory_id, limit], memory_event_row_from_sql)?;
    let mut rows = Vec::new();
    for row in iter {
        rows.push(row?);
    }
    Ok(rows)
}

pub fn read_memory_object_store_summary(
    db_path: &Path,
) -> Result<MemoryObjectStoreSummary, rusqlite::Error> {
    if !db_path.is_file() {
        return Ok(MemoryObjectStoreSummary::default());
    }
    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    conn.execute_batch("PRAGMA busy_timeout = 2000;")?;
    let object_count = query_i64_or_zero(&conn, "SELECT COUNT(*) FROM rust_hub_memory_objects")?;
    let active_object_count = query_i64_or_zero(
        &conn,
        "SELECT COUNT(*) FROM rust_hub_memory_objects WHERE status = 'active'",
    )?;
    let candidate_object_count = query_i64_or_zero(
        &conn,
        "SELECT COUNT(*) FROM rust_hub_memory_objects WHERE status = 'candidate'",
    )?;
    let deleted_tombstone_count = query_i64_or_zero(
        &conn,
        "SELECT COUNT(*) FROM rust_hub_memory_objects WHERE status = 'deleted'",
    )?;
    let event_count = query_i64_or_zero(&conn, "SELECT COUNT(*) FROM rust_hub_memory_events")?;
    let latest_object_updated_at_ms = query_i64_or_zero(
        &conn,
        "SELECT COALESCE(MAX(updated_at_ms), 0) FROM rust_hub_memory_objects",
    )?;
    let latest_event_created_at_ms = query_i64_or_zero(
        &conn,
        "SELECT COALESCE(MAX(created_at_ms), 0) FROM rust_hub_memory_events",
    )?;
    Ok(MemoryObjectStoreSummary {
        object_count,
        active_object_count,
        candidate_object_count,
        deleted_tombstone_count,
        event_count,
        latest_object_updated_at_ms,
        latest_event_created_at_ms,
    })
}

pub fn rebuild_memory_object_index(
    db_path: &Path,
) -> Result<MemoryObjectIndexRebuildReport, rusqlite::Error> {
    let stale_before_count = read_memory_object_index_summary(db_path)
        .map(|summary| summary.stale_index_count)
        .unwrap_or(0);
    let generated_at_ms = now_ms_i64();
    let mut conn = open_rw_with_pragmas(db_path)?;
    let tx = conn.transaction()?;
    let objects = {
        let mut stmt = tx.prepare(
            "SELECT memory_id, schema_version, scope, owner_id, run_id, project_id, agent_id,
                    source_kind, layer, title, text, summary, tags_json, sensitivity, visibility,
                    status, pinned, immutable, ttl_ms, created_at_ms, updated_at_ms,
                    last_accessed_at_ms, version, provenance_json, policy_json
             FROM rust_hub_memory_objects
             ORDER BY updated_at_ms DESC, memory_id DESC",
        )?;
        let iter = stmt.query_map([], memory_object_row_from_sql)?;
        let mut rows = Vec::new();
        for row in iter {
            rows.push(row?);
        }
        rows
    };
    tx.execute("DELETE FROM rust_hub_memory_object_index", [])?;
    let mut indexed_count = 0_i64;
    let mut skipped_secret_count = 0_i64;
    let mut skipped_inactive_count = 0_i64;
    for object in objects {
        if object.status != "active" {
            skipped_inactive_count += 1;
            continue;
        }
        if object.sensitivity == "secret"
            || memory_index_looks_secret(&object.title)
            || memory_index_looks_secret(&object.summary)
            || memory_index_looks_secret(&object.text)
        {
            skipped_secret_count += 1;
            continue;
        }
        for row in memory_object_index_records(&object, generated_at_ms)? {
            insert_memory_object_index_row(&tx, &row)?;
            indexed_count += 1;
        }
    }
    tx.commit()?;
    let stale_after_count = read_memory_object_index_summary(db_path)
        .map(|summary| summary.stale_index_count)
        .unwrap_or(0);
    Ok(MemoryObjectIndexRebuildReport {
        schema_version: "xhub.memory.object_index_rebuild.v1".to_string(),
        rebuilt: true,
        indexed_count,
        skipped_secret_count,
        skipped_inactive_count,
        stale_before_count,
        stale_after_count,
        generated_at_ms,
    })
}

pub fn list_memory_object_index(
    db_path: &Path,
    filter: &MemoryObjectIndexFilter,
) -> Result<Vec<MemoryObjectIndexRecord>, rusqlite::Error> {
    if !db_path.is_file() {
        return Ok(Vec::new());
    }
    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    conn.execute_batch("PRAGMA busy_timeout = 2000;")?;

    let mut where_parts = Vec::new();
    let mut params_vec = Vec::<String>::new();
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "scope",
        filter.scope.as_ref(),
    );
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "owner_id",
        filter.owner_id.as_ref(),
    );
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "project_id",
        filter.project_id.as_ref(),
    );
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "agent_id",
        filter.agent_id.as_ref(),
    );
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "source_kind",
        filter.source_kind.as_ref(),
    );
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "layer",
        filter.layer.as_ref(),
    );
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "sensitivity",
        filter.sensitivity.as_ref(),
    );
    push_memory_filter(
        &mut where_parts,
        &mut params_vec,
        "visibility",
        filter.visibility.as_ref(),
    );
    let where_sql = if where_parts.is_empty() {
        String::new()
    } else {
        format!(" WHERE {}", where_parts.join(" AND "))
    };
    let sql = format!(
        "SELECT memory_id, chunk_id, chunk_ordinal, chunk_start_line, chunk_end_line,
                object_version, object_created_at_ms, object_updated_at_ms, scope, owner_id,
                run_id, project_id, agent_id, source_kind, layer, title, summary,
                text, searchable_text, content_hash, sensitivity, visibility,
                pinned, has_code, has_todo, has_error, has_decision, has_approval,
                has_blocker, has_link, indexed_at_ms
         FROM rust_hub_memory_object_index{}
         ORDER BY pinned DESC, object_updated_at_ms DESC, memory_id DESC, chunk_ordinal ASC
         LIMIT ?",
        where_sql
    );
    let limit = filter.limit.clamp(1, 1000).to_string();
    let mut row_params = params_vec.iter().collect::<Vec<_>>();
    row_params.push(&limit);
    let mut stmt = match conn.prepare(sql.as_str()) {
        Ok(stmt) => stmt,
        Err(err) if is_no_such_table(&err) => return Ok(Vec::new()),
        Err(err) => return Err(err),
    };
    let iter = stmt.query_map(
        rusqlite::params_from_iter(row_params),
        memory_object_index_row_from_sql,
    )?;
    let mut rows = Vec::new();
    for row in iter {
        rows.push(row?);
    }
    Ok(rows)
}

pub fn read_memory_object_index_summary(
    db_path: &Path,
) -> Result<MemoryObjectIndexSummary, rusqlite::Error> {
    if !db_path.is_file() {
        return Ok(MemoryObjectIndexSummary::default());
    }
    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    conn.execute_batch("PRAGMA busy_timeout = 2000;")?;
    let index_row_count =
        query_i64_or_zero(&conn, "SELECT COUNT(*) FROM rust_hub_memory_object_index")?;
    let active_indexable_object_count = query_i64_or_zero(
        &conn,
        "SELECT COUNT(*) FROM rust_hub_memory_objects
         WHERE status = 'active'
           AND sensitivity != 'secret'
           AND lower(title || char(10) || summary || char(10) || text) NOT LIKE '%api key%'
           AND lower(title || char(10) || summary || char(10) || text) NOT LIKE '%apikey%'
           AND lower(title || char(10) || summary || char(10) || text) NOT LIKE '%secret%'
           AND lower(title || char(10) || summary || char(10) || text) NOT LIKE '%password%'
           AND lower(title || char(10) || summary || char(10) || text) NOT LIKE '%private key%'
           AND lower(title || char(10) || summary || char(10) || text) NOT LIKE '%authorization:%'
           AND lower(title || char(10) || summary || char(10) || text) NOT LIKE '%bearer %'
           AND lower(title || char(10) || summary || char(10) || text) NOT LIKE '%sk-%'
           AND lower(title || char(10) || summary || char(10) || text) NOT LIKE '%xoxb-%'
           AND lower(title || char(10) || summary || char(10) || text) NOT LIKE '%aws_secret_access_key%'",
    )?;
    let stale_missing = query_i64_or_zero(
        &conn,
        "SELECT COUNT(DISTINCT o.memory_id) FROM rust_hub_memory_objects o
         LEFT JOIN rust_hub_memory_object_index i ON i.memory_id = o.memory_id
         WHERE o.status = 'active'
           AND o.sensitivity != 'secret'
           AND lower(o.title || char(10) || o.summary || char(10) || o.text) NOT LIKE '%api key%'
           AND lower(o.title || char(10) || o.summary || char(10) || o.text) NOT LIKE '%apikey%'
           AND lower(o.title || char(10) || o.summary || char(10) || o.text) NOT LIKE '%secret%'
           AND lower(o.title || char(10) || o.summary || char(10) || o.text) NOT LIKE '%password%'
           AND lower(o.title || char(10) || o.summary || char(10) || o.text) NOT LIKE '%private key%'
           AND lower(o.title || char(10) || o.summary || char(10) || o.text) NOT LIKE '%authorization:%'
           AND lower(o.title || char(10) || o.summary || char(10) || o.text) NOT LIKE '%bearer %'
           AND lower(o.title || char(10) || o.summary || char(10) || o.text) NOT LIKE '%sk-%'
           AND lower(o.title || char(10) || o.summary || char(10) || o.text) NOT LIKE '%xoxb-%'
           AND lower(o.title || char(10) || o.summary || char(10) || o.text) NOT LIKE '%aws_secret_access_key%'
           AND (
             i.memory_id IS NULL
             OR i.object_version != o.version
             OR i.object_updated_at_ms != o.updated_at_ms
           )",
    )?;
    let stale_orphan = query_i64_or_zero(
        &conn,
        "SELECT COUNT(*) FROM rust_hub_memory_object_index i
         LEFT JOIN rust_hub_memory_objects o ON o.memory_id = i.memory_id
         WHERE o.memory_id IS NULL
            OR o.status != 'active'
            OR o.sensitivity = 'secret'",
    )?;
    let latest_indexed_at_ms = query_i64_or_zero(
        &conn,
        "SELECT COALESCE(MAX(indexed_at_ms), 0) FROM rust_hub_memory_object_index",
    )?;
    Ok(MemoryObjectIndexSummary {
        index_ready: true,
        index_row_count,
        active_indexable_object_count,
        stale_index_count: stale_missing + stale_orphan,
        latest_indexed_at_ms,
    })
}

fn open_rw_with_pragmas(db_path: &Path) -> Result<Connection, rusqlite::Error> {
    if let Some(parent) = db_path.parent() {
        std::fs::create_dir_all(parent).map_err(|err| {
            rusqlite::Error::ToSqlConversionFailure(Box::new(std::io::Error::new(
                err.kind(),
                format!("create db dir failed: {err}"),
            )))
        })?;
    }
    let conn = Connection::open(db_path)?;
    conn.execute_batch(
        "PRAGMA journal_mode = WAL;
         PRAGMA synchronous = NORMAL;
         PRAGMA busy_timeout = 2000;
         PRAGMA foreign_keys = ON;",
    )?;
    Ok(conn)
}

fn audit_row_from_sql(row: &rusqlite::Row<'_>) -> Result<SkillPreflightAuditRow, rusqlite::Error> {
    Ok(SkillPreflightAuditRow {
        event_id: row.get(0)?,
        created_at_ms: row.get(1)?,
        scope_key: row.get(2)?,
        request_id: row.get(3)?,
        audit_ref: row.get(4)?,
        skill_id: row.get(5)?,
        decision: row.get(6)?,
        ok: row.get::<_, i64>(7)? == 1,
        reason_json: row.get(8)?,
    })
}

fn policy_event_row_from_sql(
    row: &rusqlite::Row<'_>,
) -> Result<SkillPolicyEventRow, rusqlite::Error> {
    Ok(SkillPolicyEventRow {
        event_id: row.get(0)?,
        created_at_ms: row.get(1)?,
        operation: row.get(2)?,
        scope_key: row.get(3)?,
        skill_id: row.get(4)?,
        capability: row.get(5)?,
        actor: row.get(6)?,
        result: row.get(7)?,
    })
}

fn evidence_row_from_sql(row: &rusqlite::Row<'_>) -> Result<EvidenceLedgerRow, rusqlite::Error> {
    Ok(EvidenceLedgerRow {
        evidence_id: row.get(0)?,
        created_at_ms: row.get(1)?,
        component: row.get(2)?,
        authority_mode: row.get(3)?,
        project_id: row.get(4)?,
        run_id: row.get(5)?,
        output_verdict: row.get(6)?,
        reason_json: row.get(7)?,
        parent_evidence_json: row.get(8)?,
        input_ref_json: row.get(9)?,
        payload_json: row.get(10)?,
        expires_at_ms: row.get(11)?,
    })
}

fn memory_object_row_from_sql(
    row: &rusqlite::Row<'_>,
) -> Result<MemoryObjectRecord, rusqlite::Error> {
    Ok(MemoryObjectRecord {
        memory_id: row.get(0)?,
        schema_version: row.get(1)?,
        scope: row.get(2)?,
        owner_id: row.get(3)?,
        run_id: row.get(4)?,
        project_id: row.get(5)?,
        agent_id: row.get(6)?,
        source_kind: row.get(7)?,
        layer: row.get(8)?,
        title: row.get(9)?,
        text: row.get(10)?,
        summary: row.get(11)?,
        tags_json: row.get(12)?,
        sensitivity: row.get(13)?,
        visibility: row.get(14)?,
        status: row.get(15)?,
        pinned: row.get::<_, i64>(16)? == 1,
        immutable: row.get::<_, i64>(17)? == 1,
        ttl_ms: row.get(18)?,
        created_at_ms: row.get(19)?,
        updated_at_ms: row.get(20)?,
        last_accessed_at_ms: row.get(21)?,
        version: row.get(22)?,
        provenance_json: row.get(23)?,
        policy_json: row.get(24)?,
    })
}

fn memory_event_row_from_sql(
    row: &rusqlite::Row<'_>,
) -> Result<MemoryEventRecord, rusqlite::Error> {
    Ok(MemoryEventRecord {
        event_id: row.get(0)?,
        memory_id: row.get(1)?,
        operation: row.get(2)?,
        actor: row.get(3)?,
        reason: row.get(4)?,
        before_version: row.get(5)?,
        after_version: row.get(6)?,
        before_json: row.get(7)?,
        after_json: row.get(8)?,
        policy_decision: row.get(9)?,
        deny_code: row.get(10)?,
        audit_ref: row.get(11)?,
        created_at_ms: row.get(12)?,
    })
}

fn memory_object_index_row_from_sql(
    row: &rusqlite::Row<'_>,
) -> Result<MemoryObjectIndexRecord, rusqlite::Error> {
    Ok(MemoryObjectIndexRecord {
        memory_id: row.get(0)?,
        chunk_id: row.get(1)?,
        chunk_ordinal: row.get(2)?,
        chunk_start_line: row.get(3)?,
        chunk_end_line: row.get(4)?,
        object_version: row.get(5)?,
        object_created_at_ms: row.get(6)?,
        object_updated_at_ms: row.get(7)?,
        scope: row.get(8)?,
        owner_id: row.get(9)?,
        run_id: row.get(10)?,
        project_id: row.get(11)?,
        agent_id: row.get(12)?,
        source_kind: row.get(13)?,
        layer: row.get(14)?,
        title: row.get(15)?,
        summary: row.get(16)?,
        text: row.get(17)?,
        searchable_text: row.get(18)?,
        content_hash: row.get(19)?,
        sensitivity: row.get(20)?,
        visibility: row.get(21)?,
        pinned: row.get::<_, i64>(22)? == 1,
        has_code: row.get::<_, i64>(23)? == 1,
        has_todo: row.get::<_, i64>(24)? == 1,
        has_error: row.get::<_, i64>(25)? == 1,
        has_decision: row.get::<_, i64>(26)? == 1,
        has_approval: row.get::<_, i64>(27)? == 1,
        has_blocker: row.get::<_, i64>(28)? == 1,
        has_link: row.get::<_, i64>(29)? == 1,
        indexed_at_ms: row.get(30)?,
    })
}

const MEMORY_OBJECT_INDEX_TARGET_CHARS: usize = 1600;
const MEMORY_OBJECT_INDEX_OVERLAP_LINES: usize = 2;

#[derive(Debug, Clone)]
struct MemoryObjectIndexChunk {
    chunk_ordinal: i64,
    chunk_start_line: i64,
    chunk_end_line: i64,
    text: String,
}

fn memory_object_index_records(
    object: &MemoryObjectRecord,
    indexed_at_ms: i64,
) -> Result<Vec<MemoryObjectIndexRecord>, rusqlite::Error> {
    Ok(memory_object_index_chunks(&object.text)
        .into_iter()
        .map(|chunk| {
            let searchable_text = format!(
                "{}\n{}\n{}\n{}",
                object.title, object.summary, chunk.text, object.tags_json
            );
            let lower = searchable_text.to_ascii_lowercase();
            let content_hash = stable_hash16(searchable_text.as_bytes());
            MemoryObjectIndexRecord {
                memory_id: object.memory_id.clone(),
                chunk_id: format!(
                    "object-{}-{}-{}",
                    chunk.chunk_ordinal,
                    chunk
                        .chunk_end_line
                        .saturating_sub(chunk.chunk_start_line)
                        .saturating_add(1),
                    content_hash
                ),
                chunk_ordinal: chunk.chunk_ordinal,
                chunk_start_line: chunk.chunk_start_line,
                chunk_end_line: chunk.chunk_end_line,
                object_version: object.version,
                object_created_at_ms: object.created_at_ms,
                object_updated_at_ms: object.updated_at_ms,
                scope: object.scope.clone(),
                owner_id: object.owner_id.clone(),
                run_id: object.run_id.clone(),
                project_id: object.project_id.clone(),
                agent_id: object.agent_id.clone(),
                source_kind: object.source_kind.clone(),
                layer: object.layer.clone(),
                title: object.title.clone(),
                summary: object.summary.clone(),
                text: chunk.text,
                searchable_text,
                content_hash,
                sensitivity: object.sensitivity.clone(),
                visibility: object.visibility.clone(),
                pinned: object.pinned,
                has_code: lower.contains("```")
                    || lower.contains("fn ")
                    || lower.contains("func ")
                    || lower.contains("class ")
                    || lower.contains("struct "),
                has_todo: lower.contains("todo")
                    || lower.contains("next step")
                    || lower.contains("next_steps"),
                has_error: lower.contains("error")
                    || lower.contains("failed")
                    || lower.contains("exception"),
                has_decision: lower.contains("decision")
                    || lower.contains("decided")
                    || lower.contains("choose")
                    || lower.contains("chosen"),
                has_approval: lower.contains("approval")
                    || lower.contains("approved")
                    || lower.contains("authorized"),
                has_blocker: lower.contains("blocker")
                    || lower.contains("blocked")
                    || lower.contains("risk"),
                has_link: lower.contains("http://")
                    || lower.contains("https://")
                    || lower.contains("memory://"),
                indexed_at_ms,
            }
        })
        .collect())
}

fn memory_object_index_chunks(text: &str) -> Vec<MemoryObjectIndexChunk> {
    if text.trim().is_empty() {
        return vec![MemoryObjectIndexChunk {
            chunk_ordinal: 1,
            chunk_start_line: 1,
            chunk_end_line: 1,
            text: String::new(),
        }];
    }
    if text.chars().count() <= MEMORY_OBJECT_INDEX_TARGET_CHARS {
        return vec![MemoryObjectIndexChunk {
            chunk_ordinal: 1,
            chunk_start_line: 1,
            chunk_end_line: text.lines().count().max(1) as i64,
            text: text.trim().to_string(),
        }];
    }

    let lines = text.lines().collect::<Vec<_>>();
    let mut out = Vec::new();
    let mut current = Vec::<&str>::new();
    let mut current_start_idx = 0usize;
    let mut ordinal = 1_i64;

    for (idx, line) in lines.iter().enumerate() {
        current.push(*line);
        let current_text = current.join("\n");
        let at_boundary = line.trim().is_empty() || idx + 1 == lines.len();
        let over_budget = current_text.chars().count() >= MEMORY_OBJECT_INDEX_TARGET_CHARS;
        if (over_budget && at_boundary)
            || (over_budget && current.len() >= 8)
            || idx + 1 == lines.len()
        {
            let trimmed = current_text.trim();
            if !trimmed.is_empty() {
                out.push(MemoryObjectIndexChunk {
                    chunk_ordinal: ordinal,
                    chunk_start_line: current_start_idx.saturating_add(1) as i64,
                    chunk_end_line: idx.saturating_add(1) as i64,
                    text: trimmed.to_string(),
                });
                ordinal += 1;
            }
            let overlap_start = current
                .len()
                .saturating_sub(MEMORY_OBJECT_INDEX_OVERLAP_LINES);
            current = current[overlap_start..].to_vec();
            current_start_idx = idx.saturating_add(1).saturating_sub(current.len());
        }
    }

    if out.is_empty() {
        out.push(MemoryObjectIndexChunk {
            chunk_ordinal: 1,
            chunk_start_line: 1,
            chunk_end_line: lines.len().max(1) as i64,
            text: text.trim().to_string(),
        });
    }
    out
}

fn insert_memory_object_index_row(
    conn: &rusqlite::Connection,
    row: &MemoryObjectIndexRecord,
) -> Result<(), rusqlite::Error> {
    conn.execute(
        "INSERT OR REPLACE INTO rust_hub_memory_object_index
         (memory_id, chunk_id, chunk_ordinal, chunk_start_line, chunk_end_line,
          object_version, object_created_at_ms, object_updated_at_ms, scope, owner_id,
          run_id, project_id, agent_id, source_kind, layer, title, summary,
          text, searchable_text, content_hash, sensitivity, visibility, pinned,
          has_code, has_todo, has_error, has_decision, has_approval,
          has_blocker, has_link, indexed_at_ms)
         VALUES (?1, ?2, ?3, ?4, ?5,
                 ?6, ?7, ?8, ?9, ?10,
                 ?11, ?12, ?13, ?14, ?15, ?16, ?17,
                 ?18, ?19, ?20, ?21, ?22, ?23,
                 ?24, ?25, ?26, ?27, ?28,
                 ?29, ?30, ?31)",
        params![
            row.memory_id,
            row.chunk_id,
            row.chunk_ordinal,
            row.chunk_start_line,
            row.chunk_end_line,
            row.object_version,
            row.object_created_at_ms,
            row.object_updated_at_ms,
            row.scope,
            row.owner_id,
            row.run_id,
            row.project_id,
            row.agent_id,
            row.source_kind,
            row.layer,
            row.title,
            row.summary,
            row.text,
            row.searchable_text,
            row.content_hash,
            row.sensitivity,
            row.visibility,
            bool_to_i64(row.pinned),
            bool_to_i64(row.has_code),
            bool_to_i64(row.has_todo),
            bool_to_i64(row.has_error),
            bool_to_i64(row.has_decision),
            bool_to_i64(row.has_approval),
            bool_to_i64(row.has_blocker),
            bool_to_i64(row.has_link),
            row.indexed_at_ms,
        ],
    )?;
    Ok(())
}

fn insert_memory_event(
    conn: &rusqlite::Connection,
    event: &MemoryEventRecord,
) -> Result<(), rusqlite::Error> {
    conn.execute(
        "INSERT INTO rust_hub_memory_events
         (event_id, memory_id, operation, actor, reason, before_version,
          after_version, before_json, after_json, policy_decision, deny_code,
          audit_ref, created_at_ms)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6,
                 ?7, ?8, ?9, ?10, ?11,
                 ?12, ?13)",
        params![
            event.event_id,
            event.memory_id,
            event.operation,
            event.actor,
            event.reason,
            event.before_version,
            event.after_version,
            event.before_json,
            event.after_json,
            event.policy_decision,
            event.deny_code,
            event.audit_ref,
            event.created_at_ms,
        ],
    )?;
    Ok(())
}

fn push_memory_filter(
    where_parts: &mut Vec<&'static str>,
    params_vec: &mut Vec<String>,
    column: &'static str,
    value: Option<&String>,
) {
    let Some(value) = value
        .map(|item| item.trim())
        .filter(|item| !item.is_empty())
    else {
        return;
    };
    where_parts.push(match column {
        "scope" => "scope = ?",
        "owner_id" => "owner_id = ?",
        "project_id" => "project_id = ?",
        "agent_id" => "agent_id = ?",
        "source_kind" => "source_kind = ?",
        "layer" => "layer = ?",
        "status" => "status = ?",
        "sensitivity" => "sensitivity = ?",
        "visibility" => "visibility = ?",
        _ => return,
    });
    params_vec.push(value.to_string());
}

fn bool_to_i64(value: bool) -> i64 {
    if value {
        1
    } else {
        0
    }
}

fn stable_hash16(bytes: &[u8]) -> String {
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{hash:016x}")
}

fn memory_index_looks_secret(value: &str) -> bool {
    let lower = value.to_ascii_lowercase();
    lower.contains("api key")
        || lower.contains("apikey")
        || lower.contains("secret")
        || lower.contains("password")
        || lower.contains("private key")
        || lower.contains("authorization:")
        || lower.contains("bearer ")
        || lower.contains("sk-")
        || lower.contains("xoxb-")
        || lower.contains("aws_secret_access_key")
}

fn now_ms_i64() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .min(i64::MAX as u128) as i64
}

fn query_i64_or_zero(conn: &Connection, sql: &str) -> Result<i64, rusqlite::Error> {
    match conn.query_row(sql, [], |row| row.get::<_, i64>(0)) {
        Ok(value) => Ok(value),
        Err(err) if is_no_such_table(&err) => Ok(0),
        Err(err) => Err(err),
    }
}

fn empty_shadow_compare_summary(component: &str) -> ShadowCompareReportSummary {
    ShadowCompareReportSummary {
        component: component.to_string(),
        total: 0,
        matched: 0,
        mismatched: 0,
        latest_compared_at_ms: 0,
        rows: Vec::new(),
    }
}

fn empty_skill_preflight_audit_summary(
    scope_key: Option<String>,
    skill_id: Option<String>,
) -> SkillPreflightAuditSummary {
    SkillPreflightAuditSummary {
        scope_key,
        skill_id,
        total: 0,
        allowed: 0,
        denied: 0,
        latest_created_at_ms: 0,
        rows: Vec::new(),
    }
}

fn empty_skill_policy_event_summary(
    scope_key: Option<String>,
    skill_id: Option<String>,
) -> SkillPolicyEventSummary {
    SkillPolicyEventSummary {
        scope_key,
        skill_id,
        total: 0,
        latest_created_at_ms: 0,
        rows: Vec::new(),
    }
}

fn empty_evidence_ledger_summary(
    component: Option<String>,
    project_id: Option<String>,
    run_id: Option<String>,
) -> EvidenceLedgerSummary {
    EvidenceLedgerSummary {
        component,
        project_id,
        run_id,
        total: 0,
        latest_created_at_ms: 0,
        rows: Vec::new(),
    }
}

fn normalize_optional_filter(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn is_no_such_table(err: &rusqlite::Error) -> bool {
    matches!(
        err,
        rusqlite::Error::SqliteFailure(_, Some(message)) if message.contains("no such table")
    )
}

impl Default for SkillPolicyStoreSummary {
    fn default() -> Self {
        Self {
            active_pin_count: 0,
            active_grant_count: 0,
            preflight_audit_count: 0,
            policy_event_count: 0,
            latest_preflight_audit_ms: 0,
            latest_policy_event_ms: 0,
        }
    }
}

impl Default for MemoryObjectStoreSummary {
    fn default() -> Self {
        Self {
            object_count: 0,
            active_object_count: 0,
            candidate_object_count: 0,
            deleted_tombstone_count: 0,
            event_count: 0,
            latest_object_updated_at_ms: 0,
            latest_event_created_at_ms: 0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migrations_are_idempotent_and_create_scheduler_tables() {
        let db_path = unique_temp_db_path("xhub_migrations");

        let first = apply_baseline_migrations(&db_path).expect("first migration run");
        assert_eq!(first.len(), 9);
        assert!(first.iter().all(|item| item.applied));

        let second = apply_baseline_migrations(&db_path).expect("second migration run");
        assert_eq!(second.len(), 9);
        assert!(second.iter().all(|item| !item.applied));

        let conn = Connection::open(&db_path).expect("open migrated db");
        let table_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master
                 WHERE type = 'table'
                   AND name IN (
                     'rust_hub_scheduler_snapshots',
                     'rust_hub_run_queue',
                     'rust_hub_run_leases',
                     'rust_hub_scheduler_events',
                     'rust_hub_scheduler_scope_counters',
                     'rust_hub_memory_objects',
                     'rust_hub_memory_events',
                     'rust_hub_memory_object_index'
                   )",
                [],
                |row| row.get(0),
            )
            .expect("table count");
        assert_eq!(table_count, 8);

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn memory_object_store_creates_lists_and_reads_history() {
        let db_path = unique_temp_db_path("xhub_memory_objects");
        apply_baseline_migrations(&db_path).expect("migrate db");

        let object = MemoryObjectRecord {
            memory_id: "mem_test".to_string(),
            schema_version: "xhub.memory.object.v1".to_string(),
            scope: "project".to_string(),
            owner_id: "project-a".to_string(),
            run_id: None,
            project_id: Some("project-a".to_string()),
            agent_id: Some("coder".to_string()),
            source_kind: "project_capsule".to_string(),
            layer: "l1_canonical".to_string(),
            title: "Decision".to_string(),
            text: "Use Rust memory object store.".to_string(),
            summary: "Use Rust memory object store.".to_string(),
            tags_json: "[\"memory\"]".to_string(),
            sensitivity: "internal".to_string(),
            visibility: "local_only".to_string(),
            status: "active".to_string(),
            pinned: false,
            immutable: false,
            ttl_ms: None,
            created_at_ms: 1_000,
            updated_at_ms: 1_000,
            last_accessed_at_ms: 1_000,
            version: 1,
            provenance_json: "{}".to_string(),
            policy_json: "{}".to_string(),
        };
        let event = MemoryEventRecord {
            event_id: "mev_test".to_string(),
            memory_id: object.memory_id.clone(),
            operation: "create".to_string(),
            actor: "test".to_string(),
            reason: "unit_test".to_string(),
            before_version: None,
            after_version: Some(1),
            before_json: None,
            after_json: Some("{}".to_string()),
            policy_decision: "allow".to_string(),
            deny_code: String::new(),
            audit_ref: "audit-test".to_string(),
            created_at_ms: 1_001,
        };

        create_memory_object_with_event(&db_path, &object, &event).expect("create object");
        let fetched = read_memory_object(&db_path, "mem_test")
            .expect("read object")
            .expect("object exists");
        assert_eq!(fetched.owner_id, "project-a");

        let mut updated = fetched;
        updated.text = "Use Rust memory object store with update history.".to_string();
        updated.summary = "Use Rust memory object store with update history.".to_string();
        updated.updated_at_ms = 1_100;
        updated.last_accessed_at_ms = 1_100;
        updated.version = 2;
        let update_event = MemoryEventRecord {
            event_id: "mev_test_update".to_string(),
            memory_id: updated.memory_id.clone(),
            operation: "update".to_string(),
            actor: "test".to_string(),
            reason: "unit_test_update".to_string(),
            before_version: Some(1),
            after_version: Some(2),
            before_json: Some("{}".to_string()),
            after_json: Some("{\"version\":2}".to_string()),
            policy_decision: "allow".to_string(),
            deny_code: String::new(),
            audit_ref: "audit-test-update".to_string(),
            created_at_ms: 1_101,
        };
        update_memory_object_with_event(&db_path, &updated, &update_event).expect("update object");
        let fetched_after_update = read_memory_object(&db_path, "mem_test")
            .expect("read updated object")
            .expect("updated object exists");
        assert_eq!(fetched_after_update.version, 2);
        assert!(fetched_after_update.text.contains("update history"));

        let rows = list_memory_objects(
            &db_path,
            &MemoryObjectListFilter {
                project_id: Some("project-a".to_string()),
                status: Some("active".to_string()),
                limit: 10,
                ..Default::default()
            },
        )
        .expect("list objects");
        assert_eq!(rows.len(), 1);

        let history =
            read_memory_object_history(&db_path, "mem_test", 10).expect("read object history");
        assert_eq!(history.len(), 2);
        assert_eq!(history[0].operation, "update");
        assert_eq!(history[1].operation, "create");

        let summary = read_memory_object_store_summary(&db_path).expect("summary");
        assert_eq!(summary.object_count, 1);
        assert_eq!(summary.event_count, 2);

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn memory_object_index_rebuilds_from_active_non_secret_objects() {
        let db_path = unique_temp_db_path("xhub_memory_object_index");
        apply_baseline_migrations(&db_path).expect("migrate db");

        let base = MemoryObjectRecord {
            memory_id: "mem_index_decision".to_string(),
            schema_version: "xhub.memory.object.v1".to_string(),
            scope: "project".to_string(),
            owner_id: "project-a".to_string(),
            run_id: None,
            project_id: Some("project-a".to_string()),
            agent_id: Some("coder".to_string()),
            source_kind: "decision_track".to_string(),
            layer: "l1_canonical".to_string(),
            title: "Gateway decision".to_string(),
            text: "Decision: route model calls through Rust memory gateway.".to_string(),
            summary: "Decision: route model calls through Rust memory gateway.".to_string(),
            tags_json: "[\"decision\"]".to_string(),
            sensitivity: "internal".to_string(),
            visibility: "local_only".to_string(),
            status: "active".to_string(),
            pinned: true,
            immutable: false,
            ttl_ms: None,
            created_at_ms: 1_000,
            updated_at_ms: 1_000,
            last_accessed_at_ms: 1_000,
            version: 1,
            provenance_json: "{}".to_string(),
            policy_json: "{}".to_string(),
        };
        create_memory_object_with_event(
            &db_path,
            &base,
            &MemoryEventRecord {
                event_id: "mev_index_decision".to_string(),
                memory_id: base.memory_id.clone(),
                operation: "create".to_string(),
                actor: "test".to_string(),
                reason: "unit_test".to_string(),
                before_version: None,
                after_version: Some(1),
                before_json: None,
                after_json: Some("{}".to_string()),
                policy_decision: "allow".to_string(),
                deny_code: String::new(),
                audit_ref: "audit-index".to_string(),
                created_at_ms: 1_001,
            },
        )
        .expect("create index object");
        let mut secret = base.clone();
        secret.memory_id = "mem_index_secret".to_string();
        secret.title = "Secret".to_string();
        secret.text = "api_key: sk-secret-value".to_string();
        secret.summary = "secret".to_string();
        create_memory_object_with_event(
            &db_path,
            &secret,
            &MemoryEventRecord {
                event_id: "mev_index_secret".to_string(),
                memory_id: secret.memory_id.clone(),
                operation: "create".to_string(),
                actor: "test".to_string(),
                reason: "unit_test_secret".to_string(),
                before_version: None,
                after_version: Some(1),
                before_json: None,
                after_json: Some("{}".to_string()),
                policy_decision: "allow".to_string(),
                deny_code: String::new(),
                audit_ref: "audit-index-secret".to_string(),
                created_at_ms: 1_002,
            },
        )
        .expect("create secret object");

        let before = read_memory_object_index_summary(&db_path).expect("summary before");
        assert_eq!(before.index_row_count, 0);
        assert_eq!(before.active_indexable_object_count, 1);
        assert_eq!(before.stale_index_count, 1);

        let report = rebuild_memory_object_index(&db_path).expect("rebuild index");
        assert_eq!(report.indexed_count, 1);
        assert_eq!(report.skipped_secret_count, 1);
        assert_eq!(report.stale_before_count, 1);
        assert_eq!(report.stale_after_count, 0);

        let rows = list_memory_object_index(
            &db_path,
            &MemoryObjectIndexFilter {
                project_id: Some("project-a".to_string()),
                layer: Some("l1_canonical".to_string()),
                limit: 10,
                ..Default::default()
            },
        )
        .expect("list index");
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].memory_id, "mem_index_decision");
        assert!(rows[0].chunk_id.starts_with("object-1-"));
        assert_eq!(rows[0].chunk_ordinal, 1);
        assert_eq!(rows[0].chunk_start_line, 1);
        assert_eq!(rows[0].chunk_end_line, 1);
        assert!(rows[0].has_decision);
        assert!(rows[0].pinned);
        assert!(rows[0].content_hash.len() >= 16);

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn memory_object_index_rebuilds_long_objects_as_stable_chunks() {
        let db_path = unique_temp_db_path("xhub_memory_object_index_chunks");
        apply_baseline_migrations(&db_path).expect("migrate db");

        let text = (0..48)
            .map(|idx| {
                if idx == 30 {
                    format!(
                        "Line {idx}: Blocker: route-specific reviewer context must expand from a stable chunk ref."
                    )
                } else {
                    format!(
                        "Line {idx}: background project memory filler for chunked object indexing and retrieval."
                    )
                }
            })
            .collect::<Vec<_>>()
            .join("\n");
        let object = MemoryObjectRecord {
            memory_id: "mem_index_chunked".to_string(),
            schema_version: "xhub.memory.object.v1".to_string(),
            scope: "project".to_string(),
            owner_id: "project-chunk".to_string(),
            run_id: None,
            project_id: Some("project-chunk".to_string()),
            agent_id: Some("coder".to_string()),
            source_kind: "project_capsule".to_string(),
            layer: "l2_observations".to_string(),
            title: "Chunked object".to_string(),
            text,
            summary: "Chunked object retrieval fixture.".to_string(),
            tags_json: "[\"chunk\"]".to_string(),
            sensitivity: "internal".to_string(),
            visibility: "local_only".to_string(),
            status: "active".to_string(),
            pinned: false,
            immutable: false,
            ttl_ms: None,
            created_at_ms: 2_000,
            updated_at_ms: 2_000,
            last_accessed_at_ms: 2_000,
            version: 1,
            provenance_json: "{}".to_string(),
            policy_json: "{}".to_string(),
        };
        create_memory_object_with_event(
            &db_path,
            &object,
            &MemoryEventRecord {
                event_id: "mev_index_chunked".to_string(),
                memory_id: object.memory_id.clone(),
                operation: "create".to_string(),
                actor: "test".to_string(),
                reason: "unit_test_chunked".to_string(),
                before_version: None,
                after_version: Some(1),
                before_json: None,
                after_json: Some("{}".to_string()),
                policy_decision: "allow".to_string(),
                deny_code: String::new(),
                audit_ref: "audit-index-chunked".to_string(),
                created_at_ms: 2_001,
            },
        )
        .expect("create chunked object");

        let report = rebuild_memory_object_index(&db_path).expect("rebuild index");
        assert!(report.indexed_count > 1);
        assert_eq!(report.stale_after_count, 0);

        let rows = list_memory_object_index(
            &db_path,
            &MemoryObjectIndexFilter {
                project_id: Some("project-chunk".to_string()),
                limit: 20,
                ..Default::default()
            },
        )
        .expect("list chunks");
        assert!(rows.len() > 1);
        assert!(
            rows.iter()
                .all(|row| row.memory_id == "mem_index_chunked"
                    && row.chunk_id.starts_with("object-"))
        );
        assert_eq!(rows[0].chunk_ordinal, 1);
        assert!(rows[1].chunk_start_line <= rows[0].chunk_end_line);
        let first_chunk_id = rows[0].chunk_id.clone();

        let report = rebuild_memory_object_index(&db_path).expect("rebuild index again");
        assert_eq!(report.stale_after_count, 0);
        let rows_again = list_memory_object_index(
            &db_path,
            &MemoryObjectIndexFilter {
                project_id: Some("project-chunk".to_string()),
                limit: 20,
                ..Default::default()
            },
        )
        .expect("list chunks again");
        assert_eq!(rows_again[0].chunk_id, first_chunk_id);

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn evidence_ledger_writer_is_append_only_and_filterable() {
        let db_path = unique_temp_db_path("xhub_evidence_ledger");
        apply_baseline_migrations(&db_path).expect("migrate db");

        write_evidence_record(
            &db_path,
            &EvidenceLedgerRecord {
                evidence_id: "ev-provider-1".to_string(),
                created_at_ms: 1_000,
                component: "provider_route".to_string(),
                authority_mode: "candidate".to_string(),
                project_id: Some("project-a".to_string()),
                run_id: Some("run-a".to_string()),
                output_verdict: "allow".to_string(),
                reason_json: "[\"ready\"]".to_string(),
                parent_evidence_json: "[]".to_string(),
                input_ref_json: "{\"request\":\"redacted\"}".to_string(),
                payload_json: "{\"selected_provider\":\"openai\"}".to_string(),
                expires_at_ms: Some(2_000),
            },
        )
        .expect("write first evidence");
        write_evidence_record(
            &db_path,
            &EvidenceLedgerRecord {
                evidence_id: "ev-scheduler-1".to_string(),
                created_at_ms: 1_500,
                component: "scheduler_lease".to_string(),
                authority_mode: "production".to_string(),
                project_id: Some("project-a".to_string()),
                run_id: Some("run-a".to_string()),
                output_verdict: "leased".to_string(),
                reason_json: "[\"slot_acquired\"]".to_string(),
                parent_evidence_json: "[\"ev-provider-1\"]".to_string(),
                input_ref_json: "{}".to_string(),
                payload_json: "{\"scope_key\":\"project:project-a\"}".to_string(),
                expires_at_ms: None,
            },
        )
        .expect("write second evidence");

        let all = read_evidence_ledger_summary(&db_path, None, Some("project-a"), None, 10)
            .expect("read evidence");
        assert_eq!(all.total, 2);
        assert_eq!(all.latest_created_at_ms, 1_500);
        assert_eq!(all.rows[0].evidence_id, "ev-scheduler-1");
        assert_eq!(all.rows[1].evidence_id, "ev-provider-1");

        let provider =
            read_evidence_ledger_summary(&db_path, Some("provider_route"), None, None, 10)
                .expect("read provider evidence");
        assert_eq!(provider.total, 1);
        assert_eq!(provider.rows[0].output_verdict, "allow");

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn shadow_compare_report_writer_is_append_only() {
        let db_path = unique_temp_db_path("xhub_shadow_compare");
        apply_baseline_migrations(&db_path).expect("migrate db");

        write_shadow_compare_report(
            &db_path,
            &ShadowCompareReport {
                report_id: "report-1".to_string(),
                component: "scheduler".to_string(),
                compared_at_ms: 1234,
                match_result: "match".to_string(),
                rust_status_json: "{\"queue_depth\":0}".to_string(),
                node_status_json: "{\"queue_depth\":0}".to_string(),
                mismatch_json: "[]".to_string(),
            },
        )
        .expect("write report");

        let conn = Connection::open(&db_path).expect("open db");
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM rust_hub_shadow_compare_reports",
                [],
                |row| row.get(0),
            )
            .expect("report count");
        assert_eq!(count, 1);

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn shadow_compare_report_summary_reads_recent_rows() {
        let db_path = unique_temp_db_path("xhub_shadow_compare_summary");
        apply_baseline_migrations(&db_path).expect("migrate db");

        for (report_id, compared_at_ms, match_result, mismatch_json) in [
            ("report-1", 1000, "match", "[]"),
            (
                "report-2",
                2000,
                "mismatch",
                "[{\"field\":\"queue_depth\",\"rust\":0,\"node\":1}]",
            ),
            ("report-3", 3000, "match", "[]"),
        ] {
            write_shadow_compare_report(
                &db_path,
                &ShadowCompareReport {
                    report_id: report_id.to_string(),
                    component: "scheduler".to_string(),
                    compared_at_ms,
                    match_result: match_result.to_string(),
                    rust_status_json: "{}".to_string(),
                    node_status_json: "{}".to_string(),
                    mismatch_json: mismatch_json.to_string(),
                },
            )
            .expect("write report");
        }

        let summary =
            read_shadow_compare_report_summary(&db_path, "scheduler", 2).expect("read summary");
        assert_eq!(summary.total, 3);
        assert_eq!(summary.matched, 2);
        assert_eq!(summary.mismatched, 1);
        assert_eq!(summary.latest_compared_at_ms, 3000);
        assert_eq!(summary.rows.len(), 2);
        assert_eq!(summary.rows[0].report_id, "report-3");
        assert_eq!(summary.rows[1].report_id, "report-2");

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn latest_scheduler_snapshot_reads_most_recent_row() {
        let db_path = unique_temp_db_path("xhub_scheduler_snapshot");
        apply_baseline_migrations(&db_path).expect("migrate db");
        let conn = Connection::open(&db_path).expect("open db");
        conn.execute(
            "INSERT INTO rust_hub_scheduler_snapshots
             (snapshot_id, created_at_ms, in_flight_total, queue_depth, detail_json)
             VALUES ('old', 1000, 1, 2, '{}'), ('new', 2000, 3, 4, '{\"ok\":true}')",
            [],
        )
        .expect("insert snapshots");

        let latest = read_latest_scheduler_snapshot(&db_path)
            .expect("read latest")
            .expect("snapshot exists");
        assert_eq!(latest.created_at_ms, 2000);
        assert_eq!(latest.in_flight_total, 3);
        assert_eq!(latest.queue_depth, 4);

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn project_role_transcript_rows_read_thread_and_metadata_turns() {
        let db_path = unique_temp_db_path("xhub_project_role_transcript");
        let conn = Connection::open(&db_path).expect("open db");
        conn.execute_batch(
            r#"
            CREATE TABLE threads (
              thread_id TEXT PRIMARY KEY,
              thread_key TEXT NOT NULL,
              device_id TEXT NOT NULL,
              user_id TEXT NOT NULL,
              app_id TEXT NOT NULL,
              project_id TEXT NOT NULL,
              created_at_ms INTEGER NOT NULL,
              updated_at_ms INTEGER NOT NULL
            );
            CREATE TABLE turns (
              turn_id TEXT PRIMARY KEY,
              thread_id TEXT NOT NULL,
              request_id TEXT,
              role TEXT NOT NULL,
              content TEXT NOT NULL,
              is_private INTEGER NOT NULL,
              created_at_ms INTEGER NOT NULL,
              role_metadata_json TEXT,
              client_message_id TEXT,
              source_role TEXT,
              target_role TEXT,
              dispatch_id TEXT,
              dispatch_kind TEXT,
              run_id TEXT,
              launch_run_id TEXT,
              reviewer_note_id TEXT,
              status TEXT
            );
            INSERT INTO threads(
              thread_id, thread_key, device_id, user_id, app_id, project_id, created_at_ms, updated_at_ms
            ) VALUES (
              'thread-1', 'xterminal_project_project-1', 'dev-1', 'user-1', 'x_terminal', 'project-1', 1, 3
            );
            INSERT INTO turns(
              turn_id, thread_id, request_id, role, content, is_private, created_at_ms,
              role_metadata_json, client_message_id, source_role, target_role,
              dispatch_id, dispatch_kind, run_id, launch_run_id, reviewer_note_id, status
            ) VALUES
            (
              'turn-1', 'thread-1', 'req-1', 'user', 'dispatch', 0, 1,
              '{"schema_version":"xhub.role_turn_metadata.v1","source_role":"supervisor","project_id":"project-1","dispatch_id":"dispatch-1","dispatch_kind":"supervisor_to_coder"}',
              'msg-1', 'supervisor', 'coder', 'dispatch-1', 'supervisor_to_coder', '', '', '', 'dispatched'
            ),
            (
              'turn-2', 'thread-1', 'req-1', 'assistant', 'reply', 0, 2,
              '{"schema_version":"xhub.role_turn_metadata.v1","source_role":"coder","project_id":"project-1","dispatch_id":"dispatch-1","dispatch_kind":"coder_reply"}',
              'msg-2', 'coder', 'supervisor', 'dispatch-1', 'coder_reply', '', '', '', 'completed'
            );
            "#,
        )
        .expect("seed db");

        let rows = read_project_role_transcript_rows(
            &db_path,
            ProjectRoleTranscriptQuery {
                device_id: Some("dev-1".to_string()),
                app_id: Some("x_terminal".to_string()),
                project_id: "project-1".to_string(),
                thread_key: "xterminal_project_project-1".to_string(),
                limit: 10,
            },
        )
        .expect("read transcript rows");

        let thread = rows.thread.expect("thread");
        assert_eq!(thread.thread_id, "thread-1");
        assert_eq!(rows.turns_newest_first.len(), 2);
        assert_eq!(rows.turns_newest_first[0].turn_id, "turn-2");
        assert_eq!(rows.turns_newest_first[0].source_role, "coder");
        assert_eq!(
            rows.turns_newest_first[1].dispatch_kind,
            "supervisor_to_coder"
        );

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn project_role_transcript_rows_tolerate_legacy_turn_columns() {
        let db_path = unique_temp_db_path("xhub_project_role_transcript_legacy");
        let conn = Connection::open(&db_path).expect("open db");
        conn.execute_batch(
            r#"
            CREATE TABLE threads (
              thread_id TEXT PRIMARY KEY,
              thread_key TEXT NOT NULL,
              device_id TEXT NOT NULL,
              user_id TEXT NOT NULL,
              app_id TEXT NOT NULL,
              project_id TEXT NOT NULL,
              created_at_ms INTEGER NOT NULL,
              updated_at_ms INTEGER NOT NULL
            );
            CREATE TABLE turns (
              turn_id TEXT PRIMARY KEY,
              thread_id TEXT NOT NULL,
              request_id TEXT,
              role TEXT NOT NULL,
              content TEXT NOT NULL,
              is_private INTEGER NOT NULL,
              created_at_ms INTEGER NOT NULL
            );
            INSERT INTO threads VALUES (
              'thread-legacy', 'xterminal_project_project-legacy', 'dev-1', 'user-1', 'x_terminal', 'project-legacy', 1, 2
            );
            INSERT INTO turns VALUES (
              'turn-legacy', 'thread-legacy', 'req-legacy', 'user', 'legacy content', 0, 2
            );
            "#,
        )
        .expect("seed legacy db");

        let rows = read_project_role_transcript_rows(
            &db_path,
            ProjectRoleTranscriptQuery {
                device_id: None,
                app_id: None,
                project_id: "project-legacy".to_string(),
                thread_key: "xterminal_project_project-legacy".to_string(),
                limit: 10,
            },
        )
        .expect("read legacy transcript rows");

        assert_eq!(rows.turns_newest_first.len(), 1);
        assert_eq!(rows.turns_newest_first[0].content, "legacy content");
        assert!(rows.turns_newest_first[0].role_metadata_json.is_empty());

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn skill_policy_pin_grant_and_audit_roundtrip() {
        let db_path = unique_temp_db_path("xhub_skill_policy");
        apply_baseline_migrations(&db_path).expect("migrate db");

        upsert_skill_pin(
            &db_path,
            &SkillPinRecord {
                scope_key: "project:demo".to_string(),
                skill_id: "memory-core".to_string(),
                pinned_by: "test".to_string(),
            },
        )
        .expect("pin");
        upsert_skill_grant(
            &db_path,
            &SkillGrantRecord {
                scope_key: "project:demo".to_string(),
                skill_id: "memory-core".to_string(),
                capability: "memory.read".to_string(),
                granted_by: "test".to_string(),
            },
        )
        .expect("grant");

        let binding =
            read_skill_policy_binding(&db_path, "project:demo", "memory-core").expect("binding");
        assert!(binding.pinned);
        assert_eq!(binding.granted_capabilities, vec!["memory.read"]);

        write_skill_preflight_audit(
            &db_path,
            &SkillPreflightAuditRecord {
                event_id: "evt-1".to_string(),
                scope_key: "project:demo".to_string(),
                request_id: "req-1".to_string(),
                audit_ref: "audit-1".to_string(),
                skill_id: "memory-core".to_string(),
                decision: "allow".to_string(),
                ok: true,
                reason_json: "[]".to_string(),
                detail_json: "{\"schema_version\":\"xhub.skills_preflight.audit.v1\"}".to_string(),
            },
        )
        .expect("audit");
        write_skill_preflight_audit(
            &db_path,
            &SkillPreflightAuditRecord {
                event_id: "evt-2".to_string(),
                scope_key: "project:demo".to_string(),
                request_id: "req-2".to_string(),
                audit_ref: "audit-2".to_string(),
                skill_id: "memory-core".to_string(),
                decision: "deny".to_string(),
                ok: false,
                reason_json: "[\"skill_pin_required\"]".to_string(),
                detail_json: "{\"schema_version\":\"xhub.skills_preflight.audit.v1\"}".to_string(),
            },
        )
        .expect("audit 2");

        let conn = Connection::open(&db_path).expect("open db");
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM rust_hub_skill_preflight_audit",
                [],
                |row| row.get(0),
            )
            .expect("audit count");
        assert_eq!(count, 2);

        let summary = read_skill_preflight_audit_summary(
            &db_path,
            Some("project:demo"),
            Some("memory-core"),
            10,
        )
        .expect("audit summary");
        assert_eq!(summary.total, 2);
        assert_eq!(summary.allowed, 1);
        assert_eq!(summary.denied, 1);
        assert_eq!(summary.rows.len(), 2);
        assert!(summary.rows.iter().any(|row| row.event_id == "evt-1"));

        let prune =
            prune_skill_preflight_audit_by_max_rows(&db_path, 1).expect("audit prune max rows");
        assert_eq!(prune.deleted_rows, 1);
        assert_eq!(prune.remaining_rows, 1);

        for (event_id, operation, capability, actor, result) in [
            ("policy-evt-1", "pin", None, "operator", "applied"),
            (
                "policy-evt-2",
                "grant",
                Some("memory.read"),
                "operator",
                "applied",
            ),
            (
                "policy-evt-3",
                "revoke_grant",
                Some("memory.read"),
                "operator",
                "applied",
            ),
            ("policy-evt-4", "unpin", None, "operator", "applied"),
        ] {
            write_skill_policy_event(
                &db_path,
                &SkillPolicyEventRecord {
                    event_id: event_id.to_string(),
                    operation: operation.to_string(),
                    scope_key: "project:demo".to_string(),
                    skill_id: "memory-core".to_string(),
                    capability: capability.map(str::to_string),
                    actor: actor.to_string(),
                    result: result.to_string(),
                    detail_json: "{}".to_string(),
                },
            )
            .expect("policy event");
        }
        let events = read_skill_policy_event_summary(
            &db_path,
            Some("project:demo"),
            Some("memory-core"),
            10,
        )
        .expect("policy events");
        assert_eq!(events.total, 4);
        assert_eq!(events.rows.len(), 4);
        assert!(events
            .rows
            .iter()
            .any(|row| row.operation == "revoke_grant"));

        let event_prune =
            prune_skill_policy_events_by_max_rows(&db_path, 2).expect("policy event prune");
        assert_eq!(event_prune.deleted_rows, 2);
        assert_eq!(event_prune.remaining_rows, 2);
        let events = read_skill_policy_event_summary(
            &db_path,
            Some("project:demo"),
            Some("memory-core"),
            10,
        )
        .expect("policy events after prune");
        assert_eq!(events.total, 2);
        assert_eq!(events.rows.len(), 2);

        let store_summary = read_skill_policy_store_summary(&db_path).expect("store summary");
        assert_eq!(store_summary.active_pin_count, 1);
        assert_eq!(store_summary.active_grant_count, 1);
        assert_eq!(store_summary.preflight_audit_count, 1);
        assert_eq!(store_summary.policy_event_count, 2);
        assert!(store_summary.latest_policy_event_ms > 0);

        let revoked_grant =
            revoke_skill_grant(&db_path, "project:demo", "memory-core", "memory.read")
                .expect("revoke grant");
        assert_eq!(revoked_grant.revoked_rows, 1);
        let binding =
            read_skill_policy_binding(&db_path, "project:demo", "memory-core").expect("binding");
        assert!(binding.pinned);
        assert!(binding.granted_capabilities.is_empty());

        let revoked_pin =
            revoke_skill_pin(&db_path, "project:demo", "memory-core").expect("revoke pin");
        assert_eq!(revoked_pin.revoked_rows, 1);
        let binding =
            read_skill_policy_binding(&db_path, "project:demo", "memory-core").expect("binding");
        assert!(!binding.pinned);
        assert!(binding.granted_capabilities.is_empty());

        upsert_skill_pin(
            &db_path,
            &SkillPinRecord {
                scope_key: "project:demo".to_string(),
                skill_id: "memory-core".to_string(),
                pinned_by: "test".to_string(),
            },
        )
        .expect("repin");
        let binding =
            read_skill_policy_binding(&db_path, "project:demo", "memory-core").expect("binding");
        assert!(binding.pinned);

        let _ = std::fs::remove_file(&db_path);
    }

    fn unique_temp_db_path(prefix: &str) -> std::path::PathBuf {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        std::env::temp_dir().join(format!("{prefix}_{}_{}.sqlite3", std::process::id(), now))
    }
}
