import Foundation
import RELFlowHubCore

enum HubSettingsSectionAnchorID {
    static let providerKeysSection = "provider_keys_section"
    static let providerKeyUserLedger = "provider_key_user_ledger"
    static let providerKeyConsumerLedger = "provider_key_consumer_ledger"
    static let terminalAccessSection = "terminal_access_section"
    static let grpcServerSection = "grpc_server_section"
    static let remoteAccessSection = "remote_access_section"
    static let rustHubKernelSection = "rust_hub_kernel_section"
    static let runtimeMonitorSection = "runtime_monitor_section"
    static let diagnosticsLaunchSection = "diagnostics_launch_section"
    static let doctorSection = "doctor_section"
    static let networkPoliciesSection = "network_policies_section"
    static let networkingSection = "networking_section"
}

enum HubSettingsNavigationExpansion: Equatable {
    case diagnosticsLaunch
    case diagnosticsNetwork
    case diagnosticsAdvanced
    case modelCatalogDetails
    case providerQuotaOperations
    case runtimeRouting
    case integrationsAux
    case terminalAccessIssue
}

enum HubStatusRepairNavigationSupport {
    static func target(
        snapshot: HubLaunchStatusSnapshot?,
        appInstallWarning: Bool = false,
        needsAccessibilityPermission: Bool = false
    ) -> HubSettingsNavigationTarget {
        if let rootCause = snapshot?.rootCause {
            return target(rootCause: rootCause)
        }

        if let blockedTarget = target(blockedCapabilities: snapshot?.degraded.blockedCapabilities ?? []) {
            return blockedTarget
        }

        if needsAccessibilityPermission || appInstallWarning {
            return doctorTarget()
        }

        guard let snapshot else {
            return rustKernelTarget()
        }

        switch snapshot.state {
        case .bootStart, .envValidate:
            return rustKernelTarget()
        case .startGRPCServer, .waitGRPCReady:
            return grpcServerTarget()
        case .startBridge, .waitBridgeReady:
            return networkTarget(anchorID: HubSettingsSectionAnchorID.networkingSection)
        case .startRuntime, .waitRuntimeReady:
            return runtimeMonitorTarget()
        case .degradedServing where snapshot.degraded.isDegraded:
            return diagnosticsLaunchTarget()
        case .failed:
            return diagnosticsLaunchTarget()
        case .serving, .degradedServing:
            return diagnosticsLaunchTarget()
        }
    }

    private static func target(rootCause: HubLaunchRootCause) -> HubSettingsNavigationTarget {
        let code = rootCause.errorCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        switch code {
        case "XHUB_GRPC_PORT_IN_USE",
             "XHUB_GRPC_NODE_MISSING",
             "XHUB_GRPC_SERVER_EXITED":
            return grpcServerTarget()
        case "XHUB_BRIDGE_UNAVAILABLE":
            return networkTarget(anchorID: HubSettingsSectionAnchorID.networkingSection)
        case "XHUB_RT_PYTHON_INVALID",
             "XHUB_RT_IMPORT_ERROR",
             "XHUB_RT_LOCK_BUSY",
             "XHUB_RT_NOT_READY",
             "XHUB_RT_STATUS_STALE":
            return runtimeMonitorTarget()
        case "XHUB_RT_SCRIPT_MISSING":
            return doctorTarget()
        case "XHUB_DB_OPEN_FAILED",
             "XHUB_DB_INTEGRITY_FAILED":
            return diagnosticsLaunchTarget()
        case "XHUB_ENV_INVALID":
            return doctorTarget()
        default:
            switch rootCause.component {
            case .grpc:
                return grpcServerTarget()
            case .bridge:
                return networkTarget(anchorID: HubSettingsSectionAnchorID.networkingSection)
            case .runtime:
                return runtimeMonitorTarget()
            case .env:
                return doctorTarget()
            case .db:
                return diagnosticsLaunchTarget()
            }
        }
    }

