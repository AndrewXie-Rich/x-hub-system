#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${XHUB_RELEASE_VERSION:-v0.1.0-alpha.4-rust-preview}"
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
SYSTEM_ZIP="$OUT_DIR/XHub-System-Rust-$VERSION-$PLATFORM.zip"
SYSTEM_DMG="$OUT_DIR/XHub-System-Rust-$VERSION-$PLATFORM.dmg"
HUB_ZIP="$OUT_DIR/XHub-Rust-Hub-$VERSION-$PLATFORM.zip"
XT_ZIP="$OUT_DIR/X-Terminal-RustXT-$VERSION-$PLATFORM.zip"

echo "[release] Version: $VERSION"
echo "[release] Platform: $PLATFORM"
echo "[release] Output: $OUT_DIR"

mkdir -p "$OUT_DIR"

echo "[1/6] Packaging Rust Hub..."
bash "$ROOT_DIR/rust/xhubd/tools/package_rust_hub.command"
HUB_PACKAGE_DIR="$(find "$HUB_DIST_ROOT" -maxdepth 1 -type d -name 'rust-hub-*' | sort | tail -n 1)"
if [ -z "$HUB_PACKAGE_DIR" ] || [ ! -d "$HUB_PACKAGE_DIR" ]; then
  echo "Rust Hub package not found under: $HUB_DIST_ROOT" >&2
  exit 1
fi

echo "[2/6] Packaging X-Terminal + Rust sidecar..."
XTERMINAL_RUNTIME_DIST_ROOT="$XT_DIST_ROOT" bash "$ROOT_DIR/x-terminal/tools/package_xt_runtime.command"
XT_PACKAGE_DIR="$(find "$XT_DIST_ROOT" -maxdepth 1 -type d -name 'xt-runtime-*' | sort | tail -n 1)"
if [ -z "$XT_PACKAGE_DIR" ] || [ ! -d "$XT_PACKAGE_DIR" ]; then
  echo "XT runtime package not found under: $XT_DIST_ROOT" >&2
  exit 1
fi

echo "[3/6] Creating release archives..."
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$HUB_PACKAGE_DIR" "$STAGE/Rust-Hub"
ditto "$XT_PACKAGE_DIR" "$STAGE/X-Terminal-Runtime"
if [ -d "$XT_PACKAGE_DIR/app/X-Terminal.app" ]; then
  ditto "$XT_PACKAGE_DIR/app/X-Terminal.app" "$STAGE/X-Terminal.app"
fi

HUB_LAUNCHER_APP="$STAGE/X-Hub Rust.app"
mkdir -p "$HUB_LAUNCHER_APP/Contents/MacOS" "$HUB_LAUNCHER_APP/Contents/Resources"
ditto "$HUB_PACKAGE_DIR" "$HUB_LAUNCHER_APP/Contents/Resources/Rust-Hub"
cat > "$HUB_LAUNCHER_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>xhub-rust-launcher</string>
  <key>CFBundleIdentifier</key>
  <string>com.ax.xhub.rust.preview</string>
  <key>CFBundleName</key>
  <string>X-Hub Rust</string>
  <key>CFBundleDisplayName</key>
  <string>X-Hub Rust</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
</dict>
</plist>
PLIST
cat > "$HUB_LAUNCHER_APP/Contents/MacOS/xhub-rust-launcher" <<'LAUNCHER'
#!/bin/zsh
set -u

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HUB_DIR="$APP_DIR/Resources/Rust-Hub"
SUPPORT_DIR="$HOME/Library/Application Support/XHubSystem/Rust-Hub"
LOG_DIR="$HOME/Library/Logs/XHubSystem"
mkdir -p "$SUPPORT_DIR/data/memory" "$SUPPORT_DIR/runtime" "$SUPPORT_DIR/run" "$LOG_DIR" 2>/dev/null || LOG_DIR="${TMPDIR:-/tmp}/XHubSystem"
mkdir -p "$LOG_DIR" 2>/dev/null || true

OUT_LOG="$LOG_DIR/xhubd.out.log"
ERR_LOG="$LOG_DIR/xhubd.err.log"
PID_FILE="$SUPPORT_DIR/run/xhubd.pid"
URL="http://127.0.0.1:50151/"

if [ ! -x "$HUB_DIR/bin/xhubd" ]; then
  osascript -e 'display dialog "Rust Hub runtime was not found inside X-Hub Rust.app." buttons {"OK"} default button "OK"' >/dev/null 2>&1 || true
  exit 127
fi

