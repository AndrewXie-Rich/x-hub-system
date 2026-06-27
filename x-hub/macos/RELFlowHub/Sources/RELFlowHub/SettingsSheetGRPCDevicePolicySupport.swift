import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    func deleteClientConfirmationMessage(_ client: HubGRPCClientEntry) -> String {
        let displayName = client.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? client.deviceId
            : client.name
        return HubUIStrings.Settings.GRPC.deleteClientConfirmation(displayName: displayName, deviceID: client.deviceId)
    }

    func grpcClientSecuritySummary(_ c: HubGRPCClientEntry) -> String {
        let caps = c.capabilities
        let cidrs = c.allowedCidrs
        let user = c.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cert = c.certSha256.trimmingCharacters(in: .whitespacesAndNewlines)

        let policyText: String = {
            if c.policyMode == .legacyGrant {
                return HubUIStrings.Settings.GRPC.DeviceList.legacyPolicyMode
            }
            guard let profile = c.approvedTrustProfile else {
                return HubUIStrings.Settings.GRPC.DeviceList.newProfileMissing
            }
            let paid = paidPolicyModeLabel(profile.paidModelPolicy.mode.rawValue)
            let web = HubUIStrings.Settings.GRPC.DeviceList.currentWebState(profile.networkPolicy.defaultWebFetchEnabled)
            let daily = HubUIStrings.Settings.GRPC.DeviceList.currentDailyBudget(profile.budgetPolicy.dailyTokenLimit)
            return HubUIStrings.Settings.GRPC.DeviceList.policyProfileSummary(paid: paid, web: web, daily: daily)
        }()
        let capsText = HubUIStrings.Settings.GRPC.DeviceList.capabilities(caps)
        let cidrText = HubUIStrings.Settings.GRPC.DeviceList.sourceIPs(cidrs)
        let certText = HubUIStrings.Settings.GRPC.DeviceList.mtlsFingerprint(cert)
        let userText = HubUIStrings.Settings.GRPC.DeviceList.user(user)
        return HubUIStrings.Settings.GRPC.DeviceList.securitySummary(
            policy: policyText,
            user: userText,
            caps: capsText,
            cidr: cidrText,
            cert: certText
        )
    }

    func grpcClientPaidPolicySummary(_ client: HubGRPCClientEntry) -> String {
        if client.policyMode == .legacyGrant {
            let paidEnabled = client.capabilities.contains { cap in
                cap.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ai.generate.paid"
            }
            return paidEnabled
                ? HubUIStrings.Settings.GRPC.DeviceList.paidRouteLegacyOn
                : HubUIStrings.Settings.GRPC.DeviceList.paidRouteLegacyOff
        }

        guard let profile = client.approvedTrustProfile else {
            return HubUIStrings.Settings.GRPC.DeviceList.paidRouteProfileMissing
        }

        switch profile.paidModelPolicy.mode {
        case .off:
            return HubUIStrings.Settings.GRPC.DeviceList.paidRouteOff
        case .allPaidModels:
            return HubUIStrings.Settings.GRPC.DeviceList.paidRouteAll
        case .customSelectedModels:
            let models = profile.paidModelPolicy.allowedModelIds
            if models.isEmpty {
                return HubUIStrings.Settings.GRPC.DeviceList.paidRouteCustomEmpty
            }
            let preview = models.prefix(3).joined(separator: ", ")
            return HubUIStrings.Settings.GRPC.DeviceList.paidRouteCustom(
                count: models.count,
                preview: preview,
                extraCount: max(0, models.count - 3)
            )
        }
    }

    struct GRPCClientNetworkAccessSnapshot {
        var clientEnabled: Bool
        var paidEnabled: Bool
        var webEnabled: Bool
        var usesPolicyProfile: Bool

        var policyGrantsNetwork: Bool {
            paidEnabled || webEnabled
        }

        var canNetwork: Bool {
            clientEnabled && policyGrantsNetwork
        }
    }

    func grpcClientNetworkAccessSnapshot(_ client: HubGRPCClientEntry) -> GRPCClientNetworkAccessSnapshot {
        if client.policyMode == .newProfile, let profile = client.approvedTrustProfile {
            return GRPCClientNetworkAccessSnapshot(
                clientEnabled: client.enabled,
                paidEnabled: profile.paidModelPolicy.mode != .off,
                webEnabled: profile.networkPolicy.defaultWebFetchEnabled,
                usesPolicyProfile: true
            )
        }
        let caps = Set(client.capabilities.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return GRPCClientNetworkAccessSnapshot(
            clientEnabled: client.enabled,
            paidEnabled: caps.contains("ai.generate.paid"),
            webEnabled: caps.contains("web.fetch"),
            usesPolicyProfile: false
        )
    }
}