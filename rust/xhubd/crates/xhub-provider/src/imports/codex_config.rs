use std::fs;
use std::path::{Path, PathBuf};

use super::*;

pub(super) fn build_imported_proxy_config_accounts(
    config_path: &Path,
    now_ms: u64,
) -> ImportedAccountBuild {
    let source_ref = normalize_path_ref(config_path);
    let mut errors = Vec::new();
    let mut accounts = Vec::new();
    let extension = config_path
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase();
    if extension != "toml" {
        return ImportedAccountBuild {
            accounts,
            errors: vec!["unsupported_config_format".to_string()],
        };
    }

    let raw_toml = match fs::read_to_string(config_path) {
        Ok(raw) => raw,
        Err(err) => {
            errors.push(format!("toml_read_failed: {err}"));
            return ImportedAccountBuild { accounts, errors };
        }
    };
    if !looks_like_codex_cli_toml(&raw_toml) {
        errors.push("unsupported_toml_config".to_string());
        return ImportedAccountBuild { accounts, errors };
    }

    let provider_overlay = parse_codex_cli_provider_overlay(&raw_toml).unwrap_or_default();
    let explicit_auth_file = parse_toml_string_value(&raw_toml, "auth_file");
    let files = if explicit_auth_file.is_empty() {
        collect_auth_json_files(
            config_path.parent().unwrap_or_else(|| Path::new(".")),
            Some(is_likely_codex_auth_filename),
        )
    } else {
        let auth_path = if Path::new(&explicit_auth_file).is_absolute() {
            PathBuf::from(&explicit_auth_file)
        } else {
            config_path
                .parent()
                .unwrap_or_else(|| Path::new("."))
                .join(&explicit_auth_file)
        };
        if auth_path.exists() {
            collect_auth_json_files(&auth_path, None)
        } else {
            Vec::new()
        }
    };

    let overlay = ImportOverlay {
        import_source_kind: "config_path".to_string(),
        import_source_ref: source_ref,
        ..provider_overlay
    };
    let build = build_imported_auth_accounts(&files, &overlay, now_ms);
    accounts.extend(build.accounts);
    errors.extend(build.errors);
    ImportedAccountBuild { accounts, errors }
}

fn parse_codex_cli_provider_overlay(raw_toml: &str) -> Option<ImportOverlay> {
    let mut preferred_provider = String::new();
    let mut preferred_model = String::new();
    let mut current: Option<CodexProviderTomlRow> = None;
    let mut rows = Vec::new();

    for raw_line in raw_toml.lines() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') && line.ends_with(']') {
            if let Some(row) = current.take().filter(|row| !row.name.is_empty()) {
                rows.push(row);
            }
            let section = line.trim_start_matches('[').trim_end_matches(']').trim();
            if let Some(name) = section.strip_prefix("model_providers.") {
                current = Some(CodexProviderTomlRow {
                    name: name.trim().to_string(),
                    ..CodexProviderTomlRow::default()
                });
            }
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        let value = value.trim();
        if let Some(row) = current.as_mut() {
            match key {
                "base_url" => row.base_url = unquote_toml_value(value),
                "requires_openai_auth" => {
                    row.requires_openai_auth = normalized_token(value) == "true"
                }
                "wire_api" => row.wire_api = normalize_wire_api(&unquote_toml_value(value)),
                _ => {}
            }
        } else if key == "model_provider" {
            preferred_provider = normalized_token(&unquote_toml_value(value));
        } else if key == "model" {
            preferred_model = unquote_toml_value(value);
        }
    }
    if let Some(row) = current.take().filter(|row| !row.name.is_empty()) {
        rows.push(row);
    }

    let explicit_rows: Vec<CodexProviderTomlRow> = rows
        .into_iter()
        .filter(|row| row.requires_openai_auth && !row.base_url.trim().is_empty())
        .collect();
    let selected = if preferred_provider.is_empty() {
        explicit_rows.first().cloned()
    } else {
        explicit_rows
            .iter()
            .find(|row| normalized_token(&row.name) == preferred_provider)
            .cloned()
            .or_else(|| explicit_rows.first().cloned())
    };
    if let Some(row) = selected {
        return Some(ImportOverlay {
            base_url: row.base_url,
            wire_api: normalize_wire_api(&row.wire_api),
            source: "explicit_provider".to_string(),
            ..ImportOverlay::default()
        });
    }

    if preferred_provider.is_empty()
        || preferred_provider == "openai"
        || preferred_provider == "chatgpt"
        || !preferred_model.trim().is_empty()
    {
        return Some(ImportOverlay {
            base_url: "https://api.openai.com/v1".to_string(),
            wire_api: "responses".to_string(),
            source: "fallback_openai".to_string(),
            ..ImportOverlay::default()
        });
    }

    None
}

#[derive(Debug, Clone, Default)]
struct CodexProviderTomlRow {
    name: String,
    base_url: String,
    requires_openai_auth: bool,
    wire_api: String,
}

fn parse_toml_string_value(raw_content: &str, key: &str) -> String {
    for raw_line in raw_content.lines() {
        let line = raw_line.trim();
        if line.starts_with('#') {
            continue;
        }
        let Some((line_key, value)) = line.split_once('=') else {
            continue;
        };
        if line_key.trim() == key {
            return unquote_toml_value(value.trim());
        }
    }
    String::new()
}

fn unquote_toml_value(raw: &str) -> String {
    let value = trim_string(raw);
    if value.len() >= 2 && value.starts_with('"') && value.ends_with('"') {
        value[1..value.len() - 1].to_string()
    } else {
        value
    }
}

fn looks_like_codex_cli_toml(raw_content: &str) -> bool {
    raw_content.lines().any(|line| {
        let trimmed = line.trim();
        trimmed.starts_with("model =")
            || trimmed.starts_with("model_reasoning_effort =")
            || trimmed.starts_with("[projects.")
    })
}

fn is_likely_codex_auth_filename(path: &Path) -> bool {
    let name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase();
    if !name.ends_with(".json") {
        return false;
    }
    let stem = name.trim_end_matches(".json");
    stem == "auth"
        || stem
            .strip_prefix("auth")
            .map(|tail| tail.chars().all(|c| c.is_ascii_digit()))
            .unwrap_or(false)
}
