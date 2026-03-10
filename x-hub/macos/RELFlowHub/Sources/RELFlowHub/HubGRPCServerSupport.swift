import Foundation
import AppKit
import Darwin
import Security
import RELFlowHubCore

enum HubGRPCClientPolicyMode: String, Codable, CaseIterable, Equatable, Sendable {
    case newProfile = "new_profile"
    case legacyGrant = "legacy_grant"

    var title: String {
        switch self {
        case .newProfile:
            return "Policy Profile"
        case .legacyGrant:
            return "Legacy Grant"
        }
    }
}

enum HubPaidModelSelectionMode: String, Codable, CaseIterable, Equatable, Sendable {
    case off = "off"
    case allPaidModels = "all_paid_models"
    case customSelectedModels = "custom_selected_models"

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .allPaidModels:
            return "All Paid Models"
        case .customSelectedModels:
            return "Custom Selected Models"
        }
    }
}

enum HubTrustProfileDefaults {
    static let trustMode = "trusted_daily"
    static let dailyTokenLimit = 500_000
    static let singleRequestTokenLimit = 12_000
}

struct HubPairedTerminalPaidModelPolicy: Codable, Equatable, Sendable {
    var schemaVersion: String
    var mode: HubPaidModelSelectionMode
    var allowedModelIds: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case mode
        case allowedModelIds = "allowed_model_ids"
    }

    init(mode: HubPaidModelSelectionMode, allowedModelIds: [String]) {
        self.schemaVersion = "hub.paired_terminal_paid_model_policy.v1"
        self.mode = mode
        self.allowedModelIds = HubGRPCClientEntry.normalizedStrings(
            mode == .customSelectedModels ? allowedModelIds : []
        )
    }
}

struct HubPairedTerminalNetworkPolicy: Codable, Equatable, Sendable {
    var defaultWebFetchEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case defaultWebFetchEnabled = "default_web_fetch_enabled"
    }
}

struct HubPairedTerminalBudgetPolicy: Codable, Equatable, Sendable {
    var dailyTokenLimit: Int
    var singleRequestTokenLimit: Int

    enum CodingKeys: String, CodingKey {
        case dailyTokenLimit = "daily_token_limit"
        case singleRequestTokenLimit = "single_request_token_limit"
    }
}

struct HubPairedTerminalTrustProfile: Codable, Equatable, Sendable {
    var schemaVersion: String
    var deviceId: String
    var deviceName: String
    var trustMode: String
    var capabilities: [String]
    var paidModelPolicy: HubPairedTerminalPaidModelPolicy
    var networkPolicy: HubPairedTerminalNetworkPolicy
    var budgetPolicy: HubPairedTerminalBudgetPolicy
    var auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case deviceId = "device_id"
        case deviceName = "device_name"
        case trustMode = "trust_mode"
        case capabilities
        case paidModelPolicy = "paid_model_policy"
        case networkPolicy = "network_policy"
        case budgetPolicy = "budget_policy"
        case auditRef = "audit_ref"
    }
}

// Allowed gRPC clients (LAN).
//
// Stored in: <hub_base>/hub_grpc_clients.json
// - hub_base defaults to ~/Library/Group Containers/group.rel.flowhub (or app container in dev)
// - device_id is the *authenticated* identity used for quota/audit/policy on the Hub.
// - user_id is an optional stable identity bound to the token (needed for Global(user_id) skills to work across devices).
struct HubGRPCClientEntry: Identifiable, Codable, Equatable, Sendable {
    var deviceId: String
    var userId: String
    var name: String
    var token: String
    var enabled: Bool
    var createdAtMs: Int64
    var capabilities: [String]
    var allowedCidrs: [String]
    var certSha256: String
    var policyMode: HubGRPCClientPolicyMode
    var approvedTrustProfile: HubPairedTerminalTrustProfile?

    var id: String { deviceId }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case userId = "user_id"
        case name
        case token
        case enabled
        case createdAtMs = "created_at_ms"
        case capabilities
        case allowedCidrs = "allowed_cidrs"
        case certSha256 = "cert_sha256"
        case policyMode = "policy_mode"
        case approvedTrustProfile = "approved_trust_profile"
    }

    init(
        deviceId: String,
        userId: String = "",
        name: String,
        token: String,
        enabled: Bool,
        createdAtMs: Int64,
        capabilities: [String] = [],
        allowedCidrs: [String] = [],
        certSha256: String = "",
        policyMode: HubGRPCClientPolicyMode = .legacyGrant,
        approvedTrustProfile: HubPairedTerminalTrustProfile? = nil
    ) {
        self.deviceId = deviceId
        self.userId = userId
        self.name = name
        self.token = token
        self.enabled = enabled
        self.createdAtMs = createdAtMs
        self.capabilities = HubGRPCClientEntry.normalizedStrings(capabilities)
        self.allowedCidrs = allowedCidrs
        self.certSha256 = certSha256
        self.policyMode = policyMode
        self.approvedTrustProfile = approvedTrustProfile
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = (try? c.decode(String.self, forKey: .deviceId)) ?? ""
        userId = (try? c.decode(String.self, forKey: .userId)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        token = (try? c.decode(String.self, forKey: .token)) ?? ""
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        createdAtMs = (try? c.decode(Int64.self, forKey: .createdAtMs)) ?? 0
        capabilities = HubGRPCClientEntry.normalizedStrings((try? c.decode([String].self, forKey: .capabilities)) ?? [])
        allowedCidrs = (try? c.decode([String].self, forKey: .allowedCidrs)) ?? []
        certSha256 = (try? c.decode(String.self, forKey: .certSha256)) ?? ""
        approvedTrustProfile = try? c.decode(HubPairedTerminalTrustProfile.self, forKey: .approvedTrustProfile)
        if let rawMode = try? c.decode(String.self, forKey: .policyMode),
           let decodedMode = HubGRPCClientPolicyMode(rawValue: rawMode) {
            policyMode = decodedMode
        } else {
            policyMode = approvedTrustProfile == nil ? .legacyGrant : .newProfile
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(deviceId, forKey: .deviceId)
        try c.encode(userId, forKey: .userId)
        try c.encode(name, forKey: .name)
        try c.encode(token, forKey: .token)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(createdAtMs, forKey: .createdAtMs)
        try c.encode(HubGRPCClientEntry.normalizedStrings(capabilities), forKey: .capabilities)
        try c.encode(allowedCidrs, forKey: .allowedCidrs)
        try c.encode(certSha256, forKey: .certSha256)
        try c.encode(policyMode.rawValue, forKey: .policyMode)
        try c.encodeIfPresent(approvedTrustProfile, forKey: .approvedTrustProfile)
    }

    static func normalizedStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for raw in values {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            ordered.append(trimmed)
        }
        return ordered
    }

    static func derivedCapabilities(
        requestedCapabilities: [String],
        paidModelSelectionMode: HubPaidModelSelectionMode,
        defaultWebFetchEnabled: Bool
    ) -> [String] {
        let requested = normalizedStrings(requestedCapabilities)
        var out = (requested.isEmpty ? ["models", "events", "memory", "skills", "ai.generate.local"] : requested)
            .filter { $0 != "ai.generate.paid" && $0 != "web.fetch" }
        if paidModelSelectionMode != .off {
            out.append("ai.generate.paid")
        }
        if defaultWebFetchEnabled {
            out.append("web.fetch")
        }
        return normalizedStrings(out)
    }

    static func buildApprovedTrustProfile(
        deviceId: String,
        deviceName: String,
        requestedCapabilities: [String],
        paidModelSelectionMode: HubPaidModelSelectionMode,
        allowedPaidModels: [String],
        defaultWebFetchEnabled: Bool,
        dailyTokenLimit: Int,
        auditRef: String
    ) -> HubPairedTerminalTrustProfile {
        let paidPolicy = HubPairedTerminalPaidModelPolicy(
            mode: paidModelSelectionMode,
            allowedModelIds: allowedPaidModels
        )
        let capabilities = derivedCapabilities(
            requestedCapabilities: requestedCapabilities,
            paidModelSelectionMode: paidPolicy.mode,
            defaultWebFetchEnabled: defaultWebFetchEnabled
        )
        return HubPairedTerminalTrustProfile(
            schemaVersion: "hub.paired_terminal_trust_profile.v1",
            deviceId: deviceId,
            deviceName: deviceName,
            trustMode: HubTrustProfileDefaults.trustMode,
            capabilities: capabilities,
            paidModelPolicy: paidPolicy,
            networkPolicy: HubPairedTerminalNetworkPolicy(defaultWebFetchEnabled: defaultWebFetchEnabled),
            budgetPolicy: HubPairedTerminalBudgetPolicy(
                dailyTokenLimit: max(1, dailyTokenLimit),
                singleRequestTokenLimit: HubTrustProfileDefaults.singleRequestTokenLimit
            ),
            auditRef: auditRef
        )
    }
}

