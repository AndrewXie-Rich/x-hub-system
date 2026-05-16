use std::env;
use std::net::Ipv4Addr;
use std::process::Command;

use serde_json::{json, Value};
use xhub_core::HubConfig;

const SCHEMA_VERSION: &str = "xhub.rust_hub.remote_entry_candidates.v1";

#[derive(Clone, Debug, Eq, PartialEq)]
struct InterfaceAddress {
    name: String,
    address: String,
    family: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct HostClassification {
    kind: &'static str,
    scope: &'static str,
    stable: bool,
    encrypted_private_candidate: bool,
    reason_code: &'static str,
}

pub fn run(config: &HubConfig, args: &[String]) -> Result<(), String> {
    let command = args.first().map(|value| value.as_str()).unwrap_or("help");
    if matches!(command, "help" | "-h" | "--help") {
        println!("{}", help_json());
        return Ok(());
    }
    match command {
        "remote-entry" | "remote-entry-candidates" | "candidates" => {
            println!("{}", remote_entry_candidates_json(config, ""));
            Ok(())
        }
        other => Err(format!("unknown network command: {other}")),
    }
}

pub fn remote_entry_candidates_http_json(
    config: &HubConfig,
    query: &str,
) -> (&'static str, String) {
    ("200 OK", remote_entry_candidates_json(config, query))
}

pub fn remote_entry_candidates_json(config: &HubConfig, query: &str) -> String {
    let public_base_url = query_value(query, "public_base_url")
        .or_else(|| query_value(query, "publicBaseUrl"))
        .unwrap_or_else(|| env_string("XHUB_RUST_HUB_PUBLIC_BASE_URL"));
    let current_host = query_value(query, "current_host")
        .or_else(|| query_value(query, "currentHost"))
        .unwrap_or_else(|| env_string("XHUB_RUST_HUB_REMOTE_HOST"));
    let explicit_private_host = query_value(query, "private_host")
        .or_else(|| query_value(query, "privateHost"))
        .or_else(|| query_value(query, "no_domain_private_host"))
        .or_else(|| query_value(query, "noDomainPrivateHost"))
        .or_else(|| {
            first_env_string(&[
                "XHUB_RUST_NO_DOMAIN_PRIVATE_HOST",
                "XHUB_RUST_REMOTE_PRIVATE_HOST",
                "XHUB_RUST_HUB_PRIVATE_HOST",
            ])
        });
    let rows = interface_rows_from_env().unwrap_or_else(detect_interface_rows);
    let report = build_remote_entry_report(
        config,
        public_base_url.as_str(),
        current_host.as_str(),
        explicit_private_host.as_deref(),
        &rows,
    );
    serde_json::to_string(&report).unwrap_or_else(|err| {
        json!({
            "schema_version": SCHEMA_VERSION,
            "ok": false,
            "error": "remote_entry_candidates_serialize_failed",
            "message": err.to_string(),
        })
        .to_string()
    })
}

fn help_json() -> String {
    json!({
        "schema_version": "xhub.rust_hub.network_bridge.v1",
        "ok": true,
        "commands": ["remote-entry-candidates"],
        "http_routes": ["/network/remote-entry-candidates", "/network/remote-entry", "/remote/entry-candidates"],
        "description": "Rust core authority for Swift Hub remote-entry setup, including no-domain private network candidates.",
    })
    .to_string()
}

fn build_remote_entry_report(
    config: &HubConfig,
    public_base_url: &str,
    current_host: &str,
    explicit_private_host: Option<&str>,
    rows: &[InterfaceAddress],
) -> Value {
    let public_base_url = public_base_url.trim();
    let current_host = current_host.trim();
    let public_candidate = public_remote_candidate(public_base_url);
    let explicit_private_candidate = explicit_private_host.and_then(|host| {
        let host = host.trim();
        if host.is_empty() {
            None
        } else {
            Some(private_remote_candidate_from_host(
                host,
                "explicit_private_host",
                true,
            ))
        }
    });
    let interface_candidates = private_remote_candidates_from_interfaces(rows);

    let preferred = public_candidate
        .as_ref()
        .filter(|candidate| candidate["usable"].as_bool().unwrap_or(false))
        .cloned()
        .or_else(|| {
            explicit_private_candidate
                .as_ref()
                .filter(|candidate| candidate["usable"].as_bool().unwrap_or(false))
                .cloned()
        })
        .or_else(|| interface_candidates.first().cloned());

    let mut candidates = Vec::new();
    if let Some(candidate) = public_candidate {
        candidates.push(candidate);
    }
    if let Some(candidate) = explicit_private_candidate {
        candidates.push(candidate);
    }
    candidates.extend(interface_candidates);

    let has_public = candidates.iter().any(|candidate| {
        candidate["route_kind"] == "stable_domain_or_tunnel"
            && candidate["usable"].as_bool().unwrap_or(false)
    });
    let has_private = candidates.iter().any(|candidate| {
        candidate["route_kind"] == "no_domain_private_network"
            && candidate["usable"].as_bool().unwrap_or(false)
    });
    let recommended_setup = if has_public {
        "use_stable_domain_or_tunnel"
    } else if has_private {
        "use_no_domain_private_network"
    } else {
        "needs_domain_tunnel_or_private_network"
    };

    json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "source": "rust_core_network_bridge",
        "hub": {
            "host": config.host,
            "http_port": config.http_port,
            "grpc_port": config.grpc_port,
        },
        "inputs": {
            "public_base_url": public_base_url,
            "current_host": current_host,
            "explicit_private_host_present": explicit_private_host.map(|host| !host.trim().is_empty()).unwrap_or(false),
            "interface_address_count": rows.len(),
        },
        "preferred": preferred.unwrap_or_else(|| json!({})),
        "candidates": candidates,
        "recommended_setup": recommended_setup,
        "policy": {
            "swift_shell_reads_rust_core": true,
            "stable_domain_or_tunnel_preferred": true,
            "no_domain_private_network_supported": true,
            "raw_public_ip_default_allowed": false,
            "mtls_required_for_xt_remote_entry": true,
            "pairing_export_after_smoke": true,
        },
        "operator_guidance": operator_guidance(recommended_setup),
    })
}

