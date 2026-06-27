import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func grpcClientQuickActionHint(_ snapshot: GRPCClientNetworkAccessSnapshot) -> String {
        if !snapshot.clientEnabled {
            return HubUIStrings.Settings.GRPC.DeviceList.quickActionEnableFirst
        }
        if snapshot.policyGrantsNetwork {
            return HubUIStrings.Settings.GRPC.DeviceList.quickActionCutOffOnly
        }
        return HubUIStrings.Settings.GRPC.DeviceList.quickActionRestoreWebOnly
    }

    @ViewBuilder
    func grpcClientNetworkPill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.monospaced())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    func grpcRemoteHealthColor(_ state: HubRemoteAccessHealthSummary.State) -> Color {
        switch state {
        case .ready:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    func grpcRemoteRouteColor(_ state: HubRemoteAccessRouteProbeSnapshot.State) -> Color {
        switch state {
        case .idle, .skipped:
            return .secondary
        case .resolving:
            return .blue
        case .resolved:
            return .green
        case .failed:
            return .red
        }
    }

    func grpcCutOffNetworkAccess(_ client: HubGRPCClientEntry) {
        var updated = client
        if client.policyMode == .newProfile, var profile = client.approvedTrustProfile {
            profile.paidModelPolicy = HubPairedTerminalPaidModelPolicy(mode: .off, allowedModelIds: [])
            profile.networkPolicy = HubPairedTerminalNetworkPolicy(defaultWebFetchEnabled: false)
            profile.capabilities = HubGRPCClientEntry.derivedCapabilities(
                requestedCapabilities: profile.capabilities,
                paidModelSelectionMode: .off,
                defaultWebFetchEnabled: false
            )
            updated.approvedTrustProfile = profile
            updated.capabilities = profile.capabilities
        } else {
            updated.capabilities = client.capabilities.filter {
                let lowered = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return lowered != "ai.generate.paid" && lowered != "web.fetch"
            }
        }
        grpc.upsertClient(updated)
    }

    func grpcSetWebFetchEnabled(_ client: HubGRPCClientEntry, enabled: Bool) {
        var updated = client
        if client.policyMode == .newProfile, var profile = client.approvedTrustProfile {
            profile.networkPolicy = HubPairedTerminalNetworkPolicy(defaultWebFetchEnabled: enabled)
            profile.capabilities = HubGRPCClientEntry.derivedCapabilities(
                requestedCapabilities: profile.capabilities,
                paidModelSelectionMode: profile.paidModelPolicy.mode,
                defaultWebFetchEnabled: enabled
            )
            updated.approvedTrustProfile = profile
            updated.capabilities = profile.capabilities
        } else {
            var caps = client.capabilities.filter {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "web.fetch"
            }
            if enabled {
                caps.append("web.fetch")
            }
            updated.capabilities = HubGRPCClientEntry.normalizedStrings(caps)
        }
        grpc.upsertClient(updated)
    }

    func grpcSetDailyBudget(
        _ client: HubGRPCClientEntry,
        dailyTokenLimit: Int
    ) {
        guard client.policyMode == .newProfile, var profile = client.approvedTrustProfile else {
            remoteQuotaActionText = ""
            remoteQuotaErrorText = "预算设定当前只支持已启用新策略档案的 XT。"
            return
        }

        let currentLimit = max(1, profile.budgetPolicy.dailyTokenLimit)
        let updatedLimit = max(1, dailyTokenLimit)
        guard updatedLimit != currentLimit else { return }

        profile.budgetPolicy = HubPairedTerminalBudgetPolicy(
            dailyTokenLimit: updatedLimit,
            singleRequestTokenLimit: max(1, profile.budgetPolicy.singleRequestTokenLimit)
        )

        var updated = client
        updated.approvedTrustProfile = profile
        grpc.upsertClient(updated)

        remoteQuotaErrorText = ""
        remoteQuotaActionText = "\(client.name.isEmpty ? client.deviceId : client.name) 日预算已调整为 \(terminalAccessIntText(Int64(updatedLimit))) tokens。"
    }

    func grpcAdjustDailyBudget(
        _ client: HubGRPCClientEntry,
        delta: Int
    ) {
        let currentLimit = max(1, client.approvedTrustProfile?.budgetPolicy.dailyTokenLimit ?? 1)
        grpcSetDailyBudget(client, dailyTokenLimit: currentLimit + delta)
    }
}
