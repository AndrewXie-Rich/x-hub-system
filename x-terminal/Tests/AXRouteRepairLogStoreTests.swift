import Darwin
import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct AXRouteRepairLogStoreTests {
    @Test
    func recordsRecentEventsInReverseChronologicalOrder() throws {
        let root = try makeProjectRoot(named: "route-repair-log")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXRouteRepairLogStore.record(
            actionId: "open_xt_diagnostics",
            outcome: "opened",
            latestEvent: makeEvent(fallbackReasonCode: "grpc_route_unavailable"),
            createdAt: 100,
            for: ctx
        )
        AXRouteRepairLogStore.record(
            actionId: "connect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeEvent(fallbackReasonCode: "runtime_not_running"),
            repairReasonCode: "grpc_route_unavailable",
            note: "remote tunnel timeout",
            createdAt: 200,
            for: ctx
        )

        let events = AXRouteRepairLogStore.recentEvents(for: ctx, limit: 10)
        #expect(events.count == 2)
        #expect(events.first?.actionId == "connect_hub_and_diagnose")
        #expect(events.first?.outcome == "failed")
        #expect(events.first?.repairReasonCode == "grpc_route_unavailable")
        #expect(events.first?.note == "remote tunnel timeout")

        let lines = AXRouteRepairLogStore.summaryLines(for: ctx, limit: 10)
        #expect(lines.count == 2)
        #expect(lines[0].contains("action=connect_hub_and_diagnose"))
        #expect(lines[0].contains("outcome=failed"))
        #expect(lines[0].contains("route_reason=runtime_not_running"))
        #expect(lines[0].contains("repair_reason=grpc_route_unavailable"))
    }

    @Test
    func recordUsesFriendlyRegistryDisplayNameWhenPresent() async throws {
        let root = try makeProjectRoot(named: "route-repair-log-friendly")
        let registryBase = root.appendingPathComponent("registry", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: registryBase, withIntermediateDirectories: true)

        try await withTemporaryEnvironment([
            "XTERMINAL_PROJECT_REGISTRY_BASE_DIR": registryBase.path
        ]) {
            let ctx = AXProjectContext(root: root)
            try ctx.ensureDirs()

            let projectId = AXProjectRegistryStore.projectId(forRoot: root)
            let registry = AXProjectRegistry(
                version: AXProjectRegistry.currentVersion,
                updatedAt: 950,
                sortPolicy: "manual_then_last_opened",
                globalHomeVisible: false,
                lastSelectedProjectId: projectId,
                projects: [
                    AXProjectEntry(
                        projectId: projectId,
                        rootPath: root.path,
                        displayName: "耳机复盘项目",
                        lastOpenedAt: 950,
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
            AXProjectRegistryStore.save(registry)

            AXRouteRepairLogStore.record(
                actionId: "open_xt_diagnostics",
                outcome: "opened",
                latestEvent: makeEvent(fallbackReasonCode: "grpc_route_unavailable"),
                createdAt: 100,
                for: ctx
            )

            let event = try #require(AXRouteRepairLogStore.recentEvents(for: ctx, limit: 1).first)
            #expect(event.projectDisplayName == "耳机复盘项目")
            #expect(event.summaryLine(includeProject: true).contains("project=耳机复盘项目"))
        }
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_route_repair_log_\(name)_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeEvent(fallbackReasonCode: String) -> AXModelRouteDiagnosticEvent {
        AXModelRouteDiagnosticEvent(
            schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
            createdAt: 100,
            projectId: "project-1",
            projectDisplayName: "Project 1",
            role: "coder",
            stage: "chat",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: fallbackReasonCode,
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: ""
        )
    }
}

private func currentEnvironmentValue(_ key: String) -> String? {
    guard let value = getenv(key) else { return nil }
    return String(cString: value)
}

private func withTemporaryEnvironment<T>(
    _ overrides: [String: String?],
    operation: () async throws -> T
) async rethrows -> T {
    let original = Dictionary(uniqueKeysWithValues: overrides.keys.map { ($0, currentEnvironmentValue($0)) })
    for (key, value) in overrides {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }
    defer {
        for (key, value) in original {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
    }
    return try await operation()
}
