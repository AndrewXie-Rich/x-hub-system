import Darwin
import Foundation
import Testing
@testable import XTerminal

actor RustProjectCanonicalMemoryFetchRecorder {
    private var projectIds: [String] = []

    func append(_ projectId: String) {
        projectIds.append(projectId)
    }

    func count() -> Int {
        projectIds.count
    }
}

actor RustMemoryGatewayPrepareRecorder {
    private var requests: [HubIPCClient.RustMemoryGatewayPrepareRequest] = []

    func append(_ request: HubIPCClient.RustMemoryGatewayPrepareRequest) {
        requests.append(request)
    }

    func count() -> Int {
        requests.count
    }
}

@Suite(.serialized)
struct HubIPCClientProjectCanonicalMemorySyncTests {
    private static let gate = HubGlobalStateTestGate.shared

    @Test
    func syncProjectCanonicalMemoryUsesFriendlyRegistryNameInPayloadAndCanonicalItems() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_sync_\(UUID().uuidString)", isDirectory: true)
            let projectRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub-project-memory-friendly-\(UUID().uuidString)", isDirectory: true)
            let registryBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_registry_\(UUID().uuidString)", isDirectory: true)
            let originalMode = HubAIClient.transportMode()

            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: registryBase, withIntermediateDirectories: true)
            try writeTestHubStatus(base: hubBase)

            HubAIClient.setTransportMode(.fileIPC)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
                try? FileManager.default.removeItem(at: projectRoot)
                try? FileManager.default.removeItem(at: registryBase)
            }

            try await withTemporaryEnvironment([
                "XTERMINAL_PROJECT_REGISTRY_BASE_DIR": registryBase.path
            ]) {
                let ctx = AXProjectContext(root: projectRoot)
                try ctx.ensureDirs()

                let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
                let friendlyName = "Supervisor 耳机项目"
                let registry = AXProjectRegistry(
                    version: AXProjectRegistry.currentVersion,
                    updatedAt: 500,
                    sortPolicy: "manual_then_last_opened",
                    globalHomeVisible: false,
                    lastSelectedProjectId: projectId,
                    projects: [
                        AXProjectEntry(
                            projectId: projectId,
                            rootPath: projectRoot.path,
                            displayName: friendlyName,
                            lastOpenedAt: 500,
                            manualOrderIndex: 0,
                            pinned: false,
                            statusDigest: "sync=ready",
                            currentStateSummary: nil,
                            nextStepSummary: nil,
                            blockerSummary: nil,
                            lastSummaryAt: 500,
                            lastEventAt: 500
                        )
                    ]
                )
                AXProjectRegistryStore.save(registry)

                var memory = AXMemory.new(
                    projectName: projectRoot.lastPathComponent,
                    projectRoot: projectRoot.path
                )
                memory.goal = "Keep canonical Hub memory aligned with the friendly project identity."
                memory.updatedAt = 1_772_200_222.0

                HubIPCClient.syncProjectCanonicalMemory(ctx: ctx, memory: memory, config: nil)

                let eventDir = hubBase.appendingPathComponent("ipc_events", isDirectory: true)
                let files = try FileManager.default.contentsOfDirectory(at: eventDir, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.hasPrefix("xterminal_project_memory_") }
                #expect(files.count == 1)

                let eventFile = try #require(files.first)
                let data = try Data(contentsOf: eventFile)
                let decoded = try JSONDecoder().decode(HubIPCClient.ProjectCanonicalMemoryIPCRequest.self, from: data)
                let payload = decoded.projectCanonicalMemory

                #expect(decoded.type == "project_canonical_memory")
                #expect(payload.projectId == projectId)
                #expect(payload.displayName == friendlyName)
                #expect(payload.displayName != projectRoot.lastPathComponent)

                let lookup = Dictionary(uniqueKeysWithValues: payload.items.map { ($0.key, $0.value) })
                #expect(lookup["xterminal.project.memory.project_name"] == friendlyName)

                let summary = try #require(lookup["xterminal.project.memory.summary_json"])
                let summaryData = try #require(summary.data(using: .utf8))
                let summaryObject = try #require(
                    JSONSerialization.jsonObject(with: summaryData) as? [String: Any]
                )
                #expect(summaryObject["project_name"] as? String == friendlyName)
            }
        }
    }

    @Test
    func syncProjectCanonicalMemoryRecordsFailedSyncStatusWhenLocalWriteFails() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_sync_failure_\(UUID().uuidString)", isDirectory: true)
            let projectRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub-project-memory-failure-\(UUID().uuidString)", isDirectory: true)
            let registryBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_registry_failure_\(UUID().uuidString)", isDirectory: true)
            let originalMode = HubAIClient.transportMode()

            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: registryBase, withIntermediateDirectories: true)
            try writeTestHubStatus(base: hubBase)

            HubAIClient.setTransportMode(.fileIPC)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            installScopedProjectMemoryWriteFailureOverride(base: hubBase)
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubIPCClient.resetIPCEventWriteOverrideForTesting()
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
                try? FileManager.default.removeItem(at: projectRoot)
                try? FileManager.default.removeItem(at: registryBase)
            }

            try await withTemporaryEnvironment([
                "XTERMINAL_PROJECT_REGISTRY_BASE_DIR": registryBase.path
            ]) {
                let ctx = AXProjectContext(root: projectRoot)
                try ctx.ensureDirs()

                let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
                AXProjectRegistryStore.save(
                    AXProjectRegistry(
                        version: AXProjectRegistry.currentVersion,
                        updatedAt: 500,
                        sortPolicy: "manual_then_last_opened",
                        globalHomeVisible: false,
                        lastSelectedProjectId: projectId,
                        projects: [
                            AXProjectEntry(
                                projectId: projectId,
                                rootPath: projectRoot.path,
                                displayName: "Sync Failure Project",
                                lastOpenedAt: 500,
                                manualOrderIndex: 0,
                                pinned: false,
                                statusDigest: "sync=stale",
                                currentStateSummary: nil,
                                nextStepSummary: nil,
                                blockerSummary: nil,
                                lastSummaryAt: 500,
                                lastEventAt: 500
                            )
                        ]
                    )
                )

                var memory = AXMemory.new(
                    projectName: projectRoot.lastPathComponent,
                    projectRoot: projectRoot.path
                )
                memory.goal = "Surface canonical sync write failures."
                memory.updatedAt = 1_772_200_333.0

                HubIPCClient.syncProjectCanonicalMemory(ctx: ctx, memory: memory, config: nil)

                let snapshot = try #require(HubIPCClient.canonicalMemorySyncStatusSnapshot(limit: 10))
                let item = try #require(snapshot.items.first { $0.scopeId == projectId })
                #expect(item.scopeKind == "project")
                #expect(item.ok == false)
                #expect(item.source == "file_ipc")
                #expect(item.reasonCode == "project_canonical_memory_write_failed")
                #expect(item.detail?.contains("xterminal_project_memory_write_failed") == true)
            }
        }
    }

    @Test
    func syncProjectCanonicalMemoryPrefersRustKernelWhenAvailable() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_rust_sync_\(UUID().uuidString)", isDirectory: true)
            let projectRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub-project-memory-rust-\(UUID().uuidString)", isDirectory: true)
            let stateDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_rust_state_\(UUID().uuidString)", isDirectory: true)
            let originalMode = HubAIClient.transportMode()

            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
            try writeTestHubStatus(base: hubBase)

            HubAIClient.setTransportMode(.auto)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            HubIPCClient.installProjectCanonicalRustSyncUnscopedOverrideForTesting { payload in
                #expect(payload.projectId == AXProjectRegistryStore.projectId(forRoot: projectRoot))
                return HubIPCClient.ProjectCanonicalMemoryRustSyncOverrideResult(
                    ok: true,
                    source: "rust_http",
                    deliveryState: "delivered_rust_memory_objects",
                    detail: "created_count=1 updated_count=0"
                )
            }
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubIPCClient.resetProjectCanonicalRustSyncUnscopedOverrideForTesting()
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
                try? FileManager.default.removeItem(at: projectRoot)
                try? FileManager.default.removeItem(at: stateDir)
            }

            try await withTemporaryEnvironment([
                "AXHUBCTL_STATE_DIR": stateDir.path
            ]) {
                let ctx = AXProjectContext(root: projectRoot)
                try ctx.ensureDirs()
                let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
                let pendingURL = pendingProjectCanonicalRustSyncURL(projectRoot: projectRoot)
                try FileManager.default.createDirectory(
                    at: pendingURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("stale".utf8).write(to: pendingURL, options: .atomic)

                var memory = AXMemory.new(
                    projectName: "Rust Sync Project",
                    projectRoot: projectRoot.path
                )
                memory.goal = "Route canonical project memory into Rust memory objects."
                memory.updatedAt = 1_772_200_444.0

                HubIPCClient.syncProjectCanonicalMemory(ctx: ctx, memory: memory, config: nil)

                let item = try #require(await waitForCanonicalSyncItem(scopeId: projectId))
                #expect(item.ok)
                #expect(item.source == "rust_http")
                #expect(item.deliveryState == "delivered_rust_memory_objects")
                #expect(item.detail?.contains("created_count=1") == true)

                let eventDir = hubBase.appendingPathComponent("ipc_events", isDirectory: true)
                let files = try FileManager.default.contentsOfDirectory(at: eventDir, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.hasPrefix("xterminal_project_memory_") }
                #expect(files.isEmpty)
                #expect(!FileManager.default.fileExists(atPath: pendingURL.path))
            }
        }
    }

    @Test
    func syncProjectCanonicalMemoryFallsBackToLocalIPCWhenRustKernelUnavailable() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_rust_fallback_\(UUID().uuidString)", isDirectory: true)
            let projectRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub-project-memory-rust-fallback-\(UUID().uuidString)", isDirectory: true)
            let stateDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_rust_fallback_state_\(UUID().uuidString)", isDirectory: true)
            let originalMode = HubAIClient.transportMode()

            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
            try writeTestHubStatus(base: hubBase)

            HubAIClient.setTransportMode(.auto)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            HubIPCClient.installProjectCanonicalRustSyncUnscopedOverrideForTesting { _ in
                HubIPCClient.ProjectCanonicalMemoryRustSyncOverrideResult(
                    ok: false,
                    source: "rust_http",
                    deliveryState: "rust_http_unavailable",
                    reasonCode: "project_canonical_memory_rust_http_unavailable",
                    detail: "connection refused"
                )
            }
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubIPCClient.resetProjectCanonicalRustSyncUnscopedOverrideForTesting()
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
                try? FileManager.default.removeItem(at: projectRoot)
                try? FileManager.default.removeItem(at: stateDir)
            }

            try await withTemporaryEnvironment([
                "AXHUBCTL_STATE_DIR": stateDir.path
            ]) {
                let ctx = AXProjectContext(root: projectRoot)
                try ctx.ensureDirs()
                let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)

                var memory = AXMemory.new(
                    projectName: "Rust Fallback Project",
                    projectRoot: projectRoot.path
                )
                memory.goal = "Keep local IPC fallback available when Rust sync fails."
                memory.updatedAt = 1_772_200_555.0

                HubIPCClient.syncProjectCanonicalMemory(ctx: ctx, memory: memory, config: nil)

                let item = try #require(await waitForCanonicalSyncItem(scopeId: projectId))
                #expect(item.ok)
                #expect(item.source == "file_ipc")
                #expect(item.deliveryState == "queued_local_file_ipc")

                let eventDir = hubBase.appendingPathComponent("ipc_events", isDirectory: true)
                let files = try FileManager.default.contentsOfDirectory(at: eventDir, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.hasPrefix("xterminal_project_memory_") }
                #expect(files.count == 1)

                let pendingURL = pendingProjectCanonicalRustSyncURL(projectRoot: projectRoot)
                let pendingData = try Data(contentsOf: pendingURL)
                let pending = try JSONDecoder().decode(
                    HubIPCClient.ProjectCanonicalMemoryPendingRustSyncSnapshot.self,
                    from: pendingData
                )
                #expect(pending.schemaVersion == HubIPCClient.ProjectCanonicalMemoryPendingRustSyncSnapshot.schemaVersion)
                #expect(pending.projectId == projectId)
                #expect(pending.projectRoot == projectRoot.path)
                #expect(pending.deliveryState == "rust_http_unavailable")
                #expect(pending.reasonCode == "project_canonical_memory_rust_http_unavailable")
                #expect(pending.payload.projectId == projectId)
            }
        }
    }

    @Test
    func retryPendingProjectCanonicalRustSyncClearsSnapshotWhenRustRecovers() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_rust_retry_\(UUID().uuidString)", isDirectory: true)
            let projectRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub-project-memory-rust-retry-\(UUID().uuidString)", isDirectory: true)
            let stateDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_rust_retry_state_\(UUID().uuidString)", isDirectory: true)
            let originalMode = HubAIClient.transportMode()

            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
            try writeTestHubStatus(base: hubBase)

            HubAIClient.setTransportMode(.auto)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubIPCClient.resetProjectCanonicalRustSyncUnscopedOverrideForTesting()
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
                try? FileManager.default.removeItem(at: projectRoot)
                try? FileManager.default.removeItem(at: stateDir)
            }

            try await withTemporaryEnvironment([
                "AXHUBCTL_STATE_DIR": stateDir.path
            ]) {
                let ctx = AXProjectContext(root: projectRoot)
                try ctx.ensureDirs()
                let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)

                HubIPCClient.installProjectCanonicalRustSyncUnscopedOverrideForTesting { _ in
                    HubIPCClient.ProjectCanonicalMemoryRustSyncOverrideResult(
                        ok: false,
                        source: "rust_http",
                        deliveryState: "rust_http_unavailable",
                        reasonCode: "project_canonical_memory_rust_http_unavailable",
                        detail: "connection refused"
                    )
                }

                var memory = AXMemory.new(
                    projectName: "Rust Retry Project",
                    projectRoot: projectRoot.path
                )
                memory.goal = "Retry pending Rust canonical sync when the kernel recovers."
                memory.updatedAt = 1_772_200_666.0

                HubIPCClient.syncProjectCanonicalMemory(ctx: ctx, memory: memory, config: nil)
                _ = try #require(await waitForCanonicalSyncItem(scopeId: projectId))
                let pendingURL = pendingProjectCanonicalRustSyncURL(projectRoot: projectRoot)
                #expect(FileManager.default.fileExists(atPath: pendingURL.path))

                HubIPCClient.installProjectCanonicalRustSyncUnscopedOverrideForTesting { payload in
                    #expect(payload.projectId == projectId)
                    return HubIPCClient.ProjectCanonicalMemoryRustSyncOverrideResult(
                        ok: true,
                        source: "rust_http",
                        deliveryState: "delivered_rust_memory_objects",
                        detail: "updated_count=1"
                    )
                }

                let retry = await HubIPCClient.retryPendingProjectCanonicalRustSync(ctx: ctx)
                #expect(retry.attempted)
                #expect(retry.ok)
                #expect(retry.source == "rust_http")
                #expect(retry.deliveryState == "delivered_rust_memory_objects")
                #expect(!FileManager.default.fileExists(atPath: pendingURL.path))

                let status = try #require(HubIPCClient.canonicalMemorySyncStatusSnapshot(limit: 10))
                let item = try #require(status.items.first { $0.scopeKind == "project" && $0.scopeId == projectId })
                #expect(item.ok)
                #expect(item.source == "rust_http")
            }
        }
    }

    @Test
    func retryPendingProjectCanonicalRustSyncKeepsSnapshotWhenRustStillUnavailable() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_rust_retry_unavailable_\(UUID().uuidString)", isDirectory: true)
            let projectRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub-project-memory-rust-retry-unavailable-\(UUID().uuidString)", isDirectory: true)
            let stateDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_rust_retry_unavailable_state_\(UUID().uuidString)", isDirectory: true)
            let originalMode = HubAIClient.transportMode()

            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
            try writeTestHubStatus(base: hubBase)

            HubAIClient.setTransportMode(.auto)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            HubIPCClient.installProjectCanonicalRustSyncUnscopedOverrideForTesting { _ in
                HubIPCClient.ProjectCanonicalMemoryRustSyncOverrideResult(
                    ok: false,
                    source: "rust_http",
                    deliveryState: "rust_http_unavailable",
                    reasonCode: "project_canonical_memory_rust_http_unavailable",
                    detail: "connection refused"
                )
            }
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubIPCClient.resetProjectCanonicalRustSyncUnscopedOverrideForTesting()
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
                try? FileManager.default.removeItem(at: projectRoot)
                try? FileManager.default.removeItem(at: stateDir)
            }

            try await withTemporaryEnvironment([
                "AXHUBCTL_STATE_DIR": stateDir.path
            ]) {
                let ctx = AXProjectContext(root: projectRoot)
                try ctx.ensureDirs()
                let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)

                var memory = AXMemory.new(
                    projectName: "Rust Retry Unavailable Project",
                    projectRoot: projectRoot.path
                )
                memory.goal = "Keep pending Rust canonical sync when the kernel is still unavailable."
                memory.updatedAt = 1_772_200_777.0

                HubIPCClient.syncProjectCanonicalMemory(ctx: ctx, memory: memory, config: nil)
                _ = try #require(await waitForCanonicalSyncItem(scopeId: projectId))
                let pendingURL = pendingProjectCanonicalRustSyncURL(projectRoot: projectRoot)
                #expect(FileManager.default.fileExists(atPath: pendingURL.path))

                let retry = await HubIPCClient.retryPendingProjectCanonicalRustSync(ctx: ctx)
                #expect(retry.attempted)
                #expect(!retry.ok)
                #expect(retry.deliveryState == "rust_http_unavailable")
                #expect(FileManager.default.fileExists(atPath: pendingURL.path))
            }
        }
    }

    @Test
    func requestMemoryContextPrefersRustCanonicalObjectsAfterSuccessfulRustSyncStatus() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_rust_context_\(UUID().uuidString)", isDirectory: true)
            let projectRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub-project-memory-rust-context-\(UUID().uuidString)", isDirectory: true)
            let originalMode = HubAIClient.transportMode()
            let recorder = RustProjectCanonicalMemoryFetchRecorder()

            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
            HubAIClient.setTransportMode(.auto)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubIPCClient.resetMemoryContextResolutionOverrideForTesting()
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
                try? FileManager.default.removeItem(at: projectRoot)
            }

            let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
            try writeRustCanonicalSyncStatus(base: hubBase, projectId: projectId)

            HubIPCClient.installHubRouteDecisionOverrideForTesting {
                HubRouteDecision(
                    mode: .auto,
                    hasRemoteProfile: true,
                    preferRemote: true,
                    allowFileFallback: true,
                    requiresRemote: false,
                    remoteUnavailableReasonCode: nil
                )
            }
            HubIPCClient.installRemoteMemorySnapshotOverrideForTesting { _, _, _, _ in
                HubRemoteMemorySnapshotResult(
                    ok: true,
                    source: "hub_memory_v1_grpc",
                    canonicalEntries: ["remote canonical stale"],
                    workingEntries: ["remote working stale"],
                    reasonCode: nil,
                    logLines: []
                )
            }
            HubIPCClient.installRustProjectCanonicalMemoryOverrideForTesting { incomingProjectId, limit, _ in
                await recorder.append(incomingProjectId)
                #expect(incomingProjectId == projectId)
                #expect(limit == 64)
                return HubIPCClient.RustProjectCanonicalMemorySnapshot(
                    source: "rust_http",
                    projectId: incomingProjectId,
                    objects: [
                        HubIPCClient.RustProjectCanonicalMemoryObject(
                            memoryId: "mem_xt_project_\(incomingProjectId)_goal",
                            ownerId: incomingProjectId,
                            projectId: incomingProjectId,
                            sourceKind: "project_goal",
                            layer: "l1_canonical",
                            title: "Project goal",
                            text: "Rust canonical goal"
                        ),
                        HubIPCClient.RustProjectCanonicalMemoryObject(
                            memoryId: "mem_xt_project_\(incomingProjectId)_risks",
                            ownerId: incomingProjectId,
                            projectId: incomingProjectId,
                            sourceKind: "risk",
                            layer: "l2_observations",
                            title: "Risks",
                            text: "Rust risk observation"
                        ),
                        HubIPCClient.RustProjectCanonicalMemoryObject(
                            memoryId: "mem_xt_project_\(incomingProjectId)_current_state",
                            ownerId: incomingProjectId,
                            projectId: incomingProjectId,
                            sourceKind: "current_state",
                            layer: "l3_working_set",
                            title: "Current state",
                            text: "Rust current state"
                        )
                    ]
                )
            }

            let result = await HubIPCClient.requestMemoryContextDetailed(
                useMode: .projectChat,
                requesterRole: .chat,
                projectId: projectId,
                projectRoot: projectRoot.path,
                displayName: "Rust Context Project",
                latestUser: "继续当前项目",
                constitutionHint: "safe",
                canonicalText: "local canonical fallback",
                observationsText: "local observations fallback",
                workingSetText: "local working fallback",
                rawEvidenceText: "raw",
                progressiveDisclosure: false,
                budgets: nil,
                timeoutSec: 0.1
            )

            let response = try #require(result.response)
            let rustRange = try #require(response.text.range(of: "Rust canonical goal"))
            let localRange = try #require(response.text.range(of: "local canonical fallback"))
            let remoteRange = try #require(response.text.range(of: "remote canonical stale"))
            #expect(await recorder.count() == 1)
            #expect(rustRange.lowerBound < localRange.lowerBound)
            #expect(localRange.lowerBound < remoteRange.lowerBound)
            #expect(response.text.contains("[local_projection]"))
            #expect(response.text.contains("Rust risk observation"))
            #expect(response.text.contains("Rust current state"))
            #expect(response.source == "hub_memory_v1_grpc")
        }
    }

    @Test
    func requestMemoryContextSkipsRustCanonicalObjectsWithoutSuccessfulRustSyncStatus() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_rust_context_skip_\(UUID().uuidString)", isDirectory: true)
            let projectRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub-project-memory-rust-context-skip-\(UUID().uuidString)", isDirectory: true)
            let originalMode = HubAIClient.transportMode()
            let recorder = RustProjectCanonicalMemoryFetchRecorder()

            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
            HubAIClient.setTransportMode(.auto)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubIPCClient.resetMemoryContextResolutionOverrideForTesting()
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
                try? FileManager.default.removeItem(at: projectRoot)
            }

            let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
            HubIPCClient.installHubRouteDecisionOverrideForTesting {
                HubRouteDecision(
                    mode: .auto,
                    hasRemoteProfile: true,
                    preferRemote: true,
                    allowFileFallback: true,
                    requiresRemote: false,
                    remoteUnavailableReasonCode: nil
                )
            }
            HubIPCClient.installRemoteMemorySnapshotOverrideForTesting { _, _, _, _ in
                HubRemoteMemorySnapshotResult(
                    ok: true,
                    source: "hub_memory_v1_grpc",
                    canonicalEntries: ["remote canonical"],
                    workingEntries: [],
                    reasonCode: nil,
                    logLines: []
                )
            }
            HubIPCClient.installRustProjectCanonicalMemoryOverrideForTesting { incomingProjectId, _, _ in
                await recorder.append(incomingProjectId)
                return HubIPCClient.RustProjectCanonicalMemorySnapshot(
                    source: "rust_http",
                    projectId: incomingProjectId,
                    objects: [
                        HubIPCClient.RustProjectCanonicalMemoryObject(
                            memoryId: "mem_unexpected",
                            ownerId: incomingProjectId,
                            projectId: incomingProjectId,
                            sourceKind: "project_goal",
                            layer: "l1_canonical",
                            title: "Project goal",
                            text: "unexpected Rust canonical"
                        )
                    ]
                )
            }

            let result = await HubIPCClient.requestMemoryContextDetailed(
                useMode: .projectChat,
                requesterRole: .chat,
                projectId: projectId,
                projectRoot: projectRoot.path,
                displayName: "Rust Context Skip",
                latestUser: "继续当前项目",
                constitutionHint: "safe",
                canonicalText: "local canonical",
                observationsText: "local observations",
                workingSetText: "local working",
                rawEvidenceText: "raw",
                progressiveDisclosure: false,
                budgets: nil,
                timeoutSec: 0.1
            )

            let response = try #require(result.response)
            #expect(await recorder.count() == 0)
            #expect(response.text.contains("local canonical"))
            #expect(response.text.contains("remote canonical"))
            #expect(!response.text.contains("unexpected Rust canonical"))
        }
    }

    @Test
    func diagnoseProjectCanonicalRustImportDetectsMissingStaleMismatchAndExtraObjects() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_rust_import_diag_\(UUID().uuidString)", isDirectory: true)
            let projectRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub-project-memory-rust-import-diag-\(UUID().uuidString)", isDirectory: true)
            let originalMode = HubAIClient.transportMode()

            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
            HubAIClient.setTransportMode(.auto)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubIPCClient.resetMemoryContextResolutionOverrideForTesting()
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
                try? FileManager.default.removeItem(at: projectRoot)
            }

            let ctx = AXProjectContext(root: projectRoot)
            let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
            try writeRustCanonicalSyncStatus(base: hubBase, projectId: projectId)

            var memory = AXMemory.new(
                projectName: "Rust Import Diagnostics",
                projectRoot: projectRoot.path
            )
            memory.goal = "Ship Rust memory diagnostics."
            memory.requirements = ["Need parity evidence."]
            memory.decisions = ["Prefer Rust canonical reads."]
            memory.risks = ["Drift between local and Rust."]

            HubIPCClient.installRustProjectCanonicalMemoryOverrideForTesting { incomingProjectId, limit, _ in
                #expect(incomingProjectId == projectId)
                #expect(limit == 128)
                return HubIPCClient.RustProjectCanonicalMemorySnapshot(
                    source: "rust_http",
                    projectId: incomingProjectId,
                    objects: [
                        HubIPCClient.RustProjectCanonicalMemoryObject(
                            memoryId: rustProjectMemoryId(projectId: incomingProjectId, suffix: "goal"),
                            ownerId: incomingProjectId,
                            projectId: incomingProjectId,
                            sourceKind: "project_goal",
                            layer: "l1_canonical",
                            title: "Project goal",
                            text: "Ship Rust memory diagnostics."
                        ),
                        HubIPCClient.RustProjectCanonicalMemoryObject(
                            memoryId: rustProjectMemoryId(projectId: incomingProjectId, suffix: "decisions"),
                            ownerId: incomingProjectId,
                            projectId: incomingProjectId,
                            sourceKind: "decision_track",
                            layer: "l1_canonical",
                            title: "Decisions",
                            text: "Old decision projection."
                        ),
                        HubIPCClient.RustProjectCanonicalMemoryObject(
                            memoryId: rustProjectMemoryId(projectId: incomingProjectId, suffix: "risks"),
                            ownerId: incomingProjectId,
                            projectId: incomingProjectId,
                            sourceKind: "risk",
                            layer: "l1_canonical",
                            title: "Risks",
                            text: "1. Drift between local and Rust."
                        ),
                        HubIPCClient.RustProjectCanonicalMemoryObject(
                            memoryId: rustProjectMemoryId(projectId: incomingProjectId, suffix: "next_steps"),
                            ownerId: incomingProjectId,
                            projectId: incomingProjectId,
                            sourceKind: "next_step",
                            layer: "l3_working_set",
                            title: "Next steps",
                            text: "Unexpected extra object."
                        )
                    ]
                )
            }

            let diagnostics = await HubIPCClient.diagnoseProjectCanonicalRustImport(
                ctx: ctx,
                memory: memory,
                config: nil,
                timeoutSec: 0.1
            )

            #expect(!diagnostics.ok)
            #expect(diagnostics.source == "rust_memory_objects")
            #expect(diagnostics.projectId == projectId)
            #expect(diagnostics.expectedItemCount == 4)
            #expect(diagnostics.skippedMetadataCount == 5)
            #expect(diagnostics.rustObjectCount == 4)
            #expect(diagnostics.matchedCount == 1)
            #expect(diagnostics.missingCount == 1)
            #expect(diagnostics.staleCount == 1)
            #expect(diagnostics.mismatchCount == 1)
            #expect(diagnostics.extraCount == 1)
            #expect(diagnostics.reasonCode == "rust_project_canonical_import_drift")
            #expect(Set(diagnostics.issues.map(\.reasonCode)) == Set([
                "rust_project_canonical_object_missing",
                "rust_project_canonical_object_stale",
                "rust_project_canonical_object_metadata_mismatch",
                "rust_project_canonical_object_extra"
            ]))
        }
    }

    @Test
    func diagnoseProjectCanonicalRustImportDoesNotFetchObjectsWithoutSuccessfulSyncStatus() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_rust_import_diag_no_status_\(UUID().uuidString)", isDirectory: true)
            let projectRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub-project-memory-rust-import-diag-no-status-\(UUID().uuidString)", isDirectory: true)
            let originalMode = HubAIClient.transportMode()
            let recorder = RustProjectCanonicalMemoryFetchRecorder()

            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
            HubAIClient.setTransportMode(.auto)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubIPCClient.resetMemoryContextResolutionOverrideForTesting()
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
                try? FileManager.default.removeItem(at: projectRoot)
            }

            var memory = AXMemory.new(
                projectName: "Rust Import Diagnostics Missing Status",
                projectRoot: projectRoot.path
            )
            memory.goal = "Do not hit Rust without successful status."
            HubIPCClient.installRustProjectCanonicalMemoryOverrideForTesting { incomingProjectId, _, _ in
                await recorder.append(incomingProjectId)
                return HubIPCClient.RustProjectCanonicalMemorySnapshot(
                    source: "rust_http",
                    projectId: incomingProjectId,
                    objects: []
                )
            }

            let diagnostics = await HubIPCClient.diagnoseProjectCanonicalRustImport(
                ctx: AXProjectContext(root: projectRoot),
                memory: memory,
                config: nil,
                timeoutSec: 0.1
            )

            #expect(!diagnostics.ok)
            #expect(diagnostics.source == "local_status")
            #expect(diagnostics.reasonCode == "rust_project_canonical_sync_status_missing")
            #expect(diagnostics.missingCount == 1)
            #expect(await recorder.count() == 0)
        }
    }

    @Test
    func rustMemoryGatewayShadowCompareMatchesProductContextAndRecordsStatus() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_memory_gateway_shadow_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            HubIPCClient.installRustMemoryGatewayPrepareOverrideForTesting { request, timeoutSec in
                #expect(request.requesterRole == "chat")
                #expect(request.useMode == "project_chat")
                #expect(request.scope == "project")
                #expect(request.projectId == "project-gateway")
                #expect(request.remoteExportRequested == false)
                #expect(request.requestedLayers == ["l1_canonical", "l2_observations", "l3_working_set"])
                #expect(timeoutSec == 0.1)
                return rustMemoryGatewayPrepareResult(
                    projectId: request.projectId,
                    objects: [
                        rustMemoryGatewayObject(
                            memoryId: "mem_xt_project_project-gateway_goal",
                            sourceKind: "project_goal",
                            layer: "l1_canonical",
                            title: "Project goal",
                            text: "Rust canonical goal"
                        ),
                        rustMemoryGatewayObject(
                            memoryId: "mem_xt_project_project-gateway_risks",
                            sourceKind: "risk",
                            layer: "l2_observations",
                            title: "Risks",
                            text: "Rust risk observation"
                        )
                    ]
                )
            }
            defer {
                HubIPCClient.resetRustMemoryGatewayPrepareOverrideForTesting()
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
            }

            let payload = HubIPCClient.MemoryContextPayload(
                mode: XTMemoryUseMode.projectChat.rawValue,
                projectId: "project-gateway",
                displayName: "Gateway Project",
                latestUser: "continue",
                canonicalText: "Rust canonical goal",
                observationsText: "Rust risk observation",
                workingSetText: nil,
                rawEvidenceText: nil
            )
            let product = memoryContextResponse(
                text: """
                [MEMORY_V1]
                [L1_CANONICAL]
                Rust canonical goal
                [/L1_CANONICAL]

                [L2_OBSERVATIONS]
                Rust risk observation
                [/L2_OBSERVATIONS]
                [/MEMORY_V1]
                """
            )

            let compare = await HubIPCClient.compareMemoryContextWithRustGateway(
                productResponse: product,
                requesterRole: .chat,
                useMode: .projectChat,
                payload: payload,
                timeoutSec: 0.1,
                recordStatus: true
            )

            #expect(compare.ok)
            #expect(compare.parityOk)
            #expect(compare.reasonCode == nil)
            #expect(compare.rustObjectCount == 2)
            #expect(compare.matchedRustAnchors.count == 2)
            #expect(compare.missingRustAnchors.isEmpty)
            #expect(compare.productionAuthorityChange == false)

            let statusURL = hubBase.appendingPathComponent("memory_gateway_shadow_compare_status.json")
            let data = try Data(contentsOf: statusURL)
            let decoded = try JSONDecoder().decode(HubIPCClient.RustMemoryGatewayShadowCompareResult.self, from: data)
            #expect(decoded.schemaVersion == HubIPCClient.RustMemoryGatewayShadowCompareResult.schemaVersion)
            #expect(decoded.parityOk)
            #expect(decoded.mode == "shadow_compare_no_product_cutover")
            let loadedStatus = try #require(HubIPCClient.rustMemoryGatewayShadowCompareStatus())
            #expect(loadedStatus.parityOk)
            #expect(loadedStatus.rustObjectCount == 2)
            let history = try #require(HubIPCClient.rustMemoryGatewayShadowCompareHistory())
            #expect(history.schemaVersion == HubIPCClient.RustMemoryGatewayShadowCompareHistory.schemaVersion)
            #expect(history.items.count == 1)
            #expect(history.items.first?.parityOk == true)
            let readiness = HubIPCClient.rustMemoryGatewayCutoverReadinessEvidence(
                requesterRole: "chat",
                useMode: XTMemoryUseMode.projectChat.rawValue,
                projectId: "project-gateway",
                requiredSamples: 1,
                maxAgeMs: 600_000,
                recordReport: true
            )
            #expect(readiness.readyForRequire)
            #expect(readiness.passingSampleCount == 1)
            #expect(readiness.reportPath?.hasSuffix("memory_gateway_cutover_readiness.json") == true)
            #expect(FileManager.default.fileExists(atPath: readiness.reportPath ?? ""))
        }
    }

    @Test
    func rustMemoryGatewayCutoverReadinessRequiresSustainedFreshParityHistory() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_memory_gateway_cutover_readiness_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            HubIPCClient.installRustMemoryGatewayPrepareOverrideForTesting { request, _ in
                rustMemoryGatewayPrepareResult(
                    projectId: request.projectId,
                    objects: [
                        rustMemoryGatewayObject(
                            memoryId: "mem_xt_project_project-gateway-live_goal",
                            sourceKind: "project_goal",
                            layer: "l1_canonical",
                            title: "Project goal",
                            text: "Rust live parity context"
                        )
                    ]
                )
            }
            defer {
                HubIPCClient.resetRustMemoryGatewayPrepareOverrideForTesting()
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
            }

            let payload = HubIPCClient.MemoryContextPayload(
                mode: XTMemoryUseMode.projectChat.rawValue,
                projectId: "project-gateway-live",
                displayName: "Gateway Live",
                latestUser: "continue",
                canonicalText: "Rust live parity context",
                observationsText: nil,
                workingSetText: nil,
                rawEvidenceText: nil
            )
            let product = memoryContextResponse(text: "Rust live parity context")
            for _ in 0..<3 {
                let compare = await HubIPCClient.compareMemoryContextWithRustGateway(
                    productResponse: product,
                    requesterRole: .chat,
                    useMode: .projectChat,
                    payload: payload,
                    timeoutSec: 0.1,
                    recordStatus: true
                )
                #expect(compare.parityOk)
                try? await Task.sleep(nanoseconds: 2_000_000)
            }

            let history = try #require(HubIPCClient.rustMemoryGatewayShadowCompareHistory())
            #expect(history.items.count == 3)
            let insufficient = HubIPCClient.rustMemoryGatewayCutoverReadinessEvidence(
                requesterRole: "chat",
                useMode: XTMemoryUseMode.projectChat.rawValue,
                projectId: "project-gateway-live",
                requiredSamples: 4,
                maxAgeMs: 600_000
            )
            #expect(!insufficient.readyForRequire)
            #expect(insufficient.issues.contains { $0.code == "memory_gateway_cutover_insufficient_samples" })

            let ready = HubIPCClient.rustMemoryGatewayCutoverReadinessEvidence(
                requesterRole: "chat",
                useMode: XTMemoryUseMode.projectChat.rawValue,
                projectId: "project-gateway-live",
                requiredSamples: 3,
                maxAgeMs: 600_000,
                recordReport: true
            )
            #expect(ready.readyForRequire)
            #expect(ready.requiredSampleCount == 3)
            #expect(ready.matchingSampleCount == 3)
            #expect(ready.freshMatchingSampleCount == 3)
            #expect(ready.passingSampleCount == 3)
            #expect(ready.issues.isEmpty)
            #expect(FileManager.default.fileExists(atPath: ready.reportPath ?? ""))
        }
    }

    @Test
    func rustMemoryGatewayShadowCompareReportsMissingRustAnchorsAsDrift() async throws {
        await Self.gate.run {
            HubIPCClient.installRustMemoryGatewayPrepareOverrideForTesting { request, _ in
                rustMemoryGatewayPrepareResult(
                    projectId: request.projectId,
                    objects: [
                        rustMemoryGatewayObject(
                            memoryId: "mem_xt_project_project-gateway_goal",
                            sourceKind: "project_goal",
                            layer: "l1_canonical",
                            title: "Project goal",
                            text: "Rust canonical goal"
                        )
                    ]
                )
            }
            defer {
                HubIPCClient.resetRustMemoryGatewayPrepareOverrideForTesting()
            }

            let payload = HubIPCClient.MemoryContextPayload(
                mode: XTMemoryUseMode.projectChat.rawValue,
                projectId: "project-gateway",
                displayName: "Gateway Project",
                latestUser: "continue",
                canonicalText: "local canonical only",
                observationsText: nil,
                workingSetText: nil,
                rawEvidenceText: nil
            )
            let compare = await HubIPCClient.compareMemoryContextWithRustGateway(
                productResponse: memoryContextResponse(text: "local canonical only"),
                requesterRole: .chat,
                useMode: .projectChat,
                payload: payload,
                timeoutSec: 0.1,
                recordStatus: false
            )

            #expect(compare.ok)
            #expect(!compare.parityOk)
            #expect(compare.reasonCode == "rust_memory_gateway_shadow_drift")
            #expect(compare.missingRustAnchors == ["rust canonical goal"])
        }
    }

    @Test
    func requestMemoryContextUsesRustGatewayWhenPrimaryGateIsEnabled() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_memory_gateway_primary_\(UUID().uuidString)", isDirectory: true)
            let originalMode = HubAIClient.transportMode()
            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            HubAIClient.setTransportMode(.auto)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            HubIPCClient.installHubRouteDecisionOverrideForTesting {
                HubRouteDecision(
                    mode: .auto,
                    hasRemoteProfile: true,
                    preferRemote: false,
                    allowFileFallback: true,
                    requiresRemote: false,
                    remoteUnavailableReasonCode: nil
                )
            }
            HubIPCClient.installRustMemoryGatewayPrepareOverrideForTesting { request, _ in
                #expect(request.projectId == "project-gateway-primary")
                return rustMemoryGatewayPrepareResult(
                    projectId: request.projectId,
                    objects: [
                        rustMemoryGatewayObject(
                            memoryId: "mem_xt_project_project-gateway-primary_goal",
                            sourceKind: "project_goal",
                            layer: "l1_canonical",
                            title: "Project goal",
                            text: "Rust gateway primary context"
                        )
                    ]
                )
            }
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubIPCClient.resetMemoryContextResolutionOverrideForTesting()
                HubIPCClient.resetRustMemoryGatewayPrepareOverrideForTesting()
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
            }

            let result = await withTemporaryEnvironment([
                "XHUB_RUST_MEMORY_CONTEXT_GATEWAY": "1"
            ]) {
                await HubIPCClient.requestMemoryContextDetailed(
                    useMode: .projectChat,
                    requesterRole: .chat,
                    projectId: "project-gateway-primary",
                    projectRoot: nil,
                    displayName: "Gateway Primary",
                    latestUser: "continue",
                    constitutionHint: "safe",
                    canonicalText: "swift canonical fallback",
                    observationsText: nil,
                    workingSetText: nil,
                    rawEvidenceText: nil,
                    progressiveDisclosure: false,
                    budgets: nil,
                    timeoutSec: 0.1
                )
            }

            let response = try #require(result.response)
            #expect(response.source == "rust_memory_gateway_prepare")
            #expect(response.freshness == "fresh_rust_gateway")
            #expect(response.text.contains("Rust gateway primary context"))
            #expect(!response.text.contains("swift canonical fallback"))
            #expect(result.reasonCode == nil)
        }
    }

    @Test
    func requestMemoryContextRequireGateFailsClosedWithoutFreshParityEvidence() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_memory_gateway_required_missing_\(UUID().uuidString)", isDirectory: true)
            let originalMode = HubAIClient.transportMode()
            let recorder = RustMemoryGatewayPrepareRecorder()
            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            HubAIClient.setTransportMode(.auto)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            HubIPCClient.installHubRouteDecisionOverrideForTesting {
                HubRouteDecision(
                    mode: .auto,
                    hasRemoteProfile: true,
                    preferRemote: false,
                    allowFileFallback: true,
                    requiresRemote: false,
                    remoteUnavailableReasonCode: nil
                )
            }
            HubIPCClient.installRustMemoryGatewayPrepareOverrideForTesting { request, _ in
                await recorder.append(request)
                return nil
            }
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubIPCClient.installHubRouteDecisionOverrideForTesting(nil)
                HubIPCClient.resetRustMemoryGatewayPrepareOverrideForTesting()
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
            }

            let result = await withTemporaryEnvironment([
                "XHUB_RUST_MEMORY_CONTEXT_GATEWAY": nil,
                "XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE": "1",
                "XHUB_RUST_MEMORY_CONTEXT_GATEWAY_PARITY_MAX_AGE_MS": "600000"
            ]) {
                await HubIPCClient.requestMemoryContextDetailed(
                    useMode: .projectChat,
                    requesterRole: .chat,
                    projectId: "project-gateway-required",
                    projectRoot: nil,
                    displayName: "Gateway Required",
                    latestUser: "continue",
                    constitutionHint: "safe",
                    canonicalText: "swift canonical fallback",
                    observationsText: nil,
                    workingSetText: nil,
                    rawEvidenceText: nil,
                    progressiveDisclosure: false,
                    budgets: nil,
                    timeoutSec: 0.1
                )
            }

            #expect(result.response == nil)
            #expect(result.source == "rust_memory_gateway_cutover_gate")
            #expect(result.reasonCode == "memory_gateway_cutover_evidence_missing")
            #expect(HubIPCClient.isRustMemoryGatewayRequiredFailure(result))
            #expect(await recorder.count() == 0)
        }
    }

    @Test
    func requestMemoryContextRequireGateUsesRustGatewayWithFreshParityEvidence() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_memory_gateway_required_ready_\(UUID().uuidString)", isDirectory: true)
            let originalMode = HubAIClient.transportMode()
            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            HubAIClient.setTransportMode(.auto)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            HubIPCClient.installHubRouteDecisionOverrideForTesting {
                HubRouteDecision(
                    mode: .auto,
                    hasRemoteProfile: true,
                    preferRemote: false,
                    allowFileFallback: true,
                    requiresRemote: false,
                    remoteUnavailableReasonCode: nil
                )
            }
            try writeRustMemoryGatewayShadowCompareStatus(
                base: hubBase,
                requesterRole: "chat",
                useMode: XTMemoryUseMode.projectChat.rawValue,
                projectId: "project-gateway-required",
                recordedAtMs: Int64(Date().timeIntervalSince1970 * 1000.0)
            )
            HubIPCClient.installRustMemoryGatewayPrepareOverrideForTesting { request, _ in
                #expect(request.projectId == "project-gateway-required")
                return rustMemoryGatewayPrepareResult(
                    projectId: request.projectId,
                    objects: [
                        rustMemoryGatewayObject(
                            memoryId: "mem_xt_project_project-gateway-required_goal",
                            sourceKind: "project_goal",
                            layer: "l1_canonical",
                            title: "Project goal",
                            text: "Rust gateway required context"
                        )
                    ]
                )
            }
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubIPCClient.installHubRouteDecisionOverrideForTesting(nil)
                HubIPCClient.resetRustMemoryGatewayPrepareOverrideForTesting()
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
            }

            let result = await withTemporaryEnvironment([
                "XHUB_RUST_MEMORY_CONTEXT_GATEWAY": nil,
                "XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE": "1",
                "XHUB_RUST_MEMORY_CONTEXT_GATEWAY_PARITY_MAX_AGE_MS": "600000"
            ]) {
                await HubIPCClient.requestMemoryContextDetailed(
                    useMode: .projectChat,
                    requesterRole: .chat,
                    projectId: "project-gateway-required",
                    projectRoot: nil,
                    displayName: "Gateway Required",
                    latestUser: "continue",
                    constitutionHint: "safe",
                    canonicalText: "swift canonical fallback",
                    observationsText: nil,
                    workingSetText: nil,
                    rawEvidenceText: nil,
                    progressiveDisclosure: false,
                    budgets: nil,
                    timeoutSec: 0.1
                )
            }

            let response = try #require(result.response)
            #expect(response.source == "rust_memory_gateway_prepare")
            #expect(response.memoryGatewaySafetyMode == "fail_closed_required_after_shadow_parity")
            #expect(response.memoryGatewayProductionAuthorityChange == false)
            #expect(response.text.contains("Rust gateway required context"))
            #expect(!response.text.contains("swift canonical fallback"))
            #expect(result.reasonCode == nil)
        }
    }

    @Test
    func syncSupervisorProjectHeartbeatWritesCanonicalHeartbeatProjection() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_heartbeat_sync_\(UUID().uuidString)", isDirectory: true)
            let originalMode = HubAIClient.transportMode()

            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            try writeTestHubStatus(base: hubBase)

            HubAIClient.setTransportMode(.fileIPC)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
            }

            let cadence = SupervisorCadenceExplainability(
                progressHeartbeat: SupervisorCadenceDimensionExplainability(
                    dimension: .progressHeartbeat,
                    configuredSeconds: 300,
                    recommendedSeconds: 300,
                    effectiveSeconds: 300,
                    effectiveReasonCodes: ["configured"],
                    nextDueAtMs: 1_778_830_420_000,
                    nextDueReasonCodes: ["heartbeat_active"],
                    isDue: false
                ),
                reviewPulse: SupervisorCadenceDimensionExplainability(
                    dimension: .reviewPulse,
                    configuredSeconds: 900,
                    recommendedSeconds: 900,
                    effectiveSeconds: 900,
                    effectiveReasonCodes: ["configured"],
                    nextDueAtMs: 1_778_830_300_000,
                    nextDueReasonCodes: ["pulse_pending"],
                    isDue: true
                ),
                brainstormReview: SupervisorCadenceDimensionExplainability(
                    dimension: .brainstormReview,
                    configuredSeconds: 1800,
                    recommendedSeconds: 1800,
                    effectiveSeconds: 1800,
                    effectiveReasonCodes: ["configured"],
                    nextDueAtMs: 1_778_830_900_000,
                    nextDueReasonCodes: ["brainstorm_waiting_progress_window"],
                    isDue: false
                ),
                eventFollowUpCooldownSeconds: 120
            )
            let snapshot = XTProjectHeartbeatGovernanceDoctorSnapshot(
                projectId: "project-heartbeat",
                projectName: "Heartbeat Project",
                statusDigest: "verify blocked on route repair",
                currentStateSummary: "Route health regressed during verify",
                nextStepSummary: "Repair route and retry smoke suite",
                blockerSummary: "route instability",
                lastHeartbeatAtMs: 1_778_830_120_000,
                latestQualityBand: .weak,
                latestQualityScore: 39,
                weakReasons: ["hollow_progress"],
                openAnomalyTypes: [.routeFlaky, .queueStall],
                projectPhase: .verify,
                executionStatus: .blocked,
                riskTier: .high,
                cadence: cadence,
                digestExplainability: XTHeartbeatDigestExplainability(
                    visibility: .shown,
                    reasonCodes: ["open_anomalies_present", "recovery_decision_active"],
                    whatChangedText: "验证阶段再次停在 route 健康问题。",
                    whyImportantText: "继续空转会让验证结果失真。",
                    systemNextStepText: "系统会先修复 route / dispatch 健康，再尝试恢复执行。"
                ),
                recoveryDecision: HeartbeatRecoveryDecision(
                    action: .repairRoute,
                    urgency: .urgent,
                    reasonCode: "route_health_regressed",
                    summary: "Repair route before the next verify retry.",
                    sourceSignals: ["route_flaky", "queue_stall"],
                    anomalyTypes: [.routeFlaky, .queueStall],
                    blockedLaneReasons: [.runtimeError],
                    blockedLaneCount: 1,
                    stalledLaneCount: 1,
                    failedLaneCount: 0,
                    recoveringLaneCount: 0,
                    requiresUserAction: false
                ),
                projectMemoryReadiness: nil
            )
            let record = SupervisorProjectHeartbeatCanonicalSync.record(
                snapshot: snapshot,
                generatedAtMs: 1_778_830_130_000
            )

            HubIPCClient.syncSupervisorProjectHeartbeat(record)

            let eventDir = hubBase.appendingPathComponent("ipc_events", isDirectory: true)
            let files = try FileManager.default.contentsOfDirectory(at: eventDir, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("xterminal_project_memory_") }
            #expect(files.count == 1)

            let data = try Data(contentsOf: files[0])
            let decoded = try JSONDecoder().decode(HubIPCClient.ProjectCanonicalMemoryIPCRequest.self, from: data)
            let payload = decoded.projectCanonicalMemory
            let lookup: [String: String] = Dictionary(uniqueKeysWithValues: payload.items.map { ($0.key, $0.value) })

            #expect(payload.projectId == "project-heartbeat")
            #expect(payload.displayName == "Heartbeat Project")
            #expect(lookup["xterminal.project.heartbeat.latest_quality_band"] == "weak")
            #expect(lookup["xterminal.project.heartbeat.next_review_kind"] == "review_pulse")
            #expect(lookup["xterminal.project.heartbeat.digest_visibility"] == "shown")
            #expect(lookup["xterminal.project.heartbeat.recovery_action"] == "repair_route")
        }
    }

    private func writeTestHubStatus(base: URL) throws {
        let ipcDir = base.appendingPathComponent("ipc_events", isDirectory: true)
        try FileManager.default.createDirectory(at: ipcDir, withIntermediateDirectories: true)
        let status = HubStatus(
            pid: nil,
            startedAt: Date().timeIntervalSince1970,
            updatedAt: Date().timeIntervalSince1970,
            ipcMode: "file",
            ipcPath: ipcDir.path,
            baseDir: base.path,
            protocolVersion: 1,
            aiReady: true,
            loadedModelCount: 0,
            modelsUpdatedAt: Date().timeIntervalSince1970
        )
        let data = try JSONEncoder().encode(status)
        try data.write(to: base.appendingPathComponent("hub_status.json"), options: .atomic)
    }

    private func writeRustCanonicalSyncStatus(base: URL, projectId: String) throws {
        let snapshot = HubIPCClient.CanonicalMemorySyncStatusSnapshot(
            schemaVersion: "canonical_memory_sync_status.v1",
            updatedAtMs: 1_778_000_000_000,
            items: [
                HubIPCClient.CanonicalMemorySyncStatusItem(
                    scopeKind: "project",
                    scopeId: projectId,
                    displayName: "Rust Context Project",
                    source: "rust_http",
                    ok: true,
                    updatedAtMs: 1_778_000_000_000,
                    deliveryState: "delivered_rust_memory_objects"
                )
            ]
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: base.appendingPathComponent("canonical_memory_sync_status.json"), options: .atomic)
    }

    private func installScopedProjectMemoryWriteFailureOverride(base: URL) {
        let scopedBasePath = base.path
        HubIPCClient.installIPCEventWriteOverrideForTesting { data, tmpURL, finalURL in
            if finalURL.path.hasPrefix(scopedBasePath),
               finalURL.lastPathComponent.hasPrefix("xterminal_project_memory_") {
                throw NSError(domain: NSPOSIXErrorDomain, code: 28)
            }
            try data.write(to: tmpURL, options: .atomic)
            try FileManager.default.moveItem(at: tmpURL, to: finalURL)
        }
    }

    private func waitForCanonicalSyncItem(
        scopeId: String,
        timeoutMs: UInt64 = 2_000,
        pollMs: UInt64 = 25
    ) async -> HubIPCClient.CanonicalMemorySyncStatusItem? {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1_000.0)
        while Date() < deadline {
            if let item = HubIPCClient.canonicalMemorySyncStatusSnapshot(limit: 10)?.items.first(where: {
                $0.scopeKind == "project" && $0.scopeId == scopeId
            }) {
                return item
            }
            try? await Task.sleep(nanoseconds: pollMs * 1_000_000)
        }
        return HubIPCClient.canonicalMemorySyncStatusSnapshot(limit: 10)?.items.first {
            $0.scopeKind == "project" && $0.scopeId == scopeId
        }
    }

    private func pendingProjectCanonicalRustSyncURL(projectRoot: URL) -> URL {
        projectRoot
            .appendingPathComponent(".xterminal", isDirectory: true)
            .appendingPathComponent("memory_lifecycle", isDirectory: true)
            .appendingPathComponent("pending_project_canonical_rust_sync.json")
    }

    private func rustProjectMemoryId(projectId: String, suffix: String) -> String {
        "mem_xt_project_\(rustMemoryIdSegment(projectId, maxChars: 80))_\(rustMemoryIdSegment(suffix, maxChars: 64))"
    }

    private func rustMemoryIdSegment(_ raw: String, maxChars: Int) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(max(0, maxChars))
            .map { character -> Character in
                if character.isASCII,
                   character.isLetter || character.isNumber || character == "_" || character == "-" || character == "." {
                    return Character(character.lowercased())
                }
                return "_"
            }
        let normalized = String(value).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return normalized.isEmpty ? "unknown" : normalized
    }

    private func memoryContextResponse(text: String) -> HubIPCClient.MemoryContextResponsePayload {
        HubIPCClient.MemoryContextResponsePayload(
            text: text,
            source: "swift_memory_v1_builder",
            resolvedMode: XTMemoryUseMode.projectChat.rawValue,
            budgetTotalTokens: 1_000,
            usedTotalTokens: 100,
            layerUsage: [],
            truncatedLayers: [],
            redactedItems: 0,
            privateDrops: 0
        )
    }

    private func writeRustMemoryGatewayShadowCompareStatus(
        base: URL,
        requesterRole: String,
        useMode: String,
        projectId: String?,
        recordedAtMs: Int64
    ) throws {
        let result = HubIPCClient.RustMemoryGatewayShadowCompareResult(
            ok: true,
            parityOk: true,
            source: "rust_memory_gateway_shadow_compare",
            mode: "shadow_compare_no_product_cutover",
            productionAuthorityChange: false,
            requesterRole: requesterRole,
            useMode: useMode,
            projectId: projectId,
            productSource: "swift_memory_v1_builder",
            rustSource: "rust_memory_gateway_prepare",
            productTextChars: 128,
            rustContextChars: 128,
            productTextHash: "product",
            rustContextHash: "rust",
            rustObjectCount: 1,
            rustEffectiveLayers: ["l1_canonical"],
            matchedRustAnchors: ["rust gateway required context"],
            missingRustAnchors: [],
            rustDenyCode: nil,
            reasonCode: nil,
            detail: nil,
            recordedAtMs: recordedAtMs
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = base.appendingPathComponent("memory_gateway_shadow_compare_status.json")
        try encoder.encode(result).write(to: url, options: .atomic)
    }

    private func rustMemoryGatewayObject(
        memoryId: String,
        sourceKind: String,
        layer: String,
        title: String,
        text: String
    ) -> HubIPCClient.RustMemoryGatewayPrepareObject {
        HubIPCClient.RustMemoryGatewayPrepareObject(
            memoryId: memoryId,
            scope: "project",
            ownerId: "project-gateway",
            projectId: "project-gateway",
            agentId: nil,
            sourceKind: sourceKind,
            layer: layer,
            title: title,
            text: text,
            summary: text,
            sensitivity: "internal",
            visibility: "local_only",
            updatedAtMs: 1_778_000_000_000,
            version: 1
        )
    }

    private func rustMemoryGatewayPrepareResult(
        projectId: String?,
        objects: [HubIPCClient.RustMemoryGatewayPrepareObject]
    ) -> HubIPCClient.RustMemoryGatewayPrepareResult {
        let grouped = Dictionary(grouping: objects, by: \.layer)
        let slots = grouped.keys.sorted().map { layer in
            HubIPCClient.RustMemoryGatewayPrepareSlot(
                layer: layer,
                count: grouped[layer]?.count ?? 0,
                objects: grouped[layer] ?? []
            )
        }
        let context = slots.map { slot in
            let lines = slot.objects.map { "- [\($0.sourceKind)] \($0.title): \($0.text)" }
            return "## \(slot.layer)\n\(lines.joined(separator: "\n"))"
        }.joined(separator: "\n")
        return HubIPCClient.RustMemoryGatewayPrepareResult(
            schemaVersion: "xhub.memory.gateway_prepare.v1",
            ok: true,
            status: "prepared",
            source: "rust_memory_gateway_prepare",
            mode: "prepare_only_no_model_call",
            productionAuthorityChange: false,
            requesterRole: "chat",
            useMode: "project_chat",
            scope: "project",
            projectId: projectId,
            remoteExportRequested: false,
            queryPresent: true,
            objectCount: objects.count,
            maxItems: 24,
            maxSnippetChars: 420,
            requestedLayers: ["l1_canonical", "l2_observations", "l3_working_set"],
            effectiveLayers: slots.map(\.layer),
            requestedSourceKinds: [],
            slots: slots,
            contextText: context,
            skipped: HubIPCClient.RustMemoryGatewayPrepareSkipped(
                policyOrFilter: 0,
                remoteVisibility: 0,
                secret: 0
            ),
            denyCode: nil,
            reasonCode: nil,
            errorCode: nil,
            message: nil
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
