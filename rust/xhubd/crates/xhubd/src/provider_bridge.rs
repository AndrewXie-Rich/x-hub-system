use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

use serde_json::{json, Value};
use xhub_core::{now_ms, HubConfig};
use xhub_db::{
    apply_baseline_migrations, read_shadow_compare_report_summary, write_shadow_compare_report,
    ShadowCompareReport, ShadowCompareReportSummary,
};
use xhub_provider::{
    normalized_model_id_for_routing, normalized_selection_scope_for_compare,
    route_from_runtime_base_dir, ProviderRouteRequest, PROVIDER_ROUTE_SCHEMA_VERSION,
};

const SCHEMA_VERSION: &str = "xhub.provider_bridge.v1";
const PROVIDER_ROUTE_COMPONENT: &str = "provider_route";
static PROVIDER_COMPARE_REPORT_COUNTER: AtomicU64 = AtomicU64::new(1);

pub fn run(config: &HubConfig, args: &[String]) -> Result<(), String> {
    let body = dispatch(config, args)?;
    println!("{body}");
    Ok(())
}

fn dispatch(config: &HubConfig, args: &[String]) -> Result<String, String> {
    let command = args.first().map(|value| value.as_str()).unwrap_or("help");
    if matches!(command, "help" | "-h" | "--help") {
        return Ok(help_json());
    }

    match command {
        "route" => route_json(config, FlagArgs::parse(&args[1..])?),
        "compare" => compare_json(config, FlagArgs::parse(&args[1..])?),
        "reports" => reports_json(config, FlagArgs::parse(&args[1..])?),
        "readiness" | "cutover-readiness" => readiness_json(config, FlagArgs::parse(&args[1..])?),
        other => Err(format!("unknown provider command: {other}")),
    }
}

fn route_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    let request = provider_route_request(flags)?;
    route_json_from_parts(
        config,
        Some(runtime_base_dir),
        request.model_id,
        request.provider,
        Some(request.now_ms),
    )
}

pub fn route_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    model_id: String,
    provider: String,
    request_now_ms: Option<u128>,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    if model_id.trim().is_empty() {
        return Err("provider route requires model_id".to_string());
    }
    let request = ProviderRouteRequest {
        model_id,
        provider,
        now_ms: request_now_ms.unwrap_or_else(now_ms),
    };
    let decision = route_from_runtime_base_dir(&runtime_base_dir, request)
        .map_err(|err| format!("provider route failed: {err}"))?;
    let decision_json = serde_json::to_string(&decision)
        .map_err(|err| format!("provider route serialize failed: {err}"))?;
    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"route\",\"decision_schema_version\":\"{}\",\"decision\":{}}}",
        SCHEMA_VERSION, PROVIDER_ROUTE_SCHEMA_VERSION, decision_json
    ))
}

fn compare_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    let raw_node_decision = flags.required("node-decision-json")?;
    let node_value: Value = serde_json::from_str(&raw_node_decision)
        .map_err(|err| format!("invalid node-decision-json: {err}"))?;
    compare_json_from_parts(
        config,
        Some(runtime_base_dir),
        node_value,
        flags.optional("model-id"),
        flags.optional("provider"),
        flags.optional_u128("now-ms")?,
    )
}

