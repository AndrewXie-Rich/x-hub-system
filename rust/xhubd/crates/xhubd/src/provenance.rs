use std::env;
use std::fs;
use std::fs::OpenOptions;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{json, Value};

use crate::sha256;

const RUNTIME_SCHEMA_VERSION: &str = "xhub.rust_hub.provenance.v1";
const PACKAGE_SCHEMA_VERSION: &str = "xhub.rust_hub.package_provenance.v2";
const EMBEDDED_BUILD_PROVENANCE: &str = include_str!(env!("XHUB_BUILD_PROVENANCE_PATH"));

pub(crate) fn run(args: &[String]) -> Result<(), String> {
    match args {
        [] => print_runtime_report(),
        [flag] if flag == "--package-manifest" => print_package_manifest(),
        [flag] if flag == "--finalize-package-manifest" => finalize_package_manifest(),
        [flag] if matches!(flag.as_str(), "-h" | "--help" | "help") => {
            print_help();
            Ok(())
        }
        _ => Err(
            "usage: xhubd provenance [--package-manifest|--finalize-package-manifest]\n\
             package manifest operations must run from a packaged <root>/bin/xhubd layout"
                .to_string(),
        ),
    }
}

fn print_help() {
    println!("xhubd provenance");
    println!("  Print embedded build metadata, current binary SHA-256, and package verification");
    println!("xhubd provenance --package-manifest");
    println!("  Emit a fail-closed package manifest from <package>/bin/xhubd");
    println!("xhubd provenance --finalize-package-manifest");
    println!("  Atomically refresh only this package's binary hash after codesign");
}

fn print_runtime_report() -> Result<(), String> {
    let report = runtime_report();
    println!(
        "{}",
        serde_json::to_string_pretty(&report).map_err(|error| error.to_string())?
    );
    if report.get("ok").and_then(Value::as_bool) == Some(true) {
        Ok(())
    } else {
        Err("provenance verification failed; inspect the JSON issues field".to_string())
    }
}

fn print_package_manifest() -> Result<(), String> {
    let executable = env::current_exe()
        .map_err(|error| format!("resolve current xhubd executable for packaging: {error}"))?;
    let manifest = package_manifest_for_executable(&executable)?;
    println!(
        "{}",
        serde_json::to_string_pretty(&manifest).map_err(|error| error.to_string())?
    );
    Ok(())
}

fn finalize_package_manifest() -> Result<(), String> {
    let executable = env::current_exe()
        .map_err(|error| format!("resolve current xhubd executable for finalization: {error}"))?;
    let report = finalize_package_manifest_for_executable(&executable)?;
    println!(
        "{}",
        serde_json::to_string_pretty(&report).map_err(|error| error.to_string())?
    );
    Ok(())
}

fn runtime_report() -> Value {
    let build_provenance = match embedded_build_provenance() {
        Ok(value) => value,
        Err(error) => {
            return json!({
                "schema_version": RUNTIME_SCHEMA_VERSION,
                "ok": false,
                "issues": [format!("embedded_build_provenance_invalid:{error}")],
                "build_provenance": null,
                "artifact": null,
                "package": {
                    "required": false,
                    "status": "not_checked",
                    "verified": false
                }
            });
        }
    };

    let mut issues = Vec::new();
    let executable = match env::current_exe() {
        Ok(path) => path,
        Err(error) => {
            issues.push(format!("current_executable_unavailable:{error}"));
            PathBuf::new()
        }
    };
    let artifact = if executable.as_os_str().is_empty() {
        json!({
            "path": null,
            "binary_sha256": null,
            "binary_size_bytes": null
        })
    } else {
        match artifact_value(&executable) {
            Ok(value) => value,
            Err(error) => {
                issues.push(format!("binary_hash_unavailable:{error}"));
                json!({
                    "path": executable.display().to_string(),
                    "binary_sha256": null,
                    "binary_size_bytes": null
                })
            }
        }
    };

    let binary_sha256 = artifact.get("binary_sha256").and_then(Value::as_str);
    let binary_size_bytes = artifact.get("binary_size_bytes").and_then(Value::as_u64);
    let package = match (binary_sha256, binary_size_bytes) {
        (Some(hash), Some(size)) if !executable.as_os_str().is_empty() => {
            verify_discovered_package(&executable, hash, size, &build_provenance)
        }
        _ => json!({
            "required": false,
            "status": "not_checked",
            "verified": false,
            "issues": []
        }),
    };
    if let Some(package_issues) = package.get("issues").and_then(Value::as_array) {
        issues.extend(
            package_issues
                .iter()
                .filter_map(Value::as_str)
                .map(ToString::to_string),
        );
    }

    let embedded_complete = build_provenance
        .get("metadata_complete")
        .and_then(Value::as_bool)
        == Some(true);
    if !embedded_complete {
        issues.push("embedded_metadata_incomplete".to_string());
    }
    let package_required = package.get("required").and_then(Value::as_bool) == Some(true);
    let package_verified = package.get("verified").and_then(Value::as_bool) == Some(true);
    let ok = embedded_complete
        && artifact
            .get("binary_sha256")
            .and_then(Value::as_str)
            .is_some()
        && (!package_required || package_verified)
        && issues.is_empty();

    json!({
        "schema_version": RUNTIME_SCHEMA_VERSION,
        "ok": ok,
        "issues": issues,
        "build_provenance": build_provenance,
        "artifact": artifact,
        "package": package
    })
}

