#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="${XHUB_DOCTOR_HUB_LOCAL_SERVICE_SMOKE_REPORT_DIR:-${ROOT_DIR}/build/reports}"
TMP_BASE_DIR="${TMPDIR:-/tmp}"
TMP_ROOT="${XHUB_DOCTOR_HUB_LOCAL_SERVICE_SMOKE_TMP_ROOT:-}"
MIN_FREE_KB="${XHUB_DOCTOR_HUB_LOCAL_SERVICE_SMOKE_MIN_FREE_KB:-1048576}"
SMOKE_LABEL="xhub-doctor-hub-local-service-smoke"

free_space_probe_path() {
  if [ -n "$TMP_ROOT" ]; then
    dirname "$TMP_ROOT"
    return
  fi
  printf '%s\n' "$TMP_BASE_DIR"
}

available_kb_for_path() {
  local probe_path="$1"
  df -Pk "$probe_path" 2>/dev/null | awk 'NR==2 { print $4 }'
}

check_free_space_or_fail() {
  local probe_path=""
  local available_kb=""
  probe_path="$(free_space_probe_path)"
  available_kb="$(available_kb_for_path "$probe_path")"
  if ! [[ "$available_kb" =~ ^[0-9]+$ ]]; then
    echo "[$SMOKE_LABEL] failed_to_read_free_space path=$probe_path" >&2
    exit 1
  fi
  if [ "$available_kb" -lt "$MIN_FREE_KB" ]; then
    echo "[$SMOKE_LABEL] insufficient_free_space_kb=$available_kb required_kb=$MIN_FREE_KB path=$probe_path" >&2
    echo "[$SMOKE_LABEL] hint=clean build/ or stale xhub_doctor_* temp roots, or lower XHUB_DOCTOR_HUB_LOCAL_SERVICE_SMOKE_MIN_FREE_KB for a local retry if you know the disk is safe" >&2
    exit 1
  fi
}

check_free_space_or_fail

if [ -z "$TMP_ROOT" ]; then
  TMP_ROOT="$(mktemp -d "${TMP_BASE_DIR%/}/xhub_doctor_hub_local_service_smoke.XXXXXX")"
else
  mkdir -p "$TMP_ROOT"
fi
SNAPSHOT_DIR="$TMP_ROOT/repo_snapshot"
OUTPUT_DIR="$TMP_ROOT/doctor_bundle"
OUTPUT_REPORT_PATH="$OUTPUT_DIR/xhub_doctor_output_hub.json"
SNAPSHOT_OUTPUT_PATH="$OUTPUT_DIR/xhub_local_service_snapshot.redacted.json"
RECOVERY_GUIDANCE_OUTPUT_PATH="$OUTPUT_DIR/xhub_local_service_recovery_guidance.redacted.json"
HUB_SOURCE_RUN_HOME="$SNAPSHOT_DIR/.hub_source_home"
HUB_STATUS_DIR="$HUB_SOURCE_RUN_HOME/RELFlowHub"
EVIDENCE_PATH="${XHUB_DOCTOR_HUB_LOCAL_SERVICE_SMOKE_EVIDENCE_PATH:-${REPORT_DIR}/xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json}"

