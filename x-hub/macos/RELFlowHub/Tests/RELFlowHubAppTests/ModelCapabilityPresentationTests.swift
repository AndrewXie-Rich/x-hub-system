import XCTest
@testable import RELFlowHub

final class ModelCapabilityPresentationTests: XCTestCase {
    func testLocalizedTitlesCoverSharedCapabilityLabels() {
        XCTAssertEqual(ModelCapabilityPresentation.localizedTitle(for: "Text"), "文本")
        XCTAssertEqual(ModelCapabilityPresentation.localizedTitle(for: "Reasoning"), "推理")
        XCTAssertEqual(ModelCapabilityPresentation.localizedTitle(for: "Code"), "编程")
        XCTAssertEqual(ModelCapabilityPresentation.localizedTitle(for: "Embedding"), "向量")
        XCTAssertEqual(ModelCapabilityPresentation.localizedTitle(for: "Vision"), "视觉")
        XCTAssertEqual(ModelCapabilityPresentation.localizedTitle(for: "Speech"), "语音识别")
        XCTAssertEqual(ModelCapabilityPresentation.localizedTitle(for: "Audio"), "音频")
        XCTAssertEqual(ModelCapabilityPresentation.localizedTitle(for: "AudioCleanup"), "音频清理")
        XCTAssertEqual(ModelCapabilityPresentation.localizedTitle(for: "Voice"), "语音")
        XCTAssertEqual(ModelCapabilityPresentation.localizedTitle(for: "Hosted"), "托管")
        XCTAssertEqual(ModelCapabilityPresentation.localizedTitle(for: "Remote"), "远程")
        XCTAssertEqual(ModelCapabilityPresentation.localizedTitle(for: "Local"), "本地")
    }

    func testLocalizedTitleFallsBackForUnknownLabels() {
        XCTAssertEqual(ModelCapabilityPresentation.localizedTitle(for: "GGUF"), "GGUF")
    }
}
