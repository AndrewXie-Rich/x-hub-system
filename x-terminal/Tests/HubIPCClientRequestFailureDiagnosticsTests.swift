import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct HubIPCClientRequestFailureDiagnosticsTests {
    @Test
    func memoryContextDetailedReportsLocalIPCWriteFailureReason() async throws {
        let base = try makeTempDirectory("hub_ipc_memctx_failure")
        try writeTestHubStatus(base: base)
        HubPaths.setPinnedBaseDirOverride(base)
        HubIPCClient.installHubRouteDecisionOverrideForTesting { localOnlyRouteDecision() }
        installScopedIPCWriteFailureOverride(base: base)
        defer {
            HubIPCClient.resetMemoryContextResolutionOverrideForTesting()
            HubIPCClient.resetIPCEventWriteOverrideForTesting()
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: base)
        }

        let result = await HubIPCClient.requestMemoryContextDetailed(
            useMode: .projectChat,
            requesterRole: .chat,
            projectId: "proj-local-write-fail",
            projectRoot: "/tmp/proj-local-write-fail",
            displayName: "proj-local-write-fail",
            latestUser: "给我这个项目的完整背景",
            constitutionHint: "safe",
            canonicalText: "canonical memory",
            observationsText: "recent observations",
            workingSetText: "working set",
            rawEvidenceText: "raw evidence",
            timeoutSec: 0.1
        )

        #expect(result.response == nil)
        #expect(result.reasonCode == "memory_context_write_failed")
        #expect(result.detail?.contains("xterminal_mem_write_failed") == true)
    }

    @Test
    func projectMemoryRetrievalReturnsErrorPayloadWhenLocalIPCWriteFails() async throws {
        let base = try makeTempDirectory("hub_ipc_memretrieval_failure")
        try writeTestHubStatus(base: base)
        HubPaths.setPinnedBaseDirOverride(base)
        HubIPCClient.installHubRouteDecisionOverrideForTesting { localOnlyRouteDecision() }
        installScopedIPCWriteFailureOverride(base: base)
        defer {
            HubIPCClient.resetMemoryContextResolutionOverrideForTesting()
            HubIPCClient.resetIPCEventWriteOverrideForTesting()
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: base)
        }

        let response = await HubIPCClient.requestProjectMemoryRetrieval(
            requesterRole: .chat,
            useMode: .projectChat,
            projectId: "proj-retrieval-write-fail",
            projectRoot: "/tmp/proj-retrieval-write-fail",
            displayName: "proj-retrieval-write-fail",
            latestUser: "把最近 blocker 的证据拿给我",
            reason: "project_chat_progressive_disclosure_seed",
            requestedKinds: ["blocker_lineage"],
            explicitRefs: [],
            maxSnippets: 2,
            maxSnippetChars: 240,
            timeoutSec: 0.1
        )

        let normalized = try #require(response)
        #expect(normalized.status == "error")
        #expect(normalized.reasonCode == "memory_retrieval_write_failed")
        #expect(normalized.detail?.contains("xterminal_mem_retrieval_write_failed") == true)
        #expect(normalized.results?.isEmpty != false)
    }

    @Test
    func fetchVoiceWakeProfileIncludesDetailedWriteFailureLog() async throws {
        let base = try makeTempDirectory("hub_ipc_voicewake_get_failure")
        try writeTestHubStatus(base: base)
        HubPaths.setPinnedBaseDirOverride(base)
        HubIPCClient.installHubRouteDecisionOverrideForTesting { localOnlyRouteDecision() }
        installScopedIPCWriteFailureOverride(base: base)
        defer {
            HubIPCClient.resetMemoryContextResolutionOverrideForTesting()
            HubIPCClient.resetIPCEventWriteOverrideForTesting()
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: base)
        }

        let result = await HubIPCClient.fetchVoiceWakeProfile(desiredWakeMode: .wakePhrase)
        #expect(result.ok == false)
        #expect(result.reasonCode == "voice_wake_profile_write_failed")
        #expect(result.logLines.contains(where: { $0.contains("voice wake profile get request write failed:") }))
        #expect(result.logLines.contains(where: { $0.contains("xterminal_voicewake_get_write_failed") }))
    }

    @Test
    func setVoiceWakeProfileIncludesDetailedWriteFailureLog() async throws {
        let base = try makeTempDirectory("hub_ipc_voicewake_set_failure")
        try writeTestHubStatus(base: base)
        HubPaths.setPinnedBaseDirOverride(base)
        HubIPCClient.installHubRouteDecisionOverrideForTesting { localOnlyRouteDecision() }
        installScopedIPCWriteFailureOverride(base: base)
        defer {
            HubIPCClient.resetMemoryContextResolutionOverrideForTesting()
            HubIPCClient.resetIPCEventWriteOverrideForTesting()
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: base)
        }

        let profile = VoiceWakeProfile.migratedLocalOverride(wakeMode: .wakePhrase)
        let result = await HubIPCClient.setVoiceWakeProfile(profile)
        #expect(result.ok == false)
        #expect(result.reasonCode == "voice_wake_profile_write_failed")
        #expect(result.logLines.contains(where: { $0.contains("voice wake profile set request write failed:") }))
        #expect(result.logLines.contains(where: { $0.contains("xterminal_voicewake_set_write_failed") }))
    }

    @Test
    func networkAccessReturnsDetailedWriteFailure() async throws {
        let base = try makeTempDirectory("hub_ipc_need_network_failure")
        let projectRoot = try makeTempDirectory("hub_ipc_need_network_project")
        try writeTestHubStatus(base: base)
        HubPaths.setPinnedBaseDirOverride(base)
        HubIPCClient.installHubRouteDecisionOverrideForTesting { localOnlyRouteDecision() }
        installScopedIPCWriteFailureOverride(base: base)
        defer {
            HubIPCClient.resetMemoryContextResolutionOverrideForTesting()
            HubIPCClient.resetIPCEventWriteOverrideForTesting()
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: base)
            try? FileManager.default.removeItem(at: projectRoot)
        }

        let result = await HubIPCClient.requestNetworkAccess(
            root: projectRoot,
            seconds: 900,
            reason: "network research"
        )

        #expect(result.state == .failed)
        #expect(result.reasonCode == "network_request_write_failed")
        #expect(result.detail?.contains("xterminal_net_write_failed") == true)
    }

    @Test
    func secretVaultBeginUseReturnsDetailedWriteFailure() async throws {
        let base = try makeTempDirectory("hub_ipc_secret_use_failure")
        try writeTestHubStatus(base: base)
        HubPaths.setPinnedBaseDirOverride(base)
        HubIPCClient.installHubRouteDecisionOverrideForTesting { localOnlyRouteDecision() }
        installScopedIPCWriteFailureOverride(base: base)
        defer {
            HubIPCClient.resetMemoryContextResolutionOverrideForTesting()
            HubIPCClient.resetIPCEventWriteOverrideForTesting()
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: base)
        }

        let result = await HubIPCClient.beginSecretUse(
            HubIPCClient.SecretUseRequestPayload(
                itemId: "sv_login",
                scope: "project",
                name: nil,
                projectId: "proj-secret-write-fail",
                purpose: "browser_secret_fill",
                target: "https://example.com/login",
                ttlMs: 60_000
            )
        )

        #expect(result.ok == false)
        #expect(result.reasonCode == "secret_vault_use_write_failed")
        #expect(result.detail?.contains("xterminal_secret_vault_use_write_failed") == true)
    }

    private func makeTempDirectory(_ suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_\(suffix)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeTestHubStatus(base: URL) throws {
        let ipcDir = base.appendingPathComponent("ipc_events", isDirectory: true)
        try FileManager.default.createDirectory(at: ipcDir, withIntermediateDirectories: true)
        let now = Date().timeIntervalSince1970
        let status = HubStatus(
            pid: nil,
            startedAt: now,
            updatedAt: now,
            ipcMode: "file",
            ipcPath: ipcDir.path,
            baseDir: base.path,
            protocolVersion: 1,
            aiReady: true,
            loadedModelCount: 0,
            modelsUpdatedAt: now
        )
        let data = try JSONEncoder().encode(status)
        try data.write(to: base.appendingPathComponent("hub_status.json"), options: .atomic)
    }

    private func installScopedIPCWriteFailureOverride(base: URL) {
        let scopedBasePath = base.path
        HubIPCClient.installIPCEventWriteOverrideForTesting { data, tmpURL, finalURL in
            if finalURL.path.hasPrefix(scopedBasePath) {
                throw NSError(domain: NSPOSIXErrorDomain, code: 28)
            }
            try data.write(to: tmpURL, options: .atomic)
            try FileManager.default.moveItem(at: tmpURL, to: finalURL)
        }
    }

    private func localOnlyRouteDecision() -> HubRouteDecision {
        HubRouteDecision(
            mode: .fileIPC,
            hasRemoteProfile: false,
            preferRemote: false,
            allowFileFallback: true,
            requiresRemote: false,
            remoteUnavailableReasonCode: nil
        )
    }
}