fn embedded_build_provenance() -> Result<Value, String> {
    serde_json::from_str(EMBEDDED_BUILD_PROVENANCE)
        .map_err(|error| format!("generated build manifest is not valid JSON: {error}"))
}

fn artifact_value(path: &Path) -> Result<Value, String> {
    let (hash, bytes) = sha256::file_digest_hex(path)
        .map_err(|error| format!("hash executable {}: {error}", path.display()))?;
    Ok(json!({
        "path": path.display().to_string(),
        "binary_sha256": hash,
        "binary_size_bytes": bytes
    }))
}

fn package_manifest_for_executable(executable: &Path) -> Result<Value, String> {
    let package_root = package_root_for_executable(executable).ok_or_else(|| {
        format!(
            "package manifest generation requires <package>/bin/xhubd, got {}",
            executable.display()
        )
    })?;
    let build_provenance = embedded_build_provenance()?;
    if build_provenance
        .get("metadata_complete")
        .and_then(Value::as_bool)
        != Some(true)
    {
        return Err(
            "refusing to emit package manifest because embedded build metadata is incomplete"
                .to_string(),
        );
    }
    let artifact = artifact_value(executable)?;
    let contents = verify_packaged_contents(&package_root, &build_provenance);
    if !contents.issues.is_empty() {
        return Err(format!(
            "refusing to emit package manifest: {}",
            contents.issues.join(",")
        ));
    }

    Ok(json!({
        "schema_version": PACKAGE_SCHEMA_VERSION,
        "ok": true,
        "build_provenance": build_provenance,
        "artifact": {
            "relative_path": "bin/xhubd",
            "binary_sha256": artifact["binary_sha256"],
            "binary_size_bytes": artifact["binary_size_bytes"]
        },
        "contents": contents.value()
    }))
}

fn finalize_package_manifest_for_executable(executable: &Path) -> Result<Value, String> {
    let package_root = package_root_for_executable(executable).ok_or_else(|| {
        format!(
            "package finalization requires this executable to be <package>/bin/xhubd, got {}",
            executable.display()
        )
    })?;
    let manifest_path = package_root.join("provenance.json");
    let metadata = fs::symlink_metadata(&manifest_path).map_err(|error| {
        format!(
            "existing package provenance is required at {}: {error}",
            manifest_path.display()
        )
    })?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(format!(
            "refusing to finalize non-regular package provenance: {}",
            manifest_path.display()
        ));
    }
    let existing: Value = serde_json::from_slice(
        &fs::read(&manifest_path)
            .map_err(|error| format!("read {}: {error}", manifest_path.display()))?,
    )
    .map_err(|error| format!("parse {}: {error}", manifest_path.display()))?;
    let build_provenance = embedded_build_provenance()?;
    let (finalized, previous_hash, current_hash, current_size) =
        finalized_manifest_value(&existing, &build_provenance, &package_root, executable)?;

    atomic_write_json(&manifest_path, &finalized)?;
    let verification = verify_package_manifest_value(
        &finalized,
        &manifest_path,
        &package_root,
        PackageArtifact {
            executable,
            binary_sha256: &current_hash,
            binary_size_bytes: current_size,
        },
        &build_provenance,
        true,
    );
    if verification.get("verified").and_then(Value::as_bool) != Some(true) {
        return Err(format!(
            "finalized package provenance did not verify: {}",
            verification
                .get("issues")
                .cloned()
                .unwrap_or_else(|| json!(["unknown_verification_failure"]))
        ));
    }

    Ok(json!({
        "schema_version": "xhub.rust_hub.package_provenance_finalize.v1",
        "ok": true,
        "path": manifest_path.display().to_string(),
        "binary_hash_changed": previous_hash != current_hash,
        "previous_binary_sha256": previous_hash,
        "binary_sha256": current_hash,
        "binary_size_bytes": current_size,
        "package": verification
    }))
}

