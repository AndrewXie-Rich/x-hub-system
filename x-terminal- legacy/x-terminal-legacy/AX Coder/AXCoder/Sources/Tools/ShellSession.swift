import Foundation

struct ShellSessionError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

actor ShellSessionManager {
    static let shared = ShellSessionManager()
    private var sessions: [String: ShellSession] = [:]

    func run(command: String, root: URL, timeoutSec: Double, onOutput: (@MainActor @Sendable (String) -> Void)? = nil) async throws -> ProcessResult {
        let key = root.standardizedFileURL.path
        let session: ShellSession
        if let existing = sessions[key] {
            session = existing
        } else {
            let created = ShellSession(root: root)
            sessions[key] = created
            session = created
        }
        return try await session.run(command: command, timeoutSec: timeoutSec, onOutput: onOutput)
    }
}

actor ShellSession {
    private struct PendingCommand {
        let token: String
        let command: String
        let timeoutSec: Double
        let onOutput: (@MainActor @Sendable (String) -> Void)?
        let continuation: CheckedContinuation<ProcessResult, Error>
    }

    private let root: URL
    private var process: Process? = nil
    private var stdinHandle: FileHandle? = nil
    private var stdoutHandle: FileHandle? = nil
    private var buffer: String = ""
    private var emittedCount: Int = 0
    private var queue: [PendingCommand] = []
    private var current: PendingCommand? = nil
    private var lastKnownCwd: URL
    private var timeoutTask: Task<Void, Never>? = nil
    private var streamTask: Task<Void, Never>? = nil

    init(root: URL) {
        self.root = root
        self.lastKnownCwd = root
    }

    func run(command: String, timeoutSec: Double, onOutput: (@MainActor @Sendable (String) -> Void)? = nil) async throws -> ProcessResult {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        return try await withCheckedThrowingContinuation { cont in
            let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let req = PendingCommand(token: token, command: command, timeoutSec: timeoutSec, onOutput: onOutput, continuation: cont)
            queue.append(req)
            startNextIfNeeded()
        }
    }

    private func startNextIfNeeded() {
        guard current == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        current = next
        buffer = ""
        emittedCount = 0
        do {
            try ensureProcess()
            try send(next)
            scheduleTimeout(for: next)
        } catch {
            finishCurrentWithError(error)
        }
    }

    private func ensureProcess() throws {
        if let process, process.isRunning {
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-l"]
        p.currentDirectoryURL = lastKnownCwd

        let outPipe = Pipe()
        let inPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = outPipe
        p.standardInput = inPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            if data.isEmpty { return }
            Task { await self?.handleData(data) }
        }

        p.terminationHandler = { [weak self] proc in
            Task { await self?.handleTermination(status: proc.terminationStatus) }
        }

        do {
            try p.run()
            process = p
            stdinHandle = inPipe.fileHandleForWriting
            stdoutHandle = outPipe.fileHandleForReading
        } catch {
            throw ShellSessionError(message: "Failed to start shell: \(error.localizedDescription)")
        }
    }

    private func send(_ req: PendingCommand) throws {
        guard let stdinHandle else {
            throw ShellSessionError(message: "Shell stdin unavailable")
        }
        let marker = markerFor(token: req.token)
        let payload = """
\(req.command)
printf "\\n\(marker)%s\\t%s\\n" "$?" "$PWD"
"""
        guard let data = payload.data(using: .utf8) else {
            throw ShellSessionError(message: "Failed to encode command")
        }
        do {
            try stdinHandle.write(contentsOf: data)
        } catch {
            throw ShellSessionError(message: "Failed to write to shell: \(error.localizedDescription)")
        }
    }

    private func scheduleTimeout(for req: PendingCommand) {
        timeoutTask?.cancel()
        let nanos = UInt64(max(0.1, req.timeoutSec) * 1_000_000_000)
        timeoutTask = Task { [token = req.token] in
            try? await Task.sleep(nanoseconds: nanos)
            await handleTimeout(token: token)
        }
    }

    private func handleTimeout(token: String) async {
        guard let cur = current, cur.token == token else { return }
        if let process, process.isRunning {
            process.terminate()
        }
        finishCurrentWithError(ShellSessionError(message: "Process timeout"))
    }

    private func handleTermination(status: Int32) async {
        stdoutHandle?.readabilityHandler = nil
        stdoutHandle = nil
        stdinHandle = nil
        process = nil
        buffer = ""
        if current != nil {
            finishCurrentWithError(ShellSessionError(message: "Shell terminated (status=\(status))"))
        }
    }

    private func handleData(_ data: Data) async {
        guard !data.isEmpty else { return }
        buffer += String(decoding: data, as: UTF8.self)
        scheduleStreamFlush()
        guard let cur = current else { return }

        let marker = markerFor(token: cur.token)
        guard let markerRange = buffer.range(of: marker) else { return }
        let before = String(buffer[..<markerRange.lowerBound])
        let afterMarker = buffer[markerRange.upperBound...]
        guard let lineRange = afterMarker.range(of: "\n") else { return }
        let meta = String(afterMarker[..<lineRange.lowerBound])
        let rest = String(afterMarker[lineRange.upperBound...])
        buffer = rest
        finishCurrent(output: before, meta: meta)
    }

    private func finishCurrent(output: String, meta: String) {
        timeoutTask?.cancel()
        timeoutTask = nil
        streamTask?.cancel()
        streamTask = nil

        let parts = meta.split(separator: "\t", maxSplits: 1).map(String.init)
        let exitCode = Int32(parts.first ?? "") ?? 0
        if parts.count > 1 {
            let cwdStr = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !cwdStr.isEmpty {
                lastKnownCwd = URL(fileURLWithPath: cwdStr)
            }
        }

        if let cur = current {
            current = nil
            flushRemainingOutput(fullOutput: output, onOutput: cur.onOutput)
            cur.continuation.resume(returning: ProcessResult(exitCode: exitCode, stdout: output, stderr: ""))
        }
        startNextIfNeeded()
    }

    private func finishCurrentWithError(_ error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        streamTask?.cancel()
        streamTask = nil
        if let cur = current {
            current = nil
            cur.continuation.resume(throwing: error)
        }
        startNextIfNeeded()
    }

    private func markerFor(token: String) -> String {
        "__AX_DONE__\(token)__"
    }

    private func scheduleStreamFlush() {
        guard current?.onOutput != nil else { return }
        if streamTask != nil { return }
        streamTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            await self?.flushStreamOutput()
        }
    }

    private func flushStreamOutput() async {
        streamTask = nil
        guard let cur = current, let onOutput = cur.onOutput else { return }
        let marker = markerFor(token: cur.token)
        let bufferCount = buffer.count
        if bufferCount <= emittedCount { return }

        let end: Int
        if let range = buffer.range(of: marker) {
            end = buffer.distance(from: buffer.startIndex, to: range.lowerBound)
        } else {
            let safeEnd = bufferCount - marker.count
            if safeEnd <= emittedCount { return }
            end = safeEnd
        }

        if end <= emittedCount { return }
        let chunk = slice(buffer, from: emittedCount, to: end)
        emittedCount = end
        if !chunk.isEmpty {
            Task { @MainActor in onOutput(chunk) }
        }
    }

    private func flushRemainingOutput(fullOutput: String, onOutput: (@MainActor @Sendable (String) -> Void)?) {
        guard let onOutput else { return }
        let total = fullOutput.count
        guard total > emittedCount else { return }
        let chunk = slice(fullOutput, from: emittedCount, to: total)
        emittedCount = total
        if !chunk.isEmpty {
            Task { @MainActor in onOutput(chunk) }
        }
    }

    private func slice(_ s: String, from: Int, to: Int) -> String {
        guard from < to else { return "" }
        let safeFrom = max(0, min(from, s.count))
        let safeTo = max(0, min(to, s.count))
        guard safeFrom < safeTo else { return "" }
        let start = s.index(s.startIndex, offsetBy: safeFrom)
        let end = s.index(s.startIndex, offsetBy: safeTo)
        return String(s[start..<end])
    }
}
