import Foundation
import Darwin

struct ProcessResult: Equatable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
    var outputTruncated: Bool = false
    var terminationSignal: Int32? = nil

    var combined: String {
        var s = ""
        if !stdout.isEmpty { s += stdout }
        if !stderr.isEmpty {
            if !s.isEmpty, !s.hasSuffix("\n") { s += "\n" }
            s += stderr
        }
        return s
    }
}

enum ProcessCapture {
    static let defaultMaxOutputBytes = 8 * 1024 * 1024

    enum OutputLimitBehavior: Equatable {
        case fail
        case truncate
    }

    enum OutputStream: Hashable {
        case stdout
        case stderr
    }

    static func run(
        _ exe: String,
        _ args: [String],
        cwd: URL?,
        stdin: Data? = nil,
        timeoutSec: Double? = 30.0,
        env: [String: String]? = nil,
        inheritEnvironment: Bool = true,
        maxOutputBytes: Int = defaultMaxOutputBytes,
        outputLimitBehavior: OutputLimitBehavior = .fail,
        cancellation: ProcessCancellation? = nil,
        captureOutput: Bool = true,
        onStart: (@Sendable (Int32) -> Void)? = nil,
        onOutput: (@Sendable (Data, OutputStream) throws -> Void)? = nil
    ) throws -> ProcessResult {
        guard timeoutSec.map({ $0.isFinite && $0 > 0 }) ?? true, maxOutputBytes > 0 else {
            throw failure(400, "Invalid process timeout or output limit")
        }
        if cancellation?.isCancelled == true { throw CancellationError() }
        var environment = inheritEnvironment ? ProcessInfo.processInfo.environment : [:]
        environment.merge(env ?? [:]) { _, value in value }
        guard !exe.utf8.contains(0), !args.contains(where: { $0.utf8.contains(0) }),
              !environment.contains(where: { $0.key.contains("=") || $0.key.utf8.contains(0) || $0.value.utf8.contains(0) }) else {
            throw failure(400, "Invalid process argument or environment")
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        let handles = [outputPipe.fileHandleForReading, outputPipe.fileHandleForWriting,
                       errorPipe.fileHandleForReading, errorPipe.fileHandleForWriting,
                       inputPipe.fileHandleForReading, inputPipe.fileHandleForWriting]
        defer { for handle in handles { try? handle.close() } }
        for handle in handles {
            guard fcntl(handle.fileDescriptor, F_SETFD, FD_CLOEXEC) != -1 else { throw posixFailure(errno) }
        }
        for handle in [outputPipe.fileHandleForReading, errorPipe.fileHandleForReading, inputPipe.fileHandleForWriting] {
            guard fcntl(handle.fileDescriptor, F_SETFL, O_NONBLOCK) != -1 else { throw posixFailure(errno) }
        }
        guard fcntl(inputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw posixFailure(errno)
        }

        var actions: posix_spawn_file_actions_t?
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawn_file_actions_adddup2(&actions, inputPipe.fileHandleForReading.fileDescriptor, STDIN_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, outputPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, errorPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO))
        if let cwd {
            #if compiler(>=6.3)
            if #available(macOS 26, *) {
                try check(posix_spawn_file_actions_addchdir(&actions, cwd.path))
            } else {
                try check(posix_spawn_file_actions_addchdir_np(&actions, cwd.path))
            }
            #else
            try check(posix_spawn_file_actions_addchdir_np(&actions, cwd.path))
            #endif
        }
        var attributes: posix_spawnattr_t?
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        var signalMask = sigset_t()
        sigemptyset(&signalMask)
        try check(posix_spawnattr_setsigmask(&attributes, &signalMask))
        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        for signal in [SIGTERM, SIGINT, SIGHUP, SIGPIPE] { sigaddset(&defaultSignals, signal) }
        try check(posix_spawnattr_setsigdefault(&attributes, &defaultSignals))
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_CLOEXEC_DEFAULT)))

        var arguments = ([exe] + args).map { strdup($0) } + [nil]
        var environmentStrings = environment.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for pointer in arguments { free(pointer) }
            for pointer in environmentStrings { free(pointer) }
        }
        let startedAt = ProcessInfo.processInfo.systemUptime
        var processID: pid_t = 0
        try check(posix_spawn(&processID, exe, &actions, &attributes, &arguments, &environmentStrings))
        try? inputPipe.fileHandleForReading.close()
        try? outputPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForWriting.close()

        var reaped = false
        var exited = false
        var status: Int32 = 0
        defer {
            if !reaped {
                kill(-processID, SIGKILL)
                let abandonedProcessID = processID
                DispatchQueue.global(qos: .utility).async {
                    var abandonedStatus: Int32 = 0
                    while waitpid(abandonedProcessID, &abandonedStatus, 0) == -1 && errno == EINTR {}
                }
            }
        }
        onStart?(processID)
        let input = stdin ?? Data()
        var inputOffset = 0
        var inputOpen = true
        var outputOpen = true
        var errorOpen = true
        var output = Data()
        var errorOutput = Data()
        var truncated = false
        var stopError: Error?
        var terminateAt: TimeInterval?
        var forcedStopAt: TimeInterval?
        var drainUntil: TimeInterval?

        while true {
            let now = ProcessInfo.processInfo.systemUptime
            if stopError == nil && !exited {
                if cancellation?.isCancelled == true {
                    stopError = CancellationError()
                } else if let timeoutSec, now - startedAt >= timeoutSec {
                    stopError = failure(408, "Process timeout")
                }
                if stopError != nil {
                    kill(-processID, cancellation?.forceRequested == true ? SIGKILL : SIGTERM)
                    terminateAt = now
                    if inputOpen { try? inputPipe.fileHandleForWriting.close(); inputOpen = false }
                }
            }
            if let terminateAt, !exited, forcedStopAt == nil,
               now - terminateAt >= 0.2 || cancellation?.forceRequested == true {
                kill(-processID, SIGKILL)
                forcedStopAt = now
            }

            if !exited {
                var exitInfo = siginfo_t()
                let waited = waitid(P_PID, id_t(processID), &exitInfo, WEXITED | WNOHANG | WNOWAIT)
                if waited == 0 && exitInfo.si_pid == processID {
                    exited = true
                    kill(-processID, SIGKILL)
                    drainUntil = now + 0.2
                } else if waited == -1 && errno != EINTR {
                    throw posixFailure(errno)
                }
            }
            try drain(outputPipe.fileHandleForReading, into: &output, otherCount: errorOutput.count,
                      open: &outputOpen, limit: maxOutputBytes, truncated: &truncated,
                      captureOutput: captureOutput, stream: .stdout, onOutput: onOutput)
            try drain(errorPipe.fileHandleForReading, into: &errorOutput, otherCount: output.count,
                      open: &errorOpen, limit: maxOutputBytes, truncated: &truncated,
                      captureOutput: captureOutput, stream: .stderr, onOutput: onOutput)

            if inputOpen {
                if inputOffset == input.count || exited {
                    try? inputPipe.fileHandleForWriting.close()
                    inputOpen = false
                } else {
                    let written = input.withUnsafeBytes { bytes in
                        Darwin.write(inputPipe.fileHandleForWriting.fileDescriptor,
                                     bytes.baseAddress!.advanced(by: inputOffset), min(16_384, input.count - inputOffset))
                    }
                    if written > 0 {
                        inputOffset += written
                    } else if written == -1 && errno == EPIPE {
                        try? inputPipe.fileHandleForWriting.close()
                        inputOpen = false
                    } else if written == -1 && errno != EAGAIN && errno != EINTR {
                        throw posixFailure(errno)
                    }
                }
            }
            if exited && ((!outputOpen && !errorOpen) || now >= (drainUntil ?? now)) {
                if outputOpen || errorOpen { truncated = true }
                break
            }
            if let forcedStopAt, now - forcedStopAt >= 1.0 { break }

            var descriptors: [pollfd] = []
            if outputOpen { descriptors.append(pollfd(fd: outputPipe.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)) }
            if errorOpen { descriptors.append(pollfd(fd: errorPipe.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)) }
            if inputOpen { descriptors.append(pollfd(fd: inputPipe.fileHandleForWriting.fileDescriptor, events: Int16(POLLOUT), revents: 0)) }
            _ = descriptors.withUnsafeMutableBufferPointer { poll($0.baseAddress, nfds_t($0.count), 10) }
        }
        if exited {
            var waited: pid_t
            repeat { waited = waitpid(processID, &status, WNOHANG) } while waited == -1 && errno == EINTR
            guard waited == processID else { throw posixFailure(errno) }
            reaped = true
        }
        if let stopError { throw stopError }
        if truncated && outputLimitBehavior == .fail { throw failure(413, "Process output limit exceeded") }
        let signal = status & 0x7f
        return ProcessResult(exitCode: signal == 0 ? (status >> 8) & 0xff : 128 + signal,
                             stdout: String(decoding: output, as: UTF8.self),
                             stderr: String(decoding: errorOutput, as: UTF8.self), outputTruncated: truncated,
                             terminationSignal: signal == 0 ? nil : signal)
    }

    static func runAsync(
        _ exe: String, _ args: [String], cwd: URL?, stdin: Data? = nil,
        timeoutSec: Double? = 30, env: [String: String]? = nil,
        inheritEnvironment: Bool = true, maxOutputBytes: Int = defaultMaxOutputBytes,
        outputLimitBehavior: OutputLimitBehavior = .fail,
        cancellation: ProcessCancellation = ProcessCancellation(),
        captureOutput: Bool = true,
        onStart: (@Sendable (Int32) -> Void)? = nil,
        onOutput: (@Sendable (Data, OutputStream) throws -> Void)? = nil
    ) async throws -> ProcessResult {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result {
                        try run(exe, args, cwd: cwd, stdin: stdin, timeoutSec: timeoutSec, env: env,
                                inheritEnvironment: inheritEnvironment, maxOutputBytes: maxOutputBytes,
                                outputLimitBehavior: outputLimitBehavior, cancellation: cancellation,
                                captureOutput: captureOutput, onStart: onStart, onOutput: onOutput)
                    })
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func drain(_ handle: FileHandle, into data: inout Data, otherCount: Int,
                              open: inout Bool, limit: Int, truncated: inout Bool,
                              captureOutput: Bool, stream: OutputStream,
                              onOutput: (@Sendable (Data, OutputStream) throws -> Void)?) throws {
        guard open else { return }
        var buffer = [UInt8](repeating: 0, count: 16_384)
        for _ in 0..<16 {
            let count = Darwin.read(handle.fileDescriptor, &buffer, buffer.count)
            if count > 0 {
                try onOutput?(Data(buffer.prefix(count)), stream)
                if captureOutput {
                    let remaining = max(0, limit - data.count - otherCount)
                    data.append(contentsOf: buffer.prefix(min(count, remaining)))
                    if count > remaining { truncated = true }
                }
            } else if count == 0 {
                open = false
                return
            } else if errno == EAGAIN || errno == EINTR {
                return
            } else {
                throw posixFailure(errno)
            }
        }
    }

    private static func check(_ result: Int32) throws {
        if result != 0 { throw posixFailure(result) }
    }

    private static func posixFailure(_ code: Int32) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    private static func failure(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "xterminal", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

final class ProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var forced = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    var forceRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return forced
    }

    func cancel(force: Bool = false) {
        lock.lock()
        cancelled = true
        forced = forced || force
        lock.unlock()
    }
}
