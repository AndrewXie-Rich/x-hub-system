import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension HubPairingCoordinator {
    func sanitize(_ options: HubRemoteConnectOptions) -> HubRemoteConnectOptions {
        var out = options
        out.grpcPort = max(1, min(65_535, options.grpcPort))
        out.pairingPort = max(1, min(65_535, options.pairingPort))
        let device = options.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        out.deviceName = device.isEmpty ? Host.current().localizedName ?? "X-Terminal" : device
        out.internetHost = options.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        out.inviteToken = options.inviteToken.trimmingCharacters(in: .whitespacesAndNewlines)
        out.inviteAlias = options.inviteAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        out.inviteInstanceID = options.inviteInstanceID.trimmingCharacters(in: .whitespacesAndNewlines)
        out.axhubctlPath = options.axhubctlPath.trimmingCharacters(in: .whitespacesAndNewlines)
        out.stateDir = options.stateDir ?? defaultStateDir()
        return out
    }

    func appendStepLogs(into logs: inout [String], step: StepOutput) {
        logs.append("$ \(step.command)")
        if !step.output.isEmpty {
            logs.append(step.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        logs.append("(exit=\(step.exitCode))")
    }

    func runLegacyBootstrapFlow(
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
                ] + hubInviteTokenArgs(opts),
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

    func orderedPairingPortCandidates(_ preferred: Int) -> [Int] {
        var out: [Int] = []
        for p in [preferred] + Array(50052...50056) {
            let clamped = max(1, min(65_535, p))
            if !out.contains(clamped) {
                out.append(clamped)
            }
        }
        return out
    }

    func shouldFallbackLegacyBootstrap(_ output: String) -> Bool {
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

    func legacyConnectWithListModels(
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

    func runAxhubctl(
        args: [String],
        options: HubRemoteConnectOptions,
        env: [String: String],
        timeoutSec: Double
    ) -> StepOutput {
        let resolved = resolveAxhubctlExecutable(override: options.axhubctlPath)
        var commandDisplay = ""
        var result: ProcessResult
        let redactedArgs = Self.redactedAxhubctlArgs(args)

        do {
            switch resolved {
            case .direct(let path):
                commandDisplay = ([path] + redactedArgs).joined(separator: " ")
                result = try ProcessCapture.run(
                    path,
                    args,
                    cwd: nil,
                    timeoutSec: timeoutSec,
                    env: mergedAxhubEnv(options: options, extra: env)
                )
            case .bashScript(let path):
                commandDisplay = (["/bin/bash", path] + redactedArgs).joined(separator: " ")
                result = try ProcessCapture.run(
                    "/bin/bash",
                    [path] + args,
                    cwd: nil,
                    timeoutSec: timeoutSec,
                    env: mergedAxhubEnv(options: options, extra: env)
                )
            case .viaEnv:
                commandDisplay = (["axhubctl"] + redactedArgs).joined(separator: " ")
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
                command: commandDisplay.isEmpty ? ("axhubctl " + redactedArgs.joined(separator: " ")) : commandDisplay
            )
        }

        return StepOutput(exitCode: result.exitCode, output: result.combined, command: commandDisplay)
    }

    nonisolated static func redactedAxhubctlArgs(_ args: [String]) -> [String] {
        var out: [String] = []
        var redactNext = false
        for arg in args {
            if redactNext {
                out.append("[redacted_invite_token]")
                redactNext = false
                continue
            }
            if arg == "--invite-token" {
                out.append(arg)
                redactNext = true
                continue
            }
            out.append(arg)
        }
        return out
    }

    func explainBootstrapFailureIfNeeded(
        reason rawReason: String?,
        bootstrapHost: String,
        options: HubRemoteConnectOptions
    ) -> [String] {
        let reason = (rawReason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !reason.isEmpty else { return [] }

        let classification = XTHubRemoteAccessHostClassification.classify(
            bootstrapHost.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let host = classification.displayHost ?? bootstrapHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentNetworks = Self.buildLANDiscoveryScanPlan().networkSummaries
        var lines: [String] = []

        if reason.contains("first_pair_requires_same_lan") {
            lines.append("[bootstrap] Hub rejected first pairing as not same-LAN. Same Wi-Fi name alone is not sufficient; the Hub must see XT on a local LAN path.")
            switch classification.kind {
            case .lanOnly, .rawIP(scope: .privateLAN), .rawIP(scope: .loopback), .rawIP(scope: .linkLocal):
                lines.append("[bootstrap] target \(host) is a LAN/private endpoint. If XT and Hub are on the same SSID but this still fails, check AP client isolation, guest-network policy, or VLAN segmentation.")
            case .stableNamed, .rawIP(scope: .tailscale), .rawIP(scope: .carrierGradeNat), .rawIP(scope: .publicInternet), .rawIP(scope: .unknown):
                lines.append("[bootstrap] target \(host) is not a same-LAN-only endpoint, but first pairing still requires one successful local-LAN approval before formal remote reconnect can work.")
            case .missing:
                break
            }
            if !currentNetworks.isEmpty {
                lines.append("[bootstrap] current_xt_networks=\(currentNetworks.joined(separator: ", "))")
            }
            return lines
        }

        if (reason.contains("tcp_timeout") || reason.contains("hub_unreachable") || reason.contains("grpc_unavailable")),
           case .rawIP(let scope) = classification.kind,
           scope == .privateLAN || scope == .loopback || scope == .linkLocal {
            lines.append("[bootstrap] target \(host) is a same-LAN/VPN raw IP. If XT changed Wi-Fi, left the VPN, or moved behind another VLAN, direct connect will time out until that LAN path is restored.")
            if !currentNetworks.isEmpty {
                lines.append("[bootstrap] current_xt_networks=\(currentNetworks.joined(separator: ", "))")
            }
        }

        return lines
    }

    func verifyLoopbackTunnelGRPC(
        options opts: HubRemoteConnectOptions,
        host: String,
        port: Int,
        timeoutSec: Double
    ) -> StepOutput {
        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let listModelsScript = clientKitBase
            .appendingPathComponent("hub_grpc_server", isDirectory: true)
            .appendingPathComponent("src", isDirectory: true)
            .appendingPathComponent("list_models_client.js", isDirectory: false)
        let commandDisplay = "tunnel_loopback_probe \(host):\(port)"

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return StepOutput(
                exitCode: 127,
                output: "missing hub env: \(hubEnv.path)",
                command: commandDisplay
            )
        }
        guard FileManager.default.fileExists(atPath: listModelsScript.path) else {
            return StepOutput(
                exitCode: 127,
                output: "missing client kit script: \(listModelsScript.path)",
                command: commandDisplay
            )
        }

        var exported = readEnvExports(from: hubEnv)
        guard nonEmpty(exported["HUB_CLIENT_TOKEN"]) != nil else {
            return StepOutput(
                exitCode: 127,
                output: "missing HUB_CLIENT_TOKEN in \(hubEnv.path)",
                command: commandDisplay
            )
        }

        exported["HUB_HOST"] = host
        exported["HUB_PORT"] = "\(max(1, min(65_535, port)))"
        let merged = mergedAxhubEnv(options: opts, extra: exported)

        var nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        if nodeBin == nil {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: [:],
                timeoutSec: Self.remoteClientInstallTimeoutSec
            )
            if install.exitCode != 0 {
                return install
            }
            nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        }
        guard let nodeBin else {
            return StepOutput(
                exitCode: 127,
                output: "missing node runtime for tunnel probe",
                command: commandDisplay
            )
        }

        let deadline = Date().addingTimeInterval(max(2.0, timeoutSec))
        let probeCommand = ([nodeBin, listModelsScript.path]).joined(separator: " ")
        var lastStep = StepOutput(
            exitCode: 127,
            output: "tunnel loopback probe did not start",
            command: probeCommand
        )

        repeat {
            let remaining = deadline.timeIntervalSinceNow
            let stepTimeout = max(1.5, min(4.0, remaining))
            do {
                let result = try ProcessCapture.run(
                    nodeBin,
                    [listModelsScript.path],
                    cwd: nil,
                    timeoutSec: stepTimeout,
                    env: merged
                )
                lastStep = StepOutput(
                    exitCode: result.exitCode,
                    output: result.combined,
                    command: probeCommand
                )
            } catch {
                lastStep = StepOutput(
                    exitCode: 127,
                    output: String(describing: error),
                    command: probeCommand
                )
            }

            if lastStep.exitCode == 0 {
                return lastStep
            }

            let reason = inferFailureCode(from: lastStep.output, fallback: "tunnel_probe_failed")
            if !Self.shouldRetryLoopbackTunnelProbe(reasonCode: reason) {
                return lastStep
            }
            if deadline.timeIntervalSinceNow <= 0 {
                return lastStep
            }
            Thread.sleep(forTimeInterval: 0.35)
        } while deadline.timeIntervalSinceNow > 0

        return lastStep
    }

    @discardableResult
    func persistDirectRemoteRouteState(
        host rawHost: String,
        pairingPort: Int,
        grpcPort: Int,
        internetHost: String?,
        options: HubRemoteConnectOptions
    ) throws -> Bool {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return false }
        guard normalizeHost(host) != "auto" else { return false }
        guard !isLoopbackHost(host) else { return false }

        return try persistResolvedRemoteRouteState(
            host: host,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            internetHost: internetHost,
            options: options
        )
    }

    @discardableResult
    func persistLoopbackTunnelRouteState(
        host: String,
        pairingPort: Int,
        grpcPort: Int,
        internetHost: String?,
        options: HubRemoteConnectOptions
    ) throws -> Bool {
        try persistResolvedRemoteRouteState(
            host: host,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            internetHost: internetHost,
            options: options
        )
    }

    @discardableResult
    func persistResolvedRemoteRouteState(
        host rawHost: String,
        pairingPort: Int,
        grpcPort: Int,
        internetHost: String?,
        options: HubRemoteConnectOptions
    ) throws -> Bool {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return false }

        let base = options.stateDir ?? defaultStateDir()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let pairingEnv = base.appendingPathComponent("pairing.env")
        let hubEnv = base.appendingPathComponent("hub.env")
        let connectionJSON = base.appendingPathComponent("connection.json")
        let existingHubExports = readEnvExports(from: hubEnv)
        guard let token = nonEmpty(existingHubExports["HUB_CLIENT_TOKEN"]) else {
            throw NSError(
                domain: "xterminal",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "missing HUB_CLIENT_TOKEN in hub.env"]
            )
        }

        let deviceID = nonEmpty(existingHubExports["HUB_DEVICE_ID"])
        let userID = nonEmpty(existingHubExports["HUB_USER_ID"])
        let appID = canonicalHubAppID(existingHubExports["HUB_APP_ID"])
            ?? canonicalHubAppID(readEnvValue(from: pairingEnv, key: "AXHUB_APP_ID"))
            ?? "x_terminal"
        let cachedProfile = HubAIClient.cachedRemoteProfile(stateDir: base)
        let tlsMode = nonEmpty(existingHubExports["HUB_GRPC_TLS_MODE"]) ?? "insecure"
        let tlsServerName = nonEmpty(existingHubExports["HUB_GRPC_TLS_SERVER_NAME"])
        let tlsCAPath = nonEmpty(existingHubExports["HUB_GRPC_TLS_CA_CERT_PATH"])
        let tlsClientCertPath = nonEmpty(existingHubExports["HUB_GRPC_TLS_CLIENT_CERT_PATH"])
        let tlsClientKeyPath = nonEmpty(existingHubExports["HUB_GRPC_TLS_CLIENT_KEY_PATH"])
        let preservedInternetHost = Self.reusableDiscoveredInternetHost(internetHost)
            ?? Self.reusableDiscoveredInternetHost(options.internetHost)

        let hubContents = hubEnvContents(
            host: host,
            port: grpcPort,
            token: token,
            deviceID: deviceID,
            userID: userID,
            appID: appID,
            tlsMode: tlsMode,
            tlsServerName: tlsServerName,
            tlsCAPath: tlsCAPath,
            tlsClientCertPath: tlsClientCertPath,
            tlsClientKeyPath: tlsClientKeyPath
        )
        try hubContents.write(to: hubEnv, atomically: true, encoding: .utf8)

        let profile = PersistedConnectionProfile(
            schemaVersion: "axhub_connection.v1",
            updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            hubEnvPath: hubEnv.path,
            hubHost: host,
            grpcPort: grpcPort,
            pairingPort: pairingPort,
            deviceID: deviceID,
            pairingProfileEpoch: cachedProfile.pairingProfileEpoch,
            routePackVersion: cachedProfile.routePackVersion,
            tlsMode: nonEmpty(tlsMode),
            tlsServerName: tlsServerName,
            caCertPath: tlsCAPath,
            clientCertPath: tlsClientCertPath,
            clientKeyPath: tlsClientKeyPath
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let connectionData = try encoder.encode(profile)
        try connectionData.write(to: connectionJSON, options: .atomic)

        try persistDiscoveredPairingInfo(
            host: host,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            internetHost: preservedInternetHost,
            hubInstanceID: nil,
            lanDiscoveryName: nil,
            pairingProfileEpoch: cachedProfile.pairingProfileEpoch,
            routePackVersion: cachedProfile.routePackVersion,
            options: options
        )
        return true
    }

    func synchronizeAuthoritativeRemoteEndpointArtifacts(
        options rawOptions: HubRemoteConnectOptions
    ) -> [String] {
        let opts = sanitize(rawOptions)
        guard Self.shouldHonorConfiguredEndpointAuthority(
            configuredInternetHost: opts.internetHost,
            configuredEndpointIsAuthoritative: opts.configuredEndpointIsAuthoritative
        ) else {
            return []
        }

        let authoritativeHost = opts.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authoritativeHost.isEmpty else { return [] }

        let base = opts.stateDir ?? defaultStateDir()
        let pairingEnv = base.appendingPathComponent("pairing.env")
        let pairingInternetHost = nonEmpty(readEnvValue(from: pairingEnv, key: "AXHUB_INTERNET_HOST"))
        guard normalizeHost(pairingInternetHost ?? "") == normalizeHost(authoritativeHost) else {
            return []
        }

        let pairingHost = nonEmpty(readEnvValue(from: pairingEnv, key: "AXHUB_HUB_HOST"))
        let hubEnv = base.appendingPathComponent("hub.env")
        let hubHost = nonEmpty(readEnvValue(from: hubEnv, key: "HUB_HOST"))
        if normalizeHost(pairingHost ?? "") == normalizeHost(authoritativeHost),
           normalizeHost(hubHost ?? "") == normalizeHost(authoritativeHost) {
            return []
        }

        do {
            if try persistDirectRemoteRouteState(
                host: authoritativeHost,
                pairingPort: opts.pairingPort,
                grpcPort: opts.grpcPort,
                internetHost: authoritativeHost,
                options: opts
            ) {
                return [
                    "[state-sync] hub.env/connection.json realigned to authoritative remote endpoint \(authoritativeHost):\(opts.grpcPort)."
                ]
            }
        } catch {
            return ["[state-sync] authoritative_endpoint_sync_failed: \(error.localizedDescription)"]
        }

        return []
    }

    func resolveNodeExecutable(clientKitBaseDir: URL, env: [String: String]) -> String? {
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

    func extractTrailingJSONObjectLine(_ text: String) -> String? {
        for raw in text.components(separatedBy: .newlines).reversed() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("{"), line.hasSuffix("}") {
                return line
            }
        }
        return nil
    }

    func readEnvExports(from fileURL: URL) -> [String: String] {
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

    func hubEnvContents(
        host: String,
        port: Int,
        token: String,
        deviceID: String?,
        userID: String?,
        appID: String?,
        tlsMode: String,
        tlsServerName: String?,
        tlsCAPath: String?,
        tlsClientCertPath: String?,
        tlsClientKeyPath: String?
    ) -> String {
        var lines = [
            "export HUB_HOST=\(shellSingleQuoted(host))",
            "export HUB_PORT=\(shellSingleQuoted(String(max(1, min(65_535, port)))))",
            "export HUB_CLIENT_TOKEN=\(shellSingleQuoted(token))",
            "export HUB_DEVICE_ID=\(shellSingleQuoted(deviceID ?? ""))",
        ]

        if let userID {
            lines.append("export HUB_USER_ID=\(shellSingleQuoted(userID))")
        }
        if let appID {
            lines.append("export HUB_APP_ID=\(shellSingleQuoted(appID))")
        }

        let normalizedTLSMode = tlsMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedTLSMode == "tls" || normalizedTLSMode == "mtls" {
            lines.append("export HUB_GRPC_TLS_MODE=\(shellSingleQuoted(normalizedTLSMode))")
            lines.append("export HUB_GRPC_TLS_SERVER_NAME=\(shellSingleQuoted(tlsServerName ?? "axhub"))")
            if let tlsCAPath {
                lines.append("export HUB_GRPC_TLS_CA_CERT_PATH=\(shellSingleQuoted(tlsCAPath))")
            }
            if normalizedTLSMode == "mtls" {
                if let tlsClientCertPath {
                    lines.append("export HUB_GRPC_TLS_CLIENT_CERT_PATH=\(shellSingleQuoted(tlsClientCertPath))")
                }
                if let tlsClientKeyPath {
                    lines.append("export HUB_GRPC_TLS_CLIENT_KEY_PATH=\(shellSingleQuoted(tlsClientKeyPath))")
                }
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }



    func hasInstalledClientKit(stateDir: URL?) -> Bool {
        let base = stateDir ?? defaultStateDir()
        let marker = base
            .appendingPathComponent("client_kit", isDirectory: true)
            .appendingPathComponent("hub_grpc_server", isDirectory: true)
            .appendingPathComponent("src", isDirectory: true)
            .appendingPathComponent("list_models_client.js", isDirectory: false)
        return FileManager.default.fileExists(atPath: marker.path)
    }

    func connectRepairHosts(
        primaryHubHost: String?,
        options: HubRemoteConnectOptions
    ) -> [String] {
        let cached = loadCachedPairingInfo(stateDir: options.stateDir)
        return Self.connectRepairHostsValue(
            primaryHubHost: primaryHubHost,
            configuredInternetHost: options.internetHost,
            cachedHost: cached.host,
            cachedInternetHost: cached.internetHost,
            currentMachineHosts: Self.currentMachineIPv4Hosts()
        )
    }

    nonisolated static func connectRepairHostsValue(
        primaryHubHost: String?,
        configuredInternetHost: String?,
        cachedHost: String?,
        cachedInternetHost: String?,
        currentMachineHosts: Set<String>
    ) -> [String] {
        var out: [String] = []

        func append(_ raw: String?, allowPublicRawIP: Bool) {
            guard let raw = normalizedTrimmed(raw) else { return }
            let host = normalizedConnectHostCandidate(raw, currentMachineHosts: currentMachineHosts)
            guard !host.isEmpty, !out.contains(host) else { return }
            if !allowPublicRawIP &&
                !shouldReuseFallbackConnectHost(host, currentMachineHosts: currentMachineHosts) {
                return
            }
            out.append(host)
        }

        append(primaryHubHost, allowPublicRawIP: true)
        append(configuredInternetHost, allowPublicRawIP: true)
        append(cachedInternetHost, allowPublicRawIP: false)
        append(cachedHost, allowPublicRawIP: false)

        if out.isEmpty || out.contains(where: { isCurrentMachineHost($0, currentMachineHosts: currentMachineHosts) }) || out.contains("127.0.0.1") {
            append("127.0.0.1", allowPublicRawIP: true)
        }
        return out
    }

    nonisolated static func preferredPresenceHostValue(
        route: HubRemoteRoute,
        cachedHost: String?,
        cachedInternetHost: String?,
        currentMachineHosts: Set<String>
    ) -> String? {
        let directHost = HubPairingCoordinator.nonEmptyValue(cachedHost)
        let internetHost = HubPairingCoordinator.nonEmptyValue(cachedInternetHost)

        switch route {
        case .internet, .internetTunnel:
            if let internetHost {
                return internetHost
            }
            guard let directHost else { return nil }
            return isCurrentMachineHost(directHost, currentMachineHosts: currentMachineHosts) ? nil : directHost
        case .lan:
            return directHost ?? internetHost
        case .none:
            if let internetHost {
                return internetHost
            }
            guard let directHost else { return nil }
            return isCurrentMachineHost(directHost, currentMachineHosts: currentMachineHosts) ? nil : directHost
        }
    }

    func maybeInstallClientKit(
        options opts: HubRemoteConnectOptions,
        hosts: [String],
        env customEnv: [String: String],
        logs: inout [String]
    ) -> Bool {
        guard !hosts.isEmpty else { return false }
        for host in hosts {
            let install = runAxhubctl(
                args: [
                    "install-client",
                    "--hub", host,
                    "--pairing-port", "\(opts.pairingPort)",
                ],
                options: opts,
                env: customEnv,
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                return true
            }
        }
        return false
    }

    func normalizedConnectHostCandidate(_ host: String) -> String {
        Self.normalizedConnectHostCandidate(host, currentMachineHosts: Self.currentMachineIPv4Hosts())
    }

    nonisolated static func normalizedConnectHostCandidate(
        _ host: String,
        currentMachineHosts: Set<String>
    ) -> String {
        isCurrentMachineHost(host, currentMachineHosts: currentMachineHosts) ? "127.0.0.1" : host
    }

    func preferredBootstrapHub(
        discoveredHubHost: String?,
        options: HubRemoteConnectOptions
    ) -> String {
        if let discoveredHubHost, !discoveredHubHost.isEmpty {
            return normalizedConnectHostCandidate(discoveredHubHost)
        }
        let internetHost = options.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if !internetHost.isEmpty {
            return normalizedConnectHostCandidate(internetHost)
        }
        return "127.0.0.1"
    }

    func shouldRequireConfiguredHubHost(options: HubRemoteConnectOptions) -> Bool {
        Self.shouldRequireConfiguredHubHost(options.internetHost)
    }

    func shouldPinDiscoveredHostToConfiguredRemote(options: HubRemoteConnectOptions) -> Bool {
        Self.shouldPinDiscoveredHostToConfiguredRemote(options.internetHost)
    }

    nonisolated static func shouldSkipDiscoveryForAuthoritativeBootstrap(
        configuredInternetHost: String,
        inviteToken: String,
        configuredEndpointIsAuthoritative: Bool,
        hasAuthoritativeLocalProfile: Bool
    ) -> Bool {
        if shouldHonorConfiguredEndpointAuthority(
            configuredInternetHost: configuredInternetHost,
            configuredEndpointIsAuthoritative: configuredEndpointIsAuthoritative
        ) {
            return true
        }

        guard !inviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let classification = XTHubRemoteAccessHostClassification.classify(configuredInternetHost)
        guard classification.isFormalRemoteEntry else { return false }
        guard !hasAuthoritativeLocalProfile else { return false }
        return true
    }

    func hostMatchesConfiguredHost(discoveredHost: String?, options: HubRemoteConnectOptions) -> Bool {
        let configured = normalizeHost(options.internetHost)
        guard !configured.isEmpty else { return true }
        guard let discoveredHost else { return false }
        if isCurrentMachineHost(configured), isCurrentMachineHost(discoveredHost) {
            return true
        }
        return normalizeHost(discoveredHost) == configured
    }

    func normalizeHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func isLoopbackHost(_ host: String) -> Bool {
        let n = normalizeHost(host)
        return n == "localhost" || n == "127.0.0.1"
    }

    func isCurrentMachineHost(_ host: String) -> Bool {
        Self.isCurrentMachineHost(host, currentMachineHosts: Self.currentMachineIPv4Hosts())
    }

    nonisolated static func isCurrentMachineHost(
        _ host: String,
        currentMachineHosts: Set<String>
    ) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty { return false }
        if HubRemoteHostPolicy.isLoopbackHost(normalized) { return true }
        return currentMachineHosts.contains(normalized)
    }

    nonisolated static func shouldReuseFallbackConnectHost(
        _ host: String,
        currentMachineHosts: Set<String>
    ) -> Bool {
        if isCurrentMachineHost(host, currentMachineHosts: currentMachineHosts) {
            return true
        }
        return HubRemoteHostPolicy.isReusableConnectCandidate(host)
    }

    func makeEphemeralStateDir(prefix: String) -> URL? {
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

    func removeEphemeralStateDir(_ dir: URL?) {
        guard let dir else { return }
        try? FileManager.default.removeItem(at: dir)
    }


    func waitForLoopbackTunnelListener(
        port: Int,
        timeoutSec: TimeInterval,
        pollIntervalSec: TimeInterval = 0.15
    ) -> Bool {
        let clampedPort = max(1, min(65_535, port))
        let deadline = Date().timeIntervalSince1970 + max(0, timeoutSec)
        repeat {
            if Self.canConnectLoopbackTCP(port: clampedPort) {
                return true
            }
            usleep(useconds_t(max(10_000, min(500_000, Int(pollIntervalSec * 1_000_000.0)))))
        } while Date().timeIntervalSince1970 < deadline
        return Self.canConnectLoopbackTCP(port: clampedPort)
    }

    nonisolated static func canConnectLoopbackTCP(port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var address = sockaddr_in()
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(max(1, min(65_535, port))).bigEndian)
        let loopbackResult = "127.0.0.1".withCString { cString in
            inet_pton(AF_INET, cString, &address.sin_addr)
        }
        guard loopbackResult == 1 else { return false }

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }


    enum ExecutableRef {
        case direct(String)
        case bashScript(String)
        case viaEnv
    }

    func stagedBundledExecutable(named fileName: String) -> String? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let sourceURL = resourceURL.appendingPathComponent(fileName, isDirectory: false)
        return stageBundledExecutableIfNeeded(sourceURL: sourceURL)
    }

    func stageBundledExecutableIfNeeded(sourceURL: URL) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else { return nil }

        let stagedDir = HubBundledToolSupport.toolSupportBinDirectory(
            applicationSupportBase: HubBundledToolSupport.defaultApplicationSupportBase(fileManager: fm)
        )
        do {
            try fm.createDirectory(at: stagedDir, withIntermediateDirectories: true)
        } catch {
            return sourceURL.path
        }

        let stagedURL = stagedDir.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
        if shouldRefreshStagedExecutable(sourceURL: sourceURL, stagedURL: stagedURL, fileManager: fm) {
            do {
                if fm.fileExists(atPath: stagedURL.path) {
                    try fm.removeItem(at: stagedURL)
                }
                try fm.copyItem(at: sourceURL, to: stagedURL)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedURL.path)
            } catch {
                return sourceURL.path
            }
        }

        return stagedURL.path
    }

    func shouldRefreshStagedExecutable(
        sourceURL: URL,
        stagedURL: URL,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: stagedURL.path) else { return true }
        guard
            let sourceAttrs = try? fileManager.attributesOfItem(atPath: sourceURL.path),
            let stagedAttrs = try? fileManager.attributesOfItem(atPath: stagedURL.path)
        else {
            return true
        }

        let sourceSize = sourceAttrs[.size] as? NSNumber
        let stagedSize = stagedAttrs[.size] as? NSNumber
        if sourceSize != stagedSize {
            return true
        }

        let sourceModified = sourceAttrs[.modificationDate] as? Date
        let stagedModified = stagedAttrs[.modificationDate] as? Date
        if let sourceModified, let stagedModified {
            return sourceModified > stagedModified
        }
        return false
    }

    func resolveAxhubctlExecutable(override: String) -> ExecutableRef {
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

        let directCandidates = HubBundledToolSupport.defaultAxhubctlFallbackCandidates(
            homeDirectory: fm.homeDirectoryForCurrentUser
        )

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

    func bundledAxhubctlCandidate() -> String? {
        guard let staged = stagedBundledExecutable(named: "axhubctl") else { return nil }
        return FileManager.default.fileExists(atPath: staged) ? staged : nil
    }

    func preferredAxhubctlPath(primary: String) -> String {
        guard !supportsModernAxhubctlCommands(at: primary),
              let bundled = bundledAxhubctlCandidate(),
              supportsModernAxhubctlCommands(at: bundled) else {
            return primary
        }
        return bundled
    }

    func supportsModernAxhubctlCommands(at path: String) -> Bool {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return true
        }
        let lower = text.lowercased()
        return lower.contains("  discover)") && lower.contains("  connect)")
    }

    func repoRelativeAxhubctlCandidate() -> String? {
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


    func mergedAxhubEnv(
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
        if let appID = canonicalHubAppID(out["HUB_APP_ID"]) {
            out["HUB_APP_ID"] = appID
        }
        return out
    }

    func preferredNodeBinPath() -> String? {
        let fm = FileManager.default
        if let stagedNode = stagedBundledExecutable(named: "relflowhub_node"),
           fm.isExecutableFile(atPath: stagedNode) {
            return stagedNode
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

}