fn public_remote_candidate(public_base_url: &str) -> Option<Value> {
    let value = public_base_url.trim();
    if value.is_empty() {
        return None;
    }
    let host = public_base_url_host(value).unwrap_or_default();
    let classification = classify_host(host.as_str());
    let usable = value.starts_with("https://")
        && classification.stable
        && classification.kind != "public_raw_ip";
    let deny_code = if usable {
        ""
    } else if !value.starts_with("https://") {
        "https_required_for_remote_entry"
    } else if host.is_empty() {
        "public_base_url_host_missing"
    } else {
        classification.reason_code
    };
    Some(json!({
        "route_kind": "stable_domain_or_tunnel",
        "source": "public_base_url",
        "host": host,
        "public_base_url": value,
        "usable": usable,
        "requires_same_private_network": false,
        "requires_mtls": true,
        "classification": classification_json(&classification),
        "deny_code": deny_code,
    }))
}

fn private_remote_candidate_from_host(host: &str, source: &str, explicit: bool) -> Value {
    let classification = classify_host(host);
    let usable = matches!(
        classification.scope,
        "tailnet_dns" | "tailscale_headscale_ip" | "private_vpn_ip"
    );
    json!({
        "route_kind": "no_domain_private_network",
        "source": source,
        "host": host,
        "public_base_url": format!("https://{host}"),
        "usable": usable,
        "explicit": explicit,
        "requires_same_private_network": true,
        "requires_mtls": true,
        "classification": classification_json(&classification),
        "deny_code": if usable { "" } else { classification.reason_code },
    })
}

fn private_remote_candidates_from_interfaces(rows: &[InterfaceAddress]) -> Vec<Value> {
    let mut candidates = Vec::new();
    let mut seen = Vec::<String>::new();
    for row in rows {
        if row.family != "ipv4" || seen.iter().any(|value| value == &row.address) {
            continue;
        }
        let classification = classify_host(row.address.as_str());
        let tunnel_interface = interface_looks_private_tunnel(row.name.as_str());
        let usable = classification.scope == "tailscale_headscale_ip"
            || (classification.scope == "private_vpn_ip" && tunnel_interface);
        if !usable {
            continue;
        }
        seen.push(row.address.clone());
        let priority = if classification.scope == "tailscale_headscale_ip" {
            10
        } else {
            30
        };
        candidates.push(json!({
            "route_kind": "no_domain_private_network",
            "source": "local_interface",
            "interface": row.name,
            "host": row.address,
            "public_base_url": format!("https://{}", row.address),
            "usable": true,
            "priority": priority,
            "requires_same_private_network": true,
            "requires_mtls": true,
            "classification": classification_json(&classification),
            "deny_code": "",
        }));
    }
    candidates.sort_by_key(|candidate| {
        candidate
            .get("priority")
            .and_then(Value::as_i64)
            .unwrap_or(999)
    });
    candidates
}

fn operator_guidance(recommended_setup: &str) -> Vec<&'static str> {
    match recommended_setup {
        "use_stable_domain_or_tunnel" => vec![
            "Keep the Swift Hub UI as a shell over this Rust decision.",
            "Run strict domain/tunnel smoke before exporting the XT pairing bundle.",
            "Keep /ready and operational APIs behind the access-key gate.",
        ],
        "use_no_domain_private_network" => vec![
            "Use the detected private-network host for users without a domain.",
            "Hub and every XT device must join the same private network.",
            "Prefer MagicDNS/tailnet DNS over raw VPN IP when available.",
        ],
        _ => vec![
            "Ask the user to configure a stable domain/tunnel or join a private network.",
            "Do not present LAN-only hostnames or raw public IPs as stable remote entries.",
        ],
    }
}

