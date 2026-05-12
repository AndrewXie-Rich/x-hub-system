use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use rusqlite::{params, Connection, OpenFlags, OptionalExtension, TransactionBehavior};
use xhub_core::now_ms;

pub const STATUS_QUEUED: &str = "queued";
pub const STATUS_LEASED: &str = "leased";
pub const STATUS_COMPLETED: &str = "completed";
pub const STATUS_FAILED: &str = "failed";
pub const STATUS_CANCELED: &str = "canceled";

const EVENT_ENQUEUED: &str = "run_enqueued";
const EVENT_LEASE_ACQUIRED: &str = "lease_acquired";
const EVENT_LEASE_HEARTBEAT: &str = "lease_heartbeat";
const EVENT_LEASE_RELEASED: &str = "lease_released";
const EVENT_LEASE_EXPIRED: &str = "lease_expired";
const EVENT_RUN_CANCELED: &str = "run_canceled";
const EVENT_QUEUE_TIMEOUT: &str = "queue_timeout";

static ID_COUNTER: AtomicU64 = AtomicU64::new(1);

#[derive(Debug, Clone)]
pub struct SchedulerConfig {
    pub global_concurrency: u32,
    pub per_scope_concurrency: u32,
    pub queue_limit: u32,
    pub queue_timeout_ms: u64,
}

impl Default for SchedulerConfig {
    fn default() -> Self {
        Self {
            global_concurrency: 6,
            per_scope_concurrency: 2,
            queue_limit: 128,
            queue_timeout_ms: 20_000,
        }
    }
}

#[derive(Debug, Clone)]
pub struct SchedulerSnapshot {
    pub schema_version: &'static str,
    pub source: &'static str,
    pub captured_at_ms: u128,
    pub in_flight_total: u32,
    pub queue_depth: u32,
    pub oldest_queued_ms: u64,
}

impl SchedulerSnapshot {
    pub fn shadow_empty() -> Self {
        Self {
            schema_version: "xhub.scheduler_status.v1",
            source: "rust_hub_shadow",
            captured_at_ms: now_ms(),
            in_flight_total: 0,
            queue_depth: 0,
            oldest_queued_ms: 0,
        }
    }
}

#[derive(Debug, Clone)]
pub struct SchedulerStore {
    db_path: PathBuf,
    config: SchedulerConfig,
}

impl SchedulerStore {
    pub fn new(db_path: impl Into<PathBuf>, config: SchedulerConfig) -> Self {
        Self {
            db_path: db_path.into(),
            config,
        }
    }

    pub fn enqueue(&self, request: EnqueueRunRequest) -> Result<EnqueueRunResult, SchedulerError> {
        request.validate()?;
        let now = now_i64();
        let mut conn = self.open_rw()?;
        let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;

        expire_queued_runs(&tx, now, self.config.queue_timeout_ms)?;
        requeue_expired_leases(&tx, now)?;

        if let Some(existing) = find_idempotent_run(
            &tx,
            request.scope_key.as_str(),
            request.idempotency_key.as_str(),
        )? {
            rebuild_counters_and_snapshot(&tx, now)?;
            tx.commit()?;
            return Ok(EnqueueRunResult {
                run: existing,
                inserted: false,
            });
        }

        let queued_count = count_status(&tx, STATUS_QUEUED)?;
        if queued_count >= self.config.queue_limit as i64 {
            return Err(SchedulerError::QueueFull {
                queue_limit: self.config.queue_limit,
            });
        }

        let run_id = request
            .run_id
            .unwrap_or_else(|| unique_id("run", now as u128));
        let not_before_ms = request.not_before_ms.unwrap_or(0);
        let payload_json = normalize_json_object(request.payload_json);
        tx.execute(
            "INSERT INTO rust_hub_run_queue
             (run_id, request_id, scope_key, project_id, device_id, task_type, status,
              priority, idempotency_key, not_before_ms, created_at_ms, updated_at_ms, payload_json)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?11, ?12)",
            params![
                run_id,
                request.request_id,
                request.scope_key,
                request.project_id,
                request.device_id,
                request.task_type,
                STATUS_QUEUED,
                request.priority,
                request.idempotency_key,
                not_before_ms,
                now,
                payload_json,
            ],
        )?;
        insert_event(
            &tx,
            &unique_id("evt", now as u128),
            Some(run_id.as_str()),
            EVENT_ENQUEUED,
            now,
            Some(request.scope_key.as_str()),
            "{}",
        )?;
        rebuild_counters_and_snapshot(&tx, now)?;
        let run = load_run(&tx, run_id.as_str())?;
        tx.commit()?;

