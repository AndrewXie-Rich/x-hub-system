use tonic::transport::Server;
use tonic::{Request, Response, Status};

use xhub_contract::proto::{
    self,
    hub_runtime_server::{HubRuntime, HubRuntimeServer},
};
use xhub_core::HubConfig;
use xhub_db::read_latest_scheduler_snapshot;
use xhub_scheduler::{SchedulerConfig, SchedulerSnapshot, SchedulerStore};

use crate::scheduler_bridge;

#[derive(Debug, Clone)]
pub struct RuntimeService {
    scheduler_config: SchedulerConfig,
    config: HubConfig,
}

impl RuntimeService {
    pub fn new(config: HubConfig) -> Self {
        let scheduler_config = scheduler_bridge::effective_scheduler_config(&config);
        Self {
            scheduler_config,
            config,
        }
    }

    fn scheduler_status(
        &self,
        include_queue_items: bool,
        queue_items_limit: usize,
    ) -> proto::PaidAiSchedulerStatus {
        let store = SchedulerStore::new(self.config.db_path.clone(), self.scheduler_config.clone());
        if let Ok(view) = store.status_view(include_queue_items, queue_items_limit) {
            return proto::PaidAiSchedulerStatus {
                updated_at_ms: view.updated_at_ms,
                global_concurrency: self.scheduler_config.global_concurrency as i32,
                per_project_concurrency: self.scheduler_config.per_scope_concurrency as i32,
                queue_limit: self.scheduler_config.queue_limit as i32,
                queue_timeout_ms: self.scheduler_config.queue_timeout_ms as i64,
                in_flight_total: view.in_flight_total,
                queue_depth: view.queue_depth,
                oldest_queued_ms: view.oldest_queued_ms,
                in_flight_by_scope: view
                    .in_flight_by_scope
                    .into_iter()
                    .map(|item| proto::SchedulerScopeInFlight {
                        scope_key: item.scope_key,
                        in_flight: item.count,
                    })
                    .collect(),
                queued_by_scope: view
                    .queued_by_scope
                    .into_iter()
                    .map(|item| proto::SchedulerScopeQueued {
                        scope_key: item.scope_key,
                        queued: item.count,
                    })
                    .collect(),
                queue_items: view
                    .queue_items
                    .into_iter()
                    .map(|item| proto::SchedulerQueueItem {
                        request_id: item.request_id,
                        scope_key: item.scope_key,
                        enqueued_at_ms: item.enqueued_at_ms,
                        queued_ms: item.queued_ms,
                    })
                    .collect(),
            };
        }

        let fallback = SchedulerSnapshot::shadow_empty();
        let db_snapshot = read_latest_scheduler_snapshot(&self.config.db_path)
            .ok()
            .flatten();
        proto::PaidAiSchedulerStatus {
            updated_at_ms: db_snapshot
                .as_ref()
                .map(|row| row.created_at_ms)
                .unwrap_or(fallback.captured_at_ms as i64),
            global_concurrency: self.scheduler_config.global_concurrency as i32,
            per_project_concurrency: self.scheduler_config.per_scope_concurrency as i32,
            queue_limit: self.scheduler_config.queue_limit as i32,
            queue_timeout_ms: self.scheduler_config.queue_timeout_ms as i64,
            in_flight_total: db_snapshot
                .as_ref()
                .map(|row| row.in_flight_total)
                .unwrap_or(fallback.in_flight_total as i32),
            queue_depth: db_snapshot
                .as_ref()
                .map(|row| row.queue_depth)
                .unwrap_or(fallback.queue_depth as i32),
            oldest_queued_ms: fallback.oldest_queued_ms as i64,
            in_flight_by_scope: Vec::new(),
            queued_by_scope: Vec::new(),
            queue_items: if include_queue_items {
                Vec::new()
            } else {
                Vec::new()
            },
        }
    }
}

#[tonic::async_trait]
impl HubRuntime for RuntimeService {
    async fn get_scheduler_status(
        &self,
        request: Request<proto::GetSchedulerStatusRequest>,
    ) -> Result<Response<proto::GetSchedulerStatusResponse>, Status> {
        let req = request.into_inner();
        let queue_items_limit = if req.queue_items_limit > 0 {
            req.queue_items_limit as usize
        } else {
            50
        };
        Ok(Response::new(proto::GetSchedulerStatusResponse {
            paid_ai: Some(self.scheduler_status(req.include_queue_items, queue_items_limit)),
        }))
    }

