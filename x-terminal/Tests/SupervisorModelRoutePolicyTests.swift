import Foundation
import Testing
@testable import XTerminal

struct SupervisorModelRoutePolicyTests {
    @Test
    func routePolicyFreezesAllFiveRoleRoutes() {
        let policy = SupervisorModelRoutePolicy.default(projectID: "proj_demo")

        #expect(policy.schemaVersion == SupervisorModelRoutePolicy.currentSchemaVersion)
        #expect(policy.roleRoutes.count == 5)
        #expect(policy.route(for: .planner)?.taskTags == ["scope_freeze", "spec_capsule", "decision_blocker"])
        #expect(policy.route(for: .coder)?.taskTags == ["codegen", "refactor", "runtime_fix"])
        #expect(policy.route(for: .reviewer)?.taskTags == ["review", "regression", "gate_review"])
        #expect(policy.route(for: .doc)?.taskTags == ["docs", "release_notes", "spec_freeze_writeup"])
        #expect(policy.route(for: .ops)?.taskTags == ["runbook", "rollout", "runtime_probe", "operator_action"])
    }

    @Test
    func routeDecisionEscalatesHighRiskToHubPolicyRequiredAndExplainsWhy() {
        let policy = SupervisorModelRoutePolicy.default(projectID: "proj_demo")
        let decision = policy.routeDecision(
            for: .init(
                taskTags: ["runtime_fix"],
                risk: .high,
                sideEffect: .localMutation,
                codeExecution: true
            )
        )

        #expect(decision.role == .coder)
        #expect(decision.grantPolicy == .hubPolicyRequired)
        #expect(decision.hubPolicyRequired)
        #expect(!decision.explainability.isEmpty)
        #expect(decision.explainability.whyRole.contains("runtime_fix"))
        #expect(decision.explainability.whyPreferredModelClasses.contains("project-wide model"))
        #expect(decision.explainability.whyHubStillDecides.contains("Hub"))
    }

    @Test
    func routeDecisionReusesProjectConfigHintsWithoutCollapsingAllRolesToOneModel() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-route-policy-\(UUID().uuidString)", isDirectory: true)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-coder")
        config = config.settingModelOverride(role: .reviewer, modelId: "anthropic/reviewer-pro")
        config = config.settingModelOverride(role: .advisor, modelId: "local/reasoner")
        config = config.settingModelOverride(role: .refine, modelId: "local/writer")

        let policy = SupervisorModelRoutePolicy.default(projectID: "proj_demo")
        let planner = policy.routeDecision(for: .init(taskTags: ["scope_freeze"]), projectConfig: config)
        let coder = policy.routeDecision(
            for: .init(taskTags: ["codegen"], codeExecution: true),
            projectConfig: config
        )
        let reviewer = policy.routeDecision(for: .init(taskTags: ["review"]), projectConfig: config)
        let doc = policy.routeDecision(for: .init(taskTags: ["docs"]), projectConfig: config)

        #expect(planner.projectModelHints == ["local/reasoner"])
        #expect(coder.projectModelHints == ["openai/gpt-coder", "local/writer"])
        #expect(reviewer.projectModelHints == ["anthropic/reviewer-pro", "local/reasoner"])
        #expect(doc.projectModelHints == ["local/writer", "local/reasoner", "anthropic/reviewer-pro"])

        #expect(planner.projectModelHints != coder.projectModelHints)
        #expect(coder.projectModelHints != reviewer.projectModelHints)
        #expect(doc.projectModelHints != coder.projectModelHints)
    }

    @Test
    func routeExplainabilityNeverComesBackEmptyForRequiredAssertionSet() {
        let policy = SupervisorModelRoutePolicy.default(projectID: "proj_demo")
        let inputs: [SupervisorTaskRoleClassifier.Input] = [
            .init(taskTags: ["scope_freeze"]),
            .init(taskTags: ["codegen"], sideEffect: .localMutation, codeExecution: true),
            .init(taskTags: ["review"], risk: .medium),
            .init(taskTags: ["docs"]),
            .init(taskTags: ["operator_action"], sideEffect: .externalWrite),
        ]

        for input in inputs {
            let decision = policy.routeDecision(for: input)
            #expect(!decision.preferredModelClasses.isEmpty)
            #expect(!decision.explainability.isEmpty)
        }
    }

    @Test
    func captureXTW333CEvidenceWhenRequested() throws {
        guard let captureDir = ProcessInfo.processInfo.environment["XT_W3_33_C_CAPTURE_DIR"], !captureDir.isEmpty else {
            return
        }

        let base = URL(fileURLWithPath: captureDir, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)

        let policy = SupervisorModelRoutePolicy.default(projectID: "proj_demo")
        let configRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-route-policy-evidence-\(UUID().uuidString)", isDirectory: true)
        var config = AXProjectConfig.default(forProjectRoot: configRoot)
        config = config.settingModelOverride(role: .advisor, modelId: "local/reasoner")
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-coder")
        config = config.settingModelOverride(role: .reviewer, modelId: "anthropic/reviewer-pro")
        config = config.settingModelOverride(role: .refine, modelId: "local/writer")

        let samples: [SupervisorModelRouteDecision] = [
            policy.routeDecision(for: .init(taskTags: ["scope_freeze"]), projectConfig: config),
            policy.routeDecision(
                for: .init(taskTags: ["codegen"], risk: .high, sideEffect: .localMutation, codeExecution: true),
                projectConfig: config
            ),
            policy.routeDecision(for: .init(taskTags: ["review"]), projectConfig: config),
            policy.routeDecision(for: .init(taskTags: ["docs"]), projectConfig: config),
            policy.routeDecision(
                for: .init(taskTags: ["operator_action"], sideEffect: .externalWrite),
                projectConfig: config
            ),
        ]

        let evidence = RoleRoutePolicyEvidence(
            policy: policy,
            assertions: [
                "scope_freeze->planner",
                "codegen->coder",
                "review->reviewer",
                "docs->doc",
                "operator_action->ops",
                "high_risk->hub_policy_required",
                "explainability_non_empty"
            ],
            sampleDecisions: samples,
            sourceRefs: [
                "x-terminal/work-orders/xt-w3-33-supervisor-decision-kernel-routing-and-memory-governance-implementation-pack-v1.md",
                "docs/xhub-multi-model-orchestration-and-supervisor-v1.md",
                "docs/xhub-agent-efficiency-and-safety-governance-v1.md",
                "x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md",
                "docs/memory-new/xhub-lane-command-board-v2.md#CD-20260311-XT-W333-001"
            ]
        )
        let destination = base.appendingPathComponent("xt_w3_33_c_role_route_policy_evidence.v1.json")
        try writeJSON(evidence, to: destination)

        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    private struct RoleRoutePolicyEvidence: Codable, Equatable {
        var schemaVersion: String = "xt.w3.33.c.role_route_policy_evidence.v1"
        var workstream: String = "XT-W3-33-C"
        var policy: SupervisorModelRoutePolicy
        var assertions: [String]
        var sampleDecisions: [SupervisorModelRouteDecision]
        var sourceRefs: [String]
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}
