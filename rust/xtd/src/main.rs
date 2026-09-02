use std::env;
use std::fs;
use std::process;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::Deserialize;
use serde_json::{json, Value};

const SERVICE_NAME: &str = "xtd";
const PROJECTION_PROTOCOL: &str = "xt-core-projection.v1";
const HUB_REMOTE_LOG_DISPLAY_CHARACTER_LIMIT: usize = 16_000;
const ROUTE_REPAIR_LOG_DISPLAY_LINE_LIMIT: usize = 80;
const DIAGNOSTICS_LINE_LIMIT: usize = 120;

#[derive(Debug, Default)]
struct ProjectionOptions {
    generated_at_ms: u128,
    input_json: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SidebarProjectionInput {
    #[serde(default)]
    revision: Option<u64>,
    #[serde(default)]
    selected_project_id: Option<String>,
    #[serde(default)]
    projects: Vec<SidebarProjectInput>,
    #[serde(default)]
    selected_supplemental: Option<SidebarSelectedSupplementalInput>,
}

#[derive(Debug, Deserialize)]
struct SidebarProjectInput {
    id: String,
    display_name: String,
    root_path: String,
    #[serde(default)]
    status_digest: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SidebarSelectedSupplementalInput {
    project_id: String,
    #[serde(default)]
    resume_badge_text: Option<String>,
    #[serde(default)]
    resume_help_text: Option<String>,
    #[serde(default)]
    governance: Option<SidebarGovernanceInput>,
}

#[derive(Debug, Deserialize)]
struct SidebarGovernanceInput {
    execution_tier: String,
    execution_tier_token: String,
    execution_tier_label: String,
    execution_tier_help: String,
    supervisor_tier: String,
    supervisor_tier_token: String,
    supervisor_tier_label: String,
    supervisor_tier_help: String,
}

#[derive(Debug, Default, Deserialize)]
struct SettingsDiagnosticsInput {
    #[serde(default)]
    connection_state_label: Option<String>,
    #[serde(default)]
    diagnostics_lines: Vec<String>,
    #[serde(default)]
    route_repair_log_lines: Vec<String>,
    #[serde(default)]
    hub_remote_log: String,
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let command = args.get(1).map(String::as_str).unwrap_or("health");

