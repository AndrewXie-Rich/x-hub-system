import XCTest
@testable import RELFlowHubCore

final class LocalTaskRoutingCatalogTests: XCTestCase {
    func testSupportedTaskKindsNormalizeFilterAndDedupe() {
        let taskKinds = LocalTaskRoutingCatalog.supportedTaskKinds(
            in: ["Embedding", "ocr", "unknown", "embedding", "speech_to_text"]
        )

        XCTAssertEqual(taskKinds, ["embedding", "ocr", "speech_to_text"])
    }

    func testDescriptorAndFallbackTitles() {
        XCTAssertEqual(LocalTaskRoutingCatalog.title(for: "vision_understand"), "Vision Understanding")
        XCTAssertEqual(LocalTaskRoutingCatalog.shortTitle(for: "text_generate"), "Generate")
        XCTAssertEqual(LocalTaskRoutingCatalog.title(for: "custom_task"), "Custom Task")
    }
}
