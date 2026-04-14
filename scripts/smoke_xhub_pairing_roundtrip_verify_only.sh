#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_REPORT_PATH="${ROOT_DIR}/build/reports/xhub_pairing_roundtrip_verify_only_smoke_evidence.v1.json"

XHUB_PAIRING_SMOKE_MODE=verify_only \
XHUB_PAIRING_SMOKE_REPORT_PATH="${XHUB_PAIRING_SMOKE_REPORT_PATH:-$DEFAULT_REPORT_PATH}" \
  "$SCRIPT_DIR/smoke_xhub_background_pairing_roundtrip.sh" "$@"
