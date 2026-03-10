import Foundation

struct ProcessResult: Equatable {
    var exitCode: Int32
    var stdout: String
    var stderr: String

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
    static func run(
        _ exe: String,
        _ args: [String],
        cwd: URL?,
        stdin: Data? = nil,
        timeoutSec: Double = 30.0,
        env: [String: String]? = nil
    ) throws -> ProcessResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        if let env, !env.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            for (k, v) in env { merged[k] = v }
            p.environment = merged
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        if let stdin {
            let inPipe = Pipe()
            p.standardInput = inPipe
            try p.run()
            inPipe.fileHandleForWriting.write(stdin)
            try? inPipe.fileHandleForWriting.close()
        } else {
            try p.run()
        }

        let deadline = Date().addingTimeInterval(timeoutSec)
        while p.isRunning {
            if Date() > deadline {
                p.terminate()
                throw NSError(domain: "xterminal", code: 408, userInfo: [NSLocalizedDescriptionKey: "Process timeout"])
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        let out = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        let err = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()

        return ProcessResult(
            exitCode: p.terminationStatus,
            stdout: String(decoding: out, as: UTF8.self),
            stderr: String(decoding: err, as: UTF8.self)
        )
    }
}
