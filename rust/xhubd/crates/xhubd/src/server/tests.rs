#![allow(unused_imports)]
use super::auth::*;
use super::handler::*;
use super::handlers::evidence::*;
use super::handlers::health::*;
use super::handlers::metrics::*;
use super::request::*;
use super::response::*;
use super::state::*;
use super::*;
use crate::config::*;
use serde_json::{json, Value};
use std::collections::{BTreeMap, VecDeque};
use std::net::{SocketAddr, TcpStream};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicUsize};
use std::sync::Arc;
use std::sync::Mutex;
use std::thread;
use std::time::Duration;
use xhub_core::{json_escape, now_ms, HubConfig};
use xhub_db::apply_baseline_migrations;

fn test_config(access_key: Option<&str>, require_access_key: bool) -> HubConfig {
    let root = PathBuf::from("/tmp/xhubd-test");
    HubConfig {
        root_dir: root.clone(),
        host: "127.0.0.1".to_string(),
        http_port: 50151,
        grpc_port: 50152,
        db_path: root.join("data").join("hub.sqlite3"),
        runtime_base_dir: root.join("runtime"),
        proto_path: root
            .join("assets")
            .join("proto")
            .join("hub_protocol_v1.proto"),
        canonical_proto_path: root
            .join("assets")
            .join("proto")
            .join("hub_protocol_v1.proto"),
        http_access_key: access_key.map(str::to_string),
        http_access_key_source: if access_key.is_some() {
            "test".to_string()
        } else {
            String::new()
        },
        http_access_key_required: require_access_key,
    }
}

fn request(headers: Vec<(&str, &str)>) -> HttpRequest {
    HttpRequest {
        method: "GET".to_string(),
        path: "/ready".to_string(),
        body: String::new(),
        headers: headers
            .into_iter()
            .map(|(key, value)| (key.to_ascii_lowercase(), value.to_string()))
            .collect(),
    }
}

fn test_state(max_in_flight: usize) -> HubState {
    HubState {
        config: test_config(None, false),
        http_in_flight: AtomicUsize::new(0),
        http_max_in_flight: max_in_flight,
        http_slow_ms: 2_000,
        http_read_timeout_ms: 5_000,
        http_write_timeout_ms: 5_000,
        http_metrics_recent_limit: 3,
        http_metrics: Mutex::new(HttpMetrics::default()),
        readiness_cache: Mutex::new(ReadinessCache::default()),
        readiness_cache_ttl_ms: 250,
        product_kernel_readiness_refresh_in_flight: AtomicBool::new(false),
        memory_snapshot_cache: Mutex::new(MemorySnapshotCache::default()),
        memory_snapshot_cache_ttl_ms: 500,
        skills_catalog_cache: Mutex::new(SkillsCatalogCache::default()),
        skills_catalog_cache_ttl_ms: 500,
    }
}

#[test]
fn readiness_cache_returns_hot_body_without_recompute() {
    let state = test_state(128);
    {
        let mut cache = state.readiness_cache.lock().unwrap();
        cache.body = "{\"cached\":true}\n".to_string();
        cache.refreshed_at_ms = now_ms();
        cache.expires_at_ms = now_ms().saturating_add(5_000);
    }

    assert_eq!(readiness_json_cached(&state), "{\"cached\":true}\n");
}

#[test]
fn product_kernel_readiness_cache_uses_recent_stale_body() {
    let state = Arc::new(test_state(128));
    let now = now_ms();
    {
        let mut cache = state.readiness_cache.lock().unwrap();
        cache.body = "{\"schema_version\":\"xhub.rust_hub.readiness.v1\",\"ok\":true,\"ready\":true,\"checks\":[]}\n".to_string();
        cache.refreshed_at_ms = now.saturating_sub(500);
        cache.expires_at_ms = now.saturating_sub(250);
    }

    assert_eq!(
            product_kernel_readiness_json_cached(&state),
            "{\"schema_version\":\"xhub.rust_hub.readiness.v1\",\"ok\":true,\"ready\":true,\"checks\":[]}\n"
        );
}