struct HubGRPCClientsSnapshot: Codable, Equatable, Sendable {
    var schemaVersion: String
    var updatedAtMs: Int64
    var clients: [HubGRPCClientEntry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case clients
    }

    static func empty() -> HubGRPCClientsSnapshot {
        HubGRPCClientsSnapshot(schemaVersion: "hub_grpc_clients.v1", updatedAtMs: 0, clients: [])
    }
}

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

    @Published private(set) var statusText: String = "gRPC: unknown"
    @Published private(set) var lastError: String = ""
    @Published private(set) var lanAddresses: [String] = []
    @Published private(set) var connectionGuide: String = ""
    @Published private(set) var allowedClients: [HubGRPCClientEntry] = []

    var xtTerminalInternetHost: String? {
        Self.firstNonLoopbackIPv4(from: lanAddresses)
    }

    var xtTerminalInternetHostFallback: String {
        xtTerminalInternetHost ?? "127.0.0.1"
    }

    var xtTerminalPairingPort: Int {
        Self.pairingPort(grpcPort: port)
    }

    private static let autoStartKey = "relflowhub_grpc_autostart"
    private static let portKey = "relflowhub_grpc_port"
    private static let tlsModeKey = "relflowhub_grpc_tls_mode"

    private static let defaultPort: Int = 50051

    private var proc: Process?
    private var logHandle: FileHandle?
    private var timer: Timer?
    private var stopRequestedAt: Double = 0

    // If a Process is still running when it deinitializes, Foundation can throw an ObjC
    // exception which aborts the app. Keep a small bounded set of "leaked" processes as
    // a last resort to prevent startup crashes if we fail to terminate within timeouts.
    private var leakedProcs: [Process] = []

    private var nextStartAttemptAt: Double = 0
    private var failCount: Int = 0
    private var externalPairingHealthy: Bool = false
    private var recentFailureTimes: [Double] = []
    private var lastExitLogSignature: String = ""
    private var lastExitLogAt: Double = 0

    private static let retryMinDelaySec: Double = 3.0
    private static let retryMaxDelaySec: Double = 300.0
    private static let failureBurstWindowSec: Double = 90.0
    private static let failureBurstLimit: Int = 4
    private static let failureBurstCooldownSec: Double = 300.0
    private static let duplicateExitLogCooldownSec: Double = 12.0

    var isRunning: Bool {
        if let p = proc, p.isRunning {
            return true
        }
        return false
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

        // If the configured port is already occupied, avoid crash-looping the embedded Node server.
        // This happens when another Hub instance (or a different process) is already listening on the same port.
        if Self.isTCPPortInUse(port) {
            // If the FlowHub pairing port is healthy, treat it as an already-running server instance.
            let pairingOk = Self.probeLocalPairingHealth(pairingPort: Self.pairingPort(grpcPort: port))
            externalPairingHealthy = pairingOk
            if pairingOk {
                // No need to start a second copy; just surface status.
                lastError = ""
                resetFailureBackoffState()
                refresh()
                return
            }

            lastError = "Port \(port) is already in use. Stop the other process or change the port in Settings → LAN (gRPC) → Advanced."
            failCount = max(failCount, 6)
            let now = Date().timeIntervalSince1970
            let sched = scheduleRetryAfterFailure(now: now)
            // Port conflicts rarely self-heal quickly; keep a strong cool-down.
            nextStartAttemptAt = max(nextStartAttemptAt, now + 300.0, now + sched.delaySec)
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
            lastError = "Node not found. Please install Node.js (v22+) or set a custom Node path."
            statusText = "gRPC: node missing"
            failCount += 1
            _ = scheduleRetryAfterFailure(now: Date().timeIntervalSince1970)
            return
        }

        guard let serverJS = bundledServerJSURL() else {
            lastError = "Bundled gRPC server not found in app Resources. Rebuild Hub with tools/build_hub_app.command."
            statusText = "gRPC: missing server.js"
            failCount += 1
            _ = scheduleRetryAfterFailure(now: Date().timeIntervalSince1970)
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

        var env = ProcessInfo.processInfo.environment
        env["HUB_HOST"] = "0.0.0.0"
        env["HUB_PORT"] = String(port)
        env["HUB_DB_PATH"] = dbURL.path
        env["HUB_CLIENT_TOKEN"] = clientToken
        env["HUB_ADMIN_TOKEN"] = adminToken
        env["HUB_GRPC_TLS_MODE"] = tlsMode
        // Stable authority name for TLS host verification when clients connect by IP.
        env["HUB_GRPC_TLS_SERVER_NAME"] = "axhub"
        // Enforce token + client-cert pin in mTLS mode (defense-in-depth).
        env["HUB_GRPC_MTLS_REQUIRE_CERT_PIN"] = "1"
        // Pin base dir so Node uses the same filesystem IPC directories as the Hub runtime + Bridge.
        env["HUB_RUNTIME_BASE_DIR"] = base.path
        // Bridge IPC should live next to the Hub runtime base dir so the bundled gRPC server
        // can always find Bridge status/requests in sandboxed builds (where /private/tmp may
        // not be writable). EmbeddedBridgeRunner uses the same base dir choice.
        env["HUB_BRIDGE_BASE_DIR"] = base.path
        env["HUB_AI_AUTO_LOAD"] = "1"
        // LAN source-IP allowlist (defense-in-depth).
        //
        // IMPORTANT: some corporate LANs use globally routable IPv4 ranges (non-RFC1918),
        // so "private" alone can incorrectly block legitimate LAN peers. We therefore
        // allow:
        // - private (RFC1918) + loopback
        // - AND the Hub's own detected IPv4 interface subnets (CIDRs)
        //
        // For remote mode (VPN), clients typically fall under "private" (10.x/172.16/192.168).
        let lanAllowed = Self.defaultLANAllowedCidrs()
        env["HUB_ALLOWED_CIDRS"] = lanAllowed.joined(separator: ",")
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
        env["HUB_PAIRING_HOST"] = "0.0.0.0"
        env["HUB_PAIRING_PORT"] = String(max(1, min(65535, port + 1)))
        env["HUB_PAIRING_ALLOWED_CIDRS"] = lanAllowed.joined(separator: ",")
        p.environment = env

        if let h = logHandle {
            p.standardOutput = h
            p.standardError = h
        }

        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self else { return }

                // Avoid clobbering a newer process if we restarted quickly.
                if let cur = self.proc, cur !== proc {
                    self.appendLogLine("gRPC exited (stale proc ignored): pid=\(proc.processIdentifier) code=\(proc.terminationStatus)")
                    return
                }

                self.proc = nil
                if proc.terminationStatus != 0 {
                    self.failCount += 1
                    let now = Date().timeIntervalSince1970
                    let portBusy = Self.isTCPPortInUse(self.port)
                    // If the port is occupied (common EADDRINUSE scenario), back off longer so we don't crash-loop.
                    if portBusy {
                        self.lastError = "Port \(self.port) is already in use. Stop the other process or change the port in Settings → LAN (gRPC) → Advanced."
                        self.failCount = max(self.failCount, 6)
                    } else if self.lastError.isEmpty {
                        self.lastError = "gRPC server exited (code \(proc.terminationStatus)). Check hub_grpc.log for details."
                    }
                    var sched = self.scheduleRetryAfterFailure(now: now)
                    if portBusy {
                        self.nextStartAttemptAt = max(self.nextStartAttemptAt, now + 300.0)
                        sched.delaySec = max(sched.delaySec, 300.0)
                    }
                    if sched.inCooldown {
                        self.lastError = "gRPC crash-loop detected (\(sched.burstCount)x/\(Int(Self.failureBurstWindowSec))s). Auto-retry cooling down \(Int(sched.delaySec))s. Check hub_grpc.log or click Fix Now."
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
            refresh()
        } catch {
            lastError = "Failed to start gRPC server: \(error.localizedDescription)"
            failCount += 1
            _ = scheduleRetryAfterFailure(now: Date().timeIntervalSince1970)
            refresh()
        }
    }

    func stop() {
        lastError = ""
        resetFailureBackoffState()
        stopRequestedAt = Date().timeIntervalSince1970

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
            lastError = "Failed to stop gRPC server (timeout). pid=\(p.processIdentifier)"
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
        let pairingPort = xtTerminalPairingPort
        let hostText = xtTerminalInternetHostFallback

        let cmd = """
HUB_HOST='\(hostText)'
GRPC_PORT=\(port)
PAIRING_PORT=\(pairingPort)

AXHUBCTL="$HOME/.local/bin/axhubctl"
mkdir -p "$(dirname "$AXHUBCTL")"

curl -fsSL "http://${HUB_HOST}:${PAIRING_PORT}/install/axhubctl" -o "$AXHUBCTL" && \\
  curl -fsSL "http://${HUB_HOST}:${PAIRING_PORT}/install/axhubctl.sha256" -o "$AXHUBCTL.sha256" && \\
  expected="$(awk '{print $1}' "$AXHUBCTL.sha256")" && \\
  actual="$(shasum -a 256 "$AXHUBCTL" | awk '{print $1}')" && \\
  [ "$expected" = "$actual" ] && \\
  chmod +x "$AXHUBCTL" && \\
  "$AXHUBCTL" bootstrap --hub "$HUB_HOST" --pairing-port "$PAIRING_PORT" --grpc-port "$GRPC_PORT" \\
    --device-name \"<device_name>\" \\
    --requested-scopes \"models,events,memory,skills,ai.generate.local\"

# Verify (LAN):
"$AXHUBCTL" list-models

# Remote (VPN/Tunnel) example:
# "$AXHUBCTL" tunnel --hub <hub_vpn_or_tailnet_host> --grpc-port "$GRPC_PORT" --local-port "$GRPC_PORT" --install
# "$AXHUBCTL" tunnel --status
# "$AXHUBCTL" remote list-models
"""

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
    }

    // For local control-plane calls (e.g. pairing approvals). Keep token private to Hub.
    func localAdminToken() -> String {
        HubGRPCTokens.getOrCreateAdminToken()
    }

    func regenerateClientToken() {
        let tok = HubGRPCTokens.regenerateClientToken()

        // Keep the default entry in hub_grpc_clients.json in sync.
        createClientsTemplateIfMissing()
        var snap = loadClientsSnapshot()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        var updated = false
        for i in snap.clients.indices {
            if snap.clients[i].deviceId == "terminal_device" {
                snap.clients[i].token = tok
                snap.clients[i].enabled = true
                snap.clients[i].createdAtMs = nowMs
                updated = true
            }
        }
        if !updated {
            snap.clients.append(
                HubGRPCClientEntry(
                    deviceId: "terminal_device",
                    userId: "",
                    name: "Terminal (default)",
                    token: tok,
                    enabled: true,
                    createdAtMs: nowMs,
                    capabilities: HubGRPCClientsStore.defaultCapabilities(),
                    allowedCidrs: HubGRPCClientsStore.defaultAllowedCidrs()
                )
            )
        }
        snap.updatedAtMs = nowMs
        saveClientsSnapshot(snap)
        restart()
    }

    func regenerateAdminToken() {
        _ = HubGRPCTokens.regenerateAdminToken()
        restart()
    }

    func openLog() {
        let base = SharedPaths.ensureHubDirectory()
        let logURL = base.appendingPathComponent("hub_grpc.log")
        NSWorkspace.shared.open(logURL)
    }

    func quotaConfigURL() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent("hub_quotas.json")
    }

    func clientsConfigURL() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent("hub_grpc_clients.json")
    }

    func createQuotaTemplateIfMissing() {
        let url = quotaConfigURL()
        if FileManager.default.fileExists(atPath: url.path) {
            return
        }
        let template: [String: Any] = [
            "default_daily_token_cap": 0,
            "devices": [
                "terminal_device": ["daily_token_cap": 50_000],
            ],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: template, options: [.prettyPrinted]),
           let s = String(data: data, encoding: .utf8),
           let out = (s + "\n").data(using: .utf8) {
            try? out.write(to: url, options: .atomic)
        }
    }

    func openQuotaConfig() {
        createQuotaTemplateIfMissing()
        NSWorkspace.shared.open(quotaConfigURL())
    }

    private func createClientsTemplateIfMissing() {
        let url = clientsConfigURL()
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(HubGRPCClientsSnapshot.self, from: data),
           !decoded.clients.isEmpty {
            return
        }

        // Keep default client token stable across restarts (Keychain).
        let tok = HubGRPCTokens.getOrCreateClientToken()
        let snap = HubGRPCClientsStore.defaultSnapshot(defaultToken: tok)
        saveClientsSnapshot(snap)
    }

    private func loadClientsSnapshot() -> HubGRPCClientsSnapshot {
        let url = clientsConfigURL()
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONDecoder().decode(HubGRPCClientsSnapshot.self, from: data) else {
            return .empty()
        }
        return obj
    }

    private func saveClientsSnapshot(_ snap: HubGRPCClientsSnapshot) {
        var cur = snap
        if cur.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cur.schemaVersion = "hub_grpc_clients.v1"
        }
        if cur.updatedAtMs <= 0 {
            cur.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        }

        let url = clientsConfigURL()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data0 = try? enc.encode(cur),
              let s = String(data: data0, encoding: .utf8),
              let out = (s + "\n").data(using: .utf8) else {
            return
        }
        try? out.write(to: url, options: .atomic)
        // Contains bearer tokens; keep owner-readable only.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func openClientsConfig() {
        createClientsTemplateIfMissing()
        NSWorkspace.shared.open(clientsConfigURL())
    }

    @discardableResult
    func createClient(name: String) -> HubGRPCClientEntry {
        createClientsTemplateIfMissing()
        var snap = loadClientsSnapshot()

        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanedName.isEmpty ? "LAN Client" : cleanedName

        // Generate a stable device_id for quota/policy. Keep it URL/filesystem friendly.
        let rawId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let deviceId = "dev_" + String(rawId.prefix(12))
        let token = HubGRPCClientsStore.generateToken(prefix: "axhub_client_")
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)

        let entry = HubGRPCClientEntry(
            deviceId: deviceId,
            userId: "",
            name: displayName,
            token: token,
            enabled: true,
            createdAtMs: nowMs,
            // Safe default: local-only + memory/events. Paid/network require explicit enable.
            capabilities: HubGRPCClientsStore.defaultCapabilities(),
            // Safe default: bind token to LAN (private RFC1918) + loopback.
            allowedCidrs: HubGRPCClientsStore.defaultAllowedCidrs()
        )

        snap.clients.append(entry)
        snap.updatedAtMs = nowMs
        saveClientsSnapshot(snap)
        refresh()
        return entry
    }

    func upsertClient(_ entry: HubGRPCClientEntry) {
        createClientsTemplateIfMissing()
        var snap = loadClientsSnapshot()
        let did = entry.deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !did.isEmpty else { return }

        var replaced = false
        for i in snap.clients.indices {
            if snap.clients[i].deviceId == did {
                snap.clients[i] = entry
                replaced = true
            }
        }
        if !replaced {
            snap.clients.append(entry)
        }

        snap.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        saveClientsSnapshot(snap)
        refresh()
    }

    func setClientEnabled(deviceId: String, enabled: Bool) {
        createClientsTemplateIfMissing()
        var snap = loadClientsSnapshot()
        let did = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !did.isEmpty else { return }
        var changed = false
        for i in snap.clients.indices {
            if snap.clients[i].deviceId == did {
                if snap.clients[i].enabled != enabled {
                    snap.clients[i].enabled = enabled
                    changed = true
                }
            }
        }
        guard changed else { return }
        snap.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        saveClientsSnapshot(snap)
        refresh()
    }

    func addAllowedCidr(deviceId: String, value: String) {
        createClientsTemplateIfMissing()
        var snap = loadClientsSnapshot()
        let did = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !did.isEmpty, !raw.isEmpty else { return }

        var changed = false
        for i in snap.clients.indices {
            if snap.clients[i].deviceId != did { continue }

            // Empty = allow-any source IP. Don't change semantics in this helper.
            if snap.clients[i].allowedCidrs.isEmpty { return }

            var cur = Self.normalizeAllowedCidrs(snap.clients[i].allowedCidrs)
            let canon = Self.canonicalAllowedCidrValue(raw)
            if canon.isEmpty { return }
            if cur.contains(where: { $0.lowercased() == canon.lowercased() }) { return }
            cur.append(canon)
            snap.clients[i].allowedCidrs = Self.orderedAllowedCidrs(cur)
            changed = true
        }

        guard changed else { return }
        snap.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        saveClientsSnapshot(snap)
        refresh()
    }

    @discardableResult
    func rotateClientToken(deviceId: String) -> String? {
        createClientsTemplateIfMissing()
        var snap = loadClientsSnapshot()
        let did = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !did.isEmpty else { return nil }
        let newToken: String = {
            if did == "terminal_device" {
                // Keep Keychain token in sync for the default client.
                return HubGRPCTokens.regenerateClientToken()
            }
            return HubGRPCClientsStore.generateToken(prefix: "axhub_client_")
        }()
        var changed = false
        for i in snap.clients.indices {
            if snap.clients[i].deviceId == did {
                snap.clients[i].token = newToken
                snap.clients[i].createdAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
                changed = true
            }
        }
        guard changed else { return nil }
        snap.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        saveClientsSnapshot(snap)
        refresh()
        return newToken
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
        // Detect an already-running server on this machine (e.g. another Hub app instance)
        // so we don't crash-loop due to EADDRINUSE when autoStart is enabled.
        externalPairingHealthy = Self.probeLocalPairingHealth(pairingPort: Self.pairingPort(grpcPort: port))
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
    }

    private static func canonicalAllowedCidrValue(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "" }
        let lower = cleaned.lowercased()
        if lower == "localhost" { return "loopback" }
        if lower == "loopback" { return "loopback" }
        if lower == "private" { return "private" }
        return cleaned
    }

    private static func normalizeAllowedCidrs(_ list: [String]) -> [String] {
        let raw = list
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Any/* means "allow any source IP" (represented as empty list).
        if raw.contains(where: { s in
            let lower = s.lowercased()
            return lower == "any" || lower == "*"
        }) {
            return []
        }

        // De-dup while preserving order.
        var seen = Set<String>()
        var out: [String] = []
        for s in raw {
            let canon = canonicalAllowedCidrValue(s)
            let key = canon.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(canon)
        }
        return out
    }

    private static func orderedAllowedCidrs(_ list: [String]) -> [String] {
        let clean = normalizeAllowedCidrs(list)
        if clean.isEmpty { return [] }

        // Keep stable order but pull well-known rules to the front.
        let order = ["private", "loopback"]
        var out: [String] = []
        for k in order {
            if clean.contains(where: { $0.lowercased() == k }) { out.append(k) }
        }
        out.append(contentsOf: clean.filter { v in
            let lower = v.lowercased()
            return !order.contains(lower)
        })
        return out
    }

    private func updateStatusText() {
        let tls = tlsMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tlsText = tls == "insecure" ? "insecure" : tls
        if isRunning, let p = proc {
            statusText = "gRPC: running · tls \(tlsText) · pid \(p.processIdentifier) · 0.0.0.0:\(port)"
            return
        }
        if externalPairingHealthy {
            statusText = "gRPC: running (external) · tls \(tlsText) · 0.0.0.0:\(port)"
            return
        }
        if let err = lastError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : lastError {
            statusText = "gRPC: error"
            lastError = err
            return
        }
        statusText = "gRPC: off · tls \(tlsText)"
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

    private static func firstNonLoopbackIPv4(from rows: [String]) -> String? {
        for row in rows {
            guard let idx = row.firstIndex(of: ":") else { continue }
            let addr = row[row.index(after: idx)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if addr.isEmpty || addr == "127.0.0.1" {
                continue
            }
            return String(addr)
        }
        return nil
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

    private func resetFailureBackoffState() {
        failCount = 0
        nextStartAttemptAt = 0
        recentFailureTimes.removeAll(keepingCapacity: false)
        lastExitLogSignature = ""
        lastExitLogAt = 0
    }

    @discardableResult
    private func scheduleRetryAfterFailure(now: Double) -> (delaySec: Double, burstCount: Int, inCooldown: Bool) {
        recentFailureTimes.append(now)
        recentFailureTimes.removeAll { now - $0 > Self.failureBurstWindowSec }
        let burstCount = recentFailureTimes.count

        let exp = Double(min(7, max(0, failCount)))
        var delay = max(Self.retryMinDelaySec, pow(2.0, exp))
        delay = min(Self.retryMaxDelaySec, delay)

        var inCooldown = false
        if burstCount >= Self.failureBurstLimit {
            delay = max(delay, Self.failureBurstCooldownSec)
            inCooldown = true
        }

        nextStartAttemptAt = now + delay
        return (delay, burstCount, inCooldown)
    }

    private func appendExitLogRateLimited(code: Int32, retryDelaySec: Double, burstCount: Int, inCooldown: Bool) {
        let now = Date().timeIntervalSince1970
        let sig = "c=\(code)|d=\(Int(retryDelaySec))|b=\(burstCount)|cd=\(inCooldown ? 1 : 0)"
        if sig == lastExitLogSignature, (now - lastExitLogAt) < Self.duplicateExitLogCooldownSec {
            return
        }
        lastExitLogSignature = sig
        lastExitLogAt = now
        let cooldownText = inCooldown ? " cooldown=1" : ""
        appendLogLine("gRPC exited: code=\(code) fail_count=\(failCount) retry_in=\(Int(retryDelaySec))s burst=\(burstCount)\(cooldownText)")
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
                lastError = "gRPC crash-loop detected (\(recentFailureTimes.count)x/\(Int(Self.failureBurstWindowSec))s). Auto-retry cooling down \(remain)s. Check hub_grpc.log or click Fix Now."
            }
            return
        }

        let exp = Double(min(7, max(0, failCount)))
        let delay = min(Self.retryMaxDelaySec, max(Self.retryMinDelaySec, pow(2.0, exp)))
        nextStartAttemptAt = now + delay
        start()
    }

    private func appendLogLine(_ line: String) {
        guard let h = logHandle else { return }
        let s = "\(Date().timeIntervalSince1970)\t\(line)\n"
        if let data = s.data(using: .utf8) {
            try? h.write(contentsOf: data)
        }
    }

    private func leakRunningProcess(_ p: Process) {
        leakedProcs.append(p)
        if leakedProcs.count > 8 {
            leakedProcs.removeFirst(leakedProcs.count - 8)
        }
    }

    private func waitForProcessExit(_ p: Process, timeoutSec: Double) -> Bool {
        let deadline = Date().addingTimeInterval(max(0.1, timeoutSec))
        while p.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.03))
        }
        return !p.isRunning
    }

    private static func pairingPort(grpcPort: Int) -> Int {
        max(1, min(65535, grpcPort + 1))
    }

    private static func isTCPPortInUse(_ port: Int) -> Bool {
        let p = max(1, min(65535, port))
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        if sock < 0 { return false }
        defer { close(sock) }

        var yes: Int32 = 1
        _ = setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(p).bigEndian
        addr.sin_addr = in_addr(s_addr: in_addr_t(0)) // INADDR_ANY

        let bindRes: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindRes == 0 {
            return false
        }
        if errno == EADDRINUSE {
            return true
        }
        return false
    }

    static func diagnosticsFindAvailablePort(startingAt: Int, maxTries: Int = 32) -> Int? {
        // Ensure pairing port (grpc+1) stays valid.
        let start = max(1024, min(65534, startingAt))
        let cap = max(1, maxTries)
        for delta in 0..<cap {
            let p = start + delta
            if p > 65534 { break }
            if isTCPPortInUse(p) { continue }
            if isTCPPortInUse(pairingPort(grpcPort: p)) { continue }
            return p
        }
        return nil
    }

    private static func probeLocalPairingHealth(pairingPort: Int) -> Bool {
        let p = max(1, min(65535, pairingPort))
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        if sock < 0 { return false }
        defer { close(sock) }

        // Ensure the probe never stalls the UI thread.
        var tv = timeval(tv_sec: 0, tv_usec: 200_000) // 200ms
        _ = setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(p).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let connRes: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connRes != 0 {
            return false
        }

        // Minimal HTTP probe: if the embedded pairing server is up, it responds with JSON
        // containing `"service":"pairing"`.
        let req = "GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        _ = req.withCString { cstr in
            Darwin.send(sock, cstr, strlen(cstr), 0)
        }

        var buf = [UInt8](repeating: 0, count: 1024)
        let n = Darwin.recv(sock, &buf, buf.count, 0)
        if n <= 0 { return false }
        let data = Data(buf.prefix(Int(n)))
        let s = String(data: data, encoding: .utf8) ?? ""
        return s.contains("\"service\":\"pairing\"")
    }

    private struct NodeLaunchConfig: Equatable {
        var exePath: String
        var argsPrefix: [String]
    }

    private func autoDetectNodeLaunch() -> NodeLaunchConfig? {
        let fm = FileManager.default

        // Prefer a bundled Node runtime (works in App Sandbox; avoids relying on system PATH/Homebrew).
        if let u = Bundle.main.url(forAuxiliaryExecutable: "relflowhub_node") {
            let p = u.path
            if fm.isExecutableFile(atPath: p) {
                return NodeLaunchConfig(exePath: p, argsPrefix: [])
            }
        }

        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ]
        for c in candidates {
            if fm.isExecutableFile(atPath: c) {
                return NodeLaunchConfig(exePath: c, argsPrefix: [])
            }
        }
        // Fallback: try /usr/bin/env node (may work if PATH is configured for the app).
        if fm.isExecutableFile(atPath: "/usr/bin/env") {
            let probe = Process()
            probe.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            probe.arguments = ["node", "--version"]
            let out = Pipe()
            let err = Pipe()
            probe.standardOutput = out
            probe.standardError = err
            do {
                try probe.run()
            } catch {
                return nil
            }
            probe.waitUntilExit()
            if probe.terminationStatus == 0 {
                return NodeLaunchConfig(exePath: "/usr/bin/env", argsPrefix: ["node"])
            }
        }
        return nil
    }

    private func bundledServerJSURL() -> URL? {
        // Bundled layout (Resources):
        // - hub_grpc_server/src/server.js
        // - hub_grpc_server/node_modules/...
        // - protocol/hub_protocol_v1.proto (sibling of hub_grpc_server/ under Resources)
        if let r = Bundle.main.resourceURL {
            let cand = r.appendingPathComponent("hub_grpc_server", isDirectory: true)
                .appendingPathComponent("src", isDirectory: true)
                .appendingPathComponent("server.js")
            if FileManager.default.fileExists(atPath: cand.path) {
                return cand
            }
        }

        // Dev fallback: run from repo root.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let dev = cwd.appendingPathComponent("hub_grpc_server", isDirectory: true)
            .appendingPathComponent("src", isDirectory: true)
            .appendingPathComponent("server.js")
        if FileManager.default.fileExists(atPath: dev.path) {
            return dev
        }
        return nil
    }

    private static func redactedToken(_ token: String) -> String {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 10 { return t }
        let a = t.prefix(4)
        let b = t.suffix(4)
        return "\(a)…\(b)"
    }

    private static func currentLANAddresses() -> [String] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return []
        }
        defer {
            freeifaddrs(ifaddr)
        }

        var out: [String] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }

            let flags = Int32(p.pointee.ifa_flags)
            if (flags & IFF_UP) == 0 { continue }
            if (flags & IFF_LOOPBACK) != 0 { continue }

            guard let addr = p.pointee.ifa_addr else { continue }
            if addr.pointee.sa_family != UInt8(AF_INET) { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            var sa = addr.pointee
            let ok = withUnsafePointer(to: &sa) { saPtr -> Int32 in
                let sa2 = UnsafeRawPointer(saPtr).assumingMemoryBound(to: sockaddr.self)
                return getnameinfo(sa2, socklen_t(sa2.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            }
            if ok != 0 { continue }

            let ip = String(cString: host)
            if ip == "127.0.0.1" { continue }
            if ip.hasPrefix("169.254.") { continue } // link-local

            let ifname = String(cString: p.pointee.ifa_name)
            out.append("\(ifname): \(ip)")
        }

        // Sort so en0/en1 are near the top.
        out.sort { a, b in
            let pa = a.lowercased()
            let pb = b.lowercased()
            if pa.hasPrefix("en0:") != pb.hasPrefix("en0:") {
                return pa.hasPrefix("en0:")
            }
            return pa < pb
        }
        return out
    }

    private static func defaultLANAllowedCidrs() -> [String] {
        var out: [String] = ["private", "loopback"]
        for cidr in currentLANIPv4Cidrs(maxBroadPrefix: 16) {
            if !out.contains(cidr) {
                out.append(cidr)
            }
        }
        // Some corporate networks use globally routable IPv4 ranges (non-RFC1918), and are also
        // segmented into many /24s. In those environments, restricting to the Hub's *exact* interface
        // subnet can incorrectly block legitimate peers (e.g. Hub is 17.81.12.x/24 but a coworker is
        // 17.81.11.x/24).
        //
        // As a pragmatic, defense-in-depth default for pairing + gRPC ports, we also allow a /16
        // "coarse LAN" supernet derived from the Hub's active IPv4 addresses (when not private).
        //
        // Devices can (and should) further restrict their own `allowed_cidrs` in the per-device UI.
        for cidr in currentLANIPv4CoarseCidrs(prefix: 16) {
            if !out.contains(cidr) {
                out.append(cidr)
            }
        }
        return out
    }

    private static func currentLANIPv4CoarseCidrs(prefix: Int) -> [String] {
        // Derive a coarse supernet CIDR from currently detected LAN IPv4 addresses without relying
        // on ifa_netmask parsing (which can vary between environments).
        //
        // For prefix=16: a.b.c.d -> a.b.0.0/16
        let p = max(0, min(32, prefix))
        guard p == 16 else { return [] }

        func parseIPv4(_ s: String) -> (Int, Int, Int, Int)? {
            let parts = s.split(separator: ".")
            if parts.count != 4 { return nil }
            let nums = parts.compactMap { Int($0) }
            if nums.count != 4 { return nil }
            for n in nums {
                if n < 0 || n > 255 { return nil }
            }
            return (nums[0], nums[1], nums[2], nums[3])
        }

        func isPrivate(_ a: Int, _ b: Int) -> Bool {
            if a == 10 { return true }
            if a == 172, b >= 16, b <= 31 { return true }
            if a == 192, b == 168 { return true }
            return false
        }

        var out: [String] = []
        var seen: Set<String> = []
        for row in currentLANAddresses() {
            guard let idx = row.firstIndex(of: ":") else { continue }
            let ip = row[row.index(after: idx)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let (a, b, _, _) = parseIPv4(String(ip)) else { continue }
            if a == 127 { continue }
            if a == 169, b == 254 { continue } // link-local
            if isPrivate(a, b) { continue } // already covered by the "private" rule

            let cidr = "\(a).\(b).0.0/16"
            if seen.contains(cidr) { continue }
            seen.insert(cidr)
            out.append(cidr)
        }
        return out
    }

    private static func currentLANIPv4Cidrs(maxBroadPrefix: Int) -> [String] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return []
        }
        defer {
            freeifaddrs(ifaddr)
        }

        func ipv4HostOrder(_ sa: UnsafeMutablePointer<sockaddr>) -> UInt32? {
            let fam = sa.pointee.sa_family
            guard fam == UInt8(AF_INET) else { return nil }
            let sin = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            return UInt32(bigEndian: sin.sin_addr.s_addr)
        }

        func ipv4String(hostOrder: UInt32) -> String? {
            var addr = in_addr(s_addr: hostOrder.bigEndian)
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buf)
        }

        func prefixLength(mask: UInt32) -> Int? {
            if mask == 0 { return nil }
            var bits = 0
            var m = mask
            while (m & 0x8000_0000) != 0 {
                bits += 1
                m <<= 1
                if bits >= 32 { break }
            }
            if bits <= 0 { return nil }
            let reconstructed: UInt32 = {
                if bits >= 32 { return 0xffff_ffff }
                let allOnes: UInt32 = 0xffff_ffff
                return allOnes << (32 - bits)
            }()
            return reconstructed == mask ? bits : nil
        }

        var rows: [(ifname: String, cidr: String)] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }

            let flags = Int32(p.pointee.ifa_flags)
            if (flags & IFF_UP) == 0 { continue }
            if (flags & IFF_LOOPBACK) != 0 { continue }

            guard let addr = p.pointee.ifa_addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard let netmask = p.pointee.ifa_netmask, netmask.pointee.sa_family == UInt8(AF_INET) else { continue }

            guard let ipH = ipv4HostOrder(addr) else { continue }
            guard let maskH0 = ipv4HostOrder(netmask) else { continue }

            // Skip loopback/link-local and unset addresses.
            if (ipH & 0xff00_0000) == 0x7f00_0000 { continue } // 127.0.0.0/8
            if (ipH & 0xffff_0000) == 0xa9fe_0000 { continue } // 169.254.0.0/16
            if ipH == 0 { continue }

            guard let rawPrefix = prefixLength(mask: maskH0) else { continue }
            let minPrefix = max(0, min(32, maxBroadPrefix))
            let clampedPrefix = max(minPrefix, min(32, rawPrefix))
            let maskH: UInt32 = {
                if clampedPrefix >= 32 { return 0xffff_ffff }
                let allOnes: UInt32 = 0xffff_ffff
                return allOnes << (32 - clampedPrefix)
            }()
            let netH = ipH & maskH
            guard let netS = ipv4String(hostOrder: netH) else { continue }

            let ifname = String(cString: p.pointee.ifa_name)
            rows.append((ifname: ifname, cidr: "\(netS)/\(clampedPrefix)"))
        }

        // Sort so en0/en1 are near the top (matches currentLANAddresses()).
        rows.sort { a, b in
            let pa = "\(a.ifname): \(a.cidr)".lowercased()
            let pb = "\(b.ifname): \(b.cidr)".lowercased()
            if pa.hasPrefix("en0:") != pb.hasPrefix("en0:") {
                return pa.hasPrefix("en0:")
            }
            return pa < pb
        }

        // De-dup by cidr.
        var seen: Set<String> = []
        var out: [String] = []
        for r in rows {
            if seen.contains(r.cidr) { continue }
            seen.insert(r.cidr)
            out.append(r.cidr)
        }
        return out
    }
}

private enum HubGRPCClientsStore {
    private static func safeString(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func generateToken(prefix: String) -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let st = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if st != errSecSuccess {
            return prefix + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        let data = Data(bytes)
        // URL-safe base64 (no padding).
        return prefix + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func defaultCapabilities() -> [String] {
        // Safe baseline: client can list models, receive events, use Hub-side memory, and run local/offline inference.
        // Paid models + web fetch are enabled per-device in the UI.
        ["models", "events", "memory", "skills", "ai.generate.local"]
    }

    static func defaultAllowedCidrs() -> [String] {
        // Safe baseline: only allow LAN (RFC1918) and localhost access.
        // For remote mode (VPN), admins typically set this to the VPN subnet (e.g. 10.7.0.0/24).
        ["private", "loopback"]
    }

    static func defaultSnapshot(defaultToken: String) -> HubGRPCClientsSnapshot {
        let tok = safeString(defaultToken)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        let def = HubGRPCClientEntry(
            deviceId: "terminal_device",
            userId: "",
            name: "Terminal (default)",
            token: tok.isEmpty ? generateToken(prefix: "axhub_client_") : tok,
            enabled: true,
            createdAtMs: nowMs,
            capabilities: defaultCapabilities(),
            allowedCidrs: defaultAllowedCidrs()
        )
        return HubGRPCClientsSnapshot(schemaVersion: "hub_grpc_clients.v1", updatedAtMs: nowMs, clients: [def])
    }
}

@MainActor
private enum HubGRPCTokens {
    private static let clientAccount = "hub_grpc_client_token"
    private static let adminAccount = "hub_grpc_admin_token"
    private static let serviceName = "com.rel.flowhub.hub_grpc"

    // Cache in memory to avoid repeated Keychain hits (and repeated prompts) in periodic refresh loops.
    private static var cachedClientToken: String?
    private static var cachedAdminToken: String?

    private enum TokenKind {
        case client
        case admin
    }

    private struct TokensFile: Codable {
        var schemaVersion: String
        var updatedAtMs: Int64
        var clientTokenCiphertext: String?
        var adminTokenCiphertext: String?
        // Plaintext fallback (only used if encryption fails or for legacy/debug).
        var clientToken: String?
        var adminToken: String?

        init(
            schemaVersion: String = "hub_grpc_tokens.v1",
            updatedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0),
            clientTokenCiphertext: String? = nil,
            adminTokenCiphertext: String? = nil,
            clientToken: String? = nil,
            adminToken: String? = nil
        ) {
            self.schemaVersion = schemaVersion
            self.updatedAtMs = updatedAtMs
            self.clientTokenCiphertext = clientTokenCiphertext
            self.adminTokenCiphertext = adminTokenCiphertext
            self.clientToken = clientToken
            self.adminToken = adminToken
        }
    }

    private static func tokensFileURL() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent("hub_grpc_tokens.json")
    }

    private static func loadTokensFile() -> TokensFile? {
        let url = tokensFileURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TokensFile.self, from: data)
    }

    private static func saveTokensFile(_ obj: TokensFile) {
        let url = tokensFileURL()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data0 = try? enc.encode(obj),
              let s = String(data: data0, encoding: .utf8),
              let out = (s + "\n").data(using: .utf8) else {
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? out.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func readTokenFromFile(kind: TokenKind) -> String? {
        guard let obj = loadTokensFile() else { return nil }
        let cipher: String? = (kind == .client) ? obj.clientTokenCiphertext : obj.adminTokenCiphertext
        if let c = cipher,
           let dec = RemoteSecretsStore.decrypt(c) {
            let s = dec.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
        }
        let plain: String? = (kind == .client) ? obj.clientToken : obj.adminToken
        let s = (plain ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private static func persistTokenToFile(kind: TokenKind, token: String) {
        let tok = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tok.isEmpty else { return }
        var obj = loadTokensFile() ?? TokensFile()
        obj.schemaVersion = "hub_grpc_tokens.v1"
        obj.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)

        if let enc = RemoteSecretsStore.encrypt(tok) {
            if kind == .client {
                obj.clientTokenCiphertext = enc
                obj.clientToken = nil
            } else {
                obj.adminTokenCiphertext = enc
                obj.adminToken = nil
            }
        } else {
            // Encryption shouldn't fail, but keep a stable fallback so the Hub remains operable.
            if kind == .client {
                obj.clientToken = tok
            } else {
                obj.adminToken = tok
            }
        }
        saveTokensFile(obj)
    }

    static func getOrCreateClientToken() -> String {
        if let v = cachedClientToken, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return v
        }
        if let v = readTokenFromFile(kind: .client) {
            cachedClientToken = v
            return v
        }
        // Migration path: older builds stored tokens in Keychain only.
        if let v = read(account: clientAccount) {
            cachedClientToken = v
            persistTokenToFile(kind: .client, token: v)
            return v
        }

        let tok = generateToken(prefix: "axhub_client_")
        persistTokenToFile(kind: .client, token: tok)
        _ = write(account: clientAccount, value: tok) // best-effort
        cachedClientToken = tok
        return tok
    }

    static func getOrCreateAdminToken() -> String {
        if let v = cachedAdminToken, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return v
        }
        if let v = readTokenFromFile(kind: .admin) {
            cachedAdminToken = v
            return v
        }
        // Migration path: older builds stored tokens in Keychain only.
        if let v = read(account: adminAccount) {
            cachedAdminToken = v
            persistTokenToFile(kind: .admin, token: v)
            return v
        }

        let tok = generateToken(prefix: "axhub_admin_")
        persistTokenToFile(kind: .admin, token: tok)
        _ = write(account: adminAccount, value: tok) // best-effort
        cachedAdminToken = tok
        return tok
    }

    @discardableResult
    static func regenerateClientToken() -> String {
        let tok = generateToken(prefix: "axhub_client_")
        persistTokenToFile(kind: .client, token: tok)
        _ = write(account: clientAccount, value: tok)
        cachedClientToken = tok
        return tok
    }

    @discardableResult
    static func regenerateAdminToken() -> String {
        let tok = generateToken(prefix: "axhub_admin_")
        persistTokenToFile(kind: .admin, token: tok)
        _ = write(account: adminAccount, value: tok)
        cachedAdminToken = tok
        return tok
    }

    private static func generateToken(prefix: String) -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let st = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if st != errSecSuccess {
            return prefix + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        let data = Data(bytes)
        // URL-safe base64 (no padding).
        return prefix + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func read(account: String) -> String? {
        let acct = account.trimmingCharacters(in: .whitespacesAndNewlines)
        if acct.isEmpty { return nil }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: acct,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
            // Avoid repeatedly popping Keychain password dialogs.
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        if KeychainStore.hasSharedAccessGroup, let g = KeychainStore.sharedAccessGroup {
            query[kSecAttrAccessGroup as String] = g
        }

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return s.isEmpty ? nil : s
        }
        return nil
    }

    private static func write(account: String, value: String) -> Bool {
        let acct = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if acct.isEmpty || v.isEmpty { return false }

        let data = Data(v.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: acct,
            // Avoid repeatedly popping Keychain password dialogs (best-effort persistence).
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        if KeychainStore.hasSharedAccessGroup, let g = KeychainStore.sharedAccessGroup {
            query[kSecAttrAccessGroup as String] = g
        }

        let attrs: [String: Any] = [
            kSecValueData as String: data,
        ]
        let st = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if st == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            let st2 = SecItemAdd(add as CFDictionary, nil)
            return st2 == errSecSuccess
        }
        return st == errSecSuccess
    }
}
