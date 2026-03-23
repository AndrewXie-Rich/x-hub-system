import Foundation

enum SupervisorDurableCandidateMirrorStatus: String, Codable, Equatable, Sendable {
    case notNeeded = "not_needed"
    case pending = "pending"
    case mirroredToHub = "mirrored_to_hub"
    case localOnly = "local_only"
    case hubMirrorFailed = "hub_mirror_failed"
}

struct SupervisorDurableCandidateMirrorResult: Equatable, Sendable {
    var status: SupervisorDurableCandidateMirrorStatus
    var target: String
    var attempted: Bool
    var errorCode: String?
}

enum XTSupervisorDurableCandidateMirror {
    private static let allowedSessionParticipationClasses: Set<String> = [
        "ignore",
        "read_only",
        "scoped_write"
    ]

    private struct CandidateEnvelope: Encodable, Sendable {
        var scope: String
        var recordType: String
        var confidence: Double
        var whyPromoted: String
        var sourceRef: String
        var auditRef: String
        var sessionParticipationClass: String
        var writePermissionScope: String
        var idempotencyKey: String
        var payloadSummary: String

        enum CodingKeys: String, CodingKey {
            case scope
            case recordType = "record_type"
            case confidence
            case whyPromoted = "why_promoted"
            case sourceRef = "source_ref"
            case auditRef = "audit_ref"
            case sessionParticipationClass = "session_participation_class"
            case writePermissionScope = "write_permission_scope"
            case idempotencyKey = "idempotency_key"
            case payloadSummary = "payload_summary"
        }
    }

