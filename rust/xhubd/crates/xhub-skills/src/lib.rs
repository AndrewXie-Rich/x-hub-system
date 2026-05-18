use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use serde_json::Value;

pub const SKILL_CATALOG_SCHEMA: &str = "xhub.skills_catalog.v1";
pub const SKILL_READINESS_SCHEMA: &str = "xhub.skills_readiness.v1";
pub const SKILL_PREFLIGHT_SCHEMA: &str = "xhub.skills_preflight.v1";
pub const SKILL_PREFLIGHT_AUDIT_SCHEMA: &str = "xhub.skills_preflight.audit.v1";
pub const SKILL_PREFLIGHT_AUDIT_SUMMARY_SCHEMA: &str = "xhub.skills_preflight_audit_summary.v1";
pub const SKILL_PREFLIGHT_AUDIT_PRUNE_SCHEMA: &str = "xhub.skills_preflight_audit_prune.v1";
pub const SKILL_POLICY_EVENTS_SCHEMA: &str = "xhub.skills_policy_events.v1";
pub const SKILL_POLICY_EVENTS_PRUNE_SCHEMA: &str = "xhub.skills_policy_events_prune.v1";
pub const SKILL_POLICY_STORE_READINESS_SCHEMA: &str = "xhub.skills_policy_store_readiness.v1";
pub const SKILL_PREAUTHORIZATION_SCHEMA: &str = "xhub.skills.preauthorization.v1";
pub const SKILL_PREAUTHORIZED_LEASE_SCHEMA: &str = "xhub.skills.preauthorized_lease.v1";
pub const SKILL_POLICY_SOURCE: &str = "rust_hub_skill_policy_gate_v1";

const MAX_MANIFEST_BYTES: usize = 64 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SkillAuthority {
    HubRegistry,
    TerminalCache,
}

#[derive(Debug, Clone)]
pub struct SkillBoundary {
    pub authority: SkillAuthority,
    pub hub_executes_third_party_code: bool,
    pub requires_pin_or_grant: bool,
}

impl Default for SkillBoundary {
    fn default() -> Self {
        Self {
            authority: SkillAuthority::HubRegistry,
            hub_executes_third_party_code: false,
            requires_pin_or_grant: true,
        }
    }
}

#[derive(Debug, Clone)]
pub struct SkillCatalog {
    pub skills_dir: PathBuf,
    pub skills_dir_exists: bool,
    pub ready: bool,
    pub entries: Vec<SkillCatalogEntry>,
    pub issues: Vec<SkillIssue>,
    pub boundary: SkillBoundary,
}

impl SkillCatalog {
    pub fn skill_count(&self) -> usize {
        self.entries.len()
    }

    pub fn accepted_count(&self) -> usize {
        self.entries
            .iter()
            .filter(|entry| entry.status == SkillStatus::Accepted)
            .count()
    }

    pub fn blocked_count(&self) -> usize {
        self.entries
            .iter()
            .filter(|entry| entry.status == SkillStatus::Blocked)
            .count()
    }
}

#[derive(Debug, Clone)]
pub struct SkillCatalogEntry {
    pub skill_id: String,
    pub display_name: String,
    pub directory_name: String,
    pub manifest_path: String,
    pub manifest_kind: ManifestKind,
    pub status: SkillStatus,
    pub reason_codes: Vec<String>,
    pub capability_tags: Vec<String>,
    pub risk_level: String,
    pub requires_grant: bool,
    pub requires_pin_or_grant: bool,
    pub hub_executes_third_party_code: bool,
    pub execution: SkillExecutionSpec,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillExecutionSpec {
    pub kind: String,
    pub name: String,
    pub runner: String,
    pub entrypoint: String,
    pub args: Vec<String>,
    pub timeout_ms: u64,
}

impl SkillExecutionSpec {
    pub fn none() -> Self {
        Self {
            kind: "none".to_string(),
            name: String::new(),
            runner: String::new(),
            entrypoint: String::new(),
            args: Vec::new(),
            timeout_ms: 0,
        }
    }

    pub fn is_executable(&self) -> bool {
        matches!(self.kind.as_str(), "builtin" | "process")
    }

    pub fn executes_third_party_code(&self) -> bool {
        self.kind == "process"
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ManifestKind {
    SkillJson,
    SkillMd,
}

impl ManifestKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::SkillJson => "skill_json",
            Self::SkillMd => "skill_md",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SkillStatus {
    Accepted,
    Blocked,
}

impl SkillStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Accepted => "accepted",
            Self::Blocked => "blocked",
        }
    }
}

