use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Component, Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{json, Value};

use crate::sha256;

const MANIFEST_SCHEMA_VERSION: &str = "xhub.xterminal.artifact_provenance.v1";
const VERIFICATION_SCHEMA_VERSION: &str = "xhub.xterminal.artifact_provenance_verification.v1";
const COMPONENT_NAME: &str = "x-terminal";
const COMPONENT_ROOT: &str = "x-terminal";
const SIDECAR_NAME: &str = "xtd";
const SIDECAR_ROOT: &str = "rust/xtd";
const BUILD_INVENTORY_ROOT: &str = "X-Terminal.app";
const BUILD_MANIFEST_PATH: &str = "X-Terminal.provenance.json";
const PACKAGE_INVENTORY_ROOT: &str = ".";
const PACKAGE_MANIFEST_PATH: &str = "provenance.json";
const BUILD_SWIFT_PATH: &str = "X-Terminal.app/Contents/MacOS/XTerminal";
const BUILD_XTD_PATH: &str = "X-Terminal.app/Contents/Resources/xtd";
const PACKAGE_SWIFT_PATH: &str = "app/X-Terminal.app/Contents/MacOS/XTerminal";
const PACKAGE_XTD_PATH: &str = "app/X-Terminal.app/Contents/Resources/xtd";
const PACKAGE_STANDALONE_XTD_PATH: &str = "bin/xtd";
const MAX_MANIFEST_BYTES: u64 = 1024 * 1024;

#[derive(Debug)]
struct CreateOptions {
    manifest_path: PathBuf,
    repository_root: PathBuf,
    artifact_root: PathBuf,
    swift_path: String,
    xtd_path: String,
    packaged_xtd_path: Option<String>,
    inventory_root: String,
    source_date_epoch: Option<u64>,
    release: bool,
}

#[derive(Debug)]
struct VerifyOptions {
    manifest_path: PathBuf,
    artifact_root: PathBuf,
    repository_root: Option<PathBuf>,
    require_release: bool,
}

#[derive(Debug, Clone)]
struct SourceIdentity {
    git_commit: String,
    git_dirty: bool,
    git_commit_timestamp: u64,
}

#[derive(Debug, Clone, Copy)]
struct ArtifactLayout<'a> {
    swift_path: &'a str,
    xtd_path: &'a str,
    packaged_xtd_path: Option<&'a str>,
    inventory_root: &'a str,
    manifest_relative_path: &'a str,
}

pub(crate) fn run(args: &[String]) -> Result<(), String> {
    match args.first().map(String::as_str) {
        Some("create") => create(parse_create_options(&args[1..])?),
        Some("verify") => verify(parse_verify_options(&args[1..])?),
        Some("help" | "--help" | "-h") => {
            print_help();
            Ok(())
        }
        _ => Err(usage()),
    }
}

fn print_help() {
    println!("{}", usage());
}

fn usage() -> String {
    concat!(
        "usage:\n",
        "  xtd provenance create --manifest <path> --repository-root <path> \\\n",
        "    --artifact-root <path> --swift-path <relative-path> --xtd-path <relative-path> \\\n",
        "    --inventory-root <relative-path|.> \\\n",
        "    [--packaged-xtd-path <relative-path>] [--source-date-epoch <seconds>] [--release]\n",
        "  xtd provenance verify --manifest <path> --artifact-root <path> \\\n",
        "    [--repository-root <path>] [--require-release]"
    )
    .to_string()
}

fn parse_create_options(args: &[String]) -> Result<CreateOptions, String> {
    let mut manifest_path = None;
    let mut repository_root = None;
    let mut artifact_root = None;
    let mut swift_path = None;
    let mut xtd_path = None;
    let mut packaged_xtd_path = None;
    let mut inventory_root = None;
    let mut source_date_epoch = None;
    let mut release = false;
    let mut index = 0;

    while index < args.len() {
        match args[index].as_str() {
            "--manifest" => set_once(
                &mut manifest_path,
                PathBuf::from(option_value(args, &mut index, "--manifest")?),
                "--manifest",
            )?,
            "--repository-root" => set_once(
                &mut repository_root,
                PathBuf::from(option_value(args, &mut index, "--repository-root")?),
                "--repository-root",
            )?,
            "--artifact-root" => set_once(
                &mut artifact_root,
                PathBuf::from(option_value(args, &mut index, "--artifact-root")?),
                "--artifact-root",
            )?,
            "--swift-path" => set_once(
                &mut swift_path,
                option_value(args, &mut index, "--swift-path")?,
                "--swift-path",
            )?,
            "--xtd-path" => set_once(
                &mut xtd_path,
                option_value(args, &mut index, "--xtd-path")?,
                "--xtd-path",
            )?,
            "--packaged-xtd-path" => set_once(
                &mut packaged_xtd_path,
                option_value(args, &mut index, "--packaged-xtd-path")?,
                "--packaged-xtd-path",
            )?,
            "--inventory-root" => set_once(
                &mut inventory_root,
                option_value(args, &mut index, "--inventory-root")?,
                "--inventory-root",
            )?,
            "--source-date-epoch" => {
                let raw = option_value(args, &mut index, "--source-date-epoch")?;
                let parsed = raw.parse::<u64>().map_err(|_| {
                    format!("--source-date-epoch must be a non-negative integer: {raw}")
                })?;
                set_once(&mut source_date_epoch, parsed, "--source-date-epoch")?;
            }
            "--release" => {
                if release {
                    return Err("duplicate option: --release".to_string());
                }
                release = true;
                index += 1;
            }
            unknown => return Err(format!("unknown provenance create option: {unknown}")),
        }
    }

    Ok(CreateOptions {
        manifest_path: required(manifest_path, "--manifest")?,
        repository_root: required(repository_root, "--repository-root")?,
        artifact_root: required(artifact_root, "--artifact-root")?,
        swift_path: required(swift_path, "--swift-path")?,
        xtd_path: required(xtd_path, "--xtd-path")?,
        packaged_xtd_path,
        inventory_root: required(inventory_root, "--inventory-root")?,
        source_date_epoch,
        release,
    })
}

fn parse_verify_options(args: &[String]) -> Result<VerifyOptions, String> {
    let mut manifest_path = None;
    let mut artifact_root = None;
    let mut repository_root = None;
    let mut require_release = false;
    let mut index = 0;

    while index < args.len() {
        match args[index].as_str() {
            "--manifest" => set_once(
                &mut manifest_path,
                PathBuf::from(option_value(args, &mut index, "--manifest")?),
                "--manifest",
            )?,
            "--artifact-root" => set_once(
                &mut artifact_root,
                PathBuf::from(option_value(args, &mut index, "--artifact-root")?),
                "--artifact-root",
            )?,
            "--repository-root" => set_once(
                &mut repository_root,
                PathBuf::from(option_value(args, &mut index, "--repository-root")?),
                "--repository-root",
            )?,
            "--require-release" => {
                if require_release {
                    return Err("duplicate option: --require-release".to_string());
                }
                require_release = true;
                index += 1;
            }
            unknown => return Err(format!("unknown provenance verify option: {unknown}")),
        }
    }

    Ok(VerifyOptions {
        manifest_path: required(manifest_path, "--manifest")?,
        artifact_root: required(artifact_root, "--artifact-root")?,
        repository_root,
        require_release,
    })
}

