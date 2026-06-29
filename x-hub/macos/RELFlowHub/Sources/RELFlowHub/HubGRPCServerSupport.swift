import Foundation
import AppKit
import Darwin
import LocalAuthentication
import Security
import RELFlowHubCore

// Runs the Node gRPC server (hub_grpc_server) from inside the Hub app so DMG installs
// don't require a Terminal command to start LAN access.
@MainActor
final class HubGRPCServerSupport: ObservableObject {
    static let shared = HubGRPCServerSupport()

    @Published var autoStart: Bool = UserDefaults.standard.bool(forKey: HubGRPCServerSupport.autoStartKey) {
        didSet {
            UserDefaults.standard.set(autoStart, forKey: HubGRPCServerSupport.autoStartKey)
            if autoStart { autoStartIfNeeded() }
            else { stop() }
            refreshServingPowerState()
        }
    }

    @Published var port: Int = UserDefaults.standard.integer(forKey: HubGRPCServerSupport.portKey) {
        didSet {
            let v = max(1, min(65535, port))
            if v != port { port = v }
            UserDefaults.standard.set(v, forKey: HubGRPCServerSupport.portKey)
            // Port changes require restart.
            if isRunning {
                restart()
            } else {
                refresh()
                autoStartIfNeeded()
            }
        }
    }

    @Published var tlsMode: String = (UserDefaults.standard.string(forKey: HubGRPCServerSupport.tlsModeKey) ?? "insecure") {
        didSet {
            let cleaned = tlsMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let v: String = {
                if cleaned == "tls" { return "tls" }
                if cleaned == "mtls" { return "mtls" }
                return "insecure"
            }()
            if v != tlsMode {
                tlsMode = v
                return
            }
            UserDefaults.standard.set(v, forKey: HubGRPCServerSupport.tlsModeKey)
            // Transport changes require restart.
            if isRunning {
                restart()
            } else {
                refresh()
                autoStartIfNeeded()
            }
        }
    }

    @Published var internetHostOverride: String = (UserDefaults.standard.string(forKey: HubGRPCServerSupport.internetHostOverrideKey) ?? "") {
        didSet {
            let trimmed = internetHostOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != internetHostOverride {
                internetHostOverride = trimmed
                return
            }
            UserDefaults.standard.set(trimmed, forKey: HubGRPCServerSupport.internetHostOverrideKey)
            if isRunning {
                restart()
            } else {
                refresh()
                autoStartIfNeeded()
            }
            refreshServingPowerState()
        }
    }

    @Published var externalHubAlias: String = (UserDefaults.standard.string(forKey: HubGRPCServerSupport.externalHubAliasKey) ?? "") {
        didSet {
            let normalized = HubExternalAccessInviteSupport.normalizedExternalHubAlias(externalHubAlias) ?? ""
            if normalized != externalHubAlias {
                externalHubAlias = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: HubGRPCServerSupport.externalHubAliasKey)
        }
    }

    @Published private(set) var statusText: String = HubUIStrings.Settings.GRPC.Runtime.statusUnknown
    @Published private(set) var lastError: String = ""
    @Published private(set) var autoPortSwitchMessage: String = ""
    @Published private(set) var lanAddresses: [String] = []
    @Published private(set) var connectionGuide: String = ""
    @Published private(set) var allowedClients: [HubGRPCClientEntry] = []
    @Published private(set) var externalInviteTokenRecord: HubExternalInviteTokenRecord? = HubExternalInviteTokenStore.load()

    var xtTerminalInternetHost: String? {
        Self.preferredXTTerminalInternetHost(
            override: internetHostOverride,
            interfaceRows: lanAddresses
        )
    }

    var xtTerminalInternetHostFallback: String {
        xtTerminalInternetHost ?? "127.0.0.1"
    }

    var xtTerminalPairingPort: Int {
        Self.pairingPort(grpcPort: port)
    }

    var preferredExternalHubAlias: String? {
        HubExternalAccessInviteSupport.preferredExternalHubAlias(
            override: externalHubAlias,
            bonjourMetadata: bonjourAdvertiser.metadata,
            externalHost: xtTerminalInternetHost
        )
    }

    var externalInviteURL: URL? {
        HubExternalAccessInviteSupport.externalInviteURL(
            alias: preferredExternalHubAlias,
            externalHost: xtTerminalInternetHost,
            inviteToken: externalInviteTokenRecord?.tokenSecret,
            pairingPort: xtTerminalPairingPort,
            grpcPort: port,
            hubInstanceID: bonjourAdvertiser.metadata?.hubInstanceID
        )
    }

    var externalInviteLinkText: String {
        externalInviteURL?.absoluteString ?? ""
    }