        Ok(EnqueueRunResult {
            run,
            inserted: true,
        })
    }

    pub fn acquire_next(
        &self,
        lease_owner: &str,
        lease_duration_ms: u64,
    ) -> Result<Option<LeasedRun>, SchedulerError> {
        if lease_owner.trim().is_empty() {
            return Err(SchedulerError::InvalidInput(
                "lease_owner must not be empty".to_string(),
            ));
        }
        if lease_duration_ms == 0 {
            return Err(SchedulerError::InvalidInput(
                "lease_duration_ms must be greater than zero".to_string(),
            ));
        }

        let now = now_i64();
        let mut conn = self.open_rw()?;
        let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;

        expire_queued_runs(&tx, now, self.config.queue_timeout_ms)?;
        requeue_expired_leases(&tx, now)?;

        let in_flight = count_status(&tx, STATUS_LEASED)?;
        if in_flight >= self.config.global_concurrency as i64 {
            rebuild_counters_and_snapshot(&tx, now)?;
            tx.commit()?;
            return Ok(None);
        }

        let candidates = load_candidate_runs(&tx, now)?;
        let mut chosen = None;
        for candidate in candidates {
            let scope_in_flight =
                count_scope_status(&tx, candidate.scope_key.as_str(), STATUS_LEASED)?;
            if scope_in_flight < self.config.per_scope_concurrency as i64 {
                chosen = Some(candidate);
                break;
            }
        }

        let Some(run) = chosen else {
            rebuild_counters_and_snapshot(&tx, now)?;
            tx.commit()?;
            return Ok(None);
        };

        let leased = lease_run(&tx, run, lease_owner, lease_duration_ms, now, "{}")?;
        rebuild_counters_and_snapshot(&tx, now)?;
        tx.commit()?;

        Ok(Some(leased))
    }

    pub fn acquire_run(
        &self,
        run_id: &str,
        lease_owner: &str,
        lease_duration_ms: u64,
    ) -> Result<Option<LeasedRun>, SchedulerError> {
        if run_id.trim().is_empty() {
            return Err(SchedulerError::InvalidInput(
                "run_id must not be empty".to_string(),
            ));
        }
        if lease_owner.trim().is_empty() {
            return Err(SchedulerError::InvalidInput(
                "lease_owner must not be empty".to_string(),
            ));
        }
        if lease_duration_ms == 0 {
            return Err(SchedulerError::InvalidInput(
                "lease_duration_ms must be greater than zero".to_string(),
            ));
        }

        let now = now_i64();
        let mut conn = self.open_rw()?;
        let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;

        expire_queued_runs(&tx, now, self.config.queue_timeout_ms)?;
        requeue_expired_leases(&tx, now)?;

        let run = load_run(&tx, run_id)?;
        if run.status == STATUS_LEASED {
            let lease = load_lease(&tx, run_id)?;
            rebuild_counters_and_snapshot(&tx, now)?;
            tx.commit()?;
            return Ok(Some(LeasedRun {
                run_id: run.run_id,
                request_id: run.request_id,
                scope_key: run.scope_key,
                task_type: run.task_type,
                payload_json: run.payload_json,
                lease_owner: lease.lease_owner,
                lease_token: lease.lease_token,
                lease_expires_at_ms: lease.lease_expires_at_ms,
                attempt: lease.attempt,
                queued_ms: now.saturating_sub(run.created_at_ms),
            }));
        }
        if run.status != STATUS_QUEUED {
            rebuild_counters_and_snapshot(&tx, now)?;
            tx.commit()?;
            return Ok(None);
        }

        let in_flight = count_status(&tx, STATUS_LEASED)?;
        let scope_in_flight = count_scope_status(&tx, run.scope_key.as_str(), STATUS_LEASED)?;
        if in_flight >= self.config.global_concurrency as i64
            || scope_in_flight >= self.config.per_scope_concurrency as i64
        {
            rebuild_counters_and_snapshot(&tx, now)?;
            tx.commit()?;
            return Ok(None);
        }

        let leased = lease_run(
            &tx,
            run,
            lease_owner,
            lease_duration_ms,
            now,
            "{\"mode\":\"exact_run\"}",
        )?;
        rebuild_counters_and_snapshot(&tx, now)?;
        tx.commit()?;

        Ok(Some(leased))
    }

    pub fn claim(
        &self,
        request: EnqueueRunRequest,
        lease_owner: &str,
        lease_duration_ms: u64,
    ) -> Result<ClaimRunResult, SchedulerError> {
        request.validate()?;
        if lease_owner.trim().is_empty() {
            return Err(SchedulerError::InvalidInput(
                "lease_owner must not be empty".to_string(),
            ));
        }
        if lease_duration_ms == 0 {
            return Err(SchedulerError::InvalidInput(
                "lease_duration_ms must be greater than zero".to_string(),
            ));
        }

        let now = now_i64();
        let mut conn = self.open_rw()?;
        let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;

        expire_queued_runs(&tx, now, self.config.queue_timeout_ms)?;
        requeue_expired_leases(&tx, now)?;

        let mut inserted = false;
        let run = if let Some(existing) = find_idempotent_run(
            &tx,
            request.scope_key.as_str(),
            request.idempotency_key.as_str(),
        )? {
            existing
        } else {
            let queued_count = count_status(&tx, STATUS_QUEUED)?;
            if queued_count >= self.config.queue_limit as i64 {
                return Err(SchedulerError::QueueFull {
                    queue_limit: self.config.queue_limit,
                });
            }

            let run_id = request
                .run_id
                .as_ref()
                .cloned()
                .unwrap_or_else(|| unique_id("run", now as u128));
            let not_before_ms = request.not_before_ms.unwrap_or(0);
            let payload_json = normalize_json_object(request.payload_json.clone());
            tx.execute(
                "INSERT INTO rust_hub_run_queue
                 (run_id, request_id, scope_key, project_id, device_id, task_type, status,
                  priority, idempotency_key, not_before_ms, created_at_ms, updated_at_ms, payload_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?11, ?12)",
                params![
                    run_id.as_str(),
                    request.request_id.as_str(),
                    request.scope_key.as_str(),
                    request.project_id.as_deref(),
                    request.device_id.as_deref(),
                    request.task_type.as_str(),
                    STATUS_QUEUED,
                    request.priority,
                    request.idempotency_key.as_str(),
                    not_before_ms,
                    now,
                    payload_json.as_str(),
                ],
            )?;
            insert_event(
                &tx,
                &unique_id("evt", now as u128),
                Some(run_id.as_str()),
                EVENT_ENQUEUED,
                now,
                Some(request.scope_key.as_str()),
                "{\"mode\":\"claim\"}",
            )?;
            inserted = true;
            load_run(&tx, run_id.as_str())?
        };

        if run.status == STATUS_LEASED {
            let lease = load_lease(&tx, run.run_id.as_str())?;
            rebuild_counters_and_snapshot(&tx, now)?;
            tx.commit()?;
            return Ok(ClaimRunResult {
                run: run.clone(),
                inserted,
                leased: Some(LeasedRun {
                    run_id: run.run_id,
                    request_id: run.request_id,
                    scope_key: run.scope_key,
                    task_type: run.task_type,
                    payload_json: run.payload_json,
                    lease_owner: lease.lease_owner,
                    lease_token: lease.lease_token,
                    lease_expires_at_ms: lease.lease_expires_at_ms,
                    attempt: lease.attempt,
                    queued_ms: now.saturating_sub(run.created_at_ms),
                }),
            });
        }

        if run.status != STATUS_QUEUED {
            rebuild_counters_and_snapshot(&tx, now)?;
            tx.commit()?;
            return Ok(ClaimRunResult {
                run,
                inserted,
                leased: None,
            });
        }

        let in_flight = count_status(&tx, STATUS_LEASED)?;
        if in_flight >= self.config.global_concurrency as i64 {
            rebuild_counters_and_snapshot(&tx, now)?;
            tx.commit()?;
            return Ok(ClaimRunResult {
                run,
                inserted,
                leased: None,
            });
        }

        let candidates = load_candidate_runs(&tx, now)?;
        let mut chosen = None;
        for candidate in candidates {
            let scope_in_flight =
                count_scope_status(&tx, candidate.scope_key.as_str(), STATUS_LEASED)?;
            if scope_in_flight < self.config.per_scope_concurrency as i64 {
                chosen = Some(candidate);
                break;
            }
        }

        if chosen.as_ref().map(|candidate| candidate.run_id.as_str()) != Some(run.run_id.as_str()) {
            rebuild_counters_and_snapshot(&tx, now)?;
            tx.commit()?;
            return Ok(ClaimRunResult {
                run,
                inserted,
                leased: None,
            });
        }

        let leased = lease_run(
            &tx,
            run.clone(),
            lease_owner,
            lease_duration_ms,
            now,
            "{\"mode\":\"claim\"}",
        )?;
        rebuild_counters_and_snapshot(&tx, now)?;
        tx.commit()?;
        let mut claimed_run = run;
        claimed_run.status = STATUS_LEASED.to_string();

        Ok(ClaimRunResult {
            run: claimed_run,
            inserted,
            leased: Some(leased),
        })
    }

    pub fn heartbeat(
        &self,
        run_id: &str,
        lease_token: &str,
        lease_duration_ms: u64,
    ) -> Result<LeaseHeartbeatResult, SchedulerError> {
        if lease_duration_ms == 0 {
            return Err(SchedulerError::InvalidInput(
                "lease_duration_ms must be greater than zero".to_string(),
            ));
        }
        let now = now_i64();
        let mut conn = self.open_rw()?;
        let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
        requeue_expired_leases(&tx, now)?;
        let lease = load_lease(&tx, run_id)?;
        ensure_lease_token(&lease, lease_token)?;

        let lease_expires_at_ms = now + lease_duration_ms as i64;
        tx.execute(
            "UPDATE rust_hub_run_leases
             SET lease_expires_at_ms = ?2, heartbeat_at_ms = ?3
             WHERE run_id = ?1",
            params![run_id, lease_expires_at_ms, now],
        )?;
        insert_event(
            &tx,
            &unique_id("evt", now as u128),
            Some(run_id),
            EVENT_LEASE_HEARTBEAT,
            now,
            None,
            "{}",
        )?;
        rebuild_counters_and_snapshot(&tx, now)?;
        tx.commit()?;

        Ok(LeaseHeartbeatResult {
            run_id: run_id.to_string(),
            lease_expires_at_ms,
        })
    }

    pub fn release(
        &self,
        run_id: &str,
        lease_token: &str,
        outcome: ReleaseOutcome,
    ) -> Result<ReleaseRunResult, SchedulerError> {
        let now = now_i64();
        let mut conn = self.open_rw()?;
        let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
        requeue_expired_leases(&tx, now)?;
        let lease = load_lease(&tx, run_id)?;
        ensure_lease_token(&lease, lease_token)?;

        let (status, not_before_ms, error_code, error_message) = match outcome {
            ReleaseOutcome::Completed => (STATUS_COMPLETED, 0, None, None),
            ReleaseOutcome::Failed {
                error_code,
                error_message,
            } => (
                STATUS_FAILED,
                0,
                Some(error_code),
                error_message.filter(|value| !value.trim().is_empty()),
            ),
            ReleaseOutcome::Requeue { not_before_ms } => (
                STATUS_QUEUED,
                not_before_ms.unwrap_or(0),
                Some("released_for_retry".to_string()),
                None,
            ),
        };

        tx.execute(
            "DELETE FROM rust_hub_run_leases WHERE run_id = ?1",
            params![run_id],
        )?;
        tx.execute(
            "UPDATE rust_hub_run_queue
             SET status = ?2,
                 not_before_ms = ?3,
                 updated_at_ms = ?4,
                 last_error_code = ?5,
                 last_error_message = ?6
             WHERE run_id = ?1",
            params![
                run_id,
                status,
                not_before_ms,
                now,
                error_code,
                error_message
            ],
        )?;
        insert_event(
            &tx,
            &unique_id("evt", now as u128),
            Some(run_id),
            EVENT_LEASE_RELEASED,
            now,
            None,
            "{}",
        )?;
        rebuild_counters_and_snapshot(&tx, now)?;
        tx.commit()?;

        Ok(ReleaseRunResult {
            run_id: run_id.to_string(),
            status: status.to_string(),
        })
    }

    pub fn cancel(
        &self,
        run_id: &str,
        reason: Option<&str>,
    ) -> Result<CancelRunResult, SchedulerError> {
        let now = now_i64();
        let mut conn = self.open_rw()?;
        let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
        requeue_expired_leases(&tx, now)?;
        let run = load_run(&tx, run_id)?;
        if matches!(
            run.status.as_str(),
            STATUS_COMPLETED | STATUS_FAILED | STATUS_CANCELED
        ) {
            return Err(SchedulerError::TerminalRun {
                run_id: run_id.to_string(),
                status: run.status,
            });
        }

        tx.execute(
            "DELETE FROM rust_hub_run_leases WHERE run_id = ?1",
            params![run_id],
        )?;
        tx.execute(
            "UPDATE rust_hub_run_queue
             SET status = ?2,
                 updated_at_ms = ?3,
                 last_error_code = ?4,
                 last_error_message = ?5
             WHERE run_id = ?1",
            params![run_id, STATUS_CANCELED, now, "canceled", reason],
        )?;
        insert_event(
            &tx,
            &unique_id("evt", now as u128),
            Some(run_id),
            EVENT_RUN_CANCELED,
            now,
            Some(run.scope_key.as_str()),
            "{}",
        )?;
        rebuild_counters_and_snapshot(&tx, now)?;
        tx.commit()?;

        Ok(CancelRunResult {
            run_id: run_id.to_string(),
            status: STATUS_CANCELED.to_string(),
        })
    }

    pub fn status_view(
        &self,
        include_queue_items: bool,
        queue_items_limit: usize,
    ) -> Result<SchedulerStatusView, SchedulerError> {
        let conn = self.open_ro()?;
        let now = now_i64();
        let in_flight_total = count_status(&conn, STATUS_LEASED)? as i32;
        let queue_depth = count_status(&conn, STATUS_QUEUED)? as i32;
        let oldest_queued_ms = oldest_queued_ms(&conn, now)? as i64;
        let updated_at_ms = latest_snapshot_time(&conn)?.unwrap_or(now);
        let in_flight_by_scope = scope_counters(&conn, "in_flight")?;
        let queued_by_scope = scope_counters(&conn, "queued")?;
        let queue_items = if include_queue_items {
            queued_items(&conn, now, queue_items_limit)?
        } else {
            Vec::new()
        };

        Ok(SchedulerStatusView {
            updated_at_ms,
            in_flight_total,
            queue_depth,
            oldest_queued_ms,
            in_flight_by_scope,
            queued_by_scope,
            queue_items,
        })
    }

    pub fn lease_shadow_evidence(
        &self,
        run_id_prefix: &str,
        stale_after_ms: u64,
        recent_limit: usize,
    ) -> Result<LeaseShadowEvidence, SchedulerError> {
        let prefix = if run_id_prefix.trim().is_empty() {
            "node_paid_ai_"
        } else {
            run_id_prefix.trim()
        };
        let like_pattern = format!("{prefix}%");
        let now = now_i64();
        let stale_cutoff = now.saturating_sub(stale_after_ms as i64);
        let conn = self.open_ro()?;

        let total_runs = count_runs_like(&conn, like_pattern.as_str())?;
        let queued = count_runs_like_status(&conn, like_pattern.as_str(), STATUS_QUEUED)?;
        let leased = count_runs_like_status(&conn, like_pattern.as_str(), STATUS_LEASED)?;
        let completed = count_runs_like_status(&conn, like_pattern.as_str(), STATUS_COMPLETED)?;
        let failed = count_runs_like_status(&conn, like_pattern.as_str(), STATUS_FAILED)?;
        let canceled = count_runs_like_status(&conn, like_pattern.as_str(), STATUS_CANCELED)?;
        let stale_active = count_stale_active_runs(&conn, like_pattern.as_str(), stale_cutoff)?;
        let orphaned_leases = count_orphaned_leases(&conn, like_pattern.as_str())?;
        let event_counts = lease_shadow_event_counts(&conn, like_pattern.as_str())?;
        let recent = lease_shadow_recent_rows(&conn, like_pattern.as_str(), now, recent_limit)?;

        Ok(LeaseShadowEvidence {
            generated_at_ms: now,
            run_id_prefix: prefix.to_string(),
            stale_after_ms: stale_after_ms as i64,
            total_runs,
            queued,
            leased,
            completed,
            failed,
            canceled,
            stale_active,
            orphaned_leases,
            event_counts,
            recent,
        })
    }

    fn open_rw(&self) -> Result<Connection, SchedulerError> {
        ensure_parent_dir(self.db_path.as_path())?;
        let conn = Connection::open(self.db_path.as_path())?;
        apply_pragmas(&conn)?;
        Ok(conn)
    }

    fn open_ro(&self) -> Result<Connection, SchedulerError> {
        let conn = Connection::open_with_flags(
            self.db_path.as_path(),
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )?;
        apply_pragmas(&conn)?;
        Ok(conn)
    }
}