#[derive(Debug, Clone)]
pub struct SkillIssue {
    pub code: String,
    pub path: String,
}

#[derive(Debug, Clone, Default)]
pub struct SkillPreflightRequest {
    pub request_id: String,
    pub audit_ref: String,
    pub scope_key: String,
    pub skill_id: String,
    pub requested_capabilities: Vec<String>,
    pub pinned_skill_ids: Vec<String>,
    pub granted_capabilities: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct SkillPreflightDecision {
    pub schema_version: &'static str,
    pub source: &'static str,
    pub allowed: bool,
    pub decision: String,
    pub reason_codes: Vec<String>,
    pub request_id: String,
    pub audit_ref: String,
    pub scope_key: String,
    pub skill_id: String,
    pub skill_found: bool,
    pub skill_status: String,
    pub requested_capabilities: Vec<String>,
    pub declared_capabilities: Vec<String>,
    pub granted_capabilities: Vec<String>,
    pub missing_capabilities: Vec<String>,
    pub undeclared_capabilities: Vec<String>,
    pub pinned: bool,
    pub risk_level: String,
    pub requires_grant: bool,
    pub preauthorization: SkillPreauthorizationDecision,
    pub requires_pin_or_grant: bool,
    pub execution_authority_in_rust: bool,
    pub hub_executes_third_party_code: bool,
    pub audit_schema_version: &'static str,
}

#[derive(Debug, Clone)]
pub struct SkillPreauthorizationDecision {
    pub schema_version: &'static str,
    pub source: &'static str,
    pub preauthorized: bool,
    pub decision: String,
    pub reason_code: String,
    pub deny_code: String,
    pub grant_ttl_ms: u64,
    pub issued_at_ms: i64,
    pub expires_at_ms: i64,
    pub scope_key: String,
    pub skill_id: String,
    pub risk_level: String,
    pub requires_grant: bool,
    pub execution_surface: &'static str,
    pub hub_authority: bool,
    pub hub_executes_third_party_code: bool,
}

pub fn scan_skill_catalog(skills_dir: &Path) -> SkillCatalog {
    let boundary = SkillBoundary::default();
    let mut catalog = SkillCatalog {
        skills_dir: skills_dir.to_path_buf(),
        skills_dir_exists: skills_dir.is_dir(),
        ready: false,
        entries: Vec::new(),
        issues: Vec::new(),
        boundary,
    };

    if !catalog.skills_dir_exists {
        catalog.issues.push(SkillIssue {
            code: "skills_dir_missing".to_string(),
            path: skills_dir.display().to_string(),
        });
        return catalog;
    }

    let Ok(entries) = fs::read_dir(skills_dir) else {
        catalog.issues.push(SkillIssue {
            code: "skills_dir_unreadable".to_string(),
            path: skills_dir.display().to_string(),
        });
        return catalog;
    };

    let mut skill_dirs = entries
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false))
        .map(|entry| entry.path())
        .collect::<Vec<_>>();
    skill_dirs.sort();

    for skill_dir in skill_dirs {
        if let Some(entry) = scan_skill_dir(&skill_dir) {
            for reason in &entry.reason_codes {
                if is_blocking_reason(reason) {
                    catalog.issues.push(SkillIssue {
                        code: reason.clone(),
                        path: entry.manifest_path.clone(),
                    });
                }
            }
            catalog.entries.push(entry);
        }
    }

    catalog.boundary.hub_executes_third_party_code = catalog
        .entries
        .iter()
        .any(|entry| entry.hub_executes_third_party_code);
    catalog.ready = catalog.issues.is_empty();
    catalog
}

pub fn evaluate_skill_preflight(
    catalog: &SkillCatalog,
    request: SkillPreflightRequest,
) -> SkillPreflightDecision {
    evaluate_skill_preflight_with_authority(catalog, request, false)
}