    private static func target(blockedCapabilities: [String]) -> HubSettingsNavigationTarget? {
        let normalized = blockedCapabilities
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else { return nil }

        if normalized.contains(where: isLocalModelCapability) {
            return runtimeMonitorTarget()
        }
        if normalized.contains(where: isPaidModelCapability) {
            return .settingsPage(
                page: .models,
                anchorID: HubSettingsSectionAnchorID.providerKeysSection,
                expansion: .providerQuotaOperations
            )
        }
        if normalized.contains(where: isNetworkCapability) {
            return networkTarget(anchorID: HubSettingsSectionAnchorID.networkPoliciesSection)
        }
        if normalized.contains(where: isTerminalAccessCapability) {
            return .settingsPage(
                page: .access,
                anchorID: HubSettingsSectionAnchorID.terminalAccessSection,
                expansion: .terminalAccessIssue
            )
        }
        if normalized.contains(where: isRemoteAccessCapability) {
            return .settingsPage(
                page: .access,
                anchorID: HubSettingsSectionAnchorID.remoteAccessSection,
                expansion: nil
            )
        }
        if normalized.contains(where: isIntegrationCapability) {
            return .settingsPage(page: .integrations, anchorID: nil, expansion: .integrationsAux)
        }

        return diagnosticsLaunchTarget()
    }

    private static func isLocalModelCapability(_ capability: String) -> Bool {
        capability == "ai.generate.local"
            || capability == "ai.embed.local"
            || capability == "ai.audio.local"
            || capability == "ai.vision.local"
            || capability.contains(".local")
            || capability.contains("local_model")
            || capability.contains("runtime")
    }

    private static func isPaidModelCapability(_ capability: String) -> Bool {
        capability == "ai.generate.paid"
            || capability.contains("paid")
            || capability.contains("provider")
            || capability.contains("quota")
            || capability.contains("rate_limit")
            || capability.contains("api_key")
            || capability.contains("oauth")
    }

    private static func isNetworkCapability(_ capability: String) -> Bool {
        capability == "web.fetch"
            || capability.contains("network")
            || capability.contains("internet")
            || capability.contains("http")
            || capability.contains("url")
    }

    private static func isTerminalAccessCapability(_ capability: String) -> Bool {
        capability.contains("terminal")
            || capability.contains("openai_compatible")
            || capability.contains("access_key")
    }

    private static func isRemoteAccessCapability(_ capability: String) -> Bool {
        capability.contains("remote")
            || capability.contains("domain")
            || capability.contains("tailscale")
            || capability.contains("funnel")
    }

    private static func isIntegrationCapability(_ capability: String) -> Bool {
        capability.contains("skill")
            || capability.contains("operator")
            || capability.contains("integration")
            || capability.contains("calendar")
            || capability.contains("slack")
            || capability.contains("messages")
    }

    private static func rustKernelTarget() -> HubSettingsNavigationTarget {
        .settingsPage(
            page: .runtime,
            anchorID: HubSettingsSectionAnchorID.rustHubKernelSection,
            expansion: nil
        )
    }

    private static func runtimeMonitorTarget() -> HubSettingsNavigationTarget {
        .settingsPage(
            page: .runtime,
            anchorID: HubSettingsSectionAnchorID.runtimeMonitorSection,
            expansion: nil
        )
    }

    private static func grpcServerTarget() -> HubSettingsNavigationTarget {
        .settingsPage(
            page: .access,
            anchorID: HubSettingsSectionAnchorID.grpcServerSection,
            expansion: nil
        )
    }

    private static func networkTarget(anchorID: String) -> HubSettingsNavigationTarget {
        .settingsPage(page: .diagnostics, anchorID: anchorID, expansion: .diagnosticsNetwork)
    }

    private static func doctorTarget() -> HubSettingsNavigationTarget {
        .settingsPage(
            page: .diagnostics,
            anchorID: HubSettingsSectionAnchorID.doctorSection,
            expansion: nil
        )
    }

    private static func diagnosticsLaunchTarget() -> HubSettingsNavigationTarget {
        .settingsPage(
            page: .diagnostics,
            anchorID: HubSettingsSectionAnchorID.diagnosticsLaunchSection,
            expansion: .diagnosticsLaunch
        )
    }
}
