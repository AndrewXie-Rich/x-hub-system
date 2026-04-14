import Foundation
import Darwin

enum ProcessWaitSupport {
    private static let waitQueue = DispatchQueue(
        label: "com.rel.flowhub.process-wait",
        qos: .utility,
        attributes: .concurrent
    )

    static func waitForExit(_ process: Process, timeoutSec: Double) -> Bool {
        guard process.isRunning else { return true }

        let semaphore = DispatchSemaphore(value: 0)
        waitQueue.async {
            process.waitUntilExit()
            semaphore.signal()
        }

        let timeout = DispatchTime.now() + max(0.05, timeoutSec)
        if semaphore.wait(timeout: timeout) == .success {
            return true
        }
        return !process.isRunning
    }
}

enum ProcessCaptureSupport {
    private static let leakedProcessLock = NSLock()
    nonisolated(unsafe) private static var leakedProcesses: [Process] = []

    static func runCapture(
        _ executable: String,
        _ arguments: [String],
        env: [String: String] = [:],
        timeoutSec: Double = 1.2
    ) -> (code: Int32, out: String, err: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in env {
            environment[key] = value
        }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return (127, "", String(describing: error))
        }

        var timedOut = !ProcessWaitSupport.waitForExit(process, timeoutSec: timeoutSec)
        if process.isRunning {
            timedOut = true
            process.terminate()
            if process.isRunning && !ProcessWaitSupport.waitForExit(process, timeoutSec: 0.6) {
                let pid = process.processIdentifier
                if pid > 0 {
                    kill(pid, SIGKILL)
                }
                _ = ProcessWaitSupport.waitForExit(process, timeoutSec: 0.6)
            }
        }

        if process.isRunning {
            leakRunningProcess(process)
            return (124, "", "timeout")
        }

        let outData = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
        let errData = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
        try? stdout.fileHandleForReading.close()
        try? stderr.fileHandleForReading.close()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""

        return (
            timedOut ? 124 : process.terminationStatus,
            out.trimmingCharacters(in: .whitespacesAndNewlines),
            err.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func leakRunningProcess(_ process: Process) {
        leakedProcessLock.lock()
        defer { leakedProcessLock.unlock() }
        leakedProcesses.append(process)
        if leakedProcesses.count > 8 {
            leakedProcesses.removeFirst(leakedProcesses.count - 8)
        }
    }
}
