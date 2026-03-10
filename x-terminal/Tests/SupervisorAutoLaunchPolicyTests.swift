import Foundation
import Testing
@testable import XTerminal

struct SupervisorAutoLaunchPolicyTests {

    @MainActor
    @Test
    func safeAutoLaunchAllowsValidatedMainlineLane() {
        let engine = OneShotAutonomyPolicyEngine()
        let project = ProjectModel(
            name: "XT-W3-26 Runtime",
            taskDescription: "safe auto launch mainline",
            modelName: "gpt-4.1",
            autonomyLevel: .auto
        )
        let lane = makeLane(
            laneID: "XT-W3-26-E",
            risk: .low,
            metadata: [
                "requested_scope": DeliveryScopeFreezeStore.defaultValidatedScope.joined(separator: ","),
                "validated_scope": DeliveryScopeFreezeStore.defaultValidatedScope.joined(separator: ",")
            ]
        )
        let policy = engine.buildPolicy(
            project: project,
            lanes: [lane],
            splitPlanID: "run-safe-allow",
            now: Date(timeIntervalSince1970: 1_773_000_000)
        )
        let freeze = DeliveryScopeFreezeStore().freeze(
            projectID: project.id,
            runID: "run-safe-allow",
            requestedScope: DeliveryScopeFreezeStore.defaultValidatedScope,
            auditRef: policy.auditRef
        )

        let decision = engine.evaluateLaunch(
            policy: policy,
            lane: lane,
            project: project,
            scopeFreeze: freeze
        )

        #expect(policy.schemaVersion == "xt.one_shot_autonomy_policy.v1")
        #expect(policy.grantGateMode == "fail_closed")
        #expect(decision.decision == .allow)
        #expect(decision.autoLaunchAllowed)
        #expect(decision.failClosed == false)
    }

    @MainActor
    @Test
    func safeAutoLaunchFailsClosedForHighRiskGrantRequiredLane() {
        let engine = OneShotAutonomyPolicyEngine()
        let project = ProjectModel(
            name: "XT-W3-26 Runtime",
            taskDescription: "grant required side effect",
            modelName: "gpt-4.1",
            autonomyLevel: .auto
        )
        let lane = makeLane(
            laneID: "XT-W3-26-E-high",
            risk: .high,
            metadata: [
                "grant_required": "1",
                "requires_external_side_effect": "1",
                "requested_scope": DeliveryScopeFreezeStore.defaultValidatedScope.joined(separator: ","),
                "validated_scope": DeliveryScopeFreezeStore.defaultValidatedScope.joined(separator: ",")
            ]
        )
        let policy = engine.buildPolicy(
            project: project,
            lanes: [lane],
            splitPlanID: "run-grant-block",
            now: Date(timeIntervalSince1970: 1_773_000_100)
        )
        let freeze = DeliveryScopeFreezeStore().freeze(
            projectID: project.id,
            runID: "run-grant-block",
            requestedScope: DeliveryScopeFreezeStore.defaultValidatedScope,
            auditRef: policy.auditRef
        )

        let decision = engine.evaluateLaunch(
            policy: policy,
            lane: lane,
            project: project,
            scopeFreeze: freeze
        )

        #expect(decision.decision == .deny)
        #expect(decision.denyCode == "grant_required")
        #expect(decision.blockedReason == .grantPending)
        #expect(decision.failClosed)
    }

