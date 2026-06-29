import Foundation
import Darwin

enum HubIPCClient {
    private enum RuntimeSurfaceOverrideCompatContract {
        static let snapshotFilename = "autonomy_policy_overrides_status.json"
        static let fileSource = "hub_autonomy_policy_overrides_file"
    }

    private static let remoteRuntimeSurfaceOverrideCacheTTLSeconds: TimeInterval = 20.0
    private static var remoteRuntimeSurfaceOverrideCache = HubRemoteRuntimeSurfaceOverrideCache(
        ttlSeconds: remoteRuntimeSurfaceOverrideCacheTTLSeconds
    )
    private static let testingOverrideLock = NSLock()
    private static let runtimeSurfaceFetchLock = NSLock()
    private static var inFlightRuntimeSurfaceOverrideFetches: [HubRemoteRuntimeSurfaceOverrideCache.Key: Task<RuntimeSurfaceOverridesSnapshot?, Never>] = [:]
    private struct TestingOverrideScopeKey: Hashable {
        let task: UnsafeCurrentTask
    }
    private static var agentImportStageOverrideForTesting: (@Sendable (AgentImportStageRequestPayload) async -> AgentImportStageResult)?
    private static var agentImportRecordOverrideForTesting: (@Sendable (AgentImportRecordLookupPayload) async -> AgentImportRecordResult)?
    private static var skillPackageUploadOverrideForTesting: (@Sendable (SkillPackageUploadRequestPayload) async -> SkillPackageUploadResult)?
    private static var agentImportPromoteOverrideForTesting: (@Sendable (AgentImportPromoteRequestPayload) async -> AgentImportPromoteResult)?
    private static var skillPinOverrideForTesting: (@Sendable (SkillPinRequestPayload) async -> SkillPinResult)?
    private static var scopedSkillPinOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (SkillPinRequestPayload) async -> SkillPinResult)] = [:]
    private static var resolvedSkillsOverrideForTesting: (@Sendable (String?) async -> ResolvedSkillsResult)?
    private static var scopedResolvedSkillsOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (String?) async -> ResolvedSkillsResult)] = [:]
    private static var skillManifestOverrideForTesting: (@Sendable (String) async -> SkillManifestResult)?
    private static var scopedSkillManifestOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (String) async -> SkillManifestResult)] = [:]
    private static var skillPackageDownloadOverrideForTesting: (@Sendable (String) async -> SkillPackageDownloadResult)?
    private static var scopedSkillPackageDownloadOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (String) async -> SkillPackageDownloadResult)] = [:]
    private static var skillRunnerGateOverrideForTesting: (@Sendable (SkillRunnerGateRequestPayload) async -> SkillRunnerGateResult)?
    private static var scopedSkillRunnerGateOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (SkillRunnerGateRequestPayload) async -> SkillRunnerGateResult)] = [:]
    private static var secretUseOverrideForTesting: (@Sendable (SecretUseRequestPayload) async -> SecretUseResult)?
    private static var secretRedeemOverrideForTesting: (@Sendable (SecretRedeemRequestPayload) async -> SecretRedeemResult)?
    private static var localTaskExecutionOverrideForTesting: (@Sendable (LocalTaskRequestPayload, Double) -> LocalTaskResult)?
    private static var routeDecisionOverrideForTesting: (@Sendable () async -> HubRouteDecision)?
    private static var scopedRouteDecisionOverridesForTesting: [TestingOverrideScopeKey: (@Sendable () async -> HubRouteDecision)] = [:]
    private static var memoryContextResolutionOverrideForTesting: (@Sendable (XTMemoryRouteDecision, XTMemoryUseMode, Double) async -> MemoryContextResolutionResult)?
    private static var scopedMemoryContextResolutionOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (XTMemoryRouteDecision, XTMemoryUseMode, Double) async -> MemoryContextResolutionResult)] = [:]
    private static var memoryRetrievalOverrideForTesting: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)?
    private static var scopedMemoryRetrievalOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)] = [:]
    private static var localMemoryRetrievalIPCOverrideForTesting: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)?
    private static var scopedLocalMemoryRetrievalIPCOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)] = [:]
    private static var remoteMemorySnapshotOverrideForTesting: (@Sendable (XTMemoryUseMode, String?, Bool, Double) async -> HubRemoteMemorySnapshotResult)?
    private static var scopedRemoteMemorySnapshotOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (XTMemoryUseMode, String?, Bool, Double) async -> HubRemoteMemorySnapshotResult)] = [:]
    private static var voiceGrantChallengeOverrideForTesting: (@Sendable (VoiceGrantChallengeRequestPayload) async -> VoiceGrantChallengeResult)?
    private static var scopedVoiceGrantChallengeOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (VoiceGrantChallengeRequestPayload) async -> VoiceGrantChallengeResult)] = [:]
    private static var voiceGrantVerificationOverrideForTesting: (@Sendable (VoiceGrantVerificationPayload) async -> VoiceGrantVerificationResult)?
    private static var scopedVoiceGrantVerificationOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (VoiceGrantVerificationPayload) async -> VoiceGrantVerificationResult)] = [:]
    private static var remoteMemoryRetrievalOverrideForTesting: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)?
    private static var scopedRemoteMemoryRetrievalOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)] = [:]
    private static var remoteRuntimeSurfaceOverridesOverrideForTesting: (@Sendable (String?, Int, Double) async -> HubRemoteRuntimeSurfaceOverridesResult)?
    private static var scopedRemoteRuntimeSurfaceOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (String?, Int, Double) async -> HubRemoteRuntimeSurfaceOverridesResult)] = [:]
    private static var projectCanonicalRustSyncOverrideForTesting: (@Sendable (ProjectCanonicalMemoryPayload) async -> ProjectCanonicalMemoryRustSyncOverrideResult?)?
    private static var scopedProjectCanonicalRustSyncOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (ProjectCanonicalMemoryPayload) async -> ProjectCanonicalMemoryRustSyncOverrideResult?)] = [:]
    private static var rustProjectCanonicalMemoryOverrideForTesting: (@Sendable (String, Int, Double) async -> RustProjectCanonicalMemorySnapshot?)?
    private static var scopedRustProjectCanonicalMemoryOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (String, Int, Double) async -> RustProjectCanonicalMemorySnapshot?)] = [:]
    private static var rustMemoryGatewayPrepareOverrideForTesting: (@Sendable (RustMemoryGatewayPrepareRequest, Double) async -> RustMemoryGatewayPrepareResult?)?
    private static var scopedRustMemoryGatewayPrepareOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (RustMemoryGatewayPrepareRequest, Double) async -> RustMemoryGatewayPrepareResult?)] = [:]
    private static var rustMemoryGatewayModelCallPlanOverrideForTesting: (@Sendable (RustMemoryGatewayModelCallPlanRequest, Double) async -> RustMemoryGatewayModelCallPlanResult?)?
    private static var scopedRustMemoryGatewayModelCallPlanOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (RustMemoryGatewayModelCallPlanRequest, Double) async -> RustMemoryGatewayModelCallPlanResult?)] = [:]
    private static var memoryWritebackCandidateExtractOverrideForTesting: (@Sendable (MemoryWritebackCandidateExtractPayload, Double) async -> MemoryWritebackCandidateExtractResult)?
    private static var scopedMemoryWritebackCandidateExtractOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (MemoryWritebackCandidateExtractPayload, Double) async -> MemoryWritebackCandidateExtractResult)] = [:]
    private static var memoryWritebackCandidateListOverrideForTesting: (@Sendable (String?, Int, Double) async -> MemoryWritebackCandidateListResult)?
    private static var scopedMemoryWritebackCandidateListOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (String?, Int, Double) async -> MemoryWritebackCandidateListResult)] = [:]
    private static var memoryObjectListOverrideForTesting: (@Sendable (MemoryObjectListFilter, Double) async -> MemoryObjectListResult)?
    private static var scopedMemoryObjectListOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (MemoryObjectListFilter, Double) async -> MemoryObjectListResult)] = [:]
    private static var memoryUserRevealGrantOverrideForTesting: (@Sendable (MemoryUserRevealGrantRequest, Double) async -> MemoryUserRevealGrantResult)?
    private static var scopedMemoryUserRevealGrantOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (MemoryUserRevealGrantRequest, Double) async -> MemoryUserRevealGrantResult)] = [:]
    private static var memoryObjectHistoryOverrideForTesting: (@Sendable (String, Int, Double) async -> MemoryObjectHistoryResult)?
    private static var scopedMemoryObjectHistoryOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (String, Int, Double) async -> MemoryObjectHistoryResult)] = [:]
    private static var memoryWritebackCandidateDecisionOverrideForTesting: (@Sendable (String, String, MemoryWritebackCandidateDecisionPayload, Double) async -> MemoryWritebackCandidateDecisionResult)?
    private static var scopedMemoryWritebackCandidateDecisionOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (String, String, MemoryWritebackCandidateDecisionPayload, Double) async -> MemoryWritebackCandidateDecisionResult)] = [:]
    private static var memoryWritebackCandidateMaintenanceOverrideForTesting: (@Sendable (MemoryWritebackCandidateMaintenancePayload, Double) async -> MemoryWritebackCandidateMaintenanceResult)?
    private static var scopedMemoryWritebackCandidateMaintenanceOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (MemoryWritebackCandidateMaintenancePayload, Double) async -> MemoryWritebackCandidateMaintenanceResult)] = [:]
    private static var memoryObjectGetOverrideForTesting: (@Sendable (String, Double) async -> MemoryObjectResult)?
    private static var scopedMemoryObjectGetOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (String, Double) async -> MemoryObjectResult)] = [:]
    private static var memoryObjectMutationOverrideForTesting: (@Sendable (String, String, MemoryObjectMutationPayload, Double) async -> MemoryObjectMutationResult)?
    private static var scopedMemoryObjectMutationOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (String, String, MemoryObjectMutationPayload, Double) async -> MemoryObjectMutationResult)] = [:]
    private static var supervisorRemoteContinuityOverrideForTesting: (@Sendable (Bool) async -> SupervisorRemoteContinuityResult)?
    private static var scopedSupervisorRemoteContinuityOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (Bool) async -> SupervisorRemoteContinuityResult)] = [:]
    private static var supervisorConversationAppendOverrideForTesting: (@Sendable (HubRemoteSupervisorConversationPayload) async -> Bool)?
    private static var scopedSupervisorConversationAppendOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (HubRemoteSupervisorConversationPayload) async -> Bool)] = [:]
    private static var supervisorRouteDecisionOverrideForTesting: (@Sendable (SupervisorRouteDecisionRequestPayload) async -> SupervisorRouteDecisionResult)?
    private static var scopedSupervisorRouteDecisionOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (SupervisorRouteDecisionRequestPayload) async -> SupervisorRouteDecisionResult)] = [:]
    private static var eventWriteOverrideForTesting: (@Sendable (Data, URL, URL) throws -> Void)?
    private static let voiceTTSReadinessCacheLock = NSLock()
    private static let voiceTTSReadinessCacheTTL: TimeInterval = 1.0
    private static var voiceTTSReadinessCache: [String: CachedVoiceTTSReadiness] = [:]
    private static func withTestingOverrideLock<T>(_ body: () -> T) -> T {
        testingOverrideLock.lock()
        defer { testingOverrideLock.unlock() }
        return body()
    }

    private static func currentTestingOverrideScopeKey() -> TestingOverrideScopeKey? {
        var scopeKey: TestingOverrideScopeKey?
        withUnsafeCurrentTask { task in
            if let task {
                scopeKey = TestingOverrideScopeKey(task: task)
            }
        }
        return scopeKey
    }

    private static func testingOverride<T>(
        fallback: T?,
        scoped: [TestingOverrideScopeKey: T]
    ) -> T? {
        if let scopeKey = currentTestingOverrideScopeKey(),
           let override = scoped[scopeKey] {
            return override
        }
        return fallback
    }

    private static func setTestingOverride<T>(
        _ override: T?,
        fallback: inout T?,
        scoped: inout [TestingOverrideScopeKey: T]
    ) {
        if let scopeKey = currentTestingOverrideScopeKey() {
            if let override {
                scoped[scopeKey] = override
            } else {
                scoped.removeValue(forKey: scopeKey)
            }
            return
        }
        fallback = override
    }

    private static func resetTestingOverride<T>(
        fallback: inout T?,
        scoped: inout [TestingOverrideScopeKey: T]
    ) {
        if let scopeKey = currentTestingOverrideScopeKey() {
            scoped.removeValue(forKey: scopeKey)
            return
        }
        fallback = nil
    }

    private struct CachedVoiceTTSReadiness {
        var result: VoiceTTSReadinessResult
        var expiresAt: TimeInterval
    }

    static func currentRouteDecision() async -> HubRouteDecision {
        if let override = routeDecisionOverride() {
            return await override()
        }
        let mode = HubAIClient.transportMode()
        let hasRemote = HubPairingCoordinator.hasHubEnvFast(stateDir: nil)
        return HubRouteStateMachine.resolve(mode: mode, hasRemoteProfile: hasRemote)
    }

    private static func localIPCTransport(ttl: Double = 3.0) -> LocalIPCTransport? {
        guard let st = HubConnector.readHubStatusIfAny(ttl: ttl) else { return nil }
        let mode = (st.ipcMode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ipcPath = (st.ipcPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mode.isEmpty, !ipcPath.isEmpty else { return nil }

        let ipcURL: URL
        switch mode {
        case "file":
            ipcURL = URL(fileURLWithPath: ipcPath, isDirectory: true)
        case "socket":
            ipcURL = URL(fileURLWithPath: ipcPath, isDirectory: false)
        default:
            return nil
        }

        return LocalIPCTransport(
            mode: mode,
            ipcURL: ipcURL,
            baseDir: URL(fileURLWithPath: st.baseDir, isDirectory: true)
        )
    }

    private static func writeAll(_ data: Data, to fd: Int32) -> Bool {
        var totalWritten = 0
        return data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return false }
            while totalWritten < data.count {
                let written = Darwin.write(fd, base.advanced(by: totalWritten), data.count - totalWritten)
                if written <= 0 { return false }
                totalWritten += written
            }
            return true
        }
    }

    private static func summarized(_ error: Error) -> String {
        "\(type(of: error)):\(error.localizedDescription)"
    }

    private static func sendSocketRequest<Request: Encodable, Response: Decodable>(
        _ request: Request,
        socketURL: URL,
        timeoutSec: Double = 2.0
    ) -> Response? {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let bytes = Array(socketURL.path.utf8) + [0]
        guard bytes.count <= maxLen else { return nil }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: maxLen) { buf in
                for index in 0..<bytes.count {
                    buf[index] = bytes[index]
                }
            }
        }

        var socketAddr = addr
        let connectRC = withUnsafePointer(to: &socketAddr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectRC == 0 else { return nil }

        let clampedTimeout = max(0.2, min(4.0, timeoutSec))
        var timeout = timeval(
            tv_sec: Int(clampedTimeout.rounded(.down)),
            tv_usec: __darwin_suseconds_t((clampedTimeout.truncatingRemainder(dividingBy: 1)) * 1_000_000)
        )
        withUnsafePointer(to: &timeout) { ptr in
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
        }

        guard let encoded = try? JSONEncoder().encode(request) else { return nil }
        var payload = encoded
        payload.append(0x0A)
        guard writeAll(payload, to: fd) else { return nil }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            if buffer.count > 262_144 { return nil }
            if buffer.contains(0x0A) { break }
        }

        guard let lineEnd = buffer.firstIndex(of: 0x0A) else { return nil }
        let line = buffer.prefix(upTo: lineEnd)
        return try? JSONDecoder().decode(Response.self, from: line)
    }

    static func isLocalHubVoicePackPlaybackAvailable(preferredModelID: String) -> Bool {
        let normalizedPreferredModelID = preferredModelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedPreferredModelID.isEmpty else { return false }
        guard let model = localModelStateSnapshot()?.models.first(where: {
            $0.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedPreferredModelID
        }) else {
            return false
        }
        guard model.isEligibleHubVoicePackModel else { return false }
        guard let transport = localIPCTransport(ttl: 3.0) else { return false }
        guard transport.mode == "file" || transport.mode == "socket" else { return false }

        let cacheKey = "\(transport.baseDir.path.lowercased())::\(normalizedPreferredModelID)"
        if let cached = Self.cachedVoiceTTSReadiness(for: cacheKey) {
            return cached.ok
        }

        let result = requestVoiceTTSReadinessViaLocalIPC(
            preferredModelID: model.id,
            timeoutSec: 0.8
        )
        Self.storeVoiceTTSReadiness(result, for: cacheKey)
        return result.ok
    }

    static func synthesizeVoiceViaLocalHub(
        preferredModelID: String,
        text: String,
        localeIdentifier: String?,
        voiceColor: String?,
        speechRate: Double?,
        timeoutSec: Double = 3.0
    ) -> VoiceTTSResult {
        let payload = VoiceTTSRequestPayload(
            preferredModelId: preferredModelID,
            text: text,
            localeIdentifier: normalized(localeIdentifier),
            voiceColor: normalized(voiceColor),
            speechRate: speechRate
        )
        return requestVoiceTTSSynthesisViaLocalIPC(payload, timeoutSec: timeoutSec)
    }

    static func executeLocalTaskViaLocalHub(
        taskKind: String,
        modelID: String,
        parameters: [String: JSONValue],
        deviceID: String? = nil,
        timeoutSec: Double = 5.0
    ) -> LocalTaskResult {
        let payload = LocalTaskRequestPayload(
            taskKind: taskKind,
            modelId: modelID,
            deviceId: normalized(deviceID),
            timeoutSec: timeoutSec,
            parameters: parameters
        )
        return requestLocalTaskExecutionViaLocalIPC(payload, timeoutSec: timeoutSec)
    }

    static func fetchVoiceWakeProfile(
        desiredWakeMode: VoiceWakeMode
    ) async -> VoiceWakeProfileSyncResult {
        let routeDecision = await currentRouteDecision()

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteVoiceWakeProfile(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                desiredWakeMode: desiredWakeMode
            )
            if remote.ok || !routeDecision.allowFileFallback {
                return remote
            }
        }

        if routeDecision.requiresRemote {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                ),
                logLines: ["voice wake profile fetch requires remote route"],
                syncedAtMs: nil
            )
        }

        return await fetchVoiceWakeProfileViaLocalIPC(desiredWakeMode: desiredWakeMode)
    }

    static func setVoiceWakeProfile(
        _ profile: VoiceWakeProfile
    ) async -> VoiceWakeProfileSyncResult {
        let routeDecision = await currentRouteDecision()

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.setRemoteVoiceWakeProfile(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                profile: profile
            )
            if remote.ok || !routeDecision.allowFileFallback {
                return remote
            }
        }

        if routeDecision.requiresRemote {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                ),
                logLines: ["voice wake profile set requires remote route"],
                syncedAtMs: nil
            )
        }

        return await setVoiceWakeProfileViaLocalIPC(profile)
    }

    static func syncProject(_ entry: AXProjectEntry) {
        let payload = ProjectSyncPayload(
            projectId: entry.projectId,
            rootPath: entry.rootPath,
            displayName: entry.displayName,
            statusDigest: entry.statusDigest,
            lastSummaryAt: entry.lastSummaryAt,
            lastEventAt: entry.lastEventAt,
            updatedAt: Date().timeIntervalSince1970
        )

        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                _ = await syncProjectViaPreferredRoute(payload: payload, allowFileFallback: false)
            }
        case .auto:
            Task {
                _ = await syncProjectViaPreferredRoute(payload: payload, allowFileFallback: true)
            }
        case .fileIPC:
            _ = writeProjectSyncViaFileIPC(payload)
        }
    }

    static func appendProjectConversationTurn(
        ctx: AXProjectContext,
        userText: String,
        assistantText: String,
        createdAt: Double,
        config: AXProjectConfig?,
        userSender: AXChatMessageSender? = nil,
        userLineage: AXChatMessageLineageMetadata? = nil,
        assistantLineage: AXChatMessageLineageMetadata? = nil
    ) async -> Bool {
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let threadKey = XTProjectConversationMirror.projectThreadKey(projectId: projectId)
        let mirroredMessages = XTProjectConversationMirror.roleAwareMessages(
            projectId: projectId,
            threadKey: threadKey,
            userText: userText,
            assistantText: assistantText,
            createdAt: createdAt,
            userSender: userSender,
            userLineage: userLineage,
            assistantLineage: assistantLineage
        )
        return await appendProjectConversationTurns(
            ctx: ctx,
            messages: mirroredMessages,
            createdAt: createdAt,
            config: config
        )
    }

    static func appendProjectConversationTurns(
        ctx: AXProjectContext,
        messages: [XTProjectConversationMirrorMessage],
        createdAt: Double,
        config: AXProjectConfig?
    ) async -> Bool {
        guard XTProjectMemoryGovernance.prefersHubMemory(config) else { return false }

        let mirroredMessages = messages.filter { message in
            !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !mirroredMessages.isEmpty else { return false }

        let routeDecision = await currentRouteDecision()
        guard routeDecision.preferRemote else { return false }

        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let threadKey = XTProjectConversationMirror.projectThreadKey(projectId: projectId)
        let payload = HubRemoteProjectConversationPayload(
            projectId: projectId,
            threadKey: threadKey,
            requestId: XTProjectConversationMirror.requestID(projectId: projectId, createdAt: createdAt),
            createdAtMs: XTProjectConversationMirror.createdAtMs(createdAt),
            userText: mirroredMessages.first(where: { $0.role == "user" })?.content ?? "",
            assistantText: mirroredMessages.first(where: { $0.role == "assistant" })?.content ?? "",
            messages: mirroredMessages
        )

        let remote = await HubPairingCoordinator.shared.appendRemoteProjectConversationTurn(
            options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
            payload: payload
        )
        if remote.ok {
            await invalidateProjectRemoteMemorySnapshotCache(
                projectId: projectId,
                reason: .newTurnAppend
            )
        }
        return remote.ok
    }

    static func appendSupervisorConversationTurn(
        userText: String,
        assistantText: String,
        createdAt: Double
    ) async -> Bool {
        if let override = supervisorConversationAppendOverride() {
            guard let normalizedTurn = XTSupervisorConversationMirror.normalizedTurn(
                userText: userText,
                assistantText: assistantText
            ) else {
                return false
            }
            let payload = HubRemoteSupervisorConversationPayload(
                threadKey: XTSupervisorConversationMirror.threadKey,
                requestId: XTSupervisorConversationMirror.requestID(createdAt: createdAt),
                createdAtMs: XTSupervisorConversationMirror.createdAtMs(createdAt),
                userText: normalizedTurn.userText,
                assistantText: normalizedTurn.assistantText
            )
            return await override(payload)
        }

        guard let normalizedTurn = XTSupervisorConversationMirror.normalizedTurn(
            userText: userText,
            assistantText: assistantText
        ) else {
            return false
        }

        let routeDecision = await currentRouteDecision()
        guard routeDecision.preferRemote else { return false }

        let payload = HubRemoteSupervisorConversationPayload(
            threadKey: XTSupervisorConversationMirror.threadKey,
            requestId: XTSupervisorConversationMirror.requestID(createdAt: createdAt),
            createdAtMs: XTSupervisorConversationMirror.createdAtMs(createdAt),
            userText: normalizedTurn.userText,
            assistantText: normalizedTurn.assistantText
        )

        let remote = await HubPairingCoordinator.shared.appendRemoteSupervisorConversationTurn(
            options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
            payload: payload
        )
        if remote.ok {
            await invalidateSupervisorMemoryCache(reason: .newTurnAppend)
        }
        return remote.ok
    }

    static func requestSupervisorRemoteContinuity(
        bypassCache: Bool = false,
        timeoutSec: Double = 0.9
    ) async -> SupervisorRemoteContinuityResult {
        if let override = supervisorRemoteContinuityOverride() {
            return await override(bypassCache)
        }

        let routeDecision = await currentRouteDecision()
        guard routeDecision.preferRemote else {
            return SupervisorRemoteContinuityResult(
                ok: false,
                source: "xt_cache",
                workingEntries: [],
                cacheHit: false,
                reasonCode: routeDecision.remoteUnavailableReasonCode ?? "remote_route_not_preferred"
            )
        }

        let remote = await fetchRemoteMemorySnapshot(
            mode: .supervisorOrchestration,
            projectId: nil,
            bypassCache: bypassCache,
            timeoutSec: timeoutSec
        )
        return SupervisorRemoteContinuityResult(
            ok: remote.snapshot.ok,
            source: remote.snapshot.ok ? "hub_thread" : remote.snapshot.source,
            workingEntries: remote.snapshot.ok ? remote.snapshot.workingEntries : [],
            cacheHit: remote.cacheHit,
            reasonCode: remote.snapshot.reasonCode,
            remoteSnapshotCacheScope: remote.cacheMetadata?.scope,
            remoteSnapshotCachedAtMs: remote.cacheMetadata?.storedAtMs,
            remoteSnapshotAgeMs: remote.cacheMetadata?.ageMs,
            remoteSnapshotTTLRemainingMs: remote.cacheMetadata?.ttlRemainingMs,
            remoteSnapshotCachePosture: remote.cacheMetadata?.cachePosture.rawValue,
            remoteSnapshotInvalidationReason: remote.cacheMetadata?.invalidationReason?.rawValue
        )
    }

    static func syncProjectCanonicalMemory(
        ctx: AXProjectContext,
        memory: AXMemory,
        config: AXProjectConfig?
    ) {
        guard XTProjectMemoryGovernance.prefersHubMemory(config) else { return }

        let projectDisplayName = AXProjectRegistryStore.displayName(
            forRoot: ctx.root,
            preferredDisplayName: memory.projectName
        )
        let payload = ProjectCanonicalMemoryPayload(
            projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
            projectRoot: ctx.root.path,
            displayName: projectDisplayName,
            updatedAt: memory.updatedAt,
            items: XTProjectCanonicalMemorySync.items(
                memory: memory,
                preferredProjectName: projectDisplayName
            ).map { item in
                ProjectCanonicalMemoryItemPayload(key: item.key, value: item.value)
            }
        )
        guard !payload.items.isEmpty else { return }

        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                let result = await syncProjectCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "project",
                    scopeId: payload.projectId,
                    displayName: payload.displayName,
                    result: result
                )
            }
        case .auto:
            Task {
                let result = await syncProjectCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: true
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "project",
                    scopeId: payload.projectId,
                    displayName: payload.displayName,
                    result: result
                )
            }
        case .fileIPC:
            let result = writeProjectCanonicalMemoryViaLocalIPC(payload)
            recordCanonicalMemorySyncStatus(
                scopeKind: "project",
                scopeId: payload.projectId,
                displayName: payload.displayName,
                result: result
            )
            if result.ok {
                Task {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        }
    }

    static func diagnoseProjectCanonicalRustImport(
        ctx: AXProjectContext,
        memory: AXMemory,
        config: AXProjectConfig?,
        timeoutSec: Double = 0.75
    ) async -> ProjectCanonicalRustImportDiagnostics {
        let projectDisplayName = AXProjectRegistryStore.displayName(
            forRoot: ctx.root,
            preferredDisplayName: memory.projectName
        )
        let payload = ProjectCanonicalMemoryPayload(
            projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
            projectRoot: ctx.root.path,
            displayName: projectDisplayName,
            updatedAt: memory.updatedAt,
            items: XTProjectCanonicalMemorySync.items(
                memory: memory,
                preferredProjectName: projectDisplayName
            ).map { item in
                ProjectCanonicalMemoryItemPayload(key: item.key, value: item.value)
            }
        )

        guard XTProjectMemoryGovernance.prefersHubMemory(config) else {
            return ProjectCanonicalRustImportDiagnostics(
                ok: true,
                source: "local_config",
                projectId: payload.projectId,
                displayName: projectDisplayName,
                expectedItemCount: 0,
                skippedMetadataCount: payload.items.count,
                rustObjectCount: 0,
                matchedCount: 0,
                missingCount: 0,
                staleCount: 0,
                mismatchCount: 0,
                extraCount: 0,
                reasonCode: "hub_memory_not_preferred",
                issues: []
            )
        }

        let (expected, skippedMetadataCount) = expectedRustProjectCanonicalObjects(payload: payload)
        guard hasSuccessfulRustProjectCanonicalSync(projectId: payload.projectId) else {
            return ProjectCanonicalRustImportDiagnostics(
                ok: false,
                source: "local_status",
                projectId: payload.projectId,
                displayName: projectDisplayName,
                expectedItemCount: expected.count,
                skippedMetadataCount: skippedMetadataCount,
                rustObjectCount: 0,
                matchedCount: 0,
                missingCount: expected.count,
                staleCount: 0,
                mismatchCount: 0,
                extraCount: 0,
                reasonCode: "rust_project_canonical_sync_status_missing",
                issues: [
                    ProjectCanonicalRustImportDiagnosticIssue(
                        severity: "warning",
                        reasonCode: "rust_project_canonical_sync_status_missing",
                        key: nil,
                        memoryId: nil,
                        detail: "canonical_memory_sync_status.json has no successful Rust delivery for project \(payload.projectId)"
                    )
                ]
            )
        }

        guard let rustSnapshot = await fetchRustProjectCanonicalMemorySnapshot(
            projectId: payload.projectId,
            limit: 128,
            timeoutSec: timeoutSec
        ) else {
            return ProjectCanonicalRustImportDiagnostics(
                ok: false,
                source: "rust_http",
                projectId: payload.projectId,
                displayName: projectDisplayName,
                expectedItemCount: expected.count,
                skippedMetadataCount: skippedMetadataCount,
                rustObjectCount: 0,
                matchedCount: 0,
                missingCount: expected.count,
                staleCount: 0,
                mismatchCount: 0,
                extraCount: 0,
                reasonCode: "rust_project_canonical_objects_unavailable",
                issues: [
                    ProjectCanonicalRustImportDiagnosticIssue(
                        severity: "error",
                        reasonCode: "rust_project_canonical_objects_unavailable",
                        key: nil,
                        memoryId: nil,
                        detail: "Rust memory object list unavailable for project \(payload.projectId)"
                    )
                ]
            )
        }

        return projectCanonicalRustImportDiagnostics(
            payload: payload,
            displayName: projectDisplayName,
            expected: expected,
            skippedMetadataCount: skippedMetadataCount,
            rustSnapshot: rustSnapshot
        )
    }

    static func syncSupervisorProjectCapsule(_ capsule: SupervisorProjectCapsule) {
        let payload = ProjectCanonicalMemoryPayload(
            projectId: capsule.projectId,
            projectRoot: nil,
            displayName: capsule.projectName,
            updatedAt: Double(capsule.updatedAtMs) / 1000.0,
            items: SupervisorProjectCapsuleCanonicalSync.items(capsule: capsule).map { item in
                ProjectCanonicalMemoryItemPayload(key: item.key, value: item.value)
            }
        )
        guard !payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !payload.items.isEmpty else { return }

        let localResult = writeProjectCanonicalMemoryViaLocalIPC(payload)
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                let remoteResult = await syncProjectCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                let finalResult = mergedCanonicalMemorySyncResult(
                    primary: remoteResult,
                    secondary: localResult
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "project",
                    scopeId: payload.projectId,
                    displayName: payload.displayName,
                    result: finalResult
                )
                if finalResult.ok {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        case .auto:
            Task {
                let remoteResult = await syncProjectCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                let finalResult = mergedCanonicalMemorySyncResult(
                    primary: remoteResult,
                    secondary: localResult
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "project",
                    scopeId: payload.projectId,
                    displayName: payload.displayName,
                    result: finalResult
                )
                if finalResult.ok {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        case .fileIPC:
            recordCanonicalMemorySyncStatus(
                scopeKind: "project",
                scopeId: payload.projectId,
                displayName: payload.displayName,
                result: localResult
            )
            if localResult.ok {
                Task {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        }
    }

    static func syncSupervisorProjectWorkflow(_ snapshot: SupervisorProjectWorkflowSnapshot) {
        let payload = ProjectCanonicalMemoryPayload(
            projectId: snapshot.projectId,
            projectRoot: nil,
            displayName: snapshot.projectName,
            updatedAt: Double(snapshot.updatedAtMs) / 1000.0,
            items: SupervisorProjectWorkflowCanonicalSync.items(snapshot: snapshot).map { item in
                ProjectCanonicalMemoryItemPayload(key: item.key, value: item.value)
            }
        )
        guard !payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !payload.items.isEmpty else { return }

        let localResult = writeProjectCanonicalMemoryViaLocalIPC(payload)
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                let remoteResult = await syncProjectCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                let finalResult = mergedCanonicalMemorySyncResult(
                    primary: remoteResult,
                    secondary: localResult
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "project",
                    scopeId: payload.projectId,
                    displayName: payload.displayName,
                    result: finalResult
                )
                if finalResult.ok {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        case .auto:
            Task {
                let remoteResult = await syncProjectCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                let finalResult = mergedCanonicalMemorySyncResult(
                    primary: remoteResult,
                    secondary: localResult
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "project",
                    scopeId: payload.projectId,
                    displayName: payload.displayName,
                    result: finalResult
                )
                if finalResult.ok {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        case .fileIPC:
            recordCanonicalMemorySyncStatus(
                scopeKind: "project",
                scopeId: payload.projectId,
                displayName: payload.displayName,
                result: localResult
            )
            if localResult.ok {
                Task {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        }
    }

    static func syncSupervisorProjectHeartbeat(_ record: SupervisorProjectHeartbeatCanonicalRecord) {
        let payload = ProjectCanonicalMemoryPayload(
            projectId: record.projectId,
            projectRoot: nil,
            displayName: record.projectName,
            updatedAt: Double(record.updatedAtMs) / 1000.0,
            items: SupervisorProjectHeartbeatCanonicalSync.items(record: record).map { item in
                ProjectCanonicalMemoryItemPayload(key: item.key, value: item.value)
            }
        )
        guard !payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !payload.items.isEmpty else { return }

        let localResult = writeProjectCanonicalMemoryViaLocalIPC(payload)
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                let remoteResult = await syncProjectCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                let finalResult = mergedCanonicalMemorySyncResult(
                    primary: remoteResult,
                    secondary: localResult
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "project",
                    scopeId: payload.projectId,
                    displayName: payload.displayName,
                    result: finalResult
                )
                if finalResult.ok {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                    await appendSupervisorProjectHeartbeatRoleTurn(record)
                }
            }
        case .auto:
            Task {
                let remoteResult = await syncProjectCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                let finalResult = mergedCanonicalMemorySyncResult(
                    primary: remoteResult,
                    secondary: localResult
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "project",
                    scopeId: payload.projectId,
                    displayName: payload.displayName,
                    result: finalResult
                )
                if finalResult.ok {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                    await appendSupervisorProjectHeartbeatRoleTurn(record)
                }
            }
        case .fileIPC:
            recordCanonicalMemorySyncStatus(
                scopeKind: "project",
                scopeId: payload.projectId,
                displayName: payload.displayName,
                result: localResult
            )
            if localResult.ok {
                Task {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        }
    }

    private static func appendSupervisorProjectHeartbeatRoleTurn(
        _ record: SupervisorProjectHeartbeatCanonicalRecord
    ) async {
        guard let message = SupervisorProjectHeartbeatCanonicalSync.roleTurnMessage(record: record) else {
            return
        }
        let routeDecision = await currentRouteDecision()
        guard routeDecision.preferRemote else { return }

        let projectId = record.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectId.isEmpty else { return }
        let createdAtMs = max(record.updatedAtMs, record.lastHeartbeatAtMs)
        let createdAt = Double(max(Int64(0), createdAtMs)) / 1000.0
        let payload = HubRemoteProjectConversationPayload(
            projectId: projectId,
            threadKey: XTProjectConversationMirror.projectThreadKey(projectId: projectId),
            requestId: "\(XTProjectConversationMirror.requestID(projectId: projectId, createdAt: createdAt))_heartbeat",
            createdAtMs: XTProjectConversationMirror.createdAtMs(createdAt),
            userText: "",
            assistantText: "",
            messages: [message]
        )
        let remote = await HubPairingCoordinator.shared.appendRemoteProjectConversationTurn(
            options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
            payload: payload
        )
        if remote.ok {
            await invalidateProjectRemoteMemorySnapshotCache(
                projectId: projectId,
                reason: .newTurnAppend
            )
        }
    }

    static func syncSupervisorPortfolioSnapshot(
        _ snapshot: SupervisorPortfolioSnapshot,
        supervisorId: String = defaultSupervisorCanonicalID(),
        displayName: String? = nil
    ) {
        let normalizedSupervisorId = supervisorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSupervisorId.isEmpty else { return }

        let payload = DeviceCanonicalMemoryPayload(
            supervisorId: normalizedSupervisorId,
            displayName: displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedAt: snapshot.updatedAt,
            items: SupervisorPortfolioSnapshotCanonicalSync.items(
                snapshot: snapshot,
                supervisorId: normalizedSupervisorId
            ).map { item in
                ProjectCanonicalMemoryItemPayload(key: item.key, value: item.value)
            }
        )
        guard !payload.items.isEmpty else { return }

        let localResult = writeDeviceCanonicalMemoryViaLocalIPC(payload)
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                let remoteResult = await syncDeviceCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                let finalResult = mergedCanonicalMemorySyncResult(
                    primary: remoteResult,
                    secondary: localResult
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "device",
                    scopeId: payload.supervisorId,
                    displayName: payload.displayName,
                    result: finalResult
                )
                if finalResult.ok {
                    await invalidateSupervisorMemoryCache(reason: .reviewGuidanceCarryForwardChanged)
                }
            }
        case .auto:
            Task {
                let remoteResult = await syncDeviceCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                let finalResult = mergedCanonicalMemorySyncResult(
                    primary: remoteResult,
                    secondary: localResult
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "device",
                    scopeId: payload.supervisorId,
                    displayName: payload.displayName,
                    result: finalResult
                )
                if finalResult.ok {
                    await invalidateSupervisorMemoryCache(reason: .reviewGuidanceCarryForwardChanged)
                }
            }
        case .fileIPC:
            recordCanonicalMemorySyncStatus(
                scopeKind: "device",
                scopeId: payload.supervisorId,
                displayName: payload.displayName,
                result: localResult
            )
            if localResult.ok {
                Task {
                    await invalidateSupervisorMemoryCache(reason: .reviewGuidanceCarryForwardChanged)
                }
            }
        }
    }

    static func requestNetworkAccess(root: URL, seconds: Int, reason: String?) async -> NetworkAccessResult {
        let bridge = HubBridgeClient.status()
        if bridge.enabled {
            let remaining = Int(max(0, bridge.enabledUntil - Date().timeIntervalSince1970))
            return NetworkAccessResult(
                state: .enabled,
                source: "bridge",
                reasonCode: nil,
                remainingSeconds: remaining,
                grantRequestId: nil
            )
        }

        let routeDecision = await currentRouteDecision()
        let requestedSeconds = max(30, min(86_400, seconds))
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        if routeDecision.preferRemote {
            let grant = await HubPairingCoordinator.shared.requestRemoteNetworkGrant(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                requestedSeconds: requestedSeconds,
                reason: reason,
                projectId: projectId
            )
            let grantId = normalized(grant.grantRequestId)
            let reasonCode = normalizedReasonCode(grant.reasonCode, fallback: grant.ok ? nil : "grant_failed")

            if grant.ok {
                switch grant.decision {
                case .approved:
                    let bridgeAfterGrant = await waitForBridgeEnabled(timeoutSec: 4.2)
                    if bridgeAfterGrant.enabled {
                        let remaining = Int(max(0, bridgeAfterGrant.enabledUntil - Date().timeIntervalSince1970))
                        await noteRemoteMemoryGrantStateChanged(projectId: projectId)
                        return NetworkAccessResult(
                            state: .autoApproved,
                            source: "grpc",
                            reasonCode: "auto_approved",
                            remainingSeconds: remaining,
                            grantRequestId: grantId
                        )
                    }
                    await noteRemoteMemoryGrantStateChanged(projectId: projectId)
                    return NetworkAccessResult(
                        state: .autoApproved,
                        source: "grpc",
                        reasonCode: "bridge_starting",
                        remainingSeconds: nil,
                        grantRequestId: grantId
                    )

                case .queued:
                    await noteRemoteMemoryGrantStateChanged(projectId: projectId)
                    return NetworkAccessResult(
                        state: .queued,
                        source: "grpc",
                        reasonCode: reasonCode ?? "queued",
                        remainingSeconds: nil,
                        grantRequestId: grantId
                    )

                case .denied:
                    await noteRemoteMemoryGrantStateChanged(projectId: projectId)
                    return NetworkAccessResult(
                        state: .denied,
                        source: "grpc",
                        reasonCode: reasonCode ?? "denied",
                        remainingSeconds: nil,
                        grantRequestId: grantId
                    )

                case .failed:
                    if routeDecision.allowFileFallback,
                       HubRouteStateMachine.shouldFallbackToFile(afterRemoteReasonCode: reasonCode) {
                        break
                    }
                    return NetworkAccessResult(
                        state: networkFailureState(reasonCode: reasonCode),
                        source: "grpc",
                        reasonCode: reasonCode ?? "grant_failed",
                        remainingSeconds: nil,
                        grantRequestId: grantId
                    )
                }
            }

            if !routeDecision.allowFileFallback {
                return NetworkAccessResult(
                    state: networkFailureState(reasonCode: reasonCode),
                    source: "grpc",
                    reasonCode: reasonCode ?? "grant_failed",
                    remainingSeconds: nil,
                    grantRequestId: grantId
                )
            }
        } else if routeDecision.requiresRemote {
            return NetworkAccessResult(
                state: .failed,
                source: "grpc",
                reasonCode: routeDecision.remoteUnavailableReasonCode ?? "hub_env_missing",
                remainingSeconds: nil,
                grantRequestId: nil
            )
        }

        let dispatch = requestNetworkViaLocalIPC(root: root, seconds: requestedSeconds, reason: reason)
        guard let dispatch else {
            return NetworkAccessResult(
                state: .failed,
                source: "local_ipc",
                reasonCode: "hub_not_connected",
                remainingSeconds: nil,
                grantRequestId: nil
            )
        }

        if let dispatchReason = dispatch.reasonCode {
            return NetworkAccessResult(
                state: networkFailureState(reasonCode: dispatchReason),
                source: dispatch.source,
                reasonCode: dispatchReason,
                remainingSeconds: nil,
                grantRequestId: dispatch.ticket.reqId,
                detail: dispatch.detail
            )
        }

        let ack: NetworkIPCResponse?
        if let existingAck = dispatch.ack {
            ack = existingAck
        } else {
            ack = await pollNetworkResponse(
                baseDir: dispatch.ticket.baseDir,
                reqId: dispatch.ticket.reqId,
                timeoutSec: 2.6
            )
        }
        if let ack {
            let grantId = normalized(ack.id) ?? dispatch.ticket.reqId
            if !ack.ok {
                let reasonCode = normalizedReasonCode(ack.error, fallback: "denied") ?? "denied"
                return NetworkAccessResult(
                    state: networkFailureState(reasonCode: reasonCode),
                    source: dispatch.source,
                    reasonCode: reasonCode,
                    remainingSeconds: nil,
                    grantRequestId: grantId,
                    detail: normalized(ack.error)
                )
            }

            let reasonCode = normalizedReasonCode(ack.error, fallback: nil)
            if reasonCode == "auto_approved" {
                let bridgeAfterGrant = await waitForBridgeEnabled(timeoutSec: 4.2)
                if bridgeAfterGrant.enabled {
                    let remaining = Int(max(0, bridgeAfterGrant.enabledUntil - Date().timeIntervalSince1970))
                    await noteRemoteMemoryGrantStateChanged(projectId: projectId)
                    return NetworkAccessResult(
                        state: .autoApproved,
                        source: dispatch.source,
                        reasonCode: "auto_approved",
                        remainingSeconds: remaining,
                        grantRequestId: grantId
                    )
                }
                await noteRemoteMemoryGrantStateChanged(projectId: projectId)
                return NetworkAccessResult(
                    state: .autoApproved,
                    source: dispatch.source,
                    reasonCode: "bridge_starting",
                    remainingSeconds: nil,
                    grantRequestId: grantId
                )
            }

            if reasonCode == "denied" || reasonCode == "forbidden" {
                await noteRemoteMemoryGrantStateChanged(projectId: projectId)
                return NetworkAccessResult(
                    state: .denied,
                    source: dispatch.source,
                    reasonCode: reasonCode,
                    remainingSeconds: nil,
                    grantRequestId: grantId
                )
            }

            await noteRemoteMemoryGrantStateChanged(projectId: projectId)
            return NetworkAccessResult(
                state: .queued,
                source: dispatch.source,
                reasonCode: reasonCode ?? "queued",
                remainingSeconds: nil,
                grantRequestId: grantId
            )
        }

        if dispatch.source == "file_ipc" {
            let bridgeAfterFileRequest = HubBridgeClient.status()
            if bridgeAfterFileRequest.enabled {
                let remaining = Int(max(0, bridgeAfterFileRequest.enabledUntil - Date().timeIntervalSince1970))
                await noteRemoteMemoryGrantStateChanged(projectId: projectId)
                return NetworkAccessResult(
                    state: .enabled,
                    source: "bridge",
                    reasonCode: nil,
                    remainingSeconds: remaining,
                    grantRequestId: dispatch.ticket.reqId
                )
            }
        }

        await noteRemoteMemoryGrantStateChanged(projectId: projectId)
        return NetworkAccessResult(
            state: .queued,
            source: dispatch.source,
            reasonCode: "ack_timeout",
            remainingSeconds: nil,
            grantRequestId: dispatch.ticket.reqId
        )
    }

    private static func requestNetworkViaLocalIPC(root: URL, seconds: Int, reason: String?) -> NetworkIPCDispatchResult? {
        guard let transport = localIPCTransport(ttl: 3.0) else { return nil }
        let reqId = UUID().uuidString
        let rootPath = AXProjectRegistryStore.normalizedRootPath(root)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let displayName = AXProjectRegistryStore.displayName(forRoot: root)

        let payload = NetworkRequestPayload(
            id: reqId,
            source: "x_terminal",
            projectId: projectId,
            rootPath: rootPath,
            displayName: displayName,
            reason: reason?.trimmingCharacters(in: .whitespacesAndNewlines),
            requestedSeconds: max(10, seconds),
            createdAt: Date().timeIntervalSince1970
        )
        let req = NetworkIPCRequest(type: "need_network", reqId: reqId, network: payload)
        let ticket = NetworkRequestTicket(reqId: reqId, baseDir: transport.baseDir)

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let data: Data
            do {
                data = try JSONEncoder().encode(req)
            } catch {
                return NetworkIPCDispatchResult(
                    ticket: ticket,
                    ack: nil,
                    source: "file_ipc",
                    reasonCode: "network_request_encode_failed",
                    detail: summarized(error)
                )
            }
            let writeStatus = writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_net",
                tmpPrefix: ".xterminal_net",
                in: transport.ipcURL
            )
            if writeStatus.requestQueued == true {
                return NetworkIPCDispatchResult(ticket: ticket, ack: nil, source: "file_ipc")
            }
            return NetworkIPCDispatchResult(
                ticket: ticket,
                ack: nil,
                source: "file_ipc",
                reasonCode: "network_request_write_failed",
                detail: normalized(writeStatus.requestError)
            )
        case "socket":
            guard let ack: NetworkIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return NetworkIPCDispatchResult(
                    ticket: ticket,
                    ack: nil,
                    source: "socket_ipc",
                    reasonCode: "socket_request_failed",
                    detail: "need_network socket request failed"
                )
            }
            return NetworkIPCDispatchResult(ticket: ticket, ack: ack, source: "socket_ipc")
        default:
            return NetworkIPCDispatchResult(
                ticket: ticket,
                ack: nil,
                source: "local_ipc",
                reasonCode: "unsupported_ipc_mode",
                detail: "need_network local IPC mode unsupported"
            )
        }
    }

    @discardableResult
    private static func syncProjectViaPreferredRoute(
        payload: ProjectSyncPayload,
        allowFileFallback: Bool
    ) async -> Bool {
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.syncRemoteProjectSnapshot(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteProjectSyncPayload(
                    projectId: payload.projectId,
                    rootPath: payload.rootPath,
                    displayName: payload.displayName,
                    statusDigest: payload.statusDigest,
                    lastSummaryAt: payload.lastSummaryAt,
                    lastEventAt: payload.lastEventAt,
                    updatedAt: payload.updatedAt
                )
            )
            if remote.ok {
                return true
            }
            if !allowFileFallback {
                return false
            }
        } else if !allowFileFallback {
            return false
        }

        return writeProjectSyncViaFileIPC(payload)
    }

    @discardableResult
    private static func syncProjectCanonicalMemoryViaPreferredRoute(
        payload: ProjectCanonicalMemoryPayload,
        allowFileFallback: Bool
    ) async -> CanonicalMemorySyncDispatchResult {
        let rustResult = await syncProjectCanonicalMemoryViaRustHub(payload: payload)
        if let rustResult, rustResult.ok {
            await invalidateProjectRemoteMemorySnapshotCache(
                projectId: payload.projectId,
                reason: .projectCanonicalSave
            )
            clearPendingProjectCanonicalRustSync(payload: payload)
            return rustResult
        }
        if let rustResult {
            if shouldPersistPendingProjectCanonicalRustSync(result: rustResult) {
                recordPendingProjectCanonicalRustSync(payload: payload, result: rustResult)
            } else {
                clearPendingProjectCanonicalRustSync(payload: payload)
            }
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.upsertRemoteProjectCanonicalMemory(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteProjectCanonicalMemoryPayload(
                    projectId: payload.projectId,
                    items: payload.items.map { item in
                        HubRemoteCanonicalMemoryItem(key: item.key, value: item.value)
                    }
                )
            )
            if remote.ok {
                await invalidateProjectRemoteMemorySnapshotCache(
                    projectId: payload.projectId,
                    reason: .projectCanonicalSave
                )
                return CanonicalMemorySyncDispatchResult(
                    ok: true,
                    source: normalized(remote.source) ?? "grpc",
                    deliveryState: "delivered_remote",
                    auditRefs: remote.auditRefs,
                    evidenceRefs: remote.evidenceRefs,
                    writebackRefs: remote.writebackRefs,
                    detail: normalized(remote.logText)
                )
            }
            if !allowFileFallback {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: normalized(remote.source) ?? "grpc",
                    deliveryState: "remote_delivery_failed",
                    auditRefs: remote.auditRefs,
                    evidenceRefs: remote.evidenceRefs,
                    writebackRefs: remote.writebackRefs,
                    reasonCode: normalizedReasonCode(
                        remote.reasonCode,
                        fallback: "project_canonical_memory_remote_failed"
                    ),
                    detail: normalized(remote.logText)
                )
            }
        } else if !allowFileFallback {
            if let rustResult {
                return rustResult
            }
            return CanonicalMemorySyncDispatchResult(
                ok: false,
                source: "grpc",
                reasonCode: "hub_not_connected",
                detail: "project canonical memory remote route unavailable"
            )
        }

        let localResult = writeProjectCanonicalMemoryViaLocalIPC(payload)
        if localResult.ok {
            await invalidateProjectRemoteMemorySnapshotCache(
                projectId: payload.projectId,
                reason: .projectCanonicalSave
            )
        }
        return localResult
    }

    private static func syncProjectCanonicalMemoryViaRustHub(
        payload: ProjectCanonicalMemoryPayload,
        timeoutSec: Double = 1.0
    ) async -> CanonicalMemorySyncDispatchResult? {
        if let override = projectCanonicalRustSyncOverride() {
            guard let result = await override(payload) else { return nil }
            return CanonicalMemorySyncDispatchResult(
                ok: result.ok,
                source: normalized(result.source) ?? "rust_http",
                deliveryState: normalized(result.deliveryState)
                    ?? (result.ok ? "delivered_rust_memory_objects" : "rust_http_failed"),
                reasonCode: normalizedReasonCode(
                    result.reasonCode,
                    fallback: result.ok ? nil : "project_canonical_memory_rust_http_failed"
                ),
                detail: normalized(result.detail)
            )
        }

        let baseURL = RustHubReadinessClient.defaultBaseURL()
        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("memory")
                .appendingPathComponent("project-canonical-sync"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "apply", value: "1")]
        guard let url = components?.url else {
            return CanonicalMemorySyncDispatchResult(
                ok: false,
                source: "rust_http",
                deliveryState: "rust_http_url_invalid",
                reasonCode: "project_canonical_memory_rust_url_invalid",
                detail: "invalid Rust Hub project canonical memory URL"
            )
        }

        let reqId = "project_canonical_rust_\(UUID().uuidString.lowercased())"
        let envelope = ProjectCanonicalMemoryIPCRequest(
            type: "project_canonical_memory",
            reqId: reqId,
            projectCanonicalMemory: payload
        )
        guard let body = try? JSONEncoder().encode(envelope) else {
            return CanonicalMemorySyncDispatchResult(
                ok: false,
                source: "rust_http",
                deliveryState: "rust_http_encode_failed",
                reasonCode: "project_canonical_memory_encode_failed",
                detail: "project canonical memory Rust request encoding failed"
            )
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = max(0.25, min(5.0, timeoutSec))
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            RustHubHTTPAccess.applyAccessKey(to: &request)
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let ok = (parsed?["ok"] as? Bool) == true && (200..<300).contains(statusCode)
            return CanonicalMemorySyncDispatchResult(
                ok: ok,
                source: "rust_http",
                deliveryState: ok ? "delivered_rust_memory_objects" : "rust_http_rejected",
                reasonCode: normalizedReasonCode(
                    parsed?["error_code"] as? String
                        ?? parsed?["reason_code"] as? String
                        ?? (ok ? nil : "project_canonical_memory_rust_http_failed"),
                    fallback: ok ? nil : "project_canonical_memory_rust_http_failed"
                ),
                detail: projectCanonicalRustSyncDetail(parsed: parsed, httpStatus: statusCode)
            )
        } catch {
            return CanonicalMemorySyncDispatchResult(
                ok: false,
                source: "rust_http",
                deliveryState: "rust_http_unavailable",
                reasonCode: "project_canonical_memory_rust_http_unavailable",
                detail: summarized(error)
            )
        }
    }

    static func extractMemoryWritebackCandidatesViaRust(
        payload: MemoryWritebackCandidateExtractPayload,
        timeoutSec: Double = 0.75
    ) async -> MemoryWritebackCandidateExtractResult {
        if let override = memoryWritebackCandidateExtractOverride() {
            return await override(payload, timeoutSec)
        }

        let baseURL = RustHubReadinessClient.defaultBaseURL()
        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("memory")
                .appendingPathComponent("writeback")
                .appendingPathComponent("candidates")
                .appendingPathComponent("extract"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "apply", value: "1")]
        guard let url = components?.url else {
            return MemoryWritebackCandidateExtractResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_url_invalid",
                projectId: payload.projectId,
                reasonCode: "memory_writeback_candidate_extract_url_invalid",
                detail: "invalid Rust Hub memory writeback candidate extract URL"
            )
        }

        do {
            let body = try JSONEncoder().encode(payload)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = max(0.1, min(2.0, timeoutSec))
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            RustHubHTTPAccess.applyAccessKey(to: &request)

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if var decoded = try? JSONDecoder().decode(MemoryWritebackCandidateExtractResult.self, from: data) {
                decoded.source = normalized(decoded.source) ?? "rust_http"
                decoded.projectId = normalized(decoded.projectId) ?? payload.projectId
                decoded.reasonCode = normalizedReasonCode(
                    decoded.reasonCode ?? decoded.errorCode ?? decoded.denyCode,
                    fallback: decoded.ok && (200..<300).contains(statusCode)
                        ? nil
                        : "memory_writeback_candidate_extract_rust_http_failed"
                )
                if decoded.detail == nil {
                    decoded.detail = memoryWritebackCandidateExtractDetail(decoded, httpStatus: statusCode)
                }
                return decoded
            }

            return MemoryWritebackCandidateExtractResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_decode_failed",
                projectId: payload.projectId,
                reasonCode: "memory_writeback_candidate_extract_decode_failed",
                detail: "http_status=\(statusCode)"
            )
        } catch {
            return MemoryWritebackCandidateExtractResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_unavailable",
                projectId: payload.projectId,
                reasonCode: "memory_writeback_candidate_extract_rust_http_unavailable",
                detail: summarized(error)
            )
        }
    }

    static func listMemoryWritebackCandidatesViaRust(
        projectId: String?,
        limit: Int = 50,
        timeoutSec: Double = 0.75
    ) async -> MemoryWritebackCandidateListResult {
        let boundedLimit = max(1, min(200, limit))
        if let override = memoryWritebackCandidateListOverride() {
            return await override(projectId, boundedLimit, timeoutSec)
        }

        let baseURL = RustHubReadinessClient.defaultBaseURL()
        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("memory")
                .appendingPathComponent("writeback")
                .appendingPathComponent("candidates"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [URLQueryItem(name: "limit", value: String(boundedLimit))]
        if let projectId = normalized(projectId) {
            queryItems.append(URLQueryItem(name: "project_id", value: projectId))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            return MemoryWritebackCandidateListResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_url_invalid",
                reasonCode: "memory_writeback_candidate_list_url_invalid",
                detail: "invalid Rust Hub memory writeback candidate list URL"
            )
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = max(0.1, min(2.0, timeoutSec))
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            RustHubHTTPAccess.applyAccessKey(to: &request)

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if var decoded = try? JSONDecoder().decode(MemoryWritebackCandidateListResult.self, from: data) {
                decoded.source = normalized(decoded.source) ?? "rust_http"
                decoded.reasonCode = normalizedReasonCode(
                    decoded.reasonCode ?? decoded.errorCode ?? decoded.denyCode,
                    fallback: decoded.ok && (200..<300).contains(statusCode)
                        ? nil
                        : "memory_writeback_candidate_list_rust_http_failed"
                )
                if decoded.detail == nil {
                    decoded.detail = memoryWritebackCandidateListDetail(decoded, httpStatus: statusCode)
                }
                return decoded
            }

            return MemoryWritebackCandidateListResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_decode_failed",
                reasonCode: "memory_writeback_candidate_list_decode_failed",
                detail: "http_status=\(statusCode)"
            )
        } catch {
            return MemoryWritebackCandidateListResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_unavailable",
                reasonCode: "memory_writeback_candidate_list_rust_http_unavailable",
                detail: summarized(error)
            )
        }
    }

    static func listMemoryObjectsViaRust(
        filter: MemoryObjectListFilter,
        timeoutSec: Double = 0.75
    ) async -> MemoryObjectListResult {
        var normalizedFilter = filter
        normalizedFilter.scope = normalized(normalizedFilter.scope)
        normalizedFilter.ownerId = normalized(normalizedFilter.ownerId)
        normalizedFilter.projectId = normalized(normalizedFilter.projectId)
        normalizedFilter.agentId = normalized(normalizedFilter.agentId)
        normalizedFilter.sourceKind = normalized(normalizedFilter.sourceKind)
        normalizedFilter.layer = normalized(normalizedFilter.layer)
        normalizedFilter.status = normalized(normalizedFilter.status) ?? "active"
        normalizedFilter.sensitivity = normalized(normalizedFilter.sensitivity)
        normalizedFilter.visibility = normalized(normalizedFilter.visibility)
        normalizedFilter.limit = max(1, min(200, normalizedFilter.limit))

        if let override = memoryObjectListOverride() {
            return await override(normalizedFilter, timeoutSec)
        }

        let baseURL = RustHubReadinessClient.defaultBaseURL()
        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("memory")
                .appendingPathComponent("objects"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [URLQueryItem(name: "limit", value: String(normalizedFilter.limit))]
        if let scope = normalizedFilter.scope {
            queryItems.append(URLQueryItem(name: "scope", value: scope))
        }
        if let ownerId = normalizedFilter.ownerId {
            queryItems.append(URLQueryItem(name: "owner_id", value: ownerId))
        }
        if let projectId = normalizedFilter.projectId {
            queryItems.append(URLQueryItem(name: "project_id", value: projectId))
        }
        if let agentId = normalizedFilter.agentId {
            queryItems.append(URLQueryItem(name: "agent_id", value: agentId))
        }
        if let sourceKind = normalizedFilter.sourceKind {
            queryItems.append(URLQueryItem(name: "source_kind", value: sourceKind))
        }
        if let layer = normalizedFilter.layer {
            queryItems.append(URLQueryItem(name: "layer", value: layer))
        }
        if let status = normalizedFilter.status {
            queryItems.append(URLQueryItem(name: "status", value: status))
        }
        if let sensitivity = normalizedFilter.sensitivity {
            queryItems.append(URLQueryItem(name: "sensitivity", value: sensitivity))
        }
        if let visibility = normalizedFilter.visibility {
            queryItems.append(URLQueryItem(name: "visibility", value: visibility))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            return MemoryObjectListResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_url_invalid",
                filter: normalizedFilter,
                reasonCode: "memory_object_list_url_invalid",
                detail: "invalid Rust Hub memory object list URL"
            )
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = max(0.1, min(2.0, timeoutSec))
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            RustHubHTTPAccess.applyAccessKey(to: &request)

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if var decoded = try? JSONDecoder().decode(MemoryObjectListResult.self, from: data) {
                decoded.source = normalized(decoded.source) ?? "rust_http"
                decoded.reasonCode = normalizedReasonCode(
                    decoded.reasonCode ?? decoded.errorCode ?? decoded.denyCode,
                    fallback: decoded.ok && (200..<300).contains(statusCode)
                        ? nil
                        : "memory_object_list_rust_http_failed"
                )
                if decoded.filter == nil {
                    decoded.filter = normalizedFilter
                }
                if decoded.detail == nil {
                    decoded.detail = memoryObjectListDetail(decoded, httpStatus: statusCode)
                }
                return decoded
            }

            return MemoryObjectListResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_decode_failed",
                filter: normalizedFilter,
                reasonCode: "memory_object_list_decode_failed",
                detail: "http_status=\(statusCode)"
            )
        } catch {
            return MemoryObjectListResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_unavailable",
                filter: normalizedFilter,
                reasonCode: "memory_object_list_rust_http_unavailable",
                detail: summarized(error)
            )
        }
    }

    static func requestMemoryUserRevealGrantViaRust(
        _ requestPayload: MemoryUserRevealGrantRequest,
        timeoutSec: Double = 0.75
    ) async -> MemoryUserRevealGrantResult {
        var normalizedPayload = requestPayload
        normalizedPayload.action = normalized(requestPayload.action)?.lowercased().replacingOccurrences(of: "-", with: "_") ?? "evaluate"
        normalizedPayload.grantId = normalized(requestPayload.grantId)
        normalizedPayload.scope = normalized(requestPayload.scope) ?? "user"
        normalizedPayload.surface = normalized(requestPayload.surface) ?? "assistant_user_memory_inspector"
        normalizedPayload.actor = normalized(requestPayload.actor) ?? "xt_swift_shell"
        normalizedPayload.requesterRole = normalized(requestPayload.requesterRole) ?? "supervisor"
        normalizedPayload.useMode = normalized(requestPayload.useMode) ?? "assistant_user_memory_inspector"
        if let ttlMs = normalizedPayload.ttlMs {
            normalizedPayload.ttlMs = max(1_000, min(900_000, ttlMs))
        }
        normalizedPayload.auditRef = normalized(requestPayload.auditRef)

        guard ["issue", "grant", "evaluate", "status", "check", "revoke", "end"].contains(normalizedPayload.action) else {
            return MemoryUserRevealGrantResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_request_invalid",
                scope: normalizedPayload.scope,
                surface: normalizedPayload.surface,
                reasonCode: "memory_user_reveal_grant_action_invalid",
                contentIncluded: false,
                memoryIdsIncluded: false,
                projectCoderAllowed: false,
                modelContextAuthority: false,
                memoryServingAuthorityChange: false,
                productionAuthorityChange: false,
                detail: "unsupported memory user reveal grant action"
            )
        }

        if let override = memoryUserRevealGrantOverride() {
            return await override(normalizedPayload, timeoutSec)
        }

        let url = RustHubReadinessClient.defaultBaseURL()
            .appendingPathComponent("memory")
            .appendingPathComponent("user-reveal-grant")
            .appendingPathComponent(normalizedPayload.action)

        do {
            let body = try JSONEncoder().encode(normalizedPayload)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = max(0.1, min(2.0, timeoutSec))
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            RustHubHTTPAccess.applyAccessKey(to: &request)

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if var decoded = try? JSONDecoder().decode(MemoryUserRevealGrantResult.self, from: data) {
                decoded.source = normalized(decoded.source) ?? "rust_http"
                decoded.reasonCode = normalizedReasonCode(
                    decoded.reasonCode ?? decoded.errorCode ?? decoded.denyCode,
                    fallback: decoded.ok && (200..<300).contains(statusCode)
                        ? nil
                        : "memory_user_reveal_grant_rust_http_failed"
                )
                if decoded.contentIncluded == nil {
                    decoded.contentIncluded = false
                }
                if decoded.memoryIdsIncluded == nil {
                    decoded.memoryIdsIncluded = false
                }
                if decoded.projectCoderAllowed == nil {
                    decoded.projectCoderAllowed = false
                }
                if decoded.modelContextAuthority == nil {
                    decoded.modelContextAuthority = false
                }
                if decoded.memoryServingAuthorityChange == nil {
                    decoded.memoryServingAuthorityChange = false
                }
                if decoded.productionAuthorityChange == nil {
                    decoded.productionAuthorityChange = false
                }
                if decoded.detail == nil {
                    decoded.detail = memoryUserRevealGrantDetail(decoded, httpStatus: statusCode)
                }
                return decoded
            }

            return MemoryUserRevealGrantResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_decode_failed",
                scope: normalizedPayload.scope,
                surface: normalizedPayload.surface,
                reasonCode: "memory_user_reveal_grant_decode_failed",
                contentIncluded: false,
                memoryIdsIncluded: false,
                projectCoderAllowed: false,
                modelContextAuthority: false,
                memoryServingAuthorityChange: false,
                productionAuthorityChange: false,
                detail: "http_status=\(statusCode)"
            )
        } catch {
            return MemoryUserRevealGrantResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_unavailable",
                scope: normalizedPayload.scope,
                surface: normalizedPayload.surface,
                reasonCode: "memory_user_reveal_grant_rust_http_unavailable",
                contentIncluded: false,
                memoryIdsIncluded: false,
                projectCoderAllowed: false,
                modelContextAuthority: false,
                memoryServingAuthorityChange: false,
                productionAuthorityChange: false,
                detail: summarized(error)
            )
        }
    }

    static func getMemoryObjectHistoryViaRust(
        memoryId: String,
        limit: Int = 20,
        timeoutSec: Double = 0.75
    ) async -> MemoryObjectHistoryResult {
        let normalizedMemoryId = memoryId.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedLimit = max(1, min(100, limit))
        guard !normalizedMemoryId.isEmpty else {
            return MemoryObjectHistoryResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_request_invalid",
                memoryId: nil,
                reasonCode: "memory_object_id_required",
                detail: "memory_id is required"
            )
        }
        if let override = memoryObjectHistoryOverride() {
            return await override(normalizedMemoryId, boundedLimit, timeoutSec)
        }

        var components = URLComponents(
            url: RustHubReadinessClient.defaultBaseURL()
                .appendingPathComponent("memory")
                .appendingPathComponent("objects")
                .appendingPathComponent(normalizedMemoryId)
                .appendingPathComponent("history"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "limit", value: String(boundedLimit))]
        guard let url = components?.url else {
            return MemoryObjectHistoryResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_url_invalid",
                memoryId: normalizedMemoryId,
                reasonCode: "memory_object_history_url_invalid",
                detail: "invalid Rust Hub memory object history URL"
            )
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = max(0.1, min(2.0, timeoutSec))
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            RustHubHTTPAccess.applyAccessKey(to: &request)

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if var decoded = try? JSONDecoder().decode(MemoryObjectHistoryResult.self, from: data) {
                decoded.source = normalized(decoded.source) ?? "rust_http"
                decoded.memoryId = normalized(decoded.memoryId) ?? normalizedMemoryId
                decoded.reasonCode = normalizedReasonCode(
                    decoded.reasonCode ?? decoded.errorCode ?? decoded.denyCode,
                    fallback: decoded.ok && (200..<300).contains(statusCode)
                        ? nil
                        : "memory_object_history_rust_http_failed"
                )
                if decoded.detail == nil {
                    decoded.detail = memoryObjectHistoryDetail(decoded, httpStatus: statusCode)
                }
                return decoded
            }

            return MemoryObjectHistoryResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_decode_failed",
                memoryId: normalizedMemoryId,
                reasonCode: "memory_object_history_decode_failed",
                detail: "http_status=\(statusCode)"
            )
        } catch {
            return MemoryObjectHistoryResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_unavailable",
                memoryId: normalizedMemoryId,
                reasonCode: "memory_object_history_rust_http_unavailable",
                detail: summarized(error)
            )
        }
    }

    static func getMemoryObjectViaRust(
        memoryId: String,
        timeoutSec: Double = 0.75
    ) async -> MemoryObjectResult {
        let normalizedMemoryId = memoryId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMemoryId.isEmpty else {
            return MemoryObjectResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_request_invalid",
                memoryId: nil,
                reasonCode: "memory_object_id_required",
                detail: "memory_id is required"
            )
        }
        if let override = memoryObjectGetOverride() {
            return await override(normalizedMemoryId, timeoutSec)
        }

        let url = RustHubReadinessClient.defaultBaseURL()
            .appendingPathComponent("memory")
            .appendingPathComponent("objects")
            .appendingPathComponent(normalizedMemoryId)

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = max(0.1, min(2.0, timeoutSec))
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            RustHubHTTPAccess.applyAccessKey(to: &request)

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if var decoded = try? JSONDecoder().decode(MemoryObjectResult.self, from: data) {
                decoded.source = normalized(decoded.source) ?? "rust_http"
                decoded.memoryId = normalized(decoded.memoryId) ?? normalizedMemoryId
                decoded.reasonCode = normalizedReasonCode(
                    decoded.reasonCode ?? decoded.errorCode ?? decoded.denyCode,
                    fallback: decoded.ok && (200..<300).contains(statusCode)
                        ? nil
                        : "memory_object_get_rust_http_failed"
                )
                if decoded.detail == nil {
                    decoded.detail = memoryObjectDetail(decoded, httpStatus: statusCode)
                }
                return decoded
            }

            return MemoryObjectResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_decode_failed",
                memoryId: normalizedMemoryId,
                reasonCode: "memory_object_get_decode_failed",
                detail: "http_status=\(statusCode)"
            )
        } catch {
            return MemoryObjectResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_unavailable",
                memoryId: normalizedMemoryId,
                reasonCode: "memory_object_get_rust_http_unavailable",
                detail: summarized(error)
            )
        }
    }

    static func mutateMemoryObjectViaRust(
        memoryId: String,
        action: String,
        payload: MemoryObjectMutationPayload,
        timeoutSec: Double = 0.75
    ) async -> MemoryObjectMutationResult {
        let normalizedMemoryId = memoryId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAction = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedMemoryId.isEmpty else {
            return MemoryObjectMutationResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_request_invalid",
                memoryId: nil,
                action: normalizedAction.isEmpty ? nil : normalizedAction,
                productionAuthorityChange: false,
                reasonCode: "memory_object_id_required",
                detail: "memory_id is required"
            )
        }
        guard ["archive", "delete", "pin", "unpin"].contains(normalizedAction) else {
            return MemoryObjectMutationResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_request_invalid",
                memoryId: normalizedMemoryId,
                action: normalizedAction.isEmpty ? nil : normalizedAction,
                productionAuthorityChange: false,
                reasonCode: "memory_object_mutation_action_invalid",
                detail: "unsupported memory object mutation action"
            )
        }
        var normalizedPayload = payload
        if normalized(normalizedPayload.actor) == nil {
            normalizedPayload.actor = "xt_swift_shell"
        }
        if normalized(normalizedPayload.requesterRole) == nil {
            normalizedPayload.requesterRole = "tool"
        }
        if normalized(normalizedPayload.useMode) == nil {
            normalizedPayload.useMode = "tool_plan"
        }
        if normalizedAction == "archive", normalizedPayload.confirm, normalizedPayload.confirmArchive == nil {
            normalizedPayload.confirmArchive = true
        }
        if normalizedAction == "delete", normalizedPayload.confirm, normalizedPayload.confirmDelete == nil {
            normalizedPayload.confirmDelete = true
        }

        if let override = memoryObjectMutationOverride() {
            return await override(normalizedAction, normalizedMemoryId, normalizedPayload, timeoutSec)
        }

        let url = RustHubReadinessClient.defaultBaseURL()
            .appendingPathComponent("memory")
            .appendingPathComponent("objects")
            .appendingPathComponent(normalizedMemoryId)
            .appendingPathComponent(normalizedAction)

        do {
            let body = try JSONEncoder().encode(normalizedPayload)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = max(0.1, min(2.0, timeoutSec))
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            RustHubHTTPAccess.applyAccessKey(to: &request)

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if var decoded = try? JSONDecoder().decode(MemoryObjectMutationResult.self, from: data) {
                decoded.source = normalized(decoded.source) ?? "rust_http"
                decoded.memoryId = normalized(decoded.memoryId) ?? normalizedMemoryId
                decoded.action = normalized(decoded.action) ?? normalized(decoded.mutation?.operation) ?? normalizedAction
                decoded.reasonCode = normalizedReasonCode(
                    decoded.reasonCode ?? decoded.errorCode ?? decoded.denyCode,
                    fallback: decoded.ok && (200..<300).contains(statusCode)
                        ? nil
                        : "memory_object_\(normalizedAction)_rust_http_failed"
                )
                if decoded.productionAuthorityChange == nil {
                    decoded.productionAuthorityChange = false
                }
                if decoded.detail == nil {
                    decoded.detail = memoryObjectMutationDetail(decoded, httpStatus: statusCode)
                }
                return decoded
            }

            return MemoryObjectMutationResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_decode_failed",
                memoryId: normalizedMemoryId,
                action: normalizedAction,
                productionAuthorityChange: false,
                reasonCode: "memory_object_\(normalizedAction)_decode_failed",
                detail: "http_status=\(statusCode)"
            )
        } catch {
            return MemoryObjectMutationResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_unavailable",
                memoryId: normalizedMemoryId,
                action: normalizedAction,
                productionAuthorityChange: false,
                reasonCode: "memory_object_\(normalizedAction)_rust_http_unavailable",
                detail: summarized(error)
            )
        }
    }

    static func maintainMemoryWritebackCandidatesViaRust(
        payload: MemoryWritebackCandidateMaintenancePayload,
        timeoutSec: Double = 0.75
    ) async -> MemoryWritebackCandidateMaintenanceResult {
        let normalizedLimit = max(1, min(500, payload.limit))
        var normalizedPayload = payload
        normalizedPayload.limit = normalizedLimit
        if normalizedPayload.apply {
            normalizedPayload.dryRun = false
        } else {
            normalizedPayload.dryRun = true
        }
        if let override = memoryWritebackCandidateMaintenanceOverride() {
            return await override(normalizedPayload, timeoutSec)
        }

        let url = RustHubReadinessClient.defaultBaseURL()
            .appendingPathComponent("memory")
            .appendingPathComponent("writeback")
            .appendingPathComponent("candidates")
            .appendingPathComponent("maintenance")

        do {
            let body = try JSONEncoder().encode(normalizedPayload)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = max(0.1, min(3.0, timeoutSec))
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            RustHubHTTPAccess.applyAccessKey(to: &request)

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if var decoded = try? JSONDecoder().decode(MemoryWritebackCandidateMaintenanceResult.self, from: data) {
                decoded.source = normalized(decoded.source) ?? "rust_http"
                decoded.projectId = normalized(decoded.projectId) ?? normalizedPayload.projectId
                decoded.reasonCode = normalizedReasonCode(
                    decoded.reasonCode ?? decoded.errorCode ?? decoded.denyCode,
                    fallback: decoded.ok && (200..<300).contains(statusCode)
                        ? nil
                        : "memory_writeback_candidate_maintenance_rust_http_failed"
                )
                if decoded.productionAuthorityChange == nil {
                    decoded.productionAuthorityChange = false
                }
                if decoded.detail == nil {
                    decoded.detail = memoryWritebackCandidateMaintenanceDetail(decoded, httpStatus: statusCode)
                }
                return decoded
            }

            return MemoryWritebackCandidateMaintenanceResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_decode_failed",
                projectId: normalizedPayload.projectId,
                productionAuthorityChange: false,
                reasonCode: "memory_writeback_candidate_maintenance_decode_failed",
                detail: "http_status=\(statusCode)"
            )
        } catch {
            return MemoryWritebackCandidateMaintenanceResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_unavailable",
                projectId: normalizedPayload.projectId,
                productionAuthorityChange: false,
                reasonCode: "memory_writeback_candidate_maintenance_rust_http_unavailable",
                detail: summarized(error)
            )
        }
    }

    static func approveMemoryWritebackCandidateViaRust(
        memoryId: String,
        payload: MemoryWritebackCandidateDecisionPayload,
        timeoutSec: Double = 0.75
    ) async -> MemoryWritebackCandidateDecisionResult {
        await decideMemoryWritebackCandidateViaRust(
            action: "approve",
            memoryId: memoryId,
            payload: payload,
            timeoutSec: timeoutSec
        )
    }

    static func rejectMemoryWritebackCandidateViaRust(
        memoryId: String,
        payload: MemoryWritebackCandidateDecisionPayload,
        timeoutSec: Double = 0.75
    ) async -> MemoryWritebackCandidateDecisionResult {
        await decideMemoryWritebackCandidateViaRust(
            action: "reject",
            memoryId: memoryId,
            payload: payload,
            timeoutSec: timeoutSec
        )
    }

    private static func decideMemoryWritebackCandidateViaRust(
        action: String,
        memoryId: String,
        payload: MemoryWritebackCandidateDecisionPayload,
        timeoutSec: Double
    ) async -> MemoryWritebackCandidateDecisionResult {
        let normalizedAction = action == "reject" ? "reject" : "approve"
        let normalizedMemoryId = memoryId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMemoryId.isEmpty else {
            return MemoryWritebackCandidateDecisionResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_request_invalid",
                memoryId: nil,
                reasonCode: "memory_writeback_candidate_id_required",
                action: normalizedAction,
                productionAuthorityChange: false,
                detail: "memory_id is required"
            )
        }
        if let override = memoryWritebackCandidateDecisionOverride() {
            return await override(normalizedAction, normalizedMemoryId, payload, timeoutSec)
        }

        let url = RustHubReadinessClient.defaultBaseURL()
            .appendingPathComponent("memory")
            .appendingPathComponent("writeback")
            .appendingPathComponent("candidates")
            .appendingPathComponent(normalizedMemoryId)
            .appendingPathComponent(normalizedAction)

        do {
            let body = try JSONEncoder().encode(payload)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = max(0.1, min(2.0, timeoutSec))
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            RustHubHTTPAccess.applyAccessKey(to: &request)

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if var decoded = try? JSONDecoder().decode(MemoryWritebackCandidateDecisionResult.self, from: data) {
                decoded.source = normalized(decoded.source) ?? "rust_http"
                decoded.memoryId = normalized(decoded.memoryId) ?? normalizedMemoryId
                decoded.action = normalized(decoded.action) ?? normalizedAction
                decoded.reasonCode = normalizedReasonCode(
                    decoded.reasonCode ?? decoded.errorCode ?? decoded.denyCode,
                    fallback: decoded.ok && (200..<300).contains(statusCode)
                        ? nil
                        : "memory_writeback_candidate_\(normalizedAction)_rust_http_failed"
                )
                if decoded.productionAuthorityChange == nil {
                    decoded.productionAuthorityChange = false
                }
                if decoded.detail == nil {
                    decoded.detail = memoryWritebackCandidateDecisionDetail(decoded, httpStatus: statusCode)
                }
                return decoded
            }

            return MemoryWritebackCandidateDecisionResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_decode_failed",
                memoryId: normalizedMemoryId,
                reasonCode: "memory_writeback_candidate_\(normalizedAction)_decode_failed",
                action: normalizedAction,
                productionAuthorityChange: false,
                detail: "http_status=\(statusCode)"
            )
        } catch {
            return MemoryWritebackCandidateDecisionResult(
                ok: false,
                source: "rust_http",
                status: "rust_http_unavailable",
                memoryId: normalizedMemoryId,
                reasonCode: "memory_writeback_candidate_\(normalizedAction)_rust_http_unavailable",
                action: normalizedAction,
                productionAuthorityChange: false,
                detail: summarized(error)
            )
        }
    }

    static func retryPendingProjectCanonicalRustSync(
        ctx: AXProjectContext
    ) async -> ProjectCanonicalMemoryPendingRustSyncRetryResult {
        let url = pendingProjectCanonicalRustSyncURL(projectRoot: ctx.root)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ProjectCanonicalMemoryPendingRustSyncRetryResult(
                attempted: false,
                ok: true,
                source: "local_file",
                deliveryState: "no_pending_project_canonical_rust_sync"
            )
        }

        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(
                ProjectCanonicalMemoryPendingRustSyncSnapshot.self,
                from: data
              ) else {
            return ProjectCanonicalMemoryPendingRustSyncRetryResult(
                attempted: false,
                ok: false,
                source: "local_file",
                deliveryState: "pending_snapshot_decode_failed",
                reasonCode: "pending_project_canonical_rust_sync_decode_failed",
                detail: url.path
            )
        }

        guard snapshot.schemaVersion == ProjectCanonicalMemoryPendingRustSyncSnapshot.schemaVersion else {
            return ProjectCanonicalMemoryPendingRustSyncRetryResult(
                attempted: false,
                ok: false,
                source: "local_file",
                deliveryState: "pending_snapshot_schema_mismatch",
                reasonCode: "pending_project_canonical_rust_sync_schema_mismatch",
                detail: snapshot.schemaVersion
            )
        }

        let expectedProjectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        guard snapshot.projectId == expectedProjectId,
              snapshot.payload.projectId == expectedProjectId else {
            return ProjectCanonicalMemoryPendingRustSyncRetryResult(
                attempted: false,
                ok: false,
                source: "local_file",
                deliveryState: "pending_snapshot_project_mismatch",
                reasonCode: "pending_project_canonical_rust_sync_project_mismatch",
                detail: "expected=\(expectedProjectId) snapshot=\(snapshot.projectId) payload=\(snapshot.payload.projectId)"
            )
        }

        let result = await syncProjectCanonicalMemoryViaRustHub(payload: snapshot.payload)
            ?? CanonicalMemorySyncDispatchResult(
                ok: false,
                source: "rust_http",
                deliveryState: "rust_http_unavailable",
                reasonCode: "project_canonical_memory_rust_http_unavailable",
                detail: "Rust project canonical sync route unavailable"
            )

        if result.ok {
            await invalidateProjectRemoteMemorySnapshotCache(
                projectId: snapshot.payload.projectId,
                reason: .projectCanonicalSave
            )
            clearPendingProjectCanonicalRustSync(payload: snapshot.payload)
        } else if shouldPersistPendingProjectCanonicalRustSync(result: result) {
            recordPendingProjectCanonicalRustSync(payload: snapshot.payload, result: result)
        } else {
            clearPendingProjectCanonicalRustSync(payload: snapshot.payload)
        }
        recordCanonicalMemorySyncStatus(
            scopeKind: "project",
            scopeId: snapshot.payload.projectId,
            displayName: snapshot.payload.displayName,
            result: result
        )

        return ProjectCanonicalMemoryPendingRustSyncRetryResult(
            attempted: true,
            ok: result.ok,
            source: normalized(result.source) ?? "rust_http",
            deliveryState: normalized(result.deliveryState),
            reasonCode: normalizedReasonCode(
                result.reasonCode,
                fallback: result.ok ? nil : "project_canonical_memory_rust_http_failed"
            ),
            detail: normalized(result.detail)
        )
    }

    private static func shouldPersistPendingProjectCanonicalRustSync(
        result: CanonicalMemorySyncDispatchResult
    ) -> Bool {
        guard !result.ok else { return false }
        let deliveryState = normalized(result.deliveryState)?.lowercased()
        let reasonCode = normalizedReasonCode(result.reasonCode, fallback: nil)
        return deliveryState == "rust_http_unavailable"
            || reasonCode == "project_canonical_memory_rust_http_unavailable"
    }

    @discardableResult
    private static func recordPendingProjectCanonicalRustSync(
        payload: ProjectCanonicalMemoryPayload,
        result: CanonicalMemorySyncDispatchResult
    ) -> Bool {
        guard let url = pendingProjectCanonicalRustSyncURL(payload: payload) else {
            return false
        }
        let snapshot = ProjectCanonicalMemoryPendingRustSyncSnapshot(
            schemaVersion: ProjectCanonicalMemoryPendingRustSyncSnapshot.schemaVersion,
            projectId: payload.projectId,
            projectRoot: normalized(payload.projectRoot) ?? "",
            displayName: normalized(payload.displayName) ?? "",
            recordedAtMs: max(0, Int64((Date().timeIntervalSince1970 * 1_000.0).rounded())),
            memoryUpdatedAt: payload.updatedAt,
            source: normalized(result.source) ?? "rust_http",
            deliveryState: normalized(result.deliveryState) ?? "rust_http_unavailable",
            reasonCode: normalizedReasonCode(
                result.reasonCode,
                fallback: "project_canonical_memory_rust_http_unavailable"
            ) ?? "project_canonical_memory_rust_http_unavailable",
            detail: normalized(result.detail) ?? "",
            itemCount: payload.items.count,
            payload: payload
        )
        return writeLocalSnapshot(snapshot, to: url)
    }

    private static func clearPendingProjectCanonicalRustSync(
        payload: ProjectCanonicalMemoryPayload
    ) {
        guard let url = pendingProjectCanonicalRustSyncURL(payload: payload),
              FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    private static func pendingProjectCanonicalRustSyncURL(
        payload: ProjectCanonicalMemoryPayload
    ) -> URL? {
        guard let projectRoot = normalized(payload.projectRoot) else {
            return nil
        }
        return pendingProjectCanonicalRustSyncURL(
            projectRoot: URL(fileURLWithPath: projectRoot, isDirectory: true)
        )
    }

    private static func pendingProjectCanonicalRustSyncURL(
        projectRoot: URL
    ) -> URL {
        projectRoot
            .appendingPathComponent(".xterminal", isDirectory: true)
            .appendingPathComponent("memory_lifecycle", isDirectory: true)
            .appendingPathComponent("pending_project_canonical_rust_sync.json")
    }

    private static func writeProjectSyncViaFileIPC(_ payload: ProjectSyncPayload) -> Bool {
        guard let dir = fileIPCEventsDir() else { return false }
        let reqId = UUID().uuidString
        let req = IPCRequest(type: "project_sync", reqId: reqId, project: payload)
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(req) else { return false }
        return writeEvent(data: data, reqId: reqId, filePrefix: "xterminal", tmpPrefix: ".xterminal", in: dir)
    }

    private static func writeProjectCanonicalMemoryViaLocalIPC(
        _ payload: ProjectCanonicalMemoryPayload
    ) -> CanonicalMemorySyncDispatchResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return CanonicalMemorySyncDispatchResult(
                ok: false,
                source: "local_ipc",
                deliveryState: "local_ipc_unavailable",
                reasonCode: "project_canonical_memory_local_ipc_unavailable",
                detail: "project canonical memory local IPC unavailable"
            )
        }

        let reqId = UUID().uuidString
        let req = ProjectCanonicalMemoryIPCRequest(
            type: "project_canonical_memory",
            reqId: reqId,
            projectCanonicalMemory: payload
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(req) else {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: "file_ipc",
                    deliveryState: "local_file_ipc_encode_failed",
                    reasonCode: "project_canonical_memory_encode_failed",
                    detail: "project canonical memory request encoding failed"
                )
            }
            let writeStatus = writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_project_memory",
                tmpPrefix: ".xterminal_project_memory",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: "file_ipc",
                    deliveryState: "local_file_ipc_write_failed",
                    reasonCode: "project_canonical_memory_write_failed",
                    detail: normalized(writeStatus.requestError)
                )
            }
            return CanonicalMemorySyncDispatchResult(
                ok: true,
                source: "file_ipc",
                deliveryState: "queued_local_file_ipc"
            )
        case "socket":
            guard let ack: AckIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: "socket_ipc",
                    deliveryState: "local_socket_ipc_request_failed",
                    reasonCode: "socket_request_failed",
                    detail: "project canonical memory socket request failed"
                )
            }
            guard ack.ok else {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: "socket_ipc",
                    deliveryState: "local_socket_ipc_rejected",
                    reasonCode: normalizedReasonCode(
                        ack.error,
                        fallback: "project_canonical_memory_ipc_rejected"
                    ),
                    detail: normalized(ack.error)
                )
            }
            return CanonicalMemorySyncDispatchResult(
                ok: true,
                source: "socket_ipc",
                deliveryState: "accepted_local_socket_ipc"
            )
        default:
            return CanonicalMemorySyncDispatchResult(
                ok: false,
                source: "local_ipc",
                deliveryState: "local_ipc_mode_unsupported",
                reasonCode: "unsupported_ipc_mode",
                detail: "project canonical memory local IPC mode unsupported"
            )
        }
    }

    @discardableResult
    private static func syncDeviceCanonicalMemoryViaPreferredRoute(
        payload: DeviceCanonicalMemoryPayload,
        allowFileFallback: Bool
    ) async -> CanonicalMemorySyncDispatchResult {
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.upsertRemoteDeviceCanonicalMemory(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteDeviceCanonicalMemoryPayload(
                    items: payload.items.map { item in
                        HubRemoteCanonicalMemoryItem(key: item.key, value: item.value)
                    }
                )
            )
            if remote.ok {
                await invalidateSupervisorMemoryCache(reason: .reviewGuidanceCarryForwardChanged)
                return CanonicalMemorySyncDispatchResult(
                    ok: true,
                    source: normalized(remote.source) ?? "grpc",
                    deliveryState: "delivered_remote",
                    auditRefs: remote.auditRefs,
                    evidenceRefs: remote.evidenceRefs,
                    writebackRefs: remote.writebackRefs,
                    detail: normalized(remote.logText)
                )
            }
            if !allowFileFallback {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: normalized(remote.source) ?? "grpc",
                    deliveryState: "remote_delivery_failed",
                    auditRefs: remote.auditRefs,
                    evidenceRefs: remote.evidenceRefs,
                    writebackRefs: remote.writebackRefs,
                    reasonCode: normalizedReasonCode(
                        remote.reasonCode,
                        fallback: "device_canonical_memory_remote_failed"
                    ),
                    detail: normalized(remote.logText)
                )
            }
        } else if !allowFileFallback {
            return CanonicalMemorySyncDispatchResult(
                ok: false,
                source: "grpc",
                reasonCode: "hub_not_connected",
                detail: "device canonical memory remote route unavailable"
            )
        }

        let localResult = writeDeviceCanonicalMemoryViaLocalIPC(payload)
        if localResult.ok {
            await invalidateSupervisorMemoryCache(reason: .reviewGuidanceCarryForwardChanged)
        }
        return localResult
    }

    private static func writeDeviceCanonicalMemoryViaLocalIPC(
        _ payload: DeviceCanonicalMemoryPayload
    ) -> CanonicalMemorySyncDispatchResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return CanonicalMemorySyncDispatchResult(
                ok: false,
                source: "local_ipc",
                deliveryState: "local_ipc_unavailable",
                reasonCode: "device_canonical_memory_local_ipc_unavailable",
                detail: "device canonical memory local IPC unavailable"
            )
        }

        let reqId = UUID().uuidString
        let req = DeviceCanonicalMemoryIPCRequest(
            type: "device_canonical_memory",
            reqId: reqId,
            deviceCanonicalMemory: payload
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(req) else {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: "file_ipc",
                    deliveryState: "local_file_ipc_encode_failed",
                    reasonCode: "device_canonical_memory_encode_failed",
                    detail: "device canonical memory request encoding failed"
                )
            }
            let writeStatus = writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_device_memory",
                tmpPrefix: ".xterminal_device_memory",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: "file_ipc",
                    deliveryState: "local_file_ipc_write_failed",
                    reasonCode: "device_canonical_memory_write_failed",
                    detail: normalized(writeStatus.requestError)
                )
            }
            return CanonicalMemorySyncDispatchResult(
                ok: true,
                source: "file_ipc",
                deliveryState: "queued_local_file_ipc"
            )
        case "socket":
            guard let ack: AckIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: "socket_ipc",
                    deliveryState: "local_socket_ipc_request_failed",
                    reasonCode: "socket_request_failed",
                    detail: "device canonical memory socket request failed"
                )
            }
            guard ack.ok else {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: "socket_ipc",
                    deliveryState: "local_socket_ipc_rejected",
                    reasonCode: normalizedReasonCode(
                        ack.error,
                        fallback: "device_canonical_memory_ipc_rejected"
                    ),
                    detail: normalized(ack.error)
                )
            }
            return CanonicalMemorySyncDispatchResult(
                ok: true,
                source: "socket_ipc",
                deliveryState: "accepted_local_socket_ipc"
            )
        default:
            return CanonicalMemorySyncDispatchResult(
                ok: false,
                source: "local_ipc",
                deliveryState: "local_ipc_mode_unsupported",
                reasonCode: "unsupported_ipc_mode",
                detail: "device canonical memory local IPC mode unsupported"
            )
        }
    }

    static func defaultSupervisorCanonicalID() -> String {
        let raw = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let scalars = raw.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let token = String(String.UnicodeScalarView(scalars))
        return token.isEmpty ? "supervisor-main" : "supervisor-\(token)"
    }

    @discardableResult
    private static func pushNotificationViaPreferredRoute(
        payload: NotificationPayload,
        allowFileFallback: Bool
    ) async -> Bool {
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.pushRemoteNotificationMemory(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteNotificationPayload(
                    source: payload.source,
                    title: payload.title,
                    body: payload.body,
                    dedupeKey: payload.dedupeKey,
                    actionURL: payload.actionURL,
                    unread: payload.unread
                )
            )
            if remote.ok {
                return true
            }
            if !allowFileFallback {
                return false
            }
        } else if !allowFileFallback {
            return false
        }

        return writeNotificationViaFileIPC(payload)
    }

    private static func writeNotificationViaFileIPC(_ payload: NotificationPayload) -> Bool {
        guard let dir = fileIPCEventsDir() else { return false }
        let reqId = UUID().uuidString
        let req = NotificationIPCRequest(type: "push_notification", reqId: reqId, notification: payload)
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(req) else { return false }
        return writeEvent(data: data, reqId: reqId, filePrefix: "xterminal_notify", tmpPrefix: ".xterminal_notify", in: dir)
    }

    @discardableResult
    private static func removeNotificationViaLocalIPC(
        dedupeKey: String?,
        id: String?
    ) -> Bool {
        let normalizedDedupeKey = dedupeKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedDedupeKey.isEmpty || !normalizedID.isEmpty else { return false }
        guard let transport = localIPCTransport(ttl: 3.0) else { return false }

        let reqId = UUID().uuidString
        let req = NotificationDismissIPCRequest(
            type: "remove_notification",
            reqId: reqId,
            notificationDismiss: NotificationDismissPayload(
                id: normalizedID.isEmpty ? nil : normalizedID,
                dedupeKey: normalizedDedupeKey.isEmpty ? nil : normalizedDedupeKey
            )
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(req) else { return false }
            let status = writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_notify_remove",
                tmpPrefix: ".xterminal_notify_remove",
                in: transport.ipcURL
            )
            return status.requestQueued == true
        case "socket":
            guard let ack: AckIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return false
            }
            return ack.ok
        default:
            return false
        }
    }

    static func requestMemoryContext(
        useMode: XTMemoryUseMode,
        requesterRole: XTMemoryRequesterRole,
        projectId: String?,
        projectRoot: String?,
        displayName: String?,
        latestUser: String,
        reviewLevelHint: String? = nil,
        constitutionHint: String?,
        dialogueWindowText: String? = nil,
        portfolioBriefText: String? = nil,
        focusedProjectAnchorPackText: String? = nil,
        longtermOutlineText: String? = nil,
        deltaFeedText: String? = nil,
        conflictSetText: String? = nil,
        contextRefsText: String? = nil,
        evidencePackText: String? = nil,
        canonicalText: String?,
        observationsText: String?,
        workingSetText: String?,
        rawEvidenceText: String?,
        servingProfile: XTMemoryServingProfile? = nil,
        progressiveDisclosure: Bool = false,
        budgets: MemoryContextBudgets? = nil,
        timeoutSec: Double = 1.2
    ) async -> MemoryContextResponsePayload? {
        let result = await requestMemoryContextDetailed(
            useMode: useMode,
            requesterRole: requesterRole,
            projectId: projectId,
            projectRoot: projectRoot,
            displayName: displayName,
            latestUser: latestUser,
            reviewLevelHint: reviewLevelHint,
            constitutionHint: constitutionHint,
            dialogueWindowText: dialogueWindowText,
            portfolioBriefText: portfolioBriefText,
            focusedProjectAnchorPackText: focusedProjectAnchorPackText,
            longtermOutlineText: longtermOutlineText,
            deltaFeedText: deltaFeedText,
            conflictSetText: conflictSetText,
            contextRefsText: contextRefsText,
            evidencePackText: evidencePackText,
            canonicalText: canonicalText,
            observationsText: observationsText,
            workingSetText: workingSetText,
            rawEvidenceText: rawEvidenceText,
            servingProfile: servingProfile,
            progressiveDisclosure: progressiveDisclosure,
            budgets: budgets,
            timeoutSec: timeoutSec
        )
        return result.response
    }

    struct MemoryLongtermDisclosure: Equatable {
        var longtermMode: String
        var retrievalAvailable: Bool
        var fulltextNotLoaded: Bool
        var policyCode: String?
        var stage0: String?
        var stage1: String?
        var stage2: String?
        var stage1Rule: String?
        var stage2Rule: String?
    }

    struct MemoryRetrievalRequest: Equatable, Sendable {
        var requesterRole: XTMemoryRequesterRole
        var useMode: XTMemoryUseMode
        var scope: String = "current_project"
        var projectId: String?
        var crossProjectTargetIds: [String] = []
        var projectRoot: String?
        var displayName: String?
        var query: String
        var reason: String?
        var requestedKinds: [String] = []
        var explicitRefs: [String] = []
        var allowedLayers: [XTMemoryLayer] = []
        var retrievalKind: String? = nil
        var maxResults: Int = 3
        var maxSnippetChars: Int = 420
        var requireExplainability: Bool = true
    }

    static func defaultRetrievalAvailability(for useMode: XTMemoryUseMode) -> Bool {
        switch useMode {
        case .projectChat, .supervisorOrchestration, .toolPlan:
            return true
        default:
            return false
        }
    }

    static func resolveMemoryLongtermDisclosure(
        useMode: XTMemoryUseMode,
        retrievalAvailable fallbackRetrievalAvailable: Bool,
        overrideLongtermMode: String? = nil,
        overrideRetrievalAvailable: Bool? = nil,
        overrideFulltextNotLoaded: Bool? = nil
    ) -> MemoryLongtermDisclosure {
        let policy = XTMemoryRoleScopedRouter.contract(for: useMode).longtermPolicy
        let retrievalAvailable = overrideRetrievalAvailable ?? fallbackRetrievalAvailable
        let defaultLongtermMode: String
        switch policy {
        case .progressiveDisclosureRequired where retrievalAvailable:
            defaultLongtermMode = "progressive_disclosure"
        case .denied:
            defaultLongtermMode = XTMemoryLongtermPolicy.denied.rawValue
        default:
            defaultLongtermMode = XTMemoryLongtermPolicy.summaryOnly.rawValue
        }
        let resolvedMode = normalized(overrideLongtermMode) ?? defaultLongtermMode
        let enableStageRules = policy == .progressiveDisclosureRequired || resolvedMode == "progressive_disclosure"

        return MemoryLongtermDisclosure(
            longtermMode: resolvedMode,
            retrievalAvailable: retrievalAvailable,
            fulltextNotLoaded: overrideFulltextNotLoaded ?? true,
            policyCode: policy.rawValue,
            stage0: enableStageRules ? "outline_summary" : nil,
            stage1: enableStageRules ? "related_snippets" : nil,
            stage2: enableStageRules ? "explicit_ref_read_only" : nil,
            stage1Rule: enableStageRules ? "state_summary_insufficient_before_requesting_snippets" : nil,
            stage2Rule: enableStageRules ? "explicit_ref_required_before_ref_read" : nil
        )
    }

    static func ensureMemoryLongtermDisclosureText(
        _ text: String,
        disclosure: MemoryLongtermDisclosure
    ) -> String {
        var sectionLines = [
            "[LONGTERM_MEMORY]",
            "longterm_mode=\(disclosure.longtermMode)",
            "retrieval_available=\(disclosure.retrievalAvailable ? "true" : "false")",
            "fulltext_not_loaded=\(disclosure.fulltextNotLoaded ? "true" : "false")"
        ]
        if let policyCode = normalized(disclosure.policyCode) {
            sectionLines.append("policy=\(policyCode)")
        }
        if let stage0 = normalized(disclosure.stage0) {
            sectionLines.append("stage_0=\(stage0)")
        }
        if let stage1 = normalized(disclosure.stage1) {
            sectionLines.append("stage_1=\(stage1)")
        }
        if let stage2 = normalized(disclosure.stage2) {
            sectionLines.append("stage_2=\(stage2)")
        }
        if let stage1Rule = normalized(disclosure.stage1Rule) {
            sectionLines.append("stage_1_rule=\(stage1Rule)")
        }
        if let stage2Rule = normalized(disclosure.stage2Rule) {
            sectionLines.append("stage_2_rule=\(stage2Rule)")
        }
        sectionLines.append("[/LONGTERM_MEMORY]")
        let section = sectionLines.joined(separator: "\n")

        if let start = text.range(of: "[LONGTERM_MEMORY]"),
           let end = text.range(of: "[/LONGTERM_MEMORY]"),
           start.lowerBound <= end.lowerBound {
            return String(text[..<start.lowerBound]) + section + String(text[end.upperBound...])
        }

        if let range = text.range(of: "[/SERVING_PROFILE]\n") {
            return String(text[..<range.upperBound]) + section + "\n" + String(text[range.upperBound...])
        }
        if let range = text.range(of: "[MEMORY_V1]\n") {
            return String(text[..<range.upperBound]) + section + "\n" + String(text[range.upperBound...])
        }
        return section + "\n" + text
    }

    static func requestMemoryContextDetailed(
        useMode: XTMemoryUseMode,
        requesterRole: XTMemoryRequesterRole,
        projectId: String?,
        projectRoot: String?,
        displayName: String?,
        latestUser: String,
        reviewLevelHint: String? = nil,
        constitutionHint: String?,
        dialogueWindowText: String? = nil,
        portfolioBriefText: String? = nil,
        focusedProjectAnchorPackText: String? = nil,
        longtermOutlineText: String? = nil,
        deltaFeedText: String? = nil,
        conflictSetText: String? = nil,
        contextRefsText: String? = nil,
        evidencePackText: String? = nil,
        canonicalText: String?,
        observationsText: String?,
        workingSetText: String?,
        rawEvidenceText: String?,
        servingProfile: XTMemoryServingProfile? = nil,
        progressiveDisclosure: Bool = false,
        budgets: MemoryContextBudgets? = nil,
        timeoutSec: Double = 1.2
    ) async -> MemoryContextResolutionResult {
        let rawPayload = MemoryContextPayload(
            mode: useMode.rawValue,
            projectId: normalized(projectId),
            projectRoot: normalized(projectRoot),
            displayName: normalized(displayName),
            latestUser: latestUser,
            reviewLevelHint: normalizedReviewLevelHint(reviewLevelHint),
            constitutionHint: normalized(constitutionHint),
            dialogueWindowText: normalized(dialogueWindowText),
            portfolioBriefText: normalized(portfolioBriefText),
            focusedProjectAnchorPackText: normalized(focusedProjectAnchorPackText),
            longtermOutlineText: normalized(longtermOutlineText),
            deltaFeedText: normalized(deltaFeedText),
            conflictSetText: normalized(conflictSetText),
            contextRefsText: normalized(contextRefsText),
            evidencePackText: normalized(evidencePackText),
            canonicalText: normalized(canonicalText),
            observationsText: normalized(observationsText),
            workingSetText: normalized(workingSetText),
            rawEvidenceText: normalized(rawEvidenceText),
            servingProfile: servingProfile?.rawValue,
            budgets: budgets
        )
        let targetRoute = XTMemoryRoleScopedRouter.route(
            role: requesterRole,
            mode: useMode,
            payload: rawPayload
        )
        let requestedProfile = targetRoute.servingProfile.rawValue
        if let denyCode = targetRoute.denyCode?.rawValue {
            return MemoryContextResolutionResult(
                response: nil,
                source: "memory_router",
                resolvedMode: useMode,
                requestedProfile: requestedProfile,
                attemptedProfiles: [requestedProfile],
                freshness: "unavailable",
                cacheHit: false,
                denyCode: denyCode,
                downgradeCode: targetRoute.downgradeCode?.rawValue,
                reasonCode: denyCode
            )
        }
        let progressiveProfiles = progressiveDisclosureProfiles(
            enabled: progressiveDisclosure,
            mode: useMode,
            targetProfile: targetRoute.servingProfile,
            reviewLevelHint: rawPayload.reviewLevelHint,
            hasFocusedProjectAnchor: normalized(rawPayload.focusedProjectAnchorPackText) != nil
        )
        var attemptedProfiles: [String] = []
        var lastResult: MemoryContextResolutionResult?

        for profile in progressiveProfiles {
            var stagedPayload = rawPayload
            stagedPayload.servingProfile = profile.rawValue
            let stagedRoute = XTMemoryRoleScopedRouter.route(
                role: requesterRole,
                mode: useMode,
                payload: stagedPayload
            )
            let single = await requestMemoryContextSingleDetailed(
                useMode: useMode,
                requesterRole: requesterRole,
                route: stagedRoute,
                timeoutSec: timeoutSec
            )
            attemptedProfiles.append(stagedRoute.servingProfile.rawValue)
            let enriched = enrichProgressiveMemoryContextResult(
                single,
                requestedProfile: requestedProfile,
                attemptedProfiles: attemptedProfiles
            )
            lastResult = enriched
            guard let response = enriched.response else {
                return enriched
            }
            if !shouldUpgradeMemoryContextProgressively(
                response: response,
                currentProfile: stagedRoute.servingProfile,
                targetProfile: targetRoute.servingProfile
            ) {
                return enriched
            }
        }

        return lastResult ?? MemoryContextResolutionResult(
            response: nil,
            source: "memory_router",
            resolvedMode: useMode,
            requestedProfile: requestedProfile,
            attemptedProfiles: attemptedProfiles.isEmpty ? [requestedProfile] : attemptedProfiles,
            freshness: "unavailable",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: "memory_context_unavailable"
        )
    }

    private static func memoryContextPayloadByPreferringRustProjectCanonicalObjects(
        _ payload: MemoryContextPayload,
        routeDecision: HubRouteDecision,
        timeoutSec: Double
    ) async -> MemoryContextPayload {
        guard routeDecision.mode != .fileIPC,
              let projectId = normalized(payload.projectId),
              hasSuccessfulRustProjectCanonicalSync(projectId: projectId),
              let snapshot = await fetchRustProjectCanonicalMemorySnapshot(
                projectId: projectId,
                limit: 64,
                timeoutSec: timeoutSec
              ),
              !snapshot.objects.isEmpty else {
            return payload
        }

        let layers = rustProjectCanonicalMemoryLayerTexts(snapshot.objects)
        var enriched = payload
        if let canonical = mergedRustPrimaryMemoryLayer(
            rustPrimary: layers.canonical,
            localSecondary: payload.canonicalText
        ) {
            enriched.canonicalText = canonical
        }
        if let observations = mergedRustPrimaryMemoryLayer(
            rustPrimary: layers.observations,
            localSecondary: payload.observationsText
        ) {
            enriched.observationsText = observations
        }
        if let workingSet = mergedRustPrimaryMemoryLayer(
            rustPrimary: layers.workingSet,
            localSecondary: payload.workingSetText
        ) {
            enriched.workingSetText = workingSet
        }
        return enriched
    }

    static func hasSuccessfulRustProjectCanonicalSync(projectId: String) -> Bool {
        let normalizedProjectId = normalized(projectId) ?? ""
        guard !normalizedProjectId.isEmpty,
              let item = canonicalMemorySyncStatusSnapshot(limit: 500)?.items.first(where: {
                $0.scopeKind.lowercased() == "project"
                    && $0.scopeId == normalizedProjectId
              }),
              item.ok else {
            return false
        }
        let source = normalized(item.source)?.lowercased()
        let deliveryState = normalized(item.deliveryState)?.lowercased()
        return source == "rust_http"
            && (
                deliveryState == nil
                || deliveryState == "delivered_rust_memory_objects"
                || deliveryState == "accepted_rust_memory_objects"
            )
    }

    private static func expectedRustProjectCanonicalObjects(
        payload: ProjectCanonicalMemoryPayload
    ) -> (objects: [ProjectCanonicalRustExpectedObject], skippedMetadataCount: Int) {
        var expected: [ProjectCanonicalRustExpectedObject] = []
        var skipped = 0
        for item in payload.items {
            guard let mapping = rustProjectCanonicalMapping(forKey: item.key),
                  let text = normalized(item.value) else {
                skipped += 1
                continue
            }
            expected.append(
                ProjectCanonicalRustExpectedObject(
                    key: item.key,
                    suffix: mapping.suffix,
                    memoryId: rustProjectCanonicalMemoryID(
                        projectId: payload.projectId,
                        suffix: mapping.suffix
                    ),
                    sourceKind: mapping.sourceKind,
                    layer: mapping.layer,
                    title: mapping.title,
                    text: text
                )
            )
        }
        return (expected, skipped)
    }

    private static func projectCanonicalRustImportDiagnostics(
        payload: ProjectCanonicalMemoryPayload,
        displayName: String,
        expected: [ProjectCanonicalRustExpectedObject],
        skippedMetadataCount: Int,
        rustSnapshot: RustProjectCanonicalMemorySnapshot
    ) -> ProjectCanonicalRustImportDiagnostics {
        let rustByMemoryID = Dictionary(
            uniqueKeysWithValues: rustSnapshot.objects.map { ($0.memoryId, $0) }
        )
        let expectedIDs = Set(expected.map(\.memoryId))
        var issues: [ProjectCanonicalRustImportDiagnosticIssue] = []
        var matchedCount = 0
        var missingCount = 0
        var staleCount = 0
        var mismatchCount = 0

        for item in expected {
            guard let object = rustByMemoryID[item.memoryId] else {
                missingCount += 1
                issues.append(
                    ProjectCanonicalRustImportDiagnosticIssue(
                        severity: "error",
                        reasonCode: "rust_project_canonical_object_missing",
                        key: item.key,
                        memoryId: item.memoryId,
                        detail: "missing active Rust memory object"
                    )
                )
                continue
            }

            var itemHasIssue = false
            if normalized(object.text) != normalized(item.text) {
                staleCount += 1
                itemHasIssue = true
                issues.append(
                    ProjectCanonicalRustImportDiagnosticIssue(
                        severity: "warning",
                        reasonCode: "rust_project_canonical_object_stale",
                        key: item.key,
                        memoryId: item.memoryId,
                        detail: "Rust text differs from current AXMemory projection"
                    )
                )
            }
            if normalized(object.sourceKind)?.lowercased() != item.sourceKind
                || normalized(object.layer)?.lowercased() != item.layer {
                mismatchCount += 1
                itemHasIssue = true
                issues.append(
                    ProjectCanonicalRustImportDiagnosticIssue(
                        severity: "warning",
                        reasonCode: "rust_project_canonical_object_metadata_mismatch",
                        key: item.key,
                        memoryId: item.memoryId,
                        detail: "expected source_kind=\(item.sourceKind) layer=\(item.layer), got source_kind=\(object.sourceKind) layer=\(object.layer)"
                    )
                )
            }
            if !itemHasIssue {
                matchedCount += 1
            }
        }

        let projectPrefix = rustProjectCanonicalMemoryIDPrefix(projectId: payload.projectId)
        let extraObjects = rustSnapshot.objects.filter { object in
            object.memoryId.hasPrefix(projectPrefix) && !expectedIDs.contains(object.memoryId)
        }
        for object in extraObjects {
            issues.append(
                ProjectCanonicalRustImportDiagnosticIssue(
                    severity: "info",
                    reasonCode: "rust_project_canonical_object_extra",
                    key: nil,
                    memoryId: object.memoryId,
                    detail: "active Rust object is not present in current AXMemory projection"
                )
            )
        }

        let ok = missingCount == 0 && staleCount == 0 && mismatchCount == 0
        return ProjectCanonicalRustImportDiagnostics(
            ok: ok,
            source: "rust_memory_objects",
            projectId: payload.projectId,
            displayName: displayName,
            expectedItemCount: expected.count,
            skippedMetadataCount: skippedMetadataCount,
            rustObjectCount: rustSnapshot.objects.count,
            matchedCount: matchedCount,
            missingCount: missingCount,
            staleCount: staleCount,
            mismatchCount: mismatchCount,
            extraCount: extraObjects.count,
            reasonCode: ok ? nil : "rust_project_canonical_import_drift",
            issues: issues
        )
    }

    static func fetchRustProjectCanonicalMemorySnapshot(
        projectId: String,
        limit: Int,
        timeoutSec: Double
    ) async -> RustProjectCanonicalMemorySnapshot? {
        let boundedLimit = max(1, min(128, limit))
        if let override = rustProjectCanonicalMemoryOverride() {
            return await override(projectId, boundedLimit, timeoutSec)
        }

        let baseURL = RustHubReadinessClient.defaultBaseURL()
        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("memory")
                .appendingPathComponent("objects"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "scope", value: "project"),
            URLQueryItem(name: "project_id", value: projectId),
            URLQueryItem(name: "status", value: "active"),
            URLQueryItem(name: "limit", value: "\(boundedLimit)")
        ]
        guard let url = components?.url else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = max(0.05, min(0.75, timeoutSec))
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            RustHubHTTPAccess.applyAccessKey(to: &request)
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(RustProjectCanonicalMemoryListResponse.self, from: data)
            guard decoded.ok else {
                return nil
            }
            let activeObjects = decoded.objects.filter { object in
                let objectProjectId = normalized(object.projectId) ?? normalized(object.ownerId) ?? ""
                let status = normalized(object.status)?.lowercased() ?? "active"
                let scope = normalized(object.scope)?.lowercased()
                let layer = normalized(object.layer)?.lowercased() ?? ""
                return objectProjectId == projectId
                    && (scope == nil || scope == "project")
                    && status == "active"
                    && ["l1_canonical", "l2_observations", "l3_working_set"].contains(layer)
            }
            return RustProjectCanonicalMemorySnapshot(
                source: "rust_http",
                projectId: projectId,
                objects: activeObjects
            )
        } catch {
            return nil
        }
    }

    private static func rustProjectCanonicalMemoryLayerTexts(
        _ objects: [RustProjectCanonicalMemoryObject]
    ) -> (canonical: String, observations: String, workingSet: String) {
        let sorted = objects.sorted { lhs, rhs in
            let lhsLayerRank = rustProjectCanonicalMemoryLayerRank(lhs.layer)
            let rhsLayerRank = rustProjectCanonicalMemoryLayerRank(rhs.layer)
            if lhsLayerRank != rhsLayerRank { return lhsLayerRank < rhsLayerRank }
            let lhsSourceRank = rustProjectCanonicalMemorySourceRank(lhs.sourceKind)
            let rhsSourceRank = rustProjectCanonicalMemorySourceRank(rhs.sourceKind)
            if lhsSourceRank != rhsSourceRank { return lhsSourceRank < rhsSourceRank }
            let lhsTitle = normalized(lhs.title) ?? lhs.memoryId
            let rhsTitle = normalized(rhs.title) ?? rhs.memoryId
            return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
        }

        var canonical: [String] = []
        var observations: [String] = []
        var workingSet: [String] = []
        for object in sorted {
            guard let block = rustProjectCanonicalMemoryBlock(object) else { continue }
            switch normalized(object.layer)?.lowercased() {
            case "l1_canonical":
                canonical.append(block)
            case "l2_observations":
                observations.append(block)
            case "l3_working_set":
                workingSet.append(block)
            default:
                continue
            }
        }

        return (
            XTMemorySanitizer.sanitizeText(canonical.joined(separator: "\n\n"), maxChars: 3_200, lineCap: 36) ?? "",
            XTMemorySanitizer.sanitizeText(observations.joined(separator: "\n\n"), maxChars: 1_800, lineCap: 24) ?? "",
            XTMemorySanitizer.sanitizeText(workingSet.joined(separator: "\n\n"), maxChars: 2_600, lineCap: 28) ?? ""
        )
    }

    private static func rustProjectCanonicalMemoryBlock(
        _ object: RustProjectCanonicalMemoryObject
    ) -> String? {
        guard let text = normalized(object.text) else { return nil }
        guard let title = normalized(object.title) else { return text }
        return """
\(title):
\(text)
"""
    }

    private static func mergedRustPrimaryMemoryLayer(
        rustPrimary: String,
        localSecondary: String?
    ) -> String? {
        guard let rust = normalized(rustPrimary) else {
            return normalized(localSecondary)
        }
        guard let local = normalized(localSecondary),
              local != rust else {
            return rust
        }
        return """
\(rust)

[local_projection]
\(local)
[/local_projection]
"""
    }

    private static func rustProjectCanonicalMemoryLayerRank(_ layer: String) -> Int {
        switch normalized(layer)?.lowercased() {
        case "l1_canonical":
            return 1
        case "l2_observations":
            return 2
        case "l3_working_set":
            return 3
        default:
            return 99
        }
    }

    static func rustProjectCanonicalMemorySourceRank(_ sourceKind: String) -> Int {
        switch normalized(sourceKind)?.lowercased() {
        case "project_goal":
            return 1
        case "project_requirement":
            return 2
        case "decision_track":
            return 3
        case "open_question":
            return 4
        case "risk":
            return 5
        case "recommendation":
            return 6
        case "current_state":
            return 7
        case "next_step":
            return 8
        default:
            return 99
        }
    }

    private static func rustProjectCanonicalMapping(
        forKey rawKey: String
    ) -> (suffix: String, title: String, sourceKind: String, layer: String)? {
        let prefix = "\(XTProjectCanonicalMemorySync.keyPrefix)."
        let suffix = rawKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: prefix, with: "")
        switch suffix {
        case "goal":
            return ("goal", "Project goal", "project_goal", "l1_canonical")
        case "requirements":
            return ("requirements", "Project requirements", "project_requirement", "l1_canonical")
        case "current_state":
            return ("current_state", "Current state", "current_state", "l3_working_set")
        case "decisions":
            return ("decisions", "Decisions", "decision_track", "l1_canonical")
        case "next_steps":
            return ("next_steps", "Next steps", "next_step", "l3_working_set")
        case "open_questions":
            return ("open_questions", "Open questions", "open_question", "l2_observations")
        case "risks":
            return ("risks", "Risks", "risk", "l2_observations")
        case "recommendations":
            return ("recommendations", "Recommendations", "recommendation", "l2_observations")
        default:
            return nil
        }
    }

    private static func rustProjectCanonicalMemoryID(
        projectId: String,
        suffix: String
    ) -> String {
        "\(rustProjectCanonicalMemoryIDPrefix(projectId: projectId))\(rustProjectCanonicalIDSegment(suffix, maxChars: 64))"
    }

    private static func rustProjectCanonicalMemoryIDPrefix(projectId: String) -> String {
        "mem_xt_project_\(rustProjectCanonicalIDSegment(projectId, maxChars: 80))_"
    }

    private static func rustProjectCanonicalIDSegment(
        _ raw: String,
        maxChars: Int
    ) -> String {
        var value = ""
        for scalar in raw.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
            let v = scalar.value
            if (65...90).contains(v), let lower = UnicodeScalar(v + 32) {
                value.append(Character(lower))
            } else if (97...122).contains(v)
                || (48...57).contains(v)
                || v == 95
                || v == 45
                || v == 46 {
                value.append(Character(scalar))
            } else {
                value.append("_")
            }
            if value.count >= max(1, maxChars) {
                break
            }
        }
        let text = value.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return text.isEmpty ? "unknown" : text
    }

    private static func requestMemoryContextSingleDetailed(
        useMode: XTMemoryUseMode,
        requesterRole: XTMemoryRequesterRole,
        route: XTMemoryRouteDecision,
        timeoutSec: Double
    ) async -> MemoryContextResolutionResult {
        if let override = memoryContextResolutionOverride() {
            return await override(route, useMode, timeoutSec)
        }

        var payload = route.payload
        let routeDecision = await currentRouteDecision()
        payload = await memoryContextPayloadByPreferringRustProjectCanonicalObjects(
            payload,
            routeDecision: routeDecision,
            timeoutSec: timeoutSec
        )

        if let rustGateway = await requestMemoryContextViaRustGatewayIfEnabled(
            payload: payload,
            route: route,
            routeDecision: routeDecision,
            requesterRole: requesterRole,
            useMode: useMode,
            timeoutSec: timeoutSec
        ) {
            return rustGateway
        }

        if routeDecision.preferRemote {
            let remote = await fetchRemoteMemorySnapshot(
                mode: useMode,
                projectId: payload.projectId,
                bypassCache: route.bypassRemoteCache,
                timeoutSec: timeoutSec
            )
            if remote.snapshot.ok {
                var response = buildMemoryContextFromRemoteSnapshot(snapshot: remote.snapshot, payload: payload)
                let disclosure = resolveMemoryLongtermDisclosure(
                    useMode: useMode,
                    retrievalAvailable: defaultRetrievalAvailability(for: useMode),
                    overrideLongtermMode: response.longtermMode,
                    overrideRetrievalAvailable: response.retrievalAvailable,
                    overrideFulltextNotLoaded: response.fulltextNotLoaded
                )
                response.resolvedMode = useMode.rawValue
                response.resolvedProfile = route.servingProfile.rawValue
                response.longtermMode = disclosure.longtermMode
                response.retrievalAvailable = disclosure.retrievalAvailable
                response.fulltextNotLoaded = disclosure.fulltextNotLoaded
                response.text = ensureMemoryLongtermDisclosureText(response.text, disclosure: disclosure)
                response.freshness = remote.cacheHit ? "ttl_cache" : "fresh_remote"
                response.cacheHit = remote.cacheHit
                response.remoteSnapshotCacheScope = remote.cacheMetadata?.scope
                response.remoteSnapshotCachedAtMs = remote.cacheMetadata?.storedAtMs
                response.remoteSnapshotAgeMs = remote.cacheMetadata?.ageMs
                response.remoteSnapshotTTLRemainingMs = remote.cacheMetadata?.ttlRemainingMs
                response.remoteSnapshotCachePosture = remote.cacheMetadata?.cachePosture.rawValue
                response.remoteSnapshotInvalidationReason = remote.cacheMetadata?.invalidationReason?.rawValue
                response.denyCode = nil
                response.downgradeCode = route.downgradeCode?.rawValue
                scheduleRustMemoryGatewayShadowCompareIfEnabled(
                    productResponse: response,
                    payload: payload,
                    requesterRole: requesterRole,
                    useMode: useMode,
                    timeoutSec: timeoutSec
                )
                return MemoryContextResolutionResult(
                    response: response,
                    source: response.source,
                    resolvedMode: useMode,
                    requestedProfile: route.servingProfile.rawValue,
                    attemptedProfiles: [route.servingProfile.rawValue],
                    freshness: response.freshness ?? "fresh_remote",
                    cacheHit: remote.cacheHit,
                    remoteSnapshotCacheScope: remote.cacheMetadata?.scope,
                    remoteSnapshotCachedAtMs: remote.cacheMetadata?.storedAtMs,
                    remoteSnapshotAgeMs: remote.cacheMetadata?.ageMs,
                    remoteSnapshotTTLRemainingMs: remote.cacheMetadata?.ttlRemainingMs,
                    remoteSnapshotCachePosture: remote.cacheMetadata?.cachePosture.rawValue,
                    remoteSnapshotInvalidationReason: remote.cacheMetadata?.invalidationReason?.rawValue,
                    denyCode: nil,
                    downgradeCode: route.downgradeCode?.rawValue,
                    reasonCode: nil
                )
            }
            if !routeDecision.allowFileFallback {
                return MemoryContextResolutionResult(
                    response: nil,
                    source: remote.snapshot.source,
                    resolvedMode: useMode,
                    requestedProfile: route.servingProfile.rawValue,
                    attemptedProfiles: [route.servingProfile.rawValue],
                    freshness: route.bypassRemoteCache ? "fresh_remote_required" : "remote_failed",
                    cacheHit: remote.cacheHit,
                    remoteSnapshotCacheScope: remote.cacheMetadata?.scope,
                    remoteSnapshotCachedAtMs: remote.cacheMetadata?.storedAtMs,
                    remoteSnapshotAgeMs: remote.cacheMetadata?.ageMs,
                    remoteSnapshotTTLRemainingMs: remote.cacheMetadata?.ttlRemainingMs,
                    remoteSnapshotCachePosture: remote.cacheMetadata?.cachePosture.rawValue,
                    remoteSnapshotInvalidationReason: remote.cacheMetadata?.invalidationReason?.rawValue,
                    denyCode: route.bypassRemoteCache
                        ? XTMemoryUseDenyCode.memorySnapshotStaleForHighRiskAct.rawValue
                        : nil,
                    downgradeCode: nil,
                    reasonCode: normalizedReasonCode(remote.snapshot.reasonCode, fallback: "remote_memory_snapshot_failed")
                )
            }
        }

        if routeDecision.requiresRemote {
            return MemoryContextResolutionResult(
                response: nil,
                source: "hub_memory_v1_grpc",
                resolvedMode: useMode,
                requestedProfile: route.servingProfile.rawValue,
                attemptedProfiles: [route.servingProfile.rawValue],
                freshness: "unavailable",
                cacheHit: false,
                denyCode: route.bypassRemoteCache
                    ? XTMemoryUseDenyCode.memorySnapshotStaleForHighRiskAct.rawValue
                    : nil,
                downgradeCode: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        let local = await requestMemoryContextViaLocalIPC(payload: payload, timeoutSec: timeoutSec)
        guard let localResponse = local.response else {
            return MemoryContextResolutionResult(
                response: nil,
                source: "local_ipc",
                resolvedMode: useMode,
                requestedProfile: route.servingProfile.rawValue,
                attemptedProfiles: [route.servingProfile.rawValue],
                freshness: "unavailable",
                cacheHit: false,
                denyCode: route.bypassRemoteCache
                    ? XTMemoryUseDenyCode.memorySnapshotStaleForHighRiskAct.rawValue
                    : nil,
                downgradeCode: nil,
                reasonCode: local.reasonCode ?? "memory_context_unavailable",
                detail: local.detail
            )
        }

        var response = localResponse
        let disclosure = resolveMemoryLongtermDisclosure(
            useMode: useMode,
            retrievalAvailable: defaultRetrievalAvailability(for: useMode),
            overrideLongtermMode: response.longtermMode,
            overrideRetrievalAvailable: response.retrievalAvailable,
            overrideFulltextNotLoaded: response.fulltextNotLoaded
        )
        response.resolvedMode = useMode.rawValue
        response.resolvedProfile = route.servingProfile.rawValue
        response.longtermMode = disclosure.longtermMode
        response.retrievalAvailable = disclosure.retrievalAvailable
        response.fulltextNotLoaded = disclosure.fulltextNotLoaded
        response.text = ensureMemoryLongtermDisclosureText(response.text, disclosure: disclosure)
        response.freshness = "fresh_local_ipc"
        response.cacheHit = false
        response.denyCode = nil
        response.downgradeCode = route.downgradeCode?.rawValue
        scheduleRustMemoryGatewayShadowCompareIfEnabled(
            productResponse: response,
            payload: payload,
            requesterRole: requesterRole,
            useMode: useMode,
            timeoutSec: timeoutSec
        )
        return MemoryContextResolutionResult(
            response: response,
            source: response.source,
            resolvedMode: useMode,
            requestedProfile: route.servingProfile.rawValue,
            attemptedProfiles: [route.servingProfile.rawValue],
            freshness: "fresh_local_ipc",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: route.downgradeCode?.rawValue,
            reasonCode: nil,
            detail: nil
        )
    }

    private static func progressiveDisclosureProfiles(
        enabled: Bool,
        mode: XTMemoryUseMode,
        targetProfile: XTMemoryServingProfile,
        reviewLevelHint: String? = nil,
        hasFocusedProjectAnchor: Bool = false
    ) -> [XTMemoryServingProfile] {
        guard enabled else { return [targetProfile] }
        switch mode {
        case .projectChat, .supervisorOrchestration:
            guard targetProfile.rank >= XTMemoryServingProfile.m2PlanReview.rank else {
                return [targetProfile]
            }
            let startProfile = progressiveDisclosureStartProfile(
                mode: mode,
                targetProfile: targetProfile,
                reviewLevelHint: reviewLevelHint,
                hasFocusedProjectAnchor: hasFocusedProjectAnchor
            )
            var profiles: [XTMemoryServingProfile] = [startProfile]
            if targetProfile.rank >= XTMemoryServingProfile.m2PlanReview.rank {
                profiles.append(.m2PlanReview)
            }
            if targetProfile.rank >= XTMemoryServingProfile.m3DeepDive.rank {
                profiles.append(.m3DeepDive)
            }
            if targetProfile.rank >= XTMemoryServingProfile.m4FullScan.rank {
                profiles.append(.m4FullScan)
            }
            return Array(NSOrderedSet(array: profiles)) as? [XTMemoryServingProfile] ?? profiles
        default:
            return [targetProfile]
        }
    }

    private static func progressiveDisclosureStartProfile(
        mode: XTMemoryUseMode,
        targetProfile: XTMemoryServingProfile,
        reviewLevelHint: String?,
        hasFocusedProjectAnchor: Bool
    ) -> XTMemoryServingProfile {
        guard mode == .supervisorOrchestration,
              let reviewLevel = parseSupervisorReviewLevelHint(reviewLevelHint) else {
            return .m1Execute
        }

        let floor = minimumSupervisorServingProfile(
            for: reviewLevel,
            hasFocusedProjectAnchor: hasFocusedProjectAnchor
        )
        if floor.rank >= targetProfile.rank {
            return targetProfile
        }
        return floor
    }

    private static func shouldUpgradeMemoryContextProgressively(
        response: MemoryContextResponsePayload,
        currentProfile: XTMemoryServingProfile,
        targetProfile: XTMemoryServingProfile
    ) -> Bool {
        guard currentProfile.rank < targetProfile.rank else { return false }
        if !response.truncatedLayers.isEmpty { return true }
        let totalRatio = usageRatio(used: response.usedTotalTokens, budget: response.budgetTotalTokens)
        if totalRatio >= 0.82 { return true }

        let saturatedCoreLayer = response.layerUsage.contains { layer in
            switch layer.layer {
            case "l1_canonical", "l2_observations", "l3_working_set":
                return usageRatio(used: layer.usedTokens, budget: layer.budgetTokens) >= 0.88
            default:
                return false
            }
        }
        return saturatedCoreLayer
    }

    private static func usageRatio(used: Int, budget: Int) -> Double {
        guard budget > 0, used > 0 else { return 0 }
        return Double(used) / Double(budget)
    }

    private static func enrichProgressiveMemoryContextResult(
        _ result: MemoryContextResolutionResult,
        requestedProfile: String,
        attemptedProfiles: [String]
    ) -> MemoryContextResolutionResult {
        var enriched = result
        enriched.requestedProfile = requestedProfile
        enriched.attemptedProfiles = attemptedProfiles
        if var response = enriched.response {
            response.requestedProfile = requestedProfile
            response.attemptedProfiles = attemptedProfiles
            response.progressiveUpgradeCount = max(0, attemptedProfiles.count - 1)
            enriched.response = response
        }
        return enriched
    }

    private static func memoryContextResolutionOverride() -> (@Sendable (XTMemoryRouteDecision, XTMemoryUseMode, Double) async -> MemoryContextResolutionResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: memoryContextResolutionOverrideForTesting,
                scoped: scopedMemoryContextResolutionOverridesForTesting
            )
        }
    }

    private static func routeDecisionOverride() -> (@Sendable () async -> HubRouteDecision)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: routeDecisionOverrideForTesting,
                scoped: scopedRouteDecisionOverridesForTesting
            )
        }
    }

    private static func supervisorRouteDecisionOverride() -> (@Sendable (SupervisorRouteDecisionRequestPayload) async -> SupervisorRouteDecisionResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: supervisorRouteDecisionOverrideForTesting,
                scoped: scopedSupervisorRouteDecisionOverridesForTesting
            )
        }
    }

    private static func supervisorRemoteContinuityOverride() -> (@Sendable (Bool) async -> SupervisorRemoteContinuityResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: supervisorRemoteContinuityOverrideForTesting,
                scoped: scopedSupervisorRemoteContinuityOverridesForTesting
            )
        }
    }

    private static func supervisorConversationAppendOverride() -> (@Sendable (HubRemoteSupervisorConversationPayload) async -> Bool)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: supervisorConversationAppendOverrideForTesting,
                scoped: scopedSupervisorConversationAppendOverridesForTesting
            )
        }
    }

    static func memoryRetrievalOverride() -> (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: memoryRetrievalOverrideForTesting,
                scoped: scopedMemoryRetrievalOverridesForTesting
            )
        }
    }

    static func remoteMemoryRetrievalOverride() -> (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: remoteMemoryRetrievalOverrideForTesting,
                scoped: scopedRemoteMemoryRetrievalOverridesForTesting
            )
        }
    }

    private static func remoteRuntimeSurfaceOverridesOverride() -> (@Sendable (String?, Int, Double) async -> HubRemoteRuntimeSurfaceOverridesResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: remoteRuntimeSurfaceOverridesOverrideForTesting,
                scoped: scopedRemoteRuntimeSurfaceOverridesForTesting
            )
        }
    }

    private static func projectCanonicalRustSyncOverride() -> (@Sendable (ProjectCanonicalMemoryPayload) async -> ProjectCanonicalMemoryRustSyncOverrideResult?)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: projectCanonicalRustSyncOverrideForTesting,
                scoped: scopedProjectCanonicalRustSyncOverridesForTesting
            )
        }
    }

    private static func rustProjectCanonicalMemoryOverride() -> (@Sendable (String, Int, Double) async -> RustProjectCanonicalMemorySnapshot?)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: rustProjectCanonicalMemoryOverrideForTesting,
                scoped: scopedRustProjectCanonicalMemoryOverridesForTesting
            )
        }
    }

    static func rustMemoryGatewayPrepareOverride() -> (@Sendable (RustMemoryGatewayPrepareRequest, Double) async -> RustMemoryGatewayPrepareResult?)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: rustMemoryGatewayPrepareOverrideForTesting,
                scoped: scopedRustMemoryGatewayPrepareOverridesForTesting
            )
        }
    }

    static func rustMemoryGatewayModelCallPlanOverride() -> (@Sendable (RustMemoryGatewayModelCallPlanRequest, Double) async -> RustMemoryGatewayModelCallPlanResult?)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: rustMemoryGatewayModelCallPlanOverrideForTesting,
                scoped: scopedRustMemoryGatewayModelCallPlanOverridesForTesting
            )
        }
    }

    private static func memoryWritebackCandidateExtractOverride() -> (@Sendable (MemoryWritebackCandidateExtractPayload, Double) async -> MemoryWritebackCandidateExtractResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: memoryWritebackCandidateExtractOverrideForTesting,
                scoped: scopedMemoryWritebackCandidateExtractOverridesForTesting
            )
        }
    }

    private static func memoryWritebackCandidateListOverride() -> (@Sendable (String?, Int, Double) async -> MemoryWritebackCandidateListResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: memoryWritebackCandidateListOverrideForTesting,
                scoped: scopedMemoryWritebackCandidateListOverridesForTesting
            )
        }
    }

    private static func memoryWritebackCandidateDecisionOverride() -> (@Sendable (String, String, MemoryWritebackCandidateDecisionPayload, Double) async -> MemoryWritebackCandidateDecisionResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: memoryWritebackCandidateDecisionOverrideForTesting,
                scoped: scopedMemoryWritebackCandidateDecisionOverridesForTesting
            )
        }
    }

    private static func memoryWritebackCandidateMaintenanceOverride() -> (@Sendable (MemoryWritebackCandidateMaintenancePayload, Double) async -> MemoryWritebackCandidateMaintenanceResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: memoryWritebackCandidateMaintenanceOverrideForTesting,
                scoped: scopedMemoryWritebackCandidateMaintenanceOverridesForTesting
            )
        }
    }

    private static func memoryObjectListOverride() -> (@Sendable (MemoryObjectListFilter, Double) async -> MemoryObjectListResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: memoryObjectListOverrideForTesting,
                scoped: scopedMemoryObjectListOverridesForTesting
            )
        }
    }

    private static func memoryUserRevealGrantOverride() -> (@Sendable (MemoryUserRevealGrantRequest, Double) async -> MemoryUserRevealGrantResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: memoryUserRevealGrantOverrideForTesting,
                scoped: scopedMemoryUserRevealGrantOverridesForTesting
            )
        }
    }

    private static func memoryObjectHistoryOverride() -> (@Sendable (String, Int, Double) async -> MemoryObjectHistoryResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: memoryObjectHistoryOverrideForTesting,
                scoped: scopedMemoryObjectHistoryOverridesForTesting
            )
        }
    }

    private static func memoryObjectGetOverride() -> (@Sendable (String, Double) async -> MemoryObjectResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: memoryObjectGetOverrideForTesting,
                scoped: scopedMemoryObjectGetOverridesForTesting
            )
        }
    }

    private static func memoryObjectMutationOverride() -> (@Sendable (String, String, MemoryObjectMutationPayload, Double) async -> MemoryObjectMutationResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: memoryObjectMutationOverrideForTesting,
                scoped: scopedMemoryObjectMutationOverridesForTesting
            )
        }
    }

    static func remoteMemorySnapshotOverride() -> (@Sendable (XTMemoryUseMode, String?, Bool, Double) async -> HubRemoteMemorySnapshotResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: remoteMemorySnapshotOverrideForTesting,
                scoped: scopedRemoteMemorySnapshotOverridesForTesting
            )
        }
    }

    private static func voiceGrantChallengeOverride() -> (@Sendable (VoiceGrantChallengeRequestPayload) async -> VoiceGrantChallengeResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: voiceGrantChallengeOverrideForTesting,
                scoped: scopedVoiceGrantChallengeOverridesForTesting
            )
        }
    }

    private static func voiceGrantVerificationOverride() -> (@Sendable (VoiceGrantVerificationPayload) async -> VoiceGrantVerificationResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: voiceGrantVerificationOverrideForTesting,
                scoped: scopedVoiceGrantVerificationOverridesForTesting
            )
        }
    }

    private static func localMemoryRetrievalIPCOverride() -> (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: localMemoryRetrievalIPCOverrideForTesting,
                scoped: scopedLocalMemoryRetrievalIPCOverridesForTesting
            )
        }
    }

    static func pushNotification(
        source: String,
        title: String,
        body: String,
        dedupeKey: String? = nil,
        actionURL: String? = nil,
        unread: Bool = true
    ) {
        let payload = NotificationPayload(
            id: "",
            source: source,
            title: title,
            body: body,
            createdAt: Date().timeIntervalSince1970,
            dedupeKey: dedupeKey,
            actionURL: actionURL,
            unread: unread
        )
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                _ = await pushNotificationViaPreferredRoute(payload: payload, allowFileFallback: false)
            }
        case .auto:
            Task {
                _ = await pushNotificationViaPreferredRoute(payload: payload, allowFileFallback: true)
            }
        case .fileIPC:
            _ = writeNotificationViaFileIPC(payload)
        }
    }

    static func removeNotification(dedupeKey: String? = nil, id: String? = nil) {
        _ = removeNotificationViaLocalIPC(dedupeKey: dedupeKey, id: id)
    }

    static func appendSupervisorIncidentAudit(
        incidentID: String,
        laneID: String,
        taskID: UUID,
        projectID: UUID?,
        incidentCode: String,
        eventType: String,
        denyCode: String,
        proposedAction: String,
        severity: String,
        category: String,
        detectedAtMs: Int64,
        handledAtMs: Int64?,
        takeoverLatencyMs: Int64?,
        auditRef: String,
        detail: String?,
        status: String
    ) {
        guard let dir = supervisorIncidentAuditEventsDir() else { return }

        let normalizedEventType = normalized(eventType) ?? ""
        let normalizedIncidentCode = normalized(incidentCode) ?? ""
        let normalizedDenyCode = normalized(denyCode) ?? ""
        let normalizedLaneID = normalized(laneID) ?? ""
        let normalizedAuditRef = normalized(auditRef) ?? ""
        guard !normalizedEventType.isEmpty,
              !normalizedIncidentCode.isEmpty,
              !normalizedDenyCode.isEmpty,
              !normalizedLaneID.isEmpty,
              !normalizedAuditRef.isEmpty else {
            return
        }

        let reqId = UUID().uuidString
        let payload = SupervisorIncidentAuditPayload(
            incidentId: normalized(incidentID) ?? "",
            laneId: normalizedLaneID,
            taskId: taskID.uuidString.lowercased(),
            projectId: projectID?.uuidString.lowercased(),
            incidentCode: normalizedIncidentCode,
            eventType: normalizedEventType,
            denyCode: normalizedDenyCode,
            proposedAction: normalized(proposedAction) ?? "",
            severity: normalized(severity) ?? "",
            category: normalized(category) ?? "",
            detectedAtMs: max(0, detectedAtMs),
            handledAtMs: handledAtMs != nil ? max(0, handledAtMs ?? 0) : nil,
            takeoverLatencyMs: takeoverLatencyMs != nil ? max(0, takeoverLatencyMs ?? 0) : nil,
            auditRef: normalizedAuditRef,
            detail: normalized(detail),
            status: normalized(status) ?? "",
            source: "x_terminal_supervisor"
        )
        let req = SupervisorIncidentAuditIPCRequest(
            type: "supervisor_incident_audit",
            reqId: reqId,
            supervisorIncident: payload
        )
        guard let data = try? JSONEncoder().encode(req) else { return }
        _ = writeEvent(
            data: data,
            reqId: reqId,
            filePrefix: "xterminal_incident_audit",
            tmpPrefix: ".xterminal_incident_audit",
            in: dir
        )
    }

    static func appendSupervisorProjectActionAudit(
        eventID: String,
        projectID: String,
        projectName: String,
        eventType: String,
        severity: String,
        actionTitle: String,
        actionSummary: String,
        whyItMatters: String,
        nextAction: String,
        occurredAtMs: Int64,
        deliveryChannel: String,
        deliveryStatus: String,
        jurisdictionRole: String?,
        grantedScope: String?,
        auditRef: String
    ) {
        let normalizedEventID = normalized(eventID) ?? ""
        let normalizedProjectID = normalized(projectID) ?? ""
        let normalizedProjectName = normalized(projectName) ?? ""
        let normalizedEventType = normalized(eventType) ?? ""
        let normalizedSeverity = normalized(severity) ?? ""
        let normalizedActionTitle = normalized(actionTitle) ?? ""
        let normalizedActionSummary = normalized(actionSummary) ?? ""
        let normalizedWhy = normalized(whyItMatters) ?? ""
        let normalizedNextAction = normalized(nextAction) ?? ""
        let normalizedDeliveryChannel = normalized(deliveryChannel) ?? ""
        let normalizedDeliveryStatus = normalized(deliveryStatus) ?? ""
        let normalizedAuditRef = normalized(auditRef) ?? ""
        guard !normalizedEventID.isEmpty,
              !normalizedProjectID.isEmpty,
              !normalizedProjectName.isEmpty,
              !normalizedEventType.isEmpty,
              !normalizedSeverity.isEmpty,
              !normalizedActionTitle.isEmpty,
              !normalizedActionSummary.isEmpty,
              !normalizedWhy.isEmpty,
              !normalizedNextAction.isEmpty,
              !normalizedDeliveryChannel.isEmpty,
              !normalizedDeliveryStatus.isEmpty,
              !normalizedAuditRef.isEmpty else {
            return
        }

        let payload = SupervisorProjectActionAuditPayload(
            eventId: normalizedEventID,
            projectId: normalizedProjectID,
            projectName: normalizedProjectName,
            eventType: normalizedEventType,
            severity: normalizedSeverity,
            actionTitle: normalizedActionTitle,
            actionSummary: normalizedActionSummary,
            whyItMatters: normalizedWhy,
            nextAction: normalizedNextAction,
            occurredAtMs: max(0, occurredAtMs),
            deliveryChannel: normalizedDeliveryChannel,
            deliveryStatus: normalizedDeliveryStatus,
            jurisdictionRole: normalized(jurisdictionRole),
            grantedScope: normalized(grantedScope),
            auditRef: normalizedAuditRef,
            source: "x_terminal_supervisor"
        )
        let wroteLocalAudit = writeSupervisorProjectActionAuditViaLocalIPC(payload)
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                _ = await appendSupervisorProjectActionAuditViaPreferredRoute(payload: payload, allowFileFallback: false)
            }
        case .auto:
            Task {
                _ = await appendSupervisorProjectActionAuditViaPreferredRoute(payload: payload, allowFileFallback: false)
            }
        case .fileIPC:
            _ = wroteLocalAudit
        }
    }

    @discardableResult
    private static func appendSupervisorProjectActionAuditViaPreferredRoute(
        payload: SupervisorProjectActionAuditPayload,
        allowFileFallback: Bool
    ) async -> Bool {
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let record = SupervisorProjectActionCanonicalRecord(
                schemaVersion: SupervisorProjectActionCanonicalSync.schemaVersion,
                eventId: payload.eventId,
                projectId: payload.projectId,
                projectName: payload.projectName,
                eventType: payload.eventType,
                severity: payload.severity,
                actionTitle: payload.actionTitle,
                actionSummary: payload.actionSummary,
                whyItMatters: payload.whyItMatters,
                nextAction: payload.nextAction,
                occurredAtMs: payload.occurredAtMs,
                deliveryChannel: payload.deliveryChannel,
                deliveryStatus: payload.deliveryStatus,
                jurisdictionRole: payload.jurisdictionRole,
                grantedScope: payload.grantedScope,
                auditRef: payload.auditRef
            )
            let remote = await HubPairingCoordinator.shared.upsertRemoteProjectCanonicalMemory(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteProjectCanonicalMemoryPayload(
                    projectId: payload.projectId,
                    items: SupervisorProjectActionCanonicalSync.items(record: record).map { item in
                        HubRemoteCanonicalMemoryItem(key: item.key, value: item.value)
                    }
                )
            )
            if remote.ok {
                await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                return true
            }
            if !allowFileFallback {
                return false
            }
        } else if !allowFileFallback {
            return false
        }

        return writeSupervisorProjectActionAuditViaLocalIPC(payload)
    }

    private static func writeSupervisorProjectActionAuditViaLocalIPC(_ payload: SupervisorProjectActionAuditPayload) -> Bool {
        guard let dir = supervisorIncidentAuditEventsDir() else { return false }

        let reqId = UUID().uuidString
        let req = SupervisorProjectActionAuditIPCRequest(
            type: "supervisor_project_action_audit",
            reqId: reqId,
            supervisorProjectAction: payload
        )
        guard let data = try? JSONEncoder().encode(req) else { return false }
        return writeEvent(
            data: data,
            reqId: reqId,
            filePrefix: "xterminal_project_action_audit",
            tmpPrefix: ".xterminal_project_action_audit",
            in: dir
        )
    }

    static func requestSchedulerStatus(
        includeQueueItems: Bool = true,
        queueItemsLimit: Int = 80
    ) async -> SchedulerStatusSnapshot? {
        let routeDecision = await currentRouteDecision()

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteSchedulerStatus(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                includeQueueItems: includeQueueItems,
                queueItemsLimit: max(1, min(500, queueItemsLimit))
            )
            if remote.ok {
                return SchedulerStatusSnapshot(
                    source: remote.source,
                    updatedAtMs: max(0, remote.updatedAtMs),
                    inFlightTotal: max(0, remote.inFlightTotal),
                    queueDepth: max(0, remote.queueDepth),
                    oldestQueuedMs: max(0, remote.oldestQueuedMs),
                    inFlightByScope: remote.inFlightByScope.map { row in
                        SchedulerScopeCount(
                            scopeKey: row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            count: max(0, row.count)
                        )
                    },
                    queuedByScope: remote.queuedByScope.map { row in
                        SchedulerScopeCount(
                            scopeKey: row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            count: max(0, row.count)
                        )
                    },
                    queueItems: remote.queueItems.map { row in
                        SchedulerQueueItem(
                            requestId: row.requestId.trimmingCharacters(in: .whitespacesAndNewlines),
                            scopeKey: row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            enqueuedAtMs: max(0, row.enqueuedAtMs),
                            queuedMs: max(0, row.queuedMs)
                        )
                    }
                )
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return readLocalSchedulerStatus(
            includeQueueItems: includeQueueItems,
            queueItemsLimit: max(1, min(500, queueItemsLimit))
        )
    }

    static func requestPendingGrantRequests(
        projectId: String? = nil,
        limit: Int = 200
    ) async -> PendingGrantSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)
        var sourceOverrideForLocalSnapshot: String?

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemotePendingGrantRequests(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                projectId: normalizedProjectId,
                limit: boundedLimit
            )
            if remote.ok {
                let items = remote.items.map { row in
                    PendingGrantItem(
                        grantRequestId: row.grantRequestId,
                        requestId: row.requestId,
                        deviceId: row.deviceId,
                        userId: row.userId,
                        appId: row.appId,
                        projectId: row.projectId,
                        capability: row.capability,
                        modelId: row.modelId,
                        reason: row.reason,
                        requestedTtlSec: max(0, row.requestedTtlSec),
                        requestedTokenCap: max(0, row.requestedTokenCap),
                        status: row.status,
                        decision: row.decision,
                        createdAtMs: max(0, row.createdAtMs),
                        decidedAtMs: max(0, row.decidedAtMs)
                    )
                }
                return PendingGrantSnapshot(
                    source: remote.source.trimmingCharacters(in: .whitespacesAndNewlines),
                    updatedAtMs: max(0, remote.updatedAtMs),
                    items: items
                )
            }

            let remoteReasonCode = normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_pending_grants_failed"
            )
            guard HubRouteStateMachine.shouldFallbackToFileForPendingGrantSnapshot(
                routeDecision: routeDecision,
                remoteReasonCode: remoteReasonCode
            ) else {
                return nil
            }
            sourceOverrideForLocalSnapshot = HubRouteStateMachine.pendingGrantSnapshotFallbackSource(
                localSource: "hub_pending_grants_file",
                routeDecision: routeDecision,
                remoteReasonCode: remoteReasonCode
            )
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return readLocalPendingGrantRequests(
            projectId: normalizedProjectId,
            limit: boundedLimit,
            sourceOverride: sourceOverrideForLocalSnapshot
        )
    }

    static func requestSupervisorCandidateReviewSnapshot(
        projectId: String? = nil,
        limit: Int = 200
    ) async -> SupervisorCandidateReviewSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteSupervisorCandidateReviewQueue(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                projectId: normalizedProjectId,
                limit: boundedLimit
            )
            if remote.ok {
                return SupervisorCandidateReviewSnapshot(
                    source: remote.source.trimmingCharacters(in: .whitespacesAndNewlines),
                    updatedAtMs: max(0, remote.updatedAtMs),
                    items: remote.items.map { row in
                        SupervisorCandidateReviewItem(
                            schemaVersion: row.schemaVersion,
                            reviewId: row.reviewId,
                            requestId: row.requestId,
                            evidenceRef: row.evidenceRef,
                            reviewState: row.reviewState,
                            durablePromotionState: row.durablePromotionState,
                            promotionBoundary: row.promotionBoundary,
                            deviceId: row.deviceId,
                            userId: row.userId,
                            appId: row.appId,
                            threadId: row.threadId,
                            threadKey: row.threadKey,
                            projectId: row.projectId,
                            projectIds: row.projectIds,
                            scopes: row.scopes,
                            recordTypes: row.recordTypes,
                            auditRefs: row.auditRefs,
                            idempotencyKeys: row.idempotencyKeys,
                            candidateCount: max(0, row.candidateCount),
                            summaryLine: row.summaryLine,
                            mirrorTarget: row.mirrorTarget,
                            localStoreRole: row.localStoreRole,
                            carrierKind: row.carrierKind,
                            carrierSchemaVersion: row.carrierSchemaVersion,
                            pendingChangeId: row.pendingChangeId,
                            pendingChangeStatus: row.pendingChangeStatus,
                            editSessionId: row.editSessionId,
                            docId: row.docId,
                            writebackRef: row.writebackRef,
                            stageCreatedAtMs: max(0, row.stageCreatedAtMs),
                            stageUpdatedAtMs: max(0, row.stageUpdatedAtMs),
                            latestEmittedAtMs: max(0, row.latestEmittedAtMs),
                            createdAtMs: max(0, row.createdAtMs),
                            updatedAtMs: max(0, row.updatedAtMs)
                        )
                    }
                )
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return readLocalSupervisorCandidateReviewSnapshot(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    static func requestSupervisorSkillRegistrySnapshot(
        projectId: String?,
        projectName: String?
    ) async -> SupervisorSkillRegistrySnapshot? {
        guard let normalizedProjectId = normalized(projectId) else { return nil }
        return AXSkillsLibrary.supervisorSkillRegistrySnapshot(
            projectId: normalizedProjectId,
            projectName: normalized(projectName),
            hubBaseDir: HubPaths.baseDir()
        )
    }

    static func searchSkills(
        query: String,
        sourceFilter: String? = nil,
        projectId: String? = nil,
        limit: Int = 20
    ) async -> SkillsSearchResult {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSourceFilter = normalized(sourceFilter)
        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(100, limit))

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.searchRemoteSkills(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                query: normalizedQuery,
                sourceFilter: normalizedSourceFilter,
                projectId: normalizedProjectId,
                limit: boundedLimit
            )
            return SkillsSearchResult(
                ok: remote.ok,
                source: remote.source,
                updatedAtMs: remote.updatedAtMs,
                results: remote.results.map { row in
                    SkillCatalogEntry(
                        skillID: row.skillID,
                        name: row.name,
                        version: row.version,
                        description: row.description,
                        publisherID: row.publisherID,
                        capabilitiesRequired: row.capabilitiesRequired,
                        sourceID: row.sourceID,
                        packageSHA256: row.packageSHA256,
                        installHint: row.installHint,
                        riskLevel: row.riskLevel,
                        requiresGrant: row.requiresGrant,
                        sideEffectClass: row.sideEffectClass
                    )
                },
                reasonCode: remote.reasonCode,
                officialChannelStatus: remote.officialChannelStatus.map { status in
                    OfficialSkillChannelStatus(
                        channelID: status.channelID,
                        status: status.status,
                        updatedAtMs: status.updatedAtMs,
                        lastAttemptAtMs: status.lastAttemptAtMs,
                        lastSuccessAtMs: status.lastSuccessAtMs,
                        skillCount: status.skillCount,
                        errorCode: status.errorCode,
                        maintenanceEnabled: status.maintenanceEnabled,
                        maintenanceIntervalMs: status.maintenanceIntervalMs,
                        maintenanceLastRunAtMs: status.maintenanceLastRunAtMs,
                        maintenanceSourceKind: status.maintenanceSourceKind,
                        lastTransitionAtMs: status.lastTransitionAtMs,
                        lastTransitionKind: status.lastTransitionKind,
                        lastTransitionSummary: status.lastTransitionSummary
                    )
                }
            )
        }

        return SkillsSearchResult(
            ok: false,
            source: "file_ipc",
            updatedAtMs: 0,
            results: [],
            reasonCode: "skills_search_file_ipc_not_supported",
            officialChannelStatus: nil
        )
    }

    static func setSkillPin(
        scope: String,
        skillId: String,
        packageSHA256: String,
        projectId: String? = nil,
        note: String? = nil,
        requestId: String? = nil
    ) async -> SkillPinResult {
        let normalizedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedSkillId = skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPackageSHA256 = packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedProjectId = normalized(projectId)
        let override = withTestingOverrideLock {
            testingOverride(
                fallback: skillPinOverrideForTesting,
                scoped: scopedSkillPinOverridesForTesting
            )
        }
        if let override {
            return await override(
                SkillPinRequestPayload(
                    scope: normalizedScope,
                    skillId: normalizedSkillId,
                    packageSHA256: normalizedPackageSHA256,
                    projectId: normalizedProjectId,
                    note: note,
                    requestId: requestId
                )
            )
        }

        guard normalizedScope == "global" || normalizedScope == "project" else {
            return SkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: "",
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "unsupported_skill_pin_scope"
            )
        }
        if normalizedScope == "project", normalizedProjectId == nil {
            return SkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: "",
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "missing_project_id"
            )
        }
        guard !normalizedSkillId.isEmpty else {
            return SkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: normalizedProjectId ?? "",
                skillId: "",
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "missing_skill_id"
            )
        }
        guard !normalizedPackageSHA256.isEmpty else {
            return SkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: normalizedProjectId ?? "",
                skillId: normalizedSkillId,
                packageSHA256: "",
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "missing_package_sha256"
            )
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.setRemoteSkillPin(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                scope: normalizedScope,
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                projectId: normalizedProjectId,
                note: note,
                requestId: requestId
            )
            return SkillPinResult(
                ok: remote.ok,
                source: remote.source,
                scope: remote.scope,
                userId: remote.userId,
                projectId: remote.projectId,
                skillId: remote.skillId,
                packageSHA256: remote.packageSHA256,
                previousPackageSHA256: remote.previousPackageSHA256,
                updatedAtMs: remote.updatedAtMs,
                reasonCode: remote.reasonCode
            )
        }

        return SkillPinResult(
            ok: false,
            source: "file_ipc",
            scope: normalizedScope,
            userId: "",
            projectId: normalizedProjectId ?? "",
            skillId: normalizedSkillId,
            packageSHA256: normalizedPackageSHA256,
            previousPackageSHA256: "",
            updatedAtMs: 0,
            reasonCode: "skills_pin_file_ipc_not_supported"
        )
    }

    static func listResolvedSkills(
        projectId: String? = nil
    ) async -> ResolvedSkillsResult {
        let normalizedProjectId = normalized(projectId)
        if let override = withTestingOverrideLock({
            testingOverride(
                fallback: resolvedSkillsOverrideForTesting,
                scoped: scopedResolvedSkillsOverridesForTesting
            )
        }) {
            return await override(normalizedProjectId)
        }
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteResolvedSkills(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                projectId: normalizedProjectId
            )
            return ResolvedSkillsResult(
                ok: remote.ok,
                source: remote.source,
                skills: remote.skills.map { row in
                    ResolvedSkillEntry(
                        scope: row.scope,
                        skill: SkillCatalogEntry(
                            skillID: row.skill.skillID,
                            name: row.skill.name,
                            version: row.skill.version,
                            description: row.skill.description,
                            publisherID: row.skill.publisherID,
                            capabilitiesRequired: row.skill.capabilitiesRequired,
                            sourceID: row.skill.sourceID,
                            packageSHA256: row.skill.packageSHA256,
                            installHint: row.skill.installHint,
                            riskLevel: row.skill.riskLevel,
                            requiresGrant: row.skill.requiresGrant,
                            sideEffectClass: row.skill.sideEffectClass
                        )
                    )
                },
                reasonCode: remote.reasonCode
            )
        }

        return ResolvedSkillsResult(
            ok: false,
            source: "file_ipc",
            skills: [],
            reasonCode: "skills_resolved_file_ipc_not_supported"
        )
    }

    static func getSkillManifest(
        packageSHA256: String
    ) async -> SkillManifestResult {
        let normalizedPackageSHA256 = packageSHA256
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedPackageSHA256.isEmpty else {
            return SkillManifestResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: "",
                manifestJSON: "",
                reasonCode: "missing_package_sha256"
            )
        }

        if let override = withTestingOverrideLock({
            testingOverride(
                fallback: skillManifestOverrideForTesting,
                scoped: scopedSkillManifestOverridesForTesting
            )
        }) {
            return await override(normalizedPackageSHA256)
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteSkillManifest(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                packageSHA256: normalizedPackageSHA256
            )
            return SkillManifestResult(
                ok: remote.ok,
                source: remote.source,
                packageSHA256: remote.packageSHA256,
                manifestJSON: remote.manifestJSON,
                reasonCode: remote.reasonCode
            )
        }

        return SkillManifestResult(
            ok: false,
            source: "file_ipc",
            packageSHA256: normalizedPackageSHA256,
            manifestJSON: "",
            reasonCode: "skills_manifest_file_ipc_not_supported"
        )
    }

    static func downloadSkillPackage(
        packageSHA256: String
    ) async -> SkillPackageDownloadResult {
        let normalizedPackageSHA256 = packageSHA256
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedPackageSHA256.isEmpty else {
            return SkillPackageDownloadResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: "",
                data: Data(),
                reasonCode: "missing_package_sha256"
            )
        }

        if let override = withTestingOverrideLock({
            testingOverride(
                fallback: skillPackageDownloadOverrideForTesting,
                scoped: scopedSkillPackageDownloadOverridesForTesting
            )
        }) {
            return await override(normalizedPackageSHA256)
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.downloadRemoteSkillPackage(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                packageSHA256: normalizedPackageSHA256
            )
            return SkillPackageDownloadResult(
                ok: remote.ok,
                source: remote.source,
                packageSHA256: remote.packageSHA256,
                data: remote.data,
                reasonCode: remote.reasonCode
            )
        }

        return SkillPackageDownloadResult(
            ok: false,
            source: "file_ipc",
            packageSHA256: normalizedPackageSHA256,
            data: Data(),
            reasonCode: "skills_package_download_file_ipc_not_supported"
        )
    }

    static func evaluateSkillRunnerGate(
        _ request: SkillRunnerGateRequestPayload
    ) async -> SkillRunnerGateResult {
        let normalizedSkillId = request.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPackageSHA256 = request.packageSHA256
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedToolName = request.toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRequestId = request.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSkillId.isEmpty else {
            return SkillRunnerGateResult(
                ok: false,
                source: "hub_runtime_grpc",
                skillId: "",
                packageSHA256: normalizedPackageSHA256,
                toolName: normalizedToolName,
                decision: "deny",
                toolRequestId: "",
                grantId: "",
                executionId: "",
                denyCode: "missing_skill_id",
                resultJSON: "",
                executedAtMs: 0
            )
        }
        guard !normalizedPackageSHA256.isEmpty else {
            return SkillRunnerGateResult(
                ok: false,
                source: "hub_runtime_grpc",
                skillId: normalizedSkillId,
                packageSHA256: "",
                toolName: normalizedToolName,
                decision: "deny",
                toolRequestId: "",
                grantId: "",
                executionId: "",
                denyCode: "missing_package_sha256",
                resultJSON: "",
                executedAtMs: 0
            )
        }
        guard !normalizedToolName.isEmpty else {
            return SkillRunnerGateResult(
                ok: false,
                source: "hub_runtime_grpc",
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                toolName: "",
                decision: "deny",
                toolRequestId: "",
                grantId: "",
                executionId: "",
                denyCode: "missing_tool_name",
                resultJSON: "",
                executedAtMs: 0
            )
        }
        guard !normalizedRequestId.isEmpty,
              !request.toolArgsHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.execArgv.isEmpty,
              !request.execCwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SkillRunnerGateResult(
                ok: false,
                source: "hub_runtime_grpc",
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                toolName: normalizedToolName,
                decision: "deny",
                toolRequestId: "",
                grantId: "",
                executionId: "",
                denyCode: "approval_binding_invalid",
                resultJSON: "",
                executedAtMs: 0
            )
        }

        let normalizedRequest = SkillRunnerGateRequestPayload(
            requestId: normalizedRequestId,
            projectId: normalized(request.projectId),
            executionRole: normalized(request.executionRole),
            agentMode: normalized(request.agentMode),
            laneId: normalized(request.laneId),
            auditRef: normalized(request.auditRef),
            skillId: normalizedSkillId,
            packageSHA256: normalizedPackageSHA256,
            toolName: normalizedToolName,
            toolArgsHash: request.toolArgsHash.trimmingCharacters(in: .whitespacesAndNewlines),
            riskTier: request.riskTier.trimmingCharacters(in: .whitespacesAndNewlines),
            requiredGrantScope: request.requiredGrantScope.trimmingCharacters(in: .whitespacesAndNewlines),
            execArgv: request.execArgv,
            execCwd: request.execCwd.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if let override = withTestingOverrideLock({
            testingOverride(
                fallback: skillRunnerGateOverrideForTesting,
                scoped: scopedSkillRunnerGateOverridesForTesting
            )
        }) {
            return await override(normalizedRequest)
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.evaluateRemoteSkillRunnerGate(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                request: normalizedRequest
            )
            return SkillRunnerGateResult(
                ok: remote.ok,
                source: remote.source,
                skillId: remote.skillId,
                packageSHA256: remote.packageSHA256,
                toolName: remote.toolName,
                decision: remote.decision,
                toolRequestId: remote.toolRequestId,
                grantId: remote.grantId,
                executionId: remote.executionId,
                denyCode: remote.denyCode,
                resultJSON: remote.resultJSON,
                executedAtMs: remote.executedAtMs
            )
        }

        return SkillRunnerGateResult(
            ok: false,
            source: "file_ipc",
            skillId: normalizedSkillId,
            packageSHA256: normalizedPackageSHA256,
            toolName: normalizedToolName,
            decision: "deny",
            toolRequestId: "",
            grantId: "",
            executionId: "",
            denyCode: "skill_runner_gate_file_ipc_not_supported",
            resultJSON: "",
            executedAtMs: 0
        )
    }

    static func stageAgentImport(
        importManifestJSON: String,
        findingsJSON: String? = nil,
        scanInputJSON: String? = nil,
        requestedBy: String? = nil,
        note: String? = nil,
        requestId: String? = nil
    ) async -> AgentImportStageResult {
        let manifestText = importManifestJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !manifestText.isEmpty else {
            return AgentImportStageResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                preflightStatus: nil,
                skillId: nil,
                policyScope: nil,
                findingsCount: 0,
                vetterStatus: nil,
                vetterCriticalCount: 0,
                vetterWarnCount: 0,
                vetterAuditRef: nil,
                recordPath: nil,
                reasonCode: "missing_agent_import_manifest"
            )
        }

        if let override = agentImportStageOverrideSnapshotForTesting() {
            return await override(
                AgentImportStageRequestPayload(
                    importManifestJSON: manifestText,
                    findingsJSON: findingsJSON,
                    scanInputJSON: scanInputJSON,
                    requestedBy: requestedBy,
                    note: note,
                    requestId: requestId
                )
            )
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.stageRemoteAgentImport(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                importManifestJSON: manifestText,
                findingsJSON: findingsJSON,
                scanInputJSON: scanInputJSON,
                requestedBy: requestedBy,
                note: note,
                requestId: requestId
            )
            return AgentImportStageResult(
                ok: remote.ok,
                source: remote.source,
                stagingId: remote.stagingId,
                status: remote.status,
                auditRef: remote.auditRef,
                preflightStatus: remote.preflightStatus,
                skillId: remote.skillId,
                policyScope: remote.policyScope,
                findingsCount: remote.findingsCount,
                vetterStatus: remote.vetterStatus,
                vetterCriticalCount: remote.vetterCriticalCount,
                vetterWarnCount: remote.vetterWarnCount,
                vetterAuditRef: remote.vetterAuditRef,
                recordPath: remote.recordPath,
                reasonCode: remote.reasonCode
            )
        }

        return AgentImportStageResult(
            ok: false,
            source: "file_ipc",
            stagingId: nil,
            status: nil,
            auditRef: nil,
            preflightStatus: nil,
            skillId: nil,
            policyScope: nil,
            findingsCount: 0,
            vetterStatus: nil,
            vetterCriticalCount: 0,
            vetterWarnCount: 0,
            vetterAuditRef: nil,
            recordPath: nil,
            reasonCode: "skills_stage_file_ipc_not_supported"
        )
    }

    static func getAgentImportRecord(
        stagingId: String? = nil,
        selector: String? = nil,
        skillId: String? = nil,
        projectId: String? = nil
    ) async -> AgentImportRecordResult {
        let normalizedStagingId = stagingId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedSelector = selector?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedSkillId = skillId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lookup = AgentImportRecordLookupPayload(
            stagingId: normalizedStagingId.isEmpty ? nil : normalizedStagingId,
            selector: normalizedSelector.isEmpty ? nil : normalizedSelector,
            skillId: normalizedSkillId.isEmpty ? nil : normalizedSkillId,
            projectId: normalizedProjectId.isEmpty ? nil : normalizedProjectId
        )

        guard lookup.stagingId != nil || lookup.selector != nil else {
            return AgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: lookup.selector,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: lookup.skillId,
                projectId: lookup.projectId,
                recordJSON: nil,
                reasonCode: "missing_agent_import_locator"
            )
        }

        if let override = agentImportRecordOverrideSnapshotForTesting() {
            return await override(lookup)
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote: HubRemoteAgentImportRecordResult
            if let normalizedStagingId = lookup.stagingId {
                remote = await HubPairingCoordinator.shared.fetchRemoteAgentImportRecord(
                    options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                    stagingId: normalizedStagingId
                )
            } else {
                remote = await HubPairingCoordinator.shared.fetchRemoteResolvedAgentImportRecord(
                    options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                    selector: lookup.selector ?? "last_import",
                    skillId: lookup.skillId,
                    projectId: lookup.projectId
                )
            }
            return AgentImportRecordResult(
                ok: remote.ok,
                source: remote.source,
                selector: remote.selector ?? lookup.selector,
                stagingId: remote.stagingId,
                status: remote.status,
                auditRef: remote.auditRef,
                schemaVersion: remote.schemaVersion,
                skillId: remote.skillId ?? lookup.skillId,
                projectId: remote.projectId ?? lookup.projectId,
                recordJSON: remote.recordJSON,
                reasonCode: remote.reasonCode
            )
        }

        return AgentImportRecordResult(
            ok: false,
            source: "file_ipc",
            selector: lookup.selector,
            stagingId: nil,
            status: nil,
            auditRef: nil,
            schemaVersion: nil,
            skillId: lookup.skillId,
            projectId: lookup.projectId,
            recordJSON: nil,
            reasonCode: "skills_record_file_ipc_not_supported"
        )
    }

    private static func agentImportRecordOverrideSnapshotForTesting() -> (@Sendable (AgentImportRecordLookupPayload) async -> AgentImportRecordResult)? {
        withTestingOverrideLock {
            agentImportRecordOverrideForTesting
        }
    }

    private static func agentImportStageOverrideSnapshotForTesting() -> (@Sendable (AgentImportStageRequestPayload) async -> AgentImportStageResult)? {
        withTestingOverrideLock {
            agentImportStageOverrideForTesting
        }
    }

    private static func secretUseOverrideSnapshotForTesting() -> (@Sendable (SecretUseRequestPayload) async -> SecretUseResult)? {
        withTestingOverrideLock {
            secretUseOverrideForTesting
        }
    }

    private static func skillPackageUploadOverrideSnapshotForTesting() -> (@Sendable (SkillPackageUploadRequestPayload) async -> SkillPackageUploadResult)? {
        withTestingOverrideLock {
            skillPackageUploadOverrideForTesting
        }
    }

    private static func secretRedeemOverrideSnapshotForTesting() -> (@Sendable (SecretRedeemRequestPayload) async -> SecretRedeemResult)? {
        withTestingOverrideLock {
            secretRedeemOverrideForTesting
        }
    }

    private static func agentImportPromoteOverrideSnapshotForTesting() -> (@Sendable (AgentImportPromoteRequestPayload) async -> AgentImportPromoteResult)? {
        withTestingOverrideLock {
            agentImportPromoteOverrideForTesting
        }
    }

    static func uploadSkillPackage(
        packageFileURL: URL,
        manifestJSON: String,
        sourceId: String = "local:xt-import",
        requestId: String? = nil
    ) async -> SkillPackageUploadResult {
        let manifestText = manifestJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !manifestText.isEmpty else {
            return SkillPackageUploadResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: nil,
                alreadyPresent: false,
                skillId: nil,
                version: nil,
                reasonCode: "missing_manifest_json"
            )
        }

        if let override = skillPackageUploadOverrideSnapshotForTesting() {
            return await override(
                SkillPackageUploadRequestPayload(
                    packageFileURL: packageFileURL,
                    manifestJSON: manifestText,
                    sourceId: sourceId,
                    requestId: requestId
                )
            )
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.uploadRemoteSkillPackage(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                packageFileURL: packageFileURL,
                manifestJSON: manifestText,
                sourceId: sourceId,
                requestId: requestId
            )
            return SkillPackageUploadResult(
                ok: remote.ok,
                source: remote.source,
                packageSHA256: remote.packageSHA256,
                alreadyPresent: remote.alreadyPresent,
                skillId: remote.skillId,
                version: remote.version,
                reasonCode: remote.reasonCode
            )
        }

        return SkillPackageUploadResult(
            ok: false,
            source: "file_ipc",
            packageSHA256: nil,
            alreadyPresent: false,
            skillId: nil,
            version: nil,
            reasonCode: "skills_upload_file_ipc_not_supported"
        )
    }

    static func promoteAgentImport(
        stagingId: String,
        packageSHA256: String,
        note: String? = nil,
        requestId: String? = nil
    ) async -> AgentImportPromoteResult {
        let normalizedStagingId = stagingId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPackageSHA256 = packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedStagingId.isEmpty else {
            return AgentImportPromoteResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                packageSHA256: nil,
                scope: nil,
                skillId: nil,
                previousPackageSHA256: nil,
                recordPath: nil,
                reasonCode: "missing_agent_staging_id"
            )
        }
        guard !normalizedPackageSHA256.isEmpty else {
            return AgentImportPromoteResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                packageSHA256: nil,
                scope: nil,
                skillId: nil,
                previousPackageSHA256: nil,
                recordPath: nil,
                reasonCode: "missing_package_sha256"
            )
        }

        if let override = agentImportPromoteOverrideSnapshotForTesting() {
            return await override(
                AgentImportPromoteRequestPayload(
                    stagingId: normalizedStagingId,
                    packageSHA256: normalizedPackageSHA256,
                    note: note,
                    requestId: requestId
                )
            )
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.promoteRemoteAgentImport(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                stagingId: normalizedStagingId,
                packageSHA256: normalizedPackageSHA256,
                note: note,
                requestId: requestId
            )
            return AgentImportPromoteResult(
                ok: remote.ok,
                source: remote.source,
                stagingId: remote.stagingId,
                status: remote.status,
                auditRef: remote.auditRef,
                packageSHA256: remote.packageSHA256,
                scope: remote.scope,
                skillId: remote.skillId,
                previousPackageSHA256: remote.previousPackageSHA256,
                recordPath: remote.recordPath,
                reasonCode: remote.reasonCode
            )
        }

        return AgentImportPromoteResult(
            ok: false,
            source: "file_ipc",
            stagingId: nil,
            status: nil,
            auditRef: nil,
            packageSHA256: nil,
            scope: nil,
            skillId: nil,
            previousPackageSHA256: nil,
            recordPath: nil,
            reasonCode: "skills_promote_file_ipc_not_supported"
        )
    }

    static func requestConnectorIngressReceipts(
        projectId: String? = nil,
        limit: Int = 200
    ) async -> ConnectorIngressSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteConnectorIngressReceipts(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                projectId: normalizedProjectId,
                limit: boundedLimit
            )
            if remote.ok {
                let items = remote.items.map { row in
                    ConnectorIngressReceipt(
                        receiptId: row.receiptId.trimmingCharacters(in: .whitespacesAndNewlines),
                        requestId: row.requestId.trimmingCharacters(in: .whitespacesAndNewlines),
                        projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                        connector: row.connector.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        targetId: row.targetId.trimmingCharacters(in: .whitespacesAndNewlines),
                        ingressType: row.ingressType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        channelScope: row.channelScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        sourceId: row.sourceId.trimmingCharacters(in: .whitespacesAndNewlines),
                        messageId: row.messageId.trimmingCharacters(in: .whitespacesAndNewlines),
                        dedupeKey: row.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                        receivedAtMs: max(0, row.receivedAtMs),
                        eventSequence: Swift.max(0, row.eventSequence),
                        deliveryState: row.deliveryState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        runtimeState: row.runtimeState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    )
                }
                return ConnectorIngressSnapshot(
                    source: remote.source.trimmingCharacters(in: .whitespacesAndNewlines),
                    updatedAtMs: max(0, remote.updatedAtMs),
                    items: items
                )
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return readLocalConnectorIngressReceipts(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    static func requestOperatorChannelXTCommands(
        projectId: String? = nil,
        limit: Int = 200
    ) async -> OperatorChannelXTCommandSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote, !routeDecision.allowFileFallback {
            return nil
        }

        if routeDecision.requiresRemote, !routeDecision.allowFileFallback {
            return nil
        }

        return readLocalOperatorChannelXTCommands(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    static func requestOperatorChannelXTCommandResults(
        projectId: String? = nil,
        limit: Int = 200
    ) async -> OperatorChannelXTCommandResultSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote, !routeDecision.allowFileFallback {
            return nil
        }

        if routeDecision.requiresRemote, !routeDecision.allowFileFallback {
            return nil
        }

        return readLocalOperatorChannelXTCommandResults(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    @discardableResult
    static func appendOperatorChannelXTCommandResult(
        _ result: OperatorChannelXTCommandResultItem
    ) -> Bool {
        let commandId = result.commandId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commandId.isEmpty else { return false }

        let baseDir = HubPaths.baseDir()
        let url = baseDir.appendingPathComponent("operator_channel_xt_command_results_status.json")
        let existing = readLocalOperatorChannelXTCommandResults(projectId: nil, limit: 1_000)
        var deduped: [String: OperatorChannelXTCommandResultItem] = [:]
        for item in existing?.items ?? [] {
            deduped[item.commandId] = item
        }
        deduped[commandId] = result

        let merged = deduped.values.sorted { lhs, rhs in
            let leftTimestamp = max(lhs.completedAtMs, lhs.createdAtMs)
            let rightTimestamp = max(rhs.completedAtMs, rhs.createdAtMs)
            if leftTimestamp != rightTimestamp { return leftTimestamp > rightTimestamp }
            return lhs.commandId.localizedCaseInsensitiveCompare(rhs.commandId) == .orderedAscending
        }

        let payload = OperatorChannelXTCommandResultSnapshot(
            source: "xterminal_operator_channel_result_writer",
            updatedAtMs: max(
                result.completedAtMs,
                result.createdAtMs,
                Date().timeIntervalSince1970 * 1000.0
            ),
            items: Array(merged.prefix(1_000))
        )
        return writeLocalSnapshot(payload, to: url)
    }

    private struct RemoteRuntimeSurfaceOverridesFetchResult {
        var snapshot: RuntimeSurfaceOverridesSnapshot
        var cacheHit: Bool
    }

    private enum RuntimeSurfaceFetchWaitOutcome {
        case completed(RuntimeSurfaceOverridesSnapshot?)
        case timedOut
    }

    private static func runtimeSurfaceInFlightTask(
        for key: HubRemoteRuntimeSurfaceOverrideCache.Key,
        createIfMissing: () -> Task<RuntimeSurfaceOverridesSnapshot?, Never>
    ) -> (task: Task<RuntimeSurfaceOverridesSnapshot?, Never>, isOwner: Bool) {
        runtimeSurfaceFetchLock.lock()
        defer { runtimeSurfaceFetchLock.unlock() }
        if let task = inFlightRuntimeSurfaceOverrideFetches[key] {
            return (task, false)
        }
        let task = createIfMissing()
        inFlightRuntimeSurfaceOverrideFetches[key] = task
        return (task, true)
    }

    private static func clearRuntimeSurfaceInFlightTask(
        for key: HubRemoteRuntimeSurfaceOverrideCache.Key
    ) {
        runtimeSurfaceFetchLock.lock()
        defer { runtimeSurfaceFetchLock.unlock() }
        inFlightRuntimeSurfaceOverrideFetches[key] = nil
    }

    private static func waitForRuntimeSurfaceFetchTask(
        _ task: Task<RuntimeSurfaceOverridesSnapshot?, Never>,
        for key: HubRemoteRuntimeSurfaceOverrideCache.Key,
        cache: HubRemoteRuntimeSurfaceOverrideCache,
        timeoutSec: Double
    ) async -> RuntimeSurfaceOverridesSnapshot? {
        let clampedTimeoutNs = UInt64(
            (max(0.2, min(4.0, timeoutSec)) * 1_000_000_000).rounded()
        )
        let outcome: RuntimeSurfaceFetchWaitOutcome = await withCheckedContinuation { continuation in
            let lock = NSLock()
            var resumed = false

            func resumeOnce(_ value: RuntimeSurfaceFetchWaitOutcome) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }

            Task.detached(priority: .userInitiated) {
                resumeOnce(.completed(await task.value))
            }
            Task.detached(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: clampedTimeoutNs)
                resumeOnce(.timedOut)
            }
        }

        switch outcome {
        case .completed(let snapshot):
            return snapshot
        case .timedOut:
            task.cancel()
            clearRuntimeSurfaceInFlightTask(for: key)
            await cache.markMiss(for: key)
            return nil
        }
    }

    private static func resetRuntimeSurfaceRemoteStateForTesting() {
        runtimeSurfaceFetchLock.lock()
        let tasks = Array(inFlightRuntimeSurfaceOverrideFetches.values)
        inFlightRuntimeSurfaceOverrideFetches.removeAll(keepingCapacity: false)
        runtimeSurfaceFetchLock.unlock()
        tasks.forEach { $0.cancel() }
        remoteRuntimeSurfaceOverrideCache = HubRemoteRuntimeSurfaceOverrideCache(
            ttlSeconds: remoteRuntimeSurfaceOverrideCacheTTLSeconds
        )
    }

    private static func fetchRemoteRuntimeSurfaceOverrides(
        projectId: String?,
        limit: Int,
        bypassCache: Bool,
        timeoutSec: Double
    ) async -> RemoteRuntimeSurfaceOverridesFetchResult? {
        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))
        let cache = remoteRuntimeSurfaceOverrideCache
        let cacheKey = HubRemoteRuntimeSurfaceOverrideCache.Key(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
        if !bypassCache, let cached = await cache.snapshot(for: cacheKey) {
            return RemoteRuntimeSurfaceOverridesFetchResult(snapshot: cached, cacheHit: true)
        }
        if !bypassCache, await cache.hasRecentMiss(for: cacheKey) {
            return nil
        }
        let taskFactory = {
            Task<RuntimeSurfaceOverridesSnapshot?, Never> {
            let remote: HubRemoteRuntimeSurfaceOverridesResult
            if let override = remoteRuntimeSurfaceOverridesOverride() {
                remote = await override(normalizedProjectId, boundedLimit, timeoutSec)
            } else {
                remote = await HubPairingCoordinator.shared.fetchRemoteRuntimeSurfaceOverrides(
                    options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                    projectId: normalizedProjectId,
                    limit: boundedLimit,
                    timeoutSec: timeoutSec
                )
            }
            guard remote.ok else {
                await cache.markMiss(for: cacheKey)
                return nil
            }

            let snapshot = RuntimeSurfaceOverridesSnapshot(
                source: remote.source.trimmingCharacters(in: .whitespacesAndNewlines),
                updatedAtMs: max(0, Int64(remote.updatedAtMs.rounded())),
                items: remote.items.map { row in
                    RuntimeSurfaceOverrideItem(
                        projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                        overrideMode: row.overrideMode,
                        updatedAtMs: max(0, Int64(row.updatedAtMs.rounded())),
                        reason: row.reason.trimmingCharacters(in: .whitespacesAndNewlines),
                        auditRef: row.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            )
            await cache.store(snapshot, for: cacheKey)
            return snapshot
        }
        }
        if !bypassCache {
            let inFlight = runtimeSurfaceInFlightTask(for: cacheKey, createIfMissing: taskFactory)
            if !inFlight.isOwner {
                guard let snapshot = await waitForRuntimeSurfaceFetchTask(
                    inFlight.task,
                    for: cacheKey,
                    cache: cache,
                    timeoutSec: timeoutSec
                ) else {
                    return nil
                }
                return RemoteRuntimeSurfaceOverridesFetchResult(snapshot: snapshot, cacheHit: false)
            }
            defer { clearRuntimeSurfaceInFlightTask(for: cacheKey) }
            let snapshot = await waitForRuntimeSurfaceFetchTask(
                inFlight.task,
                for: cacheKey,
                cache: cache,
                timeoutSec: timeoutSec
            )
            guard let snapshot else { return nil }
            return RemoteRuntimeSurfaceOverridesFetchResult(snapshot: snapshot, cacheHit: false)
        }
        let directTask = taskFactory()
        let snapshot = await waitForRuntimeSurfaceFetchTask(
            directTask,
            for: cacheKey,
            cache: cache,
            timeoutSec: timeoutSec
        )
        guard let snapshot else { return nil }
        return RemoteRuntimeSurfaceOverridesFetchResult(snapshot: snapshot, cacheHit: false)
    }

    static func requestRuntimeSurfaceOverrides(
        projectId: String? = nil,
        limit: Int = 200,
        bypassCache: Bool = false,
        timeoutSec: Double = 1.0
    ) async -> RuntimeSurfaceOverridesSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            if let remote = await fetchRemoteRuntimeSurfaceOverrides(
                projectId: normalizedProjectId,
                limit: boundedLimit,
                bypassCache: bypassCache,
                timeoutSec: timeoutSec
            ) {
                return remote.snapshot
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return readLocalRuntimeSurfaceOverrides(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    @available(*, deprecated, message: "Use requestRuntimeSurfaceOverrides(projectId:limit:bypassCache:)")
    static func requestAutonomyPolicyOverrides(
        projectId: String? = nil,
        limit: Int = 200,
        bypassCache: Bool = false
    ) async -> AutonomyPolicyOverridesSnapshot? {
        await requestRuntimeSurfaceOverrides(
            projectId: projectId,
            limit: limit,
            bypassCache: bypassCache
        )
    }

    static func requestSecretVaultSnapshot(
        scope: String? = nil,
        namePrefix: String? = nil,
        projectId: String? = nil,
        limit: Int = 200
    ) async -> SecretVaultSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedScope = normalized(scope)?.lowercased()
        let normalizedNamePrefix = normalized(namePrefix)?.lowercased()
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteSecretVaultItems(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                scope: normalizedScope,
                namePrefix: normalizedNamePrefix,
                limit: boundedLimit
            )
            if remote.ok {
                return SecretVaultSnapshot(
                    source: remote.source.trimmingCharacters(in: .whitespacesAndNewlines),
                    updatedAtMs: max(0, Int64(remote.updatedAtMs.rounded())),
                    items: remote.items.map { row in
                        SecretVaultItem(
                            itemId: row.itemId.trimmingCharacters(in: .whitespacesAndNewlines),
                            scope: row.scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                            name: row.name.trimmingCharacters(in: .whitespacesAndNewlines),
                            sensitivity: row.sensitivity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                            createdAtMs: max(0, Int64(row.createdAtMs.rounded())),
                            updatedAtMs: max(0, Int64(row.updatedAtMs.rounded()))
                        )
                    }
                )
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        if let snapshot = await requestSecretVaultSnapshotViaLocalIPC(
            scope: normalizedScope,
            namePrefix: normalizedNamePrefix,
            projectId: normalizedProjectId,
            limit: boundedLimit
        ) {
            return snapshot
        }

        return readLocalSecretVaultSnapshot(
            scope: normalizedScope,
            namePrefix: normalizedNamePrefix,
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    static func createProtectedSecret(
        _ payload: SecretCreateRequestPayload
    ) async -> SecretCreateResult {
        let normalizedScope = normalized(payload.scope)?.lowercased()
        let normalizedName = normalized(payload.name)
        let normalizedPlaintext = normalized(payload.plaintext)
        let normalizedSensitivity = normalized(payload.sensitivity)?.lowercased() ?? "secret"

        guard normalizedScope != nil, normalizedName != nil, normalizedPlaintext != nil else {
            return SecretCreateResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                item: nil,
                reasonCode: "invalid_request"
            )
        }

        let sanitizedPayload = SecretCreateRequestPayload(
            scope: normalizedScope ?? "",
            name: normalizedName ?? "",
            plaintext: normalizedPlaintext ?? "",
            sensitivity: normalizedSensitivity,
            projectId: normalized(payload.projectId),
            displayName: normalized(payload.displayName),
            reason: normalized(payload.reason)
        )

        let routeDecision = await currentRouteDecision()
        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.createRemoteSecretVaultItem(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                scope: sanitizedPayload.scope,
                name: sanitizedPayload.name,
                plaintext: sanitizedPayload.plaintext,
                sensitivity: sanitizedPayload.sensitivity,
                projectId: sanitizedPayload.projectId,
                displayName: sanitizedPayload.displayName,
                reason: sanitizedPayload.reason
            )
            if remote.ok || !routeDecision.allowFileFallback {
                return mapSecretVaultCreateResult(remote)
            }
        }

        if routeDecision.requiresRemote {
            return SecretCreateResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                item: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        return await createProtectedSecretViaLocalIPC(sanitizedPayload)
    }

    static func beginSecretUse(
        _ payload: SecretUseRequestPayload
    ) async -> SecretUseResult {
        let override = secretUseOverrideSnapshotForTesting()
        if let override {
            return await override(payload)
        }

        let normalizedItemId = normalized(payload.itemId)
        let normalizedScope = normalized(payload.scope)?.lowercased()
        let normalizedName = normalized(payload.name)
        let normalizedPurpose = normalized(payload.purpose)

        guard normalizedPurpose != nil,
              normalizedItemId != nil || (normalizedScope != nil && normalizedName != nil) else {
            return SecretUseResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                useToken: nil,
                itemId: nil,
                expiresAtMs: nil,
                reasonCode: "invalid_request"
            )
        }

        let sanitizedPayload = SecretUseRequestPayload(
            itemId: normalizedItemId,
            scope: normalizedScope,
            name: normalizedName,
            projectId: normalized(payload.projectId),
            purpose: normalizedPurpose ?? "",
            target: normalized(payload.target),
            ttlMs: max(1_000, min(600_000, payload.ttlMs))
        )

        let routeDecision = await currentRouteDecision()
        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.beginRemoteSecretVaultUse(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                itemId: sanitizedPayload.itemId,
                scope: sanitizedPayload.scope,
                name: sanitizedPayload.name,
                projectId: sanitizedPayload.projectId,
                purpose: sanitizedPayload.purpose,
                target: sanitizedPayload.target,
                ttlMs: sanitizedPayload.ttlMs
            )
            if remote.ok || !routeDecision.allowFileFallback {
                return mapSecretVaultUseResult(remote)
            }
        }

        if routeDecision.requiresRemote {
            return SecretUseResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                useToken: nil,
                itemId: sanitizedPayload.itemId,
                expiresAtMs: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        return await beginSecretUseViaLocalIPC(sanitizedPayload)
    }

    static func redeemSecretUse(
        _ payload: SecretRedeemRequestPayload
    ) async -> SecretRedeemResult {
        let override = secretRedeemOverrideSnapshotForTesting()
        if let override {
            return await override(payload)
        }

        let normalizedUseToken = normalized(payload.useToken)
        guard normalizedUseToken != nil else {
            return SecretRedeemResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "invalid_request"
            )
        }

        let sanitizedPayload = SecretRedeemRequestPayload(
            useToken: normalizedUseToken ?? "",
            projectId: normalized(payload.projectId)
        )

        let routeDecision = await currentRouteDecision()
        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.redeemRemoteSecretVaultUse(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                useToken: sanitizedPayload.useToken,
                projectId: sanitizedPayload.projectId
            )
            if remote.ok || !routeDecision.allowFileFallback {
                return mapSecretVaultRedeemResult(remote)
            }
        }

        if routeDecision.requiresRemote {
            return SecretRedeemResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        return await redeemSecretUseViaLocalIPC(sanitizedPayload)
    }

    static func requestProjectRuntimeSurfaceOverride(
        projectId: String,
        bypassCache: Bool = false,
        timeoutSec: Double = 1.0
    ) async -> AXProjectRuntimeSurfaceRemoteOverrideSnapshot? {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectId.isEmpty else { return nil }
        if !bypassCache {
            let sharedCache = remoteRuntimeSurfaceOverrideCache
            let sharedCacheKey = HubRemoteRuntimeSurfaceOverrideCache.Key(projectId: nil, limit: 500)
            if let sharedSnapshot = await requestRuntimeSurfaceOverrides(
                projectId: nil,
                limit: 500,
                bypassCache: false,
                timeoutSec: timeoutSec
            ) {
                if let row = sharedSnapshot.items.first(where: { $0.projectId == normalizedProjectId }) {
                    return AXProjectRuntimeSurfaceRemoteOverrideSnapshot(
                        projectId: row.projectId,
                        overrideMode: row.overrideMode,
                        updatedAtMs: row.updatedAtMs,
                        source: sharedSnapshot.source,
                        reason: row.reason.isEmpty ? nil : row.reason,
                        auditRef: row.auditRef.isEmpty ? nil : row.auditRef
                    )
                }
                if sharedSnapshot.items.count < 500 {
                    return nil
                }
            }
            if await sharedCache.hasRecentMiss(for: sharedCacheKey) {
                return nil
            }
        }

        guard let snapshot = await requestRuntimeSurfaceOverrides(
            projectId: normalizedProjectId,
            limit: 1,
            bypassCache: bypassCache,
            timeoutSec: timeoutSec
        ) else {
            return nil
        }
        guard let row = snapshot.items.first(where: { $0.projectId == normalizedProjectId }) else {
            return nil
        }
        return AXProjectRuntimeSurfaceRemoteOverrideSnapshot(
            projectId: row.projectId,
            overrideMode: row.overrideMode,
            updatedAtMs: row.updatedAtMs,
            source: snapshot.source,
            reason: row.reason.isEmpty ? nil : row.reason,
            auditRef: row.auditRef.isEmpty ? nil : row.auditRef
        )
    }

    @available(*, deprecated, message: "Use requestProjectRuntimeSurfaceOverride(projectId:bypassCache:)")
    static func requestProjectAutonomyPolicyOverride(
        projectId: String,
        bypassCache: Bool = false
    ) async -> AXProjectAutonomyRemoteOverrideSnapshot? {
        await requestProjectRuntimeSurfaceOverride(
            projectId: projectId,
            bypassCache: bypassCache
        )
    }

    static func approvePendingGrantRequest(
        grantRequestId: String,
        projectId: String? = nil,
        requestedTtlSec: Int? = nil,
        requestedTokenCap: Int? = nil,
        note: String? = nil
    ) async -> PendingGrantActionResult {
        let normalizedGrantId = normalized(grantRequestId)
        guard let normalizedGrantId else {
            return PendingGrantActionResult(
                ok: false,
                decision: .failed,
                source: "hub_runtime_grpc",
                grantRequestId: nil,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "grant_request_id_empty"
            )
        }

        let routeDecision = await currentRouteDecision()
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.approveRemotePendingGrantRequest(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                grantRequestId: normalizedGrantId,
                projectId: normalizedProjectId,
                ttlSec: requestedTtlSec,
                tokenCap: requestedTokenCap,
                note: note
            )
            let result = mapPendingGrantActionResult(remote, defaultGrantRequestId: normalizedGrantId)
            if result.ok {
                await noteRemoteMemoryGrantStateChanged(projectId: normalizedProjectId)
            }
            return result
        }

        let fallbackReason = routeDecision.requiresRemote
            ? (routeDecision.remoteUnavailableReasonCode ?? "hub_env_missing")
            : "pending_grant_action_not_supported"
        return PendingGrantActionResult(
            ok: false,
            decision: .failed,
            source: "hub_runtime_grpc",
            grantRequestId: normalizedGrantId,
            grantId: nil,
            expiresAtMs: nil,
            reasonCode: fallbackReason
        )
    }

    static func denyPendingGrantRequest(
        grantRequestId: String,
        projectId: String? = nil,
        reason: String? = nil
    ) async -> PendingGrantActionResult {
        let normalizedGrantId = normalized(grantRequestId)
        guard let normalizedGrantId else {
            return PendingGrantActionResult(
                ok: false,
                decision: .failed,
                source: "hub_runtime_grpc",
                grantRequestId: nil,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "grant_request_id_empty"
            )
        }

        let routeDecision = await currentRouteDecision()
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.denyRemotePendingGrantRequest(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                grantRequestId: normalizedGrantId,
                projectId: normalizedProjectId,
                reason: reason
            )
            let result = mapPendingGrantActionResult(remote, defaultGrantRequestId: normalizedGrantId)
            if result.ok {
                await noteRemoteMemoryGrantStateChanged(projectId: normalizedProjectId)
            }
            return result
        }

        let fallbackReason = routeDecision.requiresRemote
            ? (routeDecision.remoteUnavailableReasonCode ?? "hub_env_missing")
            : "pending_grant_action_not_supported"
        return PendingGrantActionResult(
            ok: false,
            decision: .failed,
            source: "hub_runtime_grpc",
            grantRequestId: normalizedGrantId,
            grantId: nil,
            expiresAtMs: nil,
            reasonCode: fallbackReason
        )
    }

    static func stageSupervisorCandidateReview(
        candidateRequestId: String,
        projectId: String? = nil
    ) async -> SupervisorCandidateReviewStageResult {
        let normalizedCandidateRequestId = normalized(candidateRequestId)
        guard let normalizedCandidateRequestId else {
            return SupervisorCandidateReviewStageResult(
                ok: false,
                staged: false,
                idempotent: false,
                source: "hub_memory_v1_grpc",
                reviewState: "",
                durablePromotionState: "",
                promotionBoundary: "",
                candidateRequestId: nil,
                evidenceRef: nil,
                editSessionId: nil,
                pendingChangeId: nil,
                docId: nil,
                baseVersion: nil,
                workingVersion: nil,
                sessionRevision: 0,
                status: nil,
                markdown: nil,
                createdAtMs: 0,
                updatedAtMs: 0,
                expiresAtMs: 0,
                reasonCode: "candidate_request_id_empty"
            )
        }

        let routeDecision = await currentRouteDecision()
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.stageRemoteSupervisorCandidateReview(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                candidateRequestId: normalizedCandidateRequestId,
                projectId: normalizedProjectId
            )
            return SupervisorCandidateReviewStageResult(
                ok: remote.ok,
                staged: remote.staged,
                idempotent: remote.idempotent,
                source: remote.source,
                reviewState: remote.reviewState,
                durablePromotionState: remote.durablePromotionState,
                promotionBoundary: remote.promotionBoundary,
                candidateRequestId: remote.candidateRequestId ?? normalizedCandidateRequestId,
                evidenceRef: remote.evidenceRef,
                editSessionId: remote.editSessionId,
                pendingChangeId: remote.pendingChangeId,
                docId: remote.docId,
                baseVersion: remote.baseVersion,
                workingVersion: remote.workingVersion,
                sessionRevision: remote.sessionRevision,
                status: remote.status,
                markdown: remote.markdown,
                createdAtMs: max(0, remote.createdAtMs),
                updatedAtMs: max(0, remote.updatedAtMs),
                expiresAtMs: max(0, remote.expiresAtMs),
                reasonCode: normalizedReasonCode(
                    remote.reasonCode,
                    fallback: remote.ok ? nil : "supervisor_candidate_review_stage_failed"
                )
            )
        }

        let fallbackReason = routeDecision.requiresRemote
            ? normalizedReasonCode(
                routeDecision.remoteUnavailableReasonCode,
                fallback: "hub_env_missing"
            )
            : "supervisor_candidate_review_stage_file_ipc_not_supported"
        return SupervisorCandidateReviewStageResult(
            ok: false,
            staged: false,
            idempotent: false,
            source: routeDecision.requiresRemote ? "hub_memory_v1_grpc" : "file_ipc",
            reviewState: "",
            durablePromotionState: "",
            promotionBoundary: "",
            candidateRequestId: normalizedCandidateRequestId,
            evidenceRef: nil,
            editSessionId: nil,
            pendingChangeId: nil,
            docId: nil,
            baseVersion: nil,
            workingVersion: nil,
            sessionRevision: 0,
            status: nil,
            markdown: nil,
            createdAtMs: 0,
            updatedAtMs: 0,
            expiresAtMs: 0,
            reasonCode: fallbackReason
        )
    }

    static func requestSupervisorBriefProjection(
        _ payload: SupervisorBriefProjectionRequestPayload
    ) async -> SupervisorBriefProjectionResult {
        let normalizedRequestId = normalized(payload.requestId)
        guard let normalizedRequestId else {
            return SupervisorBriefProjectionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                projection: nil,
                reasonCode: "request_id_empty"
            )
        }

        let normalizedProjectId = normalized(payload.projectId)
        guard let normalizedProjectId else {
            return SupervisorBriefProjectionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                projection: nil,
                reasonCode: "project_id_empty"
            )
        }

        let routeDecision = await currentRouteDecision()
        let projectionKind = normalized(payload.projectionKind) ?? "progress_brief"
        let trigger = normalized(payload.trigger) ?? "daily_digest"
        let boundedEvidenceRefs = max(0, min(12, payload.maxEvidenceRefs))

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteSupervisorBriefProjection(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                requestId: normalizedRequestId,
                projectId: normalizedProjectId,
                runId: normalized(payload.runId),
                missionId: normalized(payload.missionId),
                projectionKind: projectionKind,
                trigger: trigger,
                includeTtsScript: payload.includeTtsScript,
                includeCardSummary: payload.includeCardSummary,
                maxEvidenceRefs: boundedEvidenceRefs
            )
            let projection = remote.projection.map { row in
                SupervisorBriefProjectionSnapshot(
                    schemaVersion: row.schemaVersion,
                    projectionId: row.projectionId,
                    projectionKind: row.projectionKind,
                    projectId: row.projectId,
                    runId: row.runId,
                    missionId: row.missionId,
                    trigger: row.trigger,
                    status: row.status,
                    criticalBlocker: row.criticalBlocker,
                    topline: row.topline,
                    nextBestAction: row.nextBestAction,
                    pendingGrantCount: max(0, row.pendingGrantCount),
                    ttsScript: row.ttsScript,
                    cardSummary: row.cardSummary,
                    evidenceRefs: row.evidenceRefs,
                    generatedAtMs: max(0, row.generatedAtMs),
                    expiresAtMs: max(0, row.expiresAtMs),
                    auditRef: row.auditRef
                )
            }
            return SupervisorBriefProjectionResult(
                ok: remote.ok && projection != nil,
                source: remote.source,
                projection: projection,
                reasonCode: normalizedReasonCode(
                    remote.reasonCode,
                    fallback: remote.ok ? nil : "supervisor_brief_projection_failed"
                )
            )
        }

        let fallbackReason = routeDecision.requiresRemote
            ? normalizedReasonCode(
                routeDecision.remoteUnavailableReasonCode,
                fallback: "hub_env_missing"
            )
            : "supervisor_brief_projection_file_ipc_not_supported"
        return SupervisorBriefProjectionResult(
            ok: false,
            source: routeDecision.requiresRemote ? "hub_supervisor_grpc" : "file_ipc",
            projection: nil,
            reasonCode: fallbackReason
        )
    }

    static func requestSupervisorRouteDecision(
        _ payload: SupervisorRouteDecisionRequestPayload
    ) async -> SupervisorRouteDecisionResult {
        let normalizedRequestId = normalized(payload.requestId)
        guard let normalizedRequestId else {
            return SupervisorRouteDecisionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                route: nil,
                governanceRuntimeReadiness: nil,
                reasonCode: "request_id_empty"
            )
        }

        let normalizedProjectId = normalized(payload.projectId)
        guard let normalizedProjectId else {
            return SupervisorRouteDecisionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                route: nil,
                governanceRuntimeReadiness: nil,
                reasonCode: "project_id_empty"
            )
        }

        let routeDecision = await currentRouteDecision()
        let surfaceType = normalized(payload.surfaceType) ?? "xt_ui"
        let trustLevel = normalized(payload.trustLevel) ?? "paired_surface"
        let normalizedIntentType = normalized(payload.normalizedIntentType) ?? "directive"

        if routeDecision.preferRemote {
            let remote: HubRemoteSupervisorRouteDecisionResult
            if let override = supervisorRouteDecisionOverride() {
                let result = await override(
                    SupervisorRouteDecisionRequestPayload(
                        requestId: normalizedRequestId,
                        projectId: normalizedProjectId,
                        runId: normalized(payload.runId),
                        missionId: normalized(payload.missionId),
                        surfaceType: surfaceType,
                        trustLevel: trustLevel,
                        normalizedIntentType: normalizedIntentType,
                        preferredDeviceId: normalized(payload.preferredDeviceId),
                        requireXT: payload.requireXT,
                        requireRunner: payload.requireRunner,
                        actorRef: normalized(payload.actorRef),
                        conversationId: normalized(payload.conversationId),
                        threadKey: normalized(payload.threadKey)
                    )
                )
                return result
            } else {
                remote = await HubPairingCoordinator.shared.fetchRemoteSupervisorRouteDecision(
                    options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                    requestId: normalizedRequestId,
                    projectId: normalizedProjectId,
                    runId: normalized(payload.runId),
                    missionId: normalized(payload.missionId),
                    surfaceType: surfaceType,
                    trustLevel: trustLevel,
                    normalizedIntentType: normalizedIntentType,
                    preferredDeviceId: normalized(payload.preferredDeviceId),
                    requireXT: payload.requireXT,
                    requireRunner: payload.requireRunner,
                    actorRef: normalized(payload.actorRef),
                    conversationId: normalized(payload.conversationId),
                    threadKey: normalized(payload.threadKey)
                )
            }

            let route = remote.route.map { row in
                SupervisorRouteDecisionSnapshot(
                    schemaVersion: row.schemaVersion,
                    routeId: row.routeId,
                    requestId: row.requestId,
                    projectId: row.projectId,
                    runId: row.runId,
                    missionId: row.missionId,
                    decision: row.decision,
                    riskTier: row.riskTier,
                    preferredDeviceId: row.preferredDeviceId,
                    resolvedDeviceId: row.resolvedDeviceId,
                    runnerId: row.runnerId,
                    xtOnline: row.xtOnline,
                    runnerRequired: row.runnerRequired,
                    sameProjectScope: row.sameProjectScope,
                    requiresGrant: row.requiresGrant,
                    grantScope: row.grantScope,
                    denyCode: row.denyCode,
                    updatedAtMs: max(0, row.updatedAtMs),
                    auditRef: row.auditRef
                )
            }
            let governanceRuntimeReadiness = remote.governanceRuntimeReadiness.map { row in
                SupervisorRouteGovernanceRuntimeReadinessSnapshot(
                    schemaVersion: row.schemaVersion,
                    source: row.source,
                    governanceSurface: row.governanceSurface,
                    context: row.context,
                    configured: row.configured,
                    state: row.state,
                    runtimeReady: row.runtimeReady,
                    projectId: row.projectId,
                    blockers: row.blockers,
                    blockedComponentKeys: row.blockedComponentKeys,
                    missingReasonCodes: row.missingReasonCodes,
                    summaryLine: row.summaryLine,
                    missingSummaryLine: row.missingSummaryLine,
                    components: row.components.map { component in
                        SupervisorRouteGovernanceComponentSnapshot(
                            key: component.key,
                            state: component.state,
                            denyCode: component.denyCode,
                            summaryLine: component.summaryLine,
                            missingReasonCodes: component.missingReasonCodes
                        )
                    }
                )
            }
            return SupervisorRouteDecisionResult(
                ok: remote.ok && route != nil,
                source: remote.source,
                route: route,
                governanceRuntimeReadiness: governanceRuntimeReadiness,
                reasonCode: normalizedReasonCode(
                    remote.reasonCode,
                    fallback: remote.ok ? nil : "supervisor_route_decision_failed"
                )
            )
        }

        let fallbackReason = routeDecision.requiresRemote
            ? normalizedReasonCode(
                routeDecision.remoteUnavailableReasonCode,
                fallback: "hub_env_missing"
            )
            : "supervisor_route_file_ipc_not_supported"
        return SupervisorRouteDecisionResult(
            ok: false,
            source: routeDecision.requiresRemote ? "hub_supervisor_grpc" : "file_ipc",
            route: nil,
            governanceRuntimeReadiness: nil,
            reasonCode: fallbackReason
        )
    }

    static func issueVoiceGrantChallenge(
        _ payload: VoiceGrantChallengeRequestPayload
    ) async -> VoiceGrantChallengeResult {
        let normalizedRequestId = normalized(payload.requestId)
        guard let normalizedRequestId else {
            return VoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: "request_id_empty"
            )
        }

        let normalizedTemplateId = normalized(payload.templateId)
        let normalizedActionDigest = normalized(payload.actionDigest)
        let normalizedScopeDigest = normalized(payload.scopeDigest)
        let normalizedProjectId = normalized(payload.projectId)
        guard normalizedTemplateId != nil, normalizedActionDigest != nil, normalizedScopeDigest != nil else {
            return VoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: "invalid_request"
            )
        }

        if let override = voiceGrantChallengeOverride() {
            let result = await override(payload)
            if shouldInvalidateRemoteMemoryForVoiceGrantChallenge(result) {
                await noteRemoteMemoryGrantStateChanged(projectId: normalizedProjectId)
            }
            return result
        }

        let routeDecision = await currentRouteDecision()
        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.issueRemoteVoiceGrantChallenge(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                requestId: normalizedRequestId,
                projectId: normalizedProjectId,
                templateId: normalizedTemplateId ?? "",
                actionDigest: normalizedActionDigest ?? "",
                scopeDigest: normalizedScopeDigest ?? "",
                amountDigest: normalized(payload.amountDigest),
                challengeCode: normalized(payload.challengeCode),
                riskLevel: normalized(payload.riskLevel) ?? "high",
                boundDeviceId: normalized(payload.boundDeviceId),
                mobileTerminalId: normalized(payload.mobileTerminalId),
                allowVoiceOnly: payload.allowVoiceOnly,
                requiresMobileConfirm: payload.requiresMobileConfirm,
                ttlMs: max(10_000, min(600_000, payload.ttlMs))
            )
            let result = mapVoiceGrantChallengeResult(remote)
            if shouldInvalidateRemoteMemoryForVoiceGrantChallenge(result) {
                await noteRemoteMemoryGrantStateChanged(projectId: normalizedProjectId)
            }
            return result
        }

        if routeDecision.requiresRemote {
            return VoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        return VoiceGrantChallengeResult(
            ok: false,
            source: "file_ipc",
            challenge: nil,
            reasonCode: "voice_grant_file_ipc_not_supported"
        )
    }

    static func verifyVoiceGrantResponse(
        _ payload: VoiceGrantVerificationPayload
    ) async -> VoiceGrantVerificationResult {
        let normalizedRequestId = normalized(payload.requestId)
        guard let normalizedRequestId else {
            return VoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: nil,
                transcriptHash: nil,
                semanticMatchScore: 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: payload.mobileConfirmed,
                reasonCode: "request_id_empty"
            )
        }

        let normalizedChallengeId = normalized(payload.challengeId)
        let normalizedProjectId = normalized(payload.projectId)
        guard let normalizedChallengeId else {
            return VoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: nil,
                transcriptHash: nil,
                semanticMatchScore: 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: payload.mobileConfirmed,
                reasonCode: "challenge_id_empty"
            )
        }

        let normalizedVerifyNonce = normalized(payload.verifyNonce)
        guard let normalizedVerifyNonce else {
            return VoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: normalizedChallengeId,
                transcriptHash: nil,
                semanticMatchScore: 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: payload.mobileConfirmed,
                reasonCode: "verify_nonce_empty"
            )
        }

        if let override = voiceGrantVerificationOverride() {
            let result = await override(payload)
            if shouldInvalidateRemoteMemoryForVoiceGrantVerification(result) {
                await noteRemoteMemoryGrantStateChanged(projectId: normalizedProjectId)
            }
            return result
        }

        let routeDecision = await currentRouteDecision()
        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.verifyRemoteVoiceGrantResponse(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                requestId: normalizedRequestId,
                projectId: normalizedProjectId,
                challengeId: normalizedChallengeId,
                challengeCode: normalized(payload.challengeCode),
                transcript: payload.transcript,
                transcriptHash: normalized(payload.transcriptHash),
                semanticMatchScore: payload.semanticMatchScore,
                parsedActionDigest: normalized(payload.parsedActionDigest),
                parsedScopeDigest: normalized(payload.parsedScopeDigest),
                parsedAmountDigest: normalized(payload.parsedAmountDigest),
                verifyNonce: normalizedVerifyNonce,
                boundDeviceId: normalized(payload.boundDeviceId),
                mobileConfirmed: payload.mobileConfirmed
            )
            let result = mapVoiceGrantVerificationResult(remote)
            if shouldInvalidateRemoteMemoryForVoiceGrantVerification(result) {
                await noteRemoteMemoryGrantStateChanged(projectId: normalizedProjectId)
            }
            return result
        }

        if routeDecision.requiresRemote {
            return VoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: normalizedChallengeId,
                transcriptHash: nil,
                semanticMatchScore: payload.semanticMatchScore ?? 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: payload.mobileConfirmed,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        return VoiceGrantVerificationResult(
            ok: false,
            verified: false,
            decision: .failed,
            source: "file_ipc",
            denyCode: nil,
            challengeId: normalizedChallengeId,
            transcriptHash: nil,
            semanticMatchScore: payload.semanticMatchScore ?? 0,
            challengeMatch: false,
            deviceBindingOK: false,
            mobileConfirmed: payload.mobileConfirmed,
            reasonCode: "voice_grant_file_ipc_not_supported"
        )
    }

    private static func requestMemoryContextViaLocalIPC(
        payload: MemoryContextPayload,
        timeoutSec: Double
    ) async -> LocalMemoryContextIPCResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return LocalMemoryContextIPCResult(
                response: nil,
                reasonCode: "hub_not_connected",
                detail: nil
            )
        }

        let reqId = UUID().uuidString
        let req = MemoryContextIPCRequest(type: "memory_context", reqId: reqId, memoryContext: payload)

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let data: Data
            do {
                data = try JSONEncoder().encode(req)
            } catch {
                return LocalMemoryContextIPCResult(
                    response: nil,
                    reasonCode: "memory_context_encode_failed",
                    detail: summarized(error)
                )
            }
            let writeStatus = Self.writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_mem",
                tmpPrefix: ".xterminal_mem",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return LocalMemoryContextIPCResult(
                    response: nil,
                    reasonCode: "memory_context_write_failed",
                    detail: normalized(writeStatus.requestError)
                )
            }

            guard let ack = await pollMemoryContextResponse(
                baseDir: transport.baseDir,
                reqId: reqId,
                timeoutSec: timeoutSec
            ) else {
                return LocalMemoryContextIPCResult(
                    response: nil,
                    reasonCode: "ack_timeout",
                    detail: "memory context ack timeout"
                )
            }
            guard ack.ok else {
                return LocalMemoryContextIPCResult(
                    response: nil,
                    reasonCode: normalizedReasonCode(ack.error, fallback: "memory_context_failed"),
                    detail: normalized(ack.error)
                )
            }
            return LocalMemoryContextIPCResult(
                response: ack.memoryContext,
                reasonCode: nil,
                detail: nil
            )
        case "socket":
            guard let ack: MemoryContextIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: timeoutSec) else {
                return LocalMemoryContextIPCResult(
                    response: nil,
                    reasonCode: "socket_request_failed",
                    detail: "memory context socket request failed"
                )
            }
            guard ack.ok else {
                return LocalMemoryContextIPCResult(
                    response: nil,
                    reasonCode: normalizedReasonCode(ack.error, fallback: "memory_context_failed"),
                    detail: normalized(ack.error)
                )
            }
            return LocalMemoryContextIPCResult(
                response: ack.memoryContext,
                reasonCode: nil,
                detail: nil
            )
        default:
            return LocalMemoryContextIPCResult(
                response: nil,
                reasonCode: "unsupported_ipc_mode",
                detail: "memory context local IPC mode unsupported"
            )
        }
    }

    static func requestMemoryRetrievalViaLocalIPC(
        payload: MemoryRetrievalPayload,
        timeoutSec: Double
    ) async -> MemoryRetrievalResponsePayload? {
        if let override = localMemoryRetrievalIPCOverride() {
            return await override(payload, timeoutSec)
        }
        guard let transport = localIPCTransport(ttl: 3.0) else { return nil }

        let reqId = UUID().uuidString
        let req = MemoryRetrievalIPCRequest(
            type: "memory_retrieval",
            reqId: reqId,
            memoryRetrieval: payload
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let data: Data
            do {
                data = try JSONEncoder().encode(req)
            } catch {
                return MemoryRetrievalResponsePayload(
                    requestId: payload.requestId,
                    status: "error",
                    resolvedScope: payload.scope,
                    source: "file_ipc",
                    scope: payload.scope,
                    auditRef: payload.auditRef,
                    reasonCode: "memory_retrieval_encode_failed",
                    detail: summarized(error),
                    snippets: [],
                    truncated: false,
                    budgetUsedChars: 0,
                    truncatedItems: 0,
                    redactedItems: 0
                )
            }
            let writeStatus = Self.writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_mem_retrieval",
                tmpPrefix: ".xterminal_mem_retrieval",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return MemoryRetrievalResponsePayload(
                    requestId: payload.requestId,
                    status: "error",
                    resolvedScope: payload.scope,
                    source: "file_ipc",
                    scope: payload.scope,
                    auditRef: payload.auditRef,
                    reasonCode: "memory_retrieval_write_failed",
                    detail: normalized(writeStatus.requestError),
                    snippets: [],
                    truncated: false,
                    budgetUsedChars: 0,
                    truncatedItems: 0,
                    redactedItems: 0
                )
            }

            guard let ack = await pollMemoryRetrievalResponse(
                baseDir: transport.baseDir,
                reqId: reqId,
                timeoutSec: timeoutSec
            ) else {
                return MemoryRetrievalResponsePayload(
                    requestId: payload.requestId,
                    status: "error",
                    resolvedScope: payload.scope,
                    source: "file_ipc",
                    scope: payload.scope,
                    auditRef: payload.auditRef,
                    reasonCode: "ack_timeout",
                    detail: "memory retrieval ack timeout",
                    snippets: [],
                    truncated: false,
                    budgetUsedChars: 0,
                    truncatedItems: 0,
                    redactedItems: 0
                )
            }
            guard ack.ok else {
                return MemoryRetrievalResponsePayload(
                    requestId: payload.requestId,
                    status: "error",
                    resolvedScope: payload.scope,
                    source: "file_ipc",
                    scope: payload.scope,
                    auditRef: payload.auditRef,
                    reasonCode: normalizedReasonCode(ack.error, fallback: "memory_retrieval_failed"),
                    detail: normalized(ack.error),
                    snippets: [],
                    truncated: false,
                    budgetUsedChars: 0,
                    truncatedItems: 0,
                    redactedItems: 0
                )
            }
            return ack.memoryRetrieval
        case "socket":
            guard let ack: MemoryContextIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: timeoutSec) else {
                return MemoryRetrievalResponsePayload(
                    requestId: payload.requestId,
                    status: "error",
                    resolvedScope: payload.scope,
                    source: "socket_ipc",
                    scope: payload.scope,
                    auditRef: payload.auditRef,
                    reasonCode: "socket_request_failed",
                    detail: "memory retrieval socket request failed",
                    snippets: [],
                    truncated: false,
                    budgetUsedChars: 0,
                    truncatedItems: 0,
                    redactedItems: 0
                )
            }
            guard ack.ok else {
                return MemoryRetrievalResponsePayload(
                    requestId: payload.requestId,
                    status: "error",
                    resolvedScope: payload.scope,
                    source: "socket_ipc",
                    scope: payload.scope,
                    auditRef: payload.auditRef,
                    reasonCode: normalizedReasonCode(ack.error, fallback: "memory_retrieval_failed"),
                    detail: normalized(ack.error),
                    snippets: [],
                    truncated: false,
                    budgetUsedChars: 0,
                    truncatedItems: 0,
                    redactedItems: 0
                )
            }
            return ack.memoryRetrieval
        default:
            return MemoryRetrievalResponsePayload(
                requestId: payload.requestId,
                status: "error",
                resolvedScope: payload.scope,
                source: "local_ipc",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: "unsupported_ipc_mode",
                detail: "memory retrieval local IPC mode unsupported",
                snippets: [],
                truncated: false,
                budgetUsedChars: 0,
                truncatedItems: 0,
                redactedItems: 0
            )
        }
    }

    private static func requestVoiceTTSReadinessViaLocalIPC(
        preferredModelID: String,
        timeoutSec: Double
    ) -> VoiceTTSReadinessResult {
        let normalizedPreferredModelID = normalized(preferredModelID)
        guard let normalizedPreferredModelID else {
            return VoiceTTSReadinessResult(
                ok: false,
                source: "local_ipc",
                provider: nil,
                modelId: nil,
                reasonCode: "voice_tts_missing_model_id",
                detail: "preferred_model_id is required"
            )
        }

        guard let transport = localIPCTransport(ttl: 3.0) else {
            return VoiceTTSReadinessResult(
                ok: false,
                source: "local_ipc",
                provider: nil,
                modelId: normalizedPreferredModelID,
                reasonCode: "hub_not_connected",
                detail: "voice TTS readiness local IPC unavailable"
            )
        }

        let reqId = UUID().uuidString
        let req = VoiceTTSReadinessIPCRequest(
            type: "voice_tts_readiness",
            reqId: reqId,
            voiceTTSReadiness: VoiceTTSReadinessRequestPayload(
                preferredModelId: normalizedPreferredModelID
            )
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let data: Data
            do {
                data = try JSONEncoder().encode(req)
            } catch {
                return VoiceTTSReadinessResult(
                    ok: false,
                    source: "file_ipc",
                    provider: nil,
                    modelId: normalizedPreferredModelID,
                    reasonCode: "voice_tts_readiness_encode_failed",
                    detail: summarized(error)
                )
            }
            let writeStatus = Self.writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_voice_tts_readiness",
                tmpPrefix: ".xterminal_voice_tts_readiness",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return VoiceTTSReadinessResult(
                    ok: false,
                    source: "file_ipc",
                    provider: nil,
                    modelId: normalizedPreferredModelID,
                    reasonCode: "voice_tts_readiness_write_failed",
                    detail: normalized(writeStatus.requestError) ?? "voice TTS readiness request write failed"
                )
            }
            guard let ack = Self.pollVoiceTTSReadinessResponse(
                baseDir: transport.baseDir,
                reqId: reqId,
                timeoutSec: timeoutSec
            ) else {
                return VoiceTTSReadinessResult(
                    ok: false,
                    source: "file_ipc",
                    provider: nil,
                    modelId: normalizedPreferredModelID,
                    reasonCode: "ack_timeout",
                    detail: "voice TTS readiness ack timeout"
                )
            }
            return mapVoiceTTSReadinessAck(ack, source: "file_ipc", fallbackModelID: normalizedPreferredModelID)
        case "socket":
            guard let ack: VoiceTTSReadinessIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: timeoutSec) else {
                return VoiceTTSReadinessResult(
                    ok: false,
                    source: "socket_ipc",
                    provider: nil,
                    modelId: normalizedPreferredModelID,
                    reasonCode: "ack_timeout",
                    detail: "voice TTS readiness ack timeout"
                )
            }
            return mapVoiceTTSReadinessAck(ack, source: "socket_ipc", fallbackModelID: normalizedPreferredModelID)
        default:
            return VoiceTTSReadinessResult(
                ok: false,
                source: "local_ipc",
                provider: nil,
                modelId: normalizedPreferredModelID,
                reasonCode: "unsupported_ipc_mode",
                detail: "voice TTS readiness local IPC mode unsupported"
            )
        }
    }

    private static func requestVoiceTTSSynthesisViaLocalIPC(
        _ payload: VoiceTTSRequestPayload,
        timeoutSec: Double
    ) -> VoiceTTSResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return VoiceTTSResult(
                ok: false,
                source: "local_ipc",
                provider: nil,
                modelId: normalized(payload.preferredModelId),
                taskKind: "text_to_speech",
                audioFilePath: nil,
                reasonCode: "hub_not_connected",
                runtimeReasonCode: nil,
                error: nil,
                detail: "voice TTS local IPC unavailable"
            )
        }

        let reqId = UUID().uuidString
        let req = VoiceTTSIPCRequest(
            type: "voice_tts_synthesize",
            reqId: reqId,
            voiceTTS: payload
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let data: Data
            do {
                data = try JSONEncoder().encode(req)
            } catch {
                return VoiceTTSResult(
                    ok: false,
                    source: "file_ipc",
                    provider: nil,
                    modelId: normalized(payload.preferredModelId),
                    taskKind: "text_to_speech",
                    audioFilePath: nil,
                    reasonCode: "voice_tts_encode_failed",
                    runtimeReasonCode: nil,
                    error: summarized(error),
                    detail: "voice TTS request encoding failed"
                )
            }
            let writeStatus = Self.writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_voice_tts",
                tmpPrefix: ".xterminal_voice_tts",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return VoiceTTSResult(
                    ok: false,
                    source: "file_ipc",
                    provider: nil,
                    modelId: normalized(payload.preferredModelId),
                    taskKind: "text_to_speech",
                    audioFilePath: nil,
                    reasonCode: "voice_tts_write_failed",
                    runtimeReasonCode: nil,
                    error: normalized(writeStatus.requestError),
                    detail: "voice TTS request write failed"
                )
            }
            guard let ack = pollVoiceTTSResponse(baseDir: transport.baseDir, reqId: reqId, timeoutSec: timeoutSec) else {
                return VoiceTTSResult(
                    ok: false,
                    source: "file_ipc",
                    provider: nil,
                    modelId: normalized(payload.preferredModelId),
                    taskKind: "text_to_speech",
                    audioFilePath: nil,
                    reasonCode: "ack_timeout",
                    runtimeReasonCode: nil,
                    error: nil,
                    detail: "voice TTS ack timeout"
                )
            }
            return mapVoiceTTSAck(ack, source: "file_ipc", fallbackModelID: payload.preferredModelId)
        case "socket":
            guard let ack: VoiceTTSIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: timeoutSec) else {
                return VoiceTTSResult(
                    ok: false,
                    source: "socket_ipc",
                    provider: nil,
                    modelId: normalized(payload.preferredModelId),
                    taskKind: "text_to_speech",
                    audioFilePath: nil,
                    reasonCode: "socket_request_failed",
                    runtimeReasonCode: nil,
                    error: nil,
                    detail: "voice TTS socket request failed"
                )
            }
            return mapVoiceTTSAck(ack, source: "socket_ipc", fallbackModelID: payload.preferredModelId)
        default:
            return VoiceTTSResult(
                ok: false,
                source: "local_ipc",
                provider: nil,
                modelId: normalized(payload.preferredModelId),
                taskKind: "text_to_speech",
                audioFilePath: nil,
                reasonCode: "unsupported_ipc_mode",
                runtimeReasonCode: nil,
                error: nil,
                detail: "voice TTS local IPC mode unsupported"
            )
        }
    }

    private static func requestLocalTaskExecutionViaLocalIPC(
        _ payload: LocalTaskRequestPayload,
        timeoutSec: Double
    ) -> LocalTaskResult {
        if let override = withTestingOverrideLock({ localTaskExecutionOverrideForTesting }) {
            return override(payload, timeoutSec)
        }

        let normalizedTaskKind = normalized(payload.taskKind)
        let normalizedModelID = normalized(payload.modelId)

        guard let transport = localIPCTransport(ttl: 3.0) else {
            return LocalTaskResult(
                ok: false,
                source: "local_ipc",
                runtimeSource: nil,
                provider: nil,
                modelId: normalizedModelID,
                taskKind: normalizedTaskKind,
                reasonCode: "hub_not_connected",
                runtimeReasonCode: nil,
                error: nil,
                detail: "local task IPC unavailable"
            )
        }

        let reqId = UUID().uuidString
        let req = LocalTaskIPCRequest(
            type: "local_task_execute",
            reqId: reqId,
            localTask: payload
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let data: Data
            do {
                data = try JSONEncoder().encode(req)
            } catch {
                return LocalTaskResult(
                    ok: false,
                    source: "file_ipc",
                    runtimeSource: nil,
                    provider: nil,
                    modelId: normalizedModelID,
                    taskKind: normalizedTaskKind,
                    reasonCode: "local_task_encode_failed",
                    runtimeReasonCode: nil,
                    error: summarized(error),
                    detail: "local task request encoding failed"
                )
            }
            let writeStatus = Self.writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_local_task",
                tmpPrefix: ".xterminal_local_task",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return LocalTaskResult(
                    ok: false,
                    source: "file_ipc",
                    runtimeSource: nil,
                    provider: nil,
                    modelId: normalizedModelID,
                    taskKind: normalizedTaskKind,
                    reasonCode: "local_task_write_failed",
                    runtimeReasonCode: nil,
                    error: normalized(writeStatus.requestError),
                    detail: "local task request write failed"
                )
            }
            guard let ack = pollLocalTaskResponse(
                baseDir: transport.baseDir,
                reqId: reqId,
                timeoutSec: timeoutSec
            ) else {
                return LocalTaskResult(
                    ok: false,
                    source: "file_ipc",
                    runtimeSource: nil,
                    provider: nil,
                    modelId: normalizedModelID,
                    taskKind: normalizedTaskKind,
                    reasonCode: "ack_timeout",
                    runtimeReasonCode: nil,
                    error: nil,
                    detail: "local task ack timeout"
                )
            }
            return mapLocalTaskAck(
                ack,
                source: "file_ipc",
                fallbackModelID: payload.modelId,
                fallbackTaskKind: payload.taskKind
            )
        case "socket":
            guard let ack: LocalTaskIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: timeoutSec) else {
                return LocalTaskResult(
                    ok: false,
                    source: "socket_ipc",
                    runtimeSource: nil,
                    provider: nil,
                    modelId: normalizedModelID,
                    taskKind: normalizedTaskKind,
                    reasonCode: "socket_request_failed",
                    runtimeReasonCode: nil,
                    error: nil,
                    detail: "local task socket request failed"
                )
            }
            return mapLocalTaskAck(
                ack,
                source: "socket_ipc",
                fallbackModelID: payload.modelId,
                fallbackTaskKind: payload.taskKind
            )
        default:
            return LocalTaskResult(
                ok: false,
                source: "local_ipc",
                runtimeSource: nil,
                provider: nil,
                modelId: normalizedModelID,
                taskKind: normalizedTaskKind,
                reasonCode: "unsupported_ipc_mode",
                runtimeReasonCode: nil,
                error: nil,
                detail: "local task IPC mode unsupported"
            )
        }
    }

    private static func fetchVoiceWakeProfileViaLocalIPC(
        desiredWakeMode: VoiceWakeMode
    ) async -> VoiceWakeProfileSyncResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "local_ipc",
                profile: nil,
                reasonCode: "hub_not_connected",
                logLines: ["voice wake profile fetch local IPC unavailable"],
                syncedAtMs: nil
            )
        }

        let reqId = UUID().uuidString
        let req = VoiceWakeProfileGetIPCRequest(
            type: "voice_wake_profile_get",
            reqId: reqId,
            voiceWakeProfileRequest: VoiceWakeProfileRequestPayload(desiredWakeMode: desiredWakeMode.rawValue)
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let data: Data
            do {
                data = try JSONEncoder().encode(req)
            } catch {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "file_ipc",
                    profile: nil,
                    reasonCode: "voice_wake_profile_write_failed",
                    logLines: ["voice wake profile get request encode failed: \(summarized(error))"],
                    syncedAtMs: nil
                )
            }
            let writeStatus = Self.writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_voicewake_get",
                tmpPrefix: ".xterminal_voicewake_get",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "file_ipc",
                    profile: nil,
                    reasonCode: "voice_wake_profile_write_failed",
                    logLines: ["voice wake profile get request write failed: \(writeStatus.requestError)"],
                    syncedAtMs: nil
                )
            }

            guard let ack = await pollVoiceWakeProfileResponse(baseDir: transport.baseDir, reqId: reqId, timeoutSec: 2.0) else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "file_ipc",
                    profile: nil,
                    reasonCode: "ack_timeout",
                    logLines: ["voice wake profile get ack timeout"],
                    syncedAtMs: nil
                )
            }
            return mapVoiceWakeProfileAck(ack, source: "file_ipc", verb: "get")
        case "socket":
            guard let ack: VoiceWakeProfileIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "socket_ipc",
                    profile: nil,
                    reasonCode: "socket_request_failed",
                    logLines: ["voice wake profile get socket request failed"],
                    syncedAtMs: nil
                )
            }
            return mapVoiceWakeProfileAck(ack, source: "socket_ipc", verb: "get")
        default:
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "local_ipc",
                profile: nil,
                reasonCode: "unsupported_ipc_mode",
                logLines: ["voice wake profile fetch local IPC mode unsupported"],
                syncedAtMs: nil
            )
        }
    }

    private static func setVoiceWakeProfileViaLocalIPC(
        _ profile: VoiceWakeProfile
    ) async -> VoiceWakeProfileSyncResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "local_ipc",
                profile: nil,
                reasonCode: "hub_not_connected",
                logLines: ["voice wake profile set local IPC unavailable"],
                syncedAtMs: nil
            )
        }

        let reqId = UUID().uuidString
        let req = VoiceWakeProfileSetIPCRequest(
            type: "voice_wake_profile_set",
            reqId: reqId,
            voiceWakeProfile: profile.sanitized()
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let data: Data
            do {
                data = try JSONEncoder().encode(req)
            } catch {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "file_ipc",
                    profile: nil,
                    reasonCode: "voice_wake_profile_write_failed",
                    logLines: ["voice wake profile set request encode failed: \(summarized(error))"],
                    syncedAtMs: nil
                )
            }
            let writeStatus = Self.writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_voicewake_set",
                tmpPrefix: ".xterminal_voicewake_set",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "file_ipc",
                    profile: nil,
                    reasonCode: "voice_wake_profile_write_failed",
                    logLines: ["voice wake profile set request write failed: \(writeStatus.requestError)"],
                    syncedAtMs: nil
                )
            }

            guard let ack = await pollVoiceWakeProfileResponse(baseDir: transport.baseDir, reqId: reqId, timeoutSec: 2.0) else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "file_ipc",
                    profile: nil,
                    reasonCode: "ack_timeout",
                    logLines: ["voice wake profile set ack timeout"],
                    syncedAtMs: nil
                )
            }
            return mapVoiceWakeProfileAck(ack, source: "file_ipc", verb: "set")
        case "socket":
            guard let ack: VoiceWakeProfileIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "socket_ipc",
                    profile: nil,
                    reasonCode: "socket_request_failed",
                    logLines: ["voice wake profile set socket request failed"],
                    syncedAtMs: nil
                )
            }
            return mapVoiceWakeProfileAck(ack, source: "socket_ipc", verb: "set")
        default:
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "local_ipc",
                profile: nil,
                reasonCode: "unsupported_ipc_mode",
                logLines: ["voice wake profile set local IPC mode unsupported"],
                syncedAtMs: nil
            )
        }
    }

    private static func requestSecretVaultSnapshotViaLocalIPC(
        scope: String?,
        namePrefix: String?,
        projectId: String?,
        limit: Int
    ) async -> SecretVaultSnapshot? {
        guard let transport = localIPCTransport(ttl: 3.0) else { return nil }

        let reqId = UUID().uuidString
        let req = SecretVaultListIPCRequest(
            type: "secret_vault_list",
            reqId: reqId,
            secretVaultList: SecretVaultListRequestPayload(
                scope: scope,
                namePrefix: namePrefix,
                projectId: projectId,
                limit: max(1, min(500, limit))
            )
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(req),
                  writeEvent(
                    data: data,
                    reqId: reqId,
                    filePrefix: "xterminal_secret_vault_list",
                    tmpPrefix: ".xterminal_secret_vault_list",
                    in: transport.ipcURL
                  ),
                  let ack = await pollSecretVaultListResponse(baseDir: transport.baseDir, reqId: reqId, timeoutSec: 2.0),
                  ack.ok,
                  let snapshot = ack.secretVaultSnapshot else {
                return nil
            }
            return snapshot
        case "socket":
            guard let ack: SecretVaultListIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0),
                  ack.ok,
                  let snapshot = ack.secretVaultSnapshot else {
                return nil
            }
            return snapshot
        default:
            return nil
        }
    }

    private static func createProtectedSecretViaLocalIPC(
        _ payload: SecretCreateRequestPayload
    ) async -> SecretCreateResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return SecretCreateResult(
                ok: false,
                source: "local_ipc",
                item: nil,
                reasonCode: "secret_vault_local_ipc_unavailable"
            )
        }

        if transport.mode == "file" {
            return SecretCreateResult(
                ok: false,
                source: "file_ipc",
                item: nil,
                reasonCode: "secret_vault_secure_capture_requires_socket_ipc"
            )
        }

        let req = SecretVaultCreateIPCRequest(
            type: "secret_vault_create",
            reqId: UUID().uuidString,
            secretVaultCreate: payload
        )

        guard let ack: SecretVaultCreateIPCResponse = sendSocketRequest(
            req,
            socketURL: transport.ipcURL,
            timeoutSec: 3.0
        ) else {
            return SecretCreateResult(
                ok: false,
                source: "socket_ipc",
                item: nil,
                reasonCode: "socket_request_failed"
            )
        }

        guard ack.ok else {
            return SecretCreateResult(
                ok: false,
                source: "socket_ipc",
                item: nil,
                reasonCode: normalizedReasonCode(ack.error, fallback: "secret_vault_create_failed")
            )
        }

        guard let item = ack.secretVaultItem else {
            return SecretCreateResult(
                ok: false,
                source: "socket_ipc",
                item: nil,
                reasonCode: "secret_vault_item_missing"
            )
        }

        return SecretCreateResult(
            ok: true,
            source: "socket_ipc",
            item: item,
            reasonCode: nil
        )
    }

    private static func beginSecretUseViaLocalIPC(
        _ payload: SecretUseRequestPayload
    ) async -> SecretUseResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return SecretUseResult(
                ok: false,
                source: "local_ipc",
                leaseId: nil,
                useToken: nil,
                itemId: payload.itemId,
                expiresAtMs: nil,
                reasonCode: "secret_vault_local_ipc_unavailable"
            )
        }

        let reqId = UUID().uuidString
        let req = SecretVaultBeginUseIPCRequest(
            type: "secret_vault_begin_use",
            reqId: reqId,
            secretVaultUse: payload
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(req) else {
                return SecretUseResult(
                    ok: false,
                    source: "file_ipc",
                    leaseId: nil,
                    useToken: nil,
                    itemId: payload.itemId,
                    expiresAtMs: nil,
                    reasonCode: "secret_vault_use_encode_failed",
                    detail: "secret vault use request encoding failed"
                )
            }
            let writeStatus = Self.writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_secret_vault_use",
                tmpPrefix: ".xterminal_secret_vault_use",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return SecretUseResult(
                    ok: false,
                    source: "file_ipc",
                    leaseId: nil,
                    useToken: nil,
                    itemId: payload.itemId,
                    expiresAtMs: nil,
                    reasonCode: "secret_vault_use_write_failed",
                    detail: normalized(writeStatus.requestError)
                )
            }
            guard let ack = await pollSecretVaultUseResponse(baseDir: transport.baseDir, reqId: reqId, timeoutSec: 2.0) else {
                return SecretUseResult(
                    ok: false,
                    source: "file_ipc",
                    leaseId: nil,
                    useToken: nil,
                    itemId: payload.itemId,
                    expiresAtMs: nil,
                    reasonCode: "ack_timeout",
                    detail: "secret vault use ack timeout"
                )
            }
            return mapSecretVaultUseAck(ack, source: "file_ipc", fallbackItemId: payload.itemId)
        case "socket":
            guard let ack: SecretVaultUseIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return SecretUseResult(
                    ok: false,
                    source: "socket_ipc",
                    leaseId: nil,
                    useToken: nil,
                    itemId: payload.itemId,
                    expiresAtMs: nil,
                    reasonCode: "socket_request_failed",
                    detail: "secret vault use socket request failed"
                )
            }
            return mapSecretVaultUseAck(ack, source: "socket_ipc", fallbackItemId: payload.itemId)
        default:
            return SecretUseResult(
                ok: false,
                source: "local_ipc",
                leaseId: nil,
                useToken: nil,
                itemId: payload.itemId,
                expiresAtMs: nil,
                reasonCode: "unsupported_ipc_mode",
                detail: "secret vault use local IPC mode unsupported"
            )
        }
    }

    private static func redeemSecretUseViaLocalIPC(
        _ payload: SecretRedeemRequestPayload
    ) async -> SecretRedeemResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return SecretRedeemResult(
                ok: false,
                source: "local_ipc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "secret_vault_local_ipc_unavailable"
            )
        }

        let reqId = UUID().uuidString
        let req = SecretVaultRedeemIPCRequest(
            type: "secret_vault_redeem_use",
            reqId: reqId,
            secretVaultRedeem: payload
        )

        switch transport.mode {
        case "file":
            return SecretRedeemResult(
                ok: false,
                source: "file_ipc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "secret_vault_redeem_requires_socket_ipc",
                detail: "secret vault redeem requires socket IPC"
            )
        case "socket":
            guard let ack: SecretVaultRedeemIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return SecretRedeemResult(
                    ok: false,
                    source: "socket_ipc",
                    leaseId: nil,
                    itemId: nil,
                    plaintext: nil,
                    reasonCode: "socket_request_failed",
                    detail: "secret vault redeem socket request failed"
                )
            }
            return mapSecretVaultRedeemAck(ack, source: "socket_ipc")
        default:
            return SecretRedeemResult(
                ok: false,
                source: "local_ipc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "unsupported_ipc_mode",
                detail: "secret vault redeem local IPC mode unsupported"
            )
        }
    }

    private static func mapVoiceWakeProfileAck(
        _ ack: VoiceWakeProfileIPCResponse,
        source: String,
        verb: String
    ) -> VoiceWakeProfileSyncResult {
        guard ack.ok else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: source,
                profile: nil,
                reasonCode: normalizedReasonCode(ack.error, fallback: "voice_wake_profile_\(verb)_failed"),
                logLines: ["voice wake profile \(verb) failed: \(ack.error ?? "unknown_error")"],
                syncedAtMs: nil
            )
        }
        guard let profile = ack.voiceWakeProfile else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: source,
                profile: nil,
                reasonCode: "voice_wake_profile_missing",
                logLines: ["voice wake profile \(verb) missing payload"],
                syncedAtMs: nil
            )
        }
        return VoiceWakeProfileSyncResult(
            ok: true,
            source: source,
            profile: profile,
            reasonCode: nil,
            logLines: ["voice wake profile \(verb) succeeded via \(source)"],
            syncedAtMs: profile.updatedAtMs
        )
    }

    private static func mapVoiceTTSReadinessAck(
        _ ack: VoiceTTSReadinessIPCResponse,
        source: String,
        fallbackModelID: String
    ) -> VoiceTTSReadinessResult {
        if let result = ack.voiceTTSReadiness {
            return VoiceTTSReadinessResult(
                ok: result.ok,
                source: source,
                provider: result.provider,
                modelId: result.modelId ?? normalized(fallbackModelID),
                reasonCode: result.reasonCode ?? (!ack.ok ? normalizedReasonCode(ack.error, fallback: "voice_tts_readiness_failed") : nil),
                detail: result.detail ?? (!ack.ok ? ack.error : nil)
            )
        }

        return VoiceTTSReadinessResult(
            ok: false,
            source: source,
            provider: nil,
            modelId: normalized(fallbackModelID),
            reasonCode: normalizedReasonCode(ack.error, fallback: "voice_tts_readiness_missing_payload"),
            detail: "voice TTS readiness response payload missing"
        )
    }

    private static func mapVoiceTTSAck(
        _ ack: VoiceTTSIPCResponse,
        source: String,
        fallbackModelID: String
    ) -> VoiceTTSResult {
        if let result = ack.voiceTTS {
            return VoiceTTSResult(
                ok: result.ok,
                source: source,
                provider: result.provider,
                modelId: result.modelId ?? normalized(fallbackModelID),
                taskKind: result.taskKind ?? "text_to_speech",
                audioFilePath: result.audioFilePath,
                audioFormat: result.audioFormat,
                voiceName: result.voiceName,
                engineName: result.engineName,
                speakerId: result.speakerId,
                deviceBackend: result.deviceBackend,
                nativeTTSUsed: result.nativeTTSUsed,
                fallbackMode: result.fallbackMode,
                fallbackReasonCode: result.fallbackReasonCode,
                reasonCode: result.reasonCode ?? (!ack.ok ? normalizedReasonCode(ack.error, fallback: "voice_tts_failed") : nil),
                runtimeReasonCode: result.runtimeReasonCode,
                error: result.error ?? (!ack.ok ? ack.error : nil),
                detail: result.detail,
                ttsAudit: result.ttsAudit,
                ttsAuditLine: result.ttsAuditLine
            )
        }

        return VoiceTTSResult(
            ok: false,
            source: source,
            provider: nil,
            modelId: normalized(fallbackModelID),
            taskKind: "text_to_speech",
            audioFilePath: nil,
            reasonCode: normalizedReasonCode(ack.error, fallback: "voice_tts_missing_payload"),
            runtimeReasonCode: nil,
            error: ack.error,
            detail: "voice TTS response payload missing"
        )
    }

    private static func mapLocalTaskAck(
        _ ack: LocalTaskIPCResponse,
        source: String,
        fallbackModelID: String,
        fallbackTaskKind: String
    ) -> LocalTaskResult {
        if let result = ack.localTask {
            return LocalTaskResult(
                ok: result.ok,
                source: source,
                runtimeSource: result.runtimeSource ?? normalized(result.source),
                provider: result.provider,
                modelId: result.modelId ?? normalized(fallbackModelID),
                taskKind: result.taskKind ?? normalized(fallbackTaskKind),
                reasonCode: result.reasonCode ?? (!ack.ok ? normalizedReasonCode(ack.error, fallback: "local_task_failed") : nil),
                runtimeReasonCode: result.runtimeReasonCode,
                error: result.error ?? (!ack.ok ? ack.error : nil),
                detail: result.detail,
                payload: result.payload
            )
        }

        return LocalTaskResult(
            ok: false,
            source: source,
            runtimeSource: nil,
            provider: nil,
            modelId: normalized(fallbackModelID),
            taskKind: normalized(fallbackTaskKind),
            reasonCode: normalizedReasonCode(ack.error, fallback: "local_task_missing_payload"),
            runtimeReasonCode: nil,
            error: ack.error,
            detail: "local task response payload missing",
            payload: [:]
        )
    }

    private struct LocalPaidSchedulerConfig: Codable {
        var globalConcurrency: Int?
        var perProjectConcurrency: Int?
        var queueLimit: Int?
        var queueTimeoutMs: Int?

        enum CodingKeys: String, CodingKey {
            case globalConcurrency = "global_concurrency"
            case perProjectConcurrency = "per_project_concurrency"
            case queueLimit = "queue_limit"
            case queueTimeoutMs = "queue_timeout_ms"
        }
    }

    private struct LocalPaidSchedulerState: Codable {
        var inFlightTotal: Int?
        var queueDepth: Int?
        var oldestQueuedMs: Int?

        enum CodingKeys: String, CodingKey {
            case inFlightTotal = "in_flight_total"
            case queueDepth = "queue_depth"
            case oldestQueuedMs = "oldest_queued_ms"
        }
    }

    private struct LocalPaidSchedulerInFlightScope: Codable {
        var scopeKey: String
        var inFlight: Int?

        enum CodingKeys: String, CodingKey {
            case scopeKey = "scope_key"
            case inFlight = "in_flight"
        }
    }

    private struct LocalPaidSchedulerQueuedScope: Codable {
        var scopeKey: String
        var queued: Int?

        enum CodingKeys: String, CodingKey {
            case scopeKey = "scope_key"
            case queued
        }
    }

    private struct LocalPaidSchedulerQueueItem: Codable {
        var requestId: String
        var scopeKey: String
        var enqueuedAtMs: Double?
        var queuedMs: Int?

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case scopeKey = "scope_key"
            case enqueuedAtMs = "enqueued_at_ms"
            case queuedMs = "queued_ms"
        }
    }

    private struct LocalPaidSchedulerSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var config: LocalPaidSchedulerConfig?
        var state: LocalPaidSchedulerState?
        var inFlightByScope: [LocalPaidSchedulerInFlightScope]?
        var queuedByScope: [LocalPaidSchedulerQueuedScope]?
        var queueItems: [LocalPaidSchedulerQueueItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case config
            case state
            case inFlightByScope = "in_flight_by_scope"
            case queuedByScope = "queued_by_scope"
            case queueItems = "queue_items"
        }
    }

    private static func readLocalSchedulerStatus(
        includeQueueItems: Bool,
        queueItemsLimit: Int
    ) -> SchedulerStatusSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("paid_ai_scheduler_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalPaidSchedulerSnapshotFile.self, from: data) else {
            return nil
        }

        let inFlightByScope = (decoded.inFlightByScope ?? []).compactMap { row -> SchedulerScopeCount? in
            let key = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return SchedulerScopeCount(scopeKey: key, count: max(0, row.inFlight ?? 0))
        }
        let queuedByScope = (decoded.queuedByScope ?? []).compactMap { row -> SchedulerScopeCount? in
            let key = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return SchedulerScopeCount(scopeKey: key, count: max(0, row.queued ?? 0))
        }
        let queueItems: [SchedulerQueueItem] = includeQueueItems
            ? (decoded.queueItems ?? []).prefix(max(1, min(500, queueItemsLimit))).compactMap { row in
                let requestId = row.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
                let scopeKey = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !requestId.isEmpty, !scopeKey.isEmpty else { return nil }
                return SchedulerQueueItem(
                    requestId: requestId,
                    scopeKey: scopeKey,
                    enqueuedAtMs: max(0, row.enqueuedAtMs ?? 0),
                    queuedMs: max(0, row.queuedMs ?? 0)
                )
            }
            : []

        return SchedulerStatusSnapshot(
            source: "hub_scheduler_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            inFlightTotal: max(0, decoded.state?.inFlightTotal ?? inFlightByScope.reduce(0, { $0 + max(0, $1.count) })),
            queueDepth: max(0, decoded.state?.queueDepth ?? queuedByScope.reduce(0, { $0 + max(0, $1.count) })),
            oldestQueuedMs: max(0, decoded.state?.oldestQueuedMs ?? queueItems.map(\.queuedMs).max() ?? 0),
            inFlightByScope: inFlightByScope,
            queuedByScope: queuedByScope,
            queueItems: queueItems
        )
    }

    private struct LocalPendingGrantItem: Codable {
        var grantRequestId: String
        var requestId: String?
        var client: LocalPendingGrantClient?
        var capability: String?
        var modelId: String?
        var reason: String?
        var requestedTtlSec: Int?
        var requestedTokenCap: Int?
        var status: String?
        var decision: String?
        var createdAtMs: Double?
        var decidedAtMs: Double?

        enum CodingKeys: String, CodingKey {
            case grantRequestId = "grant_request_id"
            case requestId = "request_id"
            case client
            case capability
            case modelId = "model_id"
            case reason
            case requestedTtlSec = "requested_ttl_sec"
            case requestedTokenCap = "requested_token_cap"
            case status
            case decision
            case createdAtMs = "created_at_ms"
            case decidedAtMs = "decided_at_ms"
        }
    }

    private struct LocalPendingGrantClient: Codable {
        var deviceId: String?
        var userId: String?
        var appId: String?
        var projectId: String?

        enum CodingKeys: String, CodingKey {
            case deviceId = "device_id"
            case userId = "user_id"
            case appId = "app_id"
            case projectId = "project_id"
        }
    }

    private struct LocalPendingGrantSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalPendingGrantItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalPendingGrantRequests(
        projectId: String?,
        limit: Int,
        sourceOverride: String? = nil
    ) -> PendingGrantSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("pending_grant_requests_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalPendingGrantSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> PendingGrantItem? in
            let grantRequestId = row.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !grantRequestId.isEmpty else { return nil }

            let project = row.client?.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let normalizedProjectId, !normalizedProjectId.isEmpty, project != normalizedProjectId {
                return nil
            }

            return PendingGrantItem(
                grantRequestId: grantRequestId,
                requestId: row.requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                deviceId: row.client?.deviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                userId: row.client?.userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                appId: row.client?.appId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                projectId: project,
                capability: row.capability?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                modelId: row.modelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                reason: row.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                requestedTtlSec: max(0, row.requestedTtlSec ?? 0),
                requestedTokenCap: max(0, row.requestedTokenCap ?? 0),
                status: row.status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                decision: row.decision?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                createdAtMs: max(0, row.createdAtMs ?? 0),
                decidedAtMs: max(0, row.decidedAtMs ?? 0)
            )
        }
        .sorted { lhs, rhs in
            if lhs.createdAtMs != rhs.createdAtMs { return lhs.createdAtMs < rhs.createdAtMs }
            return lhs.grantRequestId.localizedCaseInsensitiveCompare(rhs.grantRequestId) == .orderedAscending
        }
        let resolvedSource = {
            let normalized = sourceOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return normalized.isEmpty ? "hub_pending_grants_file" : normalized
        }()

        return PendingGrantSnapshot(
            source: resolvedSource,
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private struct LocalSupervisorCandidateReviewItem: Codable {
        var schemaVersion: String?
        var reviewId: String?
        var requestId: String?
        var evidenceRef: String?
        var reviewState: String?
        var durablePromotionState: String?
        var promotionBoundary: String?
        var deviceId: String?
        var userId: String?
        var appId: String?
        var threadId: String?
        var threadKey: String?
        var projectId: String?
        var projectIds: [String]?
        var scopes: [String]?
        var recordTypes: [String]?
        var auditRefs: [String]?
        var idempotencyKeys: [String]?
        var candidateCount: Int?
        var summaryLine: String?
        var mirrorTarget: String?
        var localStoreRole: String?
        var carrierKind: String?
        var carrierSchemaVersion: String?
        var pendingChangeId: String?
        var pendingChangeStatus: String?
        var editSessionId: String?
        var docId: String?
        var writebackRef: String?
        var stageCreatedAtMs: Double?
        var stageUpdatedAtMs: Double?
        var latestEmittedAtMs: Double?
        var createdAtMs: Double?
        var updatedAtMs: Double?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case reviewId = "review_id"
            case requestId = "request_id"
            case evidenceRef = "evidence_ref"
            case reviewState = "review_state"
            case durablePromotionState = "durable_promotion_state"
            case promotionBoundary = "promotion_boundary"
            case deviceId = "device_id"
            case userId = "user_id"
            case appId = "app_id"
            case threadId = "thread_id"
            case threadKey = "thread_key"
            case projectId = "project_id"
            case projectIds = "project_ids"
            case scopes
            case recordTypes = "record_types"
            case auditRefs = "audit_refs"
            case idempotencyKeys = "idempotency_keys"
            case candidateCount = "candidate_count"
            case summaryLine = "summary_line"
            case mirrorTarget = "mirror_target"
            case localStoreRole = "local_store_role"
            case carrierKind = "carrier_kind"
            case carrierSchemaVersion = "carrier_schema_version"
            case pendingChangeId = "pending_change_id"
            case pendingChangeStatus = "pending_change_status"
            case editSessionId = "edit_session_id"
            case docId = "doc_id"
            case writebackRef = "writeback_ref"
            case stageCreatedAtMs = "stage_created_at_ms"
            case stageUpdatedAtMs = "stage_updated_at_ms"
            case latestEmittedAtMs = "latest_emitted_at_ms"
            case createdAtMs = "created_at_ms"
            case updatedAtMs = "updated_at_ms"
        }
    }

    private struct LocalSupervisorCandidateReviewSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalSupervisorCandidateReviewItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalSupervisorCandidateReviewSnapshot(
        projectId: String?,
        limit: Int
    ) -> SupervisorCandidateReviewSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("supervisor_candidate_review_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalSupervisorCandidateReviewSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> SupervisorCandidateReviewItem? in
            let requestId = row.requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !requestId.isEmpty else { return nil }

            let project = row.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let projectIDs = (row.projectIds ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let normalizedProjectId, !normalizedProjectId.isEmpty,
               project != normalizedProjectId,
               !projectIDs.contains(normalizedProjectId) {
                return nil
            }

            return SupervisorCandidateReviewItem(
                schemaVersion: row.schemaVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                reviewId: row.reviewId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                requestId: requestId,
                evidenceRef: row.evidenceRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                reviewState: row.reviewState?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                durablePromotionState: row.durablePromotionState?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                promotionBoundary: row.promotionBoundary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                deviceId: row.deviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                userId: row.userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                appId: row.appId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                threadId: row.threadId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                threadKey: row.threadKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                projectId: project,
                projectIds: projectIDs,
                scopes: (row.scopes ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                recordTypes: (row.recordTypes ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                auditRefs: (row.auditRefs ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                idempotencyKeys: (row.idempotencyKeys ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                candidateCount: max(0, row.candidateCount ?? 0),
                summaryLine: row.summaryLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                mirrorTarget: row.mirrorTarget?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                localStoreRole: row.localStoreRole?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                carrierKind: row.carrierKind?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                carrierSchemaVersion: row.carrierSchemaVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                pendingChangeId: row.pendingChangeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                pendingChangeStatus: row.pendingChangeStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                editSessionId: row.editSessionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                docId: row.docId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                writebackRef: row.writebackRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                stageCreatedAtMs: max(0, row.stageCreatedAtMs ?? 0),
                stageUpdatedAtMs: max(0, row.stageUpdatedAtMs ?? 0),
                latestEmittedAtMs: max(0, row.latestEmittedAtMs ?? 0),
                createdAtMs: max(0, row.createdAtMs ?? 0),
                updatedAtMs: max(0, row.updatedAtMs ?? 0)
            )
        }
        .sorted { lhs, rhs in
            if lhs.latestEmittedAtMs != rhs.latestEmittedAtMs {
                return lhs.latestEmittedAtMs > rhs.latestEmittedAtMs
            }
            if lhs.candidateCount != rhs.candidateCount {
                return lhs.candidateCount > rhs.candidateCount
            }
            return lhs.requestId.localizedCaseInsensitiveCompare(rhs.requestId) == .orderedAscending
        }

        return SupervisorCandidateReviewSnapshot(
            source: "hub_supervisor_candidate_review_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private struct LocalConnectorIngressReceipt: Codable {
        var receiptId: String
        var requestId: String?
        var projectId: String?
        var connector: String?
        var targetId: String?
        var ingressType: String?
        var channelScope: String?
        var sourceId: String?
        var messageId: String?
        var dedupeKey: String?
        var receivedAtMs: Double?
        var eventSequence: Int64?
        var deliveryState: String?
        var runtimeState: String?

        enum CodingKeys: String, CodingKey {
            case receiptId = "receipt_id"
            case requestId = "request_id"
            case projectId = "project_id"
            case connector
            case targetId = "target_id"
            case ingressType = "ingress_type"
            case channelScope = "channel_scope"
            case sourceId = "source_id"
            case messageId = "message_id"
            case dedupeKey = "dedupe_key"
            case receivedAtMs = "received_at_ms"
            case eventSequence = "event_sequence"
            case deliveryState = "delivery_state"
            case runtimeState = "runtime_state"
        }
    }

    private struct LocalConnectorIngressSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalConnectorIngressReceipt]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalConnectorIngressReceipts(
        projectId: String?,
        limit: Int
    ) -> ConnectorIngressSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("connector_ingress_receipts_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalConnectorIngressSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> ConnectorIngressReceipt? in
            let receiptId = row.receiptId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !receiptId.isEmpty else { return nil }

            let project = row.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let normalizedProjectId, !normalizedProjectId.isEmpty, project != normalizedProjectId {
                return nil
            }

            return ConnectorIngressReceipt(
                receiptId: receiptId,
                requestId: row.requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                projectId: project,
                connector: row.connector?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                targetId: row.targetId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                ingressType: row.ingressType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                channelScope: row.channelScope?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                sourceId: row.sourceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                messageId: row.messageId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                dedupeKey: row.dedupeKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                receivedAtMs: max(0, row.receivedAtMs ?? 0),
                eventSequence: Swift.max(0, row.eventSequence ?? 0),
                deliveryState: row.deliveryState?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                runtimeState: row.runtimeState?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            )
        }
        .sorted { lhs, rhs in
            if lhs.receivedAtMs != rhs.receivedAtMs { return lhs.receivedAtMs > rhs.receivedAtMs }
            return lhs.receiptId.localizedCaseInsensitiveCompare(rhs.receiptId) == .orderedAscending
        }

        return ConnectorIngressSnapshot(
            source: "hub_connector_ingress_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private struct LocalOperatorChannelXTCommandItem: Codable {
        var commandId: String?
        var requestId: String?
        var actionName: String?
        var bindingId: String?
        var routeId: String?
        var scopeType: String?
        var scopeId: String?
        var projectId: String?
        var provider: String?
        var accountId: String?
        var conversationId: String?
        var threadKey: String?
        var actorRef: String?
        var resolvedDeviceId: String?
        var preferredDeviceId: String?
        var note: String?
        var createdAtMs: Double?
        var auditRef: String?

        enum CodingKeys: String, CodingKey {
            case commandId = "command_id"
            case requestId = "request_id"
            case actionName = "action_name"
            case bindingId = "binding_id"
            case routeId = "route_id"
            case scopeType = "scope_type"
            case scopeId = "scope_id"
            case projectId = "project_id"
            case provider
            case accountId = "account_id"
            case conversationId = "conversation_id"
            case threadKey = "thread_key"
            case actorRef = "actor_ref"
            case resolvedDeviceId = "resolved_device_id"
            case preferredDeviceId = "preferred_device_id"
            case note
            case createdAtMs = "created_at_ms"
            case auditRef = "audit_ref"
        }
    }

    private struct LocalOperatorChannelXTCommandSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalOperatorChannelXTCommandItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalOperatorChannelXTCommands(
        projectId: String?,
        limit: Int
    ) -> OperatorChannelXTCommandSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("operator_channel_xt_command_queue_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalOperatorChannelXTCommandSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> OperatorChannelXTCommandItem? in
            let commandId = row.commandId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !commandId.isEmpty else { return nil }

            let project = (row.projectId ?? row.scopeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalizedProjectId, !normalizedProjectId.isEmpty, project != normalizedProjectId {
                return nil
            }

            return OperatorChannelXTCommandItem(
                commandId: commandId,
                requestId: row.requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                actionName: row.actionName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                bindingId: row.bindingId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                routeId: row.routeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                scopeType: row.scopeType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                scopeId: row.scopeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                projectId: project,
                provider: row.provider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                accountId: row.accountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                conversationId: row.conversationId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                threadKey: row.threadKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                actorRef: row.actorRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                resolvedDeviceId: row.resolvedDeviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                preferredDeviceId: row.preferredDeviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                note: row.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                createdAtMs: max(0, row.createdAtMs ?? 0),
                auditRef: row.auditRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
        .sorted { lhs, rhs in
            if lhs.createdAtMs != rhs.createdAtMs { return lhs.createdAtMs > rhs.createdAtMs }
            return lhs.commandId.localizedCaseInsensitiveCompare(rhs.commandId) == .orderedAscending
        }

        return OperatorChannelXTCommandSnapshot(
            source: "hub_operator_channel_xt_command_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private struct LocalOperatorChannelXTCommandResultItem: Codable {
        var commandId: String?
        var requestId: String?
        var actionName: String?
        var projectId: String?
        var resolvedDeviceId: String?
        var status: String?
        var denyCode: String?
        var detail: String?
        var runId: String?
        var createdAtMs: Double?
        var completedAtMs: Double?
        var auditRef: String?

        enum CodingKeys: String, CodingKey {
            case commandId = "command_id"
            case requestId = "request_id"
            case actionName = "action_name"
            case projectId = "project_id"
            case resolvedDeviceId = "resolved_device_id"
            case status
            case denyCode = "deny_code"
            case detail
            case runId = "run_id"
            case createdAtMs = "created_at_ms"
            case completedAtMs = "completed_at_ms"
            case auditRef = "audit_ref"
        }
    }

    private struct LocalOperatorChannelXTCommandResultSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalOperatorChannelXTCommandResultItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalOperatorChannelXTCommandResults(
        projectId: String?,
        limit: Int
    ) -> OperatorChannelXTCommandResultSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("operator_channel_xt_command_results_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalOperatorChannelXTCommandResultSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> OperatorChannelXTCommandResultItem? in
            let commandId = row.commandId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !commandId.isEmpty else { return nil }

            let project = row.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let normalizedProjectId, !normalizedProjectId.isEmpty, project != normalizedProjectId {
                return nil
            }

            return OperatorChannelXTCommandResultItem(
                commandId: commandId,
                requestId: row.requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                actionName: row.actionName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                projectId: project,
                resolvedDeviceId: row.resolvedDeviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                status: row.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                denyCode: row.denyCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                detail: row.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                runId: row.runId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                createdAtMs: max(0, row.createdAtMs ?? 0),
                completedAtMs: max(0, row.completedAtMs ?? 0),
                auditRef: row.auditRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
        .sorted { lhs, rhs in
            let leftTimestamp = max(lhs.completedAtMs, lhs.createdAtMs)
            let rightTimestamp = max(rhs.completedAtMs, rhs.createdAtMs)
            if leftTimestamp != rightTimestamp { return leftTimestamp > rightTimestamp }
            return lhs.commandId.localizedCaseInsensitiveCompare(rhs.commandId) == .orderedAscending
        }

        return OperatorChannelXTCommandResultSnapshot(
            source: "hub_operator_channel_xt_command_result_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private struct LocalRuntimeSurfaceOverrideItem: Codable {
        var projectId: String
        var overrideMode: String
        var updatedAtMs: Double?
        var reason: String?
        var auditRef: String?

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
            case overrideMode = "override_mode"
            case updatedAtMs = "updated_at_ms"
            case reason
            case auditRef = "audit_ref"
        }
    }

    private struct LocalRuntimeSurfaceOverridesSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalRuntimeSurfaceOverrideItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalRuntimeSurfaceOverrides(
        projectId: String?,
        limit: Int
    ) -> RuntimeSurfaceOverridesSnapshot? {
        // Legacy filename/source retained for Hub file-IPC compatibility.
        let url = HubPaths.baseDir().appendingPathComponent(
            RuntimeSurfaceOverrideCompatContract.snapshotFilename
        )
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalRuntimeSurfaceOverridesSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> RuntimeSurfaceOverrideItem? in
            let projectId = row.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            let overrideModeRaw = row.overrideMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !projectId.isEmpty,
                  let overrideMode = AXProjectRuntimeSurfaceHubOverrideMode(rawValue: overrideModeRaw) else {
                return nil
            }
            if let normalizedProjectId, !normalizedProjectId.isEmpty, projectId != normalizedProjectId {
                return nil
            }

            return RuntimeSurfaceOverrideItem(
                projectId: projectId,
                overrideMode: overrideMode,
                updatedAtMs: max(0, Int64((row.updatedAtMs ?? 0).rounded())),
                reason: row.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                auditRef: row.auditRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
        .sorted { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs { return lhs.updatedAtMs > rhs.updatedAtMs }
            return lhs.projectId.localizedCaseInsensitiveCompare(rhs.projectId) == .orderedAscending
        }

        return RuntimeSurfaceOverridesSnapshot(
            source: RuntimeSurfaceOverrideCompatContract.fileSource,
            updatedAtMs: max(0, Int64((decoded.updatedAtMs ?? 0).rounded())),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    @available(*, deprecated, message: "Use readLocalRuntimeSurfaceOverrides(projectId:limit:)")
    private static func readLocalAutonomyPolicyOverrides(
        projectId: String?,
        limit: Int
    ) -> AutonomyPolicyOverridesSnapshot? {
        readLocalRuntimeSurfaceOverrides(
            projectId: projectId,
            limit: limit
        )
    }

    private struct LocalSecretVaultItem: Codable {
        var itemId: String
        var scope: String
        var name: String
        var sensitivity: String?
        var createdAtMs: Double?
        var updatedAtMs: Double?

        enum CodingKeys: String, CodingKey {
            case itemId = "item_id"
            case scope
            case name
            case sensitivity
            case createdAtMs = "created_at_ms"
            case updatedAtMs = "updated_at_ms"
        }
    }

    private struct LocalSecretVaultSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalSecretVaultItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalSecretVaultSnapshot(
        scope: String?,
        namePrefix: String?,
        projectId: String?,
        limit: Int
    ) -> SecretVaultSnapshot? {
        if normalized(projectId) != nil {
            return nil
        }

        let url = HubPaths.baseDir().appendingPathComponent("secret_vault_items_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalSecretVaultSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedScope = normalized(scope)?.lowercased()
        let normalizedNamePrefix = normalized(namePrefix)?.lowercased()
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> SecretVaultItem? in
            let itemId = row.itemId.trimmingCharacters(in: .whitespacesAndNewlines)
            let scope = row.scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let sensitivity = row.sensitivity?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "secret"
            guard !itemId.isEmpty, !scope.isEmpty, !name.isEmpty else { return nil }
            if scope == "project" {
                return nil
            }
            if let normalizedScope, scope != normalizedScope {
                return nil
            }
            if let normalizedNamePrefix, !name.lowercased().hasPrefix(normalizedNamePrefix) {
                return nil
            }
            return SecretVaultItem(
                itemId: itemId,
                scope: scope,
                name: name,
                sensitivity: sensitivity,
                createdAtMs: max(0, Int64((row.createdAtMs ?? 0).rounded())),
                updatedAtMs: max(0, Int64((row.updatedAtMs ?? 0).rounded()))
            )
        }
        .sorted { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs { return lhs.updatedAtMs > rhs.updatedAtMs }
            let nameCompare = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameCompare != .orderedSame {
                return nameCompare == .orderedAscending
            }
            return lhs.itemId.localizedCaseInsensitiveCompare(rhs.itemId) == .orderedAscending
        }

        return SecretVaultSnapshot(
            source: "hub_secret_vault_file",
            updatedAtMs: max(0, Int64((decoded.updatedAtMs ?? 0).rounded())),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private static func fileIPCEventsDir() -> URL? {
        guard let st = HubConnector.readHubStatusIfAny(ttl: 3.0) else { return nil }
        guard let mode = st.ipcMode, mode == "file" else { return nil }
        guard let ipcPath = st.ipcPath, !ipcPath.isEmpty else { return nil }

        let dir = URL(fileURLWithPath: ipcPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func supervisorIncidentAuditEventsDir() -> URL? {
        if let dir = fileIPCEventsDir() {
            return dir
        }
        let fallback = HubPaths.baseDir().appendingPathComponent("ipc_events", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        } catch {
            return nil
        }
    }

    private static func pollMemoryContextResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> MemoryContextIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.25, min(4.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(MemoryContextIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func pollMemoryRetrievalResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> MemoryContextIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.25, min(4.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(MemoryContextIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func pollVoiceWakeProfileResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> VoiceWakeProfileIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(4.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(VoiceWakeProfileIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func pollVoiceTTSReadinessResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) -> VoiceTTSReadinessIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(3.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(VoiceTTSReadinessIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            usleep(90_000)
        }
        return nil
    }

    private static func pollVoiceTTSResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) -> VoiceTTSIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(5.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(VoiceTTSIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            usleep(90_000)
        }
        return nil
    }

    private static func pollLocalTaskResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) -> LocalTaskIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(8.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(LocalTaskIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            usleep(90_000)
        }
        return nil
    }

    private static func cachedVoiceTTSReadiness(for key: String) -> VoiceTTSReadinessResult? {
        voiceTTSReadinessCacheLock.lock()
        defer { voiceTTSReadinessCacheLock.unlock() }
        guard let cached = voiceTTSReadinessCache[key] else { return nil }
        if cached.expiresAt <= Date().timeIntervalSince1970 {
            voiceTTSReadinessCache.removeValue(forKey: key)
            return nil
        }
        return cached.result
    }

    private static func storeVoiceTTSReadiness(_ result: VoiceTTSReadinessResult, for key: String) {
        voiceTTSReadinessCacheLock.lock()
        voiceTTSReadinessCache[key] = CachedVoiceTTSReadiness(
            result: result,
            expiresAt: Date().timeIntervalSince1970 + voiceTTSReadinessCacheTTL
        )
        voiceTTSReadinessCacheLock.unlock()
    }

    private static func pollSecretVaultListResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> SecretVaultListIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(4.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(SecretVaultListIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func pollSecretVaultUseResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> SecretVaultUseIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(4.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(SecretVaultUseIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func pollNetworkResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> NetworkIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(6.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(NetworkIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func waitForBridgeEnabled(timeoutSec: Double) async -> HubBridgeClient.BridgeStatus {
        let deadline = Date().addingTimeInterval(max(0.2, min(8.0, timeoutSec)))
        while Date() < deadline {
            let st = HubBridgeClient.status()
            if st.enabled {
                return st
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return HubBridgeClient.status()
    }

    private static func mapPendingGrantActionResult(
        _ remote: HubRemotePendingGrantActionResult,
        defaultGrantRequestId: String
    ) -> PendingGrantActionResult {
        let mappedDecision: PendingGrantActionDecision = {
            switch remote.decision {
            case .approved:
                return .approved
            case .denied:
                return .denied
            case .failed:
                return .failed
            }
        }()
        let reason = normalizedReasonCode(remote.reasonCode, fallback: remote.ok ? nil : "pending_grant_action_failed")
        return PendingGrantActionResult(
            ok: remote.ok,
            decision: mappedDecision,
            source: "hub_runtime_grpc",
            grantRequestId: normalized(remote.grantRequestId) ?? defaultGrantRequestId,
            grantId: normalized(remote.grantId),
            expiresAtMs: remote.expiresAtMs,
            reasonCode: reason
        )
    }

    private static func mapSecretVaultCreateResult(
        _ remote: HubRemoteSecretVaultCreateResult
    ) -> SecretCreateResult {
        let mappedItem: SecretVaultItem? = {
            guard let item = remote.item else { return nil }
            return SecretVaultItem(
                itemId: item.itemId,
                scope: item.scope,
                name: item.name,
                sensitivity: item.sensitivity,
                createdAtMs: max(0, Int64(item.createdAtMs.rounded())),
                updatedAtMs: max(0, Int64(item.updatedAtMs.rounded()))
            )
        }()
        return SecretCreateResult(
            ok: remote.ok,
            source: remote.source,
            item: mappedItem,
            reasonCode: normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_secret_vault_create_failed"
            )
        )
    }

    private static func mapSecretVaultUseResult(
        _ remote: HubRemoteSecretVaultUseResult
    ) -> SecretUseResult {
        SecretUseResult(
            ok: remote.ok,
            source: remote.source,
            leaseId: normalized(remote.leaseId),
            useToken: normalized(remote.useToken),
            itemId: normalized(remote.itemId),
            expiresAtMs: remote.expiresAtMs.map { max(0, Int64($0.rounded())) },
            reasonCode: normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_secret_vault_use_failed"
            ),
            detail: normalized(remote.logText)
        )
    }

    private static func mapSecretVaultUseAck(
        _ ack: SecretVaultUseIPCResponse,
        source: String,
        fallbackItemId: String?
    ) -> SecretUseResult {
        guard ack.ok else {
            return SecretUseResult(
                ok: false,
                source: source,
                leaseId: nil,
                useToken: nil,
                itemId: fallbackItemId,
                expiresAtMs: nil,
                reasonCode: normalizedReasonCode(ack.error, fallback: "secret_vault_use_failed"),
                detail: normalized(ack.error)
            )
        }
        guard let result = ack.secretVaultUse else {
            return SecretUseResult(
                ok: false,
                source: source,
                leaseId: nil,
                useToken: nil,
                itemId: fallbackItemId,
                expiresAtMs: nil,
                reasonCode: "secret_vault_use_missing",
                detail: "secret vault use result missing from IPC ack"
            )
        }
        return SecretUseResult(
            ok: result.ok,
            source: source,
            leaseId: normalized(result.leaseId),
            useToken: normalized(result.useToken),
            itemId: normalized(result.itemId) ?? fallbackItemId,
            expiresAtMs: result.expiresAtMs.map { max(0, $0) },
            reasonCode: normalizedReasonCode(
                result.reasonCode,
                fallback: result.ok ? nil : "secret_vault_use_failed"
            ),
            detail: normalized(result.detail)
        )
    }

    private static func mapSecretVaultRedeemResult(
        _ remote: HubRemoteSecretVaultRedeemResult
    ) -> SecretRedeemResult {
        SecretRedeemResult(
            ok: remote.ok,
            source: remote.source,
            leaseId: normalized(remote.leaseId),
            itemId: normalized(remote.itemId),
            plaintext: remote.plaintext,
            reasonCode: normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_secret_vault_redeem_failed"
            ),
            detail: normalized(remote.logText)
        )
    }

    private static func mapSecretVaultRedeemAck(
        _ ack: SecretVaultRedeemIPCResponse,
        source: String
    ) -> SecretRedeemResult {
        guard ack.ok else {
            return SecretRedeemResult(
                ok: false,
                source: source,
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: normalizedReasonCode(ack.error, fallback: "secret_vault_redeem_failed"),
                detail: normalized(ack.error)
            )
        }
        guard let result = ack.secretVaultRedeem else {
            return SecretRedeemResult(
                ok: false,
                source: source,
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "secret_vault_redeem_missing",
                detail: "secret vault redeem result missing from IPC ack"
            )
        }
        return SecretRedeemResult(
            ok: result.ok,
            source: source,
            leaseId: normalized(result.leaseId),
            itemId: normalized(result.itemId),
            plaintext: result.plaintext,
            reasonCode: normalizedReasonCode(
                result.reasonCode,
                fallback: result.ok ? nil : "secret_vault_redeem_failed"
            ),
            detail: normalized(result.detail)
        )
    }

    private static func mapVoiceGrantChallengeResult(
        _ remote: HubRemoteVoiceGrantChallengeResult
    ) -> VoiceGrantChallengeResult {
        let mappedChallenge: VoiceGrantChallengeSnapshot? = {
            guard let challenge = remote.challenge else { return nil }
            return VoiceGrantChallengeSnapshot(
                challengeId: challenge.challengeId,
                templateId: challenge.templateId,
                actionDigest: challenge.actionDigest,
                scopeDigest: challenge.scopeDigest,
                amountDigest: challenge.amountDigest,
                challengeCode: challenge.challengeCode,
                riskLevel: challenge.riskLevel,
                requiresMobileConfirm: challenge.requiresMobileConfirm,
                allowVoiceOnly: challenge.allowVoiceOnly,
                boundDeviceId: challenge.boundDeviceId,
                mobileTerminalId: challenge.mobileTerminalId,
                issuedAtMs: challenge.issuedAtMs,
                expiresAtMs: challenge.expiresAtMs
            )
        }()
        return VoiceGrantChallengeResult(
            ok: remote.ok,
            source: remote.source,
            challenge: mappedChallenge,
            reasonCode: normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_voice_grant_challenge_failed"
            )
        )
    }

    private static func mapVoiceGrantVerificationResult(
        _ remote: HubRemoteVoiceGrantVerificationResult
    ) -> VoiceGrantVerificationResult {
        let mappedDecision: VoiceGrantVerificationDecision = {
            switch remote.decision {
            case .allow:
                return .allow
            case .deny:
                return .deny
            case .failed:
                return .failed
            }
        }()
        return VoiceGrantVerificationResult(
            ok: remote.ok,
            verified: remote.verified,
            decision: mappedDecision,
            source: remote.source,
            denyCode: normalized(remote.denyCode),
            challengeId: normalized(remote.challengeId),
            transcriptHash: normalized(remote.transcriptHash),
            semanticMatchScore: remote.semanticMatchScore,
            challengeMatch: remote.challengeMatch,
            deviceBindingOK: remote.deviceBindingOK,
            mobileConfirmed: remote.mobileConfirmed,
            reasonCode: normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_voice_grant_verify_failed"
            )
        )
    }

    private static func shouldInvalidateRemoteMemoryForVoiceGrantChallenge(
        _ result: VoiceGrantChallengeResult
    ) -> Bool {
        result.ok && result.challenge != nil
    }

    private static func shouldInvalidateRemoteMemoryForVoiceGrantVerification(
        _ result: VoiceGrantVerificationResult
    ) -> Bool {
        if result.ok || result.verified {
            return true
        }

        switch result.decision {
        case .allow, .deny:
            return true
        case .failed:
            return false
        }
    }

    static func normalizedReasonCode(_ raw: String?, fallback: String? = nil) -> String? {
        let primary = normalized(raw)
        let backup = normalized(fallback)
        let token = sanitizeReasonToken(primary ?? backup ?? "")
        guard !token.isEmpty else { return nil }

        if token.contains("grant_required") { return "grant_required" }
        if token.contains("bridge_disabled") { return "bridge_disabled" }
        if token.contains("bridge_unavailable") { return "bridge_unavailable" }
        if token.contains("permission_denied") || token.contains("forbidden") || token == "403" || token.contains("_403") {
            return "forbidden"
        }
        if token.contains("unauthenticated") || token == "401" || token.contains("_401") {
            return "unauthenticated"
        }
        if token.contains("certificate") || token.contains("tls") || token.contains("ssl") {
            return "tls_error"
        }
        if token.contains("timeout") { return "timeout" }
        if token.contains("hub_env_missing") { return "hub_env_missing" }
        if token.contains("client_kit_missing") { return "client_kit_missing" }
        if token.contains("node_missing") { return "node_missing" }
        if token.contains("hub_not_connected") || token.contains("not_connected") {
            return "hub_not_connected"
        }
        if token.contains("auto_approved") { return "auto_approved" }
        if token.contains("ack_timeout") { return "ack_timeout" }
        if token.contains("denied") { return "denied" }
        return token
    }

    static func isBridgeGrantRequiredReason(_ reasonCode: String?) -> Bool {
        guard let reason = normalizedReasonCode(reasonCode, fallback: nil) else { return false }
        return reason == "grant_required" || reason == "bridge_disabled" || reason == "bridge_unavailable"
    }

    private static func networkFailureState(reasonCode: String?) -> NetworkAccessState {
        guard let reason = normalizedReasonCode(reasonCode, fallback: nil) else { return .failed }
        if reason == "denied" || reason == "forbidden" {
            return .denied
        }
        return .failed
    }

    private static func sanitizeReasonToken(_ raw: String) -> String {
        var token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        while token.contains("__") {
            token = token.replacingOccurrences(of: "__", with: "_")
        }
        return token.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    static func writeLocalSnapshot<T: Encodable>(_ payload: T, to url: URL) -> Bool {
        do {
            let data = try JSONEncoder().encode(payload)
            try XTStoreWriteSupport.writeSnapshotData(data, to: url)
            return true
        } catch {
            return false
        }
    }

    private static func writeEventStatus(
        data: Data,
        reqId: String,
        filePrefix: String,
        tmpPrefix: String,
        in dir: URL
    ) -> IPCEventWriteStatus {
        let file = dir.appendingPathComponent("\(filePrefix)_\(Int(Date().timeIntervalSince1970))_\(reqId).json")
        let tmp = dir.appendingPathComponent("\(tmpPrefix)_\(reqId).tmp")
        do {
            if let override = withTestingOverrideLock({ eventWriteOverrideForTesting }) {
                try override(data, tmp, file)
            } else {
                try data.write(to: tmp, options: .atomic)
                try FileManager.default.moveItem(at: tmp, to: file)
            }
            return IPCEventWriteStatus(requestQueued: true, requestError: "")
        } catch {
            return IPCEventWriteStatus(
                requestQueued: false,
                requestError: "\(filePrefix)_write_failed=\(summarized(error))"
            )
        }
    }

    private static func writeEvent(
        data: Data,
        reqId: String,
        filePrefix: String,
        tmpPrefix: String,
        in dir: URL
    ) -> Bool {
        writeEventStatus(
            data: data,
            reqId: reqId,
            filePrefix: filePrefix,
            tmpPrefix: tmpPrefix,
            in: dir
        ).requestQueued == true
    }

    static func orderedUniqueStringTokens(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return raw.compactMap { item in
            guard let token = normalized(item)?.lowercased(), !token.isEmpty else { return nil }
            guard seen.insert(token).inserted else { return nil }
            return token
        }
    }

    static func orderedUniqueNormalizedStrings(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in raw {
            guard let trimmed = normalized(item) else { continue }
            let dedupeKey = trimmed.lowercased()
            guard seen.insert(dedupeKey).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered
    }

    private static func localModelStateSnapshot() -> ModelStateSnapshot? {
        let url = HubPaths.modelsStateURL()
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(ModelStateSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func rustMemoryGatewayDiagnosticLine(_ text: String?) -> String? {
        guard let normalized = normalized(text) else { return nil }
        let collapsed = normalized
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return String(collapsed.prefix(500))
    }

    private static func projectCanonicalRustSyncDetail(
        parsed: [String: Any]?,
        httpStatus: Int
    ) -> String {
        guard let parsed else {
            return "http_status=\(httpStatus)"
        }
        var parts = ["http_status=\(httpStatus)"]
        for key in [
            "planned_count",
            "created_count",
            "updated_count",
            "unchanged_count",
            "skipped_count",
            "blocking_count"
        ] {
            if let value = parsed[key] as? NSNumber {
                parts.append("\(key)=\(value.intValue)")
            } else if let value = parsed[key] as? Int {
                parts.append("\(key)=\(value)")
            }
        }
        if let status = normalized(parsed["status"] as? String) {
            parts.append("status=\(status)")
        }
        return parts.joined(separator: " ")
    }

    private static func memoryWritebackCandidateExtractDetail(
        _ result: MemoryWritebackCandidateExtractResult,
        httpStatus: Int
    ) -> String {
        var parts = ["http_status=\(httpStatus)"]
        let counts: [(String, Int?)] = [
            ("planned_count", result.plannedCount),
            ("planned_create_count", result.plannedCreateCount),
            ("created_count", result.createdCount),
            ("duplicate_count", result.duplicateCount),
            ("skipped_count", result.skippedCount),
            ("blocking_count", result.blockingCount)
        ]
        for (key, value) in counts {
            if let value {
                parts.append("\(key)=\(value)")
            }
        }
        if let status = normalized(result.status) {
            parts.append("status=\(status)")
        }
        if let activeWrite = result.candidateWriteback?.activeWrite {
            parts.append("active_write=\(activeWrite)")
        }
        return parts.joined(separator: " ")
    }

    private static func memoryWritebackCandidateListDetail(
        _ result: MemoryWritebackCandidateListResult,
        httpStatus: Int
    ) -> String {
        var parts = ["http_status=\(httpStatus)"]
        if let candidateCount = result.candidateCount {
            parts.append("candidate_count=\(candidateCount)")
        } else {
            parts.append("candidate_count=\(result.objects.count)")
        }
        if let status = normalized(result.status) {
            parts.append("status=\(status)")
        }
        return parts.joined(separator: " ")
    }

    private static func memoryWritebackCandidateDecisionDetail(
        _ result: MemoryWritebackCandidateDecisionResult,
        httpStatus: Int
    ) -> String {
        var parts = ["http_status=\(httpStatus)"]
        if let status = normalized(result.status) {
            parts.append("status=\(status)")
        }
        if let operation = normalized(result.transition?.operation ?? result.action) {
            parts.append("operation=\(operation)")
        }
        if let fromStatus = normalized(result.transition?.fromStatus) {
            parts.append("from_status=\(fromStatus)")
        }
        if let toStatus = normalized(result.transition?.toStatus) {
            parts.append("to_status=\(toStatus)")
        }
        if let productionAuthorityChange = result.productionAuthorityChange {
            parts.append("production_authority_change=\(productionAuthorityChange)")
        }
        return parts.joined(separator: " ")
    }

    private static func memoryWritebackCandidateMaintenanceDetail(
        _ result: MemoryWritebackCandidateMaintenanceResult,
        httpStatus: Int
    ) -> String {
        var parts = ["http_status=\(httpStatus)"]
        let counts: [(String, Int?)] = [
            ("candidate_count", result.candidateCount),
            ("stale_count", result.staleCount),
            ("planned_archive_count", result.plannedArchiveCount),
            ("planned_stale_review_required_count", result.plannedStaleReviewRequiredCount),
            ("mutation_count", result.mutationCount),
            ("skipped_count", result.skippedCount)
        ]
        for (key, value) in counts {
            if let value {
                parts.append("\(key)=\(value)")
            }
        }
        if let status = normalized(result.status) {
            parts.append("status=\(status)")
        }
        if let applied = result.applied {
            parts.append("applied=\(applied)")
        }
        if let productionAuthorityChange = result.productionAuthorityChange {
            parts.append("production_authority_change=\(productionAuthorityChange)")
        }
        return parts.joined(separator: " ")
    }

    private static func memoryObjectListDetail(
        _ result: MemoryObjectListResult,
        httpStatus: Int
    ) -> String {
        var parts = ["http_status=\(httpStatus)"]
        if let status = normalized(result.status) {
            parts.append("status=\(status)")
        }
        if let count = result.count {
            parts.append("count=\(count)")
        } else {
            parts.append("count=\(result.objects.count)")
        }
        if let scope = normalized(result.filter?.scope) {
            parts.append("scope=\(scope)")
        }
        if let projectId = normalized(result.filter?.projectId) {
            parts.append("project_id=\(projectId)")
        }
        if let objectStatus = normalized(result.filter?.status) {
            parts.append("object_status=\(objectStatus)")
        }
        return parts.joined(separator: " ")
    }

    private static func memoryUserRevealGrantDetail(
        _ result: MemoryUserRevealGrantResult,
        httpStatus: Int
    ) -> String {
        var parts = ["http_status=\(httpStatus)"]
        if let status = normalized(result.status) {
            parts.append("status=\(status)")
        }
        if let scope = normalized(result.scope) {
            parts.append("scope=\(scope)")
        }
        if let surface = normalized(result.surface) {
            parts.append("surface=\(surface)")
        }
        if let expiresAtMs = result.expiresAtMs {
            parts.append("expires_at_ms=\(expiresAtMs)")
        }
        if let productionAuthorityChange = result.productionAuthorityChange {
            parts.append("production_authority_change=\(productionAuthorityChange)")
        }
        return parts.joined(separator: " ")
    }

    private static func memoryObjectHistoryDetail(
        _ result: MemoryObjectHistoryResult,
        httpStatus: Int
    ) -> String {
        var parts = ["http_status=\(httpStatus)"]
        if let status = normalized(result.status) {
            parts.append("status=\(status)")
        }
        if let memoryId = normalized(result.memoryId) {
            parts.append("memory_id=\(memoryId)")
        }
        if let count = result.count {
            parts.append("count=\(count)")
        } else {
            parts.append("count=\(result.events.count)")
        }
        return parts.joined(separator: " ")
    }

    private static func memoryObjectDetail(
        _ result: MemoryObjectResult,
        httpStatus: Int
    ) -> String {
        var parts = ["http_status=\(httpStatus)"]
        if let status = normalized(result.status) {
            parts.append("status=\(status)")
        }
        if let memoryId = normalized(result.memoryId) {
            parts.append("memory_id=\(memoryId)")
        }
        if let objectStatus = normalized(result.object?.status) {
            parts.append("object_status=\(objectStatus)")
        }
        return parts.joined(separator: " ")
    }

    private static func memoryObjectMutationDetail(
        _ result: MemoryObjectMutationResult,
        httpStatus: Int
    ) -> String {
        var parts = ["http_status=\(httpStatus)"]
        if let status = normalized(result.status) {
            parts.append("status=\(status)")
        }
        if let operation = normalized(result.mutation?.operation ?? result.action) {
            parts.append("operation=\(operation)")
        }
        if let fromStatus = normalized(result.mutation?.fromStatus) {
            parts.append("from_status=\(fromStatus)")
        }
        if let toStatus = normalized(result.mutation?.toStatus ?? result.object?.status) {
            parts.append("to_status=\(toStatus)")
        }
        if let version = result.version ?? result.object?.version {
            parts.append("version=\(version)")
        }
        if let eventId = normalized(result.eventId) {
            parts.append("event_id_present=\(!eventId.isEmpty)")
        }
        if let productionAuthorityChange = result.productionAuthorityChange ?? result.mutation?.productionAuthorityChange {
            parts.append("production_authority_change=\(productionAuthorityChange)")
        }
        return parts.joined(separator: " ")
    }

    static func normalizedReviewLevelHint(_ raw: String?) -> String? {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case SupervisorReviewLevel.r1Pulse.rawValue:
            return SupervisorReviewLevel.r1Pulse.rawValue
        case SupervisorReviewLevel.r2Strategic.rawValue:
            return SupervisorReviewLevel.r2Strategic.rawValue
        case SupervisorReviewLevel.r3Rescue.rawValue:
            return SupervisorReviewLevel.r3Rescue.rawValue
        default:
            return nil
        }
    }

    static func installSecretVaultUseOverrideForTesting(
        _ override: (@Sendable (SecretUseRequestPayload) async -> SecretUseResult)?
    ) {
        withTestingOverrideLock {
            secretUseOverrideForTesting = override
        }
    }

    static func installAgentImportStageOverrideForTesting(
        _ override: (@Sendable (AgentImportStageRequestPayload) async -> AgentImportStageResult)?
    ) {
        withTestingOverrideLock {
            agentImportStageOverrideForTesting = override
        }
    }

    static func installAgentImportRecordOverrideForTesting(
        _ override: (@Sendable (AgentImportRecordLookupPayload) async -> AgentImportRecordResult)?
    ) {
        withTestingOverrideLock {
            agentImportRecordOverrideForTesting = override
        }
    }

    static func installSkillPackageUploadOverrideForTesting(
        _ override: (@Sendable (SkillPackageUploadRequestPayload) async -> SkillPackageUploadResult)?
    ) {
        withTestingOverrideLock {
            skillPackageUploadOverrideForTesting = override
        }
    }

    static func installAgentImportPromoteOverrideForTesting(
        _ override: (@Sendable (AgentImportPromoteRequestPayload) async -> AgentImportPromoteResult)?
    ) {
        withTestingOverrideLock {
            agentImportPromoteOverrideForTesting = override
        }
    }

    static func installSkillPinOverrideForTesting(
        _ override: (@Sendable (SkillPinRequestPayload) async -> SkillPinResult)?
    ) {
        withTestingOverrideLock {
            skillPinOverrideForTesting = override
            setTestingOverride(
                override,
                fallback: &skillPinOverrideForTesting,
                scoped: &scopedSkillPinOverridesForTesting
            )
        }
    }

    static func installResolvedSkillsOverrideForTesting(
        _ override: (@Sendable (String?) async -> ResolvedSkillsResult)?
    ) {
        withTestingOverrideLock {
            resolvedSkillsOverrideForTesting = override
            setTestingOverride(
                override,
                fallback: &resolvedSkillsOverrideForTesting,
                scoped: &scopedResolvedSkillsOverridesForTesting
            )
        }
    }

    static func installSkillManifestOverrideForTesting(
        _ override: (@Sendable (String) async -> SkillManifestResult)?
    ) {
        withTestingOverrideLock {
            skillManifestOverrideForTesting = override
            setTestingOverride(
                override,
                fallback: &skillManifestOverrideForTesting,
                scoped: &scopedSkillManifestOverridesForTesting
            )
        }
    }

    static func installSkillPackageDownloadOverrideForTesting(
        _ override: (@Sendable (String) async -> SkillPackageDownloadResult)?
    ) {
        withTestingOverrideLock {
            skillPackageDownloadOverrideForTesting = override
            setTestingOverride(
                override,
                fallback: &skillPackageDownloadOverrideForTesting,
                scoped: &scopedSkillPackageDownloadOverridesForTesting
            )
        }
    }

    static func installSkillRunnerGateOverrideForTesting(
        _ override: (@Sendable (SkillRunnerGateRequestPayload) async -> SkillRunnerGateResult)?
    ) {
        withTestingOverrideLock {
            skillRunnerGateOverrideForTesting = override
            setTestingOverride(
                override,
                fallback: &skillRunnerGateOverrideForTesting,
                scoped: &scopedSkillRunnerGateOverridesForTesting
            )
        }
    }

    static func installSecretVaultRedeemOverrideForTesting(
        _ override: (@Sendable (SecretRedeemRequestPayload) async -> SecretRedeemResult)?
    ) {
        withTestingOverrideLock {
            secretRedeemOverrideForTesting = override
        }
    }

    static func installLocalTaskExecutionOverrideForTesting(
        _ override: (@Sendable (LocalTaskRequestPayload, Double) -> LocalTaskResult)?
    ) {
        withTestingOverrideLock {
            localTaskExecutionOverrideForTesting = override
        }
    }

    static func installHubRouteDecisionOverrideForTesting(
        _ override: (@Sendable () async -> HubRouteDecision)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &routeDecisionOverrideForTesting,
                scoped: &scopedRouteDecisionOverridesForTesting
            )
        }
    }

    static func installMemoryContextResolutionOverrideForTesting(
        _ override: (@Sendable (XTMemoryRouteDecision, XTMemoryUseMode, Double) async -> MemoryContextResolutionResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &memoryContextResolutionOverrideForTesting,
                scoped: &scopedMemoryContextResolutionOverridesForTesting
            )
        }
    }

    static func installMemoryRetrievalOverrideForTesting(
        _ override: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &memoryRetrievalOverrideForTesting,
                scoped: &scopedMemoryRetrievalOverridesForTesting
            )
        }
    }

    static func installSupervisorRemoteContinuityOverrideForTesting(
        _ override: (@Sendable (Bool) async -> SupervisorRemoteContinuityResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &supervisorRemoteContinuityOverrideForTesting,
                scoped: &scopedSupervisorRemoteContinuityOverridesForTesting
            )
        }
    }

    static func installSupervisorConversationAppendOverrideForTesting(
        _ override: (@Sendable (HubRemoteSupervisorConversationPayload) async -> Bool)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &supervisorConversationAppendOverrideForTesting,
                scoped: &scopedSupervisorConversationAppendOverridesForTesting
            )
        }
    }

    static func installSupervisorRouteDecisionOverrideForTesting(
        _ override: (@Sendable (SupervisorRouteDecisionRequestPayload) async -> SupervisorRouteDecisionResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &supervisorRouteDecisionOverrideForTesting,
                scoped: &scopedSupervisorRouteDecisionOverridesForTesting
            )
        }
    }

    static func installLocalMemoryRetrievalIPCOverrideForTesting(
        _ override: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &localMemoryRetrievalIPCOverrideForTesting,
                scoped: &scopedLocalMemoryRetrievalIPCOverridesForTesting
            )
        }
    }

    static func installRemoteMemorySnapshotOverrideForTesting(
        _ override: (@Sendable (XTMemoryUseMode, String?, Bool, Double) async -> HubRemoteMemorySnapshotResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &remoteMemorySnapshotOverrideForTesting,
                scoped: &scopedRemoteMemorySnapshotOverridesForTesting
            )
        }
    }

    static func installVoiceGrantChallengeOverrideForTesting(
        _ override: (@Sendable (VoiceGrantChallengeRequestPayload) async -> VoiceGrantChallengeResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &voiceGrantChallengeOverrideForTesting,
                scoped: &scopedVoiceGrantChallengeOverridesForTesting
            )
        }
    }

    static func installVoiceGrantVerificationOverrideForTesting(
        _ override: (@Sendable (VoiceGrantVerificationPayload) async -> VoiceGrantVerificationResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &voiceGrantVerificationOverrideForTesting,
                scoped: &scopedVoiceGrantVerificationOverridesForTesting
            )
        }
    }

    static func installRemoteMemoryRetrievalOverrideForTesting(
        _ override: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &remoteMemoryRetrievalOverrideForTesting,
                scoped: &scopedRemoteMemoryRetrievalOverridesForTesting
            )
        }
    }

    static func installRemoteRuntimeSurfaceOverridesOverrideForTesting(
        _ override: (@Sendable (String?, Int, Double) async -> HubRemoteRuntimeSurfaceOverridesResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &remoteRuntimeSurfaceOverridesOverrideForTesting,
                scoped: &scopedRemoteRuntimeSurfaceOverridesForTesting
            )
        }
    }

    static func installProjectCanonicalRustSyncOverrideForTesting(
        _ override: (@Sendable (ProjectCanonicalMemoryPayload) async -> ProjectCanonicalMemoryRustSyncOverrideResult?)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &projectCanonicalRustSyncOverrideForTesting,
                scoped: &scopedProjectCanonicalRustSyncOverridesForTesting
            )
        }
    }

    static func installRustProjectCanonicalMemoryOverrideForTesting(
        _ override: (@Sendable (String, Int, Double) async -> RustProjectCanonicalMemorySnapshot?)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &rustProjectCanonicalMemoryOverrideForTesting,
                scoped: &scopedRustProjectCanonicalMemoryOverridesForTesting
            )
        }
    }

    static func installRustMemoryGatewayPrepareOverrideForTesting(
        _ override: (@Sendable (RustMemoryGatewayPrepareRequest, Double) async -> RustMemoryGatewayPrepareResult?)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &rustMemoryGatewayPrepareOverrideForTesting,
                scoped: &scopedRustMemoryGatewayPrepareOverridesForTesting
            )
        }
    }

    static func installRustMemoryGatewayModelCallPlanOverrideForTesting(
        _ override: (@Sendable (RustMemoryGatewayModelCallPlanRequest, Double) async -> RustMemoryGatewayModelCallPlanResult?)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &rustMemoryGatewayModelCallPlanOverrideForTesting,
                scoped: &scopedRustMemoryGatewayModelCallPlanOverridesForTesting
            )
        }
    }

    static func installMemoryWritebackCandidateExtractOverrideForTesting(
        _ override: (@Sendable (MemoryWritebackCandidateExtractPayload, Double) async -> MemoryWritebackCandidateExtractResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &memoryWritebackCandidateExtractOverrideForTesting,
                scoped: &scopedMemoryWritebackCandidateExtractOverridesForTesting
            )
        }
    }

    static func installMemoryWritebackCandidateListOverrideForTesting(
        _ override: (@Sendable (String?, Int, Double) async -> MemoryWritebackCandidateListResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &memoryWritebackCandidateListOverrideForTesting,
                scoped: &scopedMemoryWritebackCandidateListOverridesForTesting
            )
        }
    }

    static func installMemoryWritebackCandidateDecisionOverrideForTesting(
        _ override: (@Sendable (String, String, MemoryWritebackCandidateDecisionPayload, Double) async -> MemoryWritebackCandidateDecisionResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &memoryWritebackCandidateDecisionOverrideForTesting,
                scoped: &scopedMemoryWritebackCandidateDecisionOverridesForTesting
            )
        }
    }

    static func installMemoryWritebackCandidateMaintenanceOverrideForTesting(
        _ override: (@Sendable (MemoryWritebackCandidateMaintenancePayload, Double) async -> MemoryWritebackCandidateMaintenanceResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &memoryWritebackCandidateMaintenanceOverrideForTesting,
                scoped: &scopedMemoryWritebackCandidateMaintenanceOverridesForTesting
            )
        }
    }

    static func installMemoryObjectListOverrideForTesting(
        _ override: (@Sendable (MemoryObjectListFilter, Double) async -> MemoryObjectListResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &memoryObjectListOverrideForTesting,
                scoped: &scopedMemoryObjectListOverridesForTesting
            )
        }
    }

    static func installMemoryUserRevealGrantOverrideForTesting(
        _ override: (@Sendable (MemoryUserRevealGrantRequest, Double) async -> MemoryUserRevealGrantResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &memoryUserRevealGrantOverrideForTesting,
                scoped: &scopedMemoryUserRevealGrantOverridesForTesting
            )
        }
    }

    static func installMemoryObjectHistoryOverrideForTesting(
        _ override: (@Sendable (String, Int, Double) async -> MemoryObjectHistoryResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &memoryObjectHistoryOverrideForTesting,
                scoped: &scopedMemoryObjectHistoryOverridesForTesting
            )
        }
    }

    static func installMemoryObjectGetOverrideForTesting(
        _ override: (@Sendable (String, Double) async -> MemoryObjectResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &memoryObjectGetOverrideForTesting,
                scoped: &scopedMemoryObjectGetOverridesForTesting
            )
        }
    }

    static func installMemoryObjectMutationOverrideForTesting(
        _ override: (@Sendable (String, String, MemoryObjectMutationPayload, Double) async -> MemoryObjectMutationResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &memoryObjectMutationOverrideForTesting,
                scoped: &scopedMemoryObjectMutationOverridesForTesting
            )
        }
    }

    static func installProjectCanonicalRustSyncUnscopedOverrideForTesting(
        _ override: (@Sendable (ProjectCanonicalMemoryPayload) async -> ProjectCanonicalMemoryRustSyncOverrideResult?)?
    ) {
        withTestingOverrideLock {
            projectCanonicalRustSyncOverrideForTesting = override
        }
    }

    static func installRemoteMemoryRetrievalOverrideForTesting(
        _ override: (@Sendable (MemoryRetrievalPayload) async -> MemoryRetrievalResponsePayload?)?
    ) {
        withTestingOverrideLock {
            guard let override else {
                setTestingOverride(
                    nil as (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)?,
                    fallback: &remoteMemoryRetrievalOverrideForTesting,
                    scoped: &scopedRemoteMemoryRetrievalOverridesForTesting
                )
                return
            }
            setTestingOverride(
                { payload, _ in
                    await override(payload)
                },
                fallback: &remoteMemoryRetrievalOverrideForTesting,
                scoped: &scopedRemoteMemoryRetrievalOverridesForTesting
            )
        }
    }

    static func installIPCEventWriteOverrideForTesting(
        _ override: (@Sendable (Data, URL, URL) throws -> Void)?
    ) {
        withTestingOverrideLock {
            eventWriteOverrideForTesting = override
        }
    }

    static func resetSecretVaultOverridesForTesting() {
        withTestingOverrideLock {
            secretUseOverrideForTesting = nil
            secretRedeemOverrideForTesting = nil
        }
    }

    static func resetLocalTaskExecutionOverrideForTesting() {
        withTestingOverrideLock {
            localTaskExecutionOverrideForTesting = nil
        }
    }

    static func resetMemoryContextResolutionOverrideForTesting() {
        withTestingOverrideLock {
            resetTestingOverride(
                fallback: &routeDecisionOverrideForTesting,
                scoped: &scopedRouteDecisionOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryContextResolutionOverrideForTesting,
                scoped: &scopedMemoryContextResolutionOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryRetrievalOverrideForTesting,
                scoped: &scopedMemoryRetrievalOverridesForTesting
            )
            resetTestingOverride(
                fallback: &localMemoryRetrievalIPCOverrideForTesting,
                scoped: &scopedLocalMemoryRetrievalIPCOverridesForTesting
            )
            resetTestingOverride(
                fallback: &remoteMemorySnapshotOverrideForTesting,
                scoped: &scopedRemoteMemorySnapshotOverridesForTesting
            )
            resetTestingOverride(
                fallback: &voiceGrantChallengeOverrideForTesting,
                scoped: &scopedVoiceGrantChallengeOverridesForTesting
            )
            resetTestingOverride(
                fallback: &voiceGrantVerificationOverrideForTesting,
                scoped: &scopedVoiceGrantVerificationOverridesForTesting
            )
            resetTestingOverride(
                fallback: &remoteMemoryRetrievalOverrideForTesting,
                scoped: &scopedRemoteMemoryRetrievalOverridesForTesting
            )
            resetTestingOverride(
                fallback: &remoteRuntimeSurfaceOverridesOverrideForTesting,
                scoped: &scopedRemoteRuntimeSurfaceOverridesForTesting
            )
            resetTestingOverride(
                fallback: &rustProjectCanonicalMemoryOverrideForTesting,
                scoped: &scopedRustProjectCanonicalMemoryOverridesForTesting
            )
            resetTestingOverride(
                fallback: &rustMemoryGatewayPrepareOverrideForTesting,
                scoped: &scopedRustMemoryGatewayPrepareOverridesForTesting
            )
            resetTestingOverride(
                fallback: &rustMemoryGatewayModelCallPlanOverrideForTesting,
                scoped: &scopedRustMemoryGatewayModelCallPlanOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryWritebackCandidateExtractOverrideForTesting,
                scoped: &scopedMemoryWritebackCandidateExtractOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryWritebackCandidateListOverrideForTesting,
                scoped: &scopedMemoryWritebackCandidateListOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryWritebackCandidateDecisionOverrideForTesting,
                scoped: &scopedMemoryWritebackCandidateDecisionOverridesForTesting
            )
            resetTestingOverride(
                fallback: &supervisorRemoteContinuityOverrideForTesting,
                scoped: &scopedSupervisorRemoteContinuityOverridesForTesting
            )
            resetTestingOverride(
                fallback: &supervisorConversationAppendOverrideForTesting,
                scoped: &scopedSupervisorConversationAppendOverridesForTesting
            )
            resetTestingOverride(
                fallback: &supervisorRouteDecisionOverrideForTesting,
                scoped: &scopedSupervisorRouteDecisionOverridesForTesting
            )
        }
        resetRuntimeSurfaceRemoteStateForTesting()
    }

    static func resetIPCEventWriteOverrideForTesting() {
        withTestingOverrideLock {
            eventWriteOverrideForTesting = nil
        }
    }

    static func resetProjectCanonicalRustSyncOverrideForTesting() {
        withTestingOverrideLock {
            resetTestingOverride(
                fallback: &projectCanonicalRustSyncOverrideForTesting,
                scoped: &scopedProjectCanonicalRustSyncOverridesForTesting
            )
        }
    }

    static func resetRustProjectCanonicalMemoryOverrideForTesting() {
        withTestingOverrideLock {
            resetTestingOverride(
                fallback: &rustProjectCanonicalMemoryOverrideForTesting,
                scoped: &scopedRustProjectCanonicalMemoryOverridesForTesting
            )
        }
    }

    static func resetRustMemoryGatewayPrepareOverrideForTesting() {
        withTestingOverrideLock {
            resetTestingOverride(
                fallback: &rustMemoryGatewayPrepareOverrideForTesting,
                scoped: &scopedRustMemoryGatewayPrepareOverridesForTesting
            )
        }
    }

    static func resetRustMemoryGatewayModelCallPlanOverrideForTesting() {
        withTestingOverrideLock {
            resetTestingOverride(
                fallback: &rustMemoryGatewayModelCallPlanOverrideForTesting,
                scoped: &scopedRustMemoryGatewayModelCallPlanOverridesForTesting
            )
        }
    }

    static func resetMemoryWritebackCandidateExtractOverrideForTesting() {
        withTestingOverrideLock {
            resetTestingOverride(
                fallback: &memoryWritebackCandidateExtractOverrideForTesting,
                scoped: &scopedMemoryWritebackCandidateExtractOverridesForTesting
            )
        }
    }

    static func resetMemoryObjectOverridesForTesting() {
        withTestingOverrideLock {
            resetTestingOverride(
                fallback: &memoryObjectListOverrideForTesting,
                scoped: &scopedMemoryObjectListOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryUserRevealGrantOverrideForTesting,
                scoped: &scopedMemoryUserRevealGrantOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryObjectHistoryOverrideForTesting,
                scoped: &scopedMemoryObjectHistoryOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryObjectGetOverrideForTesting,
                scoped: &scopedMemoryObjectGetOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryObjectMutationOverrideForTesting,
                scoped: &scopedMemoryObjectMutationOverridesForTesting
            )
        }
    }

    static func resetMemoryWritebackCandidateQueueOverridesForTesting() {
        withTestingOverrideLock {
            resetTestingOverride(
                fallback: &memoryWritebackCandidateListOverrideForTesting,
                scoped: &scopedMemoryWritebackCandidateListOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryWritebackCandidateDecisionOverrideForTesting,
                scoped: &scopedMemoryWritebackCandidateDecisionOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryWritebackCandidateMaintenanceOverrideForTesting,
                scoped: &scopedMemoryWritebackCandidateMaintenanceOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryObjectListOverrideForTesting,
                scoped: &scopedMemoryObjectListOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryUserRevealGrantOverrideForTesting,
                scoped: &scopedMemoryUserRevealGrantOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryObjectHistoryOverrideForTesting,
                scoped: &scopedMemoryObjectHistoryOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryObjectGetOverrideForTesting,
                scoped: &scopedMemoryObjectGetOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryObjectMutationOverrideForTesting,
                scoped: &scopedMemoryObjectMutationOverridesForTesting
            )
        }
    }

    static func resetProjectCanonicalRustSyncUnscopedOverrideForTesting() {
        withTestingOverrideLock {
            projectCanonicalRustSyncOverrideForTesting = nil
        }
    }

    static func resetAgentImportRecordOverrideForTesting() {
        withTestingOverrideLock {
            agentImportRecordOverrideForTesting = nil
        }
    }

    static func resetAgentImportStageOverrideForTesting() {
        withTestingOverrideLock {
            agentImportStageOverrideForTesting = nil
        }
    }

    static func resetSkillPackageUploadOverrideForTesting() {
        withTestingOverrideLock {
            skillPackageUploadOverrideForTesting = nil
        }
    }

    static func resetAgentImportPromoteOverrideForTesting() {
        withTestingOverrideLock {
            agentImportPromoteOverrideForTesting = nil
        }
    }

    static func resetSkillPinOverrideForTesting() {
        withTestingOverrideLock {
            skillPinOverrideForTesting = nil
            resetTestingOverride(
                fallback: &skillPinOverrideForTesting,
                scoped: &scopedSkillPinOverridesForTesting
            )
        }
    }

    static func resetResolvedSkillsOverrideForTesting() {
        withTestingOverrideLock {
            resolvedSkillsOverrideForTesting = nil
            resetTestingOverride(
                fallback: &resolvedSkillsOverrideForTesting,
                scoped: &scopedResolvedSkillsOverridesForTesting
            )
        }
    }

    static func resetSkillManifestOverrideForTesting() {
        withTestingOverrideLock {
            skillManifestOverrideForTesting = nil
            resetTestingOverride(
                fallback: &skillManifestOverrideForTesting,
                scoped: &scopedSkillManifestOverridesForTesting
            )
        }
    }

    static func resetSkillPackageDownloadOverrideForTesting() {
        withTestingOverrideLock {
            skillPackageDownloadOverrideForTesting = nil
            resetTestingOverride(
                fallback: &skillPackageDownloadOverrideForTesting,
                scoped: &scopedSkillPackageDownloadOverridesForTesting
            )
        }
    }

    static func resetSkillRunnerGateOverrideForTesting() {
        withTestingOverrideLock {
            skillRunnerGateOverrideForTesting = nil
            resetTestingOverride(
                fallback: &skillRunnerGateOverrideForTesting,
                scoped: &scopedSkillRunnerGateOverridesForTesting
            )
        }
    }
}

private extension Array where Element == String {
    var nonEmptyArray: [String]? {
        isEmpty ? nil : self
    }
}
