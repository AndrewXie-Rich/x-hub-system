import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class HubTaskRoutingPolicyTests: XCTestCase {
    func testCoderRoutesToLoadedTextGenerationModelWithoutExplicitRole() {
        let decision = HubTaskRoutingPolicy.decision(
            taskType: .coder,
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

    func testCoderUsesRoleOnlyAsTieBreakerWithinTaskMatches() {
        let decision = HubTaskRoutingPolicy.decision(
            taskType: .coder,
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
                    roles: ["coder"],
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

    func testSupervisorAutoloadsTaskMatchBeforeLoadedUnsupportedModel() {
        let decision = HubTaskRoutingPolicy.decision(
            taskType: .supervisor,
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
            roles: ["general", "coder"],
            state: .available,
            taskKinds: ["vision_understand", "ocr"]
        )

        XCTAssertEqual(HubTaskRoutingPolicy.capabilityTags(for: model), ["视觉", "OCR"])
    }
}
