import Foundation
import Darwin

#if !XT_EXECUTION_REGRESSION_MAIN
@testable import XTerminal
#endif

enum ExecutionSafetyRegression {
    final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []

        var chunks: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func append(_ chunk: String) {
            lock.lock()
            storage.append(chunk)
            lock.unlock()
        }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    static func expectFailure(_ operation: () throws -> Void, code: Int) throws {
        do {
            try operation()
        } catch let error as NSError where error.domain == "xterminal" && error.code == code {
            return
        }
        throw Failure(description: "Expected xterminal error \(code)")
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func runAll() async throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("xt-execution-regression-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        try captureContract(fixture: fixture)
        print("PASS capture: dual streams, bounded output, stdin, environment, timeout, descendants")
        try await cancellationContract(fixture: fixture)
        print("PASS cancellation: asynchronous execution and task cancellation")
        for estimate in [0.0, 8, 60, Double.infinity, Double.nan] {
            let delay = SupervisorVoiceTimingPolicy.resumeDelay(estimatedPlaybackDuration: estimate)
            try require(SupervisorVoiceTimingPolicy.resumeObservationTimeout - delay >= 2, "Voice smoke must allow capture startup after the maximum resume delay")
        }
        print("PASS voice timing: smoke budget exceeds runtime resume delay")
        try monitorByteContract()
        try await ManagedProcessSafetyRegression.runAll()
        try await monitoringContract(fixture: fixture)
        print("PASS monitoring: sandbox output is delivered incrementally")
        try pathContract(fixture: fixture)
        print("PASS paths: sibling prefixes, symlink reads/writes, missing targets")
        try require(ToolSandboxPolicy.denialCode(mode: .sandbox, requested: false, tool: "run_command") == "sandbox_downgrade_denied", "Model must not downgrade sandbox mode")
        try require(ToolSandboxPolicy.denialCode(mode: .sandbox, requested: nil, tool: "skills.execute.runner") == "sandbox_tool_not_supported", "Unsupported tools must not escape to host")
        try require(ToolSandboxPolicy.usesSandbox(mode: .host, requested: true), "Explicit sandbox request must remain available")
        try await shellContract(fixture: fixture)
        print("PASS shell: state preservation, timeout recovery, cancellation, bounded output")
        try await sandboxContract(fixture: fixture)
        print("PASS sandbox: real OS enforcement, file/network denial, cleanup, limits, resource labels")
    }

    private static func captureContract(fixture: URL) throws {
        let large = try ProcessCapture.run("/bin/zsh", ["-f", "-c", "head -c 1048576 /dev/zero; head -c 1048576 /dev/zero >&2"], cwd: fixture, timeoutSec: 5)
        try require(large.stdout.utf8.count == 1_048_576 && large.stderr.utf8.count == 1_048_576, "Both output streams must drain")
        let bounded = try ProcessCapture.run("/usr/bin/head", ["-c", "1048576", "/dev/zero"], cwd: fixture, maxOutputBytes: 4096, outputLimitBehavior: .truncate)
        try require(bounded.outputTruncated && bounded.stdout.utf8.count == 4096, "Output must be bounded and marked")
        try expectFailure({ _ = try ProcessCapture.run("/usr/bin/head", ["-c", "8192", "/dev/zero"], cwd: fixture, maxOutputBytes: 4096) }, code: 413)
        let input = Data(repeating: 120, count: 1024 * 1024)
        let echoed = try ProcessCapture.run("/bin/zsh", ["-f", "-c", "head -c 1048576 /dev/zero >&2; cat"], cwd: fixture, stdin: input, timeoutSec: 5)
        try require(Data(echoed.stdout.utf8) == input && echoed.stderr.utf8.count == input.count, "stdin must not block output draining")
        let earlyExit = try ProcessCapture.run("/usr/bin/true", [], cwd: fixture, stdin: input)
        try require(earlyExit.exitCode == 0, "Early stdin close must not deliver SIGPIPE to XT")
        let environment = try ProcessCapture.run("/usr/bin/env", [], cwd: fixture, env: ["XT_REGRESSION_VALUE": "present"], inheritEnvironment: false)
        try require(environment.stdout == "XT_REGRESSION_VALUE=present\n", "Explicit environment must not inherit host values")
        try expectFailure({ _ = try ProcessCapture.run("/usr/bin/true", [], cwd: fixture, timeoutSec: .nan) }, code: 400)
        let marker = fixture.appendingPathComponent("late-child")
        let startedAt = ProcessInfo.processInfo.systemUptime
        try expectFailure({
            _ = try ProcessCapture.run("/bin/zsh", ["-f", "-c", "trap '' TERM; (sleep 1; printf leaked > \(quote(marker.path))) & wait"], cwd: fixture, stdin: input, timeoutSec: 0.15)
        }, code: 408)
        try require(ProcessInfo.processInfo.systemUptime - startedAt < 2, "Timeout must be bounded even when TERM is ignored")
        Thread.sleep(forTimeInterval: 1.1)
        try require(!FileManager.default.fileExists(atPath: marker.path), "Timeout must stop descendants")
        let inheritedPipe = try ProcessCapture.run("/bin/zsh", ["-f", "-c", "sleep 5 & exit 0"], cwd: fixture, timeoutSec: 2)
        try require(inheritedPipe.exitCode == 0, "Inherited pipe must not hang after parent exit")
    }

    private static func cancellationContract(fixture: URL) async throws {
        let task = Task { try await ProcessCapture.runAsync("/bin/sleep", ["5"], cwd: fixture) }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do {
            _ = try await task.value
            throw Failure(description: "Cancelled process completed successfully")
        } catch is CancellationError {}
    }

    private static func pathContract(fixture: URL) throws {
        let mapper = try VirtualPathMapper(projectId: UUID(), baseDirectory: fixture)
        try require(!mapper.isValidVirtualPath(mapper.workspaceVirtualPath + "-other/file"), "Virtual sibling prefix must be rejected")
        try require(!mapper.isWithinSandbox(mapper.workspaceRealPath + "-other/file"), "Real sibling prefix must be rejected")
        let outside = fixture.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = URL(fileURLWithPath: mapper.workspaceRealPath).appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        try require(!mapper.isWithinSandbox(link.appendingPathComponent("new-file").path), "Missing target through external symlink must be rejected")
        try require(mapper.isWithinSandbox(URL(fileURLWithPath: mapper.workspaceRealPath).appendingPathComponent("safe-file").path), "Workspace writes must remain available")
        let movedWorkspace = URL(fileURLWithPath: mapper.workspaceRealPath + "-moved")
        try FileManager.default.moveItem(at: URL(fileURLWithPath: mapper.workspaceRealPath), to: movedWorkspace)
        try FileManager.default.createSymbolicLink(atPath: mapper.workspaceRealPath, withDestinationPath: outside.path)
        try require(!mapper.isWithinSandbox(mapper.workspaceRealPath), "Replacing a root with an external symlink must not expand authority")
    }

    @MainActor
    private static func sandboxContract(fixture: URL) async throws {
        let provider = try LocalSandboxProvider(projectId: UUID(), baseDirectory: fixture)
        try await provider.initialize()
        let workspace = URL(fileURLWithPath: provider.toRealPath(provider.workingDirectory))
        let policy = LocalExecutionPolicy(workspace: workspace, readableRoots: [workspace], writableRoots: [workspace], allowNetwork: false)
        let environment = policy.environment(overrides: [:], host: ["API_KEY": "test-secret", "SSH_AUTH_SOCK": "test-socket", "LANG": "C"])
        try require(environment["API_KEY"] == nil && environment["SSH_AUTH_SOCK"] == nil && environment["LANG"] == "C", "Sandbox environment must drop ambient credentials")
        let allowed = try await provider.execute(command: "printf safe > allowed.txt; cat allowed.txt", timeout: 5)
        try require(allowed.isSuccess && allowed.stdout == "safe", "OS sandbox must allow workspace I/O: exit=\(allowed.exitCode) stdout=\(allowed.stdout) stderr=\(allowed.stderr)")
        let script = try await provider.executeScript("printf script-ok", timeout: 5)
        try require(script.isSuccess && script.stdout == "script-ok", "Scripts must use real paths")
        let outside = fixture.appendingPathComponent("outside-secret")
        try Data("private fixture".utf8).write(to: outside)
        let readDenied = try await provider.execute(command: "cat \(quote(outside.path))", timeout: 5)
        try require(!readDenied.isSuccess && !readDenied.stdout.contains("private fixture"), "OS sandbox must deny outside reads")
        let writeDenied = try await provider.execute(command: "printf changed > \(quote(outside.path))", timeout: 5)
        try require(!writeDenied.isSuccess && (try String(contentsOf: outside, encoding: .utf8)) == "private fixture", "OS sandbox must deny outside writes")
        try FileManager.default.createSymbolicLink(at: workspace.appendingPathComponent("outside-link"), withDestinationURL: outside)
        let symlinkDenied = try await provider.execute(command: "cat outside-link", timeout: 5)
        try require(!symlinkDenied.isSuccess && !symlinkDenied.stdout.contains("private fixture"), "OS sandbox must deny symlink escapes")
        let networkDenied = try await provider.execute(command: "curl --noproxy '*' --max-time 1 http://127.0.0.1:9", timeout: 5)
        try require(!networkDenied.isSuccess && networkDenied.stderr.localizedCaseInsensitiveContains("Operation not permitted"), "OS sandbox must deny network sockets: \(networkDenied.stderr)")
        let usage = try await provider.getResourceUsage()
        try require(usage.measurementKind == .estimated, "Estimated metrics must be labeled")
        let execution = Task { @MainActor in try await provider.execute(command: "sleep 5", timeout: 10) }
        try await Task.sleep(nanoseconds: 100_000_000)
        try await provider.cleanup()
        do {
            _ = try await execution.value
            throw Failure(description: "Cleanup must cancel active execution")
        } catch is CancellationError {}
        try require(!provider.isInitialized, "Cleanup must not restore ready status")

        var limitedConfiguration = SandboxConfiguration.default
        limitedConfiguration.maxProcesses = 1
        let limited = try LocalSandboxProvider(projectId: UUID(), configuration: limitedConfiguration, baseDirectory: fixture)
        try await limited.initialize()
        let longExecution = Task { @MainActor in try await limited.execute(command: "sleep 5", timeout: 10) }
        try await Task.sleep(nanoseconds: 100_000_000)
        do {
            _ = try await limited.execute(command: "printf unexpected", timeout: 5)
            throw Failure(description: "Maximum concurrent executions must be enforced")
        } catch SandboxError.resourceLimitExceeded {}
        try await limited.cleanup()
        do { _ = try await longExecution.value } catch is CancellationError {}

        var noFilesConfiguration = SandboxConfiguration.default
        noFilesConfiguration.allowFileSystemAccess = false
        let noFiles = try LocalSandboxProvider(projectId: UUID(), configuration: noFilesConfiguration, baseDirectory: fixture)
        try await noFiles.initialize()
        do {
            try await noFiles.writeFile(path: "forbidden", content: "data")
            throw Failure(description: "File API must enforce allowFileSystemAccess")
        } catch SandboxError.permissionDenied {}
        let noFilesResult = try await noFiles.execute(command: "printf blocked > blocked-file", timeout: 5)
        try require(!noFilesResult.isSuccess, "Shell must enforce disabled workspace access")
        try await noFiles.cleanup()
    }

    @MainActor
    private static func monitoringContract(fixture: URL) async throws {
        let provider = try LocalSandboxProvider(projectId: UUID(), baseDirectory: fixture)
        try await provider.initialize()
        let collector = OutputCollector()
        let acknowledged = URL(fileURLWithPath: provider.toRealPath(provider.workingDirectory)).appendingPathComponent("output-acknowledged")
        let result = try await provider.executeWithMonitoring(
            command: "printf first; while [ ! -f output-acknowledged ]; do sleep 0.01; done; printf second",
            timeout: 5,
            onOutput: { chunk in
                collector.append(chunk)
                if chunk.contains("first") { try? Data().write(to: acknowledged) }
            }
        )
        try require(result.isSuccess && collector.chunks.joined().contains("first") && collector.chunks.joined().contains("second"), "Monitoring must receive command output")
        try require(collector.chunks.count >= 2, "Monitoring must deliver output before command completion")
        try await provider.cleanup()
    }

    private static func monitorByteContract() throws {
        let collector = OutputCollector()
        let monitor = ProcessOutputMonitor(maxBytes: 6, handler: { collector.append($0) })
        monitor.append(Data([0xe4]), stream: .stdout)
        monitor.append(Data("err".utf8), stream: .stderr)
        monitor.append(Data([0xb8, 0xad]), stream: .stdout)
        monitor.append(Data("discarded".utf8), stream: .stdout)
        monitor.finish()
        try require(collector.chunks.joined() == "err中", "Stream monitoring must preserve split UTF-8, separate stderr, and enforce the combined budget")
    }

    private static func shellContract(fixture: URL) async throws {
        let shell = ShellSession(root: fixture, loadLoginEnvironment: false)
        do {
            let result = try await shell.run(command: "export XT_REGRESSION_STATE=kept", timeoutSec: 3)
            try require(result.exitCode == 0, "Shell startup must succeed")
            let state = try await shell.run(command: "printf '%s' \"$XT_REGRESSION_STATE\"", timeoutSec: 3)
            try require(state.stdout.contains("kept"), "Shell environment state must persist")
            let unicode = String(repeating: "终端🙂", count: 50_000)
            try Data(unicode.utf8).write(to: fixture.appendingPathComponent("unicode-output"))
            let unicodeResult = try await shell.run(command: "cat unicode-output", timeoutSec: 3)
            try require(unicodeResult.stdout == unicode + "\n", "Output ordering and UTF-8 must survive pipe chunk boundaries")
            do {
                _ = try await shell.run(command: "sleep 5", timeoutSec: 0.1)
                throw Failure(description: "Shell timeout must fail")
            } catch let error as ShellSessionError {
                try require(error.message == "Process timeout", "Expected shell timeout")
            }
            let recovered = try await shell.run(command: "printf recovered", timeoutSec: 3)
            try require(recovered.stdout.contains("recovered"), "Old shell callbacks must not fail the next command")
            let active = Task { try await shell.run(command: "sleep 0.2; printf active", timeoutSec: 3) }
            try await Task.sleep(nanoseconds: 50_000_000)
            let queued = Task { try await shell.run(command: "printf unexpected > queued-command", timeoutSec: 3) }
            try await Task.sleep(nanoseconds: 30_000_000)
            queued.cancel()
            do {
                _ = try await queued.value
                throw Failure(description: "Queued cancellation must not execute")
            } catch is CancellationError {}
            _ = try await active.value
            try require(!FileManager.default.fileExists(atPath: fixture.appendingPathComponent("queued-command").path), "Cancelled queued command must not run")
            let pending = Task { try await shell.run(command: "sleep 5", timeoutSec: 10) }
            try await Task.sleep(nanoseconds: 100_000_000)
            pending.cancel()
            do {
                _ = try await pending.value
                throw Failure(description: "Shell cancellation must fail")
            } catch is CancellationError {}
            do {
                _ = try await shell.run(command: "head -c 9437184 /dev/zero", timeoutSec: 10)
                throw Failure(description: "Shell output limit must fail")
            } catch let error as ShellSessionError {
                try require(error.message == "Process output limit exceeded", "Expected bounded shell output")
            }
            await shell.shutdown()
        } catch {
            await shell.shutdown()
            throw error
        }
    }
}

#if XT_EXECUTION_REGRESSION_MAIN
@main
struct ExecutionSafetyRegressionMain {
    static func main() async throws {
        do {
            try await ExecutionSafetyRegression.runAll()
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }
}
#endif
