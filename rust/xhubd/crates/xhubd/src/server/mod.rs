pub(crate) mod auth;
pub(crate) mod handler;
pub(crate) mod handlers;
pub(crate) mod parse;
pub(crate) mod request;
pub(crate) mod response;
pub(crate) mod state;

#[cfg(test)]
mod tests;

use std::net::TcpListener;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use xhub_core::HubConfig;
use xhub_db::apply_baseline_migrations;

use crate::config::{enforce_http_bind_policy, env_bool, env_u128_in_range};
use crate::local_ml_bridge;
use crate::server::handler::handle_client;
use crate::server::handlers::health::{readiness_json_uncached, store_readiness_cache_body};
use crate::server::state::HubState;
use crate::{xt_compat, xt_file_ipc};

pub(crate) fn serve_http(config: HubConfig) -> Result<(), String> {
    enforce_http_bind_policy(&config)?;
    apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("serve migration preflight failed: {err}"))?;
    let addr = config.http_addr();
    let listener = TcpListener::bind(&addr).map_err(|err| format!("bind {addr} failed: {err}"))?;
    println!("[xhubd] shadow HTTP listening on http://{addr}");
    println!("[xhubd] health: http://{addr}/health");
    println!("[xhubd] mode=shadow_http grpc=not_started");

    let shared = Arc::new(HubState::new(config));
    start_readiness_cache_prewarm_if_enabled(Arc::clone(&shared));
    start_xt_classic_status_heartbeat_if_enabled(&shared.config);
    xt_file_ipc::start_projection_prewarm_if_enabled(&shared.config);
    local_ml_bridge::start_resident_runtime_preheat_if_enabled(&shared.config);
    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                let state = Arc::clone(&shared);
                thread::spawn(move || {
                    if let Err(err) = handle_client(stream, &state) {
                        eprintln!("xhubd request error: {err}");
                    }
                });
            }
            Err(err) => eprintln!("xhubd accept error: {err}"),
        }
    }
    Ok(())
}

pub(crate) fn start_readiness_cache_prewarm_if_enabled(state: Arc<HubState>) {
    if !env_bool("XHUB_RUST_READY_CACHE_PREWARM", true) || state.readiness_cache_ttl_ms == 0 {
        return;
    }
    thread::spawn(move || {
        let body = readiness_json_uncached(&state);
        store_readiness_cache_body(&state, body);
    });
}

pub(crate) fn start_xt_classic_status_heartbeat_if_enabled(config: &HubConfig) {
    if !env_bool("XHUB_RUST_XT_CLASSIC_STATUS_WRITER_HEARTBEAT", false) {
        return;
    }
    let interval_ms = env_u128_in_range(
        "XHUB_RUST_XT_CLASSIC_STATUS_WRITER_HEARTBEAT_MS",
        1_000,
        100,
        60_000,
    ) as u64;
    let config = config.clone();
    let mut trusted_fast_refresh = env_bool("XHUB_RUST_XT_CLASSIC_PRODUCTION_CUTOVER", false)
        && env_bool("XHUB_RUST_XT_CLASSIC_STATUS_WRITER_APPLY", false)
        && env_bool("XHUB_RUST_XT_CLASSIC_FILE_IPC_READY", false)
        && env_bool("XHUB_RUST_XT_CLASSIC_ROLLBACK_CONTRACT", false);
    thread::spawn(move || loop {
        let ok = if trusted_fast_refresh {
            xt_compat::classic_hub_status_write_trusted_heartbeat_once(&config)
        } else {
            xt_compat::classic_hub_status_write_heartbeat_once(&config)
        };
        trusted_fast_refresh = ok;
        thread::sleep(Duration::from_millis(interval_ms));
    });
}
