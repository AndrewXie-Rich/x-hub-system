import Foundation
import Testing
@testable import XTerminal

struct SessionRuntimeFoundationTests {

    @MainActor
    @Test
    func ensurePrimarySessionReturnsStableRootSessionPerProject() {
        let fixture = SessionRuntimeFixture()
        defer { fixture.cleanup() }

        let first = fixture.manager.ensurePrimarySession(
            projectId: "project-alpha",
            title: "Alpha",
            directory: "/tmp/alpha"
        )
        let second = fixture.manager.ensurePrimarySession(
            projectId: "project-alpha",
            title: "Alpha Renamed",
            directory: "/tmp/alpha"
        )

        #expect(first.id == second.id)
        #expect(fixture.manager.sessions.count == 1)
        #expect(second.parentId == nil)
        #expect(second.title == "Alpha")
        #expect(second.directory == "/tmp/alpha")
        #expect(second.runtime?.state == .idle)
        #expect(second.runtime?.pendingToolCallCount == 0)
    }

    @MainActor
    @Test
    func updateRuntimeTracksAwaitingApprovalThenCompletion() {
        let fixture = SessionRuntimeFixture()
        defer { fixture.cleanup() }

        let session = fixture.manager.ensurePrimarySession(
            projectId: "project-beta",
            title: "Beta",
            directory: "/tmp/beta"
        )

        fixture.manager.updateRuntime(sessionId: session.id, at: 100) { runtime in
            runtime.state = .awaiting_tool_approval
            runtime.runID = "run-beta-1"
            runtime.startedAt = 100
            runtime.lastRuntimeSummary = "awaiting approval"
            runtime.lastToolBatchIDs = ["tool-1", "tool-2"]
            runtime.pendingToolCallCount = 2
            runtime.resumeToken = "tool_approval:run-beta-1"
            runtime.recoverable = true
        }

        let pending = fixture.manager.session(for: session.id)?.runtime
        #expect(pending?.state == .awaiting_tool_approval)
        #expect(pending?.runID == "run-beta-1")
        #expect(pending?.lastToolBatchIDs == ["tool-1", "tool-2"])
        #expect(pending?.pendingToolCallCount == 2)
        #expect(pending?.resumeToken == "tool_approval:run-beta-1")
        #expect(pending?.recoverable == true)

        fixture.manager.updateRuntime(sessionId: session.id, at: 180) { runtime in
            runtime.state = .completed
            runtime.completedAt = 180
            runtime.lastRuntimeSummary = "done"
            runtime.lastToolBatchIDs = []
            runtime.pendingToolCallCount = 0
            runtime.lastFailureCode = nil
            runtime.resumeToken = nil
            runtime.recoverable = false
        }

        let completed = fixture.manager.session(for: session.id)?.runtime
        #expect(completed?.state == .completed)
        #expect(completed?.runID == "run-beta-1")
        #expect(completed?.startedAt == 100)
        #expect(completed?.completedAt == 180)
        #expect(completed?.pendingToolCallCount == 0)
        #expect(completed?.resumeToken == nil)
        #expect(completed?.recoverable == false)
    }

    @MainActor
    @Test
    func forkSessionStartsFromFreshIdleRuntimeSnapshot() {
        let fixture = SessionRuntimeFixture()
        defer { fixture.cleanup() }

        let original = fixture.manager.ensurePrimarySession(
            projectId: "project-gamma",
            title: "Gamma",
            directory: "/tmp/gamma"
        )

        fixture.manager.updateRuntime(sessionId: original.id, at: 240) { runtime in
            runtime.state = .awaiting_tool_approval
            runtime.runID = "run-gamma-1"
            runtime.startedAt = 200
            runtime.lastToolBatchIDs = ["tool-x"]
            runtime.pendingToolCallCount = 1
            runtime.resumeToken = "tool_approval:run-gamma-1"
            runtime.recoverable = true
        }

        let fork = fixture.manager.forkSession(original.id)

        #expect(fork != nil)
        #expect(fork?.parentId == original.id)
        #expect(fork?.directory == original.directory)
        #expect(fork?.runtime?.state == .idle)
        #expect(fork?.runtime?.runID == nil)
        #expect(fork?.runtime?.pendingToolCallCount == 0)
        #expect(fork?.runtime?.resumeToken == nil)
        #expect(fork?.runtime?.recoverable == false)
    }
}

@MainActor
private struct SessionRuntimeFixture {
    let suiteName: String
    let userDefaults: UserDefaults
    let manager: AXSessionManager

    init() {
        suiteName = "xterminal.session.runtime.tests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        manager = AXSessionManager(userDefaults: userDefaults, observeEvents: false)
    }

    func cleanup() {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}