#[test]
fn strict_readiness_cache_does_not_use_stale_body() {
    let state = test_state(128);
    let now = now_ms();
    {
        let mut cache = state.readiness_cache.lock().unwrap();
        cache.body = "{\"cached\":true}\n".to_string();
        cache.refreshed_at_ms = now.saturating_sub(1_000);
        cache.expires_at_ms = now.saturating_sub(500);
    }

    let body = readiness_json_cached(&state);
    assert_ne!(body, "{\"cached\":true}\n");
    assert!(body.contains("\"schema_version\":\"xhub.rust_hub.readiness.v1\""));
}

#[test]
fn product_kernel_contract_declares_rust_kernel_and_swift_shell() {
    let config = test_config(None, false);
    let readiness = json!({
        "schema_version": "xhub.rust_hub.readiness.v1",
        "ok": true,
        "ready": true,
        "version": "0.1.0",
        "mode": "shadow_http",
        "http_addr": "127.0.0.1:50151",
        "network": {
            "public_base_url": "https://hub.example.com",
            "public_base_url_ready": true,
            "public_endpoint_ready": true,
            "http_access_key_required": true,
            "http_access_key_configured": true
        },
        "storage": {
            "db_path": "/tmp/xhubd-test/data/hub.sqlite3"
        },
        "runtime": {
            "runtime_base_dir": "/tmp/xhubd-test/runtime",
            "ml_execution_in_rust": true,
            "ml_execution_authority_enabled": true
        },
        "memory": {
            "canonical_writer_in_rust": true
        },
        "skills": {
            "execution_authority_in_rust": true
        },
        "capabilities": {
            "cross_network_ready": true,
            "domain_public_endpoint_ready": true,
            "xt_file_ipc_production_surface_ready": true
        },
        "checks": [{"name": "proto", "ok": true, "blocking": true}]
    })
    .to_string();

    let body = product_kernel_json_from_readiness(&config, readiness.as_str());
    let value: Value = serde_json::from_str(&body).expect("product kernel json should parse");

    assert_eq!(value["schema_version"], "xhub.product_kernel.v1");
    assert_eq!(value["product"]["name"], "X-Hub");
    assert_eq!(
        value["product"]["boundary"],
        "rust_product_kernel_swift_shell"
    );
    assert_eq!(value["kernel"]["name"], "rust");
    assert_eq!(value["shell"]["name"], "swift");
    assert_eq!(value["authority"]["memory_writer_in_rust"], true);
    assert_eq!(value["authority"]["skills_execution_in_rust"], true);
    assert_eq!(value["authority"]["local_ml_execution_in_rust"], true);
    assert_eq!(value["authority"]["node_compatibility_layer"], true);
    assert_eq!(value["authority"]["node_remains_authority"], false);
    assert_eq!(value["authority"]["swift_shell_owns_ui"], true);
    assert_eq!(value["authority"]["rust_browser_product_ui"], false);
    assert_eq!(value["network"]["cross_network_ready"], true);
    assert_eq!(value["network"]["domain_public_endpoint_ready"], true);
}

#[test]
fn loopback_request_does_not_require_access_key_by_default() {
    let config = test_config(None, false);
    let peer = "127.0.0.1:49152".parse::<SocketAddr>().unwrap();
    assert!(http_access_key_failure(&request(vec![]), &config, Some(peer), "/ready").is_none());
}

#[test]
fn non_loopback_request_requires_configured_access_key() {
    let config = test_config(None, false);
    let peer = "198.51.100.10:49152".parse::<SocketAddr>().unwrap();
    let failure = http_access_key_failure(&request(vec![]), &config, Some(peer), "/ready")
        .expect("remote request should be blocked");
    assert_eq!(failure.0, "403 Forbidden");
    assert!(failure.1.contains("access_key_not_configured"));
}

#[test]
fn non_loopback_request_accepts_bearer_access_key() {
    let config = test_config(Some("secret-123"), false);
    let peer = "198.51.100.10:49152".parse::<SocketAddr>().unwrap();
    let request = request(vec![("authorization", "BEARER secret-123")]);
    assert!(http_access_key_failure(&request, &config, Some(peer), "/ready").is_none());
}

#[test]
fn explicit_require_access_key_blocks_loopback_without_key() {
    let config = test_config(Some("secret-123"), true);
    let peer = "127.0.0.1:49152".parse::<SocketAddr>().unwrap();
    let failure = http_access_key_failure(&request(vec![]), &config, Some(peer), "/ready")
        .expect("explicit local auth should be enforced");
    assert_eq!(failure.0, "401 Unauthorized");
    assert!(failure.1.contains("missing_access_key"));
}

