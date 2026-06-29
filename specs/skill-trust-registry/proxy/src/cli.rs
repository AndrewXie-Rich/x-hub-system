//! CLI dispatch — keygen, sign, verify, check.

use anyhow::{anyhow, bail, Context, Result};
use clap::{Parser, Subcommand};
use ed25519_dalek::SigningKey;
use rand::rngs::OsRng;
use serde_json::Value;
use std::path::{Path, PathBuf};
use time::OffsetDateTime;

use crate::attestation::{self, Attestation};
use crate::capability::{self, Decision};
use crate::codec;
use crate::manifest::Manifest;
use crate::receipt::{self, ReceiptInput};

#[derive(Parser, Debug)]
#[command(
    name = "skill-trust-proxy",
    version,
    about = "Reference implementation of the Skill Trust Registry v0.1 trust layer.",
    long_about = "Provides keygen / sign / verify / check primitives over Skill-Trust v0.1 manifests \
and attestations. The protocol is agnostic to the underlying tool RPC (MCP, A2A, OpenAI tools, \
custom — see protocol-v0.1.md §1). Runtime sandboxing of an actual tool server is deferred to v0.1.1."
)]
pub struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// Generate a fresh ed25519 keypair.
    Keygen {
        /// Path prefix; writes <out>.secret.key (32-byte seed) and <out>.pub.txt (key id).
        #[arg(long, default_value = "publisher")]
        out: PathBuf,
    },

    /// Sign a manifest, producing an attestation JSON document.
    Sign {
        #[arg(long)]
        manifest: PathBuf,
        /// Path to the 32-byte ed25519 seed produced by `keygen`.
        #[arg(long)]
        key: PathBuf,
        /// Output path for the attestation JSON.
        #[arg(long)]
        out: PathBuf,
    },

    /// Verify a (manifest, attestation) pair.
    Verify {
        /// Use the bundled `examples/` fixtures rather than --manifest/--attestation.
        #[arg(long, conflicts_with_all = ["manifest", "attestation"])]
        example: bool,
        #[arg(long, requires = "attestation")]
        manifest: Option<PathBuf>,
        #[arg(long, requires = "manifest")]
        attestation: Option<PathBuf>,
        /// Optional receipt output path. If set, emits a signed session receipt
        /// (using an ephemeral verifier key — for demo purposes only).
        #[arg(long)]
        receipt_out: Option<PathBuf>,
    },

    /// Resolve a capability request against the manifest's declared capabilities.
    Check {
        #[arg(long)]
        manifest: PathBuf,
        /// Token to check, e.g. `shell:exec`, `fs:read:/etc/passwd`.
        #[arg(long)]
        capability: String,
    },
}

impl Cli {
    pub fn run(self) -> Result<()> {
        match self.cmd {
            Cmd::Keygen { out } => cmd_keygen(&out),
            Cmd::Sign { manifest, key, out } => cmd_sign(&manifest, &key, &out),
            Cmd::Verify { example, manifest, attestation, receipt_out } => {
                cmd_verify(example, manifest, attestation, receipt_out)
            }
            Cmd::Check { manifest, capability } => cmd_check(&manifest, &capability),
        }
    }
}

fn cmd_keygen(out: &Path) -> Result<()> {
    let key = SigningKey::generate(&mut OsRng);
    let secret_path = with_suffix(out, ".secret.key");
    let pub_path = with_suffix(out, ".pub.txt");

    std::fs::write(&secret_path, key.to_bytes())
        .with_context(|| format!("write {}", secret_path.display()))?;
    let key_id = codec::encode_key_id(&key.verifying_key());
    std::fs::write(&pub_path, format!("{key_id}\n"))
        .with_context(|| format!("write {}", pub_path.display()))?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perm = std::fs::metadata(&secret_path)?.permissions();
        perm.set_mode(0o600);
        std::fs::set_permissions(&secret_path, perm)?;
    }

    println!("wrote secret seed:  {}", secret_path.display());
    println!("wrote public id:    {}  ({key_id})", pub_path.display());
    Ok(())
}

fn cmd_sign(manifest_path: &Path, key_path: &Path, out: &Path) -> Result<()> {
    let manifest = Manifest::load(manifest_path)?;
    let manifest_hash = manifest.hash()?;
    let artifact_hash = manifest
        .artifact_hash()
        .ok_or_else(|| anyhow!("manifest is missing /artifact/sha256"))?;

    let seed_bytes = std::fs::read(key_path)
        .with_context(|| format!("read key {}", key_path.display()))?;
    if seed_bytes.len() != 32 {
        bail!("key file must be 32 bytes (got {})", seed_bytes.len());
    }
    let seed: [u8; 32] = seed_bytes.as_slice().try_into().unwrap();
    let key = SigningKey::from_bytes(&seed);

    if let Some(decl) = manifest.publisher_key_id() {
        let declared_key = codec::encode_key_id(&key.verifying_key());
        if decl != declared_key {
            bail!(
                "manifest publisher.key_id={decl} does not match key file (which is {declared_key})"
            );
        }
    }

    let issued = OffsetDateTime::now_utc();
    let att = attestation::build_signed(&manifest_hash, &format!("sha256:{artifact_hash}"), &key, issued)?;
    std::fs::write(out, serialize_pretty(&att.raw)?)
        .with_context(|| format!("write {}", out.display()))?;

    println!("manifest hash:     {manifest_hash}");
    println!("wrote attestation: {}", out.display());
    Ok(())
}