pub fn compare_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    node_value: Value,
    model_id: Option<String>,
    provider: Option<String>,
    compare_now_ms: Option<u128>,
) -> Result<String, String> {
    apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("provider compare migration failed: {err}"))?;
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    let model_id = model_id
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| value_string(&node_value, "requested_model_id"));
    if model_id.trim().is_empty() {
        return Err("provider compare requires model_id or node requested_model_id".to_string());
    }
    let provider = provider
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| value_string(&node_value, "requested_provider"));
    let compare_now_ms = compare_now_ms
        .or_else(|| value_u128(&node_value, "updated_at_ms"))
        .unwrap_or_else(now_ms);

    let rust_decision = route_from_runtime_base_dir(
        &runtime_base_dir,
        ProviderRouteRequest {
            model_id,
            provider,
            now_ms: compare_now_ms,
        },
    )
    .map_err(|err| format!("provider compare route failed: {err}"))?;
    let rust_value = serde_json::to_value(&rust_decision)
        .map_err(|err| format!("provider compare serialize failed: {err}"))?;
    let node_normalized = normalize_provider_decision(&node_value);
    let rust_normalized = normalize_provider_decision(&rust_value);
    let mut mismatches = Vec::new();
    collect_value_mismatches("", &node_normalized, &rust_normalized, &mut mismatches);

    let compared_at_ms = now_ms().min(i64::MAX as u128) as i64;
    let report_id = format!(
        "provider_route_compare_{}_{}_{}",
        compared_at_ms,
        std::process::id(),
        PROVIDER_COMPARE_REPORT_COUNTER.fetch_add(1, Ordering::Relaxed)
    );
    let match_result = if mismatches.is_empty() {
        "match"
    } else {
        "mismatch"
    };
    let rust_status_json = serde_json::to_string(&rust_normalized)
        .map_err(|err| format!("provider compare rust normalize failed: {err}"))?;
    let node_status_json = serde_json::to_string(&node_normalized)
        .map_err(|err| format!("provider compare node normalize failed: {err}"))?;
    let mismatch_json = serde_json::to_string(&mismatches)
        .map_err(|err| format!("provider compare mismatch serialize failed: {err}"))?;

    write_shadow_compare_report(
        &config.db_path,
        &ShadowCompareReport {
            report_id: report_id.clone(),
            component: PROVIDER_ROUTE_COMPONENT.to_string(),
            compared_at_ms,
            match_result: match_result.to_string(),
            rust_status_json,
            node_status_json,
            mismatch_json,
        },
    )
    .map_err(|err| format!("provider compare report write failed: {err}"))?;

    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "compare",
        "component": PROVIDER_ROUTE_COMPONENT,
        "report_id": report_id,
        "match": mismatches.is_empty(),
        "match_result": match_result,
        "decision_schema_version": PROVIDER_ROUTE_SCHEMA_VERSION,
        "node": node_normalized,
        "rust": rust_normalized,
        "mismatches": mismatches,
    })
    .to_string())
}

fn reports_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let limit = flags.optional_usize("limit")?.unwrap_or(20);
    reports_json_from_parts(config, limit)
}

pub fn reports_json_from_parts(config: &HubConfig, limit: usize) -> Result<String, String> {
    apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("provider reports migration failed: {err}"))?;
    let summary =
        read_shadow_compare_report_summary(&config.db_path, PROVIDER_ROUTE_COMPONENT, limit)
            .map_err(|err| format!("provider reports read failed: {err}"))?;
    Ok(report_summary_json(&summary))
}

fn readiness_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let limit = flags.optional_usize("limit")?.unwrap_or(20);
    let min_compare_reports = flags
        .optional_i64("min-compare-reports")?
        .unwrap_or(10)
        .max(0);
    let max_mismatches = flags.optional_i64("max-mismatches")?.unwrap_or(0).max(0);
    readiness_json_from_parts(config, min_compare_reports, max_mismatches, limit)
}

pub fn readiness_json_from_parts(
    config: &HubConfig,
    min_compare_reports: i64,
    max_mismatches: i64,
    limit: usize,
) -> Result<String, String> {
    apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("provider readiness migration failed: {err}"))?;
    let min_compare_reports = min_compare_reports.max(0);
    let max_mismatches = max_mismatches.max(0);
    let summary =
        read_shadow_compare_report_summary(&config.db_path, PROVIDER_ROUTE_COMPONENT, limit)
            .map_err(|err| format!("provider readiness report read failed: {err}"))?;
    let total_ok = summary.total >= min_compare_reports;
    let mismatch_ok = summary.mismatched <= max_mismatches;
    let ready = total_ok && mismatch_ok;
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "readiness",
        "component": PROVIDER_ROUTE_COMPONENT,
        "ready": ready,
        "decision": if ready { "ready" } else { "not_ready" },
        "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
        "thresholds": {
            "min_compare_reports": min_compare_reports,
            "max_mismatches": max_mismatches,
        },
        "checks": [
            {
                "name": "provider_route_min_reports",
                "ok": total_ok,
                "actual": summary.total,
                "threshold": min_compare_reports,
                "detail": "provider route shadow compare evidence count"
            },
            {
                "name": "provider_route_mismatches",
                "ok": mismatch_ok,
                "actual": summary.mismatched,
                "threshold": max_mismatches,
                "detail": "provider route mismatches must stay within threshold"
            }
        ],
        "compare": {
            "component": summary.component,
            "total": summary.total,
            "matched": summary.matched,
            "mismatched": summary.mismatched,
            "latest_compared_at_ms": summary.latest_compared_at_ms,
        }
    })
    .to_string())
}