    async fn get_pending_grant_requests(
        &self,
        _request: Request<proto::GetPendingGrantRequestsRequest>,
    ) -> Result<Response<proto::GetPendingGrantRequestsResponse>, Status> {
        Ok(Response::new(proto::GetPendingGrantRequestsResponse {
            updated_at_ms: SchedulerSnapshot::shadow_empty().captured_at_ms as i64,
            items: Vec::new(),
        }))
    }

    async fn get_supervisor_candidate_review_queue(
        &self,
        _request: Request<proto::GetSupervisorCandidateReviewQueueRequest>,
    ) -> Result<Response<proto::GetSupervisorCandidateReviewQueueResponse>, Status> {
        Ok(Response::new(
            proto::GetSupervisorCandidateReviewQueueResponse {
                updated_at_ms: SchedulerSnapshot::shadow_empty().captured_at_ms as i64,
                items: Vec::new(),
            },
        ))
    }

    async fn get_connector_ingress_receipts(
        &self,
        _request: Request<proto::GetConnectorIngressReceiptsRequest>,
    ) -> Result<Response<proto::GetConnectorIngressReceiptsResponse>, Status> {
        Ok(Response::new(proto::GetConnectorIngressReceiptsResponse {
            updated_at_ms: SchedulerSnapshot::shadow_empty().captured_at_ms as i64,
            items: Vec::new(),
        }))
    }

    async fn get_autonomy_policy_overrides(
        &self,
        _request: Request<proto::GetAutonomyPolicyOverridesRequest>,
    ) -> Result<Response<proto::GetAutonomyPolicyOverridesResponse>, Status> {
        Ok(Response::new(proto::GetAutonomyPolicyOverridesResponse {
            updated_at_ms: SchedulerSnapshot::shadow_empty().captured_at_ms as i64,
            items: Vec::new(),
        }))
    }

    async fn approve_pending_grant_request(
        &self,
        _request: Request<proto::ApprovePendingGrantRequestRequest>,
    ) -> Result<Response<proto::ApprovePendingGrantRequestResponse>, Status> {
        Err(Status::failed_precondition("rust_hub_shadow_read_only"))
    }

    async fn deny_pending_grant_request(
        &self,
        _request: Request<proto::DenyPendingGrantRequestRequest>,
    ) -> Result<Response<proto::DenyPendingGrantRequestResponse>, Status> {
        Err(Status::failed_precondition("rust_hub_shadow_read_only"))
    }

    async fn get_channel_runtime_status_snapshot(
        &self,
        _request: Request<proto::GetChannelRuntimeStatusSnapshotRequest>,
    ) -> Result<Response<proto::GetChannelRuntimeStatusSnapshotResponse>, Status> {
        Ok(Response::new(
            proto::GetChannelRuntimeStatusSnapshotResponse {
                schema_version: "xhub.channel_runtime_status_snapshot.v1".to_string(),
                updated_at_ms: SchedulerSnapshot::shadow_empty().captured_at_ms as i64,
                providers: Vec::new(),
                totals: None,
                unknown_provider_rows: Vec::new(),
            },
        ))
    }

    async fn list_channel_identity_bindings(
        &self,
        _request: Request<proto::ListChannelIdentityBindingsRequest>,
    ) -> Result<Response<proto::ListChannelIdentityBindingsResponse>, Status> {
        Ok(Response::new(proto::ListChannelIdentityBindingsResponse {
            updated_at_ms: SchedulerSnapshot::shadow_empty().captured_at_ms as i64,
            bindings: Vec::new(),
        }))
    }

    async fn upsert_channel_identity_binding(
        &self,
        _request: Request<proto::UpsertChannelIdentityBindingRequest>,
    ) -> Result<Response<proto::UpsertChannelIdentityBindingResponse>, Status> {
        Err(Status::failed_precondition("rust_hub_shadow_read_only"))
    }

    async fn list_supervisor_operator_channel_bindings(
        &self,
        _request: Request<proto::ListSupervisorOperatorChannelBindingsRequest>,
    ) -> Result<Response<proto::ListSupervisorOperatorChannelBindingsResponse>, Status> {
        Ok(Response::new(
            proto::ListSupervisorOperatorChannelBindingsResponse {
                updated_at_ms: SchedulerSnapshot::shadow_empty().captured_at_ms as i64,
                bindings: Vec::new(),
            },
        ))
    }

    async fn upsert_supervisor_operator_channel_binding(
        &self,
        _request: Request<proto::UpsertSupervisorOperatorChannelBindingRequest>,
    ) -> Result<Response<proto::UpsertSupervisorOperatorChannelBindingResponse>, Status> {
        Err(Status::failed_precondition("rust_hub_shadow_read_only"))
    }