fn option_value(args: &[String], index: &mut usize, name: &str) -> Result<String, String> {
    let value = args
        .get(*index + 1)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| format!("{name} requires a value"))?
        .clone();
    *index += 2;
    Ok(value)
}

fn set_once<T>(slot: &mut Option<T>, value: T, name: &str) -> Result<(), String> {
    if slot.is_some() {
        return Err(format!("duplicate option: {name}"));
    }
    *slot = Some(value);
    Ok(())
}

fn required<T>(value: Option<T>, name: &str) -> Result<T, String> {
    value.ok_or_else(|| format!("missing required option: {name}"))
}

fn create(options: CreateOptions) -> Result<(), String> {
    let repository_root = canonical_repository_root(&options.repository_root)?;
    let artifact_root = canonical_directory(&options.artifact_root, "artifact root")?;
    let source = read_source_identity(&repository_root)?;
    let source_date_epoch =
        resolved_source_date_epoch(&source, options.source_date_epoch, options.release)?;
    if options.release {
        verify_exact_annotated_signed_tag(&repository_root, &source.git_commit).map_err(
            |error| format!("release provenance requires an exact annotated signed tag: {error}"),
        )?;
    }
    let manifest_relative_path = manifest_relative_path(&artifact_root, &options.manifest_path)?;
    let value = manifest_value(
        &artifact_root,
        &source,
        options.release,
        source_date_epoch,
        ArtifactLayout {
            swift_path: &options.swift_path,
            xtd_path: &options.xtd_path,
            packaged_xtd_path: options.packaged_xtd_path.as_deref(),
            inventory_root: &options.inventory_root,
            manifest_relative_path: &manifest_relative_path,
        },
    )?;

    let preflight = verify_manifest_value(
        &value,
        &artifact_root,
        &manifest_relative_path,
        Some(&source),
        options.release,
    );
    if preflight.get("ok").and_then(Value::as_bool) != Some(true) {
        return Err(format!(
            "refusing to publish unverifiable XT provenance: {}",
            preflight["issues"]
        ));
    }
    atomic_write_json(&options.manifest_path, &value)?;

    let persisted = read_manifest(&options.manifest_path)?;
    let verification = verify_manifest_value(
        &persisted,
        &artifact_root,
        &manifest_relative_path,
        Some(&source),
        options.release,
    );
    if verification.get("ok").and_then(Value::as_bool) != Some(true) {
        return Err(format!(
            "persisted XT provenance failed verification: {}",
            verification["issues"]
        ));
    }

    println!(
        "{}",
        serde_json::to_string_pretty(&json!({
            "schema_version": "xhub.xterminal.artifact_provenance_create.v1",
            "ok": true,
            "manifest_path": options.manifest_path.display().to_string(),
            "verification": verification,
        }))
        .map_err(|error| error.to_string())?
    );
    Ok(())
}

fn verify(options: VerifyOptions) -> Result<(), String> {
    let artifact_root = canonical_directory(&options.artifact_root, "artifact root")?;
    let repository_root = options
        .repository_root
        .as_deref()
        .map(canonical_repository_root)
        .transpose()?;
    let expected_source = repository_root
        .as_deref()
        .map(read_source_identity)
        .transpose()?;
    let manifest = read_manifest(&options.manifest_path)?;
    let manifest_relative_path = manifest_relative_path(&artifact_root, &options.manifest_path)?;
    let mut report = verify_manifest_value(
        &manifest,
        &artifact_root,
        &manifest_relative_path,
        expected_source.as_ref(),
        options.require_release,
    );
    if options.require_release {
        if let (Some(repository_root), Some(source)) =
            (repository_root.as_deref(), expected_source.as_ref())
        {
            if let Err(error) =
                verify_exact_annotated_signed_tag(repository_root, &source.git_commit)
            {
                append_verification_issue(
                    &mut report,
                    format!("release_signed_tag_unverified:{error}"),
                );
            }
        }
    }
    println!(
        "{}",
        serde_json::to_string_pretty(&report).map_err(|error| error.to_string())?
    );
    if report.get("ok").and_then(Value::as_bool) == Some(true) {
        Ok(())
    } else {
        Err("XT artifact provenance verification failed".to_string())
    }
}

fn append_verification_issue(report: &mut Value, issue: String) {
    if let Some(issues) = report.get_mut("issues").and_then(Value::as_array_mut) {
        issues.push(Value::String(issue));
    } else {
        report["issues"] = json!([issue]);
    }
    report["ok"] = Value::Bool(false);
}

fn manifest_value(
    artifact_root: &Path,
    source: &SourceIdentity,
    release: bool,
    source_date_epoch: u64,
    layout: ArtifactLayout<'_>,
) -> Result<Value, String> {
    validate_source_identity(source, release, source_date_epoch)?;
    let mut artifacts = vec![
        artifact_value(artifact_root, "swift_app_binary", layout.swift_path)?,
        artifact_value(artifact_root, "xtd_sidecar", layout.xtd_path)?,
    ];
    if let Some(path) = layout.packaged_xtd_path {
        artifacts.push(artifact_value(artifact_root, "xtd_package_binary", path)?);
    }
    validate_inventory_layout(
        layout.packaged_xtd_path.is_some(),
        layout.inventory_root,
        layout.manifest_relative_path,
    )?;
    let inventory = inventory_value(
        artifact_root,
        layout.inventory_root,
        layout.manifest_relative_path,
    )?;

    Ok(json!({
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "ok": true,
        "component": {
            "name": COMPONENT_NAME,
            "canonical_source_root": COMPONENT_ROOT,
            "sidecar": {
                "name": SIDECAR_NAME,
                "canonical_source_root": SIDECAR_ROOT,
            },
        },
        "source": {
            "git_commit": source.git_commit,
            "git_dirty": source.git_dirty,
            "git_commit_timestamp": source.git_commit_timestamp,
        },
        "build": {
            "mode": if release { "release" } else { "development" },
            "release": release,
            "source_date_epoch": source_date_epoch,
            "source_date_epoch_source": if release { "SOURCE_DATE_EPOCH" } else if source_date_epoch == source.git_commit_timestamp { "git_commit_timestamp" } else { "SOURCE_DATE_EPOCH" },
        },
        "artifacts": artifacts,
        "inventory": inventory,
    }))
}

