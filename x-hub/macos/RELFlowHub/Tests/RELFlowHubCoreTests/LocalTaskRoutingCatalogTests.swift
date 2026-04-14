import XCTest
@testable import RELFlowHubCore

final class LocalTaskRoutingCatalogTests: XCTestCase {
    func testSupportedTaskKindsNormalizeFilterAndDedupe() {
        let taskKinds = LocalTaskRoutingCatalog.supportedTaskKinds(
            in: ["Embedding", "ocr", "unknown", "embedding", "speech_to_text", "text_to_speech"]
        )

        XCTAssertEqual(taskKinds, ["embedding", "ocr", "speech_to_text", "text_to_speech"])
    }

    func testDescriptorAndFallbackTitles() {
        XCTAssertEqual(LocalTaskRoutingCatalog.title(for: "vision_understand"), "视觉理解")
        XCTAssertEqual(LocalTaskRoutingCatalog.shortTitle(for: "text_generate"), "生成")
        XCTAssertEqual(LocalTaskRoutingCatalog.title(for: "text_to_speech"), "文本转语音")
        XCTAssertEqual(LocalTaskRoutingCatalog.shortTitle(for: "text_to_speech"), "语音")
        XCTAssertEqual(LocalTaskRoutingCatalog.title(for: "custom_task"), "Custom Task")
    }
}
