import AppKit

public enum WindowCollectionBehaviorPolicy {
    public static func mainPanel() -> NSWindow.CollectionBehavior {
        // macOS rejects combining `.canJoinAllSpaces` with `.moveToActiveSpace`.
        // The main panel should follow the active desktop when reopened.
        [.fullScreenAuxiliary, .moveToActiveSpace]
    }

    public static func floatingPanel() -> NSWindow.CollectionBehavior {
        // Keep the orb/card available across spaces without forcing a move.
        [.fullScreenAuxiliary, .canJoinAllSpaces]
    }

    public static func isValid(_ behavior: NSWindow.CollectionBehavior) -> Bool {
        !(behavior.contains(.canJoinAllSpaces) && behavior.contains(.moveToActiveSpace))
    }
}
