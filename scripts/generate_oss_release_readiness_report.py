#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

ROOT = (
    Path(os.environ["XHUB_RELEASE_ROOT"]).expanduser().resolve()
    if os.environ.get("XHUB_RELEASE_ROOT")
    else Path(__file__).resolve().parents[1]
)
REPORT_DIR = ROOT / "build" / "reports"
REPORT_DIR.mkdir(parents=True, exist_ok=True)

ALLOWLIST_DIRS = [
    ".github",
    "specs",
    "docs",
    "protocol",
    "scripts",
    "third_party",
    "x-hub/grpc-server/hub_grpc_server",
    "x-hub/macos",
    "x-hub/python-runtime",
    "x-hub/tools",
    "x-terminal",
]

ALLOWLIST_FILES = [
    "README.md",
    "LICENSE",
    "NOTICE.md",
    "SECURITY.md",
    "CONTRIBUTING.md",
    "CODE_OF_CONDUCT.md",
    "CODEOWNERS",
    "CHANGELOG.md",
    "RELEASE.md",
    ".gitignore",
    "X_MEMORY.md",
    "docs/WORKING_INDEX.md",
    "docs/open-source/OSS_RELEASE_CHECKLIST_v1.md",
    "docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md",
    "docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md",
    "check_hub_db.sh",
    "check_hub_status.sh",
    "check_report.sh",
    "check_supervisor_incident_db.sh",
    "run_supervisor_incident_db_probe.sh",
    "run_xt_ready_db_check.sh",
    "xt_ready_require_real_run.sh",
    "generate_xt_script.sh",
]

BLACKLIST_DIR_NAMES = {
    ".git",
    "build",
    "data",
    ".build",
    ".axcoder",
    ".scratch",
    ".sandbox_home",
    ".sandbox_tmp",
    ".clang-module-cache",
    ".swift-module-cache",
    "DerivedData",
    "node_modules",
    "__pycache__",
}

BLACKLIST_SUFFIXES = (
    ".sqlite",
    ".sqlite3",
    ".sqlite3-shm",
    ".sqlite3-wal",
    ".log",
    ".app",
    ".dmg",
    ".zip",
    ".tar.gz",
    ".tgz",
    ".pkg",
)

HIGH_RISK_CONTENT_PATTERNS = [
    re.compile(r"-----BEGIN (?:RSA|EC|OPENSSH|PRIVATE) PRIVATE KEY-----[\s\S]{20,}?-----END (?:RSA|EC|OPENSSH|PRIVATE) PRIVATE KEY-----"),
    re.compile(r"ghp_[A-Za-z0-9]{20,}"),
    re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}"),
    re.compile(r"sk-(?:live|proj)-[A-Za-z0-9]{10,}", re.IGNORECASE),
    re.compile(r"api[_-]?key\s*[:=]\s*['\"][A-Za-z0-9_\-]{12,}['\"]", re.IGNORECASE),
    re.compile(r"(?:access|api|auth|bearer|bot|client|id|refresh|replay|secret|session|slack|webhook)[_-]?token\s*[:=]\s*['\"][A-Za-z0-9_\-]{12,}['\"]", re.IGNORECASE),
    re.compile(r"password\s*[:=]\s*['\"][^\s'\"]{8,}['\"]", re.IGNORECASE),
]

KEYWORD_SCAN_PATTERNS = [
    re.compile(r"BEGIN (?:RSA|EC|OPENSSH) PRIVATE KEY"),
    re.compile(r"api[_-]?key", re.IGNORECASE),
    re.compile(r"secret", re.IGNORECASE),
    re.compile(r"token", re.IGNORECASE),
    re.compile(r"password", re.IGNORECASE),
    re.compile(r"kek", re.IGNORECASE),
    re.compile(r"dek", re.IGNORECASE),
]


