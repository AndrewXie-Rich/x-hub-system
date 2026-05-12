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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migrations_are_idempotent_and_create_scheduler_tables() {
        let db_path = unique_temp_db_path("xhub_migrations");

        let first = apply_baseline_migrations(&db_path).expect("first migration run");
        assert_eq!(first.len(), 6);
        assert!(first.iter().all(|item| item.applied));

        let second = apply_baseline_migrations(&db_path).expect("second migration run");
        assert_eq!(second.len(), 6);
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
                     'rust_hub_scheduler_scope_counters'
                   )",
                [],
                |row| row.get(0),
            )
            .expect("table count");
        assert_eq!(table_count, 5);

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