#[test]
fn public_endpoint_blocks_loopback_ready_without_key() {
    let config = test_config(Some("secret-123"), false);
    let peer = "127.0.0.1:49152".parse::<SocketAddr>().unwrap();
    let failure = http_access_key_failure_with_public_endpoint(
        &request(vec![]),
        &config,
        Some(peer),
        "/ready",
        true,
    )
    .expect("public endpoint auth should apply before loopback exemption");
    assert_eq!(failure.0, "401 Unauthorized");
    assert!(failure.1.contains("missing_access_key"));
}

#[test]
fn public_endpoint_accepts_loopback_bearer_access_key() {
    let config = test_config(Some("secret-123"), false);
    let peer = "127.0.0.1:49152".parse::<SocketAddr>().unwrap();
    let request = request(vec![("authorization", "Bearer secret-123")]);
    assert!(http_access_key_failure_with_public_endpoint(
        &request,
        &config,
        Some(peer),
        "/ready",
        true,
    )
    .is_none());
}

#[test]
fn public_endpoint_accepts_loopback_header_access_key() {
    let config = test_config(Some("secret-123"), false);
    let peer = "127.0.0.1:49152".parse::<SocketAddr>().unwrap();
    let request = request(vec![("x-xhub-access-key", "secret-123")]);
    assert!(http_access_key_failure_with_public_endpoint(
        &request,
        &config,
        Some(peer),
        "/ready",
        true,
    )
    .is_none());
}

#[test]
fn public_endpoint_keeps_health_unauthenticated_on_loopback() {
    let config = test_config(Some("secret-123"), false);
    let peer = "127.0.0.1:49152".parse::<SocketAddr>().unwrap();
    assert!(http_access_key_failure_with_public_endpoint(
        &request(vec![]),
        &config,
        Some(peer),
        "/health",
        true,
    )
    .is_none());
}

#[test]
fn health_check_stays_unauthenticated_for_launchd_and_local_probes() {
    let config = test_config(Some("secret-123"), true);
    let peer = "198.51.100.10:49152".parse::<SocketAddr>().unwrap();
    assert!(http_access_key_failure(&request(vec![]), &config, Some(peer), "/health").is_none());
}

#[test]
fn public_base_url_readiness_rejects_loopback_and_placeholders() {
    assert!(!public_base_url_ready(""));
    assert!(!public_base_url_ready("https://replace_with_domain"));
    assert!(!public_base_url_ready("http://127.0.0.1:50151"));
    assert!(!public_base_url_ready("https://localhost"));
    assert!(!public_base_url_ready("https://0.0.0.0:50151"));
}

#[test]
fn public_base_url_readiness_accepts_domain_and_lan_hosts() {
    assert!(public_base_url_ready("https://hub.example.com"));
    assert!(public_base_url_ready("https://hub.example.com/xhub"));
    assert!(public_base_url_ready("http://192.168.1.20:50151"));
}

#[test]
fn http_backpressure_exempts_health_and_releases_slots() {
    let state = test_state(1);
    match acquire_http_inflight_slot(&state, "/health") {
        Ok(None) => {}
        _ => panic!("health should not consume an in-flight slot"),
    }

    let first = match acquire_http_inflight_slot(&state, "/ready") {
        Ok(Some(guard)) => guard,
        _ => panic!("first business request should acquire a slot"),
    };
    match acquire_http_inflight_slot(&state, "/ready") {
        Err(body) => {
            assert!(body.contains("http_backpressure"));
            assert!(body.contains("\"max_in_flight\":1"));
        }
        _ => panic!("second business request should be backpressured"),
    }

    drop(first);
    match acquire_http_inflight_slot(&state, "/ready") {
        Ok(Some(_guard)) => {}
        _ => panic!("slot should be released after guard drop"),
    };
}

#[test]
fn http_metrics_records_route_without_detail_payloads() {
    let state = test_state(2);
    record_http_route_metrics(&state, "/memory/search", "200 OK", 7);
    record_http_route_metrics(&state, "/memory/search", "200 OK", state.http_slow_ms);
    let (_status, body) = http_metrics_json(&state);
    assert!(body.contains("xhub.rust_hub.http_metrics.v1"));
    assert!(body.contains("\"route\":\"/memory/search\""));
    assert!(body.contains("\"total_requests\":2"));
    assert!(body.contains("\"slow_requests\":1"));
    assert!(body.contains("\"recent_slow_requests\":1"));
    assert!(body.contains("\"recent_sample_capacity\":3"));
    assert!(body.contains("\"recent_samples_newest_first\""));
    assert!(body.contains("\"detail_json_included\":false"));
    assert!(!body.contains("api_key"));
}

