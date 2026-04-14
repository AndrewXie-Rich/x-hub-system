import Foundation
import Testing
@testable import XTerminal

struct ToolExecutorGovernedReadRootsTests {
    @Test
    func readFileOutsideProjectRootFailsClosedByDefault() async throws {
        let fixture = ToolExecutorProjectFixture(name: "governed-read-roots-default-deny")
        let externalDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-governed-read-external-\(UUID().uuidString)", isDirectory: true)
        defer {
            fixture.cleanup()
            try? FileManager.default.removeItem(at: externalDir)
        }

        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        let externalFile = externalDir.appendingPathComponent("notes.txt")
        try Data("secret".utf8).write(to: externalFile, options: .atomic)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .read_file,
                args: ["path": .string(externalFile.path)]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["deny_code"]) == "path_outside_governed_read_roots")
        #expect(jsonString(summary["policy_source"]) == "governed_path_scope")
        #expect(jsonString(summary["target_path"]) == PathGuard.resolve(externalFile).path)
    }

    @Test
    func readFileOutsideProjectRootSucceedsWhenGovernedAuthorityAndRootsAreConfigured() async throws {
        let fixture = ToolExecutorProjectFixture(name: "governed-read-roots-read-ok")
        let externalDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-governed-read-allowed-\(UUID().uuidString)", isDirectory: true)
        defer {
            fixture.cleanup()
            try? FileManager.default.removeItem(at: externalDir)
        }

        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        let externalFile = externalDir.appendingPathComponent("notes.txt")
        try Data("external knowledge".utf8).write(to: externalFile, options: .atomic)

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingTrustedAutomationBinding(
            mode: .trustedAutomation,
            deviceId: "device_xt_001",
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
        )
        config = config.settingRuntimeSurfacePolicy(
            mode: .trustedOpenClawMode,
            ttlSeconds: 86_400,
            updatedAt: Date()
        )
        config = config.settingGovernedReadableRoots(
            paths: [externalDir.path],
            projectRoot: fixture.root
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .read_file,
                args: ["path": .string(externalFile.path)]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        #expect(result.output.contains("external knowledge"))
    }

    @Test
    func attachmentScopedReadableRootsAllowReadWithoutChangingProjectGovernance() async throws {
        let fixture = ToolExecutorProjectFixture(name: "attachment-readable-roots-read-ok")
        let externalDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-attachment-read-\(UUID().uuidString)", isDirectory: true)
        defer {
            fixture.cleanup()
            try? FileManager.default.removeItem(at: externalDir)
        }

        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        let externalFile = externalDir.appendingPathComponent("attachment.txt")
        try Data("attachment context".utf8).write(to: externalFile, options: .atomic)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .read_file,
                args: ["path": .string(externalFile.path)]
            ),
            projectRoot: fixture.root,
            extraReadableRoots: [externalDir]
        )

        #expect(result.ok)
        #expect(result.output.contains("attachment context"))
    }

    @Test
    func searchSupportsGovernedExternalRootWhenPathIsProvided() async throws {
        let fixture = ToolExecutorProjectFixture(name: "governed-read-roots-search-ok")
        let externalDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-governed-search-allowed-\(UUID().uuidString)", isDirectory: true)
        defer {
            fixture.cleanup()
            try? FileManager.default.removeItem(at: externalDir)
        }

        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        let externalFile = externalDir.appendingPathComponent("searchable.txt")
        try Data("needle-in-haystack".utf8).write(to: externalFile, options: .atomic)

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingTrustedAutomationBinding(
            mode: .trustedAutomation,
            deviceId: "device_xt_001",
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
        )
        config = config.settingRuntimeSurfacePolicy(
            mode: .trustedOpenClawMode,
            ttlSeconds: 86_400,
            updatedAt: Date()
        )
        config = config.settingGovernedReadableRoots(
            paths: [externalDir.path],
            projectRoot: fixture.root
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .search,
                args: [
                    "pattern": .string("needle-in-haystack"),
                    "path": .string(externalDir.path),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        #expect(result.output.contains("searchable.txt"))
    }

    @Test
    func listDirAtProjectRootOmitsInternalXTerminalDirectoryButKeepsWorkspaceFiles() async throws {
        let fixture = ToolExecutorProjectFixture(name: "project-root-list-dir-hides-xterminal")
        defer { fixture.cleanup() }

        let internalDir = fixture.root.appendingPathComponent(".xterminal", isDirectory: true)
        try FileManager.default.createDirectory(at: internalDir, withIntermediateDirectories: true)
        try Data("noise".utf8).write(
            to: internalDir.appendingPathComponent("usage.jsonl"),
            options: .atomic
        )
        try Data("# Tank Battle".utf8).write(
            to: fixture.root.appendingPathComponent("README.md"),
            options: .atomic
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .list_dir,
                args: ["path": .string(fixture.root.path)]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        #expect(result.output.contains("README.md"))
        #expect(!result.output.contains(".xterminal"))
    }

    @Test
    func listDirAtProjectRootWithOnlyInternalStateLooksLikeEmptyWorkspace() async throws {
        let fixture = ToolExecutorProjectFixture(name: "project-root-list-dir-only-xterminal")
        defer { fixture.cleanup() }

        let internalDir = fixture.root.appendingPathComponent(".xterminal", isDirectory: true)
        try FileManager.default.createDirectory(at: internalDir, withIntermediateDirectories: true)
        try Data("noise".utf8).write(
            to: internalDir.appendingPathComponent("usage.jsonl"),
            options: .atomic
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .list_dir,
                args: ["path": .string(fixture.root.path)]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        #expect(result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "(empty)")
        #expect(!result.output.contains(".xterminal"))
    }

    @Test
    func searchAtProjectRootSkipsInternalXTerminalMetadataButStillFindsWorkspaceFiles() async throws {
        let fixture = ToolExecutorProjectFixture(name: "project-root-search-skips-xterminal")
        defer { fixture.cleanup() }

        let internalDir = fixture.root.appendingPathComponent(".xterminal", isDirectory: true)
        try FileManager.default.createDirectory(at: internalDir, withIntermediateDirectories: true)
        try Data("needle from system state".utf8).write(
            to: internalDir.appendingPathComponent("usage.jsonl"),
            options: .atomic
        )
        try Data("needle from workspace".utf8).write(
            to: fixture.root.appendingPathComponent("README.md"),
            options: .atomic
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .search,
                args: [
                    "pattern": .string("needle"),
                    "path": .string(fixture.root.path),
                    "glob": .string("*")
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        #expect(result.output.contains("README.md"))
        #expect(!result.output.contains(".xterminal/usage.jsonl"))
    }

    @Test
    func searchAtProjectRootWithOnlyInternalStateReturnsNoMatches() async throws {
        let fixture = ToolExecutorProjectFixture(name: "project-root-search-only-xterminal")
        defer { fixture.cleanup() }

        let internalDir = fixture.root.appendingPathComponent(".xterminal", isDirectory: true)
        try FileManager.default.createDirectory(at: internalDir, withIntermediateDirectories: true)
        try Data("needle from system state".utf8).write(
            to: internalDir.appendingPathComponent("usage.jsonl"),
            options: .atomic
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .search,
                args: [
                    "pattern": .string("needle"),
                    "path": .string(fixture.root.path),
                    "glob": .string("*")
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        #expect(result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "(no matches)")
    }

    @Test
    func searchInsideInternalXTerminalDirectoryStillWorksWhenExplicitlyTargeted() async throws {
        let fixture = ToolExecutorProjectFixture(name: "xterminal-explicit-search")
        defer { fixture.cleanup() }

        let internalDir = fixture.root.appendingPathComponent(".xterminal", isDirectory: true)
        try FileManager.default.createDirectory(at: internalDir, withIntermediateDirectories: true)
        try Data("needle from system state".utf8).write(
            to: internalDir.appendingPathComponent("usage.jsonl"),
            options: .atomic
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .search,
                args: [
                    "pattern": .string("needle"),
                    "path": .string(".xterminal"),
                    "glob": .string("*")
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        #expect(result.output.contains(".xterminal/usage.jsonl"))
    }

    @Test
    func writeFileOutsideProjectRootRemainsDeniedEvenWithGovernedAuthority() async throws {
        let fixture = ToolExecutorProjectFixture(name: "governed-read-roots-write-deny")
        let externalDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-governed-write-deny-\(UUID().uuidString)", isDirectory: true)
        defer {
            fixture.cleanup()
            try? FileManager.default.removeItem(at: externalDir)
        }

        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        let externalFile = externalDir.appendingPathComponent("mutate.txt")

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingTrustedAutomationBinding(
            mode: .trustedAutomation,
            deviceId: "device_xt_001",
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
        )
        config = config.settingToolPolicy(profile: ToolProfile.coding.rawValue)
        config = config.settingRuntimeSurfacePolicy(
            mode: .trustedOpenClawMode,
            ttlSeconds: 86_400,
            updatedAt: Date()
        )
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        config = config.settingGovernedReadableRoots(
            paths: [externalDir.path],
            projectRoot: fixture.root
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .write_file,
                args: [
                    "path": .string(externalFile.path),
                    "content": .string("mutated")
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["deny_code"]) == "path_write_outside_project_root")
        #expect(jsonString(summary["policy_source"]) == "governed_path_scope")
        #expect(!FileManager.default.fileExists(atPath: externalFile.path))
    }

    @Test
    func attachmentScopedReadableRootsDoNotGrantWriteAccess() async throws {
        let fixture = ToolExecutorProjectFixture(name: "attachment-readable-roots-write-deny")
        let externalDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-attachment-write-\(UUID().uuidString)", isDirectory: true)
        defer {
            fixture.cleanup()
            try? FileManager.default.removeItem(at: externalDir)
        }

        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        let externalFile = externalDir.appendingPathComponent("attachment.txt")

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingToolPolicy(profile: ToolProfile.coding.rawValue)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .write_file,
                args: [
                    "path": .string(externalFile.path),
                    "content": .string("mutated")
                ]
            ),
            projectRoot: fixture.root,
            extraReadableRoots: [externalDir]
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["deny_code"]) == "path_write_outside_project_root")
        #expect(!FileManager.default.fileExists(atPath: externalFile.path))
    }
}
