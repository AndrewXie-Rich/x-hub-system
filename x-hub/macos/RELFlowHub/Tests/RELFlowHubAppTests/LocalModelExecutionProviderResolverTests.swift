import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class LocalModelExecutionProviderResolverTests: XCTestCase {
    func testSuggestedRuntimeProviderUsesMLXVLMRuntimeForMLXVisionModel() {
        let suggested = LocalModelExecutionProviderResolver.suggestedRuntimeProviderID(
            backend: "mlx",
            modelPath: "/tmp/models/glm4v-mlx",
            taskKinds: ["vision_understand", "ocr"],
            helperBinaryPath: "/Users/test/.lmstudio/bin/lms"
        )

        XCTAssertEqual(suggested, "mlx_vlm")
    }

    func testSuggestedRuntimeProviderKeepsMLXTextModelOnNativeProvider() {
        let suggested = LocalModelExecutionProviderResolver.suggestedRuntimeProviderID(
            backend: "mlx",
            modelPath: "/tmp/models/qwen-mlx",
            taskKinds: ["text_generate"],
            helperBinaryPath: "/Users/test/.lmstudio/bin/lms"
        )

        XCTAssertNil(suggested)
    }

    func testBackfilledEntryStoresMLXVLMRuntimeProviderForMLXVisionModel() {
        let entry = ModelCatalogEntry(
            id: "glm4v-mlx",
            name: "GLM4V MLX",
            backend: "mlx",
            quant: "int4",
            contextLength: 8192,
            paramsB: 9.0,
            modelPath: "/tmp/models/glm4v-mlx",
            taskKinds: ["vision_understand"]
        )

        let updated = LocalModelExecutionProviderResolver.backfilled(
            entry,
            helperBinaryPath: "/Users/test/.lmstudio/bin/lms"
        )

        XCTAssertEqual(updated.runtimeProviderID, "mlx_vlm")
    }

    func testSuggestedRuntimeProviderKeepsExplicitLlamaCppMappingForGGUFModel() {
        let suggested = LocalModelExecutionProviderResolver.suggestedRuntimeProviderID(
            backend: "llama.cpp",
            modelPath: "/tmp/models/qwen3-q4_k_m.gguf",
            taskKinds: ["text_generate"],
            helperBinaryPath: "/Users/test/.lmstudio/bin/lms"
        )

        XCTAssertEqual(suggested, "llama.cpp")
    }

    func testBackfilledEntryStoresExplicitLlamaCppRuntimeProviderForGGUFModel() {
        let entry = ModelCatalogEntry(
            id: "qwen3-gguf",
            name: "Qwen3 GGUF",
            backend: "llama.cpp",
            quant: "q4_k_m",
            contextLength: 8192,
            paramsB: 8.0,
            modelPath: "/tmp/models/qwen3-q4_k_m.gguf",
            taskKinds: ["text_generate"]
        )

        let updated = LocalModelExecutionProviderResolver.backfilled(
            entry,
            helperBinaryPath: "/Users/test/.lmstudio/bin/lms"
        )

        XCTAssertEqual(updated.runtimeProviderID, "llama.cpp")
    }
}