    @MainActor
    @Test
    func safeAutoLaunchFailsClosedForPermissionDeniedLane() {
        let engine = OneShotAutonomyPolicyEngine()
        let project = ProjectModel(
            name: "XT-W3-26 Runtime",
            taskDescription: "permission denied",
            modelName: "gpt-4.1",
            autonomyLevel: .auto
        )
        let lane = makeLane(
            laneID: "XT-W3-26-E-permission",
            risk: .medium,
            metadata: [
                "permission_denied": "1",
                "requested_scope": DeliveryScopeFreezeStore.defaultValidatedScope.joined(separator: ","),
                "validated_scope": DeliveryScopeFreezeStore.defaultValidatedScope.joined(separator: ",")
            ]
        )
        let policy = engine.buildPolicy(
            project: project,
            lanes: [lane],
            splitPlanID: "run-permission-block",
            now: Date(timeIntervalSince1970: 1_773_000_200)
        )
        let freeze = DeliveryScopeFreezeStore().freeze(
            projectID: project.id,
            runID: "run-permission-block",
            requestedScope: DeliveryScopeFreezeStore.defaultValidatedScope,
            auditRef: policy.auditRef
        )

        let decision = engine.evaluateLaunch(
            policy: policy,
            lane: lane,
            project: project,
            scopeFreeze: freeze
        )

        #expect(decision.decision == .deny)
        #expect(decision.denyCode == "permission_denied")
        #expect(decision.blockedReason == .authzDenied)
        #expect(decision.failClosed)
    }

    @MainActor
    @Test
    func xtW326ECaptureEmitsMachineReadablePolicyEvidence() throws {
        guard ProcessInfo.processInfo.environment["XT_W3_26_E_CAPTURE"] == "1" else { return }

        let engine = OneShotAutonomyPolicyEngine()
        let project = ProjectModel(
            name: "XT-W3-26 Runtime",
            taskDescription: "capture policy evidence",
            modelName: "gpt-4.1",
            autonomyLevel: .auto
        )

        let allowedLane = makeLane(
            laneID: "XT-W3-26-E-allowed",
            risk: .low,
            metadata: [
                "requested_scope": DeliveryScopeFreezeStore.defaultValidatedScope.joined(separator: ","),
                "validated_scope": DeliveryScopeFreezeStore.defaultValidatedScope.joined(separator: ",")
            ]
        )
        let blockedLane = makeLane(
            laneID: "XT-W3-26-E-blocked",
            risk: .high,
            metadata: [
                "grant_required": "1",
                "requires_external_side_effect": "1",
                "requested_scope": DeliveryScopeFreezeStore.defaultValidatedScope.joined(separator: ","),
                "validated_scope": DeliveryScopeFreezeStore.defaultValidatedScope.joined(separator: ",")
            ]
        )
        let policy = engine.buildPolicy(
            project: project,
            lanes: [allowedLane, blockedLane],
            splitPlanID: "capture-safe-auto-launch",
            now: Date(timeIntervalSince1970: 1_773_000_300)
        )
        let freeze = DeliveryScopeFreezeStore().freeze(
            projectID: project.id,
            runID: "capture-safe-auto-launch",
            requestedScope: DeliveryScopeFreezeStore.defaultValidatedScope,
            auditRef: policy.auditRef
        )

        let capture = XTW326ESafeAutoLaunchCapture(
            schemaVersion: "xt.w3_26.safe_auto_launch_capture.v1",
            policy: policy,
            decisions: [
                engine.evaluateLaunch(policy: policy, lane: allowedLane, project: project, scopeFreeze: freeze),
                engine.evaluateLaunch(policy: policy, lane: blockedLane, project: project, scopeFreeze: freeze)
            ],
            sourceRefs: [
                "x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift",
                "x-terminal/Sources/Supervisor/OneShotReplayHarness.swift",
                "x-terminal/Tests/SupervisorAutoLaunchPolicyTests.swift"
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try String(decoding: encoder.encode(capture), as: UTF8.self)
        print("XT_W3_26_E_CAPTURE_JSON=\(json)")
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
            priority: 8,
            metadata: metadata.merging(["lane_id": laneID, "risk_tier": risk.rawValue]) { _, new in new }
        )
        let plan = SupervisorLanePlan(
            laneID: laneID,
            goal: "policy test \(laneID)",
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
            decisionReasons: ["test_policy"],
            explain: "test_policy_lane"
        )
    }
}

private struct XTW326ESafeAutoLaunchCapture: Codable {
    let schemaVersion: String
    let policy: OneShotAutonomyPolicy
    let decisions: [OneShotLaunchDecision]
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case policy
        case decisions
        case sourceRefs = "source_refs"
    }
}
