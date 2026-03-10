import Foundation

enum HubRemoteRoute: String, Sendable {
    case none
    case lan
    case internet
    case internetTunnel
}

struct HubRemoteConnectOptions: Sendable {
    var grpcPort: Int
    var pairingPort: Int
    var deviceName: String
    var internetHost: String
    var axhubctlPath: String
    var stateDir: URL?
}

struct HubRemoteConnectReport: Sendable {
    var ok: Bool
    var route: HubRemoteRoute
    var summary: String
    var logLines: [String]
    var reasonCode: String?

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

enum HubRemoteProgressPhase: String, Sendable {
    case discover
    case bootstrap
    case connect
}

enum HubRemoteProgressState: String, Sendable {
    case started
    case succeeded
    case failed
    case skipped
}

struct HubRemoteProgressEvent: Sendable {
    var phase: HubRemoteProgressPhase
    var state: HubRemoteProgressState
    var detail: String?
}

struct HubRemotePortProbeResult: Sendable {
    var ok: Bool
    var pairingPort: Int
    var grpcPort: Int
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteResetResult: Sendable {
    var ok: Bool
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteModelsResult: Sendable {
    var ok: Bool
    var models: [HubModel]
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteGenerateResult: Sendable {
    var ok: Bool
    var text: String
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

enum HubRemoteGrantDecision: String, Sendable {
    case approved
    case queued
    case denied
    case failed
}

struct HubRemoteGrantResult: Sendable {
    var ok: Bool
    var decision: HubRemoteGrantDecision
    var grantRequestId: String?
    var expiresAtSec: Double?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteWebFetchResult: Sendable {
    var ok: Bool
    var status: Int
    var finalURL: String
    var contentType: String
    var truncated: Bool
    var bytes: Int
    var text: String
    var errorMessage: String?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteProjectSyncPayload: Sendable {
    var projectId: String
    var rootPath: String
    var displayName: String
    var statusDigest: String?
    var lastSummaryAt: Double?
    var lastEventAt: Double?
    var updatedAt: Double?
}

struct HubRemoteNotificationPayload: Sendable {
    var source: String
    var title: String
    var body: String
    var dedupeKey: String?
    var actionURL: String?
    var unread: Bool
}

struct HubRemoteMutationResult: Sendable {
    var ok: Bool
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteMemorySnapshotResult: Sendable {
    var ok: Bool
    var source: String
    var canonicalEntries: [String]
    var workingEntries: [String]
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteSchedulerScopeCount: Sendable {
    var scopeKey: String
    var count: Int
}

struct HubRemoteSchedulerQueueItem: Sendable {
    var requestId: String
    var scopeKey: String
    var enqueuedAtMs: Double
    var queuedMs: Int
}

struct HubRemoteSchedulerStatusResult: Sendable {
    var ok: Bool
    var source: String
    var updatedAtMs: Double
    var inFlightTotal: Int
    var queueDepth: Int
    var oldestQueuedMs: Int
    var inFlightByScope: [HubRemoteSchedulerScopeCount]
    var queuedByScope: [HubRemoteSchedulerScopeCount]
    var queueItems: [HubRemoteSchedulerQueueItem]
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemotePendingGrantItem: Sendable {
    var grantRequestId: String
    var requestId: String
    var deviceId: String
    var userId: String
    var appId: String
    var projectId: String
    var capability: String
    var modelId: String
    var reason: String
    var requestedTtlSec: Int
    var requestedTokenCap: Int
    var status: String
    var decision: String
    var createdAtMs: Double
    var decidedAtMs: Double
}

struct HubRemotePendingGrantRequestsResult: Sendable {
    var ok: Bool
    var source: String
    var updatedAtMs: Double
    var items: [HubRemotePendingGrantItem]
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

enum HubRemotePendingGrantActionDecision: String, Sendable {
    case approved
    case denied
    case failed
}

struct HubRemotePendingGrantActionResult: Sendable {
    var ok: Bool
    var decision: HubRemotePendingGrantActionDecision
    var grantRequestId: String?
    var grantId: String?
    var expiresAtMs: Double?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

actor HubPairingCoordinator {
    static let shared = HubPairingCoordinator()

    func hasHubEnv(stateDir: URL?) -> Bool {
        let base = stateDir ?? defaultStateDir()
        let env = base.appendingPathComponent("hub.env")
        guard FileManager.default.fileExists(atPath: env.path) else { return false }
        let token = readEnvValue(from: env, key: "HUB_CLIENT_TOKEN") ?? ""
        return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    func ensureConnected(
        options rawOptions: HubRemoteConnectOptions,
        allowBootstrap: Bool,
        onProgress: (@Sendable (HubRemoteProgressEvent) -> Void)? = nil
    ) -> HubRemoteConnectReport {
        var opts = sanitize(rawOptions)
        var logs: [String] = []
        let customEnv = discoveryEnv(internetHost: opts.internetHost)
        var discoveredHubHost: String?
        let cachedPairing = loadCachedPairingInfo(stateDir: opts.stateDir)

        let hasEnv = hasHubEnv(stateDir: opts.stateDir)
        if allowBootstrap {
            // Always try discover during one-click setup so stale pairing ports can self-heal.
            logs.append("[1/3] Discover Hub ...")
            emit(onProgress, .discover, .started, nil)
            var discoverSuccess = false
            var discoverUnsupported = false
            var lastDiscoverOutput = ""
            let candidates = Array(Set([opts.pairingPort, 50052, 50053])).sorted()
            let probeStateDir = makeEphemeralStateDir(prefix: "xterminal_discover_probe")
            var discoverOpts = opts
            discoverOpts.stateDir = probeStateDir
            for p in candidates {
                let discover = runAxhubctl(
                    args: [
                        "discover",
                        "--pairing-port", "\(p)",
                        "--timeout-sec", "3",
                    ],
                    options: discoverOpts,
                    env: customEnv,
                    timeoutSec: 30.0
                )
                appendStepLogs(into: &logs, step: discover)
                lastDiscoverOutput = discover.output
                if discover.exitCode == 0 {
                    let parsedHost = parseStringField(discover.output, fieldName: "host")
                    if shouldRequireConfiguredHubHost(options: opts),
                       !hostMatchesConfiguredHost(discoveredHost: parsedHost, options: opts) {
                        logs.append("[discover] ignore host mismatch (want \(opts.internetHost), got \(parsedHost ?? "unknown"))")
                        continue
                    }

                    discoverSuccess = true
                    opts.pairingPort = parsePortField(discover.output, fieldName: "pairing_port") ?? p
                    opts.grpcPort = parsePortField(discover.output, fieldName: "grpc_port") ?? opts.grpcPort
                    if let parsedHost, !parsedHost.isEmpty {
                        discoveredHubHost = parsedHost
                    }
                    break
                } else if isUnknownCommand(discover.output, command: "discover") {
                    discoverUnsupported = true
                    break
                }
            }
            removeEphemeralStateDir(probeStateDir)

            if discoverSuccess {
                emit(onProgress, .discover, .succeeded, nil)
            } else if discoverUnsupported {
                if let configuredHost = nonEmpty(opts.internetHost) {
                    discoveredHubHost = configuredHost
                    logs.append("[discover] axhubctl missing discover; use configured host: \(configuredHost)")
                    emit(onProgress, .discover, .skipped, "discover_unsupported_using_configured_host")
                } else if let cachedHost = nonEmpty(cachedPairing.host) {
                    discoveredHubHost = cachedHost
                    if let pair = cachedPairing.pairingPort {
                        opts.pairingPort = pair
                    }
                    if let grpc = cachedPairing.grpcPort {
                        opts.grpcPort = grpc
                    }
                    logs.append("[discover] axhubctl missing discover; use cached host: \(cachedHost)")
                    emit(onProgress, .discover, .skipped, "discover_unsupported_using_cached_host")
                } else {
                    let reason = "discover_unsupported_need_hub_host"
                    emit(onProgress, .discover, .failed, reason)
                    emit(onProgress, .bootstrap, .skipped, "blocked_by_discover_failure")
                    emit(onProgress, .connect, .skipped, "blocked_by_discover_failure")
                    return HubRemoteConnectReport(
                        ok: false,
                        route: .none,
                        summary: reason,
                        logLines: logs,
                        reasonCode: reason
                    )
                }
            } else if shouldRequireConfiguredHubHost(options: opts) {
                // Cross-device scenario: the configured host is authoritative; do not downgrade to localhost.
                discoveredHubHost = opts.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
                logs.append("[discover] fallback to configured host: \(discoveredHubHost ?? opts.internetHost)")
                emit(onProgress, .discover, .skipped, "using_configured_hub_host")
            } else if hasEnv {
                // Existing paired profile: continue with cached profile even if discover failed.
                let reason = inferFailureCode(from: lastDiscoverOutput, fallback: "discover_failed_using_cached_profile")
                emit(onProgress, .discover, .failed, reason)
            } else {
                let reason = inferFailureCode(from: lastDiscoverOutput, fallback: "discover_failed")
                emit(onProgress, .discover, .failed, reason)
                emit(onProgress, .bootstrap, .skipped, "blocked_by_discover_failure")
                emit(onProgress, .connect, .skipped, "blocked_by_discover_failure")
                return HubRemoteConnectReport(
                    ok: false,
                    route: .none,
                    summary: reason,
                    logLines: logs,
                    reasonCode: reason
                )
            }
        } else {
            emit(onProgress, .discover, .skipped, "bootstrap_disabled")
            emit(onProgress, .bootstrap, .skipped, "bootstrap_disabled")
        }

        if allowBootstrap && !hasEnv {
            logs.append("[2/3] Pair + bootstrap (wait approval) ...")
            emit(onProgress, .bootstrap, .started, nil)
            let bootstrapHost = preferredBootstrapHub(discoveredHubHost: discoveredHubHost, options: opts)
            let bootstrap = runAxhubctl(
                args: [
                    "bootstrap",
                    "--hub", bootstrapHost,
                    "--pairing-port", "\(opts.pairingPort)",
                    "--grpc-port", "\(opts.grpcPort)",
                    "--device-name", opts.deviceName,
                ],
                options: opts,
                env: customEnv,
                timeoutSec: 1_300.0
            )
            appendStepLogs(into: &logs, step: bootstrap)

            if bootstrap.exitCode != 0, shouldFallbackLegacyBootstrap(bootstrap.output) {
                logs.append("[bootstrap-fallback] bootstrap failed; try legacy knock/wait.")
                let fallbackResult = runLegacyBootstrapFlow(
                    options: opts,
                    hubHost: bootstrapHost,
                    grpcPort: opts.grpcPort,
                    preferredPairingPort: opts.pairingPort,
                    env: customEnv,
                    logs: &logs
                )
                if fallbackResult.ok {
                    opts.pairingPort = fallbackResult.pairingPort
                } else {
                    let reason = fallbackResult.reasonCode ?? "bootstrap_failed"
                    emit(onProgress, .bootstrap, .failed, reason)
                    emit(onProgress, .connect, .skipped, "blocked_by_bootstrap_failure")
                    return HubRemoteConnectReport(
                        ok: false,
                        route: .none,
                        summary: reason,
                        logLines: logs,
                        reasonCode: reason
                    )
                }
            } else if bootstrap.exitCode != 0 {
                let reason = inferFailureCode(from: bootstrap.output, fallback: "bootstrap_failed")
                emit(onProgress, .bootstrap, .failed, reason)
                emit(onProgress, .connect, .skipped, "blocked_by_bootstrap_failure")
                return HubRemoteConnectReport(
                    ok: false,
                    route: .none,
                    summary: reason,
                    logLines: logs,
                    reasonCode: reason
                )
            }
            emit(onProgress, .bootstrap, .succeeded, nil)
        } else if allowBootstrap {
            logs.append("[2/3] Bootstrap already paired (cached profile).")
            emit(onProgress, .bootstrap, .succeeded, "already_paired")
        }

        var firstConnect = connectWithFallback(
            options: opts,
            primaryHubHost: discoveredHubHost,
            env: customEnv,
            logs: &logs,
            onProgress: onProgress,
            startProgress: true,
            autoReconnect: false
        )
        if firstConnect.ok {
            return firstConnect
        }

        // If one-click setup starts from an existing profile and connect fails, try a bootstrap refresh once.
        if allowBootstrap && hasEnv {
            logs.append("[2/3] Refresh pairing via bootstrap (connect failed with cached profile) ...")
            emit(onProgress, .bootstrap, .started, "refresh")
            let refreshBootstrap = runAxhubctl(
                args: [
                    "bootstrap",
                    "--hub", preferredBootstrapHub(discoveredHubHost: discoveredHubHost, options: opts),
                    "--pairing-port", "\(opts.pairingPort)",
                    "--grpc-port", "\(opts.grpcPort)",
                    "--device-name", opts.deviceName,
                ],
                options: opts,
                env: customEnv,
                timeoutSec: 1_300.0
            )
            appendStepLogs(into: &logs, step: refreshBootstrap)
            guard refreshBootstrap.exitCode == 0 else {
                let reason = inferFailureCode(from: refreshBootstrap.output, fallback: "bootstrap_refresh_failed")
                emit(onProgress, .bootstrap, .failed, reason)
                emit(onProgress, .connect, .failed, reason)
                return HubRemoteConnectReport(
                    ok: false,
                    route: .none,
                    summary: reason,
                    logLines: logs,
                    reasonCode: reason
                )
            }
            emit(onProgress, .bootstrap, .succeeded, "refresh")

            firstConnect = connectWithFallback(
                options: opts,
                primaryHubHost: discoveredHubHost,
                env: customEnv,
                logs: &logs,
                onProgress: onProgress,
                startProgress: true,
                autoReconnect: false
            )
            return firstConnect
        }

        return firstConnect
    }

    private func connectWithFallback(
        options opts: HubRemoteConnectOptions,
        primaryHubHost: String?,
        env customEnv: [String: String],
        logs: inout [String],
        onProgress: (@Sendable (HubRemoteProgressEvent) -> Void)?,
        startProgress: Bool,
        autoReconnect: Bool
    ) -> HubRemoteConnectReport {
        logs.append(autoReconnect ? "[3/3] Connect + auto-reconnect probe (LAN first) ..." : "[3/3] Connect probe (LAN first) ...")
        if startProgress {
            emit(onProgress, .connect, .started, "lan")
        }
        var lanArgs: [String] = [
            "connect",
            "--hub", primaryHubHost ?? "auto",
            "--pairing-port", "\(opts.pairingPort)",
            "--grpc-port", "\(opts.grpcPort)",
            "--timeout-sec", "2",
        ]
        if autoReconnect {
            lanArgs += [
                "--auto-reconnect",
                "--max-failures", "4",
                "--max-backoff-sec", "10",
            ]
        }
        let lanConnect = runAxhubctl(
            args: lanArgs,
            options: opts,
            env: customEnv,
            timeoutSec: 90.0
        )
        appendStepLogs(into: &logs, step: lanConnect)
        if lanConnect.exitCode == 0 {
            emit(onProgress, .connect, .succeeded, "lan")
            return HubRemoteConnectReport(
                ok: true,
                route: .lan,
                summary: "connected_lan",
                logLines: logs,
                reasonCode: nil
            )
        }

        if isUnknownCommand(lanConnect.output, command: "connect") {
            return legacyConnectWithListModels(
                options: opts,
                env: customEnv,
                logs: &logs,
                onProgress: onProgress
            )
        }

        if opts.internetHost.isEmpty {
            let reason = inferFailureCode(from: lanConnect.output, fallback: "connect_failed")
            emit(onProgress, .connect, .failed, reason)
            return HubRemoteConnectReport(
                ok: false,
                route: .none,
                summary: reason,
                logLines: logs,
                reasonCode: reason
            )
        }

        logs.append("[fallback] Try internet host direct ...")
        var internetArgs: [String] = [
            "connect",
            "--hub", opts.internetHost,
            "--pairing-port", "\(opts.pairingPort)",
            "--grpc-port", "\(opts.grpcPort)",
            "--timeout-sec", "2",
        ]
        if autoReconnect {
            internetArgs += [
                "--auto-reconnect",
                "--max-failures", "4",
                "--max-backoff-sec", "12",
            ]
        }
        let internetConnect = runAxhubctl(
            args: internetArgs,
            options: opts,
            env: customEnv,
            timeoutSec: 90.0
        )
        appendStepLogs(into: &logs, step: internetConnect)
        if internetConnect.exitCode == 0 {
            emit(onProgress, .connect, .succeeded, "internet")
            return HubRemoteConnectReport(
                ok: true,
                route: .internet,
                summary: "connected_internet",
                logLines: logs,
                reasonCode: nil
            )
        }

        logs.append("[fallback] Install/refresh Mode3 tunnel + connect localhost ...")
        let tunnelInstall = runAxhubctl(
            args: [
                "tunnel",
                "--hub", opts.internetHost,
                "--grpc-port", "\(opts.grpcPort)",
                "--local-port", "\(opts.grpcPort)",
                "--install",
            ],
            options: opts,
            env: customEnv,
            timeoutSec: 90.0
        )
        appendStepLogs(into: &logs, step: tunnelInstall)

        var tunnelArgs: [String] = [
            "connect",
            "--hub", "127.0.0.1",
            "--grpc-port", "\(opts.grpcPort)",
            "--pairing-port", "\(opts.pairingPort)",
            "--timeout-sec", "2",
        ]
        if autoReconnect {
            tunnelArgs += [
                "--auto-reconnect",
                "--max-failures", "3",
                "--max-backoff-sec", "8",
            ]
        }
        let tunnelConnect = runAxhubctl(
            args: tunnelArgs,
            options: opts,
            env: customEnv,
            timeoutSec: 60.0
        )
        appendStepLogs(into: &logs, step: tunnelConnect)
        if tunnelConnect.exitCode == 0 {
            emit(onProgress, .connect, .succeeded, "tunnel")
            return HubRemoteConnectReport(
                ok: true,
                route: .internetTunnel,
                summary: "connected_internet_tunnel",
                logLines: logs,
                reasonCode: nil
            )
        }

        let reason = inferFailureCode(
            from: [tunnelConnect.output, tunnelInstall.output, internetConnect.output, lanConnect.output]
                .joined(separator: "\n"),
            fallback: "connect_failed_after_internet_fallback"
        )
        emit(onProgress, .connect, .failed, reason)
        return HubRemoteConnectReport(
            ok: false,
            route: .none,
            summary: reason,
            logLines: logs,
            reasonCode: reason
        )
    }

    func detectPorts(
        options rawOptions: HubRemoteConnectOptions,
        candidates rawCandidates: [Int] = [50052, 50053]
    ) -> HubRemotePortProbeResult {
        let opts = sanitize(rawOptions)
        let customEnv = discoveryEnv(internetHost: opts.internetHost)
        var logs: [String] = []

        let normalized = rawCandidates
            .map { max(1, min(65_535, $0)) }
        let candidates = Array(Set(normalized)).sorted()
        if candidates.isEmpty {
            return HubRemotePortProbeResult(
                ok: false,
                pairingPort: opts.pairingPort,
                grpcPort: opts.grpcPort,
                reasonCode: "no_port_candidates",
                logLines: ["port probe candidates are empty"]
            )
        }

        var lastOutput = ""
        var discoverUnsupported = false
        let probeStateDir = makeEphemeralStateDir(prefix: "xterminal_port_probe")
        var probeOptions = opts
        probeOptions.stateDir = probeStateDir
        for p in candidates {
            let step = runAxhubctl(
                args: [
                    "discover",
                    "--pairing-port", "\(p)",
                    "--timeout-sec", "2",
                ],
                options: probeOptions,
                env: customEnv,
                timeoutSec: 12.0
            )
            appendStepLogs(into: &logs, step: step)
            lastOutput = step.output
            if step.exitCode == 0 {
                let parsedHost = parseStringField(step.output, fieldName: "host")
                if shouldRequireConfiguredHubHost(options: opts),
                   !hostMatchesConfiguredHost(discoveredHost: parsedHost, options: opts) {
                    logs.append("[port-detect] ignore host mismatch (want \(opts.internetHost), got \(parsedHost ?? "unknown"))")
                    continue
                }
                let parsedPair = parsePortField(step.output, fieldName: "pairing_port") ?? p
                let parsedGrpc = parsePortField(step.output, fieldName: "grpc_port") ?? opts.grpcPort
                removeEphemeralStateDir(probeStateDir)
                return HubRemotePortProbeResult(
                    ok: true,
                    pairingPort: parsedPair,
                    grpcPort: parsedGrpc,
                    reasonCode: nil,
                    logLines: logs
                )
            } else if isUnknownCommand(step.output, command: "discover") {
                discoverUnsupported = true
                break
            }
        }
        removeEphemeralStateDir(probeStateDir)

        if discoverUnsupported {
            if let pair = loadCachedPairingInfo(stateDir: opts.stateDir).pairingPort,
               let grpc = loadCachedPairingInfo(stateDir: opts.stateDir).grpcPort {
                return HubRemotePortProbeResult(
                    ok: true,
                    pairingPort: pair,
                    grpcPort: grpc,
                    reasonCode: nil,
                    logLines: logs + ["[port-detect] discover unsupported; using cached pairing/grpc ports."]
                )
            }
            if nonEmpty(opts.internetHost) != nil {
                return HubRemotePortProbeResult(
                    ok: true,
                    pairingPort: opts.pairingPort,
                    grpcPort: opts.grpcPort,
                    reasonCode: nil,
                    logLines: logs + ["[port-detect] discover unsupported; keep configured ports."]
                )
            }
            return HubRemotePortProbeResult(
                ok: false,
                pairingPort: opts.pairingPort,
                grpcPort: opts.grpcPort,
                reasonCode: "discover_unsupported",
                logLines: logs
            )
        }

        let reason = inferFailureCode(from: lastOutput, fallback: "port_probe_failed")
        return HubRemotePortProbeResult(
            ok: false,
            pairingPort: opts.pairingPort,
            grpcPort: opts.grpcPort,
            reasonCode: reason,
            logLines: logs
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

    func fetchRemoteModels(options rawOptions: HubRemoteConnectOptions) -> HubRemoteModelsResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let env: [String: String] = [:]

        var list = runAxhubctl(
            args: ["list-models"],
            options: opts,
            env: env,
            timeoutSec: 60.0
        )
        appendStepLogs(into: &logs, step: list)

        if list.exitCode != 0, shouldRetryAfterClientKitInstall(list.output) {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: env,
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                list = runAxhubctl(
                    args: ["list-models"],
                    options: opts,
                    env: env,
                    timeoutSec: 60.0
                )
                appendStepLogs(into: &logs, step: list)
            }
        }

        guard list.exitCode == 0 else {
            let reason = inferFailureCode(from: list.output, fallback: "remote_models_list_failed")
            return HubRemoteModelsResult(
                ok: false,
                models: [],
                reasonCode: reason,
                logLines: logs
            )
        }

        let models = parseListModelsOutput(list.output)
        return HubRemoteModelsResult(
            ok: true,
            models: models,
            reasonCode: nil,
            logLines: logs
        )
    }

    func generateRemoteText(
        options rawOptions: HubRemoteConnectOptions,
        modelId rawModelId: String?,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        taskType: String,
        appId: String?,
        projectId: String?,
        sessionId: String?,
        requestId: String?
    ) -> HubRemoteGenerateResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let modelId = rawModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let promptText = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptText.isEmpty else {
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                reasonCode: "prompt_empty",
                logLines: ["prompt is empty for remote generate"]
            )
        }

        let limitedMaxTokens = max(1, min(8192, maxTokens))
        let limitedTemp = max(0, min(2, temperature))
        let limitedTopP = max(0.01, min(1.0, topP))
        let limitedTaskType = nonEmpty(taskType) ?? "assist"
        let limitedAppId = nonEmpty(appId) ?? "x_terminal"
        let limitedProjectId = nonEmpty(projectId) ?? ""
        let limitedSessionId = nonEmpty(sessionId) ?? ""
        let limitedReqId = nonEmpty(requestId) ?? "gen_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(6))"

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote generate"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_GEN_REQUEST_ID"] = limitedReqId
        scriptEnv["XTERMINAL_GEN_MODEL_ID"] = modelId
        scriptEnv["XTERMINAL_GEN_TASK_TYPE"] = limitedTaskType
        scriptEnv["XTERMINAL_GEN_APP_ID"] = limitedAppId
        scriptEnv["XTERMINAL_GEN_PROJECT_ID"] = limitedProjectId
        scriptEnv["XTERMINAL_GEN_SESSION_ID"] = limitedSessionId
        scriptEnv["XTERMINAL_GEN_PROMPT_B64"] = Data(prompt.utf8).base64EncodedString()
        scriptEnv["XTERMINAL_GEN_MAX_TOKENS"] = "\(limitedMaxTokens)"
        scriptEnv["XTERMINAL_GEN_TEMPERATURE"] = "\(limitedTemp)"
        scriptEnv["XTERMINAL_GEN_TOP_P"] = "\(limitedTopP)"
        scriptEnv["XTERMINAL_GEN_TIMEOUT_SEC"] = "240"

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteGenerateScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 300.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)

        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: [:],
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        func decodeGenerateStep(_ step: StepOutput) -> RemoteGenerateScriptResult? {
            guard let jsonLine = extractTrailingJSONObjectLine(step.output),
                  let data = jsonLine.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(RemoteGenerateScriptResult.self, from: data) else {
                return nil
            }
            return decoded
        }

        func normalizedFailureReason(
            from decoded: RemoteGenerateScriptResult,
            step: StepOutput,
            fallback: String
        ) -> String {
            let reason = nonEmpty(decoded.errorCode)
                ?? nonEmpty(decoded.reason)
                ?? nonEmpty(decoded.errorMessage)
                ?? inferFailureCode(from: step.output, fallback: fallback)
            return reason.replacingOccurrences(of: " ", with: "_")
        }

        func finalizeGenerateStep(_ step: StepOutput) -> HubRemoteGenerateResult {
            guard let decoded = decodeGenerateStep(step) else {
                let reason = inferFailureCode(from: step.output, fallback: "remote_chat_failed")
                return HubRemoteGenerateResult(
                    ok: false,
                    text: "",
                    reasonCode: reason,
                    logLines: logs
                )
            }

            guard decoded.ok == true else {
                return HubRemoteGenerateResult(
                    ok: false,
                    text: "",
                    reasonCode: normalizedFailureReason(from: decoded, step: step, fallback: "remote_chat_failed"),
                    logLines: logs
                )
            }

            let text = decoded.text ?? ""
            if text.isEmpty {
                return HubRemoteGenerateResult(
                    ok: false,
                    text: "",
                    reasonCode: normalizedFailureReason(from: decoded, step: step, fallback: "remote_chat_empty_output"),
                    logLines: logs
                )
            }

            return HubRemoteGenerateResult(
                ok: true,
                text: text,
                reasonCode: nil,
                logLines: logs
            )
        }

        guard let decoded = decodeGenerateStep(step) else {
            let reason = inferFailureCode(from: step.output, fallback: "remote_chat_failed")
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                reasonCode: reason,
                logLines: logs
            )
        }

        if decoded.ok != true {
            let reason = normalizedFailureReason(from: decoded, step: step, fallback: "remote_chat_failed")
            if reason == "grant_required" {
                let paidModelId = nonEmpty(decoded.modelId) ?? nonEmpty(modelId)
                if let paidModelId {
                    let grant = requestRemotePaidAIGrant(
                        options: opts,
                        modelId: paidModelId,
                        requestedSeconds: 1800,
                        requestedTokenCap: min(5000, max(1024, limitedMaxTokens * 2)),
                        reason: "x_terminal paid generate \(limitedTaskType)",
                        projectId: limitedProjectId.isEmpty ? nil : limitedProjectId
                    )
                    logs.append(contentsOf: grant.logLines)

                    switch grant.decision {
                    case .approved where grant.ok:
                        step = runScript()
                        appendStepLogs(into: &logs, step: step)
                        return finalizeGenerateStep(step)
                    case .queued:
                        return HubRemoteGenerateResult(
                            ok: false,
                            text: "",
                            reasonCode: "grant_pending",
                            logLines: logs
                        )
                    case .denied:
                        return HubRemoteGenerateResult(
                            ok: false,
                            text: "",
                            reasonCode: grant.reasonCode ?? "grant_denied",
                            logLines: logs
                        )
                    case .failed, .approved:
                        return HubRemoteGenerateResult(
                            ok: false,
                            text: "",
                            reasonCode: grant.reasonCode ?? reason,
                            logLines: logs
                        )
                    }
                }
            }

            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                reasonCode: reason,
                logLines: logs
            )
        }

        let text = decoded.text ?? ""
        if text.isEmpty {
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                reasonCode: normalizedFailureReason(from: decoded, step: step, fallback: "remote_chat_empty_output"),
                logLines: logs
            )
        }

        return HubRemoteGenerateResult(
            ok: true,
            text: text,
            reasonCode: nil,
            logLines: logs
        )
    }

    func requestRemoteNetworkGrant(
        options rawOptions: HubRemoteConnectOptions,
        requestedSeconds: Int,
        reason: String?,
        projectId: String? = nil
    ) -> HubRemoteGrantResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for client kit grant request"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_GRANT_CAPABILITY"] = "CAPABILITY_WEB_FETCH"
        scriptEnv["XTERMINAL_GRANT_SECONDS"] = "\(max(30, min(86_400, requestedSeconds)))"
        scriptEnv["XTERMINAL_GRANT_REASON"] = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_GRANT_WAIT_SEC"] = "10"
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runGrantScript() -> StepOutput {
            do {
                let script = remoteNetworkGrantScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 28.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runGrantScript()
        appendStepLogs(into: &logs, step: step)

        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: [:],
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runGrantScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteNetworkGrantScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_grant_failed")
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let decisionToken = (decoded.decision ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mappedDecision: HubRemoteGrantDecision = {
            switch decisionToken {
            case "approved":
                return .approved
            case "queued":
                return .queued
            case "denied":
                return .denied
            default:
                return .failed
            }
        }()

        let ok = decoded.ok ?? (mappedDecision == .approved || mappedDecision == .queued)
        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : inferFailureCode(from: step.output, fallback: "remote_grant_failed"))

        let expiresAtSec: Double? = {
            guard let ms = decoded.expiresAtMs, ms > 0 else { return nil }
            return ms / 1000.0
        }()

        return HubRemoteGrantResult(
            ok: ok,
            decision: mappedDecision,
            grantRequestId: nonEmpty(decoded.grantRequestId),
            expiresAtSec: expiresAtSec,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func requestRemotePaidAIGrant(
        options rawOptions: HubRemoteConnectOptions,
        modelId rawModelId: String,
        requestedSeconds: Int,
        requestedTokenCap: Int,
        reason: String?,
        projectId: String? = nil
    ) -> HubRemoteGrantResult {
        let paidModelId = rawModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !paidModelId.isEmpty else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "grant_model_id_missing",
                logLines: ["missing model id for paid AI grant request"]
            )
        }

        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for paid AI grant request"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_GRANT_CAPABILITY"] = "CAPABILITY_AI_GENERATE_PAID"
        scriptEnv["XTERMINAL_GRANT_MODEL_ID"] = paidModelId
        scriptEnv["XTERMINAL_GRANT_SECONDS"] = "\(max(30, min(86_400, requestedSeconds)))"
        scriptEnv["XTERMINAL_GRANT_TOKEN_CAP"] = "\(max(0, min(5000, requestedTokenCap)))"
        scriptEnv["XTERMINAL_GRANT_REASON"] = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_GRANT_WAIT_SEC"] = "10"
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runGrantScript() -> StepOutput {
            do {
                let script = remoteNetworkGrantScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 28.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runGrantScript()
        appendStepLogs(into: &logs, step: step)

        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: [:],
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runGrantScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteNetworkGrantScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_paid_grant_failed")
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let decisionToken = (decoded.decision ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mappedDecision: HubRemoteGrantDecision = {
            switch decisionToken {
            case "approved":
                return .approved
            case "queued":
                return .queued
            case "denied":
                return .denied
            default:
                return .failed
            }
        }()

        let ok = decoded.ok ?? (mappedDecision == .approved || mappedDecision == .queued)
        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : inferFailureCode(from: step.output, fallback: "remote_paid_grant_failed"))

        let expiresAtSec: Double? = {
            guard let ms = decoded.expiresAtMs, ms > 0 else { return nil }
            return ms / 1000.0
        }()

        return HubRemoteGrantResult(
            ok: ok,
            decision: mappedDecision,
            grantRequestId: nonEmpty(decoded.grantRequestId),
            expiresAtSec: expiresAtSec,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func requestRemoteWebFetch(
        options rawOptions: HubRemoteConnectOptions,
        url: String,
        timeoutSec: Double,
        maxBytes: Int
    ) -> HubRemoteWebFetchResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let requestURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestURL.isEmpty else {
            return HubRemoteWebFetchResult(
                ok: false,
                status: 0,
                finalURL: "",
                contentType: "",
                truncated: false,
                bytes: 0,
                text: "",
                errorMessage: "empty_url",
                reasonCode: "empty_url",
                logLines: ["empty url for web fetch"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteWebFetchResult(
                ok: false,
                status: 0,
                finalURL: "",
                contentType: "",
                truncated: false,
                bytes: 0,
                text: "",
                errorMessage: "hub_env_missing",
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteWebFetchResult(
                ok: false,
                status: 0,
                finalURL: "",
                contentType: "",
                truncated: false,
                bytes: 0,
                text: "",
                errorMessage: "client_kit_missing",
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteWebFetchResult(
                ok: false,
                status: 0,
                finalURL: "",
                contentType: "",
                truncated: false,
                bytes: 0,
                text: "",
                errorMessage: "node_missing",
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote web fetch"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_FETCH_URL"] = requestURL
        scriptEnv["XTERMINAL_FETCH_TIMEOUT_SEC"] = String(max(2.0, min(60.0, timeoutSec)))
        scriptEnv["XTERMINAL_FETCH_MAX_BYTES"] = String(max(1024, min(5_000_000, maxBytes)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runFetchScript() -> StepOutput {
            do {
                let script = remoteWebFetchScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: max(8.0, min(90.0, timeoutSec + 20.0)),
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runFetchScript()
        appendStepLogs(into: &logs, step: step)

        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: [:],
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runFetchScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteWebFetchScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_web_fetch_failed")
            return HubRemoteWebFetchResult(
                ok: false,
                status: 0,
                finalURL: requestURL,
                contentType: "",
                truncated: false,
                bytes: 0,
                text: "",
                errorMessage: fallback,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (decoded.ok == true ? nil : "remote_web_fetch_failed")
        let message = nonEmpty(decoded.errorMessage)
            ?? nonEmpty(decoded.reason)

        return HubRemoteWebFetchResult(
            ok: decoded.ok ?? false,
            status: decoded.status ?? 0,
            finalURL: nonEmpty(decoded.finalURL) ?? requestURL,
            contentType: nonEmpty(decoded.contentType) ?? "",
            truncated: decoded.truncated ?? false,
            bytes: decoded.bytes ?? 0,
            text: decoded.text ?? "",
            errorMessage: message,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func syncRemoteProjectSnapshot(
        options rawOptions: HubRemoteConnectOptions,
        payload: HubRemoteProjectSyncPayload
    ) -> HubRemoteMutationResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let pid = payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pid.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "project_id_empty", logLines: ["project_id is empty"])
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "hub_env_missing", logLines: ["missing hub env: \(hubEnv.path)"])
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "client_kit_missing", logLines: ["missing client kit src: \(clientKitSrc.path)"])
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMutationResult(ok: false, reasonCode: "node_missing", logLines: ["missing node runtime for remote project sync"])
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SYNC_PROJECT_ID"] = pid
        scriptEnv["XTERMINAL_SYNC_ROOT_PATH"] = payload.rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_SYNC_DISPLAY_NAME"] = payload.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_SYNC_STATUS_DIGEST"] = payload.statusDigest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SYNC_LAST_SUMMARY_AT"] = payload.lastSummaryAt.map { String($0) } ?? ""
        scriptEnv["XTERMINAL_SYNC_LAST_EVENT_AT"] = payload.lastEventAt.map { String($0) } ?? ""
        scriptEnv["XTERMINAL_SYNC_UPDATED_AT"] = payload.updatedAt.map { String($0) } ?? String(Date().timeIntervalSince1970)

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteProjectSyncScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMutationScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_project_sync_failed")
            return HubRemoteMutationResult(ok: false, reasonCode: fallback, logLines: logs)
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_project_sync_failed")

        return HubRemoteMutationResult(
            ok: decoded.ok ?? false,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func pushRemoteNotificationMemory(
        options rawOptions: HubRemoteConnectOptions,
        payload: HubRemoteNotificationPayload
    ) -> HubRemoteMutationResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "title_empty", logLines: ["notification title is empty"])
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "hub_env_missing", logLines: ["missing hub env: \(hubEnv.path)"])
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "client_kit_missing", logLines: ["missing client kit src: \(clientKitSrc.path)"])
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMutationResult(ok: false, reasonCode: "node_missing", logLines: ["missing node runtime for remote notification"])
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_NOTIFY_SOURCE"] = payload.source.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_NOTIFY_TITLE"] = title
        scriptEnv["XTERMINAL_NOTIFY_BODY"] = payload.body.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_NOTIFY_DEDUPE"] = payload.dedupeKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_NOTIFY_ACTION_URL"] = payload.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_NOTIFY_UNREAD"] = payload.unread ? "1" : "0"

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteNotificationScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMutationScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_notification_failed")
            return HubRemoteMutationResult(ok: false, reasonCode: fallback, logLines: logs)
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_notification_failed")

        return HubRemoteMutationResult(
            ok: decoded.ok ?? false,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteMemorySnapshot(
        options rawOptions: HubRemoteConnectOptions,
        mode rawMode: String,
        projectId: String?
    ) -> HubRemoteMemorySnapshotResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let mode = rawMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedMode = mode.isEmpty ? "project" : mode

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMemorySnapshotResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                canonicalEntries: [],
                workingEntries: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMemorySnapshotResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                canonicalEntries: [],
                workingEntries: [],
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMemorySnapshotResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                canonicalEntries: [],
                workingEntries: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote memory snapshot"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_MEM_MODE"] = normalizedMode
        scriptEnv["XTERMINAL_MEM_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_MEM_CANONICAL_LIMIT"] = "24"
        scriptEnv["XTERMINAL_MEM_WORKING_LIMIT"] = "12"

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteMemorySnapshotScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMemorySnapshotScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_memory_snapshot_failed")
            return HubRemoteMemorySnapshotResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                canonicalEntries: [],
                workingEntries: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_memory_snapshot_failed")

        return HubRemoteMemorySnapshotResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            canonicalEntries: decoded.canonicalEntries ?? [],
            workingEntries: decoded.workingEntries ?? [],
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteSchedulerStatus(
        options rawOptions: HubRemoteConnectOptions,
        includeQueueItems: Bool,
        queueItemsLimit: Int
    ) -> HubRemoteSchedulerStatusResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteSchedulerStatusResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                inFlightTotal: 0,
                queueDepth: 0,
                oldestQueuedMs: 0,
                inFlightByScope: [],
                queuedByScope: [],
                queueItems: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSchedulerStatusResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                inFlightTotal: 0,
                queueDepth: 0,
                oldestQueuedMs: 0,
                inFlightByScope: [],
                queuedByScope: [],
                queueItems: [],
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSchedulerStatusResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                inFlightTotal: 0,
                queueDepth: 0,
                oldestQueuedMs: 0,
                inFlightByScope: [],
                queuedByScope: [],
                queueItems: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote scheduler status"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SCHED_INCLUDE_QUEUE_ITEMS"] = includeQueueItems ? "1" : "0"
        scriptEnv["XTERMINAL_SCHED_QUEUE_ITEMS_LIMIT"] = String(max(1, min(500, queueItemsLimit)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSchedulerStatusScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteSchedulerStatusScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_scheduler_status_failed")
            return HubRemoteSchedulerStatusResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                inFlightTotal: 0,
                queueDepth: 0,
                oldestQueuedMs: 0,
                inFlightByScope: [],
                queuedByScope: [],
                queueItems: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_scheduler_status_failed")

        let inFlightByScope: [HubRemoteSchedulerScopeCount] = (decoded.inFlightByScope ?? []).compactMap { row in
            let key = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return HubRemoteSchedulerScopeCount(
                scopeKey: key,
                count: max(0, row.inFlight ?? 0)
            )
        }

        let queuedByScope: [HubRemoteSchedulerScopeCount] = (decoded.queuedByScope ?? []).compactMap { row in
            let key = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return HubRemoteSchedulerScopeCount(
                scopeKey: key,
                count: max(0, row.queued ?? 0)
            )
        }

        let queueItems: [HubRemoteSchedulerQueueItem] = (decoded.queueItems ?? []).compactMap { row in
            let requestId = row.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
            let scopeKey = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !requestId.isEmpty, !scopeKey.isEmpty else { return nil }
            return HubRemoteSchedulerQueueItem(
                requestId: requestId,
                scopeKey: scopeKey,
                enqueuedAtMs: max(0, row.enqueuedAtMs ?? 0),
                queuedMs: max(0, row.queuedMs ?? 0)
            )
        }

        return HubRemoteSchedulerStatusResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            inFlightTotal: max(0, decoded.inFlightTotal ?? 0),
            queueDepth: max(0, decoded.queueDepth ?? 0),
            oldestQueuedMs: max(0, decoded.oldestQueuedMs ?? 0),
            inFlightByScope: inFlightByScope,
            queuedByScope: queuedByScope,
            queueItems: queueItems,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemotePendingGrantRequests(
        options rawOptions: HubRemoteConnectOptions,
        projectId: String?,
        limit: Int
    ) -> HubRemotePendingGrantRequestsResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemotePendingGrantRequestsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemotePendingGrantRequestsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemotePendingGrantRequestsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote pending grants"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_PENDING_GRANTS_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_PENDING_GRANTS_LIMIT"] = String(max(1, min(500, limit)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remotePendingGrantRequestsScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemotePendingGrantRequestsScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_pending_grants_failed")
            return HubRemotePendingGrantRequestsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_pending_grants_failed")

        let items: [HubRemotePendingGrantItem] = (decoded.items ?? []).compactMap { row in
            let grantRequestId = row.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !grantRequestId.isEmpty else { return nil }
            return HubRemotePendingGrantItem(
                grantRequestId: grantRequestId,
                requestId: row.requestId.trimmingCharacters(in: .whitespacesAndNewlines),
                deviceId: row.deviceId.trimmingCharacters(in: .whitespacesAndNewlines),
                userId: row.userId.trimmingCharacters(in: .whitespacesAndNewlines),
                appId: row.appId.trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                capability: row.capability.trimmingCharacters(in: .whitespacesAndNewlines),
                modelId: row.modelId.trimmingCharacters(in: .whitespacesAndNewlines),
                reason: row.reason.trimmingCharacters(in: .whitespacesAndNewlines),
                requestedTtlSec: max(0, row.requestedTtlSec ?? 0),
                requestedTokenCap: max(0, row.requestedTokenCap ?? 0),
                status: row.status.trimmingCharacters(in: .whitespacesAndNewlines),
                decision: row.decision.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAtMs: max(0, row.createdAtMs ?? 0),
                decidedAtMs: max(0, row.decidedAtMs ?? 0)
            )
        }

        return HubRemotePendingGrantRequestsResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: items,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func approveRemotePendingGrantRequest(
        options rawOptions: HubRemoteConnectOptions,
        grantRequestId: String,
        projectId: String?,
        ttlSec: Int?,
        tokenCap: Int?,
        note: String?
    ) -> HubRemotePendingGrantActionResult {
        performRemotePendingGrantAction(
            options: rawOptions,
            action: "approve",
            grantRequestId: grantRequestId,
            projectId: projectId,
            ttlSec: ttlSec,
            tokenCap: tokenCap,
            note: note,
            reason: nil
        )
    }

    func denyRemotePendingGrantRequest(
        options rawOptions: HubRemoteConnectOptions,
        grantRequestId: String,
        projectId: String?,
        reason: String?
    ) -> HubRemotePendingGrantActionResult {
        performRemotePendingGrantAction(
            options: rawOptions,
            action: "deny",
            grantRequestId: grantRequestId,
            projectId: projectId,
            ttlSec: nil,
            tokenCap: nil,
            note: nil,
            reason: reason
        )
    }

    private func performRemotePendingGrantAction(
        options rawOptions: HubRemoteConnectOptions,
        action rawAction: String,
        grantRequestId: String,
        projectId: String?,
        ttlSec: Int?,
        tokenCap: Int?,
        note: String?,
        reason: String?
    ) -> HubRemotePendingGrantActionResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let action = rawAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard action == "approve" || action == "deny" else {
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "invalid_action",
                logLines: ["invalid pending grant action: \(rawAction)"]
            )
        }

        let grantId = grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !grantId.isEmpty else {
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "grant_request_id_empty",
                logLines: ["pending grant action missing grant_request_id"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: grantId,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: grantId,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: grantId,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote pending grant action"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_PENDING_GRANT_ACTION"] = action
        scriptEnv["XTERMINAL_PENDING_GRANT_ID"] = grantId
        scriptEnv["XTERMINAL_PENDING_GRANT_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        scriptEnv["XTERMINAL_PENDING_GRANT_TTL_SEC"] = ttlSec.map { String(max(10, min(86_400, $0))) } ?? ""
        scriptEnv["XTERMINAL_PENDING_GRANT_TOKEN_CAP"] = tokenCap.map { String(max(0, $0)) } ?? ""
        scriptEnv["XTERMINAL_PENDING_GRANT_NOTE"] = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_PENDING_GRANT_REASON"] = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remotePendingGrantActionScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemotePendingGrantActionScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_pending_grant_action_failed")
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: grantId,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let decisionToken = (decoded.decision ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mappedDecision: HubRemotePendingGrantActionDecision = {
            switch decisionToken {
            case "approved":
                return .approved
            case "denied":
                return .denied
            default:
                return .failed
            }
        }()

        let ok = decoded.ok ?? (mappedDecision == .approved || mappedDecision == .denied)
        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : "remote_pending_grant_action_failed")

        return HubRemotePendingGrantActionResult(
            ok: ok,
            decision: mappedDecision,
            grantRequestId: nonEmpty(decoded.grantRequestId) ?? grantId,
            grantId: nonEmpty(decoded.grantId),
            expiresAtMs: decoded.expiresAtMs,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    // MARK: - Helpers

    private struct StepOutput {
        var exitCode: Int32
        var output: String
        var command: String
    }

    private struct RemoteGenerateScriptResult: Codable {
        var ok: Bool?
        var text: String?
        var modelId: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?
        var promptTokens: Int?
        var completionTokens: Int?
        var totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case ok
            case text
            case modelId = "model_id"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    private struct RemoteNetworkGrantScriptResult: Codable {
        var ok: Bool?
        var decision: String?
        var grantRequestId: String?
        var expiresAtMs: Double?
        var reason: String?
        var queued: Bool?
        var autoApproved: Bool?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case decision
            case grantRequestId = "grant_request_id"
            case expiresAtMs = "expires_at_ms"
            case reason
            case queued
            case autoApproved = "auto_approved"
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteWebFetchScriptResult: Codable {
        var ok: Bool?
        var status: Int?
        var finalURL: String?
        var contentType: String?
        var truncated: Bool?
        var bytes: Int?
        var text: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case status
            case finalURL = "final_url"
            case contentType = "content_type"
            case truncated
            case bytes
            case text
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteMutationScriptResult: Codable {
        var ok: Bool?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteMemorySnapshotScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var canonicalEntries: [String]?
        var workingEntries: [String]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case canonicalEntries = "canonical_entries"
            case workingEntries = "working_entries"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteSchedulerScopeInFlightRow: Codable {
        var scopeKey: String
        var inFlight: Int?

        enum CodingKeys: String, CodingKey {
            case scopeKey = "scope_key"
            case inFlight = "in_flight"
        }
    }

    private struct RemoteSchedulerScopeQueuedRow: Codable {
        var scopeKey: String
        var queued: Int?

        enum CodingKeys: String, CodingKey {
            case scopeKey = "scope_key"
            case queued
        }
    }

    private struct RemoteSchedulerQueueItemRow: Codable {
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

    private struct RemoteSchedulerStatusScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var updatedAtMs: Double?
        var inFlightTotal: Int?
        var queueDepth: Int?
        var oldestQueuedMs: Int?
        var inFlightByScope: [RemoteSchedulerScopeInFlightRow]?
        var queuedByScope: [RemoteSchedulerScopeQueuedRow]?
        var queueItems: [RemoteSchedulerQueueItemRow]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case inFlightTotal = "in_flight_total"
            case queueDepth = "queue_depth"
            case oldestQueuedMs = "oldest_queued_ms"
            case inFlightByScope = "in_flight_by_scope"
            case queuedByScope = "queued_by_scope"
            case queueItems = "queue_items"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemotePendingGrantItemRow: Codable {
        var grantRequestId: String
        var requestId: String
        var deviceId: String
        var userId: String
        var appId: String
        var projectId: String
        var capability: String
        var modelId: String
        var reason: String
        var requestedTtlSec: Int?
        var requestedTokenCap: Int?
        var status: String
        var decision: String
        var createdAtMs: Double?
        var decidedAtMs: Double?

        enum CodingKeys: String, CodingKey {
            case grantRequestId = "grant_request_id"
            case requestId = "request_id"
            case deviceId = "device_id"
            case userId = "user_id"
            case appId = "app_id"
            case projectId = "project_id"
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

    private struct RemotePendingGrantRequestsScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var updatedAtMs: Double?
        var items: [RemotePendingGrantItemRow]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case items
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemotePendingGrantActionScriptResult: Codable {
        var ok: Bool?
        var decision: String?
        var grantRequestId: String?
        var grantId: String?
        var expiresAtMs: Double?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case decision
            case grantRequestId = "grant_request_id"
            case grantId = "grant_id"
            case expiresAtMs = "expires_at_ms"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private func sanitize(_ options: HubRemoteConnectOptions) -> HubRemoteConnectOptions {
        var out = options
        out.grpcPort = max(1, min(65_535, options.grpcPort))
        out.pairingPort = max(1, min(65_535, options.pairingPort))
        let device = options.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        out.deviceName = device.isEmpty ? Host.current().localizedName ?? "X-Terminal" : device
        out.internetHost = options.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        out.axhubctlPath = options.axhubctlPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return out
    }

    private func appendStepLogs(into logs: inout [String], step: StepOutput) {
        logs.append("$ \(step.command)")
        if !step.output.isEmpty {
            logs.append(step.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        logs.append("(exit=\(step.exitCode))")
    }

    private func runLegacyBootstrapFlow(
        options opts: HubRemoteConnectOptions,
        hubHost: String,
        grpcPort: Int,
        preferredPairingPort: Int,
        env customEnv: [String: String],
        logs: inout [String]
    ) -> (ok: Bool, pairingPort: Int, reasonCode: String?) {
        let candidates = orderedPairingPortCandidates(preferredPairingPort)
        var lastFailureText = ""

        for p in candidates {
            logs.append("[bootstrap-fallback] try pairing_port=\(p)")
            let knock = runAxhubctl(
                args: [
                    "knock",
                    "--hub", hubHost,
                    "--pairing-port", "\(p)",
                    "--grpc-port", "\(grpcPort)",
                    "--device-name", opts.deviceName,
                ],
                options: opts,
                env: customEnv,
                timeoutSec: 90.0
            )
            appendStepLogs(into: &logs, step: knock)
            if knock.exitCode != 0 {
                lastFailureText = knock.output
                continue
            }

            let wait = runAxhubctl(
                args: [
                    "wait",
                    "--hub", hubHost,
                    "--pairing-port", "\(p)",
                    "--grpc-port", "\(grpcPort)",
                    "--timeout-sec", "900",
                    "--interval-sec", "2",
                ],
                options: opts,
                env: customEnv,
                timeoutSec: 1_300.0
            )
            appendStepLogs(into: &logs, step: wait)
            if wait.exitCode != 0 {
                lastFailureText = wait.output
                continue
            }

            // Best-effort: if old bootstrap path is bypassed, still try fetching client kit now.
            let install = runAxhubctl(
                args: [
                    "install-client",
                    "--hub", hubHost,
                    "--pairing-port", "\(p)",
                ],
                options: opts,
                env: customEnv,
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode != 0 {
                logs.append("[bootstrap-fallback] install-client failed (best-effort); continue with pairing.")
            }

            return (true, p, nil)
        }

        return (false, preferredPairingPort, inferFailureCode(from: lastFailureText, fallback: "bootstrap_failed"))
    }

    private func orderedPairingPortCandidates(_ preferred: Int) -> [Int] {
        var out: [Int] = []
        for p in [preferred, 50052, 50053] {
            let clamped = max(1, min(65_535, p))
            if !out.contains(clamped) {
                out.append(clamped)
            }
        }
        return out
    }

    private func shouldFallbackLegacyBootstrap(_ output: String) -> Bool {
        let text = output.lowercased()
        if text.contains("permission denied") {
            return true
        }
        if text.contains("unknown command: bootstrap") {
            return true
        }
        if text.contains("request failed: curl")
            || text.contains("empty reply from server")
            || text.contains("connection refused")
            || text.contains("failed to connect") {
            return true
        }
        return false
    }

    private func legacyConnectWithListModels(
        options opts: HubRemoteConnectOptions,
        env customEnv: [String: String],
        logs: inout [String],
        onProgress: (@Sendable (HubRemoteProgressEvent) -> Void)?
    ) -> HubRemoteConnectReport {
        logs.append("[fallback] axhubctl missing connect; legacy verify via list-models.")
        var list = runAxhubctl(
            args: ["list-models"],
            options: opts,
            env: customEnv,
            timeoutSec: 60.0
        )
        appendStepLogs(into: &logs, step: list)

        if list.exitCode != 0, shouldRetryAfterClientKitInstall(list.output) {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: customEnv,
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                list = runAxhubctl(
                    args: ["list-models"],
                    options: opts,
                    env: customEnv,
                    timeoutSec: 60.0
                )
                appendStepLogs(into: &logs, step: list)
            }
        }

        if list.exitCode == 0 {
            let route: HubRemoteRoute = shouldRequireConfiguredHubHost(options: opts) ? .internet : .lan
            emit(onProgress, .connect, .succeeded, "legacy_list_models")
            return HubRemoteConnectReport(
                ok: true,
                route: route,
                summary: "connected_legacy_list_models",
                logLines: logs,
                reasonCode: nil
            )
        }

        let reason = inferFailureCode(from: list.output, fallback: "legacy_connect_failed")
        emit(onProgress, .connect, .failed, reason)
        return HubRemoteConnectReport(
            ok: false,
            route: .none,
            summary: reason,
            logLines: logs,
            reasonCode: reason
        )
    }

    private func runAxhubctl(
        args: [String],
        options: HubRemoteConnectOptions,
        env: [String: String],
        timeoutSec: Double
    ) -> StepOutput {
        let resolved = resolveAxhubctlExecutable(override: options.axhubctlPath)
        var commandDisplay = ""
        var result: ProcessResult

        do {
            switch resolved {
            case .direct(let path):
                commandDisplay = ([path] + args).joined(separator: " ")
                result = try ProcessCapture.run(
                    path,
                    args,
                    cwd: nil,
                    timeoutSec: timeoutSec,
                    env: mergedAxhubEnv(options: options, extra: env)
                )
            case .bashScript(let path):
                commandDisplay = (["/bin/bash", path] + args).joined(separator: " ")
                result = try ProcessCapture.run(
                    "/bin/bash",
                    [path] + args,
                    cwd: nil,
                    timeoutSec: timeoutSec,
                    env: mergedAxhubEnv(options: options, extra: env)
                )
            case .viaEnv:
                commandDisplay = (["axhubctl"] + args).joined(separator: " ")
                result = try ProcessCapture.run(
                    "/usr/bin/env",
                    ["axhubctl"] + args,
                    cwd: nil,
                    timeoutSec: timeoutSec,
                    env: mergedAxhubEnv(options: options, extra: env)
                )
            }
        } catch {
            return StepOutput(
                exitCode: 127,
                output: String(describing: error),
                command: commandDisplay.isEmpty ? ("axhubctl " + args.joined(separator: " ")) : commandDisplay
            )
        }

        return StepOutput(exitCode: result.exitCode, output: result.combined, command: commandDisplay)
    }

    private func resolveNodeExecutable(clientKitBaseDir: URL, env: [String: String]) -> String? {
        let fm = FileManager.default
        if let override = nonEmpty(env["AXHUBCTL_NODE_BIN"]), fm.isExecutableFile(atPath: override) {
            return override
        }

        if let bundled = preferredNodeBinPath(), fm.isExecutableFile(atPath: bundled) {
            return bundled
        }

        let kitNode = clientKitBaseDir.appendingPathComponent("bin/relflowhub_node").path
        if fm.isExecutableFile(atPath: kitNode) {
            return kitNode
        }

        let systemCandidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        for c in systemCandidates where fm.isExecutableFile(atPath: c) {
            return c
        }
        return nil
    }

    private func extractTrailingJSONObjectLine(_ text: String) -> String? {
        for raw in text.components(separatedBy: .newlines).reversed() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("{"), line.hasSuffix("}") {
                return line
            }
        }
        return nil
    }

    private func readEnvExports(from fileURL: URL) -> [String: String] {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
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
            let rhs = String(candidate[candidate.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lhs.isEmpty else { continue }
            out[lhs] = unquoteShellValue(rhs)
        }
        return out
    }

    private func remoteGenerateScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const asText = (v) => (v == null ? '' : String(v));
const safe = (v) => asText(v).trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  const projectOverride = safe(process.env.XTERMINAL_GEN_PROJECT_ID || '');
  const sessionOverride = safe(process.env.XTERMINAL_GEN_SESSION_ID || '');
  const appOverride = safe(process.env.XTERMINAL_GEN_APP_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: appOverride || safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectOverride || safe(process.env.HUB_PROJECT_ID || ''),
    session_id: sessionOverride || safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function listModels(modelsClient, md, client) {
  return await new Promise((resolve, reject) => {
    modelsClient.ListModels({ client }, md, (err, out) => {
      if (err) reject(err);
      else resolve(Array.isArray(out?.models) ? out.models : []);
    });
  });
}

function selectModelId(models, wantedModelId) {
  const wanted = safe(wantedModelId);
  if (wanted) return wanted;
  const available = models.filter((m) => safe(m?.visibility) === 'MODEL_VISIBILITY_AVAILABLE');
  if (available.length > 0) {
    const id = safe(available[0]?.model_id || '');
    if (id) return id;
  }
  for (const m of models) {
    const id = safe(m?.model_id || '');
    if (id) return id;
  }
  return '';
}

async function generateOnce(aiClient, md, req, timeoutMs) {
  const stream = aiClient.Generate(req, md);
  return await new Promise((resolve, reject) => {
    let assistantText = '';
    let doneObj = null;
    let errObj = null;

    const timer = setTimeout(() => {
      try { stream.cancel(); } catch {}
      reject(new Error('remote_generate_timeout'));
    }, Math.max(4000, timeoutMs));

    stream.on('data', (ev) => {
      const which = safe(ev?.ev || '');
      const start = ev?.start || (which === 'start' ? ev?.start : null);
      const delta = ev?.delta || (which === 'delta' ? ev?.delta : null);
      const done = ev?.done || (which === 'done' ? ev?.done : null);
      const err = ev?.error || (which === 'error' ? ev?.error : null);

      if (start && safe(start.model_id || '')) {
        req.model_id = safe(start.model_id || req.model_id || '');
      }
      if (delta && typeof delta.text === 'string' && delta.text) {
        assistantText += delta.text;
      }
      if (done) doneObj = done;
      if (err) errObj = err;
    });

    stream.on('end', () => {
      clearTimeout(timer);
      resolve({ assistantText, done: doneObj, error: errObj, model_id: safe(req.model_id || '') });
    });
    stream.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
}

async function main() {
  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubAI) {
    throw new Error('hub_ai_missing');
  }

  const { creds, options } = await makeClientCreds();
  const aiClient = new proto.HubAI(addr, creds, options);
  const modelsClient = proto?.HubModels ? new proto.HubModels(addr, creds, options) : null;
  const md = metadataFromEnv();
  const client = reqClientFromEnv();

  const reqId = safe(process.env.XTERMINAL_GEN_REQUEST_ID || `gen_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`);
  const wantedModelId = safe(process.env.XTERMINAL_GEN_MODEL_ID || '');
  const promptB64 = asText(process.env.XTERMINAL_GEN_PROMPT_B64 || '');
  const promptText = promptB64 ? Buffer.from(promptB64, 'base64').toString('utf8') : '';
  if (!safe(promptText)) {
    throw new Error('prompt_empty');
  }

  let modelId = wantedModelId;
  if (!modelId && modelsClient) {
    try {
      const models = await listModels(modelsClient, md, client);
      modelId = selectModelId(models, wantedModelId);
    } catch {}
  }
  if (!modelId) {
    throw new Error('no_model_routed');
  }

  const maxTokensRaw = Number.parseInt(safe(process.env.XTERMINAL_GEN_MAX_TOKENS || '768'), 10);
  const temperatureRaw = Number.parseFloat(safe(process.env.XTERMINAL_GEN_TEMPERATURE || '0.2'));
  const topPRaw = Number.parseFloat(safe(process.env.XTERMINAL_GEN_TOP_P || '0.95'));
  const timeoutSecRaw = Number.parseFloat(safe(process.env.XTERMINAL_GEN_TIMEOUT_SEC || '240'));

  const req = {
    request_id: reqId,
    client,
    model_id: modelId,
    messages: [{ role: 'user', content: promptText }],
    max_tokens: Math.max(1, Math.min(8192, Number.isFinite(maxTokensRaw) ? maxTokensRaw : 768)),
    temperature: Math.max(0, Math.min(2, Number.isFinite(temperatureRaw) ? temperatureRaw : 0.2)),
    top_p: Math.max(0.01, Math.min(1, Number.isFinite(topPRaw) ? topPRaw : 0.95)),
    stream: true,
    created_at_ms: Date.now(),
  };

  const streamResult = await generateOnce(
    aiClient,
    md,
    req,
    Math.max(8, Math.min(600, Number.isFinite(timeoutSecRaw) ? timeoutSecRaw : 240)) * 1000
  );

  const errPayload = streamResult?.error?.error || streamResult?.error || null;
  if (errPayload) {
    const code = safe(errPayload.code || '');
    const message = safe(errPayload.message || '');
    out({
      ok: false,
      text: '',
      model_id: streamResult?.model_id || modelId,
      reason: code || message || 'remote_chat_failed',
      error_code: code || message || 'remote_chat_failed',
      error_message: message || code || 'remote_chat_failed',
    });
    return;
  }

  const done = streamResult?.done || null;
  if (done && done.ok === false) {
    const reason = safe(done.reason || 'remote_chat_failed') || 'remote_chat_failed';
    out({
      ok: false,
      text: '',
      model_id: streamResult?.model_id || modelId,
      reason,
      error_code: reason,
      error_message: reason,
    });
    return;
  }

  const usage = done?.usage && typeof done.usage === 'object' ? done.usage : {};
  const promptTokens = Number(usage.prompt_tokens || 0) || 0;
  const completionTokens = Number(usage.completion_tokens || 0) || 0;
  const totalTokens = Number(usage.total_tokens || 0) || (promptTokens + completionTokens);

  out({
    ok: done ? done.ok !== false : true,
    text: asText(streamResult?.assistantText || ''),
    model_id: streamResult?.model_id || modelId,
    reason: safe(done?.reason || 'eos') || 'eos',
    prompt_tokens: promptTokens,
    completion_tokens: completionTokens,
    total_tokens: totalTokens,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    text: '',
    reason: msg || 'remote_chat_failed',
    error_code: msg || 'remote_chat_failed',
    error_message: msg || 'remote_chat_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remoteNetworkGrantScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function requestGrant(grantsClient, md, req) {
  return await new Promise((resolve, reject) => {
    grantsClient.RequestGrant(req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
}

async function waitGrantDecision(eventsClient, md, client, grantId, waitMs) {
  return await new Promise((resolve) => {
    let done = false;
    const finish = (payload) => {
      if (done) return;
      done = true;
      try { stream.cancel(); } catch {}
      clearTimeout(timer);
      resolve(payload || null);
    };

    const stream = eventsClient.Subscribe(
      {
        client,
        scopes: ['grants', 'requests'],
        last_event_id: '',
      },
      md
    );

    const timer = setTimeout(() => finish(null), Math.max(1000, waitMs));

    stream.on('data', (ev) => {
      const which = safe(ev?.ev || '');
      if (which !== 'grant_decision') return;
      const gd = ev?.grant_decision || null;
      const gid = safe(gd?.grant_request_id || '');
      if (!gid || gid !== grantId) return;
      finish({
        decision: safe(gd?.decision || ''),
        deny_reason: safe(gd?.deny_reason || ''),
      });
    });
    stream.on('error', () => finish(null));
    stream.on('end', () => finish(null));
  });
}

async function main() {
  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubGrants) {
    throw new Error('hub_grants_missing');
  }

  const { creds, options } = await makeClientCreds();
  const grantsClient = new proto.HubGrants(addr, creds, options);
  const eventsClient = proto?.HubEvents ? new proto.HubEvents(addr, creds, options) : null;
  const md = metadataFromEnv();
  const client = reqClientFromEnv();

  const capability = safe(process.env.XTERMINAL_GRANT_CAPABILITY || 'CAPABILITY_WEB_FETCH');
  const reqId = `grant_${capability.toLowerCase()}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const reqSecondsRaw = Number.parseInt(safe(process.env.XTERMINAL_GRANT_SECONDS || '900'), 10);
  const reqSeconds = Math.max(30, Math.min(86400, Number.isFinite(reqSecondsRaw) ? reqSecondsRaw : 900));
  const waitSecRaw = Number.parseInt(safe(process.env.XTERMINAL_GRANT_WAIT_SEC || '10'), 10);
  const waitSec = Math.max(0, Math.min(60, Number.isFinite(waitSecRaw) ? waitSecRaw : 10));
  const requestedTokenCapRaw = Number.parseInt(safe(process.env.XTERMINAL_GRANT_TOKEN_CAP || '0'), 10);
  const requestedTokenCap = Math.max(0, Math.min(5000, Number.isFinite(requestedTokenCapRaw) ? requestedTokenCapRaw : 0));
  const modelId = safe(process.env.XTERMINAL_GRANT_MODEL_ID || '');
  const reason = safe(process.env.XTERMINAL_GRANT_REASON || 'x_terminal need_network');

  if (capability === 'CAPABILITY_AI_GENERATE_PAID' && !modelId) {
    throw new Error('grant_model_id_missing');
  }

  const resp = await requestGrant(grantsClient, md, {
    request_id: reqId,
    client,
    capability,
    model_id: modelId,
    reason,
    requested_ttl_sec: reqSeconds,
    requested_token_cap: requestedTokenCap,
    created_at_ms: Date.now(),
  });

  const decisionRaw = safe(resp?.decision || '');
  const grantRequestId = safe(resp?.grant_request_id || reqId);
  const expiresAtMs = Number(resp?.expires_at_ms || 0) || 0;
  const denyReason = safe(resp?.deny_reason || '');

  if (decisionRaw === 'GRANT_DECISION_APPROVED') {
    out({
      ok: true,
      decision: 'approved',
      grant_request_id: grantRequestId,
      expires_at_ms: expiresAtMs,
      queued: false,
      auto_approved: true,
    });
    return;
  }

  if (decisionRaw === 'GRANT_DECISION_DENIED' || decisionRaw === 'GRANT_DECISION_REJECTED') {
    out({
      ok: false,
      decision: 'denied',
      grant_request_id: grantRequestId,
      expires_at_ms: expiresAtMs,
      reason: denyReason || 'grant_denied',
      queued: false,
      auto_approved: false,
      error_code: denyReason || 'grant_denied',
    });
    return;
  }

  if (decisionRaw === 'GRANT_DECISION_QUEUED' && waitSec > 0 && eventsClient) {
    const decided = await waitGrantDecision(eventsClient, md, client, grantRequestId, waitSec * 1000);
    const d = safe(decided?.decision || '');
    if (d === 'GRANT_DECISION_APPROVED') {
      out({
        ok: true,
        decision: 'approved',
        grant_request_id: grantRequestId,
        expires_at_ms: expiresAtMs,
        queued: false,
        auto_approved: false,
      });
      return;
    }
    if (d === 'GRANT_DECISION_DENIED' || d === 'GRANT_DECISION_REJECTED') {
      const deny = safe(decided?.deny_reason || 'grant_denied');
      out({
        ok: false,
        decision: 'denied',
        grant_request_id: grantRequestId,
        expires_at_ms: expiresAtMs,
        reason: deny,
        queued: false,
        auto_approved: false,
        error_code: deny,
      });
      return;
    }
  }

  out({
    ok: true,
    decision: 'queued',
    grant_request_id: grantRequestId,
    expires_at_ms: expiresAtMs,
    queued: true,
    auto_approved: false,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    decision: 'failed',
    error_code: msg || 'remote_grant_failed',
    error_message: msg || 'remote_grant_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remoteWebFetchScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function fetchOnce(webClient, md, req) {
  return await new Promise((resolve, reject) => {
    const stream = webClient.Fetch(req, md);
    let doneObj = null;
    const chunks = [];

    stream.on('data', (ev) => {
      const which = safe(ev?.ev || '');
      const chunk = ev?.chunk || (which === 'chunk' ? ev?.chunk : null);
      const done = ev?.done || (which === 'done' ? ev?.done : null);
      if (chunk?.data) {
        chunks.push(Buffer.from(chunk.data));
      }
      if (done) {
        doneObj = done;
      }
    });

    stream.on('end', () => resolve({ done: doneObj, chunks }));
    stream.on('error', (e) => reject(e));
  });
}

async function main() {
  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const fetchURL = safe(process.env.XTERMINAL_FETCH_URL || '');
  if (!fetchURL) {
    throw new Error('empty_url');
  }

  const timeoutRaw = Number.parseFloat(safe(process.env.XTERMINAL_FETCH_TIMEOUT_SEC || '12'));
  const timeoutSec = Math.max(2, Math.min(60, Number.isFinite(timeoutRaw) ? timeoutRaw : 12));
  const maxBytesRaw = Number.parseInt(safe(process.env.XTERMINAL_FETCH_MAX_BYTES || '1000000'), 10);
  const maxBytes = Math.max(1024, Math.min(5000000, Number.isFinite(maxBytesRaw) ? maxBytesRaw : 1000000));

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubWeb) {
    throw new Error('hub_web_missing');
  }

  const { creds, options } = await makeClientCreds();
  const webClient = new proto.HubWeb(addr, creds, options);
  const md = metadataFromEnv();
  const client = reqClientFromEnv();

  const req = {
    request_id: `web_fetch_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    client,
    url: fetchURL,
    method: 'GET',
    headers: {},
    timeout_sec: Math.floor(timeoutSec),
    max_bytes: Math.floor(maxBytes),
    created_at_ms: Date.now(),
    stream: false,
  };

  const resp = await fetchOnce(webClient, md, req);
  const done = resp?.done || null;
  const chunks = Array.isArray(resp?.chunks) ? resp.chunks : [];
  if (!done) {
    throw new Error('web_fetch_no_done_event');
  }

  let text = safe(done?.text || '');
  if (!text && chunks.length > 0) {
    try {
      text = Buffer.concat(chunks).toString('utf8');
    } catch {
      text = '';
    }
  }

  const errCode = safe(done?.error?.code || '');
  const errMessage = safe(done?.error?.message || '');

  out({
    ok: !!done?.ok,
    status: Number(done?.status || 0),
    final_url: safe(done?.final_url || fetchURL),
    content_type: safe(done?.content_type || ''),
    truncated: !!done?.truncated,
    bytes: Number(done?.bytes || 0),
    text,
    reason: errCode || errMessage || '',
    error_code: errCode || '',
    error_message: errMessage || '',
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    status: 0,
    final_url: safe(process.env.XTERMINAL_FETCH_URL || ''),
    content_type: '',
    truncated: false,
    bytes: 0,
    text: '',
    reason: msg || 'remote_web_fetch_failed',
    error_code: msg || 'remote_web_fetch_failed',
    error_message: msg || 'remote_web_fetch_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remoteProjectSyncScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  const projectId = safe(process.env.XTERMINAL_SYNC_PROJECT_ID || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }
  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function upsert(memoryClient, md, client, key, value) {
  return await new Promise((resolve, reject) => {
    memoryClient.UpsertCanonicalMemory(
      {
        client,
        scope: 'project',
        thread_id: '',
        key,
        value,
        pinned: false,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const client = reqClientFromEnv();
  if (!safe(client.project_id)) throw new Error('project_id_empty');

  const payload = {
    project_id: safe(process.env.XTERMINAL_SYNC_PROJECT_ID || ''),
    root_path: safe(process.env.XTERMINAL_SYNC_ROOT_PATH || ''),
    display_name: safe(process.env.XTERMINAL_SYNC_DISPLAY_NAME || ''),
    status_digest: safe(process.env.XTERMINAL_SYNC_STATUS_DIGEST || ''),
    last_summary_at: Number.parseFloat(safe(process.env.XTERMINAL_SYNC_LAST_SUMMARY_AT || '0')) || 0,
    last_event_at: Number.parseFloat(safe(process.env.XTERMINAL_SYNC_LAST_EVENT_AT || '0')) || 0,
    updated_at: Number.parseFloat(safe(process.env.XTERMINAL_SYNC_UPDATED_AT || `${Date.now() / 1000}`)) || (Date.now() / 1000),
  };

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();
  const key = 'xterminal.project.snapshot';
  const value = JSON.stringify(payload);
  await upsert(memoryClient, md, client, key, value);

  out({ ok: true });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({ ok: false, error_code: msg || 'remote_project_sync_failed', error_message: msg || 'remote_project_sync_failed' });
  process.exit(1);
});
"""#
    }

    private func remoteNotificationScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }
  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function getOrCreateThread(memoryClient, md, client, threadKey) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetOrCreateThread({ client, thread_key: threadKey }, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
  return resp?.thread || null;
}

async function appendTurns(memoryClient, md, client, threadId, content) {
  return await new Promise((resolve, reject) => {
    memoryClient.AppendTurns(
      {
        request_id: `xterminal_notify_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
        client,
        thread_id: threadId,
        messages: [{ role: 'assistant', content }],
        created_at_ms: Date.now(),
        allow_private: false,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function upsertLast(memoryClient, md, client, value) {
  return await new Promise((resolve, reject) => {
    memoryClient.UpsertCanonicalMemory(
      {
        client,
        scope: 'device',
        thread_id: '',
        key: 'xterminal.notification.last',
        value,
        pinned: false,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();

  const source = safe(process.env.XTERMINAL_NOTIFY_SOURCE || 'X-Terminal');
  const title = safe(process.env.XTERMINAL_NOTIFY_TITLE || '');
  const body = safe(process.env.XTERMINAL_NOTIFY_BODY || '');
  if (!title) throw new Error('title_empty');
  const dedupe = safe(process.env.XTERMINAL_NOTIFY_DEDUPE || '');
  const action = safe(process.env.XTERMINAL_NOTIFY_ACTION_URL || '');
  const unread = ['1', 'true', 'yes'].includes(safe(process.env.XTERMINAL_NOTIFY_UNREAD || '').toLowerCase());

  const payload = {
    source,
    title,
    body,
    dedupe_key: dedupe || null,
    action_url: action || null,
    unread,
    created_at: Date.now(),
  };
  const line = `[Notification] ${title}\n${body || '(no body)'}\nsource=${source}${action ? `\naction=${action}` : ''}${dedupe ? `\ndedupe=${dedupe}` : ''}`;

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();

  const th = await getOrCreateThread(memoryClient, md, client, 'xterminal_notifications');
  const threadId = safe(th?.thread_id || '');
  if (!threadId) throw new Error('thread_missing');

  await appendTurns(memoryClient, md, client, threadId, line);
  await upsertLast(memoryClient, md, client, JSON.stringify(payload));
  out({ ok: true });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({ ok: false, error_code: msg || 'remote_notification_failed', error_message: msg || 'remote_notification_failed' });
  process.exit(1);
});
"""#
    }

    private func remoteMemorySnapshotScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectIdOverride) {
  const projectId = safe(projectIdOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }
  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function listCanonical(memoryClient, md, client, scope, limit) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.ListCanonicalMemory(
      {
        client,
        scope,
        thread_id: '',
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
  return Array.isArray(resp?.items) ? resp.items : [];
}

async function getOrCreateThread(memoryClient, md, client, threadKey) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetOrCreateThread({ client, thread_key: threadKey }, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
  return resp?.thread || null;
}

async function getWorkingSet(memoryClient, md, client, threadId, limit) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetWorkingSet(
      {
        client,
        thread_id: threadId,
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
  return Array.isArray(resp?.messages) ? resp.messages : [];
}

function clipText(v, n = 360) {
  const s = safe(v);
  if (!s) return '';
  if (s.length <= n) return s;
  return `${s.slice(0, n)}…`;
}

async function main() {
  const mode = safe(process.env.XTERMINAL_MEM_MODE || 'project').toLowerCase();
  const projectId = safe(process.env.XTERMINAL_MEM_PROJECT_ID || '');
  const canonicalLimitRaw = Number.parseInt(safe(process.env.XTERMINAL_MEM_CANONICAL_LIMIT || '24'), 10);
  const workingLimitRaw = Number.parseInt(safe(process.env.XTERMINAL_MEM_WORKING_LIMIT || '12'), 10);
  const canonicalLimit = Math.max(1, Math.min(80, Number.isFinite(canonicalLimitRaw) ? canonicalLimitRaw : 24));
  const workingLimit = Math.max(1, Math.min(80, Number.isFinite(workingLimitRaw) ? workingLimitRaw : 12));

  const scope = mode === 'project' ? 'project' : 'device';
  const client = reqClientFromEnv(mode === 'project' ? projectId : '');
  if (scope === 'project' && !safe(client.project_id)) {
    throw new Error('project_id_empty');
  }

  const threadKey = scope === 'project'
    ? `xterminal_project_${safe(client.project_id)}`
    : 'xterminal_supervisor_device';

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();

  const canonicalItems = await listCanonical(memoryClient, md, client, scope, canonicalLimit);
  const canonicalEntries = canonicalItems
    .map((it) => {
      const key = safe(it?.key || '');
      const value = clipText(it?.value || '', 460);
      if (!key || !value) return '';
      return `${key} = ${value}`;
    })
    .filter(Boolean);

  const th = await getOrCreateThread(memoryClient, md, client, threadKey);
  const threadId = safe(th?.thread_id || '');
  let workingEntries = [];
  if (threadId) {
    const ws = await getWorkingSet(memoryClient, md, client, threadId, workingLimit);
    workingEntries = ws
      .map((m) => {
        const role = safe(m?.role || 'assistant');
        const content = clipText(m?.content || '', 420);
        if (!content) return '';
        return `${role}: ${content}`;
      })
      .filter(Boolean);
  }

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    canonical_entries: canonicalEntries,
    working_entries: workingEntries,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    canonical_entries: [],
    working_entries: [],
    reason: msg || 'remote_memory_snapshot_failed',
    error_code: msg || 'remote_memory_snapshot_failed',
    error_message: msg || 'remote_memory_snapshot_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remotePendingGrantRequestsScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const projectId = safe(process.env.XTERMINAL_PENDING_GRANTS_PROJECT_ID || '');
  const limitRaw = Number.parseInt(safe(process.env.XTERMINAL_PENDING_GRANTS_LIMIT || '200'), 10);
  const limit = Math.max(1, Math.min(500, Number.isFinite(limitRaw) ? limitRaw : 200));

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubRuntime) throw new Error('hub_runtime_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = new proto.HubRuntime(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    runtimeClient.GetPendingGrantRequests(
      {
        client,
        project_id: projectId,
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const items = Array.isArray(resp?.items)
    ? resp.items.map((it) => ({
        grant_request_id: safe(it?.grant_request_id || ''),
        request_id: safe(it?.request_id || ''),
        device_id: safe(it?.client?.device_id || ''),
        user_id: safe(it?.client?.user_id || ''),
        app_id: safe(it?.client?.app_id || ''),
        project_id: safe(it?.client?.project_id || ''),
        capability: safe(it?.capability || ''),
        model_id: safe(it?.model_id || ''),
        reason: safe(it?.reason || ''),
        requested_ttl_sec: asInt(it?.requested_ttl_sec || 0),
        requested_token_cap: asInt(it?.requested_token_cap || 0),
        status: safe(it?.status || ''),
        decision: safe(it?.decision || ''),
        created_at_ms: asMs(it?.created_at_ms || 0),
        decided_at_ms: asMs(it?.decided_at_ms || 0),
      })).filter((it) => it.grant_request_id)
    : [];

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    updated_at_ms: asMs(resp?.updated_at_ms || 0),
    items,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented') ? 'hub_runtime_unimplemented' : (msg || 'remote_pending_grants_failed');
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    updated_at_ms: 0,
    items: [],
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remotePendingGrantActionScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function callApprove(runtimeClient, md, req) {
  return await new Promise((resolve, reject) => {
    runtimeClient.ApprovePendingGrantRequest(req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
}

async function callDeny(runtimeClient, md, req) {
  return await new Promise((resolve, reject) => {
    runtimeClient.DenyPendingGrantRequest(req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
}

async function main() {
  const action = safe(process.env.XTERMINAL_PENDING_GRANT_ACTION || '').toLowerCase();
  if (action !== 'approve' && action !== 'deny') throw new Error('invalid_action');

  const grantRequestId = safe(process.env.XTERMINAL_PENDING_GRANT_ID || '');
  if (!grantRequestId) throw new Error('grant_request_id_empty');

  const projectId = safe(process.env.XTERMINAL_PENDING_GRANT_PROJECT_ID || '');
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubRuntime) throw new Error('hub_runtime_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv(projectId);
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = new proto.HubRuntime(addr, creds, options);

  if (action === 'approve') {
    const ttlRaw = Number.parseInt(safe(process.env.XTERMINAL_PENDING_GRANT_TTL_SEC || ''), 10);
    const tokenCapRaw = Number.parseInt(safe(process.env.XTERMINAL_PENDING_GRANT_TOKEN_CAP || ''), 10);
    const note = safe(process.env.XTERMINAL_PENDING_GRANT_NOTE || '');
    const req = {
      client,
      grant_request_id: grantRequestId,
      ttl_sec: Number.isFinite(ttlRaw) && ttlRaw > 0 ? Math.max(10, Math.min(86400, ttlRaw)) : 0,
      token_cap: Number.isFinite(tokenCapRaw) && tokenCapRaw > 0 ? Math.max(0, tokenCapRaw) : 0,
      note,
    };
    const resp = await callApprove(runtimeClient, md, req);
    out({
      ok: true,
      decision: 'approved',
      grant_request_id: safe(resp?.grant_request_id || grantRequestId),
      grant_id: safe(resp?.grant?.grant_id || ''),
      expires_at_ms: asMs(resp?.grant?.expires_at_ms || 0),
    });
    return;
  }

  const reason = safe(process.env.XTERMINAL_PENDING_GRANT_REASON || '');
  const resp = await callDeny(runtimeClient, md, {
    client,
    grant_request_id: grantRequestId,
    reason,
  });
  out({
    ok: true,
    decision: 'denied',
    grant_request_id: safe(resp?.grant_request_id || grantRequestId),
    grant_id: '',
    expires_at_ms: 0,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented')
    ? 'hub_runtime_unimplemented'
    : (msg || 'remote_pending_grant_action_failed');
  out({
    ok: false,
    decision: 'failed',
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remoteSchedulerStatusScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const includeQueueItems = ['1', 'true', 'yes', 'on'].includes(safe(process.env.XTERMINAL_SCHED_INCLUDE_QUEUE_ITEMS || '1').toLowerCase());
  const queueItemsLimitRaw = Number.parseInt(safe(process.env.XTERMINAL_SCHED_QUEUE_ITEMS_LIMIT || '80'), 10);
  const queueItemsLimit = Math.max(1, Math.min(500, Number.isFinite(queueItemsLimitRaw) ? queueItemsLimitRaw : 80));

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubRuntime) throw new Error('hub_runtime_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = new proto.HubRuntime(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    runtimeClient.GetSchedulerStatus(
      {
        client,
        include_queue_items: includeQueueItems,
        queue_items_limit: queueItemsLimit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const paid = resp?.paid_ai || {};
  const inFlightByScope = Array.isArray(paid?.in_flight_by_scope)
    ? paid.in_flight_by_scope.map((it) => ({
        scope_key: safe(it?.scope_key || ''),
        in_flight: asInt(it?.in_flight || 0),
      })).filter((it) => it.scope_key)
    : [];
  const queuedByScope = Array.isArray(paid?.queued_by_scope)
    ? paid.queued_by_scope.map((it) => ({
        scope_key: safe(it?.scope_key || ''),
        queued: asInt(it?.queued || 0),
      })).filter((it) => it.scope_key)
    : [];
  const queueItems = Array.isArray(paid?.queue_items)
    ? paid.queue_items.map((it) => ({
        request_id: safe(it?.request_id || ''),
        scope_key: safe(it?.scope_key || ''),
        enqueued_at_ms: asMs(it?.enqueued_at_ms || 0),
        queued_ms: asMs(it?.queued_ms || 0),
      })).filter((it) => it.request_id && it.scope_key)
    : [];

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    updated_at_ms: asMs(paid?.updated_at_ms || 0),
    in_flight_total: asInt(paid?.in_flight_total || 0),
    queue_depth: asInt(paid?.queue_depth || 0),
    oldest_queued_ms: asMs(paid?.oldest_queued_ms || 0),
    in_flight_by_scope: inFlightByScope,
    queued_by_scope: queuedByScope,
    queue_items: queueItems,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented') ? 'hub_runtime_unimplemented' : (msg || 'remote_scheduler_status_failed');
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    updated_at_ms: 0,
    in_flight_total: 0,
    queue_depth: 0,
    oldest_queued_ms: 0,
    in_flight_by_scope: [],
    queued_by_scope: [],
    queue_items: [],
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func emit(
        _ callback: (@Sendable (HubRemoteProgressEvent) -> Void)?,
        _ phase: HubRemoteProgressPhase,
        _ state: HubRemoteProgressState,
        _ detail: String?
    ) {
        callback?(HubRemoteProgressEvent(phase: phase, state: state, detail: detail))
    }

    private func inferFailureCode(from output: String, fallback: String) -> String {
        let text = output.lowercased()
        if text.isEmpty { return fallback }
        if let done = extractRegexGroup(text, pattern: #"(?m)^\[done\].*reason=([a-z0-9_.-]+)\s*$"#) {
            return done.replacingOccurrences(of: "-", with: "_")
        }
        if let errCode = extractRegexGroup(text, pattern: #"(?m)^\[error\]\s*([a-z0-9_.-]+)\s*:"#) {
            return errCode.replacingOccurrences(of: "-", with: "_")
        }
        if let fromParens = extractParenReason(text, prefix: "connect failed (") {
            return fromParens
        }
        if text.contains("bridge_disabled") { return "bridge_disabled" }
        if text.contains("bridge_unavailable") { return "bridge_unavailable" }
        if text.contains("remote_model_not_found") { return "remote_model_not_found" }
        if text.contains("api_key_missing") { return "api_key_missing" }
        if text.contains("base_url_invalid") { return "base_url_invalid" }
        if text.contains("grant_required") { return "grant_required" }
        if text.contains("permission_denied") { return "forbidden" }
        if text.contains("node_runtime_killed") || text.contains("node runtime killed") {
            return "node_runtime_killed"
        }
        if text.contains("permission denied") { return "permission_denied" }
        if text.contains("unknown command: discover") { return "discover_unsupported" }
        if text.contains("unknown command: connect") { return "connect_unsupported" }
        if text.contains("source_ip_not_allowed") || text.contains("source ip may not be allowed") {
            return "source_ip_not_allowed"
        }
        if text.contains("grpc_unavailable") { return "grpc_unavailable" }
        if text.contains("killed: 9")
            || text.contains("(exit=137)")
            || text.contains("(exit=134)")
            || text.contains("(exit=139)") {
            return "node_runtime_killed"
        }
        if text.contains("discovery_failed") { return "discovery_failed" }
        if text.contains("pairing_health_failed") { return "pairing_health_failed" }
        if text.contains("grpc_probe_failed") { return "grpc_probe_failed" }
        if text.contains("missing_pairing_secret") { return "missing_pairing_secret" }
        if text.contains("unauthenticated") { return "unauthenticated" }
        if text.contains("forbidden") || text.contains(" 403") { return "forbidden" }
        if text.contains("certificate") || text.contains("tls") { return "tls_error" }
        if text.contains("timeout") { return "timeout" }
        if text.contains("couldn't connect to server") || text.contains("failed to connect to") {
            return "hub_unreachable"
        }
        if text.contains("connection refused") { return "connection_refused" }
        if text.contains("network is unreachable") { return "network_unreachable" }
        if text.contains("doesn't exist") || text.contains("doesn’t exist") { return "file_not_found" }
        if text.contains("nscocoaerrordomain code=4") { return "file_not_found" }
        if text.contains("not found") { return "not_found" }
        if text.contains("client kit not installed") || text.contains("axhub_client_kit_not_found") {
            return "client_kit_missing"
        }
        return fallback
    }

    private func shouldRetryAfterClientKitInstall(_ output: String) -> Bool {
        let text = output.lowercased()
        return text.contains("client kit not installed")
            || text.contains("axhub_client_kit_not_found")
            || text.contains("client kit not available")
            || text.contains("killed: 9")
            || text.contains("missing node")
    }

    private func isUnknownCommand(_ output: String, command: String) -> Bool {
        output.lowercased().contains("unknown command: \(command.lowercased())")
    }

    private func parseListModelsOutput(_ output: String) -> [HubModel] {
        var rows: [HubModel] = []
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("- ") else { continue }
            let payload = String(trimmed.dropFirst(2))
            let fields = payload.components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard fields.count >= 2 else { continue }
            let name = fields[0]
            let modelId = fields[1]
            if modelId.isEmpty { continue }
            let kind = fields.count > 2 ? fields[2] : ""
            let backend = fields.count > 3 ? fields[3] : "unknown"
            let visibility = fields.count > 4 ? fields[4] : ""

            var roles: [String] = ["general"]
            let kindUpper = kind.uppercased()
            if kindUpper.contains("PAID") {
                roles.append("paid")
            } else if kindUpper.contains("LOCAL") {
                roles.append("local")
            }

            let noteParts = [kind, visibility]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            rows.append(
                HubModel(
                    id: modelId,
                    name: name.isEmpty ? modelId : name,
                    backend: backend.isEmpty ? "unknown" : backend,
                    quant: "",
                    contextLength: 8192,
                    paramsB: 0,
                    roles: roles,
                    // ListModels entries from paired Hub are directly routable in remote mode.
                    state: .loaded,
                    memoryBytes: nil,
                    tokensPerSec: nil,
                    modelPath: nil,
                    note: noteParts.isEmpty ? nil : noteParts.joined(separator: " | ")
                )
            )
        }
        return rows
    }

    private func extractChatAssistantText(_ output: String) -> String {
        let rawLines = output.components(separatedBy: .newlines)
        var content: [String] = []
        var started = false

        for raw in rawLines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                if started {
                    content.append("")
                }
                continue
            }

            if line.hasPrefix("Hub connected:")
                || line.hasPrefix("Using model:")
                || line.hasPrefix("Memory:")
                || line.hasPrefix("Usage:")
                || line.hasPrefix("Tips (interactive):")
                || line.hasPrefix("Next:")
                || line.hasPrefix("chat failed:")
                || line.hasPrefix("[grant]")
                || line.hasPrefix("[models]")
                || line.hasPrefix("[quota]")
                || line.hasPrefix("[killswitch]")
                || line.hasPrefix("[req]")
                || line.hasPrefix("[error]")
                || line.hasPrefix("[done]") {
                continue
            }

            started = true
            content.append(raw)
        }

        return content
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractParenReason(_ lowerText: String, prefix: String) -> String? {
        guard let start = lowerText.range(of: prefix) else { return nil }
        let tail = lowerText[start.upperBound...]
        guard let close = tail.firstIndex(of: ")") else { return nil }
        let raw = String(tail[..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = raw.replacingOccurrences(of: " ", with: "_")
        return cleaned.isEmpty ? nil : cleaned
    }

    private func extractRegexGroup(_ text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges >= 2 else { return nil }
        let g = m.range(at: 1)
        guard g.location != NSNotFound, g.length > 0 else { return nil }
        let out = ns.substring(with: g).trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    private func parsePortField(_ output: String, fieldName: String) -> Int? {
        let pattern = "(?m)^\\s*" + NSRegularExpression.escapedPattern(for: fieldName) + "\\s*:\\s*([0-9]{1,5})\\s*$"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = output as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: output, options: [], range: range), m.numberOfRanges > 1 else {
            return nil
        }
        let s = ns.substring(with: m.range(at: 1))
        return Int(s)
    }

    private func parseStringField(_ output: String, fieldName: String) -> String? {
        let pattern = "(?m)^\\s*" + NSRegularExpression.escapedPattern(for: fieldName) + "\\s*:\\s*(.+?)\\s*$"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = output as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: output, options: [], range: range), m.numberOfRanges > 1 else {
            return nil
        }
        let s = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private func preferredBootstrapHub(
        discoveredHubHost: String?,
        options: HubRemoteConnectOptions
    ) -> String {
        if let discoveredHubHost, !discoveredHubHost.isEmpty {
            return discoveredHubHost
        }
        let internetHost = options.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if !internetHost.isEmpty {
            return internetHost
        }
        return "127.0.0.1"
    }

    private func shouldRequireConfiguredHubHost(options: HubRemoteConnectOptions) -> Bool {
        let configured = options.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if configured.isEmpty { return false }
        return !isLoopbackHost(configured)
    }

    private func hostMatchesConfiguredHost(discoveredHost: String?, options: HubRemoteConnectOptions) -> Bool {
        let configured = normalizeHost(options.internetHost)
        guard !configured.isEmpty else { return true }
        guard let discoveredHost else { return false }
        return normalizeHost(discoveredHost) == configured
    }

    private func normalizeHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isLoopbackHost(_ host: String) -> Bool {
        let n = normalizeHost(host)
        return n == "localhost" || n == "127.0.0.1"
    }

    private func makeEphemeralStateDir(prefix: String) -> URL? {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            return tmp
        } catch {
            return nil
        }
    }

    private func removeEphemeralStateDir(_ dir: URL?) {
        guard let dir else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    private enum ExecutableRef {
        case direct(String)
        case bashScript(String)
        case viaEnv
    }

    private func resolveAxhubctlExecutable(override: String) -> ExecutableRef {
        let fm = FileManager.default

        if !override.isEmpty {
            let p = expandTilde(override)
            if fm.fileExists(atPath: p) {
                let best = preferredAxhubctlPath(primary: p)
                return fm.isExecutableFile(atPath: best) ? .direct(best) : .bashScript(best)
            }
        }

        if let bundled = bundledAxhubctlCandidate() {
            return fm.isExecutableFile(atPath: bundled) ? .direct(bundled) : .bashScript(bundled)
        }

        let home = fm.homeDirectoryForCurrentUser.path
        let directCandidates: [String] = [
            "\(home)/.local/bin/axhubctl",
            "\(home)/Documents/AX/x-hub-system/x-hub/grpc-server/hub_grpc_server/assets/axhubctl",
            "\(home)/Documents/AX/x-hub/grpc-server/hub_grpc_server/assets/axhubctl",
        ]

        for p in directCandidates {
            let e = expandTilde(p)
            if fm.fileExists(atPath: e) {
                let best = preferredAxhubctlPath(primary: e)
                return fm.isExecutableFile(atPath: best) ? .direct(best) : .bashScript(best)
            }
        }

        if let repo = repoRelativeAxhubctlCandidate(), fm.fileExists(atPath: repo) {
            let best = preferredAxhubctlPath(primary: repo)
            return fm.isExecutableFile(atPath: best) ? .direct(best) : .bashScript(best)
        }

        return .viaEnv
    }

    private func bundledAxhubctlCandidate() -> String? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let p = resourceURL.appendingPathComponent("axhubctl").path
        return FileManager.default.fileExists(atPath: p) ? p : nil
    }

    private func preferredAxhubctlPath(primary: String) -> String {
        guard !supportsModernAxhubctlCommands(at: primary),
              let bundled = bundledAxhubctlCandidate(),
              supportsModernAxhubctlCommands(at: bundled) else {
            return primary
        }
        return bundled
    }

    private func supportsModernAxhubctlCommands(at path: String) -> Bool {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return true
        }
        let lower = text.lowercased()
        return lower.contains("  discover)") && lower.contains("  connect)")
    }

    private func repoRelativeAxhubctlCandidate() -> String? {
        let fm = FileManager.default
        var url = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            let c1 = url
                .appendingPathComponent("x-hub/grpc-server/hub_grpc_server/assets/axhubctl")
                .path
            if fm.fileExists(atPath: c1) { return c1 }

            let c2 = url
                .appendingPathComponent("x-hub-system/x-hub/grpc-server/hub_grpc_server/assets/axhubctl")
                .path
            if fm.fileExists(atPath: c2) { return c2 }

            let c3 = url
                .appendingPathComponent("hub_grpc_server/assets/axhubctl")
                .path
            if fm.fileExists(atPath: c3) { return c3 }

            url.deleteLastPathComponent()
        }
        return nil
    }

    private func discoveryEnv(internetHost: String) -> [String: String] {
        let host = internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        var hints = ["127.0.0.1", "localhost"]
        if !host.isEmpty {
            hints.insert(host, at: 0)
        }
        return ["HUB_DISCOVERY_HINTS": hints.joined(separator: ",")]
    }

    private func mergedAxhubEnv(
        options: HubRemoteConnectOptions,
        extra: [String: String]
    ) -> [String: String] {
        var out = extra
        if let d = options.stateDir {
            out["AXHUBCTL_STATE_DIR"] = d.path
        }
        if out["AXHUBCTL_PREFER_BUNDLED_NODE"] == nil {
            out["AXHUBCTL_PREFER_BUNDLED_NODE"] = "0"
        }
        if out["AXHUBCTL_NODE_BIN"] == nil, let node = preferredNodeBinPath() {
            out["AXHUBCTL_NODE_BIN"] = node
        }
        return out
    }

    private func preferredNodeBinPath() -> String? {
        let fm = FileManager.default
        if let resourceNode = Bundle.main.resourceURL?.appendingPathComponent("relflowhub_node").path,
           fm.isExecutableFile(atPath: resourceNode) {
            return resourceNode
        }
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ]
        for c in candidates where fm.isExecutableFile(atPath: c) {
            return c
        }
        return nil
    }

    private func defaultStateDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".axhub", isDirectory: true)
    }

    private func loadCachedPairingInfo(stateDir: URL?) -> (host: String?, pairingPort: Int?, grpcPort: Int?) {
        let base = stateDir ?? defaultStateDir()
        let pairingEnv = base.appendingPathComponent("pairing.env")
        let hubEnv = base.appendingPathComponent("hub.env")

        let hostFromPairing = readEnvValue(from: pairingEnv, key: "AXHUB_HUB_HOST")
        let pairingPort = normalizePort(readEnvValue(from: pairingEnv, key: "AXHUB_PAIRING_PORT"))
        let grpcFromPairing = normalizePort(readEnvValue(from: pairingEnv, key: "AXHUB_GRPC_PORT"))

        let host = nonEmpty(hostFromPairing) ?? nonEmpty(readEnvValue(from: hubEnv, key: "HUB_HOST"))
        let grpcPort = grpcFromPairing ?? normalizePort(readEnvValue(from: hubEnv, key: "HUB_PORT"))

        return (host: host, pairingPort: pairingPort, grpcPort: grpcPort)
    }

    private func expandTilde(_ text: String) -> String {
        NSString(string: text).expandingTildeInPath
    }

    private func nonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizePort(_ raw: String?) -> Int? {
        guard let value = nonEmpty(raw), let p = Int(value), (1...65_535).contains(p) else {
            return nil
        }
        return p
    }

    private func readEnvValue(from fileURL: URL, key: String) -> String? {
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
            return unquoteShellValue(rhs)
        }
        return nil
    }

    private func unquoteShellValue(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
