import Combine
import Foundation

@MainActor
final class TerminalSessionModel: ObservableObject {
    @Published var output: String = ""
    @Published var draft: String = ""
    @Published var isRunning: Bool = false
    @Published var lastExitCode: Int32? = nil
    @Published var lastError: String? = nil

    private let root: URL
    private var flushTask: Task<Void, Never>? = nil
    private var pending: String = ""

    private let maxOutputChars = 240_000

    init(root: URL) {
        self.root = root
    }

    func ensureStarted() {
        Task {
            do {
                let session = await AXTerminalSessionManager.shared.session(root: root)
                try await session.start(
                    onOutput: { [weak self] chunk in
                        self?.appendOutput(chunk)
                    },
                    onExit: { [weak self] code in
                        self?.isRunning = false
                        self?.lastExitCode = code
                    }
                )
                isRunning = await session.isRunning()
            } catch {
                lastError = String(describing: error)
                isRunning = false
            }
        }
    }

    func stop() {
        Task {
            await AXTerminalSessionManager.shared.stop(root: root)
            isRunning = false
        }
    }

    func sendLine() {
        let line = draft
        draft = ""
        send(text: line + "\n")
    }

    func send(text: String) {
        Task {
            do {
                let session = await AXTerminalSessionManager.shared.session(root: root)
                if !(await session.isRunning()) {
                    try await session.start(
                        onOutput: { [weak self] chunk in self?.appendOutput(chunk) },
                        onExit: { [weak self] code in
                            self?.isRunning = false
                            self?.lastExitCode = code
                        }
                    )
                }
                try await session.write(text)
                isRunning = await session.isRunning()
            } catch {
                lastError = String(describing: error)
                isRunning = false
            }
        }
    }

    func sendCtrlC() {
        Task {
            do {
                let session = await AXTerminalSessionManager.shared.session(root: root)
                try await session.sendCtrlC()
            } catch {
                lastError = String(describing: error)
            }
        }
    }

    func clearOutput() {
        output = ""
        pending = ""
        flushTask?.cancel()
        flushTask = nil
    }

    // MARK: - Output handling

    private func appendOutput(_ chunk: String) {
        let cleaned = sanitize(chunk)
        guard !cleaned.isEmpty else { return }
        appendWithBackspaceHandling(cleaned)
        scheduleFlush()
    }

    private func scheduleFlush() {
        if flushTask != nil { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            await MainActor.run {
                self?.flushNow()
            }
        }
    }

    private func flushNow() {
        flushTask = nil
        if pending.isEmpty { return }
        output += pending
        pending = ""

        if output.count > maxOutputChars {
            output = "[x-terminal] output truncated (keeping last \(maxOutputChars) chars)\n" + String(output.suffix(maxOutputChars))
        }
    }

    private func sanitize(_ s: String) -> String {
        if s.isEmpty { return "" }
        // Keep bare carriage returns (\r). We'll interpret them during append to emulate
        // "return-to-line-start" behavior used by interactive shells and progress output.
        let normalized = s.replacingOccurrences(of: "\r\n", with: "\n")
        let noANSI = stripANSI(from: normalized)
        return filterControlChars(noANSI)
    }

    private func stripANSI(from s: String) -> String {
        // Basic CSI escape stripper: ESC [ ... command
        // This is not a full terminal emulator; it just makes logs readable.
        let esc = "\u{001B}"
        if !s.contains(esc) { return s }

        // Regex: \x1B\[[0-?]*[ -/]*[@-~]
        let pattern = "\(esc)\\[[0-?]*[ -/]*[@-~]"
        if let re = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            let out = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
            return out
        }
        return s
    }

    private func filterControlChars(_ s: String) -> String {
        // Keep: \n \t \r and backspace/del (handled later).
        // Drop other C0 controls to avoid rendering artifacts in the transcript.
        if s.isEmpty { return "" }
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x09, 0x0A, 0x0D: // \t \n \r
                out.unicodeScalars.append(scalar)
            case 0x08, 0x7F: // backspace, del
                out.unicodeScalars.append(scalar)
            case 0x00...0x1F:
                // Drop.
                continue
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    private func appendWithBackspaceHandling(_ s: String) {
        // Many interactive programs/shells use backspace to edit the current line.
        // Render it by actually deleting previous characters from pending/output buffers.
        // Also interpret carriage return (\r) as "rewind to line start" to avoid showing
        // terminal cursor mechanics as weird newlines in our plain-text transcript.
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if v == 0x0D { // \r
                rewindToLineStart()
                continue
            }
            if v == 0x08 || v == 0x7F {
                if !pending.isEmpty {
                    pending.removeLast()
                } else if !output.isEmpty {
                    output.removeLast()
                }
                continue
            }
            pending.unicodeScalars.append(scalar)
        }
    }

    private func rewindToLineStart() {
        if let idx = pending.lastIndex(of: "\n") {
            pending = String(pending[..<pending.index(after: idx)])
            return
        }
        if let idx = output.lastIndex(of: "\n") {
            output = String(output[..<output.index(after: idx)])
            pending = ""
            return
        }
        output = ""
        pending = ""
    }
}
