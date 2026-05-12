use std::collections::BTreeMap;
use std::sync::atomic::{AtomicU64, Ordering};

use serde_json::{json, Value};
use xhub_core::{now_ms, HubConfig};
use xhub_db::{
    apply_baseline_migrations, read_evidence_ledger_summary, write_evidence_record,
    EvidenceLedgerRecord, EvidenceLedgerRow, EvidenceLedgerSummary,
};

const SCHEMA_VERSION: &str = "xhub.evidence_bridge.v1";
const LEDGER_SCHEMA_VERSION: &str = "xhub.evidence_ledger.v1";
static EVIDENCE_COUNTER: AtomicU64 = AtomicU64::new(1);

pub fn run(config: &HubConfig, args: &[String]) -> Result<(), String> {
    let body = dispatch(config, args)?;
    println!("{body}");
    Ok(())
}

fn dispatch(config: &HubConfig, args: &[String]) -> Result<String, String> {
    let command = args.first().map(|value| value.as_str()).unwrap_or("help");
    if matches!(command, "help" | "-h" | "--help") {
        return Ok(help_json());
    }

    match command {
        "write" | "append" => write_json(config, FlagArgs::parse(&args[1..])?),
        "list" | "summary" | "ledger" => list_json(config, FlagArgs::parse(&args[1..])?),
        other => Err(format!("unknown evidence command: {other}")),
    }
}

pub fn write_json_from_body(config: &HubConfig, body: &str) -> Result<String, String> {
    let value = parse_body_json(body)?;
    write_json_from_value(config, value)
}

pub fn write_json_from_value(config: &HubConfig, value: Value) -> Result<String, String> {
    let evidence = write_value_to_ledger(config, value)?;
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "write",
        "ledger_schema_version": LEDGER_SCHEMA_VERSION,
        "evidence": evidence,
    })
    .to_string())
}

pub fn write_value_to_ledger(config: &HubConfig, value: Value) -> Result<Value, String> {
    apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("evidence ledger migration failed: {err}"))?;

    let component = value_string_any(&value, &["component", "component_id"])
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| "evidence write requires component".to_string())?;
    let authority_mode = value_string_any(&value, &["authority_mode", "authorityMode"])
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| "diagnostic".to_string());
    let output_verdict = value_string_any(&value, &["output_verdict", "outputVerdict", "verdict"])
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| "recorded".to_string());
    let created_at_ms = value_i64_any(&value, &["created_at_ms", "createdAtMs"])
        .unwrap_or_else(|| now_ms().min(i64::MAX as u128) as i64);
    let evidence_id = value_string_any(&value, &["evidence_id", "evidenceId"])
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| make_evidence_id(&component, created_at_ms));

    let reason_json = json_field_or_default(
        &value,
        &["reason_codes", "reasonCodes", "reason"],
        json!([]),
    )?;
    let parent_evidence_json = json_field_or_default(
        &value,
        &[
            "parent_evidence_ids",
            "parentEvidenceIds",
            "parent_evidence",
            "parentEvidence",
        ],
        json!([]),
    )?;
    let input_ref_json =
        json_field_or_default(&value, &["input_ref", "inputRef", "input"], json!({}))?;
    let payload_json =
        json_field_or_default(&value, &["payload", "detail", "detail_json"], json!({}))?;

    let record = EvidenceLedgerRecord {
        evidence_id,
        created_at_ms,
        component,
        authority_mode,
        project_id: value_string_any(&value, &["project_id", "projectId"]),
        run_id: value_string_any(&value, &["run_id", "runId"]),
        output_verdict,
        reason_json,
        parent_evidence_json,
        input_ref_json,
        payload_json,
        expires_at_ms: value_i64_any(&value, &["expires_at_ms", "expiresAtMs"]),
    };
    write_evidence_record(&config.db_path, &record)
        .map_err(|err| format!("evidence ledger write failed: {err}"))?;
    Ok(row_like_record(&record))
}

pub fn list_json_from_parts(
    config: &HubConfig,
    component: Option<String>,
    project_id: Option<String>,
    run_id: Option<String>,
    limit: usize,
) -> Result<String, String> {
    apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("evidence ledger migration failed: {err}"))?;
    let summary = read_evidence_ledger_summary(
        &config.db_path,
        component.as_deref(),
        project_id.as_deref(),
        run_id.as_deref(),
        limit,
    )
    .map_err(|err| format!("evidence ledger read failed: {err}"))?;
    Ok(summary_to_value(&summary).to_string())
}

