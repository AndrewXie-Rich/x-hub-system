import Foundation
import Testing
@testable import XTerminal

@MainActor
struct XTProjectPersistenceWriteSupportTests {
    @Test
    func projectStoreMemoryFallsBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("project_memory")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var memory = AXMemory.new(projectName: "Persistence", projectRoot: root.path)
        memory.currentState = ["old-state"]
        try AXProjectStore.saveMemory(memory, for: ctx)

        let capture = ProjectStoreWriteCapture()
        XTStoreWriteSupport.installWriteAttemptOverrideForTesting { data, url, options in
            try Self.writeWithScopedOutOfSpaceOverride(
                data: data,
                url: url,
                options: options,
                root: root,
                capture: capture
            )
        }
        defer { XTStoreWriteSupport.resetWriteBehaviorForTesting() }

        memory.currentState = ["new-state"]
        memory.nextSteps = ["ship fallback writer"]
        try AXProjectStore.saveMemory(memory, for: ctx)

        let loaded = try #require(AXProjectStore.loadMemoryIfPresent(for: ctx))
        #expect(loaded.currentState == ["new-state"])
        #expect(loaded.nextSteps == ["ship fallback writer"])

        let markdown = try String(contentsOf: ctx.memoryMarkdownURL, encoding: .utf8)
        #expect(markdown.contains("new-state"))
        #expect(markdown.contains("ship fallback writer"))

        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 4)
        #expect(options.filter { $0.contains(.atomic) }.count == 2)
        #expect(options.filter(\.isEmpty).count == 2)
    }

    @Test
    func recentContextFallsBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("recent_context")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXRecentContextStore.appendUserMessage(ctx: ctx, text: "old-user", createdAt: 100)

        let capture = ProjectStoreWriteCapture()
        XTStoreWriteSupport.installWriteAttemptOverrideForTesting { data, url, options in
            try Self.writeWithScopedOutOfSpaceOverride(
                data: data,
                url: url,
                options: options,
                root: root,
                capture: capture
            )
        }
        defer { XTStoreWriteSupport.resetWriteBehaviorForTesting() }

        AXRecentContextStore.appendAssistantMessage(ctx: ctx, text: "new-assistant", createdAt: 101)

        let recent = AXRecentContextStore.load(for: ctx)
        #expect(recent.messages.map(\.content).contains("new-assistant"))

        let markdown = try String(contentsOf: AXRecentContextStore.markdownURL(for: ctx), encoding: .utf8)
        #expect(markdown.contains("new-assistant"))

        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 4)
        #expect(options.filter { $0.contains(.atomic) }.count == 2)
        #expect(options.filter(\.isEmpty).count == 2)
    }

    @Test
    func pendingActionsFallBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("pending_actions")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXPendingActionsStore.saveToolApproval(
            pendingToolApproval(id: "approval-old", preview: "old-preview"),
            for: ctx
        )

        let capture = ProjectStoreWriteCapture()
        XTStoreWriteSupport.installWriteAttemptOverrideForTesting { data, url, options in
            try Self.writeWithScopedOutOfSpaceOverride(
                data: data,
                url: url,
                options: options,
                root: root,
                capture: capture
            )
        }
        defer { XTStoreWriteSupport.resetWriteBehaviorForTesting() }

        AXPendingActionsStore.saveToolApproval(
            pendingToolApproval(id: "approval-new", preview: "new-preview"),
            for: ctx
        )

        let pending = try #require(AXPendingActionsStore.pendingToolApproval(for: ctx))
        #expect(pending.id == "approval-new")
        #expect(pending.preview == "new-preview")

        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options.filter { $0.contains(.atomic) }.count == 1)
        #expect(options.filter(\.isEmpty).count == 1)
    }

    @Test
    func sessionSummaryFallsBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("session_summary")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var memory = AXMemory.new(projectName: "Session Summary", projectRoot: root.path)
        memory.goal = "Keep summary writable under pressure."
        try AXProjectStore.saveMemory(memory, for: ctx)

        AXRecentContextStore.appendUserMessage(ctx: ctx, text: "Need a summary.", createdAt: 200)
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000).timeIntervalSince1970
        _ = AXMemoryLifecycleStore.writeSessionSummaryCapsule(
            ctx: ctx,
            reason: "before_override",
            now: fixedNow
        )

        let capture = ProjectStoreWriteCapture()
        XTStoreWriteSupport.installWriteAttemptOverrideForTesting { data, url, options in
            try Self.writeWithScopedOutOfSpaceOverride(
                data: data,
                url: url,
                options: options,
                root: root,
                capture: capture
            )
        }
        defer { XTStoreWriteSupport.resetWriteBehaviorForTesting() }

        let summary = try #require(
            AXMemoryLifecycleStore.writeSessionSummaryCapsule(
                ctx: ctx,
                reason: "after_override",
                now: fixedNow
            )
        )

        let latestData = try Data(contentsOf: ctx.latestSessionSummaryURL)
        let latest = try JSONDecoder().decode(AXSessionSummaryCapsule.self, from: latestData)
        #expect(summary.reason == "after_override")
        #expect(latest.reason == "after_override")
        let archivedSummaries = try FileManager.default.contentsOfDirectory(
            at: ctx.sessionSummariesDir,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix("session_summary_") }
        #expect(archivedSummaries.count == 1)

        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 3)
        #expect(options.filter { $0.contains(.atomic) }.count == 2)
        #expect(options.filter(\.isEmpty).count == 1)
    }

    private func makeProjectRoot(_ suffix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_project_write_support_\(suffix)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    nonisolated private static func writeWithScopedOutOfSpaceOverride(
        data: Data,
        url: URL,
        options: Data.WritingOptions,
        root: URL,
        capture: ProjectStoreWriteCapture
    ) throws {
        if !normalizedPath(url).hasPrefix(normalizedPath(root)) {
            try data.write(to: url, options: options)
            return
        }
        capture.appendWriteOption(options)
        if options.contains(.atomic) {
            throw NSError(domain: NSPOSIXErrorDomain, code: 28)
        }
        try data.write(to: url, options: options)
    }

    nonisolated private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path.replacingOccurrences(
            of: "/private",
            with: "",
            options: [.anchored]
        )
    }

    private func pendingToolApproval(id: String, preview: String) -> AXPendingAction {
        AXPendingAction(
            id: id,
            type: .toolApproval,
            createdAt: Date().timeIntervalSince1970,
            status: "pending",
            projectId: "proj-alpha",
            projectName: "Project Alpha",
            reason: "needs-approval",
            preview: preview,
            userText: "please run the tool",
            assistantStub: nil,
            toolCalls: nil,
            flow: nil
        )
    }
}

private final class ProjectStoreWriteCapture: @unchecked Sendable {
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
