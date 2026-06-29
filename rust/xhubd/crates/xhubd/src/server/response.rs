use std::io::Write;
use std::net::TcpStream;
use std::sync::atomic::Ordering;
use std::time::Duration;

use xhub_core::now_ms;

use super::state::{HttpInflightGuard, HttpMetricSample, HubState};

pub(crate) fn apply_http_io_timeouts(stream: &TcpStream, state: &HubState) -> Result<(), String> {
    let read_timeout = duration_from_timeout_ms(state.http_read_timeout_ms);
    let write_timeout = duration_from_timeout_ms(state.http_write_timeout_ms);
    stream
        .set_read_timeout(read_timeout)
        .map_err(|err| format!("set_http_read_timeout:{err}"))?;
    stream
        .set_write_timeout(write_timeout)
        .map_err(|err| format!("set_http_write_timeout:{err}"))?;
    Ok(())
}

pub(crate) fn duration_from_timeout_ms(timeout_ms: u64) -> Option<Duration> {
    if timeout_ms == 0 {
        None
    } else {
        Some(Duration::from_millis(timeout_ms))
    }
}

pub(crate) fn write_http_response(
    stream: &mut TcpStream,
    status: &'static str,
    body: &str,
) -> Result<(), String> {
    write_http_response_with_content_type(stream, status, body, "application/json; charset=utf-8")
}

pub(crate) fn write_http_response_with_content_type(
    stream: &mut TcpStream,
    status: &'static str,
    body: &str,
    content_type: &str,
) -> Result<(), String> {
    let response = format!(
        "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.as_bytes().len(),
        body
    );
    stream
        .write_all(response.as_bytes())
        .map_err(|err| err.to_string())?;
    Ok(())
}

pub(crate) fn acquire_http_inflight_slot<'a>(
    state: &'a HubState,
    route_path: &str,
) -> Result<Option<HttpInflightGuard<'a>>, String> {
    if route_path == "/health" {
        return Ok(None);
    }
    let max = state.http_max_in_flight.max(1);
    let mut current = state.http_in_flight.load(Ordering::Acquire);
    loop {
        if current >= max {
            return Err(format!(
                "{{\"ok\":false,\"error\":\"http_backpressure\",\"message\":\"Rust Hub HTTP in-flight limit reached\",\"in_flight\":{},\"max_in_flight\":{},\"retry_after_ms\":250}}\n",
                current, max
            ));
        }
        match state.http_in_flight.compare_exchange_weak(
            current,
            current + 1,
            Ordering::AcqRel,
            Ordering::Acquire,
        ) {
            Ok(_) => return Ok(Some(HttpInflightGuard { state })),
            Err(next) => current = next,
        }
    }
}

pub(crate) fn record_http_route_metrics(
    state: &HubState,
    route_path: &str,
    status: &str,
    elapsed_ms: u128,
) {
    let route = sanitized_route_label(route_path);
    let slow = elapsed_ms >= state.http_slow_ms;
    if slow {
        eprintln!(
            "xhubd slow request route={} status={} elapsed_ms={} slow_ms={}",
            route, status, elapsed_ms, state.http_slow_ms
        );
    }

    let Ok(mut metrics) = state.http_metrics.lock() else {
        return;
    };
    metrics.total_requests = metrics.total_requests.saturating_add(1);
    metrics.max_elapsed_ms = metrics.max_elapsed_ms.max(elapsed_ms);
    if slow {
        metrics.slow_requests = metrics.slow_requests.saturating_add(1);
    }
    let route_metrics = metrics.routes.entry(route.clone()).or_default();
    route_metrics.count = route_metrics.count.saturating_add(1);
    route_metrics.total_elapsed_ms = route_metrics.total_elapsed_ms.saturating_add(elapsed_ms);
    route_metrics.max_elapsed_ms = route_metrics.max_elapsed_ms.max(elapsed_ms);
    route_metrics.last_elapsed_ms = elapsed_ms;
    route_metrics.last_status = status.to_string();
    if slow {
        route_metrics.slow_count = route_metrics.slow_count.saturating_add(1);
    }
    if state.http_metrics_recent_limit > 0 {
        while metrics.recent_samples.len() >= state.http_metrics_recent_limit {
            metrics.recent_samples.pop_front();
            metrics.recent_dropped_samples = metrics.recent_dropped_samples.saturating_add(1);
        }
        metrics.recent_samples.push_back(HttpMetricSample {
            completed_at_ms: now_ms(),
            route,
            status: status.to_string(),
            elapsed_ms,
            slow,
        });
    }
}

pub(crate) fn sanitized_route_label(route_path: &str) -> String {
    let route_without_query = route_path.split(['?', '#']).next().unwrap_or(route_path);
    let cleaned = route_without_query
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '/' | '-' | '_' | '.' | ':'))
        .take(120)
        .collect::<String>();
    if cleaned.is_empty() {
        "/unknown".to_string()
    } else {
        cleaned
    }
}
