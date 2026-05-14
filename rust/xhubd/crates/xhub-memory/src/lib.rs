use std::collections::{BTreeSet, HashSet};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use serde::Serialize;
use serde_json::{json, Value};

pub const MEMORY_RETRIEVAL_RESULT_SCHEMA: &str = "xt.memory_retrieval_result.v1";
pub const MEMORY_WRITE_RESULT_SCHEMA: &str = "xhub.rust_hub.memory_write_result.v1";
pub const MEMORY_ENTRY_SCHEMA: &str = "xhub.rust_hub.memory_entry.v1";
pub const RUST_MEMORY_SHADOW_SOURCE: &str = "rust_hub_memory_shadow_v1";
pub const RUST_MEMORY_WRITER_SOURCE: &str = "rust_hub_memory_writer_v1";
static MEMORY_WRITE_COUNTER: AtomicU64 = AtomicU64::new(1);

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MemoryMode {
    AssistantPersonal,
    ProjectCode,
}

impl MemoryMode {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::AssistantPersonal => "assistant_personal",
            Self::ProjectCode => "project_code",
        }
    }

    pub fn from_str(input: &str) -> Self {
        match input.trim().to_ascii_lowercase().as_str() {
            "assistant_personal" | "assistant" | "personal" | "project_chat" => {
                Self::AssistantPersonal
            }
            _ => Self::ProjectCode,
        }
    }
}

#[derive(Debug, Clone)]
pub struct RetrievalPlan {
    pub mode: MemoryMode,
    pub include_dialogue_window: bool,
    pub include_project_capsule: bool,
    pub include_personal_capsule: bool,
    pub fail_closed: bool,
}

impl RetrievalPlan {
    pub fn project_default() -> Self {
        Self {
            mode: MemoryMode::ProjectCode,
            include_dialogue_window: true,
            include_project_capsule: true,
            include_personal_capsule: false,
            fail_closed: true,
        }
    }