fn finalized_manifest_value(
    existing: &Value,
    build_provenance: &Value,
    package_root: &Path,
    executable: &Path,
) -> Result<(Value, String, String, u64), String> {
    if existing.get("schema_version").and_then(Value::as_str) != Some(PACKAGE_SCHEMA_VERSION) {
        return Err("refusing finalization: package manifest schema mismatch".to_string());
    }
    if existing.get("ok").and_then(Value::as_bool) != Some(true) {
        return Err("refusing finalization: existing package manifest is not ok".to_string());
    }
    if existing.get("build_provenance") != Some(build_provenance) {
        return Err(
            "refusing finalization: immutable embedded source/build provenance mismatch"
                .to_string(),
        );
    }
    if existing
        .pointer("/artifact/relative_path")
        .and_then(Value::as_str)
        != Some("bin/xhubd")
        || !same_canonical_path(&package_root.join("bin/xhubd"), executable)
    {
        return Err("refusing finalization: package binary path mismatch".to_string());
    }
    let previous_hash = existing
        .pointer("/artifact/binary_sha256")
        .and_then(Value::as_str)
        .filter(|value| is_sha256_hex(value))
        .ok_or_else(|| {
            "refusing finalization: existing package binary SHA-256 is missing or invalid"
                .to_string()
        })?
        .to_string();
    if existing
        .pointer("/artifact/binary_size_bytes")
        .and_then(Value::as_u64)
        .is_none()
    {
        return Err(
            "refusing finalization: existing package binary size is missing or invalid".to_string(),
        );
    }

    let contents = verify_packaged_contents(package_root, build_provenance);
    if !contents.issues.is_empty() {
        return Err(format!(
            "refusing finalization: immutable package contents failed verification: {}",
            contents.issues.join(",")
        ));
    }
    let contents_value = contents.value();
    if existing.get("contents") != Some(&contents_value) {
        return Err(
            "refusing finalization: immutable package contents summary mismatch".to_string(),
        );
    }

    let artifact = artifact_value(executable)?;
    let current_hash = artifact["binary_sha256"]
        .as_str()
        .expect("artifact hash generated above")
        .to_string();
    let current_size = artifact["binary_size_bytes"]
        .as_u64()
        .expect("artifact size generated above");
    let mut finalized = existing.clone();
    let artifact_object = finalized
        .get_mut("artifact")
        .and_then(Value::as_object_mut)
        .ok_or_else(|| "refusing finalization: artifact object is missing".to_string())?;
    artifact_object.insert(
        "binary_sha256".to_string(),
        Value::String(current_hash.clone()),
    );
    artifact_object.insert(
        "binary_size_bytes".to_string(),
        Value::Number(current_size.into()),
    );
    Ok((finalized, previous_hash, current_hash, current_size))
}

