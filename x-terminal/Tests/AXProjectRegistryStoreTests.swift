import Foundation
import Testing
@testable import XTerminal

struct AXProjectRegistryStoreTests {
    @Test
    func sanitizeLoadedRegistryPrunesMissingTemporaryProjects() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-supervisor-last-actual-model-\(UUID().uuidString)", isDirectory: true)

        let stableRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("AX", isDirectory: true)
            .appendingPathComponent("stable-project-\(UUID().uuidString)", isDirectory: true)

        let reg = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: AXProjectRegistryStore.projectId(forRoot: tempRoot),
            projects: [
                AXProjectEntry(
                    projectId: AXProjectRegistryStore.projectId(forRoot: tempRoot),
                    rootPath: tempRoot.path,
                    displayName: tempRoot.lastPathComponent,
                    lastOpenedAt: 1,
                    manualOrderIndex: 0,
                    pinned: false,
                    statusDigest: nil,
                    currentStateSummary: nil,
                    nextStepSummary: nil,
                    blockerSummary: nil,
                    lastSummaryAt: nil,
                    lastEventAt: nil
                ),
                AXProjectEntry(
                    projectId: AXProjectRegistryStore.projectId(forRoot: stableRoot),
                    rootPath: stableRoot.path,
                    displayName: "stable-project",
                    lastOpenedAt: 2,
                    manualOrderIndex: 1,
                    pinned: false,
                    statusDigest: nil,
                    currentStateSummary: nil,
                    nextStepSummary: nil,
                    blockerSummary: nil,
                    lastSummaryAt: nil,
                    lastEventAt: nil
                )
            ]
        )

        let sanitized = AXProjectRegistryStore.sanitizeLoadedRegistry(reg)

        #expect(sanitized.changed == true)
        #expect(sanitized.registry.projects.count == 1)
        #expect(sanitized.registry.projects.first?.displayName == "stable-project")
        #expect(sanitized.registry.lastSelectedProjectId == sanitized.registry.projects.first?.projectId)
    }

    @Test
    func sanitizeLoadedRegistryPrunesEphemeralAutomationTestProjectsEvenIfDirectoryStillExists() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-supervisor-manager-automation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let stableRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("AX", isDirectory: true)
            .appendingPathComponent("stable-project-\(UUID().uuidString)", isDirectory: true)

        let reg = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: AXProjectRegistryStore.projectId(forRoot: tempRoot),
            projects: [
                AXProjectEntry(
                    projectId: AXProjectRegistryStore.projectId(forRoot: tempRoot),
                    rootPath: tempRoot.path,
                    displayName: tempRoot.lastPathComponent,
                    lastOpenedAt: 1,
                    manualOrderIndex: 0,
                    pinned: false,
                    statusDigest: nil,
                    currentStateSummary: nil,
                    nextStepSummary: nil,
                    blockerSummary: nil,
                    lastSummaryAt: nil,
                    lastEventAt: nil
                ),
                AXProjectEntry(
                    projectId: AXProjectRegistryStore.projectId(forRoot: stableRoot),
                    rootPath: stableRoot.path,
                    displayName: "stable-project",
                    lastOpenedAt: 2,
                    manualOrderIndex: 1,
                    pinned: false,
                    statusDigest: nil,
                    currentStateSummary: nil,
                    nextStepSummary: nil,
                    blockerSummary: nil,
                    lastSummaryAt: nil,
                    lastEventAt: nil
                )
            ]
        )

        let sanitized = AXProjectRegistryStore.sanitizeLoadedRegistry(reg)

        #expect(sanitized.changed == true)
        #expect(sanitized.registry.projects.count == 1)
        #expect(sanitized.registry.projects.first?.displayName == "stable-project")
        #expect(sanitized.registry.lastSelectedProjectId == sanitized.registry.projects.first?.projectId)
    }
}