#[derive(Debug, Clone)]
pub struct EnqueueRunRequest {
    pub run_id: Option<String>,
    pub request_id: String,
    pub scope_key: String,
    pub project_id: Option<String>,
    pub device_id: Option<String>,
    pub task_type: String,
    pub priority: i32,
    pub idempotency_key: String,
    pub not_before_ms: Option<i64>,
    pub payload_json: Option<String>,
}

impl EnqueueRunRequest {
    fn validate(&self) -> Result<(), SchedulerError> {
        for (field, value) in [
            ("request_id", self.request_id.as_str()),
            ("scope_key", self.scope_key.as_str()),
            ("task_type", self.task_type.as_str()),
            ("idempotency_key", self.idempotency_key.as_str()),
        ] {
            if value.trim().is_empty() {
                return Err(SchedulerError::InvalidInput(format!(
                    "{field} must not be empty"
                )));
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EnqueueRunResult {
    pub run: RunRecord,
    pub inserted: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClaimRunResult {
    pub run: RunRecord,
    pub inserted: bool,
    pub leased: Option<LeasedRun>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunRecord {
    pub run_id: String,
    pub request_id: String,
    pub scope_key: String,
    pub task_type: String,
    pub status: String,
    pub priority: i32,
    pub created_at_ms: i64,
    pub payload_json: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LeasedRun {
    pub run_id: String,
    pub request_id: String,
    pub scope_key: String,
    pub task_type: String,
    pub payload_json: String,
    pub lease_owner: String,
    pub lease_token: String,
    pub lease_expires_at_ms: i64,
    pub attempt: i64,
    pub queued_ms: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LeaseHeartbeatResult {
    pub run_id: String,
    pub lease_expires_at_ms: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReleaseOutcome {
    Completed,
    Failed {
        error_code: String,
        error_message: Option<String>,
    },
    Requeue {
        not_before_ms: Option<i64>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReleaseRunResult {
    pub run_id: String,
    pub status: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CancelRunResult {
    pub run_id: String,
    pub status: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SchedulerStatusView {
    pub updated_at_ms: i64,
    pub in_flight_total: i32,
    pub queue_depth: i32,
    pub oldest_queued_ms: i64,
    pub in_flight_by_scope: Vec<ScopeCounter>,
    pub queued_by_scope: Vec<ScopeCounter>,
    pub queue_items: Vec<QueueItemView>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScopeCounter {
    pub scope_key: String,
    pub count: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QueueItemView {
    pub request_id: String,
    pub scope_key: String,
    pub enqueued_at_ms: i64,
    pub queued_ms: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LeaseShadowEvidence {
    pub generated_at_ms: i64,
    pub run_id_prefix: String,
    pub stale_after_ms: i64,
    pub total_runs: i64,
    pub queued: i64,
    pub leased: i64,
    pub completed: i64,
    pub failed: i64,
    pub canceled: i64,
    pub stale_active: i64,
    pub orphaned_leases: i64,
    pub event_counts: Vec<LeaseShadowEventCount>,
    pub recent: Vec<LeaseShadowRunEvidence>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LeaseShadowEventCount {
    pub event_type: String,
    pub count: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LeaseShadowRunEvidence {
    pub run_id: String,
    pub request_id: String,
    pub scope_key: String,
    pub status: String,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub age_ms: i64,
    pub lease_owner: String,
    pub lease_expires_at_ms: i64,
    pub event_count: i64,
    pub last_event_type: String,
    pub last_event_at_ms: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct LeaseRecord {
    lease_owner: String,
    lease_token: String,
    lease_expires_at_ms: i64,
    attempt: i64,
}

#[derive(Debug)]
pub enum SchedulerError {
    Db(rusqlite::Error),
    Io(String),
    InvalidInput(String),
    QueueFull { queue_limit: u32 },
    RunNotFound(String),
    LeaseNotFound(String),
    LeaseTokenMismatch(String),
    TerminalRun { run_id: String, status: String },
}

impl std::fmt::Display for SchedulerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SchedulerError::Db(err) => write!(f, "scheduler db error: {err}"),
            SchedulerError::Io(err) => write!(f, "scheduler io error: {err}"),
            SchedulerError::InvalidInput(err) => write!(f, "invalid scheduler input: {err}"),
            SchedulerError::QueueFull { queue_limit } => {
                write!(f, "scheduler queue is full: limit={queue_limit}")
            }
            SchedulerError::RunNotFound(run_id) => write!(f, "scheduler run not found: {run_id}"),
            SchedulerError::LeaseNotFound(run_id) => {
                write!(f, "scheduler lease not found: {run_id}")
            }
            SchedulerError::LeaseTokenMismatch(run_id) => {
                write!(f, "scheduler lease token mismatch: {run_id}")
            }
            SchedulerError::TerminalRun { run_id, status } => {
                write!(
                    f,
                    "scheduler run is terminal: run_id={run_id} status={status}"
                )
            }
        }
    }
}

impl std::error::Error for SchedulerError {}

impl From<rusqlite::Error> for SchedulerError {
    fn from(value: rusqlite::Error) -> Self {
        SchedulerError::Db(value)
    }
}

fn ensure_parent_dir(path: &Path) -> Result<(), SchedulerError> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|err| SchedulerError::Io(err.to_string()))?;
    }
    Ok(())
}

fn apply_pragmas(conn: &Connection) -> Result<(), SchedulerError> {
    conn.execute_batch(
        "PRAGMA journal_mode = WAL;
         PRAGMA synchronous = NORMAL;
         PRAGMA busy_timeout = 2000;
         PRAGMA foreign_keys = ON;",
    )?;
    Ok(())
}

fn normalize_json_object(payload_json: Option<String>) -> String {
    payload_json
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "{}".to_string())
}

fn now_i64() -> i64 {
    now_ms().min(i64::MAX as u128) as i64
}

fn unique_id(prefix: &str, now: u128) -> String {
    let seq = ID_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{prefix}_{now}_{}_{seq}", std::process::id())
}

fn count_status(conn: &Connection, status: &str) -> Result<i64, SchedulerError> {
    Ok(conn.query_row(
        "SELECT COUNT(*) FROM rust_hub_run_queue WHERE status = ?1",
        params![status],
        |row| row.get(0),
    )?)
}

fn count_scope_status(
    conn: &Connection,
    scope_key: &str,
    status: &str,
) -> Result<i64, SchedulerError> {
    Ok(conn.query_row(
        "SELECT COUNT(*) FROM rust_hub_run_queue WHERE scope_key = ?1 AND status = ?2",
        params![scope_key, status],
        |row| row.get(0),
    )?)
}

fn count_run_events(
    conn: &Connection,
    run_id: &str,
    event_type: &str,
) -> Result<i64, SchedulerError> {
    Ok(conn.query_row(
        "SELECT COUNT(*) FROM rust_hub_scheduler_events WHERE run_id = ?1 AND event_type = ?2",
        params![run_id, event_type],
        |row| row.get(0),
    )?)
}

fn find_idempotent_run(
    conn: &Connection,
    scope_key: &str,
    idempotency_key: &str,
) -> Result<Option<RunRecord>, SchedulerError> {
    let run_id = conn
        .query_row(
            "SELECT run_id FROM rust_hub_run_queue
             WHERE scope_key = ?1 AND idempotency_key = ?2",
            params![scope_key, idempotency_key],
            |row| row.get::<_, String>(0),
        )
        .optional()?;
    run_id
        .map(|value| load_run(conn, value.as_str()))
        .transpose()
}

fn load_run(conn: &Connection, run_id: &str) -> Result<RunRecord, SchedulerError> {
    conn.query_row(
        "SELECT run_id, request_id, scope_key, task_type, status, priority, created_at_ms, payload_json
         FROM rust_hub_run_queue
         WHERE run_id = ?1",
        params![run_id],
        |row| {
            Ok(RunRecord {
                run_id: row.get(0)?,
                request_id: row.get(1)?,
                scope_key: row.get(2)?,
                task_type: row.get(3)?,
                status: row.get(4)?,
                priority: row.get(5)?,
                created_at_ms: row.get(6)?,
                payload_json: row.get(7)?,
            })
        },
    )
    .optional()?
    .ok_or_else(|| SchedulerError::RunNotFound(run_id.to_string()))
}

fn load_candidate_runs(conn: &Connection, now: i64) -> Result<Vec<RunRecord>, SchedulerError> {
    let mut stmt = conn.prepare(
        "SELECT run_id, request_id, scope_key, task_type, status, priority, created_at_ms, payload_json
         FROM rust_hub_run_queue
         WHERE status = ?1 AND not_before_ms <= ?2
         ORDER BY priority DESC, created_at_ms ASC
         LIMIT 32",
    )?;
    let rows = stmt.query_map(params![STATUS_QUEUED, now], |row| {
        Ok(RunRecord {
            run_id: row.get(0)?,
            request_id: row.get(1)?,
            scope_key: row.get(2)?,
            task_type: row.get(3)?,
            status: row.get(4)?,
            priority: row.get(5)?,
            created_at_ms: row.get(6)?,
            payload_json: row.get(7)?,
        })
    })?;

    let mut runs = Vec::new();
    for row in rows {
        runs.push(row?);
    }
    Ok(runs)
}

fn load_lease(conn: &Connection, run_id: &str) -> Result<LeaseRecord, SchedulerError> {
    conn.query_row(
        "SELECT lease_owner, lease_token, lease_expires_at_ms, attempt
         FROM rust_hub_run_leases
         WHERE run_id = ?1",
        params![run_id],
        |row| {
            Ok(LeaseRecord {
                lease_owner: row.get(0)?,
                lease_token: row.get(1)?,
                lease_expires_at_ms: row.get(2)?,
                attempt: row.get(3)?,
            })
        },
    )
    .optional()?
    .ok_or_else(|| SchedulerError::LeaseNotFound(run_id.to_string()))
}

fn lease_run(
    conn: &Connection,
    run: RunRecord,
    lease_owner: &str,
    lease_duration_ms: u64,
    now: i64,
    detail_json: &str,
) -> Result<LeasedRun, SchedulerError> {
    let lease_token = unique_id("lease", now as u128);
    let attempt = count_run_events(conn, run.run_id.as_str(), EVENT_LEASE_ACQUIRED)? + 1;
    let lease_expires_at_ms = now + lease_duration_ms as i64;
    conn.execute(
        "UPDATE rust_hub_run_queue
         SET status = ?2, updated_at_ms = ?3
         WHERE run_id = ?1 AND status = ?4",
        params![run.run_id, STATUS_LEASED, now, STATUS_QUEUED],
    )?;
    conn.execute(
        "INSERT INTO rust_hub_run_leases
         (run_id, lease_owner, lease_token, lease_expires_at_ms, heartbeat_at_ms,
          acquired_at_ms, attempt)
         VALUES (?1, ?2, ?3, ?4, ?5, ?5, ?6)",
        params![
            run.run_id,
            lease_owner,
            lease_token,
            lease_expires_at_ms,
            now,
            attempt,
        ],
    )?;
    insert_event(
        conn,
        &unique_id("evt", now as u128),
        Some(run.run_id.as_str()),
        EVENT_LEASE_ACQUIRED,
        now,
        Some(run.scope_key.as_str()),
        detail_json,
    )?;

    Ok(LeasedRun {
        run_id: run.run_id,
        request_id: run.request_id,
        scope_key: run.scope_key,
        task_type: run.task_type,
        payload_json: run.payload_json,
        lease_owner: lease_owner.to_string(),
        lease_token,
        lease_expires_at_ms,
        attempt,
        queued_ms: now.saturating_sub(run.created_at_ms),
    })
}

fn ensure_lease_token(lease: &LeaseRecord, lease_token: &str) -> Result<(), SchedulerError> {
    if lease.lease_token != lease_token {
        return Err(SchedulerError::LeaseTokenMismatch(lease_token.to_string()));
    }
    Ok(())
}

fn expire_queued_runs(
    conn: &Connection,
    now: i64,
    queue_timeout_ms: u64,
) -> Result<(), SchedulerError> {
    if queue_timeout_ms == 0 {
        return Ok(());
    }
    let cutoff = now.saturating_sub(queue_timeout_ms as i64);
    let mut stmt = conn.prepare(
        "SELECT run_id, scope_key FROM rust_hub_run_queue
         WHERE status = ?1 AND created_at_ms < ?2",
    )?;
    let rows = stmt.query_map(params![STATUS_QUEUED, cutoff], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })?;
    let mut expired = Vec::new();
    for row in rows {
        expired.push(row?);
    }
    drop(stmt);

    for (run_id, scope_key) in expired {
        conn.execute(
            "UPDATE rust_hub_run_queue
             SET status = ?2,
                 updated_at_ms = ?3,
                 last_error_code = ?4,
                 last_error_message = ?5
             WHERE run_id = ?1 AND status = ?6",
            params![
                run_id,
                STATUS_FAILED,
                now,
                "queue_timeout",
                "scheduler queue timeout",
                STATUS_QUEUED,
            ],
        )?;
        insert_event(
            conn,
            &unique_id("evt", now as u128),
            Some(run_id.as_str()),
            EVENT_QUEUE_TIMEOUT,
            now,
            Some(scope_key.as_str()),
            "{}",
        )?;
    }
    Ok(())
}

fn requeue_expired_leases(conn: &Connection, now: i64) -> Result<(), SchedulerError> {
    let mut stmt = conn.prepare(
        "SELECT l.run_id, q.scope_key
         FROM rust_hub_run_leases l
         JOIN rust_hub_run_queue q ON q.run_id = l.run_id
         WHERE l.lease_expires_at_ms <= ?1",
    )?;
    let rows = stmt.query_map(params![now], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })?;
    let mut expired = Vec::new();
    for row in rows {
        expired.push(row?);
    }
    drop(stmt);

    for (run_id, scope_key) in expired {
        conn.execute(
            "DELETE FROM rust_hub_run_leases WHERE run_id = ?1",
            params![run_id],
        )?;
        conn.execute(
            "UPDATE rust_hub_run_queue
             SET status = ?2,
                 updated_at_ms = ?3,
                 last_error_code = ?4,
                 last_error_message = ?5
             WHERE run_id = ?1 AND status = ?6",
            params![
                run_id,
                STATUS_QUEUED,
                now,
                "lease_expired",
                "scheduler lease expired",
                STATUS_LEASED,
            ],
        )?;
        insert_event(
            conn,
            &unique_id("evt", now as u128),
            Some(run_id.as_str()),
            EVENT_LEASE_EXPIRED,
            now,
            Some(scope_key.as_str()),
            "{}",
        )?;
    }
    Ok(())
}

fn rebuild_counters_and_snapshot(conn: &Connection, now: i64) -> Result<(), SchedulerError> {
    conn.execute("DELETE FROM rust_hub_scheduler_scope_counters", [])?;
    conn.execute(
        "INSERT INTO rust_hub_scheduler_scope_counters
         (scope_key, in_flight, queued, oldest_queued_at_ms, updated_at_ms)
         SELECT
           scope_key,
           SUM(CASE WHEN status = 'leased' THEN 1 ELSE 0 END) AS in_flight,
           SUM(CASE WHEN status = 'queued' THEN 1 ELSE 0 END) AS queued,
           COALESCE(MIN(CASE WHEN status = 'queued' THEN created_at_ms END), 0) AS oldest_queued_at_ms,
           ?1
         FROM rust_hub_run_queue
         WHERE status IN ('queued', 'leased')
         GROUP BY scope_key",
        params![now],
    )?;

    let in_flight_total = count_status(conn, STATUS_LEASED)?;
    let queue_depth = count_status(conn, STATUS_QUEUED)?;
    let scope_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM rust_hub_scheduler_scope_counters",
        [],
        |row| row.get(0),
    )?;
    let oldest = oldest_queued_ms(conn, now)?;
    let detail_json = format!(
        "{{\"source\":\"xhub_scheduler_store\",\"scope_count\":{},\"oldest_queued_ms\":{}}}",
        scope_count, oldest
    );
    conn.execute(
        "INSERT INTO rust_hub_scheduler_snapshots
         (snapshot_id, created_at_ms, in_flight_total, queue_depth, detail_json)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![
            unique_id("snapshot", now as u128),
            now,
            in_flight_total,
            queue_depth,
            detail_json,
        ],
    )?;
    Ok(())
}

fn insert_event(
    conn: &Connection,
    event_id: &str,
    run_id: Option<&str>,
    event_type: &str,
    created_at_ms: i64,
    scope_key: Option<&str>,
    detail_json: &str,
) -> Result<(), SchedulerError> {
    conn.execute(
        "INSERT INTO rust_hub_scheduler_events
         (event_id, run_id, event_type, created_at_ms, scope_key, detail_json)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            event_id,
            run_id,
            event_type,
            created_at_ms,
            scope_key,
            detail_json,
        ],
    )?;
    Ok(())
}

fn oldest_queued_ms(conn: &Connection, now: i64) -> Result<i64, SchedulerError> {
    let oldest: Option<i64> = conn.query_row(
        "SELECT MIN(created_at_ms) FROM rust_hub_run_queue WHERE status = ?1",
        params![STATUS_QUEUED],
        |row| row.get(0),
    )?;
    Ok(oldest.map(|value| now.saturating_sub(value)).unwrap_or(0))
}

fn latest_snapshot_time(conn: &Connection) -> Result<Option<i64>, SchedulerError> {
    Ok(conn.query_row(
        "SELECT MAX(created_at_ms) FROM rust_hub_scheduler_snapshots",
        [],
        |row| row.get(0),
    )?)
}

fn scope_counters(conn: &Connection, column: &str) -> Result<Vec<ScopeCounter>, SchedulerError> {
    let sql = match column {
        "in_flight" => {
            "SELECT scope_key, in_flight FROM rust_hub_scheduler_scope_counters
             WHERE in_flight > 0 ORDER BY scope_key"
        }
        "queued" => {
            "SELECT scope_key, queued FROM rust_hub_scheduler_scope_counters
             WHERE queued > 0 ORDER BY scope_key"
        }
        _ => {
            return Err(SchedulerError::InvalidInput(
                "unknown counter column".to_string(),
            ))
        }
    };
    let mut stmt = conn.prepare(sql)?;
    let rows = stmt.query_map([], |row| {
        Ok(ScopeCounter {
            scope_key: row.get(0)?,
            count: row.get(1)?,
        })
    })?;
    let mut counters = Vec::new();
    for row in rows {
        counters.push(row?);
    }
    Ok(counters)
}

fn queued_items(
    conn: &Connection,
    now: i64,
    limit: usize,
) -> Result<Vec<QueueItemView>, SchedulerError> {
    let limit = limit.clamp(1, 200) as i64;
    let mut stmt = conn.prepare(
        "SELECT request_id, scope_key, created_at_ms
         FROM rust_hub_run_queue
         WHERE status = ?1
         ORDER BY priority DESC, created_at_ms ASC
         LIMIT ?2",
    )?;
    let rows = stmt.query_map(params![STATUS_QUEUED, limit], |row| {
        let enqueued_at_ms = row.get::<_, i64>(2)?;
        Ok(QueueItemView {
            request_id: row.get(0)?,
            scope_key: row.get(1)?,
            enqueued_at_ms,
            queued_ms: now.saturating_sub(enqueued_at_ms),
        })
    })?;
    let mut items = Vec::new();
    for row in rows {
        items.push(row?);
    }
    Ok(items)
}

fn count_runs_like(conn: &Connection, like_pattern: &str) -> Result<i64, SchedulerError> {
    Ok(conn.query_row(
        "SELECT COUNT(*) FROM rust_hub_run_queue WHERE run_id LIKE ?1",
        params![like_pattern],
        |row| row.get(0),
    )?)
}

fn count_runs_like_status(
    conn: &Connection,
    like_pattern: &str,
    status: &str,
) -> Result<i64, SchedulerError> {
    Ok(conn.query_row(
        "SELECT COUNT(*) FROM rust_hub_run_queue WHERE run_id LIKE ?1 AND status = ?2",
        params![like_pattern, status],
        |row| row.get(0),
    )?)
}

fn count_stale_active_runs(
    conn: &Connection,
    like_pattern: &str,
    stale_cutoff: i64,
) -> Result<i64, SchedulerError> {
    Ok(conn.query_row(
        "SELECT COUNT(*)
         FROM rust_hub_run_queue
         WHERE run_id LIKE ?1
           AND status IN ('queued', 'leased')
           AND updated_at_ms < ?2",
        params![like_pattern, stale_cutoff],
        |row| row.get(0),
    )?)
}

fn count_orphaned_leases(conn: &Connection, like_pattern: &str) -> Result<i64, SchedulerError> {
    Ok(conn.query_row(
        "SELECT COUNT(*)
         FROM rust_hub_run_leases l
         LEFT JOIN rust_hub_run_queue q ON q.run_id = l.run_id
         WHERE l.run_id LIKE ?1 AND q.run_id IS NULL",
        params![like_pattern],
        |row| row.get(0),
    )?)
}

fn lease_shadow_event_counts(
    conn: &Connection,
    like_pattern: &str,
) -> Result<Vec<LeaseShadowEventCount>, SchedulerError> {
    let mut stmt = conn.prepare(
        "SELECT e.event_type, COUNT(*) AS n
         FROM rust_hub_scheduler_events e
         WHERE e.run_id LIKE ?1
         GROUP BY e.event_type
         ORDER BY e.event_type ASC",
    )?;
    let rows = stmt.query_map(params![like_pattern], |row| {
        Ok(LeaseShadowEventCount {
            event_type: row.get(0)?,
            count: row.get(1)?,
        })
    })?;
    let mut out = Vec::new();
    for row in rows {
        out.push(row?);
    }
    Ok(out)
}

fn lease_shadow_recent_rows(
    conn: &Connection,
    like_pattern: &str,
    now: i64,
    limit: usize,
) -> Result<Vec<LeaseShadowRunEvidence>, SchedulerError> {
    let limit = limit.clamp(1, 500) as i64;
    let mut stmt = conn.prepare(
        "SELECT
           q.run_id,
           q.request_id,
           q.scope_key,
           q.status,
           q.created_at_ms,
           q.updated_at_ms,
           COALESCE(l.lease_owner, '') AS lease_owner,
           COALESCE(l.lease_expires_at_ms, 0) AS lease_expires_at_ms,
           COALESCE((
             SELECT COUNT(*) FROM rust_hub_scheduler_events e
             WHERE e.run_id = q.run_id
           ), 0) AS event_count,
           COALESCE((
             SELECT e.event_type FROM rust_hub_scheduler_events e
             WHERE e.run_id = q.run_id
             ORDER BY e.created_at_ms DESC
             LIMIT 1
           ), '') AS last_event_type,
           COALESCE((
             SELECT e.created_at_ms FROM rust_hub_scheduler_events e
             WHERE e.run_id = q.run_id
             ORDER BY e.created_at_ms DESC
             LIMIT 1
           ), 0) AS last_event_at_ms
         FROM rust_hub_run_queue q
         LEFT JOIN rust_hub_run_leases l ON l.run_id = q.run_id
         WHERE q.run_id LIKE ?1
         ORDER BY q.updated_at_ms DESC, q.created_at_ms DESC
         LIMIT ?2",
    )?;
    let rows = stmt.query_map(params![like_pattern, limit], |row| {
        let created_at_ms = row.get::<_, i64>(4)?;
        Ok(LeaseShadowRunEvidence {
            run_id: row.get(0)?,
            request_id: row.get(1)?,
            scope_key: row.get(2)?,
            status: row.get(3)?,
            created_at_ms,
            updated_at_ms: row.get(5)?,
            age_ms: now.saturating_sub(created_at_ms),
            lease_owner: row.get(6)?,
            lease_expires_at_ms: row.get(7)?,
            event_count: row.get(8)?,
            last_event_type: row.get(9)?,
            last_event_at_ms: row.get(10)?,
        })
    })?;
    let mut out = Vec::new();
    for row in rows {
        out.push(row?);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use xhub_db::{apply_baseline_migrations, read_latest_scheduler_snapshot};

    #[test]
    fn enqueue_is_idempotent_and_writes_snapshot() {
        let db_path = unique_temp_db_path("xhub_scheduler_enqueue");
        apply_baseline_migrations(&db_path).expect("migrate db");
        let store = SchedulerStore::new(db_path.clone(), test_config());

        let first = store
            .enqueue(sample_enqueue("req-1", "scope-a", "idem-1"))
            .expect("enqueue first");
        let second = store
            .enqueue(sample_enqueue("req-1-retry", "scope-a", "idem-1"))
            .expect("enqueue duplicate");

        assert!(first.inserted);
        assert!(!second.inserted);
        assert_eq!(first.run.run_id, second.run.run_id);
        assert_eq!(first.run.status, STATUS_QUEUED);

        let snapshot = read_latest_scheduler_snapshot(&db_path)
            .expect("read latest snapshot")
            .expect("snapshot exists");
        assert_eq!(snapshot.queue_depth, 1);
        assert_eq!(snapshot.in_flight_total, 0);

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn acquire_respects_scope_limit_then_release_allows_next_run() {
        let db_path = unique_temp_db_path("xhub_scheduler_acquire");
        apply_baseline_migrations(&db_path).expect("migrate db");
        let store = SchedulerStore::new(db_path.clone(), test_config());

        store
            .enqueue(sample_enqueue("req-1", "scope-a", "idem-1"))
            .expect("enqueue first");
        store
            .enqueue(sample_enqueue("req-2", "scope-a", "idem-2"))
            .expect("enqueue second");

        let first = store
            .acquire_next("worker-a", 30_000)
            .expect("acquire first")
            .expect("first lease");
        let blocked = store
            .acquire_next("worker-b", 30_000)
            .expect("per-scope limited");
        assert!(blocked.is_none());

        let view = store
            .status_view(true, 10)
            .expect("status after first lease");
        assert_eq!(view.in_flight_total, 1);
        assert_eq!(view.queue_depth, 1);
        assert_eq!(view.in_flight_by_scope[0].scope_key, "scope-a");
        assert_eq!(view.queued_by_scope[0].count, 1);
        assert_eq!(view.queue_items.len(), 1);

        let release = store
            .release(
                first.run_id.as_str(),
                first.lease_token.as_str(),
                ReleaseOutcome::Completed,
            )
            .expect("release completed");
        assert_eq!(release.status, STATUS_COMPLETED);

        let second = store
            .acquire_next("worker-b", 30_000)
            .expect("acquire second")
            .expect("second lease");
        assert_eq!(second.request_id, "req-2");

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn acquire_run_leases_exact_run_and_is_idempotent() {
        let db_path = unique_temp_db_path("xhub_scheduler_acquire_run");
        apply_baseline_migrations(&db_path).expect("migrate db");
        let store = SchedulerStore::new(db_path.clone(), test_config());

        let first = store
            .enqueue(sample_enqueue("req-exact-1", "scope-a", "idem-exact-1"))
            .expect("enqueue first");
        store
            .enqueue(sample_enqueue("req-exact-2", "scope-a", "idem-exact-2"))
            .expect("enqueue second");

        let leased = store
            .acquire_run(first.run.run_id.as_str(), "worker-exact", 30_000)
            .expect("acquire exact")
            .expect("lease exact run");
        assert_eq!(leased.run_id, first.run.run_id);
        assert_eq!(leased.request_id, "req-exact-1");

        let duplicate = store
            .acquire_run(first.run.run_id.as_str(), "worker-exact", 30_000)
            .expect("acquire exact duplicate")
            .expect("existing lease");
        assert_eq!(duplicate.run_id, leased.run_id);
        assert_eq!(duplicate.lease_token, leased.lease_token);

        let status = store.status_view(true, 10).expect("status");
        assert_eq!(status.in_flight_total, 1);
        assert_eq!(status.queue_depth, 1);

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn claim_enqueues_and_leases_when_request_is_next_fair_candidate() {
        let db_path = unique_temp_db_path("xhub_scheduler_claim");
        apply_baseline_migrations(&db_path).expect("migrate db");
        let store = SchedulerStore::new(db_path.clone(), test_config());

        let claimed = store
            .claim(
                sample_enqueue("req-claim-1", "scope-a", "idem-claim-1"),
                "worker-claim",
                30_000,
            )
            .expect("claim first");
        assert!(claimed.inserted);
        assert_eq!(claimed.run.status, STATUS_LEASED);
        let leased = claimed.leased.expect("claim leases immediately");
        assert_eq!(leased.request_id, "req-claim-1");
        assert_eq!(leased.scope_key, "scope-a");
        assert_eq!(leased.attempt, 1);

        let duplicate = store
            .claim(
                sample_enqueue("req-claim-1-retry", "scope-a", "idem-claim-1"),
                "worker-claim",
                30_000,
            )
            .expect("claim duplicate");
        assert!(!duplicate.inserted);
        assert_eq!(
            duplicate.leased.expect("existing lease").lease_token,
            leased.lease_token
        );

        let view = store.status_view(true, 10).expect("status");
        assert_eq!(view.in_flight_total, 1);
        assert_eq!(view.queue_depth, 0);

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn claim_does_not_skip_earlier_fair_candidate() {
        let db_path = unique_temp_db_path("xhub_scheduler_claim_fair");
        apply_baseline_migrations(&db_path).expect("migrate db");
        let store = SchedulerStore::new(db_path.clone(), test_config());

        store
            .enqueue(sample_enqueue("req-earlier", "scope-a", "idem-earlier"))
            .expect("enqueue earlier");
        let claimed = store
            .claim(
                sample_enqueue("req-later", "scope-b", "idem-later"),
                "worker-claim",
                30_000,
            )
            .expect("claim later");
        assert!(claimed.inserted);
        assert!(claimed.leased.is_none());

        let acquired = store
            .acquire_next("worker-next", 30_000)
            .expect("acquire next")
            .expect("lease earlier");
        assert_eq!(acquired.request_id, "req-earlier");

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn lease_shadow_evidence_summarizes_node_paid_ai_runs() {
        let db_path = unique_temp_db_path("xhub_scheduler_lease_shadow_evidence");
        apply_baseline_migrations(&db_path).expect("migrate db");
        let store = SchedulerStore::new(db_path.clone(), test_config());

        let first = store
            .enqueue(EnqueueRunRequest {
                run_id: Some("node_paid_ai_req-evidence-1".to_string()),
                ..sample_enqueue("req-evidence-1", "scope-a", "idem-evidence-1")
            })
            .expect("enqueue first");
        let leased = store
            .acquire_run(first.run.run_id.as_str(), "worker-evidence", 30_000)
            .expect("acquire exact")
            .expect("lease exact run");
        store
            .release(
                leased.run_id.as_str(),
                leased.lease_token.as_str(),
                ReleaseOutcome::Completed,
            )
            .expect("release");
        let second = store
            .enqueue(EnqueueRunRequest {
                run_id: Some("node_paid_ai_req-evidence-2".to_string()),
                ..sample_enqueue("req-evidence-2", "scope-b", "idem-evidence-2")
            })
            .expect("enqueue second");
        store
            .cancel(second.run.run_id.as_str(), Some("canceled"))
            .expect("cancel");

        let evidence = store
            .lease_shadow_evidence("node_paid_ai_", 1_000, 10)
            .expect("evidence");
        assert_eq!(evidence.total_runs, 2);
        assert_eq!(evidence.completed, 1);
        assert_eq!(evidence.canceled, 1);
        assert_eq!(evidence.queued, 0);
        assert_eq!(evidence.leased, 0);
        assert_eq!(evidence.orphaned_leases, 0);
        assert!(evidence
            .event_counts
            .iter()
            .any(|item| item.event_type == EVENT_LEASE_ACQUIRED && item.count == 1));
        assert_eq!(evidence.recent.len(), 2);

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn expired_lease_is_requeued_before_next_acquire() {
        let db_path = unique_temp_db_path("xhub_scheduler_expired_lease");
        apply_baseline_migrations(&db_path).expect("migrate db");
        let store = SchedulerStore::new(db_path.clone(), test_config());

        let enqueued = store
            .enqueue(sample_enqueue("req-1", "scope-a", "idem-1"))
            .expect("enqueue");
        let leased = store
            .acquire_next("worker-a", 1)
            .expect("acquire")
            .expect("lease");
        assert_eq!(leased.run_id, enqueued.run.run_id);
        std::thread::sleep(std::time::Duration::from_millis(3));

        let reacquired = store
            .acquire_next("worker-b", 30_000)
            .expect("reacquire after expiry")
            .expect("reacquired lease");
        assert_eq!(reacquired.run_id, enqueued.run.run_id);
        assert_eq!(reacquired.attempt, 2);

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn cancel_removes_run_from_active_counts() {
        let db_path = unique_temp_db_path("xhub_scheduler_cancel");
        apply_baseline_migrations(&db_path).expect("migrate db");
        let store = SchedulerStore::new(db_path.clone(), test_config());

        let enqueued = store
            .enqueue(sample_enqueue("req-1", "scope-a", "idem-1"))
            .expect("enqueue");
        let cancel = store
            .cancel(enqueued.run.run_id.as_str(), Some("user requested"))
            .expect("cancel");
        assert_eq!(cancel.status, STATUS_CANCELED);

        let view = store.status_view(false, 10).expect("status after cancel");
        assert_eq!(view.queue_depth, 0);
        assert_eq!(view.in_flight_total, 0);

        let _ = std::fs::remove_file(&db_path);
    }

    fn test_config() -> SchedulerConfig {
        SchedulerConfig {
            global_concurrency: 2,
            per_scope_concurrency: 1,
            queue_limit: 4,
            queue_timeout_ms: 60_000,
        }
    }

    fn sample_enqueue(
        request_id: &str,
        scope_key: &str,
        idempotency_key: &str,
    ) -> EnqueueRunRequest {
        EnqueueRunRequest {
            run_id: None,
            request_id: request_id.to_string(),
            scope_key: scope_key.to_string(),
            project_id: None,
            device_id: None,
            task_type: "paid_ai".to_string(),
            priority: 0,
            idempotency_key: idempotency_key.to_string(),
            not_before_ms: None,
            payload_json: Some("{\"prompt\":\"hello\"}".to_string()),
        }
    }

    fn unique_temp_db_path(prefix: &str) -> std::path::PathBuf {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        std::env::temp_dir().join(format!("{prefix}_{}_{}.sqlite3", std::process::id(), now))
    }
}
