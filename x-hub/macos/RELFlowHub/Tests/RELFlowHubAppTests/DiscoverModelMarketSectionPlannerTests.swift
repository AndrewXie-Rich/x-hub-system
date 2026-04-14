import XCTest
@testable import RELFlowHub

final class DiscoverModelMarketSectionPlannerTests: XCTestCase {
    func testRecommendedSectionsGroupResultsByPrimaryCapability() {
        let sections = DiscoverModelMarketSectionPlanner.recommendedSections(from: [
            makeMarketResult(
                modelKey: "mlx-community/qwen3-4b-instruct-4bit",
                capabilityTags: ["Text"]
            ),
            makeMarketResult(
                modelKey: "mlx-community/qwen3-coder-4b-4bit",
                capabilityTags: ["Text", "Coding"]
            ),
            makeMarketResult(
                modelKey: "mlx-community/qwen3-embedding-0.6b-4bit-dwq",
                capabilityTags: ["Embedding"]
            ),
            makeMarketResult(
                modelKey: "hexgrad/kokoro-82m",
                capabilityTags: ["Voice"]
            ),
            makeMarketResult(
                modelKey: "microsoft/florence-2-base",
                capabilityTags: ["Vision", "OCR"]
            ),
            makeMarketResult(
                modelKey: "custom/local-specialist",
                capabilityTags: ["AudioCleanup"]
            ),
        ])

        XCTAssertEqual(sections.map(\.id), ["text", "coding", "embedding", "voice", "ocr", "other"])
        XCTAssertEqual(sections[0].title, "文本")
        XCTAssertEqual(sections[0].subtitle, "通用终端对话、规划和写作。")
        XCTAssertEqual(sections[5].title, "专用")
        XCTAssertEqual(sections[0].results.map(\.modelKey), ["mlx-community/qwen3-4b-instruct-4bit"])
        XCTAssertEqual(sections[1].results.map(\.modelKey), ["mlx-community/qwen3-coder-4b-4bit"])
        XCTAssertEqual(sections[2].results.map(\.modelKey), ["mlx-community/qwen3-embedding-0.6b-4bit-dwq"])
        XCTAssertEqual(sections[3].results.map(\.modelKey), ["hexgrad/kokoro-82m"])
        XCTAssertEqual(sections[4].results.map(\.modelKey), ["microsoft/florence-2-base"])
        XCTAssertEqual(sections[5].results.map(\.modelKey), ["custom/local-specialist"])
    }

    func testRecommendedSectionsPreserveInputOrderWithinSection() {
        let sections = DiscoverModelMarketSectionPlanner.recommendedSections(from: [
            makeMarketResult(
                modelKey: "mlx-community/qwen3-8b-instruct-4bit",
                capabilityTags: ["Text"]
            ),
            makeMarketResult(
                modelKey: "mlx-community/gemma-3-4b-it-4bit",
                capabilityTags: ["Text"]
            ),
        ])

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].id, "text")
        XCTAssertEqual(
            sections[0].results.map(\.modelKey),
            [
                "mlx-community/qwen3-8b-instruct-4bit",
                "mlx-community/gemma-3-4b-it-4bit",
            ]
        )
    }

    private func makeMarketResult(
        modelKey: String,
        capabilityTags: [String]
    ) -> LMStudioMarketResult {
        LMStudioMarketResult(
            modelKey: modelKey,
            title: modelKey,
            summary: "",
            formatHint: "mlx",
            capabilityTags: capabilityTags,
            staffPick: false,
            recommendationReason: "",
            recommendedForThisMac: true,
            recommendedFitEstimation: "fullGPUOffload",
            recommendedSizeBytes: 1_000_000_000,
            downloadIdentifier: modelKey,
            downloaded: false,
            inLibrary: false
        )
    }
}
