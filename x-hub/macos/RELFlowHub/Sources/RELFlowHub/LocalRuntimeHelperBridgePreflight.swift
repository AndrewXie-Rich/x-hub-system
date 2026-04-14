import Foundation
import Darwin
import RELFlowHubCore

private struct LocalRuntimeHelperBridgePreflightContext: Equatable {
    let providerID: String
    let helperBinaryPath: String
}

private struct LocalRuntimeHelperBridgeProcessResult {
    let terminationStatus: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

enum LocalRuntimeHelperBridgePreflight {
    private static let lmStudioHelperBasenames: Set<String> = ["lms", "llmster", "lmstudio"]
    private static let daemonStatusTimeoutSec: TimeInterval = 3.0
    private static let daemonUpTimeoutSec: TimeInterval = 12.0

    static func performIfNeeded(
        requestData: Data,
        launchConfig: LocalRuntimeCommandLaunchConfig
    ) {
        guard let context = resolveContext(requestData: requestData, launchConfig: launchConfig) else {
            return
        }

        let statusResult = runHelperCommand(
            helperBinaryPath: context.helperBinaryPath,
            arguments: ["daemon", "status", "--json"],
            timeoutSec: daemonStatusTimeoutSec
        )
        if isRunning(statusResult) {
            return
        }

        _ = runHelperCommand(
            helperBinaryPath: context.helperBinaryPath,
            arguments: ["daemon", "up", "--json"],
            timeoutSec: daemonUpTimeoutSec
        )
    }

    private static func resolveContext(
        requestData: Data,
        launchConfig: LocalRuntimeCommandLaunchConfig
    ) -> LocalRuntimeHelperBridgePreflightContext? {
        guard let request = (try? JSONSerialization.jsonObject(with: requestData, options: [])) as? [String: Any],
              let providerID = normalizedProviderID(from: request),
              !providerID.isEmpty else {
            return nil
        }

        let baseDirPath = normalizedPath(launchConfig.baseDirPath)
        guard !baseDirPath.isEmpty else {
            return nil
        }

        let baseDir = URL(fileURLWithPath: baseDirPath, isDirectory: true)
        let snapshot = LocalProviderPackRegistry.load(baseDir: baseDir)
        guard let pack = snapshot.packs.first(where: { $0.providerId == providerID }) else {
            return nil
        }

        let executionMode = pack.runtimeRequirements.executionMode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard executionMode == "helper_binary_bridge" else {
            return nil
        }

        var helperBinaryPath = normalizedPath(pack.runtimeRequirements.helperBinary)
        if helperBinaryPath.isEmpty {
            helperBinaryPath = normalizedPath(LocalHelperBridgeDiscovery.discoverHelperBinary())
        }
        guard isLikelyLMStudioHelperPath(helperBinaryPath),
              FileManager.default.isExecutableFile(atPath: helperBinaryPath) else {
            return nil
        }

        return LocalRuntimeHelperBridgePreflightContext(
            providerID: providerID,
            helperBinaryPath: helperBinaryPath
        )
    }

    private static func normalizedProviderID(from request: [String: Any]) -> String? {
        let provider = (
            request["provider"] as? String
                ?? request["provider_id"] as? String
                ?? request["providerId"] as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return provider?.isEmpty == false ? provider : nil
    }

    private static func normalizedPath(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard !expanded.isEmpty else {
            return ""
        }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private static func isLikelyLMStudioHelperPath(_ path: String) -> Bool {
        let normalized = normalizedPath(path).lowercased()
        guard !normalized.isEmpty else {
            return false
        }
        let basename = (normalized as NSString).lastPathComponent
        return lmStudioHelperBasenames.contains(basename) || normalized.contains("/.lmstudio/bin/")
    }

    private static func isRunning(_ result: LocalRuntimeHelperBridgeProcessResult) -> Bool {
        guard !result.timedOut else {
            return false
        }

        let payloadText = [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        guard !payloadText.isEmpty else {
            return false
        }

        if let data = payloadText.data(using: .utf8),
           let payload = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] {
            let status = (payload["status"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if status == "running" {
                return true
            }
        }

        return result.terminationStatus == 0
            && payloadText.lowercased().contains("\"status\":\"running\"")
    }

    private static func runHelperCommand(
        helperBinaryPath: String,
        arguments: [String],
        timeoutSec: TimeInterval
    ) -> LocalRuntimeHelperBridgeProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperBinaryPath)
        process.arguments = arguments
        process.currentDirectoryURL = SharedPaths.realHomeDirectory()

        var environment = ProcessInfo.processInfo.environment
        let realHome = SharedPaths.realHomeDirectory().path
        environment["HOME"] = realHome
        environment["PWD"] = realHome
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return LocalRuntimeHelperBridgeProcessResult(
                terminationStatus: -1,
                stdout: "",
                stderr: String(describing: error),
                timedOut: false
            )
        }

        var timedOut = false
        if semaphore.wait(timeout: .now() + max(1.0, timeoutSec)) == .timedOut {
            timedOut = true
            process.terminate()
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            _ = semaphore.wait(timeout: .now() + 1.0)
        }

        let stdout = String(
            data: (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(
            data: (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()

        return LocalRuntimeHelperBridgeProcessResult(
            terminationStatus: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            timedOut: timedOut
        )
    }
}
