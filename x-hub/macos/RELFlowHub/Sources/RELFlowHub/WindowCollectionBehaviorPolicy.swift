import AppKit

enum WindowCollectionBehaviorPolicy {
    static func mainPanel() -> NSWindow.CollectionBehavior {
        // macOS rejects combining `.canJoinAllSpaces` with `.moveToActiveSpace`.
        // The main panel should follow the active desktop when reopened.
        [.fullScreenAuxiliary, .moveToActiveSpace]
    }

    static func floatingPanel() -> NSWindow.CollectionBehavior {
        // Keep the orb/card available across spaces without forcing a move.
        [.fullScreenAuxiliary, .canJoinAllSpaces]
    }

    static func isValid(_ behavior: NSWindow.CollectionBehavior) -> Bool {
        !(behavior.contains(.canJoinAllSpaces) && behavior.contains(.moveToActiveSpace))
    }
}