fn artifact_value(artifact_root: &Path, role: &str, relative_path: &str) -> Result<Value, String> {
    let artifact_path = verified_artifact_path(artifact_root, relative_path)?;
    let (sha256, size_bytes) = sha256::file_digest_hex(&artifact_path)
        .map_err(|error| format!("hash artifact {}: {error}", artifact_path.display()))?;
    Ok(json!({
        "role": role,
        "path": relative_path,
        "sha256": sha256,
        "size_bytes": size_bytes,
    }))
}

fn verify_manifest_value(
    manifest: &Value,
    artifact_root: &Path,
    manifest_relative_path: &str,
    expected_source: Option<&SourceIdentity>,
    require_release: bool,
) -> Value {
    let mut issues = Vec::new();
    if !object_has_exact_keys(
        manifest,
        &[
            "schema_version",
            "ok",
            "component",
            "source",
            "build",
            "artifacts",
            "inventory",
        ],
    ) {
        issues.push("manifest_shape_mismatch".to_string());
    }
    if manifest.get("schema_version").and_then(Value::as_str) != Some(MANIFEST_SCHEMA_VERSION) {
        issues.push("manifest_schema_mismatch".to_string());
    }
    if manifest.get("ok").and_then(Value::as_bool) != Some(true) {
        issues.push("manifest_not_ok".to_string());
    }
    if manifest.pointer("/component/name").and_then(Value::as_str) != Some(COMPONENT_NAME) {
        issues.push("component_name_mismatch".to_string());
    }
    if !manifest.get("component").is_some_and(|value| {
        object_has_exact_keys(value, &["name", "canonical_source_root", "sidecar"])
    }) {
        issues.push("component_shape_mismatch".to_string());
    }
    if manifest
        .pointer("/component/canonical_source_root")
        .and_then(Value::as_str)
        != Some(COMPONENT_ROOT)
    {
        issues.push("component_source_root_mismatch".to_string());
    }
    if manifest
        .pointer("/component/sidecar/name")
        .and_then(Value::as_str)
        != Some(SIDECAR_NAME)
    {
        issues.push("sidecar_name_mismatch".to_string());
    }
    if manifest
        .pointer("/component/sidecar/canonical_source_root")
        .and_then(Value::as_str)
        != Some(SIDECAR_ROOT)
    {
        issues.push("sidecar_source_root_mismatch".to_string());
    }
    if !manifest
        .pointer("/component/sidecar")
        .is_some_and(|value| object_has_exact_keys(value, &["name", "canonical_source_root"]))
    {
        issues.push("sidecar_shape_mismatch".to_string());
    }

    if !manifest.get("source").is_some_and(|value| {
        object_has_exact_keys(value, &["git_commit", "git_dirty", "git_commit_timestamp"])
    }) {
        issues.push("source_shape_mismatch".to_string());
    }

    let git_commit = manifest
        .pointer("/source/git_commit")
        .and_then(Value::as_str);
    if !git_commit.is_some_and(is_hex_commit) {
        issues.push("source_git_commit_invalid".to_string());
    }
    let git_dirty = manifest
        .pointer("/source/git_dirty")
        .and_then(Value::as_bool);
    if git_dirty.is_none() {
        issues.push("source_git_dirty_missing".to_string());
    }
    let git_commit_timestamp = manifest
        .pointer("/source/git_commit_timestamp")
        .and_then(Value::as_u64);
    if git_commit_timestamp.is_none() {
        issues.push("source_git_commit_timestamp_missing".to_string());
    }
    let release = manifest.pointer("/build/release").and_then(Value::as_bool);
    let source_date_epoch = manifest
        .pointer("/build/source_date_epoch")
        .and_then(Value::as_u64);
    let source_date_epoch_source = manifest
        .pointer("/build/source_date_epoch_source")
        .and_then(Value::as_str);
    if !manifest.get("build").is_some_and(|value| {
        object_has_exact_keys(
            value,
            &[
                "mode",
                "release",
                "source_date_epoch",
                "source_date_epoch_source",
            ],
        )
    }) {
        issues.push("build_shape_mismatch".to_string());
    }
    if release.is_none() {
        issues.push("build_release_flag_missing".to_string());
    }
    if source_date_epoch.is_none() {
        issues.push("source_date_epoch_missing".to_string());
    }
    match release {
        Some(true) => {
            if git_dirty != Some(false) {
                issues.push("release_source_dirty".to_string());
            }
            if source_date_epoch != git_commit_timestamp {
                issues.push("release_source_date_epoch_mismatch".to_string());
            }
            if manifest.pointer("/build/mode").and_then(Value::as_str) != Some("release") {
                issues.push("release_mode_mismatch".to_string());
            }
            if source_date_epoch_source != Some("SOURCE_DATE_EPOCH") {
                issues.push("release_source_date_epoch_source_mismatch".to_string());
            }
        }
        Some(false) => {
            if manifest.pointer("/build/mode").and_then(Value::as_str) != Some("development") {
                issues.push("development_mode_mismatch".to_string());
            }
            if !matches!(
                source_date_epoch_source,
                Some("git_commit_timestamp" | "SOURCE_DATE_EPOCH")
            ) {
                issues.push("development_source_date_epoch_source_invalid".to_string());
            }
        }
        None => {}
    }
    if require_release && release != Some(true) {
        issues.push("release_provenance_required".to_string());
    }

    if let Some(expected) = expected_source {
        if git_commit != Some(expected.git_commit.as_str()) {
            issues.push("source_git_commit_mismatch".to_string());
        }
        if git_dirty != Some(expected.git_dirty) {
            issues.push("source_git_dirty_mismatch".to_string());
        }
        if git_commit_timestamp != Some(expected.git_commit_timestamp) {
            issues.push("source_git_commit_timestamp_mismatch".to_string());
        }
    }

    let mut roles = HashSet::new();
    let mut swift_count = 0;
    let mut xtd_sidecar_count = 0;
    let mut verified_count = 0;
    let mut artifact_roles_in_order = Vec::new();
    let mut artifact_paths = BTreeMap::new();
    match manifest.get("artifacts").and_then(Value::as_array) {
        Some(artifacts) => {
            for artifact in artifacts {
                if !object_has_exact_keys(artifact, &["role", "path", "sha256", "size_bytes"]) {
                    issues.push("artifact_shape_mismatch".to_string());
                }
                let role = artifact.get("role").and_then(Value::as_str);
                let path = artifact.get("path").and_then(Value::as_str);
                let expected_hash = artifact.get("sha256").and_then(Value::as_str);
                let expected_size = artifact.get("size_bytes").and_then(Value::as_u64);
                let Some(role) = role else {
                    issues.push("artifact_role_missing".to_string());
                    continue;
                };
                artifact_roles_in_order.push(role.to_string());
                if !matches!(
                    role,
                    "swift_app_binary" | "xtd_sidecar" | "xtd_package_binary"
                ) {
                    issues.push(format!("artifact_role_unknown:{role}"));
                    continue;
                }
                if !roles.insert(role.to_string()) {
                    issues.push(format!("artifact_role_duplicate:{role}"));
                }
                if role == "swift_app_binary" {
                    swift_count += 1;
                }
                if role == "xtd_sidecar" {
                    xtd_sidecar_count += 1;
                }
                let Some(path) = path else {
                    issues.push(format!("artifact_path_missing:{role}"));
                    continue;
                };
                artifact_paths.insert(role.to_string(), path.to_string());
                if !expected_hash.is_some_and(is_sha256_hex) {
                    issues.push(format!("artifact_sha256_invalid:{role}"));
                    continue;
                }
                let Some(expected_size) = expected_size else {
                    issues.push(format!("artifact_size_missing:{role}"));
                    continue;
                };
                match verified_artifact_path(artifact_root, path).and_then(|artifact_path| {
                    sha256::file_digest_hex(&artifact_path).map_err(|error| {
                        format!("hash artifact {}: {error}", artifact_path.display())
                    })
                }) {
                    Ok((actual_hash, actual_size)) => {
                        if Some(actual_hash.as_str()) != expected_hash {
                            issues.push(format!("artifact_sha256_mismatch:{role}"));
                        } else if actual_size != expected_size {
                            issues.push(format!("artifact_size_mismatch:{role}"));
                        } else {
                            verified_count += 1;
                        }
                    }
                    Err(error) => issues.push(format!("artifact_unavailable:{role}:{error}")),
                }
            }
        }
        None => issues.push("artifacts_missing".to_string()),
    }
    if swift_count != 1 {
        issues.push("swift_app_binary_cardinality_invalid".to_string());
    }
    if xtd_sidecar_count != 1 {
        issues.push("xtd_sidecar_cardinality_invalid".to_string());
    }

    let package_layout = roles.contains("xtd_package_binary");
    let (expected_roles, expected_paths): (&[&str], &[(&str, &str)]) = if package_layout {
        (
            &["swift_app_binary", "xtd_sidecar", "xtd_package_binary"],
            &[
                ("swift_app_binary", PACKAGE_SWIFT_PATH),
                ("xtd_sidecar", PACKAGE_XTD_PATH),
                ("xtd_package_binary", PACKAGE_STANDALONE_XTD_PATH),
            ],
        )
    } else {
        (
            &["swift_app_binary", "xtd_sidecar"],
            &[
                ("swift_app_binary", BUILD_SWIFT_PATH),
                ("xtd_sidecar", BUILD_XTD_PATH),
            ],
        )
    };
    if artifact_roles_in_order
        != expected_roles
            .iter()
            .map(|role| role.to_string())
            .collect::<Vec<_>>()
    {
        issues.push("artifact_roles_or_order_mismatch".to_string());
    }
    for (role, expected_path) in expected_paths {
        if artifact_paths.get(*role).map(String::as_str) != Some(*expected_path) {
            issues.push(format!("artifact_path_layout_mismatch:{role}"));
        }
    }
    let expected_inventory_root = if package_layout {
        PACKAGE_INVENTORY_ROOT
    } else {
        BUILD_INVENTORY_ROOT
    };
    let expected_manifest_path = if package_layout {
        PACKAGE_MANIFEST_PATH
    } else {
        BUILD_MANIFEST_PATH
    };
    if manifest_relative_path != expected_manifest_path {
        issues.push("manifest_path_layout_mismatch".to_string());
    }
    if manifest.pointer("/inventory/root").and_then(Value::as_str) != Some(expected_inventory_root)
    {
        issues.push("inventory_root_mismatch".to_string());
    }
    if manifest
        .pointer("/inventory/manifest_path")
        .and_then(Value::as_str)
        != Some(expected_manifest_path)
    {
        issues.push("inventory_manifest_path_mismatch".to_string());
    }
    let mut inventory_verified = false;
    let mut inventory_files_verified = 0;
    match inventory_value(
        artifact_root,
        expected_inventory_root,
        expected_manifest_path,
    ) {
        Ok(actual_inventory) => {
            inventory_files_verified = actual_inventory
                .get("files")
                .and_then(Value::as_array)
                .map(Vec::len)
                .unwrap_or(0);
            let expected_inventory = manifest.get("inventory").unwrap_or(&Value::Null);
            let inventory_issues = compare_inventory(expected_inventory, &actual_inventory);
            inventory_verified = inventory_issues.is_empty();
            issues.extend(inventory_issues);
        }
        Err(error) => issues.push(format!("inventory_unavailable:{error}")),
    }

    json!({
        "schema_version": VERIFICATION_SCHEMA_VERSION,
        "ok": issues.is_empty(),
        "manifest_schema_version": manifest.get("schema_version").cloned().unwrap_or(Value::Null),
        "release": release,
        "artifacts_verified": verified_count,
        "inventory_verified": inventory_verified,
        "inventory_files_verified": inventory_files_verified,
        "issues": issues,
    })
}

