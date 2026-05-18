use std::collections::BTreeMap;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

use serde_json::{json, Value};
use xhub_core::{json_escape, now_ms, HubConfig};
use xhub_db::{
    apply_baseline_migrations, read_shadow_compare_report_summary, write_shadow_compare_report,
    ShadowCompareReport, ShadowCompareReportSummary,
};
use xhub_provider::{
    apply_openai_quota_usage_to_runtime_base_dir, apply_provider_oauth_refresh_to_runtime_base_dir,
    import_provider_keys_to_runtime_base_dir, normalized_model_id_for_routing,
    normalized_selection_scope_for_compare, plan_codex_oauth_refresh_from_runtime_base_dir,
    plan_openai_quota_refresh_from_runtime_base_dir, provider_key_pools_from_runtime_base_dir,
    provider_runtime_snapshot_from_runtime_base_dir,
    record_openai_quota_refresh_failure_to_runtime_base_dir,
    record_provider_oauth_refresh_failure_to_runtime_base_dir, route_from_runtime_base_dir,
    OpenAIQuotaApplyOptions, OpenAIQuotaRefreshFailureOptions, OpenAIQuotaRefreshPlanOptions,
    ProviderKeyStore, ProviderOAuthRefreshApplyOptions, ProviderOAuthRefreshFailureOptions,
    ProviderOAuthRefreshPlanOptions, ProviderRouteRequest, PROVIDER_KEY_IMPORT_SCHEMA_VERSION,
    PROVIDER_KEY_SNAPSHOT_SCHEMA_VERSION, PROVIDER_OAUTH_REFRESH_PLAN_SCHEMA_VERSION,
    PROVIDER_OAUTH_REFRESH_SCHEMA_VERSION, PROVIDER_QUOTA_REFRESH_APPLY_SCHEMA_VERSION,
    PROVIDER_QUOTA_REFRESH_FAILURE_SCHEMA_VERSION, PROVIDER_QUOTA_REFRESH_PLAN_SCHEMA_VERSION,
    PROVIDER_ROUTE_SCHEMA_VERSION,
};

const SCHEMA_VERSION: &str = "xhub.provider_bridge.v1";
const PROVIDER_ROUTE_COMPONENT: &str = "provider_route";
const CODEX_OAUTH_TOKEN_URL: &str = "https://auth.openai.com/oauth/token";
const CODEX_OAUTH_CLIENT_ID: &str = "app_EMoamEEZ73f0CkXaXp7hrann";
const CODEX_OAUTH_SCOPE: &str = "openid profile email";
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
        "pools" | "key-pools" => pools_json(config, FlagArgs::parse(&args[1..])?),
        "runtime-snapshot" | "snapshot" => {
            runtime_snapshot_json(config, FlagArgs::parse(&args[1..])?)
        }
        "import" | "import-keys" => import_json(config, FlagArgs::parse(&args[1..])?),
        "plan-openai-quota" | "openai-quota-plan" => {
            plan_openai_quota_json(config, FlagArgs::parse(&args[1..])?)
        }
        "apply-openai-quota" | "openai-quota-apply" => {
            apply_openai_quota_json(config, FlagArgs::parse(&args[1..])?)
        }
        "record-openai-quota-failure" | "openai-quota-failure" => {
            record_openai_quota_failure_json(config, FlagArgs::parse(&args[1..])?)
        }
        "apply-oauth-refresh" | "oauth-refresh-apply" => {
            apply_oauth_refresh_json(config, FlagArgs::parse(&args[1..])?)
        }
        "record-oauth-refresh-failure" | "oauth-refresh-failure" => {
            record_oauth_refresh_failure_json(config, FlagArgs::parse(&args[1..])?)
        }
        "plan-codex-oauth-refresh" | "codex-oauth-refresh-plan" => {
            plan_codex_oauth_refresh_json(config, FlagArgs::parse(&args[1..])?)
        }
        "refresh-codex-oauth" | "codex-oauth-refresh" => {
            refresh_codex_oauth_json(config, FlagArgs::parse(&args[1..])?)
        }
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

fn pools_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    pools_json_from_parts(
        config,
        Some(runtime_base_dir),
        flags.optional("provider").unwrap_or_default(),
        flags.optional("model-id").unwrap_or_default(),
        optional_bool_flag(&flags, "include-members", true),
        flags.optional_u128("now-ms")?,
    )
}

pub fn pools_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    provider: String,
    model_id: String,
    include_members: bool,
    request_now_ms: Option<u128>,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    let snapshot = provider_key_pools_from_runtime_base_dir(
        &runtime_base_dir,
        &provider,
        &model_id,
        include_members,
        request_now_ms.unwrap_or_else(now_ms),
    )
    .map_err(|err| format!("provider key pools failed: {err}"))?;
    let snapshot_json = serde_json::to_string(&snapshot)
        .map_err(|err| format!("provider key pools serialize failed: {err}"))?;
    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"pools\",\"snapshot_schema_version\":\"{}\",\"snapshot\":{}}}",
        SCHEMA_VERSION, PROVIDER_KEY_SNAPSHOT_SCHEMA_VERSION, snapshot_json
    ))
}

fn runtime_snapshot_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    runtime_snapshot_json_from_parts(
        config,
        Some(runtime_base_dir),
        flags.optional("provider").unwrap_or_default(),
    )
}

pub fn runtime_snapshot_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    provider: String,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    let snapshot = provider_runtime_snapshot_from_runtime_base_dir(&runtime_base_dir, &provider)
        .map_err(|err| format!("provider runtime snapshot failed: {err}"))?;
    let snapshot_json = serde_json::to_string(&snapshot)
        .map_err(|err| format!("provider runtime snapshot serialize failed: {err}"))?;
    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"runtime-snapshot\",\"snapshot_schema_version\":\"{}\",\"snapshot\":{}}}",
        SCHEMA_VERSION, PROVIDER_KEY_SNAPSHOT_SCHEMA_VERSION, snapshot_json
    ))
}

fn import_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    import_json_from_parts(
        config,
        Some(runtime_base_dir),
        flags.optional("auth-dir").unwrap_or_default(),
        flags.optional("config-path").unwrap_or_default(),
        flags.optional_u64("now-ms")?,
    )
}

pub fn import_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    auth_dir: String,
    config_path: String,
    imported_at_ms: Option<u64>,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    let result = import_provider_keys_to_runtime_base_dir(
        &runtime_base_dir,
        &auth_dir,
        &config_path,
        imported_at_ms.unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64),
    )
    .map_err(|err| format!("provider key import failed: {err}"))?;
    let result_json = serde_json::to_string(&result)
        .map_err(|err| format!("provider key import serialize failed: {err}"))?;
    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":{},\"command\":\"import\",\"import_schema_version\":\"{}\",\"imported\":{},\"errors\":{},\"result\":{}}}",
        SCHEMA_VERSION,
        if result.ok { "true" } else { "false" },
        PROVIDER_KEY_IMPORT_SCHEMA_VERSION,
        result.imported,
        serde_json::to_string(&result.errors)
            .map_err(|err| format!("provider key import errors serialize failed: {err}"))?,
        result_json
    ))
}

fn plan_openai_quota_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    plan_openai_quota_json_from_parts(
        config,
        Some(runtime_base_dir),
        OpenAIQuotaRefreshPlanOptions {
            now_ms: flags
                .optional_u64("now-ms")?
                .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64),
            include_skipped: optional_bool_flag(&flags, "include-skipped", false),
            in_flight_account_keys: flags
                .optional("in-flight-account-keys")
                .map(|raw| {
                    raw.split(',')
                        .map(|item| item.trim().to_string())
                        .filter(|item| !item.is_empty())
                        .collect()
                })
                .unwrap_or_default(),
        },
    )
}

