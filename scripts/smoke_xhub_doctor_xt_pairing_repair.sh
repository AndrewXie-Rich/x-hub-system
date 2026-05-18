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
TEST_LOG="$TMP_ROOT/swift-test-pairing-repair.log"
STALE_PROFILE_TEST_LOG="$TMP_ROOT/swift-test-stale-profile.log"
EVIDENCE_CAPTURE_PATH="$CAPTURE_DIR/xt_doctor_pairing_repair_closure_evidence.v1.json"
STALE_PROFILE_CAPTURE_PATH="$CAPTURE_DIR/xt_stale_profile_repair_capture.v1.json"
EVIDENCE_PATH="${XHUB_DOCTOR_XT_PAIRING_REPAIR_EVIDENCE_PATH:-${REPORT_DIR}/xhub_doctor_xt_pairing_repair_smoke_evidence.v1.json}"
STALE_PROFILE_EVIDENCE_PATH="${XHUB_DOCTOR_XT_STALE_PROFILE_REPAIR_EVIDENCE_PATH:-${REPORT_DIR}/xt_stale_profile_repair_evidence.v1.json}"

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

if ! (
  cd "$PACKAGE_ROOT"
  XHUB_DOCTOR_XT_STALE_PROFILE_REPAIR_CAPTURE_DIR="$CAPTURE_DIR" \
  HOME="$SNAPSHOT_DIR/.swift-home" \
  TMPDIR="$SNAPSHOT_DIR/.swift-tmp" \
  CLANG_MODULE_CACHE_PATH="$SNAPSHOT_DIR/.clang-module-cache" \
    swift test --disable-sandbox --skip-build --scratch-path "$SNAPSHOT_DIR/.swift-scratch" \
      --filter "XTStaleProfileRepairEvidenceTests/staleProfileRepairStaysFailClosedAcrossCoordinatorDoctorAndRouteTruth"
) >"$STALE_PROFILE_TEST_LOG" 2>&1; then
  echo "[$SMOKE_LABEL] swift_test_failed log=$STALE_PROFILE_TEST_LOG" >&2
  tail -n 120 "$STALE_PROFILE_TEST_LOG" >&2 || true
  exit 1
fi

python3 - "$EVIDENCE_CAPTURE_PATH" "$EVIDENCE_PATH" "$STALE_PROFILE_CAPTURE_PATH" "$STALE_PROFILE_EVIDENCE_PATH" "$BUILD_LOG" "$TEST_LOG" "$STALE_PROFILE_TEST_LOG" "$PACKAGE_ROOT" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

(
    capture_path,
    evidence_path,
    stale_capture_path,
    stale_evidence_path,
    build_log,
    test_log,
    stale_test_log,
    package_root,
) = sys.argv[1:9]
capture_path = os.path.realpath(capture_path)
stale_capture_path = os.path.realpath(stale_capture_path)
build_log = os.path.realpath(build_log)
test_log = os.path.realpath(test_log)
stale_test_log = os.path.realpath(stale_test_log)
package_root = os.path.realpath(package_root)

