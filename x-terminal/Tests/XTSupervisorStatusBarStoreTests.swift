import Testing
@testable import XTerminal

struct XTSupervisorStatusBarStoreTests {
    @Test
    @MainActor
    func statusBarStoreTracksSupervisorExecutionProjection() async {
        let supervisor = SupervisorManager.makeForTesting(
            enableAutomaticSupervisorMemorySnapshotRefresh: false
        )
        let store = XTSupervisorStatusBarStore()
        store.bind(to: supervisor)

        supervisor.recordSupervisorReplyExecutionForTesting(
            mode: "remote_model",
            actualModelId: "openai/gpt-5.4",
            requestedModelId: "openai/gpt-5.4"
        )
        await Task.yield()

        #expect(store.snapshot.executionSnapshot.executionPath == "remote_model")
        #expect(store.snapshot.executionSnapshot.actualModelId == "openai/gpt-5.4")
        #expect(store.snapshot.executionSnapshot.runtimeProvider == "Hub (Remote)")
    }

    @Test
    @MainActor
    func statusBarStoreSuppressesIdenticalSnapshots() {
        let snapshot = XTSupervisorStatusBarSnapshot(
            executionSnapshot: .empty(role: .supervisor, source: "test"),
            pendingMemoryFollowUpQuestion: "",
            activeProjectCount: 1,
            totalProjectCount: 2,
            pendingWorkCount: 0,
            blockedProjectCount: 0,
            completedProjectCount: 1
        )
        let store = XTSupervisorStatusBarStore(snapshot: snapshot)

        #expect(store.snapshot == snapshot)
    }
}
