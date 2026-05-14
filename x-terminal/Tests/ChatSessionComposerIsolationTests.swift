import Combine
import Testing
@testable import XTerminal

@MainActor
struct ChatSessionComposerIsolationTests {

    @Test
    func draftChangePublishesComposerWithoutPublishingSession() {
        let session = ChatSessionModel()
        var sessionUpdates = 0
        var composerUpdates = 0
        var cancellables = Set<AnyCancellable>()

        session.objectWillChange
            .sink { sessionUpdates += 1 }
            .store(in: &cancellables)
        session.composer.objectWillChange
            .sink { composerUpdates += 1 }
            .store(in: &cancellables)

        session.draft = "继续优化输入性能"

        #expect(session.draft == "继续优化输入性能")
        #expect(session.composer.draft == "继续优化输入性能")
        #expect(sessionUpdates == 0)
        #expect(composerUpdates == 1)
    }

    @Test
    func messageChangeStillPublishesSession() {
        let session = ChatSessionModel()
        var sessionUpdates = 0
        var cancellables = Set<AnyCancellable>()

        session.objectWillChange
            .sink { sessionUpdates += 1 }
            .store(in: &cancellables)

        session.messages = [
            AXChatMessage(role: .user, content: "hello", createdAt: 1)
        ]

        #expect(sessionUpdates == 1)
    }
}
