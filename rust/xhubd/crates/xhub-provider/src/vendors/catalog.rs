use std::collections::BTreeSet;

use super::super::normalized_token;

pub fn infer_provider_from_model_id(model_id: &str) -> Option<String> {
    let candidates = model_lookup_keys(model_id);
    if candidates.is_empty() {
        return None;
    }

    for lower in &candidates {
        if lower.starts_with("openai/") {
            return Some("openai".to_string());
        }
        if lower.starts_with("codex/") {
            return Some("codex".to_string());
        }
    }

    for (provider, patterns) in provider_model_map() {
        for lower in &candidates {
            for pattern in *patterns {
                if lower.starts_with(pattern) || lower.contains(pattern) {
                    return Some((*provider).to_string());
                }
            }
        }
    }

    for lower in &candidates {
        if lower.starts_with("gpt-")
            || lower.starts_with("o1")
            || lower.starts_with("o3")
            || lower.starts_with("o4")
        {
            return Some("openai".to_string());
        }
        if lower.starts_with("claude") {
            return Some("claude".to_string());
        }
        if lower.starts_with("gemini") {
            return Some("gemini".to_string());
        }
        if lower.starts_with("deepseek") {
            return Some("openai".to_string());
        }
        if lower.starts_with("qwen") {
            return Some("qwen".to_string());
        }
    }

    None
}

pub(crate) fn canonical_pool_provider(raw: &str) -> String {
    let provider = normalize_provider(raw).unwrap_or_else(|| normalized_token(raw));
    match provider.as_str() {
        "chatgpt" | "openai-chatgpt" | "codex" | "openai" => "openai".to_string(),
        "anthropic" | "claude" => "claude".to_string(),
        "google" | "gemini" => "gemini".to_string(),
        _ => provider,
    }
}

pub(crate) fn default_provider_host(provider: &str) -> String {
    match canonical_pool_provider(provider).as_str() {
        "openai" => "api.openai.com".to_string(),
        "claude" => "api.anthropic.com".to_string(),
        "gemini" => "generativelanguage.googleapis.com".to_string(),
        _ => String::new(),
    }
}

pub fn normalized_model_id_for_routing(model_id: &str) -> String {
    canonical_model_alias(&normalized_token(model_id))
}

pub fn normalized_selection_scope_for_compare(selection_scope: &str) -> String {
    let token = normalized_token(selection_scope);
    let Some((provider, scope)) = token.split_once("::") else {
        return token;
    };
    let normalized_scope = normalized_model_id_for_routing(scope);
    if normalized_scope == scope {
        token
    } else {
        format!("{provider}::{normalized_scope}")
    }
}

pub fn model_family_key_for_inventory(model_id: &str) -> String {
    let model_id = normalized_model_id_for_routing(model_id);
    if model_id.is_empty() || model_id == "*" {
        return "all".to_string();
    }
    if model_id.contains("gpt-5.4") {
        return "gpt-5.4".to_string();
    }
    if model_id.starts_with("gpt-5.3-codex")
        || model_id.starts_with("gpt-5-codex")
        || model_id.contains("codex")
    {
        return "gpt-5-codex".to_string();
    }
    if model_id.starts_with("gpt-5") {
        return "gpt-5".to_string();
    }
    if model_id.starts_with("gpt-4") || model_id.starts_with("gpt-4o") {
        return "gpt-4".to_string();
    }
    if model_id.starts_with("o1") || model_id.starts_with("o3") || model_id.starts_with("o4") {
        return "o-series".to_string();
    }
    for family in [
        "claude",
        "gemini",
        "qwen",
        "kiro",
        "copilot",
        "iflow",
        "antigravity",
    ] {
        if model_id.starts_with(family) {
            return family.to_string();
        }
    }
    model_id
}

pub(crate) fn model_lookup_keys(model_id: &str) -> Vec<String> {
    let raw = normalized_token(model_id);
    if raw.is_empty() {
        return Vec::new();
    }
    let mut out = Vec::new();
    let mut seen = BTreeSet::new();
    push_unique(&mut out, &mut seen, &raw);
    push_model_aliases(&mut out, &mut seen, &raw);
    if raw.contains('/') {
        let parts: Vec<String> = raw
            .split('/')
            .map(normalized_token)
            .filter(|value| !value.is_empty())
            .collect();
        for part in &parts {
            push_unique(&mut out, &mut seen, part);
            push_model_aliases(&mut out, &mut seen, part);
        }
        if let Some(last) = parts.last() {
            push_unique(&mut out, &mut seen, last);
            push_model_aliases(&mut out, &mut seen, last);
        }
    }
    if let Some(stripped) = raw.strip_prefix("models/") {
        push_unique(&mut out, &mut seen, stripped);
        push_model_aliases(&mut out, &mut seen, stripped);
    }
    out
}

