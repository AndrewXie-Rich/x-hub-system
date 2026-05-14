import Foundation
import Testing
@testable import XTerminal

struct XTWorkSurfaceStoreTests {
    @Test
    @MainActor
    func appModelMirrorsSelectedProjectStateIntoFocusedStore() throws {
        let root = try makeTempProjectRoot("work_surface_selected")
        let ctx = AXProjectContext(root: root)
        let memory = AXMemory.new(projectName: "Work Surface", projectRoot: root.path)
        let config = AXProjectConfig.default(forProjectRoot: root)
        let appModel = AppModel.makeForTesting()

        appModel.selectedProjectId = "project-work"
        appModel.projectContext = ctx
        appModel.memory = memory
        appModel.projectConfig = config

        let snapshot = appModel.workSurfaceStore.snapshot
        #expect(snapshot.selectedProjectId == "project-work")
        #expect(snapshot.projectContext == ctx)
        #expect(snapshot.memory == memory)
        #expect(snapshot.projectConfig == config)
        #expect(snapshot.selectedPane == .chat)
        #expect(snapshot.hasProjectContext)
    }

    @Test
    @MainActor
    func paneChangeUpdatesSelectedPaneSnapshot() {
        let appModel = AppModel.makeForTesting()

        appModel.selectedProjectId = "project-pane"
        appModel.setPane(.terminal, for: "project-pane")

        #expect(appModel.workSurfaceStore.snapshot.selectedPane == .terminal)
    }

    @Test
    @MainActor
    func multiProjectToggleUpdatesWorkSurfaceSnapshot() {
        let key = "xterminal_multi_project_view_enabled"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.set(false, forKey: key)
        let appModel = AppModel.makeForTesting()

        appModel.isMultiProjectViewEnabled = true

        #expect(appModel.workSurfaceStore.snapshot.isMultiProjectViewEnabled)
    }

    @Test
    @MainActor
    func globalHomeSelectionKeepsProjectContextOutOfPrimaryWorkSurface() {
        let appModel = AppModel.makeForTesting()

        appModel.selectedProjectId = AXProjectRegistry.globalHomeId
        appModel.projectContext = nil
        appModel.memory = nil
        appModel.projectConfig = nil

        let snapshot = appModel.workSurfaceStore.snapshot
        #expect(snapshot.isGlobalHomeSelected)
        #expect(!snapshot.hasProjectContext)
        #expect(snapshot.selectedPane == .chat)
    }

    private func makeTempProjectRoot(_ prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
