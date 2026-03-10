import Foundation
import Testing
@testable import XTerminal

private enum SplitFlowFixtureError: Error {
    case invalidJSON
    case missingSchemaVersion
    case unsupportedSchemaVersion(String)
    case malformedSnapshotCase
}

private func loadSplitFlowSnapshotFixtureCases(
    named fixtureName: String = "split_flow_snapshot.sample.json",
    expectedSchemaVersion: String = "xterminal.split_flow_snapshot_fixture.v1"
) throws -> [(caseID: String, snapshot: SplitFlowSnapshot)] {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let packageRoot = testFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fixtureURL = packageRoot.appendingPathComponent("scripts/fixtures/\(fixtureName)")

    let data = try Data(contentsOf: fixtureURL)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SplitFlowFixtureError.invalidJSON
    }
    guard let schemaVersion = root["schema_version"] as? String else {
        throw SplitFlowFixtureError.missingSchemaVersion
    }
    guard schemaVersion == expectedSchemaVersion else {
        throw SplitFlowFixtureError.unsupportedSchemaVersion(schemaVersion)
    }
    guard let cases = root["snapshots"] as? [[String: Any]] else {
        throw SplitFlowFixtureError.invalidJSON
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    return try cases.map { item in
        guard let caseID = item["case_id"] as? String,
              let snapshotRaw = item["snapshot"] as? [String: Any] else {
            throw SplitFlowFixtureError.malformedSnapshotCase
        }
        let snapshotData = try JSONSerialization.data(withJSONObject: snapshotRaw)
        let snapshot = try decoder.decode(SplitFlowSnapshot.self, from: snapshotData)
        return (caseID: caseID, snapshot: snapshot)
    }
}

struct SplitFlowContractTests {

    @Test
    func splitProposalFlowStateMachineContractRemainsStable() {
        #expect(SplitProposalFlowState.stateMachineVersion == "xterminal.split_flow_state_machine.v1")

        #expect(SplitProposalFlowState.idle.canTransition(to: .proposing))
        #expect(SplitProposalFlowState.proposing.canTransition(to: .proposed))
        #expect(SplitProposalFlowState.proposed.canTransition(to: .overridden))
        #expect(SplitProposalFlowState.overridden.canTransition(to: .confirmed))
        #expect(SplitProposalFlowState.blocked.canTransition(to: .blocked))
        #expect(SplitProposalFlowState.confirmed.canTransition(to: .idle))

        #expect(SplitProposalFlowState.idle.canTransition(to: .confirmed) == false)
        #expect(SplitProposalFlowState.rejected.canTransition(to: .confirmed) == false)

        let blockedTransitions = SplitProposalFlowState.allowedTransitions(from: .blocked)
        #expect(blockedTransitions.contains(.proposed))
        #expect(blockedTransitions.contains(.overridden))
        #expect(blockedTransitions.contains(.confirmed))
        #expect(blockedTransitions.contains(.idle))
    }

    @MainActor
    @Test
    func splitFlowSnapshotCapturesOverrideReplayAndAuditFields() async throws {
        let supervisor = SupervisorModel()
        let orchestrator = supervisor.orchestrator!

        let buildResult = await orchestrator.proposeSplit(for: "拆分并行任务，随后覆盖并回放")
        let laneID = try #require(buildResult.proposal.lanes.first?.laneId)

        let proposedSnapshot = orchestrator.splitFlowSnapshot()
        #expect(proposedSnapshot.schema == SplitFlowSnapshot.schema)
        #expect(proposedSnapshot.version == SplitFlowSnapshot.version)
        #expect(proposedSnapshot.stateMachineVersion == SplitProposalFlowState.stateMachineVersion)
        #expect(proposedSnapshot.flowState == .proposed)
        #expect(proposedSnapshot.laneCount == buildResult.proposal.lanes.count)
        #expect(proposedSnapshot.overrideCount == 0)
        #expect(proposedSnapshot.overrideLaneIDs.isEmpty)
        #expect(proposedSnapshot.lastAuditEventType == .splitProposed)

        let overrideResult = try #require(
            orchestrator.overrideActiveSplitProposal(
                [SplitLaneOverride(laneId: laneID, note: "snapshot_contract")],
                reason: "snapshot_override"
            )
        )
        #expect(overrideResult.validation.hasBlockingIssues == false)

        let overriddenSnapshot = orchestrator.splitFlowSnapshot()
        #expect(overriddenSnapshot.flowState == .overridden)
        #expect(overriddenSnapshot.overrideCount == 1)
        #expect(overriddenSnapshot.overrideLaneIDs == [laneID])
        #expect(overriddenSnapshot.lastAuditEventType == .splitOverridden)

        let replayResult = try #require(orchestrator.replayActiveSplitProposalOverrides())
        #expect(replayResult.validation.hasBlockingIssues == false)

        let replaySnapshot = orchestrator.splitFlowSnapshot()
        #expect(replaySnapshot.flowState == .overridden)
        #expect(replaySnapshot.replayConsistent == true)
        #expect(replaySnapshot.lastAuditEventType == .splitOverridden)
    }

    @MainActor
    @Test
    func splitFlowSnapshotCapturesPromptLintBlocking() async throws {
        let supervisor = SupervisorModel()
        let orchestrator = supervisor.orchestrator!

        _ = await orchestrator.proposeSplit(for: " ")
        let compilation = try #require(orchestrator.confirmActiveSplitProposal(globalContext: "snapshot_lint"))
        #expect(compilation.status == .rejected)
        #expect(compilation.lintResult.blockingIssues.contains(where: { $0.code == "missing_goal" }))

        let snapshot = orchestrator.splitFlowSnapshot()
        #expect(snapshot.flowState == .blocked)
        #expect(snapshot.promptStatus == .rejected)
        #expect(snapshot.promptCoverage != nil)
        #expect(snapshot.promptBlockingLintCodes.contains("missing_goal"))
        #expect(snapshot.lastAuditEventType == .promptRejected)
    }

    @Test
    func splitFlowSnapshotFixtureRemainsDecodableAndTransitionSafe() throws {
        let fixtureCases = try loadSplitFlowSnapshotFixtureCases()
        #expect(fixtureCases.count == 4)

        let requiredStates: Set<SplitProposalFlowState> = [.proposed, .overridden, .blocked, .confirmed]
        let fixtureStates = Set(fixtureCases.map { $0.snapshot.flowState })
        #expect(requiredStates.isSubset(of: fixtureStates))

        for index in 1..<fixtureCases.count {
            let previous = fixtureCases[index - 1].snapshot.flowState
            let current = fixtureCases[index].snapshot.flowState
            #expect(previous.canTransition(to: current))
        }

        let firstSnapshot = try #require(fixtureCases.first?.snapshot)
        #expect(firstSnapshot.schema == SplitFlowSnapshot.schema)
        #expect(firstSnapshot.version == SplitFlowSnapshot.version)
        #expect(firstSnapshot.stateMachineVersion == SplitProposalFlowState.stateMachineVersion)
    }
}
