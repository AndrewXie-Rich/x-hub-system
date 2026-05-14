import Testing
@testable import XTerminal

struct HistoryPanelPresentationTests {
    @Test
    func historyRowPreviewLeavesShortContentWhole() {
        let content = "abcdef"

        let preview = MessageHistoryRowPresentation.previewContent(
            for: content,
            characterLimit: 6
        )

        #expect(preview == content)
    }

    @Test
    func historyRowPreviewUsesBoundedPrefixForLongContent() {
        let content = "abcdefghijklmnopqrstuvwxyz"

        let preview = MessageHistoryRowPresentation.previewContent(
            for: content,
            characterLimit: 6
        )

        #expect(preview == "abcdef\n...")
        #expect(preview.utf8.count < content.utf8.count)
    }
}
