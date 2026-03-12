import Foundation

enum AXProjectAutonomyMode: String, Codable, Equatable, CaseIterable {
    case manual
    case guided
    case trustedOpenClawMode = "trusted_openclaw_mode"

    var displayName: String {
        switch self {
        case .manual:
            return "Manual"
        case .guided:
            return "Guided"
        case .trustedOpenClawMode:
            return "Trusted OpenClaw Mode"
        }
    }
}

enum AXProjectAutonomyHubOverrideMode: String, Codable, Equatable, CaseIterable {
    case none
    case clampGuided = "clamp_guided"
    case clampManual = "clamp_manual"
    case killSwitch = "kill_switch"

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .clampGuided:
            return "Clamp Guided"
        case .clampManual:
            return "Clamp Manual"
        case .killSwitch:
            return "Kill Switch"
        }
    }
}

struct AXProjectAutonomyRemoteOverrideSnapshot: Equatable, Sendable {
    var projectId: String
    var overrideMode: AXProjectAutonomyHubOverrideMode
    var updatedAtMs: Int64
    var source: String
    var reason: String?
    var auditRef: String?
}

struct AXProjectAutonomyEffectivePolicy: Equatable, Sendable {
    var configuredMode: AXProjectAutonomyMode
    var effectiveMode: AXProjectAutonomyMode
    var hubOverrideMode: AXProjectAutonomyHubOverrideMode
    var localOverrideMode: AXProjectAutonomyHubOverrideMode
    var remoteOverrideMode: AXProjectAutonomyHubOverrideMode
    var remoteOverrideUpdatedAtMs: Int64
    var remoteOverrideSource: String
    var allowDeviceTools: Bool
    var allowBrowserRuntime: Bool
    var allowConnectorActions: Bool
    var allowExtensions: Bool
    var ttlSeconds: Int
    var remainingSeconds: Int
    var expired: Bool
    var killSwitchEngaged: Bool

    var allowedSurfaceLabels: [String] {
        var labels: [String] = []
        if allowDeviceTools { labels.append("device") }
        if allowBrowserRuntime { labels.append("browser") }
        if allowConnectorActions { labels.append("connector") }
        if allowExtensions { labels.append("extension") }
        return labels
    }
}

struct AXProjectResolvedAutonomyPolicyState: Equatable, Sendable {
    var projectId: String
    var remoteOverride: AXProjectAutonomyRemoteOverrideSnapshot?
    var effectivePolicy: AXProjectAutonomyEffectivePolicy
}

private struct AXProjectAutonomyPreset {
    var allowDeviceTools: Bool
    var allowBrowserRuntime: Bool
    var allowConnectorActions: Bool
    var allowExtensions: Bool
}

private func xtProjectAutonomyPreset(for mode: AXProjectAutonomyMode) -> AXProjectAutonomyPreset {
    switch mode {
    case .manual:
        return AXProjectAutonomyPreset(
            allowDeviceTools: false,
            allowBrowserRuntime: false,
            allowConnectorActions: false,
            allowExtensions: false
        )
    case .guided:
        return AXProjectAutonomyPreset(
            allowDeviceTools: false,
            allowBrowserRuntime: true,
            allowConnectorActions: false,
            allowExtensions: false
        )
    case .trustedOpenClawMode:
        return AXProjectAutonomyPreset(
            allowDeviceTools: true,
            allowBrowserRuntime: true,
            allowConnectorActions: true,
            allowExtensions: true
        )
    }
}

private func xtAutonomyOverrideRank(_ mode: AXProjectAutonomyHubOverrideMode) -> Int {
    switch mode {
    case .none:
        return 0
    case .clampGuided:
        return 1
    case .clampManual:
        return 2
    case .killSwitch:
        return 3
    }
}

private func xtResolvedAutonomyOverrideMode(
    local: AXProjectAutonomyHubOverrideMode,
    remote: AXProjectAutonomyHubOverrideMode
) -> AXProjectAutonomyHubOverrideMode {
    xtAutonomyOverrideRank(remote) > xtAutonomyOverrideRank(local) ? remote : local
}

func xtResolveProjectAutonomyPolicy(
    projectRoot: URL,
    config: AXProjectConfig
) async -> AXProjectResolvedAutonomyPolicyState {
    let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
    let remoteOverride = await HubIPCClient.requestProjectAutonomyPolicyOverride(projectId: projectId)
    return AXProjectResolvedAutonomyPolicyState(
        projectId: projectId,
        remoteOverride: remoteOverride,
        effectivePolicy: config.effectiveAutonomyPolicy(remoteOverride: remoteOverride)
    )
}

extension AXProjectConfig {
    var configuredAutonomySurfaceLabels: [String] {
        var labels: [String] = []
        if autonomyAllowBrowserRuntime { labels.append("browser") }
        if autonomyAllowDeviceTools { labels.append("device") }
        if autonomyAllowConnectorActions { labels.append("connector") }
        if autonomyAllowExtensions { labels.append("extension") }
        return labels
    }

