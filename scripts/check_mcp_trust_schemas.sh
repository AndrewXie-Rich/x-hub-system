#!/usr/bin/env bash
# Backwards-compatible wrapper. mcp-trust-registry was renamed to
# skill-trust-registry after the MCP community posting path was closed.

set -euo pipefail

echo "NOTE: mcp-trust-registry was renamed to skill-trust-registry; running skill-trust schema gate."
exec "$(dirname "$0")/check_skill_trust_schemas.sh"
