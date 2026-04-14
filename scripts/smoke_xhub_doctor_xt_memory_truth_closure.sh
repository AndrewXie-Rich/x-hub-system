#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="${XHUB_DOCTOR_XT_MEMORY_TRUTH_CLOSURE_REPORT_DIR:-${ROOT_DIR}/build/reports}"
TMP_BASE_DIR="${TMPDIR:-/tmp}"
TMP_ROOT="${XHUB_DOCTOR_XT_MEMORY_TRUTH_CLOSURE_TMP_ROOT:-}"
MIN_FREE_KB="${XHUB_DOCTOR_XT_MEMORY_TRUTH_CLOSURE_MIN_FREE_KB:-1048576}"
SMOKE_LABEL="xhub-doctor-xt-memory-truth-closure-smoke"

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
    echo "[$SMOKE_LABEL] hint=clean build/ or stale xhub_doctor_* temp roots, or lower XHUB_DOCTOR_XT_MEMORY_TRUTH_CLOSURE_MIN_FREE_KB for a local retry if you know the disk is safe" >&2
    exit 1
  fi
}

check_free_space_or_fail

if [ -z "$TMP_ROOT" ]; then
  TMP_ROOT="$(mktemp -d "${TMP_BASE_DIR%/}/xhub_doctor_xt_memory_truth_closure.XXXXXX")"
else
  mkdir -p "$TMP_ROOT"
fi

SNAPSHOT_DIR="$TMP_ROOT/repo_snapshot"
PACKAGE_ROOT="$SNAPSHOT_DIR/x-terminal"
CAPTURE_DIR="$TMP_ROOT/capture"
BUILD_LOG="$TMP_ROOT/swift-build.log"
TEST_LOG="$TMP_ROOT/swift-test.log"
EVIDENCE_CAPTURE_PATH="$CAPTURE_DIR/xt_doctor_memory_truth_closure_evidence.v1.json"
EVIDENCE_PATH="${XHUB_DOCTOR_XT_MEMORY_TRUTH_CLOSURE_EVIDENCE_PATH:-${REPORT_DIR}/xhub_doctor_xt_memory_truth_closure_smoke_evidence.v1.json}"