fn provider_route_request(flags: FlagArgs) -> Result<ProviderRouteRequest, String> {
    if let Some(raw) = flags.optional("request-json") {
        let value: serde_json::Value =
            serde_json::from_str(&raw).map_err(|err| format!("invalid request-json: {err}"))?;
        let model_id = value
            .get("model_id")
            .or_else(|| value.get("modelId"))
            .and_then(|value| value.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        if model_id.is_empty() {
            return Err("provider route requires model_id in request-json".to_string());
        }
        let provider = value
            .get("provider")
            .or_else(|| value.get("provider_override"))
            .or_else(|| value.get("providerOverride"))
            .and_then(|value| value.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        let request_now_ms = value
            .get("now_ms")
            .or_else(|| value.get("nowMs"))
            .and_then(|value| value.as_u64())
            .map(u128::from)
            .unwrap_or_else(now_ms);
        return Ok(ProviderRouteRequest {
            model_id,
            provider,
            now_ms: request_now_ms,
        });
    }

    let model_id = flags.required("model-id")?;
    Ok(ProviderRouteRequest {
        model_id,
        provider: flags.optional("provider").unwrap_or_default(),
        now_ms: flags.optional_u128("now-ms")?.unwrap_or_else(now_ms),
    })
}

fn help_json() -> String {
    format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"commands\":[\"route\",\"compare\",\"reports\",\"readiness\"],\"route_flags\":[\"--model-id\",\"--provider\",\"--runtime-base-dir\",\"--request-json\",\"--now-ms\"],\"compare_flags\":[\"--node-decision-json\",\"--model-id\",\"--provider\",\"--runtime-base-dir\",\"--now-ms\"],\"reports_flags\":[\"--limit\"],\"readiness_flags\":[\"--min-compare-reports\",\"--max-mismatches\",\"--limit\"]}}",
        SCHEMA_VERSION
    )
}

fn normalize_provider_decision(decision: &Value) -> Value {
    let candidates = decision
        .get("candidates")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .map(|candidate| {
                    json!({
                        "account_key": value_string(candidate, "account_key"),
                        "provider": value_string(candidate, "provider"),
                        "provider_group": value_string(candidate, "provider_group"),
                        "state": value_string(candidate, "state").if_empty("blocked"),
                        "reason_code": value_string(candidate, "reason_code"),
                        "selected": candidate.get("selected").and_then(Value::as_bool).unwrap_or(false),
                        "model_state_key": normalized_model_id_for_routing(&value_string(candidate, "model_state_key")),
                    })
                })
                .collect::<Vec<Value>>()
        })
        .unwrap_or_default();
    json!({
        "requested_provider": value_string(decision, "requested_provider"),
        "requested_model_id": normalized_model_id_for_routing(&value_string(decision, "requested_model_id")),
        "resolved_provider": value_string(decision, "resolved_provider"),
        "strategy": value_string(decision, "strategy").if_empty("fill-first"),
        "selection_scope": normalized_selection_scope_for_compare(&value_string(decision, "selection_scope")),
        "selected_account_key": value_string(decision, "selected_account_key"),
        "fallback_reason_code": value_string(decision, "fallback_reason_code"),
        "available_count": value_u64(decision, "available_count").unwrap_or(0),
        "total_count": value_u64(decision, "total_count").unwrap_or(0),
        "candidates": candidates,
    })
}

fn collect_value_mismatches(path: &str, left: &Value, right: &Value, out: &mut Vec<String>) {
    match (left, right) {
        (Value::Object(left_obj), Value::Object(right_obj)) => {
            let keys: std::collections::BTreeSet<String> = left_obj
                .keys()
                .chain(right_obj.keys())
                .map(|key| key.to_string())
                .collect();
            for key in keys {
                let next_path = if path.is_empty() {
                    key.clone()
                } else {
                    format!("{path}.{key}")
                };
                collect_value_mismatches(
                    &next_path,
                    left_obj.get(&key).unwrap_or(&Value::Null),
                    right_obj.get(&key).unwrap_or(&Value::Null),
                    out,
                );
            }
        }
        (Value::Array(left_items), Value::Array(right_items)) => {
            if left_items.len() != right_items.len() {
                out.push(format!(
                    "{} length {} != {}",
                    if path.is_empty() { "value" } else { path },
                    left_items.len(),
                    right_items.len()
                ));
                return;
            }
            for (idx, (left_item, right_item)) in
                left_items.iter().zip(right_items.iter()).enumerate()
            {
                collect_value_mismatches(&format!("{path}[{idx}]"), left_item, right_item, out);
            }
        }
        _ if left != right => out.push(format!(
            "{} {} != {}",
            if path.is_empty() { "value" } else { path },
            left,
            right
        )),
        _ => {}
    }
}

