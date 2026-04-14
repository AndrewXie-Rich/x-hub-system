import Foundation

enum XTFirstPairRemoteShadowSmokeStatus: String, Codable, Equatable, Sendable {
    case notRun = "not_run"
    case running
    case passed
    case failed
}

struct XTFirstPairCompletionProofSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.first_pair_completion_proof.v1"

    var schemaVersion: String = currentSchemaVersion
    var generatedAtMs: Int64
    var readiness: XTPairedRouteReadiness
    var sameLanVerified: Bool
    var ownerLocalApprovalVerified: Bool
    var pairingMaterialIssued: Bool
    var cachedReconnectSmokePassed: Bool
    var stableRemoteRoutePresent: Bool
    var remoteShadowSmokePassed: Bool
    var remoteShadowSmokeStatus: XTFirstPairRemoteShadowSmokeStatus
    var remoteShadowSmokeSource: XTRemoteShadowReconnectSmokeSource? = nil
    var remoteShadowTriggeredAtMs: Int64? = nil
    var remoteShadowCompletedAtMs: Int64? = nil
    var remoteShadowRoute: HubRemoteRoute? = nil
    var remoteShadowReasonCode: String? = nil
    var remoteShadowSummary: String? = nil
    var summaryLine: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case readiness
        case sameLanVerified = "same_lan_verified"
        case ownerLocalApprovalVerified = "owner_local_approval_verified"
        case pairingMaterialIssued = "pairing_material_issued"
        case cachedReconnectSmokePassed = "cached_reconnect_smoke_passed"
        case stableRemoteRoutePresent = "stable_remote_route_present"
        case remoteShadowSmokePassed = "remote_shadow_smoke_passed"
        case remoteShadowSmokeStatus = "remote_shadow_smoke_status"
        case remoteShadowSmokeSource = "remote_shadow_smoke_source"
        case remoteShadowTriggeredAtMs = "remote_shadow_triggered_at_ms"
        case remoteShadowCompletedAtMs = "remote_shadow_completed_at_ms"
        case remoteShadowRoute = "remote_shadow_route"
        case remoteShadowReasonCode = "remote_shadow_reason_code"
        case remoteShadowSummary = "remote_shadow_summary"
        case summaryLine = "summary_line"
    }
}

struct XTFirstPairCompletionProofBuildInput: Sendable {
    var generatedAt: Date
    var localConnected: Bool
    var remoteConnected: Bool
    var remoteRoute: HubRemoteRoute
    var cachedProfile: HubAIClient.CachedRemoteProfile
    var freshPairReconnectSmokeSnapshot: XTFreshPairReconnectSmokeSnapshot?
    var remoteShadowReconnectSmokeSnapshot: XTRemoteShadowReconnectSmokeSnapshot?
    var pairedRouteSetSnapshot: XTPairedRouteSetSnapshot
}

enum XTFirstPairCompletionProofBuilder {
    static func build(input: XTFirstPairCompletionProofBuildInput) -> XTFirstPairCompletionProofSnapshot {
        let readiness = input.pairedRouteSetSnapshot.readiness
        let sameLanVerified = input.pairedRouteSetSnapshot.lanRoute != nil
            || input.localConnected
            || input.pairedRouteSetSnapshot.lastKnownGoodRoute?.routeKind == .lan
        let pairingMaterialIssued = hasIssuedPairingMaterial(
            cachedProfile: input.cachedProfile,
            pairedRouteSetSnapshot: input.pairedRouteSetSnapshot
        )
        let ownerLocalApprovalVerified = sameLanVerified && pairingMaterialIssued
        let cachedReconnectSmokePassed = input.freshPairReconnectSmokeSnapshot?.status == .succeeded
        let stableRemoteRoutePresent = input.pairedRouteSetSnapshot.stableRemoteRoute != nil
        let remoteShadowEvidence = resolveRemoteShadowEvidence(input: input)
        let remoteShadowSmokePassed = remoteShadowEvidence.status == .passed

        return XTFirstPairCompletionProofSnapshot(
            generatedAtMs: Int64(input.generatedAt.timeIntervalSince1970 * 1000),
            readiness: readiness,
            sameLanVerified: sameLanVerified,
            ownerLocalApprovalVerified: ownerLocalApprovalVerified,
            pairingMaterialIssued: pairingMaterialIssued,
            cachedReconnectSmokePassed: cachedReconnectSmokePassed,
            stableRemoteRoutePresent: stableRemoteRoutePresent,
            remoteShadowSmokePassed: remoteShadowSmokePassed,
            remoteShadowSmokeStatus: remoteShadowEvidence.status,
            remoteShadowSmokeSource: remoteShadowEvidence.source,
            remoteShadowTriggeredAtMs: remoteShadowEvidence.triggeredAtMs,
            remoteShadowCompletedAtMs: remoteShadowEvidence.completedAtMs,
            remoteShadowRoute: remoteShadowEvidence.route,
            remoteShadowReasonCode: remoteShadowEvidence.reasonCode,
            remoteShadowSummary: remoteShadowEvidence.summary,
            summaryLine: summaryLine(
                readiness: readiness,
                sameLanVerified: sameLanVerified,
                stableRemoteRoutePresent: stableRemoteRoutePresent,
                cachedReconnectSmokePassed: cachedReconnectSmokePassed,
                remoteShadowSmokeStatus: remoteShadowEvidence.status
            )
        )
    }

