#!/bin/bash
set -euo pipefail

PLIST_ID="com.rel.flowhub.dock-agent"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_ID.plist"

UID_NOW=$(id -u)
launchctl bootout "gui/$UID_NOW" "$PLIST_PATH" 2>/dev/null || true
rm -f "$PLIST_PATH" 2>/dev/null || true

echo "Uninstalled: $PLIST_ID"