pub fn plan_openai_quota_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    options: OpenAIQuotaRefreshPlanOptions,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    let result = plan_openai_quota_refresh_from_runtime_base_dir(&runtime_base_dir, options)
        .map_err(|err| format!("provider openai quota plan failed: {err}"))?;
    let result_json = serde_json::to_string(&result)
        .map_err(|err| format!("provider openai quota plan serialize failed: {err}"))?;
    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"plan-openai-quota\",\"plan_schema_version\":\"{}\",\"result\":{}}}",
        SCHEMA_VERSION, PROVIDER_QUOTA_REFRESH_PLAN_SCHEMA_VERSION, result_json
    ))
}

fn apply_openai_quota_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    let usage_raw = flags.required("usage-json")?;
    let usage = serde_json::from_str::<Value>(&usage_raw)
        .map_err(|err| format!("invalid usage-json: {err}"))?;
    let refreshed_at_ms = flags
        .optional_u64("refreshed-at-ms")?
        .or(flags.optional_u64("now-ms")?)
        .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64);
    apply_openai_quota_json_from_parts(
        config,
        Some(runtime_base_dir),
        usage,
        OpenAIQuotaApplyOptions {
            account_key: flags.required("account-key")?,
            refreshed_at_ms,
            success_interval_ms: flags
                .optional_u64("success-interval-ms")?
                .unwrap_or(5 * 60_000),
            high_water_interval_ms: flags
                .optional_u64("high-water-interval-ms")?
                .unwrap_or(60_000),
            account_id: flags.optional("account-id").unwrap_or_default(),
            oauth_source_key: flags.optional("oauth-source-key").unwrap_or_default(),
        },
    )
}

pub fn apply_openai_quota_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    usage: Value,
    options: OpenAIQuotaApplyOptions,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    let result = apply_openai_quota_usage_to_runtime_base_dir(&runtime_base_dir, usage, options)
        .map_err(|err| format!("provider openai quota apply failed: {err}"))?;
    let result_json = serde_json::to_string(&result)
        .map_err(|err| format!("provider openai quota apply serialize failed: {err}"))?;
    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"apply-openai-quota\",\"apply_schema_version\":\"{}\",\"result\":{}}}",
        SCHEMA_VERSION, PROVIDER_QUOTA_REFRESH_APPLY_SCHEMA_VERSION, result_json
    ))
}

fn record_openai_quota_failure_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    record_openai_quota_failure_json_from_parts(
        config,
        Some(runtime_base_dir),
        OpenAIQuotaRefreshFailureOptions {
            account_key: flags.required("account-key")?,
            failed_at_ms: flags
                .optional_u64("failed-at-ms")?
                .or(flags.optional_u64("now-ms")?)
                .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64),
            base_failure_backoff_ms: flags
                .optional_u64("base-failure-backoff-ms")?
                .unwrap_or(60_000),
            max_failure_backoff_ms: flags
                .optional_u64("max-failure-backoff-ms")?
                .unwrap_or(15 * 60_000),
            error_code: flags.optional("error-code").unwrap_or_default(),
            error_message: flags.optional("error-message").unwrap_or_default(),
        },
    )
}

pub fn record_openai_quota_failure_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    options: OpenAIQuotaRefreshFailureOptions,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    let result =
        record_openai_quota_refresh_failure_to_runtime_base_dir(&runtime_base_dir, options)
            .map_err(|err| format!("provider openai quota failure failed: {err}"))?;
    let result_json = serde_json::to_string(&result)
        .map_err(|err| format!("provider openai quota failure serialize failed: {err}"))?;
    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"record-openai-quota-failure\",\"failure_schema_version\":\"{}\",\"result\":{}}}",
        SCHEMA_VERSION, PROVIDER_QUOTA_REFRESH_FAILURE_SCHEMA_VERSION, result_json
    ))
}

fn apply_oauth_refresh_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    let refreshed_at_ms = flags
        .optional_u64("refreshed-at-ms")?
        .or(flags.optional_u64("now-ms")?)
        .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64);
    apply_oauth_refresh_json_from_parts(
        config,
        Some(runtime_base_dir),
        ProviderOAuthRefreshApplyOptions {
            account_key: flags.required("account-key")?,
            refreshed_at_ms,
            access_token: flags.required("access-token")?,
            refresh_token: flags.optional("refresh-token").unwrap_or_default(),
            expires_at_ms: flags.optional_u64("expires-at-ms")?.unwrap_or(0),
            account_id: flags.optional("account-id").unwrap_or_default(),
            email: flags.optional("email").unwrap_or_default(),
            oauth_source_key: flags.optional("oauth-source-key").unwrap_or_default(),
        },
    )
}

pub fn apply_oauth_refresh_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    options: ProviderOAuthRefreshApplyOptions,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    let result = apply_provider_oauth_refresh_to_runtime_base_dir(&runtime_base_dir, options)
        .map_err(|err| format!("provider oauth refresh apply failed: {err}"))?;
    let result_json = serde_json::to_string(&result)
        .map_err(|err| format!("provider oauth refresh apply serialize failed: {err}"))?;
    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":{},\"command\":\"apply-oauth-refresh\",\"refresh_schema_version\":\"{}\",\"result\":{}}}",
        SCHEMA_VERSION,
        if result.ok { "true" } else { "false" },
        PROVIDER_OAUTH_REFRESH_SCHEMA_VERSION,
        result_json
    ))
}

fn record_oauth_refresh_failure_json(
    config: &HubConfig,
    flags: FlagArgs,
) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    record_oauth_refresh_failure_json_from_parts(
        config,
        Some(runtime_base_dir),
        ProviderOAuthRefreshFailureOptions {
            account_key: flags.required("account-key")?,
            failed_at_ms: flags
                .optional_u64("failed-at-ms")?
                .or(flags.optional_u64("now-ms")?)
                .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64),
            base_failure_backoff_ms: flags
                .optional_u64("base-failure-backoff-ms")?
                .unwrap_or(60_000),
            max_failure_backoff_ms: flags
                .optional_u64("max-failure-backoff-ms")?
                .unwrap_or(15 * 60_000),
            terminal: optional_bool_flag(&flags, "terminal", false),
            error_code: flags.optional("error-code").unwrap_or_default(),
            error_message: flags.optional("error-message").unwrap_or_default(),
        },
    )
}

pub fn record_oauth_refresh_failure_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    options: ProviderOAuthRefreshFailureOptions,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    let result =
        record_provider_oauth_refresh_failure_to_runtime_base_dir(&runtime_base_dir, options)
            .map_err(|err| format!("provider oauth refresh failure failed: {err}"))?;
    let result_json = serde_json::to_string(&result)
        .map_err(|err| format!("provider oauth refresh failure serialize failed: {err}"))?;
    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"record-oauth-refresh-failure\",\"refresh_schema_version\":\"{}\",\"result\":{}}}",
        SCHEMA_VERSION, PROVIDER_OAUTH_REFRESH_SCHEMA_VERSION, result_json
    ))
}

fn plan_codex_oauth_refresh_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    plan_codex_oauth_refresh_json_from_parts(
        config,
        Some(runtime_base_dir),
        ProviderOAuthRefreshPlanOptions {
            now_ms: flags
                .optional_u64("now-ms")?
                .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64),
            include_skipped: optional_bool_flag(&flags, "include-skipped", false),
            in_flight_account_keys: flags
                .optional("in-flight-account-keys")
                .map(|raw| {
                    raw.split(',')
                        .map(|item| item.trim().to_string())
                        .filter(|item| !item.is_empty())
                        .collect()
                })
                .unwrap_or_default(),
            refresh_lead_ms: flags.optional_u64("refresh-lead-ms")?.unwrap_or(0),
            min_refresh_lead_ms: flags.optional_u64("min-refresh-lead-ms")?.unwrap_or(0),
        },
    )
}

