import XCTest
@testable import RELFlowHub
import RELFlowHubCore

final class DiscoverModelMarketLifecyclePlannerTests: XCTestCase {
    func testStatusIsNotDownloadedWhenFilesAreMissing() {
        let status = DiscoverModelMarketLifecyclePlanner.status(
            for: makeMarketResult(downloaded: false, inLibrary: false),
            matchingModel: nil
        ) { _ in
            XCTFail("runtime readiness should not be evaluated")
            return .ready()
        }

        XCTAssertEqual(status, .notDownloaded)
    }

    func testStatusShowsDownloadedBeforeImport() {
        let status = DiscoverModelMarketLifecyclePlanner.status(
            for: makeMarketResult(downloaded: true, inLibrary: false),
            matchingModel: nil
        ) { _ in
            XCTFail("runtime readiness should not be evaluated")
            return .ready()
        }

        XCTAssertEqual(
            status,
            DiscoverModelMarketLifecycleStatus(
                isDownloaded: true,
                isImported: false,
                runtimeReadiness: nil,
                health: nil,
                isHealthScanning: false,
                verificationStage: nil,
                matchingModelID: nil
            )
        )
    }

    func testStatusShowsImportedWhileVerificationIsPending() {
        let status = DiscoverModelMarketLifecyclePlanner.status(
            for: makeMarketResult(downloaded: true, inLibrary: true),
            matchingModel: nil
        ) { _ in
            XCTFail("runtime readiness should not be evaluated")
            return .ready()
        }

        XCTAssertEqual(status.verificationStage, .pendingVerification)
        XCTAssertNil(status.runtimeReadiness)
    }

    func testStatusKeepsUnverifiedModelPendingInsteadOfRuntimeUnavailable() {
        let status = DiscoverModelMarketLifecyclePlanner.status(
            for: makeMarketResult(downloaded: true, inLibrary: true),
            matchingModel: makeHubModel(id: "hexgrad/kokoro-82m"),
            health: nil
        ) { _ in
            XCTFail("runtime readiness should not be evaluated until health exists")
            return .unavailable("provider down")
        }

        XCTAssertEqual(status.verificationStage, .pendingVerification)
        XCTAssertNil(status.runtimeReadiness)
        XCTAssertEqual(status.matchingModelID, "hexgrad/kokoro-82m")
    }

    func testStatusShowsReviewForDegradedHealthWithoutRuntimeUnavailable() {
        let status = DiscoverModelMarketLifecyclePlanner.status(
            for: makeMarketResult(downloaded: true, inLibrary: true),
            matchingModel: makeHubModel(id: "hexgrad/kokoro-82m"),
            health: makeHealth(state: .degraded, detail: "预检通过，等待试跑")
        ) { _ in
            XCTFail("runtime readiness should not be evaluated for review state")
            return .unavailable("provider down")
        }

        XCTAssertEqual(status.verificationStage, .needsReview)
        XCTAssertNil(status.runtimeReadiness)
        XCTAssertEqual(status.health?.detail, "预检通过，等待试跑")
    }

    func testStatusMarksImportedModelReadyAfterHealthyScan() {
        let status = DiscoverModelMarketLifecyclePlanner.status(
            for: makeMarketResult(downloaded: true, inLibrary: true),
            matchingModel: makeHubModel(id: "hexgrad/kokoro-82m"),
            health: makeHealth(state: .healthy, detail: "轻量扫描通过")
        ) { _ in
            .ready("Imported and ready for local Hub voice playback.")
        }

        XCTAssertEqual(status.verificationStage, .ready)
        XCTAssertEqual(status.runtimeReadiness, .ready("Imported and ready for local Hub voice playback."))
    }

    func testStatusMarksImportedModelRuntimeUnavailableAfterBlockedHealth() {
        let status = DiscoverModelMarketLifecyclePlanner.status(
            for: makeMarketResult(downloaded: true, inLibrary: true),
            matchingModel: makeHubModel(id: "hexgrad/kokoro-82m"),
            health: makeHealth(state: .blockedRuntime, detail: "Hub could not resolve a local runtime launch configuration for transformers.")
        ) { _ in
            XCTFail("blocked health should provide the lifecycle detail")
            return .ready()
        }

        XCTAssertEqual(status.verificationStage, .runtimeUnavailable)
        XCTAssertEqual(
            status.runtimeReadiness,
            .unavailable("Hub could not resolve a local runtime launch configuration for transformers.")
        )
    }

    private func makeMarketResult(downloaded: Bool, inLibrary: Bool) -> LMStudioMarketResult {
        LMStudioMarketResult(
            modelKey: "hexgrad/kokoro-82m",
            title: "Kokoro",
            summary: "",
            formatHint: "transformers",
            capabilityTags: ["Voice"],
            staffPick: false,
            recommendationReason: "",
            recommendedForThisMac: true,
            recommendedFitEstimation: "fullGPUOffload",
            recommendedSizeBytes: 1_000_000_000,
            downloadIdentifier: "hexgrad/kokoro-82m",
            downloaded: downloaded,
            inLibrary: inLibrary
        )
    }

    private func makeHubModel(id: String) -> HubModel {
        HubModel(
            id: id,
            name: "Kokoro",
            backend: "transformers",
            quant: "bf16",
            contextLength: 4096,
            paramsB: 0.08,
            state: .available,
            modelPath: "/tmp/kokoro",
            taskKinds: ["text_to_speech"]
        )
    }

    private func makeHealth(state: LocalModelHealthState, detail: String) -> LocalModelHealthRecord {
        LocalModelHealthRecord(
            modelId: "hexgrad/kokoro-82m",
            providerID: "transformers",
            state: state,
            summary: "state",
            detail: detail,
            lastCheckedAt: Date().timeIntervalSince1970,
            lastSuccessAt: state == .healthy ? Date().timeIntervalSince1970 : nil
        )
    }
}
