#!/bin/bash
set -euo pipefail

# Install and start the X-Hub Dock Agent as a user LaunchAgent.
# The agent reads Dock badge counts (Slack/Mail/Messages) via Accessibility and
# pushes counts-only updates to the Hub via file IPC.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

SRC_APP="$ROOT_DIR/build/X-Hub Dock Agent.app"
LEGACY_SRC_APP="$ROOT_DIR/build/RELFlowHubDockAgent.app"

if [ ! -d "$SRC_APP" ]; then
  if [ -d "$LEGACY_SRC_APP" ]; then
    SRC_APP="$LEGACY_SRC_APP"
  else
    echo "Dock Agent app not found: $SRC_APP" >&2
    echo "Run: \"$ROOT_DIR/x-hub/tools/build_hub_app.command\" first." >&2
    exit 1
  fi
fi

echo "Using X-Hub Dock Agent app bundle: $SRC_APP"
echo "(Tip: for a cleaner install you can copy it to /Applications manually, but it's not required.)"

PLIST_ID="com.rel.flowhub.dock-agent"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_ID.plist"
mkdir -p "$HOME/Library/LaunchAgents"

mkdir -p "$HOME/RELFlowHub" 2>/dev/null || true

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$PLIST_ID</string>

  <key>ProgramArguments</key>
  <array>
    <string>$SRC_APP/Contents/MacOS/RELFlowHubDockAgent</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>StandardOutPath</key>
  <string>$HOME/RELFlowHub/dock_agent.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/RELFlowHub/dock_agent.stderr.log</string>
</dict>
</plist>
EOF

UID_NOW=$(id -u)

launchctl bootout "gui/$UID_NOW" "$PLIST_PATH" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NOW" "$PLIST_PATH"
launchctl enable "gui/$UID_NOW/$PLIST_ID" 2>/dev/null || true
launchctl kickstart -k "gui/$UID_NOW/$PLIST_ID" 2>/dev/null || true

echo
echo "Installed and started: X-Hub Dock Agent ($PLIST_ID)"
echo "Next: System Settings → Privacy & Security → Accessibility → enable 'X-Hub Dock Agent'."
echo "Logs (legacy runtime dir until migration): $HOME/RELFlowHub/dock_agent.*.log"
