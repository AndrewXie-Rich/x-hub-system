use std::fs;
use std::io;
use std::path::{Path, PathBuf};

pub mod proto {
    tonic::include_proto!("ax.hub.v1");
}

#[derive(Debug, Clone)]
pub struct ProtoSummary {
    pub path: PathBuf,
    pub bytes: u64,
    pub package_name: String,
    pub service_count: usize,
    pub rpc_count: usize,
    pub message_count: usize,
    pub enum_count: usize,
}

impl ProtoSummary {
    pub fn empty(path: PathBuf) -> Self {
        Self {
            path,
            bytes: 0,
            package_name: String::new(),
            service_count: 0,
            rpc_count: 0,
            message_count: 0,
            enum_count: 0,
        }
    }
}

pub fn summarize_proto(path: &Path) -> io::Result<ProtoSummary> {
    let text = fs::read_to_string(path)?;
    let bytes = fs::metadata(path)?.len();
    let mut summary = ProtoSummary::empty(path.to_path_buf());
    summary.bytes = bytes;

    for raw_line in text.lines() {
        let line = raw_line.trim();
        if let Some(rest) = line.strip_prefix("package ") {
            summary.package_name = rest.trim_end_matches(';').trim().to_string();
        } else if line.starts_with("service ") {
            summary.service_count += 1;
        } else if line.starts_with("rpc ") {
            summary.rpc_count += 1;
        } else if line.starts_with("message ") {
            summary.message_count += 1;
        } else if line.starts_with("enum ") {
            summary.enum_count += 1;
        }
    }

    Ok(summary)
}

pub fn expected_package() -> &'static str {
    "ax.hub.v1"
}