    async fn list_channel_onboarding_discovery_tickets(
        &self,
        _request: Request<proto::ListChannelOnboardingDiscoveryTicketsRequest>,
    ) -> Result<Response<proto::ListChannelOnboardingDiscoveryTicketsResponse>, Status> {
        Ok(Response::new(
            proto::ListChannelOnboardingDiscoveryTicketsResponse {
                updated_at_ms: SchedulerSnapshot::shadow_empty().captured_at_ms as i64,
                tickets: Vec::new(),
            },
        ))
    }

    async fn get_channel_onboarding_discovery_ticket(
        &self,
        _request: Request<proto::GetChannelOnboardingDiscoveryTicketRequest>,
    ) -> Result<Response<proto::GetChannelOnboardingDiscoveryTicketResponse>, Status> {
        Ok(Response::new(
            proto::GetChannelOnboardingDiscoveryTicketResponse {
                ok: false,
                deny_code: "rust_hub_shadow_not_found".to_string(),
                ticket: None,
                latest_decision: None,
                automation_state: None,
                revocation: None,
            },
        ))
    }

    async fn create_or_touch_channel_onboarding_discovery_ticket(
        &self,
        _request: Request<proto::CreateOrTouchChannelOnboardingDiscoveryTicketRequest>,
    ) -> Result<Response<proto::CreateOrTouchChannelOnboardingDiscoveryTicketResponse>, Status>
    {
        Err(Status::failed_precondition("rust_hub_shadow_read_only"))
    }

    async fn review_channel_onboarding_discovery_ticket(
        &self,
        _request: Request<proto::ReviewChannelOnboardingDiscoveryTicketRequest>,
    ) -> Result<Response<proto::ReviewChannelOnboardingDiscoveryTicketResponse>, Status> {
        Err(Status::failed_precondition("rust_hub_shadow_read_only"))
    }

    async fn revoke_channel_onboarding_discovery_ticket(
        &self,
        _request: Request<proto::RevokeChannelOnboardingDiscoveryTicketRequest>,
    ) -> Result<Response<proto::RevokeChannelOnboardingDiscoveryTicketResponse>, Status> {
        Err(Status::failed_precondition("rust_hub_shadow_read_only"))
    }

    async fn retry_channel_onboarding_outbox(
        &self,
        _request: Request<proto::RetryChannelOnboardingOutboxRequest>,
    ) -> Result<Response<proto::RetryChannelOnboardingOutboxResponse>, Status> {
        Err(Status::failed_precondition("rust_hub_shadow_read_only"))
    }

    async fn evaluate_channel_command_gate(
        &self,
        _request: Request<proto::EvaluateChannelCommandGateRequest>,
    ) -> Result<Response<proto::EvaluateChannelCommandGateResponse>, Status> {
        Err(Status::failed_precondition(
            "rust_hub_shadow_policy_not_authoritative",
        ))
    }

    async fn resolve_supervisor_channel_route(
        &self,
        _request: Request<proto::ResolveSupervisorChannelRouteRequest>,
    ) -> Result<Response<proto::ResolveSupervisorChannelRouteResponse>, Status> {
        Err(Status::failed_precondition(
            "rust_hub_shadow_route_not_authoritative",
        ))
    }

    async fn execute_operator_channel_hub_command(
        &self,
        _request: Request<proto::ExecuteOperatorChannelHubCommandRequest>,
    ) -> Result<Response<proto::ExecuteOperatorChannelHubCommandResponse>, Status> {
        Err(Status::failed_precondition("rust_hub_shadow_read_only"))
    }
}

