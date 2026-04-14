import Foundation
import RELFlowHubCore

private final class XHubCLISynchronizedBox<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

enum XHubCLIRunner {
    private struct PersistedGRPCTokensFile: Decodable {
        var adminTokenCiphertext: String?
        var adminToken: String?
    }

    static let doctorSubcommand = "doctor"
    static let localRuntimeSubcommand = "local-runtime"
    static let outJSONFlag = "--out-json"
    static let commandFlag = "--command"
    static let requestJSONFlag = "--request-json"
    static let timeoutFlag = "--timeout-sec"
    static let baseDirFlag = "--base-dir"

    static func isCLIInvocation(arguments: [String]) -> Bool {
        guard arguments.count > 1 else { return false }
        switch arguments[1] {
        case doctorSubcommand, localRuntimeSubcommand:
            return true
        default:
            return false
        }
    }

    static func runIfRequested(arguments: [String]) -> Int? {
        guard isCLIInvocation(arguments: arguments) else { return nil }
        switch arguments[1] {
        case doctorSubcommand:
            return runDoctor(arguments: arguments)
        case localRuntimeSubcommand:
            return runLocalRuntime(arguments: arguments)
        default:
            return nil
        }
    }

    static func runDoctor(
        arguments: [String],
        status: AIRuntimeStatus? = AIRuntimeStatusStorage.load(),
        blockedCapabilities: [String] = HubLaunchStatusStorage.load()?.degraded.blockedCapabilities ?? [],
        statusURL: URL = AIRuntimeStatusStorage.url(),
        operatorChannelAdminToken: String? = nil,
        operatorChannelGRPCPort: Int? = nil
    ) -> Int {
        if arguments.contains("--help") || arguments.contains("-h") {
            printUsage()
            return 0
        }

        let runtimeOutputURL = outputJSONURL(
            from: arguments,
            defaultURL: XHubDoctorOutputStore.defaultHubReportURL()
        )
        let channelOutputURL = XHubDoctorOutputStore.defaultHubChannelOnboardingReportURL(
            baseDir: runtimeOutputURL.deletingLastPathComponent()
        )
        let resolvedOperatorChannel = resolveOperatorChannelContext(
            adminTokenOverride: operatorChannelAdminToken,
            grpcPortOverride: operatorChannelGRPCPort
        )
        let exportResult = waitForUnifiedDoctorReports(
            status: status,
            blockedCapabilities: blockedCapabilities,
            statusURL: statusURL,
            operatorChannelAdminToken: resolvedOperatorChannel.adminToken,
            operatorChannelGRPCPort: resolvedOperatorChannel.grpcPort,
            runtimeOutputURL: runtimeOutputURL,
            channelOutputURL: channelOutputURL
        )

        guard FileManager.default.fileExists(atPath: exportResult.runtimeReportPath),
              FileManager.default.fileExists(atPath: exportResult.channelOnboardingReportPath) else {
            print("[xhub-doctor] FAIL: failed to write report")
            print("[xhub-doctor] runtime_output=\(runtimeOutputURL.path)")
            print("[xhub-doctor] channel_output=\(channelOutputURL.path)")
            return 2
        }

        let decoder = JSONDecoder()
        guard let runtimeReport = try? decoder.decode(
            XHubDoctorOutputReport.self,
            from: Data(contentsOf: runtimeOutputURL)
        ), let channelReport = try? decoder.decode(
            XHubDoctorOutputReport.self,
            from: Data(contentsOf: channelOutputURL)
        ) else {
            print("[xhub-doctor] FAIL: failed to decode report")
            print("[xhub-doctor] runtime_output=\(runtimeOutputURL.path)")
            print("[xhub-doctor] channel_output=\(channelOutputURL.path)")
            return 2
        }

        print("[xhub-doctor] runtime_source=\(runtimeReport.sourceReportPath)")
        print("[xhub-doctor] runtime_output=\(runtimeReport.reportPath)")
        print(
            "[xhub-doctor] runtime_overall_state=\(runtimeReport.overallState.rawValue) ready_for_first_task=\(runtimeReport.readyForFirstTask ? "yes" : "no") failed=\(runtimeReport.summary.failed) warned=\(runtimeReport.summary.warned)"
        )
        printReportGuidance(prefix: "runtime", report: runtimeReport)
        print("[xhub-doctor] channel_source=\(channelReport.sourceReportPath)")
        print("[xhub-doctor] channel_output=\(channelReport.reportPath)")
        print(
            "[xhub-doctor] channel_overall_state=\(channelReport.overallState.rawValue) ready_for_first_task=\(channelReport.readyForFirstTask ? "yes" : "no") failed=\(channelReport.summary.failed) warned=\(channelReport.summary.warned)"
        )
        printReportGuidance(prefix: "channel", report: channelReport)
        print("[xhub-doctor] local_service_snapshot=\(exportResult.localServiceSnapshotPath)")
        print("[xhub-doctor] local_service_recovery_guidance=\(exportResult.localServiceRecoveryGuidancePath)")

        return (runtimeReport.summary.failed == 0 && channelReport.summary.failed == 0) ? 0 : 1
    }