    var localPairingInviteURL: URL? {
        HubExternalAccessInviteSupport.localPairingInviteURL(
            alias: preferredExternalHubAlias,
            inviteToken: externalInviteTokenRecord?.tokenSecret,
            pairingPort: xtTerminalPairingPort,
            grpcPort: port,
            hubInstanceID: bonjourAdvertiser.metadata?.hubInstanceID
        )
    }

    var localPairingInviteLinkText: String {
        localPairingInviteURL?.absoluteString ?? ""
    }

    var externalInviteQRCodeImage: NSImage? {
        guard let inviteURL = externalInviteURL else { return nil }
        return Self.qrCodeImage(for: inviteURL.absoluteString, side: 156)
    }

    var externalInviteUnavailableReason: String {
        HubExternalAccessInviteSupport.externalInviteUnavailableReason(
            externalHost: xtTerminalInternetHost,
            hasInviteToken: externalInviteTokenRecord != nil
        )
    }

    var canProvisionExternalInvite: Bool {
        HubExternalAccessInviteSupport.normalizedInviteHost(xtTerminalInternetHost) != nil
    }

    var canProvisionLocalPairingInvite: Bool {
        HubExternalAccessInviteSupport.localPairingInviteURL(
            alias: preferredExternalHubAlias,
            inviteToken: externalInviteTokenRecord?.tokenSecret ?? "axhub_invite_preview",
            pairingPort: xtTerminalPairingPort,
            grpcPort: port,
            hubInstanceID: bonjourAdvertiser.metadata?.hubInstanceID
        ) != nil
    }

    var canProvisionSecureRemoteSetupPack: Bool {
        HubExternalAccessInviteSupport.normalizedSecureRemoteHost(
            xtTerminalInternetHost,
            allowPrivateVPNIP: allowsPrivateVPNIPForSecureRemoteSetupPack
        ) != nil
    }

    var hasExternalInviteToken: Bool {
        externalInviteTokenRecord != nil
    }

    var externalInviteTokenPreview: String {
        externalInviteTokenRecord?.redactedSecret ?? ""
    }

    var secureRemoteSetupPackText: String {
        HubSecureRemoteSetupPackBuilder.build(
            externalHost: xtTerminalInternetHost,
            alias: preferredExternalHubAlias,
            inviteToken: externalInviteTokenRecord?.tokenSecret,
            pairingPort: xtTerminalPairingPort,
            grpcPort: port,
            hubInstanceID: bonjourAdvertiser.metadata?.hubInstanceID,
            allowPrivateVPNIP: allowsPrivateVPNIPForSecureRemoteSetupPack
        ) ?? ""
    }

