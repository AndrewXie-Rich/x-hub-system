import AppKit
import Foundation
import SwiftUI

struct XTSupervisorWindowPresentationDecision: Equatable {
    var shouldOpenWindow: Bool
}

enum XTSupervisorWindowPresentationPolicy {
    static func decision(
        for request: SupervisorConversationWindowOpenRequest,
        isWindowVisible: Bool
    ) -> XTSupervisorWindowPresentationDecision {
        .init(
            shouldOpenWindow: request.focusConversation || !isWindowVisible
        )
    }
}

@MainActor
final class XTSupervisorWindowVisibilityRegistry {
    static let shared = XTSupervisorWindowVisibilityRegistry()

    private weak var window: NSWindow?

    var isWindowVisible: Bool {
        guard let window else { return false }
        return window.isVisible && !window.isMiniaturized
    }

    func track(window: NSWindow?) {
        self.window = window
    }
}

struct XTSupervisorWindowAccessor: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onWindowChange = onWindowChange
        DispatchQueue.main.async {
            nsView.onWindowChange(nsView.window)
        }
    }

    final class TrackingView: NSView {
        var onWindowChange: (NSWindow?) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange(window)
        }
    }
}
