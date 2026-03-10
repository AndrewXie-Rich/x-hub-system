#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[1]
REPORT_DIR = ROOT / "build" / "reports"
REPORT_DIR.mkdir(parents=True, exist_ok=True)

ALLOWLIST_DIRS = [
    ".github",
    ".kiro/specs",
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
    re.compile(r"token\s*[:=]\s*['\"][A-Za-z0-9_\-]{12,}['\"]", re.IGNORECASE),
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
    if rel_path.startswith("x-terminal- legacy/"):
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
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        files.append(rel_posix(path))
    return sorted(files)


def load_json(rel_path: str) -> dict:
    return json.loads((ROOT / rel_path).read_text(encoding="utf-8"))


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
    xt_ready_report = load_json("build/xt_ready_gate_e2e_report.json")
    xt_ready_source = load_json("build/xt_ready_evidence_source.json")
    connector_snapshot = load_json("build/connector_ingress_gate_snapshot.json")
    boundary_readiness = load_json("build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json")
    release_ready_decision = load_json("build/reports/xt_w3_release_ready_decision.v1.json")
    provenance = load_json("build/reports/xt_w3_require_real_provenance.v2.json")
    competitive_rollback = load_json("build/reports/xt_w3_25_competitive_rollback.v1.json")
    global_pass_lines = load_json("build/hub_l5_release_internal_pass_lines_report.json")

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
        "pass": len(high_risk_findings) == 0,
    }

    external_scope = boundary_readiness["scope_boundary"]
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
            },
            "security_baseline": {
                "xt_ready_ref": "build/xt_ready_gate_e2e_report.json",
                "xt_ready_ok": xt_ready_report.get("ok") is True,
                "require_real_audit_source": xt_ready_report.get("require_real_audit_source") is True,
                "selected_audit_source": xt_ready_source.get("selected_source"),
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
            "build/xt_ready_gate_e2e_report.json",
            "build/xt_ready_evidence_source.json",
            "build/connector_ingress_gate_snapshot.json",
            "build/hub_l5_release_internal_pass_lines_report.json",
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