pub fn plan_codex_oauth_refresh_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    options: ProviderOAuthRefreshPlanOptions,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    let result = plan_codex_oauth_refresh_from_runtime_base_dir(&runtime_base_dir, options)
        .map_err(|err| format!("provider codex oauth refresh plan failed: {err}"))?;
    let result_json = serde_json::to_string(&result)
        .map_err(|err| format!("provider codex oauth refresh plan serialize failed: {err}"))?;
    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"plan-codex-oauth-refresh\",\"plan_schema_version\":\"{}\",\"result\":{}}}",
        SCHEMA_VERSION, PROVIDER_OAUTH_REFRESH_PLAN_SCHEMA_VERSION, result_json
    ))
}

#[derive(Debug, Clone, Default)]
pub struct CodexOAuthRefreshOptions {
    pub account_key: String,
    pub refreshed_at_ms: u64,
    pub timeout_ms: u64,
    pub base_failure_backoff_ms: u64,
    pub max_failure_backoff_ms: u64,
    pub token_url: String,
    pub force: bool,
}

#[derive(Debug, Clone)]
struct CodexOAuthRefreshAccount {
    account_key: String,
    provider: String,
    email: String,
    account_id: String,
    refresh_token: String,
    auth_type: String,
    oauth_source_key: String,
    enabled: bool,
}

#[derive(Debug, Clone, Default)]
struct CodexTokenResponse {
    access_token: String,
    refresh_token: String,
    id_token: String,
    expires_in: u64,
}

#[derive(Debug, Clone)]
struct TokenEndpointResponse {
    http_status: u16,
    body: String,
}

fn refresh_codex_oauth_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    refresh_codex_oauth_json_from_parts(
        config,
        Some(runtime_base_dir),
        CodexOAuthRefreshOptions {
            account_key: flags.required("account-key")?,
            refreshed_at_ms: flags
                .optional_u64("refreshed-at-ms")?
                .or(flags.optional_u64("now-ms")?)
                .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64),
            timeout_ms: flags.optional_u64("timeout-ms")?.unwrap_or(15_000),
            base_failure_backoff_ms: flags
                .optional_u64("base-failure-backoff-ms")?
                .unwrap_or(60_000),
            max_failure_backoff_ms: flags
                .optional_u64("max-failure-backoff-ms")?
                .unwrap_or(15 * 60_000),
            token_url: flags
                .optional("token-url")
                .filter(|value| !value.trim().is_empty())
                .unwrap_or_else(|| CODEX_OAUTH_TOKEN_URL.to_string()),
            force: optional_bool_flag(&flags, "force", false),
        },
    )
}

pub fn refresh_codex_oauth_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    options: CodexOAuthRefreshOptions,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    let account_key = options.account_key.trim().to_string();
    if account_key.is_empty() {
        return Err("provider codex oauth refresh requires account_key".to_string());
    }
    let refreshed_at_ms = if options.refreshed_at_ms == 0 {
        now_ms().min(u64::MAX as u128) as u64
    } else {
        options.refreshed_at_ms
    };
    let account = load_codex_oauth_refresh_account(&runtime_base_dir, &account_key)?;
    if !account.enabled && !options.force {
        return record_codex_oauth_refresh_failure_body(
            &runtime_base_dir,
            ProviderOAuthRefreshFailureOptions {
                account_key,
                failed_at_ms: refreshed_at_ms,
                base_failure_backoff_ms: options.base_failure_backoff_ms,
                max_failure_backoff_ms: options.max_failure_backoff_ms,
                terminal: true,
                error_code: "disabled".to_string(),
                error_message: "disabled".to_string(),
            },
            "disabled",
            0,
        );
    }
    if !supported_codex_oauth_refresh_account(&account) {
        return record_codex_oauth_refresh_failure_body(
            &runtime_base_dir,
            ProviderOAuthRefreshFailureOptions {
                account_key,
                failed_at_ms: refreshed_at_ms,
                base_failure_backoff_ms: options.base_failure_backoff_ms,
                max_failure_backoff_ms: options.max_failure_backoff_ms,
                terminal: true,
                error_code: "unsupported_refresh_schema".to_string(),
                error_message: "unsupported_refresh_schema".to_string(),
            },
            "unsupported_refresh_schema",
            0,
        );
    }
    if account.refresh_token.trim().is_empty() {
        return record_codex_oauth_refresh_failure_body(
            &runtime_base_dir,
            ProviderOAuthRefreshFailureOptions {
                account_key,
                failed_at_ms: refreshed_at_ms,
                base_failure_backoff_ms: options.base_failure_backoff_ms,
                max_failure_backoff_ms: options.max_failure_backoff_ms,
                terminal: true,
                error_code: "missing_refresh_token".to_string(),
                error_message: "missing_refresh_token".to_string(),
            },
            "missing_refresh_token",
            0,
        );
    }

    let endpoint = match call_codex_oauth_token_endpoint(
        &options
            .token_url
            .trim()
            .if_empty(CODEX_OAUTH_TOKEN_URL)
            .to_string(),
        &account.refresh_token,
        options.timeout_ms,
    ) {
        Ok(response) => response,
        Err(err) => {
            let error_code = if err.to_ascii_lowercase().contains("timed out")
                || err.to_ascii_lowercase().contains("timeout")
            {
                "refresh_timeout"
            } else {
                "refresh_request_failed"
            };
            return record_codex_oauth_refresh_failure_body(
                &runtime_base_dir,
                ProviderOAuthRefreshFailureOptions {
                    account_key,
                    failed_at_ms: refreshed_at_ms,
                    base_failure_backoff_ms: options.base_failure_backoff_ms,
                    max_failure_backoff_ms: options.max_failure_backoff_ms,
                    terminal: false,
                    error_code: error_code.to_string(),
                    error_message: sanitize_provider_message(&err, error_code),
                },
                error_code,
                0,
            );
        }
    };

    if endpoint.http_status != 200 {
        let (error_code, error_message) =
            oauth_error_from_response(endpoint.http_status, &endpoint.body);
        return record_codex_oauth_refresh_failure_body(
            &runtime_base_dir,
            ProviderOAuthRefreshFailureOptions {
                account_key,
                failed_at_ms: refreshed_at_ms,
                base_failure_backoff_ms: options.base_failure_backoff_ms,
                max_failure_backoff_ms: options.max_failure_backoff_ms,
                terminal: matches!(endpoint.http_status, 401 | 403),
                error_code: error_code.clone(),
                error_message,
            },
            &error_code,
            endpoint.http_status,
        );
    }

    let token_response = parse_codex_token_response(&endpoint.body).map_err(|err| {
        format!(
            "provider codex oauth refresh response parse failed: {}",
            sanitize_provider_message(&err, "refresh_failed")
        )
    })?;
    if token_response.access_token.trim().is_empty() {
        return record_codex_oauth_refresh_failure_body(
            &runtime_base_dir,
            ProviderOAuthRefreshFailureOptions {
                account_key,
                failed_at_ms: refreshed_at_ms,
                base_failure_backoff_ms: options.base_failure_backoff_ms,
                max_failure_backoff_ms: options.max_failure_backoff_ms,
                terminal: false,
                error_code: "refresh_failed".to_string(),
                error_message: "missing_access_token".to_string(),
            },
            "refresh_failed",
            endpoint.http_status,
        );
    }
    let expires_at_ms = codex_token_expires_at_ms(&token_response, refreshed_at_ms);
    if expires_at_ms <= refreshed_at_ms {
        return record_codex_oauth_refresh_failure_body(
            &runtime_base_dir,
            ProviderOAuthRefreshFailureOptions {
                account_key,
                failed_at_ms: refreshed_at_ms,
                base_failure_backoff_ms: options.base_failure_backoff_ms,
                max_failure_backoff_ms: options.max_failure_backoff_ms,
                terminal: false,
                error_code: "refresh_failed".to_string(),
                error_message: "missing_token_expiry".to_string(),
            },
            "refresh_failed",
            endpoint.http_status,
        );
    }

    let account_id = jwt_claim_string(
        &token_response.id_token,
        &[
            "chatgpt_account_id",
            "account_id",
            "https://api.openai.com/auth.chatgpt_account_id",
        ],
    )
    .if_empty(&account.account_id);
    let email = jwt_claim_string(&token_response.id_token, &["email"]).if_empty(&account.email);
    let result = apply_provider_oauth_refresh_to_runtime_base_dir(
        &runtime_base_dir,
        ProviderOAuthRefreshApplyOptions {
            account_key: account.account_key,
            refreshed_at_ms,
            access_token: token_response.access_token,
            refresh_token: token_response.refresh_token,
            expires_at_ms,
            account_id,
            email,
            oauth_source_key: account.oauth_source_key.if_empty("chatgpt"),
        },
    )
    .map_err(|err| format!("provider codex oauth refresh apply failed: {err}"))?;
    let result_json = serde_json::to_string(&result)
        .map_err(|err| format!("provider codex oauth refresh result serialize failed: {err}"))?;
    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":{},\"command\":\"refresh-codex-oauth\",\"refresh_schema_version\":\"{}\",\"provider\":\"{}\",\"http_status\":{},\"refreshed\":{},\"result\":{}}}",
        SCHEMA_VERSION,
        if result.ok { "true" } else { "false" },
        PROVIDER_OAUTH_REFRESH_SCHEMA_VERSION,
        json_escape(&account.provider),
        endpoint.http_status,
        if result.ok { "true" } else { "false" },
        result_json
    ))
}

