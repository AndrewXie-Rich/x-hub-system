import XCTest
import Darwin
@testable import RELFlowHub
@testable import RELFlowHubCore

private enum XHubCLITestCaptureError: Error {
    case cannotDuplicateStdout
    case cannotRedirectStdout
}

final class XHubCLIRunnerTests: XCTestCase {
    func testDoctorWritesHubCLIBundleAndReturnsSuccessWithoutFailedChecks() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub_cli_runner_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let outputURL = tempRoot.appendingPathComponent("doctor_output.json")
        let code = XHubCLIRunner.runDoctor(
            arguments: ["XHub", "doctor", "--out-json", outputURL.path],
            status: sampleHealthyRuntimeStatus(),
            blockedCapabilities: [],
            statusURL: URL(fileURLWithPath: "/tmp/ai_runtime_status.json"),
            operatorChannelAdminToken: "",
            operatorChannelGRPCPort: 0
        )

        XCTAssertEqual(code, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let channelOutputURL = tempRoot.appendingPathComponent("xhub_doctor_output_channel_onboarding.redacted.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: channelOutputURL.path))

        let decoded = try JSONDecoder().decode(
            XHubDoctorOutputReport.self,
            from: Data(contentsOf: outputURL)
        )
        XCTAssertEqual(decoded.surface, .hubCLI)
        XCTAssertEqual(decoded.reportPath, outputURL.path)
        XCTAssertEqual(decoded.summary.failed, 0)
        XCTAssertTrue(decoded.readyForFirstTask)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tempRoot.appendingPathComponent("xhub_local_service_snapshot.redacted.json").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tempRoot.appendingPathComponent("xhub_local_service_recovery_guidance.redacted.json").path
            )
        )
        let channelDecoded = try JSONDecoder().decode(
            XHubDoctorOutputReport.self,
            from: Data(contentsOf: channelOutputURL)
        )
        XCTAssertEqual(channelDecoded.surface, .hubCLI)
        XCTAssertEqual(channelDecoded.reportPath, channelOutputURL.path)
        XCTAssertEqual(channelDecoded.bundleKind, .channelOnboardingReadiness)
        XCTAssertEqual(channelDecoded.overallState, .degraded)
        XCTAssertEqual(channelDecoded.checks.map(\.status), [.warn, .warn, .warn])
    }

    func testDoctorReturnsBlockingExitCodeWhenRuntimeIsUnavailable() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub_cli_runner_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let outputURL = tempRoot.appendingPathComponent("doctor_output.json")
        let code = XHubCLIRunner.runDoctor(
            arguments: ["XHub", "doctor", "--out-json", outputURL.path],
            status: nil,
            blockedCapabilities: [],
            statusURL: URL(fileURLWithPath: "/tmp/ai_runtime_status.json"),
            operatorChannelAdminToken: "",
            operatorChannelGRPCPort: 0
        )

        XCTAssertEqual(code, 1)

        let decoded = try JSONDecoder().decode(
            XHubDoctorOutputReport.self,
            from: Data(contentsOf: outputURL)
        )
        XCTAssertEqual(decoded.surface, .hubCLI)
        XCTAssertEqual(decoded.overallState, .blocked)
        XCTAssertEqual(decoded.summary.failed, 1)
        XCTAssertFalse(decoded.readyForFirstTask)

        let channelOutputURL = tempRoot.appendingPathComponent("xhub_doctor_output_channel_onboarding.redacted.json")
        let channelDecoded = try JSONDecoder().decode(
            XHubDoctorOutputReport.self,
            from: Data(contentsOf: channelOutputURL)
        )
        XCTAssertEqual(channelDecoded.surface, .hubCLI)
        XCTAssertEqual(channelDecoded.bundleKind, .channelOnboardingReadiness)
        XCTAssertEqual(channelDecoded.overallState, .degraded)
    }

    func testDoctorPrintsPrimaryAndAdvisoryNextStepsForHealthyRuntime() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub_cli_runner_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let outputURL = tempRoot.appendingPathComponent("doctor_output.json")
        let (code, stdout) = try captureStandardOutput {
            XHubCLIRunner.runDoctor(
                arguments: ["XHub", "doctor", "--out-json", outputURL.path],
                status: sampleHealthyRuntimeStatus(),
                blockedCapabilities: [],
                statusURL: URL(fileURLWithPath: "/tmp/ai_runtime_status.json"),
                operatorChannelAdminToken: "",
                operatorChannelGRPCPort: 0
            )
        }

        XCTAssertEqual(code, 0)
        XCTAssertTrue(stdout.contains("[xhub-doctor] runtime_current_failure_code=provider_partial_readiness"))
        XCTAssertTrue(stdout.contains("[xhub-doctor] runtime_current_failure_issue=provider_readiness"))
        XCTAssertTrue(stdout.contains("[xhub-doctor] runtime_primary_next_step={"))
        XCTAssertTrue(stdout.contains("\"step_id\":\"start_first_task\""))
        XCTAssertTrue(stdout.contains("[xhub-doctor] runtime_blocking_next_step=null"))
        XCTAssertTrue(stdout.contains("[xhub-doctor] runtime_advisory_next_step=null"))
        XCTAssertTrue(stdout.contains("[xhub-doctor] channel_primary_next_step={"))
        XCTAssertTrue(stdout.contains("\"step_id\":\"inspect_operator_channel_diagnostics\""))
        XCTAssertTrue(stdout.contains("[xhub-doctor] channel_blocking_next_step=null"))
        XCTAssertTrue(stdout.contains("[xhub-doctor] channel_advisory_next_step={"))
    }

    func testDoctorPrintsBlockingRepairSummaryWhenRuntimeIsUnavailable() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub_cli_runner_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let outputURL = tempRoot.appendingPathComponent("doctor_output.json")
        let (code, stdout) = try captureStandardOutput {
            XHubCLIRunner.runDoctor(
                arguments: ["XHub", "doctor", "--out-json", outputURL.path],
                status: nil,
                blockedCapabilities: [],
                statusURL: URL(fileURLWithPath: "/tmp/ai_runtime_status.json"),
                operatorChannelAdminToken: "",
                operatorChannelGRPCPort: 0
            )
        }

        XCTAssertEqual(code, 1)
        XCTAssertTrue(stdout.contains("[xhub-doctor] runtime_current_failure_code=runtime_heartbeat_stale"))
        XCTAssertTrue(stdout.contains("[xhub-doctor] runtime_current_failure_issue=runtime_heartbeat"))
        XCTAssertTrue(stdout.contains("[xhub-doctor] runtime_primary_next_step={"))
        XCTAssertTrue(stdout.contains("[xhub-doctor] runtime_blocking_next_step={"))
        XCTAssertTrue(stdout.contains("\"step_id\":\"repair_runtime\""))
        XCTAssertTrue(stdout.contains("\"destination_ref\":\"hub:\\/\\/settings\\/diagnostics\""))
        XCTAssertTrue(stdout.contains("[xhub-doctor] runtime_advisory_next_step=null"))
        XCTAssertTrue(stdout.contains("[xhub-doctor] channel_primary_next_step={"))
        XCTAssertTrue(stdout.contains("\"step_id\":\"inspect_operator_channel_diagnostics\""))
    }

    func testRunIfRequestedReturnsNilForNormalLaunchArguments() {
        XCTAssertNil(XHubCLIRunner.runIfRequested(arguments: ["XHub", "--foreground"]))
    }

    private func sampleHealthyRuntimeStatus() -> AIRuntimeStatus {
        AIRuntimeStatus(
            pid: 2048,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            runtimeVersion: "entry-v2",
            schemaVersion: "xhub.local_runtime_status.v2",
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "fallback_ready",
                    runtimeVersion: "entry-v2",
                    runtimeSource: "user_python_venv",
                    runtimeSourcePath: "/tmp/.venv/bin/python3",
                    runtimeResolutionState: "user_runtime_fallback",
                    runtimeReasonCode: "ready",
                    fallbackUsed: true,
                    availableTaskKinds: ["embedding"],
                    loadedModels: ["bge-small"],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    loadedInstances: [
                        AIRuntimeLoadedInstance(
                            instanceKey: "transformers:bge-small:hash1234",
                            modelId: "bge-small",
                            taskKinds: ["embedding"],
                            loadProfileHash: "hash1234",
                            effectiveContextLength: 8192,
                            effectiveLoadProfile: LocalModelLoadProfile(
                                contextLength: 8192,
                                ttl: 600,
                                parallel: 2,
                                identifier: "cli-a"
                            ),
                            loadedAt: Date().timeIntervalSince1970 - 20,
                            lastUsedAt: Date().timeIntervalSince1970 - 1,
                            residency: "resident",
                            residencyScope: "provider_runtime",
                            deviceBackend: "mps"
                        )
                    ]
                ),
            ],
            providerPacks: [
                AIRuntimeProviderPackStatus(
                    schemaVersion: "xhub.provider_pack_manifest.v1",
                    providerId: "transformers",
                    engine: "hf-transformers",
                    version: "builtin-2026-03-16",
                    supportedFormats: ["hf_transformers"],
                    supportedDomains: ["embedding"],
                    runtimeRequirements: AIRuntimeProviderPackRuntimeRequirements(
                        executionMode: "builtin_python",
                        pythonModules: ["transformers", "torch"]
                    ),
                    minHubVersion: "2026.03",
                    installed: true,
                    enabled: true,
                    packState: "installed",
                    reasonCode: "builtin_pack_registered"
                ),
            ],
            monitorSnapshot: AIRuntimeMonitorSnapshot(
                schemaVersion: "xhub.local_runtime_monitor.v1",
                updatedAt: Date().timeIntervalSince1970,
                providers: [
                    AIRuntimeMonitorProvider(
                        provider: "transformers",
                        ok: true,
                        reasonCode: "fallback_ready",
                        runtimeSource: "user_python_venv",
                        runtimeResolutionState: "user_runtime_fallback",
                        runtimeReasonCode: "ready",
                        fallbackUsed: true,
                        availableTaskKinds: ["embedding"],
                        realTaskKinds: ["embedding"],
                        fallbackTaskKinds: [],
                        unavailableTaskKinds: [],
                        deviceBackend: "mps",
                        lifecycleMode: "warmable",
                        residencyScope: "provider_runtime",
                        loadedInstanceCount: 1,
                        loadedModelCount: 1,
                        activeTaskCount: 0,
                        queuedTaskCount: 0,
                        concurrencyLimit: 2,
                        queueMode: "fifo",
                        queueingSupported: true,
                        oldestWaiterStartedAt: 0,
                        oldestWaiterAgeMs: 0,
                        contentionCount: 0,
                        lastContentionAt: 0,
                        activeMemoryBytes: 2048,
                        peakMemoryBytes: 4096,
                        memoryState: "ok",
                        idleEvictionPolicy: "ttl",
                        lastIdleEvictionReason: "timeout",
                        updatedAt: Date().timeIntervalSince1970
                    ),
                ],
                activeTasks: [],
                loadedInstances: [
                    AIRuntimeLoadedInstance(
                        instanceKey: "transformers:bge-small:hash1234",
                        modelId: "bge-small",
                        taskKinds: ["embedding"],
                        loadProfileHash: "hash1234",
                        effectiveContextLength: 8192,
                        effectiveLoadProfile: LocalModelLoadProfile(
                            contextLength: 8192,
                            ttl: 600,
                            parallel: 2,
                            identifier: "cli-a"
                        ),
                        loadedAt: Date().timeIntervalSince1970 - 20,
                        lastUsedAt: Date().timeIntervalSince1970 - 1,
                        residency: "resident",
                        residencyScope: "provider_runtime",
                        deviceBackend: "mps"
                    ),
                ],
                queue: AIRuntimeMonitorQueue(
                    providerCount: 1,
                    activeTaskCount: 0,
                    queuedTaskCount: 0,
                    providersBusyCount: 0,
                    providersWithQueuedTasksCount: 0,
                    maxOldestWaitMs: 0,
                    contentionCount: 0,
                    lastContentionAt: 0,
                    updatedAt: Date().timeIntervalSince1970
                ),
                lastErrors: [],
                fallbackCounters: AIRuntimeMonitorFallbackCounters(
                    providerCount: 1,
                    fallbackReadyProviderCount: 1,
                    fallbackOnlyProviderCount: 0,
                    fallbackReadyTaskCount: 0,
                    fallbackOnlyTaskCount: 0,
                    taskKindCounts: [:]
                )
            )
        )
    }

    private func captureStandardOutput<T>(_ body: () throws -> T) throws -> (T, String) {
        fflush(stdout)
        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        guard originalStdout >= 0 else { throw XHubCLITestCaptureError.cannotDuplicateStdout }
        var stdoutRestored = false
        guard dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO) >= 0 else {
            close(originalStdout)
            throw XHubCLITestCaptureError.cannotRedirectStdout
        }

        defer {
            fflush(stdout)
            if !stdoutRestored {
                _ = dup2(originalStdout, STDOUT_FILENO)
                stdoutRestored = true
            }
            close(originalStdout)
            try? pipe.fileHandleForWriting.close()
        }

        let value = try body()
        fflush(stdout)
        _ = dup2(originalStdout, STDOUT_FILENO)
        stdoutRestored = true
        try? pipe.fileHandleForWriting.close()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (value, String(decoding: data, as: UTF8.self))
    }
}
