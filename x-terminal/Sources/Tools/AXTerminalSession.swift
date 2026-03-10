import Foundation

// Interactive terminal session for user-driven workflows.
// Note: This is intentionally separate from ShellSession (tool run_command).
// - ShellSession: deterministic, marker-based, non-interactive tool execution for the agent.
// - AXTerminalSession: continuous, interactive stream for the user (Terminal mode).
//
// For MVP we use /usr/bin/script to allocate a PTY for the inner shell, while our app still uses pipes.
// This avoids low-level PTY/controlling-tty complexity and works well for common CLI workflows.
actor AXTerminalSessionManager {
    static let shared = AXTerminalSessionManager()
    private var sessions: [String: AXTerminalSession] = [:]

    func session(root: URL) -> AXTerminalSession {
        let key = root.standardizedFileURL.path
        if let existing = sessions[key] {
            return existing
        }
        let created = AXTerminalSession(root: root)
        sessions[key] = created
        return created
    }

    func stop(root: URL) async {
        let key = root.standardizedFileURL.path
        if let s = sessions[key] {
            await s.stop()
        }
        sessions[key] = nil
    }
}

actor AXTerminalSession {
    private let root: URL
    private var process: Process? = nil
    private var stdinHandle: FileHandle? = nil
    private var stdoutHandle: FileHandle? = nil

    private var onOutput: (@MainActor @Sendable (String) -> Void)? = nil
    private var onExit: (@MainActor @Sendable (Int32) -> Void)? = nil

    init(root: URL) {
        self.root = root
    }

    func start(
        onOutput: (@MainActor @Sendable (String) -> Void)?,
        onExit: (@MainActor @Sendable (Int32) -> Void)?
    ) async throws {
        self.onOutput = onOutput
        self.onExit = onExit

        if let p = process, p.isRunning {
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        // `script` allocates a PTY for the child command (inner shell).
        // file=/dev/null means we only stream via stdout, and -q keeps it quiet.
        p.arguments = ["-q", "/dev/null", "/bin/zsh", "-l"]
        p.currentDirectoryURL = root

        var env = ProcessInfo.processInfo.environment
        // Encourage common terminal behavior; the UI currently strips ANSI sequences for readability.
        if (env["TERM"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            env["TERM"] = "xterm-256color"
        }
        p.environment = env

        let outPipe = Pipe()
        let inPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = outPipe
        p.standardInput = inPipe

        let outFH = outPipe.fileHandleForReading
        outFH.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            if data.isEmpty { return }
            let chunk = String(decoding: data, as: UTF8.self)
            Task { await self?.emit(chunk) }
        }

        p.terminationHandler = { [weak self] proc in
            Task { await self?.handleTermination(status: proc.terminationStatus) }
        }

        do {
            try p.run()
        } catch {
            outFH.readabilityHandler = nil
            throw error
        }

        process = p
        stdinHandle = inPipe.fileHandleForWriting
        stdoutHandle = outFH
    }

    func isRunning() -> Bool {
        process?.isRunning ?? false
    }

    func write(_ text: String) async throws {
        guard let stdinHandle else {
            throw ShellSessionError(message: "Terminal stdin unavailable")
        }
        guard let data = text.data(using: .utf8) else { return }
        try stdinHandle.write(contentsOf: data)
    }

    func sendCtrlC() async throws {
        try await write(String(UnicodeScalar(3))) // ETX
    }

    func stop() async {
        stdoutHandle?.readabilityHandler = nil
        stdoutHandle = nil
        stdinHandle = nil
        if let p = process, p.isRunning {
            p.terminate()
        }
        process = nil
    }

    // MARK: - Internals

    private func emit(_ chunk: String) async {
        guard let onOutput else { return }
        Task { @MainActor in onOutput(chunk) }
    }

    private func handleTermination(status: Int32) async {
        stdoutHandle?.readabilityHandler = nil
        stdoutHandle = nil
        stdinHandle = nil
        process = nil
        if let onExit {
            Task { @MainActor in onExit(status) }
        }
    }
}

