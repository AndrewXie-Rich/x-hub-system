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

    @Test
    func stabilizedScavengesStaleBusyRuntimeWithoutRecoveryPath() {
        let runtime = AXSessionRuntimeSnapshot(
            schemaVersion: AXSessionRuntimeSnapshot.currentSchemaVersion,
            state: .planning,
            runID: "run-stale-1",
            updatedAt: 100,
            startedAt: 90,
            completedAt: nil,
            lastRuntimeSummary: "planning first reply",
            lastToolBatchIDs: ["tool-a"],
            pendingToolCallCount: 1,
            lastFailureCode: nil,
            resumeToken: "run-stale-1",
            recoverable: false
        )

        let stabilized = runtime.stabilized(
            now: 100 + AXSessionRuntimeSnapshot.staleBusyScavengeAfterSeconds + 1
        )

        #expect(stabilized.state == .failed_recoverable)
        #expect(stabilized.lastFailureCode == "stale_session_runtime_scavenged")
        #expect(stabilized.lastRuntimeSummary?.contains("stale_session_runtime_scavenged") == true)
        #expect(stabilized.pendingToolCallCount == 0)
        #expect(stabilized.lastToolBatchIDs.isEmpty)
        #expect(stabilized.resumeToken == nil)
        #expect(stabilized.recoverable == false)
        #expect(stabilized.completedAt == 100 + AXSessionRuntimeSnapshot.staleBusyScavengeAfterSeconds + 1)
    }

    @Test
    func stabilizedKeepsAwaitingApprovalRecoverableRuntimeIntact() {
        let runtime = AXSessionRuntimeSnapshot(
            schemaVersion: AXSessionRuntimeSnapshot.currentSchemaVersion,
            state: .awaiting_tool_approval,
            runID: "run-approval-1",
            updatedAt: 100,
            startedAt: 90,
            completedAt: nil,
            lastRuntimeSummary: "awaiting approval",
            lastToolBatchIDs: ["tool-a"],
            pendingToolCallCount: 1,
            lastFailureCode: nil,
            resumeToken: "tool_approval:run-approval-1",
            recoverable: true
        )

        let stabilized = runtime.stabilized(
            now: 100 + AXSessionRuntimeSnapshot.staleBusyScavengeAfterSeconds + 1
        )

        #expect(stabilized.state == .awaiting_tool_approval)
        #expect(stabilized.pendingToolCallCount == 1)
        #expect(stabilized.resumeToken == "tool_approval:run-approval-1")
        #expect(stabilized.recoverable == true)
    }

    @MainActor
    @Test
    func loadSessionsRecoversInterruptedBusyRuntimeToIdle() throws {
        let suiteName = "xterminal.session.runtime.restore.tests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.removePersistentDomain(forName: suiteName)

        let persisted = AXSessionInfo(
            id: "session-restore-1",
            projectId: "project-restore",
            title: "Restore",
            directory: "/tmp/restore",
            parentId: nil,
            createdAt: 100,
            updatedAt: 100,
            version: "1.0",
            summary: nil,
            runtime: AXSessionRuntimeSnapshot(
                schemaVersion: AXSessionRuntimeSnapshot.currentSchemaVersion,
                state: .awaiting_model,
                runID: "run-restore-1",
                updatedAt: 100,
                startedAt: 90,
                completedAt: nil,
                lastRuntimeSummary: "waiting for remote model",
                lastToolBatchIDs: ["tool-restore"],
                pendingToolCallCount: 1,
                lastFailureCode: nil,
                resumeToken: "run-restore-1",
                recoverable: false
            )
        )
        let encoded = try JSONEncoder().encode([persisted])
        userDefaults.set(encoded, forKey: "xterminal_sessions")

        let manager = AXSessionManager(userDefaults: userDefaults, observeEvents: false)
        let runtime = try #require(manager.session(for: persisted.id)?.runtime)

        #expect(runtime.state == .idle)
        #expect(runtime.pendingToolCallCount == 0)
        #expect(runtime.lastToolBatchIDs.isEmpty)
        #expect(runtime.resumeToken == nil)
        #expect(runtime.lastFailureCode == AXSessionRuntimeSnapshot.restoredInterruptedFailureCode)
        #expect(runtime.lastRuntimeSummary?.contains("waiting for remote model") == true)
    }

    @MainActor
    @Test
    func loadSessionsPreservesAwaitingApprovalAcrossRestart() throws {
        let suiteName = "xterminal.session.runtime.restore.approval.tests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.removePersistentDomain(forName: suiteName)

        let persisted = AXSessionInfo(
            id: "session-approval-1",
            projectId: "project-approval",
            title: "Approval",
            directory: "/tmp/approval",
            parentId: nil,
            createdAt: 100,
            updatedAt: 100,
            version: "1.0",
            summary: nil,
            runtime: AXSessionRuntimeSnapshot(
                schemaVersion: AXSessionRuntimeSnapshot.currentSchemaVersion,
                state: .awaiting_tool_approval,
                runID: "run-approval-restore-1",
                updatedAt: 100,
                startedAt: 90,
                completedAt: nil,
                lastRuntimeSummary: "awaiting approval",
                lastToolBatchIDs: ["tool-approval"],
                pendingToolCallCount: 1,
                lastFailureCode: nil,
                resumeToken: "tool_approval:run-approval-restore-1",
                recoverable: true
            )
        )
        let encoded = try JSONEncoder().encode([persisted])
        userDefaults.set(encoded, forKey: "xterminal_sessions")

        let manager = AXSessionManager(userDefaults: userDefaults, observeEvents: false)
        let runtime = try #require(manager.session(for: persisted.id)?.runtime)

        #expect(runtime.state == .awaiting_tool_approval)
        #expect(runtime.pendingToolCallCount == 1)
        #expect(runtime.resumeToken == "tool_approval:run-approval-restore-1")
        #expect(runtime.lastFailureCode == nil)
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