cleanup() {
  if [ "${XHUB_KEEP_SMOKE_TMP:-0}" = "1" ] || [ -n "${XHUB_DOCTOR_XT_MEMORY_TRUTH_CLOSURE_TMP_ROOT:-}" ]; then
    echo "[$SMOKE_LABEL] kept_tmp_root=$TMP_ROOT"
    return
  fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$REPORT_DIR" "$SNAPSHOT_DIR" "$CAPTURE_DIR"

rsync -a --delete \
  --exclude '.build' \
  --exclude '.axcoder' \
  --exclude '.ax-test-cache' \
  --exclude '.scratch' \
  --exclude '.sandbox_home' \
  --exclude '.sandbox_tmp' \
  --exclude '.clang-module-cache' \
  --exclude '.swift-module-cache' \
  --exclude 'DerivedData' \
  --exclude '__pycache__' \
  --exclude '.DS_Store' \
  "$ROOT_DIR/x-terminal/" "$PACKAGE_ROOT/"

mkdir -p \
  "$SNAPSHOT_DIR/.swift-home" \
  "$SNAPSHOT_DIR/.swift-tmp" \
  "$SNAPSHOT_DIR/.swift-scratch" \
  "$SNAPSHOT_DIR/.clang-module-cache"

if ! (
  cd "$PACKAGE_ROOT"
  HOME="$SNAPSHOT_DIR/.swift-home" \
  TMPDIR="$SNAPSHOT_DIR/.swift-tmp" \
  CLANG_MODULE_CACHE_PATH="$SNAPSHOT_DIR/.clang-module-cache" \
    swift build --disable-sandbox --build-tests --scratch-path "$SNAPSHOT_DIR/.swift-scratch"
) >"$BUILD_LOG" 2>&1; then
  echo "[$SMOKE_LABEL] swift_build_failed log=$BUILD_LOG" >&2
  tail -n 80 "$BUILD_LOG" >&2 || true
  exit 1
fi

if ! (
  cd "$PACKAGE_ROOT"
  XHUB_DOCTOR_XT_MEMORY_TRUTH_CLOSURE_CAPTURE_DIR="$CAPTURE_DIR" \
  HOME="$SNAPSHOT_DIR/.swift-home" \
  TMPDIR="$SNAPSHOT_DIR/.swift-tmp" \
  CLANG_MODULE_CACHE_PATH="$SNAPSHOT_DIR/.clang-module-cache" \
    swift test --disable-sandbox --skip-build --scratch-path "$SNAPSHOT_DIR/.swift-scratch" \
      --filter "XTDoctorMemoryTruthClosureEvidenceTests/memoryTruthAndCanonicalSyncClosureStayExplainableAcrossXTAndSupervisorSurfaces"
) >"$TEST_LOG" 2>&1; then
  echo "[$SMOKE_LABEL] swift_test_failed log=$TEST_LOG" >&2
  tail -n 120 "$TEST_LOG" >&2 || true
  exit 1
fi

python3 - "$EVIDENCE_CAPTURE_PATH" "$EVIDENCE_PATH" "$BUILD_LOG" "$TEST_LOG" "$PACKAGE_ROOT" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

capture_path, evidence_path, build_log, test_log, package_root = sys.argv[1:6]
capture_path = os.path.realpath(capture_path)
build_log = os.path.realpath(build_log)
test_log = os.path.realpath(test_log)
package_root = os.path.realpath(package_root)

with open(capture_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

assert payload["schemaVersion"] == "xt.doctor_memory_truth_closure_evidence.v1", payload["schemaVersion"]
assert payload["status"] == "pass", payload["status"]

truth_examples = payload.get("truthExamples") or []
project_context = payload.get("projectContext") or {}
supervisor_memory = payload.get("supervisorMemory") or {}
canonical_sync = payload.get("canonicalSyncClosure") or {}

assert len(truth_examples) >= 3, truth_examples
assert project_context["memorySource"] == "hub_memory_v1_grpc", project_context
assert project_context["memorySourceLabel"] == "Hub 快照 + 本地 overlay", project_context
assert project_context["writerGateBoundaryPresent"] is True, project_context
assert supervisor_memory["memorySource"] == "hub", supervisor_memory
assert "Hub 记忆（Hub durable truth）" in supervisor_memory["modeSourceText"], supervisor_memory
assert "Hub 记忆（Hub durable truth）" in supervisor_memory["continuityDetailLine"], supervisor_memory
assert canonical_sync["auditRef"] == "audit-project-alpha-incident-1", canonical_sync
assert canonical_sync["evidenceRef"] == "canonical_memory_item:item-project-alpha-incident-1", canonical_sync
assert canonical_sync["writebackRef"] == "canonical_memory_item:item-project-alpha-incident-1", canonical_sync
assert canonical_sync["strictIssueCode"] == "memory:memory_canonical_sync_delivery_failed", canonical_sync
assert "audit_ref=audit-project-1" in canonical_sync["doctorDetailLine"], canonical_sync
assert "evidence_ref=canonical_memory_item:item-project-1" in canonical_sync["doctorDetailLine"], canonical_sync
assert "writeback_ref=canonical_memory_item:item-project-1" in canonical_sync["doctorDetailLine"], canonical_sync
assert "audit_ref=audit-project-alpha-incident-1" in canonical_sync["xtReadyDetailLine"], canonical_sync
assert "evidence_ref=canonical_memory_item:item-project-alpha-incident-1" in canonical_sync["xtReadyDetailLine"], canonical_sync
assert "writeback_ref=canonical_memory_item:item-project-alpha-incident-1" in canonical_sync["xtReadyDetailLine"], canonical_sync

evidence = {
    "schema_version": "xhub.doctor_xt_memory_truth_closure_smoke_evidence.v1",
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "status": "pass",
    "smoke_kind": "xt_memory_truth_closure",
    "package_root": package_root,
    "build_log_path": build_log,
    "test_log_path": test_log,
    "raw_evidence_path": capture_path,
    "truth_examples": truth_examples,
    "project_context": project_context,
    "supervisor_memory": supervisor_memory,
    "canonical_sync_closure": canonical_sync,
    "assertions": {
        "project_context_memory_source": {
            "expected": "hub_memory_v1_grpc",
            "actual": project_context["memorySource"],
            "pass": project_context["memorySource"] == "hub_memory_v1_grpc",
        },
        "project_context_memory_source_label": {
            "expected": "Hub 快照 + 本地 overlay",
            "actual": project_context["memorySourceLabel"],
            "pass": project_context["memorySourceLabel"] == "Hub 快照 + 本地 overlay",
        },
        "writer_gate_boundary_present": {
            "expected": True,
            "actual": project_context["writerGateBoundaryPresent"],
            "pass": project_context["writerGateBoundaryPresent"] is True,
        },
        "supervisor_memory_source": {
            "expected": "hub",
            "actual": supervisor_memory["memorySource"],
            "pass": supervisor_memory["memorySource"] == "hub",
        },
        "supervisor_mode_source_truth": {
            "expected_substring": "Hub 记忆（Hub durable truth）",
            "actual": supervisor_memory["modeSourceText"],
            "pass": "Hub 记忆（Hub durable truth）" in supervisor_memory["modeSourceText"],
        },
        "canonical_sync_audit_ref": {
            "expected": "audit-project-alpha-incident-1",
            "actual": canonical_sync["auditRef"],
            "pass": canonical_sync["auditRef"] == "audit-project-alpha-incident-1",
        },
        "canonical_sync_evidence_ref": {
            "expected": "canonical_memory_item:item-project-alpha-incident-1",
            "actual": canonical_sync["evidenceRef"],
            "pass": canonical_sync["evidenceRef"] == "canonical_memory_item:item-project-alpha-incident-1",
        },
        "canonical_sync_writeback_ref": {
            "expected": "canonical_memory_item:item-project-alpha-incident-1",
            "actual": canonical_sync["writebackRef"],
            "pass": canonical_sync["writebackRef"] == "canonical_memory_item:item-project-alpha-incident-1",
        },
        "canonical_sync_strict_issue_code": {
            "expected": "memory:memory_canonical_sync_delivery_failed",
            "actual": canonical_sync["strictIssueCode"],
            "pass": canonical_sync["strictIssueCode"] == "memory:memory_canonical_sync_delivery_failed",
        },
    },
}

os.makedirs(os.path.dirname(evidence_path), exist_ok=True)
with open(evidence_path, "w", encoding="utf-8") as handle:
    json.dump(evidence, handle, indent=2, sort_keys=True)
    handle.write("\n")

print("[xhub-doctor-xt-memory-truth-closure-smoke] PASS")
print(f"[xhub-doctor-xt-memory-truth-closure-smoke] capture={capture_path}")
print(f"[xhub-doctor-xt-memory-truth-closure-smoke] evidence={os.path.realpath(evidence_path)}")
PY
