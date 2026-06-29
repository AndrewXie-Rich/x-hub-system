import Foundation

extension HubPairingCoordinator {
    func ensureConnected(
        options rawOptions: HubRemoteConnectOptions,
        allowBootstrap: Bool,
        preferredRoute: XTHubRouteCandidate? = nil,
        candidateRoutes: [XTHubRouteCandidate] = [],
        handoffReason: String? = nil,
        cooldownApplied: Bool = false,
        onProgress: (@Sendable (HubRemoteProgressEvent) -> Void)? = nil
    ) async -> HubRemoteConnectReport {
        var opts = sanitize(rawOptions)
        var logs: [String] = []
        var discoveredHubHost: String?
        var bootstrapDisposition: HubRemoteBootstrapDisposition = allowBootstrap ? .freshPairingApproved : .connectOnly
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
        if nonEmpty(opts.internetHost) == nil, let cachedInternetHost = cachedPairing.internetHost {
            opts.internetHost = cachedInternetHost
        }
        logs.append(
            "[config] requested hub=\(nonEmpty(opts.internetHost) ?? "(auto)") pairing=\(opts.pairingPort) grpc=\(opts.grpcPort) authoritative=\(opts.configuredEndpointIsAuthoritative ? "true" : "false")"
        )
        let customEnv = discoveryEnv(
            internetHost: opts.internetHost,
            cachedPairing: cachedPairing,
            inviteAlias: opts.inviteAlias,
            inviteInstanceID: opts.inviteInstanceID,
            hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile
        )
        let effectiveAllowBootstrap: Bool
        if allowBootstrap {
            effectiveAllowBootstrap = true
        } else if !hasEnv {
            effectiveAllowBootstrap = true
            logs.append("[repair] missing hub.env; promote reconnect to bootstrap.")
        } else {
            effectiveAllowBootstrap = false
        }

        if effectiveAllowBootstrap {
            bootstrapDisposition = hasEnv ? .reusedExistingProfile : .freshPairingApproved
        } else {
            bootstrapDisposition = .connectOnly
        }

        if effectiveAllowBootstrap {
            if Self.shouldSkipDiscoveryForAuthoritativeBootstrap(
                configuredInternetHost: opts.internetHost,
                inviteToken: opts.inviteToken,
                configuredEndpointIsAuthoritative: opts.configuredEndpointIsAuthoritative,
                hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile
            ) {
                logs.append("[1/3] Discover Hub ...")
                if Self.shouldHonorConfiguredEndpointAuthority(
                    configuredInternetHost: opts.internetHost,
                    configuredEndpointIsAuthoritative: opts.configuredEndpointIsAuthoritative
                ) {
                    logs.append("[discover] skip: using user-configured hub endpoint for bootstrap.")
                    emit(onProgress, .discover, .skipped, "using_authoritative_configured_endpoint")
                } else {
                    logs.append("[discover] skip: using configured formal host for authoritative remote bootstrap.")
                    emit(onProgress, .discover, .skipped, "using_authoritative_formal_host")
                }
                discoveredHubHost = nonEmpty(opts.internetHost)
            } else {
                // Always try discover during one-click setup so stale pairing ports can self-heal.
                logs.append("[1/3] Discover Hub ...")
                emit(onProgress, .discover, .started, nil)
                var discoverSuccess = false
                var discoverUnsupported = false
                var lastDiscoverOutput = ""
                let candidates = orderedPairingPortCandidates(opts.pairingPort)
                var localDiscoveryBlockedReason: String?
                var ignoredLocalLoopbackDiscoverCandidate = false

                let knownHostProbe = await discoverHubViaKnownHosts(
                    options: opts,
                    pairingPorts: candidates,
                    cachedPairing: cachedPairing,
                    hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile
                )
                logs.append(contentsOf: knownHostProbe.logLines)
                if let candidate = knownHostProbe.candidate {
                    discoverSuccess = true
                    opts.pairingPort = candidate.pairingPort
                    opts.grpcPort = candidate.grpcPort
                    if nonEmpty(opts.internetHost) == nil,
                       let discoveredInternetHost = nonEmpty(candidate.internetHost) {
                        opts.internetHost = discoveredInternetHost
                    }
                    discoveredHubHost = candidate.host
                } else if let reason = knownHostProbe.reasonCode {
                    localDiscoveryBlockedReason = reason
                    lastDiscoverOutput = reason
                }

                if !discoverSuccess,
                   localDiscoveryBlockedReason == nil,
                   shouldAttemptLANDiscovery(
                    options: opts,
                    cachedPairing: cachedPairing,
                    allowConfiguredHostRepair: effectiveAllowBootstrap
                   ) {
                    let lanFallback = await discoverHubOnLAN(
                        options: opts,
                        pairingPorts: candidates,
                        cachedPairing: cachedPairing,
                        allowConfiguredHostRepair: effectiveAllowBootstrap
                    )
                    logs.append(contentsOf: lanFallback.logLines)
                    if let candidate = lanFallback.candidate {
                        discoverSuccess = true
                        opts.pairingPort = candidate.pairingPort
                        opts.grpcPort = candidate.grpcPort
                        if nonEmpty(opts.internetHost) == nil,
                           let discoveredInternetHost = nonEmpty(candidate.internetHost) {
                            opts.internetHost = discoveredInternetHost
                        }
                        discoveredHubHost = candidate.host
                    } else if let reason = lanFallback.reasonCode {
                        localDiscoveryBlockedReason = reason
                        lastDiscoverOutput = reason
                    }
                }

                if !discoverSuccess, localDiscoveryBlockedReason == nil {
                    let probeStateDir = makeEphemeralStateDir(prefix: "xterminal_discover_probe")
                    logs.append(contentsOf: prepareDiscoveryProbeState(
                        sourceStateDir: opts.stateDir,
                        probeStateDir: probeStateDir,
                        fallbackDeviceName: opts.deviceName
                    ))
                    var discoverOpts = opts
                    discoverOpts.stateDir = probeStateDir
                    for p in candidates {
                        let discover = runAxhubctl(
                            args: [
                                "discover",
                                "--pairing-port", "\(p)",
                                "--timeout-sec", "3",
                            ] + configuredDiscoverHintArgs(options: discoverOpts),
                            options: discoverOpts,
                            env: customEnv,
                            timeoutSec: 30.0
                        )
                        appendStepLogs(into: &logs, step: discover)
                        lastDiscoverOutput = discover.output
                        if discover.exitCode == 0 {
                            let parsedHost = parseStringField(discover.output, fieldName: "host")
                            let currentMachineHosts = Self.currentMachineIPv4Hosts()
                            if let parsedHost,
                               Self.isCurrentMachineHost(
                                parsedHost,
                                currentMachineHosts: currentMachineHosts
                               ),
                               shouldRequireConfiguredHubHost(options: opts) {
                                ignoredLocalLoopbackDiscoverCandidate = true
                                logs.append("[discover] ignore local XT Hub candidate while repairing remote host (got \(parsedHost))")
                                continue
                            }
                            if shouldPinDiscoveredHostToConfiguredRemote(options: opts),
                               !hostMatchesConfiguredHost(discoveredHost: parsedHost, options: opts) {
                                logs.append("[discover] ignore host mismatch (want \(opts.internetHost), got \(parsedHost ?? "unknown"))")
                                continue
                            }
                            if Self.shouldIgnoreDiscoveredLoopbackCandidate(
                                discoveredHost: parsedHost,
                                configuredInternetHost: opts.internetHost,
                                cachedPairing: cachedPairing,
                                hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile,
                                currentMachineHosts: currentMachineHosts
                            ) {
                                ignoredLocalLoopbackDiscoverCandidate = true
                                logs.append("[discover] ignore loopback candidate without authoritative local pairing state (got \(parsedHost ?? "unknown"))")
                                continue
                            }

                            guard let rawCandidate = parsedRawDiscoveryCandidate(
                                from: discover.output,
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
                                source: "discover"
                            ) {
                                localDiscoveryBlockedReason = repairBlock.reasonCode
                                lastDiscoverOutput = repairBlock.reasonCode
                                logs.append(repairBlock.detailLine)
                                break
                            }

                            discoverSuccess = true
                            opts.pairingPort = parsedCandidate.pairingPort
                            opts.grpcPort = parsedCandidate.grpcPort
                            if nonEmpty(opts.internetHost) == nil,
                               let parsedInternetHost = nonEmpty(parsedCandidate.internetHost) {
                                opts.internetHost = parsedInternetHost
                            }
                            discoveredHubHost = parsedCandidate.host
                            logs.append(contentsOf: persistDiscoveryCandidate(parsedCandidate, options: opts, source: "discover"))
                            break
                        } else if isUnknownCommand(discover.output, command: "discover") {
                            discoverUnsupported = true
                            break
                        }
                    }
                    removeEphemeralStateDir(probeStateDir)
                }

                if discoverSuccess {
                    emit(onProgress, .discover, .succeeded, nil)
                } else if let blockedReason = localDiscoveryBlockedReason,
                          Self.shouldFailClosedOnDiscoveryReason(blockedReason) {
                    emit(onProgress, .discover, .failed, blockedReason)
                    emit(onProgress, .bootstrap, .skipped, "blocked_by_discover_failure")
                    emit(onProgress, .connect, .skipped, "blocked_by_discover_failure")
                    return HubRemoteConnectReport(
                        ok: false,
                        route: .none,
                        summary: blockedReason,
                        logLines: logs,
                        reasonCode: blockedReason
                    )
                } else if let blockedReason = localDiscoveryBlockedReason, hasEnv {
                    logs.append("[discover] multiple LAN hubs detected; keep existing paired profile.")
                    emit(onProgress, .discover, .failed, blockedReason)
                } else if let blockedReason = localDiscoveryBlockedReason {
                    emit(onProgress, .discover, .failed, blockedReason)
                    emit(onProgress, .bootstrap, .skipped, "blocked_by_discover_failure")
                    emit(onProgress, .connect, .skipped, "blocked_by_discover_failure")
                    return HubRemoteConnectReport(
                        ok: false,
                        route: .none,
                        summary: blockedReason,
                        logLines: logs,
                        reasonCode: blockedReason
                    )
                } else if let loopbackOnlyReason = Self.loopbackOnlyDiscoveryFailureReason(
                    ignoredLoopbackCandidate: ignoredLocalLoopbackDiscoverCandidate,
                    hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile
                ) {
                    logs.append("[discover] remote LAN discovery is blocked; XT only saw its own loopback Hub. Check Local Network permission or Wi-Fi client isolation.")
                    emit(onProgress, .discover, .failed, loopbackOnlyReason)
                    emit(onProgress, .bootstrap, .skipped, "blocked_by_discover_failure")
                    emit(onProgress, .connect, .skipped, "blocked_by_discover_failure")
                    return HubRemoteConnectReport(
                        ok: false,
                        route: .none,
                        summary: loopbackOnlyReason,
                        logLines: logs,
                        reasonCode: loopbackOnlyReason
                    )
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
            }
        } else {
            if Self.shouldHonorConfiguredEndpointAuthority(
                configuredInternetHost: opts.internetHost,
                configuredEndpointIsAuthoritative: opts.configuredEndpointIsAuthoritative
            ) {
                logs.append("[1/3] Discover Hub ...")
                logs.append("[discover] skip: using user-configured hub endpoint for reconnect.")
                discoveredHubHost = nonEmpty(opts.internetHost)
                emit(onProgress, .discover, .skipped, "using_authoritative_configured_endpoint")
            } else if Self.shouldRunLANDiscoveryPrepassValue(
                configuredInternetHost: opts.internetHost,
                cachedPairing: cachedPairing,
                allowConfiguredHostRepair: true,
                configuredEndpointIsAuthoritative: opts.configuredEndpointIsAuthoritative
            ) {
                logs.append("[1/3] Discover Hub ...")
                emit(onProgress, .discover, .started, "repair_reconnect")

                var discoverSuccess = false
                var discoverUnsupported = false
                var lastDiscoverOutput = ""
                var localDiscoveryBlockedReason: String?
                let candidates = orderedPairingPortCandidates(opts.pairingPort)
                var ignoredLocalLoopbackDiscoverCandidate = false

                let knownHostProbe = await discoverHubViaKnownHosts(
                    options: opts,
                    pairingPorts: candidates,
                    cachedPairing: cachedPairing,
                    hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile
                )
                logs.append(contentsOf: knownHostProbe.logLines)
                if let candidate = knownHostProbe.candidate {
                    discoverSuccess = true
                    opts.pairingPort = candidate.pairingPort
                    opts.grpcPort = candidate.grpcPort
                    if nonEmpty(opts.internetHost) == nil,
                       let discoveredInternetHost = nonEmpty(candidate.internetHost) {
                        opts.internetHost = discoveredInternetHost
                    }
                    discoveredHubHost = candidate.host
                } else if let reason = knownHostProbe.reasonCode {
                    localDiscoveryBlockedReason = reason
                    lastDiscoverOutput = reason
                }

                if !discoverSuccess, localDiscoveryBlockedReason == nil {
                    let lanFallback = await discoverHubOnLAN(
                        options: opts,
                        pairingPorts: candidates,
                        cachedPairing: cachedPairing,
                        allowConfiguredHostRepair: true
                    )
                    logs.append(contentsOf: lanFallback.logLines)
                    if let candidate = lanFallback.candidate {
                        discoverSuccess = true
                        opts.pairingPort = candidate.pairingPort
                        opts.grpcPort = candidate.grpcPort
                        if nonEmpty(opts.internetHost) == nil,
                           let discoveredInternetHost = nonEmpty(candidate.internetHost) {
                            opts.internetHost = discoveredInternetHost
                        }
                        discoveredHubHost = candidate.host
                    } else if let reason = lanFallback.reasonCode {
                        localDiscoveryBlockedReason = reason
                        lastDiscoverOutput = reason
                    }
                }

                if !discoverSuccess, localDiscoveryBlockedReason == nil {
                    let probeStateDir = makeEphemeralStateDir(prefix: "xterminal_reconnect_probe")
                    logs.append(contentsOf: prepareDiscoveryProbeState(
                        sourceStateDir: opts.stateDir,
                        probeStateDir: probeStateDir,
                        fallbackDeviceName: opts.deviceName
                    ))
                    var discoverOpts = opts
                    discoverOpts.stateDir = probeStateDir
                    for p in candidates {
                        let discover = runAxhubctl(
                            args: [
                                "discover",
                                "--pairing-port", "\(p)",
                                "--timeout-sec", "3",
                            ] + configuredDiscoverHintArgs(options: discoverOpts),
                            options: discoverOpts,
                            env: customEnv,
                            timeoutSec: 30.0
                        )
                        appendStepLogs(into: &logs, step: discover)
                        lastDiscoverOutput = discover.output
                        if discover.exitCode == 0 {
                            let parsedHost = parseStringField(discover.output, fieldName: "host")
                            let currentMachineHosts = Self.currentMachineIPv4Hosts()
                            if let parsedHost,
                               Self.isCurrentMachineHost(
                                parsedHost,
                                currentMachineHosts: currentMachineHosts
                               ),
                               shouldRequireConfiguredHubHost(options: opts) {
                                ignoredLocalLoopbackDiscoverCandidate = true
                                logs.append("[discover] ignore local XT Hub candidate while repairing remote host (got \(parsedHost))")
                                continue
                            }
                            if shouldPinDiscoveredHostToConfiguredRemote(options: opts),
                               !hostMatchesConfiguredHost(discoveredHost: parsedHost, options: opts) {
                                logs.append("[discover] ignore host mismatch (want \(opts.internetHost), got \(parsedHost ?? "unknown"))")
                                continue
                            }
                            if Self.shouldIgnoreDiscoveredLoopbackCandidate(
                                discoveredHost: parsedHost,
                                configuredInternetHost: opts.internetHost,
                                cachedPairing: cachedPairing,
                                hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile,
                                currentMachineHosts: currentMachineHosts
                            ) {
                                ignoredLocalLoopbackDiscoverCandidate = true
                                logs.append("[discover] ignore loopback candidate without authoritative local pairing state (got \(parsedHost ?? "unknown"))")
                                continue
                            }

                            guard let rawCandidate = parsedRawDiscoveryCandidate(
                                from: discover.output,
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
                                source: "discover"
                            ) {
                                localDiscoveryBlockedReason = repairBlock.reasonCode
                                lastDiscoverOutput = repairBlock.reasonCode
                                logs.append(repairBlock.detailLine)
                                break
                            }

                            discoverSuccess = true
                            opts.pairingPort = parsedCandidate.pairingPort
                            opts.grpcPort = parsedCandidate.grpcPort
                            if nonEmpty(opts.internetHost) == nil,
                               let parsedInternetHost = nonEmpty(parsedCandidate.internetHost) {
                                opts.internetHost = parsedInternetHost
                            }
                            discoveredHubHost = parsedCandidate.host
                            logs.append(contentsOf: persistDiscoveryCandidate(parsedCandidate, options: opts, source: "discover"))
                            break
                        } else if isUnknownCommand(discover.output, command: "discover") {
                            discoverUnsupported = true
                            break
                        }
                    }
                    removeEphemeralStateDir(probeStateDir)
                }

                if discoverSuccess {
                    emit(onProgress, .discover, .succeeded, "repair_reconnect")
                } else if let blockedReason = localDiscoveryBlockedReason,
                          Self.shouldFailClosedOnDiscoveryReason(blockedReason) {
                    emit(onProgress, .discover, .failed, blockedReason)
                    emit(onProgress, .bootstrap, .skipped, "blocked_by_discover_failure")
                    emit(onProgress, .connect, .skipped, "blocked_by_discover_failure")
                    return HubRemoteConnectReport(
                        ok: false,
                        route: .none,
                        summary: blockedReason,
                        logLines: logs,
                        reasonCode: blockedReason
                    )
                } else if let blockedReason = localDiscoveryBlockedReason {
                    logs.append("[discover] reconnect repair blocked; keep existing paired profile.")
                    emit(onProgress, .discover, .failed, blockedReason)
                } else if let loopbackOnlyReason = Self.loopbackOnlyDiscoveryFailureReason(
                    ignoredLoopbackCandidate: ignoredLocalLoopbackDiscoverCandidate,
                    hasAuthoritativeLocalProfile: hasAuthoritativeLocalProfile
                ) {
                    logs.append("[discover] remote LAN discovery is blocked; XT only saw its own loopback Hub. Check Local Network permission or Wi-Fi client isolation.")
                    emit(onProgress, .discover, .failed, loopbackOnlyReason)
                    emit(onProgress, .bootstrap, .skipped, "blocked_by_discover_failure")
                    emit(onProgress, .connect, .skipped, "blocked_by_discover_failure")
                    return HubRemoteConnectReport(
                        ok: false,
                        route: .none,
                        summary: loopbackOnlyReason,
                        logLines: logs,
                        reasonCode: loopbackOnlyReason
                    )
                } else if discoverUnsupported {
                    emit(onProgress, .discover, .skipped, "discover_unsupported_using_existing_profile")
                } else {
                    let reason = inferFailureCode(from: lastDiscoverOutput, fallback: "discover_failed_using_cached_profile")
                    logs.append("[discover] reconnect repair failed; keep existing paired profile.")
                    emit(onProgress, .discover, .failed, reason)
                }
            } else {
                emit(onProgress, .discover, .skipped, "bootstrap_disabled")
            }
            emit(onProgress, .bootstrap, .skipped, "bootstrap_disabled")
        }

        if effectiveAllowBootstrap && !hasEnv {
            logs.append("[2/3] Pair + bootstrap (wait approval) ...")
            emit(onProgress, .bootstrap, .started, "awaiting_hub_approval")
            let bootstrapHost = preferredBootstrapHub(discoveredHubHost: discoveredHubHost, options: opts)
            let bootstrap = runAxhubctl(
                args: [
                    "bootstrap",
                    "--hub", bootstrapHost,
                    "--pairing-port", "\(opts.pairingPort)",
                    "--grpc-port", "\(opts.grpcPort)",
                    "--device-name", opts.deviceName,
                ] + hubInviteTokenArgs(opts),
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
                logs.append(contentsOf: explainBootstrapFailureIfNeeded(
                    reason: reason,
                    bootstrapHost: bootstrapHost,
                    options: opts
                ))
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
        } else if effectiveAllowBootstrap {
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
            autoReconnect: false,
            preferredRoute: preferredRoute,
            candidateRoutes: candidateRoutes,
            handoffReason: handoffReason,
            cooldownApplied: cooldownApplied
        )
        if firstConnect.ok {
            firstConnect.summary = connectedSummary(
                route: firstConnect.route,
                bootstrapDisposition: bootstrapDisposition
            )
            firstConnect.completedFreshPairing = (bootstrapDisposition == .freshPairingApproved)
            return firstConnect
        }

        // If one-click setup starts from an existing profile and connect fails, try a bootstrap refresh once.
        if effectiveAllowBootstrap && hasEnv {
            if Self.shouldSkipBootstrapRefreshAfterConnectFailure(firstConnect.reasonCode) {
                let blockedReason = Self.sanitizedReasonToken(firstConnect.reasonCode) ?? "identity_repair_required"
                logs.append("[bootstrap] skip refresh: connect failure \(blockedReason) requires pairing/identity repair.")
                emit(onProgress, .bootstrap, .skipped, "blocked_by_identity_failure")
                firstConnect.logLines = logs
                return firstConnect
            }
            logs.append("[2/3] Refresh pairing via bootstrap (connect failed with cached profile) ...")
            emit(onProgress, .bootstrap, .started, "refresh")
            let refreshBootstrap = runAxhubctl(
                args: [
                    "bootstrap",
                    "--hub", preferredBootstrapHub(discoveredHubHost: discoveredHubHost, options: opts),
                    "--pairing-port", "\(opts.pairingPort)",
                    "--grpc-port", "\(opts.grpcPort)",
                    "--device-name", opts.deviceName,
                ] + hubInviteTokenArgs(opts),
                options: opts,
                env: customEnv,
                timeoutSec: 1_300.0
            )
            appendStepLogs(into: &logs, step: refreshBootstrap)
            guard refreshBootstrap.exitCode == 0 else {
                let reason = inferFailureCode(from: refreshBootstrap.output, fallback: "bootstrap_refresh_failed")
                logs.append(contentsOf: explainBootstrapFailureIfNeeded(
                    reason: reason,
                    bootstrapHost: preferredBootstrapHub(discoveredHubHost: discoveredHubHost, options: opts),
                    options: opts
                ))
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
            bootstrapDisposition = .refreshedExistingProfile

            firstConnect = connectWithFallback(
                options: opts,
                primaryHubHost: discoveredHubHost,
                env: customEnv,
                logs: &logs,
                onProgress: onProgress,
                startProgress: true,
                autoReconnect: false,
                preferredRoute: preferredRoute,
                candidateRoutes: candidateRoutes,
                handoffReason: handoffReason,
                cooldownApplied: cooldownApplied
            )
            if firstConnect.ok {
                firstConnect.summary = connectedSummary(
                    route: firstConnect.route,
                    bootstrapDisposition: bootstrapDisposition
                )
                firstConnect.completedFreshPairing = (bootstrapDisposition == .freshPairingApproved)
            }
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
        autoReconnect: Bool,
        preferredRoute: XTHubRouteCandidate?,
        candidateRoutes: [XTHubRouteCandidate],
        handoffReason: String?,
        cooldownApplied: Bool
    ) -> HubRemoteConnectReport {
        let preferredHub = preferredConnectHub(primaryHubHost: primaryHubHost, options: opts)
        let useAutoDiscovery = normalizeHost(preferredHub) == "auto"
        let orderedCandidates = Self.orderedConnectRouteCandidates(
            requestedCandidates: candidateRoutes,
            preferredRoute: preferredRoute,
            internetHost: opts.internetHost
        )
        let selectedRoute = preferredRoute ?? orderedCandidates.first

        logs.append(connectProbeHeading(
            autoReconnect: autoReconnect,
            selectedRoute: selectedRoute,
            preferredHub: preferredHub,
            useAutoDiscovery: useAutoDiscovery,
            internetHost: opts.internetHost
        ))

        if hasHubEnv(stateDir: opts.stateDir), !hasInstalledClientKit(stateDir: opts.stateDir) {
            let repairHosts = connectRepairHosts(primaryHubHost: preferredHub, options: opts)
            if maybeInstallClientKit(
                options: opts,
                hosts: repairHosts,
                env: customEnv,
                logs: &logs
            ) {
                logs.append("[repair] client kit restored before connect probe.")
            }
        }
        var attemptedRoutes: [XTHubRouteCandidate] = []
        var failureOutputs: [String] = []

        for (index, candidate) in orderedCandidates.enumerated() {
            attemptedRoutes.append(candidate)
            if startProgress || index > 0 {
                emit(onProgress, .connect, .started, candidate.progressDetail)
            }

            let outcome: HubRemoteConnectAttemptOutcome
            switch candidate {
            case .lanDirect:
                outcome = attemptLANConnect(
                    options: opts,
                    preferredHub: preferredHub,
                    env: customEnv,
                    logs: &logs,
                    onProgress: onProgress,
                    autoReconnect: autoReconnect
                )
            case .stableNamedRemote:
                outcome = attemptInternetConnect(
                    options: opts,
                    env: customEnv,
                    logs: &logs,
                    onProgress: onProgress,
                    autoReconnect: autoReconnect
                )
            case .managedTunnelFallback:
                outcome = attemptTunnelConnect(
                    options: opts,
                    env: customEnv,
                    logs: &logs,
                    onProgress: onProgress,
                    autoReconnect: autoReconnect
                )
            }

            switch outcome {
            case .succeeded(var report):
                report.selectedRoute = selectedRoute ?? candidate
                report.attemptedRoutes = attemptedRoutes
                report.handoffReason = handoffReason
                report.cooldownApplied = cooldownApplied
                return report
            case .legacy(var report):
                report.selectedRoute = selectedRoute ?? candidate
                report.attemptedRoutes = attemptedRoutes
                report.handoffReason = handoffReason
                report.cooldownApplied = cooldownApplied
                return report
            case .failed(let output):
                failureOutputs.append(output)
            }
        }

        let fallbackReason = opts.internetHost.isEmpty || orderedCandidates == [.lanDirect]
            ? "connect_failed"
            : "connect_failed_after_internet_fallback"
        let reason = inferFailureCode(
            from: failureOutputs.joined(separator: "\n"),
            fallback: fallbackReason
        )
        emit(onProgress, .connect, .failed, reason)
        return HubRemoteConnectReport(
            ok: false,
            route: .none,
            summary: reason,
            logLines: logs,
            reasonCode: reason,
            selectedRoute: selectedRoute,
            attemptedRoutes: attemptedRoutes,
            handoffReason: handoffReason,
            cooldownApplied: cooldownApplied
        )
    }

    private func connectProbeHeading(
        autoReconnect: Bool,
        selectedRoute: XTHubRouteCandidate?,
        preferredHub: String,
        useAutoDiscovery: Bool,
        internetHost: String
    ) -> String {
        let prefix = autoReconnect ? "[3/3] Connect + auto-reconnect probe" : "[3/3] Connect probe"
        switch selectedRoute {
        case .some(.stableNamedRemote):
            let host = nonEmpty(internetHost) ?? preferredHub
            let label = HubRemoteHostPolicy.isFormalRemoteHost(host)
                ? "formal remote first"
                : "internet direct first"
            return "\(prefix) (\(label): \(host)) ..."
        case .some(.managedTunnelFallback):
            let host = nonEmpty(internetHost) ?? preferredHub
            return "\(prefix) (managed tunnel first: \(host)) ..."
        case .some(.lanDirect), .none:
            if useAutoDiscovery {
                return "\(prefix) (LAN first) ..."
            }
            return "\(prefix) (preferred host: \(preferredHub)) ..."
        }
    }

    private func attemptLANConnect(
        options opts: HubRemoteConnectOptions,
        preferredHub: String,
        env customEnv: [String: String],
        logs: inout [String],
        onProgress: (@Sendable (HubRemoteProgressEvent) -> Void)?,
        autoReconnect: Bool
    ) -> HubRemoteConnectAttemptOutcome {
        var lanArgs: [String] = [
            "connect",
            "--hub", preferredHub,
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
            do {
                if try persistDirectRemoteRouteState(
                    host: preferredHub,
                    pairingPort: opts.pairingPort,
                    grpcPort: opts.grpcPort,
                    internetHost: nonEmpty(opts.internetHost),
                    options: opts
                ) {
                    logs.append("[state-sync] remote endpoint cached as \(preferredHub):\(opts.grpcPort).")
                }
            } catch {
                logs.append("[state-sync] direct_route_state_sync_failed: \(error.localizedDescription)")
            }
            emit(onProgress, .connect, .succeeded, "lan")
            return .succeeded(
                HubRemoteConnectReport(
                    ok: true,
                    route: .lan,
                    summary: "connected_lan",
                    logLines: logs,
                    reasonCode: nil
                )
            )
        }

        if isUnknownCommand(lanConnect.output, command: "connect") {
            return .legacy(
                legacyConnectWithListModels(
                    options: opts,
                    env: customEnv,
                    logs: &logs,
                    onProgress: onProgress
                )
            )
        }

        return .failed(lanConnect.output)
    }

    private func attemptInternetConnect(
        options opts: HubRemoteConnectOptions,
        env customEnv: [String: String],
        logs: inout [String],
        onProgress: (@Sendable (HubRemoteProgressEvent) -> Void)?,
        autoReconnect: Bool
    ) -> HubRemoteConnectAttemptOutcome {
        guard !opts.internetHost.isEmpty else {
            return .failed("internet_host_missing")
        }

        logs.append("[handoff] Try stable remote direct ...")
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
            do {
                if try persistDirectRemoteRouteState(
                    host: opts.internetHost,
                    pairingPort: opts.pairingPort,
                    grpcPort: opts.grpcPort,
                    internetHost: nonEmpty(opts.internetHost),
                    options: opts
                ) {
                    logs.append("[state-sync] remote endpoint cached as \(opts.internetHost):\(opts.grpcPort).")
                }
            } catch {
                logs.append("[state-sync] direct_route_state_sync_failed: \(error.localizedDescription)")
            }
            emit(onProgress, .connect, .succeeded, "internet")
            return .succeeded(
                HubRemoteConnectReport(
                    ok: true,
                    route: .internet,
                    summary: "connected_internet",
                    logLines: logs,
                    reasonCode: nil
                )
            )
        }

        if isUnknownCommand(internetConnect.output, command: "connect") {
            return .legacy(
                legacyConnectWithListModels(
                    options: opts,
                    env: customEnv,
                    logs: &logs,
                    onProgress: onProgress
                )
            )
        }

        return .failed(internetConnect.output)
    }

    private func attemptTunnelConnect(
        options opts: HubRemoteConnectOptions,
        env customEnv: [String: String],
        logs: inout [String],
        onProgress: (@Sendable (HubRemoteProgressEvent) -> Void)?,
        autoReconnect: Bool
    ) -> HubRemoteConnectAttemptOutcome {
        guard !opts.internetHost.isEmpty else {
            return .failed("internet_host_missing")
        }

        logs.append("[handoff] Install/refresh managed tunnel + connect localhost ...")
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
        if tunnelInstall.exitCode == 0 {
            if waitForLoopbackTunnelListener(port: opts.grpcPort, timeoutSec: 3.0) {
                logs.append("[handoff] Managed tunnel localhost ready.")
            } else {
                logs.append("[handoff] Managed tunnel localhost not ready before probe; continuing anyway.")
            }
        }

        let tunnelProbe = verifyLoopbackTunnelGRPC(
            options: opts,
            host: "127.0.0.1",
            port: opts.grpcPort,
            timeoutSec: autoReconnect ? 14.0 : 10.0
        )
        appendStepLogs(into: &logs, step: tunnelProbe)
        if tunnelProbe.exitCode == 0 {
            do {
                try persistLoopbackTunnelRouteState(
                    host: "127.0.0.1",
                    pairingPort: opts.pairingPort,
                    grpcPort: opts.grpcPort,
                    internetHost: nonEmpty(opts.internetHost),
                    options: opts
                )
                logs.append("[handoff] Tunnel route persisted as loopback profile.")
                emit(onProgress, .connect, .succeeded, "tunnel")
                return .succeeded(
                    HubRemoteConnectReport(
                        ok: true,
                        route: .internetTunnel,
                        summary: "connected_internet_tunnel",
                        logLines: logs,
                        reasonCode: nil
                    )
                )
            } catch {
                appendStepLogs(
                    into: &logs,
                    step: StepOutput(
                        exitCode: 1,
                        output: "loopback tunnel state persist failed: \(error.localizedDescription)",
                        command: "persist_loopback_tunnel_route_state"
                    )
                )
            }
        }

        return .failed([tunnelProbe.output, tunnelInstall.output].joined(separator: "\n"))
    }

    private nonisolated static func orderedConnectRouteCandidates(
        requestedCandidates: [XTHubRouteCandidate],
        preferredRoute: XTHubRouteCandidate?,
        internetHost: String
    ) -> [XTHubRouteCandidate] {
        let hasFormalRemote = HubRemoteHostPolicy.isFormalRemoteHost(internetHost)
        let hasDirectInternetRemote = HubRemoteHostPolicy.isDirectInternetRemoteHost(internetHost)
        let canUseManagedTunnel = HubRemoteHostPolicy.isStableNamedRemoteHost(internetHost)
        var candidates = requestedCandidates
        if candidates.isEmpty {
            candidates = [.lanDirect]
            if hasDirectInternetRemote {
                // Keep global connect/reconnect conservative. Tunnel is opt-in via
                // explicit request-scoped handoff or an explicit preferred route.
                candidates.append(.stableNamedRemote)
            }
        }
        if let preferredRoute {
            switch preferredRoute {
            case .lanDirect:
                candidates.append(.lanDirect)
            case .stableNamedRemote:
                if hasDirectInternetRemote {
                    candidates.append(preferredRoute)
                }
            case .managedTunnelFallback:
                if canUseManagedTunnel {
                    candidates.append(preferredRoute)
                }
            }
        }
        if !hasDirectInternetRemote {
            candidates.removeAll { $0 == .stableNamedRemote }
        }
        if !canUseManagedTunnel {
            candidates.removeAll { $0 == .managedTunnelFallback }
        }
        if let preferredRoute, candidates.contains(preferredRoute) {
            candidates.removeAll { $0 == preferredRoute }
            candidates.insert(preferredRoute, at: 0)
        }
        if !hasDirectInternetRemote {
            candidates.removeAll { $0 != .lanDirect }
        }
        if !hasFormalRemote {
            candidates.removeAll { $0 == .managedTunnelFallback }
        }

        var ordered: [XTHubRouteCandidate] = []
        for candidate in candidates where !ordered.contains(candidate) {
            ordered.append(candidate)
        }
        return ordered.isEmpty ? [.lanDirect] : ordered
    }

    nonisolated static func orderedConnectRouteCandidatesForTesting(
        requestedCandidates: [XTHubRouteCandidate],
        preferredRoute: XTHubRouteCandidate?,
        internetHost: String
    ) -> [XTHubRouteCandidate] {
        orderedConnectRouteCandidates(
            requestedCandidates: requestedCandidates,
            preferredRoute: preferredRoute,
            internetHost: internetHost
        )
    }

    private func preferredConnectHub(
        primaryHubHost: String?,
        options: HubRemoteConnectOptions
    ) -> String {
        let cachedPairing = loadCachedPairingInfo(stateDir: options.stateDir)
        return Self.preferredConnectHubValue(
            primaryHubHost: primaryHubHost,
            configuredInternetHost: options.internetHost,
            cachedHost: cachedPairing.host,
            cachedInternetHost: cachedPairing.internetHost,
            currentMachineHosts: Self.currentMachineIPv4Hosts()
        )
    }

    nonisolated static func preferredConnectHubValue(
        primaryHubHost: String?,
        configuredInternetHost: String?,
        cachedHost: String?,
        cachedInternetHost: String?,
        currentMachineHosts: Set<String>
    ) -> String {
        if let discovered = normalizedTrimmed(primaryHubHost) {
            return normalizedConnectHostCandidate(discovered, currentMachineHosts: currentMachineHosts)
        }
        if let configured = normalizedTrimmed(configuredInternetHost) {
            return normalizedConnectHostCandidate(configured, currentMachineHosts: currentMachineHosts)
        }
        if let cachedInternetHost = normalizedTrimmed(cachedInternetHost),
           shouldReuseFallbackConnectHost(cachedInternetHost, currentMachineHosts: currentMachineHosts) {
            return normalizedConnectHostCandidate(cachedInternetHost, currentMachineHosts: currentMachineHosts)
        }
        if let cachedHost = normalizedTrimmed(cachedHost),
           shouldReuseFallbackConnectHost(cachedHost, currentMachineHosts: currentMachineHosts) {
            return normalizedConnectHostCandidate(cachedHost, currentMachineHosts: currentMachineHosts)
        }
        return "auto"
    }

    private func connectedSummary(
        route: HubRemoteRoute,
        bootstrapDisposition: HubRemoteBootstrapDisposition
    ) -> String {
        let routeText: String
        switch route {
        case .lan:
            routeText = "remote gRPC 已连通（LAN）"
        case .internet:
            routeText = "remote gRPC 已连通（Internet）"
        case .internetTunnel:
            routeText = "remote gRPC 已连通（Internet tunnel）"
        case .none:
            routeText = "remote gRPC 已连通"
        }

        let pairingText: String
        switch bootstrapDisposition {
        case .connectOnly:
            pairingText = "本次只是重连检查，没有执行新的配对。"
        case .freshPairingApproved:
            pairingText = "本次完成了新的配对批准与凭据下发。"
        case .reusedExistingProfile:
            pairingText = "本次复用了现有配对资料，没有触发新的 Hub 审批。"
        case .refreshedExistingProfile:
            pairingText = "旧配对资料已刷新并重新建立了连接。"
        }

        return "\(routeText)。\(pairingText) 这一步只验证了链路连通，不代表已经验证过实际模型生成。"
    }
}
