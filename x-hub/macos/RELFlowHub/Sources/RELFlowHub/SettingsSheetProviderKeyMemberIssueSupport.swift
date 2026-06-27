import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    @ViewBuilder
    func providerKeyMemberIssueSummaryView(_ member: ProviderKeyPoolMemberState) -> some View {
        let summary = member.reasonMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = member.detailMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let isExpanded = expandedProviderKeyMemberIssueIDs.contains(member.id)
        let tint = providerKeyMemberStateColor(member)

        if !summary.isEmpty && member.state != "ready" {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(tint)
                        .fixedSize(horizontal: false, vertical: true)

                    if !detail.isEmpty {
                        Button {
                            if isExpanded {
                                expandedProviderKeyMemberIssueIDs.remove(member.id)
                            } else {
                                expandedProviderKeyMemberIssueIDs.insert(member.id)
                            }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up.circle.fill" : "info.circle")
                                .imageScale(.small)
                                .foregroundStyle(tint)
                        }
                        .buttonStyle(.plain)
                        .help(isExpanded ? "收起详细错误" : "展开详细错误")
                    }
                }

                if isExpanded && !detail.isEmpty {
                    Text(detail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    func providerKeyMemberRetryText(_ member: ProviderKeyPoolMemberState) -> String? {
        let explicitText = member.account.errorState.retryAtText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitText.isEmpty {
            return HubUIStrings.Settings.ProviderKeys.nextRetry(explicitText)
        }
        guard member.nextRetryAtMs > 0 else { return nil }
        return HubUIStrings.Settings.ProviderKeys.nextRetry(
            formattedProviderKeyImportSourceTime(member.nextRetryAtMs)
        )
    }

    func accountStatusColor(_ account: ProviderKeyAccount) -> Color {
        if !account.enabled { return .gray }
        switch account.errorState.status {
        case "healthy": return .green
        case "degraded": return .yellow
        case "rate_limited": return .orange
        case "auth_failed": return .red
        case "disabled": return .gray
        default: return .secondary
        }
    }

    func errorStateDescription(_ state: ProviderKeyErrorState) -> String {
        switch state.status {
        case "healthy": return HubUIStrings.Settings.ProviderKeys.healthy
        case "degraded": return HubUIStrings.Settings.ProviderKeys.degraded
        case "rate_limited":
            if state.lastErrorCode == "429" {
                return HubUIStrings.Settings.ProviderKeys.rateLimited
            }
            return "\(HubUIStrings.Settings.ProviderKeys.rateLimited) (\(state.lastErrorCode))"
        case "auth_failed":
            return "\(HubUIStrings.Settings.ProviderKeys.authFailed) (\(state.lastErrorCode))"
        case "disabled":
            return HubUIStrings.Settings.ProviderKeys.disabled
        default: return state.status
        }
    }
}
