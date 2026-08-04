use std::fs;
use std::path::PathBuf;

fn repository_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|path| path.parent())
        .expect("xtd must live under <repository>/rust/xtd")
        .to_path_buf()
}

#[test]
fn app_build_hashes_final_signed_binaries_and_verifies_detached_manifest() {
    let script =
        fs::read_to_string(repository_root().join("x-terminal/tools/build_xterminal_app.command"))
            .expect("read X-Terminal app builder");

    assert!(script.contains("PROVENANCE_MANIFEST=\"$OUT_DIR/X-Terminal.provenance.json\""));
    assert!(script.contains("--swift-path \"X-Terminal.app/Contents/MacOS/XTerminal\""));
    assert!(script.contains("--xtd-path \"X-Terminal.app/Contents/Resources/xtd\""));
    assert!(script.contains("--inventory-root \"X-Terminal.app\""));
    assert!(script.contains("PROVENANCE_CREATE_ARGS+=(--source-date-epoch \"$SOURCE_DATE_EPOCH\")"));
    assert!(script.contains("PROVENANCE_CREATE_ARGS+=(--release)"));
    assert!(script.contains("PROVENANCE_VERIFY_ARGS+=(--require-release)"));
    assert!(script.contains("INSTALLED_VERIFY_ARGS+=(--require-release)"));
    assert!(script.contains("Refusing existing install target containing symlinks."));
    assert!(script.contains("\"$INSTALL_TARGET_EXPANDED/Contents/Resources/xtd\""));
    assert!(script.contains("codesign --verify --deep --strict \"$INSTALL_TARGET_EXPANDED\""));

    let signature_verify = script
        .find("codesign --verify --deep --strict \"$APP_DIR\"")
        .expect("signature verification");
    let manifest_create = script
        .find("\"$EMBEDDED_XTD\" \"${PROVENANCE_CREATE_ARGS[@]}\" >/dev/null")
        .expect("manifest creation");
    let manifest_verify = script
        .find("\"$EMBEDDED_XTD\" \"${PROVENANCE_VERIFY_ARGS[@]}\" >/dev/null")
        .expect("manifest verification");
    assert!(signature_verify < manifest_create);
    assert!(manifest_create < manifest_verify);
}

#[test]
fn runtime_package_reverifies_build_and_covers_both_xtd_copies_before_archiving() {
    let script =
        fs::read_to_string(repository_root().join("x-terminal/tools/package_xt_runtime.command"))
            .expect("read XT runtime packager");

    assert!(script.contains("BUILD_PROVENANCE=\"$BUILD_OUT_DIR/X-Terminal.provenance.json\""));
    assert!(script.contains("--xtd-path \"app/X-Terminal.app/Contents/Resources/xtd\""));
    assert!(script.contains("--packaged-xtd-path \"bin/xtd\""));
    assert!(script.contains("--inventory-root \".\""));
    assert!(script.contains("\"$SCRIPT_DIR/bin/xtd\" provenance verify"));
    assert!(script.contains("codesign --verify --deep --strict \"$SCRIPT_DIR/app/X-Terminal.app\""));
    assert!(script.contains("Refusing to overwrite an existing XT runtime package or archive."));
    assert!(!script.contains("rm -rf \"$PACKAGE_DIR\""));

    let build_verify = script
        .find("\"$RUST_XTD_DIR/target/release/xtd\" \"${BUILD_VERIFY_ARGS[@]}\" >/dev/null")
        .expect("build provenance verification");
    let package_create = script
        .find("\"$PACKAGED_XTD\" \"${PROVENANCE_CREATE_ARGS[@]}\" >/dev/null")
        .expect("package provenance creation");
    let package_verify = script
        .find("\"$PACKAGED_XTD\" \"${PROVENANCE_VERIFY_ARGS[@]}\" >/dev/null")
        .expect("package provenance verification");
    let archive = script
        .find("ditto -c -k --keepParent \"$PACKAGE_NAME\" \"$ARCHIVE_PATH\"")
        .expect("package archive creation");
    let extracted_verify = script
        .find("\"$EXTRACTED_PACKAGE/bin/xtd\" \"${EXTRACTED_VERIFY_ARGS[@]}\" >/dev/null")
        .expect("extracted archive provenance verification");
    assert!(build_verify < package_create);
    assert!(package_create < package_verify);
    assert!(package_verify < archive);
    assert!(archive < extracted_verify);
}