fn report_summary_json(summary: &ShadowCompareReportSummary) -> String {
    let rows: Vec<Value> = summary
        .rows
        .iter()
        .map(|row| {
            json!({
                "report_id": row.report_id,
                "component": row.component,
                "compared_at_ms": row.compared_at_ms,
                "match_result": row.match_result,
                "mismatches": serde_json::from_str::<Value>(&row.mismatch_json).unwrap_or_else(|_| json!([])),
            })
        })
        .collect();
    json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "reports",
        "component": summary.component,
        "total": summary.total,
        "matched": summary.matched,
        "mismatched": summary.mismatched,
        "latest_compared_at_ms": summary.latest_compared_at_ms,
        "rows": rows,
    })
    .to_string()
}

fn value_string(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string()
}

fn value_u64(value: &Value, key: &str) -> Option<u64> {
    value.get(key).and_then(|item| {
        item.as_u64()
            .or_else(|| {
                item.as_i64()
                    .and_then(|number| u64::try_from(number.max(0)).ok())
            })
            .or_else(|| item.as_str().and_then(|raw| raw.trim().parse::<u64>().ok()))
    })
}

fn value_u128(value: &Value, key: &str) -> Option<u128> {
    value_u64(value, key).map(u128::from)
}

trait IfEmpty {
    fn if_empty(self, fallback: &str) -> String;
}

impl IfEmpty for String {
    fn if_empty(self, fallback: &str) -> String {
        if self.is_empty() {
            fallback.to_string()
        } else {
            self
        }
    }
}

#[derive(Debug, Clone)]
struct FlagArgs {
    values: BTreeMap<String, String>,
}

impl FlagArgs {
    fn parse(args: &[String]) -> Result<Self, String> {
        let mut values = BTreeMap::new();
        let mut i = 0;
        while i < args.len() {
            let raw = &args[i];
            if !raw.starts_with("--") {
                return Err(format!("unexpected positional argument: {raw}"));
            }
            let key = raw.trim_start_matches("--").to_string();
            if key.is_empty() {
                return Err("empty flag name".to_string());
            }
            let value = args
                .get(i + 1)
                .ok_or_else(|| format!("missing value for --{key}"))?;
            if value.starts_with("--") {
                return Err(format!("missing value for --{key}"));
            }
            values.insert(key, value.clone());
            i += 2;
        }
        Ok(Self { values })
    }

    fn required(&self, key: &str) -> Result<String, String> {
        self.optional(key)
            .filter(|value| !value.trim().is_empty())
            .ok_or_else(|| format!("missing required flag --{key}"))
    }

    fn optional(&self, key: &str) -> Option<String> {
        self.values.get(key).cloned()
    }

    fn optional_u128(&self, key: &str) -> Result<Option<u128>, String> {
        let Some(value) = self.optional(key) else {
            return Ok(None);
        };
        value
            .parse::<u128>()
            .map(Some)
            .map_err(|err| format!("invalid --{key}: {err}"))
    }

    fn optional_i64(&self, key: &str) -> Result<Option<i64>, String> {
        let Some(value) = self.optional(key) else {
            return Ok(None);
        };
        value
            .parse::<i64>()
            .map(Some)
            .map_err(|err| format!("invalid --{key}: {err}"))
    }

    fn optional_usize(&self, key: &str) -> Result<Option<usize>, String> {
        let Some(value) = self.optional(key) else {
            return Ok(None);
        };
        value
            .parse::<usize>()
            .map(Some)
            .map_err(|err| format!("invalid --{key}: {err}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compare_normalization_canonicalizes_openai_gpt_model_aliases() {
        let normalized = normalize_provider_decision(&json!({
            "requested_provider": "openai",
            "requested_model_id": "openai/GPT5.5",
            "resolved_provider": "openai",
            "strategy": "",
            "selection_scope": "openai::gpt5.5",
            "selected_account_key": "acct-a",
            "fallback_reason_code": "",
            "available_count": 1,
            "total_count": 1,
            "candidates": [
                {
                    "account_key": "acct-a",
                    "provider": "openai",
                    "provider_group": "openai",
                    "state": "ready",
                    "reason_code": "selected_by_scheduler",
                    "selected": true,
                    "model_state_key": "gpt5.5"
                }
            ]
        }));

        assert_eq!(normalized["requested_model_id"], "gpt-5.5");
        assert_eq!(normalized["selection_scope"], "openai::gpt-5.5");
        assert_eq!(normalized["candidates"][0]["model_state_key"], "gpt-5.5");
    }
}
