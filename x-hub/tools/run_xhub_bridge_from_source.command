#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PKG_DIR="$ROOT_DIR/x-hub/macos/RELFlowHub"

cd "$PKG_DIR"
exec swift run XHubBridge "$@"