    private struct RemoteShadowEvidence {
        var status: XTFirstPairRemoteShadowSmokeStatus
        var source: XTRemoteShadowReconnectSmokeSource? = nil
        var triggeredAtMs: Int64? = nil
        var completedAtMs: Int64? = nil
        var route: HubRemoteRoute? = nil
        var reasonCode: String? = nil
        var summary: String? = nil
    }

    private static func hasIssuedPairingMaterial(
        cachedProfile: HubAIClient.CachedRemoteProfile,
        pairedRouteSetSnapshot: XTPairedRouteSetSnapshot
    ) -> Bool {
        let hasPorts = (cachedProfile.pairingPort ?? 0) > 0 && (cachedProfile.grpcPort ?? 0) > 0
        let hasHostHint = [
            cachedProfile.host,
            cachedProfile.internetHost,
            cachedProfile.hubInstanceID,
            pairedRouteSetSnapshot.hubInstanceID
        ].contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return hasPorts && hasHostHint
    }

    private static func resolveRemoteShadowEvidence(
        input: XTFirstPairCompletionProofBuildInput
    ) -> RemoteShadowEvidence {
        let stableRemoteRoutePresent = input.pairedRouteSetSnapshot.stableRemoteRoute != nil
        guard stableRemoteRoutePresent else {
            return RemoteShadowEvidence(status: .notRun)
        }

        if let snapshot = input.remoteShadowReconnectSmokeSnapshot {
            return RemoteShadowEvidence(
                status: remoteShadowSmokeStatus(snapshot.status),
                source: snapshot.source,
                triggeredAtMs: snapshot.triggeredAtMs,
                completedAtMs: snapshot.completedAtMs > 0 ? snapshot.completedAtMs : nil,
                route: snapshot.route == .none ? nil : snapshot.route,
                reasonCode: snapshot.reasonCode,
                summary: normalizedNonEmpty(snapshot.summary)
            )
        }

        if input.remoteConnected,
           input.remoteRoute == .internet || input.remoteRoute == .internetTunnel {
            return RemoteShadowEvidence(
                status: .passed,
                source: .liveRemoteRoute,
                route: input.remoteRoute,
                summary: "stable remote route is already active."
            )
        }

        switch input.pairedRouteSetSnapshot.readiness {
        case .remoteBlocked, .remoteDegraded:
            return RemoteShadowEvidence(status: .failed)
        case .unknown, .localReady, .remoteReady:
            return RemoteShadowEvidence(status: .notRun)
        }
    }

    private static func remoteShadowSmokeStatus(
        _ status: XTRemoteShadowReconnectSmokeStatus
    ) -> XTFirstPairRemoteShadowSmokeStatus {
        switch status {
        case .running:
            return .running
        case .succeeded:
            return .passed
        case .failed:
            return .failed
        }
    }

    private static func summaryLine(
        readiness: XTPairedRouteReadiness,
        sameLanVerified: Bool,
        stableRemoteRoutePresent: Bool,
        cachedReconnectSmokePassed: Bool,
        remoteShadowSmokeStatus: XTFirstPairRemoteShadowSmokeStatus
    ) -> String {
        switch readiness {
        case .remoteReady:
            if remoteShadowSmokeStatus == .passed {
                return "first pair complete; cached reconnect and stable remote route are verified."
            }
            if remoteShadowSmokeStatus == .running {
                return "first pair cached reconnect passed; stable remote route verification is still running."
            }
            if cachedReconnectSmokePassed {
                return "first pair complete; cached reconnect is verified, and stable remote route evidence is present."
            }
            return "stable remote route is active, but first-pair proof is still missing cached reconnect evidence."
        case .remoteDegraded:
            return "first pair reached local readiness, but stable remote route verification is degraded."
        case .remoteBlocked:
            return "first pair reached local readiness, but stable remote route is blocked by pairing or identity repair."
        case .localReady:
            if remoteShadowSmokeStatus == .running {
                return "first pair is local ready; stable remote route verification is still running."
            }
            if remoteShadowSmokeStatus == .failed {
                return "first pair is local ready, but the latest stable remote route verification failed."
            }
            if stableRemoteRoutePresent {
                return "first pair is local ready; stable remote route is present but not fully verified yet."
            }
            if sameLanVerified {
                return "first pair is local ready; same-LAN verification passed, but no stable remote route is present yet."
            }
            return "pairing material exists, but first-pair proof still lacks same-LAN verification."
        case .unknown:
            return "first-pair completion proof is still incomplete."
        }
    }

    private static func normalizedNonEmpty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
