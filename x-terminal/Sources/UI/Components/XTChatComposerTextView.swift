import AppKit
import SwiftUI

enum XTChatComposerDropIntent: String, Equatable {
    case attachReadOnly = "attach_read_only"
    case importToProject = "import_to_project"
}

enum XTChatComposerKeyHandling {
    private static let submitKeyCodes: Set<UInt16> = [36, 76]
    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    static func shouldSubmit(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        hasMarkedText: Bool
    ) -> Bool {
        guard !hasMarkedText, submitKeyCodes.contains(keyCode) else { return false }
        let normalized = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection(relevantModifiers)
        return normalized.isEmpty || normalized == [.command]
    }
}

enum XTChatComposerFocusPolicy {
    static func shouldDeferProgrammaticFocus(
        isFocused: Bool,
        windowAttached: Bool
    ) -> Bool {
        isFocused && !windowAttached
    }

    static func shouldRequestProgrammaticFocus(
        isFocused: Bool,
        alreadyFirstResponder: Bool
    ) -> Bool {
        isFocused && !alreadyFirstResponder
    }
}

enum XTChatComposerLayoutPolicy {
    static func documentHeight(
        viewportHeight: CGFloat,
        usedRectHeight: CGFloat,
        insetHeight: CGFloat,
        minimumLineHeight: CGFloat
    ) -> CGFloat {
        let contentHeight = max(minimumLineHeight + insetHeight, usedRectHeight + insetHeight)
        return max(viewportHeight, ceil(contentHeight))
    }
}

enum XTChatComposerSyncPolicy {
    static func shouldApplyExternalText(
        currentViewText: String,
        externalText: String,
        hasMarkedText: Bool
    ) -> Bool {
        guard currentViewText != externalText else { return false }
        return !hasMarkedText
    }
}

enum XTChatComposerFileDrop {
    private static let importTriggerRatio: CGFloat = 0.62

    static func normalizedDroppedURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var ordered: [URL] = []

        for url in urls where url.isFileURL {
            let resolved = PathGuard.resolve(url).path
            guard seen.insert(resolved).inserted else { continue }
            ordered.append(URL(fileURLWithPath: resolved))
        }

        return ordered
    }

    static func intent(
        locationX: CGFloat,
        width: CGFloat,
        allowsImportDrop: Bool
    ) -> XTChatComposerDropIntent {
        guard allowsImportDrop, width > 0 else { return .attachReadOnly }
        let clampedX = min(max(locationX, 0), width)
        return clampedX >= width * importTriggerRatio ? .importToProject : .attachReadOnly
    }
}

enum XTChatComposerDiagnostics {
    static let enabled = ProcessInfo.processInfo.environment["XT_CHAT_COMPOSER_DIAGNOSTICS"] == "1"
    static let logURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("xterminal-chat-composer.log", isDirectory: false)

    private static let lock = NSLock()
    private static let formatter = ISO8601DateFormatter()
    private static var wroteSessionHeader = false

    static func log(_ scope: String, _ message: @autoclosure () -> String) {
        guard enabled else { return }

        lock.lock()
        defer { lock.unlock() }

        var lines: [String] = []
        if !wroteSessionHeader {
            wroteSessionHeader = true
            lines.append(
                "==== XTerminal composer diagnostics pid=\(ProcessInfo.processInfo.processIdentifier) started=\(formatter.string(from: Date())) ===="
            )
        }
        lines.append(
            "[\(formatter.string(from: Date()))] [\(scope)] \(message())"
        )
        lines.append("")

        let payload = lines.joined(separator: "\n")
        guard let data = payload.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logURL.path) {
            do {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                return
            } catch {
                // Fall through and try replacing the file.
            }
        }

        try? data.write(to: logURL, options: .atomic)
    }

    static func describe(_ responder: NSResponder?) -> String {
        guard let responder else { return "nil" }
        let typeName = String(describing: type(of: responder))
        if let view = responder as? NSView {
            return "\(typeName) frame=\(NSStringFromRect(view.frame)) window=\(describe(view.window))"
        }
        return typeName
    }

    static func describe(_ window: NSWindow?) -> String {
        guard let window else { return "nil" }
        let title = window.title.isEmpty ? "<untitled>" : window.title
        return "#\(window.windowNumber) \(title)"
    }
}

