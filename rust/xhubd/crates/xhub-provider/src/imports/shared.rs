use serde_json::Value;

#[derive(Debug, Clone, Default)]
pub(super) struct ImportOverlay {
    pub(super) provider: String,
    pub(super) base_url: String,
    pub(super) proxy_url: String,
    pub(super) wire_api: String,
    pub(super) source: String,
    pub(super) import_source_kind: String,
    pub(super) import_source_ref: String,
}

#[derive(Debug, Clone, Default)]
pub(super) struct ImportedAccountBuild {
    pub(super) accounts: Vec<Value>,
    pub(super) errors: Vec<String>,
}

#[derive(Debug, Clone, Default)]
pub(super) struct ImportedAccountApply {
    pub(super) imported: u32,
    pub(super) errors: Vec<String>,
}