fn write_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let mut value = json!({
        "component": flags.required("component")?,
        "authority_mode": flags.optional("authority-mode").unwrap_or_else(|| "diagnostic".to_string()),
        "output_verdict": flags.optional("verdict").unwrap_or_else(|| "recorded".to_string()),
    });
    set_optional_string(&mut value, "evidence_id", flags.optional("evidence-id"));
    set_optional_string(&mut value, "project_id", flags.optional("project-id"));
    set_optional_string(&mut value, "run_id", flags.optional("run-id"));
    set_optional_i64(
        &mut value,
        "created_at_ms",
        flags.optional_i64("created-at-ms")?,
    );
    set_optional_i64(
        &mut value,
        "expires_at_ms",
        flags.optional_i64("expires-at-ms")?,
    );
    set_optional_json(
        &mut value,
        "reason_codes",
        flags.optional_json("reason-json")?,
    );
    set_optional_json(
        &mut value,
        "parent_evidence_ids",
        flags.optional_json("parent-evidence-json")?,
    );
    set_optional_json(
        &mut value,
        "input_ref",
        flags.optional_json("input-ref-json")?,
    );
    set_optional_json(&mut value, "payload", flags.optional_json("payload-json")?);
    write_json_from_value(config, value)
}

fn list_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let limit = flags.optional_usize("limit")?.unwrap_or(50);
    list_json_from_parts(
        config,
        flags.optional("component"),
        flags.optional("project-id"),
        flags.optional("run-id"),
        limit,
    )
}

fn summary_to_value(summary: &EvidenceLedgerSummary) -> Value {
    json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "list",
        "ledger_schema_version": LEDGER_SCHEMA_VERSION,
        "filters": {
            "component": summary.component,
            "project_id": summary.project_id,
            "run_id": summary.run_id,
        },
        "total": summary.total,
        "latest_created_at_ms": summary.latest_created_at_ms,
        "rows": summary.rows.iter().map(row_to_value).collect::<Vec<_>>(),
    })
}

fn row_to_value(row: &EvidenceLedgerRow) -> Value {
    json!({
        "evidence_id": row.evidence_id,
        "created_at_ms": row.created_at_ms,
        "component": row.component,
        "authority_mode": row.authority_mode,
        "project_id": row.project_id,
        "run_id": row.run_id,
        "output_verdict": row.output_verdict,
        "reason_codes": parse_json_or_raw(&row.reason_json),
        "parent_evidence_ids": parse_json_or_raw(&row.parent_evidence_json),
        "input_ref": parse_json_or_raw(&row.input_ref_json),
        "payload": parse_json_or_raw(&row.payload_json),
        "expires_at_ms": row.expires_at_ms,
    })
}

fn row_like_record(record: &EvidenceLedgerRecord) -> Value {
    json!({
        "evidence_id": record.evidence_id,
        "created_at_ms": record.created_at_ms,
        "component": record.component,
        "authority_mode": record.authority_mode,
        "project_id": record.project_id,
        "run_id": record.run_id,
        "output_verdict": record.output_verdict,
        "reason_codes": parse_json_or_raw(&record.reason_json),
        "parent_evidence_ids": parse_json_or_raw(&record.parent_evidence_json),
        "input_ref": parse_json_or_raw(&record.input_ref_json),
        "payload": parse_json_or_raw(&record.payload_json),
        "expires_at_ms": record.expires_at_ms,
    })
}

fn make_evidence_id(component: &str, created_at_ms: i64) -> String {
    let normalized = component
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
                ch
            } else {
                '_'
            }
        })
        .take(48)
        .collect::<String>();
    format!(
        "ev_{}_{}_{}_{}",
        if normalized.is_empty() {
            "unknown"
        } else {
            normalized.as_str()
        },
        created_at_ms,
        std::process::id(),
        EVIDENCE_COUNTER.fetch_add(1, Ordering::Relaxed)
    )
}

fn parse_body_json(body: &str) -> Result<Value, String> {
    if body.trim().is_empty() {
        return Err("evidence write requires JSON body".to_string());
    }
    serde_json::from_str(body).map_err(|err| format!("invalid evidence JSON body: {err}"))
}

fn json_field_or_default(value: &Value, keys: &[&str], fallback: Value) -> Result<String, String> {
    for key in keys {
        if let Some(found) = value.get(*key) {
            return serde_json::to_string(found)
                .map_err(|err| format!("evidence field {key} serialize failed: {err}"));
        }
    }
    serde_json::to_string(&fallback)
        .map_err(|err| format!("evidence default serialize failed: {err}"))
}

fn parse_json_or_raw(raw: &str) -> Value {
    serde_json::from_str(raw).unwrap_or_else(|_| Value::String(raw.to_string()))
}

fn value_string_any(value: &Value, keys: &[&str]) -> Option<String> {
    keys.iter().find_map(|key| {
        value.get(*key).and_then(|item| {
            item.as_str()
                .map(ToString::to_string)
                .or_else(|| item.as_i64().map(|number| number.to_string()))
        })
    })
}