fn validate_inventory_layout(
    package_layout: bool,
    inventory_root: &str,
    manifest_relative_path: &str,
) -> Result<(), String> {
    let (expected_root, expected_manifest) = if package_layout {
        (PACKAGE_INVENTORY_ROOT, PACKAGE_MANIFEST_PATH)
    } else {
        (BUILD_INVENTORY_ROOT, BUILD_MANIFEST_PATH)
    };
    if inventory_root != expected_root {
        return Err(format!(
            "inventory root must be {expected_root} for this artifact layout, got {inventory_root}"
        ));
    }
    if manifest_relative_path != expected_manifest {
        return Err(format!(
            "detached manifest must be {expected_manifest} for this artifact layout, got {manifest_relative_path}"
        ));
    }
    Ok(())
}

fn manifest_relative_path(artifact_root: &Path, manifest_path: &Path) -> Result<String, String> {
    let absolute = if manifest_path.is_absolute() {
        manifest_path.to_path_buf()
    } else {
        std::env::current_dir()
            .map_err(|error| format!("resolve current directory: {error}"))?
            .join(manifest_path)
    };
    let file_name = absolute
        .file_name()
        .ok_or_else(|| format!("manifest path has no file name: {}", absolute.display()))?;
    let parent = absolute
        .parent()
        .ok_or_else(|| format!("manifest path has no parent: {}", absolute.display()))?;
    let parent = canonical_directory(parent, "manifest parent")?;
    if !parent.starts_with(artifact_root) {
        return Err(format!(
            "detached manifest escapes artifact root: {}",
            absolute.display()
        ));
    }
    let normalized = parent.join(file_name);
    let relative = normalized
        .strip_prefix(artifact_root)
        .map_err(|_| format!("manifest escapes artifact root: {}", normalized.display()))?;
    let relative = relative_path_string(relative)?;
    if !is_safe_relative_path(&relative) {
        return Err(format!("unsafe detached manifest path: {relative}"));
    }
    Ok(relative)
}