    let result = match command {
        "health" => {
            println!("{}", health_json());
            Ok(())
        }
        "version" | "--version" | "-V" => {
            println!("{} {}", SERVICE_NAME, env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        "run-once" => {
            println!("{}", run_once_json());
            Ok(())
        }
        "projection" => match projection_command_json(&args[2..]) {
            Ok(json) => {
                println!("{}", json);
                Ok(())
            }
            Err(message) => Err(message),
        },
        "help" | "--help" | "-h" => {
            print_help();
            Ok(())
        }
        other => Err(format!("unknown command: {}", other)),
    };

    if let Err(message) = result {
        eprintln!("{}", message);
        print_help();
        process::exit(2);
    }
}

fn health_json() -> String {
    format!(
        "{{\"service\":\"{}\",\"status\":\"ok\",\"version\":\"{}\",\"epoch_ms\":{}}}",
        SERVICE_NAME,
        env!("CARGO_PKG_VERSION"),
        epoch_ms()
    )
}

fn run_once_json() -> String {
    format!(
        "{{\"service\":\"{}\",\"mode\":\"run_once\",\"status\":\"idle\",\"epoch_ms\":{}}}",
        SERVICE_NAME,
        epoch_ms()
    )
}

fn projection_command_json(args: &[String]) -> Result<String, String> {
    let surface = args
        .first()
        .map(String::as_str)
        .ok_or_else(|| "missing projection surface".to_string())?;
    let options = projection_options(&args[1..])?;

    match surface {
        "sidebar" | "project-sidebar" | "project_sidebar" => {
            Ok(project_sidebar_projection_json(&options)?)
        }
        "settings-diagnostics" | "settings_diagnostics" => {
            Ok(settings_diagnostics_projection_json(&options)?)
        }
        other => Err(format!("unknown projection surface: {}", other)),
    }
}

fn projection_options(args: &[String]) -> Result<ProjectionOptions, String> {
    let mut generated_at_ms: Option<u128> = None;
    let mut input_json: Option<String> = None;
    let mut index = 0;

    while index < args.len() {
        let token = args[index].as_str();
        if let Some(raw) = token.strip_prefix("--generated-at-ms=") {
            generated_at_ms = Some(parse_generated_at_ms(raw)?);
            index += 1;
            continue;
        }

        if token == "--generated-at-ms" {
            let raw = args
                .get(index + 1)
                .ok_or_else(|| "missing value for --generated-at-ms".to_string())?;
            generated_at_ms = Some(parse_generated_at_ms(raw)?);
            index += 2;
            continue;
        }

        if let Some(raw) = token.strip_prefix("--input-json=") {
            input_json = Some(raw.to_string());
            index += 1;
            continue;
        }

        if token == "--input-json" {
            let raw = args
                .get(index + 1)
                .ok_or_else(|| "missing value for --input-json".to_string())?;
            input_json = Some(raw.to_string());
            index += 2;
            continue;
        }

        if let Some(path) = token.strip_prefix("--input-file=") {
            input_json = Some(read_input_file(path)?);
            index += 1;
            continue;
        }

        if token == "--input-file" {
            let path = args
                .get(index + 1)
                .ok_or_else(|| "missing value for --input-file".to_string())?;
            input_json = Some(read_input_file(path)?);
            index += 2;
            continue;
        }

        return Err(format!("unknown projection option: {}", token));
    }

    Ok(ProjectionOptions {
        generated_at_ms: generated_at_ms.unwrap_or_else(epoch_ms),
        input_json,
    })
}

fn parse_generated_at_ms(raw: &str) -> Result<u128, String> {
    raw.parse::<u128>()
        .map_err(|_| format!("invalid --generated-at-ms value: {}", raw))
}

fn read_input_file(path: &str) -> Result<String, String> {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return Err("missing value for --input-file".to_string());
    }
    fs::read_to_string(trimmed)
        .map_err(|err| format!("failed to read --input-file {}: {}", trimmed, err))
}

fn project_sidebar_projection_json(options: &ProjectionOptions) -> Result<String, String> {
    if let Some(input_json) = options.input_json.as_deref() {
        let input: SidebarProjectionInput = serde_json::from_str(input_json)
            .map_err(|err| format!("invalid sidebar projection input JSON: {}", err))?;
        return serde_json::to_string(&sidebar_projection_from_input(
            &input,
            options.generated_at_ms,
        ))
        .map_err(|err| format!("failed to serialize sidebar projection: {}", err));
    }

    Ok(format!(
        concat!(
            "{{",
            "\"protocol\":\"{}\",",
            "\"surface\":\"project_sidebar\",",
            "\"revision\":1,",
            "\"generated_at_ms\":{},",
            "\"source\":\"xtd_fixture_projection\",",
            "\"authority\":{{",
            "\"hub_owns_truth\":true,",
            "\"xtd_owns_authority\":false,",
            "\"memory_writer_authority\":false,",
            "\"skills_authority\":false,",
            "\"model_route_authority\":false",
            "}},",
            "\"payload\":{{",
            "\"selected_project_id\":\"\",",
            "\"project_count_text\":\"0\",",
            "\"rows\":[]",
            "}}",
            "}}"
        ),
        PROJECTION_PROTOCOL, options.generated_at_ms
    ))
}

fn sidebar_projection_from_input(input: &SidebarProjectionInput, generated_at_ms: u128) -> Value {
    let selected_project_id = normalized_string(input.selected_project_id.as_deref());
    let selected_supplemental = input.selected_supplemental.as_ref().filter(|supplemental| {
        selected_project_id
            .as_deref()
            .map(|selected| supplemental.project_id.trim() == selected)
            .unwrap_or(false)
    });
    let rows = input
        .projects
        .iter()
        .map(|project| {
            let id = project.id.trim();
            let is_selected = selected_project_id
                .as_deref()
                .map(|selected| selected == id)
                .unwrap_or(false);
            let supplemental = selected_supplemental.filter(|value| {
                value.project_id.trim() == id && is_selected
            });

            json!({
                "id": id,
                "display_name": project.display_name.trim(),
                "root_path": project.root_path.trim(),
                "is_selected": is_selected,
                "status_digest": if is_selected { normalized_string(project.status_digest.as_deref()) } else { None },
                "resume_badge_text": supplemental.and_then(|value| normalized_string(value.resume_badge_text.as_deref())),
                "resume_help_text": supplemental.and_then(|value| normalized_string(value.resume_help_text.as_deref())),
                "governance": supplemental.and_then(|value| value.governance.as_ref()).map(governance_json),
            })
        })
        .collect::<Vec<_>>();

    json!({
        "protocol": PROJECTION_PROTOCOL,
        "surface": "project_sidebar",
        "revision": 1,
        "generated_at_ms": generated_at_ms,
        "source": "xtd_sidebar_projection",
        "authority": {
            "hub_owns_truth": true,
            "xtd_owns_authority": false,
            "memory_writer_authority": false,
            "skills_authority": false,
            "model_route_authority": false,
        },
        "payload": {
            "revision": input.revision.unwrap_or(0),
            "selected_project_id": selected_project_id,
            "project_count_text": input.projects.len().to_string(),
            "rows": rows,
        },
    })
}

fn governance_json(input: &SidebarGovernanceInput) -> Value {
    json!({
        "execution_tier": input.execution_tier.trim(),
        "execution_tier_token": input.execution_tier_token.trim(),
        "execution_tier_label": input.execution_tier_label.trim(),
        "execution_tier_help": input.execution_tier_help.trim(),
        "supervisor_tier": input.supervisor_tier.trim(),
        "supervisor_tier_token": input.supervisor_tier_token.trim(),
        "supervisor_tier_label": input.supervisor_tier_label.trim(),
        "supervisor_tier_help": input.supervisor_tier_help.trim(),
    })
}

fn normalized_string(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
}

fn settings_diagnostics_projection_json(options: &ProjectionOptions) -> Result<String, String> {
    if let Some(input_json) = options.input_json.as_deref() {
        let input: SettingsDiagnosticsInput = serde_json::from_str(input_json)
            .map_err(|err| format!("invalid settings diagnostics input JSON: {}", err))?;
        return serde_json::to_string(&settings_diagnostics_projection_from_input(
            &input,
            options.generated_at_ms,
        ))
        .map_err(|err| {
            format!(
                "failed to serialize settings diagnostics projection: {}",
                err
            )
        });
    }

    Ok(format!(
        concat!(
            "{{",
            "\"protocol\":\"{}\",",
            "\"surface\":\"settings_diagnostics\",",
            "\"revision\":1,",
            "\"generated_at_ms\":{},",
            "\"source\":\"xtd_fixture_projection\",",
            "\"authority\":{{",
            "\"hub_owns_truth\":true,",
            "\"xtd_owns_authority\":false,",
            "\"memory_writer_authority\":false,",
            "\"skills_authority\":false,",
            "\"model_route_authority\":false",
            "}},",
            "\"payload\":{{",
            "\"connection_state_label\":\"未连接\",",
            "\"diagnostics_lines\":[],",
            "\"route_repair_recent_lines\":[],",
            "\"hub_remote_log_tail\":{{",
            "\"title\":\"Hub Remote Log\",",
            "\"text\":\"\",",
            "\"truncated\":false,",
            "\"total_bytes\":0,",
            "\"displayed_bytes\":0",
            "}}",
            "}}",
            "}}"
        ),
        PROJECTION_PROTOCOL, options.generated_at_ms
    ))
}

fn settings_diagnostics_projection_from_input(
    input: &SettingsDiagnosticsInput,
    generated_at_ms: u128,
) -> Value {
    json!({
        "protocol": PROJECTION_PROTOCOL,
        "surface": "settings_diagnostics",
        "revision": 1,
        "generated_at_ms": generated_at_ms,
        "source": "xtd_settings_diagnostics_projection",
        "authority": {
            "hub_owns_truth": true,
            "xtd_owns_authority": false,
            "memory_writer_authority": false,
            "skills_authority": false,
            "model_route_authority": false,
        },
        "payload": {
            "connection_state_label": normalized_string(input.connection_state_label.as_deref()).unwrap_or_else(|| "未连接".to_string()),
            "diagnostics_lines": string_tail(&input.diagnostics_lines, DIAGNOSTICS_LINE_LIMIT),
            "route_repair_recent_lines": string_tail(&input.route_repair_log_lines, ROUTE_REPAIR_LOG_DISPLAY_LINE_LIMIT),
            "route_repair_total_line_count": input.route_repair_log_lines.len(),
            "hub_remote_log_tail": projected_hub_remote_log_tail(input.hub_remote_log.as_str()),
        },
    })
}

fn string_tail(values: &[String], limit: usize) -> Vec<String> {
    if values.len() <= limit {
        return values.to_vec();
    }
    values[values.len() - limit..].to_vec()
}

fn projected_hub_remote_log_tail(raw_log: &str) -> Value {
    let total_bytes = raw_log.len();
    let (text, truncated) = if total_bytes > HUB_REMOTE_LOG_DISPLAY_CHARACTER_LIMIT {
        let suffix = char_suffix(raw_log, HUB_REMOTE_LOG_DISPLAY_CHARACTER_LIMIT);
        (
            format!(
                "...已截断较早日志，仅显示最近 {} 个字符。\n\n{}",
                HUB_REMOTE_LOG_DISPLAY_CHARACTER_LIMIT, suffix
            ),
            true,
        )
    } else {
        (raw_log.to_string(), false)
    };
    let displayed_bytes = text.len();
    json!({
        "title": "Hub Remote Log",
        "text": text,
        "truncated": truncated,
        "total_bytes": total_bytes,
        "displayed_bytes": displayed_bytes,
    })
}

fn char_suffix(value: &str, limit: usize) -> String {
    let mut chars = value.chars().rev().take(limit).collect::<Vec<_>>();
    chars.reverse();
    chars.into_iter().collect()
}

fn epoch_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0)
}

fn print_help() {
    println!(
        "{} {}\n\nCommands:\n  health                         Print a JSON health snapshot\n  run-once                       Execute one placeholder runtime tick\n  projection <surface> [options] Print a versioned Swift-shell projection envelope\n  version                        Print version\n  help                           Show this help\n\nProjection surfaces:\n  sidebar\n  settings-diagnostics\n\nProjection options:\n  --generated-at-ms <ms>          Override timestamp for fixture tests\n  --input-json <json>             Build projection from a bounded input JSON envelope\n  --input-file <path>             Read projection input JSON from disk\n",
        SERVICE_NAME,
        env!("CARGO_PKG_VERSION")
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| value.to_string()).collect()
    }

