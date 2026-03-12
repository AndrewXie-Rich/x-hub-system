import Foundation
import Testing
@testable import XTerminal

struct SupervisorProjectSpecCapsuleTests {
    @Test
    func capsuleEncodesDecodesAndAnswersRequiredMachineReadableFields() throws {
        let capsule = SupervisorProjectSpecCapsuleBuilder.build(
            projectId: "proj_demo",
            goal: "Ship governed desktop supervisor workflow.",
            mvpDefinition: "User can submit one large task and observe actionable lane progress.",
            nonGoals: ["Cross-tenant reporting", "Enterprise BI"],
            approvedTechStack: ["SwiftUI", "Hub canonical memory", "role-based routing"],
            techStackBlacklist: ["unapproved remote secret export"],
            moduleMap: [
                SupervisorProjectSpecModule(
                    moduleId: "portfolio",
                    title: "Supervisor portfolio",
                    status: .active,
                    dependsOn: []
                )
            ],
            milestoneMap: [
                SupervisorProjectSpecMilestone(
                    milestoneId: "mvp",
                    title: "Validated mainline",
                    status: .active
                )
            ],
            decisionDefaults: [
                .techStack: .proposalWithTimeoutEscalation,
                .uiStyle: .proposalOnly
            ],
            riskProfile: .medium,
            updatedAtMs: 1_760_000_000_000,
            sourceRefs: [
                "x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md"
            ]
        )

        let data = try JSONEncoder().encode(capsule)
        let decoded = try JSONDecoder().decode(SupervisorProjectSpecCapsule.self, from: data)
        let answers = try #require(decoded.machineReadableAnswers)

        #expect(decoded.schemaVersion == "xt.supervisor_project_spec_capsule.v1")
        #expect(decoded.missingRequiredFields.isEmpty)
        #expect(answers.goal == "Ship governed desktop supervisor workflow.")
        #expect(answers.mvpDefinition.contains("one large task"))
        #expect(answers.nonGoals == ["Cross-tenant reporting", "Enterprise BI"])
        #expect(answers.approvedTechStack == ["SwiftUI", "Hub canonical memory", "role-based routing"])
        #expect(answers.milestones.map(\.milestoneId) == ["mvp"])
        #expect(decoded.decisionDefault(for: .techStack) == .proposalWithTimeoutEscalation)
    }

    @Test
    func capsuleMergePreservesRequiredAnswersAndUpsertsMilestones() throws {
        let baseline = SupervisorProjectSpecCapsuleBuilder.build(
            projectId: "proj_demo",
            goal: "Ship governed desktop supervisor workflow.",
            mvpDefinition: "Initial MVP",
            nonGoals: ["Enterprise BI"],
            approvedTechStack: ["SwiftUI"],
            milestoneMap: [
                SupervisorProjectSpecMilestone(
                    milestoneId: "mvp",
                    title: "MVP",
                    status: .planned
                )
            ],
            decisionDefaults: [.techStack: .proposalOnly],
            updatedAtMs: 100
        )

        let incoming = SupervisorProjectSpecCapsuleBuilder.build(
            projectId: "proj_demo",
            goal: "",
            mvpDefinition: "User can observe governed pool progress.",
            nonGoals: ["Cross-tenant reporting"],
            approvedTechStack: ["Hub canonical memory", "SwiftUI"],
            moduleMap: [
                SupervisorProjectSpecModule(
                    moduleId: "portfolio",
                    title: "Portfolio",
                    status: .active,
                    dependsOn: []
                )
            ],
            milestoneMap: [
                SupervisorProjectSpecMilestone(
                    milestoneId: "mvp",
                    title: "Validated mainline",
                    status: .active
                ),
                SupervisorProjectSpecMilestone(
                    milestoneId: "ga",
                    title: "GA",
                    status: .planned
                )
            ],
            decisionDefaults: [.techStack: .proposalWithTimeoutEscalation],
            updatedAtMs: 200,
            sourceRefs: ["build/reports/xt_w3_33_a_project_spec_capsule_evidence.v1.json"]
        )

        let merged = try baseline.merged(with: incoming)
        let answers = try #require(merged.machineReadableAnswers)

        #expect(merged.goal == "Ship governed desktop supervisor workflow.")
        #expect(merged.mvpDefinition == "User can observe governed pool progress.")
        #expect(merged.nonGoals == ["Cross-tenant reporting", "Enterprise BI"])
        #expect(merged.approvedTechStack == ["Hub canonical memory", "SwiftUI"])
        #expect(answers.milestones.map(\.milestoneId) == ["mvp", "ga"])
        #expect(merged.milestoneMap.first?.title == "Validated mainline")
        #expect(merged.decisionDefault(for: .techStack) == .proposalWithTimeoutEscalation)
    }

    @Test
    func storeRoundTripsMergedCapsuleToProjectLocalFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w333_spec_capsule_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let baseline = SupervisorProjectSpecCapsuleBuilder.build(
            projectId: "proj_demo",
            goal: "Ship governed desktop supervisor workflow.",
            mvpDefinition: "Initial MVP",
            nonGoals: ["Enterprise BI"],
            approvedTechStack: ["SwiftUI"],
            milestoneMap: [
                SupervisorProjectSpecMilestone(
                    milestoneId: "mvp",
                    title: "MVP",
                    status: .planned
                )
            ],
            updatedAtMs: 100
        )
        let incoming = SupervisorProjectSpecCapsuleBuilder.build(
            projectId: "proj_demo",
            goal: "",
            mvpDefinition: "User can observe governed pool progress.",
            nonGoals: ["Cross-tenant reporting"],
            approvedTechStack: ["Hub canonical memory"],
            milestoneMap: [
                SupervisorProjectSpecMilestone(
                    milestoneId: "mvp",
                    title: "Validated mainline",
                    status: .active
                )
            ],
            updatedAtMs: 200
        )

        _ = try SupervisorProjectSpecCapsuleStore.upsert(baseline, for: ctx)
        let saved = try SupervisorProjectSpecCapsuleStore.upsert(incoming, for: ctx)
        let loaded = try #require(SupervisorProjectSpecCapsuleStore.load(for: ctx))

        #expect(saved == loaded)
        #expect(loaded.approvedTechStack == ["Hub canonical memory", "SwiftUI"])
        #expect(loaded.milestoneMap.first?.status == .active)
        #expect(loaded.machineReadableAnswers?.goal == "Ship governed desktop supervisor workflow.")
    }
}