#[test]
fn release_dmgs_carry_and_reverify_signed_xt_provenance() {
    let root = repository_root();
    let xt_dmg = fs::read_to_string(root.join("x-terminal/tools/build_xterminal_dmg.command"))
        .expect("read X-Terminal DMG builder");
    let system_release = fs::read_to_string(root.join("scripts/package_macos_release.command"))
        .expect("read system release packager");

    assert!(xt_dmg.contains("X-Terminal.provenance.json"));
    assert!(xt_dmg.contains("verify_xt_artifact_root \"$STAGE\""));
    assert!(xt_dmg.contains("--require-release"));
    assert!(xt_dmg.contains("codesign --force --sign \"$IDENTITY\" \"$OUT_DMG\""));
    assert!(xt_dmg.contains("hdiutil attach -nobrowse -readonly"));
    assert!(xt_dmg.contains("-mountpoint \"$MOUNT_POINT\" \"$OUT_DMG\""));
    assert!(xt_dmg.contains("verify_xt_artifact_root \"$MOUNT_POINT\""));
    assert!(xt_dmg.contains("normalize_dmg_output_path"));
    assert!(xt_dmg.contains("detach_mount"));
    assert!(!xt_dmg.contains("hdiutil detach \"$MOUNT_POINT\" >/dev/null 2>&1 || true"));

    let xt_app_signature = xt_dmg
        .find("xterminal_verify_pinned_codesign \"$app\" \"$ROOT_DIR\" 1")
        .expect("XT app pinned Team ID verification");
    let xt_verifier_signature = xt_dmg
        .find("xterminal_verify_pinned_codesign \"$verifier\" \"$ROOT_DIR\" 0")
        .expect("XT verifier pinned Team ID verification");
    let xt_provenance = xt_dmg
        .find("\"$verifier\" \"${verify_args[@]}\"")
        .expect("XT provenance verification");
    assert!(xt_app_signature < xt_verifier_signature);
    assert!(xt_verifier_signature < xt_provenance);

    assert!(system_release.contains(
        "cp -f \"$ROOT_DIR/build/X-Terminal.provenance.json\" \\\n  \"$SYSTEM_STAGE/X-Terminal.provenance.json\""
    ));
    assert!(system_release.contains("verify_release_xt_artifact_root \"$SYSTEM_STAGE\""));
    assert!(system_release.contains("sign_and_verify_release_disk_image \"$SYSTEM_DMG\""));
    assert!(
        system_release.contains("verify_release_xt_artifact_root \"$COMBINED_DMG_MOUNT_POINT\"")
    );
    assert!(system_release.contains("XTERMINAL_RELEASE_BUILD=1"));
    assert!(system_release.contains("XTERMINAL_CODESIGN_IDENTITY=\"$RELEASE_CODESIGN_IDENTITY\""));

    let release_app_signature = system_release
        .find("xterminal_verify_pinned_codesign \"$app\" \"$ROOT_DIR\" 1")
        .expect("release XT app pinned Team ID verification");
    let release_verifier_signature = system_release
        .find("xterminal_verify_pinned_codesign \"$verifier\" \"$ROOT_DIR\" 0")
        .expect("release XT verifier pinned Team ID verification");
    let release_provenance = system_release
        .find("\"$verifier\" provenance verify")
        .expect("release XT provenance verification");
    assert!(release_app_signature < release_verifier_signature);
    assert!(release_verifier_signature < release_provenance);

    let hub_dmg_sign = system_release
        .find("sign_and_verify_release_disk_image \"$HUB_DMG\"")
        .expect("Hub DMG signing");
    let hub_dmg_mount = system_release[hub_dmg_sign..]
        .find("hdiutil attach -nobrowse -readonly")
        .expect("Hub DMG readonly mount")
        + hub_dmg_sign;
    let mounted_hub_verify = system_release[hub_dmg_mount..]
        .find("verify_release_hub_app \"$HUB_DMG_MOUNT_POINT/X-Hub.app\"")
        .expect("mounted Hub app Team ID verification")
        + hub_dmg_mount;
    let hub_dmg_detach = system_release[mounted_hub_verify..]
        .find("detach_hub_dmg_mount")
        .expect("strict Hub DMG detach")
        + mounted_hub_verify;
    assert!(hub_dmg_sign < hub_dmg_mount);
    assert!(hub_dmg_mount < mounted_hub_verify);
    assert!(mounted_hub_verify < hub_dmg_detach);

    // The XT builder already mounts and verifies its contents. The outer
    // packager rechecks the returned DMG signature before delivery.
    assert!(system_release.contains("xterminal_verify_pinned_codesign \"$XT_DMG\" \"$ROOT_DIR\" 0"));
    assert!(system_release.contains("xhub-hub-dmg-verify.XXXXXX"));
    assert!(system_release.contains("xhub-system-dmg-verify.XXXXXX"));
}
