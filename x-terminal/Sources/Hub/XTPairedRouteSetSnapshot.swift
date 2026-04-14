import Foundation

enum XTPairedRouteReadiness: String, Codable, Equatable, Sendable {
    case unknown
    case localReady = "local_ready"
    case remoteReady = "remote_ready"
    case remoteDegraded = "remote_degraded"
    case remoteBlocked = "remote_blocked"
}

enum XTPairedRouteTargetKind: String, Codable, Equatable, Sendable {
    case localFileIPC = "local_fileipc"
    case lan
    case internet
    case internetTunnel = "internet_tunnel"
}

enum XTPairedRouteTargetSource: String, Codable, Equatable, Sendable {
    case activeConnection = "active_connection"
    case cachedProfileHost = "cached_profile_host"
    case cachedProfileInternetHost = "cached_profile_internet_host"
    case configuredInternetHost = "configured_internet_host"
    case freshPairReconnectSmoke = "fresh_pair_reconnect_smoke"
    case localRuntime = "local_runtime"
}

struct XTPairedRouteTargetSnapshot: Codable, Equatable, Sendable {
    var routeKind: XTPairedRouteTargetKind
    var host: String
    var pairingPort: Int
    var grpcPort: Int
    var hostKind: String
    var source: XTPairedRouteTargetSource
}

struct XTPairedRouteSetSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.paired_route_set.v1"

    var schemaVersion: String = currentSchemaVersion
    var readiness: XTPairedRouteReadiness
    var readinessReasonCode: String
    var summaryLine: String
    var hubInstanceID: String?
    var pairingProfileEpoch: Int? = nil
    var routePackVersion: String? = nil
    var activeRoute: XTPairedRouteTargetSnapshot?
    var lanRoute: XTPairedRouteTargetSnapshot?
    var stableRemoteRoute: XTPairedRouteTargetSnapshot?
    var lastKnownGoodRoute: XTPairedRouteTargetSnapshot?
    var cachedReconnectSmokeStatus: String?
    var cachedReconnectSmokeReasonCode: String?
    var cachedReconnectSmokeSummary: String?
}

struct XTPairedRouteSetBuildInput: Sendable {
    var cachedProfile: HubAIClient.CachedRemoteProfile
    var configuredInternetHost: String
    var configuredHubInstanceID: String?
    var pairingPort: Int
    var grpcPort: Int
    var localConnected: Bool
    var remoteConnected: Bool
    var remoteRoute: HubRemoteRoute
    var linking: Bool
    var failureCode: String
    var freshPairReconnectSmokeSnapshot: XTFreshPairReconnectSmokeSnapshot?
    var remoteShadowReconnectSmokeSnapshot: XTRemoteShadowReconnectSmokeSnapshot?
}

enum XTPairedRouteSetSnapshotBuilder {
    static func build(input: XTPairedRouteSetBuildInput) -> XTPairedRouteSetSnapshot {
        let lanRoute = resolveLanRoute(input: input)
        let stableRemoteRoute = resolveStableRemoteRoute(input: input)
        let activeRoute = resolveActiveRoute(
            input: input,
            lanRoute: lanRoute,
            stableRemoteRoute: stableRemoteRoute
        )
        let lastKnownGoodRoute = resolveLastKnownGoodRoute(
            input: input,
            activeRoute: activeRoute,
            lanRoute: lanRoute,
            stableRemoteRoute: stableRemoteRoute
        )
        let readinessContext = resolveReadiness(
            input: input,
            lanRoute: lanRoute,
            stableRemoteRoute: stableRemoteRoute
        )
        let smokeStatus = input.freshPairReconnectSmokeSnapshot?.status.rawValue
        let smokeReasonCode = normalizedNonEmpty(input.freshPairReconnectSmokeSnapshot?.reasonCode)
        let smokeSummary = normalizedNonEmpty(input.freshPairReconnectSmokeSnapshot?.summary)
        let hubInstanceID = normalizedNonEmpty(input.cachedProfile.hubInstanceID)
            ?? normalizedNonEmpty(input.configuredHubInstanceID)

        return XTPairedRouteSetSnapshot(
            readiness: readinessContext.readiness,
            readinessReasonCode: readinessContext.reasonCode,
            summaryLine: readinessSummaryLine(
                readiness: readinessContext.readiness,
                hasStableRemoteRoute: stableRemoteRoute != nil
            ),
            hubInstanceID: hubInstanceID,
            pairingProfileEpoch: input.cachedProfile.pairingProfileEpoch,
            routePackVersion: normalizedNonEmpty(input.cachedProfile.routePackVersion),
            activeRoute: activeRoute,
            lanRoute: lanRoute,
            stableRemoteRoute: stableRemoteRoute,
            lastKnownGoodRoute: lastKnownGoodRoute,
            cachedReconnectSmokeStatus: smokeStatus,
            cachedReconnectSmokeReasonCode: smokeReasonCode,
            cachedReconnectSmokeSummary: smokeSummary
        )
    }