if command -v curl >/dev/null 2>&1 && curl -fsS --max-time 1 "${URL}health" >/dev/null 2>&1; then
  open "$URL" >/dev/null 2>&1 || true
  exit 0
fi

if [ -d "$HUB_DIR/skills" ] && [ ! -d "$SUPPORT_DIR/skills" ]; then
  ditto "$HUB_DIR/skills" "$SUPPORT_DIR/skills" >/dev/null 2>&1 || true
fi

(
  cd "$HUB_DIR" || exit 1
  export XHUB_RUST_HUB_ROOT="$HUB_DIR"
  export XHUB_RUST_HUB_HOST="127.0.0.1"
  export XHUB_RUST_HUB_HTTP_PORT="50151"
  export HUB_DB_PATH="$SUPPORT_DIR/data/hub.sqlite3"
  export HUB_RUNTIME_BASE_DIR="$SUPPORT_DIR/runtime"
  export XHUB_RUST_MEMORY_DIR="$SUPPORT_DIR/data/memory"
  export XHUB_RUST_SKILLS_DIR="${SUPPORT_DIR}/skills"
  exec "$HUB_DIR/bin/xhubd" serve >>"$OUT_LOG" 2>>"$ERR_LOG"
) &
echo "$!" > "$PID_FILE" 2>/dev/null || true

for _ in {1..40}; do
  if command -v curl >/dev/null 2>&1 && curl -fsS --max-time 1 "${URL}ready" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

open "$URL" >/dev/null 2>&1 || osascript -e "display dialog \"Rust Hub was started, but macOS could not open the browser. Open ${URL} manually. Logs: ${LOG_DIR}\" buttons {\"OK\"} default button \"OK\"" >/dev/null 2>&1 || true
LAUNCHER
chmod +x "$HUB_LAUNCHER_APP/Contents/MacOS/xhub-rust-launcher"
if command -v swiftc >/dev/null 2>&1; then
  LAUNCHER_SWIFT="$OUT_DIR/xhub_rust_launcher.swift"
  cat > "$LAUNCHER_SWIFT" <<'SWIFT'
import AppKit
import Foundation

let fileManager = FileManager.default
let bundleURL = Bundle.main.bundleURL
let resourcesURL = Bundle.main.resourceURL ?? bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
let hubURL = resourcesURL.appendingPathComponent("Rust-Hub", isDirectory: true)
let xhubdURL = hubURL.appendingPathComponent("bin/xhubd")
let statusURL = URL(string: "http://127.0.0.1:50151/")!
let healthURL = URL(string: "http://127.0.0.1:50151/health")!
let readyURL = URL(string: "http://127.0.0.1:50151/ready")!

func preferredDirectory(_ candidates: [URL]) -> URL {
    for candidate in candidates {
        do {
            try fileManager.createDirectory(at: candidate, withIntermediateDirectories: true)
            if fileManager.isWritableFile(atPath: candidate.path) {
                return candidate
            }
        } catch {}
    }
    let fallback = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("XHubSystem", isDirectory: true)
    try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
    return fallback
}

let supportBase = preferredDirectory([
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("XHubSystem/Rust-Hub", isDirectory: true),
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("XHubSystem/Rust-Hub", isDirectory: true)
].compactMap { $0 })

let logBase = preferredDirectory([
    fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Logs/XHubSystem", isDirectory: true),
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("XHubSystem", isDirectory: true)
].compactMap { $0 })

let dataURL = supportBase.appendingPathComponent("data", isDirectory: true)
let memoryURL = dataURL.appendingPathComponent("memory", isDirectory: true)
let runtimeURL = supportBase.appendingPathComponent("runtime", isDirectory: true)
let runURL = supportBase.appendingPathComponent("run", isDirectory: true)
let writableSkillsURL = supportBase.appendingPathComponent("skills", isDirectory: true)
let embeddedSkillsURL = hubURL.appendingPathComponent("skills", isDirectory: true)
let outLogURL = logBase.appendingPathComponent("xhubd.out.log")
let errLogURL = logBase.appendingPathComponent("xhubd.err.log")
let pidURL = runURL.appendingPathComponent("xhubd.pid")

for directory in [dataURL, memoryURL, runtimeURL, runURL, logBase] {
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
}

func appendLog(_ line: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let text = "[\(stamp)] \(line)\n"
    let data = Data(text.utf8)
    if !fileManager.fileExists(atPath: outLogURL.path) {
        fileManager.createFile(atPath: outLogURL.path, contents: nil)
    }
    if let handle = try? FileHandle(forWritingTo: outLogURL) {
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}

func showAlert(_ title: String, _ message: String) {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "Open Logs")
    alert.addButton(withTitle: "OK")
    if alert.runModal() == .alertFirstButtonReturn {
        NSWorkspace.shared.open(logBase)
    }
}

