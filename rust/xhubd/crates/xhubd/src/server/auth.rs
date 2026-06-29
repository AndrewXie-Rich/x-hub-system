use std::net::SocketAddr;

use xhub_core::HubConfig;

use super::request::HttpRequest;
use crate::config::{cross_network_public_endpoint_enabled, is_loopback_host};

pub(crate) fn http_access_key_failure(
    request: &HttpRequest,
    config: &HubConfig,
    peer_addr: Option<SocketAddr>,
    route_path: &str,
) -> Option<(&'static str, String)> {
    http_access_key_failure_with_public_endpoint(
        request,
        config,
        peer_addr,
        route_path,
        cross_network_public_endpoint_enabled(),
    )
}

pub(crate) fn http_access_key_failure_with_public_endpoint(
    request: &HttpRequest,
    config: &HubConfig,
    peer_addr: Option<SocketAddr>,
    route_path: &str,
    public_endpoint_enabled: bool,
) -> Option<(&'static str, String)> {
    if !http_access_key_required_for_request_with_public_endpoint(
        config,
        peer_addr,
        route_path,
        public_endpoint_enabled,
    ) {
        return None;
    }

    let Some(expected) = config
        .http_access_key
        .as_deref()
        .filter(|value| !value.is_empty())
    else {
        return Some((
            "403 Forbidden",
            "{\"ok\":false,\"error\":\"access_key_not_configured\",\"message\":\"cross-network Rust Hub HTTP requires XHUB_RUST_HTTP_ACCESS_KEY_FILE or XHUB_RUST_HTTP_ACCESS_KEY\"}\n".to_string(),
        ));
    };

    match http_access_key_from_request(request) {
        Some(actual) if constant_time_eq(actual.as_bytes(), expected.as_bytes()) => None,
        Some(_) => Some((
            "401 Unauthorized",
            "{\"ok\":false,\"error\":\"invalid_access_key\"}\n".to_string(),
        )),
        None => Some((
            "401 Unauthorized",
            "{\"ok\":false,\"error\":\"missing_access_key\",\"message\":\"send Authorization: Bearer <key> or X-XHub-Access-Key\"}\n".to_string(),
        )),
    }
}

pub(crate) fn http_access_key_required_for_request_with_public_endpoint(
    config: &HubConfig,
    peer_addr: Option<SocketAddr>,
    route_path: &str,
    public_endpoint_enabled: bool,
) -> bool {
    if route_path == "/health" {
        return false;
    }
    if config.http_access_key_required {
        return true;
    }
    if public_endpoint_enabled {
        return true;
    }
    let peer_is_loopback = peer_addr
        .map(|addr| addr.ip().is_loopback())
        .unwrap_or_else(|| is_loopback_host(&config.host));
    !peer_is_loopback
}

pub(crate) fn http_access_key_from_request(request: &HttpRequest) -> Option<String> {
    request
        .header("authorization")
        .and_then(|value| {
            let trimmed = value.trim();
            let mut parts = trimmed.splitn(2, char::is_whitespace);
            let scheme = parts.next().unwrap_or("");
            let token = parts.next().unwrap_or("").trim();
            if scheme.eq_ignore_ascii_case("bearer") && !token.is_empty() {
                Some(token.to_string())
            } else {
                None
            }
        })
        .or_else(|| {
            request
                .header("x-xhub-access-key")
                .or_else(|| request.header("x-hub-access-key"))
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty())
        })
}

pub(crate) fn constant_time_eq(left: &[u8], right: &[u8]) -> bool {
    if left.len() != right.len() {
        return false;
    }
    let mut diff = 0_u8;
    for (a, b) in left.iter().zip(right.iter()) {
        diff |= a ^ b;
    }
    diff == 0
}