fn inventory_value(
    artifact_root: &Path,
    inventory_root: &str,
    manifest_relative_path: &str,
) -> Result<Value, String> {
    let inventory_path = if inventory_root == PACKAGE_INVENTORY_ROOT {
        artifact_root.to_path_buf()
    } else {
        verified_directory_path(artifact_root, inventory_root)?
    };
    let mut directories = Vec::new();
    let mut files = Vec::new();
    collect_inventory(
        artifact_root,
        &inventory_path,
        manifest_relative_path,
        &mut directories,
        &mut files,
    )?;
    directories.sort();
    files.sort_by(|left, right| {
        left.get("path")
            .and_then(Value::as_str)
            .cmp(&right.get("path").and_then(Value::as_str))
    });
    Ok(json!({
        "root": inventory_root,
        "manifest_path": manifest_relative_path,
        "directories": directories,
        "files": files,
    }))
}

fn collect_inventory(
    artifact_root: &Path,
    directory: &Path,
    manifest_relative_path: &str,
    directories: &mut Vec<String>,
    files: &mut Vec<Value>,
) -> Result<(), String> {
    let mut entries = fs::read_dir(directory)
        .map_err(|error| format!("read inventory directory {}: {error}", directory.display()))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("read inventory entry in {}: {error}", directory.display()))?;
    entries.sort_by_key(|entry| entry.file_name());

    for entry in entries {
        let path = entry.path();
        let metadata = fs::symlink_metadata(&path)
            .map_err(|error| format!("inspect inventory path {}: {error}", path.display()))?;
        let canonical_relative =
            relative_path_string(path.strip_prefix(artifact_root).map_err(|_| {
                format!("inventory path escapes artifact root: {}", path.display())
            })?)?;
        if metadata.file_type().is_symlink() {
            return Err(format!(
                "inventory contains forbidden symlink: {canonical_relative}"
            ));
        }
        if metadata.is_dir() {
            directories.push(canonical_relative);
            collect_inventory(
                artifact_root,
                &path,
                manifest_relative_path,
                directories,
                files,
            )?;
            continue;
        }
        if !metadata.is_file() {
            return Err(format!(
                "inventory contains unsupported file type: {canonical_relative}"
            ));
        }
        if canonical_relative == manifest_relative_path {
            continue;
        }
        let (sha256, size_bytes) = sha256::file_digest_hex(&path)
            .map_err(|error| format!("hash inventory file {}: {error}", path.display()))?;
        files.push(json!({
            "path": canonical_relative,
            "sha256": sha256,
            "size_bytes": size_bytes,
        }));
    }
    Ok(())
}

fn compare_inventory(expected: &Value, actual: &Value) -> Vec<String> {
    let mut issues = Vec::new();
    let expected_directories = inventory_directories(expected, "expected", &mut issues);
    let actual_directories = inventory_directories(actual, "actual", &mut issues);
    for missing in expected_directories.difference(&actual_directories) {
        issues.push(format!("inventory_directory_missing:{missing}"));
    }
    for extra in actual_directories.difference(&expected_directories) {
        issues.push(format!("inventory_directory_extra:{extra}"));
    }

    let expected_files = inventory_files(expected, "expected", &mut issues);
    let actual_files = inventory_files(actual, "actual", &mut issues);
    for (path, (expected_hash, expected_size)) in &expected_files {
        match actual_files.get(path) {
            None => issues.push(format!("inventory_file_missing:{path}")),
            Some((actual_hash, actual_size)) => {
                if actual_hash != expected_hash {
                    issues.push(format!("inventory_file_sha256_mismatch:{path}"));
                }
                if actual_size != expected_size {
                    issues.push(format!("inventory_file_size_mismatch:{path}"));
                }
            }
        }
    }
    for extra in actual_files.keys() {
        if !expected_files.contains_key(extra) {
            issues.push(format!("inventory_file_extra:{extra}"));
        }
    }
    if expected != actual && issues.is_empty() {
        issues.push("inventory_schema_or_order_mismatch".to_string());
    }
    issues
}

fn object_has_exact_keys(value: &Value, expected: &[&str]) -> bool {
    let Some(object) = value.as_object() else {
        return false;
    };
    object.len() == expected.len() && expected.iter().all(|key| object.contains_key(*key))
}

fn inventory_directories(
    inventory: &Value,
    label: &str,
    issues: &mut Vec<String>,
) -> BTreeSet<String> {
    let Some(rows) = inventory.get("directories").and_then(Value::as_array) else {
        issues.push(format!("inventory_{label}_directories_missing"));
        return BTreeSet::new();
    };
    let mut values = BTreeSet::new();
    for row in rows {
        let Some(path) = row.as_str().filter(|path| is_safe_relative_path(path)) else {
            issues.push(format!("inventory_{label}_directory_invalid"));
            continue;
        };
        if !values.insert(path.to_string()) {
            issues.push(format!("inventory_{label}_directory_duplicate:{path}"));
        }
    }
    values
}

fn inventory_files(
    inventory: &Value,
    label: &str,
    issues: &mut Vec<String>,
) -> BTreeMap<String, (String, u64)> {
    let Some(rows) = inventory.get("files").and_then(Value::as_array) else {
        issues.push(format!("inventory_{label}_files_missing"));
        return BTreeMap::new();
    };
    let mut values = BTreeMap::new();
    for row in rows {
        let Some(path) = row
            .get("path")
            .and_then(Value::as_str)
            .filter(|path| is_safe_relative_path(path))
        else {
            issues.push(format!("inventory_{label}_file_path_invalid"));
            continue;
        };
        let Some(hash) = row
            .get("sha256")
            .and_then(Value::as_str)
            .filter(|hash| is_sha256_hex(hash))
        else {
            issues.push(format!("inventory_{label}_file_sha256_invalid:{path}"));
            continue;
        };
        let Some(size) = row.get("size_bytes").and_then(Value::as_u64) else {
            issues.push(format!("inventory_{label}_file_size_invalid:{path}"));
            continue;
        };
        if values
            .insert(path.to_string(), (hash.to_string(), size))
            .is_some()
        {
            issues.push(format!("inventory_{label}_file_duplicate:{path}"));
        }
    }
    values
}

