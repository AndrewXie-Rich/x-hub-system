import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorConversationWindowBridgeTests {

    @Test
    func dedupeSuppressesRepeatedOpenRequestsWithinCooldown() {
        let center = NotificationCenter()
        let bridge = SupervisorConversationWindowBridge(
            notificationCenter: center,
            dedupeInterval: 60
        )
        var received: [String] = []
        let token = center.addObserver(
            forName: .xterminalOpenSupervisorWindow,
            object: nil,
            queue: nil
        ) { notification in
            received.append(notification.userInfo?["reason"] as? String ?? "")
        }
        defer {
            center.removeObserver(token)
        }

        bridge.requestOpen(reason: "wake_1")
        bridge.requestOpen(reason: "wake_2")

        #expect(received == ["wake_1"])
    }
}
