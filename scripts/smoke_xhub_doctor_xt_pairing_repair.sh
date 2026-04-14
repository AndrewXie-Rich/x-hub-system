#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="${XHUB_DOCTOR_XT_PAIRING_REPAIR_REPORT_DIR:-${ROOT_DIR}/build/reports}"
TMP_BASE_DIR="${TMPDIR:-/tmp}"
TMP_ROOT="${XHUB_DOCTOR_XT_PAIRING_REPAIR_TMP_ROOT:-}"
MIN_FREE_KB="${XHUB_DOCTOR_XT_PAIRING_REPAIR_MIN_FREE_KB:-786432}"
SMOKE_LABEL="xhub-doctor-xt-pairing-repair-smoke"

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
    echo "[$SMOKE_LABEL] hint=clean build/ or stale xhub_doctor_* temp roots, or lower XHUB_DOCTOR_XT_PAIRING_REPAIR_MIN_FREE_KB for a local retry if you know the disk is safe" >&2
    exit 1
  fi
}

check_free_space_or_fail

if [ -z "$TMP_ROOT" ]; then
  TMP_ROOT="$(mktemp -d "${TMP_BASE_DIR%/}/xhub_doctor_xt_pairing_repair.XXXXXX")"
else
  mkdir -p "$TMP_ROOT"
fi

SNAPSHOT_DIR="$TMP_ROOT/repo_snapshot"
PACKAGE_ROOT="$SNAPSHOT_DIR/x-terminal"
CAPTURE_DIR="$TMP_ROOT/capture"
BUILD_LOG="$TMP_ROOT/swift-build.log"
TEST_LOG="$TMP_ROOT/swift-test.log"
EVIDENCE_CAPTURE_PATH="$CAPTURE_DIR/xt_doctor_pairing_repair_closure_evidence.v1.json"
EVIDENCE_PATH="${XHUB_DOCTOR_XT_PAIRING_REPAIR_EVIDENCE_PATH:-${REPORT_DIR}/xhub_doctor_xt_pairing_repair_smoke_evidence.v1.json}"