fn value_i64_any(value: &Value, keys: &[&str]) -> Option<i64> {
    keys.iter()
        .find_map(|key| value.get(*key).and_then(value_to_i64))
}

fn value_to_i64(value: &Value) -> Option<i64> {
    value
        .as_i64()
        .or_else(|| value.as_u64().and_then(|number| i64::try_from(number).ok()))
        .or_else(|| {
            value
                .as_str()
                .and_then(|text| text.trim().parse::<i64>().ok())
        })
}

fn set_optional_string(value: &mut Value, key: &str, item: Option<String>) {
    if let Some(item) = item {
        value[key] = Value::String(item);
    }
}

fn set_optional_i64(value: &mut Value, key: &str, item: Option<i64>) {
    if let Some(item) = item {
        value[key] = Value::Number(item.into());
    }
}

fn set_optional_json(value: &mut Value, key: &str, item: Option<Value>) {
    if let Some(item) = item {
        value[key] = item;
    }
}

fn help_json() -> String {
    json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "commands": ["write", "list"],
        "write_required": ["component"],
        "write_optional": [
            "evidence-id",
            "authority-mode",
            "project-id",
            "run-id",
            "verdict",
            "reason-json",
            "parent-evidence-json",
            "input-ref-json",
            "payload-json",
            "expires-at-ms"
        ],
    })
    .to_string()
}

#[derive(Debug, Clone, Default)]
struct FlagArgs {
    values: BTreeMap<String, String>,
}

impl FlagArgs {
    fn parse(args: &[String]) -> Result<Self, String> {
        let mut values = BTreeMap::new();
        let mut i = 0;
        while i < args.len() {
            let key = args[i].trim();
            if !key.starts_with("--") {
                return Err(format!("unexpected argument: {key}"));
            }
            let normalized = key.trim_start_matches("--").to_string();
            let Some(value) = args.get(i + 1) else {
                return Err(format!("missing value for --{normalized}"));
            };
            values.insert(normalized, value.to_string());
            i += 2;
        }
        Ok(Self { values })
    }

    fn optional(&self, key: &str) -> Option<String> {
        self.values
            .get(key)
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
    }

    fn required(&self, key: &str) -> Result<String, String> {
        self.optional(key)
            .ok_or_else(|| format!("missing required --{key}"))
    }

    fn optional_i64(&self, key: &str) -> Result<Option<i64>, String> {
        self.optional(key)
            .map(|value| {
                value
                    .parse::<i64>()
                    .map_err(|_| format!("invalid --{key}: expected integer"))
            })
            .transpose()
    }

    fn optional_usize(&self, key: &str) -> Result<Option<usize>, String> {
        self.optional(key)
            .map(|value| {
                value
                    .parse::<usize>()
                    .map_err(|_| format!("invalid --{key}: expected unsigned integer"))
            })
            .transpose()
    }

    fn optional_json(&self, key: &str) -> Result<Option<Value>, String> {
        self.optional(key)
            .map(|value| {
                serde_json::from_str::<Value>(&value)
                    .map_err(|err| format!("invalid --{key}: {err}"))
            })
            .transpose()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn evidence_write_and_list_round_trip() {
        let root = unique_temp_dir("xhub-evidence-bridge");
        let config = HubConfig {
            root_dir: root.clone(),
            host: "127.0.0.1".to_string(),
            http_port: 0,
            grpc_port: 0,
            db_path: root.join("hub.sqlite3"),
            runtime_base_dir: root.clone(),
            proto_path: root.join("proto"),
            canonical_proto_path: root.join("proto"),
            http_access_key: None,
            http_access_key_source: String::new(),
            http_access_key_required: false,
        };
        let body = json!({
            "component": "provider_route",
            "authority_mode": "candidate",
            "project_id": "project-a",
            "run_id": "run-a",
            "verdict": "allow",
            "reason_codes": ["ready"],
            "payload": {"selected_provider":"openai"}
        })
        .to_string();
        let written = write_json_from_body(&config, &body).expect("write evidence");
        let written_value: Value = serde_json::from_str(&written).expect("write json");
        assert_eq!(written_value["ok"], true);
        assert_eq!(written_value["evidence"]["component"], "provider_route");

        let listed = list_json_from_parts(
            &config,
            Some("provider_route".to_string()),
            Some("project-a".to_string()),
            None,
            10,
        )
        .expect("list evidence");
        let listed_value: Value = serde_json::from_str(&listed).expect("list json");
        assert_eq!(listed_value["total"], 1);
        assert_eq!(listed_value["rows"][0]["reason_codes"][0], "ready");

        let _ = std::fs::remove_dir_all(root);
    }

    fn unique_temp_dir(prefix: &str) -> std::path::PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("{prefix}_{}_{}", std::process::id(), nanos));
        std::fs::create_dir_all(&dir).expect("create temp dir");
        dir
    }
}
