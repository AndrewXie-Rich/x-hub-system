#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${XHUB_RELEASE_VERSION:-v0.1.0-alpha.5-rust-preview}"
ARCH="${XHUB_RELEASE_ARCH:-$(uname -m)}"
case "$ARCH" in
  arm64) PLATFORM="macos-arm64" ;;
  x86_64) PLATFORM="macos-x86_64" ;;
  *) PLATFORM="macos-$ARCH" ;;
esac

OUT_DIR="${XHUB_RELEASE_DIR:-$ROOT_DIR/build/release/$VERSION}"
STAGE="$OUT_DIR/stage/XHub-System-Rust-$VERSION-$PLATFORM"
HUB_DIST_ROOT="$ROOT_DIR/rust/xhubd/dist"
XT_DIST_ROOT="$ROOT_DIR/build/release"
HUB_APP="$ROOT_DIR/build/X-Hub.app"
SYSTEM_ZIP="$OUT_DIR/XHub-System-Rust-$VERSION-$PLATFORM.zip"
SYSTEM_DMG="$OUT_DIR/XHub-System-Rust-$VERSION-$PLATFORM.dmg"
HUB_APP_ZIP="$OUT_DIR/X-Hub-$VERSION-$PLATFORM.zip"
HUB_RUNTIME_ZIP="$OUT_DIR/XHub-Rust-Hub-$VERSION-$PLATFORM.zip"
XT_ZIP="$OUT_DIR/X-Terminal-RustXT-$VERSION-$PLATFORM.zip"

echo "[release] Version: $VERSION"
echo "[release] Platform: $PLATFORM"
echo "[release] Output: $OUT_DIR"

require_path() {
  local relative_path="$1"
  if [ ! -e "$ROOT_DIR/$relative_path" ]; then
    echo "Required release source is missing: $relative_path" >&2
    exit 1
  fi
}

require_git_tracked() {
  local relative_path="$1"
  if [ ! -d "$ROOT_DIR/.git" ] || [ "${XHUB_RELEASE_SKIP_GIT_TRACKED_GATE:-0}" = "1" ]; then
    return 0
  fi
  if ! git -C "$ROOT_DIR" ls-files --error-unmatch "$relative_path" >/dev/null 2>&1; then
    echo "Required UI source exists but is not tracked by Git: $relative_path" >&2
    echo "Add it before publishing, otherwise GitHub will not contain the Hub UI." >&2
    exit 1
  fi
}

assert_hub_ui_source_gate() {
  local required=(
    "x-hub/macos/RELFlowHub/Package.swift"
    "x-hub/macos/RELFlowHub/Sources/RELFlowHub/RELFlowHubApp.swift"
    "x-hub/macos/RELFlowHub/Sources/RELFlowHub/RustHubRuntimeSupport.swift"
    "x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubGRPCServerSupport.swift"
    "x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift"
    "x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift"
    "x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift"
    "x-hub/grpc-server/hub_grpc_server/src/pairing_http.js"
    "x-hub/tools/build_hub_app.command"
    "x-hub/tools/build_hub_dmg.command"
    "rust/xhubd/Cargo.toml"
    "rust/xhubd/crates/xhubd/src/main.rs"
    "rust/xhubd/crates/xhubd/src/network_bridge.rs"
    "rust/xhubd/crates/xhubd/src/xt_contract.rs"
    "rust/xhubd/tools/package_rust_hub.command"
    "rust/xhubd/tools/xt_hub_contract_smoke.command"
    "rust/xhubd/tools/xt_hub_contract_smoke.js"
    "x-terminal/Sources/Hub/HubContractClient.swift"
    "x-terminal/Sources/UI/XTUnifiedDoctor.swift"
    "scripts/rust_preview_release_live_smoke.command"
  )
  for relative_path in "${required[@]}"; do
    require_path "$relative_path"
    require_git_tracked "$relative_path"
  done
}

find_latest_dir() {
  local root="$1"
  local pattern="$2"
  find "$root" -maxdepth 1 -type d -name "$pattern" | sort | tail -n 1
}

codesign_app_after_embedding() {
  local app_path="$1"
  local identity="${XHUB_HUB_APP_CODESIGN_IDENTITY:--}"
  if ! command -v codesign >/dev/null 2>&1; then
    return 0
  fi
  codesign --force --deep --sign "$identity" "$app_path" >/dev/null 2>&1 || true
}