pub fn evaluate_skill_preflight_with_authority(
    catalog: &SkillCatalog,
    request: SkillPreflightRequest,
    execution_authority_in_rust: bool,
) -> SkillPreflightDecision {
    let boundary = SkillBoundary::default();
    let request_id = sanitize_public_text(&request.request_id).unwrap_or_default();
    let audit_ref = sanitize_public_text(&request.audit_ref).unwrap_or_default();
    let scope_key =
        sanitize_public_token(&request.scope_key).unwrap_or_else(|| "default".to_string());
    let skill_id = sanitize_public_token(&request.skill_id).unwrap_or_default();
    let request_has_secret = request_contains_secret(&request);
    let requested_capabilities = normalize_tokens(request.requested_capabilities);
    let pinned_skill_ids = normalize_tokens(request.pinned_skill_ids);
    let granted_capabilities = normalize_tokens(request.granted_capabilities);

    let mut reason_codes = Vec::new();
    if request_has_secret {
        reason_codes.push("preflight_secret_pattern_denied".to_string());
    }
    if skill_id.is_empty() {
        reason_codes.push("skill_id_missing".to_string());
    }
    if requested_capabilities.is_empty() {
        reason_codes.push("requested_capability_required".to_string());
    }
    if !catalog.ready {
        reason_codes.push("skills_catalog_not_ready".to_string());
    }

    let skill = catalog
        .entries
        .iter()
        .find(|entry| entry.skill_id == skill_id || entry.directory_name == skill_id);
    let skill_found = skill.is_some();
    if !skill_found && !skill_id.is_empty() {
        reason_codes.push("skill_not_found".to_string());
    }

    let declared_capabilities = skill
        .map(|entry| normalize_tokens(entry.capability_tags.clone()))
        .unwrap_or_default();
    let skill_status = skill
        .map(|entry| entry.status.as_str().to_string())
        .unwrap_or_else(|| "missing".to_string());
    if matches!(skill, Some(entry) if entry.status == SkillStatus::Blocked) {
        reason_codes.push("skill_blocked".to_string());
    }
    let hub_executes_third_party_code = skill
        .map(|entry| entry.hub_executes_third_party_code)
        .unwrap_or(false);
    let risk_level = skill
        .map(|entry| entry.risk_level.clone())
        .unwrap_or_else(|| "unknown".to_string());
    let requires_grant = skill.map(|entry| entry.requires_grant).unwrap_or(false);

    let pinned = !skill_id.is_empty() && pinned_skill_ids.iter().any(|item| item == &skill_id);
    if boundary.requires_pin_or_grant && !pinned {
        reason_codes.push("skill_pin_required".to_string());
    }

    let undeclared_capabilities = requested_capabilities
        .iter()
        .filter(|capability| {
            !declared_capabilities
                .iter()
                .any(|declared| declared == *capability)
        })
        .cloned()
        .collect::<Vec<_>>();
    if !undeclared_capabilities.is_empty() {
        reason_codes.push("capability_not_declared".to_string());
    }

    let missing_capabilities = requested_capabilities
        .iter()
        .filter(|capability| {
            !granted_capabilities
                .iter()
                .any(|grant| grant == *capability)
        })
        .cloned()
        .collect::<Vec<_>>();
    if !missing_capabilities.is_empty() {
        reason_codes.push("capability_grant_required".to_string());
    }

    dedupe_strings(&mut reason_codes);
    let allowed = reason_codes.is_empty();
    let preauthorization = build_skill_preauthorization(
        allowed,
        &reason_codes,
        &scope_key,
        &skill_id,
        pinned,
        &risk_level,
        requires_grant,
        hub_executes_third_party_code,
    );

    SkillPreflightDecision {
        schema_version: SKILL_PREFLIGHT_SCHEMA,
        source: SKILL_POLICY_SOURCE,
        allowed,
        decision: if allowed { "allow" } else { "deny" }.to_string(),
        reason_codes,
        request_id,
        audit_ref,
        scope_key,
        skill_id,
        skill_found,
        skill_status,
        requested_capabilities,
        declared_capabilities,
        granted_capabilities,
        missing_capabilities,
        undeclared_capabilities,
        pinned,
        risk_level,
        requires_grant,
        preauthorization,
        requires_pin_or_grant: boundary.requires_pin_or_grant,
        execution_authority_in_rust,
        hub_executes_third_party_code,
        audit_schema_version: SKILL_PREFLIGHT_AUDIT_SCHEMA,
    }
}

fn scan_skill_dir(skill_dir: &Path) -> Option<SkillCatalogEntry> {
    let skill_json = skill_dir.join("skill.json");
    let skill_md = skill_dir.join("SKILL.md");
    if skill_json.is_file() {
        Some(scan_skill_json(skill_dir, &skill_json))
    } else if skill_md.is_file() {
        Some(scan_skill_md(skill_dir, &skill_md))
    } else {
        None
    }
}

