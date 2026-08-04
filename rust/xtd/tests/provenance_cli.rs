use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::Value;

struct TestRoot(PathBuf);

impl TestRoot {
    fn new() -> Self {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("test clock")
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "xtd-provenance-cli-test-{}-{stamp}",
            std::process::id()
        ));
        fs::create_dir_all(path.join("X-Terminal.app/Contents/MacOS"))
            .expect("create Swift fixture parent");
        fs::create_dir_all(path.join("X-Terminal.app/Contents/Resources"))
            .expect("create xtd fixture parent");
        Self(path)
    }
}

impl Drop for TestRoot {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn repository_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|path| path.parent())
        .expect("xtd must live under <repository>/rust/xtd")
        .to_path_buf()
}

fn verify(root: &TestRoot, manifest_path: &Path) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_xtd"))
        .args([
            "provenance",
            "verify",
            "--manifest",
            manifest_path.to_str().unwrap(),
            "--artifact-root",
            root.0.to_str().unwrap(),
        ])
        .output()
        .expect("run provenance verify")
}

fn issues(output: &std::process::Output) -> Vec<String> {
    serde_json::from_slice::<Value>(&output.stdout).expect("parse verification report")["issues"]
        .as_array()
        .expect("verification issues")
        .iter()
        .filter_map(Value::as_str)
        .map(ToString::to_string)
        .collect()
}

#[test]
fn cli_creates_verifies_and_rejects_tampered_detached_manifest() {
    let root = TestRoot::new();
    let swift_path = root.0.join("X-Terminal.app/Contents/MacOS/XTerminal");
    let xtd_path = root.0.join("X-Terminal.app/Contents/Resources/xtd");
    let manifest_path = root.0.join("X-Terminal.provenance.json");
    fs::write(&swift_path, b"signed-swift-fixture").expect("write Swift fixture");
    fs::write(&xtd_path, b"signed-xtd-fixture").expect("write xtd fixture");
    let info_plist = root.0.join("X-Terminal.app/Contents/Info.plist");
    fs::write(&info_plist, b"signed-resource-fixture").expect("write inventory fixture");

    let create = Command::new(env!("CARGO_BIN_EXE_xtd"))
        .args([
            "provenance",
            "create",
            "--manifest",
            manifest_path.to_str().unwrap(),
            "--repository-root",
            repository_root().to_str().unwrap(),
            "--artifact-root",
            root.0.to_str().unwrap(),
            "--swift-path",
            "X-Terminal.app/Contents/MacOS/XTerminal",
            "--xtd-path",
            "X-Terminal.app/Contents/Resources/xtd",
            "--inventory-root",
            "X-Terminal.app",
        ])
        .output()
        .expect("run provenance create");
    assert!(
        create.status.success(),
        "create stderr: {}",
        String::from_utf8_lossy(&create.stderr)
    );

    let manifest: Value =
        serde_json::from_slice(&fs::read(&manifest_path).expect("read detached manifest"))
            .expect("parse detached manifest");
    assert_eq!(
        manifest["schema_version"],
        "xhub.xterminal.artifact_provenance.v1"
    );
    assert_eq!(manifest["component"]["canonical_source_root"], "x-terminal");
    assert_eq!(
        manifest["component"]["sidecar"]["canonical_source_root"],
        "rust/xtd"
    );
    assert_eq!(manifest["artifacts"].as_array().unwrap().len(), 2);
    assert_eq!(manifest["inventory"]["files"].as_array().unwrap().len(), 3);

    let initial_verify = Command::new(env!("CARGO_BIN_EXE_xtd"))
        .args([
            "provenance",
            "verify",
            "--manifest",
            manifest_path.to_str().unwrap(),
            "--artifact-root",
            root.0.to_str().unwrap(),
            "--repository-root",
            repository_root().to_str().unwrap(),
        ])
        .output()
        .expect("run provenance verify");
    assert!(
        initial_verify.status.success(),
        "verify stderr: {}",
        String::from_utf8_lossy(&initial_verify.stderr)
    );

    fs::write(&xtd_path, b"tampered-xtd-fixture").expect("tamper xtd fixture");
    let tampered = verify(&root, &manifest_path);
    assert!(!tampered.status.success());
    assert!(issues(&tampered)
        .iter()
        .any(|issue| issue == "artifact_sha256_mismatch:xtd_sidecar"));

    fs::write(&xtd_path, b"signed-xtd-fixture").expect("restore xtd fixture");
    let extra_path = root.0.join("X-Terminal.app/Contents/Resources/extra.bin");
    fs::write(&extra_path, b"unlisted").expect("write unlisted fixture");
    let extra = verify(&root, &manifest_path);
    assert!(!extra.status.success());
    assert!(issues(&extra)
        .iter()
        .any(|issue| issue
            .ends_with("inventory_file_extra:X-Terminal.app/Contents/Resources/extra.bin")));
    fs::remove_file(&extra_path).expect("remove unlisted fixture");

    fs::remove_file(&info_plist).expect("remove inventoried fixture");
    let missing = verify(&root, &manifest_path);
    assert!(!missing.status.success());
    assert!(issues(&missing)
        .iter()
        .any(|issue| issue.ends_with("inventory_file_missing:X-Terminal.app/Contents/Info.plist")));
    fs::write(&info_plist, b"signed-resource-fixture").expect("restore inventory fixture");

    #[cfg(unix)]
    {
        use std::os::unix::fs::symlink;

        let symlink_path = root
            .0
            .join("X-Terminal.app/Contents/Resources/forbidden-link");
        symlink(&info_plist, &symlink_path).expect("create forbidden inventory symlink");
        let symlinked = verify(&root, &manifest_path);
        assert!(!symlinked.status.success());
        assert!(issues(&symlinked)
            .iter()
            .any(|issue| issue.contains("inventory contains forbidden symlink")));
    }
}
