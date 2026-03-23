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
            updatedAt: Date(timeIntervalSince1970: 1_773_700_000)
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
            updatedAt: Date(timeIntervalSince1970: 1_773_700_100)
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
        config = config.settingRuntimeSurfacePolicy(
            mode: .trustedOpenClawMode,
            updatedAt: Date(timeIntervalSince1970: 1_773_700_200)
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
}