fn record_codex_oauth_refresh_failure_body(
    runtime_base_dir: &std::path::Path,
    options: ProviderOAuthRefreshFailureOptions,
    reason_code: &str,
    http_status: u16,
) -> Result<String, String> {
    let result =
        record_provider_oauth_refresh_failure_to_runtime_base_dir(runtime_base_dir, options)
            .map_err(|err| format!("provider codex oauth refresh failure record failed: {err}"))?;
    let result_json = serde_json::to_string(&result)
        .map_err(|err| format!("provider codex oauth refresh failure serialize failed: {err}"))?;
    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":false,\"command\":\"refresh-codex-oauth\",\"refresh_schema_version\":\"{}\",\"reason_code\":\"{}\",\"http_status\":{},\"refreshed\":false,\"result\":{}}}",
        SCHEMA_VERSION,
        PROVIDER_OAUTH_REFRESH_SCHEMA_VERSION,
        json_escape(reason_code),
        http_status,
        result_json
    ))
}

fn load_codex_oauth_refresh_account(
    runtime_base_dir: &std::path::Path,
    account_key: &str,
) -> Result<CodexOAuthRefreshAccount, String> {
    let store = ProviderKeyStore::load_runtime_base_dir(runtime_base_dir)
        .map_err(|err| format!("provider codex oauth refresh store load failed: {err}"))?;
    for provider_data in store.providers.values() {
        for account in &provider_data.accounts {
            if account.account_key.trim() != account_key {
                continue;
            }
            return Ok(CodexOAuthRefreshAccount {
                account_key: account.account_key.trim().to_string(),
                provider: account.provider.trim().to_string(),
                email: account.email.trim().to_string(),
                account_id: account.account_id.trim().to_string(),
                refresh_token: account.refresh_token.trim().to_string(),
                auth_type: account.auth_type.trim().to_string(),
                oauth_source_key: account.oauth_source_key.trim().to_string(),
                enabled: account.enabled,
            });
        }
    }
    Err(format!(
        "provider codex oauth refresh account not found: {}",
        account_key
    ))
}

fn supported_codex_oauth_refresh_account(account: &CodexOAuthRefreshAccount) -> bool {
    if account.auth_type.trim().to_ascii_lowercase() != "oauth" {
        return false;
    }
    let provider = account.provider.trim().to_ascii_lowercase();
    let source = account.oauth_source_key.trim().to_ascii_lowercase();
    matches!(provider.as_str(), "openai" | "codex")
        || matches!(
            source.as_str(),
            "chatgpt" | "openai" | "openai-chatgpt" | "codex"
        )
}

fn call_codex_oauth_token_endpoint(
    token_url: &str,
    refresh_token: &str,
    timeout_ms: u64,
) -> Result<TokenEndpointResponse, String> {
    let timeout_seconds = ((timeout_ms.max(1_000) + 999) / 1000).to_string();
    let form_body = form_urlencoded(&[
        ("client_id", CODEX_OAUTH_CLIENT_ID),
        ("grant_type", "refresh_token"),
        ("refresh_token", refresh_token),
        ("scope", CODEX_OAUTH_SCOPE),
    ]);
    let mut child = Command::new(curl_binary())
        .arg("-sS")
        .arg("-X")
        .arg("POST")
        .arg("--max-time")
        .arg(timeout_seconds)
        .arg("-H")
        .arg("content-type: application/x-www-form-urlencoded")
        .arg("-H")
        .arg("accept: application/json")
        .arg("--data-binary")
        .arg("@-")
        .arg("-w")
        .arg("\n__XHUB_HTTP_STATUS__:%{http_code}")
        .arg(token_url)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|err| format!("curl spawn failed: {err}"))?;
    if let Some(stdin) = child.stdin.as_mut() {
        stdin
            .write_all(form_body.as_bytes())
            .map_err(|err| format!("curl stdin write failed: {err}"))?;
    }
    let output = child
        .wait_with_output()
        .map_err(|err| format!("curl wait failed: {err}"))?;
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = sanitize_provider_message(
        &String::from_utf8_lossy(&output.stderr),
        "refresh_request_failed",
    );
    if !output.status.success() {
        return Err(if stderr.is_empty() {
            "refresh_request_failed".to_string()
        } else {
            stderr
        });
    }
    let marker = "\n__XHUB_HTTP_STATUS__:";
    let Some((body, status_raw)) = stdout.rsplit_once(marker) else {
        return Err("missing_http_status".to_string());
    };
    let http_status = status_raw
        .trim()
        .parse::<u16>()
        .map_err(|_| "invalid_http_status".to_string())?;
    Ok(TokenEndpointResponse {
        http_status,
        body: body.to_string(),
    })
}

fn curl_binary() -> &'static str {
    if std::path::Path::new("/usr/bin/curl").is_file() {
        "/usr/bin/curl"
    } else {
        "curl"
    }
}

fn parse_codex_token_response(body: &str) -> Result<CodexTokenResponse, String> {
    let value: Value = serde_json::from_str(body).map_err(|err| format!("invalid json: {err}"))?;
    Ok(CodexTokenResponse {
        access_token: value_string(&value, "access_token"),
        refresh_token: value_string(&value, "refresh_token"),
        id_token: value_string(&value, "id_token"),
        expires_in: value_u64(&value, "expires_in").unwrap_or(0),
    })
}

