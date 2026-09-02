#[path = "src/sha256.rs"]
mod sha256;

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{json, Value};

const BUILD_SCHEMA_VERSION: &str = "xhub.rust_hub.build_provenance.v1";
const CAPABILITY_SCHEMA_VERSION: &str = "xhub.rust_hub.capabilities.v1";

fn main() {
    let manifest_dir = required_path_env("CARGO_MANIFEST_DIR");
    let source_root = manifest_dir
        .parent()
        .and_then(Path::parent)
        .expect("xhubd crate must live under <workspace>/crates/xhubd")
        .canonicalize()
        .expect("canonicalize Rust Hub source root");
    let out_dir = required_path_env("OUT_DIR");

    emit_rebuild_inputs(&source_root);

    let mut issues = Vec::new();
    let repository_root = git_output(&source_root, &["rev-parse", "--show-toplevel"])
        .map(PathBuf::from)
        .map(|path| path.canonicalize().unwrap_or(path))
        .map_err(|error| issues.push(format!("git_repository_root_unavailable:{error}")))
        .ok();

    if let Some(root) = repository_root.as_deref() {
        emit_git_rebuild_inputs(root);
    }

    let git_commit = repository_root.as_deref().and_then(|root| {
        match git_output(root, &["rev-parse", "HEAD"]) {
            Ok(commit) if is_hex_commit(&commit) => Some(commit),
            Ok(_) => {
                issues.push("git_commit_invalid".to_string());
                None
            }
            Err(error) => {
                issues.push(format!("git_commit_unavailable:{error}"));
                None
            }
        }
    });
    let git_dirty = repository_root.as_deref().and_then(|root| {
        match git_output(
            root,
            &["status", "--porcelain=v1", "--untracked-files=normal"],
        ) {
            Ok(status) => Some(!status.is_empty()),
            Err(error) => {
                issues.push(format!("git_dirty_unavailable:{error}"));
                None
            }
        }
    });

    let (build_timestamp_unix_seconds, build_timestamp_source) = build_timestamp();
    let migrations = migration_manifest(&source_root);
    let (capability_manifest, capability_sha256, capability_bytes) =
        capability_manifest(&source_root);

    let target_triple = required_build_env("TARGET", &mut issues);
    let target_arch = required_build_env("CARGO_CFG_TARGET_ARCH", &mut issues);
    let target_os = required_build_env("CARGO_CFG_TARGET_OS", &mut issues);
    let target_env = optional_build_env("CARGO_CFG_TARGET_ENV");
    let profile = required_build_env("PROFILE", &mut issues);
    let rustc_version = rustc_version().map_err(|error| {
        issues.push(format!("rustc_version_unavailable:{error}"));
    });
    let rustc_version = rustc_version.ok();

    let manifest = json!({
        "schema_version": BUILD_SCHEMA_VERSION,
        "metadata_complete": issues.is_empty(),
        "issues": issues,
        "daemon": {
            "name": env::var("CARGO_PKG_NAME").unwrap_or_else(|_| "xhubd".to_string()),
            "version": env::var("CARGO_PKG_VERSION").unwrap_or_else(|_| "unavailable".to_string())
        },
        "source": {
            "root": source_root.display().to_string(),
            "repository_root": repository_root.as_ref().map(|path| path.display().to_string()),
            "git_commit": git_commit,
            "git_dirty": git_dirty,
            "git_scope": "enclosing_repository"
        },
        "build": {
            "timestamp_unix_seconds": build_timestamp_unix_seconds,
            "timestamp_source": build_timestamp_source,
            "profile": profile,
            "rustc_version": rustc_version
        },
        "target": {
            "triple": target_triple,
            "arch": target_arch,
            "os": target_os,
            "environment": target_env
        },
        "migrations": migrations,
        "capability_manifest": {
            "source_file": "provenance/capabilities.json",
            "sha256": capability_sha256,
            "bytes": capability_bytes,
            "manifest": capability_manifest
        }
    });

    let output_path = out_dir.join("xhubd_build_provenance.json");
    let output = serde_json::to_vec_pretty(&manifest).expect("serialize build provenance");
    fs::write(&output_path, output).expect("write generated build provenance");
    println!(
        "cargo:rustc-env=XHUB_BUILD_PROVENANCE_PATH={}",
        output_path.display()
    );
}

fn required_path_env(name: &str) -> PathBuf {
    env::var_os(name)
        .map(PathBuf::from)
        .unwrap_or_else(|| panic!("required build environment variable {name} is unavailable"))
}