def iso_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def rel_posix(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def path_under_prefix(rel_path: str, prefix: str) -> bool:
    prefix = prefix.rstrip("/")
    return rel_path == prefix or rel_path.startswith(prefix + "/")


def is_allowlisted(rel_path: str) -> bool:
    if rel_path in ALLOWLIST_FILES:
        return True
    return any(path_under_prefix(rel_path, prefix) for prefix in ALLOWLIST_DIRS)


def has_blacklist_component(rel_path: str) -> bool:
    parts = rel_path.split("/")
    if any(part in BLACKLIST_DIR_NAMES for part in parts):
        return True
    if rel_path.startswith("archive/x-terminal-legacy/"):
        return True
    lower = rel_path.lower()
    if any(lower.endswith(suffix) for suffix in BLACKLIST_SUFFIXES):
        return True
    basename = parts[-1].lower()
    if basename == ".env":
        return True
    if "private key" in lower:
        return True
    if "kek" in lower or "dek" in lower:
        return True
    if "secret" in lower or "token" in lower or "password" in lower:
        return True
    return False


def walk_all_files() -> list[str]:
    files: list[str] = []
    for dirpath, dirnames, filenames in os.walk(ROOT, topdown=True, followlinks=False):
        current = Path(dirpath)
        rel_dir = "" if current == ROOT else current.relative_to(ROOT).as_posix()

        kept_dirnames: list[str] = []
        for name in dirnames:
            rel_path = f"{rel_dir}/{name}" if rel_dir else name
            if (
                name in BLACKLIST_DIR_NAMES
                or name.startswith(".scratch")
                or (name.startswith(".ax") and name != ".github")
                or rel_path == "archive/x-terminal-legacy"
            ):
                continue
            kept_dirnames.append(name)
        dirnames[:] = kept_dirnames

        for filename in filenames:
            rel_path = f"{rel_dir}/{filename}" if rel_dir else filename
            files.append(rel_path)
    return sorted(files)


def load_json(rel_path: str) -> dict:
    return json.loads((ROOT / rel_path).read_text(encoding="utf-8"))


def load_json_if_exists(rel_path: str) -> dict | None:
    path = ROOT / rel_path
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def read_text(rel_path: str) -> str:
    return (ROOT / rel_path).read_text(encoding="utf-8")


def safe_text(path: Path) -> str | None:
    try:
        if path.stat().st_size > 2_000_000:
            return None
        return path.read_text(encoding="utf-8")
    except Exception:
        return None


def is_example_or_test_path(rel_path: str) -> bool:
    lower = rel_path.lower()
    return (
        lower.startswith("docs/")
        or lower.endswith("readme.md")
        or "/tests/" in lower
        or lower.endswith(".test.js")
        or lower.endswith(".test.ts")
        or lower.endswith("tests.swift")
        or "/fixtures/" in lower
        or ".sample." in lower
        or lower.endswith("sample.json")
    )


def is_placeholder_excerpt(text: str) -> bool:
    lower = text.lower()
    placeholders = ["replace", "example", "sample", "dummy", "danger", "abcdef", "snapshot", "client_token", "replay_token"]
    return any(token in lower for token in placeholders)


def sha256_lines(lines: Iterable[str]) -> str:
    payload = "\n".join(lines).encode("utf-8")
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def compact_project_context_summary(summary: dict | None) -> dict | None:
    if not isinstance(summary, dict):
        return None
    return {
        "source_kind": summary.get("source_kind"),
        "source_badge": summary.get("source_badge"),
        "status_line": summary.get("status_line"),
        "project_label": summary.get("project_label"),
        "dialogue_metric": summary.get("dialogue_metric"),
        "depth_metric": summary.get("depth_metric"),
        "dialogue_line": summary.get("dialogue_line"),
        "depth_line": summary.get("depth_line"),
        "coverage_metric": summary.get("coverage_metric"),
        "boundary_metric": summary.get("boundary_metric"),
        "coverage_line": summary.get("coverage_line"),
        "boundary_line": summary.get("boundary_line"),
    }


def compact_project_memory_policy(policy: dict | None) -> dict | None:
    if not isinstance(policy, dict):
        return None
    return {
        "configured_recent_project_dialogue_profile": policy.get("configured_recent_project_dialogue_profile"),
        "configured_project_context_depth": policy.get("configured_project_context_depth"),
        "recommended_recent_project_dialogue_profile": policy.get("recommended_recent_project_dialogue_profile"),
        "recommended_project_context_depth": policy.get("recommended_project_context_depth"),
        "effective_recent_project_dialogue_profile": policy.get("effective_recent_project_dialogue_profile"),
        "effective_project_context_depth": policy.get("effective_project_context_depth"),
        "a_tier_memory_ceiling": policy.get("a_tier_memory_ceiling"),
        "audit_ref": policy.get("audit_ref"),
    }


def compact_supervisor_memory_policy(policy: dict | None) -> dict | None:
    if not isinstance(policy, dict):
        return None
    return {
        "configured_supervisor_recent_raw_context_profile": policy.get("configured_supervisor_recent_raw_context_profile"),
        "configured_review_memory_depth": policy.get("configured_review_memory_depth"),
        "recommended_supervisor_recent_raw_context_profile": policy.get("recommended_supervisor_recent_raw_context_profile"),
        "recommended_review_memory_depth": policy.get("recommended_review_memory_depth"),
        "effective_supervisor_recent_raw_context_profile": policy.get("effective_supervisor_recent_raw_context_profile"),
        "effective_review_memory_depth": policy.get("effective_review_memory_depth"),
        "s_tier_review_memory_ceiling": policy.get("s_tier_review_memory_ceiling"),
        "audit_ref": policy.get("audit_ref"),
    }


def compact_memory_assembly_resolution(snapshot: dict | None) -> dict | None:
    if not isinstance(snapshot, dict):
        return None
    return {
        "role": snapshot.get("role"),
        "dominant_mode": snapshot.get("dominant_mode"),
        "trigger": snapshot.get("trigger"),
        "configured_depth": snapshot.get("configured_depth"),
        "recommended_depth": snapshot.get("recommended_depth"),
        "effective_depth": snapshot.get("effective_depth"),
        "ceiling_from_tier": snapshot.get("ceiling_from_tier"),
        "ceiling_hit": snapshot.get("ceiling_hit"),
        "selected_slots": snapshot.get("selected_slots") if isinstance(snapshot.get("selected_slots"), list) else [],
        "selected_planes": snapshot.get("selected_planes") if isinstance(snapshot.get("selected_planes"), list) else [],
        "selected_serving_objects": snapshot.get("selected_serving_objects") if isinstance(snapshot.get("selected_serving_objects"), list) else [],
        "excluded_blocks": snapshot.get("excluded_blocks") if isinstance(snapshot.get("excluded_blocks"), list) else [],
        "budget_summary": snapshot.get("budget_summary"),
        "audit_ref": snapshot.get("audit_ref"),
    }


def compact_durable_candidate_mirror_snapshot(snapshot: dict | None) -> dict | None:
    if not isinstance(snapshot, dict):
        return None
    return {
        "status": snapshot.get("status"),
        "target": snapshot.get("target"),
        "attempted": snapshot.get("attempted"),
        "error_code": snapshot.get("error_code"),
        "local_store_role": snapshot.get("local_store_role"),
    }


def compact_heartbeat_governance_snapshot(snapshot: dict | None) -> dict | None:
    if not isinstance(snapshot, dict):
        return None
    weak_reasons = snapshot.get("weak_reasons")
    open_anomaly_types = snapshot.get("open_anomaly_types")
    return {
        "project_id": snapshot.get("project_id"),
        "project_name": snapshot.get("project_name"),
        "status_digest": snapshot.get("status_digest"),
        "latest_quality_band": snapshot.get("latest_quality_band"),
        "latest_quality_score": snapshot.get("latest_quality_score"),
        "weak_reasons": weak_reasons if isinstance(weak_reasons, list) else [],
        "open_anomaly_types": open_anomaly_types if isinstance(open_anomaly_types, list) else [],
        "project_phase": snapshot.get("project_phase"),
        "execution_status": snapshot.get("execution_status"),
        "risk_tier": snapshot.get("risk_tier"),
        "progress_heartbeat_effective_seconds": snapshot.get("progress_heartbeat_effective_seconds"),
        "review_pulse_effective_seconds": snapshot.get("review_pulse_effective_seconds"),
        "brainstorm_review_effective_seconds": snapshot.get("brainstorm_review_effective_seconds"),
        "next_review_kind": snapshot.get("next_review_kind"),
        "next_review_due": snapshot.get("next_review_due"),
        "recovery_decision": compact_heartbeat_recovery_decision(snapshot.get("recovery_decision")),
    }


def compact_heartbeat_recovery_decision(decision: dict | None) -> dict | None:
    if not isinstance(decision, dict):
        return None

    compacted: dict[str, object] = {}
    scalar_fields = [
        "action",
        "action_display_text",
        "urgency",
        "urgency_display_text",
        "reason_code",
        "reason_display_text",
        "system_next_step_display_text",
        "summary",
        "doctor_explainability_text",
        "queued_review_trigger",
        "queued_review_trigger_display_text",
        "queued_review_level",
        "queued_review_level_display_text",
        "queued_review_run_kind",
        "queued_review_run_kind_display_text",
    ]
    for field in scalar_fields:
        value = decision.get(field)
        if value not in (None, ""):
            compacted[field] = value

    array_fields = [
        "source_signals",
        "source_signal_display_texts",
        "anomaly_types",
        "anomaly_type_display_texts",
        "blocked_lane_reasons",
        "blocked_lane_reason_display_texts",
    ]
    for field in array_fields:
        value = decision.get(field)
        if isinstance(value, list) and value:
            compacted[field] = value

    count_fields = [
        "blocked_lane_count",
        "stalled_lane_count",
        "failed_lane_count",
        "recovering_lane_count",
    ]
    for field in count_fields:
        value = decision.get(field)
        if isinstance(value, int):
            compacted[field] = value

    requires_user_action = decision.get("requires_user_action")
    if isinstance(requires_user_action, bool):
        compacted["requires_user_action"] = requires_user_action

    return compacted or None


def compact_local_store_write_snapshot(snapshot: dict | None) -> dict | None:
    if not isinstance(snapshot, dict):
        return None
    return {
        "personal_memory_intent": snapshot.get("personal_memory_intent"),
        "cross_link_intent": snapshot.get("cross_link_intent"),
        "personal_review_intent": snapshot.get("personal_review_intent"),
    }


def compact_remote_snapshot_cache_snapshot(snapshot: dict | None) -> dict | None:
    if not isinstance(snapshot, dict):
        return None
    return {
        "source": snapshot.get("source"),
        "freshness": snapshot.get("freshness"),
        "cache_hit": snapshot.get("cache_hit"),
        "scope": snapshot.get("scope"),
        "cached_at_ms": snapshot.get("cached_at_ms"),
        "age_ms": snapshot.get("age_ms"),
        "ttl_remaining_ms": snapshot.get("ttl_remaining_ms"),
    }


def compact_xt_route_target_snapshot(snapshot: dict | None) -> dict | None:
    if not isinstance(snapshot, dict):
        return None
    return {
        "route_kind": snapshot.get("route_kind"),
        "host": snapshot.get("host"),
        "pairing_port": snapshot.get("pairing_port"),
        "grpc_port": snapshot.get("grpc_port"),
        "host_kind": snapshot.get("host_kind"),
        "source": snapshot.get("source"),
    }


def compact_xt_first_pair_completion_proof_snapshot(snapshot: dict | None) -> dict | None:
    if not isinstance(snapshot, dict):
        return None
    return {
        "readiness": snapshot.get("readiness"),
        "same_lan_verified": snapshot.get("same_lan_verified"),
        "owner_local_approval_verified": snapshot.get("owner_local_approval_verified"),
        "pairing_material_issued": snapshot.get("pairing_material_issued"),
        "cached_reconnect_smoke_passed": snapshot.get("cached_reconnect_smoke_passed"),
        "stable_remote_route_present": snapshot.get("stable_remote_route_present"),
        "remote_shadow_smoke_passed": snapshot.get("remote_shadow_smoke_passed"),
        "remote_shadow_smoke_status": snapshot.get("remote_shadow_smoke_status"),
        "remote_shadow_smoke_source": snapshot.get("remote_shadow_smoke_source"),
        "remote_shadow_route": snapshot.get("remote_shadow_route"),
        "remote_shadow_reason_code": snapshot.get("remote_shadow_reason_code"),
        "remote_shadow_summary": snapshot.get("remote_shadow_summary"),
        "summary_line": snapshot.get("summary_line"),
    }


def compact_xt_paired_route_set_snapshot(snapshot: dict | None) -> dict | None:
    if not isinstance(snapshot, dict):
        return None
    return {
        "readiness": snapshot.get("readiness"),
        "readiness_reason_code": snapshot.get("readiness_reason_code"),
        "summary_line": snapshot.get("summary_line"),
        "hub_instance_id": snapshot.get("hub_instance_id"),
        "pairing_profile_epoch": snapshot.get("pairing_profile_epoch"),
        "route_pack_version": snapshot.get("route_pack_version"),
        "active_route": compact_xt_route_target_snapshot(snapshot.get("active_route")),
        "lan_route": compact_xt_route_target_snapshot(snapshot.get("lan_route")),
        "stable_remote_route": compact_xt_route_target_snapshot(snapshot.get("stable_remote_route")),
        "last_known_good_route": compact_xt_route_target_snapshot(snapshot.get("last_known_good_route")),
        "cached_reconnect_smoke_status": snapshot.get("cached_reconnect_smoke_status"),
        "cached_reconnect_smoke_reason_code": snapshot.get("cached_reconnect_smoke_reason_code"),
        "cached_reconnect_smoke_summary": snapshot.get("cached_reconnect_smoke_summary"),
    }


def compact_xt_pairing_readiness_support(support: dict | None) -> dict | None:
    if not isinstance(support, dict):
        return None
    return {
        "xt_source_smoke_status": support.get("xt_source_smoke_status"),
        "all_source_smoke_status": support.get("all_source_smoke_status"),
        "xt_source_first_pair_completion_proof": compact_xt_first_pair_completion_proof_snapshot(
            support.get("xt_source_first_pair_completion_proof")
        ),
        "xt_source_paired_route_set": compact_xt_paired_route_set_snapshot(
            support.get("xt_source_paired_route_set")
        ),
        "all_source_first_pair_completion_proof": compact_xt_first_pair_completion_proof_snapshot(
            support.get("all_source_first_pair_completion_proof")
        ),
        "all_source_paired_route_set": compact_xt_paired_route_set_snapshot(
            support.get("all_source_paired_route_set")
        ),
        "xt_source_smoke_evidence_ref": support.get("xt_source_smoke_evidence_ref"),
        "all_source_smoke_evidence_ref": support.get("all_source_smoke_evidence_ref"),
    }


def compact_memory_route_truth_snapshot(snapshot: dict | None) -> dict | None:
    if not isinstance(snapshot, dict):
        return None
    return {
        "projection_source": snapshot.get("projection_source"),
        "completeness": snapshot.get("completeness"),
        "route_source": snapshot.get("route_source"),
        "route_reason_code": snapshot.get("route_reason_code"),
        "binding_provider": snapshot.get("binding_provider"),
        "binding_model_id": snapshot.get("binding_model_id"),
    }


def compact_memory_truth_closure_snapshot(snapshot: dict | None) -> dict | None:
    if not isinstance(snapshot, dict):
        return None
    truth_examples = snapshot.get("truth_examples")
    return {
        "truth_examples": [
            {
                "raw_source": item.get("raw_source"),
                "label": item.get("label"),
                "explainable_label": item.get("explainable_label"),
                "truth_hint": item.get("truth_hint"),
            }
            for item in truth_examples
            if isinstance(item, dict)
        ] if isinstance(truth_examples, list) else [],
        "project_context": (
            {
                "memory_source": snapshot.get("project_context", {}).get("memory_source"),
                "memory_source_label": snapshot.get("project_context", {}).get("memory_source_label"),
                "writer_gate_boundary_present": snapshot.get("project_context", {}).get("writer_gate_boundary_present"),
            }
            if isinstance(snapshot.get("project_context"), dict)
            else None
        ),
        "supervisor_memory": (
            {
                "memory_source": snapshot.get("supervisor_memory", {}).get("memory_source"),
                "mode_source_text": snapshot.get("supervisor_memory", {}).get("mode_source_text"),
                "continuity_detail_line": snapshot.get("supervisor_memory", {}).get("continuity_detail_line"),
            }
            if isinstance(snapshot.get("supervisor_memory"), dict)
            else None
        ),
        "canonical_sync_closure": (
            {
                "doctor_summary_line": snapshot.get("canonical_sync_closure", {}).get("doctor_summary_line"),
                "audit_ref": snapshot.get("canonical_sync_closure", {}).get("audit_ref"),
                "evidence_ref": snapshot.get("canonical_sync_closure", {}).get("evidence_ref"),
                "writeback_ref": snapshot.get("canonical_sync_closure", {}).get("writeback_ref"),
                "strict_issue_code": snapshot.get("canonical_sync_closure", {}).get("strict_issue_code"),
            }
            if isinstance(snapshot.get("canonical_sync_closure"), dict)
            else None
        ),
    }


def compact_build_snapshot_inventory_surface(surface: dict | None) -> dict | None:
    if not isinstance(surface, dict):
        return None
    keep_refs = surface.get("would_keep_history_refs")
    prune_refs = surface.get("would_prune_history_refs")
    return {
        "status": surface.get("status"),
        "snapshot_root_ref": surface.get("snapshot_root_ref"),
        "snapshot_root_exists": surface.get("snapshot_root_exists"),
        "retention_keep_count": surface.get("retention_keep_count"),
        "current_snapshot_ref": surface.get("current_snapshot_ref"),
        "current_snapshot_size_bytes": surface.get("current_snapshot_size_bytes"),
        "historical_snapshot_count": surface.get("historical_snapshot_count"),
        "historical_snapshot_total_bytes": surface.get("historical_snapshot_total_bytes"),
        "would_prune_history_count": surface.get("would_prune_history_count"),
        "would_prune_total_bytes": surface.get("would_prune_total_bytes"),
        "would_keep_history_refs": keep_refs if isinstance(keep_refs, list) else [],
        "would_prune_history_refs": prune_refs if isinstance(prune_refs, list) else [],
    }


def compact_build_snapshot_inventory_support(support: dict | None) -> dict | None:
    if not isinstance(support, dict):
        return None
    inventory_summary = support.get("inventory_summary")
    if not isinstance(inventory_summary, dict):
        inventory_summary = {}
    stale_history_surface_ids = inventory_summary.get("stale_history_surface_ids")
    return {
        "report_ref": support.get("report_ref"),
        "build_snapshot_inventory_generation_status": support.get("build_snapshot_inventory_generation_status"),
        "summary_status": inventory_summary.get("summary_status"),
        "verdict_reason": inventory_summary.get("verdict_reason"),
        "stale_history_surface_ids": (
            stale_history_surface_ids if isinstance(stale_history_surface_ids, list) else []
        ),
        "largest_reclaim_candidate_surface_id": inventory_summary.get("largest_reclaim_candidate_surface_id"),
        "current_snapshot_total_bytes": inventory_summary.get("current_snapshot_total_bytes"),
        "historical_snapshot_total_bytes": inventory_summary.get("historical_snapshot_total_bytes"),
        "projected_prune_total_bytes": inventory_summary.get("projected_prune_total_bytes"),
        "projected_prune_history_count": inventory_summary.get("projected_prune_history_count"),
        "hub": compact_build_snapshot_inventory_surface(inventory_summary.get("hub")),
        "xterminal": compact_build_snapshot_inventory_surface(inventory_summary.get("xterminal")),
    }


def compact_scan_root_snapshot(snapshot: dict | None) -> dict | None:
    if not isinstance(snapshot, dict):
        return None
    return {
        "path": snapshot.get("path"),
        "present": snapshot.get("present"),
    }


def compact_helper_local_service_recovery(report: dict | None) -> dict | None:
    if not isinstance(report, dict):
        return None
    current_machine_state = report.get("current_machine_state")
    helper_route_contract = report.get("helper_route_contract")
    top_recommended_action = report.get("top_recommended_action")
    operator_workflow = report.get("operator_workflow")
    artifact_refs = report.get("artifact_refs")
    return {
        "current_machine_state": (
            {
                "helper_binary_found": current_machine_state.get("helper_binary_found"),
                "helper_binary_path": current_machine_state.get("helper_binary_path"),
                "helper_server_base_url": current_machine_state.get("helper_server_base_url"),
                "server_models_endpoint_ok": current_machine_state.get("server_models_endpoint_ok"),
                "settings_found": current_machine_state.get("settings_found"),
                "settings_path": current_machine_state.get("settings_path"),
                "enable_local_service": current_machine_state.get("enable_local_service"),
                "cli_installed": current_machine_state.get("cli_installed"),
                "app_first_load": current_machine_state.get("app_first_load"),
                "primary_blocker": current_machine_state.get("primary_blocker"),
                "recommended_next_step": current_machine_state.get("recommended_next_step"),
            }
            if isinstance(current_machine_state, dict)
            else None
        ),
        "helper_route_contract": (
            {
                "helper_route_role": helper_route_contract.get("helper_route_role"),
                "helper_route_ready_verdict": helper_route_contract.get("helper_route_ready_verdict"),
                "required_ready_signals": helper_route_contract.get("required_ready_signals"),
                "reject_signals": [
                    {
                        "signal": signal.get("signal"),
                        "reason": signal.get("reason"),
                    }
                    for signal in helper_route_contract.get("reject_signals", [])
                    if isinstance(signal, dict)
                ],
            }
            if isinstance(helper_route_contract, dict)
            else None
        ),
        "top_recommended_action": (
            {
                "action_id": top_recommended_action.get("action_id"),
                "action_summary": top_recommended_action.get("action_summary"),
                "next_step": top_recommended_action.get("next_step"),
                "command_or_ref": top_recommended_action.get("command_or_ref"),
            }
            if isinstance(top_recommended_action, dict)
            else None
        ),
        "operator_workflow": [
            {
                "step_id": step.get("step_id"),
                "allowed_now": step.get("allowed_now"),
                "description": step.get("description"),
                "command": step.get("command"),
                "command_or_ref": step.get("command_or_ref"),
            }
            for step in operator_workflow
            if isinstance(step, dict)
        ] if isinstance(operator_workflow, list) else [],
        "artifact_refs": (
            {
                "helper_probe_report": artifact_refs.get("helper_probe_report"),
            }
            if isinstance(artifact_refs, dict)
            else None
        ),
    }


def compact_require_real_search_recovery(report: dict | None) -> dict | None:
    if not isinstance(report, dict):
        return None
    return {
        "exact_path_known": report.get("exact_path_known"),
        "exact_path_exists": report.get("exact_path_exists"),
        "exact_path_validation_command": report.get("exact_path_validation_command"),
        "wide_shortlist_search_command": report.get("wide_shortlist_search_command"),
        "preferred_next_step": report.get("preferred_next_step"),
    }


def compact_operator_recovery_support(report: dict | None) -> dict | None:
    if not isinstance(report, dict):
        return None
    recommended_actions = report.get("recommended_actions")
    top_action = recommended_actions[0] if isinstance(recommended_actions, list) and recommended_actions else None
    require_real_focus = report.get("require_real_focus")
    return {
        "schema_version": report.get("schema_version"),
        "gate_verdict": report.get("gate_verdict"),
        "release_stance": report.get("release_stance"),
        "machine_decision": (
            {
                "support_ready": report.get("machine_decision", {}).get("support_ready"),
                "release_ready": report.get("machine_decision", {}).get("release_ready"),
                "source_gate_status": report.get("machine_decision", {}).get("source_gate_status"),
                "snapshot_smoke_status": report.get("machine_decision", {}).get("snapshot_smoke_status"),
                "require_real_release_stance": report.get("machine_decision", {}).get("require_real_release_stance"),
                "require_real_focus_helper_local_service_recovery_present": report.get("machine_decision", {}).get("require_real_focus_helper_local_service_recovery_present"),
                "action_category": report.get("machine_decision", {}).get("action_category"),
            }
            if isinstance(report.get("machine_decision"), dict)
            else None
        ),
        "local_service_truth": (
            {
                "provider_id": report.get("local_service_truth", {}).get("provider_id"),
                "primary_issue_reason_code": report.get("local_service_truth", {}).get("primary_issue_reason_code"),
                "doctor_failure_code": report.get("local_service_truth", {}).get("doctor_failure_code"),
                "doctor_provider_check_status": report.get("local_service_truth", {}).get("doctor_provider_check_status"),
                "service_state": report.get("local_service_truth", {}).get("service_state"),
                "runtime_reason_code": report.get("local_service_truth", {}).get("runtime_reason_code"),
                "managed_process_state": report.get("local_service_truth", {}).get("managed_process_state"),
                "managed_start_attempt_count": report.get("local_service_truth", {}).get("managed_start_attempt_count"),
                "managed_last_start_error": report.get("local_service_truth", {}).get("managed_last_start_error"),
                "repair_destination_ref": report.get("local_service_truth", {}).get("repair_destination_ref"),
            }
            if isinstance(report.get("local_service_truth"), dict)
            else None
        ),
        "recovery_classification": (
            {
                "action_category": report.get("recovery_classification", {}).get("action_category"),
                "severity": report.get("recovery_classification", {}).get("severity"),
                "install_hint": report.get("recovery_classification", {}).get("install_hint"),
            }
            if isinstance(report.get("recovery_classification"), dict)
            else None
        ),
        "release_wording": (
            {
                "external_status_line": report.get("release_wording", {}).get("external_status_line"),
            }
            if isinstance(report.get("release_wording"), dict)
            else None
        ),
        "top_recommended_action": (
            {
                "rank": top_action.get("rank"),
                "action_id": top_action.get("action_id"),
                "title": top_action.get("title"),
                "command_or_ref": top_action.get("command_or_ref"),
            }
            if isinstance(top_action, dict)
            else None
        ),
        "require_real_focus": (
            {
                "handoff_state": require_real_focus.get("handoff_state"),
                "blocker_class": require_real_focus.get("blocker_class"),
                "top_recommended_action": (
                    {
                        "action_id": require_real_focus.get("top_recommended_action", {}).get("action_id"),
                        "action_summary": require_real_focus.get("top_recommended_action", {}).get("action_summary"),
                    }
                    if isinstance(require_real_focus.get("top_recommended_action"), dict)
                    else None
                ),
                "helper_local_service_recovery": compact_helper_local_service_recovery(
                    require_real_focus.get("helper_local_service_recovery")
                ),
                "checked_sources": (
                    {
                        "scan_roots": [
                            compacted
                            for compacted in (
                                compact_scan_root_snapshot(snapshot)
                                for snapshot in require_real_focus.get("checked_sources", {}).get("scan_roots", [])
                            )
                            if compacted is not None
                        ],
                    }
                    if isinstance(require_real_focus.get("checked_sources"), dict)
                    else None
                ),
                "search_recovery": compact_require_real_search_recovery(
                    require_real_focus.get("search_recovery")
                ),
                "candidate_acceptance": (
                    {
                        "acceptance_contract": (
                            {
                                "required_gate_verdict": require_real_focus.get("candidate_acceptance", {}).get("acceptance_contract", {}).get("required_gate_verdict"),
                                "required_loadability_verdict": require_real_focus.get("candidate_acceptance", {}).get("acceptance_contract", {}).get("required_loadability_verdict"),
                            }
                            if isinstance(require_real_focus.get("candidate_acceptance", {}).get("acceptance_contract"), dict)
                            else None
                        ),
                        "current_no_go_example": (
                            {
                                "normalized_model_dir": require_real_focus.get("candidate_acceptance", {}).get("current_no_go_example", {}).get("normalized_model_dir"),
                                "loadability_blocker": require_real_focus.get("candidate_acceptance", {}).get("current_no_go_example", {}).get("loadability_blocker"),
                            }
                            if isinstance(require_real_focus.get("candidate_acceptance", {}).get("current_no_go_example"), dict)
                            else None
                        ),
                    }
                    if isinstance(require_real_focus.get("candidate_acceptance"), dict)
                    else None
                ),
                "candidate_registration": (
                    {
                        "machine_decision": (
                            {
                                "catalog_write_allowed_now": require_real_focus.get("candidate_registration", {}).get("machine_decision", {}).get("catalog_write_allowed_now"),
                                "top_recommended_action": (
                                    {
                                        "action_id": require_real_focus.get("candidate_registration", {}).get("machine_decision", {}).get("top_recommended_action", {}).get("action_id"),
                                        "action_summary": require_real_focus.get("candidate_registration", {}).get("machine_decision", {}).get("top_recommended_action", {}).get("action_summary"),
                                    }
                                    if isinstance(require_real_focus.get("candidate_registration", {}).get("machine_decision", {}).get("top_recommended_action"), dict)
                                    else None
                                ),
                            }
                            if isinstance(require_real_focus.get("candidate_registration", {}).get("machine_decision"), dict)
                            else None
                        ),
                        "candidate_validation": (
                            {
                                "gate_verdict": require_real_focus.get("candidate_registration", {}).get("candidate_validation", {}).get("gate_verdict"),
                                "loadability_blocker": require_real_focus.get("candidate_registration", {}).get("candidate_validation", {}).get("loadability_blocker"),
                            }
                            if isinstance(require_real_focus.get("candidate_registration", {}).get("candidate_validation"), dict)
                            else None
                        ),
                        "proposed_catalog_entry": (
                            {
                                "id": require_real_focus.get("candidate_registration", {}).get("proposed_catalog_entry", {}).get("id"),
                                "backend": require_real_focus.get("candidate_registration", {}).get("proposed_catalog_entry", {}).get("backend"),
                                "model_path": require_real_focus.get("candidate_registration", {}).get("proposed_catalog_entry", {}).get("model_path"),
                            }
                            if isinstance(require_real_focus.get("candidate_registration", {}).get("proposed_catalog_entry"), dict)
                            else None
                        ),
                        "catalog_patch_plan_summary": (
                            {
                                "artifact_ref": require_real_focus.get("candidate_registration", {}).get("catalog_patch_plan_summary", {}).get("artifact_ref"),
                                "manual_patch_allowed_now": require_real_focus.get("candidate_registration", {}).get("catalog_patch_plan_summary", {}).get("manual_patch_allowed_now"),
                                "blocked_reason": require_real_focus.get("candidate_registration", {}).get("catalog_patch_plan_summary", {}).get("blocked_reason"),
                                "eligible_target_base_count": require_real_focus.get("candidate_registration", {}).get("catalog_patch_plan_summary", {}).get("eligible_target_base_count"),
                                "blocked_target_base_count": require_real_focus.get("candidate_registration", {}).get("catalog_patch_plan_summary", {}).get("blocked_target_base_count"),
                            }
                            if isinstance(require_real_focus.get("candidate_registration", {}).get("catalog_patch_plan_summary"), dict)
                            else None
                        ),
                    }
                    if isinstance(require_real_focus.get("candidate_registration"), dict)
                    else None
                ),
            }
            if isinstance(require_real_focus, dict)
            else None
        ),
    }


def compact_operator_channel_recovery_support(report: dict | None) -> dict | None:
    if not isinstance(report, dict):
        return None
    recommended_actions = report.get("recommended_actions")
    top_action = recommended_actions[0] if isinstance(recommended_actions, list) and recommended_actions else None
    onboarding_truth = report.get("onboarding_truth")
    current_failure_code = (
        onboarding_truth.get("current_failure_code")
        if isinstance(onboarding_truth, dict)
        else None
    )
    heartbeat_governance_visibility_gap = (
        current_failure_code == "channel_live_test_heartbeat_visibility_missing"
    )
    return {
        "schema_version": report.get("schema_version"),
        "gate_verdict": report.get("gate_verdict"),
        "release_stance": report.get("release_stance"),
        "heartbeat_governance_visibility_gap": heartbeat_governance_visibility_gap,
        "channel_focus_highlight": (
            "First smoke proof still lacks heartbeat governance visibility."
            if heartbeat_governance_visibility_gap
            else None
        ),
        "machine_decision": (
            {
                "support_ready": report.get("machine_decision", {}).get("support_ready"),
                "source": report.get("machine_decision", {}).get("source"),
                "source_gate_status": report.get("machine_decision", {}).get("source_gate_status"),
                "all_source_smoke_status": report.get("machine_decision", {}).get("all_source_smoke_status"),
                "overall_state": report.get("machine_decision", {}).get("overall_state"),
                "ready_for_first_task": report.get("machine_decision", {}).get("ready_for_first_task"),
                "current_failure_code": report.get("machine_decision", {}).get("current_failure_code"),
                "current_failure_issue": report.get("machine_decision", {}).get("current_failure_issue"),
                "action_category": report.get("machine_decision", {}).get("action_category"),
            }
            if isinstance(report.get("machine_decision"), dict)
            else None
        ),
        "onboarding_truth": (
            {
                "overall_state": onboarding_truth.get("overall_state"),
                "ready_for_first_task": onboarding_truth.get("ready_for_first_task"),
                "current_failure_code": onboarding_truth.get("current_failure_code"),
                "current_failure_issue": onboarding_truth.get("current_failure_issue"),
                "primary_check_kind": onboarding_truth.get("primary_check_kind"),
                "primary_check_status": onboarding_truth.get("primary_check_status"),
                "primary_check_blocking": onboarding_truth.get("primary_check_blocking"),
                "repair_destination_ref": onboarding_truth.get("repair_destination_ref"),
            }
            if isinstance(onboarding_truth, dict)
            else None
        ),
        "recovery_classification": (
            {
                "action_category": report.get("recovery_classification", {}).get("action_category"),
                "severity": report.get("recovery_classification", {}).get("severity"),
                "install_hint": report.get("recovery_classification", {}).get("install_hint"),
            }
            if isinstance(report.get("recovery_classification"), dict)
            else None
        ),
        "release_wording": (
            {
                "external_status_line": report.get("release_wording", {}).get("external_status_line"),
            }
            if isinstance(report.get("release_wording"), dict)
            else None
        ),
        "top_recommended_action": (
            {
                "rank": top_action.get("rank"),
                "action_id": top_action.get("action_id"),
                "title": top_action.get("title"),
                "command_or_ref": top_action.get("command_or_ref"),
            }
            if isinstance(top_action, dict)
            else None
        ),
    }


def resolve_preferred_xt_ready_artifacts() -> tuple[str, str, str, str]:
    candidates = [
        (
            "require_real_release_chain",
            "build/xt_ready_gate_e2e_require_real_report.json",
            [
                "build/xt_ready_evidence_source.require_real.json",
                "build/xt_ready_evidence_source.json",
            ],
            [
                "build/connector_ingress_gate_snapshot.require_real.json",
                "build/connector_ingress_gate_snapshot.json",
            ],
        ),
        (
            "db_real_release_chain",
            "build/xt_ready_gate_e2e_db_real_report.json",
            [
                "build/xt_ready_evidence_source.db_real.json",
                "build/xt_ready_evidence_source.require_real.json",
                "build/xt_ready_evidence_source.json",
            ],
            [
                "build/connector_ingress_gate_snapshot.db_real.json",
                "build/connector_ingress_gate_snapshot.require_real.json",
                "build/connector_ingress_gate_snapshot.json",
            ],
        ),
        (
            "current_gate",
            "build/xt_ready_gate_e2e_report.json",
            [
                "build/xt_ready_evidence_source.json",
            ],
            [
                "build/connector_ingress_gate_snapshot.json",
            ],
        ),
    ]
    for mode, report_ref, source_refs, connector_refs in candidates:
        if not (ROOT / report_ref).exists():
            continue
        source_ref = next((ref for ref in source_refs if (ROOT / ref).exists()), source_refs[0])
        connector_ref = next((ref for ref in connector_refs if (ROOT / ref).exists()), connector_refs[0])
        return mode, report_ref, source_ref, connector_ref
    raise FileNotFoundError("missing XT-Ready gate evidence: no preferred report candidate exists")


def main() -> None:
    all_files = walk_all_files()
    allowlisted_files = [path for path in all_files if is_allowlisted(path)]
    public_files = [path for path in allowlisted_files if not has_blacklist_component(path)]
    excluded_blacklist_hits = [path for path in all_files if has_blacklist_component(path)]
    excluded_allowlist_misses = [path for path in all_files if not is_allowlisted(path) and not has_blacklist_component(path)]

    governance_required = [
        "README.md",
        "LICENSE",
        "NOTICE.md",
        "SECURITY.md",
        "CONTRIBUTING.md",
        "CODE_OF_CONDUCT.md",
        "CODEOWNERS",
        "CHANGELOG.md",
        "RELEASE.md",
        ".gitignore",
    ]
    community_required = [
        ".github/ISSUE_TEMPLATE/bug_report.yml",
        ".github/ISSUE_TEMPLATE/feature_request.yml",
        ".github/PULL_REQUEST_TEMPLATE.md",
        ".github/dependabot.yml",
    ]

    governance_checks = [{"path": path, "ok": (ROOT / path).exists()} for path in governance_required]
    community_checks = [{"path": path, "ok": (ROOT / path).exists()} for path in community_required]

    readme_text = read_text("README.md")
    release_text = read_text("RELEASE.md")
    paths_text = read_text("docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md")

    xt_gate_index = load_json("x-terminal/.axcoder/reports/xt-report-index.json")
    xt_rollback_verify = load_json("x-terminal/.axcoder/reports/xt-rollback-verify.json")
    secrets_dry_run = load_json("x-terminal/.axcoder/reports/secrets-dry-run-report.json")
    xt_ready_mode, xt_ready_report_ref, xt_ready_source_ref, connector_snapshot_ref = resolve_preferred_xt_ready_artifacts()
    xt_ready_report = load_json(xt_ready_report_ref)
    xt_ready_source = load_json(xt_ready_source_ref)
    connector_snapshot = load_json(connector_snapshot_ref)
    boundary_readiness = load_json("build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json")
    release_ready_decision = load_json("build/reports/xt_w3_release_ready_decision.v1.json")
    provenance = load_json("build/reports/xt_w3_require_real_provenance.v2.json")
    competitive_rollback = load_json("build/reports/xt_w3_25_competitive_rollback.v1.json")
    global_pass_lines = load_json("build/hub_l5_release_internal_pass_lines_report.json")
    doctor_source_gate_ref = "build/reports/xhub_doctor_source_gate_summary.v1.json"
    doctor_source_gate = load_json_if_exists(doctor_source_gate_ref)
    operator_recovery_ref = "build/reports/xhub_local_service_operator_recovery_report.v1.json"
    operator_recovery_report = load_json_if_exists(operator_recovery_ref)
    operator_channel_recovery_ref = "build/reports/xhub_operator_channel_recovery_report.v1.json"
    operator_channel_recovery_report = load_json_if_exists(operator_channel_recovery_ref)
    doctor_project_context_support = doctor_source_gate.get("project_context_summary_support", {}) if doctor_source_gate else {}
    doctor_project_memory_policy_support = doctor_source_gate.get("project_memory_policy_support", {}) if doctor_source_gate else {}
    doctor_project_memory_assembly_resolution_support = doctor_source_gate.get("project_memory_assembly_resolution_support", {}) if doctor_source_gate else {}
    doctor_project_remote_snapshot_cache_support = doctor_source_gate.get("project_remote_snapshot_cache_support", {}) if doctor_source_gate else {}
    doctor_heartbeat_governance_support = doctor_source_gate.get("heartbeat_governance_support", {}) if doctor_source_gate else {}
    doctor_supervisor_memory_policy_support = doctor_source_gate.get("supervisor_memory_policy_support", {}) if doctor_source_gate else {}
    doctor_supervisor_memory_assembly_resolution_support = doctor_source_gate.get("supervisor_memory_assembly_resolution_support", {}) if doctor_source_gate else {}
    doctor_supervisor_remote_snapshot_cache_support = doctor_source_gate.get("supervisor_remote_snapshot_cache_support", {}) if doctor_source_gate else {}
    doctor_durable_candidate_mirror_support = doctor_source_gate.get("durable_candidate_mirror_support", {}) if doctor_source_gate else {}
    doctor_local_store_write_support = doctor_source_gate.get("local_store_write_support", {}) if doctor_source_gate else {}
    doctor_xt_pairing_readiness_support = doctor_source_gate.get("xt_pairing_readiness_support", {}) if doctor_source_gate else {}
    doctor_memory_route_support = doctor_source_gate.get("memory_route_truth_support", {}) if doctor_source_gate else {}
    doctor_memory_truth_closure_support = doctor_source_gate.get("xt_memory_truth_closure_support", {}) if doctor_source_gate else {}
    doctor_build_snapshot_inventory_support = doctor_source_gate.get("build_snapshot_inventory_support", {}) if doctor_source_gate else {}
    doctor_xt_smoke_evidence_ref = (
        doctor_project_context_support.get("xt_source_smoke_evidence_ref")
        or doctor_project_memory_policy_support.get("xt_source_smoke_evidence_ref")
        or doctor_project_memory_assembly_resolution_support.get("xt_source_smoke_evidence_ref")
        or doctor_project_remote_snapshot_cache_support.get("xt_source_smoke_evidence_ref")
        or doctor_heartbeat_governance_support.get("xt_source_smoke_evidence_ref")
        or doctor_supervisor_memory_policy_support.get("xt_source_smoke_evidence_ref")
        or doctor_supervisor_memory_assembly_resolution_support.get("xt_source_smoke_evidence_ref")
        or doctor_supervisor_remote_snapshot_cache_support.get("xt_source_smoke_evidence_ref")
        or doctor_xt_pairing_readiness_support.get("xt_source_smoke_evidence_ref")
    )
    doctor_all_smoke_evidence_ref = (
        doctor_project_context_support.get("all_source_smoke_evidence_ref")
        or doctor_project_memory_policy_support.get("all_source_smoke_evidence_ref")
        or doctor_project_memory_assembly_resolution_support.get("all_source_smoke_evidence_ref")
        or doctor_project_remote_snapshot_cache_support.get("all_source_smoke_evidence_ref")
        or doctor_heartbeat_governance_support.get("all_source_smoke_evidence_ref")
        or doctor_supervisor_memory_policy_support.get("all_source_smoke_evidence_ref")
        or doctor_supervisor_memory_assembly_resolution_support.get("all_source_smoke_evidence_ref")
        or doctor_supervisor_remote_snapshot_cache_support.get("all_source_smoke_evidence_ref")
        or doctor_xt_pairing_readiness_support.get("all_source_smoke_evidence_ref")
    )
    doctor_xt_memory_truth_closure_evidence_ref = doctor_memory_truth_closure_support.get("xt_memory_truth_closure_smoke_evidence_ref")
    doctor_build_snapshot_inventory_report_ref = doctor_build_snapshot_inventory_support.get("report_ref")

    doctor_source_gate_steps = {}
    if doctor_source_gate is not None:
        doctor_source_gate_steps = {
            step.get("step_id"): step
            for step in doctor_source_gate.get("steps", [])
            if isinstance(step, dict) and step.get("step_id")
        }
    doctor_source_gate_support = {
        "report_ref": doctor_source_gate_ref,
        "present": doctor_source_gate is not None,
        "schema_version": doctor_source_gate.get("schema_version") if doctor_source_gate else None,
        "overall_status": doctor_source_gate.get("overall_status") if doctor_source_gate else "not_present",
        "summary": doctor_source_gate.get("summary") if doctor_source_gate else None,
        "wrapper_dispatch_status": doctor_source_gate_steps.get("wrapper_dispatch_tests", {}).get("status"),
        "xt_source_smoke_status": doctor_source_gate_steps.get("xt_source_smoke", {}).get("status"),
        "aggregate_source_smoke_status": doctor_source_gate_steps.get("all_source_smoke", {}).get("status"),
        "aggregate_source_smoke_tmp_root": doctor_source_gate_steps.get("all_source_smoke", {}).get("smoke_tmp_root"),
        "build_snapshot_inventory_generation_status": doctor_source_gate_steps.get("build_snapshot_inventory_report", {}).get("status"),
        "project_context_summary_support": (
            {
                "xt_source_smoke_status": doctor_source_gate.get("project_context_summary_support", {}).get("xt_source_smoke_status"),
                "all_source_smoke_status": doctor_source_gate.get("project_context_summary_support", {}).get("all_source_smoke_status"),
                "xt_source_project_context_summary": compact_project_context_summary(
                    doctor_source_gate.get("project_context_summary_support", {}).get("xt_source_project_context_summary")
                ),
                "all_source_project_context_summary": compact_project_context_summary(
                    doctor_source_gate.get("project_context_summary_support", {}).get("all_source_project_context_summary")
                ),
                "xt_source_smoke_evidence_ref": doctor_source_gate.get("project_context_summary_support", {}).get("xt_source_smoke_evidence_ref"),
                "all_source_smoke_evidence_ref": doctor_source_gate.get("project_context_summary_support", {}).get("all_source_smoke_evidence_ref"),
            }
            if doctor_source_gate is not None and doctor_source_gate.get("project_context_summary_support")
            else None
        ),
        "project_memory_policy_support": (
            {
                "xt_source_smoke_status": doctor_project_memory_policy_support.get("xt_source_smoke_status"),
                "all_source_smoke_status": doctor_project_memory_policy_support.get("all_source_smoke_status"),
                "xt_source_project_memory_policy": compact_project_memory_policy(
                    doctor_project_memory_policy_support.get("xt_source_project_memory_policy")
                ),
                "all_source_project_memory_policy": compact_project_memory_policy(
                    doctor_project_memory_policy_support.get("all_source_project_memory_policy")
                ),
                "xt_source_smoke_evidence_ref": doctor_project_memory_policy_support.get("xt_source_smoke_evidence_ref"),
                "all_source_smoke_evidence_ref": doctor_project_memory_policy_support.get("all_source_smoke_evidence_ref"),
            }
            if doctor_source_gate is not None and doctor_project_memory_policy_support
            else None
        ),
        "project_memory_assembly_resolution_support": (
            {
                "xt_source_smoke_status": doctor_project_memory_assembly_resolution_support.get("xt_source_smoke_status"),
                "all_source_smoke_status": doctor_project_memory_assembly_resolution_support.get("all_source_smoke_status"),
                "xt_source_project_memory_assembly_resolution": compact_memory_assembly_resolution(
                    doctor_project_memory_assembly_resolution_support.get("xt_source_project_memory_assembly_resolution")
                ),
                "all_source_project_memory_assembly_resolution": compact_memory_assembly_resolution(
                    doctor_project_memory_assembly_resolution_support.get("all_source_project_memory_assembly_resolution")
                ),
                "xt_source_smoke_evidence_ref": doctor_project_memory_assembly_resolution_support.get("xt_source_smoke_evidence_ref"),
                "all_source_smoke_evidence_ref": doctor_project_memory_assembly_resolution_support.get("all_source_smoke_evidence_ref"),
            }
            if doctor_source_gate is not None and doctor_project_memory_assembly_resolution_support
            else None
        ),
        "project_remote_snapshot_cache_support": (
            {
                "xt_source_smoke_status": doctor_project_remote_snapshot_cache_support.get("xt_source_smoke_status"),
                "all_source_smoke_status": doctor_project_remote_snapshot_cache_support.get("all_source_smoke_status"),
                "xt_source_project_remote_snapshot_cache_snapshot": compact_remote_snapshot_cache_snapshot(
                    doctor_project_remote_snapshot_cache_support.get("xt_source_project_remote_snapshot_cache_snapshot")
                ),
                "all_source_project_remote_snapshot_cache_snapshot": compact_remote_snapshot_cache_snapshot(
                    doctor_project_remote_snapshot_cache_support.get("all_source_project_remote_snapshot_cache_snapshot")
                ),
                "xt_source_smoke_evidence_ref": doctor_project_remote_snapshot_cache_support.get("xt_source_smoke_evidence_ref"),
                "all_source_smoke_evidence_ref": doctor_project_remote_snapshot_cache_support.get("all_source_smoke_evidence_ref"),
            }
            if doctor_source_gate is not None and doctor_project_remote_snapshot_cache_support
            else None
        ),
        "heartbeat_governance_support": (
            {
                "xt_source_smoke_status": doctor_heartbeat_governance_support.get("xt_source_smoke_status"),
                "all_source_smoke_status": doctor_heartbeat_governance_support.get("all_source_smoke_status"),
                "xt_source_heartbeat_governance_snapshot": compact_heartbeat_governance_snapshot(
                    doctor_heartbeat_governance_support.get("xt_source_heartbeat_governance_snapshot")
                ),
                "all_source_heartbeat_governance_snapshot": compact_heartbeat_governance_snapshot(
                    doctor_heartbeat_governance_support.get("all_source_heartbeat_governance_snapshot")
                ),
                "xt_source_smoke_evidence_ref": doctor_heartbeat_governance_support.get("xt_source_smoke_evidence_ref"),
                "all_source_smoke_evidence_ref": doctor_heartbeat_governance_support.get("all_source_smoke_evidence_ref"),
            }
            if doctor_source_gate is not None and doctor_heartbeat_governance_support
            else None
        ),
        "supervisor_memory_policy_support": (
            {
                "xt_source_smoke_status": doctor_supervisor_memory_policy_support.get("xt_source_smoke_status"),
                "all_source_smoke_status": doctor_supervisor_memory_policy_support.get("all_source_smoke_status"),
                "xt_source_supervisor_memory_policy": compact_supervisor_memory_policy(
                    doctor_supervisor_memory_policy_support.get("xt_source_supervisor_memory_policy")
                ),
                "all_source_supervisor_memory_policy": compact_supervisor_memory_policy(
                    doctor_supervisor_memory_policy_support.get("all_source_supervisor_memory_policy")
                ),
                "xt_source_smoke_evidence_ref": doctor_supervisor_memory_policy_support.get("xt_source_smoke_evidence_ref"),
                "all_source_smoke_evidence_ref": doctor_supervisor_memory_policy_support.get("all_source_smoke_evidence_ref"),
            }
            if doctor_source_gate is not None and doctor_supervisor_memory_policy_support
            else None
        ),
        "supervisor_memory_assembly_resolution_support": (
            {
                "xt_source_smoke_status": doctor_supervisor_memory_assembly_resolution_support.get("xt_source_smoke_status"),
                "all_source_smoke_status": doctor_supervisor_memory_assembly_resolution_support.get("all_source_smoke_status"),
                "xt_source_supervisor_memory_assembly_resolution": compact_memory_assembly_resolution(
                    doctor_supervisor_memory_assembly_resolution_support.get("xt_source_supervisor_memory_assembly_resolution")
                ),
                "all_source_supervisor_memory_assembly_resolution": compact_memory_assembly_resolution(
                    doctor_supervisor_memory_assembly_resolution_support.get("all_source_supervisor_memory_assembly_resolution")
                ),
                "xt_source_smoke_evidence_ref": doctor_supervisor_memory_assembly_resolution_support.get("xt_source_smoke_evidence_ref"),
                "all_source_smoke_evidence_ref": doctor_supervisor_memory_assembly_resolution_support.get("all_source_smoke_evidence_ref"),
            }
            if doctor_source_gate is not None and doctor_supervisor_memory_assembly_resolution_support
            else None
        ),
        "supervisor_remote_snapshot_cache_support": (
            {
                "xt_source_smoke_status": doctor_supervisor_remote_snapshot_cache_support.get("xt_source_smoke_status"),
                "all_source_smoke_status": doctor_supervisor_remote_snapshot_cache_support.get("all_source_smoke_status"),
                "xt_source_supervisor_remote_snapshot_cache_snapshot": compact_remote_snapshot_cache_snapshot(
                    doctor_supervisor_remote_snapshot_cache_support.get("xt_source_supervisor_remote_snapshot_cache_snapshot")
                ),
                "all_source_supervisor_remote_snapshot_cache_snapshot": compact_remote_snapshot_cache_snapshot(
                    doctor_supervisor_remote_snapshot_cache_support.get("all_source_supervisor_remote_snapshot_cache_snapshot")
                ),
                "xt_source_smoke_evidence_ref": doctor_supervisor_remote_snapshot_cache_support.get("xt_source_smoke_evidence_ref"),
                "all_source_smoke_evidence_ref": doctor_supervisor_remote_snapshot_cache_support.get("all_source_smoke_evidence_ref"),
            }
            if doctor_source_gate is not None and doctor_supervisor_remote_snapshot_cache_support
            else None
        ),
        "durable_candidate_mirror_support": (
            {
                "xt_source_smoke_status": doctor_durable_candidate_mirror_support.get("xt_source_smoke_status"),
                "all_source_smoke_status": doctor_durable_candidate_mirror_support.get("all_source_smoke_status"),
                "xt_source_durable_candidate_mirror_snapshot": compact_durable_candidate_mirror_snapshot(
                    doctor_durable_candidate_mirror_support.get("xt_source_durable_candidate_mirror_snapshot")
                ),
                "all_source_durable_candidate_mirror_snapshot": compact_durable_candidate_mirror_snapshot(
                    doctor_durable_candidate_mirror_support.get("all_source_durable_candidate_mirror_snapshot")
                ),
                "xt_source_smoke_evidence_ref": doctor_durable_candidate_mirror_support.get("xt_source_smoke_evidence_ref"),
                "all_source_smoke_evidence_ref": doctor_durable_candidate_mirror_support.get("all_source_smoke_evidence_ref"),
            }
            if doctor_source_gate is not None and doctor_durable_candidate_mirror_support
            else None
        ),
        "local_store_write_support": (
            {
                "xt_source_smoke_status": doctor_local_store_write_support.get("xt_source_smoke_status"),
                "all_source_smoke_status": doctor_local_store_write_support.get("all_source_smoke_status"),
                "xt_source_local_store_write_snapshot": compact_local_store_write_snapshot(
                    doctor_local_store_write_support.get("xt_source_local_store_write_snapshot")
                ),
                "all_source_local_store_write_snapshot": compact_local_store_write_snapshot(
                    doctor_local_store_write_support.get("all_source_local_store_write_snapshot")
                ),
                "xt_source_smoke_evidence_ref": doctor_local_store_write_support.get("xt_source_smoke_evidence_ref"),
                "all_source_smoke_evidence_ref": doctor_local_store_write_support.get("all_source_smoke_evidence_ref"),
            }
            if doctor_source_gate is not None and doctor_local_store_write_support
            else None
        ),
        "xt_pairing_readiness_support": (
            compact_xt_pairing_readiness_support(doctor_xt_pairing_readiness_support)
            if doctor_source_gate is not None and doctor_xt_pairing_readiness_support
            else None
        ),
        "memory_route_truth_support": (
            {
                "xt_source_smoke_status": doctor_memory_route_support.get("xt_source_smoke_status"),
                "all_source_smoke_status": doctor_memory_route_support.get("all_source_smoke_status"),
                "xt_source_memory_route_truth_snapshot": compact_memory_route_truth_snapshot(
                    doctor_memory_route_support.get("xt_source_memory_route_truth_snapshot")
                ),
                "all_source_memory_route_truth_snapshot": compact_memory_route_truth_snapshot(
                    doctor_memory_route_support.get("all_source_memory_route_truth_snapshot")
                ),
                "xt_source_smoke_evidence_ref": doctor_memory_route_support.get("xt_source_smoke_evidence_ref"),
                "all_source_smoke_evidence_ref": doctor_memory_route_support.get("all_source_smoke_evidence_ref"),
            }
            if doctor_source_gate is not None and doctor_memory_route_support
            else None
        ),
        "xt_memory_truth_closure_support": (
            {
                "xt_memory_truth_closure_smoke_status": doctor_memory_truth_closure_support.get("xt_memory_truth_closure_smoke_status"),
                "xt_memory_truth_closure_snapshot": compact_memory_truth_closure_snapshot(
                    doctor_memory_truth_closure_support.get("xt_memory_truth_closure_snapshot")
                ),
                "xt_memory_truth_closure_smoke_evidence_ref": doctor_memory_truth_closure_support.get(
                    "xt_memory_truth_closure_smoke_evidence_ref"
                ),
            }
            if doctor_source_gate is not None and doctor_memory_truth_closure_support
            else None
        ),
        "build_snapshot_inventory_support": (
            compact_build_snapshot_inventory_support(
                {
                    **doctor_build_snapshot_inventory_support,
                    "build_snapshot_inventory_generation_status": doctor_source_gate_steps.get("build_snapshot_inventory_report", {}).get("status"),
                }
            )
            if doctor_source_gate is not None and (
                doctor_build_snapshot_inventory_support
                or doctor_source_gate_steps.get("build_snapshot_inventory_report", {}).get("status")
            )
            else None
        ),
        "status": (
            "pass(source_run_wrapper_xt_and_aggregate_smoke_green)"
            if doctor_source_gate and doctor_source_gate.get("overall_status") == "pass"
            else (
                "warn(source_run_wrapper_xt_or_aggregate_smoke_failed)"
                if doctor_source_gate
                else "not_present(optional_supporting_evidence)"
            )
        ),
    }

    high_risk_findings: list[dict] = []
    keyword_hits: list[dict] = []
    for rel_path in public_files:
        text = safe_text(ROOT / rel_path)
        if text is None:
            continue
        example_or_test_path = is_example_or_test_path(rel_path)
        for pattern in HIGH_RISK_CONTENT_PATTERNS:
            match = pattern.search(text)
            if not match:
                continue
            excerpt = match.group(0)[:120]
            if example_or_test_path and pattern.pattern != r"-----BEGIN (?:RSA|EC|OPENSSH|PRIVATE) PRIVATE KEY-----":
                continue
            if is_placeholder_excerpt(excerpt):
                continue
            high_risk_findings.append({
                "path": rel_path,
                "pattern": pattern.pattern,
                "match_excerpt": excerpt,
            })
        if len(keyword_hits) < 50:
            keyword_count = sum(1 for pattern in KEYWORD_SCAN_PATTERNS if pattern.search(text))
            if keyword_count:
                keyword_hits.append({"path": rel_path, "keyword_pattern_count": keyword_count})

    public_manifest = {
        "schema_version": "xhub.oss_public_manifest.v1",
        "generated_at": iso_now(),
        "scope": "XT-W3-23 -> XT-W3-24 -> XT-W3-25 mainline only",
        "release_profile": "minimal-runnable-package",
        "allowlist_policy_ref": "docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md",
        "allowlist_dirs": ALLOWLIST_DIRS,
        "allowlist_files": ALLOWLIST_FILES,
        "public_file_count": len(public_files),
        "manifest_sha256": sha256_lines(public_files),
        "excluded_blacklist_hit_count": len(excluded_blacklist_hits),
        "excluded_blacklist_hits": excluded_blacklist_hits,
        "excluded_non_allowlist_count": len(excluded_allowlist_misses),
        "excluded_non_allowlist_sample": excluded_allowlist_misses[:100],
        "public_files": public_files,
    }

    external_scope = boundary_readiness["scope_boundary"]

    scrub_report = {
        "schema_version": "xhub.oss_secret_scrub_report.v1",
        "generated_at": iso_now(),
        "scope": public_manifest["scope"],
        "public_manifest_ref": "build/reports/oss_public_manifest_v1.json",
        "scan_profile": "allowlisted_public_files_only",
        "scan_file_count": len(public_files),
        "high_risk_secret_findings": len(high_risk_findings),
        "build_artifacts_committed": sum(1 for path in public_files if path.startswith("build/")),
        "runtime_artifacts_committed": sum(1 for path in public_files if path.startswith("data/")),
        "blocking_count": len(high_risk_findings),
        "high_risk_findings": high_risk_findings,
        "keyword_hit_sample": keyword_hits,
        "dry_run_cross_check": {
            "secrets_dry_run_report_ref": "x-terminal/.axcoder/reports/secrets-dry-run-report.json",
            "blocking_count": int(secrets_dry_run.get("blocking_count", 0)),
            "missing_variables_count": int(secrets_dry_run.get("missing_variables_count", 0)),
            "permission_boundary_error_count": int(secrets_dry_run.get("permission_boundary_error_count", 0)),
        },
        "truth_source_boundary": {
            "boundary_report_ref": "build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json",
            "release_scope_ref": "build/reports/xt_w3_release_ready_decision.v1.json",
            "require_real_ref": "build/reports/xt_w3_require_real_provenance.v2.json",
            "boundary_ready": str(boundary_readiness.get("status", "")).startswith("delivered("),
            "release_ready": release_ready_decision.get("release_ready") is True,
            "require_real_pass": provenance.get("summary", {}).get("unified_release_ready_provenance_pass") is True,
            "doctor_source_gate": doctor_source_gate_support,
            "xhub_local_service_operator_recovery": (
                {
                    "report_ref": operator_recovery_ref,
                    "present": True,
                    **compact_operator_recovery_support(operator_recovery_report),
                    "status": (
                        "pass(structured_local_service_recovery_truth_available_for_release_decision)"
                        if str(operator_recovery_report.get("gate_verdict", "")).startswith("PASS(")
                        else "warn(structured_local_service_recovery_truth_fail_closed)"
                    ),
                }
                if operator_recovery_report is not None
                else {
                    "report_ref": operator_recovery_ref,
                    "present": False,
                    "status": "not_present(optional_supporting_evidence)",
                }
            ),
            "xhub_operator_channel_recovery": (
                {
                    "report_ref": operator_channel_recovery_ref,
                    "present": True,
                    **compact_operator_channel_recovery_support(operator_channel_recovery_report),
                    "status": (
                        "pass(structured_operator_channel_recovery_truth_available_for_supporting_release_context)"
                        if str(operator_channel_recovery_report.get("gate_verdict", "")).startswith("PASS(")
                        else "warn(structured_operator_channel_recovery_truth_fail_closed)"
                    ),
                }
                if operator_channel_recovery_report is not None
                else {
                    "report_ref": operator_channel_recovery_ref,
                    "present": False,
                    "status": "not_present(optional_supporting_evidence)",
                }
            ),
            "allowed_external_claims": external_scope.get("external_claims_limited_to", []),
        },
        "evidence_refs": [
            "build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json",
            "build/reports/xt_w3_release_ready_decision.v1.json",
            "build/reports/xt_w3_require_real_provenance.v2.json",
            *([doctor_source_gate_ref] if doctor_source_gate is not None else []),
            *([operator_recovery_ref] if operator_recovery_report is not None else []),
            *([operator_channel_recovery_ref] if operator_channel_recovery_report is not None else []),
            *([doctor_xt_smoke_evidence_ref] if doctor_xt_smoke_evidence_ref else []),
            *([doctor_all_smoke_evidence_ref] if doctor_all_smoke_evidence_ref else []),
            *([doctor_xt_memory_truth_closure_evidence_ref] if doctor_xt_memory_truth_closure_evidence_ref else []),
            *([doctor_build_snapshot_inventory_report_ref] if doctor_build_snapshot_inventory_report_ref else []),
            "x-terminal/.axcoder/reports/secrets-dry-run-report.json",
            "docs/open-source/OSS_RELEASE_CHECKLIST_v1.md",
            "docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md",
        ],
        "pass": len(high_risk_findings) == 0,
    }
    hard_lines = [
        "validated_mainline_only",
        "no_scope_expansion",
        "no_unverified_claims",
        "allowlist_first_fail_closed",
        "exclude_build_data_axcoder_sqlite_logs_keys",
        "rollback_must_remain_executable",
    ]

    gates = {
        "OSS-G0": "PASS" if all(item["ok"] for item in governance_checks) else "FAIL",
        "OSS-G1": "PASS" if scrub_report["pass"] and scrub_report["build_artifacts_committed"] == 0 and scrub_report["runtime_artifacts_committed"] == 0 else "FAIL",
        "OSS-G2": "PASS" if ("## Quick Start" in readme_text and "bash x-terminal/scripts/ci/xt_release_gate.sh" in readme_text and xt_gate_index.get("release_decision") == "GO") else "FAIL",
        "OSS-G3": "PASS" if (xt_ready_report.get("ok") is True and xt_ready_report.get("require_real_audit_source") is True and xt_ready_source.get("selected_source") != "sample_fixture" and connector_snapshot.get("source_used") == "audit" and connector_snapshot.get("snapshot", {}).get("pass") is True and provenance.get("summary", {}).get("release_stance") == "release_ready") else "FAIL",
        "OSS-G4": "PASS" if (all(item["ok"] for item in community_checks) and all(item["ok"] for item in governance_checks)) else "FAIL",
        "OSS-G5": "PASS" if ("## 6) Rollback" in release_text and xt_rollback_verify.get("status") == "pass" and competitive_rollback.get("rollback_ready") is True and global_pass_lines.get("release_decision") == "GO") else "FAIL",
    }

    missing_evidence: list[str] = []
    if gates["OSS-G0"] != "PASS":
        missing_evidence.append("governance_or_legal_file_missing")
    if gates["OSS-G1"] != "PASS":
        missing_evidence.append("secret_scrub_not_clean")
    if gates["OSS-G2"] != "PASS":
        missing_evidence.append("quick_start_or_smoke_repro_not_proven")
    if gates["OSS-G3"] != "PASS":
        missing_evidence.append("security_baseline_not_release_green")
    if gates["OSS-G4"] != "PASS":
        missing_evidence.append("community_readiness_missing")
    if gates["OSS-G5"] != "PASS":
        missing_evidence.append("rollback_or_release_runbook_missing")

    release_stance = "GO" if not missing_evidence else "NO-GO"
    status = "delivered(oss_minimal_runnable_package_go)" if release_stance == "GO" else "blocked(oss_minimal_runnable_package_gap)"

    readiness = {
        "schema_version": "xhub.oss_release_readiness_v1",
        "generated_at": iso_now(),
        "scope": public_manifest["scope"],
        "release_profile": "minimal-runnable-package",
        "status": status,
        "release_stance": release_stance,
        "tag_strategy": "v0.1.0-alpha",
        "scope_boundary": {
            "validated_mainline_only": bool(external_scope.get("validated_mainline_only")),
            "mainline_chain": external_scope.get("mainline_chain", []),
            "no_scope_expansion": bool(external_scope.get("no_scope_expansion")),
            "no_unverified_claims": bool(external_scope.get("no_unverified_claims")),
            "external_claims_limited_to": external_scope.get("external_claims_limited_to", []),
        },
        "gates": gates,
        "checks": {
            "legal": {
                "governance_checks": governance_checks,
                "license_present": (ROOT / "LICENSE").exists(),
                "notice_present": (ROOT / "NOTICE.md").exists(),
            },
            "secret_scrub": {
                "report_ref": "build/reports/oss_secret_scrub_report.v1.json",
                "high_risk_secret_findings": scrub_report["high_risk_secret_findings"],
                "build_artifacts_committed": scrub_report["build_artifacts_committed"],
                "runtime_artifacts_committed": scrub_report["runtime_artifacts_committed"],
                "excluded_blacklist_hit_count": public_manifest["excluded_blacklist_hit_count"],
            },
            "reproducibility": {
                "readme_quick_start_present": "## Quick Start" in readme_text,
                "smoke_command": "bash x-terminal/scripts/ci/xt_release_gate.sh",
                "smoke_report_index_ref": "x-terminal/.axcoder/reports/xt-report-index.json",
                "smoke_release_decision": xt_gate_index.get("release_decision"),
                "smoke_generated_at": xt_gate_index.get("generated_at"),
                "doctor_source_gate": doctor_source_gate_support,
            },
            "security_baseline": {
                "xt_ready_evidence_mode": xt_ready_mode,
                "xt_ready_ref": xt_ready_report_ref,
                "xt_ready_ok": xt_ready_report.get("ok") is True,
                "require_real_audit_source": xt_ready_report.get("require_real_audit_source") is True,
                "xt_ready_evidence_source_ref": xt_ready_source_ref,
                "selected_audit_source": xt_ready_source.get("selected_source"),
                "connector_snapshot_ref": connector_snapshot_ref,
                "connector_source_used": connector_snapshot.get("source_used"),
                "connector_snapshot_pass": connector_snapshot.get("snapshot", {}).get("pass") is True,
                "global_internal_pass_lines": global_pass_lines.get("release_decision"),
            },
            "community_readiness": {
                "community_checks": community_checks,
                "changelog_present": (ROOT / "CHANGELOG.md").exists(),
                "codeowners_present": (ROOT / "CODEOWNERS").exists(),
            },
            "rollback": {
                "release_doc_has_rollback": "## 6) Rollback" in release_text,
                "xt_rollback_verify_ref": "x-terminal/.axcoder/reports/xt-rollback-verify.json",
                "xt_rollback_verify_status": xt_rollback_verify.get("status"),
                "competitive_rollback_ref": "build/reports/xt_w3_25_competitive_rollback.v1.json",
                "competitive_rollback_ready": competitive_rollback.get("rollback_ready") is True,
            },
            "external_messaging_scope": {
                "boundary_ref": "build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json",
                "validated_mainline_only": bool(external_scope.get("validated_mainline_only")),
                "no_scope_expansion": bool(external_scope.get("no_scope_expansion")),
                "no_unverified_claims": bool(external_scope.get("no_unverified_claims")),
                "allowed_claims": external_scope.get("external_claims_limited_to", []),
            },
            "local_service_recovery_support": (
                {
                    "report_ref": operator_recovery_ref,
                    "present": True,
                    **compact_operator_recovery_support(operator_recovery_report),
                    "status": (
                        "pass(structured_local_service_recovery_truth_available_for_release_decision)"
                        if str(operator_recovery_report.get("gate_verdict", "")).startswith("PASS(")
                        else "warn(structured_local_service_recovery_truth_fail_closed)"
                    ),
                }
                if operator_recovery_report is not None
                else {
                    "report_ref": operator_recovery_ref,
                    "present": False,
                    "status": "not_present(optional_supporting_evidence)",
                }
            ),
            "operator_channel_recovery_support": (
                {
                    "report_ref": operator_channel_recovery_ref,
                    "present": True,
                    **compact_operator_channel_recovery_support(operator_channel_recovery_report),
                    "status": (
                        "pass(structured_operator_channel_recovery_truth_available_for_supporting_release_context)"
                        if str(operator_channel_recovery_report.get("gate_verdict", "")).startswith("PASS(")
                        else "warn(structured_operator_channel_recovery_truth_fail_closed)"
                    ),
                }
                if operator_channel_recovery_report is not None
                else {
                    "report_ref": operator_channel_recovery_ref,
                    "present": False,
                    "status": "not_present(optional_supporting_evidence)",
                }
            ),
            "public_path_policy": {
                "allowlist_policy_ref": "docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md",
                "allowlist_first": "allowlist-first + fail-closed" in paths_text,
                "blacklist_effective": all(has_blacklist_component(path) for path in excluded_blacklist_hits),
                "public_file_count": len(public_files),
            },
        },
        "missing_evidence": missing_evidence,
        "hard_lines": hard_lines,
        "next_required_artifacts": [] if release_stance == "GO" else [
            "build/reports/oss_public_manifest_v1.json",
            "build/reports/oss_secret_scrub_report.v1.json",
            "build/reports/oss_release_readiness_v1.json",
        ],
        "rollback": {
            "rollback_ref": "build/reports/xt_w3_25_competitive_rollback.v1.json",
            "rollback_verify_ref": "x-terminal/.axcoder/reports/xt-rollback-verify.json",
            "release_runbook_ref": "RELEASE.md",
        },
        "evidence_refs": [
            "build/reports/oss_public_manifest_v1.json",
            "build/reports/oss_secret_scrub_report.v1.json",
            "build/reports/oss_release_readiness_v1.json",
            "build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json",
            "build/reports/xt_w3_release_ready_decision.v1.json",
            "build/reports/xt_w3_require_real_provenance.v2.json",
            xt_ready_report_ref,
            xt_ready_source_ref,
            connector_snapshot_ref,
            "build/hub_l5_release_internal_pass_lines_report.json",
            *([doctor_source_gate_ref] if doctor_source_gate is not None else []),
            *([operator_recovery_ref] if operator_recovery_report is not None else []),
            *([operator_channel_recovery_ref] if operator_channel_recovery_report is not None else []),
            *([doctor_xt_smoke_evidence_ref] if doctor_xt_smoke_evidence_ref else []),
            *([doctor_all_smoke_evidence_ref] if doctor_all_smoke_evidence_ref else []),
            *([doctor_xt_memory_truth_closure_evidence_ref] if doctor_xt_memory_truth_closure_evidence_ref else []),
            *([doctor_build_snapshot_inventory_report_ref] if doctor_build_snapshot_inventory_report_ref else []),
            "x-terminal/.axcoder/reports/xt-report-index.json",
            "x-terminal/.axcoder/reports/xt-rollback-verify.json",
            "x-terminal/.axcoder/reports/secrets-dry-run-report.json",
            "README.md",
            "RELEASE.md",
            "docs/open-source/OSS_RELEASE_CHECKLIST_v1.md",
            "docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md",
        ],
    }

    (REPORT_DIR / "oss_public_manifest_v1.json").write_text(json.dumps(public_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (REPORT_DIR / "oss_secret_scrub_report.v1.json").write_text(json.dumps(scrub_report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (REPORT_DIR / "oss_release_readiness_v1.json").write_text(json.dumps(readiness, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("wrote", REPORT_DIR / "oss_public_manifest_v1.json")
    print("wrote", REPORT_DIR / "oss_secret_scrub_report.v1.json")
    print("wrote", REPORT_DIR / "oss_release_readiness_v1.json")


if __name__ == "__main__":
    main()
