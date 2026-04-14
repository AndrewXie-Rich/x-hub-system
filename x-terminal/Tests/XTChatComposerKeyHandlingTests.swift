import AppKit
import Testing
@testable import XTerminal

struct XTChatComposerKeyHandlingTests {

    @Test
    func plainReturnSubmits() {
        #expect(
            XTChatComposerKeyHandling.shouldSubmit(
                keyCode: 36,
                modifierFlags: [],
                hasMarkedText: false
            )
        )
    }

    @Test
    func commandReturnAlsoSubmits() {
        #expect(
            XTChatComposerKeyHandling.shouldSubmit(
                keyCode: 36,
                modifierFlags: [.command],
                hasMarkedText: false
            )
        )
    }

    @Test
    func shiftReturnDoesNotSubmit() {
        #expect(
            !XTChatComposerKeyHandling.shouldSubmit(
                keyCode: 36,
                modifierFlags: [.shift],
                hasMarkedText: false
            )
        )
    }

    @Test
    func markedTextPreventsSubmit() {
        #expect(
            !XTChatComposerKeyHandling.shouldSubmit(
                keyCode: 36,
                modifierFlags: [],
                hasMarkedText: true
            )
        )
    }

    @Test
    func externalSyncSkipsWhileMarkedTextIsActive() {
        #expect(
            !XTChatComposerSyncPolicy.shouldApplyExternalText(
                currentViewText: "ni",
                externalText: "",
                hasMarkedText: true
            )
        )
    }

    @Test
    func externalSyncAppliesWhenTextDiffersAndNoMarkedTextExists() {
        #expect(
            XTChatComposerSyncPolicy.shouldApplyExternalText(
                currentViewText: "hello",
                externalText: "",
                hasMarkedText: false
            )
        )
    }

    @Test
    func droppedURLsAreDeduplicatedAndOnlyKeepFileURLs() {
        let fileURL = URL(fileURLWithPath: "/tmp/demo.txt")
        let normalized = XTChatComposerFileDrop.normalizedDroppedURLs([
            fileURL,
            URL(fileURLWithPath: "/tmp/demo.txt"),
            URL(string: "https://example.com/demo.txt")!
        ])

        #expect(normalized == [fileURL])
    }

    @Test
    func dropIntentDefaultsToReadOnlyWhenImportLaneIsDisabled() {
        #expect(
            XTChatComposerFileDrop.intent(
                locationX: 320,
                width: 400,
                allowsImportDrop: false
            ) == .attachReadOnly
        )
    }

    @Test
    func dropIntentSwitchesToImportLaneNearTrailingEdge() {
        #expect(
            XTChatComposerFileDrop.intent(
                locationX: 340,
                width: 400,
                allowsImportDrop: true
            ) == .importToProject
        )
    }

    @Test
    func focusRequestDefersUntilWindowIsAttached() {
        #expect(
            XTChatComposerFocusPolicy.shouldDeferProgrammaticFocus(
                isFocused: true,
                windowAttached: false
            )
        )
    }

    @Test
    func focusRequestDoesNotDeferWithoutFocusIntent() {
        #expect(
            !XTChatComposerFocusPolicy.shouldDeferProgrammaticFocus(
                isFocused: false,
                windowAttached: false
            )
        )
    }

    @Test
    func focusRequestRunsWhenComposerIsNotFirstResponder() {
        #expect(
            XTChatComposerFocusPolicy.shouldRequestProgrammaticFocus(
                isFocused: true,
                alreadyFirstResponder: false
            )
        )
    }

    @Test
    func focusRequestSkipsWhenComposerAlreadyOwnsFocus() {
        #expect(
            !XTChatComposerFocusPolicy.shouldRequestProgrammaticFocus(
                isFocused: true,
                alreadyFirstResponder: true
            )
        )
    }

    @Test
    func layoutKeepsDocumentAtLeastViewportHeight() {
        #expect(
            XTChatComposerLayoutPolicy.documentHeight(
                viewportHeight: 60,
                usedRectHeight: 0,
                insetHeight: 12,
                minimumLineHeight: 20
            ) == 60
        )
    }

    @Test
    func layoutExpandsWhenContentOutgrowsViewport() {
        #expect(
            XTChatComposerLayoutPolicy.documentHeight(
                viewportHeight: 60,
                usedRectHeight: 88,
                insetHeight: 12,
                minimumLineHeight: 20
            ) == 100
        )
    }
    @Test
    @MainActor
    func scrollViewRoutesContentHitsToTextView() {
        let scrollView = XTChatComposerTextView.ComposerScrollView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 88)
        )
        let textView = XTChatComposerTextView.ComposerTextView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 88),
            textContainer: nil
        )

        scrollView.documentView = textView

        #expect(scrollView.hitTest(NSPoint(x: 20, y: 20)) === textView)
    }

    @Test
    @MainActor
    func composerTextViewInstallsEditableTextSystemWhenContainerIsMissing() {
        let textView = XTChatComposerTextView.ComposerTextView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 88),
            textContainer: nil
        )

        #expect(textView.textStorage != nil)
        #expect(textView.layoutManager != nil)
        #expect(textView.textContainer != nil)
    }

    @Test
    @MainActor
    func composerTextViewCanInsertPlainTextWithoutExternalTextContainer() {
        let textView = XTChatComposerTextView.ComposerTextView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 88),
            textContainer: nil
        )

        textView.insertText("abc", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(textView.string == "abc")
    }

}