    pub fn for_mode(mode: MemoryMode) -> Self {
        match mode {
            MemoryMode::AssistantPersonal => Self {
                mode,
                include_dialogue_window: true,
                include_project_capsule: true,
                include_personal_capsule: true,
                fail_closed: true,
            },
            MemoryMode::ProjectCode => Self::project_default(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct MemoryRetrievalRequest {
    pub request_id: String,
    pub memory_dir: PathBuf,
    pub scope: String,
    pub mode: MemoryMode,
    pub project_id: String,
    pub query: String,
    pub latest_user: String,
    pub retrieval_kind: String,
    pub max_results: usize,
    pub max_snippet_chars: usize,
    pub requested_kinds: Vec<String>,
    pub explicit_refs: Vec<String>,
    pub audit_ref: String,
}

impl MemoryRetrievalRequest {
    pub fn with_defaults(memory_dir: PathBuf) -> Self {
        Self {
            request_id: String::new(),
            memory_dir,
            scope: "current_project".to_string(),
            mode: MemoryMode::ProjectCode,
            project_id: String::new(),
            query: String::new(),
            latest_user: String::new(),
            retrieval_kind: "search".to_string(),
            max_results: 5,
            max_snippet_chars: 480,
            requested_kinds: Vec::new(),
            explicit_refs: Vec::new(),
            audit_ref: String::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct MemoryRetrievalItem {
    #[serde(rename = "ref")]
    pub ref_id: String,
    pub source_kind: String,
    pub summary: String,
    pub snippet: String,
    pub score: f64,
    pub redacted: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct MemoryRetrievalResponse {
    pub schema_version: String,
    pub request_id: String,
    pub status: String,
    pub resolved_scope: String,
    pub source: String,
    pub scope: String,
    pub audit_ref: String,
    pub reason_code: String,
    pub deny_code: String,
    pub results: Vec<MemoryRetrievalItem>,
    pub truncated: bool,
    pub budget_used_chars: i32,
    pub truncated_items: i32,
    pub redacted_items: i32,
}

#[derive(Debug, Clone)]
pub struct MemoryWriteRequest {
    pub request_id: String,
    pub memory_dir: PathBuf,
    pub scope: String,
    pub mode: MemoryMode,
    pub project_id: String,
    pub source_kind: String,
    pub title: String,
    pub text: String,
    pub tags: Vec<String>,
    pub audit_ref: String,
    pub actor: String,
}

impl MemoryWriteRequest {
    pub fn with_defaults(memory_dir: PathBuf) -> Self {
        Self {
            request_id: String::new(),
            memory_dir,
            scope: "current_project".to_string(),
            mode: MemoryMode::ProjectCode,
            project_id: String::new(),
            source_kind: "project_capsule".to_string(),
            title: String::new(),
            text: String::new(),
            tags: Vec::new(),
            audit_ref: String::new(),
            actor: "rust_hub".to_string(),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct MemoryWriteResponse {
    pub schema_version: String,
    pub ok: bool,
    pub status: String,
    pub source: String,
    pub authority: String,
    pub writer_authority_in_rust: bool,
    pub request_id: String,
    pub audit_ref: String,
    pub scope: String,
    pub mode: String,
    pub project_id: String,
    pub source_kind: String,
    pub ref_id: String,
    pub relative_path: String,
    pub summary: String,
    pub bytes_written: usize,
    pub deny_code: String,
    pub error_code: String,
    pub detail_json_included: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct MemoryReadiness {
    pub schema_version: String,
    pub ok: bool,
    pub ready: bool,
    pub memory_dir: String,
    pub memory_dir_exists: bool,
    pub memory_dir_is_dir: bool,
    pub supported_file_count: usize,
    pub indexed_document_count: usize,
    pub skipped_file_count: usize,
    pub total_supported_bytes: u64,
    pub max_file_bytes: usize,
    pub fail_closed: bool,
    pub writer_authority_in_rust: bool,
    pub mode_default: String,
    pub deny_code: String,
}

#[derive(Debug, Clone)]
struct MemoryDocument {
    ref_id: String,
    source_kind: String,
    summary: String,
    text: String,
    sensitivity: String,
    redacted: bool,
}

#[derive(Debug, Clone, Default)]
struct ScanStats {
    supported_file_count: usize,
    indexed_document_count: usize,
    skipped_file_count: usize,
    total_supported_bytes: u64,
}

#[derive(Debug, Clone)]
pub struct MemoryIndexSnapshot {
    memory_dir: PathBuf,
    memory_dir_exists: bool,
    memory_dir_is_dir: bool,
    documents: Vec<MemoryDocument>,
    stats: ScanStats,
    scan_error: String,
}

const MAX_FILES: usize = 1000;
const MAX_FILE_BYTES: usize = 256 * 1024;
const MAX_TEXT_BYTES: usize = 32 * 1024;

pub fn readiness(memory_dir: &Path) -> MemoryReadiness {
    let snapshot = scan_memory_snapshot(memory_dir);
    readiness_from_snapshot(&snapshot)
}

pub fn scan_memory_snapshot(memory_dir: &Path) -> MemoryIndexSnapshot {
    let exists = memory_dir.exists();
    let is_dir = memory_dir.is_dir();
    let (documents, stats, scan_error) = if exists && is_dir {
        match scan_memory_documents(memory_dir) {
            Ok((documents, stats)) => (documents, stats, String::new()),
            Err(err) => (Vec::new(), ScanStats::default(), err),
        }
    } else {
        (Vec::new(), ScanStats::default(), String::new())
    };
    MemoryIndexSnapshot {
        memory_dir: memory_dir.to_path_buf(),
        memory_dir_exists: exists,
        memory_dir_is_dir: is_dir,
        documents,
        stats,
        scan_error,
    }
}

pub fn readiness_from_snapshot(snapshot: &MemoryIndexSnapshot) -> MemoryReadiness {
    readiness_from_snapshot_with_writer(snapshot, false)
}

pub fn readiness_from_snapshot_with_writer(
    snapshot: &MemoryIndexSnapshot,
    writer_authority_in_rust: bool,
) -> MemoryReadiness {
    let ready = snapshot.memory_dir_exists && snapshot.memory_dir_is_dir;
    MemoryReadiness {
        schema_version: "xhub.rust_hub.memory_readiness.v1".to_string(),
        ok: true,
        ready,
        memory_dir: snapshot.memory_dir.display().to_string(),
        memory_dir_exists: snapshot.memory_dir_exists,
        memory_dir_is_dir: snapshot.memory_dir_is_dir,
        supported_file_count: snapshot.stats.supported_file_count,
        indexed_document_count: snapshot.stats.indexed_document_count,
        skipped_file_count: snapshot.stats.skipped_file_count,
        total_supported_bytes: snapshot.stats.total_supported_bytes,
        max_file_bytes: MAX_FILE_BYTES,
        fail_closed: true,
        writer_authority_in_rust,
        mode_default: RetrievalPlan::project_default().mode.as_str().to_string(),
        deny_code: if ready {
            String::new()
        } else {
            "memory_dir_missing_or_not_directory".to_string()
        },
    }
}

pub fn write_memory_entry(
    request: MemoryWriteRequest,
    writer_authority_in_rust: bool,
) -> MemoryWriteResponse {
    let request_id = sanitize_public_text(&request.request_id).unwrap_or_default();
    let audit_ref = sanitize_public_text(&request.audit_ref).unwrap_or_default();
    let scope = normalize_scope(&request.scope);
    let mode = request.mode.as_str().to_string();
    let project_id = sanitize_public_token(&request.project_id).unwrap_or_default();
    let source_kind = sanitize_source_kind(&request.source_kind, &request.mode);
    let actor = sanitize_public_token(&request.actor).unwrap_or_else(|| "rust_hub".to_string());
    let tags = sanitize_tags(&request.tags);
    let title = sanitize_public_text(&request.title).unwrap_or_default();
    let text = request.text.trim().to_string();

    if !writer_authority_in_rust {
        return denied_write_response(
            request_id,
            audit_ref,
            scope,
            mode,
            project_id,
            source_kind,
            "memory_writer_authority_disabled",
        );
    }
    if !request.memory_dir.is_dir() {
        return denied_write_response(
            request_id,
            audit_ref,
            scope,
            mode,
            project_id,
            source_kind,
            "memory_dir_missing_or_not_directory",
        );
    }
    if text.is_empty() {
        return denied_write_response(
            request_id,
            audit_ref,
            scope,
            mode,
            project_id,
            source_kind,
            "memory_text_required",
        );
    }
    if text.len() > MAX_TEXT_BYTES {
        return denied_write_response(
            request_id,
            audit_ref,
            scope,
            mode,
            project_id,
            source_kind,
            "memory_text_too_large",
        );
    }
    if looks_like_secret(&text)
        || looks_like_secret(&title)
        || looks_like_secret(&audit_ref)
        || looks_like_secret(&actor)
        || tags.iter().any(|tag| looks_like_secret(tag))
    {
        return denied_write_response(
            request_id,
            audit_ref,
            scope,
            mode,
            project_id,
            source_kind,
            "memory_secret_pattern_denied",
        );
    }

    let created_at_ms = now_ms();
    let record_id = memory_record_id(&request_id, created_at_ms);
    let relative_path = format!("writes/{record_id}.json");
    let ref_id = format!("memory://rust/local/{relative_path}#chunk-1");
    let summary = first_non_empty(&[&title, &summarize_text(&text)]);
    let record = json!({
        "schema_version": MEMORY_ENTRY_SCHEMA,
        "source": RUST_MEMORY_WRITER_SOURCE,
        "created_at_ms": created_at_ms,
        "request_id": request_id,
        "audit_ref": audit_ref,
        "scope": scope,
        "mode": mode,
        "project_id": project_id,
        "source_kind": source_kind,
        "title": title,
        "summary": summary,
        "text": text,
        "tags": tags,
        "actor": actor,
        "ref": ref_id,
    });
    let serialized = match serde_json::to_string_pretty(&record) {
        Ok(value) => format!("{value}\n"),
        Err(_) => {
            return errored_write_response(
                "memory_record_serialize_failed",
                request_id,
                audit_ref,
                scope,
                mode,
                project_id,
                source_kind,
            )
        }
    };
    let path = request.memory_dir.join(&relative_path);
    if let Some(parent) = path.parent() {
        if let Err(err) = fs::create_dir_all(parent) {
            return errored_write_response(
                &format!("memory_write_dir_create_failed:{:?}", err.kind()),
                request_id,
                audit_ref,
                scope,
                mode,
                project_id,
                source_kind,
            );
        }
    }
    match OpenOptions::new().write(true).create_new(true).open(&path) {
        Ok(mut file) => {
            if let Err(err) = file.write_all(serialized.as_bytes()) {
                return errored_write_response(
                    &format!("memory_write_failed:{:?}", err.kind()),
                    request_id,
                    audit_ref,
                    scope,
                    mode,
                    project_id,
                    source_kind,
                );
            }
        }
        Err(err) => {
            return errored_write_response(
                &format!("memory_write_open_failed:{:?}", err.kind()),
                request_id,
                audit_ref,
                scope,
                mode,
                project_id,
                source_kind,
            )
        }
    }

    MemoryWriteResponse {
        schema_version: MEMORY_WRITE_RESULT_SCHEMA.to_string(),
        ok: true,
        status: "written".to_string(),
        source: RUST_MEMORY_WRITER_SOURCE.to_string(),
        authority: "canonical_writer".to_string(),
        writer_authority_in_rust: true,
        request_id,
        audit_ref,
        scope,
        mode,
        project_id,
        source_kind,
        ref_id,
        relative_path,
        summary,
        bytes_written: serialized.len(),
        deny_code: String::new(),
        error_code: String::new(),
        detail_json_included: false,
    }
}

pub fn retrieve_memory(request: MemoryRetrievalRequest) -> MemoryRetrievalResponse {
    if !request.memory_dir.is_dir() {
        let request_id = request.request_id.clone();
        let audit_ref = request.audit_ref.clone();
        let scope = normalize_scope(&request.scope);
        return denied_response(
            request_id,
            scope,
            audit_ref,
            "memory_dir_missing_or_not_directory",
        );
    }
    let snapshot = scan_memory_snapshot(&request.memory_dir);
    retrieve_memory_from_snapshot(request, &snapshot)
}

fn denied_write_response(
    request_id: String,
    audit_ref: String,
    scope: String,
    mode: String,
    project_id: String,
    source_kind: String,
    deny_code: &str,
) -> MemoryWriteResponse {
    MemoryWriteResponse {
        schema_version: MEMORY_WRITE_RESULT_SCHEMA.to_string(),
        ok: false,
        status: "denied".to_string(),
        source: RUST_MEMORY_WRITER_SOURCE.to_string(),
        authority: "canonical_writer".to_string(),
        writer_authority_in_rust: false,
        request_id,
        audit_ref,
        scope,
        mode,
        project_id,
        source_kind,
        ref_id: String::new(),
        relative_path: String::new(),
        summary: String::new(),
        bytes_written: 0,
        deny_code: deny_code.to_string(),
        error_code: String::new(),
        detail_json_included: false,
    }
}

fn errored_write_response(
    error_code: &str,
    request_id: String,
    audit_ref: String,
    scope: String,
    mode: String,
    project_id: String,
    source_kind: String,
) -> MemoryWriteResponse {
    MemoryWriteResponse {
        schema_version: MEMORY_WRITE_RESULT_SCHEMA.to_string(),
        ok: false,
        status: "error".to_string(),
        source: RUST_MEMORY_WRITER_SOURCE.to_string(),
        authority: "canonical_writer".to_string(),
        writer_authority_in_rust: true,
        request_id,
        audit_ref,
        scope,
        mode,
        project_id,
        source_kind,
        ref_id: String::new(),
        relative_path: String::new(),
        summary: String::new(),
        bytes_written: 0,
        deny_code: String::new(),
        error_code: error_code.to_string(),
        detail_json_included: false,
    }
}

pub fn retrieve_memory_from_snapshot(
    request: MemoryRetrievalRequest,
    snapshot: &MemoryIndexSnapshot,
) -> MemoryRetrievalResponse {
    let request_id = request.request_id.clone();
    let audit_ref = request.audit_ref.clone();
    let scope = normalize_scope(&request.scope);
    let retrieval_kind = normalize_token(&request.retrieval_kind);
    let plan = RetrievalPlan::for_mode(request.mode.clone());

    if query_requests_secret(&request.query) || query_requests_secret(&request.latest_user) {
        return denied_response(request_id, scope, audit_ref, "query_secret_pattern_denied");
    }

    if !snapshot.memory_dir_is_dir {
        return denied_response(
            request_id,
            scope,
            audit_ref,
            "memory_dir_missing_or_not_directory",
        );
    }
    if !snapshot.scan_error.is_empty() {
        return denied_response(request_id, scope, audit_ref, &snapshot.scan_error);
    }

    let requested_kinds = request
        .requested_kinds
        .iter()
        .map(|value| normalize_token(value))
        .filter(|value| !value.is_empty())
        .collect::<BTreeSet<_>>();
    let explicit_refs = request
        .explicit_refs
        .iter()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .collect::<BTreeSet<_>>();
    let mut redacted_items = 0_i32;
    let query_text = first_non_empty(&[&request.query, &request.latest_user]);
    let query_tokens = tokenize(&query_text);

    let mut scored = Vec::new();
    for document in snapshot.documents.iter().cloned() {
        if !document_allowed_by_plan(&document, &plan) {
            continue;
        }
        if !requested_kinds.is_empty() && !requested_kinds.contains(&document.source_kind) {
            continue;
        }
        if retrieval_kind == "get_ref" && !explicit_refs.contains(&document.ref_id) {
            continue;
        }
        if document.redacted || document.sensitivity == "secret" {
            redacted_items += 1;
            continue;
        }

        let score = if retrieval_kind == "get_ref" {
            1.0
        } else {
            lexical_score(&query_tokens, &document.text)
        };
        if retrieval_kind != "get_ref" && score <= 0.0 {
            continue;
        }
        scored.push((score, document));
    }

    scored.sort_by(|(left_score, left_doc), (right_score, right_doc)| {
        right_score
            .partial_cmp(left_score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| left_doc.ref_id.cmp(&right_doc.ref_id))
    });

    let limit = request.max_results.clamp(1, 50);
    let max_snippet_chars = request.max_snippet_chars.clamp(80, 4000);
    let mut budget_used_chars = 0_i32;
    let mut results = Vec::new();
    for (score, doc) in scored.iter().take(limit) {
        let snippet = snippet_for(&doc.text, &query_tokens, max_snippet_chars);
        budget_used_chars += snippet.chars().count() as i32;
        results.push(MemoryRetrievalItem {
            ref_id: doc.ref_id.clone(),
            source_kind: doc.source_kind.clone(),
            summary: doc.summary.clone(),
            snippet,
            score: round6(*score),
            redacted: false,
        });
    }

    let truncated_items = scored.len().saturating_sub(results.len()) as i32;
    MemoryRetrievalResponse {
        schema_version: MEMORY_RETRIEVAL_RESULT_SCHEMA.to_string(),
        request_id,
        status: if truncated_items > 0 {
            "truncated".to_string()
        } else {
            "ok".to_string()
        },
        resolved_scope: scope.clone(),
        source: RUST_MEMORY_SHADOW_SOURCE.to_string(),
        scope,
        audit_ref,
        reason_code: if snapshot.stats.indexed_document_count == 0 {
            "no_memory_documents".to_string()
        } else {
            "ok".to_string()
        },
        deny_code: String::new(),
        results,
        truncated: truncated_items > 0,
        budget_used_chars,
        truncated_items,
        redacted_items,
    }
}

fn denied_response(
    request_id: String,
    scope: String,
    audit_ref: String,
    deny_code: &str,
) -> MemoryRetrievalResponse {
    MemoryRetrievalResponse {
        schema_version: MEMORY_RETRIEVAL_RESULT_SCHEMA.to_string(),
        request_id,
        status: "denied".to_string(),
        resolved_scope: scope.clone(),
        source: RUST_MEMORY_SHADOW_SOURCE.to_string(),
        scope,
        audit_ref,
        reason_code: "fail_closed".to_string(),
        deny_code: deny_code.to_string(),
        results: Vec::new(),
        truncated: false,
        budget_used_chars: 0,
        truncated_items: 0,
        redacted_items: 0,
    }
}

fn scan_memory_documents(memory_dir: &Path) -> Result<(Vec<MemoryDocument>, ScanStats), String> {
    let mut files = Vec::new();
    collect_supported_files(memory_dir, memory_dir, 0, &mut files)?;
    files.sort();
    let mut stats = ScanStats::default();
    let mut documents = Vec::new();

    for path in files.into_iter().take(MAX_FILES) {
        let metadata = match fs::metadata(&path) {
            Ok(value) => value,
            Err(_) => {
                stats.skipped_file_count += 1;
                continue;
            }
        };
        if metadata.len() as usize > MAX_FILE_BYTES {
            stats.skipped_file_count += 1;
            continue;
        }
        stats.supported_file_count += 1;
        stats.total_supported_bytes += metadata.len();
        let raw = match fs::read_to_string(&path) {
            Ok(value) => value,
            Err(_) => {
                stats.skipped_file_count += 1;
                continue;
            }
        };
        let mut next_docs = documents_from_file(memory_dir, &path, &raw);
        stats.indexed_document_count += next_docs.len();
        documents.append(&mut next_docs);
    }

    Ok((documents, stats))
}

fn collect_supported_files(
    root: &Path,
    dir: &Path,
    depth: usize,
    out: &mut Vec<PathBuf>,
) -> Result<(), String> {
    if depth > 8 || out.len() >= MAX_FILES {
        return Ok(());
    }
    let entries =
        fs::read_dir(dir).map_err(|err| format!("memory_dir_read_failed:{:?}", err.kind()))?;
    for entry in entries.filter_map(Result::ok) {
        let path = entry.path();
        let file_name = path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or("");
        if should_skip_path(file_name) {
            continue;
        }
        if path.is_dir() {
            collect_supported_files(root, &path, depth + 1, out)?;
        } else if is_supported_memory_file(&path) {
            let _ = root;
            out.push(path);
        }
        if out.len() >= MAX_FILES {
            break;
        }
    }
    Ok(())
}

fn documents_from_file(root: &Path, path: &Path, raw: &str) -> Vec<MemoryDocument> {
    let rel = path.strip_prefix(root).unwrap_or(path);
    let rel_text = rel.to_string_lossy().replace('\\', "/");
    let ext = path
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if ext == "jsonl" {
        return raw
            .lines()
            .enumerate()
            .filter_map(|(idx, line)| {
                let line = line.trim();
                if line.is_empty() {
                    return None;
                }
                let text = match serde_json::from_str::<Value>(line) {
                    Ok(value) => collect_json_text(&value),
                    Err(_) => truncate_to_chars(line, MAX_TEXT_BYTES),
                };
                Some(document_from_text(
                    rel_text.as_str(),
                    &format!("line-{}", idx + 1),
                    text,
                ))
            })
            .collect();
    }

    let text = if ext == "json" {
        match serde_json::from_str::<Value>(raw) {
            Ok(value) => collect_json_text(&value),
            Err(_) => truncate_to_chars(raw, MAX_TEXT_BYTES),
        }
    } else {
        truncate_to_chars(raw, MAX_TEXT_BYTES)
    };
    vec![document_from_text(rel_text.as_str(), "chunk-1", text)]
}

fn document_from_text(relative_path: &str, chunk_id: &str, text: String) -> MemoryDocument {
    let source_kind = infer_source_kind(relative_path);
    let sensitivity = infer_sensitivity(relative_path, &text);
    let redacted = sensitivity == "secret";
    let summary = if redacted {
        "redacted by Rust memory policy".to_string()
    } else {
        summarize_text(&text)
    };
    MemoryDocument {
        ref_id: format!(
            "memory://rust/local/{}#{}",
            stable_ref_path(relative_path),
            chunk_id
        ),
        source_kind,
        summary,
        text,
        sensitivity,
        redacted,
    }
}

fn document_allowed_by_plan(document: &MemoryDocument, plan: &RetrievalPlan) -> bool {
    if document.sensitivity == "secret" {
        return false;
    }
    match document.source_kind.as_str() {
        "personal_capsule" => plan.include_personal_capsule,
        "project_capsule" => plan.include_project_capsule,
        "dialogue_window" => plan.include_dialogue_window,
        _ => true,
    }
}

fn collect_json_text(value: &Value) -> String {
    let mut out = Vec::new();
    collect_json_text_inner(value, "", &mut out);
    truncate_to_chars(&out.join("\n"), MAX_TEXT_BYTES)
}

fn collect_json_text_inner(value: &Value, key: &str, out: &mut Vec<String>) {
    if is_sensitive_key(key) {
        return;
    }
    match value {
        Value::String(text) => {
            let trimmed = text.trim();
            if !trimmed.is_empty() && !looks_like_secret(trimmed) {
                out.push(trimmed.to_string());
            }
        }
        Value::Array(items) => {
            for item in items.iter().take(64) {
                collect_json_text_inner(item, key, out);
            }
        }
        Value::Object(map) => {
            for (next_key, next_value) in map.iter() {
                collect_json_text_inner(next_value, next_key, out);
            }
        }
        _ => {}
    }
}

fn is_supported_memory_file(path: &Path) -> bool {
    matches!(
        path.extension()
            .and_then(|value| value.to_str())
            .map(|value| value.to_ascii_lowercase())
            .as_deref(),
        Some("json" | "jsonl" | "md" | "txt")
    )
}

fn should_skip_path(file_name: &str) -> bool {
    matches!(
        file_name,
        ".git" | "node_modules" | "target" | "dist" | ".DS_Store"
    )
}

fn infer_source_kind(relative_path: &str) -> String {
    let lower = relative_path.to_ascii_lowercase();
    if lower.contains("personal") {
        "personal_capsule".to_string()
    } else if lower.contains("dialogue") || lower.contains("turn") || lower.contains("thread") {
        "dialogue_window".to_string()
    } else if lower.contains("capsule") || lower.contains("project") {
        "project_capsule".to_string()
    } else if lower.contains("guidance") {
        "guidance_injection".to_string()
    } else if lower.contains("checkpoint") {
        "automation_checkpoint".to_string()
    } else if lower.contains("handoff") {
        "automation_handoff".to_string()
    } else {
        "memory_file".to_string()
    }
}

fn infer_sensitivity(relative_path: &str, text: &str) -> String {
    let haystack = format!(
        "{}\n{}",
        relative_path.to_ascii_lowercase(),
        text.to_ascii_lowercase()
    );
    if looks_like_secret(&haystack) {
        "secret".to_string()
    } else if haystack.contains("private") || haystack.contains("personal") {
        "private".to_string()
    } else {
        "internal".to_string()
    }
}

fn query_requests_secret(query: &str) -> bool {
    let lower = query.to_ascii_lowercase();
    [
        "api key",
        "apikey",
        "secret",
        "password",
        "private key",
        "token",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
}

fn looks_like_secret(value: &str) -> bool {
    let lower = value.to_ascii_lowercase();
    [
        "api_key",
        "apikey",
        "secret",
        "password",
        "private_key",
        "authorization:",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
        || lower.contains("sk-")
        || lower.contains("bearer ")
}

fn is_sensitive_key(key: &str) -> bool {
    let lower = key.to_ascii_lowercase();
    [
        "api_key",
        "apikey",
        "secret",
        "password",
        "private_key",
        "token",
        "authorization",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
}

fn lexical_score(query_tokens: &[String], text: &str) -> f64 {
    if query_tokens.is_empty() {
        return 0.05;
    }
    let doc_tokens = tokenize(text).into_iter().collect::<HashSet<_>>();
    if doc_tokens.is_empty() {
        return 0.0;
    }
    let matches = query_tokens
        .iter()
        .filter(|token| doc_tokens.contains(*token))
        .count();
    if matches == 0 {
        return 0.0;
    }
    let coverage = matches as f64 / query_tokens.len().max(1) as f64;
    let density = matches as f64 / doc_tokens.len().max(1) as f64;
    (coverage * 0.85) + (density * 0.15)
}

fn tokenize(text: &str) -> Vec<String> {
    let mut tokens = BTreeSet::new();
    let mut current = String::new();
    for ch in text.chars() {
        if ch.is_alphanumeric() || ch == '_' || ch == '-' {
            current.push(ch.to_ascii_lowercase());
        } else {
            push_token(&mut tokens, &mut current);
        }
    }
    push_token(&mut tokens, &mut current);
    tokens.into_iter().collect()
}

fn push_token(tokens: &mut BTreeSet<String>, current: &mut String) {
    let token = current.trim_matches('-').to_string();
    if token.chars().count() >= 2 {
        tokens.insert(token);
    }
    current.clear();
}

fn snippet_for(text: &str, query_tokens: &[String], max_chars: usize) -> String {
    let lower = text.to_ascii_lowercase();
    let start_byte = query_tokens
        .iter()
        .filter_map(|token| lower.find(token))
        .min()
        .unwrap_or(0);
    let start_char = text[..start_byte.min(text.len())].chars().count();
    let window_start = start_char.saturating_sub(max_chars / 5);
    truncate_to_chars_from(text, window_start, max_chars)
        .replace('\n', " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn summarize_text(text: &str) -> String {
    let first_line = text
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or("");
    truncate_to_chars(first_line, 160)
}

fn truncate_to_chars(text: &str, max_chars: usize) -> String {
    text.chars().take(max_chars).collect()
}

fn truncate_to_chars_from(text: &str, start_char: usize, max_chars: usize) -> String {
    text.chars().skip(start_char).take(max_chars).collect()
}

fn stable_ref_path(relative_path: &str) -> String {
    relative_path
        .chars()
        .map(|ch| match ch {
            '/' | '.' | '-' | '_' => ch,
            c if c.is_ascii_alphanumeric() => c,
            ' ' => '_',
            _ => '_',
        })
        .collect()
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .min(i64::MAX as u128) as i64
}

fn memory_record_id(request_id: &str, created_at_ms: i64) -> String {
    let counter = MEMORY_WRITE_COUNTER.fetch_add(1, Ordering::Relaxed);
    let request = sanitize_public_token(request_id).unwrap_or_default();
    if request.is_empty() {
        format!("entry_{created_at_ms}_{}_{}", std::process::id(), counter)
    } else {
        format!("entry_{created_at_ms}_{}_{}", request, counter)
    }
}

fn normalize_scope(scope: &str) -> String {
    match scope.trim() {
        "" => "current_project".to_string(),
        value => value.to_string(),
    }
}

fn normalize_token(input: &str) -> String {
    input.trim().to_ascii_lowercase().replace('-', "_")
}

fn sanitize_source_kind(source_kind: &str, mode: &MemoryMode) -> String {
    let normalized = sanitize_public_token(source_kind).unwrap_or_default();
    match normalized.as_str() {
        "dialogue_window"
        | "project_capsule"
        | "personal_capsule"
        | "guidance_injection"
        | "automation_checkpoint"
        | "automation_handoff"
        | "memory_file" => normalized,
        _ => match mode {
            MemoryMode::AssistantPersonal => "personal_capsule".to_string(),
            MemoryMode::ProjectCode => "project_capsule".to_string(),
        },
    }
}

fn sanitize_tags(tags: &[String]) -> Vec<String> {
    let mut out = tags
        .iter()
        .filter_map(|tag| sanitize_public_token(tag))
        .take(32)
        .collect::<Vec<_>>();
    out.sort();
    out.dedup();
    out
}

fn sanitize_public_token(raw: &str) -> Option<String> {
    let value = raw.trim();
    if value.is_empty() || looks_like_secret(value) {
        return None;
    }
    let normalized = value
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.' | ':' | '/'))
        .collect::<String>();
    if normalized.is_empty() {
        None
    } else {
        Some(normalized.chars().take(96).collect())
    }
}

fn sanitize_public_text(raw: &str) -> Option<String> {
    let value = raw.trim();
    if value.is_empty() || looks_like_secret(value) {
        return None;
    }
    let filtered = value
        .chars()
        .filter(|ch| ch.is_ascii() && !ch.is_control())
        .collect::<String>();
    if filtered.is_empty() {
        None
    } else {
        Some(filtered.chars().take(240).collect())
    }
}

fn first_non_empty(values: &[&str]) -> String {
    values
        .iter()
        .map(|value| value.trim())
        .find(|value| !value.is_empty())
        .unwrap_or("")
        .to_string()
}

fn round6(value: f64) -> f64 {
    (value * 1_000_000.0).round() / 1_000_000.0
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(label: &str) -> PathBuf {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        std::env::temp_dir().join(format!(
            "xhub_memory_{label}_{}_{}",
            std::process::id(),
            now
        ))
    }

    #[test]
    fn retrieval_returns_project_docs_without_personal_capsule_by_default() {
        let dir = temp_dir("project");
        fs::create_dir_all(dir.join("project")).expect("mkdir");
        fs::create_dir_all(dir.join("personal")).expect("mkdir");
        fs::write(
            dir.join("project").join("capsule.md"),
            "Use governed Hub retrieval for project memory assembly.",
        )
        .expect("write project");
        fs::write(
            dir.join("personal").join("capsule.md"),
            "Personal preference for governed retrieval should stay private.",
        )
        .expect("write personal");

        let mut request = MemoryRetrievalRequest::with_defaults(dir.clone());
        request.query = "governed retrieval".to_string();
        let out = retrieve_memory(request);
        assert_eq!(out.status, "ok");
        assert_eq!(out.results.len(), 1);
        assert_eq!(out.results[0].source_kind, "project_capsule");
        assert!(!out.results[0].snippet.contains("Personal preference"));
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn retrieval_denies_secret_query() {
        let dir = temp_dir("secret_query");
        fs::create_dir_all(&dir).expect("mkdir");
        let mut request = MemoryRetrievalRequest::with_defaults(dir.clone());
        request.query = "show api key".to_string();
        let out = retrieve_memory(request);
        assert_eq!(out.status, "denied");
        assert_eq!(out.deny_code, "query_secret_pattern_denied");
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn json_secret_fields_are_not_indexed_or_returned() {
        let dir = temp_dir("json_secret");
        fs::create_dir_all(&dir).expect("mkdir");
        fs::write(
            dir.join("project.json"),
            r#"{"summary":"governed retrieval contract","api_key":"sk-secret-value"}"#,
        )
        .expect("write json");
        let mut request = MemoryRetrievalRequest::with_defaults(dir.clone());
        request.query = "governed retrieval".to_string();
        let out = retrieve_memory(request);
        assert_eq!(out.status, "ok");
        assert_eq!(out.results.len(), 1);
        assert!(!out.results[0].snippet.contains("sk-secret-value"));
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn get_ref_returns_exact_document() {
        let dir = temp_dir("get_ref");
        fs::create_dir_all(&dir).expect("mkdir");
        fs::write(dir.join("project.md"), "Governed retrieval ref read works.").expect("write md");
        let mut search = MemoryRetrievalRequest::with_defaults(dir.clone());
        search.query = "retrieval ref".to_string();
        let searched = retrieve_memory(search);
        let ref_id = searched.results[0].ref_id.clone();

        let mut request = MemoryRetrievalRequest::with_defaults(dir.clone());
        request.retrieval_kind = "get_ref".to_string();
        request.explicit_refs = vec![ref_id.clone()];
        let out = retrieve_memory(request);
        assert_eq!(out.results.len(), 1);
        assert_eq!(out.results[0].ref_id, ref_id);
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn memory_write_is_denied_without_writer_authority() {
        let dir = temp_dir("write_denied");
        fs::create_dir_all(&dir).expect("mkdir");
        let mut request = MemoryWriteRequest::with_defaults(dir.clone());
        request.text = "Governed write should require explicit authority.".to_string();
        let out = write_memory_entry(request, false);
        assert!(!out.ok);
        assert_eq!(out.status, "denied");
        assert_eq!(out.deny_code, "memory_writer_authority_disabled");
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn memory_write_creates_retrievable_json_entry_without_secret_leak() {
        let dir = temp_dir("write_ok");
        fs::create_dir_all(&dir).expect("mkdir");
        let mut request = MemoryWriteRequest::with_defaults(dir.clone());
        request.request_id = "write-ok".to_string();
        request.title = "Rust governed write".to_string();
        request.text =
            "Governed Rust memory writer creates retrievable project memory.".to_string();
        request.tags = vec!["memory.write".to_string(), "project".to_string()];
        let out = write_memory_entry(request, true);
        assert!(out.ok);
        assert!(dir.join(out.relative_path).is_file());

        let mut retrieve = MemoryRetrievalRequest::with_defaults(dir.clone());
        retrieve.query = "governed writer retrievable".to_string();
        let found = retrieve_memory(retrieve);
        assert_eq!(found.status, "ok");
        assert_eq!(found.results.len(), 1);
        assert!(!serde_json::to_string(&found)
            .unwrap()
            .contains("detail_json"));
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn memory_write_rejects_secret_text() {
        let dir = temp_dir("write_secret");
        fs::create_dir_all(&dir).expect("mkdir");
        let mut request = MemoryWriteRequest::with_defaults(dir.clone());
        request.text = "store sk-secret-value".to_string();
        let out = write_memory_entry(request, true);
        assert!(!out.ok);
        assert_eq!(out.deny_code, "memory_secret_pattern_denied");
        let _ = fs::remove_dir_all(dir);
    }
}