fn relative_path_string(path: &Path) -> Result<String, String> {
    let mut segments = Vec::new();
    for component in path.components() {
        let Component::Normal(segment) = component else {
            return Err(format!(
                "path is not a normalized relative path: {}",
                path.display()
            ));
        };
        let segment = segment
            .to_str()
            .ok_or_else(|| format!("path is not UTF-8: {}", path.display()))?;
        segments.push(segment);
    }
    if segments.is_empty() {
        return Err("relative path is empty".to_string());
    }
    Ok(segments.join("/"))
}

fn resolved_source_date_epoch(
    source: &SourceIdentity,
    requested: Option<u64>,
    release: bool,
) -> Result<u64, String> {
    let source_date_epoch = requested.unwrap_or(source.git_commit_timestamp);
    validate_source_identity(source, release, source_date_epoch)?;
    if release && requested.is_none() {
        return Err("release provenance requires explicit SOURCE_DATE_EPOCH".to_string());
    }
    Ok(source_date_epoch)
}

fn validate_source_identity(
    source: &SourceIdentity,
    release: bool,
    source_date_epoch: u64,
) -> Result<(), String> {
    if !is_hex_commit(&source.git_commit) {
        return Err("source git commit is invalid".to_string());
    }
    if release && source.git_dirty {
        return Err("release provenance requires git_dirty=false".to_string());
    }
    if release && source_date_epoch != source.git_commit_timestamp {
        return Err(format!(
            "release SOURCE_DATE_EPOCH {source_date_epoch} does not match commit timestamp {}",
            source.git_commit_timestamp
        ));
    }
    Ok(())
}

fn canonical_repository_root(path: &Path) -> Result<PathBuf, String> {
    let root = canonical_directory(path, "repository root")?;
    let reported_root = git_output(&root, &["rev-parse", "--show-toplevel"])?;
    let reported_root = canonical_directory(Path::new(&reported_root), "git repository root")?;
    if root != reported_root {
        return Err(format!(
            "repository root must be the git toplevel: requested {}, git reported {}",
            root.display(),
            reported_root.display()
        ));
    }
    git_output(
        &root,
        &[
            "ls-files",
            "--error-unmatch",
            "x-terminal/Package.swift",
            "rust/xtd/Cargo.toml",
        ],
    )?;
    Ok(root)
}

fn read_source_identity(repository_root: &Path) -> Result<SourceIdentity, String> {
    let git_commit = git_output(repository_root, &["rev-parse", "HEAD"])?;
    if !is_hex_commit(&git_commit) {
        return Err(format!("git returned an invalid HEAD commit: {git_commit}"));
    }
    let status = git_output(
        repository_root,
        &["status", "--porcelain=v1", "--untracked-files=all"],
    )?;
    let raw_timestamp = git_output(repository_root, &["show", "-s", "--format=%ct", "HEAD"])?;
    let git_commit_timestamp = raw_timestamp
        .parse::<u64>()
        .map_err(|_| format!("git returned an invalid commit timestamp: {raw_timestamp}"))?;
    Ok(SourceIdentity {
        git_commit,
        git_dirty: !status.is_empty(),
        git_commit_timestamp,
    })
}

fn verify_exact_annotated_signed_tag(
    repository_root: &Path,
    git_commit: &str,
) -> Result<String, String> {
    let tags = git_output(repository_root, &["tag", "--points-at", git_commit])?;
    if tags.is_empty() {
        return Err(format!("no tag points at commit {git_commit}"));
    }

    let mut annotated_tags = Vec::new();
    let mut signature_failures = Vec::new();
    for tag in tags.lines().map(str::trim).filter(|tag| !tag.is_empty()) {
        let tag_ref = format!("refs/tags/{tag}");
        let object_type = match git_output(repository_root, &["cat-file", "-t", &tag_ref]) {
            Ok(object_type) => object_type,
            Err(error) => {
                signature_failures.push(format!("{tag}: {error}"));
                continue;
            }
        };
        if object_type != "tag" {
            continue;
        }
        annotated_tags.push(tag.to_string());

        let peeled_ref = format!("{tag_ref}^{{commit}}");
        let peeled_commit = match git_output(repository_root, &["rev-parse", &peeled_ref]) {
            Ok(peeled_commit) => peeled_commit,
            Err(error) => {
                signature_failures.push(format!("{tag}: {error}"));
                continue;
            }
        };
        if peeled_commit != git_commit {
            signature_failures.push(format!(
                "{tag}: peeled commit {peeled_commit} does not match {git_commit}"
            ));
            continue;
        }

        match git_output(repository_root, &["verify-tag", &tag_ref]) {
            Ok(_) => return Ok(tag.to_string()),
            Err(error) => signature_failures.push(format!("{tag}: {error}")),
        }
    }

    if annotated_tags.is_empty() {
        return Err(format!(
            "no annotated tag points at commit {git_commit}; lightweight tags are not releases"
        ));
    }
    Err(format!(
        "no cryptographically verifiable annotated tag points at commit {git_commit}: {}",
        signature_failures.join("; ")
    ))
}

fn git_output(working_dir: &Path, args: &[&str]) -> Result<String, String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(working_dir)
        .args(args)
        .output()
        .map_err(|error| format!("run git: {error}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(if stderr.is_empty() {
            format!("git {:?} exited with {}", args, output.status)
        } else {
            stderr
        });
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn canonical_directory(path: &Path, label: &str) -> Result<PathBuf, String> {
    if !path.is_dir() {
        return Err(format!("{label} is not a directory: {}", path.display()));
    }
    path.canonicalize()
        .map_err(|error| format!("canonicalize {label} {}: {error}", path.display()))
}

fn verified_artifact_path(artifact_root: &Path, relative_path: &str) -> Result<PathBuf, String> {
    if !is_safe_relative_path(relative_path) {
        return Err(format!("unsafe artifact relative path: {relative_path}"));
    }
    let path = artifact_root.join(relative_path);
    let metadata = fs::symlink_metadata(&path)
        .map_err(|error| format!("inspect artifact {}: {error}", path.display()))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(format!(
            "artifact must be a regular non-symlink file: {}",
            path.display()
        ));
    }
    let canonical = path
        .canonicalize()
        .map_err(|error| format!("canonicalize artifact {}: {error}", path.display()))?;
    if !canonical.starts_with(artifact_root) {
        return Err(format!(
            "artifact escapes artifact root: {}",
            path.display()
        ));
    }
    Ok(canonical)
}