fn classify_host(host: &str) -> HostClassification {
    let normalized = host
        .trim()
        .trim_start_matches('[')
        .trim_end_matches(']')
        .trim_end_matches('.')
        .to_ascii_lowercase();
    if normalized.is_empty() {
        return classification("missing", "missing", false, false, "remote_host_missing");
    }
    if normalized == "localhost" || normalized == "::1" || normalized.starts_with("127.") {
        return classification("loopback", "loopback", false, false, "remote_host_loopback");
    }
    if normalized == "0.0.0.0" || normalized == "::" || normalized == "*" {
        return classification("wildcard", "wildcard", false, false, "remote_host_wildcard");
    }
    if normalized.ends_with(".local") {
        return classification("lan_only", "lan_name", false, false, "remote_host_lan_only");
    }
    if normalized.ends_with(".ts.net") || normalized.ends_with(".tailscale.net") {
        return classification("stable_named", "tailnet_dns", true, true, "");
    }
    if let Ok(ip) = normalized.parse::<Ipv4Addr>() {
        if is_tailscale_headscale_ip(ip) {
            return classification(
                "vpn_raw",
                "tailscale_headscale_ip",
                true,
                true,
                "vpn_raw_host_requires_explicit_allowance",
            );
        }
        if is_private_ipv4(ip) {
            return classification(
                "vpn_raw",
                "private_vpn_ip",
                true,
                true,
                "private_vpn_host_requires_same_network",
            );
        }
        return classification(
            "public_raw_ip",
            "public_ip",
            false,
            false,
            "public_raw_ip_forbidden",
        );
    }
    classification("stable_named", "public_dns", true, false, "")
}

fn classification(
    kind: &'static str,
    scope: &'static str,
    stable: bool,
    encrypted_private_candidate: bool,
    reason_code: &'static str,
) -> HostClassification {
    HostClassification {
        kind,
        scope,
        stable,
        encrypted_private_candidate,
        reason_code,
    }
}

fn classification_json(classification: &HostClassification) -> Value {
    json!({
        "kind": classification.kind,
        "scope": classification.scope,
        "stable": classification.stable,
        "encrypted_private_candidate": classification.encrypted_private_candidate,
        "reason_code": classification.reason_code,
    })
}

fn is_tailscale_headscale_ip(ip: Ipv4Addr) -> bool {
    let octets = ip.octets();
    octets[0] == 100 && (64..=127).contains(&octets[1])
}

fn is_private_ipv4(ip: Ipv4Addr) -> bool {
    let octets = ip.octets();
    octets[0] == 10
        || (octets[0] == 172 && (16..=31).contains(&octets[1]))
        || (octets[0] == 192 && octets[1] == 168)
}

fn interface_looks_private_tunnel(name: &str) -> bool {
    let normalized = name.trim().to_ascii_lowercase();
    normalized.starts_with("tailscale")
        || normalized.starts_with("wg")
        || normalized.starts_with("utun")
        || normalized.starts_with("zt")
        || normalized.starts_with("zerotier")
        || normalized.starts_with("tun")
}