    private struct ReadinessContext {
        var readiness: XTPairedRouteReadiness
        var reasonCode: String
    }

    private static func resolveReadiness(
        input: XTPairedRouteSetBuildInput,
        lanRoute: XTPairedRouteTargetSnapshot?,
        stableRemoteRoute: XTPairedRouteTargetSnapshot?
    ) -> ReadinessContext {
        let normalizedFailureCode = UITroubleshootKnowledgeBase.normalizedFailureCode(input.failureCode)
        let smokeSnapshot = input.freshPairReconnectSmokeSnapshot
        let remoteShadowSnapshot = input.remoteShadowReconnectSmokeSnapshot
        let remoteShadowFailureCode = UITroubleshootKnowledgeBase.normalizedFailureCode(
            input.remoteShadowReconnectSmokeSnapshot?.reasonCode ?? ""
        )
        let hasStableRemoteRoute = stableRemoteRoute != nil
        let localReadyObserved = input.localConnected
            || lanRoute != nil
            || (smokeSnapshot?.status == .succeeded && smokeSnapshot?.route == .lan)
        let remoteReadyObserved = hasStableRemoteRoute && (
            (input.remoteConnected && (input.remoteRoute == .internet || input.remoteRoute == .internetTunnel))
                || remoteShadowSnapshot?.status == .succeeded
                || (smokeSnapshot?.status == .succeeded
                    && (smokeSnapshot?.route == .internet || smokeSnapshot?.route == .internetTunnel))
        )
        let remoteBoundaryBlocked = hasStableRemoteRoute && (
            isRemoteBoundaryBlocked(normalizedFailureCode)
                || (remoteShadowSnapshot?.status == .failed && isRemoteBoundaryBlocked(remoteShadowFailureCode))
        )
        let remoteFailureObserved = hasStableRemoteRoute && !remoteBoundaryBlocked && (
            remoteShadowSnapshot?.status == .failed
                || smokeSnapshot?.status == .failed
                || (!normalizedFailureCode.isEmpty && !input.linking)
        )

        if remoteReadyObserved {
            if input.remoteConnected && input.remoteRoute == .internetTunnel {
                return ReadinessContext(readiness: .remoteReady, reasonCode: "remote_tunnel_route_verified")
            }
            if remoteShadowSnapshot?.status == .succeeded {
                return ReadinessContext(readiness: .remoteReady, reasonCode: "remote_shadow_smoke_verified")
            }
            if smokeSnapshot?.status == .succeeded {
                return ReadinessContext(readiness: .remoteReady, reasonCode: "cached_remote_reconnect_smoke_verified")
            }
            return ReadinessContext(readiness: .remoteReady, reasonCode: "active_remote_route_verified")
        }

        if remoteBoundaryBlocked {
            return ReadinessContext(readiness: .remoteBlocked, reasonCode: "remote_pairing_or_identity_blocked")
        }

        if remoteFailureObserved {
            if remoteShadowSnapshot?.status == .failed {
                return ReadinessContext(readiness: .remoteDegraded, reasonCode: "remote_shadow_smoke_failed")
            }
            if smokeSnapshot?.status == .failed {
                return ReadinessContext(readiness: .remoteDegraded, reasonCode: "cached_remote_reconnect_smoke_failed")
            }
            return ReadinessContext(readiness: .remoteDegraded, reasonCode: "remote_route_validation_failed")
        }

        if localReadyObserved {
            return ReadinessContext(
                readiness: .localReady,
                reasonCode: hasStableRemoteRoute ? "local_pairing_ready_remote_unverified" : "local_pairing_ready"
            )
        }

        return ReadinessContext(readiness: .unknown, reasonCode: "no_paired_route_evidence")
    }

