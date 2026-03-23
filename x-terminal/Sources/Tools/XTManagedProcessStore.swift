import Foundation
import Darwin

enum XTManagedProcessState: String, Codable, CaseIterable, Sendable {
    case starting
    case running
    case stopping
    case restarting
    case exited
    case failed
}

struct XTManagedProcessRecord: Identifiable, Codable, Equatable, Sendable {
    var processId: String
    var name: String
    var command: String
    var cwd: String
    var env: [String: String]
    var restartOnExit: Bool
    var status: XTManagedProcessState
    var pid: Int32?
    var createdAtMs: Int64
    var startedAtMs: Int64?
    var updatedAtMs: Int64
    var exitCode: Int32?
    var terminationReason: String?
    var restartCount: Int
    var lastError: String?
    var stopRequested: Bool
    var logPath: String

    var id: String { processId }
}

struct XTManagedProcessSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.managed_processes.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var processes: [XTManagedProcessRecord]
}

enum XTManagedProcessStoreError: LocalizedError {
    case commandMissing
    case invalidProcessID
    case processNotFound(String)
    case processAlreadyRunning(String)
    case pathOutsideProjectRoot(String)

    var errorDescription: String? {
        switch self {
        case .commandMissing:
            return "Managed process command is required"
        case .invalidProcessID:
            return "Managed process id must be ASCII letters, digits, dash, or underscore"
        case .processNotFound(let id):
            return "Managed process not found: \(id)"
        case .processAlreadyRunning(let id):
            return "Managed process is already running: \(id)"
        case .pathOutsideProjectRoot(let path):
            return "Managed process cwd is outside the project root: \(path)"
        }
    }
}

