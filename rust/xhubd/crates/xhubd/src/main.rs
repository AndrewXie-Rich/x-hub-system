#![recursion_limit = "512"]

mod cli;
mod config;
mod evidence_bridge;
mod grpc_runtime;
mod local_ml_bridge;
mod memory_bridge;
mod memory_role_projection;
mod model_bridge;
mod network_bridge;
mod provider_bridge;
mod scheduler_bridge;
mod server;
mod skills_bridge;
mod xt_compat;
mod xt_contract;
mod xt_file_ipc;

#[tokio::main]
async fn main() {
    if let Err(err) = cli::run().await {
        eprintln!("xhubd error: {err}");
        std::process::exit(1);
    }
}