    private static func resolveLanRoute(input: XTPairedRouteSetBuildInput) -> XTPairedRouteTargetSnapshot? {
        if let host = normalizedNonEmpty(input.cachedProfile.host),
           HubRemoteHostPolicy.isDirectLocalFallbackHost(host) {
            return makeTarget(
                routeKind: .lan,
                host: host,
                pairingPort: input.pairingPort,
                grpcPort: input.grpcPort,
                source: .cachedProfileHost
            )
        }

        if let host = normalizedNonEmpty(input.configuredInternetHost),
           HubRemoteHostPolicy.isDirectLocalFallbackHost(host) {
            return makeTarget(
                routeKind: .lan,
                host: host,
                pairingPort: input.pairingPort,
                grpcPort: input.grpcPort,
                source: .configuredInternetHost
            )
        }

        return nil
    }

    private static func resolveStableRemoteRoute(input: XTPairedRouteSetBuildInput) -> XTPairedRouteTargetSnapshot? {
        if let host = normalizedNonEmpty(input.cachedProfile.internetHost),
           HubRemoteHostPolicy.isStableNamedRemoteHost(host) {
            return makeTarget(
                routeKind: .internet,
                host: host,
                pairingPort: input.pairingPort,
                grpcPort: input.grpcPort,
                source: .cachedProfileInternetHost
            )
        }

        if let host = normalizedNonEmpty(input.configuredInternetHost),
           HubRemoteHostPolicy.isStableNamedRemoteHost(host) {
            return makeTarget(
                routeKind: .internet,
                host: host,
                pairingPort: input.pairingPort,
                grpcPort: input.grpcPort,
                source: .configuredInternetHost
            )
        }

        return nil
    }

    private static func resolveActiveRoute(
        input: XTPairedRouteSetBuildInput,
        lanRoute: XTPairedRouteTargetSnapshot?,
        stableRemoteRoute: XTPairedRouteTargetSnapshot?
    ) -> XTPairedRouteTargetSnapshot? {
        if input.localConnected {
            return makeTarget(
                routeKind: .localFileIPC,
                host: "localhost",
                pairingPort: input.pairingPort,
                grpcPort: input.grpcPort,
                source: .localRuntime
            )
        }

        guard input.remoteConnected else { return nil }

        switch input.remoteRoute {
        case .lan:
            return lanRoute ?? makeTarget(
                routeKind: .lan,
                host: normalizedNonEmpty(input.cachedProfile.host) ?? "localhost",
                pairingPort: input.pairingPort,
                grpcPort: input.grpcPort,
                source: .activeConnection
            )
        case .internet:
            let host = stableRemoteRoute?.host
                ?? normalizedNonEmpty(input.configuredInternetHost)
                ?? normalizedNonEmpty(input.cachedProfile.internetHost)
                ?? normalizedNonEmpty(input.cachedProfile.host)
                ?? ""
            guard !host.isEmpty else { return nil }
            return makeTarget(
                routeKind: .internet,
                host: host,
                pairingPort: input.pairingPort,
                grpcPort: input.grpcPort,
                source: .activeConnection
            )
        case .internetTunnel:
            let host = stableRemoteRoute?.host
                ?? normalizedNonEmpty(input.configuredInternetHost)
                ?? normalizedNonEmpty(input.cachedProfile.internetHost)
                ?? normalizedNonEmpty(input.cachedProfile.host)
                ?? ""
            guard !host.isEmpty else { return nil }
            return makeTarget(
                routeKind: .internetTunnel,
                host: host,
                pairingPort: input.pairingPort,
                grpcPort: input.grpcPort,
                source: .activeConnection
            )
        case .none:
            return nil
        }
    }