func httpOK(_ url: URL, requireReady: Bool = false) -> Bool {
    var request = URLRequest(url: url)
    request.timeoutInterval = 1.0
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let semaphore = DispatchSemaphore(value: 0)
    var ok = false
    URLSession.shared.dataTask(with: request) { data, response, _ in
        if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
            if requireReady {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                ok = body.contains("\"ready\":true")
            } else {
                ok = true
            }
        }
        semaphore.signal()
    }.resume()
    _ = semaphore.wait(timeout: .now() + 1.5)
    return ok
}

func waitForReady() -> Bool {
    for _ in 0..<50 {
        if httpOK(readyURL, requireReady: true) {
            return true
        }
        Thread.sleep(forTimeInterval: 0.25)
    }
    return false
}

func startHubIfNeeded() throws {
    if httpOK(healthURL) {
        appendLog("Rust Hub already responding on \(statusURL.absoluteString)")
        return
    }
    guard fileManager.isExecutableFile(atPath: xhubdURL.path) else {
        throw NSError(domain: "XHubRustLauncher", code: 127, userInfo: [
            NSLocalizedDescriptionKey: "Missing executable: \(xhubdURL.path)"
        ])
    }
    if fileManager.fileExists(atPath: embeddedSkillsURL.path)
        && !fileManager.fileExists(atPath: writableSkillsURL.path) {
        try? fileManager.copyItem(at: embeddedSkillsURL, to: writableSkillsURL)
    }
    if !fileManager.fileExists(atPath: outLogURL.path) {
        fileManager.createFile(atPath: outLogURL.path, contents: nil)
    }
    if !fileManager.fileExists(atPath: errLogURL.path) {
        fileManager.createFile(atPath: errLogURL.path, contents: nil)
    }
    let process = Process()
    process.executableURL = xhubdURL
    process.arguments = ["serve"]
    process.currentDirectoryURL = hubURL
    var env = ProcessInfo.processInfo.environment
    env["XHUB_RUST_HUB_ROOT"] = hubURL.path
    env["XHUB_RUST_HUB_HOST"] = "127.0.0.1"
    env["XHUB_RUST_HUB_HTTP_PORT"] = "50151"
    env["HUB_DB_PATH"] = dataURL.appendingPathComponent("hub.sqlite3").path
    env["HUB_RUNTIME_BASE_DIR"] = runtimeURL.path
    env["XHUB_RUST_MEMORY_DIR"] = memoryURL.path
    env["XHUB_RUST_SKILLS_DIR"] = fileManager.fileExists(atPath: writableSkillsURL.path)
        ? writableSkillsURL.path
        : embeddedSkillsURL.path
    env["XHUB_RUST_READY_CACHE_TTL_MS"] = "500"
    process.environment = env
    process.standardOutput = try? FileHandle(forWritingTo: outLogURL)
    process.standardError = try? FileHandle(forWritingTo: errLogURL)
    appendLog("Starting Rust Hub from \(hubURL.path)")
    try process.run()
    try? "\(process.processIdentifier)\n".write(to: pidURL, atomically: true, encoding: .utf8)
}

do {
    try startHubIfNeeded()
    let ready = waitForReady()
    let opened = NSWorkspace.shared.open(statusURL)
    if !ready {
        showAlert(
            "Rust Hub is not ready yet",
            "The launcher started xhubd and tried to open \(statusURL.absoluteString).\n\nLogs: \(logBase.path)"
        )
    } else if !opened {
        showAlert(
            "Rust Hub started",
            "Open \(statusURL.absoluteString) manually.\n\nLogs: \(logBase.path)"
        )
    }
} catch {
    showAlert(
        "Rust Hub could not start",
        "\(error.localizedDescription)\n\nLogs: \(logBase.path)"
    )
    exit(1)
}
SWIFT
  swift_target_args=()
  if [ "$ARCH" = "arm64" ]; then
    swift_target_args=(-target arm64-apple-macos13.0)
  elif [ "$ARCH" = "x86_64" ]; then
    swift_target_args=(-target x86_64-apple-macos13.0)
  fi
  if swiftc "${swift_target_args[@]}" "$LAUNCHER_SWIFT" -o "$HUB_LAUNCHER_APP/Contents/MacOS/xhub-rust-launcher" >/dev/null 2>&1; then
    chmod +x "$HUB_LAUNCHER_APP/Contents/MacOS/xhub-rust-launcher"
  else
    echo "warning: swiftc launcher build failed; keeping shell launcher fallback" >&2
  fi
