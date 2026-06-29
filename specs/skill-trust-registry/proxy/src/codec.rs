//! Encoding helpers for the wire formats v0.1 specifies.
//!
//! - `ed25519:<base32 lowercase, no padding>` for public-key identifiers (52 chars).
//! - `ed25519:<base64 standard, padded>` for signatures.
//! - `sha256:<lowercase hex>` for content hashes.

use anyhow::{anyhow, bail, Context, Result};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use data_encoding::BASE32_NOPAD;
use ed25519_dalek::{Signature, VerifyingKey, PUBLIC_KEY_LENGTH, SIGNATURE_LENGTH};

const KEY_PREFIX: &str = "ed25519:";

pub fn encode_key_id(pubkey: &VerifyingKey) -> String {
    let bytes = pubkey.to_bytes();
    let b32 = BASE32_NOPAD.encode(&bytes).to_lowercase();
    format!("{KEY_PREFIX}{b32}")
}

pub fn decode_key_id(key_id: &str) -> Result<VerifyingKey> {
    let body = key_id
        .strip_prefix(KEY_PREFIX)
        .ok_or_else(|| anyhow!("key id missing 'ed25519:' prefix: {key_id}"))?;
    if body.len() != 52 {
        bail!("key id base32 body must be 52 chars, got {}: {key_id}", body.len());
    }
    let upper = body.to_uppercase();
    let bytes = BASE32_NOPAD
        .decode(upper.as_bytes())
        .with_context(|| format!("base32 decode failed for {key_id}"))?;
    if bytes.len() != PUBLIC_KEY_LENGTH {
        bail!("public key wrong length: {} bytes", bytes.len());
    }
    let arr: [u8; PUBLIC_KEY_LENGTH] = bytes.as_slice().try_into().unwrap();
    VerifyingKey::from_bytes(&arr).context("invalid ed25519 public key bytes")
}

pub fn encode_signature(sig: &Signature) -> String {
    format!("{KEY_PREFIX}{}", BASE64.encode(sig.to_bytes()))
}

pub fn decode_signature(s: &str) -> Result<Signature> {
    let body = s
        .strip_prefix(KEY_PREFIX)
        .ok_or_else(|| anyhow!("signature missing 'ed25519:' prefix"))?;
    let bytes = BASE64
        .decode(body.as_bytes())
        .context("signature base64 decode failed")?;
    if bytes.len() != SIGNATURE_LENGTH {
        bail!("signature wrong length: {} bytes", bytes.len());
    }
    let arr: [u8; SIGNATURE_LENGTH] = bytes.as_slice().try_into().unwrap();
    Ok(Signature::from_bytes(&arr))
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    let digest = Sha256::digest(bytes);
    format!("sha256:{}", hex_lower(&digest))
}

fn hex_lower(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        out.push_str(&format!("{:02x}", b));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::SigningKey;
    use rand::rngs::OsRng;

    #[test]
    fn key_id_roundtrip() {
        let sk = SigningKey::generate(&mut OsRng);
        let vk = sk.verifying_key();
        let id = encode_key_id(&vk);
        assert!(id.starts_with("ed25519:"));
        assert_eq!(id.len(), 8 + 52);
        let decoded = decode_key_id(&id).unwrap();
        assert_eq!(decoded.to_bytes(), vk.to_bytes());
    }

    #[test]
    fn signature_roundtrip() {
        let sk = SigningKey::generate(&mut OsRng);
        let sig = ed25519_dalek::Signer::sign(&sk, b"hello");
        let encoded = encode_signature(&sig);
        let decoded = decode_signature(&encoded).unwrap();
        assert_eq!(sig.to_bytes(), decoded.to_bytes());
    }

    #[test]
    fn sha256_known_vector() {
        assert_eq!(
            sha256_hex(b""),
            "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
    }
}
