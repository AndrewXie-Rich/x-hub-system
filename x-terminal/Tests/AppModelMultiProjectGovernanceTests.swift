import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct AppModelMultiProjectGovernanceTests {
    @Test
    func multiProjectManagerCreateProjectDefaultsToConservativeGovernanceWithoutLegacyOrExplicitTier() async {
        let manager = MultiProjectManager(supervisor: SupervisorModel())
        let project = await manager.createProject(
            ProjectConfig(
                name: "Conservative Default",
                taskDescription: "No explicit governance should stay fail-closed.",
                modelName: "claude-sonnet-4.6"
            )
        )

        #expect(project.executionTier == .a0Observe)
        #expect(project.supervisorInterventionTier == .s0SilentAudit)
        #expect(project.reviewPolicyMode == .milestoneOnly)
        #expect(project.progressHeartbeatSeconds == AXProjectExecutionTier.a0Observe.defaultProgressHeartbeatSeconds)
        #expect(project.reviewPulseSeconds == 0)
        #expect(project.brainstormReviewSeconds == 0)
        #expect(project.eventDrivenReviewEnabled == false)
        #expect(project.eventReviewTriggers == [.manualRequest])
        #expect(project.autonomyLevel == .manual)
    }

    @Test
    func multiProjectManagerCreateProjectFollowsExplicitGovernanceInsteadOfLegacyCompatShadow() async {
        let manager = MultiProjectManager(supervisor: SupervisorModel())
        let project = await manager.createProject(
            ProjectConfig(
                name: "Governance First",
                taskDescription: "Verify explicit governance wins over the stale legacy compat shadow.",
                modelName: "claude-sonnet-4.6",
                autonomyLevel: .manual,
                executionTier: .a4OpenClaw,
                supervisorInterventionTier: .s4TightSupervision,
                reviewPolicyMode: .aggressive,
                progressHeartbeatSeconds: 300,
                reviewPulseSeconds: 600,
                brainstormReviewSeconds: 900,
                eventDrivenReviewEnabled: true,
                eventReviewTriggers: [.failureStreak, .planDrift, .preDoneSummary]
            )
        )

        #expect(project.executionTier == .a4OpenClaw)
        #expect(project.supervisorInterventionTier == .s4TightSupervision)
        #expect(project.reviewPolicyMode == .aggressive)
        #expect(project.progressHeartbeatSeconds == 300)
        #expect(project.reviewPulseSeconds == 600)
        #expect(project.brainstormReviewSeconds == 900)
        #expect(project.eventDrivenReviewEnabled)
        #expect(project.eventReviewTriggers == [.failureStreak, .planDrift, .preDoneSummary])
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
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .preHighRiskAction, .preDoneSummary]
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
        #expect(project.eventDrivenReviewEnabled)
        #expect(project.eventReviewTriggers == [.blockerDetected, .preHighRiskAction, .preDoneSummary])
        #expect(project.autonomyLevel == .auto)
    }

    @Test
    func applyProjectGovernanceTemplatePersistsGovernanceTemplateRawLogType() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_appmodel_governance_template_log_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let appModel = AppModel()
        appModel.projectContext = ctx
        appModel.projectConfig = try AXProjectStore.loadOrCreateConfig(for: ctx)

        appModel.applyProjectGovernanceTemplate(.safe)

        let rows = try rawLogEntries(for: ctx)
        let row = try #require(rows.last(where: { ($0["type"] as? String) == "project_governance_template" }))
        #expect(row["legacy_type"] as? String == "project_autonomy_profile")
        #expect(row["template"] as? String == AXProjectGovernanceTemplate.safe.rawValue)
        #expect(row["profile"] as? String == AXProjectGovernanceTemplate.safe.rawValue)
        #expect(row["execution_tier"] as? String == AXProjectExecutionTier.a3DeliverAuto.rawValue)
        #expect(row["supervisor_intervention_tier"] as? String == AXProjectSupervisorInterventionTier.s3StrategicCoach.rawValue)
    }
}

private func rawLogEntries(for ctx: AXProjectContext) throws -> [[String: Any]] {
    guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path) else { return [] }
    let data = try Data(contentsOf: ctx.rawLogURL)
    let lines = String(decoding: data, as: UTF8.self)
        .split(separator: "\n")
        .map(String.init)

    return try lines.map { line in
        let rowData = try #require(line.data(using: .utf8))
        let object = try #require(try JSONSerialization.jsonObject(with: rowData) as? [String: Any])
        return object
    }
}