fi
codesign --force --sign "${XHUB_RUST_LAUNCHER_CODESIGN_IDENTITY:--}" "$HUB_LAUNCHER_APP" >/dev/null 2>&1 || true

cat > "$STAGE/README.txt" <<EOF
XHub-System Rust Preview $VERSION

Contents:
- X-Hub Rust.app: native launcher for the Rust Hub daemon and browser status page
- X-Terminal.app: latest X-Terminal app built from the Rust preview source lane
- Rust-Hub/: packaged xhubd daemon, config, migrations, tools, skills, and docs
- X-Terminal-Runtime/: X-Terminal.app plus Rust xtd sidecar and run helper

Double-click:
  X-Hub Rust.app
  X-Terminal.app

Rust Hub opens this local status page:
  http://127.0.0.1:50151/

Runtime data and logs:
  ~/Library/Application Support/XHubSystem/Rust-Hub
  ~/Library/Logs/XHubSystem

Terminal/developer fallback:
  Rust-Hub/bin/xhubd serve

Important:
- This is the Rust preview distribution.
- Rust Hub is packaged as xhubd runtime/daemon plus X-Hub Rust.app launcher, not as the legacy X-Hub.app GUI.
- No Rosetta is required for the macOS arm64 package.
- The package is a developer preview. If macOS blocks it, Control-click X-Hub Rust.app and choose Open.
- Mark the GitHub Release as prerelease.
EOF

rm -f "$HUB_ZIP" "$XT_ZIP" "$SYSTEM_ZIP" "$SYSTEM_DMG"
ditto -c -k --keepParent "$HUB_PACKAGE_DIR" "$HUB_ZIP"
ditto -c -k --keepParent "$XT_PACKAGE_DIR" "$XT_ZIP"
ditto -c -k --keepParent "$STAGE" "$SYSTEM_ZIP"

echo "[4/6] Creating combined DMG..."
if command -v hdiutil >/dev/null 2>&1; then
  hdiutil create -volname "XHub Rust Preview" -srcfolder "$STAGE" -ov -format UDZO "$SYSTEM_DMG" >/dev/null
else
  echo "hdiutil not found; skipping DMG creation" >&2
fi

echo "[5/6] Writing SHA256SUMS.txt..."
(
  cd "$OUT_DIR"
  checksum_inputs=(./*.zip)
  if [ -f "$SYSTEM_DMG" ]; then
    checksum_inputs+=("$(basename "$SYSTEM_DMG")")
  fi
  shasum -a 256 "${checksum_inputs[@]}" > SHA256SUMS.txt
)

cat > "$OUT_DIR/RELEASE_BODY.md" <<EOF
# X-Hub-System $VERSION

This prerelease contains the current Rust preview lane for X-Hub-System.

Recommended download:

- \`XHub-System-Rust-$VERSION-$PLATFORM.dmg\`

What is included:

- \`X-Hub Rust.app\`: native launcher for the Rust Hub daemon and local browser status page.
- \`X-Terminal.app\`: latest X-Terminal app built from the Rust preview source lane.
- \`Rust-Hub/\`: packaged \`xhubd\` daemon, config, migrations, tools, skills, and docs.
- \`X-Terminal-Runtime/\`: X-Terminal runtime bundle plus the Rust \`xtd\` sidecar.
- \`SHA256SUMS.txt\`: checksums for release assets.

How to run:

1. Download and open the DMG.
2. Control-click \`X-Hub Rust.app\`, choose \`Open\`, and approve the developer preview warning once if macOS asks.
3. Double-click \`X-Terminal.app\`.

Important:

- This is the Rust preview distribution.
- No Rosetta is required for the macOS arm64 package.
- The current Rust Hub is packaged as the \`xhubd\` runtime/daemon plus \`X-Hub Rust.app\` launcher.
- \`X-Hub Rust.app\` opens the local status page at \`http://127.0.0.1:50151/\`.
- Do not use old \`X-Hub.app\` assets from earlier releases if you want the Rust preview.
- This preview is not notarized yet; a notarized Developer ID DMG should be produced before a broader public release.

Source tag:

- \`$VERSION\`
EOF

echo "[6/6] Done."
echo "Upload these files to the GitHub Release for $VERSION:"
echo "  $SYSTEM_ZIP"
if [ -f "$SYSTEM_DMG" ]; then
  echo "  $SYSTEM_DMG"
fi
echo "  $HUB_ZIP"
echo "  $XT_ZIP"
echo "  $OUT_DIR/SHA256SUMS.txt"
echo "  $OUT_DIR/RELEASE_BODY.md"
