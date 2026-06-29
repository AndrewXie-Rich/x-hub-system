use std::collections::BTreeMap;
use std::sync::atomic::Ordering;

use serde_json::json;
use xhub_core::now_ms;

use crate::server::state::{HttpRouteMetrics, HubState};

pub(crate) fn http_metrics_json(state: &HubState) -> (&'static str, String) {
    const RECENT_SAMPLE_OUTPUT_LIMIT: usize = 64;
    let now = now_ms();
    let Ok(metrics) = state.http_metrics.lock() else {
        return (
            "503 Service Unavailable",
            "{\"ok\":false,\"error\":\"http_metrics_unavailable\"}\n".to_string(),
        );
    };
    let routes = metrics
        .routes
        .iter()
        .map(|(route, item)| {
            let avg_elapsed_ms = if item.count == 0 {
                0.0
            } else {
                item.total_elapsed_ms as f64 / item.count as f64
            };
            json!({
                "route": route,
                "count": item.count,
                "slow_count": item.slow_count,
                "avg_elapsed_ms": round2(avg_elapsed_ms),
                "max_elapsed_ms": item.max_elapsed_ms.min(i64::MAX as u128) as i64,
                "last_elapsed_ms": item.last_elapsed_ms.min(i64::MAX as u128) as i64,
                "last_status": item.last_status,
            })
        })
        .collect::<Vec<_>>();
    let recent_sample_count = metrics.recent_samples.len();
    let recent_slow_requests = metrics
        .recent_samples
        .iter()
        .filter(|sample| sample.slow)
        .count();
    let recent_total_elapsed_ms = metrics
        .recent_samples
        .iter()
        .fold(0_u128, |acc, sample| acc.saturating_add(sample.elapsed_ms));
    let recent_avg_elapsed_ms = if recent_sample_count == 0 {
        0.0
    } else {
        recent_total_elapsed_ms as f64 / recent_sample_count as f64
    };
    let recent_max_elapsed_ms = metrics
        .recent_samples
        .iter()
        .map(|sample| sample.elapsed_ms)
        .max()
        .unwrap_or(0);
    let mut recent_routes: BTreeMap<String, HttpRouteMetrics> = BTreeMap::new();
    for sample in metrics.recent_samples.iter() {
        let route_metrics = recent_routes.entry(sample.route.clone()).or_default();
        route_metrics.count = route_metrics.count.saturating_add(1);
        route_metrics.total_elapsed_ms = route_metrics
            .total_elapsed_ms
            .saturating_add(sample.elapsed_ms);
        route_metrics.max_elapsed_ms = route_metrics.max_elapsed_ms.max(sample.elapsed_ms);
        route_metrics.last_elapsed_ms = sample.elapsed_ms;
        route_metrics.last_status = sample.status.clone();
        if sample.slow {
            route_metrics.slow_count = route_metrics.slow_count.saturating_add(1);
        }
    }
    let recent_route_summaries = recent_routes
        .iter()
        .map(|(route, item)| {
            let avg_elapsed_ms = if item.count == 0 {
                0.0
            } else {
                item.total_elapsed_ms as f64 / item.count as f64
            };
            json!({
                "route": route,
                "count": item.count,
                "slow_count": item.slow_count,
                "avg_elapsed_ms": round2(avg_elapsed_ms),
                "max_elapsed_ms": item.max_elapsed_ms.min(i64::MAX as u128) as i64,
                "last_elapsed_ms": item.last_elapsed_ms.min(i64::MAX as u128) as i64,
                "last_status": item.last_status,
            })
        })
        .collect::<Vec<_>>();
    let recent_samples = metrics
        .recent_samples
        .iter()
        .rev()
        .take(RECENT_SAMPLE_OUTPUT_LIMIT)
        .map(|sample| {
            json!({
                "completed_at_ms": sample.completed_at_ms.min(i64::MAX as u128) as i64,
                "route": sample.route,
                "status": sample.status,
                "elapsed_ms": sample.elapsed_ms.min(i64::MAX as u128) as i64,
                "slow": sample.slow,
            })
        })
        .collect::<Vec<_>>();
    let avg_elapsed_ms = if metrics.total_requests == 0 {
        0.0
    } else {
        let total = metrics.routes.values().fold(0_u128, |acc, item| {
            acc.saturating_add(item.total_elapsed_ms)
        });
        total as f64 / metrics.total_requests as f64
    };
    let body = json!({
        "schema_version": "xhub.rust_hub.http_metrics.v1",
        "ok": true,
        "generated_at_ms": now.min(i64::MAX as u128) as i64,
        "started_at_ms": metrics.started_at_ms.min(i64::MAX as u128) as i64,
        "uptime_ms": now.saturating_sub(metrics.started_at_ms).min(i64::MAX as u128) as i64,
        "total_requests": metrics.total_requests,
        "slow_requests": metrics.slow_requests,
        "avg_elapsed_ms": round2(avg_elapsed_ms),
        "max_elapsed_ms": metrics.max_elapsed_ms.min(i64::MAX as u128) as i64,
        "slow_threshold_ms": state.http_slow_ms.min(i64::MAX as u128) as i64,
        "recent_sample_capacity": state.http_metrics_recent_limit,
        "recent_sample_count": recent_sample_count,
        "recent_samples_output_limit": RECENT_SAMPLE_OUTPUT_LIMIT,
        "recent_samples_included": recent_samples.len(),
        "recent_dropped_samples": metrics.recent_dropped_samples,
        "recent_slow_requests": recent_slow_requests,
        "recent_avg_elapsed_ms": round2(recent_avg_elapsed_ms),
        "recent_max_elapsed_ms": recent_max_elapsed_ms.min(i64::MAX as u128) as i64,
        "recent_route_count": recent_route_summaries.len(),
        "recent_routes": recent_route_summaries,
        "recent_samples_newest_first": recent_samples,
        "http_max_in_flight": state.http_max_in_flight,
        "current_in_flight": state.http_in_flight.load(Ordering::Acquire),
        "route_count": routes.len(),
        "routes": routes,
        "authority": "diagnostics_only",
        "production_authority_change": false,
        "detail_json_included": false,
    });
    ("200 OK", format!("{body}\n"))
}

pub(crate) fn round2(value: f64) -> f64 {
    (value * 100.0).round() / 100.0
}
