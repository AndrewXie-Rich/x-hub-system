import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class ModelLibrarySectionPlannerTests: XCTestCase {
    func testSectionsGroupByPrimaryCapability() {
        let sections = ModelLibrarySectionPlanner.sections(from: [
            makeModel(
                id: "text-model",
                taskKinds: ["text_generate"],
                state: .loaded
            ),
            makeModel(
                id: "coding-model",
                name: "Qwen Coder",
                taskKinds: ["text_generate"],
                state: .available
            ),
            makeModel(
                id: "embedding-model",
                taskKinds: ["embedding"],
                state: .available
            ),
            makeModel(
                id: "vision-model",
                taskKinds: ["vision_understand"],
                inputModalities: ["image"],
                state: .loaded
            ),
            makeModel(
                id: "ocr-model",
                taskKinds: ["ocr"],
                inputModalities: ["image"],
                state: .available
            ),
            makeModel(
                id: "audio-model",
                taskKinds: ["speech_to_text"],
                inputModalities: ["audio"],
                state: .available
            ),
            makeModel(
                id: "voice-pack-model",
                taskKinds: ["text_to_speech"],
                outputModalities: ["audio"],
                state: .available
            ),
        ])

        XCTAssertEqual(
            sections.map(\.id),
            ["text", "coding", "embedding", "voice", "audio", "vision", "ocr"]
        )
        XCTAssertEqual(sections[0].title, "通用文本")
        XCTAssertEqual(sections[0].subtitle, "终端对话、规划整理和日常写作。")
        XCTAssertEqual(sections[0].loadedCount, 1)
        XCTAssertEqual(sections[1].models.map(\.id), ["coding-model"])
        XCTAssertEqual(sections[2].models.map(\.id), ["embedding-model"])
        XCTAssertEqual(sections[3].models.map(\.id), ["voice-pack-model"])
        XCTAssertEqual(sections[4].models.map(\.id), ["audio-model"])
        XCTAssertEqual(sections[5].models.map(\.id), ["vision-model"])
        XCTAssertEqual(sections[6].models.map(\.id), ["ocr-model"])
    }

    func testSectionsPreserveInputOrderWithinGroup() {
        let sections = ModelLibrarySectionPlanner.sections(from: [
            makeModel(id: "first", taskKinds: ["text_generate"], state: .available),
            makeModel(id: "second", taskKinds: ["text_generate"], state: .loaded),
        ])

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].id, "text")
        XCTAssertEqual(sections[0].models.map(\.id), ["first", "second"])
        XCTAssertEqual(sections[0].loadedCount, 1)
    }

    func testSectionsCanPreferRemoteBucket() {
        let remote = makeModel(
            id: "remote-coder",
            name: "Remote Coder",
            backend: "openai",
            modelPath: nil,
            taskKinds: ["text_generate"],
            state: .available
        )

        let defaultSections = ModelLibrarySectionPlanner.sections(from: [remote])
        XCTAssertEqual(defaultSections.map(\.id), ["coding"])

        let remoteSections = ModelLibrarySectionPlanner.sections(from: [remote], preferRemoteSection: true)
        XCTAssertEqual(remoteSections.map(\.id), ["remote"])
    }

    private func makeModel(
        id: String,
        name: String? = nil,
        backend: String = "mlx",
        modelPath: String? = "/tmp/\(UUID().uuidString)",
        taskKinds: [String],
        inputModalities: [String]? = nil,
        outputModalities: [String]? = nil,
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
            taskKinds: taskKinds,
            inputModalities: inputModalities,
            outputModalities: outputModalities
        )
    }
}
