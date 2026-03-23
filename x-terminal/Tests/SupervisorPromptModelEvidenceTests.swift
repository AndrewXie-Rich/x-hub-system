import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorPromptModelEvidenceTests {

    @Test
    func localMemoryUsesTypedLoadConfigVocabularyForAvailableModels() async {
        let previousModels = HubModelManager.shared.availableModels
        defer { HubModelManager.shared.availableModels = previousModels }

        let manager = SupervisorManager.makeForTesting()
        HubModelManager.shared.availableModels = [
            HubModel(
                id: "qwen3-14b-mlx",
                name: "Qwen 3 14B",
                backend: "mlx",
                quant: "4bit",
                contextLength: 131_072,
                maxContextLength: 196_608,
                paramsB: 14,
                roles: ["coder"],
                state: .loaded,
                memoryBytes: nil,
                tokensPerSec: nil,
                modelPath: "/models/qwen3-14b-mlx",
                note: nil,
                modelFormat: "mlx",
                defaultLoadProfile: HubLocalModelLoadProfile(
                    contextLength: 128_000,
                    ttl: 900,
                    parallel: 2,
                    identifier: "coder-a"
                )
            )
        ]

        let memory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续推进")

        #expect(memory.contains("默认加载配置：ctx 128000 · ttl 900s · par 2 · id coder-a"))
        #expect(memory.contains("本地加载上限：ctx 196608"))
        #expect(!memory.contains("上下文长度:"))
    }
}