fn atomic_write_json(path: &Path, value: &Value) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| format!("package provenance has no parent: {}", path.display()))?;
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| format!("system clock is before Unix epoch: {error}"))?
        .as_nanos();
    let temp_path = parent.join(format!(
        ".provenance.json.{}.{stamp}.tmp",
        std::process::id()
    ));
    let write_result = (|| -> Result<(), String> {
        let mut file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&temp_path)
            .map_err(|error| format!("create {}: {error}", temp_path.display()))?;
        let mut bytes = serde_json::to_vec_pretty(value).map_err(|error| error.to_string())?;
        bytes.push(b'\n');
        file.write_all(&bytes)
            .map_err(|error| format!("write {}: {error}", temp_path.display()))?;
        file.sync_all()
            .map_err(|error| format!("sync {}: {error}", temp_path.display()))?;
        fs::rename(&temp_path, path).map_err(|error| {
            format!(
                "atomically replace {} with {}: {error}",
                path.display(),
                temp_path.display()
            )
        })?;
        Ok(())
    })();
    if write_result.is_err() && temp_path.exists() {
        let _ = fs::remove_file(&temp_path);
    }
    write_result
}

fn verify_discovered_package(
    executable: &Path,
    binary_sha256: &str,
    binary_size_bytes: u64,
    build_provenance: &Value,
) -> Value {
    let explicit_manifest = env::var_os("XHUB_PROVENANCE_MANIFEST").map(PathBuf::from);
    let package_root = package_root_for_executable(executable);
    let required = explicit_manifest.is_some() || package_root.is_some();
    let manifest_path = explicit_manifest.or_else(|| {
        package_root
            .as_ref()
            .map(|root| root.join("provenance.json"))
    });
    let Some(manifest_path) = manifest_path else {
        return json!({
            "required": false,
            "status": "not_applicable",
            "verified": false,
            "path": null,
            "issues": []
        });
    };
    let manifest_metadata = fs::symlink_metadata(&manifest_path);
    if manifest_metadata.is_err() {
        return json!({
            "required": required,
            "status": "missing",
            "verified": false,
            "path": manifest_path.display().to_string(),
            "issues": ["package_manifest_missing"]
        });
    }
    let manifest_metadata = manifest_metadata.expect("checked above");
    if manifest_metadata.file_type().is_symlink() || !manifest_metadata.is_file() {
        return json!({
            "required": required,
            "status": "invalid",
            "verified": false,
            "path": manifest_path.display().to_string(),
            "issues": ["package_manifest_not_regular_file"]
        });
    }

    let package_manifest = match fs::read_to_string(&manifest_path)
        .map_err(|error| error.to_string())
        .and_then(|raw| serde_json::from_str::<Value>(&raw).map_err(|error| error.to_string()))
    {
        Ok(value) => value,
        Err(error) => {
            return json!({
                "required": required,
                "status": "invalid",
                "verified": false,
                "path": manifest_path.display().to_string(),
                "issues": [format!("package_manifest_invalid:{error}")]
            });
        }
    };

    let root = manifest_path.parent().unwrap_or_else(|| Path::new("."));
    let artifact = PackageArtifact {
        executable,
        binary_sha256,
        binary_size_bytes,
    };
    verify_package_manifest_value(
        &package_manifest,
        &manifest_path,
        root,
        artifact,
        build_provenance,
        required,
    )
}

struct PackageArtifact<'a> {
    executable: &'a Path,
    binary_sha256: &'a str,
    binary_size_bytes: u64,
}

fn verify_package_manifest_value(
    package_manifest: &Value,
    manifest_path: &Path,
    package_root: &Path,
    artifact: PackageArtifact<'_>,
    build_provenance: &Value,
    required: bool,
) -> Value {
    let mut issues = Vec::new();
    if package_manifest
        .get("schema_version")
        .and_then(Value::as_str)
        != Some(PACKAGE_SCHEMA_VERSION)
    {
        issues.push("package_manifest_schema_mismatch".to_string());
    }
    if package_manifest.get("ok").and_then(Value::as_bool) != Some(true) {
        issues.push("package_manifest_not_ok".to_string());
    }
    if package_manifest.get("build_provenance") != Some(build_provenance) {
        issues.push("package_build_provenance_mismatch".to_string());
    }
    if package_manifest
        .pointer("/artifact/binary_sha256")
        .and_then(Value::as_str)
        != Some(artifact.binary_sha256)
    {
        issues.push("package_binary_sha256_mismatch".to_string());
    }
    if package_manifest
        .pointer("/artifact/binary_size_bytes")
        .and_then(Value::as_u64)
        != Some(artifact.binary_size_bytes)
    {
        issues.push("package_binary_size_mismatch".to_string());
    }

    let relative_path = package_manifest
        .pointer("/artifact/relative_path")
        .and_then(Value::as_str);
    match relative_path {
        Some(path) if is_safe_relative_path(path) => {
            if !same_canonical_path(&package_root.join(path), artifact.executable) {
                issues.push("package_binary_path_mismatch".to_string());
            }
        }
        Some(_) => issues.push("package_binary_relative_path_unsafe".to_string()),
        None => issues.push("package_binary_relative_path_missing".to_string()),
    }

    let contents = verify_packaged_contents(package_root, build_provenance);
    let contents_value = contents.value();
    if package_manifest.get("contents") != Some(&contents_value) {
        issues.push("package_contents_summary_mismatch".to_string());
    }
    issues.extend(contents.issues.iter().cloned());
    let verified = issues.is_empty();
    json!({
        "required": required,
        "status": if verified { "verified" } else { "mismatch" },
        "verified": verified,
        "path": manifest_path.display().to_string(),
        "contents": contents_value,
        "issues": issues
    })
}