fn scan_skill_json(skill_dir: &Path, manifest_path: &Path) -> SkillCatalogEntry {
    let mut reason_codes = Vec::new();
    let raw = match read_limited(manifest_path) {
        Ok(value) => value,
        Err(_) => {
            reason_codes.push("manifest_read_failed".to_string());
            String::new()
        }
    };
    if contains_secret_pattern(&raw) {
        reason_codes.push("manifest_secret_pattern_denied".to_string());
    }

    let parsed = serde_json::from_str::<Value>(&raw);
    let value = match parsed {
        Ok(value) => value,
        Err(_) => {
            reason_codes.push("invalid_skill_json".to_string());
            Value::Null
        }
    };

    let directory_name = directory_name(skill_dir);
    let display_name = value_string(&value, "name")
        .or_else(|| value_string(&value, "display_name"))
        .or_else(|| value_string(&value, "displayName"))
        .unwrap_or_else(|| directory_name.clone());
    let skill_id = value_string(&value, "id")
        .or_else(|| value_string(&value, "skill_id"))
        .or_else(|| value_string(&value, "skillId"))
        .unwrap_or_else(|| directory_name.clone());
    if skill_id.trim().is_empty() {
        reason_codes.push("skill_id_missing".to_string());
    }

    let capability_tags = collect_json_tags(&value);
    let risk_level = normalized_risk_level(
        value_string(&value, "risk_level")
            .or_else(|| value_string(&value, "riskLevel"))
            .or_else(|| value_string(&value, "risk")),
    );
    let grant_floor = value_string(&value, "grant_floor")
        .or_else(|| value_string(&value, "grantFloor"))
        .unwrap_or_default();
    let requires_grant = value_bool(&value, "requires_grant")
        .or_else(|| value_bool(&value, "requiresGrant"))
        .unwrap_or_else(|| grant_floor_requires_grant(&grant_floor));
    let execution = parse_execution_spec(value.get("execution"), &mut reason_codes);
    entry_from_parts(
        skill_id,
        display_name,
        directory_name,
        manifest_path,
        ManifestKind::SkillJson,
        reason_codes,
        capability_tags,
        risk_level,
        requires_grant,
        execution,
    )
}

fn scan_skill_md(skill_dir: &Path, manifest_path: &Path) -> SkillCatalogEntry {
    let mut reason_codes = Vec::new();
    let raw = match read_limited(manifest_path) {
        Ok(value) => value,
        Err(_) => {
            reason_codes.push("manifest_read_failed".to_string());
            String::new()
        }
    };
    if contains_secret_pattern(&raw) {
        reason_codes.push("manifest_secret_pattern_denied".to_string());
    }

    let directory_name = directory_name(skill_dir);
    let display_name = first_markdown_heading(&raw).unwrap_or_else(|| directory_name.clone());
    let capability_tags = infer_markdown_tags(&raw);
    entry_from_parts(
        directory_name.clone(),
        display_name,
        directory_name,
        manifest_path,
        ManifestKind::SkillMd,
        reason_codes,
        capability_tags,
        "medium".to_string(),
        false,
        SkillExecutionSpec::none(),
    )
}

fn entry_from_parts(
    skill_id: String,
    display_name: String,
    directory_name: String,
    manifest_path: &Path,
    manifest_kind: ManifestKind,
    reason_codes: Vec<String>,
    capability_tags: Vec<String>,
    risk_level: String,
    requires_grant: bool,
    execution: SkillExecutionSpec,
) -> SkillCatalogEntry {
    let blocked = reason_codes.iter().any(|code| is_blocking_reason(code));
    let boundary = SkillBoundary::default();
    SkillCatalogEntry {
        skill_id: sanitize_public_token(&skill_id).unwrap_or_else(|| directory_name.clone()),
        display_name: sanitize_public_text(&display_name).unwrap_or_else(|| directory_name.clone()),
        directory_name,
        manifest_path: manifest_path.display().to_string(),
        manifest_kind,
        status: if blocked {
            SkillStatus::Blocked
        } else {
            SkillStatus::Accepted
        },
        reason_codes,
        capability_tags,
        risk_level: normalized_risk_level(Some(risk_level)),
        requires_grant,
        requires_pin_or_grant: boundary.requires_pin_or_grant,
        hub_executes_third_party_code: execution.executes_third_party_code(),
        execution,
    }
}

