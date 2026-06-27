import Foundation
import Darwin

@MainActor
extension HubGRPCServerSupport {
    private struct BundledServerProcessRecord: Codable {
        var pid: Int32
        var nodeExecutablePath: String
        var serverJSPath: String
        var recordedAtMs: Int64
    }

    private static func bundledServerProcessRecordURL(baseDir: URL) -> URL {
        baseDir.appendingPathComponent("hub_grpc_process.json")
    }

    private static func loadBundledServerProcessRecord(baseDir: URL) -> BundledServerProcessRecord? {
        let url = bundledServerProcessRecordURL(baseDir: baseDir)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BundledServerProcessRecord.self, from: data)
    }

    static func saveBundledServerProcessRecord(
        baseDir: URL,
        pid: pid_t,
        nodeExecutablePath: String,
        serverJSPath: String
    ) {
        guard pid > 0 else { return }
        let record = BundledServerProcessRecord(
            pid: Int32(pid),
            nodeExecutablePath: nodeExecutablePath,
            serverJSPath: serverJSPath,
            recordedAtMs: Int64(Date().timeIntervalSince1970 * 1000.0)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(record),
              let text = String(data: data, encoding: .utf8),
              let out = (text + "\n").data(using: .utf8) else {
            return
        }
        let url = bundledServerProcessRecordURL(baseDir: baseDir)
        try? out.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func removeBundledServerProcessRecord(baseDir: URL, pid: pid_t? = nil) {
        let url = bundledServerProcessRecordURL(baseDir: baseDir)
        guard let expectedPID = pid else {
            try? FileManager.default.removeItem(at: url)
            return
        }

        if let existing = loadBundledServerProcessRecord(baseDir: baseDir),
           existing.pid != Int32(expectedPID) {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    static func bundledServerProcessPIDs(
        processListOutput: String,
        nodeExecutablePath: String,
        serverJSPath: String,
        excluding excludedPIDs: Set<pid_t> = []
    ) -> [pid_t] {
        let expectedNodePath = nodeExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedServerPath = serverJSPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expectedNodePath.isEmpty, !expectedServerPath.isEmpty else { return [] }

        var pids: [pid_t] = []
        for rawLine in processListOutput.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2, let pid = pid_t(parts[0]), !excludedPIDs.contains(pid) else {
                continue
            }

            let command = String(parts[1])
            guard command.contains(expectedNodePath), command.contains(expectedServerPath) else {
                continue
            }
            pids.append(pid)
        }

        return pids
    }

    static func terminateBundledServerProcessesIfNeeded(
        nodeExecutablePath: String,
        serverJSPath: String,
        excluding excludedPIDs: Set<pid_t> = []
    ) -> Int {
        let candidates = bundledServerProcessPIDs(
            processListOutput: processListOutput(),
            nodeExecutablePath: nodeExecutablePath,
            serverJSPath: serverJSPath,
            excluding: excludedPIDs
        )
        guard !candidates.isEmpty else { return 0 }

        for pid in candidates {
            _ = kill(pid, SIGTERM)
        }

        let deadline = Date().addingTimeInterval(1.2)
        while Date() < deadline {
            let survivors = candidates.filter { processExists($0) }
            if survivors.isEmpty {
                return candidates.count
            }
            usleep(100_000)
        }

        for pid in candidates where processExists(pid) {
            _ = kill(pid, SIGKILL)
        }

        return candidates.count
    }

    static func terminateRecordedBundledServerProcessIfNeeded(
        baseDir: URL,
        nodeExecutablePath: String,
        excluding excludedPIDs: Set<pid_t> = []
    ) -> Int {
        guard let record = loadBundledServerProcessRecord(baseDir: baseDir) else {
            return 0
        }

        let pid = pid_t(record.pid)
        guard pid > 0, !excludedPIDs.contains(pid) else {
            removeBundledServerProcessRecord(baseDir: baseDir)
            return 0
        }
        guard processExists(pid) else {
            removeBundledServerProcessRecord(baseDir: baseDir)
            return 0
        }

        let expectedNodePath = nodeExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let recordedNodePath = record.nodeExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expectedNodePath.isEmpty, recordedNodePath == expectedNodePath else {
            removeBundledServerProcessRecord(baseDir: baseDir)
            return 0
        }

        _ = kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(1.2)
        while Date() < deadline {
            if !processExists(pid) {
                removeBundledServerProcessRecord(baseDir: baseDir, pid: pid)
                return 1
            }
            usleep(100_000)
        }

        if processExists(pid) {
            _ = kill(pid, SIGKILL)
        }
        removeBundledServerProcessRecord(baseDir: baseDir, pid: pid)
        return 1
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
            HubDiagnostics.log("hub_grpc.process_list_failed error=\(error.localizedDescription)")
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