#[test]
fn http_metrics_recent_window_is_bounded_and_query_sanitized() {
    let state = test_state(2);
    record_http_route_metrics(&state, "/ready", "200 OK", 1);
    record_http_route_metrics(&state, "/memory/search?api_key=sk-secret", "200 OK", 2);
    record_http_route_metrics(&state, "/skills/readiness#token=secret", "200 OK", 3);
    record_http_route_metrics(&state, "/model/route", "200 OK", state.http_slow_ms);
    let (_status, body) = http_metrics_json(&state);
    assert!(body.contains("\"recent_sample_count\":3"));
    assert!(body.contains("\"recent_dropped_samples\":1"));
    assert!(body.contains("\"recent_slow_requests\":1"));
    assert!(body.contains("\"route\":\"/memory/search\""));
    assert!(body.contains("\"route\":\"/skills/readiness\""));
    assert!(body.contains("\"route\":\"/model/route\""));
    let parsed: Value = serde_json::from_str(&body).expect("metrics json should parse");
    let recent_routes = parsed["recent_samples_newest_first"]
        .as_array()
        .expect("recent samples should be an array")
        .iter()
        .map(|sample| sample["route"].as_str().unwrap_or(""))
        .collect::<Vec<_>>();
    assert!(!recent_routes.contains(&"/ready"));
    assert!(!body.contains("sk-secret"));
    assert!(!body.contains("api_key"));
    assert!(!body.contains("token=secret"));
}

#[test]
fn route_evidence_is_opt_in_and_appends_evidence_id() {
    let mut config = test_config(None, false);
    let db_path = std::env::temp_dir().join(format!(
        "xhub_route_evidence_{}_{}.sqlite3",
        std::process::id(),
        now_ms()
    ));
    config.db_path = db_path.clone();
    let response_body = json!({
        "schema_version": "xhub.model_route_decision.v1",
        "ok": true,
        "command": "route",
        "updated_at_ms": 1000,
        "request": {"task_type":"summarize","model_id":"auto"},
        "selected_route_kind": "local",
        "selected_model_id": "local.summary",
        "blocking_reason_code": "",
        "selected": {"route_kind":"local","model_id":"local.summary"}
    })
    .to_string();

    let without_evidence = maybe_attach_route_evidence(
        &config,
        "",
        &Value::Null,
        "model_route",
        response_body.clone(),
    )
    .expect("route without evidence should pass through");
    let without_value: Value = serde_json::from_str(&without_evidence).expect("json");
    assert!(without_value.get("evidence_id").is_none());

    let with_evidence = maybe_attach_route_evidence(
        &config,
        "write_evidence=true&project_id=project-a&run_id=run-a",
        &Value::Null,
        "model_route",
        response_body,
    )
    .expect("route evidence should write");
    let with_value: Value = serde_json::from_str(&with_evidence).expect("json");
    assert!(with_value["evidence_id"]
        .as_str()
        .unwrap_or("")
        .starts_with("ev_model_route_"));
    assert_eq!(with_value["evidence"]["output_verdict"], "allow");
    assert_eq!(with_value["evidence"]["project_id"], "project-a");
    assert_eq!(with_value["evidence"]["run_id"], "run-a");
    assert_eq!(with_value["evidence"]["reason_codes"][0], "route_ready");

    let _ = std::fs::remove_file(db_path);
}

#[test]
fn http_io_timeouts_are_applied_to_streams() {
    let state = test_state(2);
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind loopback test listener");
    let addr = listener.local_addr().expect("read listener address");
    let client = TcpStream::connect(addr).expect("connect test client");
    let (server, _) = listener.accept().expect("accept test stream");

    apply_http_io_timeouts(&server, &state).expect("apply http io timeouts");

    assert_eq!(
        server.read_timeout().expect("read timeout"),
        Some(Duration::from_millis(5_000))
    );
    assert_eq!(
        server.write_timeout().expect("write timeout"),
        Some(Duration::from_millis(5_000))
    );
    drop(client);
}
