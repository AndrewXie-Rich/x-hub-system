import AppKit
import SwiftUI

struct TranscriptTextView: NSViewRepresentable {
    var attributedText: NSAttributedString

    final class Coordinator {
        var lastString: String = ""
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor.textBackgroundColor

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = true
        tv.importsGraphics = false
        tv.usesFindBar = true
        tv.allowsUndo = false
        tv.backgroundColor = NSColor.textBackgroundColor
        tv.textContainerInset = NSSize(width: 10, height: 10)

        // Make the text view behave like a growing transcript (Terminal-like).
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude)

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }

        // Keep container width in sync with the scroll view.
        let w = max(120, nsView.contentSize.width)
        tv.frame.size.width = w
        tv.textContainer?.containerSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)

        // If user is selecting text, do not disrupt selection.
        let selected = tv.selectedRange()
        let selectionActive = selected.length > 0

        let newString = attributedText.string
        if context.coordinator.lastString == newString {
            // Avoid resetting text storage on unrelated view updates (e.g. thinking dots timer),
            // which would cause flicker and break selection.
            return
        }

        context.coordinator.lastString = newString

        let shouldStickToBottom = (!selectionActive) && isNearBottom(nsView)

        tv.textStorage?.setAttributedString(attributedText)
        if selectionActive {
            tv.setSelectedRange(selected)
        }

        if shouldStickToBottom {
            scrollToBottom(nsView)
        }
    }

    private func isNearBottom(_ scroll: NSScrollView) -> Bool {
        guard let doc = scroll.documentView else { return true }
        let contentMaxY = scroll.contentView.bounds.maxY
        let docMaxY = doc.bounds.maxY
        return (docMaxY - contentMaxY) < 48.0
    }

    private func scrollToBottom(_ scroll: NSScrollView) {
        guard let doc = scroll.documentView else { return }
        let y = max(0, doc.bounds.maxY - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