fn cmd_verify(
    example: bool,
    manifest: Option<PathBuf>,
    attestation_path: Option<PathBuf>,
    receipt_out: Option<PathBuf>,
) -> Result<()> {
    let (manifest_path, att_path) = if example {
        let base = bundled_examples_dir()?;
        (base.join("manifest.json"), base.join("attestation.json"))
    } else {
        let m = manifest.ok_or_else(|| anyhow!("--manifest required (or use --example)"))?;
        let a = attestation_path.ok_or_else(|| anyhow!("--attestation required (or use --example)"))?;
        (m, a)
    };

    let manifest = Manifest::load(&manifest_path)?;
    let att = Attestation::load(&att_path)?;
    let manifest_hash = manifest.hash()?;
    attestation::verify(&att, &manifest_hash)?;
    att.check_expiry(OffsetDateTime::now_utc())?;

    let manifest_artifact_hash = manifest
        .artifact_hash()
        .ok_or_else(|| anyhow!("manifest /artifact/sha256 missing"))?;
    let attested_artifact = att.artifact_hash()?;
    let expected = format!("sha256:{manifest_artifact_hash}");
    if attested_artifact != expected {
        bail!(
            "attestation artifact_hash={attested_artifact} does not match manifest artifact_hash={expected}"
        );
    }

    println!("PASS");
    println!("  server:           {}", manifest.name().unwrap_or("<unnamed>"));
    println!("  manifest hash:    {manifest_hash}");
    println!("  artifact hash:    {attested_artifact}");
    println!("  publisher key id: {}", att.publisher_key_id()?);
    println!("  required caps:");
    for c in manifest.required_capabilities() {
        println!("    - {c}");
    }
    let optional = manifest.optional_capabilities();
    if !optional.is_empty() {
        println!("  optional caps (prompt on first use):");
        for c in &optional {
            println!("    - {c}");
        }
    }

    if let Some(receipt_path) = receipt_out {
        let now = OffsetDateTime::now_utc();
        let verifier = SigningKey::generate(&mut OsRng);
        let input = ReceiptInput {
            server_name: manifest.name().unwrap_or("unknown").to_string(),
            manifest_hash: manifest_hash.clone(),
            artifact_hash: attested_artifact.to_string(),
            started_at: now - time::Duration::minutes(1),
            ended_at: now,
            tool_calls: 0,
            capability_denials: 0,
            policy_hash: codec::sha256_hex(b"default-trust-policy/v0.1"),
            denial_summary: vec![],
        };
        let receipt = receipt::build_signed(&input, &verifier)?;
        std::fs::write(&receipt_path, serialize_pretty(&receipt)?)
            .with_context(|| format!("write {}", receipt_path.display()))?;
        println!("  receipt:          {}", receipt_path.display());
    }

    Ok(())
}

fn cmd_check(manifest_path: &Path, requested: &str) -> Result<()> {
    let manifest = Manifest::load(manifest_path)?;
    let required = manifest.required_capabilities();
    let optional = manifest.optional_capabilities();
    let decision = capability::decide(&required, &optional, requested)?;
    let label = match decision {
        Decision::Allow => "ALLOW",
        Decision::Prompt => "PROMPT",
        Decision::Deny => "DENY",
    };
    println!("{label}  {requested}");
    let explanation = match decision {
        Decision::Allow => "covered by manifest /capabilities/required",
        Decision::Prompt => "declared optional — user re-grant required at first use",
        Decision::Deny => "not declared — denied by default per §5.6",
    };
    println!("  reason: {explanation}");
    Ok(())
}

fn with_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut s = path.as_os_str().to_owned();
    s.push(suffix);
    PathBuf::from(s)
}

fn serialize_pretty(v: &Value) -> Result<Vec<u8>> {
    let mut bytes = serde_json::to_vec_pretty(v).context("pretty-print JSON")?;
    bytes.push(b'\n');
    Ok(bytes)
}

fn bundled_examples_dir() -> Result<PathBuf> {
    // Try cwd-relative first (when invoked from inside proxy/), then env override.
    if let Ok(p) = std::env::var("SKILL_TRUST_PROXY_EXAMPLES") {
        return Ok(PathBuf::from(p));
    }
    let cwd_local = PathBuf::from("examples");
    if cwd_local.join("manifest.json").exists() {
        return Ok(cwd_local);
    }
    let crate_relative = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("examples");
    Ok(crate_relative)
}