fn emit_rebuild_inputs(source_root: &Path) {
    println!("cargo:rerun-if-env-changed=SOURCE_DATE_EPOCH");
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=src");
    println!(
        "cargo:rerun-if-changed={}",
        source_root.join("Cargo.toml").display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        source_root.join("Cargo.lock").display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        source_root.join("crates").display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        source_root.join("migrations").display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        source_root.join("provenance/capabilities.json").display()
    );
}

fn emit_git_rebuild_inputs(repository_root: &Path) {
    let git_dir = repository_root.join(".git");
    println!("cargo:rerun-if-changed={}", git_dir.join("HEAD").display());
    println!("cargo:rerun-if-changed={}", git_dir.join("index").display());
    if let Ok(head) = fs::read_to_string(git_dir.join("HEAD")) {
        if let Some(reference) = head.trim().strip_prefix("ref: ") {
            println!(
                "cargo:rerun-if-changed={}",
                git_dir.join(reference).display()
            );
        }
    }
}

fn git_output(working_dir: &Path, args: &[&str]) -> Result<String, String> {
    let output = Command::new("git")
        .current_dir(working_dir)
        .args(args)
        .output()
        .map_err(|error| error.to_string())?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(if stderr.is_empty() {
            format!("git exited with {}", output.status)
        } else {
            stderr
        });
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn is_hex_commit(value: &str) -> bool {
    value.len() >= 40 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn build_timestamp() -> (u64, &'static str) {
    if let Ok(raw) = env::var("SOURCE_DATE_EPOCH") {
        let value = raw
            .trim()
            .parse::<u64>()
            .unwrap_or_else(|_| panic!("SOURCE_DATE_EPOCH must be an unsigned Unix timestamp"));
        return (value, "SOURCE_DATE_EPOCH");
    }
    let value = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock is before Unix epoch")
        .as_secs();
    (value, "system_clock")
}

fn migration_manifest(source_root: &Path) -> Vec<Value> {
    let migration_dir = source_root.join("migrations");
    let mut paths = fs::read_dir(&migration_dir)
        .unwrap_or_else(|error| {
            panic!(
                "read migrations directory {}: {error}",
                migration_dir.display()
            )
        })
        .map(|entry| entry.expect("read migration directory entry").path())
        .filter(|path| path.extension().and_then(|value| value.to_str()) == Some("sql"))
        .collect::<Vec<_>>();
    paths.sort();
    assert!(
        !paths.is_empty(),
        "no SQL migrations found under {}",
        migration_dir.display()
    );

    paths
        .into_iter()
        .map(|path| {
            println!("cargo:rerun-if-changed={}", path.display());
            let bytes = fs::read(&path)
                .unwrap_or_else(|error| panic!("read migration {}: {error}", path.display()));
            json!({
                "file_name": path
                    .file_name()
                    .and_then(|value| value.to_str())
                    .expect("migration filename must be UTF-8"),
                "sha256": sha256::digest_hex(&bytes),
                "bytes": bytes.len()
            })
        })
        .collect()
}

fn capability_manifest(source_root: &Path) -> (Value, String, usize) {
    let path = source_root.join("provenance/capabilities.json");
    let bytes = fs::read(&path)
        .unwrap_or_else(|error| panic!("read capability manifest {}: {error}", path.display()));
    let manifest: Value = serde_json::from_slice(&bytes)
        .unwrap_or_else(|error| panic!("parse capability manifest {}: {error}", path.display()));
    assert_eq!(
        manifest.get("schema_version").and_then(Value::as_str),
        Some(CAPABILITY_SCHEMA_VERSION),
        "capability manifest schema must be {CAPABILITY_SCHEMA_VERSION}"
    );
    assert!(
        manifest.get("capabilities").is_some_and(Value::is_object),
        "capability manifest must contain a capabilities object"
    );
    assert!(
        manifest
            .get("cli_commands")
            .and_then(Value::as_array)
            .is_some_and(|commands| commands.iter().any(|value| value == "provenance")),
        "capability manifest must list the provenance command"
    );
    let hash = sha256::digest_hex(&bytes);
    (manifest, hash, bytes.len())
}

fn required_build_env(name: &str, issues: &mut Vec<String>) -> Option<String> {
    match env::var(name) {
        Ok(value) if !value.trim().is_empty() => Some(value),
        _ => {
            issues.push(format!("build_environment_unavailable:{name}"));
            None
        }
    }
}

fn optional_build_env(name: &str) -> Option<String> {
    env::var(name).ok().filter(|value| !value.trim().is_empty())
}

fn rustc_version() -> Result<String, String> {
    let rustc = env::var_os("RUSTC").unwrap_or_else(|| "rustc".into());
    let output = Command::new(rustc)
        .arg("--version")
        .output()
        .map_err(|error| error.to_string())?;
    if !output.status.success() {
        return Err(format!("rustc exited with {}", output.status));
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}
