import Foundation
import Darwin

enum LegacyBridgeProcessCleanup {
    private static let legacyExecutableMarkers: [String] = [
        "/RELFlowHubBridge.app/Contents/MacOS/RELFlowHubBridge",
        "/X-Hub Bridge.app/Contents/MacOS/X-Hub Bridge",
        "/RELFlowHubDockAgent.app/Contents/MacOS/RELFlowHubDockAgent",
        "/X-Hub Dock Agent.app/Contents/MacOS/X-Hub Dock Agent",
    ]

    static func terminateLegacyProcessesIfNeeded() {
        let currentPID = getpid()
        let candidates = legacyProcessPIDs(excluding: currentPID)
        guard !candidates.isEmpty else { return }

        for pid in candidates {
            HubDiagnostics.log("legacy_bridge.cleanup terminating pid=\(pid)")
            _ = kill(pid, SIGTERM)
        }

        let deadline = Date().addingTimeInterval(1.2)
        while Date() < deadline {
            let survivors = candidates.filter { processExists($0) }
            if survivors.isEmpty {
                return
            }
            usleep(100_000)
        }

        for pid in candidates where processExists(pid) {
            HubDiagnostics.log("legacy_bridge.cleanup force_kill pid=\(pid)")
            _ = kill(pid, SIGKILL)
        }
    }

    private static func legacyProcessPIDs(excluding currentPID: pid_t) -> [pid_t] {
        let output = processListOutput()
        guard !output.isEmpty else { return [] }

        var pids: [pid_t] = []
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2, let pid = pid_t(parts[0]), pid != currentPID else { continue }

            let command = String(parts[1])
            guard legacyExecutableMarkers.contains(where: { command.contains($0) }) else { continue }
            pids.append(pid)
        }
        return pids
    }

    private static func processListOutput() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["ax", "-o", "pid=,command="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            HubDiagnostics.log("legacy_bridge.cleanup ps_failed error=\(error.localizedDescription)")
            return ""
        }

        process.waitUntilExit()
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func processExists(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}
