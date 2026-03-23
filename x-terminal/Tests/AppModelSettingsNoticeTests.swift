import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct AppModelSettingsNoticeTests {

    @Test
    func supervisorWorkModeChangeAppendsSingleSupervisorNotice() {
        let manager = SupervisorManager.shared
        let originalMessages = manager.messages
        defer { manager.messages = originalMessages }
        manager.messages = []

        let appModel = AppModel()
        let current = appModel.settingsStore.settings.supervisorWorkMode
        let next: XTSupervisorWorkMode = current == .conversationOnly ? .guidedProgress : .conversationOnly

        appModel.setSupervisorWorkMode(next)

        #expect(manager.messages.count == 1)
        #expect(manager.messages.last?.content.contains("Supervisor 设置已更新：") == true)

        appModel.setSupervisorWorkMode(next)

        #expect(manager.messages.count == 1)
    }

    @Test
    func sandboxModeChangeAppendsProjectNoticeForSelectedProject() throws {
        let fixture = ToolExecutorProjectFixture(name: "app-model-settings-notice-project")
        defer { fixture.cleanup() }

        try AXProjectContext(root: fixture.root).ensureDirs()

        var registry = AXProjectRegistry.empty()
        registry.globalHomeVisible = true
        let upsert = AXProjectRegistryStore.upsertProject(registry, root: fixture.root)

        let originalSandboxMode = ToolExecutor.sandboxMode()
        defer { ToolExecutor.setSandboxMode(originalSandboxMode) }
        let nextSandboxMode: ToolSandboxMode = originalSandboxMode == .host ? .sandbox : .host

        let appModel = AppModel()
        appModel.registry = upsert.0
        appModel.selectedProjectId = upsert.1.projectId

        appModel.setDefaultToolSandboxMode(nextSandboxMode)

        let session = try #require(appModel.sessionForProjectId(upsert.1.projectId))
        #expect(session.messages.count == 1)
        #expect(session.messages.last?.content.contains("XT Runtime 设置已更新：") == true)
    }

    @Test
    func sandboxModeChangeDoesNotAppendProjectNoticeWhenGlobalHomeIsSelected() throws {
        let fixture = ToolExecutorProjectFixture(name: "app-model-settings-notice-global-home")
        defer { fixture.cleanup() }

        try AXProjectContext(root: fixture.root).ensureDirs()

        var registry = AXProjectRegistry.empty()
        registry.globalHomeVisible = true
        let upsert = AXProjectRegistryStore.upsertProject(registry, root: fixture.root)

        let originalSandboxMode = ToolExecutor.sandboxMode()
        defer { ToolExecutor.setSandboxMode(originalSandboxMode) }
        let nextSandboxMode: ToolSandboxMode = originalSandboxMode == .host ? .sandbox : .host

        let appModel = AppModel()
        appModel.registry = upsert.0
        appModel.selectedProjectId = AXProjectRegistry.globalHomeId

        appModel.setDefaultToolSandboxMode(nextSandboxMode)

        let session = try #require(appModel.sessionForProjectId(upsert.1.projectId))
        #expect(session.messages.isEmpty)
    }
}
