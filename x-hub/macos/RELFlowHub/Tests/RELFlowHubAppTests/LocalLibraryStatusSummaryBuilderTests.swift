import XCTest
@testable import RELFlowHub
import RELFlowHubCore

@MainActor
final class LocalLibraryStatusSummaryBuilderTests: XCTestCase {
    func testBuildCountsLoadedLocalReadyBlockedAndRemoteModels() {
        let readyLocal = makeLocalModel(
            id: "mlx-community/qwen3-4b-instruct-4bit",
            state: .available
        )
        let loadedLocal = makeLocalModel(
            id: "hexgrad/kokoro-82m",
            state: .loaded,
            backend: "transformers",
            taskKinds: ["text_to_speech"]
        )
        let blockedLocal = makeLocalModel(
            id: "microsoft/florence-2-base",
            state: .available,
            backend: "transformers",
            taskKinds: ["vision_understand"]
        )
        let remote = HubModel(
            id: "openai/gpt-5.4",
            name: "gpt-5.4",
            backend: "remote_catalog",
            quant: "remote",
            contextLength: 128_000,
            paramsB: 0,
            state: .available
        )

        let summary = LocalLibraryStatusSummaryBuilder.build(
            models: [readyLocal, loadedLocal, blockedLocal, remote]
        ) { model in
            switch model.id {
            case readyLocal.id, loadedLocal.id:
                return .ready("ready")
            case blockedLocal.id:
                return .unavailable("blocked")
            default:
                XCTFail("remote models should not request local readiness")
                return .unavailable()
            }
        }

        XCTAssertEqual(
            summary,
            LocalLibraryStatusSummary(
                totalCount: 4,
                loadedCount: 1,
                localReadyCount: 2,
                localBlockedCount: 1,
                remoteCount: 1
            )
        )
    }

    private func makeLocalModel(
        id: String,
        state: HubModelState,
        backend: String = "mlx",
        taskKinds: [String] = ["text_generate"]
    ) -> HubModel {
        HubModel(
            id: id,
            name: id,
            backend: backend,
            quant: "bf16",
            contextLength: 8192,
            paramsB: 1.0,
            state: state,
            modelPath: "/tmp/\(UUID().uuidString)",
            taskKinds: taskKinds
        )
    }
}
