#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "$SCRIPT_DIR/cross_network_readiness_gate.command" \
  --require-live-ready \
  --require-launchd-loaded \
  --require-watchdog-timer \
  "$@"
