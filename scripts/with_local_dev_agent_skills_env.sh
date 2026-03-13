#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_PUBLISHER_ID="${XHUB_LOCAL_DEV_AGENT_SKILLS_PUBLISHER_ID:-xhub.local.dev}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/with_local_dev_agent_skills_env.sh [--publisher-id <id>] -- <command> [args...]

Examples:
  bash scripts/with_local_dev_agent_skills_env.sh -- bash x-hub/tools/run_xhub_from_source.command
  bash scripts/with_local_dev_agent_skills_env.sh -- build/X-Hub.app/Contents/MacOS/RELFlowHub
EOF
}

PUBLISHER_ID="$DEFAULT_PUBLISHER_ID"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --publisher-id)
      if [ "$#" -lt 2 ]; then
        echo "missing value for --publisher-id" >&2
        usage >&2
        exit 1
      fi
      PUBLISHER_ID="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ "$#" -eq 0 ]; then
  echo "missing command to execute" >&2
  usage >&2
  exit 1
fi

ENV_FILE="$ROOT_DIR/build/local-dev-agent-skills/$PUBLISHER_ID/use_local_dev_agent_skills.env.sh"
if [ ! -f "$ENV_FILE" ]; then
  echo "local dev agent skills env not found: $ENV_FILE" >&2
  echo "generate it with:" >&2
  echo "  node scripts/build_local_dev_agent_skills_release.js --publisher-id $PUBLISHER_ID --force" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"
exec "$@"