pub(crate) fn provider_pool_candidates(provider: &str) -> Vec<String> {
    match normalized_token(provider).as_str() {
        "openai" => vec!["openai".to_string(), "codex".to_string()],
        "codex" => vec!["codex".to_string(), "openai".to_string()],
        other if !other.is_empty() => vec![other.to_string()],
        _ => Vec::new(),
    }
}

pub(crate) fn normalize_provider(raw: &str) -> Option<String> {
    let token = normalized_token(raw);
    let provider = match token.as_str() {
        "openai-chatgpt" | "chatgpt" => "codex",
        "github-copilot" => "copilot",
        "openai" | "claude" | "gemini" | "codex" | "kiro" | "copilot" | "antigravity" | "qwen"
        | "iflow" | "custom" => token.as_str(),
        _ => return None,
    };
    Some(provider.to_string())
}

fn push_model_aliases(out: &mut Vec<String>, seen: &mut BTreeSet<String>, raw: &str) {
    let canonical = canonical_model_alias(raw);
    push_unique(out, seen, &canonical);
    if let Some(compact) = compact_openai_gpt_alias(&canonical) {
        push_unique(out, seen, &compact);
    }
}

fn canonical_model_alias(raw: &str) -> String {
    let mut token = normalized_token(raw);
    if let Some(stripped) = token.strip_prefix("models/") {
        token = stripped.to_string();
    }
    if let Some(stripped) = token.strip_prefix("openai/") {
        token = stripped.to_string();
    }

    if let Some(rest) = token.strip_prefix("gpt") {
        if !rest.is_empty() && rest.chars().next().is_some_and(|ch| ch.is_ascii_digit()) {
            return format!("gpt-{rest}");
        }
    }
    token
}

fn compact_openai_gpt_alias(raw: &str) -> Option<String> {
    let token = normalized_token(raw);
    let rest = token.strip_prefix("gpt-")?;
    if !rest.is_empty() && rest.chars().next().is_some_and(|ch| ch.is_ascii_digit()) {
        return Some(format!("gpt{rest}"));
    }
    None
}

fn push_unique(out: &mut Vec<String>, seen: &mut BTreeSet<String>, raw: &str) {
    let token = normalized_token(raw);
    if token.is_empty() || seen.contains(&token) {
        return;
    }
    seen.insert(token.clone());
    out.push(token);
}

fn provider_model_map() -> &'static [(&'static str, &'static [&'static str])] {
    &[
        (
            "openai",
            &[
                "gpt-",
                "gpt-4",
                "gpt-4o",
                "gpt-4-turbo",
                "gpt-3.5-turbo",
                "o1",
                "o1-mini",
                "o3",
                "o3-mini",
                "o4",
                "o4-mini",
                "chatgpt",
                "dall-e",
                "deepseek",
            ],
        ),
        (
            "claude",
            &[
                "claude-3.5-sonnet",
                "claude-3-opus",
                "claude-3-haiku",
                "claude-3.5-haiku",
                "claude-sonnet-4",
                "claude-opus-4",
            ],
        ),
        (
            "gemini",
            &[
                "gemini-1.5-pro",
                "gemini-1.5-flash",
                "gemini-2.0-flash",
                "gemini-2.5-pro",
                "gemini-2.5-flash",
            ],
        ),
        (
            "codex",
            &["codex", "gpt-5.3-codex", "gpt-5-codex", "codex-mini"],
        ),
        ("kiro", &["kiro"]),
        ("copilot", &["copilot", "gpt-4", "gpt-4o", "o1", "o3-mini"]),
        ("antigravity", &["antigravity"]),
        ("qwen", &["qwen-turbo", "qwen-plus", "qwen-max", "qwen-vl"]),
        ("iflow", &["iflow"]),
        ("custom", &[]),
    ]
}
