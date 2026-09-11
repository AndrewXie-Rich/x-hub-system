import Foundation
import Darwin

#if !XT_EXECUTION_REGRESSION_MAIN
@testable import XTerminal
#endif

enum ManagedProcessSafetyRegression {
    static func runAll() async throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("xt-managed-regression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        let store = XTManagedProcessStore()
        do {
            try logContract(fixture: fixture)
            try environmentContract()
            try await lifecycleContract(store: store, fixture: fixture)
            try await restartContract(store: store, fixture: fixture)
            try await failedLaunchContract(store: store, fixture: fixture)
            try await snapshotContract(fixture: fixture)
            try await cleanup(store: store, fixture: fixture)
            try FileManager.default.removeItem(at: fixture)
        } catch {
            try? await cleanup(store: store, fixture: fixture)
            try? FileManager.default.removeItem(at: fixture)
            throw error
        }
        print("PASS managed processes: group cleanup, cancellation, restart fencing, bounded logs, environment, unowned PID refusal")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        try ExecutionSafetyRegression.require(condition, message)
    }

    private static func cleanup(store: XTManagedProcessStore, fixture: URL) async throws {
        for record in await store.status(projectRoot: fixture, processId: nil, includeExited: false) {
            _ = try await store.stop(projectRoot: fixture, processId: record.processId, force: true)
        }
    }

    private static func waitUntil(_ message: String, timeout: Double = 5, condition: () async throws -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if try await condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw ExecutionSafetyRegression.Failure(description: message)
    }

    private static func logContract(fixture: URL) throws {
        let url = fixture.appendingPathComponent("bounded.log")
        let log = XTManagedProcessLog(url: url, segmentBytes: 4096)
        try log.append(Data(repeating: 97, count: 60_000))
        try log.append(Data("tail-marker\n".utf8))
        let tail = try log.tail(maxBytes: 64)
        try require(tail.data.count <= 64 && tail.truncated, "Log reads must be bounded and disclose rotation")
        try require(String(decoding: tail.data, as: UTF8.self).hasSuffix("tail-marker\n"), "Log tail must preserve recent output")
        for file in [url, url.appendingPathExtension("previous")] {
            let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
            try require((size?.intValue ?? Int.max) <= 4096, "Each log segment must respect the disk budget")
        }
        let oversized = fixture.appendingPathComponent("legacy.log")
        FileManager.default.createFile(atPath: oversized.path, contents: nil)
        let sparse = try FileHandle(forWritingTo: oversized)
        try sparse.truncate(atOffset: 128 * 1024 * 1024)
        try sparse.close()
        let legacyLog = XTManagedProcessLog(url: oversized, segmentBytes: 4096)
        let boundedTail = try legacyLog.tail(maxBytes: Int.max)
        try require(boundedTail.data.count == XTManagedProcessLog.maximumReadBytes, "Legacy oversized logs must not be read in full")
        try legacyLog.append(Data("rotated".utf8))
        let legacySize = try FileManager.default.attributesOfItem(atPath: oversized.appendingPathExtension("previous").path)[.size] as? NSNumber
        try require(legacySize?.intValue == 4096, "Legacy rotation must not retain an oversized segment")

        let sentinel = fixture.appendingPathComponent("log-sentinel")
        try Data("untouched".utf8).write(to: sentinel)
        let link = fixture.appendingPathComponent("symlink.log")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sentinel)
        do {
            try XTManagedProcessLog(url: link).append(Data("bad".utf8))
            throw ExecutionSafetyRegression.Failure(description: "Log writes must reject symbolic links")
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain {}
        try require(try String(contentsOf: sentinel, encoding: .utf8) == "untouched", "Log symlink target must not change")
    }

    private static func environmentContract() throws {
        let environment = XTManagedProcessEnvironment.make(
            overrides: ["XT_EXPLICIT": "yes"],
            host: ["PATH": "/usr/bin:/bin", "HOME": "/tmp", "API_KEY": "ambient-secret", "SSH_AUTH_SOCK": "ambient-socket", "ZDOTDIR": "/tmp/startup"]
        )
        try require(environment["API_KEY"] == nil && environment["SSH_AUTH_SOCK"] == nil && environment["ZDOTDIR"] == nil,
                    "Managed processes must not inherit ambient credential or shell-configuration variables")
        try require(environment["PATH"] == "/usr/bin:/bin" && environment["XT_EXPLICIT"] == "yes", "PATH and explicit configuration remain available")
    }