    #[test]
    fn sidebar_projection_envelope_is_stable_with_fixed_timestamp() {
        let output = projection_command_json(&args(&["sidebar", "--generated-at-ms", "0"]))
            .expect("projection should render");

        assert!(output.contains("\"protocol\":\"xt-core-projection.v1\""));
        assert!(output.contains("\"surface\":\"project_sidebar\""));
        assert!(output.contains("\"generated_at_ms\":0"));
        assert!(output.contains("\"hub_owns_truth\":true"));
        assert!(output.contains("\"xtd_owns_authority\":false"));
        assert!(output.contains("\"memory_writer_authority\":false"));
        assert!(output.contains("\"skills_authority\":false"));
        assert!(output.contains("\"model_route_authority\":false"));
        assert!(output.contains(
            "\"payload\":{\"selected_project_id\":\"\",\"project_count_text\":\"0\",\"rows\":[]}"
        ));
    }

    #[test]
    fn settings_diagnostics_projection_keeps_payload_bounded_shape() {
        let output =
            projection_command_json(&args(&["settings-diagnostics", "--generated-at-ms=0"]))
                .expect("projection should render");

        assert!(output.contains("\"surface\":\"settings_diagnostics\""));
        assert!(output.contains("\"diagnostics_lines\":[]"));
        assert!(output.contains("\"route_repair_recent_lines\":[]"));
        assert!(output.contains("\"hub_remote_log_tail\""));
        assert!(output.contains("\"displayed_bytes\":0"));
    }

