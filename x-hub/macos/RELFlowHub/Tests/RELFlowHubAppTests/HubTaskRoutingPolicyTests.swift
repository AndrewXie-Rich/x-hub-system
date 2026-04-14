import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class HubTaskRoutingPolicyTests: XCTestCase {
    func testTranslateRoutesToLoadedTextGenerationModelWithoutExplicitRole() {
        let decision = HubTaskRoutingPolicy.decision(
            taskType: .translate,
            models: [
                HubModel(
                    id: "vision-only",
                    name: "Vision Only",
                    backend: "transformers",
                    quant: "fp16",
                    contextLength: 8192,
                    paramsB: 7.0,
                    state: .loaded,
                    taskKinds: ["vision_understand"]
                ),
                HubModel(
                    id: "text-general",
                    name: "Text General",
                    backend: "transformers",
                    quant: "fp16",
                    contextLength: 8192,
                    paramsB: 7.0,
                    state: .loaded,
                    taskKinds: ["text_generate"]
                ),
            ],
            preferredModelId: "",
            allowAutoLoad: true
        )

        XCTAssertEqual(decision.modelId, "text-general")
        XCTAssertEqual(decision.reason, "task_match_loaded")
        XCTAssertFalse(decision.willAutoLoad)
    }

    func testTranslateUsesRoleOnlyAsTieBreakerWithinTaskMatches() {
        let decision = HubTaskRoutingPolicy.decision(
            taskType: .translate,
            models: [
                HubModel(
                    id: "bigger-general",
                    name: "Bigger General",
                    backend: "transformers",
                    quant: "fp16",
                    contextLength: 8192,
                    paramsB: 13.0,
                    state: .loaded,
                    taskKinds: ["text_generate"]
                ),
                HubModel(
                    id: "translate-role",
                    name: "Translate Role",
                    backend: "transformers",
                    quant: "fp16",
                    contextLength: 8192,
                    paramsB: 7.0,
                    roles: ["translate"],
                    state: .loaded,
                    taskKinds: ["text_generate"]
                ),
            ],
            preferredModelId: "",
            allowAutoLoad: true
        )

        XCTAssertEqual(decision.modelId, "translate-role")
        XCTAssertEqual(decision.reason, "task_match_loaded")
    }

    func testAssistAutoloadsTaskMatchBeforeLoadedUnsupportedModel() {
        let decision = HubTaskRoutingPolicy.decision(
            taskType: .assist,
            models: [
                HubModel(
                    id: "loaded-embedding",
                    name: "Loaded Embedding",
                    backend: "transformers",
                    quant: "fp16",
                    contextLength: 8192,
                    paramsB: 2.0,
                    state: .loaded,
                    taskKinds: ["embedding"]
                ),
                HubModel(
                    id: "available-text",
                    name: "Available Text",
                    backend: "transformers",
                    quant: "fp16",
                    contextLength: 8192,
                    paramsB: 7.0,
                    state: .available,
                    taskKinds: ["text_generate"]
                ),
            ],
            preferredModelId: "",
            allowAutoLoad: true
        )

        XCTAssertEqual(decision.modelId, "available-text")
        XCTAssertEqual(decision.reason, "task_match_autoload")
        XCTAssertTrue(decision.willAutoLoad)
    }

    func testCapabilityTagsPreferTaskKindsOverLegacyRoles() {
        let model = HubModel(
            id: "vision",
            name: "Vision",
            backend: "transformers",
            quant: "fp16",
            contextLength: 8192,
            paramsB: 7.0,
            roles: ["general", "translate"],
            state: .available,
            taskKinds: ["vision_understand", "ocr"]
        )

        XCTAssertEqual(HubTaskRoutingPolicy.capabilityTags(for: model), ["视觉", "OCR"])
    }
}
