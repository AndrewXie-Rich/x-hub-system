import Foundation
import Testing
@testable import XTerminal

struct AXProjectRegistryStoreTests {
    @Test
    func saveFallsBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let url = AXProjectRegistryStore.url()
        let baseDir = AXProjectRegistryStore.baseDir()
        let backup = try? Data(contentsOf: url)
        defer {
            XTStoreWriteSupport.resetWriteBehaviorForTesting()
            if let backup {
                try? backup.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-registry-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let initial = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [
                AXProjectEntry(
                    projectId: projectId,
                    rootPath: root.path,
                    displayName: "Old Name",
                    lastOpenedAt: 1,
                    manualOrderIndex: 0,
                    pinned: false,
                    statusDigest: "old-digest",
                    currentStateSummary: "old-state",
                    nextStepSummary: "old-next",
                    blockerSummary: nil,
                    lastSummaryAt: 1,
                    lastEventAt: 1
                )
            ]
        )
        AXProjectRegistryStore.save(initial)

        let capture = AXProjectRegistryWriteCapture()
        XTStoreWriteSupport.installWriteAttemptOverrideForTesting { data, writeURL, options in
            if !Self.normalizedPath(writeURL).hasPrefix(Self.normalizedPath(baseDir)) {
                try data.write(to: writeURL, options: options)
                return
            }
            capture.appendWriteOption(options)
            if options.contains(.atomic) {
                throw NSError(domain: NSPOSIXErrorDomain, code: 28)
            }
            try data.write(to: writeURL, options: options)
        }

        var updated = initial
        updated.globalHomeVisible = true
        updated.projects[0].displayName = "New Name"
        updated.projects[0].statusDigest = "new-digest"
        AXProjectRegistryStore.save(updated)

        let loaded = AXProjectRegistryStore.load()
        #expect(loaded.globalHomeVisible == true)
        #expect(loaded.projects.first?.displayName == "New Name")
        #expect(loaded.projects.first?.statusDigest == "new-digest")

        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options.filter { $0.contains(.atomic) }.count == 1)
        #expect(options.filter(\.isEmpty).count == 1)
    }

    @Test
    func upsertProjectPreservesFriendlyDisplayNameForExistingEntry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-registry-friendly-name-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let reg = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [
                AXProjectEntry(
                    projectId: projectId,
                    rootPath: root.path,
                    displayName: "亮亮",
                    lastOpenedAt: 1,
                    manualOrderIndex: 0,
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

        let updated = AXProjectRegistryStore.upsertProject(reg, root: root)

        #expect(updated.1.displayName == "亮亮")
        #expect(updated.0.projects.first?.displayName == "亮亮")
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path.replacingOccurrences(
            of: "/private",
            with: "",
            options: [.anchored]
        )
    }

    @Test
    func displayNamePrefersFriendlyRegistryEntry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-display-name-friendly-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let reg = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [
                AXProjectEntry(
                    projectId: projectId,
                    rootPath: root.path,
                    displayName: "Supervisor 耳机项目",
                    lastOpenedAt: 1,
                    manualOrderIndex: 0,
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

        #expect(
            AXProjectRegistryStore.displayName(forRoot: root, registry: reg) == "Supervisor 耳机项目"
        )
    }

    @Test
    func displayNameFallsBackToPreferredFriendlyNameWhenRegistryIsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-display-name-preferred-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(
            AXProjectRegistryStore.displayName(
                forRoot: root,
                registry: .empty(),
                preferredDisplayName: "亮亮"
            ) == "亮亮"
        )
    }

    @Test
    func sanitizeLoadedRegistryStripsMarkdownWrappersFromDisplayName() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("`坦克大战`", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let reg = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [
                AXProjectEntry(
                    projectId: projectId,
                    rootPath: root.path,
                    displayName: "`坦克大战`",
                    lastOpenedAt: 1,
                    manualOrderIndex: 0,
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
        #expect(sanitized.registry.projects.first?.displayName == "坦克大战")
        #expect(AXProjectRegistryStore.displayName(forRoot: root, registry: sanitized.registry) == "坦克大战")
    }

    @Test
    func projectContextDisplayNameUsesFriendlyRegistryEntry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-context-display-name-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let reg = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [
                AXProjectEntry(
                    projectId: projectId,
                    rootPath: root.path,
                    displayName: "自然语言耳机项目",
                    lastOpenedAt: 1,
                    manualOrderIndex: 0,
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

        let ctx = AXProjectContext(root: root)
        #expect(ctx.displayName(registry: reg) == "自然语言耳机项目")
    }

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

private final class AXProjectRegistryWriteCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var writeOptions: [Data.WritingOptions] = []

    func appendWriteOption(_ option: Data.WritingOptions) {
        lock.lock()
        defer { lock.unlock() }
        writeOptions.append(option)
    }

    func writeOptionsSnapshot() -> [Data.WritingOptions] {
        lock.lock()
        defer { lock.unlock() }
        return writeOptions
    }
}