pub async fn serve_grpc(config: HubConfig) -> Result<(), Box<dyn std::error::Error>> {
    let addr = format!("{}:{}", config.host, config.grpc_port).parse()?;
    let service = RuntimeService::new(config);
    println!("[xhubd] shadow gRPC listening on {addr}");
    println!("[xhubd] service=HubRuntime method=GetSchedulerStatus mode=shadow_read_only");
    Server::builder()
        .add_service(HubRuntimeServer::new(service))
        .serve(addr)
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio_stream::wrappers::TcpListenerStream;
    use xhub_contract::proto::hub_runtime_client::HubRuntimeClient;
    use xhub_core::{now_ms, HubConfig};
    use xhub_db::apply_baseline_migrations;
    use xhub_scheduler::EnqueueRunRequest;

    #[tokio::test]
    async fn get_scheduler_status_returns_shadow_snapshot() {
        let std_listener = std::net::TcpListener::bind("127.0.0.1:0").expect("bind test listener");
        std_listener
            .set_nonblocking(true)
            .expect("set listener nonblocking");
        let addr = std_listener.local_addr().expect("read listener addr");
        let listener = tokio::net::TcpListener::from_std(std_listener).expect("tokio listener");
        let incoming = TcpListenerStream::new(listener);

        let server = tokio::spawn(async move {
            Server::builder()
                .add_service(HubRuntimeServer::new(RuntimeService::new(
                    HubConfig::from_env(std::env::temp_dir()),
                )))
                .serve_with_incoming(incoming)
                .await
        });

        let endpoint = format!("http://{addr}");
        let mut client = HubRuntimeClient::connect(endpoint)
            .await
            .expect("connect client");
        let response = client
            .get_scheduler_status(proto::GetSchedulerStatusRequest {
                client: None,
                include_queue_items: true,
                queue_items_limit: 16,
            })
            .await
            .expect("scheduler status response")
            .into_inner();

        let paid_ai = response.paid_ai.expect("paid_ai payload");
        assert_eq!(paid_ai.global_concurrency, 6);
        assert_eq!(paid_ai.per_project_concurrency, 2);
        assert_eq!(paid_ai.queue_depth, 0);
        assert_eq!(paid_ai.in_flight_total, 0);

        server.abort();
    }

    #[tokio::test]
    async fn get_scheduler_status_returns_db_backed_queue_view() {
        let db_path = unique_temp_db_path("xhubd_grpc_scheduler_view");
        apply_baseline_migrations(&db_path).expect("migrate db");
        let store = SchedulerStore::new(db_path.clone(), SchedulerConfig::default());
        store
            .enqueue(EnqueueRunRequest {
                run_id: None,
                request_id: "req-grpc-1".to_string(),
                scope_key: "project:grpc".to_string(),
                project_id: Some("grpc".to_string()),
                device_id: None,
                task_type: "paid_ai".to_string(),
                priority: 3,
                idempotency_key: "grpc-idem-1".to_string(),
                not_before_ms: None,
                payload_json: Some("{\"kind\":\"grpc-test\"}".to_string()),
            })
            .expect("enqueue scheduler row");

        let std_listener = std::net::TcpListener::bind("127.0.0.1:0").expect("bind test listener");
        std_listener
            .set_nonblocking(true)
            .expect("set listener nonblocking");
        let addr = std_listener.local_addr().expect("read listener addr");
        let listener = tokio::net::TcpListener::from_std(std_listener).expect("tokio listener");
        let incoming = TcpListenerStream::new(listener);
        let root = std::env::temp_dir().join(format!(
            "xhubd_grpc_root_{}_{}",
            std::process::id(),
            now_ms()
        ));
        let config = HubConfig {
            root_dir: root.clone(),
            host: "127.0.0.1".to_string(),
            http_port: 0,
            grpc_port: addr.port(),
            db_path: db_path.clone(),
            runtime_base_dir: std::path::PathBuf::new(),
            proto_path: root.join("hub_protocol_v1.proto"),
            canonical_proto_path: root.join("hub_protocol_v1.proto"),
            http_access_key: None,
            http_access_key_source: String::new(),
            http_access_key_required: false,
        };

        let server = tokio::spawn(async move {
            Server::builder()
                .add_service(HubRuntimeServer::new(RuntimeService::new(config)))
                .serve_with_incoming(incoming)
                .await
        });

        let endpoint = format!("http://{addr}");
        let mut client = HubRuntimeClient::connect(endpoint)
            .await
            .expect("connect client");
        let response = client
            .get_scheduler_status(proto::GetSchedulerStatusRequest {
                client: None,
                include_queue_items: true,
                queue_items_limit: 4,
            })
            .await
            .expect("scheduler status response")
            .into_inner();

        let paid_ai = response.paid_ai.expect("paid_ai payload");
        assert_eq!(paid_ai.queue_depth, 1);
        assert_eq!(paid_ai.in_flight_total, 0);
        assert_eq!(paid_ai.queued_by_scope.len(), 1);
        assert_eq!(paid_ai.queued_by_scope[0].scope_key, "project:grpc");
        assert_eq!(paid_ai.queued_by_scope[0].queued, 1);
        assert_eq!(paid_ai.queue_items.len(), 1);
        assert_eq!(paid_ai.queue_items[0].request_id, "req-grpc-1");

        server.abort();
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
