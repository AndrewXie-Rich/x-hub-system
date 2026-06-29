use super::*;

#[derive(Debug, Clone, Default)]
pub(super) struct OpenAIQuotaMetadata {
    pub(super) account_id: String,
    pub(super) oauth_source_key: String,
    pub(super) can_use_direct_access_token: bool,
}

pub(super) fn openai_quota_metadata_for_account(account: &ProviderAccount) -> OpenAIQuotaMetadata {
    let claims = decode_jwt_payload_value(&account.api_key);
    let auth_claims = claims
        .as_ref()
        .and_then(|value| value.get("https://api.openai.com/auth"));
    let account_id = first_non_empty(&[
        &account.account_id,
        &auth_claims
            .map(|value| json_string(value, "chatgpt_account_id"))
            .unwrap_or_default(),
        &claims
            .as_ref()
            .map(|value| json_string(value, "chatgpt_account_id"))
            .unwrap_or_default(),
        &claims
            .as_ref()
            .map(|value| json_string(value, "account_id"))
            .unwrap_or_default(),
    ])
    .unwrap_or_default();
    let oauth_source_key = first_non_empty(&[
        &account.oauth_source_key,
        if !account_id.is_empty() && claims.is_some() {
            "chatgpt"
        } else {
            ""
        },
    ])
    .unwrap_or_default();
    OpenAIQuotaMetadata {
        account_id: trim_string(&account_id),
        oauth_source_key: normalized_token(&oauth_source_key),
        can_use_direct_access_token: claims.is_some() && !account_id.trim().is_empty(),
    }
}

pub(super) fn supported_openai_quota_account_with_metadata(
    account: &ProviderAccount,
    metadata: &OpenAIQuotaMetadata,
) -> bool {
    if metadata.account_id.is_empty() {
        return false;
    }
    let provider = normalized_token(&account.provider);
    if provider == "openai" || provider == "codex" {
        return account.auth_index > 0 || metadata.can_use_direct_access_token;
    }
    if OPENAI_USAGE_WINDOW_OAUTH_SOURCES
        .iter()
        .any(|source| *source == metadata.oauth_source_key.as_str())
    {
        return account.auth_index > 0 || metadata.can_use_direct_access_token;
    }
    metadata.can_use_direct_access_token
}
