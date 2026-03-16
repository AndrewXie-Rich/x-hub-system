import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct AppModelMultiProjectGovernanceTests {
    @Test
    func multiProjectManagerCreateProjectFollowsExplicitGovernanceInsteadOfLegacyAutonomy() async {
        let manager = MultiProjectManager(supervisor: SupervisorModel())
        let project = await manager.createProject(
            ProjectConfig(
                name: "Governance First",
                taskDescription: "Verify explicit governance wins over stale legacy autonomy.",
                modelName: "claude-sonnet-4.6",
                autonomyLevel: .manual,
                executionTier: .a4OpenClaw,
                supervisorInterventionTier: .s4TightSupervision,
                reviewPolicyMode: .aggressive,
                progressHeartbeatSeconds: 300,
                reviewPulseSeconds: 600,
                brainstormReviewSeconds: 900,
                eventDrivenReviewEnabled: true
            )
        )

        #expect(project.executionTier == .a4OpenClaw)
        #expect(project.supervisorInterventionTier == .s4TightSupervision)
        #expect(project.reviewPolicyMode == .aggressive)
        #expect(project.progressHeartbeatSeconds == 300)
        #expect(project.reviewPulseSeconds == 600)
        #expect(project.brainstormReviewSeconds == 900)
        #expect(project.eventDrivenReviewEnabled)
        #expect(project.autonomyLevel == .fullAuto)
    }

    @Test
    func appModelCreateMultiProjectPreservesBindingAndGovernanceDials() async throws {
        AppModel.resetSharedMultiProjectRuntimeForTesting()
        defer { AppModel.resetSharedMultiProjectRuntimeForTesting() }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_appmodel_multi_project_governance_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let entry = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Bound Governance Project",
            lastOpenedAt: 1_773_557_400,
            manualOrderIndex: 0,
            pinned: true,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_557_401,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: entry.projectId,
            projects: [entry]
        )

        let project = await appModel.createMultiProject(
            name: "Bound Multi Project",
            taskDescription: "Ensure AppModel forwards governance and project binding.",
            modelName: "claude-opus-4.6",
            registeredProjectId: entry.projectId,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s4TightSupervision,
            reviewPolicyMode: .aggressive,
            progressHeartbeatSeconds: 420,
            reviewPulseSeconds: 840,
            brainstormReviewSeconds: 1260,
            eventDrivenReviewEnabled: false
        )

        let binding = try #require(project.registeredProjectBinding)
        #expect(binding.projectId == entry.projectId)
        #expect(binding.rootPath == entry.rootPath)
        #expect(binding.displayName == entry.displayName)
        #expect(project.executionTier == .a3DeliverAuto)
        #expect(project.supervisorInterventionTier == .s4TightSupervision)
        #expect(project.reviewPolicyMode == .aggressive)
        #expect(project.progressHeartbeatSeconds == 420)
        #expect(project.reviewPulseSeconds == 840)
        #expect(project.brainstormReviewSeconds == 1260)
        #expect(project.eventDrivenReviewEnabled == false)
        #expect(project.autonomyLevel == .auto)
    }
}
