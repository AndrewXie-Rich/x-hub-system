import Testing
@testable import XTerminal

@MainActor
struct SupervisorLeanHeaderProjectionStoreTests {
    @Test
    func snapshotProjectsLeanHeaderInputs() {
        let manager = SupervisorManager.makeForTesting()
        let appModel = AppModel.makeForTesting()
        manager.messages = [
            SupervisorMessage(
                id: "assistant",
                role: .assistant,
                content: "reply",
                isVoice: false,
                timestamp: 1
            ),
            SupervisorMessage(
                id: "user",
                role: .user,
                content: "please build the new workflow",
                isVoice: false,
                timestamp: 2
            )
        ]
        manager.setRuntimeActivityEntriesForTesting([
            SupervisorManager.RuntimeActivityEntry(
                id: "runtime-1",
                createdAt: 10,
                text: "运行中"
            )
        ])

        let snapshot = SupervisorLeanHeaderProjectionSnapshot.make(
            supervisor: manager,
            appModel: appModel
        )

        #expect(snapshot.latestUserMessageContent == "please build the new workflow")
        #expect(snapshot.latestRuntimeActivityText == "运行中")
        #expect(snapshot.context.hasLatestRuntimeActivity)
    }

    @Test
    func storeTracksFocusProcessingAndPendingInputs() async {
        let manager = SupervisorManager.makeForTesting()
        let appModel = AppModel.makeForTesting()
        let store = SupervisorLeanHeaderProjectionStore()
        store.bind(supervisor: manager, appModel: appModel)

        appModel.requestSupervisorBoardFocus(anchorID: "overview")
        manager.processingStatusText = "正在调度"
        manager.setPendingHubGrantsForTesting([pendingGrant()])
        await Task.yield()

        #expect(store.snapshot.focusRequestNonce == 1)
        #expect(store.snapshot.processingStatusText == "正在调度")
        #expect(store.snapshot.pendingHubGrantCount == 1)
        #expect(store.snapshot.context.hasFocusRequest)
    }

    @Test
    func snapshotContextCanApplyVisibilityWithoutMutatingStoreState() {
        let snapshot = SupervisorLeanHeaderProjectionSnapshot.empty
        let visibleContext = snapshot.context(
            heartbeatFeedVisible: true,
            signalCenterVisible: true
        )

        #expect(visibleContext.isHeartbeatFeedVisible)
        #expect(visibleContext.isSignalCenterVisible)
        #expect(!snapshot.context.isHeartbeatFeedVisible)
        #expect(!snapshot.context.isSignalCenterVisible)
    }

    private func pendingGrant() -> SupervisorManager.SupervisorPendingGrant {
        SupervisorManager.SupervisorPendingGrant(
            id: "grant-1",
            dedupeKey: "grant:key",
            grantRequestId: "grant-1",
            requestId: "request-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            capability: "browser.control",
            modelId: "gpt-5.4",
            reason: "browser automation requested",
            requestedTtlSec: 600,
            requestedTokenCap: 4000,
            createdAt: 940,
            actionURL: "x-terminal://supervisor?grant=grant-1",
            priorityRank: 1,
            priorityReason: "critical path",
            nextAction: "approve now"
        )
    }
}
