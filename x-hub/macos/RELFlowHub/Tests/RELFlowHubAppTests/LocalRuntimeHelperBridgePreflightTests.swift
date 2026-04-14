import XCTest
@testable import RELFlowHub

final class LocalRuntimeHelperBridgePreflightTests: XCTestCase {
    func testRunPreflightsLMStudioHelperDaemonBeforeRuntimeCommand() throws {
        let baseDir = try makeTempDir()
        let readyFile = baseDir.appendingPathComponent("helper.ready")
        let helperLog = baseDir.appendingPathComponent("helper.log")
        let helperBinary = try makeHelperBinary(logFile: helperLog, readyFile: readyFile)
        let runtimeBinary = try makeRuntimeBinary(requiredReadyFile: readyFile)

        try writePackRegistry(
            baseDir: baseDir,
            providerID: "llama.cpp",
            executionMode: "helper_binary_bridge",
            helperBinaryPath: helperBinary.path
        )

        let requestData = try JSONSerialization.data(
            withJSONObject: ["provider": "llama.cpp"],
            options: []
        )
        let payloadData = try LocalRuntimeCommandRunner.run(
            command: "run-local-bench",
            requestData: requestData,
            launchConfig: LocalRuntimeCommandLaunchConfig(
                executable: runtimeBinary.path,
                argumentsPrefix: [],
                environment: [:],
                baseDirPath: baseDir.path
            ),
            timeoutSec: 5.0
        )

        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payloadData, options: []) as? [String: Any]
        )
        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(try readLines(from: helperLog), [
            "daemon status --json",
            "daemon up --json",
        ])
        XCTAssertTrue(FileManager.default.fileExists(atPath: readyFile.path))
    }

    func testRunDoesNotRestartLMStudioHelperWhenDaemonIsAlreadyRunning() throws {
        let baseDir = try makeTempDir()
        let readyFile = baseDir.appendingPathComponent("helper.ready")
        let helperLog = baseDir.appendingPathComponent("helper.log")
        let helperBinary = try makeHelperBinary(logFile: helperLog, readyFile: readyFile)
        let runtimeBinary = try makeRuntimeBinary(requiredReadyFile: readyFile)
        try Data().write(to: readyFile)

        try writePackRegistry(
            baseDir: baseDir,
            providerID: "llama.cpp",
            executionMode: "helper_binary_bridge",
            helperBinaryPath: helperBinary.path
        )

        let requestData = try JSONSerialization.data(
            withJSONObject: ["provider": "llama.cpp"],
            options: []
        )
        _ = try LocalRuntimeCommandRunner.run(
            command: "manage-local-model",
            requestData: requestData,
            launchConfig: LocalRuntimeCommandLaunchConfig(
                executable: runtimeBinary.path,
                argumentsPrefix: [],
                environment: [:],
                baseDirPath: baseDir.path
            ),
            timeoutSec: 5.0
        )

        XCTAssertEqual(try readLines(from: helperLog), [
            "daemon status --json",
        ])
    }

    func testRunSkipsHelperPreflightForNonHelperProviders() throws {
        let baseDir = try makeTempDir()
        let helperLog = baseDir.appendingPathComponent("helper.log")
        let helperBinary = try makeHelperBinary(
            logFile: helperLog,
            readyFile: baseDir.appendingPathComponent("helper.ready")
        )
        let runtimeBinary = try makeRuntimeBinary(requiredReadyFile: nil)

        try writePackRegistry(
            baseDir: baseDir,
            providerID: "transformers",
            executionMode: "builtin_python",
            helperBinaryPath: helperBinary.path
        )

        let requestData = try JSONSerialization.data(
            withJSONObject: ["provider": "transformers"],
            options: []
        )
        let payloadData = try LocalRuntimeCommandRunner.run(
            command: "run-local-task",
            requestData: requestData,
            launchConfig: LocalRuntimeCommandLaunchConfig(
                executable: runtimeBinary.path,
                argumentsPrefix: [],
                environment: [:],
                baseDirPath: baseDir.path
            ),
            timeoutSec: 5.0
        )

        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payloadData, options: []) as? [String: Any]
        )
        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: helperLog.path))
    }

    private func writePackRegistry(
        baseDir: URL,
        providerID: String,
        executionMode: String,
        helperBinaryPath: String
    ) throws {
        let snapshot = LocalProviderPackRegistrySnapshot(
            schemaVersion: LocalProviderPackRegistry.schemaVersion,
            updatedAt: 1,
            packs: [
                LocalProviderPackRegistryEntry(
                    providerId: providerID,
                    runtimeRequirements: LocalProviderPackRegistryRuntimeRequirements(
                        executionMode: executionMode,
                        helperBinary: helperBinaryPath
                    ),
                    installed: true,
                    enabled: true,
                    packState: "installed",
                    reasonCode: "test_fixture"
                ),
            ]
        )
        LocalProviderPackRegistry.save(snapshot, baseDir: baseDir)
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeHelperBinary(logFile: URL, readyFile: URL) throws -> URL {
        let directory = try makeTempDir()
        let binary = directory.appendingPathComponent("lms")
        let script = """
        #!/bin/sh
        set -eu
        LOG_FILE=\(shellSingleQuoted(logFile.path))
        READY_FILE=\(shellSingleQuoted(readyFile.path))
        printf '%s\\n' "$*" >> "$LOG_FILE"
        if [ "$#" -ge 3 ] && [ "$1" = "daemon" ] && [ "$2" = "status" ] && [ "$3" = "--json" ]; then
          if [ -f "$READY_FILE" ]; then
            printf '{"status":"running","pid":111,"isDaemon":true}\\n'
            exit 0
          fi
          printf '{"status":"stopped"}\\n'
          exit 1
        fi
        if [ "$#" -ge 3 ] && [ "$1" = "daemon" ] && [ "$2" = "up" ] && [ "$3" = "--json" ]; then
          : > "$READY_FILE"
          printf '{"status":"running","pid":111,"isDaemon":true}\\n'
          exit 0
        fi
        printf '{"status":"unexpected"}\\n' >&2
        exit 2
        """
        try writeExecutable(script, to: binary)
        return binary
    }

    private func makeRuntimeBinary(requiredReadyFile: URL?) throws -> URL {
        let directory = try makeTempDir()
        let binary = directory.appendingPathComponent("fake-runtime")
        let readyFile = requiredReadyFile?.path ?? ""
        let script = """
        #!/bin/sh
        set -eu
        READY_FILE=\(shellSingleQuoted(readyFile))
        cat >/dev/null
        if [ -n "$READY_FILE" ] && [ ! -f "$READY_FILE" ]; then
          printf 'daemon not ready\\n' >&2
          exit 9
        fi
        printf '{"ok":true,"source":"runtime"}\\n'
        """
        try writeExecutable(script, to: binary)
        return binary
    }

    private func writeExecutable(_ content: String, to url: URL) throws {
        let data = try XCTUnwrap(content.data(using: .utf8))
        try data.write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
    }

    private func readLines(from url: URL) throws -> [String] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return content
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