    #[test]
    fn settings_diagnostics_projection_builds_bounded_payload_from_input_json() {
        let input = format!(
            r#"{{
                "connection_state_label": "已连接",
                "diagnostics_lines": ["diag-a", "diag-b"],
                "route_repair_log_lines": [{}],
                "hub_remote_log": "{}"
            }}"#,
            (0..100)
                .map(|index| format!("\"route-line-{index}\""))
                .collect::<Vec<_>>()
                .join(","),
            "x".repeat(17_000)
        );

        let output = projection_command_json(&args(&[
            "settings-diagnostics",
            "--generated-at-ms=0",
            "--input-json",
            input.as_str(),
        ]))
        .expect("projection should render");
        let value: Value = serde_json::from_str(&output).expect("valid JSON");
        let payload = &value["payload"];
        let recent_lines = payload["route_repair_recent_lines"]
            .as_array()
            .expect("route repair lines should be an array");

        assert_eq!(value["source"], "xtd_settings_diagnostics_projection");
        assert_eq!(payload["connection_state_label"], "已连接");
        assert_eq!(payload["route_repair_total_line_count"], 100);
        assert_eq!(recent_lines.len(), 80);
        assert_eq!(recent_lines.first().unwrap(), "route-line-20");
        assert_eq!(recent_lines.last().unwrap(), "route-line-99");
        assert_eq!(payload["hub_remote_log_tail"]["truncated"], true);
        assert_eq!(payload["hub_remote_log_tail"]["total_bytes"], 17_000);
        assert!(payload["hub_remote_log_tail"]["text"]
            .as_str()
            .unwrap()
            .contains("仅显示最近 16000 个字符"));
    }

    #[test]
    fn settings_diagnostics_projection_rejects_invalid_input_json() {
        let error = projection_command_json(&args(&[
            "settings-diagnostics",
            "--input-json",
            "{\"diagnostics_lines\":12}",
        ]))
        .expect_err("invalid input JSON should fail closed");

        assert!(error.contains("invalid settings diagnostics input JSON"));
    }

    #[test]
    fn projection_rejects_unknown_surface() {
        let error = projection_command_json(&args(&["memory-authority", "--generated-at-ms", "0"]))
            .expect_err("unknown surface should fail closed");

        assert!(error.contains("unknown projection surface"));
    }

    #[test]
    fn projection_rejects_unknown_option() {
        let error = projection_command_json(&args(&["sidebar", "--take-authority"]))
            .expect_err("unknown option should fail closed");

        assert!(error.contains("unknown projection option"));
    }

    #[test]
    fn sidebar_projection_builds_rows_from_input_json() {
        let input = r#"{
            "revision": 7,
            "selected_project_id": "project-a",
            "projects": [
                {
                    "id": "project-a",
                    "display_name": "Project A",
                    "root_path": "/tmp/project-a",
                    "status_digest": "running"
                },
                {
                    "id": "project-b",
                    "display_name": "Project B",
                    "root_path": "/tmp/project-b",
                    "status_digest": "idle"
                }
            ],
            "selected_supplemental": {
                "project_id": "project-a",
                "resume_badge_text": "最近交接",
                "resume_help_text": "resume help",
                "governance": {
                    "execution_tier": "a4_openclaw",
                    "execution_tier_token": "A4",
                    "execution_tier_label": "A4 Agent",
                    "execution_tier_help": "execution help",
                    "supervisor_tier": "s3_strategic_coach",
                    "supervisor_tier_token": "S3",
                    "supervisor_tier_label": "S3 Strategic Coach",
                    "supervisor_tier_help": "supervisor help"
                }
            }
        }"#;

        let output = projection_command_json(&args(&[
            "sidebar",
            "--generated-at-ms=0",
            "--input-json",
            input,
        ]))
        .expect("projection should render");
        let value: Value = serde_json::from_str(&output).expect("valid JSON");
        let payload = &value["payload"];

        assert_eq!(value["source"], "xtd_sidebar_projection");
        assert_eq!(payload["revision"], 7);
        assert_eq!(payload["selected_project_id"], "project-a");
        assert_eq!(payload["project_count_text"], "2");
        assert_eq!(payload["rows"][0]["id"], "project-a");
        assert_eq!(payload["rows"][0]["is_selected"], true);
        assert_eq!(payload["rows"][0]["status_digest"], "running");
        assert_eq!(payload["rows"][0]["resume_badge_text"], "最近交接");
        assert_eq!(
            payload["rows"][0]["governance"]["execution_tier"],
            "a4_openclaw"
        );
        assert_eq!(payload["rows"][1]["is_selected"], false);
        assert!(payload["rows"][1]["status_digest"].is_null());
        assert!(payload["rows"][1]["governance"].is_null());
    }

    #[test]
    fn sidebar_projection_rejects_invalid_input_json() {
        let error = projection_command_json(&args(&[
            "sidebar",
            "--input-json",
            "{\"projects\":[{\"id\":12}]}",
        ]))
        .expect_err("invalid input JSON should fail closed");

        assert!(error.contains("invalid sidebar projection input JSON"));
    }
}
