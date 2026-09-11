import Foundation
import Darwin

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
    private let loadLoginEnvironment: Bool
    private var process: Process? = nil
    private var processGeneration: UUID?
    private var outputBudget = ShellOutputBudget()
    private var stdinHandle: FileHandle? = nil
    private var stdoutHandle: FileHandle? = nil
    private var buffer = Data()
    private var markerSearchOffset = 0
    private var pendingOutputChunks: [Int: Data] = [:]
    private var nextOutputSequence = 0
    private var emittedCount: Int = 0
    private var queue: [PendingCommand] = []
    private var current: PendingCommand? = nil
    private var lastKnownCwd: URL
    private var timeoutTask: Task<Void, Never>? = nil
    private var streamTask: Task<Void, Never>? = nil

    init(root: URL, loadLoginEnvironment: Bool = true) {
        self.root = root
        self.lastKnownCwd = root
        self.loadLoginEnvironment = loadLoginEnvironment
    }

    func run(command: String, timeoutSec: Double, onOutput: (@MainActor @Sendable (String) -> Void)? = nil) async throws -> ProcessResult {
        try Task.checkCancellation()
        guard timeoutSec.isFinite, timeoutSec > 0, timeoutSec <= Double(UInt64.max / 1_000_000_000),
              command.utf8.count <= 64 * 1024, !command.utf8.contains(0) else {
            throw ShellSessionError(message: "Invalid shell timeout or command size")
        }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let request = PendingCommand(token: token, command: command, timeoutSec: timeoutSec, onOutput: onOutput, continuation: continuation)
                queue.append(request)
                startNextIfNeeded()
            }
        } onCancel: {
            Task { await self.cancel(token: token) }
        }
    }

    func shutdown() {
        let pending = queue
        queue.removeAll()
        invalidateProcess()
        finishCurrentWithError(CancellationError())
        for request in pending { request.continuation.resume(throwing: CancellationError()) }
    }

    private func cancel(token: String) {
        if current?.token == token {
            invalidateProcess()
            finishCurrentWithError(CancellationError())
        } else if let index = queue.firstIndex(where: { $0.token == token }) {
            queue.remove(at: index).continuation.resume(throwing: CancellationError())
        }
    }

    private func startNextIfNeeded() {
        guard current == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        current = next
        buffer.removeAll(keepingCapacity: true)
        markerSearchOffset = 0
        emittedCount = 0
        outputBudget.reset()
        do {
            try ensureProcess()
            scheduleTimeout(for: next)
            try send(next)
        } catch {
            invalidateProcess()
            finishCurrentWithError(error)
        }
    }

    private func ensureProcess() throws {
        if let process, process.isRunning {
            return
        }

        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = loadLoginEnvironment ? ["-l"] : ["-f"]
        shell.currentDirectoryURL = lastKnownCwd
        let generation = UUID()
        let budget = ShellOutputBudget()
        outputBudget = budget
        nextOutputSequence = 0
        pendingOutputChunks.removeAll()

        let outPipe = Pipe()
        let inPipe = Pipe()
        shell.standardOutput = outPipe
        shell.standardError = outPipe
        shell.standardInput = inPipe
        guard fcntl(inPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw ShellSessionError(message: "Failed to configure shell input")
        }

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            if data.isEmpty { return }
            switch budget.accept(data.count) {
            case .accept(let sequence):
                Task { await self?.handleData(data, sequence: sequence, generation: generation) }
            case .exceeded:
                Task { await self?.handleOutputLimit(generation: generation) }
            case .discard:
                break
            }
        }

        shell.terminationHandler = { [weak self] process in
            Task { await self?.handleTermination(status: process.terminationStatus, generation: generation) }
        }

        do {
            try shell.run()
            guard getpgid(shell.processIdentifier) == shell.processIdentifier else {
                shell.terminate()
                throw ShellSessionError(message: "Shell process group unavailable")
            }
            process = shell
            processGeneration = generation
            stdinHandle = inPipe.fileHandleForWriting
            stdoutHandle = outPipe.fileHandleForReading
        } catch {
            throw ShellSessionError(message: "Failed to start shell: \(error.localizedDescription)")
        }
    }

    private func send(_ req: PendingCommand) throws {
        guard let stdinHandle, let generation = processGeneration else {
            throw ShellSessionError(message: "Shell stdin unavailable")
        }
        let marker = markerFor(token: req.token)
        let payload = """
\(req.command)
printf "\\n\(marker)%s\\t%s\\n" "$?" "$PWD"
"""
        guard let data = (payload + "\n").data(using: .utf8) else {
            throw ShellSessionError(message: "Failed to encode command")
        }
        let descriptor = fcntl(stdinHandle.fileDescriptor, F_DUPFD_CLOEXEC, 0)
        guard descriptor >= 0 else { throw ShellSessionError(message: "Failed to duplicate shell input") }
        let writer = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { try? writer.close() }
            do {
                try writer.write(contentsOf: data)
            } catch {
                Task { await self?.handleWriteFailure(token: req.token, generation: generation) }
            }
        }
    }

    private func scheduleTimeout(for req: PendingCommand) {
        timeoutTask?.cancel()
        let nanos = UInt64(max(0.1, req.timeoutSec) * 1_000_000_000)
        timeoutTask = Task { [token = req.token] in
            do { try await Task.sleep(nanoseconds: nanos) } catch { return }
            await handleTimeout(token: token)
        }
    }

    private func handleTimeout(token: String) async {
        guard let cur = current, cur.token == token else { return }
        invalidateProcess()
        finishCurrentWithError(ShellSessionError(message: "Process timeout"))
    }

    private func invalidateProcess() {
        clearProcess(killDescendants: true)
    }

    private func clearProcess(killDescendants: Bool) {
        let previousProcess = process
        processGeneration = nil
        process = nil
        stdoutHandle?.readabilityHandler = nil
        try? stdinHandle?.close()
        stdoutHandle = nil
        stdinHandle = nil
        buffer.removeAll(keepingCapacity: false)
        markerSearchOffset = 0
        pendingOutputChunks.removeAll()
        if killDescendants, let previousProcess, previousProcess.isRunning {
            kill(-previousProcess.processIdentifier, SIGKILL)
        }
    }

    private func handleWriteFailure(token: String, generation: UUID) {
        guard processGeneration == generation, current?.token == token else { return }
        invalidateProcess()
        finishCurrentWithError(ShellSessionError(message: "Failed to write to shell"))
    }

    private func handleOutputLimit(generation: UUID) {
        guard processGeneration == generation else { return }
        invalidateProcess()
        finishCurrentWithError(ShellSessionError(message: "Process output limit exceeded"))
    }

    private func handleTermination(status: Int32, generation: UUID) async {
        guard processGeneration == generation else { return }
        clearProcess(killDescendants: false)
        if current != nil {
            finishCurrentWithError(ShellSessionError(message: "Shell terminated (status=\(status))"))
        }
    }

    private func handleData(_ data: Data, sequence: Int, generation: UUID) async {
        guard processGeneration == generation, !data.isEmpty else { return }
        pendingOutputChunks[sequence] = data
        while processGeneration == generation, let chunk = pendingOutputChunks.removeValue(forKey: nextOutputSequence) {
            nextOutputSequence += 1
            consumeData(chunk)
        }
    }

    private func consumeData(_ data: Data) {
        buffer.append(data)
        scheduleStreamFlush()
        guard let cur = current else { return }

        let marker = Data(markerFor(token: cur.token).utf8)
        guard let markerRange = buffer.range(of: marker, in: markerSearchOffset..<buffer.count) else {
            markerSearchOffset = max(0, buffer.count - marker.count)
            return
        }
        markerSearchOffset = markerRange.lowerBound
        guard let newline = buffer[markerRange.upperBound...].firstIndex(of: 10) else { return }
        let before = Data(buffer[..<markerRange.lowerBound])
        let meta = String(decoding: buffer[markerRange.upperBound..<newline], as: UTF8.self)
        buffer = Data(buffer[(newline + 1)...])
        markerSearchOffset = 0
        finishCurrent(output: before, meta: meta)
    }

    private func finishCurrent(output: Data, meta: String) {
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
            cur.continuation.resume(returning: ProcessResult(exitCode: exitCode, stdout: String(decoding: output, as: UTF8.self), stderr: ""))
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
            do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
            await self?.flushStreamOutput()
        }
    }

    private func flushStreamOutput() async {
        streamTask = nil
        guard let cur = current, let onOutput = cur.onOutput else { return }
        let marker = Data(markerFor(token: cur.token).utf8)
        let bufferCount = buffer.count
        if bufferCount <= emittedCount { return }

        var end: Int
        if let range = buffer.range(of: marker) {
            end = range.lowerBound
        } else {
            let safeEnd = bufferCount - marker.count
            if safeEnd <= emittedCount { return }
            end = safeEnd
        }

        while end > emittedCount && end < buffer.count && buffer[end] & 0xc0 == 0x80 { end -= 1 }
        if end <= emittedCount { return }
        let chunk = String(decoding: buffer[emittedCount..<end], as: UTF8.self)
        emittedCount = end
        if !chunk.isEmpty {
            Task { @MainActor in onOutput(chunk) }
        }
    }

    private func flushRemainingOutput(fullOutput: Data, onOutput: (@MainActor @Sendable (String) -> Void)?) {
        guard let onOutput else { return }
        let total = fullOutput.count
        guard total > emittedCount else { return }
        let chunk = String(decoding: fullOutput[emittedCount..<total], as: UTF8.self)
        emittedCount = total
        if !chunk.isEmpty {
            Task { @MainActor in onOutput(chunk) }
        }
    }

}

private final class ShellOutputBudget: @unchecked Sendable {
    enum Decision {
        case accept(Int)
        case exceeded
        case discard
    }

    private let lock = NSLock()
    private var count = 0
    private var exceeded = false
    private var sequence = 0

    func reset() {
        lock.lock()
        count = 0
        exceeded = false
        lock.unlock()
    }

    func accept(_ size: Int) -> Decision {
        lock.lock()
        defer { lock.unlock() }
        guard !exceeded else { return .discard }
        count += size
        if count > ProcessCapture.defaultMaxOutputBytes {
            exceeded = true
            return .exceeded
        }
        defer { sequence += 1 }
        return .accept(sequence)
    }
}
