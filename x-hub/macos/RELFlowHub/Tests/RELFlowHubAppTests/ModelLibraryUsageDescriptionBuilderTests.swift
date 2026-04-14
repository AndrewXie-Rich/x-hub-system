import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class ModelLibraryUsageDescriptionBuilderTests: XCTestCase {
    func testLoadedTextModelUsesReadyLanguage() {
        let model = makeModel(
            id: "text-model",
            taskKinds: ["text_generate"],
            state: .loaded
        )

        XCTAssertEqual(
            ModelLibraryUsageDescriptionBuilder.description(for: model),
            "已就绪，可用于日常对话、规划整理和写作"
        )
    }

    func testCodingModelUsesCodingDescription() {
        let model = makeModel(
            id: "coding-model",
            name: "Qwen Coder",
            taskKinds: ["text_generate"],
            state: .available
        )

        XCTAssertEqual(
            ModelLibraryUsageDescriptionBuilder.description(for: model),
            "适合仓库改动、调试修复和终端编程"
        )
    }

    func testEmbeddingModelUsesRetrievalDescription() {
        let model = makeModel(
            id: "embedding-model",
            taskKinds: ["embedding"],
            state: .available
        )

        XCTAssertEqual(
            ModelLibraryUsageDescriptionBuilder.description(for: model),
            "适合检索、记忆和语义搜索"
        )
    }

    func testRemoteNonCodingModelUsesRemoteDescription() {
        let model = makeModel(
            id: "remote-general",
            backend: "openai",
            modelPath: nil,
            taskKinds: ["tool_use"],
            state: .available
        )

        XCTAssertEqual(
            ModelLibraryUsageDescriptionBuilder.description(for: model),
            "适合无需本地运行时的云端任务"
        )
    }

    private func makeModel(
        id: String,
        name: String? = nil,
        backend: String = "mlx",
        modelPath: String? = "/tmp/\(UUID().uuidString)",
        taskKinds: [String],
        state: HubModelState
    ) -> HubModel {
        HubModel(
            id: id,
            name: name ?? id,
            backend: backend,
            quant: "4bit",
            contextLength: 8192,
            paramsB: 4.0,
            state: state,
            modelPath: modelPath,
            taskKinds: taskKinds
        )
    }
}
