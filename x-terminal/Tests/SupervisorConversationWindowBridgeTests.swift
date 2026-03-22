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
            dedupeInterval: 60,
            windowVisibleProvider: { true }
        )
        var received: [SupervisorConversationWindowOpenRequest] = []
        let token = center.addObserver(
            forName: .xterminalOpenSupervisorWindow,
            object: nil,
            queue: nil
        ) { notification in
            received.append(SupervisorConversationWindowOpenRequest(notification: notification))
        }
        defer {
            center.removeObserver(token)
        }

        bridge.requestOpen(reason: "wake_1")
        bridge.requestOpen(reason: "wake_1")

        #expect(
            received == [
                SupervisorConversationWindowOpenRequest(reason: "wake_1")
            ]
        )
    }

    @Test
    func differentOpenRequestsAreNotDedupedWithinCooldown() {
        let center = NotificationCenter()
        let bridge = SupervisorConversationWindowBridge(
            notificationCenter: center,
            dedupeInterval: 60,
            windowVisibleProvider: { true }
        )
        var received: [SupervisorConversationWindowOpenRequest] = []
        let token = center.addObserver(
            forName: .xterminalOpenSupervisorWindow,
            object: nil,
            queue: nil
        ) { notification in
            received.append(SupervisorConversationWindowOpenRequest(notification: notification))
        }
        defer {
            center.removeObserver(token)
        }

        bridge.requestOpen(reason: "wake_1")
        bridge.requestOpen(reason: "pending_hub_grant:demo", focusConversation: false)

        #expect(
            received == [
                SupervisorConversationWindowOpenRequest(reason: "wake_1"),
                SupervisorConversationWindowOpenRequest(
                    reason: "pending_hub_grant:demo",
                    focusConversation: false
                )
            ]
        )
    }

    @Test
    func notificationPayloadCarriesFocusConversationPreference() {
        let center = NotificationCenter()
        let bridge = SupervisorConversationWindowBridge(
            notificationCenter: center,
            dedupeInterval: 60,
            windowVisibleProvider: { true }
        )
        var received: SupervisorConversationWindowOpenRequest?
        let token = center.addObserver(
            forName: .xterminalOpenSupervisorWindow,
            object: nil,
            queue: nil
        ) { notification in
            received = SupervisorConversationWindowOpenRequest(notification: notification)
        }
        defer {
            center.removeObserver(token)
        }

        bridge.requestOpen(
            reason: "pending_local_skill_approval:demo",
            focusConversation: false
        )

        #expect(
            received == SupervisorConversationWindowOpenRequest(
                reason: "pending_local_skill_approval:demo",
                focusConversation: false
            )
        )
    }

    @Test
    func sameReasonWithDifferentFocusPreferenceIsNotDeduped() {
        let center = NotificationCenter()
        let bridge = SupervisorConversationWindowBridge(
            notificationCenter: center,
            dedupeInterval: 60,
            windowVisibleProvider: { true }
        )
        var received: [SupervisorConversationWindowOpenRequest] = []
        let token = center.addObserver(
            forName: .xterminalOpenSupervisorWindow,
            object: nil,
            queue: nil
        ) { notification in
            received.append(SupervisorConversationWindowOpenRequest(notification: notification))
        }
        defer {
            center.removeObserver(token)
        }

        bridge.requestOpen(reason: "deep_link_supervisor", focusConversation: true)
        bridge.requestOpen(reason: "deep_link_supervisor", focusConversation: false)

        #expect(
            received == [
                SupervisorConversationWindowOpenRequest(
                    reason: "deep_link_supervisor",
                    focusConversation: true
                ),
                SupervisorConversationWindowOpenRequest(
                    reason: "deep_link_supervisor",
                    focusConversation: false
                )
            ]
        )
        #expect(
            bridge.latestRequest == SupervisorConversationWindowOpenRequest(
                reason: "deep_link_supervisor",
                focusConversation: false
            )
        )
    }

    @Test
    func repeatedOpenRequestIsNotDedupedAfterWindowBecomesHidden() {
        let center = NotificationCenter()
        var isWindowVisible = true
        let bridge = SupervisorConversationWindowBridge(
            notificationCenter: center,
            dedupeInterval: 60,
            windowVisibleProvider: { isWindowVisible }
        )
        var received: [SupervisorConversationWindowOpenRequest] = []
        let token = center.addObserver(
            forName: .xterminalOpenSupervisorWindow,
            object: nil,
            queue: nil
        ) { notification in
            received.append(SupervisorConversationWindowOpenRequest(notification: notification))
        }
        defer {
            center.removeObserver(token)
        }

        bridge.requestOpen(reason: "wake_1")
        isWindowVisible = false
        bridge.requestOpen(reason: "wake_1")

        #expect(
            received == [
                SupervisorConversationWindowOpenRequest(reason: "wake_1"),
                SupervisorConversationWindowOpenRequest(reason: "wake_1")
            ]
        )
        #expect(bridge.latestRequest == SupervisorConversationWindowOpenRequest(reason: "wake_1"))
    }
}
