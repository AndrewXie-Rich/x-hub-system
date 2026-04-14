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
                runtimeReadiness: nil
            )
        )
    }

    func testStatusShowsImportedWhileRuntimeCheckIsPending() {
        let status = DiscoverModelMarketLifecyclePlanner.status(
            for: makeMarketResult(downloaded: true, inLibrary: true),
            matchingModel: nil
        ) { _ in
            XCTFail("runtime readiness should not be evaluated")
            return .ready()
        }

        XCTAssertEqual(
            status,
            DiscoverModelMarketLifecycleStatus(
                isDownloaded: true,
                isImported: true,
                runtimeReadiness: nil
            )
        )
    }

    func testStatusMarksImportedModelReady() {
        let status = DiscoverModelMarketLifecyclePlanner.status(
            for: makeMarketResult(downloaded: true, inLibrary: true),
            matchingModel: makeHubModel(id: "hexgrad/kokoro-82m")
        ) { _ in
            .ready("Imported and ready for local Hub voice playback.")
        }

        XCTAssertEqual(
            status,
            DiscoverModelMarketLifecycleStatus(
                isDownloaded: true,
                isImported: true,
                runtimeReadiness: .ready("Imported and ready for local Hub voice playback.")
            )
        )
    }

    func testStatusMarksImportedModelRuntimeUnavailable() {
        let status = DiscoverModelMarketLifecyclePlanner.status(
            for: makeMarketResult(downloaded: true, inLibrary: true),
            matchingModel: makeHubModel(id: "hexgrad/kokoro-82m")
        ) { _ in
            .unavailable("Hub could not resolve a local runtime launch configuration for transformers.")
        }

        XCTAssertEqual(
            status,
            DiscoverModelMarketLifecycleStatus(
                isDownloaded: true,
                isImported: true,
                runtimeReadiness: .unavailable(
                    "Hub could not resolve a local runtime launch configuration for transformers."
                )
            )
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
}