    private static func lifecycleContract(store: XTManagedProcessStore, fixture: URL) async throws {
        let marker = fixture.appendingPathComponent("leaked-child")
        let command = "trap '' TERM; (sleep 1; printf leaked > \(ExecutionSafetyRegression.quote(marker.path))) & printf 'ready\\n'; wait"
        let started = try await store.start(projectRoot: fixture, processId: "tree", name: nil,
                                            command: command, cwd: nil, env: [:], restartOnExit: false)
        try require(started.pid != nil, "Managed launch must return an owned PID")
        try await waitUntil("Managed process output was not streamed") {
            try await store.logs(projectRoot: fixture, processId: "tree", tailLines: 20, maxBytes: 4096).text.contains("ready")
        }
        let stopAt = ProcessInfo.processInfo.systemUptime
        let stopped = try await store.stop(projectRoot: fixture, processId: "tree", force: false)
        try require(stopped.status == .exited && stopped.pid == nil, "Stop must wait for owned process cleanup")
        try require(ProcessInfo.processInfo.systemUptime - stopAt < 2, "TERM-resistant managed process must be killed within a bounded interval")
        try await Task.sleep(nanoseconds: 1_100_000_000)
        try require(!FileManager.default.fileExists(atPath: marker.path), "Managed cancellation must kill descendants")

        let naturalMarker = fixture.appendingPathComponent("natural-exit-child")
        _ = try await store.start(projectRoot: fixture, processId: "natural", name: nil,
                                 command: "(sleep 1; touch \(ExecutionSafetyRegression.quote(naturalMarker.path))) & exit 0",
                                 cwd: nil, env: [:], restartOnExit: false)
        try await waitUntil("Natural exit was not observed") {
            await store.status(projectRoot: fixture, processId: "natural", includeExited: true).first?.status == .exited
        }
        try await Task.sleep(nanoseconds: 1_100_000_000)
        try require(!FileManager.default.fileExists(atPath: naturalMarker.path), "Natural parent exit must clean remaining group members")

        _ = try await store.start(projectRoot: fixture, processId: "logs", name: nil,
                                 command: "head -c 3145728 /dev/zero; head -c 3145728 /dev/zero >&2; printf 'output-complete\\n'",
                                 cwd: nil, env: [:], restartOnExit: false)
        try await waitUntil("High-output managed process did not complete") {
            await store.status(projectRoot: fixture, processId: "logs", includeExited: true).first?.status == .exited
        }
        let logs = try await store.logs(projectRoot: fixture, processId: "logs", tailLines: 10, maxBytes: 4096)
        try require(logs.truncated && logs.text.utf8.count <= 4096, "Managed logs must disclose bounded retention")
        let segment = URL(fileURLWithPath: logs.record.logPath)
        for file in [segment, segment.appendingPathExtension("previous")] {
            let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
            try require((size?.intValue ?? Int.max) <= XTManagedProcessLog.defaultSegmentBytes, "Managed process output must stay within two capped segments")
        }
    }

    private static func restartContract(store: XTManagedProcessStore, fixture: URL) async throws {
        _ = try await store.start(projectRoot: fixture, processId: "automatic", name: nil,
                                 command: "printf restart; sleep 0.1; exit 7", cwd: nil, env: [:], restartOnExit: true)
        try await waitUntil("Managed process did not automatically restart") {
            (await store.status(projectRoot: fixture, processId: "automatic", includeExited: true).first?.restartCount ?? 0) >= 1
        }
        _ = try await store.stop(projectRoot: fixture, processId: "automatic", force: true)
        _ = try await store.start(projectRoot: fixture, processId: "restart", name: nil,
                                 command: "printf 'first-generation\\n'; exit 0", cwd: nil, env: [:], restartOnExit: true)
        try await waitUntil("Auto-restart was not scheduled") {
            await store.status(projectRoot: fixture, processId: "restart", includeExited: true).first?.status == .restarting
        }
        _ = try await store.stop(projectRoot: fixture, processId: "restart", force: true)
        _ = try await store.start(projectRoot: fixture, processId: "restart", name: nil,
                                 command: "printf 'replacement\\n'; sleep 5", cwd: nil, env: [:], restartOnExit: false)
        try await Task.sleep(nanoseconds: 700_000_000)
        let current = await store.status(projectRoot: fixture, processId: "restart", includeExited: true).first
        try require(current?.status == .running && current?.restartCount == 0, "Cancelled restart must not mutate a replacement generation")
        _ = try await store.stop(projectRoot: fixture, processId: "restart", force: true)
        try await Task.sleep(nanoseconds: 600_000_000)
        let final = await store.status(projectRoot: fixture, processId: "restart", includeExited: true).first
        try require(final?.status == .exited && final?.pid == nil, "Stopped process must remain stopped")
    }