cleanup() {
  if [ "${XHUB_KEEP_SMOKE_TMP:-0}" = "1" ] || [ -n "${XHUB_DOCTOR_XT_PAIRING_REPAIR_TMP_ROOT:-}" ]; then
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
  XHUB_DOCTOR_XT_PAIRING_REPAIR_CAPTURE_DIR="$CAPTURE_DIR" \
  HOME="$SNAPSHOT_DIR/.swift-home" \
  TMPDIR="$SNAPSHOT_DIR/.swift-tmp" \
  CLANG_MODULE_CACHE_PATH="$SNAPSHOT_DIR/.clang-module-cache" \
    swift test --disable-sandbox --skip-build --scratch-path "$SNAPSHOT_DIR/.swift-scratch" \
      --filter "UITroubleshootingPathTests/pairingRepairClosuresStayAlignedAcrossGuideWizardSettingsAndDoctor"
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

assert payload["schema_version"] == "xt.doctor_pairing_repair_closure_evidence.v1", payload["schema_version"]
assert payload["status"] == "pass", payload["status"]
scenarios = payload.get("scenarios") or []
assert len(scenarios) >= 5, scenarios

scenario_by_code = {}
for scenario in scenarios:
    code = scenario.get("failure_code")
    assert isinstance(code, str) and code, scenario
    scenario_by_code[code] = scenario

expected = {
    "discovery_failed": {
        "mapped_issue": "hub_unreachable",
        "guide_destinations": ["xt_pair_hub", "hub_lan_grpc", "hub_diagnostics_recovery"],
        "wizard_primary_action_id": "connect_hub",
        "settings_primary_action_id": "connect_hub",
        "doctor_headline": "Hub 暂时不可达，但正式异网入口已配置",
        "doctor_next_step_contains": "防火墙",
    },
    "pairing_health_failed": {
        "mapped_issue": "pairing_repair_required",
        "guide_destinations": ["xt_pair_hub", "hub_pairing_device_trust", "hub_diagnostics_recovery"],
        "wizard_primary_action_id": "connect_hub",
        "settings_primary_action_id": "connect_hub",
        "doctor_headline": "现有配对档案已失效，需要清理并重配",
        "doctor_next_step_contains": "清除配对后重连",
    },
    "discover_failed_using_cached_profile": {
        "mapped_issue": "pairing_repair_required",
        "guide_destinations": ["xt_pair_hub", "hub_pairing_device_trust", "hub_diagnostics_recovery"],
        "wizard_primary_action_id": "connect_hub",
        "settings_primary_action_id": "connect_hub",
        "doctor_headline": "现有配对档案已失效，需要清理并重配",
        "doctor_next_step_contains": "清除配对后重连",
    },
    "hub_port_conflict": {
        "mapped_issue": "hub_port_conflict",
        "guide_destinations": ["xt_pair_hub", "hub_lan_grpc", "xt_diagnostics"],
        "wizard_primary_action_id": "connect_hub",
        "settings_primary_action_id": "connect_hub",
        "doctor_headline": "Hub 端口冲突，必须先修复网络端口",
        "doctor_next_step_contains": "空闲端口",
    },
    "bonjour_multiple_hubs_ambiguous": {
        "mapped_issue": "multiple_hubs_ambiguous",
        "guide_destinations": ["xt_pair_hub", "hub_lan_grpc", "xt_diagnostics"],
        "wizard_primary_action_id": "connect_hub",
        "settings_primary_action_id": "connect_hub",
        "doctor_headline": "发现到多台 Hub，必须先固定目标",
        "doctor_next_step_contains": "固定一台目标 Hub",
    },
}

assertions = {}
for failure_code, expectation in expected.items():
    scenario = scenario_by_code[failure_code]
    assertions[f"{failure_code}_mapped_issue"] = {
        "expected": expectation["mapped_issue"],
        "actual": scenario["mapped_issue"],
        "pass": scenario["mapped_issue"] == expectation["mapped_issue"],
    }
    assertions[f"{failure_code}_guide_destinations"] = {
        "expected": expectation["guide_destinations"],
        "actual": scenario["guide_destinations"],
        "pass": scenario["guide_destinations"] == expectation["guide_destinations"],
    }
    assertions[f"{failure_code}_wizard_primary_action_id"] = {
        "expected": expectation["wizard_primary_action_id"],
        "actual": scenario["wizard_primary_action_id"],
        "pass": scenario["wizard_primary_action_id"] == expectation["wizard_primary_action_id"],
    }
    assertions[f"{failure_code}_settings_primary_action_id"] = {
        "expected": expectation["settings_primary_action_id"],
        "actual": scenario["settings_primary_action_id"],
        "pass": scenario["settings_primary_action_id"] == expectation["settings_primary_action_id"],
    }
    assertions[f"{failure_code}_doctor_headline"] = {
        "expected": expectation["doctor_headline"],
        "actual": scenario["doctor_headline"],
        "pass": scenario["doctor_headline"] == expectation["doctor_headline"],
    }
    assertions[f"{failure_code}_doctor_next_step"] = {
        "expected_substring": expectation["doctor_next_step_contains"],
        "actual": scenario["doctor_next_step"],
        "pass": expectation["doctor_next_step_contains"] in scenario["doctor_next_step"],
    }

evidence = {
    "schema_version": "xhub.doctor_xt_pairing_repair_smoke_evidence.v1",
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "status": "pass",
    "smoke_kind": "xt_pairing_repair",
    "package_root": package_root,
    "build_log_path": build_log,
    "test_log_path": test_log,
    "raw_evidence_path": capture_path,
    "scenario_count": len(scenarios),
    "failure_codes": list(expected.keys()),
    "scenarios": scenarios,
    "assertions": assertions,
}

os.makedirs(os.path.dirname(evidence_path), exist_ok=True)
with open(evidence_path, "w", encoding="utf-8") as handle:
    json.dump(evidence, handle, indent=2, sort_keys=True)
    handle.write("\n")

print("[xhub-doctor-xt-pairing-repair-smoke] PASS")
print(f"[xhub-doctor-xt-pairing-repair-smoke] capture={capture_path}")
print(f"[xhub-doctor-xt-pairing-repair-smoke] evidence={os.path.realpath(evidence_path)}")
PY
