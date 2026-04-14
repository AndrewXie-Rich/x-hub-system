import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class XHubLocalServiceRecoveryGuidanceTests: XCTestCase {
    func testBuildReturnsNilWhenNoXHubLocalServiceProviderIsPresent() {
        XCTAssertNil(
            XHubLocalServiceRecoveryGuidanceBuilder.build(
                status: sampleNonManagedRuntimeStatus(),
                blockedCapabilities: []
            )
        )
    }

    func testBuildClassifiesMissingConfigAsConcreteConfigRepair() throws {
        let guidance = try XCTUnwrap(
            XHubLocalServiceRecoveryGuidanceBuilder.build(
                status: sampleManagedRuntimeStatus(
                    reasonCode: "xhub_local_service_config_missing",
                    serviceBaseURL: "",
                    runtimeSourcePath: "",
                    processState: "down",
                    startAttemptCount: 0
                ),
                blockedCapabilities: []
            )
        )

        XCTAssertEqual(guidance.actionCategory, "repair_config")
        XCTAssertEqual(guidance.severity, "high")
        XCTAssertEqual(guidance.primaryIssue.reasonCode, "xhub_local_service_config_missing")
        XCTAssertEqual(guidance.recommendedActions.first?.actionID, "set_loopback_service_base_url")
        XCTAssertTrue(guidance.installHint.contains("runtimeRequirements.serviceBaseUrl"))
        XCTAssertEqual(guidance.serviceBaseURL, "http://127.0.0.1:50171")
        XCTAssertEqual(guidance.repairDestinationRef, "hub://settings/diagnostics")
    }

    func testBuildClassifiesManagedLaunchFailureAsLaunchRepair() throws {
        let guidance = try XCTUnwrap(
            XHubLocalServiceRecoveryGuidanceBuilder.build(
                status: sampleManagedRuntimeStatus(
                    reasonCode: "xhub_local_service_unreachable",
                    processState: "launch_failed",
                    startAttemptCount: 2,
                    lastStartError: "spawn_exit_1"
                ),
                blockedCapabilities: ["ai.embed.local"]
            )
        )

        XCTAssertEqual(guidance.actionCategory, "repair_managed_launch_failure")
        XCTAssertEqual(guidance.severity, "high")
        XCTAssertEqual(guidance.primaryIssue.reasonCode, "xhub_local_service_unreachable")
        XCTAssertEqual(guidance.recommendedActions.first?.actionID, "inspect_managed_launch_error")
        XCTAssertEqual(guidance.recommendedActions.first?.commandOrReference, "spawn_exit_1")
        XCTAssertTrue(guidance.installHint.contains("stderr"))
        XCTAssertTrue(guidance.clipboardText.contains("blocked_capabilities:\nai.embed.local"))
        XCTAssertTrue(guidance.clipboardText.contains("support_faq:"))
    }

    private func sampleNonManagedRuntimeStatus() -> AIRuntimeStatus {
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
                    runtimeSourcePath: "/Users/test/project/.venv/bin/python3",
                    runtimeResolutionState: "user_runtime_fallback",
                    runtimeReasonCode: "ready",
                    fallbackUsed: true,
                    availableTaskKinds: ["embedding"],
                    loadedModels: ["bge-small"],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970
                ),
            ],
            providerPacks: [
                AIRuntimeProviderPackStatus(
                    schemaVersion: "xhub.provider_pack_manifest.v1",
                    providerId: "transformers",
                    engine: "hf-transformers",
                    version: "builtin-2026-03-21",
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
            ]
        )
    }

    private func sampleManagedRuntimeStatus(
        reasonCode: String,
        serviceBaseURL: String = "http://127.0.0.1:50171",
        runtimeSourcePath: String? = nil,
        processState: String = "down",
        startAttemptCount: Int = 1,
        lastStartError: String = "",
        lastProbeError: String = "ConnectionRefusedError:[Errno 61] Connection refused"
    ) -> AIRuntimeStatus {
        let resolvedRuntimeSourcePath = runtimeSourcePath ?? serviceBaseURL
        return AIRuntimeStatus(
            pid: 4096,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            runtimeVersion: "entry-v2",
            schemaVersion: "xhub.local_runtime_status.v2",
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: false,
                    reasonCode: "runtime_missing",
                    runtimeVersion: "entry-v2",
                    runtimeSource: "xhub_local_service",
                    runtimeSourcePath: resolvedRuntimeSourcePath,
                    runtimeResolutionState: "runtime_missing",
                    runtimeReasonCode: reasonCode,
                    fallbackUsed: false,
                    availableTaskKinds: ["embedding", "vision_understand"],
                    loadedModels: [],
                    deviceBackend: "service_proxy",
                    updatedAt: Date().timeIntervalSince1970,
                    managedServiceState: AIRuntimeManagedServiceState(
                        baseURL: serviceBaseURL,
                        bindHost: "127.0.0.1",
                        bindPort: 50171,
                        pid: 43001,
                        processState: processState,
                        startedAtMs: 1_741_800_000_000,
                        lastProbeAtMs: 1_741_800_001_000,
                        lastProbeHTTPStatus: reasonCode == "xhub_local_service_starting" ? 200 : 0,
                        lastProbeError: reasonCode == "xhub_local_service_starting" ? "" : lastProbeError,
                        lastReadyAtMs: 0,
                        lastLaunchAttemptAtMs: 1_741_800_000_500,
                        startAttemptCount: startAttemptCount,
                        lastStartError: lastStartError,
                        updatedAtMs: 1_741_800_001_000
                    )
                ),
            ],
            providerPacks: [
                AIRuntimeProviderPackStatus(
                    schemaVersion: "xhub.provider_pack_manifest.v1",
                    providerId: "transformers",
                    engine: "hf-transformers",
                    version: "builtin-2026-03-21",
                    supportedFormats: ["hf_transformers"],
                    supportedDomains: ["embedding", "vision"],
                    runtimeRequirements: AIRuntimeProviderPackRuntimeRequirements(
                        executionMode: "xhub_local_service",
                        serviceBaseUrl: serviceBaseURL,
                        notes: ["hub_managed_service"]
                    ),
                    minHubVersion: "2026.03",
                    installed: true,
                    enabled: true,
                    packState: "installed",
                    reasonCode: "hub_managed_service_pack_registered"
                ),
            ],
            monitorSnapshot: AIRuntimeMonitorSnapshot(
                schemaVersion: "xhub.local_runtime_monitor.v1",
                updatedAt: Date().timeIntervalSince1970,
                providers: [
                    AIRuntimeMonitorProvider(
                        provider: "transformers",
                        ok: false,
                        reasonCode: "runtime_missing",
                        runtimeSource: "xhub_local_service",
                        runtimeResolutionState: "runtime_missing",
                        runtimeReasonCode: reasonCode,
                        fallbackUsed: false,
                        availableTaskKinds: ["embedding"],
                        realTaskKinds: ["embedding"],
                        fallbackTaskKinds: [],
                        unavailableTaskKinds: ["vision_understand"],
                        deviceBackend: "service_proxy",
                        lifecycleMode: "warmable",
                        residencyScope: "service_runtime",
                        loadedInstanceCount: 0,
                        loadedModelCount: 0,
                        activeTaskCount: 0,
                        queuedTaskCount: 1,
                        concurrencyLimit: 1,
                        queueMode: "fifo",
                        queueingSupported: true,
                        oldestWaiterStartedAt: Date().timeIntervalSince1970 - 2,
                        oldestWaiterAgeMs: 120,
                        contentionCount: 1,
                        lastContentionAt: Date().timeIntervalSince1970 - 1,
                        activeMemoryBytes: 0,
                        peakMemoryBytes: 0,
                        memoryState: "unknown",
                        idleEvictionPolicy: "ttl",
                        lastIdleEvictionReason: "",
                        updatedAt: Date().timeIntervalSince1970
                    ),
                ],
                activeTasks: [],
                loadedInstances: [],
                queue: AIRuntimeMonitorQueue(
                    providerCount: 1,
                    activeTaskCount: 0,
                    queuedTaskCount: 1,
                    providersBusyCount: 0,
                    providersWithQueuedTasksCount: 1,
                    maxOldestWaitMs: 120,
                    contentionCount: 1,
                    lastContentionAt: Date().timeIntervalSince1970 - 1,
                    updatedAt: Date().timeIntervalSince1970
                ),
                lastErrors: [],
                fallbackCounters: AIRuntimeMonitorFallbackCounters(
                    providerCount: 1,
                    fallbackReadyProviderCount: 0,
                    fallbackOnlyProviderCount: 0,
                    fallbackReadyTaskCount: 0,
                    fallbackOnlyTaskCount: 0,
                    taskKindCounts: [:]
                )
            )
        )
    }
}
