import Darwin
import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct AXModelRouteDiagnosticsStoreTests {

    @Test
    func appendUsageRecordsOnlyNotableModelRouteEvents() throws {
        let root = try makeProjectRoot(named: "model-route-diagnostics-notable")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 100,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-5.4",
                "actual_model_id": "openai/gpt-5.4",
                "runtime_provider": "Hub (Remote)",
                "execution_path": "remote_model"
            ],
            for: ctx
        )
        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 110,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-5.4",
                "actual_model_id": "qwen3-14b-mlx",
                "runtime_provider": "Hub (Local)",
                "execution_path": "hub_downgraded_to_local",
                "fallback_reason_code": "downgrade_to_local"
            ],
            for: ctx
        )
        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 120,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-5.4",
                "actual_model_id": "openai/gpt-4.1",
                "runtime_provider": "Hub (Remote)",
                "execution_path": "remote_model",
                "remote_retry_attempted": true,
                "remote_retry_from_model_id": "openai/gpt-5.4",
                "remote_retry_to_model_id": "openai/gpt-4.1",
                "remote_retry_reason_code": "model_not_found"
            ],
            for: ctx
        )

        let events = AXModelRouteDiagnosticsStore.recentEvents(for: ctx, limit: 10)

        #expect(events.count == 2)
        #expect(events.first?.executionPath == "remote_model")
        #expect(events.first?.remoteRetryAttempted == true)
        #expect(events.last?.executionPath == "hub_downgraded_to_local")
    }

    @Test
    func doctorSummaryAggregatesRecentIncidentsAcrossProjects() throws {
        let rootA = try makeProjectRoot(named: "model-route-diagnostics-summary-a")
        let rootB = try makeProjectRoot(named: "model-route-diagnostics-summary-b")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        let ctxA = AXProjectContext(root: rootA)
        let ctxB = AXProjectContext(root: rootB)
        try ctxA.ensureDirs()
        try ctxB.ensureDirs()

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 1_000,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-5.4",
                "actual_model_id": "qwen3-14b-mlx",
                "runtime_provider": "Hub (Local)",
                "execution_path": "local_fallback_after_remote_error",
                "fallback_reason_code": "model_not_found"
            ],
            for: ctxA
        )
        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 1_010,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-5.4",
                "actual_model_id": "openai/gpt-4.1",
                "runtime_provider": "Hub (Remote)",
                "execution_path": "remote_model",
                "remote_retry_attempted": true,
                "remote_retry_from_model_id": "openai/gpt-5.4",
                "remote_retry_to_model_id": "openai/gpt-4.1",
                "remote_retry_reason_code": "downgrade_to_local"
            ],
            for: ctxB
        )

        let summary = AXModelRouteDiagnosticsStore.doctorSummary(
            for: [
                AXProjectEntry(
                    projectId: AXProjectRegistryStore.projectId(forRoot: rootA),
                    rootPath: rootA.path,
                    displayName: "Project A",
                    lastOpenedAt: 1_000,
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
                    projectId: AXProjectRegistryStore.projectId(forRoot: rootB),
                    rootPath: rootB.path,
                    displayName: "Project B",
                    lastOpenedAt: 1_010,
                    manualOrderIndex: 1,
                    pinned: false,
                    statusDigest: nil,
                    currentStateSummary: nil,
                    nextStepSummary: nil,
                    blockerSummary: nil,
                    lastSummaryAt: nil,
                    lastEventAt: nil
                )
            ],
            now: Date(timeIntervalSince1970: 1_020),
            recentWindow: 60,
            limit: 3
        )

        #expect(summary.recentEventCount == 2)
        #expect(summary.recentFailureCount == 1)
        #expect(summary.recentRemoteRetryRecoveryCount == 1)
        #expect(summary.detailLines.contains("recent_route_failures_24h=1"))
        #expect(summary.detailLines.contains(where: { $0.contains("Project A") }))
        #expect(summary.detailLines.contains(where: { $0.contains("remote_retry=openai/gpt-5.4->openai/gpt-4.1") }))
    }

    @Test
    func appendUsageUsesFriendlyRegistryDisplayNameWhenPresent() async throws {
        let root = try makeProjectRoot(named: "model-route-diagnostics-friendly")
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
                updatedAt: 900,
                sortPolicy: "manual_then_last_opened",
                globalHomeVisible: false,
                lastSelectedProjectId: projectId,
                projects: [
                    AXProjectEntry(
                        projectId: projectId,
                        rootPath: root.path,
                        displayName: "亮亮",
                        lastOpenedAt: 900,
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

            AXProjectStore.appendUsage(
                [
                    "type": "ai_usage",
                    "created_at": 100,
                    "stage": "chat_plan",
                    "role": "coder",
                    "requested_model_id": "openai/gpt-5.4",
                    "actual_model_id": "qwen3-14b-mlx",
                    "runtime_provider": "Hub (Local)",
                    "execution_path": "hub_downgraded_to_local",
                    "fallback_reason_code": "downgrade_to_local"
                ],
                for: ctx
            )

            let events = AXModelRouteDiagnosticsStore.recentEvents(for: ctx, limit: 5)
            #expect(events.first?.projectDisplayName == "亮亮")
        }
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
