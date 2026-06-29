import Foundation

extension HubPairingCoordinator {
    nonisolated static func remoteGenerateResultForTesting(
        jsonLine: String,
        requestedModelId: String? = nil
    ) -> HubRemoteGenerateResult? {
        guard let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteGenerateScriptResult.self, from: data),
              decoded.ok == true else {
            return nil
        }
        return successfulRemoteGenerateResult(
            from: decoded,
            fallbackModelId: requestedModelId,
            logLines: []
        )
    }

    nonisolated static func remoteSupervisorCandidateReviewQueueResultForTesting(
        jsonLine: String
    ) -> HubRemoteSupervisorCandidateReviewQueueResult? {
        guard let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteSupervisorCandidateReviewQueueScriptResult.self, from: data),
              decoded.ok == true else {
            return nil
        }

        let items = (decoded.items ?? []).compactMap { row -> HubRemoteSupervisorCandidateReviewQueueItem? in
            let requestId = row.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !requestId.isEmpty else { return nil }
            return HubRemoteSupervisorCandidateReviewQueueItem(
                schemaVersion: row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                reviewId: row.reviewId.trimmingCharacters(in: .whitespacesAndNewlines),
                requestId: requestId,
                evidenceRef: row.evidenceRef.trimmingCharacters(in: .whitespacesAndNewlines),
                reviewState: row.reviewState.trimmingCharacters(in: .whitespacesAndNewlines),
                durablePromotionState: row.durablePromotionState.trimmingCharacters(in: .whitespacesAndNewlines),
                promotionBoundary: row.promotionBoundary.trimmingCharacters(in: .whitespacesAndNewlines),
                deviceId: row.deviceId.trimmingCharacters(in: .whitespacesAndNewlines),
                userId: row.userId.trimmingCharacters(in: .whitespacesAndNewlines),
                appId: row.appId.trimmingCharacters(in: .whitespacesAndNewlines),
                threadId: row.threadId.trimmingCharacters(in: .whitespacesAndNewlines),
                threadKey: row.threadKey.trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                projectIds: row.projectIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                scopes: row.scopes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                recordTypes: row.recordTypes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                auditRefs: row.auditRefs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                idempotencyKeys: row.idempotencyKeys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                candidateCount: max(0, row.candidateCount ?? 0),
                summaryLine: row.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines),
                mirrorTarget: row.mirrorTarget.trimmingCharacters(in: .whitespacesAndNewlines),
                localStoreRole: row.localStoreRole.trimmingCharacters(in: .whitespacesAndNewlines),
                carrierKind: row.carrierKind.trimmingCharacters(in: .whitespacesAndNewlines),
                carrierSchemaVersion: row.carrierSchemaVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                pendingChangeId: row.pendingChangeId.trimmingCharacters(in: .whitespacesAndNewlines),
                pendingChangeStatus: row.pendingChangeStatus.trimmingCharacters(in: .whitespacesAndNewlines),
                editSessionId: row.editSessionId.trimmingCharacters(in: .whitespacesAndNewlines),
                docId: row.docId.trimmingCharacters(in: .whitespacesAndNewlines),
                writebackRef: row.writebackRef.trimmingCharacters(in: .whitespacesAndNewlines),
                stageCreatedAtMs: max(0, row.stageCreatedAtMs ?? 0),
                stageUpdatedAtMs: max(0, row.stageUpdatedAtMs ?? 0),
                latestEmittedAtMs: max(0, row.latestEmittedAtMs ?? 0),
                createdAtMs: max(0, row.createdAtMs ?? 0),
                updatedAtMs: max(0, row.updatedAtMs ?? 0)
            )
        }

        return HubRemoteSupervisorCandidateReviewQueueResult(
            ok: true,
            source: (decoded.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: items,
            reasonCode: nil,
            logLines: []
        )
    }

    nonisolated static func remoteSupervisorCandidateReviewStageResultForTesting(
        jsonLine: String
    ) -> HubRemoteSupervisorCandidateReviewStageResult? {
        guard let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteSupervisorCandidateReviewStageScriptResult.self, from: data),
              decoded.ok == true else {
            return nil
        }

        return HubRemoteSupervisorCandidateReviewStageResult(
            ok: true,
            staged: decoded.staged ?? false,
            idempotent: decoded.idempotent ?? false,
            source: (decoded.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            reviewState: (decoded.reviewState ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            durablePromotionState: (decoded.durablePromotionState ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            promotionBoundary: (decoded.promotionBoundary ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            candidateRequestId: decoded.candidateRequestId?.trimmingCharacters(in: .whitespacesAndNewlines),
            evidenceRef: decoded.evidenceRef?.trimmingCharacters(in: .whitespacesAndNewlines),
            editSessionId: decoded.editSessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
            pendingChangeId: decoded.pendingChangeId?.trimmingCharacters(in: .whitespacesAndNewlines),
            docId: decoded.docId?.trimmingCharacters(in: .whitespacesAndNewlines),
            baseVersion: decoded.baseVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
            workingVersion: decoded.workingVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
            sessionRevision: Int64(decoded.sessionRevision ?? 0),
            status: decoded.status?.trimmingCharacters(in: .whitespacesAndNewlines),
            markdown: decoded.markdown,
            createdAtMs: max(0, decoded.createdAtMs ?? 0),
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            expiresAtMs: max(0, decoded.expiresAtMs ?? 0),
            reasonCode: nil,
            logLines: []
        )
    }

    nonisolated static func remoteLongtermMarkdownReviewResultForTesting(
        jsonLine: String
    ) -> HubRemoteLongtermMarkdownReviewResult? {
        guard let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteLongtermMarkdownReviewScriptResult.self, from: data),
              decoded.ok == true else {
            return nil
        }

        return HubRemoteLongtermMarkdownReviewResult(
            ok: true,
            source: (decoded.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            pendingChangeId: decoded.pendingChangeId?.trimmingCharacters(in: .whitespacesAndNewlines),
            editSessionId: decoded.editSessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
            docId: decoded.docId?.trimmingCharacters(in: .whitespacesAndNewlines),
            status: decoded.status?.trimmingCharacters(in: .whitespacesAndNewlines),
            reviewDecision: decoded.reviewDecision?.trimmingCharacters(in: .whitespacesAndNewlines),
            policyDecision: decoded.policyDecision?.trimmingCharacters(in: .whitespacesAndNewlines),
            findingsJSON: decoded.findingsJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
            redactedCount: max(0, decoded.redactedCount ?? 0),
            reviewedAtMs: max(0, decoded.reviewedAtMs ?? 0),
            approvedAtMs: max(0, decoded.approvedAtMs ?? 0),
            markdown: decoded.markdown,
            autoRejected: decoded.autoRejected ?? false,
            reasonCode: nil,
            logLines: []
        )
    }

    nonisolated static func remoteLongtermMarkdownWritebackResultForTesting(
        jsonLine: String
    ) -> HubRemoteLongtermMarkdownWritebackResult? {
        guard let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteLongtermMarkdownWritebackScriptResult.self, from: data),
              decoded.ok == true else {
            return nil
        }

        return HubRemoteLongtermMarkdownWritebackResult(
            ok: true,
            source: (decoded.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            pendingChangeId: decoded.pendingChangeId?.trimmingCharacters(in: .whitespacesAndNewlines),
            status: decoded.status?.trimmingCharacters(in: .whitespacesAndNewlines),
            candidateId: decoded.candidateId?.trimmingCharacters(in: .whitespacesAndNewlines),
            queueStatus: decoded.queueStatus?.trimmingCharacters(in: .whitespacesAndNewlines),
            writtenAtMs: max(0, decoded.writtenAtMs ?? 0),
            docId: decoded.docId?.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceVersion: decoded.sourceVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
            changeLogId: decoded.changeLogId?.trimmingCharacters(in: .whitespacesAndNewlines),
            evidenceRef: decoded.evidenceRef?.trimmingCharacters(in: .whitespacesAndNewlines),
            reasonCode: nil,
            logLines: []
        )
    }

    nonisolated static func normalizedRemoteReasonCodeForTesting(
        _ rawReason: String?,
        stepOutput: String = "",
        fallback: String = "remote_chat_failed"
    ) -> String {
        normalizedRemoteReasonCode(
            rawReason: rawReason,
            stepOutput: stepOutput,
            fallback: fallback
        )
    }

    nonisolated static func inferFailureCodeForTesting(
        from output: String,
        fallback: String
    ) -> String {
        inferFailureCodeFromText(output, fallback: fallback)
    }

    nonisolated static func pairingMetadataRepairReasonForTesting(
        cachedHubInstanceID: String? = nil,
        discoveredHubInstanceID: String? = nil,
        cachedPairingProfileEpoch: Int? = nil,
        discoveredPairingProfileEpoch: Int? = nil,
        cachedRoutePackVersion: String? = nil,
        discoveredRoutePackVersion: String? = nil
    ) -> String? {
        pairingMetadataRepairBlockValue(
            cachedHubInstanceID: cachedHubInstanceID,
            discoveredHubInstanceID: discoveredHubInstanceID,
            cachedPairingProfileEpoch: cachedPairingProfileEpoch,
            discoveredPairingProfileEpoch: discoveredPairingProfileEpoch,
            cachedRoutePackVersion: cachedRoutePackVersion,
            discoveredRoutePackVersion: discoveredRoutePackVersion
        )?.reasonCode
    }

    nonisolated static func parseRemoteModelsResultForTesting(
        _ output: String
    ) -> HubRemoteModelsResult {
        let parsed = parseListModelsResultText(output)
        return HubRemoteModelsResult(
            ok: true,
            models: parsed.models,
            paidAccessSnapshot: parsed.paidAccessSnapshot,
            reasonCode: nil,
            logLines: []
        )
    }

    nonisolated static func inferredReusableInternetHostForTesting(
        _ host: String?,
        hubInstanceID: String? = nil,
        lanDiscoveryName: String? = nil
    ) -> String? {
        inferredReusableInternetHostValue(
            host,
            hubInstanceID: hubInstanceID,
            lanDiscoveryName: lanDiscoveryName
        )
    }

    nonisolated static func preferredConnectHubForTesting(
        primaryHubHost: String? = nil,
        configuredInternetHost: String? = nil,
        cachedHost: String? = nil,
        cachedInternetHost: String? = nil
    ) -> String {
        preferredConnectHubValue(
            primaryHubHost: primaryHubHost,
            configuredInternetHost: configuredInternetHost,
            cachedHost: cachedHost,
            cachedInternetHost: cachedInternetHost,
            currentMachineHosts: ["127.0.0.1", "localhost"]
        )
    }

    nonisolated static func connectRepairHostsForTesting(
        primaryHubHost: String? = nil,
        configuredInternetHost: String? = nil,
        cachedHost: String? = nil,
        cachedInternetHost: String? = nil
    ) -> [String] {
        connectRepairHostsValue(
            primaryHubHost: primaryHubHost,
            configuredInternetHost: configuredInternetHost,
            cachedHost: cachedHost,
            cachedInternetHost: cachedInternetHost,
            currentMachineHosts: ["127.0.0.1", "localhost"]
        )
    }

    nonisolated static func preferredPresenceHostForTesting(
        route: HubRemoteRoute,
        cachedHost: String? = nil,
        cachedInternetHost: String? = nil
    ) -> String? {
        preferredPresenceHostValue(
            route: route,
            cachedHost: cachedHost,
            cachedInternetHost: cachedInternetHost,
            currentMachineHosts: ["127.0.0.1", "localhost"]
        )
    }

    nonisolated static func shouldAttemptLANRepairDiscoveryForTesting(
        configuredInternetHost: String,
        cachedHost: String? = nil,
        cachedInternetHost: String? = nil,
        cachedPairingPort: Int? = nil,
        cachedGrpcPort: Int? = nil,
        hubInstanceID: String? = nil,
        lanDiscoveryName: String? = nil,
        allowConfiguredHostRepair: Bool,
        configuredEndpointIsAuthoritative: Bool = false
    ) -> Bool {
        let cachedPairing = HubCachedPairingInfo(
            host: cachedHost,
            internetHost: cachedInternetHost,
            pairingPort: cachedPairingPort,
            grpcPort: cachedGrpcPort,
            hubInstanceID: hubInstanceID,
            lanDiscoveryName: lanDiscoveryName
        )
        return shouldRunLANDiscoveryPrepassValue(
            configuredInternetHost: configuredInternetHost,
            cachedPairing: cachedPairing,
            allowConfiguredHostRepair: allowConfiguredHostRepair,
            configuredEndpointIsAuthoritative: configuredEndpointIsAuthoritative
        )
    }

    nonisolated static func shouldRunLANDiscoveryPrepassForTesting(
        configuredInternetHost: String,
        cachedHost: String? = nil,
        cachedInternetHost: String? = nil,
        cachedPairingPort: Int? = nil,
        cachedGrpcPort: Int? = nil,
        hubInstanceID: String? = nil,
        lanDiscoveryName: String? = nil,
        inviteAlias: String = "",
        inviteInstanceID: String = "",
        allowConfiguredHostRepair: Bool,
        configuredEndpointIsAuthoritative: Bool = false
    ) -> Bool {
        let cachedPairing = HubCachedPairingInfo(
            host: cachedHost,
            internetHost: cachedInternetHost,
            pairingPort: cachedPairingPort,
            grpcPort: cachedGrpcPort,
            hubInstanceID: hubInstanceID,
            lanDiscoveryName: lanDiscoveryName
        )
        return shouldRunLANDiscoveryPrepassValue(
            configuredInternetHost: configuredInternetHost,
            cachedPairing: cachedPairing,
            allowConfiguredHostRepair: allowConfiguredHostRepair,
            configuredEndpointIsAuthoritative: configuredEndpointIsAuthoritative,
            inviteAlias: inviteAlias,
            inviteInstanceID: inviteInstanceID
        )
    }

    nonisolated static func shouldAttemptLANSubnetFallbackScanForTesting(
        configuredInternetHost: String,
        cachedHost: String? = nil,
        cachedInternetHost: String? = nil,
        cachedPairingPort: Int? = nil,
        cachedGrpcPort: Int? = nil,
        hubInstanceID: String? = nil,
        lanDiscoveryName: String? = nil,
        inviteAlias: String = "",
        inviteInstanceID: String = "",
        allowConfiguredHostRepair: Bool,
        configuredEndpointIsAuthoritative: Bool = false
    ) -> Bool {
        let cachedPairing = HubCachedPairingInfo(
            host: cachedHost,
            internetHost: cachedInternetHost,
            pairingPort: cachedPairingPort,
            grpcPort: cachedGrpcPort,
            hubInstanceID: hubInstanceID,
            lanDiscoveryName: lanDiscoveryName
        )
        return shouldAttemptLANSubnetFallbackScanValue(
            configuredInternetHost: configuredInternetHost,
            cachedPairing: cachedPairing,
            allowConfiguredHostRepair: allowConfiguredHostRepair,
            configuredEndpointIsAuthoritative: configuredEndpointIsAuthoritative,
            inviteAlias: inviteAlias,
            inviteInstanceID: inviteInstanceID
        )
    }

    nonisolated static func shouldIncludeLANDiscoveryInterfaceForTesting(
        interfaceName: String,
        flags: Int32
    ) -> Bool {
        shouldIncludeLANDiscoveryInterface(
            name: interfaceName,
            flags: flags
        )
    }

    nonisolated static func shouldSkipDiscoveryForAuthoritativeBootstrapForTesting(
        configuredInternetHost: String,
        inviteToken: String,
        configuredEndpointIsAuthoritative: Bool = false,
        hasAuthoritativeLocalProfile: Bool
    ) -> Bool {
        shouldSkipDiscoveryForAuthoritativeBootstrap(
            configuredInternetHost: configuredInternetHost,
            inviteToken: inviteToken,
            configuredEndpointIsAuthoritative: configuredEndpointIsAuthoritative,
            hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile
        )
    }

    nonisolated static func lanDiscoveryFallbackProbeTimeoutSecForTesting() -> Double {
        lanDiscoveryFallbackProbeTimeoutSec
    }

    nonisolated static func pairingDiscoveryProbeTimeoutSecForTesting() -> Double {
        pairingDiscoveryProbeTimeoutSec
    }

    nonisolated static func loopbackOnlyDiscoveryFailureReasonForTesting(
        ignoredLoopbackCandidate: Bool,
        hasAuthoritativeLocalProfile: Bool
    ) -> String? {
        loopbackOnlyDiscoveryFailureReason(
            ignoredLoopbackCandidate: ignoredLoopbackCandidate,
            hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile
        )
    }

    nonisolated static func shouldFailClosedOnDiscoveryReasonForTesting(
        _ rawReason: String?
    ) -> Bool {
        shouldFailClosedOnDiscoveryReason(rawReason)
    }

    nonisolated static func shouldSkipBootstrapRefreshAfterConnectFailureForTesting(
        _ rawReason: String?
    ) -> Bool {
        shouldSkipBootstrapRefreshAfterConnectFailure(rawReason)
    }

    nonisolated static func orderedUniquePairingPortsForTesting(
        _ pairingPorts: [Int]
    ) -> [Int] {
        orderedUniquePairingPorts(pairingPorts)
    }

    nonisolated static func lanDiscoveryPairingPortsForTesting(
        _ pairingPorts: [Int],
        configuredInternetHost: String?,
        cachedHost: String?,
        cachedInternetHost: String?,
        cachedPairingPort: Int?,
        cachedHubInstanceID: String?
    ) -> [Int] {
        lanDiscoveryPairingPorts(
            pairingPorts,
            cachedPairing: HubCachedPairingInfo(
                host: cachedHost,
                internetHost: cachedInternetHost,
                pairingPort: cachedPairingPort,
                grpcPort: nil,
                hubInstanceID: cachedHubInstanceID,
                lanDiscoveryName: nil,
                pairingProfileEpoch: nil,
                routePackVersion: nil
            ),
            configuredInternetHost: configuredInternetHost
        )
    }

    nonisolated static func lanDiscoveryPriorityHostWindowForTesting(
        _ hosts: [String],
        limitPerSubnet: Int
    ) -> [String] {
        lanDiscoveryPriorityHostWindow(
            hosts,
            limitPerSubnet: limitPerSubnet
        )
    }

    nonisolated static func isLocalNetworkAccessDeniedForTesting(
        domain: String,
        code: Int,
        description: String
    ) -> Bool {
        isLocalNetworkAccessDenied(
            NSError(
                domain: domain,
                code: code,
                userInfo: [NSLocalizedDescriptionKey: description]
            )
        )
    }

    nonisolated static func shouldPinDiscoveredHostToConfiguredRemoteForTesting(
        configuredInternetHost: String
    ) -> Bool {
        shouldPinDiscoveredHostToConfiguredRemote(configuredInternetHost)
    }

    nonisolated static func discoveryHintsForTesting(
        configuredInternetHost: String = "",
        cachedHost: String? = nil,
        cachedInternetHost: String? = nil,
        cachedLanDiscoveryName: String? = nil,
        inviteAlias: String = "",
        inviteInstanceID: String = "",
        hasAuthoritativeLocalProfile: Bool = false
    ) -> [String] {
        discoveryHintCandidatesValue(
            configuredInternetHost: configuredInternetHost,
            cachedPairing: HubCachedPairingInfo(
                host: cachedHost,
                internetHost: cachedInternetHost,
                pairingPort: nil,
                grpcPort: nil,
                hubInstanceID: nil,
                lanDiscoveryName: cachedLanDiscoveryName
            ),
            inviteAlias: inviteAlias,
            inviteInstanceID: inviteInstanceID,
            hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile
        )
    }

    nonisolated static func preferredDiscoveryHostsForTesting(
        configuredInternetHost: String = "",
        cachedHost: String? = nil,
        cachedInternetHost: String? = nil,
        cachedLanDiscoveryName: String? = nil,
        inviteAlias: String = "",
        inviteInstanceID: String = "",
        hasAuthoritativeLocalProfile: Bool = false
    ) -> [String] {
        preferredDiscoveryHostsValue(
            configuredInternetHost: configuredInternetHost,
            cachedPairing: HubCachedPairingInfo(
                host: cachedHost,
                internetHost: cachedInternetHost,
                pairingPort: nil,
                grpcPort: nil,
                hubInstanceID: nil,
                lanDiscoveryName: cachedLanDiscoveryName
            ),
            inviteAlias: inviteAlias,
            inviteInstanceID: inviteInstanceID,
            hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile,
            currentMachineHosts: ["127.0.0.1", "localhost"]
        )
    }

    nonisolated static func shouldIgnoreDiscoveredLoopbackCandidateForTesting(
        discoveredHost: String?,
        configuredInternetHost: String = "",
        cachedHost: String? = nil,
        cachedInternetHost: String? = nil,
        hasAuthoritativeLocalProfile: Bool = false
    ) -> Bool {
        shouldIgnoreDiscoveredLoopbackCandidate(
            discoveredHost: discoveredHost,
            configuredInternetHost: configuredInternetHost,
            cachedPairing: HubCachedPairingInfo(
                host: cachedHost,
                internetHost: cachedInternetHost,
                pairingPort: nil,
                grpcPort: nil,
                hubInstanceID: nil,
                lanDiscoveryName: nil
            ),
            hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile,
            currentMachineHosts: ["127.0.0.1", "localhost"]
        )
    }

    nonisolated static func hasAuthoritativeLocalPairingStateForTesting(
        cachedHost: String? = nil,
        cachedInternetHost: String? = nil,
        cachedPairingPort: Int? = nil,
        cachedGRPCPort: Int? = nil,
        cachedHubInstanceID: String? = nil,
        cachedLanDiscoveryName: String? = nil,
        cachedPairingProfileEpoch: Int? = nil,
        cachedRoutePackVersion: String? = nil
    ) -> Bool {
        hasAuthoritativeLocalPairingState(
            cachedPairing: HubCachedPairingInfo(
                host: cachedHost,
                internetHost: cachedInternetHost,
                pairingPort: cachedPairingPort,
                grpcPort: cachedGRPCPort,
                hubInstanceID: cachedHubInstanceID,
                lanDiscoveryName: cachedLanDiscoveryName,
                pairingProfileEpoch: cachedPairingProfileEpoch,
                routePackVersion: cachedRoutePackVersion
            ),
            currentMachineHosts: ["127.0.0.1", "localhost"]
        )
    }

    nonisolated static func expandedLANDiscoveryNetworksForTesting(
        address: String,
        prefixLength: Int
    ) -> [String] {
        guard let addressValue = ipv4UInt32(address),
              let mask = ipv4Mask(prefixLength: prefixLength) else {
            return []
        }
        return expandedLANDiscoveryCIDRs(
            addressValue: addressValue,
            effectiveMask: mask,
            prefixLength: prefixLength
        ).map { "\(ipv4String($0.network))/\($0.prefixLength)" }
    }

    func synchronizeCachedPairingStateForTesting(
        stateDir: URL,
        deviceName: String = "X-Terminal"
    ) {
        _ = synchronizedCachedPairingInfo(
            stateDir: stateDir,
            fallbackDeviceName: deviceName
        )
    }

    func prepareDiscoveryProbeStateForTesting(
        sourceStateDir: URL,
        probeStateDir: URL,
        deviceName: String = "X-Terminal"
    ) {
        _ = prepareDiscoveryProbeState(
            sourceStateDir: sourceStateDir,
            probeStateDir: probeStateDir,
            fallbackDeviceName: deviceName
        )
    }

    func persistLoopbackTunnelRouteStateForTesting(
        stateDir: URL,
        internetHost: String? = nil,
        pairingPort: Int = 50054,
        grpcPort: Int = 50053,
        deviceName: String = "X-Terminal"
    ) throws {
        try persistLoopbackTunnelRouteState(
            host: "127.0.0.1",
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            internetHost: internetHost,
            options: HubRemoteConnectOptions(
                grpcPort: grpcPort,
                pairingPort: pairingPort,
                deviceName: deviceName,
                internetHost: internetHost ?? "",
                inviteAlias: "",
                inviteInstanceID: "",
                axhubctlPath: "",
                stateDir: stateDir
            )
        )
    }

    func persistDirectRemoteRouteStateForTesting(
        stateDir: URL,
        host: String,
        internetHost: String? = nil,
        pairingPort: Int = 50054,
        grpcPort: Int = 50053,
        deviceName: String = "X-Terminal"
    ) throws {
        try persistDirectRemoteRouteState(
            host: host,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            internetHost: internetHost,
            options: HubRemoteConnectOptions(
                grpcPort: grpcPort,
                pairingPort: pairingPort,
                deviceName: deviceName,
                internetHost: internetHost ?? "",
                inviteAlias: "",
                inviteInstanceID: "",
                axhubctlPath: "",
                stateDir: stateDir
            )
        )
    }

    func synchronizeAuthoritativeRemoteEndpointArtifactsForTesting(
        stateDir: URL,
        host: String,
        pairingPort: Int = 50054,
        grpcPort: Int = 50053,
        deviceName: String = "X-Terminal",
        configuredEndpointIsAuthoritative: Bool = true
    ) -> [String] {
        synchronizeAuthoritativeRemoteEndpointArtifacts(
            options: HubRemoteConnectOptions(
                grpcPort: grpcPort,
                pairingPort: pairingPort,
                deviceName: deviceName,
                internetHost: host,
                inviteAlias: "",
                inviteInstanceID: "",
                axhubctlPath: "",
                configuredEndpointIsAuthoritative: configuredEndpointIsAuthoritative,
                stateDir: stateDir
            )
        )
    }

}