    private static func printUsage() {
        print("usage: XHub doctor [--out-json /path/to/report.json]")
        print("writes normalized runtime + operator-channel xhub.doctor_output.v1 reports plus CLI repair summaries for the current Hub state")
        print("")
        print("usage: XHub local-runtime --command <command> --request-json /path/to/request.json [--base-dir /path/to/base_dir] [--out-json /path/to/output.json] [--timeout-sec 45]")
        print("runs a local runtime JSON command through Hub's native command runner so helper preflight and launch resolution match the app")
    }

    private static func outputJSONURL(from arguments: [String], defaultURL: URL) -> URL {
        guard let value = argumentValue(after: outJSONFlag, in: arguments) else {
            return defaultURL
        }
        return URL(
            fileURLWithPath: NSString(string: value).expandingTildeInPath,
            isDirectory: false
        )
    }

    private static func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let idx = arguments.firstIndex(of: flag) else { return nil }
        let next = arguments.index(after: idx)
        guard next < arguments.endIndex else { return nil }
        let value = arguments[next].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return value
    }

    private static func waitForUnifiedDoctorReports(
        status: AIRuntimeStatus?,
        blockedCapabilities: [String],
        statusURL: URL,
        operatorChannelAdminToken: String,
        operatorChannelGRPCPort: Int,
        runtimeOutputURL: URL,
        channelOutputURL: URL
    ) -> HubDiagnosticsBundleExporter.UnifiedDoctorReportsResult {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = XHubCLISynchronizedBox<HubDiagnosticsBundleExporter.UnifiedDoctorReportsResult?>(nil)
        Task.detached(priority: .utility) {
            resultBox.value = await HubDiagnosticsBundleExporter.exportUnifiedDoctorReports(
                status: status,
                blockedCapabilities: blockedCapabilities,
                statusURL: statusURL,
                operatorChannelAdminToken: operatorChannelAdminToken,
                operatorChannelGRPCPort: operatorChannelGRPCPort,
                runtimeOutputURL: runtimeOutputURL,
                channelOutputURL: channelOutputURL,
                surface: .hubCLI
            )
            semaphore.signal()
        }
        semaphore.wait()
        return resultBox.value ?? HubDiagnosticsBundleExporter.UnifiedDoctorReportsResult(
            runtimeReportPath: runtimeOutputURL.path,
            channelOnboardingReportPath: channelOutputURL.path,
            localServiceSnapshotPath: runtimeOutputURL
                .deletingLastPathComponent()
                .appendingPathComponent("xhub_local_service_snapshot.redacted.json").path,
            localServiceRecoveryGuidancePath: runtimeOutputURL
                .deletingLastPathComponent()
                .appendingPathComponent("xhub_local_service_recovery_guidance.redacted.json").path
        )
    }

    private static func resolveOperatorChannelContext(
        adminTokenOverride: String?,
        grpcPortOverride: Int?
    ) -> (adminToken: String, grpcPort: Int) {
        (
            adminTokenOverride ?? loadPersistedOperatorChannelAdminToken(),
            grpcPortOverride ?? loadPersistedOperatorChannelGRPCPort()
        )
    }

    private static func loadPersistedOperatorChannelGRPCPort(
        userDefaults: UserDefaults = .standard
    ) -> Int {
        let storedPort = userDefaults.integer(forKey: "relflowhub_grpc_port")
        return storedPort > 0 ? storedPort : 50051
    }

    private static func loadPersistedOperatorChannelAdminToken() -> String {
        let tokensURL = SharedPaths.ensureHubDirectory().appendingPathComponent("hub_grpc_tokens.json")
        guard let data = try? Data(contentsOf: tokensURL),
              let tokens = try? JSONDecoder().decode(PersistedGRPCTokensFile.self, from: data) else {
            return ""
        }

        if let ciphertext = tokens.adminTokenCiphertext?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !ciphertext.isEmpty,
           let decrypted = RemoteSecretsStore.decrypt(ciphertext) {
            return decrypted
        }

        return tokens.adminToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func printReportGuidance(prefix: String, report: XHubDoctorOutputReport) {
        let failureCode = sanitizedCLIValue(report.currentFailureCode)
        let failureIssue = sanitizedCLIValue(report.currentFailureIssue)
        let primaryStep = report.nextSteps.first
        let blockingStep = report.nextSteps.first(where: \.blocking)
        let advisoryStep = report.nextSteps.first(where: { !$0.blocking && $0.kind != .startFirstTask })

        print("[xhub-doctor] \(prefix)_current_failure_code=\(failureCode)")
        print("[xhub-doctor] \(prefix)_current_failure_issue=\(failureIssue)")
        print("[xhub-doctor] \(prefix)_primary_next_step=\(encodedCLIStepSummary(primaryStep))")
        print("[xhub-doctor] \(prefix)_blocking_next_step=\(encodedCLIStepSummary(blockingStep))")
        print("[xhub-doctor] \(prefix)_advisory_next_step=\(encodedCLIStepSummary(advisoryStep))")
    }

    private static func encodedCLIStepSummary(_ step: XHubDoctorOutputNextStep?) -> String {
        guard let step else { return "null" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(step),
              let text = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return text
    }

    private static func sanitizedCLIValue(_ value: String?) -> String {
        let normalized = (value ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "none" : normalized
    }

    static func runLocalRuntime(arguments: [String]) -> Int {
        if arguments.contains("--help") || arguments.contains("-h") {
            printUsage()
            return 0
        }

        guard let command = argumentValue(after: commandFlag, in: arguments) else {
            print("[xhub-local-runtime] FAIL: missing \(commandFlag)")
            printUsage()
            return 2
        }
        guard let requestPath = argumentValue(after: requestJSONFlag, in: arguments) else {
            print("[xhub-local-runtime] FAIL: missing \(requestJSONFlag)")
            printUsage()
            return 2
        }

        let requestURL = URL(
            fileURLWithPath: NSString(string: requestPath).expandingTildeInPath,
            isDirectory: false
        )
        guard let requestData = try? Data(contentsOf: requestURL) else {
            print("[xhub-local-runtime] FAIL: cannot read request_json=\(requestURL.path)")
            return 2
        }

        let providerID = preferredProviderID(from: requestData)
        let resolvedLaunchConfig = MainActor.assumeIsolated {
            HubStore.shared.localRuntimeCommandLaunchConfig(
                preferredProviderID: providerID
            )
        }

        guard var launchConfig = resolvedLaunchConfig else {
            print("[xhub-local-runtime] FAIL: runtime_launch_config_unavailable provider=\(providerID ?? "none")")
            return 2
        }

        if let baseDirOverride = argumentValue(after: baseDirFlag, in: arguments) {
            let normalizedBaseDir = URL(
                fileURLWithPath: NSString(string: baseDirOverride).expandingTildeInPath,
                isDirectory: true
            ).standardizedFileURL.path
            var environment = launchConfig.environment
            environment["REL_FLOW_HUB_BASE_DIR"] = normalizedBaseDir
            launchConfig = LocalRuntimeCommandLaunchConfig(
                executable: launchConfig.executable,
                argumentsPrefix: launchConfig.argumentsPrefix,
                environment: environment,
                baseDirPath: normalizedBaseDir
            )
        }

        let outputURL = outputJSONURL(
            from: arguments,
            defaultURL: requestURL.deletingLastPathComponent().appendingPathComponent("xhub_local_runtime_output.json")
        )
        let timeoutSec = resolvedTimeoutSec(arguments: arguments, command: command)

        do {
            let payloadData = try LocalRuntimeCommandRunner.run(
                command: command,
                requestData: requestData,
                launchConfig: launchConfig,
                timeoutSec: timeoutSec
            )
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try payloadData.write(to: outputURL, options: .atomic)
            print("[xhub-local-runtime] command=\(command)")
            print("[xhub-local-runtime] provider=\(providerID ?? "none")")
            print("[xhub-local-runtime] request_json=\(requestURL.path)")
            print("[xhub-local-runtime] base_dir=\(launchConfig.baseDirPath)")
            print("[xhub-local-runtime] output_json=\(outputURL.path)")
            print("[xhub-local-runtime] timeout_sec=\(String(format: "%.3f", timeoutSec))")
            return 0
        } catch {
            print("[xhub-local-runtime] FAIL: \(error.localizedDescription)")
            print("[xhub-local-runtime] command=\(command)")
            print("[xhub-local-runtime] provider=\(providerID ?? "none")")
            print("[xhub-local-runtime] request_json=\(requestURL.path)")
            print("[xhub-local-runtime] base_dir=\(launchConfig.baseDirPath)")
            return 1
        }
    }

    private static func preferredProviderID(from requestData: Data) -> String? {
        guard let request = (try? JSONSerialization.jsonObject(with: requestData, options: [])) as? [String: Any] else {
            return nil
        }
        let provider = (
            request["provider"] as? String
                ?? request["provider_id"] as? String
                ?? request["providerId"] as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let provider, !provider.isEmpty else {
            return nil
        }
        return provider
    }

    private static func resolvedTimeoutSec(arguments: [String], command: String) -> Double {
        if let rawValue = argumentValue(after: timeoutFlag, in: arguments),
           let parsed = Double(rawValue),
           parsed > 0 {
            return parsed
        }
        return command == "manage-local-model" ? 60.0 : 45.0
    }
}
