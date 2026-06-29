//! Attestation load + signature verify, per protocol v0.1 §6.

use anyhow::{anyhow, bail, Context, Result};
use ed25519_dalek::{Signer, SigningKey, Verifier};
use serde_json::{Map, Value};
use std::path::Path;
use time::OffsetDateTime;

use crate::codec;

#[derive(Debug, Clone)]
pub struct Attestation {
    pub raw: Value,
}

impl Attestation {
    pub fn load(path: &Path) -> Result<Self> {
        let bytes = std::fs::read(path)
            .with_context(|| format!("read attestation {}", path.display()))?;
        let raw: Value = serde_json::from_slice(&bytes)
            .with_context(|| format!("parse attestation {}", path.display()))?;
        Ok(Self { raw })
    }

    pub fn from_value(raw: Value) -> Self {
        Self { raw }
    }

    pub fn manifest_hash(&self) -> Result<&str> {
        self.raw
            .get("manifest_hash")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow!("attestation missing manifest_hash"))
    }

    pub fn artifact_hash(&self) -> Result<&str> {
        self.raw
            .get("artifact_hash")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow!("attestation missing artifact_hash"))
    }

    pub fn publisher_key_id(&self) -> Result<&str> {
        self.raw
            .get("publisher_key_id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow!("attestation missing publisher_key_id"))
    }

    pub fn signature_str(&self) -> Result<&str> {
        match self.raw.get("signature") {
            Some(Value::String(s)) => Ok(s.as_str()),
            Some(Value::Null) | None => bail!("attestation missing signature (keyless mode is v0.1.1+)"),
            _ => bail!("attestation signature must be a string"),
        }
    }

    /// Canonical bytes signed by the publisher: full document MINUS
    /// `signature` and `sigstore_bundle` (per §6.2).
    pub fn signing_bytes(&self) -> Result<Vec<u8>> {
        let obj = self
            .raw
            .as_object()
            .ok_or_else(|| anyhow!("attestation must be a JSON object"))?;
        let mut stripped = Map::with_capacity(obj.len());
        for (k, v) in obj {
            if k == "signature" || k == "sigstore_bundle" {
                continue;
            }
            stripped.insert(k.clone(), v.clone());
        }
        serde_jcs::to_vec(&Value::Object(stripped)).context("canonicalize attestation")
    }

    pub fn check_expiry(&self, now: OffsetDateTime) -> Result<()> {
        if let Some(Value::String(s)) = self.raw.get("expires_at") {
            let expires = OffsetDateTime::parse(s, &time::format_description::well_known::Rfc3339)
                .with_context(|| format!("parse expires_at {s}"))?;
            if now > expires {
                bail!("attestation expired at {s}");
            }
        }
        Ok(())
    }
}

/// Build an attestation Value over the supplied manifest, signed with `key`.
/// `expires_at` is set 18 months after `issued_at` per §6.4.
pub fn build_signed(
    manifest_hash: &str,
    artifact_hash: &str,
    key: &SigningKey,
    issued_at: OffsetDateTime,
) -> Result<Attestation> {
    let key_id = codec::encode_key_id(&key.verifying_key());
    let expires_at = issued_at + time::Duration::days(540); // ~18 months
    let issued = issued_at.format(&time::format_description::well_known::Rfc3339)?;
    let expires = expires_at.format(&time::format_description::well_known::Rfc3339)?;

    // Build the signing payload first (no signature, no sigstore_bundle per §6.2).
    let mut signed_payload = Map::new();
    signed_payload.insert("schema".into(), Value::String("skill-trust/attestation/v0.1".into()));
    signed_payload.insert("manifest_hash".into(), Value::String(manifest_hash.into()));
    signed_payload.insert("artifact_hash".into(), Value::String(artifact_hash.into()));
    signed_payload.insert("publisher_key_id".into(), Value::String(key_id));
    signed_payload.insert("issued_at".into(), Value::String(issued));
    signed_payload.insert("expires_at".into(), Value::String(expires));

    let signing_bytes = serde_jcs::to_vec(&Value::Object(signed_payload.clone()))?;
    let sig = key.sign(&signing_bytes);

    let mut obj = signed_payload;
    obj.insert("sigstore_bundle".into(), Value::Null);
    obj.insert("signature".into(), Value::String(codec::encode_signature(&sig)));

    Ok(Attestation::from_value(Value::Object(obj)))
}

/// Verify the attestation's signature against the public key referenced by `publisher_key_id`,
/// AND that the attestation's manifest_hash equals the supplied actual manifest hash.
pub fn verify(att: &Attestation, expected_manifest_hash: &str) -> Result<()> {
    if att.manifest_hash()? != expected_manifest_hash {
        bail!(
            "attestation manifest_hash {} does not match supplied manifest hash {}",
            att.manifest_hash()?,
            expected_manifest_hash
        );
    }
    let vk = codec::decode_key_id(att.publisher_key_id()?)?;
    let sig = codec::decode_signature(att.signature_str()?)?;
    let bytes = att.signing_bytes()?;
    vk.verify(&bytes, &sig).context("ed25519 signature verification failed")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use rand::rngs::OsRng;
    use time::macros::datetime;

    #[test]
    fn sign_then_verify_roundtrip() {
        let key = SigningKey::generate(&mut OsRng);
        let mh = "sha256:1c2fb07a8e4d6b9a7f3c5e8d2a6b9f1c4e7a3b6d9c2f5e8a1d4b7c0f3e6a9d2c";
        let ah = "sha256:9f3cab2e7d1f5c4e8a2b6d9f3c4e1a7b2d5f8c9e3a6b1d4f7c2e5a8b9d0c1f3a";
        let issued = datetime!(2026-06-29 12:00:00 UTC);
        let att = build_signed(mh, ah, &key, issued).unwrap();
        verify(&att, mh).unwrap();
    }

    #[test]
    fn verify_rejects_wrong_manifest_hash() {
        let key = SigningKey::generate(&mut OsRng);
        let mh = "sha256:1c2fb07a8e4d6b9a7f3c5e8d2a6b9f1c4e7a3b6d9c2f5e8a1d4b7c0f3e6a9d2c";
        let issued = datetime!(2026-06-29 12:00:00 UTC);
        let att = build_signed(mh, "sha256:9f3c", &key, issued).unwrap();
        let result = verify(&att, "sha256:deadbeef");
        assert!(result.is_err());
    }

    #[test]
    fn verify_rejects_tampered_payload() {
        let key = SigningKey::generate(&mut OsRng);
        let mh = "sha256:1c2fb07a8e4d6b9a7f3c5e8d2a6b9f1c4e7a3b6d9c2f5e8a1d4b7c0f3e6a9d2c";
        let issued = datetime!(2026-06-29 12:00:00 UTC);
        let mut att = build_signed(mh, "sha256:9f3c", &key, issued).unwrap();
        // Tamper with artifact_hash after signing.
        att.raw.as_object_mut().unwrap().insert(
            "artifact_hash".into(),
            Value::String("sha256:tampered".into()),
        );
        assert!(verify(&att, mh).is_err());
    }
}