cleanup() {
  if [ "${XHUB_KEEP_SMOKE_TMP:-0}" = "1" ] || [ -n "${XHUB_DOCTOR_HUB_LOCAL_SERVICE_SMOKE_TMP_ROOT:-}" ]; then
    echo "[xhub-doctor-hub-local-service-smoke] kept_tmp_root=$TMP_ROOT"
    return
  fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$SNAPSHOT_DIR/scripts" "$OUTPUT_DIR" "$HUB_STATUS_DIR" "$REPORT_DIR"

rsync -a --delete \
  --exclude '.build' \
  --exclude '.axcoder' \
  --exclude '.scratch' \
  --exclude '.sandbox_home' \
  --exclude '.sandbox_tmp' \
  --exclude '.clang-module-cache' \
  --exclude '.swift-module-cache' \
  --exclude 'DerivedData' \
  --exclude '__pycache__' \
  --exclude '.DS_Store' \
  "$ROOT_DIR/x-hub/" "$SNAPSHOT_DIR/x-hub/"

cp -f "$ROOT_DIR/scripts/run_xhub_doctor_from_source.command" \
  "$SNAPSHOT_DIR/scripts/run_xhub_doctor_from_source.command"
chmod +x \
  "$SNAPSHOT_DIR/scripts/run_xhub_doctor_from_source.command" \
  "$SNAPSHOT_DIR/x-hub/tools/run_xhub_from_source.command"

python3 - "$HUB_STATUS_DIR" <<'PY'
import json
import os
import sys
import time

hub_status_dir = sys.argv[1]
now = time.time()
runtime_updated_at = now + 3600

hub_runtime_payload = {
    "pid": 4096,
    "updated_at": runtime_updated_at,
    "schema_version": "xhub.local_runtime_status.v2",
    "mlx_ok": False,
    "runtime_version": "entry-v2",
    "providers": {
        "transformers": {
            "provider": "transformers",
            "ok": False,
            "reason_code": "runtime_missing",
            "runtime_version": "entry-v2",
            "runtime_source": "xhub_local_service",
            "runtime_source_path": "http://127.0.0.1:50171",
            "runtime_resolution_state": "runtime_missing",
            "runtime_reason_code": "xhub_local_service_unreachable",
            "fallback_used": False,
            "available_task_kinds": ["embedding", "vision_understand"],
            "loaded_models": [],
            "device_backend": "service_proxy",
            "updated_at": runtime_updated_at,
            "managed_service_state": {
                "base_url": "http://127.0.0.1:50171",
                "bind_host": "127.0.0.1",
                "bind_port": 50171,
                "pid": 43001,
                "process_state": "down",
                "started_at_ms": 1741800000000,
                "last_probe_at_ms": 1741800001000,
                "last_probe_http_status": 0,
                "last_probe_error": "ConnectionRefusedError:[Errno 61] Connection refused",
                "last_ready_at_ms": 0,
                "last_launch_attempt_at_ms": 1741800000500,
                "start_attempt_count": 2,
                "last_start_error": "spawn_exit_1",
                "updated_at_ms": 1741800001000,
            },
        }
    },
    "provider_packs": [
        {
            "schema_version": "xhub.provider_pack_manifest.v1",
            "provider_id": "transformers",
            "engine": "hf-transformers",
            "version": "builtin-2026-03-21",
            "supported_formats": ["hf_transformers"],
            "supported_domains": ["embedding", "vision", "ocr"],
            "runtime_requirements": {
                "execution_mode": "xhub_local_service",
                "service_base_url": "http://127.0.0.1:50171",
                "notes": ["hub_managed_service"],
            },
            "min_hub_version": "2026.03",
            "installed": True,
            "enabled": True,
            "pack_state": "installed",
            "reason_code": "hub_managed_service_pack_registered",
        }
    ],
    "monitor_snapshot": {
        "schema_version": "xhub.local_runtime_monitor.v1",
        "updated_at": runtime_updated_at,
        "providers": [
            {
                "provider": "transformers",
                "ok": False,
                "reason_code": "runtime_missing",
                "runtime_source": "xhub_local_service",
                "runtime_resolution_state": "runtime_missing",
                "runtime_reason_code": "xhub_local_service_unreachable",
                "fallback_used": False,
                "available_task_kinds": ["embedding", "vision_understand"],
                "real_task_kinds": ["embedding"],
                "fallback_task_kinds": [],
                "unavailable_task_kinds": ["ocr"],
                "device_backend": "service_proxy",
                "lifecycle_mode": "warmable",
                "residency_scope": "service_runtime",
                "loaded_instance_count": 1,
                "loaded_model_count": 0,
                "active_task_count": 0,
                "queued_task_count": 2,
                "concurrency_limit": 1,
                "queue_mode": "fifo",
                "queueing_supported": True,
                "oldest_waiter_started_at": now - 2,
                "oldest_waiter_age_ms": 200,
                "contention_count": 1,
                "last_contention_at": now - 1,
                "active_memory_bytes": 0,
                "peak_memory_bytes": 0,
                "memory_state": "unknown",
                "idle_eviction_policy": "ttl",
                "last_idle_eviction_reason": "",
                "updated_at": runtime_updated_at,
            }
        ],
        "active_tasks": [],
        "loaded_instances": [
            {
                "instance_key": "transformers:embed-local:svc1234",
                "model_id": "embed-local",
                "task_kinds": ["embedding"],
                "load_profile_hash": "svc1234",
                "effective_context_length": 4096,
                "effective_load_profile": {
                    "context_length": 4096,
                    "ttl": 300,
                    "parallel": 1,
                    "identifier": "svc-a",
                },
                "loaded_at": now - 10,
                "last_used_at": now - 3,
                "residency": "resident",
                "residency_scope": "service_runtime",
                "device_backend": "service_proxy",
            }
        ],
        "queue": {
            "provider_count": 1,
            "active_task_count": 0,
            "queued_task_count": 2,
            "providers_busy_count": 0,
            "providers_with_queued_tasks_count": 1,
            "max_oldest_wait_ms": 200,
            "contention_count": 1,
            "last_contention_at": now - 1,
            "updated_at": runtime_updated_at,
            "providers": [],
        },
        "last_errors": [],
        "fallback_counters": {
            "provider_count": 1,
            "fallback_ready_provider_count": 0,
            "fallback_only_provider_count": 0,
            "fallback_ready_task_count": 0,
            "fallback_only_task_count": 0,
            "task_kind_counts": {},
        },
    },
}

hub_launch_payload = {
    "schema_version": "hub_launch_status.v1",
    "launch_id": "hub-local-service-smoke-launch",
    "updated_at_ms": int(now * 1000),
    "state": "SERVING",
    "steps": [],
    "root_cause": None,
    "degraded": {
        "is_degraded": False,
        "blocked_capabilities": [],
    },
}

os.makedirs(hub_status_dir, exist_ok=True)
with open(os.path.join(hub_status_dir, "ai_runtime_status.json"), "w", encoding="utf-8") as handle:
    json.dump(hub_runtime_payload, handle, indent=2, sort_keys=True)
    handle.write("\n")

with open(os.path.join(hub_status_dir, "hub_launch_status.json"), "w", encoding="utf-8") as handle:
    json.dump(hub_launch_payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

mkdir -p \
  "$SNAPSHOT_DIR/.hub_source_tmp" \
  "$SNAPSHOT_DIR/.hub_scratch" \
  "$SNAPSHOT_DIR/.hub_clang-module-cache" \
  "$SNAPSHOT_DIR/.hub_swift-module-cache"

env \
  XHUB_SOURCE_RUN_HOME="$HUB_SOURCE_RUN_HOME" \
  XHUB_SOURCE_RUN_TMPDIR="$SNAPSHOT_DIR/.hub_source_tmp" \
  XHUB_SOURCE_RUN_SCRATCH_PATH="$SNAPSHOT_DIR/.hub_scratch" \
  XHUB_SOURCE_RUN_CLANG_MODULE_CACHE_PATH="$SNAPSHOT_DIR/.hub_clang-module-cache" \
  XHUB_SOURCE_RUN_SWIFT_MODULE_CACHE_PATH="$SNAPSHOT_DIR/.hub_swift-module-cache" \
  XHUB_SOURCE_RUN_DISABLE_SANDBOX=1 \
  XHUB_SOURCE_RUN_DISABLE_INDEX_STORE=1 \
  bash "$SNAPSHOT_DIR/scripts/run_xhub_doctor_from_source.command" \
    hub \
    --out-json "$OUTPUT_REPORT_PATH" || hub_exit_code=$?

hub_exit_code="${hub_exit_code:-0}"
if [ "$hub_exit_code" -ne 1 ]; then
  echo "[xhub-doctor-hub-local-service-smoke] unexpected_hub_exit_code=$hub_exit_code" >&2
  exit 1
fi

python3 - "$OUTPUT_REPORT_PATH" "$SNAPSHOT_OUTPUT_PATH" "$RECOVERY_GUIDANCE_OUTPUT_PATH" "$HUB_STATUS_DIR" "$EVIDENCE_PATH" "$hub_exit_code" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

output_report_path, snapshot_output_path, recovery_guidance_output_path, hub_status_dir, evidence_path, hub_exit_code = sys.argv[1:7]
output_report_path = os.path.realpath(output_report_path)
snapshot_output_path = os.path.realpath(snapshot_output_path)
recovery_guidance_output_path = os.path.realpath(recovery_guidance_output_path)
hub_status_dir = os.path.realpath(hub_status_dir)

with open(output_report_path, "r", encoding="utf-8") as handle:
    report = json.load(handle)

with open(snapshot_output_path, "r", encoding="utf-8") as handle:
    snapshot = json.load(handle)

with open(recovery_guidance_output_path, "r", encoding="utf-8") as handle:
    recovery_guidance = json.load(handle)

assert report["schema_version"] == "xhub.doctor_output.v1", report["schema_version"]
assert report["surface"] == "hub_cli", report["surface"]
assert report["overall_state"] == "blocked", report["overall_state"]
assert report["ready_for_first_task"] is False, report["ready_for_first_task"]
assert report["current_failure_code"] == "xhub_local_service_unreachable", report["current_failure_code"]
assert report["summary"]["failed"] >= 1, report["summary"]
assert os.path.realpath(report["report_path"]) == output_report_path, report["report_path"]
assert report["source_report_path"].endswith("/RELFlowHub/ai_runtime_status.json"), report["source_report_path"]

assert snapshot["schema_version"] == "xhub_local_service_snapshot_export.v1", snapshot["schema_version"]
assert snapshot["provider_count"] == 1, snapshot["provider_count"]
assert snapshot["ready_provider_count"] == 0, snapshot["ready_provider_count"]

assert recovery_guidance["schema_version"] == "xhub_local_service_recovery_guidance_export.v1", recovery_guidance["schema_version"]
assert recovery_guidance["guidance_present"] is True, recovery_guidance
assert recovery_guidance["current_failure_code"] == "xhub_local_service_unreachable", recovery_guidance
assert recovery_guidance["action_category"] == "inspect_snapshot_before_retry", recovery_guidance
assert recovery_guidance["provider_check_status"] == "fail", recovery_guidance

primary_issue = snapshot.get("primary_issue")
doctor_projection = snapshot.get("doctor_projection")
providers = snapshot.get("providers") or []
recovery_actions = recovery_guidance.get("recommended_actions") or []
support_faq = recovery_guidance.get("support_faq") or []
assert isinstance(primary_issue, dict), primary_issue
assert isinstance(doctor_projection, dict), doctor_projection
assert len(providers) == 1, providers
assert len(recovery_actions) >= 1, recovery_actions
assert len(support_faq) >= 1, support_faq

provider = providers[0]
managed = provider.get("managed_service_state")
assert isinstance(managed, dict), managed

assert primary_issue["reason_code"] == "xhub_local_service_unreachable", primary_issue
assert doctor_projection["current_failure_code"] == "xhub_local_service_unreachable", doctor_projection
assert doctor_projection["provider_check_status"] == "fail", doctor_projection
assert doctor_projection["provider_check_blocking"] is True, doctor_projection
assert provider["provider_id"] == "transformers", provider
assert provider["runtime_source"] == "xhub_local_service", provider
assert provider["service_state"] == "unreachable", provider
assert provider["runtime_reason_code"] == "xhub_local_service_unreachable", provider
assert provider["service_base_url"] == "http://127.0.0.1:50171", provider
assert provider["execution_mode"] == "xhub_local_service", provider
assert provider["queued_task_count"] == 2, provider
assert provider["loaded_instance_count"] == 1, provider
assert managed["processState"] == "down", managed
assert managed["startAttemptCount"] == 2, managed
assert managed["lastStartError"] == "spawn_exit_1", managed
assert recovery_actions[0]["action_id"] == "inspect_managed_service_snapshot", recovery_actions[0]
assert support_faq[0]["faq_id"] == "why_fail_closed", support_faq[0]

evidence = {
    "schema_version": "xhub.doctor_hub_local_service_snapshot_smoke_evidence.v1",
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "status": "pass",
    "smoke_kind": "hub_local_service_snapshot",
    "hub_exit_code": int(hub_exit_code),
    "hub_output_report_path": output_report_path,
    "hub_snapshot_output_path": snapshot_output_path,
    "hub_recovery_guidance_output_path": recovery_guidance_output_path,
    "hub_status_dir": hub_status_dir,
    "hub_local_service_snapshot": snapshot,
    "hub_local_service_recovery_guidance": recovery_guidance,
    "assertions": {
        "hub_exit_code": {
            "expected": 1,
            "actual": int(hub_exit_code),
            "pass": int(hub_exit_code) == 1,
        },
        "report_failure_code": {
            "expected": "xhub_local_service_unreachable",
            "actual": report["current_failure_code"],
            "pass": report["current_failure_code"] == "xhub_local_service_unreachable",
        },
        "snapshot_primary_issue_reason_code": {
            "expected": "xhub_local_service_unreachable",
            "actual": primary_issue["reason_code"],
            "pass": primary_issue["reason_code"] == "xhub_local_service_unreachable",
        },
        "snapshot_provider_check_status": {
            "expected": "fail",
            "actual": doctor_projection["provider_check_status"],
            "pass": doctor_projection["provider_check_status"] == "fail",
        },
        "recovery_guidance_action_category": {
            "expected": "inspect_snapshot_before_retry",
            "actual": recovery_guidance["action_category"],
            "pass": recovery_guidance["action_category"] == "inspect_snapshot_before_retry",
        },
        "snapshot_provider_count": {
            "expected": 1,
            "actual": snapshot["provider_count"],
            "pass": snapshot["provider_count"] == 1,
        },
        "managed_start_attempt_count": {
            "expected": 2,
            "actual": managed["startAttemptCount"],
            "pass": managed["startAttemptCount"] == 2,
        },
    },
}

os.makedirs(os.path.dirname(evidence_path), exist_ok=True)
with open(evidence_path, "w", encoding="utf-8") as handle:
    json.dump(evidence, handle, indent=2, sort_keys=True)
    handle.write("\n")

print("[xhub-doctor-hub-local-service-smoke] PASS")
print(f"[xhub-doctor-hub-local-service-smoke] hub_output={output_report_path}")
print(f"[xhub-doctor-hub-local-service-smoke] hub_snapshot={snapshot_output_path}")
print(f"[xhub-doctor-hub-local-service-smoke] hub_recovery_guidance={recovery_guidance_output_path}")
print(f"[xhub-doctor-hub-local-service-smoke] evidence={os.path.realpath(evidence_path)}")
PY
