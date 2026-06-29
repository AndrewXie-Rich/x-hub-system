import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

actor HubPairingCoordinator {
    static let shared = HubPairingCoordinator()
    static let remoteModelsListTimeoutSec = 12.0
    static let remoteClientInstallTimeoutSec = 25.0
    private static let remoteDevicePresenceTimeoutSec = 3.0
    static let pairingDiscoveryProbeTimeoutSec = 1.0
    static let lanDiscoveryFallbackProbeTimeoutSec = pairingDiscoveryProbeTimeoutSec
    static let maxConcurrentLANDiscoveryProbes = 48
    static let lanDiscoveryPriorityHostsPerSubnet = 128
    static let localNetworkPermissionRequiredReason = "local_network_permission_required"
    static let localNetworkDiscoveryBlockedReason = "local_network_discovery_blocked"
    static let remoteGenerateDefaultTimeoutSec = 120.0
    static let remoteGenerateMinTimeoutSec = 8.0
    static let remoteGenerateMaxTimeoutSec = 240.0
    static let remoteGenerateProcessGraceSec = 20.0
    static let lanDiscoveryInterfaceSkipPrefixes = [
        "utun",
        "awdl",
        "llw",
        "bridge",
        "anpi",
        "p2p",
        "ipsec",
        "gif",
        "stf",
        "vmnet"
    ]
    static let lanDiscoveryURLSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }()

    static func normalizedRemoteGenerateTimeoutSec(_ raw: Double) -> Double {
        guard raw.isFinite, raw > 0 else { return remoteGenerateDefaultTimeoutSec }
        return max(remoteGenerateMinTimeoutSec, min(remoteGenerateMaxTimeoutSec, raw))
    }

    static func hasHubEnvFast(stateDir: URL?) -> Bool {
        let base = stateDir ?? XTProcessPaths.activeAxhubStateDir()
        let env = base.appendingPathComponent("hub.env")
        guard FileManager.default.fileExists(atPath: env.path) else { return false }
        let token = readEnvValueFast(from: env, key: "HUB_CLIENT_TOKEN") ?? ""
        return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func hasHubEnv(stateDir: URL?) -> Bool {
        Self.hasHubEnvFast(stateDir: stateDir)
    }

    func sendRemoteDevicePresence(
        route: HubRemoteRoute,
        stateDir: URL?,
        deviceName fallbackDeviceName: String?
    ) async -> Bool {
        let base = stateDir ?? defaultStateDir()
        let hubEnv = base.appendingPathComponent("hub.env")
        let pairingEnv = base.appendingPathComponent("pairing.env")
        guard FileManager.default.fileExists(atPath: hubEnv.path) else { return false }

        let cached = synchronizedCachedPairingInfo(
            stateDir: base,
            fallbackDeviceName: fallbackDeviceName
        ).pairing
        let host = Self.preferredPresenceHostValue(
            route: route,
            cachedHost: cached.host,
            cachedInternetHost: cached.internetHost,
            currentMachineHosts: Self.currentMachineIPv4Hosts()
        )
        guard let host, !host.isEmpty else { return false }

        let pairingPort = cached.pairingPort
            ?? HubPairingCoordinator.normalizePortValue(readEnvValue(from: pairingEnv, key: "AXHUB_PAIRING_PORT"))
            ?? HubPairingCoordinator.normalizePortValue(readEnvValue(from: hubEnv, key: "HUB_PAIRING_PORT"))
            ?? 50052
        let token = readEnvValue(from: hubEnv, key: "HUB_CLIENT_TOKEN") ?? ""
        guard let nonEmptyToken = nonEmpty(token) else { return false }

        let appID = canonicalHubAppID(readEnvValue(from: hubEnv, key: "HUB_APP_ID"))
            ?? canonicalHubAppID(readEnvValue(from: pairingEnv, key: "AXHUB_APP_ID"))
            ?? "x_terminal"
        let deviceName = nonEmpty(readEnvValue(from: pairingEnv, key: "AXHUB_DEVICE_NAME"))
            ?? nonEmpty(fallbackDeviceName)
            ?? Host.current().localizedName
            ?? "X-Terminal"

        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = pairingPort
        components.path = "/clients/presence"
        guard let url = components.url else { return false }

        let payload: [String: String] = [
            "app_id": appID,
            "device_name": deviceName,
            "route": route.rawValue,
            "transport_mode": HubPairingCoordinator.remotePresenceTransportMode(for: route),
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.remoteDevicePresenceTimeoutSec
        request.setValue("Bearer \(nonEmptyToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    func suggestedAxhubctlPath(override rawOverride: String = "") -> String? {
        let override = rawOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = resolveAxhubctlExecutable(override: override)
        switch resolved {
        case .direct(let path):
            return path
        case .bashScript(let path):
            return path
        case .viaEnv:
            return nil
        }
    }


    func detectPorts(
        options rawOptions: HubRemoteConnectOptions,
        candidates rawCandidates: [Int] = [50052, 50053, 50054, 50055, 50056]
    ) async -> HubRemotePortProbeResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let hasEnv = hasHubEnv(stateDir: opts.stateDir)
        let cachedPairingLoad = synchronizedCachedPairingInfo(
            stateDir: opts.stateDir,
            fallbackDeviceName: opts.deviceName
        )
        let cachedPairing = cachedPairingLoad.pairing
        let currentMachineHosts = Self.currentMachineIPv4Hosts()
        let hasAuthoritativeLocalProfile = hasEnv || Self.hasAuthoritativeLocalPairingState(
            cachedPairing: cachedPairing,
            currentMachineHosts: currentMachineHosts
        )
        logs.append(contentsOf: cachedPairingLoad.logLines)
        let customEnv = discoveryEnv(
            internetHost: opts.internetHost,
            cachedPairing: cachedPairing,
            inviteAlias: opts.inviteAlias,
            inviteInstanceID: opts.inviteInstanceID,
            hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile
        )

        let normalized = rawCandidates
            .map { max(1, min(65_535, $0)) }
        let candidates = Array(Set(normalized)).sorted()
        if candidates.isEmpty {
            return HubRemotePortProbeResult(
                ok: false,
                pairingPort: opts.pairingPort,
                grpcPort: opts.grpcPort,
                reasonCode: "no_port_candidates",
                candidates: [],
                logLines: ["port probe candidates are empty"]
            )
        }

        var lastOutput = ""
        var discoverUnsupported = false
        let knownHostProbe = await discoverHubViaKnownHosts(
            options: opts,
            pairingPorts: candidates,
            cachedPairing: cachedPairing,
            hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile
        )
        logs.append(contentsOf: knownHostProbe.logLines)
        if let candidate = knownHostProbe.candidate {
            return HubRemotePortProbeResult(
                ok: true,
                pairingPort: candidate.pairingPort,
                grpcPort: candidate.grpcPort,
                reasonCode: nil,
                candidates: [summary(from: candidate)],
                logLines: logs
            )
        }
        if let blockedReason = knownHostProbe.reasonCode {
            return HubRemotePortProbeResult(
                ok: false,
                pairingPort: opts.pairingPort,
                grpcPort: opts.grpcPort,
                reasonCode: blockedReason,
                candidates: knownHostProbe.candidates.map(summary(from:)),
                logLines: logs
            )
        }

        if shouldAttemptLANDiscovery(
            options: opts,
            cachedPairing: cachedPairing,
            allowConfiguredHostRepair: true
        ) {
            let lanFallback = await discoverHubOnLAN(
                options: opts,
                pairingPorts: candidates,
                cachedPairing: cachedPairing,
                allowConfiguredHostRepair: true
            )
            logs.append(contentsOf: lanFallback.logLines)
            if let candidate = lanFallback.candidate {
                return HubRemotePortProbeResult(
                    ok: true,
                    pairingPort: candidate.pairingPort,
                    grpcPort: candidate.grpcPort,
                    reasonCode: nil,
                    candidates: [summary(from: candidate)],
                    logLines: logs
                )
            }
            if let blockedReason = lanFallback.reasonCode {
                return HubRemotePortProbeResult(
                    ok: false,
                    pairingPort: opts.pairingPort,
                    grpcPort: opts.grpcPort,
                    reasonCode: blockedReason,
                    candidates: lanFallback.candidates.map(summary(from:)),
                    logLines: logs
                )
            }
        }

        let probeStateDir = makeEphemeralStateDir(prefix: "xterminal_port_probe")
        logs.append(contentsOf: prepareDiscoveryProbeState(
            sourceStateDir: opts.stateDir,
            probeStateDir: probeStateDir,
            fallbackDeviceName: opts.deviceName
        ))
        var probeOptions = opts
        probeOptions.stateDir = probeStateDir
        for p in candidates {
            let step = runAxhubctl(
                args: [
                    "discover",
                    "--pairing-port", "\(p)",
                    "--timeout-sec", "2",
                ] + configuredDiscoverHintArgs(options: probeOptions),
                options: probeOptions,
                env: customEnv,
                timeoutSec: 12.0
            )
            appendStepLogs(into: &logs, step: step)
            lastOutput = step.output
            if step.exitCode == 0 {
                let parsedHost = parseStringField(step.output, fieldName: "host")
                if let parsedHost,
                   Self.isCurrentMachineHost(
                    parsedHost,
                    currentMachineHosts: currentMachineHosts
                   ),
                   shouldRequireConfiguredHubHost(options: opts) {
                    logs.append("[port-detect] ignore local XT Hub candidate while repairing remote host (got \(parsedHost))")
                    continue
                }
                if shouldPinDiscoveredHostToConfiguredRemote(options: opts),
                   !hostMatchesConfiguredHost(discoveredHost: parsedHost, options: opts) {
                    logs.append("[port-detect] ignore host mismatch (want \(opts.internetHost), got \(parsedHost ?? "unknown"))")
                    continue
                }
                if Self.shouldIgnoreDiscoveredLoopbackCandidate(
                    discoveredHost: parsedHost,
                    configuredInternetHost: opts.internetHost,
                    cachedPairing: cachedPairing,
                    hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile,
                    currentMachineHosts: currentMachineHosts
                ) {
                    logs.append("[port-detect] ignore loopback candidate without authoritative local pairing state (got \(parsedHost ?? "unknown"))")
                    continue
                }
                guard let rawCandidate = parsedRawDiscoveryCandidate(
                    from: step.output,
                    defaultPairingPort: p,
                    defaultGRPCPort: opts.grpcPort,
                    fallbackHost: parsedHost ?? nonEmpty(opts.internetHost) ?? nonEmpty(cachedPairing.host),
                    fallbackInternetHost: nonEmpty(opts.internetHost) ?? nonEmpty(cachedPairing.internetHost)
                ) else {
                    continue
                }
                let parsedCandidate = finalizedDiscoveryCandidate(rawCandidate, cachedPairing: cachedPairing)
                if let repairBlock = pairingMetadataRepairBlock(
                    cachedPairing: cachedPairing,
                    discoveredCandidate: parsedCandidate,
                    source: "port-detect"
                ) {
                    logs.append(repairBlock.detailLine)
                    removeEphemeralStateDir(probeStateDir)
                    return HubRemotePortProbeResult(
                        ok: false,
                        pairingPort: opts.pairingPort,
                        grpcPort: opts.grpcPort,
                        reasonCode: repairBlock.reasonCode,
                        candidates: [summary(from: parsedCandidate)],
                        logLines: logs
                    )
                }
                logs.append(contentsOf: persistDiscoveryCandidate(parsedCandidate, options: opts, source: "port-detect"))
                removeEphemeralStateDir(probeStateDir)
                return HubRemotePortProbeResult(
                    ok: true,
                    pairingPort: parsedCandidate.pairingPort,
                    grpcPort: parsedCandidate.grpcPort,
                    reasonCode: nil,
                    candidates: [summary(from: parsedCandidate)],
                    logLines: logs
                )
            } else if isUnknownCommand(step.output, command: "discover") {
                discoverUnsupported = true
                break
            }
        }
        removeEphemeralStateDir(probeStateDir)

        if discoverUnsupported {
            if let pair = cachedPairing.pairingPort,
               let grpc = cachedPairing.grpcPort {
                return HubRemotePortProbeResult(
                    ok: true,
                    pairingPort: pair,
                    grpcPort: grpc,
                    reasonCode: nil,
                    candidates: [],
                    logLines: logs + ["[port-detect] discover unsupported; using cached pairing/grpc ports."]
                )
            }
            if nonEmpty(opts.internetHost) != nil {
                return HubRemotePortProbeResult(
                    ok: true,
                    pairingPort: opts.pairingPort,
                    grpcPort: opts.grpcPort,
                    reasonCode: nil,
                    candidates: [],
                    logLines: logs + ["[port-detect] discover unsupported; keep configured ports."]
                )
            }
            return HubRemotePortProbeResult(
                ok: false,
                pairingPort: opts.pairingPort,
                grpcPort: opts.grpcPort,
                reasonCode: "discover_unsupported",
                candidates: [],
                logLines: logs
            )
        }

        let reason = inferFailureCode(from: lastOutput, fallback: "port_probe_failed")
        return HubRemotePortProbeResult(
            ok: false,
            pairingPort: opts.pairingPort,
            grpcPort: opts.grpcPort,
            reasonCode: reason,
            candidates: [],
            logLines: logs
        )
    }

    func pinDiscoveredHubCandidate(
        _ candidate: HubDiscoveredHubCandidateSummary,
        options rawOptions: HubRemoteConnectOptions
    ) throws {
        let opts = sanitize(rawOptions)
        try persistDiscoveredPairingInfo(
            host: candidate.host,
            pairingPort: candidate.pairingPort,
            grpcPort: candidate.grpcPort,
            internetHost: nonEmpty(candidate.internetHost) ?? nonEmpty(opts.internetHost),
            hubInstanceID: candidate.hubInstanceID,
            lanDiscoveryName: candidate.lanDiscoveryName,
            pairingProfileEpoch: candidate.pairingProfileEpoch,
            routePackVersion: candidate.routePackVersion,
            options: opts
        )
    }

    func resetLocalPairingState(stateDir: URL?) -> HubRemoteResetResult {
        let base = stateDir ?? defaultStateDir()
        let fm = FileManager.default
        var logs: [String] = []

        let pathsToDelete: [URL] = [
            base.appendingPathComponent("pairing.env"),
            base.appendingPathComponent("hub.env"),
            base.appendingPathComponent("connection.json"),
            base.appendingPathComponent("client_kit", isDirectory: true),
            base.appendingPathComponent("chat.env"),
            base.appendingPathComponent("tunnel.env"),
            base.appendingPathComponent("tunnel_config.env"),
            base.appendingPathComponent("tls", isDirectory: true),
        ]

        for url in pathsToDelete {
            if fm.fileExists(atPath: url.path) {
                do {
                    try fm.removeItem(at: url)
                    logs.append("removed: \(url.path)")
                } catch {
                    logs.append("remove_failed: \(url.path) (\(error.localizedDescription))")
                    return HubRemoteResetResult(
                        ok: false,
                        reasonCode: "reset_failed",
                        logLines: logs
                    )
                }
            } else {
                logs.append("skip_missing: \(url.lastPathComponent)")
            }
        }

        return HubRemoteResetResult(
            ok: true,
            reasonCode: nil,
            logLines: logs
        )
    }

    func pruneTransientRemoteRouteArtifacts(stateDir: URL?) -> [String] {
        let base = stateDir ?? defaultStateDir()
        let fm = FileManager.default
        let transientPaths: [URL] = [
            base.appendingPathComponent("connection.json"),
            base.appendingPathComponent("tunnel.env"),
            base.appendingPathComponent("tunnel_config.env"),
        ]

        var logs: [String] = []
        for url in transientPaths {
            if fm.fileExists(atPath: url.path) {
                do {
                    try fm.removeItem(at: url)
                    logs.append("[route-repair] removed transient route artifact: \(url.lastPathComponent)")
                } catch {
                    logs.append("[route-repair] remove_failed \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        return logs
    }

    func uninstallManagedTunnelService(options rawOptions: HubRemoteConnectOptions) -> [String] {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let uninstall = runAxhubctl(
            args: ["tunnel", "--uninstall"],
            options: opts,
            env: [:],
            timeoutSec: 30.0
        )
        appendStepLogs(into: &logs, step: uninstall)
        return logs
    }








}