    private struct PayloadEnvelope: Encodable, Sendable {
        var schemaVersion: String
        var carrierKind: String
        var mirrorTarget: String
        var localStoreRole: String
        var emittedAtMs: Int64
        var summaryLine: String
        var scopes: [String]
        var candidateCount: Int
        var candidates: [CandidateEnvelope]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case carrierKind = "carrier_kind"
            case mirrorTarget = "mirror_target"
            case localStoreRole = "local_store_role"
            case emittedAtMs = "emitted_at_ms"
            case summaryLine = "summary_line"
            case scopes
            case candidateCount = "candidate_count"
            case candidates
        }
    }

    typealias TransportOverride = @Sendable (HubRemoteSupervisorConversationPayload) async -> HubRemoteMutationResult

    static let threadKey = "xterminal_supervisor_durable_candidate_device"
    static let mirrorTarget = "hub_candidate_carrier_shadow_thread"
    static let localStoreRole = "cache|fallback|edit_buffer"

    private static let transportOverrideLock = NSLock()
    private static var transportOverrideForTesting: TransportOverride?

    static func installTransportOverrideForTesting(_ override: TransportOverride?) {
        transportOverrideLock.lock()
        transportOverrideForTesting = override
        transportOverrideLock.unlock()
    }

    static func resetTransportOverrideForTesting() {
        installTransportOverrideForTesting(nil)
    }

    static func mirror(
        classification: SupervisorAfterTurnWritebackClassification,
        createdAt: Double
    ) async -> SupervisorDurableCandidateMirrorResult {
        let candidates = classification.durableCandidates
        guard !candidates.isEmpty else {
            return SupervisorDurableCandidateMirrorResult(
                status: .notNeeded,
                target: mirrorTarget,
                attempted: false,
                errorCode: nil
            )
        }
        if let failClosedResult = localPreflightFailureResult(for: candidates) {
            return failClosedResult
        }
        guard let payload = payload(
            classification: classification,
            candidates: candidates,
            createdAt: createdAt
        ) else {
            return SupervisorDurableCandidateMirrorResult(
                status: .hubMirrorFailed,
                target: mirrorTarget,
                attempted: true,
                errorCode: "candidate_payload_empty"
            )
        }

        if let override = transportOverride() {
            let remote = await override(payload)
            return mirrorResult(from: remote)
        }

        let routeDecision = await currentRouteDecision()
        guard routeDecision.preferRemote else {
            return SupervisorDurableCandidateMirrorResult(
                status: .localOnly,
                target: mirrorTarget,
                attempted: true,
                errorCode: routeDecision.remoteUnavailableReasonCode ?? "remote_route_not_preferred"
            )
        }

        let remote = await HubPairingCoordinator.shared.appendRemoteSupervisorConversationTurn(
            options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
            payload: payload
        )
        return mirrorResult(from: remote)
    }

    static func payload(
        classification: SupervisorAfterTurnWritebackClassification,
        candidates: [SupervisorAfterTurnWritebackCandidate]? = nil,
        createdAt: Double
    ) -> HubRemoteSupervisorConversationPayload? {
        let selectedCandidates = candidates ?? classification.durableCandidates
        guard !selectedCandidates.isEmpty else { return nil }

        let orderedKeys = selectedCandidates
            .map(\.idempotencyKey)
            .sorted()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let emittedAtMs = Int64((createdAt * 1000.0).rounded())
        let scopes = orderedUniqueScalars(selectedCandidates.map(\.scope.rawValue))
        let envelope = PayloadEnvelope(
            schemaVersion: "xt.supervisor.durable_candidate_mirror.v1",
            carrierKind: "supervisor_after_turn_durable_candidate_shadow_write",
            mirrorTarget: mirrorTarget,
            localStoreRole: localStoreRole,
            emittedAtMs: emittedAtMs,
            summaryLine: classification.summaryLine,
            scopes: scopes,
            candidateCount: selectedCandidates.count,
            candidates: selectedCandidates.map { candidate in
                CandidateEnvelope(
                    scope: candidate.scope.rawValue,
                    recordType: candidate.recordType,
                    confidence: candidate.confidence,
                    whyPromoted: candidate.whyPromoted,
                    sourceRef: candidate.sourceRef,
                    auditRef: candidate.auditRef,
                    sessionParticipationClass: candidate.sessionParticipationClass,
                    writePermissionScope: candidate.writePermissionScope,
                    idempotencyKey: candidate.idempotencyKey,
                    payloadSummary: candidate.payloadSummary
                )
            }
        )
        guard let encoded = try? encoder.encode(envelope),
              let assistantText = String(data: encoded, encoding: .utf8) else {
            return nil
        }

        let requestSeed = [
            "xterminal_supervisor_durable_candidate",
            threadKey,
            orderedKeys.joined(separator: "|")
        ].joined(separator: "|")
        let requestID = "xterminal_supervisor_durable_candidate_\(stableDigest(requestSeed))"
        let userText = "shadow_write durable_candidates scopes=\(scopes.joined(separator: ",")) count=\(selectedCandidates.count)"
        return HubRemoteSupervisorConversationPayload(
            threadKey: threadKey,
            requestId: requestID,
            createdAtMs: emittedAtMs,
            userText: userText,
            assistantText: assistantText
        )
    }

    private static func transportOverride() -> TransportOverride? {
        transportOverrideLock.lock()
        defer { transportOverrideLock.unlock() }
        return transportOverrideForTesting
    }

    private static func currentRouteDecision() async -> HubRouteDecision {
        let mode = HubAIClient.transportMode()
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        return HubRouteStateMachine.resolve(mode: mode, hasRemoteProfile: hasRemote)
    }

    private static func mirrorResult(
        from remote: HubRemoteMutationResult
    ) -> SupervisorDurableCandidateMirrorResult {
        SupervisorDurableCandidateMirrorResult(
            status: remote.ok ? .mirroredToHub : .hubMirrorFailed,
            target: mirrorTarget,
            attempted: true,
            errorCode: remote.ok ? nil : (remote.reasonCode ?? "hub_append_failed")
        )
    }

    private static func localPreflightFailureResult(
        for candidates: [SupervisorAfterTurnWritebackCandidate]
    ) -> SupervisorDurableCandidateMirrorResult? {
        for candidate in candidates {
            let sessionParticipationClass = normalizedScalar(candidate.sessionParticipationClass).lowercased()
            if !allowedSessionParticipationClasses.contains(sessionParticipationClass) {
                return localFailClosedResult(errorCode: "supervisor_candidate_session_participation_invalid")
            }
            if sessionParticipationClass != "scoped_write" {
                return localFailClosedResult(errorCode: "supervisor_candidate_session_participation_denied")
            }

            let writePermissionScope = normalizedScalar(candidate.writePermissionScope)
            if writePermissionScope != candidate.scope.rawValue {
                return localFailClosedResult(errorCode: "supervisor_candidate_scope_mismatch")
            }
        }
        return nil
    }

    private static func localFailClosedResult(
        errorCode: String
    ) -> SupervisorDurableCandidateMirrorResult {
        SupervisorDurableCandidateMirrorResult(
            status: .localOnly,
            target: mirrorTarget,
            attempted: true,
            errorCode: errorCode
        )
    }

    private static func stableDigest(_ value: String) -> String {
        var hash = UInt64(14_695_981_039_346_656_037)
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func orderedUniqueScalars(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in raw {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered
    }

    private static func normalizedScalar(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