fn build_skill_preauthorization(
    allowed: bool,
    reason_codes: &[String],
    scope_key: &str,
    skill_id: &str,
    pinned: bool,
    risk_level: &str,
    requires_grant: bool,
    hub_executes_third_party_code: bool,
) -> SkillPreauthorizationDecision {
    let high_risk = is_high_risk(risk_level);
    let hard_deny = reason_codes.iter().find(|code| {
        !matches!(
            code.as_str(),
            "skill_pin_required" | "capability_grant_required"
        )
    });
    let preauthorized = allowed && pinned && !high_risk && !requires_grant;
    let reason_code = if preauthorized {
        String::new()
    } else if let Some(code) = hard_deny {
        code.clone()
    } else if !pinned {
        "skill_not_preauthorized".to_string()
    } else if requires_grant {
        "skill_requires_grant".to_string()
    } else if high_risk {
        "skill_high_risk".to_string()
    } else {
        "capability_grant_required".to_string()
    };
    let decision = if preauthorized {
        "approve"
    } else if hard_deny.is_some() {
        "deny"
    } else {
        "pending"
    };
    let deny_code = if preauthorized {
        String::new()
    } else if hard_deny.is_some() {
        reason_code.clone()
    } else {
        "grant_pending".to_string()
    };
    let grant_ttl_ms = 5 * 60 * 1000;
    let issued_at_ms = if preauthorized { now_ms() } else { 0 };
    let expires_at_ms = if preauthorized {
        issued_at_ms + grant_ttl_ms as i64
    } else {
        0
    };
    SkillPreauthorizationDecision {
        schema_version: SKILL_PREAUTHORIZATION_SCHEMA,
        source: SKILL_POLICY_SOURCE,
        preauthorized,
        decision: decision.to_string(),
        reason_code,
        deny_code,
        grant_ttl_ms,
        issued_at_ms,
        expires_at_ms,
        scope_key: scope_key.to_string(),
        skill_id: skill_id.to_string(),
        risk_level: normalized_risk_level(Some(risk_level.to_string())),
        requires_grant,
        execution_surface: "xt_local",
        hub_authority: true,
        hub_executes_third_party_code,
    }
}

fn is_high_risk(risk_level: &str) -> bool {
    matches!(
        risk_level.trim().to_ascii_lowercase().as_str(),
        "high" | "critical"
    )
}

fn normalized_risk_level(raw: Option<String>) -> String {
    match raw
        .unwrap_or_else(|| "medium".to_string())
        .trim()
        .to_ascii_lowercase()
        .as_str()
    {
        "low" => "low".to_string(),
        "medium" => "medium".to_string(),
        "high" => "high".to_string(),
        "critical" => "critical".to_string(),
        "unknown" => "unknown".to_string(),
        _ => "medium".to_string(),
    }
}

fn is_blocking_reason(code: &str) -> bool {
    matches!(
        code,
        "manifest_read_failed"
            | "manifest_secret_pattern_denied"
            | "invalid_skill_json"
            | "skill_id_missing"
            | "execution_secret_pattern_denied"
            | "execution_kind_unsupported"
            | "execution_entrypoint_missing"
            | "execution_entrypoint_absolute_denied"
            | "execution_entrypoint_parent_traversal_denied"
    )
}

fn parse_execution_spec(
    value: Option<&Value>,
    reason_codes: &mut Vec<String>,
) -> SkillExecutionSpec {
    let Some(value) = value else {
        return SkillExecutionSpec::none();
    };
    let Some(object) = value.as_object() else {
        reason_codes.push("execution_kind_unsupported".to_string());
        return SkillExecutionSpec::none();
    };
    if contains_secret_pattern(&value.to_string()) {
        reason_codes.push("execution_secret_pattern_denied".to_string());
        return SkillExecutionSpec::none();
    }

    let kind = value_string(value, "kind")
        .or_else(|| value_string(value, "type"))
        .unwrap_or_else(|| "builtin".to_string())
        .to_ascii_lowercase();
    match kind.as_str() {
        "builtin" => {
            let name = value_string(value, "name")
                .or_else(|| value_string(value, "builtin"))
                .unwrap_or_else(|| "healthcheck".to_string());
            SkillExecutionSpec {
                kind,
                name: sanitize_public_token(&name).unwrap_or_else(|| "healthcheck".to_string()),
                runner: String::new(),
                entrypoint: String::new(),
                args: Vec::new(),
                timeout_ms: parse_timeout_ms(object.get("timeout_ms")).unwrap_or(1_000),
            }
        }
        "process" => {
            let entrypoint = value_string(value, "entrypoint").unwrap_or_default();
            if entrypoint.is_empty() {
                reason_codes.push("execution_entrypoint_missing".to_string());
            }
            if entrypoint.starts_with('/') {
                reason_codes.push("execution_entrypoint_absolute_denied".to_string());
            }
            if entrypoint.split('/').any(|part| part == "..") {
                reason_codes.push("execution_entrypoint_parent_traversal_denied".to_string());
            }
            SkillExecutionSpec {
                kind,
                name: String::new(),
                runner: value_string(value, "runner")
                    .and_then(|item| sanitize_public_token(&item))
                    .unwrap_or_default(),
                entrypoint: sanitize_public_text(&entrypoint).unwrap_or_default(),
                args: collect_string_array(value.get("args")),
                timeout_ms: parse_timeout_ms(object.get("timeout_ms")).unwrap_or(5_000),
            }
        }
        _ => {
            reason_codes.push("execution_kind_unsupported".to_string());
            SkillExecutionSpec::none()
        }
    }
}

