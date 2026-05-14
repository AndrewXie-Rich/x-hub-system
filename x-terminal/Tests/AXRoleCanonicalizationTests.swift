import Foundation
import Testing
@testable import XTerminal

struct AXRoleCanonicalizationTests {
    @Test
    func onlyThreeRolesRemainVisibleToUsers() {
        #expect(AXRole.allCases == [.supervisor, .coder, .reviewer])
    }

    @Test
    func legacyRoleTokensResolveToPrimaryRoles() {
        #expect(AXRole.resolveModelAssignmentToken("supervisor") == .supervisor)
        #expect(AXRole.resolveModelAssignmentToken("advisor") == .supervisor)
        #expect(AXRole.resolveModelAssignmentToken("coarse") == .coder)
        #expect(AXRole.resolveModelAssignmentToken("refine") == .coder)
        #expect(AXRole.resolveModelAssignmentToken("review") == .reviewer)
    }

    @Test
    func settingsCollapseLegacyAssignmentsIntoPrimaryRoles() {
        let settings = XTerminalSettings(
            schemaVersion: XTerminalSettings.currentSchemaVersion,
            assignments: [
                RoleProviderAssignment(role: .coarse, providerKind: .hub, model: "legacy-coder"),
                RoleProviderAssignment(role: .advisor, providerKind: .hub, model: "legacy-supervisor"),
                RoleProviderAssignment(role: .reviewer, providerKind: .hub, model: "reviewer-model"),
            ],
            openAICompatible: .init(baseURL: "https://api.openai.com/", model: "gpt-4o-mini"),
            anthropic: .init(baseURL: "https://api.anthropic.com/", model: "claude-3-5-sonnet-latest"),
            gemini: .init(baseURL: "https://generativelanguage.googleapis.com/", model: "gemini-1.5-pro"),
            voice: .default(),
            supervisorPrompt: .default(),
            supervisorPersonalProfile: .default(),
            supervisorPersonalPolicy: .default()
        )

        #expect(settings.assignment(for: .coder).model == "legacy-coder")
        #expect(settings.assignment(for: .refine).model == "legacy-coder")
        #expect(settings.assignment(for: .supervisor).model == "legacy-supervisor")
        #expect(settings.assignment(for: .advisor).model == "legacy-supervisor")
    }

    @Test
    func roleModelRoutesPreservePrimaryBackupAndAutomaticLocalFallback() throws {
        let settings = XTerminalSettings.default()
            .settingRolePrimaryModel(role: .coder, modelId: "openai/gpt-5.5")
            .settingRolePaidBackupModel(role: .coder, modelId: "gemini/gemini-3.5-pro")
            .settingRoleLocalFallback(role: .coder, mode: .automatic)

        #expect(settings.assignment(for: .coder).model == "openai/gpt-5.5")
        #expect(settings.modelRoute(for: .coder).primaryModelId == "openai/gpt-5.5")
        #expect(settings.modelRoute(for: .coder).paidBackupModelId == "gemini/gemini-3.5-pro")
        #expect(settings.modelRoute(for: .coder).localFallbackMode == .automatic)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(XTerminalSettings.self, from: data)

        #expect(decoded.assignment(for: .coder).model == "openai/gpt-5.5")
        #expect(decoded.modelRoute(for: .coder).paidBackupModelId == "gemini/gemini-3.5-pro")
        #expect(decoded.modelRoute(for: .coder).localFallbackMode == .automatic)
    }

    @Test
    func projectOverridesAndUsageSnapshotsReusePrimaryRoles() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-role-canonical-\(UUID().uuidString)", isDirectory: true)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .refine, modelId: "legacy-project-coder")
        config = config.settingModelOverride(role: .advisor, modelId: "legacy-project-supervisor")

        #expect(config.modelOverride(for: .coder) == "legacy-project-coder")
        #expect(config.modelOverride(for: .coarse) == "legacy-project-coder")
        #expect(config.modelOverride(for: .supervisor) == "legacy-project-supervisor")

        let usage = """
        {"type":"ai_usage","role":"coarse","created_at":100,"requested_model_id":"coder-a","execution_path":"remote_model"}
        {"type":"ai_usage","role":"advisor","created_at":200,"requested_model_id":"supervisor-a","execution_path":"remote_model"}
        """

        let snapshots = AXRoleExecutionSnapshots.latestSnapshots(fromUsageText: usage)
        #expect(snapshots[.coder]?.requestedModelId == "coder-a")
        #expect(snapshots[.supervisor]?.requestedModelId == "supervisor-a")
    }
}