fn package_root_for_executable(executable: &Path) -> Option<PathBuf> {
    let bin_dir = executable.parent()?;
    if bin_dir.file_name().and_then(|value| value.to_str()) != Some("bin") {
        return None;
    }
    bin_dir.parent().map(Path::to_path_buf)
}

struct ContentVerification {
    migrations_expected: usize,
    migrations_verified: usize,
    capability_manifest_verified: bool,
    package_files: Vec<Value>,
    issues: Vec<String>,
}

impl ContentVerification {
    fn value(&self) -> Value {
        json!({
            "migrations_expected": self.migrations_expected,
            "migrations_verified": self.migrations_verified,
            "capability_manifest_verified": self.capability_manifest_verified,
            "package_file_count": self.package_files.len(),
            "package_files": self.package_files,
            "issues": self.issues
        })
    }
}

fn verify_packaged_contents(package_root: &Path, build_provenance: &Value) -> ContentVerification {
    let mut issues = Vec::new();
    let package_files = package_file_inventory(package_root, &mut issues);
    let migrations = build_provenance
        .get("migrations")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    if migrations.is_empty() {
        issues.push("embedded_migration_manifest_missing".to_string());
    }
    let mut migrations_verified = 0;
    for migration in &migrations {
        let Some(file_name) = migration.get("file_name").and_then(Value::as_str) else {
            issues.push("embedded_migration_filename_missing".to_string());
            continue;
        };
        if !is_safe_file_name(file_name) {
            issues.push(format!("embedded_migration_filename_unsafe:{file_name}"));
            continue;
        }
        let Some(expected_hash) = migration.get("sha256").and_then(Value::as_str) else {
            issues.push(format!("embedded_migration_hash_missing:{file_name}"));
            continue;
        };
        let path = package_root.join("migrations").join(file_name);
        match sha256::file_digest_hex(&path) {
            Ok((actual_hash, _)) if actual_hash == expected_hash => migrations_verified += 1,
            Ok(_) => issues.push(format!("package_migration_sha256_mismatch:{file_name}")),
            Err(error) => issues.push(format!("package_migration_unavailable:{file_name}:{error}")),
        }
    }

    let capability_source = build_provenance
        .pointer("/capability_manifest/source_file")
        .and_then(Value::as_str);
    let capability_hash = build_provenance
        .pointer("/capability_manifest/sha256")
        .and_then(Value::as_str);
    let capability_manifest_verified = match (capability_source, capability_hash) {
        (Some(source), Some(expected_hash)) if is_safe_relative_path(source) => {
            match sha256::file_digest_hex(&package_root.join(source)) {
                Ok((actual_hash, _)) if actual_hash == expected_hash => true,
                Ok(_) => {
                    issues.push("package_capability_manifest_sha256_mismatch".to_string());
                    false
                }
                Err(error) => {
                    issues.push(format!("package_capability_manifest_unavailable:{error}"));
                    false
                }
            }
        }
        (Some(_), Some(_)) => {
            issues.push("embedded_capability_manifest_path_unsafe".to_string());
            false
        }
        _ => {
            issues.push("embedded_capability_manifest_metadata_missing".to_string());
            false
        }
    };

    ContentVerification {
        migrations_expected: migrations.len(),
        migrations_verified,
        capability_manifest_verified,
        package_files,
        issues,
    }
}