embed_rust_hub_into_app() {
  local hub_package_dir="$1"
  local embedded_root="$HUB_APP/Contents/Resources/rust-hub"

  if [ ! -d "$HUB_APP" ]; then
    echo "Hub app not found after build: $HUB_APP" >&2
    exit 1
  fi
  if [ ! -x "$hub_package_dir/bin/xhubd" ]; then
    echo "Rust Hub package is missing executable bin/xhubd: $hub_package_dir" >&2
    exit 1
  fi

  echo "[embed] Embedding Rust Hub runtime into X-Hub.app..."
  rm -rf "$embedded_root"
  mkdir -p "$HUB_APP/Contents/Resources"
  ditto "$hub_package_dir" "$embedded_root"

  if [ ! -x "$embedded_root/bin/xhubd" ]; then
    echo "Embedded Rust Hub executable is missing: $embedded_root/bin/xhubd" >&2
    exit 1
  fi
  codesign_app_after_embedding "$HUB_APP"
}

assert_single_hub_release_stage() {
  local stage_hub_app="$STAGE/X-Hub.app"
  local app_exec="$stage_hub_app/Contents/MacOS/RELFlowHub"
  local embedded_root="$stage_hub_app/Contents/Resources/rust-hub"
  local embedded_xhubd="$embedded_root/bin/xhubd"
  local embedded_contract_smoke="$embedded_root/tools/xt_hub_contract_smoke.command"

  if [ ! -d "$stage_hub_app" ]; then
    echo "Release stage is missing X-Hub.app. Refusing to publish a daemon-only Hub package." >&2
    exit 1
  fi
  if [ ! -x "$app_exec" ]; then
    echo "Release stage X-Hub.app is missing executable: $app_exec" >&2
    exit 1
  fi
  if [ ! -x "$embedded_xhubd" ]; then
    echo "Release stage X-Hub.app is missing embedded Rust kernel: $embedded_xhubd" >&2
    exit 1
  fi
  if [ ! -x "$embedded_contract_smoke" ]; then
    echo "Release stage X-Hub.app is missing embedded XT contract smoke tool: $embedded_contract_smoke" >&2
    exit 1
  fi
  if [ -e "$STAGE/X-Hub Rust.app" ]; then
    echo "Release stage still contains legacy X-Hub Rust.app launcher. Use X-Hub.app as the single Hub product." >&2
    exit 1
  fi
}

mkdir -p "$OUT_DIR"
assert_hub_ui_source_gate
if [ "${XHUB_RELEASE_GATE_ONLY:-0}" = "1" ]; then
  if [ "${XHUB_RELEASE_SKIP_GIT_TRACKED_GATE:-0}" = "1" ]; then
    echo "[gate] Single-Hub release source is present. Git tracked check was skipped."
  else
    echo "[gate] Single-Hub release source is present and tracked."
  fi
  exit 0
fi

echo "[1/7] Packaging Rust Hub runtime..."
bash "$ROOT_DIR/rust/xhubd/tools/package_rust_hub.command"
HUB_PACKAGE_DIR="$(find_latest_dir "$HUB_DIST_ROOT" 'rust-hub-*')"
if [ -z "$HUB_PACKAGE_DIR" ] || [ ! -d "$HUB_PACKAGE_DIR" ]; then
  echo "Rust Hub package not found under: $HUB_DIST_ROOT" >&2
  exit 1
fi

echo "[2/7] Building Swift X-Hub.app UI..."
"$ROOT_DIR/x-hub/tools/build_hub_app.command"
embed_rust_hub_into_app "$HUB_PACKAGE_DIR"

echo "[3/7] Packaging X-Terminal + Rust sidecar..."
XTERMINAL_RUNTIME_DIST_ROOT="$XT_DIST_ROOT" bash "$ROOT_DIR/x-terminal/tools/package_xt_runtime.command"
XT_PACKAGE_DIR="$(find_latest_dir "$XT_DIST_ROOT" 'xt-runtime-*')"
if [ -z "$XT_PACKAGE_DIR" ] || [ ! -d "$XT_PACKAGE_DIR" ]; then
  echo "XT runtime package not found under: $XT_DIST_ROOT" >&2
  exit 1
fi

echo "[4/7] Creating release stage..."
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$HUB_APP" "$STAGE/X-Hub.app"
ditto "$HUB_PACKAGE_DIR" "$STAGE/Rust-Hub"
ditto "$XT_PACKAGE_DIR" "$STAGE/X-Terminal-Runtime"
if [ -d "$XT_PACKAGE_DIR/app/X-Terminal.app" ]; then
  ditto "$XT_PACKAGE_DIR/app/X-Terminal.app" "$STAGE/X-Terminal.app"
fi
ln -s "/Applications" "$STAGE/Applications"

cat > "$STAGE/README.txt" <<EOF
XHub-System Rust Preview $VERSION

