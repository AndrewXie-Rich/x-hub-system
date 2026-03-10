import Foundation

@MainActor
final class CommandRunner: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var output: String = ""
    @Published var lastExitCode: Int32? = nil

    private var proc: Process? = nil

    func reset() {
        output = ""
        lastExitCode = nil
    }

    func cancel() {
        proc?.terminate()
    }

    func run(shellCommand: String, cwd: URL?) {
        guard !isRunning else { return }
        reset()
        isRunning = true

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", shellCommand]
        if let cwd {
            p.currentDirectoryURL = cwd
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        func append(_ data: Data) {
            guard !data.isEmpty else { return }
            if let s = String(data: data, encoding: .utf8) {
                output += s
            } else {
                output += String(decoding: data, as: UTF8.self)
            }
        }

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            Task { @MainActor in
                guard self != nil else { return }
                append(data)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            Task { @MainActor in
                guard self != nil else { return }
                append(data)
            }
        }

        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self else { return }
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                self.lastExitCode = proc.terminationStatus
                self.isRunning = false
                self.proc = nil
            }
        }

        do {
            proc = p
            try p.run()
        } catch {
            output += "\n[x-terminal] Failed to run: \(error.localizedDescription)\n"
            isRunning = false
            proc = nil
        }
    }
}
