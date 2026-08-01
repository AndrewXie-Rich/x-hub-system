use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::Value;

#[test]
fn version_output_remains_backwards_compatible() {
    let output = Command::new(env!("CARGO_BIN_EXE_xhubd"))
        .arg("version")
        .output()
        .expect("run xhubd version");
    assert!(output.status.success());
    assert_eq!(
        String::from_utf8(output.stdout).expect("version UTF-8"),
        format!("xhubd {}\n", env!("CARGO_PKG_VERSION"))
    );
}

#[test]
fn provenance_reports_embedded_identity_and_runtime_binary_hash() {
    let output = Command::new(env!("CARGO_BIN_EXE_xhubd"))
        .arg("provenance")
        .output()
        .expect("run xhubd provenance");
    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let value: Value = serde_json::from_slice(&output.stdout).expect("provenance JSON");
    assert_eq!(value["schema_version"], "xhub.rust_hub.provenance.v1");
    assert_eq!(value["ok"], true);
    assert_eq!(
        value["build_provenance"]["schema_version"],
        "xhub.rust_hub.build_provenance.v1"
    );
    assert_eq!(
        value["build_provenance"]["capability_manifest"]["manifest"]["schema_version"],
        "xhub.rust_hub.capabilities.v1"
    );
    let binary_hash = value["artifact"]["binary_sha256"]
        .as_str()
        .expect("binary SHA-256");
    assert_eq!(binary_hash.len(), 64);
    assert!(binary_hash.bytes().all(|byte| byte.is_ascii_hexdigit()));
    assert!(value["build_provenance"]["migrations"]
        .as_array()
        .is_some_and(|migrations| migrations.len() >= 9));
}

#[test]
fn finalize_package_manifest_is_self_scoped_and_preserves_build_identity() {
    let source_root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .expect("Rust Hub workspace root");
    let package_root = unique_temp_dir("xhub-provenance-cli-finalize");
    fs::create_dir_all(package_root.join("bin")).expect("create package bin");
    fs::create_dir_all(package_root.join("migrations")).expect("create package migrations");
    fs::create_dir_all(package_root.join("provenance")).expect("create package provenance");
    let packaged_binary = package_root.join("bin/xhubd");
    fs::copy(env!("CARGO_BIN_EXE_xhubd"), &packaged_binary).expect("copy packaged xhubd");
    for entry in fs::read_dir(source_root.join("migrations")).expect("read source migrations") {
        let path = entry.expect("migration entry").path();
        if path.extension().and_then(|value| value.to_str()) == Some("sql") {
            fs::copy(
                &path,
                package_root
                    .join("migrations")
                    .join(path.file_name().expect("migration filename")),
            )
            .expect("copy migration");
        }
    }
    fs::copy(
        source_root.join("provenance/capabilities.json"),
        package_root.join("provenance/capabilities.json"),
    )
    .expect("copy capability manifest");

    let initial_output = Command::new(&packaged_binary)
        .args(["provenance", "--package-manifest"])
        .output()
        .expect("emit initial package manifest");
    assert!(
        initial_output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&initial_output.stderr)
    );
    let mut initial: Value =
        serde_json::from_slice(&initial_output.stdout).expect("initial package JSON");
    let immutable_build = initial["build_provenance"].clone();
    initial["artifact"]["binary_sha256"] = Value::String("0".repeat(64));
    initial["artifact"]["binary_size_bytes"] = Value::Number(1_u64.into());
    initial["release_metadata"] = serde_json::json!({"channel": "integration-test"});
    fs::write(
        package_root.join("provenance.json"),
        serde_json::to_vec_pretty(&initial).expect("serialize initial package manifest"),
    )
    .expect("write initial package manifest");

    let finalize_output = Command::new(&packaged_binary)
        .args(["provenance", "--finalize-package-manifest"])
        .output()
        .expect("finalize package manifest");
    assert!(
        finalize_output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&finalize_output.stderr)
    );
    let finalize_report: Value =
        serde_json::from_slice(&finalize_output.stdout).expect("finalize report JSON");
    assert_eq!(finalize_report["ok"], true);
    assert_eq!(finalize_report["binary_hash_changed"], true);

    let finalized: Value = serde_json::from_slice(
        &fs::read(package_root.join("provenance.json")).expect("read finalized manifest"),
    )
    .expect("parse finalized manifest");
    assert_eq!(finalized["build_provenance"], immutable_build);
    assert_eq!(finalized["contents"], initial["contents"]);
    assert_eq!(finalized["release_metadata"], initial["release_metadata"]);
    assert_ne!(finalized["artifact"]["binary_sha256"], "0".repeat(64));

    let verify_output = Command::new(&packaged_binary)
        .arg("provenance")
        .output()
        .expect("verify finalized package");
    assert!(
        verify_output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&verify_output.stderr)
    );
    let verified: Value =
        serde_json::from_slice(&verify_output.stdout).expect("verified package JSON");
    assert_eq!(verified["package"]["status"], "verified");

    fs::remove_dir_all(package_root).expect("remove CLI finalization package");
}

#[test]
fn finalize_refuses_non_package_binary_layout() {
    let output = Command::new(env!("CARGO_BIN_EXE_xhubd"))
        .args(["provenance", "--finalize-package-manifest"])
        .output()
        .expect("run finalize outside package layout");
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("<package>/bin/xhubd"));
}

fn unique_temp_dir(prefix: &str) -> PathBuf {
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("time after Unix epoch")
        .as_nanos();
    std::env::temp_dir().join(format!("{prefix}-{}-{stamp}", std::process::id()))
}