fn parse_timeout_ms(value: Option<&Value>) -> Option<u64> {
    value
        .and_then(Value::as_u64)
        .map(|value| value.clamp(100, 30_000))
}

fn collect_string_array(value: Option<&Value>) -> Vec<String> {
    match value {
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(Value::as_str)
            .filter_map(sanitize_public_text)
            .take(32)
            .collect(),
        _ => Vec::new(),
    }
}

fn read_limited(path: &Path) -> Result<String, std::io::Error> {
    let bytes = fs::read(path)?;
    let capped = if bytes.len() > MAX_MANIFEST_BYTES {
        &bytes[..MAX_MANIFEST_BYTES]
    } else {
        &bytes
    };
    Ok(String::from_utf8_lossy(capped).to_string())
}

fn directory_name(path: &Path) -> String {
    path.file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("unknown-skill")
        .to_string()
}

fn value_string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn value_bool(value: &Value, key: &str) -> Option<bool> {
    match value.get(key)? {
        Value::Bool(value) => Some(*value),
        Value::String(value) => match value.trim().to_ascii_lowercase().as_str() {
            "1" | "true" | "yes" | "on" => Some(true),
            "0" | "false" | "no" | "off" => Some(false),
            _ => None,
        },
        _ => None,
    }
}

fn grant_floor_requires_grant(raw: &str) -> bool {
    let value = raw.trim().to_ascii_lowercase();
    !value.is_empty() && !matches!(value.as_str(), "none" | "no" | "false" | "0")
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .min(i64::MAX as u128) as i64
}

fn collect_json_tags(value: &Value) -> Vec<String> {
    let mut tags = BTreeSet::new();
    for key in [
        "capabilities",
        "capability_tags",
        "capabilityTags",
        "permissions",
        "tools",
    ] {
        collect_tags_from_value(value.get(key), &mut tags);
    }
    tags.into_iter().take(32).collect()
}

fn collect_tags_from_value(value: Option<&Value>, tags: &mut BTreeSet<String>) {
    match value {
        Some(Value::Array(items)) => {
            for item in items {
                if let Some(tag) = item.as_str().and_then(sanitize_public_token) {
                    tags.insert(tag);
                }
            }
        }
        Some(Value::String(raw)) => {
            for item in raw.split(',') {
                if let Some(tag) = sanitize_public_token(item) {
                    tags.insert(tag);
                }
            }
        }
        _ => {}
    }
}

fn infer_markdown_tags(raw: &str) -> Vec<String> {
    let lower = raw.to_ascii_lowercase();
    let mut tags = Vec::new();
    for (needle, tag) in [
        ("memory", "memory"),
        ("model", "model"),
        ("provider", "provider"),
        ("terminal", "terminal"),
        ("file", "filesystem"),
        ("http", "network"),
        ("browser", "browser"),
    ] {
        if lower.contains(needle) {
            tags.push(tag.to_string());
        }
    }
    tags
}

fn first_markdown_heading(raw: &str) -> Option<String> {
    raw.lines()
        .map(str::trim)
        .find_map(|line| line.strip_prefix("# "))
        .and_then(sanitize_public_text)
}

fn sanitize_public_token(raw: &str) -> Option<String> {
    let value = raw.trim();
    if value.is_empty() || contains_secret_pattern(value) {
        return None;
    }
    let normalized = value
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.' | ':' | '/'))
        .collect::<String>();
    if normalized.is_empty() {
        None
    } else {
        Some(normalized.chars().take(96).collect())
    }
}

fn sanitize_public_text(raw: &str) -> Option<String> {
    let value = raw.trim();
    if value.is_empty() || contains_secret_pattern(value) {
        return None;
    }
    let filtered = value
        .chars()
        .filter(|ch| ch.is_ascii() && !ch.is_control())
        .collect::<String>();
    if filtered.is_empty() {
        None
    } else {
        Some(filtered.chars().take(120).collect())
    }
}