    private static func failedLaunchContract(store: XTManagedProcessStore, fixture: URL) async throws {
        let cancelledStart = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.start(projectRoot: fixture, processId: "cancelled", name: nil,
                                         command: "touch should-not-run", cwd: nil, env: [:], restartOnExit: false)
        }
        do {
            _ = try await cancelledStart.value
            throw ExecutionSafetyRegression.Failure(description: "Cancelled launch must not spawn")
        } catch is CancellationError {}
        try require(!FileManager.default.fileExists(atPath: fixture.appendingPathComponent("should-not-run").path), "Cancelled launch must not execute command content")

        do {
            _ = try await store.start(projectRoot: fixture, processId: "invalid", name: nil,
                                      command: "true", cwd: nil, env: ["BAD=KEY": "value"], restartOnExit: true)
            throw ExecutionSafetyRegression.Failure(description: "Malformed launch must fail")
        } catch let error as NSError where error.domain == "xterminal" && error.code == 400 {}
        try await waitUntil("Failed launch did not settle") {
            await store.status(projectRoot: fixture, processId: "invalid", includeExited: true).first?.status == .failed
        }
        _ = try await store.start(projectRoot: fixture, processId: "invalid", name: nil,
                                 command: "sleep 5", cwd: nil, env: [:], restartOnExit: false)
        try await Task.sleep(nanoseconds: 600_000_000)
        let current = await store.status(projectRoot: fixture, processId: "invalid", includeExited: true).first
        try require(current?.status == .running && current?.restartCount == 0, "Failed launch must not schedule an obsolete restart")
        _ = try await store.stop(projectRoot: fixture, processId: "invalid", force: true)
    }

    private static func snapshotContract(fixture: URL) async throws {
        let root = fixture.appendingPathComponent("snapshot")
        let context = XTManagedProcessPaths(root: root)
        try FileManager.default.createDirectory(at: context.managedProcessesDir, withIntermediateDirectories: true)
        let record = XTManagedProcessRecord(
            processId: "unowned", name: "Unowned", command: "unused", cwd: ".", env: [:], restartOnExit: true,
            status: .running, pid: getpid(), createdAtMs: 0, startedAtMs: 0, updatedAtMs: 0, exitCode: nil,
            terminationReason: nil, restartCount: 0, lastError: nil, stopRequested: false,
            logPath: fixture.appendingPathComponent("outside-log").path
        )
        let snapshot = XTManagedProcessSnapshot(schemaVersion: XTManagedProcessSnapshot.currentSchemaVersion,
                                                updatedAtMs: 0, processes: [record])
        try JSONEncoder().encode(snapshot).write(to: context.managedProcessesSnapshotURL)
        let reloaded = XTManagedProcessStore()
        do {
            _ = try await reloaded.stop(projectRoot: root, processId: "unowned", force: true)
            throw ExecutionSafetyRegression.Failure(description: "Unowned PID stop must fail explicitly")
        } catch XTManagedProcessStoreError.processOwnershipUnverified {}
        let loaded = await reloaded.status(projectRoot: root, processId: "unowned", includeExited: true).first
        try require(loaded?.status == .failed && loaded?.terminationReason == "ownership_unverified", "Persisted PID must not grant signalling authority")
        try require(loaded?.logPath == context.managedProcessLogURL(processId: "unowned").path, "Persisted log paths must not redirect reads outside the managed log root")
        do {
            _ = try await reloaded.start(projectRoot: root, processId: "unowned", name: nil,
                                        command: "true", cwd: nil, env: [:], restartOnExit: false)
            throw ExecutionSafetyRegression.Failure(description: "Unowned process must not be silently replaced")
        } catch XTManagedProcessStoreError.processOwnershipUnverified {}
        try require(kill(getpid(), 0) == 0, "Unowned process must not receive a signal")
    }
}
