import Foundation
import Testing
@testable import XTerminal

@MainActor
struct XTProjectUIPresentationReadCacheTests {
    @Test
    func roleExecutionSnapshotUsesFreshCacheAndExpiresByAge() {
        let ctx = AXProjectContext(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("xt-ui-read-cache-role-\(UUID().uuidString)", isDirectory: true)
        )
        let now = Date(timeIntervalSince1970: 100)
        var loadCount = 0

        let first = XTProjectUIPresentationReadCache.roleExecutionSnapshot(
            for: ctx,
            role: .coder,
            now: now
        ) {
            loadCount += 1
            return roleSnapshot(requestedModelId: "first")
        }
        let second = XTProjectUIPresentationReadCache.roleExecutionSnapshot(
            for: ctx,
            role: .coder,
            now: now.addingTimeInterval(0.5)
        ) {
            loadCount += 1
            return roleSnapshot(requestedModelId: "second")
        }
        let expired = XTProjectUIPresentationReadCache.roleExecutionSnapshot(
            for: ctx,
            role: .coder,
            now: now.addingTimeInterval(2)
        ) {
            loadCount += 1
            return roleSnapshot(requestedModelId: "expired")
        }

        #expect(first.requestedModelId == "first")
        #expect(second.requestedModelId == "first")
        #expect(expired.requestedModelId == "expired")
        #expect(loadCount == 2)
    }

    @Test
    func recentSkillActivitiesCacheIsScopedByLimit() {
        let ctx = AXProjectContext(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("xt-ui-read-cache-skill-\(UUID().uuidString)", isDirectory: true)
        )
        let now = Date(timeIntervalSince1970: 200)
        var limitEightLoads = 0
        var limitTwelveLoads = 0

        _ = XTProjectUIPresentationReadCache.recentSkillActivities(
            for: ctx,
            limit: 8,
            now: now
        ) {
            limitEightLoads += 1
            return []
        }
        _ = XTProjectUIPresentationReadCache.recentSkillActivities(
            for: ctx,
            limit: 8,
            now: now.addingTimeInterval(0.2)
        ) {
            limitEightLoads += 1
            return []
        }
        _ = XTProjectUIPresentationReadCache.recentSkillActivities(
            for: ctx,
            limit: 12,
            now: now.addingTimeInterval(0.2)
        ) {
            limitTwelveLoads += 1
            return []
        }

        #expect(limitEightLoads == 1)
        #expect(limitTwelveLoads == 1)
    }

    @Test
    func latestGovernanceInterceptionCachesNilReadModels() {
        let ctx = AXProjectContext(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("xt-ui-read-cache-governance-\(UUID().uuidString)", isDirectory: true)
        )
        let now = Date(timeIntervalSince1970: 300)
        var loadCount = 0

        let first = XTProjectUIPresentationReadCache.latestGovernanceInterception(
            for: ctx,
            limit: 12,
            now: now
        ) {
            loadCount += 1
            return nil
        }
        let second = XTProjectUIPresentationReadCache.latestGovernanceInterception(
            for: ctx,
            limit: 12,
            now: now.addingTimeInterval(0.2)
        ) {
            loadCount += 1
            return nil
        }

        #expect(first == nil)
        #expect(second == nil)
        #expect(loadCount == 1)
    }

    @Test
    func projectConfigCacheKeepsFreshReadModel() {
        let ctx = AXProjectContext(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("xt-ui-read-cache-config-\(UUID().uuidString)", isDirectory: true)
        )
        let now = Date(timeIntervalSince1970: 400)
        var loadCount = 0

        let first = XTProjectUIPresentationReadCache.projectConfig(
            for: ctx,
            now: now
        ) {
            loadCount += 1
            return AXProjectConfig.default(forProjectRoot: ctx.root)
        }
        let second = XTProjectUIPresentationReadCache.projectConfig(
            for: ctx,
            now: now.addingTimeInterval(0.3)
        ) {
            loadCount += 1
            var config = AXProjectConfig.default(forProjectRoot: ctx.root)
            config = config.settingModelOverride(role: .coder, modelId: "changed")
            return config
        }

        #expect(first == second)
        #expect(loadCount == 1)
    }

    @Test
    func latestRouteEventCacheExpiresByAge() {
        let ctx = AXProjectContext(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("xt-ui-read-cache-route-\(UUID().uuidString)", isDirectory: true)
        )
        let now = Date(timeIntervalSince1970: 500)
        var loadCount = 0

        let first = XTProjectUIPresentationReadCache.latestRouteEvent(
            for: ctx,
            limit: 1,
            now: now
        ) {
            loadCount += 1
            return routeEvent(createdAt: 1)
        }
        let second = XTProjectUIPresentationReadCache.latestRouteEvent(
            for: ctx,
            limit: 1,
            now: now.addingTimeInterval(0.3)
        ) {
            loadCount += 1
            return routeEvent(createdAt: 2)
        }
        let expired = XTProjectUIPresentationReadCache.latestRouteEvent(
            for: ctx,
            limit: 1,
            now: now.addingTimeInterval(2)
        ) {
            loadCount += 1
            return routeEvent(createdAt: 3)
        }

        #expect(first?.createdAt == 1)
        #expect(second?.createdAt == 1)
        #expect(expired?.createdAt == 3)
        #expect(loadCount == 2)
    }

    private func roleSnapshot(requestedModelId: String) -> AXRoleExecutionSnapshot {
        AXRoleExecutionSnapshots.snapshot(
            role: .coder,
            updatedAt: 100,
            stage: "complete",
            requestedModelId: requestedModelId,
            actualModelId: requestedModelId,
            runtimeProvider: "hub",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            source: "test"
        )
    }

    private func routeEvent(createdAt: Double) -> AXModelRouteDiagnosticEvent {
        AXModelRouteDiagnosticEvent(
            schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
            createdAt: createdAt,
            projectId: "cache-route",
            projectDisplayName: "Cache Route",
            role: "coder",
            stage: "complete",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            runtimeProvider: "hub",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            auditRef: nil,
            denyCode: nil,
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: ""
        )
    }
}