    func settingAutonomyPolicy(
        mode: AXProjectAutonomyMode? = nil,
        allowDeviceTools: Bool? = nil,
        allowBrowserRuntime: Bool? = nil,
        allowConnectorActions: Bool? = nil,
        allowExtensions: Bool? = nil,
        ttlSeconds: Int? = nil,
        hubOverrideMode: AXProjectAutonomyHubOverrideMode? = nil,
        updatedAt: Date = Date()
    ) -> AXProjectConfig {
        var out = self

        if let mode {
            out.autonomyMode = mode
            let preset = xtProjectAutonomyPreset(for: mode)
            out.autonomyAllowDeviceTools = preset.allowDeviceTools
            out.autonomyAllowBrowserRuntime = preset.allowBrowserRuntime
            out.autonomyAllowConnectorActions = preset.allowConnectorActions
            out.autonomyAllowExtensions = preset.allowExtensions
        }
        if let allowDeviceTools {
            out.autonomyAllowDeviceTools = allowDeviceTools
        }
        if let allowBrowserRuntime {
            out.autonomyAllowBrowserRuntime = allowBrowserRuntime
        }
        if let allowConnectorActions {
            out.autonomyAllowConnectorActions = allowConnectorActions
        }
        if let allowExtensions {
            out.autonomyAllowExtensions = allowExtensions
        }
        if let ttlSeconds {
            out.autonomyTTLSeconds = max(60, ttlSeconds)
        }
        if let hubOverrideMode {
            out.autonomyHubOverrideMode = hubOverrideMode
        }

        let requestedChange = mode != nil
            || allowDeviceTools != nil
            || allowBrowserRuntime != nil
            || allowConnectorActions != nil
            || allowExtensions != nil
            || ttlSeconds != nil
            || hubOverrideMode != nil
        if requestedChange {
            out.autonomyUpdatedAtMs = max(0, Int64((updatedAt.timeIntervalSince1970 * 1000.0).rounded()))
        }

        return out.normalizedAutomationState()
    }

    var autonomyUpdatedAtDate: Date? {
        guard autonomyUpdatedAtMs > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(autonomyUpdatedAtMs) / 1000.0)
    }

    func effectiveAutonomyPolicy(
        now: Date = Date(),
        remoteOverride: AXProjectAutonomyRemoteOverrideSnapshot? = nil
    ) -> AXProjectAutonomyEffectivePolicy {
        let ttlSeconds = max(60, autonomyTTLSeconds)
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let remoteOverrideMode = remoteOverride?.overrideMode ?? .none
        let resolvedOverrideMode = xtResolvedAutonomyOverrideMode(
            local: autonomyHubOverrideMode,
            remote: remoteOverrideMode
        )
        let killSwitchEngaged = resolvedOverrideMode == .killSwitch

        let expired: Bool
        let remainingSeconds: Int
        if autonomyMode == .manual {
            expired = false
            remainingSeconds = 0
        } else if autonomyUpdatedAtMs <= 0 {
            expired = true
            remainingSeconds = 0
        } else {
            let expiresAtMs = autonomyUpdatedAtMs + Int64(ttlSeconds) * 1000
            expired = nowMs >= expiresAtMs
            remainingSeconds = expired ? 0 : max(0, Int((expiresAtMs - nowMs + 999) / 1000))
        }

        var effectiveMode = autonomyMode
        if killSwitchEngaged || expired {
            effectiveMode = .manual
        } else {
            switch resolvedOverrideMode {
            case .none:
                break
            case .clampGuided:
                if effectiveMode == .trustedOpenClawMode {
                    effectiveMode = .guided
                }
            case .clampManual:
                effectiveMode = .manual
            case .killSwitch:
                effectiveMode = .manual
            }
        }

        var allowDeviceTools = autonomyAllowDeviceTools
        var allowBrowserRuntime = autonomyAllowBrowserRuntime
        var allowConnectorActions = autonomyAllowConnectorActions
        var allowExtensions = autonomyAllowExtensions

        switch effectiveMode {
        case .manual:
            allowDeviceTools = false
            allowBrowserRuntime = false
            allowConnectorActions = false
            allowExtensions = false
        case .guided:
            allowDeviceTools = false
            allowConnectorActions = false
            allowExtensions = false
        case .trustedOpenClawMode:
            break
        }

        return AXProjectAutonomyEffectivePolicy(
            configuredMode: autonomyMode,
            effectiveMode: effectiveMode,
            hubOverrideMode: resolvedOverrideMode,
            localOverrideMode: autonomyHubOverrideMode,
            remoteOverrideMode: remoteOverrideMode,
            remoteOverrideUpdatedAtMs: max(0, remoteOverride?.updatedAtMs ?? 0),
            remoteOverrideSource: remoteOverride?.source.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            allowDeviceTools: allowDeviceTools,
            allowBrowserRuntime: allowBrowserRuntime,
            allowConnectorActions: allowConnectorActions,
            allowExtensions: allowExtensions,
            ttlSeconds: ttlSeconds,
            remainingSeconds: remainingSeconds,
            expired: expired,
            killSwitchEngaged: killSwitchEngaged
        )
    }
}