    var allowsPrivateVPNIPForSecureRemoteSetupPack: Bool {
        if !internetHostOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        guard let host = xtTerminalInternetHost?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return false
        }
        return Self.interfaceRowsContainRemoteTunnelIP(host, rows: lanAddresses)
    }

    var noDomainPrivateRemoteHost: String? {
        Self.preferredNoDomainPrivateRemoteHost(interfaceRows: lanAddresses)
    }

    var isUsingNoDomainPrivateRemoteHost: Bool {
        guard let host = noDomainPrivateRemoteHost else { return false }
        return internetHostOverride.trimmingCharacters(in: .whitespacesAndNewlines) == host
    }

    func isUsingNoDomainPrivateRemoteHost(_ preferredHost: String?) -> Bool {
        let trimmedHost = preferredHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let host = trimmedHost.isEmpty ? noDomainPrivateRemoteHost : trimmedHost
        guard let host else { return false }
        return internetHostOverride.trimmingCharacters(in: .whitespacesAndNewlines) == host
    }

    @discardableResult
    func applyNoDomainPrivateRemoteHost(_ preferredHost: String? = nil) -> Bool {
        let trimmedHost = preferredHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let host = trimmedHost.isEmpty ? noDomainPrivateRemoteHost : trimmedHost
        guard let host else { return false }
        internetHostOverride = host
        if tlsMode != "mtls" {
            tlsMode = "mtls"
        }
        return true
    }

    private static let autoStartKey = "relflowhub_grpc_autostart"
    private static let portKey = "relflowhub_grpc_port"
    private static let tlsModeKey = "relflowhub_grpc_tls_mode"
    private static let internetHostOverrideKey = "relflowhub_grpc_internet_host_override"
    private static let externalHubAliasKey = "relflowhub_external_hub_alias"

    static let defaultPort: Int = 50051

    private var proc: Process?
    var logHandle: FileHandle?
    private var timer: Timer?
    var didEnsureClientsTemplate: Bool = false
    var cachedClientsSnapshot: HubGRPCClientsSnapshot = .empty()
    var cachedClientsSnapshotFingerprint: String = ""
    private var stopRequestedAt: Double = 0

    // If a Process is still running when it deinitializes, Foundation can throw an ObjC
    // exception which aborts the app. Keep a small bounded set of "leaked" processes as
    // a last resort to prevent startup crashes if we fail to terminate within timeouts.
    var leakedProcs: [Process] = []

    var nextStartAttemptAt: Double = 0
    var failCount: Int = 0
    private var externalPairingHealthy: Bool = false
    var localPairingHealthy: Bool = false
    var lastProcessLaunchAt: Double = 0
    var localPairingProbeFailureCount: Int = 0
    var lastLocalWatchdogRestartAt: Double = 0
    var lastLoggedLocalHealthSnapshot: String = ""
    var recentFailureTimes: [Double] = []
    var lastExitLogSignature: String = ""
    var lastExitLogAt: Double = 0

    static let retryMinDelaySec: Double = 3.0
    static let retryMaxDelaySec: Double = 300.0
    static let failureBurstWindowSec: Double = 90.0
    static let failureBurstLimit: Int = 4
    static let failureBurstCooldownSec: Double = 300.0
    static let duplicateExitLogCooldownSec: Double = 12.0
    private let bonjourAdvertiser = HubBonjourAdvertiser()

    var isRunning: Bool {
        if let p = proc, p.isRunning {
            return true
        }
        return false
    }

    var isServingAvailable: Bool {
        if isRunning {
            if localPairingHealthy {
                return true
            }
            return HubLocalRuntimeWatchdog.isWithinStartupGrace(
                now: Date().timeIntervalSince1970,
                launchAt: lastProcessLaunchAt
            )
        }
        return externalPairingHealthy
    }

    private init() {
        // DMG installs should "just work": auto-start LAN server by default.
        if UserDefaults.standard.object(forKey: Self.autoStartKey) == nil {
            autoStart = true
        }
        let p0 = UserDefaults.standard.integer(forKey: Self.portKey)
        port = p0 > 0 ? p0 : Self.defaultPort

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        tick()
        refreshServingPowerState()
    }

    func refresh() {
        tick()
    }

    func start() {
        lastError = ""
        stopRequestedAt = 0
        if isRunning {
            refresh()
            return
        }

        let base = SharedPaths.ensureHubDirectory()
        let logURL = base.appendingPathComponent("hub_grpc.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        do {
            let h = try FileHandle(forWritingTo: logURL)
            try h.seekToEnd()
            logHandle = h
        } catch {
            // Non-fatal: still start without file logging.
            logHandle = nil
        }

        guard let nodeLaunch = autoDetectNodeLaunch() else {
            lastError = HubUIStrings.Settings.GRPC.Runtime.missingNode
            statusText = HubUIStrings.Settings.GRPC.Runtime.statusMissingNode
            failCount += 1
            _ = scheduleRetryAfterFailure(now: Date().timeIntervalSince1970)
            return
        }

        guard let serverJS = bundledServerJSURL() else {
            lastError = HubUIStrings.Settings.GRPC.Runtime.missingServerJS
            statusText = HubUIStrings.Settings.GRPC.Runtime.statusMissingServerJS
            failCount += 1
            _ = scheduleRetryAfterFailure(now: Date().timeIntervalSince1970)
            return
        }

        // If the configured port is occupied by an older bundled Hub gRPC server process,
        // terminate it first so the current app instance always starts the current bundle.
        if Self.isTCPPortInUse(port) {
            let cleanedRecorded = Self.terminateRecordedBundledServerProcessIfNeeded(
                baseDir: base,
                nodeExecutablePath: nodeLaunch.exePath,
                excluding: [getpid()]
            )
            let cleanedScanned = Self.terminateBundledServerProcessesIfNeeded(
                nodeExecutablePath: nodeLaunch.exePath,
                serverJSPath: serverJS.path,
                excluding: [getpid()]
            )
            let cleaned = cleanedRecorded + cleanedScanned
            if cleaned > 0 {
                appendLogLine("gRPC stale bundled server cleanup count=\(cleaned) port=\(port)")
                HubDiagnostics.log("hub_grpc.stale_bundled_server_cleanup count=\(cleaned) port=\(port)")
            }
        }

        // If the configured port is still occupied, avoid crash-looping the embedded Node server.
        // This happens when another Hub instance (or a different process) is already listening on the same port.
        if Self.isTCPPortInUse(port) {
            // If the X-Hub pairing port is healthy, treat it as an already-running server instance.
            let pairingOk = Self.probeLocalPairingHealth(pairingPort: Self.pairingPort(grpcPort: port))
            externalPairingHealthy = pairingOk
            if pairingOk {
                // No need to start a second copy; just surface status.
                lastError = ""
                autoPortSwitchMessage = ""
                resetFailureBackoffState()
                refresh()
                return
            }

            if let freePort = Self.diagnosticsFindAvailablePort(startingAt: max(Self.defaultPort, port + 1)) {
                let previousPort = port
                autoPortSwitchMessage = HubUIStrings.Settings.GRPC.Runtime.autoPortSwitched(
                    previousPort: previousPort,
                    grpcPort: freePort,
                    pairingPort: Self.pairingPort(grpcPort: freePort)
                )
                resetFailureBackoffState()
                port = freePort
                return
            }

            lastError = HubUIStrings.Settings.GRPC.Runtime.portInUse(port)
            failCount = max(failCount, 6)
            let now = Date().timeIntervalSince1970
            let sched = scheduleRetryAfterFailure(now: now)
            // Port conflicts rarely self-heal quickly; keep a strong cool-down.
            nextStartAttemptAt = max(nextStartAttemptAt, now + 300.0, now + sched.delaySec)
            refresh()
            return
        }

        // Ensure tokens exist (stable across restarts so other machines stay connected).
        let clientToken = HubGRPCTokens.getOrCreateClientToken()
        let adminToken = HubGRPCTokens.getOrCreateAdminToken()

        let dbURL = base
            .appendingPathComponent("hub_grpc", isDirectory: true)
            .appendingPathComponent("hub.sqlite3")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: nodeLaunch.exePath)
        p.arguments = nodeLaunch.argsPrefix + [serverJS.path]

        // Make module resolution predictable: node_modules lives under Resources/hub_grpc_server/.
        // (server.js itself is under Resources/hub_grpc_server/src/server.js)
        p.currentDirectoryURL = serverJS.deletingLastPathComponent().deletingLastPathComponent()

        var env = RustHubRuntimeSupport.nodeSidecarBaseEnvironment(ProcessInfo.processInfo.environment)
        let serviceBindHost = "::"
        env["HUB_HOST"] = serviceBindHost
        env["HUB_PORT"] = String(port)
        env["HUB_DB_PATH"] = dbURL.path
        env["HUB_CLIENT_TOKEN"] = clientToken
        env["HUB_ADMIN_TOKEN"] = adminToken
        env["HUB_GRPC_TLS_MODE"] = tlsMode
        // Stable authority name for TLS host verification when clients connect by IP.
        env["HUB_GRPC_TLS_SERVER_NAME"] = "axhub"
        if let publicHost = xtTerminalInternetHost {
            env["HUB_PAIRING_PUBLIC_HOST"] = publicHost
        }
        // Enforce token + client-cert pin in mTLS mode (defense-in-depth).
        env["HUB_GRPC_MTLS_REQUIRE_CERT_PIN"] = "1"
        // Keep client/access-key snapshots in the Swift sidecar base while runtime/model IPC follows
        // the Rust live kernel after authority cutover.
        env["HUB_AUTH_BASE_DIR"] = base.path
        env["HUB_CLIENTS_BASE_DIR"] = base.path
        let nodeRuntimeBase = RustHubRuntimeSupport.nodeSidecarRuntimeBaseDir(
            swiftBaseDir: base,
            baseEnvironment: env
        )
        env["HUB_RUNTIME_BASE_DIR"] = nodeRuntimeBase.path
        let concurrencyPolicyURL = HubModelConcurrencyPolicyStorage.url(baseDir: base)
        HubModelConcurrencyPolicyStorage.save(
            HubModelConcurrencyPolicyStorage.load(baseDir: base),
            baseDir: base
        )
        env["XHUB_MODEL_CONCURRENCY_POLICY_PATH"] = concurrencyPolicyURL.path
        env["HUB_MODEL_CONCURRENCY_POLICY_PATH"] = concurrencyPolicyURL.path
        // Bridge IPC should live next to the Hub runtime base dir so the bundled gRPC server
        // can always find Bridge status/requests in sandboxed builds (where /private/tmp may
        // not be writable). EmbeddedBridgeRunner uses the same base dir choice.
        env["HUB_BRIDGE_BASE_DIR"] = base.path
        env["HUB_AI_AUTO_LOAD"] = "1"
        for (key, value) in RustHubRuntimeSupport.nodeSidecarEnvironmentAdditions(baseEnvironment: env) {
            env[key] = value
        }
        // X-Terminal/Supervisor should not silently downgrade paid remote requests to a local model.
        // If the remote export gate blocks egress, fail closed and surface the deny code instead.
        if (env["HUB_REMOTE_EXPORT_ON_BLOCK"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            env["HUB_REMOTE_EXPORT_ON_BLOCK"] = "error"
        }
        // LAN source-IP allowlist (defense-in-depth).
        //
        // IMPORTANT: some corporate LANs use globally routable IPv4 ranges (non-RFC1918),
        // so "private" alone can incorrectly block legitimate LAN peers. We therefore
        // allow:
        // - private (RFC1918) + loopback
        // - AND the Hub's own detected IPv4 interface subnets (CIDRs)
        //
        // For remote Tailscale subnet-router mode, clients can still appear as private IPs.
        let lanAllowed = Self.defaultLANAllowedCidrs()
        let firstPairLANAllowed = Self.defaultFirstPairingLANAllowedCidrs()
        // Roaming XT devices are authenticated by token + mTLS cert pin. Keep first pairing
        // same-LAN, but do not bind an already-paired XT to the original LAN source IP.
        env["HUB_ALLOWED_CIDRS"] = "any"
        env["HUB_GRPC_PAIRED_CLIENT_ROAMING"] = "1"
        // Help the embedded Node server generate a server TLS cert whose SAN includes current LAN IPs.
        // (This is best-effort; clients still use authority override with HUB_GRPC_TLS_SERVER_NAME.)
        let sanIps: [String] = {
            var out: [String] = []
            var seen: Set<String> = []
            for row in lanAddresses {
                guard let idx = row.firstIndex(of: ":") else { continue }
                let ip = row[row.index(after: idx)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if ip.isEmpty { continue }
                let s = String(ip)
                if seen.contains(s) { continue }
                seen.insert(s)
                out.append(s)
            }
            return out
        }()
        if !sanIps.isEmpty {
            env["HUB_GRPC_TLS_SERVER_SAN_IPS"] = sanIps.joined(separator: ",")
        }

        // Pairing control plane (HTTP/JSON, unauthenticated request + admin approval).
        // Listens on gRPC port + 1 by default.
        env["HUB_PAIRING_HOST"] = serviceBindHost
        env["HUB_PAIRING_PORT"] = String(max(1, min(65535, port + 1)))
        env["HUB_PAIRING_ALLOWED_CIDRS"] = lanAllowed.joined(separator: ",")
        env["HUB_PAIRING_FIRST_PAIR_ALLOWED_CIDRS"] = firstPairLANAllowed.joined(separator: ",")
        p.environment = env

        if let h = logHandle {
            p.standardOutput = h
            p.standardError = h
        }

        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self else { return }
                Self.removeBundledServerProcessRecord(baseDir: base, pid: proc.processIdentifier)

                // Avoid clobbering a newer process if we restarted quickly.
                if let cur = self.proc, cur !== proc {
                    self.appendLogLine("gRPC exited (stale proc ignored): pid=\(proc.processIdentifier) code=\(proc.terminationStatus)")
                    return
                }

                self.proc = nil
                self.resetLocalRuntimeHealth(clearLaunchAt: true)
                if proc.terminationStatus != 0 {
                    self.failCount += 1
                    let now = Date().timeIntervalSince1970
                    let portBusy = Self.isTCPPortInUse(self.port)
                    // If the port is occupied (common EADDRINUSE scenario), back off longer so we don't crash-loop.
                    if portBusy {
                        self.lastError = HubUIStrings.Settings.GRPC.Runtime.portInUse(self.port)
                        self.failCount = max(self.failCount, 6)
                    } else if self.lastError.isEmpty {
                        self.lastError = HubUIStrings.Settings.GRPC.Runtime.serverExited(code: proc.terminationStatus)
                    }
                    var sched = self.scheduleRetryAfterFailure(now: now)
                    if portBusy {
                        self.nextStartAttemptAt = max(self.nextStartAttemptAt, now + 300.0)
                        sched.delaySec = max(sched.delaySec, 300.0)
                    }
                    if sched.inCooldown {
                        self.lastError = HubUIStrings.Settings.GRPC.Runtime.crashLoopDetected(
                            count: sched.burstCount,
                            windowSec: Int(Self.failureBurstWindowSec),
                            cooldownSec: Int(sched.delaySec)
                        )
                    }
                    self.appendExitLogRateLimited(
                        code: proc.terminationStatus,
                        retryDelaySec: sched.delaySec,
                        burstCount: sched.burstCount,
                        inCooldown: sched.inCooldown
                    )
                } else {
                    self.resetFailureBackoffState()
                    self.appendLogLine("gRPC exited: code=0")
                }
                try? self.logHandle?.close()
                self.logHandle = nil
                self.refresh()
                let stopRequestedRecently = (Date().timeIntervalSince1970 - self.stopRequestedAt) < 2.5
                if !stopRequestedRecently {
                    self.autoStartIfNeeded()
                }
            }
        }

        appendLogLine("==== start attempt ==== (autoStart=\(autoStart)) node=\(nodeLaunch.exePath) port=\(port) base=\(base.path)")

        do {
            try p.run()
            proc = p
            Self.saveBundledServerProcessRecord(
                baseDir: base,
                pid: p.processIdentifier,
                nodeExecutablePath: nodeLaunch.exePath,
                serverJSPath: serverJS.path
            )
            lastProcessLaunchAt = Date().timeIntervalSince1970
            resetLocalRuntimeHealth(clearLaunchAt: false)
            refresh()
        } catch {
            lastError = HubUIStrings.Settings.GRPC.Runtime.startFailed(error.localizedDescription)
            failCount += 1
            _ = scheduleRetryAfterFailure(now: Date().timeIntervalSince1970)
            refresh()
        }
    }

    func stop() {
        lastError = ""
        resetFailureBackoffState()
        stopRequestedAt = Date().timeIntervalSince1970
        bonjourAdvertiser.stop()

        guard let p = proc else {
            refresh()
            return
        }

        appendLogLine("gRPC stop requested")

        // Stop synchronously (short bounded waits) so `restart()` is reliable and we avoid
        // Process deinit crashes when the task is still running.
        if p.isRunning {
            let pid = pid_t(p.processIdentifier)
            p.terminate()
            _ = waitForProcessExit(p, timeoutSec: 0.9)
            if p.isRunning, pid > 1 {
                kill(pid, SIGKILL)
                _ = waitForProcessExit(p, timeoutSec: 0.9)
            }
        }

        if p.isRunning {
            // Keep reference to prevent Foundation from crashing on deinit.
            leakRunningProcess(p)
            lastError = HubUIStrings.Settings.GRPC.Runtime.stopTimedOut(pid: p.processIdentifier)
        } else {
            proc = nil
            try? logHandle?.close()
            logHandle = nil
        }

        // Hold off auto-start briefly so diagnostics actions can run without races.
        nextStartAttemptAt = Date().timeIntervalSince1970 + 2.0
        refresh()
    }

    func restart() {
        stop()
        start()
    }

    func copyClientTokenToClipboard() {
        let tok = preferredClientEntryForGuide()?.token ?? HubGRPCTokens.getOrCreateClientToken()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tok, forType: .string)
    }

    func copyAdminTokenToClipboard() {
        let tok = HubGRPCTokens.getOrCreateAdminToken()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tok, forType: .string)
    }

    func copyBootstrapCommandToClipboard() {
        let cmd = Self.bootstrapCommandText(
            host: xtTerminalInternetHostFallback,
            grpcPort: port,
            pairingPort: xtTerminalPairingPort,
            inviteToken: externalInviteTokenRecord?.tokenSecret
        )

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
    }

    static func bootstrapCommandText(
        host: String,
        grpcPort: Int,
        pairingPort: Int,
        inviteToken: String?
    ) -> String {
        let normalizedInviteToken = (inviteToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let inviteTokenLines = normalizedInviteToken.isEmpty ? "" : "INVITE_TOKEN='\(normalizedInviteToken)'\n\n"
        let inviteTokenArg = normalizedInviteToken.isEmpty ? "" : " \\\n    --invite-token \"$INVITE_TOKEN\""

        return """
HUB_HOST='\(host)'
GRPC_PORT=\(grpcPort)
PAIRING_PORT=\(pairingPort)

\(inviteTokenLines)AXHUBCTL="$HOME/.local/bin/axhubctl"
mkdir -p "$(dirname "$AXHUBCTL")"

curl -fsSL "http://${HUB_HOST}:${PAIRING_PORT}/install/axhubctl" -o "$AXHUBCTL" && \\
  curl -fsSL "http://${HUB_HOST}:${PAIRING_PORT}/install/axhubctl.sha256" -o "$AXHUBCTL.sha256" && \\
  expected="$(awk '{print $1}' "$AXHUBCTL.sha256")" && \\
  actual="$(shasum -a 256 "$AXHUBCTL" | awk '{print $1}')" && \\
  [ "$expected" = "$actual" ] && \\
  chmod +x "$AXHUBCTL" && \\
  "$AXHUBCTL" bootstrap --hub "$HUB_HOST" --pairing-port "$PAIRING_PORT" --grpc-port "$GRPC_PORT" \\
    --device-name \"<device_name>\" \\
    --requested-scopes \"models,events,memory,skills,ai.generate.local\" \\
    --require-client-kit\(inviteTokenArg)

# Verify (LAN):
"$AXHUBCTL" list-models

# Remote (domain/relay/public entry) example:
# "$AXHUBCTL" tunnel --hub <hub_remote_host> --grpc-port "$GRPC_PORT" --local-port "$GRPC_PORT" --install
# "$AXHUBCTL" tunnel --status
# "$AXHUBCTL" remote list-models
"""
    }

    @discardableResult
    func copyInviteLinkToClipboard() -> Bool {
        guard canProvisionExternalInvite else { return false }
        if externalInviteTokenRecord == nil {
            rotateExternalInviteToken()
        }
        guard let inviteURL = externalInviteURL else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(inviteURL.absoluteString, forType: .string)
        return true
    }

    @discardableResult
    func copyLocalPairingInviteLinkToClipboard() -> Bool {
        if externalInviteTokenRecord == nil {
            rotateExternalInviteToken()
        }
        guard let inviteURL = localPairingInviteURL else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(inviteURL.absoluteString, forType: .string)
        return true
    }

    @discardableResult
    func copySecureRemoteSetupPackToClipboard() -> Bool {
        guard canProvisionSecureRemoteSetupPack else { return false }
        if externalInviteTokenRecord == nil {
            rotateExternalInviteToken()
        }
        let text = secureRemoteSetupPackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return true
    }

    func rotateExternalInviteToken() {
        externalInviteTokenRecord = HubExternalInviteTokenStore.rotate()
    }

    func clearExternalInviteToken() {
        HubExternalInviteTokenStore.clear()
        externalInviteTokenRecord = nil
    }

    func copyConnectVars(for client: HubGRPCClientEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(connectionGuide(for: client.token, deviceId: client.deviceId), forType: .string)
    }

    // Exposed for UI sheets (copy connect vars for a specific token).
    func connectionGuideOverride(token: String, deviceId: String? = nil, host: String? = nil, port: Int? = nil) -> String {
        let p = port.map { String($0) }
        return connectionGuide(for: token, deviceId: deviceId, host: host, port: p)
    }

    // MARK: - Internals

    private func tick() {
        lanAddresses = Self.currentLANAddresses()
        let pairingHealthy = Self.probeLocalPairingHealth(pairingPort: Self.pairingPort(grpcPort: port))

        if isRunning {
            externalPairingHealthy = false
            localPairingHealthy = pairingHealthy
            if applyLocalRuntimeWatchdog(pairingHealthy: pairingHealthy) {
                return
            }
        } else {
            externalPairingHealthy = pairingHealthy
            resetLocalRuntimeHealth(clearLaunchAt: true)
        }

        // Detect an already-running server on this machine (e.g. another Hub app instance)
        // so we don't crash-loop due to EADDRINUSE when autoStart is enabled.
        if !isRunning,
           !externalPairingHealthy,
           let externalGrpcPort = Self.detectNearbyLocalHubGRPCPort(configuredPort: port),
           externalGrpcPort != port {
            let externalPairingPort = Self.pairingPort(grpcPort: externalGrpcPort)
            let message = HubUIStrings.Settings.GRPC.Runtime.externalHubDetected(
                grpcPort: externalGrpcPort,
                pairingPort: externalPairingPort
            )
            if autoPortSwitchMessage != message {
                autoPortSwitchMessage = message
                HubDiagnostics.log("hub_grpc.reconcile_external_port from=\(port) to=\(externalGrpcPort) pairing=\(externalPairingPort)")
            }
            port = externalGrpcPort
            externalPairingHealthy = true
            return
        }
        updateBonjourAdvertisement()
        updateStatusText()
        createClientsTemplateIfMissing()
        allowedClients = loadClientsSnapshot().clients.sorted { a, b in
            let an = a.name.lowercased()
            let bn = b.name.lowercased()
            if an != bn { return an < bn }
            return a.deviceId.lowercased() < b.deviceId.lowercased()
        }
        updateConnectionGuide()
        autoStartIfNeeded()
        refreshServingPowerState()
    }

    private func refreshServingPowerState() {
        HubServingPowerManager.shared.refreshServingState(
            autoStartEnabled: autoStart,
            serverRunning: isRunning || externalPairingHealthy,
            externalHost: xtTerminalInternetHost
        )
    }

    private func updateStatusText() {
        let tls = tlsMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tlsText = tls == "insecure" ? "insecure" : tls
        if isRunning, let p = proc {
            if !localPairingHealthy,
               !HubLocalRuntimeWatchdog.isWithinStartupGrace(
                now: Date().timeIntervalSince1970,
                launchAt: lastProcessLaunchAt
               ) {
                statusText = HubUIStrings.Settings.GRPC.Runtime.statusRecovering(
                    tlsText: tlsText,
                    pid: p.processIdentifier,
                    port: port
                )
                return
            }
            statusText = HubUIStrings.Settings.GRPC.Runtime.statusRunning(
                tlsText: tlsText,
                pid: p.processIdentifier,
                port: port
            )
            return
        }
        if externalPairingHealthy {
            statusText = HubUIStrings.Settings.GRPC.Runtime.statusRunningExternal(
                tlsText: tlsText,
                port: port
            )
            return
        }
        if let err = lastError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : lastError {
            statusText = HubUIStrings.Settings.GRPC.Runtime.statusError
            lastError = err
            return
        }
        statusText = HubUIStrings.Settings.GRPC.Runtime.statusStopped(tlsText: tlsText)
    }

    private func updateConnectionGuide() {
        let portText = String(port)
        let entry = preferredClientEntryForGuide()
        let clientToken = entry?.token ?? HubGRPCTokens.getOrCreateClientToken()
        let deviceId = entry?.deviceId ?? ""

        connectionGuide = connectionGuide(
            for: clientToken,
            deviceId: deviceId,
            host: xtTerminalInternetHostFallback,
            port: portText
        )
    }

    private func connectionGuide(for clientToken: String, deviceId: String? = nil, host: String? = nil, port portOverride: String? = nil) -> String {
        let tok = clientToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let did = (deviceId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let h = (host ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let p = (portOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let hostText = !h.isEmpty ? h : xtTerminalInternetHostFallback

        let portText = p.isEmpty ? String(self.port) : p
        let pairingPortText = String(Self.pairingPort(grpcPort: Int(portText) ?? self.port))

        let tlsText: String = {
            let mode = tlsMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if mode == "tls" {
                return "\nHUB_GRPC_TLS_MODE=tls\nHUB_GRPC_TLS_SERVER_NAME='axhub'\nHUB_GRPC_TLS_CA_CERT_PATH=$HOME/.axhub/tls/ca.cert.pem\n"
            }
            if mode == "mtls" {
                return "\nHUB_GRPC_TLS_MODE=mtls\nHUB_GRPC_TLS_SERVER_NAME='axhub'\nHUB_GRPC_TLS_CA_CERT_PATH=$HOME/.axhub/tls/ca.cert.pem\nHUB_GRPC_TLS_CLIENT_CERT_PATH=$HOME/.axhub/tls/client.cert.pem\nHUB_GRPC_TLS_CLIENT_KEY_PATH=$HOME/.axhub/tls/client.key.pem\n"
            }
            return ""
        }()

        return """
HUB_HOST=\(hostText)
HUB_PORT=\(portText)
HUB_PAIRING_PORT=\(pairingPortText)
HUB_CLIENT_TOKEN='\(tok)'
\(did.isEmpty ? "" : "HUB_DEVICE_ID='\(did)'\n")\(tlsText)
"""
    }

    private func updateBonjourAdvertisement() {
        guard isRunning, localPairingHealthy else {
            bonjourAdvertiser.stop()
            return
        }

        bonjourAdvertiser.publish(
            runtimeBaseDir: SharedPaths.ensureHubDirectory(),
            pairingPort: Self.pairingPort(grpcPort: port),
            grpcPort: port,
            internetHost: xtTerminalInternetHost
        )
    }

    private func preferredClientEntryForGuide() -> HubGRPCClientEntry? {
        // Prefer the default id if present so existing setups remain stable.
        let snap = loadClientsSnapshot()
        if let def = snap.clients.first(where: { $0.enabled && $0.deviceId == "terminal_device" }) {
            return def
        }
        if let first = snap.clients.first(where: { $0.enabled }) {
            return first
        }
        return nil
    }

    private func autoStartIfNeeded() {
        guard autoStart else { return }
        if isRunning || externalPairingHealthy { return }

        let now = Date().timeIntervalSince1970
        if now < nextStartAttemptAt {
            return
        }

        recentFailureTimes.removeAll { now - $0 > Self.failureBurstWindowSec }
        if recentFailureTimes.count >= Self.failureBurstLimit {
            nextStartAttemptAt = max(nextStartAttemptAt, now + Self.failureBurstCooldownSec)
            let remain = Int(max(1.0, nextStartAttemptAt - now))
            let lower = lastError.lowercased()
            if !lower.contains("already in use") {
                lastError = HubUIStrings.Settings.GRPC.Runtime.crashLoopDetected(
                    count: recentFailureTimes.count,
                    windowSec: Int(Self.failureBurstWindowSec),
                    cooldownSec: remain
                )
            }
            return
        }

        let exp = Double(min(7, max(0, failCount)))
        let delay = min(Self.retryMaxDelaySec, max(Self.retryMinDelaySec, pow(2.0, exp)))
        nextStartAttemptAt = now + delay
        start()
    }

}
