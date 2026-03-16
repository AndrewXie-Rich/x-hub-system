import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct SupervisorProjectModelOverrideRoutingTests {

    @Test
    func selectedProjectOverrideWritesOnlyTargetProjectConfig() throws {
        let alphaRoot = try makeProjectRoot(named: "supervisor-project-override-alpha")
        let betaRoot = try makeProjectRoot(named: "supervisor-project-override-beta")
        defer { try? FileManager.default.removeItem(at: alphaRoot) }
        defer { try? FileManager.default.removeItem(at: betaRoot) }

        let alpha = makeProjectEntry(root: alphaRoot, displayName: "Alpha", manualOrderIndex: 0)
        let beta = makeProjectEntry(root: betaRoot, displayName: "Beta", manualOrderIndex: 1)
        let alphaCtx = AXProjectContext(root: alphaRoot)
        let betaCtx = AXProjectContext(root: betaRoot)

        var betaConfig = try AXProjectStore.loadOrCreateConfig(for: betaCtx)
        betaConfig.setModelOverride(role: .coder, modelId: "beta-existing-coder")
        try AXProjectStore.saveConfig(betaConfig, for: betaCtx)

        let appModel = AppModel()
        appModel.registry = registry(with: [alpha, beta])
        appModel.projectContext = betaCtx
        appModel.projectConfig = betaConfig

        appModel.setProjectRoleModelOverride(
            projectId: alpha.projectId,
            role: .coder,
            modelId: "openai/gpt-5.4"
        )

        let alphaConfig = try AXProjectStore.loadOrCreateConfig(for: alphaCtx)
        let reloadedBeta = try AXProjectStore.loadOrCreateConfig(for: betaCtx)

        #expect(alphaConfig.modelOverride(for: .coder) == "openai/gpt-5.4")
        #expect(reloadedBeta.modelOverride(for: .coder) == "beta-existing-coder")
        #expect(appModel.projectConfig?.modelOverride(for: .coder) == "beta-existing-coder")
    }

    @Test
    func clearingSelectedProjectOverrideDoesNotTouchCurrentProjectConfig() throws {
        let alphaRoot = try makeProjectRoot(named: "supervisor-project-clear-alpha")
        let betaRoot = try makeProjectRoot(named: "supervisor-project-clear-beta")
        defer { try? FileManager.default.removeItem(at: alphaRoot) }
        defer { try? FileManager.default.removeItem(at: betaRoot) }

        let alpha = makeProjectEntry(root: alphaRoot, displayName: "Alpha", manualOrderIndex: 0)
        let beta = makeProjectEntry(root: betaRoot, displayName: "Beta", manualOrderIndex: 1)
        let alphaCtx = AXProjectContext(root: alphaRoot)
        let betaCtx = AXProjectContext(root: betaRoot)

        var alphaConfig = try AXProjectStore.loadOrCreateConfig(for: alphaCtx)
        alphaConfig.setModelOverride(role: .reviewer, modelId: "openai/gpt-4.1")
        try AXProjectStore.saveConfig(alphaConfig, for: alphaCtx)

        var betaConfig = try AXProjectStore.loadOrCreateConfig(for: betaCtx)
        betaConfig.setModelOverride(role: .reviewer, modelId: "beta-existing-reviewer")
        try AXProjectStore.saveConfig(betaConfig, for: betaCtx)

        let appModel = AppModel()
        appModel.registry = registry(with: [alpha, beta])
        appModel.projectContext = betaCtx
        appModel.projectConfig = betaConfig

        appModel.setProjectRoleModelOverride(
            projectId: alpha.projectId,
            role: .reviewer,
            modelId: nil
        )

        let reloadedAlpha = try AXProjectStore.loadOrCreateConfig(for: alphaCtx)
        let reloadedBeta = try AXProjectStore.loadOrCreateConfig(for: betaCtx)

        #expect(reloadedAlpha.modelOverride(for: .reviewer) == nil)
        #expect(reloadedBeta.modelOverride(for: .reviewer) == "beta-existing-reviewer")
        #expect(appModel.projectConfig?.modelOverride(for: .reviewer) == "beta-existing-reviewer")
    }

    private func registry(with projects: [AXProjectEntry]) -> AXProjectRegistry {
        AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projects.first?.projectId,
            projects: projects
        )
    }

    private func makeProjectEntry(root: URL, displayName: String, manualOrderIndex: Int) -> AXProjectEntry {
        AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: displayName,
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: manualOrderIndex,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