fn verified_directory_path(artifact_root: &Path, relative_path: &str) -> Result<PathBuf, String> {
    if !is_safe_relative_path(relative_path) {
        return Err(format!("unsafe inventory root: {relative_path}"));
    }
    let path = artifact_root.join(relative_path);
    let metadata = fs::symlink_metadata(&path)
        .map_err(|error| format!("inspect inventory root {}: {error}", path.display()))?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(format!(
            "inventory root must be a non-symlink directory: {}",
            path.display()
        ));
    }
    let canonical = path
        .canonicalize()
        .map_err(|error| format!("canonicalize inventory root {}: {error}", path.display()))?;
    if !canonical.starts_with(artifact_root) {
        return Err(format!(
            "inventory root escapes artifact root: {}",
            path.display()
        ));
    }
    Ok(canonical)
}

fn is_safe_relative_path(value: &str) -> bool {
    let path = Path::new(value);
    !value.is_empty()
        && !path.is_absolute()
        && value
            .split('/')
            .all(|segment| !segment.is_empty() && !matches!(segment, "." | ".."))
        && path
            .components()
            .all(|component| matches!(component, Component::Normal(_)))
}

fn is_hex_commit(value: &str) -> bool {
    (40..=64).contains(&value.len())
        && value
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
}

fn is_sha256_hex(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
}

fn read_manifest(path: &Path) -> Result<Value, String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("inspect provenance manifest {}: {error}", path.display()))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(format!(
            "provenance manifest must be a regular non-symlink file: {}",
            path.display()
        ));
    }
    if metadata.len() > MAX_MANIFEST_BYTES {
        return Err(format!(
            "provenance manifest exceeds {MAX_MANIFEST_BYTES} bytes: {}",
            path.display()
        ));
    }
    serde_json::from_slice(
        &fs::read(path).map_err(|error| format!("read manifest {}: {error}", path.display()))?,
    )
    .map_err(|error| format!("parse manifest {}: {error}", path.display()))
}

