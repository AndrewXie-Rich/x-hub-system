import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class LocalRuntimeProviderPolicyTests: XCTestCase {
    func testSupportsUnloadStaysOpenForProcessLocalProviderWhenUnloadIsAdvertised() {
        let providerStatus = AIRuntimeProviderStatus(
            provider: "transformers",
            ok: true,
            reasonCode: "ready",
            runtimeVersion: "v2",
            availableTaskKinds: ["embedding"],
            loadedModels: ["embed-local"],
            deviceBackend: "mps",
            updatedAt: Date().timeIntervalSince1970,
            lifecycleMode: "warmable",
            supportedLifecycleActions: ["warmup_local_model", "unload_local_model"],
            warmupTaskKinds: ["embedding"],
            residencyScope: "process_local",
            loadedInstances: []
        )

        XCTAssertTrue(
            LocalRuntimeProviderPolicy.supportsUnload(
                providerID: "transformers",
                taskKinds: ["embedding"],
                providerStatus: providerStatus,
                residencyScope: "process_local",
                residency: "resident"
            )
        )
    }

    func testSupportsUnloadFallsBackForRuntimeResidentInstanceWithoutProviderStatus() {
        XCTAssertTrue(
            LocalRuntimeProviderPolicy.supportsUnload(
                providerID: "transformers",
                taskKinds: ["embedding"],
                providerStatus: nil,
                residencyScope: "provider_runtime",
                residency: "resident"
            )
        )
    }

    func testSupportsUnloadKeepsProcessLocalFallbackClosedWithoutProviderStatus() {
        XCTAssertFalse(
            LocalRuntimeProviderPolicy.supportsUnload(
                providerID: "transformers",
                taskKinds: ["speech_to_text"],
                providerStatus: nil,
                residencyScope: "process_local",
                residency: "resident"
            )
        )
    }

    func testAllowsDaemonProxyForExplicitResidentInstanceWithoutReadyHeartbeat() {
        let requestContext = LocalModelRuntimeRequestContext(
            providerID: "transformers",
            modelID: "hf-embed",
            deviceID: "",
            instanceKey: "transformers:hf-embed:hash1234",
            loadProfileHash: "hash1234",
            predictedLoadProfileHash: "hash1234",
            effectiveContextLength: 8192,
            loadProfileOverride: nil,
            source: "bench_auto_warmup"
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 77,
            updatedAt: 1,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: false,
                    reasonCode: "warming_up",
                    lifecycleMode: "warmable",
                    supportedLifecycleActions: ["warmup_local_model", "unload_local_model"],
                    warmupTaskKinds: ["embedding"],
                    residencyScope: "provider_runtime",
                    loadedInstances: []
                )
            ]
        )

        XCTAssertTrue(
            LocalRuntimeProviderPolicy.allowsDaemonProxy(
                providerID: "transformers",
                runtimeStatus: runtimeStatus,
                requestContext: requestContext
            )
        )
    }

    func testAllowsDaemonProxyStaysClosedWithoutResidentInstanceOrReadyHeartbeat() {
        let requestContext = LocalModelRuntimeRequestContext(
            providerID: "transformers",
            modelID: "hf-embed",
            deviceID: "",
            instanceKey: "",
            loadProfileHash: "",
            predictedLoadProfileHash: "hash1234",
            effectiveContextLength: 8192,
            loadProfileOverride: nil,
            source: "paired_terminal_default"
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 88,
            updatedAt: 1,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: false,
                    reasonCode: "runtime_missing",
                    lifecycleMode: "warmable",
                    supportedLifecycleActions: ["warmup_local_model", "unload_local_model"],
                    warmupTaskKinds: ["embedding"],
                    residencyScope: "provider_runtime",
                    loadedInstances: []
                )
            ]
        )

        XCTAssertFalse(
            LocalRuntimeProviderPolicy.allowsDaemonProxy(
                providerID: "transformers",
                runtimeStatus: runtimeStatus,
                requestContext: requestContext
            )
        )
    }
}