fn codex_token_expires_at_ms(response: &CodexTokenResponse, refreshed_at_ms: u64) -> u64 {
    if response.expires_in > 0 {
        return refreshed_at_ms.saturating_add(response.expires_in.saturating_mul(1000));
    }
    jwt_claim_u64(&response.id_token, &["exp"])
        .unwrap_or(0)
        .saturating_mul(1000)
}

fn oauth_error_from_response(status: u16, body: &str) -> (String, String) {
    let value = serde_json::from_str::<Value>(body).unwrap_or(Value::Null);
    let raw_error = value_string(&value, "error");
    let raw_description = value_string(&value, "error_description")
        .if_empty(&value_string(&value, "message"))
        .if_empty(&raw_error);
    let combined = format!("{} {}", raw_error, raw_description).to_ascii_lowercase();
    let code = if combined.contains("refresh_token_reused") {
        "refresh_token_reused".to_string()
    } else if combined.contains("invalid_grant") {
        "invalid_grant".to_string()
    } else if !raw_error.trim().is_empty() {
        raw_error.trim().to_ascii_lowercase()
    } else if matches!(status, 401 | 403) {
        format!("refresh_http_{status}")
    } else if matches!(status, 408 | 504) {
        "refresh_timeout".to_string()
    } else {
        format!("refresh_http_{status}")
    };
    (
        code.clone(),
        sanitize_provider_message(&raw_description, &code),
    )
}

fn sanitize_provider_message(raw: &str, fallback: &str) -> String {
    let fallback = fallback.trim().if_empty("refresh_failed");
    let message = raw
        .split_whitespace()
        .collect::<Vec<&str>>()
        .join(" ")
        .trim()
        .to_string();
    if message.is_empty() {
        return fallback;
    }
    let lower = message.to_ascii_lowercase();
    if lower.contains("access_token")
        || lower.contains("refresh_token")
        || lower.contains("id_token")
        || lower.contains("authorization")
        || lower.contains("bearer ")
        || lower.contains("sk-")
    {
        return fallback;
    }
    if message.len() > 240 {
        let mut truncated = message.chars().take(240).collect::<String>();
        truncated.push_str("...");
        truncated
    } else {
        message
    }
}

fn form_urlencoded(pairs: &[(&str, &str)]) -> String {
    pairs
        .iter()
        .map(|(key, value)| {
            format!(
                "{}={}",
                url_encode_form_component(key),
                url_encode_form_component(value)
            )
        })
        .collect::<Vec<String>>()
        .join("&")
}

fn url_encode_form_component(raw: &str) -> String {
    let mut out = String::new();
    for byte in raw.as_bytes() {
        match *byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                out.push(*byte as char)
            }
            b' ' => out.push('+'),
            other => out.push_str(&format!("%{other:02X}")),
        }
    }
    out
}

fn jwt_claim_string(token: &str, keys: &[&str]) -> String {
    let Some(payload) = jwt_payload_value(token) else {
        return String::new();
    };
    for key in keys {
        if let Some(value) = payload.get(*key).and_then(Value::as_str) {
            let trimmed = value.trim();
            if !trimmed.is_empty() {
                return trimmed.to_string();
            }
        }
        if let Some((object_key, nested_key)) = key.split_once('.') {
            if let Some(value) = payload
                .get(object_key)
                .and_then(Value::as_object)
                .and_then(|object| object.get(nested_key))
                .and_then(Value::as_str)
            {
                let trimmed = value.trim();
                if !trimmed.is_empty() {
                    return trimmed.to_string();
                }
            }
        }
    }
    String::new()
}

fn jwt_claim_u64(token: &str, keys: &[&str]) -> Option<u64> {
    let payload = jwt_payload_value(token)?;
    for key in keys {
        if let Some(value) = payload.get(*key).and_then(|value| {
            value
                .as_u64()
                .or_else(|| value.as_str()?.trim().parse::<u64>().ok())
        }) {
            return Some(value);
        }
    }
    None
}

fn jwt_payload_value(token: &str) -> Option<Value> {
    let mut segments = token.trim().split('.');
    let _header = segments.next()?;
    let payload = segments.next()?;
    if payload.trim().is_empty() {
        return None;
    }
    let decoded = decode_base64_url(payload)?;
    serde_json::from_slice::<Value>(&decoded).ok()
}