fn atomic_write_json(path: &Path, value: &Value) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| format!("manifest has no parent: {}", path.display()))?;
    if !parent.is_dir() {
        return Err(format!(
            "manifest parent is not a directory: {}",
            parent.display()
        ));
    }
    if let Ok(metadata) = fs::symlink_metadata(path) {
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            return Err(format!(
                "refusing to replace non-regular manifest path: {}",
                path.display()
            ));
        }
    }
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| format!("system clock is before Unix epoch: {error}"))?
        .as_nanos();
    let temp_path = parent.join(format!(
        ".xterminal-provenance.{}.{stamp}.tmp",
        std::process::id()
    ));
    let result = (|| -> Result<(), String> {
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
                "atomically rename {} to {}: {error}",
                temp_path.display(),
                path.display()
            )
        })?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp_path);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    struct TestRoot(PathBuf);

    impl TestRoot {
        fn new() -> Self {
            let stamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("test clock")
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "xtd-provenance-test-{}-{stamp}",
                std::process::id()
            ));
            fs::create_dir_all(&path).expect("create test root");
            Self(path)
        }
    }

    impl Drop for TestRoot {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn clean_source() -> SourceIdentity {
        SourceIdentity {
            git_commit: "0123456789abcdef0123456789abcdef01234567".to_string(),
            git_dirty: false,
            git_commit_timestamp: 1_700_000_000,
        }
    }

    fn run_git_fixture(root: &Path, args: &[&str]) -> std::process::Output {
        Command::new("git")
            .arg("-C")
            .arg(root)
            .args(args)
            .output()
            .expect("run fixture git")
    }

    fn assert_git_fixture(root: &Path, args: &[&str]) {
        let output = run_git_fixture(root, args);
        assert!(
            output.status.success(),
            "git {:?} failed: {}",
            args,
            String::from_utf8_lossy(&output.stderr)
        );
    }

    fn initialize_release_tag_fixture(root: &Path) -> String {
        assert_git_fixture(root, &["init", "-q"]);
        assert_git_fixture(root, &["config", "user.name", "XT Release Test"]);
        assert_git_fixture(root, &["config", "user.email", "release@example.com"]);
        fs::create_dir_all(root.join("x-terminal")).expect("create XT marker parent");
        fs::create_dir_all(root.join("rust/xtd")).expect("create xtd marker parent");
        fs::write(root.join("x-terminal/Package.swift"), b"// fixture\n").expect("write XT marker");
        fs::write(root.join("rust/xtd/Cargo.toml"), b"# fixture\n").expect("write xtd marker");
        assert_git_fixture(
            root,
            &["add", "x-terminal/Package.swift", "rust/xtd/Cargo.toml"],
        );
        assert_git_fixture(root, &["commit", "-q", "-m", "fixture release source"]);
        git_output(root, &["rev-parse", "HEAD"]).expect("fixture commit")
    }

    #[test]
    fn manifest_binds_canonical_roots_source_epoch_and_artifact_hashes() {
        let root = TestRoot::new();
        fs::create_dir_all(root.0.join("X-Terminal.app/Contents/MacOS"))
            .expect("create Swift binary parent");
        fs::create_dir_all(root.0.join("X-Terminal.app/Contents/Resources"))
            .expect("create xtd parent");
        fs::write(
            root.0.join("X-Terminal.app/Contents/MacOS/XTerminal"),
            b"swift-final-binary",
        )
        .expect("write Swift fixture");
        fs::write(
            root.0.join("X-Terminal.app/Contents/Resources/xtd"),
            b"xtd-final-binary",
        )
        .expect("write xtd fixture");
        let canonical_root = root.0.canonicalize().expect("canonical test root");
        let source = clean_source();

        let manifest = manifest_value(
            &canonical_root,
            &source,
            true,
            source.git_commit_timestamp,
            ArtifactLayout {
                swift_path: BUILD_SWIFT_PATH,
                xtd_path: BUILD_XTD_PATH,
                packaged_xtd_path: None,
                inventory_root: BUILD_INVENTORY_ROOT,
                manifest_relative_path: BUILD_MANIFEST_PATH,
            },
        )
        .expect("create manifest");
        let report = verify_manifest_value(
            &manifest,
            &canonical_root,
            BUILD_MANIFEST_PATH,
            Some(&source),
            true,
        );

        assert_eq!(manifest["schema_version"], MANIFEST_SCHEMA_VERSION);
        assert_eq!(
            manifest["component"]["canonical_source_root"],
            COMPONENT_ROOT
        );
        assert_eq!(
            manifest["component"]["sidecar"]["canonical_source_root"],
            SIDECAR_ROOT
        );
        assert_eq!(manifest["source"]["git_dirty"], false);
        assert_eq!(manifest["build"]["source_date_epoch"], 1_700_000_000_u64);
        assert_eq!(manifest["artifacts"].as_array().unwrap().len(), 2);
        assert_eq!(report["ok"], true);
        assert_eq!(report["artifacts_verified"], 2);
        assert_eq!(report["inventory_verified"], true);

        let mut mismatched_source = source.clone();
        mismatched_source.git_commit = "fedcba9876543210fedcba9876543210fedcba98".to_string();
        let mismatch = verify_manifest_value(
            &manifest,
            &canonical_root,
            BUILD_MANIFEST_PATH,
            Some(&mismatched_source),
            true,
        );
        assert_eq!(mismatch["ok"], false);
        assert!(mismatch["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "source_git_commit_mismatch"));

        let mut unexpected_field = manifest.clone();
        unexpected_field["untrusted_claim"] = json!(true);
        let unexpected = verify_manifest_value(
            &unexpected_field,
            &canonical_root,
            BUILD_MANIFEST_PATH,
            Some(&source),
            true,
        );
        assert_eq!(unexpected["ok"], false);
        assert!(unexpected["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "manifest_shape_mismatch"));
    }

    #[test]
    fn verification_fails_closed_after_binary_tampering() {
        let root = TestRoot::new();
        fs::create_dir_all(root.0.join("X-Terminal.app/Contents/MacOS"))
            .expect("create Swift binary parent");
        fs::create_dir_all(root.0.join("X-Terminal.app/Contents/Resources"))
            .expect("create xtd parent");
        fs::write(
            root.0.join("X-Terminal.app/Contents/MacOS/XTerminal"),
            b"swift",
        )
        .expect("write Swift fixture");
        fs::write(root.0.join("X-Terminal.app/Contents/Resources/xtd"), b"xtd")
            .expect("write xtd fixture");
        let canonical_root = root.0.canonicalize().expect("canonical test root");
        let source = clean_source();
        let manifest = manifest_value(
            &canonical_root,
            &source,
            false,
            source.git_commit_timestamp,
            ArtifactLayout {
                swift_path: BUILD_SWIFT_PATH,
                xtd_path: BUILD_XTD_PATH,
                packaged_xtd_path: None,
                inventory_root: BUILD_INVENTORY_ROOT,
                manifest_relative_path: BUILD_MANIFEST_PATH,
            },
        )
        .expect("create manifest");

        fs::write(
            root.0.join("X-Terminal.app/Contents/Resources/xtd"),
            b"tampered",
        )
        .expect("tamper xtd fixture");
        let report =
            verify_manifest_value(&manifest, &canonical_root, BUILD_MANIFEST_PATH, None, false);
        let issues = report["issues"].as_array().expect("issues array");

        assert_eq!(report["ok"], false);
        assert!(issues
            .iter()
            .any(|issue| issue == "artifact_sha256_mismatch:xtd_sidecar"));
    }

    #[test]
    fn release_manifest_refuses_dirty_source_or_wrong_epoch() {
        let mut dirty = clean_source();
        dirty.git_dirty = true;
        assert!(
            validate_source_identity(&dirty, true, dirty.git_commit_timestamp)
                .unwrap_err()
                .contains("git_dirty=false")
        );

        let clean = clean_source();
        assert!(
            validate_source_identity(&clean, true, clean.git_commit_timestamp + 1)
                .unwrap_err()
                .contains("does not match commit timestamp")
        );
    }

    #[test]
    fn release_tag_guard_rejects_untagged_lightweight_and_unsigned_sources() {
        let root = TestRoot::new();
        let commit = initialize_release_tag_fixture(&root.0);

        let untagged = verify_exact_annotated_signed_tag(&root.0, &commit)
            .expect_err("untagged commit must fail");
        assert!(untagged.contains("no tag points"));

        assert_git_fixture(&root.0, &["tag", "lightweight-release"]);
        let lightweight = verify_exact_annotated_signed_tag(&root.0, &commit)
            .expect_err("lightweight tag must fail");
        assert!(lightweight.contains("lightweight tags are not releases"));
        assert_git_fixture(&root.0, &["tag", "-d", "lightweight-release"]);

        assert_git_fixture(
            &root.0,
            &["tag", "-a", "unsigned-release", "-m", "unsigned release"],
        );
        let unsigned = verify_exact_annotated_signed_tag(&root.0, &commit)
            .expect_err("unsigned annotated tag must fail");
        assert!(unsigned.contains("no cryptographically verifiable annotated tag"));
    }

    #[test]
    fn release_tag_guard_accepts_an_exact_ssh_signed_annotated_tag() {
        let root = TestRoot::new();
        let commit = initialize_release_tag_fixture(&root.0);
        let signing_key = root.0.join("release-signing-key");
        let key_output = Command::new("ssh-keygen")
            .args(["-q", "-t", "ed25519", "-N", "", "-f"])
            .arg(&signing_key)
            .output();
        let Ok(key_output) = key_output else {
            eprintln!("ssh-keygen unavailable; skipping SSH signed-tag positive fixture");
            return;
        };
        if !key_output.status.success() {
            eprintln!(
                "ssh-keygen cannot create the positive fixture; skipping: {}",
                String::from_utf8_lossy(&key_output.stderr)
            );
            return;
        }

        let public_key = fs::read_to_string(signing_key.with_extension("pub"))
            .expect("read release fixture public key");
        let allowed_signers = root.0.join("allowed-signers");
        fs::write(
            &allowed_signers,
            format!("release@example.com {}\n", public_key.trim()),
        )
        .expect("write allowed signers");
        assert_git_fixture(&root.0, &["config", "gpg.format", "ssh"]);
        assert_git_fixture(
            &root.0,
            &[
                "config",
                "user.signingkey",
                signing_key.to_str().expect("UTF-8 signing key path"),
            ],
        );
        assert_git_fixture(
            &root.0,
            &[
                "config",
                "gpg.ssh.allowedSignersFile",
                allowed_signers
                    .to_str()
                    .expect("UTF-8 allowed signers path"),
            ],
        );
        assert_git_fixture(
            &root.0,
            &["tag", "-s", "signed-release", "-m", "signed release"],
        );

        assert_eq!(
            verify_exact_annotated_signed_tag(&root.0, &commit)
                .expect("exact SSH signed annotated tag"),
            "signed-release"
        );

        fs::write(root.0.join("x-terminal/Package.swift"), b"// next commit\n")
            .expect("update release fixture");
        assert_git_fixture(&root.0, &["add", "x-terminal/Package.swift"]);
        assert_git_fixture(&root.0, &["commit", "-q", "-m", "untagged next commit"]);
        let next_commit = git_output(&root.0, &["rev-parse", "HEAD"]).expect("next commit");
        assert!(verify_exact_annotated_signed_tag(&root.0, &next_commit).is_err());
    }

    #[test]
    fn artifact_paths_cannot_escape_or_use_symlinks() {
        assert!(is_safe_relative_path(
            "X-Terminal.app/Contents/MacOS/XTerminal"
        ));
        assert!(!is_safe_relative_path("../XTerminal"));
        assert!(!is_safe_relative_path("/tmp/XTerminal"));
        assert!(!is_safe_relative_path("app/./XTerminal"));
    }
}
