use super::*;

pub(super) fn openai_windows_from_usage(
    usage: &Value,
    base_now_ms: u64,
) -> Vec<ProviderQuotaUsageWindow> {
    let mut windows = Vec::new();
    if let Some(rate_limit) = usage.get("rate_limit").and_then(Value::as_object) {
        let limit_reached = rate_limit
            .get("limit_reached")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        push_openai_window(
            &mut windows,
            "rate_limit",
            "primary",
            rate_limit.get("primary_window"),
            limit_reached,
            "primary",
            base_now_ms,
        );
        push_openai_window(
            &mut windows,
            "rate_limit",
            "secondary",
            rate_limit.get("secondary_window"),
            false,
            "secondary",
            base_now_ms,
        );
    }
    if let Some(rate_limit) = usage
        .get("code_review_rate_limit")
        .and_then(Value::as_object)
    {
        let limit_reached = rate_limit
            .get("limit_reached")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        push_openai_window(
            &mut windows,
            "code_review_rate_limit",
            "primary",
            rate_limit.get("primary_window"),
            limit_reached,
            "code-review primary",
            base_now_ms,
        );
        push_openai_window(
            &mut windows,
            "code_review_rate_limit",
            "secondary",
            rate_limit.get("secondary_window"),
            false,
            "code-review secondary",
            base_now_ms,
        );
    }
    windows
}

fn push_openai_window(
    windows: &mut Vec<ProviderQuotaUsageWindow>,
    source: &str,
    window_key: &str,
    raw_window: Option<&Value>,
    limit_reached: bool,
    label_prefix: &str,
    base_now_ms: u64,
) {
    let Some(raw_window) = raw_window.filter(|value| value.is_object()) else {
        return;
    };
    let used_percent = safe_percent(json_f64(raw_window, "used_percent"));
    let used_basis_points = basis_points_from_percent(used_percent);
    let limit_window_seconds = json_u64(raw_window, "limit_window_seconds");
    let label = codex_window_label(raw_window, label_prefix);
    windows.push(ProviderQuotaUsageWindow {
        key: format!(
            "{}:{}:{}",
            source,
            window_key,
            if limit_window_seconds > 0 {
                limit_window_seconds.to_string()
            } else {
                codex_window_label(raw_window, "")
            }
        ),
        source: source.to_string(),
        window_key: window_key.to_string(),
        label,
        limit_window_seconds,
        used_percent,
        used_basis_points,
        remaining_basis_points: (QUOTA_BASIS_POINTS_CAP as u32).saturating_sub(used_basis_points),
        limited: limit_reached || used_percent >= 100.0,
        reset_at_ms: reset_at_ms_from_window(raw_window, base_now_ms),
        updated_at_ms: base_now_ms,
    });
}

pub(super) fn sorted_quota_windows(
    mut windows: Vec<ProviderQuotaUsageWindow>,
) -> Vec<ProviderQuotaUsageWindow> {
    windows.sort_by(|lhs, rhs| {
        lhs.source
            .cmp(&rhs.source)
            .then_with(|| lhs.limit_window_seconds.cmp(&rhs.limit_window_seconds))
            .then_with(|| lhs.window_key.cmp(&rhs.window_key))
    });
    windows.dedup_by(|lhs, rhs| {
        lhs.key == rhs.key
            || (lhs.source == rhs.source
                && lhs.window_key == rhs.window_key
                && lhs.limit_window_seconds == rhs.limit_window_seconds)
    });
    windows
}

fn reset_at_ms_from_window(window: &Value, base_now_ms: u64) -> u64 {
    let explicit = json_u64(window, "reset_at");
    if explicit > 0 {
        let reset_at_ms = if explicit > 1_000_000_000_000 {
            explicit
        } else {
            explicit.saturating_mul(1000)
        };
        if reset_at_ms > base_now_ms {
            return reset_at_ms;
        }
    }
    let reset_after_seconds = json_u64(window, "reset_after_seconds");
    if reset_after_seconds > 0 {
        base_now_ms.saturating_add(reset_after_seconds.saturating_mul(1000))
    } else {
        0
    }
}

fn codex_window_label(window: &Value, prefix: &str) -> String {
    let seconds = json_u64(window, "limit_window_seconds");
    let label = if seconds >= 7 * 24 * 3600 {
        "7-day window"
    } else if seconds >= 24 * 3600 {
        "24-hour window"
    } else if seconds >= 5 * 3600 {
        "5-hour window"
    } else if seconds >= 3600 {
        "1-hour window"
    } else {
        "usage window"
    };
    let prefix = trim_string(prefix);
    if prefix.is_empty() {
        label.to_string()
    } else {
        format!("{prefix} {label}")
    }
}

fn safe_percent(value: f64) -> f64 {
    if value.is_finite() {
        value.clamp(0.0, 100.0)
    } else {
        0.0
    }
}

pub(super) fn basis_points_from_percent(percent: f64) -> u32 {
    let basis_points = (safe_percent(percent) * 100.0).round();
    basis_points.clamp(0.0, QUOTA_BASIS_POINTS_CAP as f64) as u32
}
