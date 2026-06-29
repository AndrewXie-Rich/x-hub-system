use std::env;
use std::path::PathBuf;

use xhub_core::HubConfig;

pub(crate) fn enforce_http_bind_policy(config: &HubConfig) -> Result<(), String> {
    if is_loopback_host(&config.host) || env_bool("XHUB_RUST_HUB_ALLOW_LAN", false) {
        return Ok(());
    }
    Err(format!(
        "refusing non-loopback HTTP bind host={} without XHUB_RUST_HUB_ALLOW_LAN=1",
        config.host
    ))
}

pub(crate) fn is_loopback_host(host: &str) -> bool {
    let normalized = host
        .trim()
        .trim_start_matches('[')
        .trim_end_matches(']')
        .to_ascii_lowercase();
    normalized == "localhost" || normalized == "::1" || normalized.starts_with("127.")
}

pub(crate) fn is_wildcard_host(host: &str) -> bool {
    let normalized = host
        .trim()
        .trim_start_matches('[')
        .trim_end_matches(']')
        .to_ascii_lowercase();
    normalized == "0.0.0.0" || normalized == "::" || normalized == "*"
}

pub(crate) fn env_string(key: &str) -> String {
    env::var(key)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_default()
}

pub(crate) fn env_bool(key: &str, fallback: bool) -> bool {
    match env::var(key) {
        Ok(value) => match value.trim().to_ascii_lowercase().as_str() {
            "1" | "true" | "yes" | "y" | "on" => true,
            "0" | "false" | "no" | "n" | "off" => false,
            _ => fallback,
        },
        Err(_) => fallback,
    }
}

pub(crate) fn env_u128_in_range(key: &str, fallback: u128, min: u128, max: u128) -> u128 {
    env::var(key)
        .ok()
        .and_then(|value| value.trim().parse::<u128>().ok())
        .map(|value| value.clamp(min, max))
        .unwrap_or(fallback.clamp(min, max))
}

pub(crate) fn env_usize_in_range(key: &str, fallback: usize, min: usize, max: usize) -> usize {
    env::var(key)
        .ok()
        .and_then(|value| value.trim().parse::<usize>().ok())
        .map(|value| value.clamp(min, max))
        .unwrap_or(fallback.clamp(min, max))
}

pub(crate) fn env_path_or_default(key: &str, fallback: PathBuf) -> PathBuf {
    env::var(key)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or(fallback)
}

pub(crate) fn cross_network_public_endpoint_enabled() -> bool {
    env_bool("XHUB_RUST_CROSS_NETWORK_PUBLIC_ENDPOINT", false)
        || env_bool("XHUB_RUST_HUB_PUBLIC_ENDPOINT", false)
}

pub(crate) fn provider_route_production_authority_enabled() -> bool {
    env_bool("XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY", false)
        || env_bool("XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION", false)
        || (env_bool("XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CUTOVER", false)
            && env_bool("XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_APPLY", false))
}

pub(crate) fn model_route_production_authority_enabled() -> bool {
    env_bool("XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY", false)
        || env_bool("XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION", false)
        || (env_bool("XHUB_RUST_MODEL_ROUTE_AUTHORITY_CUTOVER", false)
            && env_bool("XHUB_RUST_MODEL_ROUTE_AUTHORITY_APPLY", false))
}

pub(crate) fn scheduler_production_authority_enabled() -> bool {
    env_bool("XHUB_RUST_SCHEDULER_AUTHORITY", false)
}

pub(crate) fn xt_file_ipc_production_authority_enabled(surface_ready: bool) -> bool {
    surface_ready && env_bool("XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER", false)
}

pub(crate) fn public_base_url_host(public_base_url: &str) -> Option<String> {
    let value = public_base_url.trim();
    let after_scheme = value
        .strip_prefix("https://")
        .or_else(|| value.strip_prefix("http://"))?;
    if after_scheme.is_empty() || after_scheme.contains(char::is_whitespace) {
        return None;
    }
    let authority = after_scheme
        .split(['/', '?', '#'])
        .next()
        .unwrap_or_default()
        .trim();
    if authority.is_empty() || authority.contains('@') {
        return None;
    }
    if let Some(rest) = authority.strip_prefix('[') {
        return rest
            .split(']')
            .next()
            .map(|host| host.trim().to_string())
            .filter(|host| !host.is_empty());
    }
    authority
        .split(':')
        .next()
        .map(|host| host.trim().to_string())
        .filter(|host| !host.is_empty())
}

pub(crate) fn public_base_url_ready(public_base_url: &str) -> bool {
    let value = public_base_url.trim();
    if value.is_empty() || value.to_ascii_lowercase().contains("replace_with") {
        return false;
    }
    if !(value.starts_with("https://") || value.starts_with("http://")) {
        return false;
    }
    let Some(host) = public_base_url_host(value) else {
        return false;
    };
    !is_loopback_host(host.as_str()) && !is_wildcard_host(host.as_str())
}
