//! Manifest load + canonicalize + hash, per protocol v0.1 §4.

use anyhow::{Context, Result};
use serde_json::Value;
use std::path::Path;
use unicode_normalization::UnicodeNormalization;

use crate::codec;

#[derive(Debug, Clone)]
pub struct Manifest {
    pub raw: Value,
}

impl Manifest {
    pub fn load(path: &Path) -> Result<Self> {
        let bytes = std::fs::read(path)
            .with_context(|| format!("read manifest {}", path.display()))?;
        let raw: Value = serde_json::from_slice(&bytes)
            .with_context(|| format!("parse manifest {}", path.display()))?;
        Ok(Self { raw })
    }

    #[cfg(test)]
    pub fn from_value(raw: Value) -> Self {
        Self { raw }
    }

    /// Canonical JSON per §4.4: keys sorted, no whitespace, NFC strings,
    /// numbers in shortest unambiguous form. Delegated to RFC 8785 (JCS).
    pub fn canonical(&self) -> Result<Vec<u8>> {
        let nfc = nfc_normalize(&self.raw);
        serde_jcs::to_vec(&nfc).context("canonicalize manifest (JCS)")
    }

    pub fn hash(&self) -> Result<String> {
        Ok(codec::sha256_hex(&self.canonical()?))
    }

    pub fn name(&self) -> Option<&str> {
        self.raw.get("name").and_then(|v| v.as_str())
    }

    pub fn artifact_hash(&self) -> Option<&str> {
        self.raw.pointer("/artifact/sha256").and_then(|v| v.as_str())
    }

    #[allow(dead_code)]
    pub fn artifact_type(&self) -> Option<&str> {
        self.raw.pointer("/artifact/type").and_then(|v| v.as_str())
    }

    pub fn publisher_key_id(&self) -> Option<&str> {
        self.raw.pointer("/publisher/key_id").and_then(|v| v.as_str())
    }

    pub fn required_capabilities(&self) -> Vec<String> {
        self.raw
            .pointer("/capabilities/required")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().filter_map(|v| v.as_str().map(String::from)).collect())
            .unwrap_or_default()
    }

    pub fn optional_capabilities(&self) -> Vec<String> {
        self.raw
            .pointer("/capabilities/optional")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().filter_map(|v| v.as_str().map(String::from)).collect())
            .unwrap_or_default()
    }
}

fn nfc_normalize(v: &Value) -> Value {
    match v {
        Value::String(s) => Value::String(s.nfc().collect::<String>()),
        Value::Array(arr) => Value::Array(arr.iter().map(nfc_normalize).collect()),
        Value::Object(map) => {
            let mut out = serde_json::Map::with_capacity(map.len());
            for (k, val) in map {
                out.insert(k.nfc().collect::<String>(), nfc_normalize(val));
            }
            Value::Object(out)
        }
        other => other.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn canonical_sorts_keys() {
        let m = Manifest::from_value(json!({"b": 1, "a": 2}));
        let canon = m.canonical().unwrap();
        assert_eq!(std::str::from_utf8(&canon).unwrap(), r#"{"a":2,"b":1}"#);
    }

    #[test]
    fn canonical_strips_whitespace() {
        let raw: Value = serde_json::from_str("{  \"x\" :  1 }").unwrap();
        let m = Manifest::from_value(raw);
        assert_eq!(std::str::from_utf8(&m.canonical().unwrap()).unwrap(), r#"{"x":1}"#);
    }

    #[test]
    fn hash_is_stable() {
        let m1 = Manifest::from_value(json!({"a": 1, "b": [2, 3]}));
        let m2 = Manifest::from_value(json!({"b": [2, 3], "a": 1}));
        assert_eq!(m1.hash().unwrap(), m2.hash().unwrap());
    }

    #[test]
    fn accessors_pull_known_fields() {
        let m = Manifest::from_value(json!({
            "name": "browser-tools",
            "publisher": {"key_id": "ed25519:abc"},
            "artifact": {"type": "npm", "sha256": "9f3c…"},
            "capabilities": {"required": ["fs:read:/tmp/**"], "optional": ["shell:exec"]}
        }));
        assert_eq!(m.name(), Some("browser-tools"));
        assert_eq!(m.publisher_key_id(), Some("ed25519:abc"));
        assert_eq!(m.artifact_type(), Some("npm"));
        assert_eq!(m.required_capabilities(), vec!["fs:read:/tmp/**"]);
        assert_eq!(m.optional_capabilities(), vec!["shell:exec"]);
    }
}