struct XTChatComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    var font: NSFont = .preferredFont(forTextStyle: .body)
    var isEditable: Bool = true
    var canSubmit: Bool = true
    var diagnosticScope: String = "chat_composer"
    var onSubmit: (() -> Void)? = nil
    var allowsImportDrop: Bool = false
    var onDropFiles: (([URL], XTChatComposerDropIntent) -> Void)? = nil
    var onDropHoverChange: ((Bool) -> Void)? = nil
    var onDropIntentChange: ((XTChatComposerDropIntent?) -> Void)? = nil

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: XTChatComposerTextView

        init(parent: XTChatComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let next = textView.string
            XTChatComposerDiagnostics.log(
                parent.diagnosticScope,
                "textDidChange length=\(next.count) selectedRange=\(NSStringFromRange(textView.selectedRange()))"
            )
            if parent.text != next {
                parent.text = next
            }
        }
    }

    final class ComposerScrollView: NSScrollView {
        var diagnosticScope: String = "chat_composer"

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let textView = documentView as? ComposerTextView,
                  contentView.frame.contains(point) else {
                return super.hitTest(point)
            }
            return textView
        }

        override func mouseDown(with event: NSEvent) {
            XTChatComposerDiagnostics.log(
                diagnosticScope,
                "scrollView mouseDown unexpected firstResponder=\(XTChatComposerDiagnostics.describe(window?.firstResponder))"
            )
            super.mouseDown(with: event)
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(contentView.frame, cursor: .iBeam)
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.iBeam.set()
        }
    }

    final class ComposerTextView: NSTextView {
        private struct OwnedTextSystem {
            let textStorage: NSTextStorage
            let layoutManager: NSLayoutManager
            let textContainer: NSTextContainer
        }

        var diagnosticScope: String = "chat_composer"
        var canSubmit: Bool = true
        var onSubmit: (() -> Void)?
        var focusChanged: ((Bool) -> Void)?
        var allowsImportDrop: Bool = false
        var fileDropHandler: (([URL], XTChatComposerDropIntent) -> Void)?
        var fileDropHoverChanged: ((Bool) -> Void)?
        var fileDropIntentChanged: ((XTChatComposerDropIntent?) -> Void)?
        var wantsProgrammaticFocus: Bool = false {
            didSet {
                if !wantsProgrammaticFocus {
                    pendingProgrammaticFocus = false
                }
                if oldValue != wantsProgrammaticFocus {
                    XTChatComposerDiagnostics.log(
                        diagnosticScope,
                        "wantsProgrammaticFocus \(oldValue) -> \(wantsProgrammaticFocus)"
                    )
                }
            }
        }
        private var currentDropIntent: XTChatComposerDropIntent?
        private var pendingProgrammaticFocus = false
        private var ownedTextStorage: NSTextStorage?
        private var ownedLayoutManager: NSLayoutManager?

        override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
            if let container {
                super.init(frame: frameRect, textContainer: container)
            } else {
                let owned = Self.makeOwnedTextSystem(initialWidth: frameRect.width)
                ownedTextStorage = owned.textStorage
                ownedLayoutManager = owned.layoutManager
                super.init(frame: frameRect, textContainer: owned.textContainer)
            }
            commonInit()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            installOwnedTextSystemIfNeeded(initialWidth: frame.width)
            commonInit()
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override var acceptsFirstResponder: Bool {
            isEditable && isSelectable
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(visibleRect, cursor: .iBeam)
        }

        override func mouseDown(with event: NSEvent) {
            XTChatComposerDiagnostics.log(
                diagnosticScope,
                "textView mouseDown editable=\(isEditable) selectable=\(isSelectable) firstBefore=\(XTChatComposerDiagnostics.describe(window?.firstResponder))"
            )
            let accepted = window?.makeFirstResponder(self) ?? false
            XTChatComposerDiagnostics.log(
                diagnosticScope,
                "textView mouseDown makeFirstResponder=\(accepted) firstAfter=\(XTChatComposerDiagnostics.describe(window?.firstResponder))"
            )
            super.mouseDown(with: event)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                XTChatComposerDiagnostics.log(
                    self.diagnosticScope,
                    "textView mouseDown async firstResponder=\(XTChatComposerDiagnostics.describe(self.window?.firstResponder)) selectedRange=\(NSStringFromRange(self.selectedRange()))"
                )
            }
        }

        override func keyDown(with event: NSEvent) {
            XTChatComposerDiagnostics.log(
                diagnosticScope,
                "keyDown keyCode=\(event.keyCode) chars=\(event.characters ?? "") charsIgnoringModifiers=\(event.charactersIgnoringModifiers ?? "") modifiers=\(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue) hasMarkedText=\(hasMarkedText())"
            )
            interpretKeyEvents([event])
            XTChatComposerDiagnostics.log(
                diagnosticScope,
                "keyDown after interpret stringLength=\(string.count) selectedRange=\(NSStringFromRange(selectedRange())) hasMarkedText=\(hasMarkedText())"
            )
        }

        override func insertText(_ insertString: Any, replacementRange: NSRange) {
            let text: String
            if let string = insertString as? String {
                text = string
            } else if let attributed = insertString as? NSAttributedString {
                text = attributed.string
            } else {
                text = String(describing: insertString)
            }
            XTChatComposerDiagnostics.log(
                diagnosticScope,
                "insertText text=\(text.debugDescription) replacementRange=\(NSStringFromRange(replacementRange))"
            )
            super.insertText(insertString, replacementRange: replacementRange)
        }

        override func setMarkedText(
            _ string: Any,
            selectedRange: NSRange,
            replacementRange: NSRange
        ) {
            let text: String
            if let string = string as? String {
                text = string
            } else if let attributed = string as? NSAttributedString {
                text = attributed.string
            } else {
                text = String(describing: string)
            }
            XTChatComposerDiagnostics.log(
                diagnosticScope,
                "setMarkedText text=\(text.debugDescription) selectedRange=\(NSStringFromRange(selectedRange)) replacementRange=\(NSStringFromRange(replacementRange))"
            )
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        }

        override func doCommand(by selector: Selector) {
            let selectorName = NSStringFromSelector(selector)
            let currentEvent = NSApp.currentEvent
            XTChatComposerDiagnostics.log(
                diagnosticScope,
                "doCommand selector=\(selectorName) eventKeyCode=\(currentEvent?.keyCode ?? .zero) modifiers=\(currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue ?? .zero)"
            )

            if selector == #selector(insertNewline(_:))
                || selector == #selector(insertNewlineIgnoringFieldEditor(_:))
                || selector == #selector(insertLineBreak(_:)) {
                let event = currentEvent
                if XTChatComposerKeyHandling.shouldSubmit(
                    keyCode: event?.keyCode ?? 36,
                    modifierFlags: event?.modifierFlags ?? [],
                    hasMarkedText: hasMarkedText()
                ) {
                    if canSubmit {
                        XTChatComposerDiagnostics.log(
                            diagnosticScope,
                            "doCommand submitTriggered selector=\(selectorName)"
                        )
                        onSubmit?()
                    } else {
                        XTChatComposerDiagnostics.log(
                            diagnosticScope,
                            "doCommand submitBlocked selector=\(selectorName)"
                        )
                    }
                    return
                }
            }

            super.doCommand(by: selector)
        }

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            XTChatComposerDiagnostics.log(
                diagnosticScope,
                "becomeFirstResponder accepted=\(accepted) firstResponder=\(XTChatComposerDiagnostics.describe(window?.firstResponder))"
            )
            if accepted {
                focusChanged?(true)
            }
            return accepted
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            XTChatComposerDiagnostics.log(
                diagnosticScope,
                "viewDidMoveToWindow window=\(XTChatComposerDiagnostics.describe(window)) firstResponder=\(XTChatComposerDiagnostics.describe(window?.firstResponder))"
            )
            if pendingProgrammaticFocus {
                requestProgrammaticFocus()
            }
        }

        override func resignFirstResponder() -> Bool {
            let accepted = super.resignFirstResponder()
            XTChatComposerDiagnostics.log(
                diagnosticScope,
                "resignFirstResponder accepted=\(accepted) nextFirstResponder=\(XTChatComposerDiagnostics.describe(window?.firstResponder))"
            )
            if accepted {
                focusChanged?(false)
            }
            return accepted
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            updateFileDropState(using: sender)
                ? .copy
                : []
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            updateFileDropState(using: sender)
                ? .copy
                : []
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            clearFileDropState()
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            droppedFileURLs(from: sender.draggingPasteboard).isEmpty == false
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            defer { clearFileDropState() }
            let urls = droppedFileURLs(from: sender.draggingPasteboard)
            guard !urls.isEmpty else { return false }
            let localPoint = convert(sender.draggingLocation, from: nil)
            let intent = currentDropIntent ?? XTChatComposerFileDrop.intent(
                locationX: localPoint.x,
                width: bounds.width,
                allowsImportDrop: allowsImportDrop
            )
            fileDropHandler?(urls, intent)
            return true
        }

        override func concludeDragOperation(_ sender: NSDraggingInfo?) {
            clearFileDropState()
        }

        private func commonInit() {
            registerForDraggedTypes([.fileURL])
        }

        private func installOwnedTextSystemIfNeeded(initialWidth: CGFloat) {
            guard textStorage == nil || layoutManager == nil || textContainer == nil else { return }
            let owned = Self.makeOwnedTextSystem(initialWidth: initialWidth)
            replaceTextContainer(owned.textContainer)
            ownedTextStorage = owned.textStorage
            ownedLayoutManager = owned.layoutManager
            XTChatComposerDiagnostics.log(
                diagnosticScope,
                "installed owned text system width=\(max(initialWidth, 120))"
            )
        }

        private static func makeOwnedTextSystem(initialWidth: CGFloat) -> OwnedTextSystem {
            let textStorage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            let textContainer = NSTextContainer(
                size: NSSize(width: max(initialWidth, 120), height: CGFloat.greatestFiniteMagnitude)
            )
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            textStorage.addLayoutManager(layoutManager)
            layoutManager.addTextContainer(textContainer)
            return OwnedTextSystem(
                textStorage: textStorage,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
        }

        private func updateFileDropState(using sender: NSDraggingInfo) -> Bool {
            guard fileDropHandler != nil else {
                clearFileDropState()
                return false
            }
            let urls = droppedFileURLs(from: sender.draggingPasteboard)
            let accepted = !urls.isEmpty
            guard accepted else {
                clearFileDropState()
                return false
            }
            let localPoint = convert(sender.draggingLocation, from: nil)
            let intent = XTChatComposerFileDrop.intent(
                locationX: localPoint.x,
                width: bounds.width,
                allowsImportDrop: allowsImportDrop
            )
            currentDropIntent = intent
            fileDropHoverChanged?(true)
            fileDropIntentChanged?(intent)
            return accepted
        }

        private func clearFileDropState() {
            currentDropIntent = nil
            fileDropHoverChanged?(false)
            fileDropIntentChanged?(nil)
        }

        private func droppedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
            return XTChatComposerFileDrop.normalizedDroppedURLs(urls)
        }

        func requestProgrammaticFocus(force: Bool = false) {
            let requestedFocus = force || wantsProgrammaticFocus
            let windowAttached = window != nil

            XTChatComposerDiagnostics.log(
                diagnosticScope,
                "requestProgrammaticFocus force=\(force) requested=\(requestedFocus) windowAttached=\(windowAttached) firstBefore=\(XTChatComposerDiagnostics.describe(window?.firstResponder))"
            )

            if XTChatComposerFocusPolicy.shouldDeferProgrammaticFocus(
                isFocused: requestedFocus,
                windowAttached: windowAttached
            ) {
                pendingProgrammaticFocus = true
                XTChatComposerDiagnostics.log(
                    diagnosticScope,
                    "requestProgrammaticFocus deferred pendingProgrammaticFocus=true"
                )
                return
            }

            pendingProgrammaticFocus = false

            guard let window else { return }
            guard XTChatComposerFocusPolicy.shouldRequestProgrammaticFocus(
                isFocused: requestedFocus,
                alreadyFirstResponder: window.firstResponder === self
            ) else {
                XTChatComposerDiagnostics.log(
                    diagnosticScope,
                    "requestProgrammaticFocus skipped alreadyFirstResponder=\(window.firstResponder === self)"
                )
                return
            }

            if force {
                let accepted = window.makeFirstResponder(self)
                XTChatComposerDiagnostics.log(
                    diagnosticScope,
                    "requestProgrammaticFocus forceResult=\(accepted) firstAfter=\(XTChatComposerDiagnostics.describe(window.firstResponder))"
                )
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.wantsProgrammaticFocus else { return }
                let accepted = self.window?.makeFirstResponder(self) ?? false
                XTChatComposerDiagnostics.log(
                    self.diagnosticScope,
                    "requestProgrammaticFocus asyncResult=\(accepted) firstAfter=\(XTChatComposerDiagnostics.describe(self.window?.firstResponder))"
                )
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ComposerScrollView()
        scrollView.diagnosticScope = diagnosticScope
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        let textView = ComposerTextView(
            frame: NSRect(x: 0, y: 0, width: 200, height: 44),
            textContainer: nil
        )
        textView.diagnosticScope = diagnosticScope
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = NSColor.clear
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.labelColor
        textView.textContainerInset = NSSize(width: 2, height: 6)
        textView.font = font
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = false
        textView.usesFindBar = false
        textView.focusRingType = NSFocusRingType.none
        textView.allowsUndo = true
        textView.minSize = NSSize(width: 0, height: 44)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.focusChanged = { (focused: Bool) in
            DispatchQueue.main.async {
                if context.coordinator.parent.isFocused != focused {
                    context.coordinator.parent.isFocused = focused
                }
            }
        }
        textView.fileDropHoverChanged = { (hovering: Bool) in
            DispatchQueue.main.async {
                context.coordinator.parent.onDropHoverChange?(hovering)
            }
        }
        textView.fileDropIntentChanged = { intent in
            DispatchQueue.main.async {
                context.coordinator.parent.onDropIntentChange?(intent)
            }
        }

        scrollView.documentView = textView
        XTChatComposerDiagnostics.log(
            diagnosticScope,
            "makeNSView logURL=\(XTChatComposerDiagnostics.logURL.path)"
        )
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = nsView.documentView as? ComposerTextView else { return }

        if let scrollView = nsView as? ComposerScrollView {
            scrollView.diagnosticScope = diagnosticScope
        }
        textView.diagnosticScope = diagnosticScope
        textView.font = font
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.labelColor
        textView.canSubmit = canSubmit
        textView.onSubmit = onSubmit
        textView.allowsImportDrop = allowsImportDrop
        textView.fileDropHandler = onDropFiles
        textView.wantsProgrammaticFocus = isFocused
        textView.fileDropHoverChanged = { (hovering: Bool) in
            DispatchQueue.main.async {
                context.coordinator.parent.onDropHoverChange?(hovering)
            }
        }
        textView.fileDropIntentChanged = { intent in
            DispatchQueue.main.async {
                context.coordinator.parent.onDropIntentChange?(intent)
            }
        }

        if XTChatComposerSyncPolicy.shouldApplyExternalText(
            currentViewText: textView.string,
            externalText: text,
            hasMarkedText: textView.hasMarkedText()
        ) {
            textView.string = text
            let cursor = NSRange(location: (text as NSString).length, length: 0)
            textView.setSelectedRange(cursor)
        }

        let width = max(120, nsView.contentSize.width)
        let viewportHeight = max(44, nsView.contentSize.height)
        let minimumLineHeight = {
            guard let layoutManager = textView.layoutManager,
                  let font = textView.font else {
                return CGFloat(18)
            }
            return layoutManager.defaultLineHeight(for: font)
        }()
        let insetHeight = textView.textContainerInset.height * 2
        let usedRectHeight: CGFloat = {
            guard let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager else {
                return 0
            }
            layoutManager.ensureLayout(for: textContainer)
            return layoutManager.usedRect(for: textContainer).height
        }()
        let height = XTChatComposerLayoutPolicy.documentHeight(
            viewportHeight: viewportHeight,
            usedRectHeight: usedRectHeight,
            insetHeight: insetHeight,
            minimumLineHeight: minimumLineHeight
        )
        textView.frame.size = NSSize(width: width, height: height)
        textView.minSize.height = viewportHeight
        textView.textContainer?.containerSize = NSSize(
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        )

        textView.requestProgrammaticFocus()
        textView.window?.invalidateCursorRects(for: textView)
        nsView.window?.invalidateCursorRects(for: nsView)
        XTChatComposerDiagnostics.log(
            diagnosticScope,
            "updateNSView focused=\(isFocused) editable=\(isEditable) canSubmit=\(canSubmit) draftLength=\(text.count) firstResponder=\(XTChatComposerDiagnostics.describe(textView.window?.firstResponder))"
        )
    }
}