fn contains_secret_pattern(raw: &str) -> bool {
    let lower = raw.to_ascii_lowercase();
    [
        "api_key",
        "apikey",
        "access_key",
        "secret_key",
        "refresh_token",
        "client_secret",
        "private_key",
        "authorization: bearer",
        "sk-",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
}

fn normalize_tokens(items: Vec<String>) -> Vec<String> {
    let mut out = items
        .into_iter()
        .filter_map(|item| sanitize_public_token(&item))
        .collect::<Vec<_>>();
    dedupe_strings(&mut out);
    out
}

fn dedupe_strings(items: &mut Vec<String>) {
    let mut seen = BTreeSet::new();
    items.retain(|item| seen.insert(item.clone()));
}

fn request_contains_secret(request: &SkillPreflightRequest) -> bool {
    contains_secret_pattern(&request.request_id)
        || contains_secret_pattern(&request.audit_ref)
        || contains_secret_pattern(&request.scope_key)
        || contains_secret_pattern(&request.skill_id)
        || request
            .requested_capabilities
            .iter()
            .chain(request.pinned_skill_ids.iter())
            .chain(request.granted_capabilities.iter())
            .any(|item| contains_secret_pattern(item))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(label: &str) -> PathBuf {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        std::env::temp_dir().join(format!(
            "xhub_skills_{label}_{}_{}",
            std::process::id(),
            now
        ))
    }

    #[test]
    fn scans_skill_md_without_execution_authority() {
        let dir = temp_dir("md");
        let skill = dir.join("memory-core");
        fs::create_dir_all(&skill).expect("mkdir");
        fs::write(
            skill.join("SKILL.md"),
            "# Memory Core\nUse memory and model context without executing code.\n",
        )
        .expect("write");
        let catalog = scan_skill_catalog(&dir);
        assert!(catalog.ready);
        assert_eq!(catalog.skill_count(), 1);
        assert_eq!(catalog.accepted_count(), 1);
        assert!(!catalog.entries[0].hub_executes_third_party_code);
        assert!(catalog.entries[0].requires_pin_or_grant);
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn blocks_secret_manifest_without_returning_secret_as_public_field() {
        let dir = temp_dir("secret");
        let skill = dir.join("leaky");
        fs::create_dir_all(&skill).expect("mkdir");
        fs::write(
            skill.join("skill.json"),
            r#"{"id":"leaky","name":"Leaky","capabilities":["memory"],"api_key":"sk-secret-value"}"#,
        )
        .expect("write");
        let catalog = scan_skill_catalog(&dir);
        assert!(!catalog.ready);
        assert_eq!(catalog.blocked_count(), 1);
        assert_eq!(catalog.entries[0].status, SkillStatus::Blocked);
        assert!(catalog.entries[0]
            .reason_codes
            .contains(&"manifest_secret_pattern_denied".to_string()));
        assert!(!catalog.entries[0].display_name.contains("sk-secret-value"));
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn preflight_allows_only_pinned_and_granted_capability() {
        let dir = temp_dir("preflight_allow");
        let skill = dir.join("memory-core");
        fs::create_dir_all(&skill).expect("mkdir");
        fs::write(
            skill.join("skill.json"),
            r#"{"id":"memory-core","name":"Memory Core","capabilities":["memory.read"]}"#,
        )
        .expect("write");
        let catalog = scan_skill_catalog(&dir);
        let decision = evaluate_skill_preflight(
            &catalog,
            SkillPreflightRequest {
                skill_id: "memory-core".to_string(),
                requested_capabilities: vec!["memory.read".to_string()],
                pinned_skill_ids: vec!["memory-core".to_string()],
                granted_capabilities: vec!["memory.read".to_string()],
                ..Default::default()
            },
        );
        assert!(decision.allowed);
        assert_eq!(decision.decision, "allow");
        assert!(!decision.execution_authority_in_rust);
        assert_eq!(decision.risk_level, "medium");
        assert!(decision.preauthorization.preauthorized);
        assert_eq!(decision.preauthorization.decision, "approve");
        assert_eq!(decision.preauthorization.execution_surface, "xt_local");
        assert!(decision.preauthorization.hub_authority);
        assert!(decision.preauthorization.expires_at_ms > decision.preauthorization.issued_at_ms);
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn preauthorization_keeps_unpinned_or_high_risk_skills_pending() {
        let dir = temp_dir("preauth_pending");
        let skill = dir.join("publish");
        fs::create_dir_all(&skill).expect("mkdir");
        fs::write(
            skill.join("skill.json"),
            r#"{"id":"publish","name":"Publish","risk_level":"high","requires_grant":true,"capabilities":["deploy.write"]}"#,
        )
        .expect("write");
        let catalog = scan_skill_catalog(&dir);
        let decision = evaluate_skill_preflight(
            &catalog,
            SkillPreflightRequest {
                skill_id: "publish".to_string(),
                requested_capabilities: vec!["deploy.write".to_string()],
                pinned_skill_ids: vec!["publish".to_string()],
                granted_capabilities: vec!["deploy.write".to_string()],
                ..Default::default()
            },
        );
        assert!(decision.allowed);
        assert_eq!(decision.risk_level, "high");
        assert!(decision.requires_grant);
        assert!(!decision.preauthorization.preauthorized);
        assert_eq!(decision.preauthorization.decision, "pending");
        assert_eq!(decision.preauthorization.deny_code, "grant_pending");
        assert_eq!(
            decision.preauthorization.reason_code,
            "skill_requires_grant"
        );

        let unpinned = evaluate_skill_preflight(
            &catalog,
            SkillPreflightRequest {
                skill_id: "publish".to_string(),
                requested_capabilities: vec!["deploy.write".to_string()],
                granted_capabilities: vec!["deploy.write".to_string()],
                ..Default::default()
            },
        );
        assert!(!unpinned.allowed);
        assert_eq!(unpinned.preauthorization.decision, "pending");
        assert_eq!(
            unpinned.preauthorization.reason_code,
            "skill_not_preauthorized"
        );
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn scans_builtin_execution_manifest_without_third_party_code() {
        let dir = temp_dir("exec_builtin");
        let skill = dir.join("health");
        fs::create_dir_all(&skill).expect("mkdir");
        fs::write(
            skill.join("skill.json"),
            r#"{"id":"health","name":"Health","capabilities":["health"],"execution":{"kind":"builtin","name":"healthcheck"}}"#,
        )
        .expect("write");
        let catalog = scan_skill_catalog(&dir);
        assert!(catalog.ready);
        assert_eq!(catalog.entries[0].execution.kind, "builtin");
        assert!(catalog.entries[0].execution.is_executable());
        assert!(!catalog.entries[0].hub_executes_third_party_code);
        let decision = evaluate_skill_preflight_with_authority(
            &catalog,
            SkillPreflightRequest {
                skill_id: "health".to_string(),
                requested_capabilities: vec!["health".to_string()],
                pinned_skill_ids: vec!["health".to_string()],
                granted_capabilities: vec!["health".to_string()],
                ..Default::default()
            },
            true,
        );
        assert!(decision.allowed);
        assert!(decision.execution_authority_in_rust);
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn blocks_unsafe_process_entrypoint() {
        let dir = temp_dir("exec_bad_path");
        let skill = dir.join("bad");
        fs::create_dir_all(&skill).expect("mkdir");
        fs::write(
            skill.join("skill.json"),
            r#"{"id":"bad","capabilities":["filesystem"],"execution":{"kind":"process","entrypoint":"../run.sh"}}"#,
        )
        .expect("write");
        let catalog = scan_skill_catalog(&dir);
        assert!(!catalog.ready);
        assert!(catalog.entries[0]
            .reason_codes
            .contains(&"execution_entrypoint_parent_traversal_denied".to_string()));
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn preflight_denies_without_pin_or_grant() {
        let dir = temp_dir("preflight_deny");
        let skill = dir.join("memory-core");
        fs::create_dir_all(&skill).expect("mkdir");
        fs::write(
            skill.join("skill.json"),
            r#"{"id":"memory-core","name":"Memory Core","capabilities":["memory.read"]}"#,
        )
        .expect("write");
        let catalog = scan_skill_catalog(&dir);
        let decision = evaluate_skill_preflight(
            &catalog,
            SkillPreflightRequest {
                skill_id: "memory-core".to_string(),
                requested_capabilities: vec!["memory.read".to_string()],
                ..Default::default()
            },
        );
        assert!(!decision.allowed);
        assert!(decision
            .reason_codes
            .contains(&"skill_pin_required".to_string()));
        assert!(decision
            .reason_codes
            .contains(&"capability_grant_required".to_string()));
        assert_eq!(decision.preauthorization.decision, "pending");
        assert_eq!(
            decision.preauthorization.reason_code,
            "skill_not_preauthorized"
        );
        let _ = fs::remove_dir_all(dir);
    }
}