fn public_base_url_host(public_base_url: &str) -> Option<String> {
    let value = public_base_url.trim();
    let after_scheme = value
        .strip_prefix("https://")
        .or_else(|| value.strip_prefix("http://"))?;
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

fn detect_interface_rows() -> Vec<InterfaceAddress> {
    let output = Command::new("ifconfig").output();
    let Ok(output) = output else {
        return Vec::new();
    };
    if !output.status.success() {
        return Vec::new();
    }
    let text = String::from_utf8_lossy(&output.stdout);
    parse_ifconfig_rows(text.as_ref())
}

fn parse_ifconfig_rows(text: &str) -> Vec<InterfaceAddress> {
    let mut rows = Vec::new();
    let mut current_name = String::new();
    for line in text.lines() {
        if !line.starts_with('\t') && !line.starts_with(' ') {
            if let Some((name, _)) = line.split_once(':') {
                current_name = name.trim().to_string();
            }
            continue;
        }
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("inet ") {
            let address = rest.split_whitespace().next().unwrap_or_default().trim();
            if !address.is_empty() {
                rows.push(InterfaceAddress {
                    name: current_name.clone(),
                    address: address.to_string(),
                    family: "ipv4".to_string(),
                });
            }
        }
    }
    rows
}

fn interface_rows_from_env() -> Option<Vec<InterfaceAddress>> {
    let raw = env_string("XHUB_RUST_NETWORK_INTERFACE_ROWS_JSON");
    if raw.is_empty() {
        return None;
    }
    let value: Value = serde_json::from_str(raw.as_str()).ok()?;
    let rows = value.as_array()?;
    Some(
        rows.iter()
            .filter_map(|row| {
                Some(InterfaceAddress {
                    name: value_string(row, "name")
                        .or_else(|| value_string(row, "interface"))
                        .unwrap_or_default(),
                    address: value_string(row, "address")?,
                    family: value_string(row, "family").unwrap_or_else(|| "ipv4".to_string()),
                })
            })
            .collect(),
    )
}

fn query_value(query: &str, key: &str) -> Option<String> {
    for pair in query.split('&') {
        let Some((raw_key, raw_value)) = pair.split_once('=') else {
            continue;
        };
        if raw_key == key {
            let value = percent_decode(raw_value.replace('+', " ").as_str());
            let trimmed = value.trim().to_string();
            if !trimmed.is_empty() {
                return Some(trimmed);
            }
        }
    }
    None
}

fn percent_decode(raw: &str) -> String {
    let bytes = raw.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut idx = 0;
    while idx < bytes.len() {
        if bytes[idx] == b'%' && idx + 2 < bytes.len() {
            if let Ok(hex) = u8::from_str_radix(&raw[idx + 1..idx + 3], 16) {
                out.push(hex);
                idx += 3;
                continue;
            }
        }
        out.push(bytes[idx]);
        idx += 1;
    }
    String::from_utf8_lossy(&out).to_string()
}

fn first_env_string(keys: &[&str]) -> Option<String> {
    keys.iter()
        .map(|key| env_string(key))
        .find(|value| !value.is_empty())
}

fn env_string(key: &str) -> String {
    env::var(key)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_default()
}

fn value_string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn test_config() -> HubConfig {
        let root = PathBuf::from("/tmp/xhub-network-bridge-test");
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
            http_access_key: Some("test-key".to_string()),
            http_access_key_source: "test".to_string(),
            http_access_key_required: false,
        }
    }

    #[test]
    fn prefers_https_domain_over_private_candidates() {
        let rows = vec![InterfaceAddress {
            name: "utun6".to_string(),
            address: "100.96.10.8".to_string(),
            family: "ipv4".to_string(),
        }];
        let report =
            build_remote_entry_report(&test_config(), "https://hub.example.com", "", None, &rows);
        assert_eq!(report["recommended_setup"], "use_stable_domain_or_tunnel");
        assert_eq!(report["preferred"]["route_kind"], "stable_domain_or_tunnel");
    }

    #[test]
    fn no_domain_private_entry_prefers_tailscale_ip() {
        let rows = vec![
            InterfaceAddress {
                name: "en0".to_string(),
                address: "192.168.1.22".to_string(),
                family: "ipv4".to_string(),
            },
            InterfaceAddress {
                name: "utun6".to_string(),
                address: "100.96.10.8".to_string(),
                family: "ipv4".to_string(),
            },
        ];
        let report = build_remote_entry_report(&test_config(), "", "", None, &rows);
        assert_eq!(report["recommended_setup"], "use_no_domain_private_network");
        assert_eq!(report["preferred"]["host"], "100.96.10.8");
        assert_eq!(
            report["preferred"]["classification"]["scope"],
            "tailscale_headscale_ip"
        );
    }

    #[test]
    fn normal_lan_address_is_not_no_domain_remote_candidate() {
        let rows = vec![InterfaceAddress {
            name: "en0".to_string(),
            address: "192.168.1.22".to_string(),
            family: "ipv4".to_string(),
        }];
        let report = build_remote_entry_report(&test_config(), "", "", None, &rows);
        assert_eq!(
            report["recommended_setup"],
            "needs_domain_tunnel_or_private_network"
        );
        assert_eq!(report["candidates"].as_array().unwrap().len(), 0);
    }

    #[test]
    fn tailnet_dns_explicit_private_host_is_usable() {
        let report = build_remote_entry_report(
            &test_config(),
            "",
            "",
            Some("andrew.tailbe79cd.ts.net"),
            &[],
        );
        assert_eq!(report["recommended_setup"], "use_no_domain_private_network");
        assert_eq!(
            report["preferred"]["classification"]["scope"],
            "tailnet_dns"
        );
    }

    #[test]
    fn parse_ifconfig_extracts_ipv4_interface_rows() {
        let rows = parse_ifconfig_rows(
            "lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384\n\
             \tinet 127.0.0.1 netmask 0xff000000\n\
             utun6: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1280\n\
             \tinet 100.96.10.8 --> 100.96.10.8 netmask 0xffffffff\n",
        );
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[1].name, "utun6");
        assert_eq!(rows[1].address, "100.96.10.8");
    }
}
