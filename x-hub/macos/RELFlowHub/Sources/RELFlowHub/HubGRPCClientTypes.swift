import Foundation
import AppKit
import CoreImage
import Darwin
import LocalAuthentication
import Security
import RELFlowHubCore

enum HubGRPCClientPolicyMode: String, Codable, CaseIterable, Equatable, Sendable {
    case newProfile = "new_profile"
    case legacyGrant = "legacy_grant"

    var title: String {
        switch self {
        case .newProfile:
            return HubUIStrings.Settings.GRPC.Runtime.clientPolicyProfile
        case .legacyGrant:
            return HubUIStrings.Settings.GRPC.Runtime.clientLegacyGrant
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
            return HubUIStrings.Settings.GRPC.Runtime.paidModelOff
        case .allPaidModels:
            return HubUIStrings.Settings.GRPC.Runtime.paidModelAll
        case .customSelectedModels:
            return HubUIStrings.Settings.GRPC.Runtime.paidModelCustomSelected
        }
    }
}

enum HubTrustedAutomationMode: String, Codable, CaseIterable, Equatable, Sendable {
    case standard = "standard"
    case trustedAutomation = "trusted_automation"
}

enum HubTrustedAutomationState: String, Codable, CaseIterable, Equatable, Sendable {
    case off = "off"
    case armed = "armed"
    case active = "active"
    case blocked = "blocked"
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
    var mode: HubTrustedAutomationMode
    var state: HubTrustedAutomationState
    var capabilities: [String]
    var allowedProjectIds: [String]
    var allowedWorkspaceRoots: [String]
    var xtBindingRequired: Bool
    var autoGrantProfile: String
    var devicePermissionOwnerRef: String
    var paidModelPolicy: HubPairedTerminalPaidModelPolicy
    var networkPolicy: HubPairedTerminalNetworkPolicy
    var budgetPolicy: HubPairedTerminalBudgetPolicy
    var auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case deviceId = "device_id"
        case deviceName = "device_name"
        case trustMode = "trust_mode"
        case mode
        case state
        case capabilities
        case allowedProjectIds = "allowed_project_ids"
        case allowedWorkspaceRoots = "allowed_workspace_roots"
        case xtBindingRequired = "xt_binding_required"
        case autoGrantProfile = "auto_grant_profile"
        case devicePermissionOwnerRef = "device_permission_owner_ref"
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
    var appId: String
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
        case appId = "app_id"
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
        appId: String = "",
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
        self.appId = appId
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
        appId = (try? c.decode(String.self, forKey: .appId)) ?? ""
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
        try c.encode(appId, forKey: .appId)
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
        auditRef: String,
        mode: HubTrustedAutomationMode = .standard,
        state: HubTrustedAutomationState = .off,
        allowedProjectIds: [String] = [],
        allowedWorkspaceRoots: [String] = [],
        xtBindingRequired: Bool = false,
        autoGrantProfile: String = "",
        devicePermissionOwnerRef: String = ""
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
            mode: mode,
            state: state,
            capabilities: capabilities,
            allowedProjectIds: normalizedStrings(allowedProjectIds),
            allowedWorkspaceRoots: normalizedStrings(allowedWorkspaceRoots),
            xtBindingRequired: xtBindingRequired,
            autoGrantProfile: normalizedStrings([autoGrantProfile]).first ?? "",
            devicePermissionOwnerRef: normalizedStrings([devicePermissionOwnerRef]).first ?? "",
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

func decodeNullTerminatedCString(_ buffer: [CChar]) -> String {
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}

struct HubLocalRuntimeWatchdogEvaluation: Equatable {
    let nextFailureCount: Int
    let withinStartupGrace: Bool
    let inRestartCooldown: Bool
    let shouldRestart: Bool
}

enum HubLocalRuntimeWatchdog {
    static let startupGraceSec: Double = 12.0
    static let unhealthyThreshold: Int = 3
    static let restartCooldownSec: Double = 45.0

    static func evaluate(
        now: Double,
        launchAt: Double,
        consecutiveFailureCount: Int,
        lastRestartAt: Double,
        pairingHealthy: Bool
    ) -> HubLocalRuntimeWatchdogEvaluation {
        let withinStartupGrace = isWithinStartupGrace(now: now, launchAt: launchAt)
        let inRestartCooldown = isInRestartCooldown(now: now, lastRestartAt: lastRestartAt)

        if pairingHealthy || withinStartupGrace {
            return HubLocalRuntimeWatchdogEvaluation(
                nextFailureCount: 0,
                withinStartupGrace: withinStartupGrace,
                inRestartCooldown: inRestartCooldown,
                shouldRestart: false
            )
        }

        let nextFailureCount = min(
            unhealthyThreshold,
            max(0, consecutiveFailureCount) + 1
        )
        let shouldRestart = nextFailureCount >= unhealthyThreshold && !inRestartCooldown
        return HubLocalRuntimeWatchdogEvaluation(
            nextFailureCount: nextFailureCount,
            withinStartupGrace: false,
            inRestartCooldown: inRestartCooldown,
            shouldRestart: shouldRestart
        )
    }

    static func isWithinStartupGrace(now: Double, launchAt: Double) -> Bool {
        guard launchAt > 0 else { return false }
        return (now - launchAt) < startupGraceSec
    }

    static func isInRestartCooldown(now: Double, lastRestartAt: Double) -> Bool {
        guard lastRestartAt > 0 else { return false }
        return (now - lastRestartAt) < restartCooldownSec
    }
}
