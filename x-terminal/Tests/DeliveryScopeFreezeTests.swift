import Foundation
import Testing
@testable import XTerminal

struct DeliveryScopeFreezeTests {

    @Test
    func deliveryScopeFreezePassesForValidatedMainlineOnly() {
        let projectID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let freeze = DeliveryScopeFreezeStore().freeze(
            projectID: projectID,
            runID: "run-freeze-go",
            requestedScope: DeliveryScopeFreezeStore.defaultValidatedScope,
            auditRef: "audit-freeze-go"
        )

        #expect(freeze.schemaVersion == "xt.delivery_scope_freeze.v1")
        #expect(freeze.decision == .go)
        #expect(freeze.validatedScope == DeliveryScopeFreezeStore.defaultValidatedScope)
        #expect(freeze.allowedPublicStatements.count == 3)
        #expect(freeze.blockedExpansionItems.isEmpty)
    }

    @Test
    func deliveryScopeFreezeFailsClosedOnScopeExpansion() {
        let freeze = DeliveryScopeFreezeStore().freeze(
            projectID: UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")!,
            runID: "run-freeze-no-go",
            requestedScope: DeliveryScopeFreezeStore.defaultValidatedScope + ["XT-W3-27"],
            auditRef: "audit-freeze-no-go"
        )

        #expect(freeze.decision == .noGo)
        #expect(freeze.blockedExpansionItems == ["XT-W3-27"])
        #expect(freeze.nextActions.contains("trigger_replan"))
    }

    @MainActor
    @Test
    func replayHarnessCoversAllFailClosedScenarios() {
        let engine = OneShotAutonomyPolicyEngine()
        let project = ProjectModel(
            name: "XT-W3-26 Runtime",
            taskDescription: "replay harness coverage",
            modelName: "gpt-4.1",
            autonomyLevel: .auto
        )
        let lane = makeLane(
            laneID: "XT-W3-26-H",
            risk: .medium,
            metadata: [
                "requested_scope": DeliveryScopeFreezeStore.defaultValidatedScope.joined(separator: ","),
                "validated_scope": DeliveryScopeFreezeStore.defaultValidatedScope.joined(separator: ",")
            ]
        )
        let policy = engine.buildPolicy(
            project: project,
            lanes: [lane],
            splitPlanID: "run-replay-harness",
            now: Date(timeIntervalSince1970: 1_773_000_700)
        )
        let freeze = DeliveryScopeFreezeStore().freeze(
            projectID: project.id,
            runID: "run-replay-harness",
            requestedScope: DeliveryScopeFreezeStore.defaultValidatedScope,
            auditRef: policy.auditRef
        )

        let report = OneShotReplayHarness().run(
            policy: policy,
            freeze: freeze,
            now: Date(timeIntervalSince1970: 1_773_000_800)
        )

        #expect(report.schemaVersion == "xt.one_shot_replay_regression.v1")
        #expect(report.pass)
        #expect(report.scenarios.count == 4)
        #expect(report.scenarios.map(\.scenario) == [.grantRequired, .permissionDenied, .runtimeError, .scopeExpansion])
        #expect(report.scenarios.allSatisfy { $0.failClosed })
        #expect(report.uiConsumableContracts.contains("xt.unblock_baton.v1"))
    }

    @MainActor
    @Test
    func xtW326GCaptureAndReplayHarnessEmitMachineReadableEvidence() throws {
        guard ProcessInfo.processInfo.environment["XT_W3_26_G_CAPTURE"] == "1"
            || ProcessInfo.processInfo.environment["XT_W3_26_H_CAPTURE"] == "1" else {
            return
        }

        let engine = OneShotAutonomyPolicyEngine()
        let project = ProjectModel(
            name: "XT-W3-26 Runtime",
            taskDescription: "capture freeze and replay evidence",
            modelName: "gpt-4.1",
            autonomyLevel: .auto
        )
        let lane = makeLane(
            laneID: "XT-W3-26-H-capture",
            risk: .medium,
            metadata: [
                "requested_scope": DeliveryScopeFreezeStore.defaultValidatedScope.joined(separator: ","),
                "validated_scope": DeliveryScopeFreezeStore.defaultValidatedScope.joined(separator: ",")
            ]
        )
        let policy = engine.buildPolicy(
            project: project,
            lanes: [lane],
            splitPlanID: "capture-freeze-replay",
            now: Date(timeIntervalSince1970: 1_773_000_900)
        )
        let freeze = DeliveryScopeFreezeStore().freeze(
            projectID: project.id,
            runID: "capture-freeze-replay",
            requestedScope: DeliveryScopeFreezeStore.defaultValidatedScope,
            auditRef: policy.auditRef
        )
        let report = OneShotReplayHarness().run(
            policy: policy,
            freeze: freeze,
            now: Date(timeIntervalSince1970: 1_773_001_000)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        if ProcessInfo.processInfo.environment["XT_W3_26_G_CAPTURE"] == "1" {
            let freezeCapture = XTW326GDeliveryFreezeCapture(
                schemaVersion: "xt.w3_26.delivery_scope_freeze_capture.v1",
                freeze: freeze,
                sourceRefs: [
                    "x-terminal/Sources/Supervisor/DeliveryScopeFreezeStore.swift",
                    "x-terminal/Tests/DeliveryScopeFreezeTests.swift"
                ]
            )
            let json = try String(decoding: encoder.encode(freezeCapture), as: UTF8.self)
            print("XT_W3_26_G_CAPTURE_JSON=\(json)")
        }

        if ProcessInfo.processInfo.environment["XT_W3_26_H_CAPTURE"] == "1" {
            let replayCapture = XTW326HReplayHarnessCapture(
                schemaVersion: "xt.w3_26.replay_harness_capture.v1",
                report: report,
                sourceRefs: [
                    "x-terminal/Sources/Supervisor/OneShotReplayHarness.swift",
                    "x-terminal/Tests/DeliveryScopeFreezeTests.swift"
                ]
            )
            let json = try String(decoding: encoder.encode(replayCapture), as: UTF8.self)
            print("XT_W3_26_H_CAPTURE_JSON=\(json)")
        }
    }

    private func makeLane(
        laneID: String,
        risk: LaneRiskTier,
        metadata: [String: String]
    ) -> MaterializedLane {
        let task = DecomposedTask(
            description: laneID,
            type: .development,
            complexity: .moderate,
            estimatedEffort: 900,
            status: .ready,
            priority: 7,
            metadata: metadata.merging(["lane_id": laneID, "risk_tier": risk.rawValue]) { _, new in new }
        )
        let plan = SupervisorLanePlan(
            laneID: laneID,
            goal: "freeze test \(laneID)",
            dependsOn: [],
            riskTier: risk,
            budgetClass: .balanced,
            createChildProject: false,
            expectedArtifacts: [],
            dodChecklist: [],
            source: .inferred,
            metadata: metadata,
            task: task
        )

        return MaterializedLane(
            plan: plan,
            mode: .softSplit,
            task: task,
            targetProject: nil,
            lineageOperations: [],
            decisionReasons: ["test_freeze"],
            explain: "test_freeze_lane"
        )
    }
}

private struct XTW326GDeliveryFreezeCapture: Codable {
    let schemaVersion: String
    let freeze: DeliveryScopeFreeze
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case freeze
        case sourceRefs = "source_refs"
    }
}

private struct XTW326HReplayHarnessCapture: Codable {
    let schemaVersion: String
    let report: OneShotReplayReport
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case report
        case sourceRefs = "source_refs"
    }
}