    private static func resolveLastKnownGoodRoute(
        input: XTPairedRouteSetBuildInput,
        activeRoute: XTPairedRouteTargetSnapshot?,
        lanRoute: XTPairedRouteTargetSnapshot?,
        stableRemoteRoute: XTPairedRouteTargetSnapshot?
    ) -> XTPairedRouteTargetSnapshot? {
        if let activeRoute {
            return activeRoute
        }

        guard let smokeSnapshot = input.freshPairReconnectSmokeSnapshot,
              smokeSnapshot.status == .succeeded else {
            return nil
        }

        switch smokeSnapshot.route {
        case .lan:
            return lanRoute ?? makeTarget(
                routeKind: .lan,
                host: normalizedNonEmpty(input.cachedProfile.host) ?? "localhost",
                pairingPort: input.pairingPort,
                grpcPort: input.grpcPort,
                source: .freshPairReconnectSmoke
            )
        case .internet:
            let host = stableRemoteRoute?.host
                ?? normalizedNonEmpty(input.configuredInternetHost)
                ?? normalizedNonEmpty(input.cachedProfile.internetHost)
                ?? ""
            guard !host.isEmpty else { return nil }
            return makeTarget(
                routeKind: .internet,
                host: host,
                pairingPort: input.pairingPort,
                grpcPort: input.grpcPort,
                source: .freshPairReconnectSmoke
            )
        case .internetTunnel:
            let host = stableRemoteRoute?.host
                ?? normalizedNonEmpty(input.configuredInternetHost)
                ?? normalizedNonEmpty(input.cachedProfile.internetHost)
                ?? ""
            guard !host.isEmpty else { return nil }
            return makeTarget(
                routeKind: .internetTunnel,
                host: host,
                pairingPort: input.pairingPort,
                grpcPort: input.grpcPort,
                source: .freshPairReconnectSmoke
            )
        case .none:
            return nil
        }
    }

    private static func makeTarget(
        routeKind: XTPairedRouteTargetKind,
        host: String,
        pairingPort: Int,
        grpcPort: Int,
        source: XTPairedRouteTargetSource
    ) -> XTPairedRouteTargetSnapshot {
        let classification = XTHubRemoteAccessHostClassification.classify(host)
        return XTPairedRouteTargetSnapshot(
            routeKind: routeKind,
            host: host,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            hostKind: classification.kindCode,
            source: source
        )
    }

    private static func readinessSummaryLine(
        readiness: XTPairedRouteReadiness,
        hasStableRemoteRoute: Bool
    ) -> String {
        switch readiness {
        case .unknown:
            return "尚未拿到可判定的已配对路径集合。"
        case .localReady:
            if hasStableRemoteRoute {
                return "当前已完成同网首配，但正式异网入口仍未完成验证。"
            }
            return "当前已完成同网首配，但还没有正式异网入口。"
        case .remoteReady:
            return "正式异网入口已验证，切网后可继续重连。"
        case .remoteDegraded:
            return "正式异网入口已存在，但最近一次异网验证未通过。"
        case .remoteBlocked:
            return "正式异网入口已存在，但当前被配对/身份边界阻断。"
        }
    }

    private static func isRemoteBoundaryBlocked(_ normalizedFailureCode: String) -> Bool {
        guard !normalizedFailureCode.isEmpty else { return false }
        return remoteBoundaryBlockTokens.contains { normalizedFailureCode.contains($0) }
    }

    private static let remoteBoundaryBlockTokens = [
        "invite_token_required",
        "invite_token_invalid",
        "pairing_token_invalid",
        "bootstrap_token_invalid",
        "pairing_token_expired",
        "bootstrap_token_expired",
        "unauthenticated",
        "mtls_client_certificate_required",
        "certificate_required",
        "pairing_approval_timeout",
        "pairing_owner_auth_cancelled",
        "pairing_owner_auth_failed",
        "first_pair_requires_same_lan",
        "hub_instance_mismatch",
        "pairing_profile_epoch_stale",
        "route_pack_outdated",
    ]

    private static func normalizedNonEmpty(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