fn package_file_inventory(package_root: &Path, issues: &mut Vec<String>) -> Vec<Value> {
    let mut files = Vec::<Value>::new();
    collect_package_files(package_root, package_root, &mut files, issues);
    files.sort_by(|left, right| {
        left.get("relative_path")
            .and_then(Value::as_str)
            .cmp(&right.get("relative_path").and_then(Value::as_str))
    });
    files
}

fn collect_package_files(
    package_root: &Path,
    directory: &Path,
    files: &mut Vec<Value>,
    issues: &mut Vec<String>,
) {
    let entries = match fs::read_dir(directory) {
        Ok(entries) => entries,
        Err(error) => {
            issues.push(format!(
                "package_inventory_directory_unavailable:{}:{error}",
                directory.display()
            ));
            return;
        }
    };
    let mut paths = Vec::new();
    for entry in entries {
        match entry {
            Ok(entry) => paths.push(entry.path()),
            Err(error) => issues.push(format!("package_inventory_entry_unavailable:{error}")),
        }
    }
    paths.sort();

    for path in paths {
        let relative = match path.strip_prefix(package_root) {
            Ok(relative) => relative,
            Err(_) => {
                issues.push(format!("package_inventory_path_escaped:{}", path.display()));
                continue;
            }
        };
        let Some(relative_path) = relative.to_str() else {
            issues.push("package_inventory_non_utf8_path".to_string());
            continue;
        };
        let relative_path = relative_path.replace(std::path::MAIN_SEPARATOR, "/");
        if matches!(relative_path.as_str(), "provenance.json" | "bin/xhubd") {
            continue;
        }

        let metadata = match fs::symlink_metadata(&path) {
            Ok(metadata) => metadata,
            Err(error) => {
                issues.push(format!(
                    "package_inventory_metadata_unavailable:{relative_path}:{error}"
                ));
                continue;
            }
        };
        if metadata.file_type().is_symlink() {
            issues.push(format!(
                "package_inventory_symlink_forbidden:{relative_path}"
            ));
        } else if metadata.is_dir() {
            collect_package_files(package_root, &path, files, issues);
        } else if metadata.is_file() {
            match sha256::file_digest_hex(&path) {
                Ok((sha256, bytes)) => files.push(json!({
                    "relative_path": relative_path,
                    "sha256": sha256,
                    "bytes": bytes,
                })),
                Err(error) => issues.push(format!(
                    "package_inventory_hash_unavailable:{relative_path}:{error}"
                )),
            }
        } else {
            issues.push(format!(
                "package_inventory_unsupported_file_type:{relative_path}"
            ));
        }
    }
}

fn is_safe_file_name(value: &str) -> bool {
    !value.is_empty()
        && Path::new(value).file_name().and_then(|name| name.to_str()) == Some(value)
        && !matches!(value, "." | "..")
}

