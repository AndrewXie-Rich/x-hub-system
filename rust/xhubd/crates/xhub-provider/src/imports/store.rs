use std::fs;
use std::path::Path;

use serde_json::{json, Map, Value};

use super::*;

pub(super) fn load_provider_store_value_for_import(
    path: &Path,
) -> Result<Value, ProviderRouteError> {
    if !path.is_file() {
        return Ok(empty_provider_store_value());
    }
    let raw = fs::read_to_string(path)
        .map_err(|err| ProviderRouteError::Io(format!("{}: {err}", path.display())))?;
    let mut value: Value = serde_json::from_str(&raw)
        .map_err(|err| ProviderRouteError::Json(format!("{}: {err}", path.display())))?;
    ensure_provider_store_shape(&mut value);
    Ok(value)
}

pub(super) fn empty_provider_store_value() -> Value {
    json!({
        "schema_version": "hub_provider_keys.v1",
        "updated_at_ms": 0,
        "routing_strategy": default_routing_strategy(),
        "import_sources": [],
        "import_source_statuses": {},
        "providers": {},
    })
}

pub(super) fn ensure_provider_store_shape(value: &mut Value) {
    if !value.is_object() {
        *value = empty_provider_store_value();
        return;
    }
    let object = value.as_object_mut().expect("value is object");
    object
        .entry("schema_version".to_string())
        .or_insert_with(|| Value::String("hub_provider_keys.v1".to_string()));
    object
        .entry("updated_at_ms".to_string())
        .or_insert_with(|| json!(0));
    object
        .entry("routing_strategy".to_string())
        .or_insert_with(|| Value::String(default_routing_strategy()));
    if !object
        .get("import_sources")
        .map(Value::is_array)
        .unwrap_or(false)
    {
        object.insert("import_sources".to_string(), Value::Array(Vec::new()));
    }
    if !object
        .get("import_source_statuses")
        .map(Value::is_object)
        .unwrap_or(false)
    {
        object.insert(
            "import_source_statuses".to_string(),
            Value::Object(Map::new()),
        );
    }
    if !object
        .get("providers")
        .map(Value::is_object)
        .unwrap_or(false)
    {
        object.insert("providers".to_string(), Value::Object(Map::new()));
    }
}