actor XTManagedProcessStore {
    static let shared = XTManagedProcessStore()

    private final class ProcessHandle {
        let process: Process
        let pipe: Pipe

        init(process: Process, pipe: Pipe) {
            self.process = process
            self.pipe = pipe
        }
    }

    private struct ProjectRuntime {
        var records: [String: XTManagedProcessRecord] = [:]
        var handles: [String: ProcessHandle] = [:]
        var restartTasks: [String: Task<Void, Never>] = [:]
    }

    private var runtimes: [String: ProjectRuntime] = [:]

    func start(
        projectRoot: URL,
        processId rawProcessId: String?,
        name rawName: String?,
        command rawCommand: String,
        cwd rawCWD: String?,
        env: [String: String],
        restartOnExit: Bool
    ) throws -> XTManagedProcessRecord {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw XTManagedProcessStoreError.commandMissing
        }

        let processId = try normalizedProcessID(rawProcessId)
        let name = {
            let trimmed = (rawName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? processId : trimmed
        }()
        let cwdURL = try normalizedCWD(rawCWD, projectRoot: projectRoot)
        let cwd = relativePath(cwdURL, base: projectRoot)

        let projectKey = projectRoot.standardizedFileURL.path
        ensureLoaded(projectRoot: projectRoot)
        refreshLiveness(projectRoot: projectRoot)
        var runtime = runtimes[projectKey] ?? ProjectRuntime()

        if let existing = runtime.records[processId],
           managedProcessIsActive(existing) {
            throw XTManagedProcessStoreError.processAlreadyRunning(processId)
        }

        let ctx = AXProjectContext(root: projectRoot)
        try ensureManagedProcessDirectories(ctx: ctx)
        let logURL = ctx.managedProcessLogURL(processId: processId)
        try appendLogLine(
            logURL: logURL,
            line: "=== start \(iso8601Now()) id=\(processId) name=\(name) cwd=\(cwd) restart_on_exit=\(restartOnExit ? "yes" : "no") ==="
        )

        let now = currentTimeMs()
        var record = XTManagedProcessRecord(
            processId: processId,
            name: name,
            command: command,
            cwd: cwd,
            env: env,
            restartOnExit: restartOnExit,
            status: .starting,
            pid: nil,
            createdAtMs: now,
            startedAtMs: nil,
            updatedAtMs: now,
            exitCode: nil,
            terminationReason: nil,
            restartCount: 0,
            lastError: nil,
            stopRequested: false,
            logPath: logURL.path
        )
        runtime.records[processId] = record
        runtimes[projectKey] = runtime
        persistSnapshot(projectRoot: projectRoot)

        do {
            record = try launch(record: record, projectRoot: projectRoot)
            return record
        } catch {
            var failedRecord = record
            failedRecord.status = .failed
            failedRecord.updatedAtMs = currentTimeMs()
            failedRecord.lastError = error.localizedDescription
            runtime = runtimes[projectKey] ?? ProjectRuntime()
            runtime.records[processId] = failedRecord
            runtimes[projectKey] = runtime
            persistSnapshot(projectRoot: projectRoot)
            try? appendLogLine(
                logURL: logURL,
                line: "launch_failed: \(error.localizedDescription)"
            )
            throw error
        }
    }

    func status(
        projectRoot: URL,
        processId rawProcessId: String?,
        includeExited: Bool
    ) -> [XTManagedProcessRecord] {
        ensureLoaded(projectRoot: projectRoot)
        refreshLiveness(projectRoot: projectRoot)

        let projectKey = projectRoot.standardizedFileURL.path
        guard let runtime = runtimes[projectKey] else { return [] }

        if let processId = rawProcessId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !processId.isEmpty {
            guard let record = runtime.records[processId] else { return [] }
            return [record]
        }

        let records = runtime.records.values.filter { record in
            includeExited || managedProcessIsActive(record)
        }
        return records.sorted { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs {
                return lhs.updatedAtMs > rhs.updatedAtMs
            }
            return lhs.processId < rhs.processId
        }
    }

    func logs(
        projectRoot: URL,
        processId: String,
        tailLines: Int,
        maxBytes: Int
    ) throws -> (record: XTManagedProcessRecord, text: String, truncated: Bool) {
        ensureLoaded(projectRoot: projectRoot)
        refreshLiveness(projectRoot: projectRoot)

        let projectKey = projectRoot.standardizedFileURL.path
        guard let record = runtimes[projectKey]?.records[processId] else {
            throw XTManagedProcessStoreError.processNotFound(processId)
        }

        let logURL = URL(fileURLWithPath: record.logPath)
        let data = (try? Data(contentsOf: logURL)) ?? Data()
        let truncatedData: Data
        let truncated: Bool
        if data.count > maxBytes {
            truncatedData = data.suffix(maxBytes)
            truncated = true
        } else {
            truncatedData = data
            truncated = false
        }
        let text = String(decoding: truncatedData, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let tailCount = max(1, tailLines)
        return (
            record,
            lines.suffix(tailCount).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            truncated
        )
    }

    func stop(
        projectRoot: URL,
        processId: String,
        force: Bool
    ) async throws -> XTManagedProcessRecord {
        ensureLoaded(projectRoot: projectRoot)
        refreshLiveness(projectRoot: projectRoot)

        let projectKey = projectRoot.standardizedFileURL.path
        guard var runtime = runtimes[projectKey],
              var record = runtime.records[processId] else {
            throw XTManagedProcessStoreError.processNotFound(processId)
        }

        runtime.restartTasks[processId]?.cancel()
        runtime.restartTasks[processId] = nil

        record.stopRequested = true
        record.status = .stopping
        record.updatedAtMs = currentTimeMs()
        runtime.records[processId] = record
        runtimes[projectKey] = runtime
        persistSnapshot(projectRoot: projectRoot)

        if let handle = runtime.handles[processId], handle.process.isRunning {
            handle.process.terminate()
        } else if let pid = record.pid, xtManagedProcessIsAlive(pid) {
            _ = Darwin.kill(pid, SIGTERM)
        }

        var didForceKill = false
        for _ in 0..<20 {
            if let pid = record.pid, xtManagedProcessIsAlive(pid) {
                try? await Task.sleep(nanoseconds: 100_000_000)
                continue
            }
            break
        }

        if let pid = record.pid, xtManagedProcessIsAlive(pid) {
            didForceKill = true
            _ = Darwin.kill(pid, SIGKILL)
            for _ in 0..<10 {
                if !xtManagedProcessIsAlive(pid) { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        refreshLiveness(projectRoot: projectRoot)
        runtime = runtimes[projectKey] ?? ProjectRuntime()
        record = runtime.records[processId] ?? record
        if !managedProcessIsActive(record) {
            var finalizedRecord = runtime.records[processId] ?? record
            finalizedRecord.stopRequested = false
            finalizedRecord.status = .exited
            if (finalizedRecord.terminationReason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                finalizedRecord.terminationReason = "terminated"
            }
            finalizedRecord.updatedAtMs = currentTimeMs()
            runtime.records[processId] = finalizedRecord
            runtimes[projectKey] = runtime
            persistSnapshot(projectRoot: projectRoot)
            record = finalizedRecord
        }
        if didForceKill {
            let logURL = URL(fileURLWithPath: record.logPath)
            try? appendLogLine(logURL: logURL, line: "forced_kill: yes")
        }
        return runtimes[projectKey]?.records[processId] ?? record
    }

    private func launch(
        record: XTManagedProcessRecord,
        projectRoot: URL
    ) throws -> XTManagedProcessRecord {
        let projectKey = projectRoot.standardizedFileURL.path
        var runtime = runtimes[projectKey] ?? ProjectRuntime()

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", record.command]
        process.currentDirectoryURL = try normalizedCWD(record.cwd, projectRoot: projectRoot)
        process.standardOutput = pipe
        process.standardError = pipe

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        for (key, value) in record.env {
            environment[key] = value
        }
        process.environment = environment

        let processId = record.processId
        let logURL = URL(fileURLWithPath: record.logPath)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task {
                await XTManagedProcessStore.shared.appendLogData(
                    projectRootPath: projectKey,
                    processId: processId,
                    data: data
                )
            }
        }
        process.terminationHandler = { process in
            Task {
                await XTManagedProcessStore.shared.handleTermination(
                    projectRootPath: projectKey,
                    processId: processId,
                    exitCode: process.terminationStatus,
                    reason: process.terminationReason
                )
            }
        }

        try process.run()

        var updated = record
        updated.status = .running
        updated.pid = process.processIdentifier
        updated.startedAtMs = currentTimeMs()
        updated.updatedAtMs = updated.startedAtMs ?? currentTimeMs()
        updated.exitCode = nil
        updated.terminationReason = nil
        updated.lastError = nil
        updated.stopRequested = false

        runtime.records[processId] = updated
        runtime.handles[processId] = ProcessHandle(process: process, pipe: pipe)
        runtimes[projectKey] = runtime
        persistSnapshot(projectRoot: projectRoot)
        try appendLogLine(
            logURL: logURL,
            line: "pid=\(process.processIdentifier) status=running started_at_ms=\(updated.startedAtMs ?? 0)"
        )
        return updated
    }

    private func handleTermination(
        projectRootPath: String,
        processId: String,
        exitCode: Int32,
        reason: Process.TerminationReason
    ) {
        let projectRoot = URL(fileURLWithPath: projectRootPath)
        ensureLoaded(projectRoot: projectRoot)
        var runtime = runtimes[projectRootPath] ?? ProjectRuntime()
        guard var record = runtime.records[processId] else { return }

        runtime.handles[processId]?.pipe.fileHandleForReading.readabilityHandler = nil
        runtime.handles[processId] = nil

        let now = currentTimeMs()
        let terminationReason = xtManagedTerminationReason(reason)
        let shouldRestart = record.restartOnExit && !record.stopRequested

        record.pid = nil
        record.exitCode = exitCode
        record.terminationReason = terminationReason
        record.updatedAtMs = now
        record.status = shouldRestart ? .restarting : (exitCode == 0 ? .exited : .failed)
        if !shouldRestart {
            record.stopRequested = false
        }
        runtime.records[processId] = record
        runtimes[projectRootPath] = runtime
        persistSnapshot(projectRoot: projectRoot)

        let logURL = URL(fileURLWithPath: record.logPath)
        try? appendLogLine(
            logURL: logURL,
            line: "exit_code=\(exitCode) reason=\(terminationReason) restart=\(shouldRestart ? "scheduled" : "no")"
        )

        guard shouldRestart else { return }
        scheduleRestart(projectRoot: projectRoot, processId: processId)
    }

    private func scheduleRestart(projectRoot: URL, processId: String) {
        let projectKey = projectRoot.standardizedFileURL.path
        var runtime = runtimes[projectKey] ?? ProjectRuntime()
        runtime.restartTasks[processId]?.cancel()
        runtime.restartTasks[processId] = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await XTManagedProcessStore.shared.performScheduledRestart(
                projectRootPath: projectKey,
                processId: processId
            )
        }
        runtimes[projectKey] = runtime
    }

    private func performScheduledRestart(projectRootPath: String, processId: String) {
        let projectRoot = URL(fileURLWithPath: projectRootPath)
        ensureLoaded(projectRoot: projectRoot)
        var runtime = runtimes[projectRootPath] ?? ProjectRuntime()
        runtime.restartTasks[processId] = nil
        guard var record = runtime.records[processId],
              record.restartOnExit,
              !record.stopRequested else {
            runtimes[projectRootPath] = runtime
            return
        }

        record.restartCount += 1
        record.status = .restarting
        record.updatedAtMs = currentTimeMs()
        runtime.records[processId] = record
        runtimes[projectRootPath] = runtime
        persistSnapshot(projectRoot: projectRoot)

        do {
            _ = try launch(record: record, projectRoot: projectRoot)
        } catch {
            var failedRecord = record
            failedRecord.status = .failed
            failedRecord.updatedAtMs = currentTimeMs()
            failedRecord.lastError = error.localizedDescription
            runtime = runtimes[projectRootPath] ?? ProjectRuntime()
            runtime.records[processId] = failedRecord
            runtimes[projectRootPath] = runtime
            persistSnapshot(projectRoot: projectRoot)
            try? appendLogLine(
                logURL: URL(fileURLWithPath: failedRecord.logPath),
                line: "restart_failed: \(error.localizedDescription)"
            )
        }
    }

    private func appendLogData(
        projectRootPath: String,
        processId: String,
        data: Data
    ) {
        guard let runtime = runtimes[projectRootPath],
              let record = runtime.records[processId] else { return }
        let logURL = URL(fileURLWithPath: record.logPath)
        try? ensureFileExists(logURL)
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            try? handle.close()
        }
    }

    private func ensureLoaded(projectRoot: URL) {
        let projectKey = projectRoot.standardizedFileURL.path
        guard runtimes[projectKey] == nil else { return }

        let ctx = AXProjectContext(root: projectRoot)
        let decoder = JSONDecoder()
        let snapshot = (try? Data(contentsOf: ctx.managedProcessesSnapshotURL))
            .flatMap { try? decoder.decode(XTManagedProcessSnapshot.self, from: $0) }
        var runtime = ProjectRuntime()
        for record in snapshot?.processes ?? [] {
            runtime.records[record.processId] = record
        }
        runtimes[projectKey] = runtime
    }

    private func refreshLiveness(projectRoot: URL) {
        let projectKey = projectRoot.standardizedFileURL.path
        guard var runtime = runtimes[projectKey] else { return }
        var changed = false
        for (processId, record) in runtime.records {
            guard managedProcessIsActive(record) else { continue }
            guard let pid = record.pid else { continue }
            let hasLiveHandle = runtime.handles[processId]?.process.isRunning == true
            if hasLiveHandle || xtManagedProcessIsAlive(pid) {
                continue
            }

            var updated = record
            updated.pid = nil
            updated.status = .exited
            updated.stopRequested = false
            updated.updatedAtMs = currentTimeMs()
            updated.terminationReason = updated.terminationReason ?? "stale_pid_reaped"
            runtime.records[processId] = updated
            changed = true
        }
        runtimes[projectKey] = runtime
        if changed {
            persistSnapshot(projectRoot: projectRoot)
        }
    }

    private func persistSnapshot(projectRoot: URL) {
        let projectKey = projectRoot.standardizedFileURL.path
        let ctx = AXProjectContext(root: projectRoot)
        guard let runtime = runtimes[projectKey] else { return }
        try? ensureManagedProcessDirectories(ctx: ctx)
        let snapshot = XTManagedProcessSnapshot(
            schemaVersion: XTManagedProcessSnapshot.currentSchemaVersion,
            updatedAtMs: currentTimeMs(),
            processes: runtime.records.values.sorted { lhs, rhs in
                if lhs.updatedAtMs != rhs.updatedAtMs {
                    return lhs.updatedAtMs > rhs.updatedAtMs
                }
                return lhs.processId < rhs.processId
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? XTStoreWriteSupport.writeSnapshotData(data, to: ctx.managedProcessesSnapshotURL)
    }

    private func normalizedProcessID(_ raw: String?) throws -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let generated = trimmed.isEmpty
            ? "proc-" + String(UUID().uuidString.lowercased().prefix(8))
            : trimmed
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard generated.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw XTManagedProcessStoreError.invalidProcessID
        }
        return generated
    }

    private func normalizedCWD(_ raw: String?, projectRoot: URL) throws -> URL {
        let cwd = (raw ?? ".").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = FileTool.resolvePath(cwd.isEmpty ? "." : cwd, projectRoot: projectRoot)
        do {
            try PathGuard.requireInsideAny(
                roots: [projectRoot],
                target: resolved,
                denyCode: "path_process_cwd_outside_project_root",
                policyReason: "project_root_process_cwd_only",
                detail: "Managed process cwd must stay inside the project root"
            )
        } catch {
            throw XTManagedProcessStoreError.pathOutsideProjectRoot(resolved.path)
        }
        return resolved
    }

    private func relativePath(_ url: URL, base: URL) -> String {
        let resolvedURL = PathGuard.resolve(url).path
        let resolvedBase = PathGuard.resolve(base).path
        if resolvedURL == resolvedBase {
            return "."
        }
        let prefix = resolvedBase.hasSuffix("/") ? resolvedBase : resolvedBase + "/"
        if resolvedURL.hasPrefix(prefix) {
            return String(resolvedURL.dropFirst(prefix.count))
        }
        return resolvedURL
    }

    private func managedProcessIsActive(_ record: XTManagedProcessRecord) -> Bool {
        switch record.status {
        case .starting, .running, .stopping, .restarting:
            return true
        case .exited, .failed:
            return false
        }
    }

    private func ensureManagedProcessDirectories(ctx: AXProjectContext) throws {
        try FileManager.default.createDirectory(at: ctx.managedProcessesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ctx.managedProcessesLogsDir, withIntermediateDirectories: true)
    }

    private func ensureFileExists(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: Data())
        }
    }

    private func appendLogLine(logURL: URL, line: String) throws {
        try ensureFileExists(logURL)
        guard let data = (line + "\n").data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: logURL) else {
            return
        }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
    }

    private func currentTimeMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    private func iso8601Now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

private func xtManagedTerminationReason(_ reason: Process.TerminationReason) -> String {
    switch reason {
    case .exit:
        return "exit"
    case .uncaughtSignal:
        return "uncaught_signal"
    @unknown default:
        return "unknown"
    }
}

private func xtManagedProcessIsAlive(_ pid: Int32) -> Bool {
    guard pid > 0 else { return false }
    if Darwin.kill(pid, 0) == 0 {
        return true
    }
    return errno == EPERM
}
