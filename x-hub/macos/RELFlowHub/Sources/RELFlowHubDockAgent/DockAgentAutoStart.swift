import Foundation
import RELFlowHubCore
import Darwin

private func runCapture(_ exe: String, _ args: [String], timeoutSec: Double = 1.2) -> (code: Int32, out: String, err: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    let outPipe = Pipe()
    let errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe
    do {
        try p.run()
    } catch {
        return (code: 127, out: "", err: String(describing: error))
    }
    let deadline = Date().addingTimeInterval(timeoutSec)
    while p.isRunning && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.03))
    }
    if p.isRunning {
        p.terminate()
    }
    let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
    let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
    let out = String(data: outData, encoding: .utf8) ?? ""
    let err = String(data: errData, encoding: .utf8) ?? ""
    return (code: p.terminationStatus, out: out, err: err)
}

/// Manages an optional per-user LaunchAgent so RELFlowHubDockAgent can auto-start at login.
///
/// We intentionally use LaunchAgents (not SMAppService) because DockAgent is a standalone app
/// in this project, and LaunchAgents are reliable for internal/team distribution.
enum DockAgentAutoStart {
    static let label = "com.rel.flowhub.dockagent"

    struct Status {
        var installed: Bool
        var loaded: Bool
        var plistPath: String
        var debug: String
    }

    static func status() -> Status {
        let plist = launchAgentPlistURL()
        let installed = FileManager.default.fileExists(atPath: plist.path)
        let loaded = isLoaded()
        return Status(installed: installed, loaded: loaded, plistPath: plist.path, debug: "")
    }

    static func installAndLoad() -> Status {
        do {
            try writePlist()
        } catch {
            var st = status()
            st.debug = "write_plist_error:\(error.localizedDescription)"
            return st
        }

        // Load into the current GUI session.
        let uid = String(getuid())
        let plist = launchAgentPlistURL().path
        let r = runCapture("/bin/launchctl", ["bootstrap", "gui/\(uid)", plist], timeoutSec: 2.0)
        if r.code != 0 {
            // If already loaded, bootstrap can return an error; treat it as best-effort.
            // We'll still report the current loaded state.
            var st = status()
            st.debug = "bootstrap_code=\(r.code) err=\(r.err.trimmingCharacters(in: .whitespacesAndNewlines))"
            return st
        }
        return status()
    }

    static func unloadAndRemove() -> Status {
        let uid = String(getuid())
        let plistURL = launchAgentPlistURL()
        let plist = plistURL.path

        _ = runCapture("/bin/launchctl", ["bootout", "gui/\(uid)", plist], timeoutSec: 2.0)
        try? FileManager.default.removeItem(at: plistURL)
        return status()
    }

    private static func isLoaded() -> Bool {
        let uid = String(getuid())
        let target = "gui/\(uid)/\(label)"
        let r = runCapture("/bin/launchctl", ["print", target], timeoutSec: 1.2)
        return r.code == 0
    }

    private static func launchAgentPlistURL() -> URL {
        let home = SharedPaths.realHomeDirectory()
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    private static func writePlist() throws {
        let plistURL = launchAgentPlistURL()
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let exe = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("RELFlowHubDockAgent")
            .path

        let logDir = SharedPaths.realHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
            "StandardOutPath": logDir.appendingPathComponent("dock_agent.launch.out").path,
            "StandardErrorPath": logDir.appendingPathComponent("dock_agent.launch.err").path,
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
    }
}