fn decode_base64_url(input: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(input.len().saturating_mul(3) / 4);
    let mut buffer = 0_u32;
    let mut bits = 0_u8;
    for byte in input.bytes() {
        let value = match byte {
            b'A'..=b'Z' => u32::from(byte - b'A'),
            b'a'..=b'z' => u32::from(byte - b'a') + 26,
            b'0'..=b'9' => u32::from(byte - b'0') + 52,
            b'+' | b'-' => 62,
            b'/' | b'_' => 63,
            b'=' => break,
            b'\r' | b'\n' | b'\t' | b' ' => continue,
            _ => return None,
        };
        buffer = (buffer << 6) | value;
        bits = bits.saturating_add(6);
        if bits >= 8 {
            bits -= 8;
            out.push(((buffer >> bits) & 0xff) as u8);
            if bits > 0 {
                buffer &= (1 << bits) - 1;
            } else {
                buffer = 0;
            }
        }
    }
    Some(out)
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

fn optional_bool_flag(flags: &FlagArgs, key: &str, fallback: bool) -> bool {
    let Some(value) = flags.optional(key) else {
        return fallback;
    };
    match value.trim().to_lowercase().as_str() {
        "1" | "true" | "yes" | "y" | "on" => true,
        "0" | "false" | "no" | "n" | "off" => false,
        _ => fallback,
    }
}

fn help_json() -> String {
    format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"commands\":[\"route\",\"pools\",\"runtime-snapshot\",\"import\",\"plan-openai-quota\",\"apply-openai-quota\",\"record-openai-quota-failure\",\"apply-oauth-refresh\",\"record-oauth-refresh-failure\",\"plan-codex-oauth-refresh\",\"refresh-codex-oauth\",\"compare\",\"reports\",\"readiness\"],\"route_flags\":[\"--model-id\",\"--provider\",\"--runtime-base-dir\",\"--request-json\",\"--now-ms\"],\"pools_flags\":[\"--provider\",\"--model-id\",\"--include-members\",\"--runtime-base-dir\",\"--now-ms\"],\"runtime_snapshot_flags\":[\"--provider\",\"--runtime-base-dir\"],\"import_flags\":[\"--auth-dir\",\"--config-path\",\"--runtime-base-dir\",\"--now-ms\"],\"plan_openai_quota_flags\":[\"--runtime-base-dir\",\"--now-ms\",\"--include-skipped\",\"--in-flight-account-keys\"],\"apply_openai_quota_flags\":[\"--account-key\",\"--usage-json\",\"--runtime-base-dir\",\"--refreshed-at-ms\",\"--success-interval-ms\",\"--high-water-interval-ms\",\"--account-id\",\"--oauth-source-key\"],\"record_openai_quota_failure_flags\":[\"--account-key\",\"--runtime-base-dir\",\"--failed-at-ms\",\"--base-failure-backoff-ms\",\"--max-failure-backoff-ms\",\"--error-code\",\"--error-message\"],\"apply_oauth_refresh_flags\":[\"--account-key\",\"--access-token\",\"--refresh-token\",\"--runtime-base-dir\",\"--refreshed-at-ms\",\"--expires-at-ms\",\"--account-id\",\"--email\",\"--oauth-source-key\"],\"record_oauth_refresh_failure_flags\":[\"--account-key\",\"--runtime-base-dir\",\"--failed-at-ms\",\"--base-failure-backoff-ms\",\"--max-failure-backoff-ms\",\"--terminal\",\"--error-code\",\"--error-message\"],\"plan_codex_oauth_refresh_flags\":[\"--runtime-base-dir\",\"--now-ms\",\"--include-skipped\",\"--in-flight-account-keys\",\"--refresh-lead-ms\",\"--min-refresh-lead-ms\"],\"refresh_codex_oauth_flags\":[\"--account-key\",\"--runtime-base-dir\",\"--refreshed-at-ms\",\"--timeout-ms\",\"--base-failure-backoff-ms\",\"--max-failure-backoff-ms\",\"--token-url\",\"--force\"],\"compare_flags\":[\"--node-decision-json\",\"--model-id\",\"--provider\",\"--runtime-base-dir\",\"--now-ms\"],\"reports_flags\":[\"--limit\"],\"readiness_flags\":[\"--min-compare-reports\",\"--max-mismatches\",\"--limit\"]}}",
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

impl IfEmpty for &str {
    fn if_empty(self, fallback: &str) -> String {
        if self.is_empty() {
            fallback.to_string()
        } else {
            self.to_string()
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
            let Some(value) = args.get(i + 1) else {
                if flag_accepts_implicit_true(&key) {
                    values.insert(key, "true".to_string());
                    i += 1;
                    continue;
                }
                return Err(format!("missing value for --{key}"));
            };
            if value.starts_with("--") {
                if flag_accepts_implicit_true(&key) {
                    values.insert(key, "true".to_string());
                    i += 1;
                    continue;
                }
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

    fn optional_u64(&self, key: &str) -> Result<Option<u64>, String> {
        let Some(value) = self.optional(key) else {
            return Ok(None);
        };
        value
            .parse::<u64>()
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

fn flag_accepts_implicit_true(key: &str) -> bool {
    matches!(
        key,
        "include-members" | "include-skipped" | "terminal" | "force"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flag_args_accept_bare_boolean_flags() {
        let flags = FlagArgs::parse(&[
            "--include-skipped".to_string(),
            "--runtime-base-dir".to_string(),
            "/tmp/runtime".to_string(),
        ])
        .expect("bare boolean flag should parse");
        assert_eq!(flags.optional("include-skipped").as_deref(), Some("true"));
        assert_eq!(
            flags.optional("runtime-base-dir").as_deref(),
            Some("/tmp/runtime")
        );

        let err = FlagArgs::parse(&["--account-key".to_string()])
            .expect_err("value flags should still require a value");
        assert_eq!(err, "missing value for --account-key");
    }

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

    #[test]
    fn import_json_returns_xt_compatible_top_level_result() {
        let dir = unique_temp_dir("xhubd-provider-import-runtime");
        let auth_dir = unique_temp_dir("xhubd-provider-import-auth");
        std::fs::create_dir_all(&dir).expect("runtime dir should be created");
        std::fs::create_dir_all(&auth_dir).expect("auth dir should be created");
        std::fs::write(
            auth_dir.join("auth17.json"),
            r#"{
              "auth_mode": "chatgpt",
              "tokens": {
                "id_token": "h.eyJlbWFpbCI6ImNvZGV4LXVzZXJAdGVzdC5jb20iLCJjaGF0Z3B0X2FjY291bnRfaWQiOiJhY2N0LWNvZGV4LWNsaS0xIiwiZXhwIjoyMDAwMDAwMDAwfQ.s",
                "access_token": "codex-cli-access-token",
                "refresh_token": "codex-cli-refresh-token",
                "account_id": "acct-codex-cli-1"
              }
            }"#,
        )
        .expect("auth file should be written");
        let config = test_config(&dir);

        let out = import_json_from_parts(
            &config,
            Some(dir.clone()),
            auth_dir.to_string_lossy().to_string(),
            String::new(),
            Some(1_000_000),
        )
        .expect("provider import wrapper should succeed");

        let value: Value = serde_json::from_str(&out).expect("output should parse");
        assert_eq!(value["ok"], true);
        assert_eq!(value["command"], "import");
        assert_eq!(value["imported"], 1);
        assert_eq!(value["errors"].as_array().unwrap().len(), 0);
        assert_eq!(value["result"]["imported"], 1);

        let store = xhub_provider::ProviderKeyStore::load_runtime_base_dir(&dir)
            .expect("provider store should load");
        assert_eq!(store.providers["codex"].accounts.len(), 1);
        let _ = std::fs::remove_dir_all(&dir);
        let _ = std::fs::remove_dir_all(&auth_dir);
    }

    #[test]
    fn apply_openai_quota_json_writes_rust_quota_projection() {
        let dir = unique_temp_dir("xhubd-provider-quota-apply");
        std::fs::create_dir_all(&dir).expect("temp dir should be created");
        std::fs::write(
            dir.join(xhub_provider::PROVIDER_STORE_FILE_NAME),
            r#"{
              "providers": {
                "openai": {
                  "accounts": [
                    {
                      "account_key": "acct-1",
                      "provider": "openai",
                      "api_key": "sk-test",
                      "models": ["gpt-5.4"]
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("provider store should be written");
        let config = test_config(&dir);

        let out = apply_openai_quota_json_from_parts(
            &config,
            Some(dir.clone()),
            json!({
                "plan_type": "plus",
                "rate_limit": {
                    "limit_reached": false,
                    "primary_window": {
                        "used_percent": 37.5,
                        "limit_window_seconds": 5 * 60 * 60,
                        "reset_at": 0
                    }
                }
            }),
            OpenAIQuotaApplyOptions {
                account_key: "acct-1".to_string(),
                refreshed_at_ms: 1_000_000,
                success_interval_ms: 300_000,
                high_water_interval_ms: 60_000,
                account_id: "acct-id".to_string(),
                oauth_source_key: "chatgpt".to_string(),
            },
        )
        .expect("quota apply wrapper should succeed");

        let value: Value = serde_json::from_str(&out).expect("output should parse");
        assert_eq!(value["ok"], true);
        assert_eq!(value["command"], "apply-openai-quota");
        assert_eq!(value["result"]["next_refresh_at_ms"], 1_300_000);

        let store: Value = serde_json::from_str(
            &std::fs::read_to_string(dir.join(xhub_provider::PROVIDER_STORE_FILE_NAME))
                .expect("provider store should be readable"),
        )
        .expect("store should parse");
        let account = &store["providers"]["openai"]["accounts"][0];
        assert_eq!(account["account_id"], "acct-id");
        assert_eq!(account["oauth_source_key"], "chatgpt");
        assert_eq!(account["quota"]["daily_tokens_used"], 3750);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn plan_openai_quota_json_returns_due_accounts() {
        let dir = unique_temp_dir("xhubd-provider-quota-plan");
        std::fs::create_dir_all(&dir).expect("temp dir should be created");
        std::fs::write(
            dir.join(xhub_provider::PROVIDER_STORE_FILE_NAME),
            r#"{
              "providers": {
                "openai": {
                  "accounts": [
                    {
                      "account_key": "acct-due",
                      "provider": "openai",
                      "api_key": "sk-test",
                      "auth_index": 1,
                      "account_id": "acct-id",
                      "oauth_source_key": "chatgpt",
                      "quota": {
                        "next_refresh_at_ms": 10
                      }
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("provider store should be written");
        let config = test_config(&dir);

        let out = plan_openai_quota_json_from_parts(
            &config,
            Some(dir.clone()),
            OpenAIQuotaRefreshPlanOptions {
                now_ms: 20,
                include_skipped: false,
                in_flight_account_keys: Vec::new(),
            },
        )
        .expect("quota plan wrapper should succeed");

        let value: Value = serde_json::from_str(&out).expect("output should parse");
        assert_eq!(value["ok"], true);
        assert_eq!(value["command"], "plan-openai-quota");
        assert_eq!(value["result"]["due_accounts"], 1);
        assert_eq!(value["result"]["accounts"][0]["account_key"], "acct-due");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn record_openai_quota_failure_json_persists_backoff_state() {
        let dir = unique_temp_dir("xhubd-provider-quota-failure");
        std::fs::create_dir_all(&dir).expect("temp dir should be created");
        std::fs::write(
            dir.join(xhub_provider::PROVIDER_STORE_FILE_NAME),
            r#"{
              "providers": {
                "openai": {
                  "accounts": [
                    {
                      "account_key": "acct-failed",
                      "provider": "openai",
                      "api_key": "sk-test",
                      "auth_index": 1,
                      "account_id": "acct-id",
                      "oauth_source_key": "chatgpt"
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("provider store should be written");
        let config = test_config(&dir);

        let out = record_openai_quota_failure_json_from_parts(
            &config,
            Some(dir.clone()),
            OpenAIQuotaRefreshFailureOptions {
                account_key: "acct-failed".to_string(),
                failed_at_ms: 1_000,
                base_failure_backoff_ms: 100,
                max_failure_backoff_ms: 1_000,
                error_code: "ETIMEDOUT".to_string(),
                error_message: "timeout".to_string(),
            },
        )
        .expect("quota failure wrapper should succeed");

        let value: Value = serde_json::from_str(&out).expect("output should parse");
        assert_eq!(value["ok"], true);
        assert_eq!(value["command"], "record-openai-quota-failure");
        assert_eq!(value["result"]["next_refresh_at_ms"], 1_100);

        let store: Value = serde_json::from_str(
            &std::fs::read_to_string(dir.join(xhub_provider::PROVIDER_STORE_FILE_NAME))
                .expect("provider store should be readable"),
        )
        .expect("store should parse");
        let account = &store["providers"]["openai"]["accounts"][0];
        assert_eq!(account["refresh_state"]["status"], "idle");
        assert_eq!(account["refresh_state"]["last_error_code"], "ETIMEDOUT");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn apply_oauth_refresh_json_updates_account_without_returning_secret() {
        let dir = unique_temp_dir("xhubd-provider-oauth-refresh-apply");
        std::fs::create_dir_all(&dir).expect("temp dir should be created");
        std::fs::write(
            dir.join(xhub_provider::PROVIDER_STORE_FILE_NAME),
            r#"{
              "providers": {
                "openai": {
                  "accounts": [
                    {
                      "account_key": "acct-oauth",
                      "provider": "openai",
                      "api_key": "old-access",
                      "refresh_token": "old-refresh",
                      "auth_type": "oauth",
                      "expires_at_ms": 1,
                      "models": ["gpt-5.4"],
                      "error_state": {
                        "status": "blocked_auth",
                        "reason_code": "token_expired",
                        "retry_at_source": "refresh"
                      }
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("provider store should be written");
        let config = test_config(&dir);

        let out = apply_oauth_refresh_json_from_parts(
            &config,
            Some(dir.clone()),
            ProviderOAuthRefreshApplyOptions {
                account_key: "acct-oauth".to_string(),
                refreshed_at_ms: 1_000,
                access_token: "new-access-secret".to_string(),
                refresh_token: String::new(),
                expires_at_ms: 2_000_000,
                account_id: String::new(),
                email: String::new(),
                oauth_source_key: String::new(),
            },
        )
        .expect("oauth apply wrapper should succeed");

        let value: Value = serde_json::from_str(&out).expect("output should parse");
        assert_eq!(value["ok"], true);
        assert_eq!(value["command"], "apply-oauth-refresh");
        assert_eq!(
            value["refresh_schema_version"],
            xhub_provider::PROVIDER_OAUTH_REFRESH_SCHEMA_VERSION
        );
        assert!(!out.contains("new-access-secret"));
        assert!(!out.contains("old-refresh"));

        let store: Value = serde_json::from_str(
            &std::fs::read_to_string(dir.join(xhub_provider::PROVIDER_STORE_FILE_NAME))
                .expect("provider store should be readable"),
        )
        .expect("store should parse");
        let account = &store["providers"]["openai"]["accounts"][0];
        assert_eq!(account["api_key"], "new-access-secret");
        assert_eq!(account["refresh_token"], "old-refresh");
        assert_eq!(account["error_state"]["status"], "healthy");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn record_oauth_refresh_failure_json_preserves_xt_reason_codes() {
        let dir = unique_temp_dir("xhubd-provider-oauth-refresh-failure");
        std::fs::create_dir_all(&dir).expect("temp dir should be created");
        std::fs::write(
            dir.join(xhub_provider::PROVIDER_STORE_FILE_NAME),
            r#"{
              "providers": {
                "openai": {
                  "accounts": [
                    {
                      "account_key": "acct-oauth-failed",
                      "provider": "openai",
                      "api_key": "old-access",
                      "refresh_token": "old-refresh",
                      "auth_type": "oauth",
                      "models": ["gpt-5.4"]
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("provider store should be written");
        let config = test_config(&dir);

        let out = record_oauth_refresh_failure_json_from_parts(
            &config,
            Some(dir.clone()),
            ProviderOAuthRefreshFailureOptions {
                account_key: "acct-oauth-failed".to_string(),
                failed_at_ms: 1_000,
                base_failure_backoff_ms: 100,
                max_failure_backoff_ms: 1_000,
                terminal: false,
                error_code: "invalid_grant".to_string(),
                error_message: "invalid_grant".to_string(),
            },
        )
        .expect("oauth failure wrapper should succeed");

        let value: Value = serde_json::from_str(&out).expect("output should parse");
        assert_eq!(value["ok"], true);
        assert_eq!(value["command"], "record-oauth-refresh-failure");
        assert_eq!(value["result"]["ok"], false);
        assert_eq!(value["result"]["error_code"], "invalid_grant");
        assert_eq!(value["result"]["next_refresh_at_ms"], 0);
        assert!(!out.contains("old-refresh"));

        let store: Value = serde_json::from_str(
            &std::fs::read_to_string(dir.join(xhub_provider::PROVIDER_STORE_FILE_NAME))
                .expect("provider store should be readable"),
        )
        .expect("store should parse");
        let account = &store["providers"]["openai"]["accounts"][0];
        assert_eq!(account["error_state"]["status"], "blocked_auth");
        assert_eq!(account["error_state"]["reason_code"], "invalid_grant");
        assert_eq!(account["error_state"]["retry_at_source"], "refresh");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn plan_codex_oauth_refresh_json_is_secret_free() {
        let dir = unique_temp_dir("xhubd-provider-codex-oauth-refresh-plan");
        std::fs::create_dir_all(&dir).expect("temp dir should be created");
        std::fs::write(
            dir.join(xhub_provider::PROVIDER_STORE_FILE_NAME),
            r#"{
              "providers": {
                "openai": {
                  "accounts": [
                    {
                      "account_key": "acct-codex-plan",
                      "provider": "openai",
                      "api_key": "old-access-secret",
                      "refresh_token": "old-refresh-secret",
                      "auth_type": "oauth",
                      "oauth_source_key": "chatgpt",
                      "expires_at_ms": 1,
                      "models": ["gpt-5.4"]
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("provider store should be written");
        let config = test_config(&dir);

        let out = plan_codex_oauth_refresh_json_from_parts(
            &config,
            Some(dir.clone()),
            ProviderOAuthRefreshPlanOptions {
                now_ms: 1_000,
                include_skipped: true,
                in_flight_account_keys: Vec::new(),
                refresh_lead_ms: 0,
                min_refresh_lead_ms: 0,
            },
        )
        .expect("codex oauth refresh plan should run");

        let value: Value = serde_json::from_str(&out).expect("output should parse");
        assert_eq!(value["ok"], true);
        assert_eq!(value["command"], "plan-codex-oauth-refresh");
        assert_eq!(value["result"]["due_accounts"], 1);
        assert_eq!(
            value["result"]["accounts"][0]["account_key"],
            "acct-codex-plan"
        );
        assert_eq!(
            value["result"]["accounts"][0]["reason_code"],
            "token_expired"
        );
        assert!(!out.contains("old-access-secret"));
        assert!(!out.contains("old-refresh-secret"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn refresh_codex_oauth_json_calls_endpoint_and_updates_store_without_secret() {
        let dir = unique_temp_dir("xhubd-provider-codex-oauth-refresh-success");
        std::fs::create_dir_all(&dir).expect("temp dir should be created");
        std::fs::write(
            dir.join(xhub_provider::PROVIDER_STORE_FILE_NAME),
            r#"{
              "providers": {
                "openai": {
                  "accounts": [
                    {
                      "account_key": "acct-codex",
                      "provider": "openai",
                      "api_key": "old-access-secret",
                      "refresh_token": "old-refresh-secret",
                      "auth_type": "oauth",
                      "oauth_source_key": "chatgpt",
                      "expires_at_ms": 1,
                      "models": ["gpt-5.4"],
                      "error_state": {
                        "status": "blocked_auth",
                        "reason_code": "token_expired",
                        "retry_at_source": "refresh"
                      }
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("provider store should be written");
        let token_url = spawn_token_endpoint(
            200,
            r#"{"access_token":"new-access-secret","refresh_token":"new-refresh-secret","expires_in":3600}"#,
        );
        let config = test_config(&dir);

        let out = refresh_codex_oauth_json_from_parts(
            &config,
            Some(dir.clone()),
            CodexOAuthRefreshOptions {
                account_key: "acct-codex".to_string(),
                refreshed_at_ms: 1_000,
                timeout_ms: 5_000,
                base_failure_backoff_ms: 100,
                max_failure_backoff_ms: 1_000,
                token_url,
                force: false,
            },
        )
        .expect("codex oauth refresh should run");

        let value: Value = serde_json::from_str(&out).expect("output should parse");
        assert_eq!(value["ok"], true);
        assert_eq!(value["command"], "refresh-codex-oauth");
        assert_eq!(value["http_status"], 200);
        assert_eq!(value["result"]["ok"], true);
        assert!(!out.contains("new-access-secret"));
        assert!(!out.contains("new-refresh-secret"));
        assert!(!out.contains("old-refresh-secret"));

        let store: Value = serde_json::from_str(
            &std::fs::read_to_string(dir.join(xhub_provider::PROVIDER_STORE_FILE_NAME))
                .expect("provider store should be readable"),
        )
        .expect("store should parse");
        let account = &store["providers"]["openai"]["accounts"][0];
        assert_eq!(account["api_key"], "new-access-secret");
        assert_eq!(account["refresh_token"], "new-refresh-secret");
        assert_eq!(account["expires_at_ms"], 3_601_000);
        assert_eq!(account["error_state"]["status"], "healthy");
        assert_eq!(account["refresh_state"]["status"], "idle");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn refresh_codex_oauth_json_records_terminal_provider_failure() {
        let dir = unique_temp_dir("xhubd-provider-codex-oauth-refresh-failure");
        std::fs::create_dir_all(&dir).expect("temp dir should be created");
        std::fs::write(
            dir.join(xhub_provider::PROVIDER_STORE_FILE_NAME),
            r#"{
              "providers": {
                "openai": {
                  "accounts": [
                    {
                      "account_key": "acct-codex-fail",
                      "provider": "openai",
                      "api_key": "old-access-secret",
                      "refresh_token": "old-refresh-secret",
                      "auth_type": "oauth",
                      "oauth_source_key": "chatgpt",
                      "models": ["gpt-5.4"]
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("provider store should be written");
        let token_url = spawn_token_endpoint(
            400,
            r#"{"error":"invalid_grant","error_description":"refresh_token_reused"}"#,
        );
        let config = test_config(&dir);

        let out = refresh_codex_oauth_json_from_parts(
            &config,
            Some(dir.clone()),
            CodexOAuthRefreshOptions {
                account_key: "acct-codex-fail".to_string(),
                refreshed_at_ms: 1_000,
                timeout_ms: 5_000,
                base_failure_backoff_ms: 100,
                max_failure_backoff_ms: 1_000,
                token_url,
                force: false,
            },
        )
        .expect("codex oauth refresh should record failure");

        let value: Value = serde_json::from_str(&out).expect("output should parse");
        assert_eq!(value["ok"], false);
        assert_eq!(value["command"], "refresh-codex-oauth");
        assert_eq!(value["reason_code"], "refresh_token_reused");
        assert_eq!(value["result"]["ok"], false);
        assert_eq!(value["result"]["error_code"], "refresh_token_reused");
        assert_eq!(value["result"]["next_refresh_at_ms"], 0);
        assert!(!out.contains("old-refresh-secret"));

        let store: Value = serde_json::from_str(
            &std::fs::read_to_string(dir.join(xhub_provider::PROVIDER_STORE_FILE_NAME))
                .expect("provider store should be readable"),
        )
        .expect("store should parse");
        let account = &store["providers"]["openai"]["accounts"][0];
        assert_eq!(account["error_state"]["status"], "blocked_auth");
        assert_eq!(
            account["error_state"]["reason_code"],
            "refresh_token_reused"
        );
        assert_eq!(account["refresh_state"]["next_refresh_at_ms"], 0);
        let _ = std::fs::remove_dir_all(&dir);
    }

    fn test_config(runtime_base_dir: &std::path::Path) -> HubConfig {
        HubConfig {
            root_dir: runtime_base_dir.to_path_buf(),
            host: "127.0.0.1".to_string(),
            http_port: 50151,
            grpc_port: 50152,
            db_path: runtime_base_dir.join("hub.sqlite3"),
            runtime_base_dir: runtime_base_dir.to_path_buf(),
            proto_path: runtime_base_dir.join("hub_protocol_v1.proto"),
            canonical_proto_path: runtime_base_dir.join("hub_protocol_v1.proto"),
            http_access_key: None,
            http_access_key_source: String::new(),
            http_access_key_required: false,
        }
    }

    fn unique_temp_dir(prefix: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "{}-{}-{}",
            prefix,
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|duration| duration.as_nanos())
                .unwrap_or(0)
        ))
    }

    fn spawn_token_endpoint(status: u16, body: &'static str) -> String {
        let listener =
            std::net::TcpListener::bind("127.0.0.1:0").expect("mock token endpoint should bind");
        let addr = listener
            .local_addr()
            .expect("mock token endpoint should have addr");
        std::thread::spawn(move || {
            let (mut stream, _) = listener
                .accept()
                .expect("mock token endpoint should accept");
            let mut request = [0_u8; 8192];
            let _ = std::io::Read::read(&mut stream, &mut request);
            let reason = if status == 200 { "OK" } else { "Bad Request" };
            let response = format!(
                "HTTP/1.1 {} {}\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{}",
                status,
                reason,
                body.len(),
                body
            );
            std::io::Write::write_all(&mut stream, response.as_bytes())
                .expect("mock token endpoint should write response");
        });
        format!("http://{addr}/oauth/token")
    }
}