with open(capture_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

with open(stale_capture_path, "r", encoding="utf-8") as handle:
    stale_payload = json.load(handle)

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

assert stale_payload["schema_version"] == "xt.stale_profile_repair_capture.v1", stale_payload["schema_version"]
assert stale_payload["status"] == "pass", stale_payload["status"]
assert stale_payload["discovery_fail_closed_reason_codes"] == [
    "hub_instance_mismatch",
    "pairing_profile_epoch_stale",
    "route_pack_outdated",
], stale_payload["discovery_fail_closed_reason_codes"]
assert stale_payload["connect_refresh_skip_reason_codes"] == [
    "invite_token_required",
    "invite_token_invalid",
    "pairing_token_invalid",
    "bootstrap_token_invalid",
    "pairing_token_expired",
    "bootstrap_token_expired",
    "unauthenticated",
    "mtls_client_certificate_required",
    "certificate_required",
    "hub_instance_mismatch",
    "pairing_profile_epoch_stale",
    "route_pack_outdated",
], stale_payload["connect_refresh_skip_reason_codes"]

stale_cases = stale_payload.get("cases") or []
assert len(stale_cases) >= 6, stale_cases
stale_case_by_code = {}
for case in stale_cases:
    code = case.get("failure_code")
    assert isinstance(code, str) and code, case
    stale_case_by_code[code] = case

stale_expected = {
    "invite_token_invalid": {
        "probe_stage": "connect_failure",
        "probe_reason_code": "invite_token_invalid",
        "should_fail_closed_on_discovery": False,
        "should_skip_bootstrap_refresh_after_connect_failure": True,
        "probe_connect_attempted": True,
        "probe_bootstrap_attempted": False,
        "probe_log_contains_skip_refresh": True,
    },
    "unauthenticated": {
        "probe_stage": "connect_failure",
        "probe_reason_code": "unauthenticated",
        "should_fail_closed_on_discovery": False,
        "should_skip_bootstrap_refresh_after_connect_failure": True,
        "probe_connect_attempted": True,
        "probe_bootstrap_attempted": False,
        "probe_log_contains_skip_refresh": True,
    },
    "certificate_required": {
        "probe_stage": "connect_failure",
        "probe_reason_code": "certificate_required",
        "should_fail_closed_on_discovery": False,
        "should_skip_bootstrap_refresh_after_connect_failure": True,
        "probe_connect_attempted": True,
        "probe_bootstrap_attempted": False,
        "probe_log_contains_skip_refresh": True,
    },
    "hub_instance_mismatch": {
        "probe_stage": "discover",
        "probe_reason_code": "hub_instance_mismatch",
        "should_fail_closed_on_discovery": True,
        "should_skip_bootstrap_refresh_after_connect_failure": True,
        "probe_connect_attempted": False,
        "probe_bootstrap_attempted": False,
        "probe_log_contains_skip_refresh": False,
    },
    "pairing_profile_epoch_stale": {
        "probe_stage": "discover",
        "probe_reason_code": "pairing_profile_epoch_stale",
        "should_fail_closed_on_discovery": True,
        "should_skip_bootstrap_refresh_after_connect_failure": True,
        "probe_connect_attempted": False,
        "probe_bootstrap_attempted": False,
        "probe_log_contains_skip_refresh": False,
    },
    "route_pack_outdated": {
        "probe_stage": "port_detect",
        "probe_reason_code": "route_pack_outdated",
        "should_fail_closed_on_discovery": True,
        "should_skip_bootstrap_refresh_after_connect_failure": True,
        "probe_connect_attempted": False,
        "probe_bootstrap_attempted": False,
        "probe_log_contains_skip_refresh": False,
    },
}

stale_assertions = {}
for failure_code, expectation in stale_expected.items():
    case = stale_case_by_code[failure_code]
    stale_assertions[f"{failure_code}_mapped_issue"] = {
        "expected": "pairing_repair_required",
        "actual": case["mapped_issue"],
        "pass": case["mapped_issue"] == "pairing_repair_required",
    }
    stale_assertions[f"{failure_code}_paired_route_readiness"] = {
        "expected": "remote_blocked",
        "actual": case["paired_route_readiness"],
        "pass": case["paired_route_readiness"] == "remote_blocked",
    }
    stale_assertions[f"{failure_code}_paired_route_reason_code"] = {
        "expected": "remote_pairing_or_identity_blocked",
        "actual": case["paired_route_reason_code"],
        "pass": case["paired_route_reason_code"] == "remote_pairing_or_identity_blocked",
    }
    stale_assertions[f"{failure_code}_probe_stage"] = {
        "expected": expectation["probe_stage"],
        "actual": case["probe_stage"],
        "pass": case["probe_stage"] == expectation["probe_stage"],
    }
    stale_assertions[f"{failure_code}_probe_reason_code"] = {
        "expected": expectation["probe_reason_code"],
        "actual": case["probe_reason_code"],
        "pass": case["probe_reason_code"] == expectation["probe_reason_code"],
    }
    stale_assertions[f"{failure_code}_should_fail_closed_on_discovery"] = {
        "expected": expectation["should_fail_closed_on_discovery"],
        "actual": case["should_fail_closed_on_discovery"],
        "pass": case["should_fail_closed_on_discovery"] == expectation["should_fail_closed_on_discovery"],
    }
    stale_assertions[f"{failure_code}_should_skip_refresh"] = {
        "expected": expectation["should_skip_bootstrap_refresh_after_connect_failure"],
        "actual": case["should_skip_bootstrap_refresh_after_connect_failure"],
        "pass": case["should_skip_bootstrap_refresh_after_connect_failure"] == expectation["should_skip_bootstrap_refresh_after_connect_failure"],
    }
    stale_assertions[f"{failure_code}_probe_connect_attempted"] = {
        "expected": expectation["probe_connect_attempted"],
        "actual": case["probe_connect_attempted"],
        "pass": case["probe_connect_attempted"] == expectation["probe_connect_attempted"],
    }
    stale_assertions[f"{failure_code}_probe_bootstrap_attempted"] = {
        "expected": expectation["probe_bootstrap_attempted"],
        "actual": case["probe_bootstrap_attempted"],
        "pass": case["probe_bootstrap_attempted"] == expectation["probe_bootstrap_attempted"],
    }
    stale_assertions[f"{failure_code}_probe_log_contains_skip_refresh"] = {
        "expected": expectation["probe_log_contains_skip_refresh"],
        "actual": case["probe_log_contains_skip_refresh"],
        "pass": case["probe_log_contains_skip_refresh"] == expectation["probe_log_contains_skip_refresh"],
    }

stale_evidence = {
    "schema_version": "xt.stale_profile_repair_evidence.v1",
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "status": "pass",
    "smoke_kind": "xt_stale_profile_repair",
    "package_root": package_root,
    "build_log_path": build_log,
    "test_log_path": stale_test_log,
    "raw_capture_path": stale_capture_path,
    "case_count": len(stale_cases),
    "completion_definition_failure_codes": list(stale_expected.keys()),
    "discovery_fail_closed_reason_codes": stale_payload["discovery_fail_closed_reason_codes"],
    "connect_refresh_skip_reason_codes": stale_payload["connect_refresh_skip_reason_codes"],
    "cases": stale_cases,
    "assertions": stale_assertions,
}

os.makedirs(os.path.dirname(stale_evidence_path), exist_ok=True)
with open(stale_evidence_path, "w", encoding="utf-8") as handle:
    json.dump(stale_evidence, handle, indent=2, sort_keys=True)
    handle.write("\n")

print("[xhub-doctor-xt-pairing-repair-smoke] PASS")
print(f"[xhub-doctor-xt-pairing-repair-smoke] capture={capture_path}")
print(f"[xhub-doctor-xt-pairing-repair-smoke] evidence={os.path.realpath(evidence_path)}")
print(f"[xhub-doctor-xt-pairing-repair-smoke] stale_capture={stale_capture_path}")
print(f"[xhub-doctor-xt-pairing-repair-smoke] stale_evidence={os.path.realpath(stale_evidence_path)}")
PY
