//! Session receipt build + sign, conforming to `receipt.schema.json`.

use anyhow::{Context, Result};
use ed25519_dalek::{Signer, SigningKey};
use rand::RngCore;
use serde_json::{json, Map, Value};
use time::OffsetDateTime;

use crate::codec;

#[derive(Debug, Clone)]
pub struct ReceiptInput {
    pub server_name: String,
    pub manifest_hash: String,
    pub artifact_hash: String,
    pub started_at: OffsetDateTime,
    pub ended_at: OffsetDateTime,
    pub tool_calls: u64,
    pub capability_denials: u64,
    pub policy_hash: String,
    pub denial_summary: Vec<(String, u64)>,
}

pub fn build_signed(input: &ReceiptInput, verifier: &SigningKey) -> Result<Value> {
    let session_id = mint_session_id();
    let started = input
        .started_at
        .format(&time::format_description::well_known::Rfc3339)?;
    let ended = input
        .ended_at
        .format(&time::format_description::well_known::Rfc3339)?;
    let verifier_key_id = codec::encode_key_id(&verifier.verifying_key());

    let mut obj = Map::new();
    obj.insert("schema".into(), Value::String("skill-trust/receipt/v0.1".into()));
    obj.insert("session_id".into(), Value::String(session_id));
    obj.insert("server_name".into(), Value::String(input.server_name.clone()));
    obj.insert("manifest_hash".into(), Value::String(input.manifest_hash.clone()));
    obj.insert("artifact_hash".into(), Value::String(input.artifact_hash.clone()));
    obj.insert("started_at".into(), Value::String(started));
    obj.insert("ended_at".into(), Value::String(ended));
    obj.insert("verifier_key_id".into(), Value::String(verifier_key_id));
    obj.insert("tool_calls".into(), json!(input.tool_calls));
    obj.insert("capability_denials".into(), json!(input.capability_denials));
    obj.insert("policy_hash".into(), Value::String(input.policy_hash.clone()));
    if !input.denial_summary.is_empty() {
        obj.insert(
            "denial_summary".into(),
            Value::Array(
                input
                    .denial_summary
                    .iter()
                    .map(|(cap, count)| json!({"capability": cap, "count": count}))
                    .collect(),
            ),
        );
    }

    let signing_bytes =
        serde_jcs::to_vec(&Value::Object(obj.clone())).context("canonicalize receipt")?;
    let sig = verifier.sign(&signing_bytes);
    obj.insert("signature".into(), Value::String(codec::encode_signature(&sig)));

    Ok(Value::Object(obj))
}

fn mint_session_id() -> String {
    let mut bytes = [0u8; 8];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    let hex: String = bytes.iter().map(|b| format!("{:02x}", b)).collect();
    format!("rcpt-{hex}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::Verifier;
    use rand::rngs::OsRng;
    use time::macros::datetime;

    #[test]
    fn receipt_signature_verifies() {
        let key = SigningKey::generate(&mut OsRng);
        let input = ReceiptInput {
            server_name: "browser-tools".into(),
            manifest_hash: "sha256:1c2fb07a8e4d6b9a7f3c5e8d2a6b9f1c4e7a3b6d9c2f5e8a1d4b7c0f3e6a9d2c"
                .into(),
            artifact_hash: "sha256:9f3cab2e7d1f5c4e8a2b6d9f3c4e1a7b2d5f8c9e3a6b1d4f7c2e5a8b9d0c1f3a"
                .into(),
            started_at: datetime!(2026-06-29 14:00:00 UTC),
            ended_at: datetime!(2026-06-29 14:05:00 UTC),
            tool_calls: 3,
            capability_denials: 1,
            policy_hash: "sha256:e0f23a4b7c8d1e2f5a8b9c0d3e6f1a4b7c0d3e6f9a2b5c8d1e4f7a0b3c6d9e2f"
                .into(),
            denial_summary: vec![("shell:exec".into(), 1)],
        };
        let receipt = build_signed(&input, &key).unwrap();
        let mut stripped = receipt.as_object().unwrap().clone();
        let sig_str = stripped.remove("signature").unwrap();
        let sig = codec::decode_signature(sig_str.as_str().unwrap()).unwrap();
        let bytes = serde_jcs::to_vec(&Value::Object(stripped)).unwrap();
        key.verifying_key().verify(&bytes, &sig).unwrap();
    }
}
