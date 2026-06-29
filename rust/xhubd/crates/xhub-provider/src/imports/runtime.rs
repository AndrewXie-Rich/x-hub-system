use std::path::Path;

use super::*;

pub fn import_provider_keys_to_runtime_base_dir(
    runtime_base_dir: &Path,
    auth_dir: &str,
    config_path: &str,
    imported_at_ms: u64,
) -> Result<ProviderKeyImportResult, ProviderRouteError> {
    let auth_dir = trim_string(auth_dir);
    let config_path = trim_string(config_path);
    if auth_dir.is_empty() && config_path.is_empty() {
        return Ok(ProviderKeyImportResult {
            ok: false,
            imported: 0,
            errors: vec!["missing_import_path".to_string()],
        });
    }

    let mut overall_ok = true;
    let mut imported = 0_u32;
    let mut errors = Vec::new();
    let now_ms = if imported_at_ms == 0 {
        current_time_millis()
    } else {
        imported_at_ms
    };

    if !auth_dir.is_empty() {
        let result = import_auth_dir_to_runtime_base_dir(runtime_base_dir, &auth_dir, now_ms)?;
        overall_ok = overall_ok && result.ok;
        imported = imported.saturating_add(result.imported);
        errors.extend(result.errors);
    }

    if !config_path.is_empty() {
        let result =
            import_proxy_config_to_runtime_base_dir(runtime_base_dir, &config_path, now_ms)?;
        overall_ok = overall_ok && result.ok;
        imported = imported.saturating_add(result.imported);
        errors.extend(result.errors);
    }

    Ok(ProviderKeyImportResult {
        ok: overall_ok && errors.is_empty(),
        imported,
        errors,
    })
}

pub fn import_auth_dir_to_runtime_base_dir(
    runtime_base_dir: &Path,
    auth_dir_path: &str,
    imported_at_ms: u64,
) -> Result<ProviderKeyImportResult, ProviderRouteError> {
    let source_ref = normalize_path_ref(Path::new(auth_dir_path));
    if source_ref.is_empty() || !Path::new(&source_ref).exists() {
        return Ok(ProviderKeyImportResult {
            ok: false,
            imported: 0,
            errors: Vec::new(),
        });
    }

    let now_ms = if imported_at_ms == 0 {
        current_time_millis()
    } else {
        imported_at_ms
    };
    let store_path = runtime_base_dir.join(PROVIDER_STORE_FILE_NAME);
    let mut store_value = load_provider_store_value_for_import(&store_path)?;
    let overlay = ImportOverlay {
        import_source_kind: "auth_dir".to_string(),
        import_source_ref: source_ref.clone(),
        ..ImportOverlay::default()
    };
    let build = build_imported_auth_accounts(
        &collect_auth_json_files(Path::new(&source_ref), None),
        &overlay,
        now_ms,
    );
    let applied = apply_imported_accounts_to_store(
        &mut store_value,
        &build.accounts,
        "auth_dir",
        &source_ref,
        build.errors.is_empty(),
        now_ms,
    )?;
    let mut errors = build.errors;
    errors.extend(applied.errors);
    record_import_source_status_in_store(
        &mut store_value,
        "auth_dir",
        &source_ref,
        if errors.is_empty() {
            "ready"
        } else {
            "sync_failed"
        },
        applied.imported,
        &errors,
        now_ms,
    );
    set_json_u64_object(&mut store_value, "updated_at_ms", now_ms);
    write_provider_store_value_atomic(&store_path, &store_value)?;

    Ok(ProviderKeyImportResult {
        ok: errors.is_empty(),
        imported: applied.imported,
        errors,
    })
}

pub fn import_proxy_config_to_runtime_base_dir(
    runtime_base_dir: &Path,
    config_path: &str,
    imported_at_ms: u64,
) -> Result<ProviderKeyImportResult, ProviderRouteError> {
    let source_ref = normalize_path_ref(Path::new(config_path));
    if source_ref.is_empty() || !Path::new(&source_ref).is_file() {
        return Ok(ProviderKeyImportResult {
            ok: false,
            imported: 0,
            errors: Vec::new(),
        });
    }

    let now_ms = if imported_at_ms == 0 {
        current_time_millis()
    } else {
        imported_at_ms
    };
    let store_path = runtime_base_dir.join(PROVIDER_STORE_FILE_NAME);
    let mut store_value = load_provider_store_value_for_import(&store_path)?;
    let build = build_imported_proxy_config_accounts(Path::new(&source_ref), now_ms);
    let applied = apply_imported_accounts_to_store(
        &mut store_value,
        &build.accounts,
        "config_path",
        &source_ref,
        build.errors.is_empty(),
        now_ms,
    )?;
    let mut errors = build.errors;
    errors.extend(applied.errors);
    record_import_source_status_in_store(
        &mut store_value,
        "config_path",
        &source_ref,
        if errors.is_empty() {
            "ready"
        } else {
            "sync_failed"
        },
        applied.imported,
        &errors,
        now_ms,
    );
    set_json_u64_object(&mut store_value, "updated_at_ms", now_ms);
    write_provider_store_value_atomic(&store_path, &store_value)?;

    Ok(ProviderKeyImportResult {
        ok: errors.is_empty(),
        imported: applied.imported,
        errors,
    })
}
