use std::env;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub const DAEMON_NAME: &str = "xhubd";
pub const SCHEMA_HEALTH_V1: &str = "xhub.rust_hub.health.v1";

#[derive(Clone)]
pub struct HubConfig {
    pub root_dir: PathBuf,
    pub host: String,
    pub http_port: u16,
    pub grpc_port: u16,
    pub db_path: PathBuf,
    pub runtime_base_dir: PathBuf,
    pub proto_path: PathBuf,
    pub canonical_proto_path: PathBuf,
    pub http_access_key: Option<String>,
    pub http_access_key_source: String,
    pub http_access_key_required: bool,
}

impl fmt::Debug for HubConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("HubConfig")
            .field("root_dir", &self.root_dir)
            .field("host", &self.host)
            .field("http_port", &self.http_port)
            .field("grpc_port", &self.grpc_port)
            .field("db_path", &self.db_path)
            .field("runtime_base_dir", &self.runtime_base_dir)
            .field("proto_path", &self.proto_path)
            .field("canonical_proto_path", &self.canonical_proto_path)
            .field(
                "http_access_key_configured",
                &self.http_access_key.is_some(),
            )
            .field("http_access_key_source", &self.http_access_key_source)
            .field("http_access_key_required", &self.http_access_key_required)
            .finish()
    }
}

impl HubConfig {
    pub fn from_env(root_dir: PathBuf) -> Self {
        let host = env_string("XHUB_RUST_HUB_HOST", "127.0.0.1");
        let http_port = env_u16("XHUB_RUST_HUB_HTTP_PORT", 50151);
        let grpc_port = env_u16("XHUB_RUST_HUB_GRPC_PORT", 50152);
        let db_path =
            env_path("HUB_DB_PATH").unwrap_or_else(|| root_dir.join("data").join("hub.sqlite3"));
        let runtime_base_dir = env_path("HUB_RUNTIME_BASE_DIR").unwrap_or_else(PathBuf::new);
        let proto_path = env_path("XHUB_RUST_HUB_PROTO_PATH").unwrap_or_else(|| {
            root_dir
                .join("assets")
                .join("proto")
                .join("hub_protocol_v1.proto")
        });
        let canonical_proto_path = env_path("XHUB_CANONICAL_PROTO_PATH").unwrap_or_else(|| {
            let source_proto = root_dir
                .join("..")
                .join("..")
                .join("x-hub-system")
                .join("protocol")
                .join("hub_protocol_v1.proto");
            if source_proto.is_file() {
                source_proto
            } else {
                proto_path.clone()
            }
        });
        let (http_access_key, http_access_key_source) = resolve_http_access_key();
        let http_access_key_required = env_bool("XHUB_RUST_HTTP_REQUIRE_ACCESS_KEY", false);

        Self {
            root_dir,
            host,
            http_port,
            grpc_port,
            db_path,
            runtime_base_dir,
            proto_path,
            canonical_proto_path,
            http_access_key,
            http_access_key_source,
            http_access_key_required,
        }
    }

    pub fn http_addr(&self) -> String {
        format!("{}:{}", self.host, self.http_port)
    }
}

pub fn workspace_root_from_manifest(manifest_dir: &str) -> PathBuf {
    let mut path = PathBuf::from(manifest_dir);
    for _ in 0..2 {
        if let Some(parent) = path.parent() {
            path = parent.to_path_buf();
        }
    }
    path
}

pub fn resolve_runtime_root(manifest_dir: &str) -> PathBuf {
    if let Some(root) = env_path("XHUB_RUST_HUB_ROOT") {
        return root;
    }

    if let Ok(exe) = env::current_exe() {
        for ancestor in exe.ancestors() {
            if looks_like_runtime_root(ancestor) {
                return ancestor.to_path_buf();
            }
        }
    }

    workspace_root_from_manifest(manifest_dir)
}

fn looks_like_runtime_root(path: &Path) -> bool {
    path.join("assets")
        .join("proto")
        .join("hub_protocol_v1.proto")
        .is_file()
        && path.join("config").join("default.toml").is_file()
}

pub fn now_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

pub fn json_escape(input: &str) -> String {
    let mut out = String::with_capacity(input.len() + 8);
    for ch in input.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c.is_control() => {
                let code = c as u32;
                out.push_str(&format!("\\u{code:04x}"));
            }
            c => out.push(c),
        }
    }
    out
}

pub fn path_exists(path: &Path) -> bool {
    std::fs::metadata(path).is_ok()
}

fn env_string(key: &str, fallback: &str) -> String {
    env::var(key)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| fallback.to_string())
}

fn env_u16(key: &str, fallback: u16) -> u16 {
    env::var(key)
        .ok()
        .and_then(|value| value.trim().parse::<u16>().ok())
        .unwrap_or(fallback)
}

fn env_bool(key: &str, fallback: bool) -> bool {
    match env::var(key) {
        Ok(value) => match value.trim().to_ascii_lowercase().as_str() {
            "1" | "true" | "yes" | "y" | "on" => true,
            "0" | "false" | "no" | "n" | "off" => false,
            _ => fallback,
        },
        Err(_) => fallback,
    }
}

fn env_path(key: &str) -> Option<PathBuf> {
    env::var(key)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

fn env_trimmed(key: &str) -> Option<String> {
    env::var(key)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn resolve_http_access_key() -> (Option<String>, String) {
    for key in ["XHUB_RUST_HTTP_ACCESS_KEY", "XHUB_RUST_HUB_ACCESS_KEY"] {
        if let Some(secret) = env_trimmed(key) {
            return (Some(secret), format!("env:{key}"));
        }
    }

    for key in [
        "XHUB_RUST_HTTP_ACCESS_KEY_FILE",
        "XHUB_RUST_HUB_ACCESS_KEY_FILE",
    ] {
        let Some(file_path) = env_path(key) else {
            continue;
        };
        match fs::read_to_string(&file_path) {
            Ok(contents) => {
                let secret = contents.trim().to_string();
                if secret.is_empty() {
                    return (None, format!("empty_file:{key}"));
                }
                return (Some(secret), format!("file:{key}"));
            }
            Err(_) => return (None, format!("unreadable_file:{key}")),
        }
    }

    (None, String::new())
}