fn is_sha256_hex(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn is_safe_relative_path(value: &str) -> bool {
    let path = Path::new(value);
    !value.is_empty()
        && !path.is_absolute()
        && path.components().all(|component| {
            matches!(
                component,
                std::path::Component::Normal(_) | std::path::Component::CurDir
            )
        })
}

fn same_canonical_path(left: &Path, right: &Path) -> bool {
    match (left.canonicalize(), right.canonicalize()) {
        (Ok(left), Ok(right)) => left == right,
        _ => left == right,
    }
}

#[cfg(test)]
mod tests {
    use super::{
        atomic_write_json, embedded_build_provenance, finalized_manifest_value, is_safe_file_name,
        is_safe_relative_path, package_root_for_executable, verify_packaged_contents,
        PACKAGE_SCHEMA_VERSION,
    };
    use crate::sha256;
    use serde_json::{json, Value};
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn embedded_manifest_has_release_identity_fields() {
        let manifest = embedded_build_provenance().expect("embedded build provenance");
        assert_eq!(
            manifest.get("schema_version").and_then(Value::as_str),
            Some("xhub.rust_hub.build_provenance.v1")
        );
        assert!(manifest
            .pointer("/source/root")
            .and_then(Value::as_str)
            .is_some());
        assert!(manifest
            .pointer("/source/git_commit")
            .and_then(Value::as_str)
            .is_some());
        assert!(manifest.pointer("/source/git_dirty").is_some());
        assert!(manifest
            .pointer("/build/timestamp_unix_seconds")
            .and_then(Value::as_u64)
            .is_some());
        assert!(manifest
            .pointer("/target/triple")
            .and_then(Value::as_str)
            .is_some());
        assert!(manifest
            .get("migrations")
            .and_then(Value::as_array)
            .is_some_and(|migrations| !migrations.is_empty()));
        assert_eq!(
            manifest
                .pointer("/capability_manifest/manifest/schema_version")
                .and_then(Value::as_str),
            Some("xhub.rust_hub.capabilities.v1")
        );
    }

    #[test]
    fn package_layout_and_relative_paths_are_fail_closed() {
        assert_eq!(
            package_root_for_executable(Path::new("/opt/xhub/rust-hub/bin/xhubd")),
            Some(Path::new("/opt/xhub/rust-hub").to_path_buf())
        );
        assert_eq!(
            package_root_for_executable(Path::new("/opt/xhub/target/release/xhubd")),
            None
        );
        assert!(is_safe_file_name("0001_runtime.sql"));
        assert!(!is_safe_file_name("../0001_runtime.sql"));
        assert!(is_safe_relative_path("provenance/capabilities.json"));
        assert!(!is_safe_relative_path("../capabilities.json"));
        assert!(!is_safe_relative_path("/tmp/capabilities.json"));
        assert_eq!(
            PACKAGE_SCHEMA_VERSION,
            "xhub.rust_hub.package_provenance.v2"
        );
    }

    #[test]
    fn packaged_content_hashes_detect_tampering() {
        let root = unique_temp_dir("xhub-provenance-content");
        fs::create_dir_all(root.join("migrations")).expect("create migrations directory");
        fs::create_dir_all(root.join("provenance")).expect("create provenance directory");
        let migration = b"CREATE TABLE provenance_test(id INTEGER);\n";
        let capabilities = br#"{"schema_version":"test"}"#;
        fs::write(root.join("migrations/0001_test.sql"), migration).expect("write migration");
        fs::write(root.join("provenance/capabilities.json"), capabilities)
            .expect("write capability manifest");
        let build = json!({
            "migrations": [{
                "file_name": "0001_test.sql",
                "sha256": sha256::digest_hex(migration)
            }],
            "capability_manifest": {
                "source_file": "provenance/capabilities.json",
                "sha256": sha256::digest_hex(capabilities)
            }
        });

        let verified = verify_packaged_contents(&root, &build);
        assert!(verified.issues.is_empty());
        assert_eq!(verified.migrations_verified, 1);
        assert!(verified.capability_manifest_verified);
        assert_eq!(verified.package_files.len(), 2);
        assert!(verified.package_files.iter().any(|file| {
            file["relative_path"] == "migrations/0001_test.sql"
                && file["sha256"] == sha256::digest_hex(migration)
        }));

        let original_inventory = verified.value()["package_files"].clone();
        fs::write(root.join("docs.txt"), b"unexpected package addition\n")
            .expect("write additional package file");
        let with_extra = verify_packaged_contents(&root, &build);
        assert_ne!(with_extra.value()["package_files"], original_inventory);
        fs::remove_file(root.join("docs.txt")).expect("remove additional package file");

        fs::write(root.join("migrations/0001_test.sql"), b"tampered\n").expect("tamper migration");
        let tampered = verify_packaged_contents(&root, &build);
        assert_eq!(tampered.migrations_verified, 0);
        assert!(tampered
            .issues
            .iter()
            .any(|issue| issue == "package_migration_sha256_mismatch:0001_test.sql"));

        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(
                root.join("provenance/capabilities.json"),
                root.join("provenance/forbidden-link.json"),
            )
            .expect("write forbidden symlink");
            let symlinked = verify_packaged_contents(&root, &build);
            assert!(symlinked.issues.iter().any(|issue| issue
                == "package_inventory_symlink_forbidden:provenance/forbidden-link.json"));
        }

        fs::remove_dir_all(root).expect("remove provenance test directory");
    }

    #[test]
    fn finalization_changes_only_binary_identity_fields() {
        let root = unique_temp_dir("xhub-provenance-finalize");
        fs::create_dir_all(root.join("bin")).expect("create bin directory");
        fs::create_dir_all(root.join("migrations")).expect("create migrations directory");
        fs::create_dir_all(root.join("provenance")).expect("create provenance directory");
        let executable = root.join("bin/xhubd");
        let binary = b"post-codesign-binary";
        let migration = b"CREATE TABLE finalize_test(id INTEGER);\n";
        let capabilities = br#"{"schema_version":"test"}"#;
        fs::write(&executable, binary).expect("write binary");
        fs::write(root.join("migrations/0001_test.sql"), migration).expect("write migration");
        fs::write(root.join("provenance/capabilities.json"), capabilities)
            .expect("write capability manifest");
        let build = json!({
            "schema_version": "xhub.rust_hub.build_provenance.v1",
            "metadata_complete": true,
            "source": {"git_commit": "0123456789012345678901234567890123456789"},
            "migrations": [{
                "file_name": "0001_test.sql",
                "sha256": sha256::digest_hex(migration)
            }],
            "capability_manifest": {
                "source_file": "provenance/capabilities.json",
                "sha256": sha256::digest_hex(capabilities)
            }
        });
        let contents = verify_packaged_contents(&root, &build).value();
        let old_hash = "0".repeat(64);
        let existing = json!({
            "schema_version": PACKAGE_SCHEMA_VERSION,
            "ok": true,
            "build_provenance": build,
            "artifact": {
                "relative_path": "bin/xhubd",
                "binary_sha256": old_hash,
                "binary_size_bytes": 1
            },
            "contents": contents,
            "release_metadata": {"channel": "test"}
        });

        let (finalized, previous_hash, current_hash, current_size) =
            finalized_manifest_value(&existing, &build, &root, &executable)
                .expect("finalize manifest value");
        assert_eq!(previous_hash, "0".repeat(64));
        assert_eq!(current_hash, sha256::digest_hex(binary));
        assert_eq!(current_size, binary.len() as u64);
        assert_eq!(finalized["build_provenance"], existing["build_provenance"]);
        assert_eq!(finalized["contents"], existing["contents"]);
        assert_eq!(finalized["release_metadata"], existing["release_metadata"]);
        assert_eq!(finalized["artifact"]["relative_path"], "bin/xhubd");
        assert_eq!(finalized["artifact"]["binary_sha256"], current_hash);
        assert_eq!(finalized["artifact"]["binary_size_bytes"], current_size);

        let mut mismatched = existing.clone();
        mismatched["build_provenance"]["source"]["git_commit"] = json!("tampered");
        let error = finalized_manifest_value(&mismatched, &build, &root, &executable)
            .expect_err("immutable build mismatch must fail");
        assert!(error.contains("immutable embedded source/build provenance mismatch"));

        fs::remove_dir_all(root).expect("remove finalization test directory");
    }

    #[test]
    fn package_manifest_write_replaces_atomically() {
        let root = unique_temp_dir("xhub-provenance-atomic");
        fs::create_dir_all(&root).expect("create atomic test directory");
        let path = root.join("provenance.json");
        fs::write(&path, b"{\"old\":true}\n").expect("write old manifest");
        let replacement = json!({"new": true});
        atomic_write_json(&path, &replacement).expect("atomic manifest write");
        let actual: Value =
            serde_json::from_slice(&fs::read(&path).expect("read replaced manifest"))
                .expect("parse replaced manifest");
        assert_eq!(actual, replacement);
        assert_eq!(
            fs::read_dir(&root)
                .expect("read atomic test directory")
                .count(),
            1
        );
        fs::remove_dir_all(root).expect("remove atomic test directory");
    }

    fn unique_temp_dir(prefix: &str) -> PathBuf {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("time after Unix epoch")
            .as_nanos();
        std::env::temp_dir().join(format!("{prefix}-{}-{stamp}", std::process::id()))
    }
}
