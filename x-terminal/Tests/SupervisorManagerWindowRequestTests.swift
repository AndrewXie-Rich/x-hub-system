import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorManagerWindowRequestTests {

    @Test
    func manualWindowRequestStartsConversationSession() {
        let controller = SupervisorConversationSessionController.makeForTesting(
            nowProvider: { Date(timeIntervalSince1970: 7_000) }
        )
        let manager = SupervisorManager.makeForTesting(
            conversationSessionController: controller
        )

        manager.requestSupervisorWindow(reason: "status_bar")

        #expect(manager.conversationSessionSnapshot.windowState == .conversing)
        #expect(manager.conversationSessionSnapshot.openedBy == .manualButton)
        #expect(manager.conversationSessionSnapshot.reasonCode == "manual_open")
        #expect(manager.conversationSessionSnapshot.remainingTTLSeconds == 45)
    }

    @Test
    func sheetWindowRequestDefaultsToNoConversationFocusAndKeepsConversationSessionIdle() {
        let controller = SupervisorConversationSessionController.makeForTesting(
            nowProvider: { Date(timeIntervalSince1970: 7_100) }
        )
        let manager = SupervisorManager.makeForTesting(
            conversationSessionController: controller
        )
        let reason = "deep_link_supervisor_settings_\(UUID().uuidString)"
        var receivedRequest: SupervisorConversationWindowOpenRequest?
        let token = NotificationCenter.default.addObserver(
            forName: .xterminalOpenSupervisorWindow,
            object: nil,
            queue: nil
        ) { notification in
            let request = SupervisorConversationWindowOpenRequest(notification: notification)
            if request.reason == reason {
                receivedRequest = request
            }
        }
        defer {
            NotificationCenter.default.removeObserver(token)
        }

        manager.requestSupervisorWindow(
            sheet: .supervisorSettings,
            reason: reason
        )

        #expect(
            receivedRequest == SupervisorConversationWindowOpenRequest(
                reason: reason,
                focusConversation: false
            )
        )
        #expect(manager.requestedWindowSheet == .supervisorSettings)
        #expect(manager.conversationSessionSnapshot.windowState == .hidden)
        #expect(manager.conversationSessionSnapshot.reasonCode == "none")
        #expect(manager.conversationSessionSnapshot.remainingTTLSeconds == 0)
    }

    @Test
    func explicitNoConversationStartStillOpensWindowWithoutFocusingComposer() {
        let controller = SupervisorConversationSessionController.makeForTesting(
            nowProvider: { Date(timeIntervalSince1970: 7_200) }
        )
        let manager = SupervisorManager.makeForTesting(
            conversationSessionController: controller
        )
        let reason = "deep_link_supervisor_focus_only_\(UUID().uuidString)"
        var receivedRequest: SupervisorConversationWindowOpenRequest?
        let token = NotificationCenter.default.addObserver(
            forName: .xterminalOpenSupervisorWindow,
            object: nil,
            queue: nil
        ) { notification in
            let request = SupervisorConversationWindowOpenRequest(notification: notification)
            if request.reason == reason {
                receivedRequest = request
            }
        }
        defer {
            NotificationCenter.default.removeObserver(token)
        }

        manager.requestSupervisorWindow(
            reason: reason,
            focusConversation: false,
            startConversation: false
        )

        #expect(
            receivedRequest == SupervisorConversationWindowOpenRequest(
                reason: reason,
                focusConversation: false
            )
        )
        #expect(manager.requestedWindowSheet == nil)
        #expect(manager.conversationSessionSnapshot.windowState == .hidden)
        #expect(manager.conversationSessionSnapshot.reasonCode == "none")
        #expect(manager.conversationSessionSnapshot.remainingTTLSeconds == 0)
    }

    @Test
    func focusOnlyWindowRequestDoesNotResetActiveConversationSession() {
        let controller = SupervisorConversationSessionController.makeForTesting(
            nowProvider: { Date(timeIntervalSince1970: 7_300) }
        )
        let manager = SupervisorManager.makeForTesting(
            conversationSessionController: controller
        )
        manager.requestSupervisorWindow(reason: "status_bar")
        let snapshotBeforeFocusOnlyOpen = manager.conversationSessionSnapshot
        let reason = "deep_link_supervisor_focus_only_\(UUID().uuidString)"
        var receivedRequest: SupervisorConversationWindowOpenRequest?
        let token = NotificationCenter.default.addObserver(
            forName: .xterminalOpenSupervisorWindow,
            object: nil,
            queue: nil
        ) { notification in
            let request = SupervisorConversationWindowOpenRequest(notification: notification)
            if request.reason == reason {
                receivedRequest = request
            }
        }
        defer {
            NotificationCenter.default.removeObserver(token)
        }

        manager.requestSupervisorWindow(
            reason: reason,
            focusConversation: false,
            startConversation: false
        )

        #expect(
            receivedRequest == SupervisorConversationWindowOpenRequest(
                reason: reason,
                focusConversation: false
            )
        )
        #expect(manager.conversationSessionSnapshot == snapshotBeforeFocusOnlyOpen)
        #expect(manager.conversationSessionSnapshot.windowState == .conversing)
        #expect(manager.conversationSessionSnapshot.reasonCode == "manual_open")
        #expect(manager.conversationSessionSnapshot.openedBy == .manualButton)
    }

    @Test
    func repeatedManualWindowRequestDoesNotRestartActiveConversation() {
        var now = Date(timeIntervalSince1970: 7_400)
        let controller = SupervisorConversationSessionController.makeForTesting(
            nowProvider: { now }
        )
        let manager = SupervisorManager.makeForTesting(
            conversationSessionController: controller
        )

        manager.requestSupervisorWindow(reason: "status_bar")
        let firstSnapshot = manager.conversationSessionSnapshot

        now = now.addingTimeInterval(20)
        controller.refresh()
        let agedSnapshot = manager.conversationSessionSnapshot

        manager.requestSupervisorWindow(reason: "status_bar")

        #expect(firstSnapshot.conversationId != nil)
        #expect(agedSnapshot.remainingTTLSeconds == 25)
        #expect(manager.conversationSessionSnapshot.conversationId == firstSnapshot.conversationId)
        #expect(manager.conversationSessionSnapshot == agedSnapshot)
        #expect(manager.conversationSessionSnapshot.windowState == .conversing)
        #expect(manager.conversationSessionSnapshot.reasonCode == "manual_open")
    }
}
