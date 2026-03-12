import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorConversationSessionControllerTests {

    @Test
    func manualOpenAndTimeoutReturnHiddenForPushToTalk() {
        var now = Date(timeIntervalSince1970: 1_000)
        let controller = SupervisorConversationSessionController.makeForTesting(
            nowProvider: { now }
        )

        #expect(controller.snapshot.windowState == .hidden)

        controller.manualOpen()
        let conversationId = controller.snapshot.conversationId

        #expect(controller.snapshot.windowState == .conversing)
        #expect(controller.snapshot.openedBy == .manualButton)
        #expect(controller.snapshot.remainingTTLSeconds == 45)
        #expect(conversationId != nil)

        now = now.addingTimeInterval(20)
        controller.refresh()
        #expect(controller.snapshot.remainingTTLSeconds == 25)

        controller.registerAssistantTurn(spoken: true)
        #expect(controller.snapshot.conversationId == conversationId)
        #expect(controller.snapshot.reasonCode == "tts_spoken")
        #expect(controller.snapshot.remainingTTLSeconds == 45)

        now = now.addingTimeInterval(46)
        controller.refresh()

        #expect(controller.snapshot.windowState == .hidden)
        #expect(controller.snapshot.remainingTTLSeconds == 0)
        #expect(controller.snapshot.reasonCode == "ttl_expired")
    }

    @Test
    func wakeHitOpensConversationAndTimeoutReturnsArmedWhenWakePhraseEnabled() {
        var now = Date(timeIntervalSince1970: 2_000)
        let controller = SupervisorConversationSessionController.makeForTesting(
            route: .funasrStreaming,
            wakeMode: .wakePhrase,
            nowProvider: { now }
        )

        #expect(controller.snapshot.windowState == .armed)

        controller.registerWakeHit()
        #expect(controller.snapshot.windowState == .conversing)
        #expect(controller.snapshot.openedBy == .wakePhrase)
        #expect(controller.snapshot.route == .funasrStreaming)

        now = now.addingTimeInterval(46)
        controller.refresh()

        #expect(controller.snapshot.windowState == .armed)
        #expect(controller.snapshot.reasonCode == "ttl_expired")
    }

    @Test
    func routeFailClosedEndsActiveConversationImmediately() {
        var now = Date(timeIntervalSince1970: 3_000)
        let controller = SupervisorConversationSessionController.makeForTesting(
            route: .systemSpeechCompatibility,
            wakeMode: .promptPhraseOnly,
            nowProvider: { now }
        )

        controller.manualOpen()
        #expect(controller.snapshot.windowState == .conversing)

        now = now.addingTimeInterval(5)
        controller.registerRouteFailClosed(reasonCode: "bridge_heartbeat_missing")

        #expect(controller.snapshot.windowState == .armed)
        #expect(controller.snapshot.reasonCode == "bridge_heartbeat_missing")
        #expect(controller.snapshot.remainingTTLSeconds == 0)
    }

    @Test
    func wakeHitDoesNotOpenConversationWhenPushToTalkIsEffective() {
        let controller = SupervisorConversationSessionController.makeForTesting(
            route: .funasrStreaming,
            wakeMode: .pushToTalk,
            nowProvider: { Date(timeIntervalSince1970: 4_000) }
        )

        controller.registerWakeHit()

        #expect(controller.snapshot.windowState == .hidden)
        #expect(controller.snapshot.openedBy == nil)
    }
}