Contents:
- X-Hub.app: Swift macOS Hub UI with the Rust Hub runtime embedded in Contents/Resources/rust-hub
- X-Terminal.app: X-Terminal app built from the Rust preview source lane
- Rust-Hub/: packaged xhubd runtime for advanced CLI/service workflows
- X-Terminal-Runtime/: X-Terminal runtime bundle plus the Rust xtd sidecar

Normal install:
1) Quit any running X-Hub first.
2) Drag X-Hub.app and X-Terminal.app to Applications, replacing older copies.
3) Launch X-Hub.app from Applications first.
4) Launch X-Terminal.app and pair it with X-Hub.

Advanced Rust runtime fallback:
  Rust-Hub/bin/xhubd serve

Important:
- The Hub product in this package is the native Swift UI shell backed by the Rust core.
- The Rust daemon/status page is an internal runtime surface, not the main user-facing Hub app.
- No Rosetta is required for the macOS arm64 package.
- The package is a developer preview. If macOS blocks it, Control-click the app and choose Open.
- Mark the GitHub Release as prerelease unless it is signed and notarized.
EOF

assert_single_hub_release_stage

echo "[5/7] Creating release archives..."
rm -f "$HUB_APP_ZIP" "$HUB_RUNTIME_ZIP" "$XT_ZIP" "$SYSTEM_ZIP" "$SYSTEM_DMG"
ditto -c -k --keepParent "$HUB_APP" "$HUB_APP_ZIP"
ditto -c -k --keepParent "$HUB_PACKAGE_DIR" "$HUB_RUNTIME_ZIP"
ditto -c -k --keepParent "$XT_PACKAGE_DIR" "$XT_ZIP"
ditto -c -k --keepParent "$STAGE" "$SYSTEM_ZIP"

if command -v hdiutil >/dev/null 2>&1; then
  hdiutil create -volname "XHub Rust Preview" -srcfolder "$STAGE" -ov -format UDZO "$SYSTEM_DMG" >/dev/null
else
  echo "hdiutil not found; skipping DMG creation" >&2
fi

echo "[6/7] Writing SHA256SUMS.txt..."
(
  cd "$OUT_DIR"
  checksum_inputs=()
  for file in "$SYSTEM_ZIP" "$SYSTEM_DMG" "$HUB_APP_ZIP" "$HUB_RUNTIME_ZIP" "$XT_ZIP"; do
    if [ -f "$file" ]; then
      checksum_inputs+=("./$(basename "$file")")
    fi
  done
  shasum -a 256 "${checksum_inputs[@]}" > SHA256SUMS.txt
)

cat > "$OUT_DIR/RELEASE_BODY.md" <<EOF
# X-Hub-System $VERSION

This prerelease contains the current Rust preview lane for X-Hub-System.

Recommended download:

- \`XHub-System-Rust-$VERSION-$PLATFORM.dmg\`

What is included:

- \`X-Hub.app\`: native Swift macOS Hub UI with the Rust Hub runtime embedded.
- \`X-Terminal.app\`: latest X-Terminal app built from the Rust preview source lane.
- \`Rust-Hub/\`: packaged \`xhubd\` runtime for advanced CLI/service workflows.
- \`X-Terminal-Runtime/\`: X-Terminal runtime bundle plus the Rust \`xtd\` sidecar.
- \`SHA256SUMS.txt\`: checksums for release assets.

How to run:

1. Download and open the DMG.
2. Quit any running \`X-Hub.app\`; macOS can otherwise activate the old installed app because the bundle id is the same.
3. Drag \`X-Hub.app\` and \`X-Terminal.app\` to Applications, replacing older copies.
4. Control-click \`X-Hub.app\`, choose \`Open\`, and approve the developer preview warning once if macOS asks.
5. Launch \`X-Terminal.app\` and pair it with X-Hub.

Important:

- The Hub product is the native Swift UI shell backed by the Rust core.
- The Rust daemon/status page is an internal runtime surface, not the main user-facing Hub app.
- The release script checks that required Hub UI source files are tracked by Git before packaging.
- No Rosetta is required for the macOS arm64 package.
- This preview is not notarized unless this GitHub Release explicitly says otherwise.

Source tag:

- \`$VERSION\`
EOF

echo "[7/7] Done."
echo "Upload these files to the GitHub Release for $VERSION:"
echo "  $SYSTEM_ZIP"
if [ -f "$SYSTEM_DMG" ]; then
  echo "  $SYSTEM_DMG"
fi
echo "  $HUB_APP_ZIP"
echo "  $HUB_RUNTIME_ZIP"
echo "  $XT_ZIP"
echo "  $OUT_DIR/SHA256SUMS.txt"
echo "  $OUT_DIR/RELEASE_BODY.md"
