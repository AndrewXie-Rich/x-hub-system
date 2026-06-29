import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension HubPairingCoordinator {
    func discoverHubOnLAN(
        options: HubRemoteConnectOptions,
        pairingPorts: [Int],
        cachedPairing: HubCachedPairingInfo,
        allowConfiguredHostRepair: Bool
    ) async -> HubLANDiscoveryAttempt {
        if !shouldAttemptLANDiscovery(
            options: options,
            cachedPairing: cachedPairing,
            allowConfiguredHostRepair: allowConfiguredHostRepair
        ) {
            return HubLANDiscoveryAttempt(candidate: nil, reasonCode: nil, candidates: [], logLines: [])
        }

        let bonjourResult = await discoverHubViaBonjour(
            options: options,
            cachedPairing: cachedPairing
        )
        if bonjourResult.candidate != nil || bonjourResult.reasonCode != nil {
            return bonjourResult
        }

        if !shouldAttemptLANSubnetFallbackScan(
            options: options,
            cachedPairing: cachedPairing,
            allowConfiguredHostRepair: allowConfiguredHostRepair
        ) {
            return HubLANDiscoveryAttempt(
                candidate: nil,
                reasonCode: nil,
                candidates: [],
                logLines: [
                    "[lan-discover] skip fallback subnet scan: configured remote host or invite identity is authoritative."
                ]
            )
        }

        let plan = Self.buildLANDiscoveryScanPlan()
        guard !plan.hosts.isEmpty else {
            return HubLANDiscoveryAttempt(
                candidate: nil,
                reasonCode: nil,
                candidates: [],
                logLines: ["[lan-discover] no active IPv4 subnets available for fallback scan."]
            )
        }

        let prioritizedHosts = prioritizeLANHosts(plan.hosts, preferredHosts: [
            cachedPairing.host,
            options.internetHost
        ])

        let portCandidates = Self.lanDiscoveryPairingPorts(
            pairingPorts,
            cachedPairing: cachedPairing,
            configuredInternetHost: nonEmpty(options.internetHost)
        )
        let summary = plan.networkSummaries.isEmpty
            ? "unknown"
            : plan.networkSummaries.joined(separator: ", ")
        var logs = [
            "[lan-discover] fallback subnet scan: networks=\(summary) hosts=\(prioritizedHosts.count)"
        ]
        let priorityHosts = Self.lanDiscoveryPriorityHostWindow(
            prioritizedHosts,
            limitPerSubnet: Self.lanDiscoveryPriorityHostsPerSubnet
        )
        let deferredHosts = Self.remainingLANDiscoveryHosts(
            prioritizedHosts,
            excluding: priorityHosts
        )
        if !priorityHosts.isEmpty, priorityHosts.count < prioritizedHosts.count {
            logs.append("[lan-discover] priority pass: hosts=\(priorityHosts.count) deferred=\(deferredHosts.count)")
        }

        var localNetworkAccessDenied = false
        var permissionLogEmitted = false

        func emitPermissionLogIfNeeded() {
            guard localNetworkAccessDenied, !permissionLogEmitted else { return }
            logs.append("[lan-discover] local network access denied; X-Terminal needs Local Network permission to probe Hub endpoints.")
            permissionLogEmitted = true
        }

        func resolveMatches(
            _ matches: [HubLANDiscoveryProbeMatch]
        ) -> HubLANDiscoveryAttempt? {
            guard !matches.isEmpty else { return nil }

            let resolved = resolveDiscoveryCandidate(
                matches.map {
                    HubLANDiscoveryCandidate(
                        host: $0.host,
                        pairingPort: $0.pairingPort,
                        grpcPort: $0.grpcPort,
                        internetHost: $0.internetHost,
                        hubInstanceID: $0.hubInstanceID,
                        lanDiscoveryName: $0.lanDiscoveryName,
                        pairingProfileEpoch: $0.pairingProfileEpoch,
                        routePackVersion: $0.routePackVersion,
                        logLines: []
                    )
                },
                cachedPairing: cachedPairing,
                configuredInternetHost: nonEmpty(options.internetHost),
                configuredHubInstanceID: nonEmpty(options.inviteInstanceID),
                source: "lan-discover",
                ambiguousReasonCode: "lan_multiple_hubs_ambiguous"
            )
            logs.append(contentsOf: resolved.logLines)
            if let candidate = resolved.candidate {
                let finalizedCandidate = finalizedDiscoveryCandidate(candidate, cachedPairing: cachedPairing)
                if let repairBlock = pairingMetadataRepairBlock(
                    cachedPairing: cachedPairing,
                    discoveredCandidate: finalizedCandidate,
                    source: "lan-discover"
                ) {
                    logs.append(repairBlock.detailLine)
                    emitPermissionLogIfNeeded()
                    return HubLANDiscoveryAttempt(
                        candidate: nil,
                        reasonCode: repairBlock.reasonCode,
                        candidates: [finalizedCandidate],
                        logLines: logs
                    )
                }
                logs.append(contentsOf: persistDiscoveryCandidate(finalizedCandidate, options: options, source: "lan-discover"))
                emitPermissionLogIfNeeded()
                return HubLANDiscoveryAttempt(
                    candidate: HubLANDiscoveryCandidate(
                        host: finalizedCandidate.host,
                        pairingPort: finalizedCandidate.pairingPort,
                        grpcPort: finalizedCandidate.grpcPort,
                        internetHost: finalizedCandidate.internetHost,
                        hubInstanceID: finalizedCandidate.hubInstanceID,
                        lanDiscoveryName: finalizedCandidate.lanDiscoveryName,
                        pairingProfileEpoch: finalizedCandidate.pairingProfileEpoch,
                        routePackVersion: finalizedCandidate.routePackVersion,
                        logLines: logs
                    ),
                    reasonCode: nil,
                    candidates: [finalizedCandidate],
                    logLines: logs
                )
            }
            if let reasonCode = resolved.reasonCode {
                emitPermissionLogIfNeeded()
                return HubLANDiscoveryAttempt(
                    candidate: nil,
                    reasonCode: reasonCode,
                    candidates: resolved.candidates,
                    logLines: logs
                )
            }
            return nil
        }

        for pairingPort in portCandidates {
            let priorityResult = await Self.collectLANDiscoveryMatches(
                hosts: priorityHosts,
                pairingPort: pairingPort,
                timeoutSec: Self.lanDiscoveryFallbackProbeTimeoutSec
            )
            if priorityResult.localNetworkAccessDenied {
                localNetworkAccessDenied = true
            }
            if let resolvedAttempt = resolveMatches(priorityResult.matches) {
                return resolvedAttempt
            }

            guard !deferredHosts.isEmpty else { continue }
            let deferredResult = await Self.collectLANDiscoveryMatches(
                hosts: deferredHosts,
                pairingPort: pairingPort,
                timeoutSec: Self.lanDiscoveryFallbackProbeTimeoutSec
            )
            if deferredResult.localNetworkAccessDenied {
                localNetworkAccessDenied = true
            }
            if let resolvedAttempt = resolveMatches(deferredResult.matches) {
                return resolvedAttempt
            }
        }

        emitPermissionLogIfNeeded()
        if localNetworkAccessDenied {
            return HubLANDiscoveryAttempt(
                candidate: nil,
                reasonCode: Self.localNetworkPermissionRequiredReason,
                candidates: [],
                logLines: logs
            )
        }
        logs.append("[lan-discover] no Hub responded on scanned subnets.")
        return HubLANDiscoveryAttempt(candidate: nil, reasonCode: nil, candidates: [], logLines: logs)
    }

    func discoverHubViaKnownHosts(
        options: HubRemoteConnectOptions,
        pairingPorts: [Int],
        cachedPairing: HubCachedPairingInfo,
        hasAuthoritativeLocalProfile: Bool
    ) async -> HubLANDiscoveryAttempt {
        let currentMachineHosts = Self.currentMachineIPv4Hosts()
        let preferredHosts = Self.preferredDiscoveryHostsValue(
            configuredInternetHost: options.internetHost,
            cachedPairing: cachedPairing,
            inviteAlias: options.inviteAlias,
            inviteInstanceID: options.inviteInstanceID,
            hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile,
            currentMachineHosts: currentMachineHosts
        )
        guard !preferredHosts.isEmpty else {
            return HubLANDiscoveryAttempt(candidate: nil, reasonCode: nil, candidates: [], logLines: [])
        }

        var logs = [
            "[known-discover] probing cached/configured hosts=\(preferredHosts.joined(separator: ", "))"
        ]
        var matches: [HubLANDiscoveryCandidate] = []
        var localNetworkAccessDenied = false
        var portCandidates: [Int] = []
        for pairingPort in pairingPorts {
            let clamped = max(1, min(65_535, pairingPort))
            if !portCandidates.contains(clamped) {
                portCandidates.append(clamped)
            }
        }

        for host in preferredHosts {
            for pairingPort in portCandidates {
                let probe = await Self.probeLANPairingEndpoint(
                    host: host,
                    pairingPort: pairingPort,
                    timeoutSec: Self.pairingDiscoveryProbeTimeoutSec
                )
                if probe.localNetworkAccessDenied {
                    localNetworkAccessDenied = true
                }
                guard let matched = probe.match else {
                    continue
                }
                if Self.shouldIgnoreDiscoveredLoopbackCandidate(
                    discoveredHost: matched.host,
                    configuredInternetHost: options.internetHost,
                    cachedPairing: cachedPairing,
                    hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile,
                    currentMachineHosts: currentMachineHosts
                ) {
                    logs.append("[known-discover] ignore loopback candidate without authoritative local pairing state (got \(matched.host))")
                    continue
                }

                matches.append(
                    HubLANDiscoveryCandidate(
                        host: matched.host,
                        pairingPort: matched.pairingPort,
                        grpcPort: matched.grpcPort,
                        internetHost: matched.internetHost,
                        hubInstanceID: matched.hubInstanceID,
                        lanDiscoveryName: matched.lanDiscoveryName,
                        pairingProfileEpoch: matched.pairingProfileEpoch,
                        routePackVersion: matched.routePackVersion,
                        logLines: []
                    )
                )
                logs.append("[known-discover] matched requested=\(host) resolved=\(matched.host) pairing=\(matched.pairingPort) grpc=\(matched.grpcPort)")
                break
            }
        }

        let resolved = resolveDiscoveryCandidate(
            matches,
            cachedPairing: cachedPairing,
            configuredInternetHost: nonEmpty(options.internetHost),
            configuredHubInstanceID: nonEmpty(options.inviteInstanceID),
            source: "known-discover",
            ambiguousReasonCode: "known_hosts_multiple_hubs_ambiguous"
        )
        if localNetworkAccessDenied {
            logs.append("[known-discover] local network access denied; X-Terminal needs Local Network permission to probe Hub endpoints.")
        }
        if localNetworkAccessDenied, matches.isEmpty {
            return HubLANDiscoveryAttempt(
                candidate: nil,
                reasonCode: Self.localNetworkPermissionRequiredReason,
                candidates: [],
                logLines: logs
            )
        }
        logs.append(contentsOf: resolved.logLines)

        guard let candidate = resolved.candidate else {
            return HubLANDiscoveryAttempt(
                candidate: nil,
                reasonCode: resolved.reasonCode,
                candidates: resolved.candidates,
                logLines: logs
            )
        }

        let finalizedCandidate = finalizedDiscoveryCandidate(candidate, cachedPairing: cachedPairing)
        if let repairBlock = pairingMetadataRepairBlock(
            cachedPairing: cachedPairing,
            discoveredCandidate: finalizedCandidate,
            source: "known-discover"
        ) {
            logs.append(repairBlock.detailLine)
            return HubLANDiscoveryAttempt(
                candidate: nil,
                reasonCode: repairBlock.reasonCode,
                candidates: [finalizedCandidate],
                logLines: logs
            )
        }
        logs.append(contentsOf: persistDiscoveryCandidate(finalizedCandidate, options: options, source: "known-discover"))

        return HubLANDiscoveryAttempt(
            candidate: HubLANDiscoveryCandidate(
                host: finalizedCandidate.host,
                pairingPort: finalizedCandidate.pairingPort,
                grpcPort: finalizedCandidate.grpcPort,
                internetHost: finalizedCandidate.internetHost,
                hubInstanceID: finalizedCandidate.hubInstanceID,
                lanDiscoveryName: finalizedCandidate.lanDiscoveryName,
                pairingProfileEpoch: finalizedCandidate.pairingProfileEpoch,
                routePackVersion: finalizedCandidate.routePackVersion,
                logLines: logs
            ),
            reasonCode: nil,
            candidates: [finalizedCandidate],
            logLines: logs
        )
    }

    func discoverHubViaBonjour(
        options: HubRemoteConnectOptions,
        cachedPairing: HubCachedPairingInfo
    ) async -> HubLANDiscoveryAttempt {
        let outcome = await HubBonjourDiscovery.discover(timeoutSec: 1.6)
        let resolved = resolveDiscoveryCandidate(
            outcome.candidates.map {
                HubLANDiscoveryCandidate(
                    host: $0.host,
                    pairingPort: $0.pairingPort,
                    grpcPort: $0.grpcPort,
                    internetHost: $0.internetHost,
                    hubInstanceID: $0.hubInstanceID,
                    lanDiscoveryName: $0.lanDiscoveryName,
                    logLines: []
                )
            },
            cachedPairing: cachedPairing,
            configuredInternetHost: nonEmpty(options.internetHost),
            configuredHubInstanceID: nonEmpty(options.inviteInstanceID),
            source: "bonjour-discover",
            ambiguousReasonCode: "bonjour_multiple_hubs_ambiguous"
        )

        guard let candidate = resolved.candidate else {
            return HubLANDiscoveryAttempt(
                candidate: nil,
                reasonCode: resolved.reasonCode,
                candidates: resolved.candidates,
                logLines: resolved.logLines
            )
        }

        var logs = resolved.logLines
        let finalizedCandidate = finalizedDiscoveryCandidate(candidate, cachedPairing: cachedPairing)
        if let repairBlock = pairingMetadataRepairBlock(
            cachedPairing: cachedPairing,
            discoveredCandidate: finalizedCandidate,
            source: "bonjour-discover"
        ) {
            logs.append(repairBlock.detailLine)
            return HubLANDiscoveryAttempt(
                candidate: nil,
                reasonCode: repairBlock.reasonCode,
                candidates: [finalizedCandidate],
                logLines: logs
            )
        }
        logs.append(contentsOf: persistDiscoveryCandidate(finalizedCandidate, options: options, source: "bonjour-discover"))

        return HubLANDiscoveryAttempt(
            candidate: HubLANDiscoveryCandidate(
                host: finalizedCandidate.host,
                pairingPort: finalizedCandidate.pairingPort,
                grpcPort: finalizedCandidate.grpcPort,
                internetHost: finalizedCandidate.internetHost,
                hubInstanceID: finalizedCandidate.hubInstanceID,
                lanDiscoveryName: finalizedCandidate.lanDiscoveryName,
                pairingProfileEpoch: finalizedCandidate.pairingProfileEpoch,
                routePackVersion: finalizedCandidate.routePackVersion,
                logLines: logs
            ),
            reasonCode: nil,
            candidates: [finalizedCandidate],
            logLines: logs
        )
    }

    func resolveDiscoveryCandidate(
        _ rawCandidates: [HubLANDiscoveryCandidate],
        cachedPairing: HubCachedPairingInfo,
        configuredInternetHost: String?,
        configuredHubInstanceID: String?,
        source: String,
        ambiguousReasonCode: String
    ) -> HubLANDiscoveryAttempt {
        let candidates = deduplicatedDiscoveryCandidates(rawCandidates)
        guard !candidates.isEmpty else {
            return HubLANDiscoveryAttempt(candidate: nil, reasonCode: nil, candidates: [], logLines: [])
        }

        if candidates.count == 1, let candidate = candidates.first {
            return HubLANDiscoveryAttempt(
                candidate: candidate,
                reasonCode: nil,
                candidates: candidates,
                logLines: ["[\(source)] selected \(describeDiscoveryCandidate(candidate))"]
            )
        }

        if let pinnedHubInstanceID = normalizedDiscoveryToken(cachedPairing.hubInstanceID) {
            let matches = candidates.filter {
                normalizedDiscoveryToken($0.hubInstanceID) == pinnedHubInstanceID
            }
            if matches.count == 1, let match = matches.first {
                return HubLANDiscoveryAttempt(
                    candidate: match,
                    reasonCode: nil,
                    candidates: candidates,
                    logLines: ["[\(source)] selected cached hub identity=\(pinnedHubInstanceID) -> \(describeDiscoveryCandidate(match))"]
                )
            }
        }

        if let configuredHubInstanceID = normalizedDiscoveryToken(configuredHubInstanceID) {
            let matches = candidates.filter {
                normalizedDiscoveryToken($0.hubInstanceID) == configuredHubInstanceID
            }
            if matches.count == 1, let match = matches.first {
                return HubLANDiscoveryAttempt(
                    candidate: match,
                    reasonCode: nil,
                    candidates: candidates,
                    logLines: ["[\(source)] selected configured hub identity=\(configuredHubInstanceID) -> \(describeDiscoveryCandidate(match))"]
                )
            }
        }

        let pinnedInternetHosts = [
            normalizedHostToken(configuredInternetHost),
            normalizedHostToken(cachedPairing.internetHost),
        ].compactMap { $0 }

        for pinnedInternetHost in pinnedInternetHosts {
            let matches = candidates.filter {
                normalizedHostToken($0.internetHost) == pinnedInternetHost
            }
            if matches.count == 1, let match = matches.first {
                return HubLANDiscoveryAttempt(
                    candidate: match,
                    reasonCode: nil,
                    candidates: candidates,
                    logLines: ["[\(source)] selected pinned internet host=\(pinnedInternetHost) -> \(describeDiscoveryCandidate(match))"]
                )
            }
        }

        let rendered = candidates
            .map { describeDiscoveryCandidate($0) }
            .joined(separator: " | ")
        return HubLANDiscoveryAttempt(
            candidate: nil,
            reasonCode: ambiguousReasonCode,
            candidates: candidates,
            logLines: ["[\(source)] multiple hubs discovered; refusing auto-select. candidates=\(rendered)"]
        )
    }

    func summary(from candidate: HubLANDiscoveryCandidate) -> HubDiscoveredHubCandidateSummary {
        HubDiscoveredHubCandidateSummary(
            host: candidate.host,
            pairingPort: candidate.pairingPort,
            grpcPort: candidate.grpcPort,
            internetHost: candidate.internetHost,
            hubInstanceID: candidate.hubInstanceID,
            lanDiscoveryName: candidate.lanDiscoveryName,
            pairingProfileEpoch: candidate.pairingProfileEpoch,
            routePackVersion: candidate.routePackVersion
        )
    }

    func deduplicatedDiscoveryCandidates(
        _ rawCandidates: [HubLANDiscoveryCandidate]
    ) -> [HubLANDiscoveryCandidate] {
        var mergedByKey: [String: HubLANDiscoveryCandidate] = [:]
        var orderedKeys: [String] = []

        for candidate in rawCandidates {
            let key = discoveryCandidateKey(candidate)
            if let existing = mergedByKey[key] {
                mergedByKey[key] = richerDiscoveryCandidate(existing, candidate)
            } else {
                mergedByKey[key] = candidate
                orderedKeys.append(key)
            }
        }

        return orderedKeys.compactMap { mergedByKey[$0] }
    }

    func discoveryCandidateKey(_ candidate: HubLANDiscoveryCandidate) -> String {
        if let hubInstanceID = normalizedDiscoveryToken(candidate.hubInstanceID) {
            return "id:\(hubInstanceID)"
        }
        return [
            normalizedHostToken(candidate.host) ?? "",
            String(candidate.pairingPort),
            String(candidate.grpcPort),
            normalizedHostToken(candidate.internetHost) ?? "",
        ].joined(separator: "|")
    }

    func richerDiscoveryCandidate(
        _ lhs: HubLANDiscoveryCandidate,
        _ rhs: HubLANDiscoveryCandidate
    ) -> HubLANDiscoveryCandidate {
        discoveryCandidateScore(lhs) >= discoveryCandidateScore(rhs) ? lhs : rhs
    }

    func discoveryCandidateScore(_ candidate: HubLANDiscoveryCandidate) -> Int {
        var score = 0
        if nonEmpty(candidate.internetHost) != nil { score += 4 }
        if nonEmpty(candidate.hubInstanceID) != nil { score += 3 }
        if nonEmpty(candidate.lanDiscoveryName) != nil { score += 2 }
        if candidate.pairingProfileEpoch != nil { score += 1 }
        if nonEmpty(candidate.routePackVersion) != nil { score += 1 }
        if !candidate.logLines.isEmpty { score += 1 }
        return score
    }

    func describeDiscoveryCandidate(_ candidate: HubLANDiscoveryCandidate) -> String {
        let service = nonEmpty(candidate.lanDiscoveryName)
            ?? nonEmpty(candidate.hubInstanceID)
            ?? candidate.host
        let internet = nonEmpty(candidate.internetHost) ?? "-"
        let epoch = candidate.pairingProfileEpoch.map(String.init) ?? "-"
        let routePack = nonEmpty(candidate.routePackVersion) ?? "-"
        return "service=\(service) host=\(candidate.host) pairing=\(candidate.pairingPort) grpc=\(candidate.grpcPort) internet=\(internet) epoch=\(epoch) route_pack=\(routePack)"
    }

    func finalizedDiscoveryCandidate(
        _ candidate: HubLANDiscoveryCandidate,
        cachedPairing: HubCachedPairingInfo
    ) -> HubLANDiscoveryCandidate {
        HubLANDiscoveryCandidate(
            host: candidate.host,
            pairingPort: candidate.pairingPort,
            grpcPort: candidate.grpcPort,
            internetHost: nonEmpty(candidate.internetHost) ?? nonEmpty(cachedPairing.internetHost),
            hubInstanceID: candidate.hubInstanceID,
            lanDiscoveryName: candidate.lanDiscoveryName,
            pairingProfileEpoch: candidate.pairingProfileEpoch,
            routePackVersion: candidate.routePackVersion,
            logLines: candidate.logLines
        )
    }

    func persistDiscoveryCandidate(
        _ candidate: HubLANDiscoveryCandidate,
        options: HubRemoteConnectOptions,
        source: String
    ) -> [String] {
        do {
            try persistDiscoveredPairingInfo(
                host: candidate.host,
                pairingPort: candidate.pairingPort,
                grpcPort: candidate.grpcPort,
                internetHost: candidate.internetHost,
                hubInstanceID: candidate.hubInstanceID,
                lanDiscoveryName: candidate.lanDiscoveryName,
                pairingProfileEpoch: candidate.pairingProfileEpoch,
                routePackVersion: candidate.routePackVersion,
                options: options
            )
            return ["[\(source)] cached host=\(candidate.host) pairing=\(candidate.pairingPort) grpc=\(candidate.grpcPort)"]
        } catch {
            return ["[\(source)] cache_write_failed: \(error.localizedDescription)"]
        }
    }

    func pairingMetadataRepairBlock(
        cachedPairing: HubCachedPairingInfo,
        discoveredCandidate: HubLANDiscoveryCandidate,
        source: String
    ) -> PairingMetadataRepairBlock? {
        guard let block = Self.pairingMetadataRepairBlockValue(
            cachedHubInstanceID: cachedPairing.hubInstanceID,
            discoveredHubInstanceID: discoveredCandidate.hubInstanceID,
            cachedPairingProfileEpoch: cachedPairing.pairingProfileEpoch,
            discoveredPairingProfileEpoch: discoveredCandidate.pairingProfileEpoch,
            cachedRoutePackVersion: cachedPairing.routePackVersion,
            discoveredRoutePackVersion: discoveredCandidate.routePackVersion
        ) else {
            return nil
        }
        return PairingMetadataRepairBlock(
            reasonCode: block.reasonCode,
            detailLine: "[\(source)] \(block.detailLine)"
        )
    }

    nonisolated static func pairingMetadataRepairBlockValue(
        cachedHubInstanceID: String?,
        discoveredHubInstanceID: String?,
        cachedPairingProfileEpoch: Int?,
        discoveredPairingProfileEpoch: Int?,
        cachedRoutePackVersion: String?,
        discoveredRoutePackVersion: String?
    ) -> PairingMetadataRepairBlock? {
        let cachedHubInstance = normalizedDiscoveryTokenValue(cachedHubInstanceID)
        let discoveredHubInstance = normalizedDiscoveryTokenValue(discoveredHubInstanceID)
        if let cachedHubInstance,
           let discoveredHubInstance,
           cachedHubInstance != discoveredHubInstance {
            let cachedDisplay = normalizedTrimmed(cachedHubInstanceID) ?? "-"
            let discoveredDisplay = normalizedTrimmed(discoveredHubInstanceID) ?? "-"
            return PairingMetadataRepairBlock(
                reasonCode: "hub_instance_mismatch",
                detailLine: "pairing identity changed; cached hub_instance_id=\(cachedDisplay) discovered hub_instance_id=\(discoveredDisplay)."
            )
        }

        if let cachedEpoch = cachedPairingProfileEpoch,
           let discoveredEpoch = discoveredPairingProfileEpoch,
           discoveredEpoch > cachedEpoch {
            return PairingMetadataRepairBlock(
                reasonCode: "pairing_profile_epoch_stale",
                detailLine: "paired profile is stale; cached pairing_profile_epoch=\(cachedEpoch) discovered pairing_profile_epoch=\(discoveredEpoch)."
            )
        }

        let cachedRoutePack = normalizedTrimmed(cachedRoutePackVersion)
        let discoveredRoutePack = normalizedTrimmed(discoveredRoutePackVersion)
        if let cachedRoutePack,
           let discoveredRoutePack,
           cachedRoutePack != discoveredRoutePack {
            return PairingMetadataRepairBlock(
                reasonCode: "route_pack_outdated",
                detailLine: "saved route pack is outdated; cached route_pack_version=\(cachedRoutePack) discovered route_pack_version=\(discoveredRoutePack)."
            )
        }

        return nil
    }

    nonisolated static func loopbackOnlyDiscoveryFailureReason(
        ignoredLoopbackCandidate: Bool,
        hasAuthoritativeLocalProfile: Bool
    ) -> String? {
        guard ignoredLoopbackCandidate, !hasAuthoritativeLocalProfile else { return nil }
        return localNetworkDiscoveryBlockedReason
    }

    nonisolated static func shouldFailClosedOnDiscoveryReason(_ rawReason: String?) -> Bool {
        switch sanitizedReasonToken(rawReason) {
        case "hub_instance_mismatch", "pairing_profile_epoch_stale", "route_pack_outdated":
            return true
        default:
            return false
        }
    }

    nonisolated static func shouldSkipBootstrapRefreshAfterConnectFailure(_ rawReason: String?) -> Bool {
        switch sanitizedReasonToken(rawReason) {
        case "invite_token_required",
             "invite_token_invalid",
             "pairing_token_invalid",
             "bootstrap_token_invalid",
             "pairing_token_expired",
             "bootstrap_token_expired",
             "unauthenticated",
             "mtls_client_certificate_required",
             "certificate_required",
             "hub_instance_mismatch",
             "pairing_profile_epoch_stale",
             "route_pack_outdated":
            return true
        default:
            return false
        }
    }

    func normalizedDiscoveryToken(_ raw: String?) -> String? {
        Self.normalizedDiscoveryTokenValue(raw)
    }

    nonisolated static func normalizedDiscoveryTokenValue(_ raw: String?) -> String? {
        normalizedTrimmed(raw)?.lowercased()
    }

    func normalizedHostToken(_ raw: String?) -> String? {
        guard let value = nonEmpty(raw)?.lowercased() else { return nil }
        if value.hasSuffix(".") {
            return String(value.dropLast())
        }
        return value
    }

    func parsedRawDiscoveryCandidate(
        from output: String,
        defaultPairingPort: Int,
        defaultGRPCPort: Int,
        fallbackHost: String?,
        fallbackInternetHost: String?
    ) -> HubLANDiscoveryCandidate? {
        let host = nonEmpty(parseStringField(output, fieldName: "host"))
            ?? nonEmpty(fallbackHost)
        guard let host else { return nil }

        return HubLANDiscoveryCandidate(
            host: host,
            pairingPort: parsePortField(output, fieldName: "pairing_port") ?? defaultPairingPort,
            grpcPort: parsePortField(output, fieldName: "grpc_port") ?? defaultGRPCPort,
            internetHost: Self.reusableDiscoveredInternetHost(parseStringField(output, fieldName: "internet_host"))
                ?? Self.reusableDiscoveredInternetHost(parseStringField(output, fieldName: "internet_host_hint"))
                ?? Self.reusableDiscoveredInternetHost(fallbackInternetHost),
            hubInstanceID: nonEmpty(parseStringField(output, fieldName: "hub_instance_id")),
            lanDiscoveryName: nonEmpty(parseStringField(output, fieldName: "lan_discovery_name")),
            pairingProfileEpoch: positiveInt(parseStringField(output, fieldName: "pairing_profile_epoch")),
            routePackVersion: nonEmpty(parseStringField(output, fieldName: "route_pack_version")),
            logLines: []
        )
    }

    func prioritizeLANHosts(
        _ hosts: [String],
        preferredHosts: [String?]
    ) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []

        func appendHost(_ raw: String?) {
            guard let raw else { return }
            let host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else { return }
            guard !isLoopbackHost(host) else { return }
            guard seen.insert(normalizeHost(host)).inserted else { return }
            ordered.append(host)
        }

        for host in preferredHosts {
            appendHost(host)
        }
        for host in hosts {
            appendHost(host)
        }
        return ordered
    }

    func persistDiscoveredPairingInfo(
        host: String,
        pairingPort: Int,
        grpcPort: Int,
        internetHost: String?,
        hubInstanceID: String?,
        lanDiscoveryName: String?,
        pairingProfileEpoch: Int?,
        routePackVersion: String?,
        options: HubRemoteConnectOptions
    ) throws {
        let base = options.stateDir ?? defaultStateDir()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let pairingEnv = base.appendingPathComponent("pairing.env")
        let appID = canonicalHubAppID(readEnvValue(from: pairingEnv, key: "AXHUB_APP_ID")) ?? "x_terminal"
        let deviceName = nonEmpty(readEnvValue(from: pairingEnv, key: "AXHUB_DEVICE_NAME"))
            ?? nonEmpty(options.deviceName)
            ?? "X-Terminal"
        let pairingRequestID = readEnvValue(from: pairingEnv, key: "AXHUB_PAIRING_REQUEST_ID") ?? ""
        let pairingSecret = readEnvValue(from: pairingEnv, key: "AXHUB_PAIRING_SECRET") ?? ""
        let preservedInternetHost = Self.reusableDiscoveredInternetHost(internetHost)
            ?? Self.reusableDiscoveredInternetHost(readEnvValue(from: pairingEnv, key: "AXHUB_INTERNET_HOST"))
            ?? ""
        let preservedHubInstanceID = nonEmpty(hubInstanceID)
            ?? nonEmpty(readEnvValue(from: pairingEnv, key: "AXHUB_HUB_INSTANCE_ID"))
            ?? ""
        let preservedLanDiscoveryName = nonEmpty(lanDiscoveryName)
            ?? nonEmpty(readEnvValue(from: pairingEnv, key: "AXHUB_LAN_DISCOVERY_NAME"))
            ?? ""
        let preservedPairingProfileEpoch = pairingProfileEpoch
            ?? positiveInt(readEnvValue(from: pairingEnv, key: "AXHUB_PAIRING_PROFILE_EPOCH"))
        let preservedRoutePackVersion = nonEmpty(routePackVersion)
            ?? nonEmpty(readEnvValue(from: pairingEnv, key: "AXHUB_ROUTE_PACK_VERSION"))
            ?? ""

        let contents = pairingEnvContents(
            host: host,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            appID: appID,
            deviceName: deviceName,
            pairingRequestID: pairingRequestID,
            pairingSecret: pairingSecret,
            internetHost: preservedInternetHost,
            hubInstanceID: preservedHubInstanceID,
            lanDiscoveryName: preservedLanDiscoveryName,
            pairingProfileEpoch: preservedPairingProfileEpoch,
            routePackVersion: preservedRoutePackVersion
        )

        try contents.write(to: pairingEnv, atomically: true, encoding: .utf8)
    }

    func synchronizedCachedPairingInfo(
        stateDir: URL?,
        fallbackDeviceName: String?
    ) -> HubCachedPairingLoadResult {
        let base = stateDir ?? defaultStateDir()
        let cached = HubAIClient.cachedRemoteProfile(stateDir: base)
        let pairing = HubCachedPairingInfo(
            host: cached.host,
            internetHost: cached.internetHost,
            pairingPort: cached.pairingPort,
            grpcPort: cached.grpcPort,
            hubInstanceID: cached.hubInstanceID,
            lanDiscoveryName: cached.lanDiscoveryName,
            pairingProfileEpoch: cached.pairingProfileEpoch,
            routePackVersion: cached.routePackVersion
        )
        var logLines: [String] = []
        do {
            if try synchronizePairingEnvIfNeeded(
                base: base,
                authoritative: pairing,
                fallbackDeviceName: fallbackDeviceName
            ) {
                logLines.append("[state-sync] pairing.env realigned to authoritative connection state.")
            }
        } catch {
            logLines.append("[state-sync] pairing.env_sync_failed: \(error.localizedDescription)")
        }
        return HubCachedPairingLoadResult(pairing: pairing, logLines: logLines)
    }

    func prepareDiscoveryProbeState(
        sourceStateDir: URL?,
        probeStateDir: URL?,
        fallbackDeviceName: String?
    ) -> [String] {
        guard let probeStateDir else { return [] }

        let sourceBase = sourceStateDir ?? defaultStateDir()
        let sourcePairingEnv = sourceBase.appendingPathComponent("pairing.env")
        let sourceHubEnv = sourceBase.appendingPathComponent("hub.env")
        let sourceConnectionJSON = sourceBase.appendingPathComponent("connection.json")
        let targetPairingEnv = probeStateDir.appendingPathComponent("pairing.env")
        let targetHubEnv = probeStateDir.appendingPathComponent("hub.env")
        let targetConnectionJSON = probeStateDir.appendingPathComponent("connection.json")
        let authoritative = HubAIClient.cachedRemoteProfile(stateDir: sourceBase)
        let pairing = HubCachedPairingInfo(
            host: authoritative.host,
            internetHost: authoritative.internetHost,
            pairingPort: authoritative.pairingPort,
            grpcPort: authoritative.grpcPort,
            hubInstanceID: authoritative.hubInstanceID,
            lanDiscoveryName: authoritative.lanDiscoveryName,
            pairingProfileEpoch: authoritative.pairingProfileEpoch,
            routePackVersion: authoritative.routePackVersion
        )
        var logLines: [String] = []

        do {
            try FileManager.default.createDirectory(at: probeStateDir, withIntermediateDirectories: true)
            if copyStateArtifactIfPresent(from: sourceHubEnv, to: targetHubEnv) {
                logLines.append("[state-sync] seeded probe hub.env.")
            }
            if copyStateArtifactIfPresent(from: sourceConnectionJSON, to: targetConnectionJSON) {
                logLines.append("[state-sync] seeded probe connection.json.")
            }
            if try writeAuthoritativePairingEnv(
                to: targetPairingEnv,
                sourcePairingEnv: sourcePairingEnv,
                authoritative: pairing,
                fallbackDeviceName: fallbackDeviceName
            ) {
                logLines.append("[state-sync] seeded probe pairing.env from authoritative state.")
            } else if copyStateArtifactIfPresent(from: sourcePairingEnv, to: targetPairingEnv) {
                logLines.append("[state-sync] copied probe pairing.env.")
            }
        } catch {
            logLines.append("[state-sync] probe_seed_failed: \(error.localizedDescription)")
        }

        return logLines
    }

    @discardableResult
    func synchronizePairingEnvIfNeeded(
        base: URL,
        authoritative: HubCachedPairingInfo,
        fallbackDeviceName: String?
    ) throws -> Bool {
        let pairingEnv = base.appendingPathComponent("pairing.env")
        return try writeAuthoritativePairingEnv(
            to: pairingEnv,
            sourcePairingEnv: pairingEnv,
            authoritative: authoritative,
            fallbackDeviceName: fallbackDeviceName
        )
    }

    @discardableResult
    func writeAuthoritativePairingEnv(
        to targetPairingEnv: URL,
        sourcePairingEnv: URL,
        authoritative: HubCachedPairingInfo,
        fallbackDeviceName: String?
    ) throws -> Bool {
        guard let contents = authoritativePairingEnvContents(
            sourcePairingEnv: sourcePairingEnv,
            authoritative: authoritative,
            fallbackDeviceName: fallbackDeviceName
        ) else {
            return false
        }

        let existingContents = try? String(contentsOf: targetPairingEnv, encoding: .utf8)
        guard existingContents != contents else { return false }

        try FileManager.default.createDirectory(
            at: targetPairingEnv.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: targetPairingEnv, atomically: true, encoding: .utf8)
        return true
    }

    func authoritativePairingEnvContents(
        sourcePairingEnv: URL,
        authoritative: HubCachedPairingInfo,
        fallbackDeviceName: String?
    ) -> String? {
        guard let host = nonEmpty(authoritative.host),
              let pairingPort = authoritative.pairingPort,
              let grpcPort = authoritative.grpcPort else {
            return nil
        }

        let currentPairingHost = nonEmpty(readEnvValue(from: sourcePairingEnv, key: "AXHUB_HUB_HOST"))
        let currentInternetHost = nonEmpty(readEnvValue(from: sourcePairingEnv, key: "AXHUB_INTERNET_HOST"))
        let currentHubInstanceID = nonEmpty(readEnvValue(from: sourcePairingEnv, key: "AXHUB_HUB_INSTANCE_ID"))
        let currentLanDiscoveryName = nonEmpty(readEnvValue(from: sourcePairingEnv, key: "AXHUB_LAN_DISCOVERY_NAME"))
        let currentPairingProfileEpoch = positiveInt(
            readEnvValue(from: sourcePairingEnv, key: "AXHUB_PAIRING_PROFILE_EPOCH")
        )
        let currentRoutePackVersion = nonEmpty(
            readEnvValue(from: sourcePairingEnv, key: "AXHUB_ROUTE_PACK_VERSION")
        )
        let trustPairingMetadata = currentPairingHost == nil
            || normalizedHostToken(currentPairingHost) == normalizedHostToken(host)
        let trustPairingInternetHost = HubRemoteHostPolicy.shouldTrustPairingInternetHost(
            pairingHost: currentPairingHost,
            authoritativeHost: host,
            pairingInternetHost: currentInternetHost
        )

        let appID = canonicalHubAppID(readEnvValue(from: sourcePairingEnv, key: "AXHUB_APP_ID")) ?? "x_terminal"
        let deviceName = nonEmpty(readEnvValue(from: sourcePairingEnv, key: "AXHUB_DEVICE_NAME"))
            ?? nonEmpty(fallbackDeviceName)
            ?? "X-Terminal"
        let pairingRequestID = readEnvValue(from: sourcePairingEnv, key: "AXHUB_PAIRING_REQUEST_ID") ?? ""
        let pairingSecret = readEnvValue(from: sourcePairingEnv, key: "AXHUB_PAIRING_SECRET") ?? ""
        let preservedInternetHost = nonEmpty(authoritative.internetHost)
            ?? (trustPairingInternetHost ? currentInternetHost : nil)
            ?? ""
        let preservedHubInstanceID = nonEmpty(authoritative.hubInstanceID)
            ?? (trustPairingMetadata ? currentHubInstanceID : nil)
            ?? ""
        let preservedLanDiscoveryName = nonEmpty(authoritative.lanDiscoveryName)
            ?? (trustPairingMetadata ? currentLanDiscoveryName : nil)
            ?? ""
        let preservedPairingProfileEpoch = authoritative.pairingProfileEpoch
            ?? (trustPairingMetadata ? currentPairingProfileEpoch : nil)
        let preservedRoutePackVersion = nonEmpty(authoritative.routePackVersion)
            ?? (trustPairingMetadata ? currentRoutePackVersion : nil)
            ?? ""

        return pairingEnvContents(
            host: host,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            appID: appID,
            deviceName: deviceName,
            pairingRequestID: pairingRequestID,
            pairingSecret: pairingSecret,
            internetHost: preservedInternetHost,
            hubInstanceID: preservedHubInstanceID,
            lanDiscoveryName: preservedLanDiscoveryName,
            pairingProfileEpoch: preservedPairingProfileEpoch,
            routePackVersion: preservedRoutePackVersion
        )
    }

    func copyStateArtifactIfPresent(from source: URL, to target: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return false }
        do {
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.copyItem(at: source, to: target)
            return true
        } catch {
            return false
        }
    }

    func pairingEnvContents(
        host: String,
        pairingPort: Int,
        grpcPort: Int,
        appID: String,
        deviceName: String,
        pairingRequestID: String,
        pairingSecret: String,
        internetHost: String,
        hubInstanceID: String,
        lanDiscoveryName: String,
        pairingProfileEpoch: Int?,
        routePackVersion: String
    ) -> String {
        [
            "AXHUB_HUB_HOST=\(shellSingleQuoted(host))",
            "AXHUB_PAIRING_PORT=\(shellSingleQuoted(String(pairingPort)))",
            "AXHUB_GRPC_PORT=\(shellSingleQuoted(String(grpcPort)))",
            "AXHUB_APP_ID=\(shellSingleQuoted(appID))",
            "AXHUB_DEVICE_NAME=\(shellSingleQuoted(deviceName))",
            "AXHUB_PAIRING_REQUEST_ID=\(shellSingleQuoted(pairingRequestID))",
            "AXHUB_PAIRING_SECRET=\(shellSingleQuoted(pairingSecret))",
            "AXHUB_INTERNET_HOST=\(shellSingleQuoted(internetHost))",
            "AXHUB_HUB_INSTANCE_ID=\(shellSingleQuoted(hubInstanceID))",
            "AXHUB_LAN_DISCOVERY_NAME=\(shellSingleQuoted(lanDiscoveryName))",
            "AXHUB_PAIRING_PROFILE_EPOCH=\(shellSingleQuoted(pairingProfileEpoch.map(String.init) ?? ""))",
            "AXHUB_ROUTE_PACK_VERSION=\(shellSingleQuoted(routePackVersion))",
        ].joined(separator: "\n") + "\n"
    }

    nonisolated static func buildLANDiscoveryScanPlan() -> HubLANDiscoveryScanPlan {
        var discoveredHosts: [String] = []
        var seenHosts: Set<String> = []
        var networkSummaries: [String] = []
        var seenNetworks: Set<String> = []

        var cursor: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&cursor) == 0, let first = cursor else {
            return HubLANDiscoveryScanPlan(hosts: [], networkSummaries: [])
        }
        defer { freeifaddrs(cursor) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = current {
            defer { current = pointer.pointee.ifa_next }

            let entry = pointer.pointee
            guard let addr = entry.ifa_addr, let netmask = entry.ifa_netmask else { continue }
            guard addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard netmask.pointee.sa_family == UInt8(AF_INET) else { continue }

            let flags = Int32(entry.ifa_flags)
            guard shouldIncludeLANDiscoveryInterface(
                name: String(cString: entry.ifa_name),
                flags: flags
            ) else { continue }

            guard let addressValue = ipv4UInt32(from: addr),
                  let maskValue = ipv4UInt32(from: netmask),
                  maskValue != 0 else {
                continue
            }

            var prefixLength = maskValue.nonzeroBitCount
            var effectiveMask = maskValue
            if prefixLength < 24 {
                prefixLength = 24
                effectiveMask = 0xFF_FF_FF_00
            }
            if prefixLength > 30 { continue }

            let cidrs = expandedLANDiscoveryCIDRs(
                addressValue: addressValue,
                effectiveMask: effectiveMask,
                prefixLength: prefixLength
            )
            for cidr in cidrs {
                guard cidr.broadcast > cidr.network + 1 else { continue }

                let networkSummary = "\(ipv4String(cidr.network))/\(cidr.prefixLength)"
                if seenNetworks.insert(networkSummary).inserted {
                    networkSummaries.append(networkSummary)
                }

                func appendHost(_ rawValue: UInt32) {
                    guard rawValue > cidr.network, rawValue < cidr.broadcast else { return }
                    guard rawValue != addressValue else { return }
                    let host = ipv4String(rawValue)
                    let key = host.lowercased()
                    guard seenHosts.insert(key).inserted else { return }
                    discoveredHosts.append(host)
                }

                appendHost(cidr.network &+ 1)
                var candidate = cidr.network &+ 1
                while candidate < cidr.broadcast {
                    appendHost(candidate)
                    candidate &+= 1
                }
            }
        }

        return HubLANDiscoveryScanPlan(
            hosts: discoveredHosts,
            networkSummaries: networkSummaries
        )
    }

    nonisolated static func expandedLANDiscoveryCIDRs(
        addressValue: UInt32,
        effectiveMask: UInt32,
        prefixLength: Int
    ) -> [HubLANDiscoveryCIDR] {
        let network = addressValue & effectiveMask
        let broadcast = network | ~effectiveMask
        var cidrs = [
            HubLANDiscoveryCIDR(
                network: network,
                broadcast: broadcast,
                prefixLength: prefixLength
            )
        ]

        guard prefixLength == 24 else { return cidrs }
        let addressHost = ipv4String(addressValue)
        guard HubRemoteHostPolicy.isPublicIPv4Host(addressHost) else { return cidrs }

        let base16 = network & 0xFFFF_0000
        let step: UInt32 = 0x100
        let nextNetwork = network &+ step
        if (nextNetwork & 0xFFFF_0000) == base16 {
            cidrs.append(
                HubLANDiscoveryCIDR(
                    network: nextNetwork,
                    broadcast: nextNetwork | 0xFF,
                    prefixLength: 24
                )
            )
        }
        if network >= step {
            let previousNetwork = network &- step
            if (previousNetwork & 0xFFFF_0000) == base16 {
                cidrs.append(
                    HubLANDiscoveryCIDR(
                        network: previousNetwork,
                        broadcast: previousNetwork | 0xFF,
                        prefixLength: 24
                    )
                )
            }
        }
        return cidrs
    }

    nonisolated static func collectLANDiscoveryMatches(
        hosts: [String],
        pairingPort: Int,
        timeoutSec: TimeInterval
    ) async -> HubLANDiscoveryProbeCollection {
        guard !hosts.isEmpty else {
            return HubLANDiscoveryProbeCollection(matches: [], localNetworkAccessDenied: false)
        }

        let maxConcurrentProbes = max(4, min(maxConcurrentLANDiscoveryProbes, hosts.count))
        var iterator = hosts.makeIterator()

        return await withTaskGroup(of: HubLANDiscoveryProbeOutcome.self) { group in
            for _ in 0..<maxConcurrentProbes {
                guard let host = iterator.next() else { break }
                group.addTask {
                    await probeLANPairingEndpoint(
                        host: host,
                        pairingPort: pairingPort,
                        timeoutSec: timeoutSec
                    )
                }
            }

            var matches: [HubLANDiscoveryProbeMatch] = []
            var localNetworkAccessDenied = false
            while let result = await group.next() {
                if let match = result.match {
                    matches.append(match)
                }
                if result.localNetworkAccessDenied {
                    localNetworkAccessDenied = true
                }
                if let nextHost = iterator.next() {
                    group.addTask {
                        await probeLANPairingEndpoint(
                            host: nextHost,
                            pairingPort: pairingPort,
                            timeoutSec: timeoutSec
                        )
                    }
                }
            }
            return HubLANDiscoveryProbeCollection(
                matches: matches,
                localNetworkAccessDenied: localNetworkAccessDenied
            )
        }
    }

    nonisolated static func collectLANDiscoveryMatchesByPort(
        hosts: [String],
        pairingPorts: [Int],
        timeoutSec: TimeInterval
    ) async -> HubLANDiscoveryMultiPortProbeCollection {
        guard !hosts.isEmpty, !pairingPorts.isEmpty else {
            return HubLANDiscoveryMultiPortProbeCollection(
                matchesByPort: [:],
                localNetworkAccessDenied: false
            )
        }

        return await withTaskGroup(of: (Int, HubLANDiscoveryProbeCollection).self) { group in
            for pairingPort in pairingPorts {
                group.addTask {
                    let matches = await collectLANDiscoveryMatches(
                        hosts: hosts,
                        pairingPort: pairingPort,
                        timeoutSec: timeoutSec
                    )
                    return (pairingPort, matches)
                }
            }

            var matchesByPort: [Int: [HubLANDiscoveryProbeMatch]] = [:]
            var localNetworkAccessDenied = false
            while let (pairingPort, result) = await group.next() {
                matchesByPort[pairingPort] = result.matches
                if result.localNetworkAccessDenied {
                    localNetworkAccessDenied = true
                }
            }
            return HubLANDiscoveryMultiPortProbeCollection(
                matchesByPort: matchesByPort,
                localNetworkAccessDenied: localNetworkAccessDenied
            )
        }
    }

    nonisolated static func probeLANPairingEndpoint(
        host: String,
        pairingPort: Int,
        timeoutSec: TimeInterval
    ) async -> HubLANDiscoveryProbeOutcome {
        guard let url = URL(string: "http://\(host):\(pairingPort)/pairing/discovery") else {
            return HubLANDiscoveryProbeOutcome(match: nil, localNetworkAccessDenied: false)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutSec
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await performLANDiscoveryRequest(request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                return HubLANDiscoveryProbeOutcome(match: nil, localNetworkAccessDenied: false)
            }
            let payload = try JSONDecoder().decode(HubPairingDiscoveryPayload.self, from: data)
            guard payload.matchesPairingService else {
                return HubLANDiscoveryProbeOutcome(match: nil, localNetworkAccessDenied: false)
            }

            let matchedHost = normalizedTrimmed(payload.hubHostHint) ?? host
            return HubLANDiscoveryProbeOutcome(
                match: HubLANDiscoveryProbeMatch(
                    host: matchedHost,
                    pairingPort: payload.pairingPort ?? pairingPort,
                    grpcPort: payload.grpcPort ?? 50051,
                    internetHost: reusableDiscoveredInternetHost(payload.internetHostHint),
                    hubInstanceID: normalizedTrimmed(payload.hubInstanceID),
                    lanDiscoveryName: normalizedTrimmed(payload.lanDiscoveryName),
                    pairingProfileEpoch: payload.pairingProfileEpoch,
                    routePackVersion: normalizedTrimmed(payload.routePackVersion)
                ),
                localNetworkAccessDenied: false
            )
        } catch {
            return HubLANDiscoveryProbeOutcome(
                match: nil,
                localNetworkAccessDenied: isLocalNetworkAccessDenied(error)
            )
        }
    }

    nonisolated static func isLocalNetworkAccessDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EPERM) {
            return true
        }
        let description = nsError.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return description.contains("operation not permitted")
    }

    nonisolated static func reusableDiscoveredInternetHost(_ raw: String?) -> String? {
        guard let host = normalizedTrimmed(raw),
              HubRemoteHostPolicy.isDirectInternetRemoteHost(host) else {
            return nil
        }
        return host
    }

    nonisolated static func performLANDiscoveryRequest(
        _ request: URLRequest
    ) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = lanDiscoveryURLSession.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(
                        throwing: URLError(.badServerResponse)
                    )
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }

    nonisolated static func shouldIncludeLANDiscoveryInterface(
        name rawName: String,
        flags: Int32
    ) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return false }
        guard (flags & IFF_UP) != 0 else { return false }
        guard (flags & IFF_RUNNING) != 0 else { return false }
        guard (flags & IFF_LOOPBACK) == 0 else { return false }
        guard (flags & IFF_POINTOPOINT) == 0 else { return false }
        if lanDiscoveryInterfaceSkipPrefixes.contains(where: { name.hasPrefix($0) }) {
            return false
        }
        return true
    }

    nonisolated static func ipv4UInt32(from sockaddrPointer: UnsafeMutablePointer<sockaddr>) -> UInt32? {
        guard sockaddrPointer.pointee.sa_family == UInt8(AF_INET) else { return nil }
        return sockaddrPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
            UInt32(bigEndian: pointer.pointee.sin_addr.s_addr)
        }
    }

    nonisolated static func ipv4UInt32(_ host: String) -> UInt32? {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { UInt32($0) }
        guard octets.count == 4, octets.allSatisfy({ $0 <= 255 }) else { return nil }
        return (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]
    }

    nonisolated static func ipv4Mask(prefixLength: Int) -> UInt32? {
        guard (0...32).contains(prefixLength) else { return nil }
        if prefixLength == 0 { return 0 }
        return UInt32.max << (32 - UInt32(prefixLength))
    }

    nonisolated static func ipv4String(_ address: UInt32) -> String {
        [
            String((address >> 24) & 0xFF),
            String((address >> 16) & 0xFF),
            String((address >> 8) & 0xFF),
            String(address & 0xFF),
        ].joined(separator: ".")
    }

    nonisolated static func lanDiscoveryPairingPorts(
        _ pairingPorts: [Int],
        cachedPairing: HubCachedPairingInfo,
        configuredInternetHost: String?
    ) -> [Int] {
        let ordered = orderedUniquePairingPorts(pairingPorts)
        let hasAuthoritativeRemoteState =
            normalizedTrimmed(configuredInternetHost) != nil
            || normalizedTrimmed(cachedPairing.host) != nil
            || normalizedTrimmed(cachedPairing.internetHost) != nil
            || cachedPairing.pairingPort != nil
            || normalizedTrimmed(cachedPairing.hubInstanceID) != nil
        if hasAuthoritativeRemoteState {
            return ordered
        }
        return orderedUniquePairingPorts([50054] + ordered)
    }

    nonisolated static func lanDiscoveryPriorityHostWindow(
        _ hosts: [String],
        limitPerSubnet: Int
    ) -> [String] {
        guard limitPerSubnet > 0 else { return hosts }
        var countsBySubnet: [String: Int] = [:]
        var prioritized: [String] = []
        for host in hosts {
            let subnet = ipv4SubnetKey(host) ?? host.lowercased()
            let count = countsBySubnet[subnet, default: 0]
            guard count < limitPerSubnet else { continue }
            countsBySubnet[subnet] = count + 1
            prioritized.append(host)
        }
        return prioritized
    }

    nonisolated static func remainingLANDiscoveryHosts(
        _ hosts: [String],
        excluding prioritizedHosts: [String]
    ) -> [String] {
        let excluded = Set(prioritizedHosts.map { $0.lowercased() })
        return hosts.filter { !excluded.contains($0.lowercased()) }
    }

    nonisolated static func ipv4SubnetKey(_ host: String) -> String? {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return parts.dropLast().joined(separator: ".")
    }

    nonisolated static func currentMachineIPv4Hosts() -> Set<String> {
        var hosts: Set<String> = ["127.0.0.1", "localhost"]
        var cursor: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&cursor) == 0, let first = cursor else {
            return hosts
        }
        defer { freeifaddrs(cursor) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = current {
            defer { current = pointer.pointee.ifa_next }
            let entry = pointer.pointee
            guard let addr = entry.ifa_addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard let addressValue = ipv4UInt32(from: addr) else { continue }
            hosts.insert(ipv4String(addressValue).lowercased())
        }
        return hosts
    }

    func defaultStateDir() -> URL {
        XTProcessPaths.activeAxhubStateDir()
    }

    func normalizedRemoteAuxTimeoutSec(_ raw: Double) -> Double {
        let clamped = max(0.8, min(6.0, raw))
        return max(0.8, min(6.0, clamped + 0.25))
    }

    func loadCachedPairingInfo(stateDir: URL?) -> HubCachedPairingInfo {
        let cached = HubAIClient.cachedRemoteProfile(stateDir: stateDir ?? defaultStateDir())
        return HubCachedPairingInfo(
            host: cached.host,
            internetHost: cached.internetHost,
            pairingPort: cached.pairingPort,
            grpcPort: cached.grpcPort,
            hubInstanceID: cached.hubInstanceID,
            lanDiscoveryName: cached.lanDiscoveryName,
            pairingProfileEpoch: cached.pairingProfileEpoch,
            routePackVersion: cached.routePackVersion
        )
    }

    func expandTilde(_ text: String) -> String {
        NSString(string: text).expandingTildeInPath
    }

    func nonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func positiveInt(_ text: String?) -> Int? {
        guard let value = nonEmpty(text), let number = Int(value), number > 0 else { return nil }
        return number
    }

    func shouldAttemptLANDiscovery(
        options: HubRemoteConnectOptions,
        cachedPairing: HubCachedPairingInfo,
        allowConfiguredHostRepair: Bool
    ) -> Bool {
        Self.shouldRunLANDiscoveryPrepassValue(
            configuredInternetHost: options.internetHost,
            cachedPairing: cachedPairing,
            allowConfiguredHostRepair: allowConfiguredHostRepair,
            configuredEndpointIsAuthoritative: options.configuredEndpointIsAuthoritative,
            inviteAlias: options.inviteAlias,
            inviteInstanceID: options.inviteInstanceID
        )
    }

    func shouldAttemptLANSubnetFallbackScan(
        options: HubRemoteConnectOptions,
        cachedPairing: HubCachedPairingInfo,
        allowConfiguredHostRepair: Bool
    ) -> Bool {
        Self.shouldAttemptLANSubnetFallbackScanValue(
            configuredInternetHost: options.internetHost,
            cachedPairing: cachedPairing,
            allowConfiguredHostRepair: allowConfiguredHostRepair,
            configuredEndpointIsAuthoritative: options.configuredEndpointIsAuthoritative,
            inviteAlias: options.inviteAlias,
            inviteInstanceID: options.inviteInstanceID
        )
    }

    nonisolated static func shouldRunLANDiscoveryPrepassValue(
        configuredInternetHost: String,
        cachedPairing: HubCachedPairingInfo,
        allowConfiguredHostRepair: Bool,
        configuredEndpointIsAuthoritative: Bool,
        inviteAlias: String = "",
        inviteInstanceID: String = ""
    ) -> Bool {
        _ = inviteAlias
        _ = inviteInstanceID
        if shouldHonorConfiguredEndpointAuthority(
            configuredInternetHost: configuredInternetHost,
            configuredEndpointIsAuthoritative: configuredEndpointIsAuthoritative
        ) {
            return false
        }
        if !shouldRequireConfiguredHubHost(configuredInternetHost) {
            return true
        }
        guard allowConfiguredHostRepair else { return false }
        return hasRecoverableCachedPairing(cachedPairing)
    }

    nonisolated static func shouldAttemptLANSubnetFallbackScanValue(
        configuredInternetHost: String,
        cachedPairing: HubCachedPairingInfo,
        allowConfiguredHostRepair: Bool,
        configuredEndpointIsAuthoritative: Bool,
        inviteAlias: String = "",
        inviteInstanceID: String = ""
    ) -> Bool {
        guard shouldRunLANDiscoveryPrepassValue(
            configuredInternetHost: configuredInternetHost,
            cachedPairing: cachedPairing,
            allowConfiguredHostRepair: allowConfiguredHostRepair,
            configuredEndpointIsAuthoritative: configuredEndpointIsAuthoritative,
            inviteAlias: inviteAlias,
            inviteInstanceID: inviteInstanceID
        ) else {
            return false
        }

        // Formal remote hosts are authoritative and should not fan out into LAN
        // subnet sweeps. Raw/.local entries are allowed because same-Wi-Fi hubs
        // can legitimately move between nearby DHCP segments.
        if let configuredHost = normalizedTrimmed(configuredInternetHost),
           HubRemoteHostPolicy.isFormalRemoteHost(configuredHost) {
            return false
        }

        if normalizedTrimmed(configuredInternetHost) == nil,
           !discoveryIdentityHostCandidates(
            inviteAlias: inviteAlias,
            inviteInstanceID: inviteInstanceID
           ).isEmpty {
            return false
        }

        return true
    }

    nonisolated static func shouldHonorConfiguredEndpointAuthority(
        configuredInternetHost: String,
        configuredEndpointIsAuthoritative: Bool
    ) -> Bool {
        guard configuredEndpointIsAuthoritative else { return false }
        let configured = configuredInternetHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !configured.isEmpty else { return false }
        return configured != "localhost" && configured != "127.0.0.1"
    }

    nonisolated static func shouldRequireConfiguredHubHost(_ configuredHost: String) -> Bool {
        let configured = configuredHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if configured.isEmpty { return false }
        let normalized = configured.lowercased()
        if normalized == "localhost" || normalized == "127.0.0.1" {
            return false
        }
        return !currentMachineIPv4Hosts().contains(normalized)
    }

    nonisolated static func shouldPinDiscoveredHostToConfiguredRemote(_ configuredHost: String) -> Bool {
        guard let configured = normalizedTrimmed(configuredHost) else { return false }
        return HubRemoteHostPolicy.isFormalRemoteHost(configured)
    }

    nonisolated static func hasRecoverableCachedPairing(_ cachedPairing: HubCachedPairingInfo) -> Bool {
        if normalizedTrimmed(cachedPairing.host) != nil { return true }
        if normalizedTrimmed(cachedPairing.internetHost) != nil { return true }
        if cachedPairing.pairingPort != nil { return true }
        if cachedPairing.grpcPort != nil { return true }
        if normalizedTrimmed(cachedPairing.hubInstanceID) != nil { return true }
        if normalizedTrimmed(cachedPairing.lanDiscoveryName) != nil { return true }
        return false
    }

    nonisolated static func orderedUniquePairingPorts(_ pairingPorts: [Int]) -> [Int] {
        var ordered: [Int] = []
        for pairingPort in pairingPorts {
            let clamped = max(1, min(65_535, pairingPort))
            if !ordered.contains(clamped) {
                ordered.append(clamped)
            }
        }
        return ordered
    }

    func orderedUniqueNonEmptyStrings(_ values: [String?]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            guard let normalized = nonEmpty(value) else { continue }
            let dedupeKey = normalized.lowercased()
            guard seen.insert(dedupeKey).inserted else { continue }
            ordered.append(normalized)
        }
        return ordered
    }

    func normalizePort(_ raw: String?) -> Int? {
        guard let value = nonEmpty(raw), let p = Int(value), (1...65_535).contains(p) else {
            return nil
        }
        return p
    }

    func inferredReusableInternetHost(
        _ host: String?,
        hubInstanceID: String? = nil,
        lanDiscoveryName: String? = nil
    ) -> String? {
        Self.inferredReusableInternetHostValue(
            host,
            hubInstanceID: hubInstanceID,
            lanDiscoveryName: lanDiscoveryName
        )
    }

    static func inferredReusableInternetHostValue(
        _ host: String?,
        hubInstanceID: String? = nil,
        lanDiscoveryName: String? = nil
    ) -> String? {
        HubRemoteHostPolicy.inferredReusableInternetHost(
            from: host,
            hubInstanceID: hubInstanceID,
            lanDiscoveryName: lanDiscoveryName
        )
    }

    static func isIPv4Host(_ host: String) -> Bool {
        HubRemoteHostPolicy.isIPv4Host(host)
    }

    static func isPrivateIPv4Host(_ host: String) -> Bool {
        HubRemoteHostPolicy.isPrivateIPv4Host(host)
    }

    nonisolated static func remotePresenceTransportMode(for route: HubRemoteRoute) -> String {
        switch route {
        case .lan:
            return "hub_grpc_lan"
        case .internet:
            return "hub_grpc_internet"
        case .internetTunnel:
            return "hub_grpc_tunnel"
        case .none:
            return "hub_grpc_unknown"
        }
    }

    nonisolated static func nonEmptyValue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func normalizePortValue(_ raw: String?) -> Int? {
        guard let value = nonEmptyValue(raw),
              let port = Int(value),
              (1...65_535).contains(port) else {
            return nil
        }
        return port
    }

    func readEnvValue(from fileURL: URL, key: String) -> String? {
        Self.readEnvValueFast(from: fileURL, key: key)
    }

    static func readEnvValueFast(from fileURL: URL, key: String) -> String? {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            var candidate = trimmed
            if candidate.hasPrefix("export ") {
                candidate = String(candidate.dropFirst("export ".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let eq = candidate.firstIndex(of: "=") else { continue }
            let lhs = String(candidate[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard lhs == key else { continue }
            let rhs = String(candidate[candidate.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return unquoteShellValueFast(rhs)
        }
        return nil
    }

    func unquoteShellValue(_ value: String) -> String {
        Self.unquoteShellValueFast(value)
    }

    static func unquoteShellValueFast(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    func shellSingleQuoted(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    nonisolated static func normalizedTrimmed(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    func discoveryEnv(
        internetHost: String,
        cachedPairing: HubCachedPairingInfo? = nil,
        inviteAlias: String = "",
        inviteInstanceID: String = "",
        hasAuthoritativeLocalProfile: Bool = false
    ) -> [String: String] {
        let hints = Self.discoveryHintCandidatesValue(
            configuredInternetHost: internetHost,
            cachedPairing: cachedPairing,
            inviteAlias: inviteAlias,
            inviteInstanceID: inviteInstanceID,
            hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile
        )
        return ["HUB_DISCOVERY_HINTS": hints.joined(separator: ",")]
    }

    func configuredDiscoverHintArgs(options: HubRemoteConnectOptions) -> [String] {
        guard let host = nonEmpty(options.internetHost) else { return [] }
        return ["--hints", host]
    }

    nonisolated static func discoveryHintCandidatesValue(
        configuredInternetHost: String,
        cachedPairing: HubCachedPairingInfo? = nil,
        inviteAlias: String = "",
        inviteInstanceID: String = "",
        hasAuthoritativeLocalProfile: Bool = false
    ) -> [String] {
        let currentMachineHosts = currentMachineIPv4Hosts()
        let allowLoopbackHints = shouldAllowLocalDiscoveryHost(
            configuredInternetHost: configuredInternetHost,
            cachedPairing: cachedPairing ?? HubCachedPairingInfo(
                host: nil,
                internetHost: nil,
                pairingPort: nil,
                grpcPort: nil,
                hubInstanceID: nil,
                lanDiscoveryName: nil
            ),
            hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile,
            currentMachineHosts: currentMachineHosts
        )
        var seen = Set<String>()
        var ordered: [String] = []

        func append(_ raw: String?) {
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { return }
            if isCurrentMachineHost(trimmed, currentMachineHosts: currentMachineHosts),
               !allowLoopbackHints {
                return
            }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return }
            ordered.append(trimmed)
        }

        append(configuredInternetHost)
        append(cachedPairing?.internetHost)
        for hostHint in discoveryIdentityHostCandidates(
            inviteAlias: inviteAlias,
            inviteInstanceID: inviteInstanceID
        ) {
            append(hostHint)
        }
        append(cachedPairing?.host)
        append(discoveryBonjourHintValue(cachedPairing?.lanDiscoveryName))
        if allowLoopbackHints {
            append("127.0.0.1")
            append("localhost")
        }
        return ordered
    }

    nonisolated static func preferredDiscoveryHostsValue(
        configuredInternetHost: String,
        cachedPairing: HubCachedPairingInfo,
        inviteAlias: String = "",
        inviteInstanceID: String = "",
        hasAuthoritativeLocalProfile: Bool,
        currentMachineHosts: Set<String>
    ) -> [String] {
        let allowLoopback = shouldAllowLocalDiscoveryHost(
            configuredInternetHost: configuredInternetHost,
            cachedPairing: cachedPairing,
            hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile,
            currentMachineHosts: currentMachineHosts
        )
        var stableRemote: [String] = []
        var localNamed: [String] = []
        var directLocal: [String] = []
        var fallback: [String] = []
        var seen = Set<String>()

        func append(_ raw: String?) {
            guard let host = normalizedTrimmed(raw) else { return }
            let key = host.lowercased()
            guard seen.insert(key).inserted else { return }

            if isCurrentMachineHost(host, currentMachineHosts: currentMachineHosts) {
                guard allowLoopback else { return }
                directLocal.append(host)
                return
            }
            if HubRemoteHostPolicy.isFormalRemoteHost(host) {
                stableRemote.append(host)
                return
            }
            if host.lowercased().hasSuffix(".local") {
                localNamed.append(host)
                return
            }
            if HubRemoteHostPolicy.isDirectLocalFallbackHost(host) {
                directLocal.append(host)
                return
            }
            fallback.append(host)
        }

        append(configuredInternetHost)
        append(cachedPairing.internetHost)
        for hostHint in discoveryIdentityHostCandidates(
            inviteAlias: inviteAlias,
            inviteInstanceID: inviteInstanceID
        ) {
            append(hostHint)
        }
        append(discoveryBonjourHintValue(cachedPairing.lanDiscoveryName))
        append(cachedPairing.host)
        if allowLoopback {
            append("127.0.0.1")
            append("localhost")
        }
        return stableRemote + localNamed + directLocal + fallback
    }

    nonisolated static func discoveryIdentityHostCandidates(
        inviteAlias: String,
        inviteInstanceID: String
    ) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        func append(_ raw: String?) {
            guard let candidate = normalizedTrimmed(raw) else { return }
            let key = candidate.lowercased()
            guard seen.insert(key).inserted else { return }
            ordered.append(candidate)
        }

        append(normalizedHostLikeInviteAlias(inviteAlias))
        append(discoveryBonjourHintValue(derivedHubLanDiscoveryName(from: inviteInstanceID)))
        return ordered
    }

    nonisolated static func normalizedHostLikeInviteAlias(_ raw: String?) -> String? {
        guard let alias = normalizedTrimmed(raw) else { return nil }
        if alias.lowercased().hasPrefix("axhub-") {
            return discoveryBonjourHintValue(alias)
        }
        if alias.contains(".") || HubRemoteHostPolicy.isIPv4Host(alias) {
            return alias
        }
        return nil
    }

    nonisolated static func derivedHubLanDiscoveryName(from hubInstanceID: String?) -> String? {
        guard let instanceID = normalizedDiscoveryTokenValue(hubInstanceID),
              instanceID.hasPrefix("hub_") else {
            return nil
        }
        let suffix = String(instanceID.dropFirst(4))
        let hexSuffix = suffix.filter { scalar in
            switch scalar {
            case "0"..."9", "a"..."f":
                return true
            default:
                return false
            }
        }
        guard hexSuffix.count >= 10 else { return nil }
        return "axhub-\(hexSuffix.prefix(10))"
    }

    nonisolated static func shouldAllowLocalDiscoveryHost(
        configuredInternetHost: String,
        cachedPairing: HubCachedPairingInfo,
        hasAuthoritativeLocalProfile: Bool,
        currentMachineHosts: Set<String>
    ) -> Bool {
        if let configuredHost = normalizedTrimmed(configuredInternetHost),
           isCurrentMachineHost(configuredHost, currentMachineHosts: currentMachineHosts) {
            return true
        }
        guard hasAuthoritativeLocalProfile else { return false }
        if let cachedHost = normalizedTrimmed(cachedPairing.host),
           isCurrentMachineHost(cachedHost, currentMachineHosts: currentMachineHosts) {
            return true
        }
        if let cachedInternetHost = normalizedTrimmed(cachedPairing.internetHost),
           isCurrentMachineHost(cachedInternetHost, currentMachineHosts: currentMachineHosts) {
            return true
        }
        return false
    }

    nonisolated static func hasAuthoritativeLocalPairingState(
        cachedPairing: HubCachedPairingInfo,
        currentMachineHosts: Set<String>
    ) -> Bool {
        let localHostBound = [
            normalizedTrimmed(cachedPairing.host),
            normalizedTrimmed(cachedPairing.internetHost),
        ]
        .compactMap { $0 }
        .contains { isCurrentMachineHost($0, currentMachineHosts: currentMachineHosts) }
        guard localHostBound else { return false }

        if cachedPairing.pairingPort != nil || cachedPairing.grpcPort != nil {
            return true
        }
        if normalizedDiscoveryTokenValue(cachedPairing.hubInstanceID) != nil {
            return true
        }
        if normalizedTrimmed(cachedPairing.lanDiscoveryName) != nil {
            return true
        }
        if cachedPairing.pairingProfileEpoch != nil {
            return true
        }
        if normalizedTrimmed(cachedPairing.routePackVersion) != nil {
            return true
        }
        return false
    }

    nonisolated static func shouldIgnoreDiscoveredLoopbackCandidate(
        discoveredHost: String?,
        configuredInternetHost: String,
        cachedPairing: HubCachedPairingInfo,
        hasAuthoritativeLocalProfile: Bool,
        currentMachineHosts: Set<String>
    ) -> Bool {
        guard let discoveredHost = normalizedTrimmed(discoveredHost) else { return false }
        guard isCurrentMachineHost(discoveredHost, currentMachineHosts: currentMachineHosts) else {
            return false
        }
        return !shouldAllowLocalDiscoveryHost(
            configuredInternetHost: configuredInternetHost,
            cachedPairing: cachedPairing,
            hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile,
            currentMachineHosts: currentMachineHosts
        )
    }

    nonisolated static func discoveryBonjourHintValue(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased().hasSuffix(".local") ? trimmed : "\(trimmed).local"
    }
}
