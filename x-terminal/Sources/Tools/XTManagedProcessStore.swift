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
    case processOwnershipUnverified(String)

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
        case .processOwnershipUnverified(let id):
            return "Managed process ownership is unverified: \(id); no signal was sent"
        }
    }
}

actor XTManagedProcessStore {
    static let shared = XTManagedProcessStore()

    private final class ProcessHandle {
        let generation = UUID()
        let cancellation = ProcessCancellation()
        var task: Task<Void, Never>?

        deinit { cancellation.cancel() }
    }

    private struct ProjectRuntime {
        var records: [String: XTManagedProcessRecord] = [:]
        var handles: [String: ProcessHandle] = [:]
        var restartTasks: [String: Task<Void, Never>] = [:]
    }

    private var runtimes: [String: ProjectRuntime] = [:]
    private var logStores: [String: XTManagedProcessLog] = [:]

    func start(
        projectRoot: URL,
        processId rawProcessId: String?,
        name rawName: String?,
        command rawCommand: String,
        cwd rawCWD: String?,
        env: [String: String],
        restartOnExit: Bool
    ) async throws -> XTManagedProcessRecord {
        try Task.checkCancellation()
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
        if runtime.records[processId]?.terminationReason == "ownership_unverified" {
            throw XTManagedProcessStoreError.processOwnershipUnverified(processId)
        }

        let ctx = XTManagedProcessPaths(root: projectRoot)
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
            record = try await launch(record: record, projectRoot: projectRoot)
            return record
        } catch {
            guard runtimes[projectKey]?.records[processId] == record else { throw error }
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

        let tail = try logStore(URL(fileURLWithPath: record.logPath)).tail(maxBytes: maxBytes)
        let text = String(decoding: tail.data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let tailCount = max(1, tailLines)
        return (
            record,
            lines.suffix(tailCount).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            tail.truncated || lines.count > tailCount
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

        guard record.terminationReason != "ownership_unverified" else {
            throw XTManagedProcessStoreError.processOwnershipUnverified(processId)
        }
        guard managedProcessIsActive(record) else { return record }

        runtime.restartTasks[processId]?.cancel()
        runtime.restartTasks[processId] = nil

        record.stopRequested = true
        record.status = .stopping
        record.updatedAtMs = currentTimeMs()
        runtime.records[processId] = record
        runtimes[projectKey] = runtime
        persistSnapshot(projectRoot: projectRoot)

        if let handle = runtime.handles[processId] {
            handle.cancellation.cancel(force: force)
            await handle.task?.value
        } else {
            record.status = .exited
            record.pid = nil
            record.terminationReason = "stopped_before_restart"
            runtime.records[processId] = record
            runtimes[projectKey] = runtime
            persistSnapshot(projectRoot: projectRoot)
        }
        return runtimes[projectKey]?.records[processId] ?? record
    }

    private func launch(
        record: XTManagedProcessRecord,
        projectRoot: URL
    ) async throws -> XTManagedProcessRecord {
        let projectKey = projectRoot.standardizedFileURL.path
        var runtime = runtimes[projectKey] ?? ProjectRuntime()
        let cwd = try normalizedCWD(record.cwd, projectRoot: projectRoot)
        let environment = XTManagedProcessEnvironment.make(overrides: record.env)
        let processId = record.processId
        let logURL = URL(fileURLWithPath: record.logPath)
        let log = logStore(logURL)
        let handle = ProcessHandle()
        let generation = handle.generation
        let cancellation = handle.cancellation
        runtime.handles[processId] = handle
        runtimes[projectKey] = runtime

        let processID = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                let launch = XTManagedProcessLaunch(continuation)
                handle.task = Task { [weak self] in
                    let result: Result<ProcessResult, Error>
                    do {
                        let captured = try await ProcessCapture.runAsync(
                            "/bin/zsh", ["-f", "-c", record.command], cwd: cwd,
                            timeoutSec: nil, env: environment, inheritEnvironment: false,
                            outputLimitBehavior: .truncate, cancellation: cancellation, captureOutput: false,
                            onStart: { launch.resolve(.success($0)) },
                            onOutput: { data, _ in try log.append(data) }
                        )
                        result = .success(captured)
                    } catch {
                        launch.resolve(.failure(error))
                        result = .failure(error)
                    }
                    await self?.handleTermination(
                        projectRootPath: projectKey, processId: processId,
                        generation: generation, result: result
                    )
                }
            }
        } onCancel: {
            cancellation.cancel()
        }

        runtime = runtimes[projectKey] ?? ProjectRuntime()
        guard runtime.handles[processId]?.generation == generation else {
            return runtime.records[processId] ?? record
        }
        var updated = runtime.records[processId] ?? record
        updated.status = updated.stopRequested ? .stopping : .running
        updated.pid = processID
        updated.startedAtMs = currentTimeMs()
        updated.updatedAtMs = updated.startedAtMs ?? currentTimeMs()
        updated.exitCode = nil
        updated.terminationReason = nil
        updated.lastError = nil

        runtime.records[processId] = updated
        runtimes[projectKey] = runtime
        persistSnapshot(projectRoot: projectRoot)
        try? appendLogLine(
            logURL: logURL,
            line: "pid=\(processID) status=\(updated.status.rawValue) started_at_ms=\(updated.startedAtMs ?? 0)"
        )
        return updated
    }

    private func handleTermination(
        projectRootPath: String,
        processId: String,
        generation: UUID,
        result: Result<ProcessResult, Error>
    ) {
        let projectRoot = URL(fileURLWithPath: projectRootPath)
        ensureLoaded(projectRoot: projectRoot)
        var runtime = runtimes[projectRootPath] ?? ProjectRuntime()
        guard var record = runtime.records[processId],
              runtime.handles[processId]?.generation == generation else { return }
        runtime.handles[processId] = nil

        let now = currentTimeMs()
        let exitCode: Int32?
        let terminationReason: String
        let completed: Bool
        switch result {
        case .success(let captured):
            exitCode = captured.exitCode
            terminationReason = captured.terminationSignal == nil ? "exit" : "uncaught_signal"
            completed = true
        case .failure(let error):
            exitCode = nil
            terminationReason = error is CancellationError ? "cancelled" : "execution_failed"
            if !(error is CancellationError) { record.lastError = error.localizedDescription }
            completed = false
        }
        let shouldRestart = completed && record.restartOnExit && !record.stopRequested

        record.pid = nil
        record.exitCode = exitCode
        record.terminationReason = terminationReason
        record.updatedAtMs = now
        record.status = shouldRestart ? .restarting : (record.stopRequested || exitCode == 0 ? .exited : .failed)
        runtime.records[processId] = record
        runtimes[projectRootPath] = runtime
        persistSnapshot(projectRoot: projectRoot)

        let logURL = URL(fileURLWithPath: record.logPath)
        try? appendLogLine(
            logURL: logURL,
            line: "exit_code=\(exitCode.map(String.init) ?? "unknown") reason=\(terminationReason) restart=\(shouldRestart ? "scheduled" : "no")"
        )

        guard shouldRestart else { return }
        scheduleRestart(projectRoot: projectRoot, processId: processId)
    }

    private func scheduleRestart(projectRoot: URL, processId: String) {
        let projectKey = projectRoot.standardizedFileURL.path
        var runtime = runtimes[projectKey] ?? ProjectRuntime()
        runtime.restartTasks[processId]?.cancel()
        runtime.restartTasks[processId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.performScheduledRestart(
                projectRootPath: projectKey,
                processId: processId
            )
        }
        runtimes[projectKey] = runtime
    }

    private func performScheduledRestart(projectRootPath: String, processId: String) async {
        let projectRoot = URL(fileURLWithPath: projectRootPath)
        ensureLoaded(projectRoot: projectRoot)
        var runtime = runtimes[projectRootPath] ?? ProjectRuntime()
        runtime.restartTasks[processId] = nil
        guard var record = runtime.records[processId],
              record.restartOnExit,
              record.status == .restarting,
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
            _ = try await launch(record: record, projectRoot: projectRoot)
        } catch {
            guard runtimes[projectRootPath]?.records[processId] == record else { return }
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

    private func ensureLoaded(projectRoot: URL) {
        let projectKey = projectRoot.standardizedFileURL.path
        guard runtimes[projectKey] == nil else { return }

        let ctx = XTManagedProcessPaths(root: projectRoot)
        let decoder = JSONDecoder()
        let snapshot = (try? Data(contentsOf: ctx.managedProcessesSnapshotURL))
            .flatMap { try? decoder.decode(XTManagedProcessSnapshot.self, from: $0) }
        var runtime = ProjectRuntime()
        for var record in snapshot?.processes ?? [] {
            guard !record.processId.isEmpty,
                  (try? normalizedProcessID(record.processId)) == record.processId else { continue }
            record.logPath = ctx.managedProcessLogURL(processId: record.processId).path
            if managedProcessIsActive(record) {
                record.status = .failed
                record.terminationReason = "ownership_unverified"
                record.lastError = "Persisted PID is not proof of process ownership; automatic adoption and signalling are disabled"
                record.stopRequested = true
            }
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
            if runtime.handles[processId] != nil || runtime.restartTasks[processId] != nil {
                continue
            }

            var updated = record
            updated.pid = nil
            updated.status = .failed
            updated.stopRequested = true
            updated.updatedAtMs = currentTimeMs()
            updated.terminationReason = "ownership_unverified"
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
        let ctx = XTManagedProcessPaths(root: projectRoot)
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
        let resolved = cwd.hasPrefix("/")
            ? URL(fileURLWithPath: cwd)
            : projectRoot.appendingPathComponent(cwd.isEmpty ? "." : cwd)
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

    private func ensureManagedProcessDirectories(ctx: XTManagedProcessPaths) throws {
        try FileManager.default.createDirectory(at: ctx.managedProcessesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ctx.managedProcessesLogsDir, withIntermediateDirectories: true)
    }

    private func logStore(_ url: URL) -> XTManagedProcessLog {
        if let existing = logStores[url.path] { return existing }
        let log = XTManagedProcessLog(url: url)
        logStores[url.path] = log
        return log
    }

    private func appendLogLine(logURL: URL, line: String) throws {
        try logStore(logURL).append(Data((line + "\n").utf8))
    }

    private func currentTimeMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    private func iso8601Now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
