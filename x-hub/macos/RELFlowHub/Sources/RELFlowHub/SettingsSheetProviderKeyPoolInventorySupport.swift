import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    func providerKeyPoolTitle(_ pool: ProviderKeyPoolSnapshot) -> String {
        if pool.providerHost.isEmpty {
            return pool.supplierDisplayName
        }
        return "\(pool.supplierDisplayName) · \(pool.providerHost)"
    }

    func providerKeyPoolDetail(_ pool: ProviderKeyPoolSnapshot) -> String {
        HubUIStrings.Settings.RemoteModels.sectionSummary([
            pool.poolID,
            pool.wireAPI == "default" ? "" : pool.wireAPI,
            pool.lastRefreshAtMs > 0 ? "上次刷新 \(formattedProviderKeyImportSourceTime(pool.lastRefreshAtMs))" : ""
        ])
    }

    func providerKeyPoolQuotaSummary(_ pool: ProviderKeyPoolSnapshot) -> String {
        HubUIStrings.Settings.RemoteModels.sectionSummary([
            HubUIStrings.Settings.ProviderKeys.dailyUsageText(
                used: pool.totalDailyTokensUsed,
                cap: pool.totalDailyTokenCap
            ),
            pool.totalTokensUsed > 0
                ? "累计 \(HubUIStrings.Settings.ProviderKeys.tokenCount(pool.totalTokensUsed))"
                : ""
        ])
    }

    @ViewBuilder
    func providerKeyPoolIssueSummaryView(_ pool: ProviderKeyPoolSnapshot) -> some View {
        let summary = pool.issueSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = pool.issueDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        let isExpanded = expandedProviderKeyPoolIssueIDs.contains(pool.id)
        let tint = providerKeyPoolStateColor(pool.state)

        if !summary.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(tint)
                        .fixedSize(horizontal: false, vertical: true)

                    if !detail.isEmpty {
                        Button {
                            if isExpanded {
                                expandedProviderKeyPoolIssueIDs.remove(pool.id)
                            } else {
                                expandedProviderKeyPoolIssueIDs.insert(pool.id)
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

    func providerKeyPoolRetrySummary(_ pool: ProviderKeyPoolSnapshot) -> String {
        if let retryText = pool.members
            .map({ $0.account.errorState.retryAtText.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return HubUIStrings.Settings.ProviderKeys.nextRetry(retryText)
        }
        guard pool.earliestRetryAtMs > 0 else {
            return HubUIStrings.Settings.ProviderKeys.nextRetryUnknown
        }
        return HubUIStrings.Settings.ProviderKeys.nextRetry(
            formattedProviderKeyImportSourceTime(pool.earliestRetryAtMs)
        )
    }

    func providerKeyPoolStateColor(_ state: String) -> Color {
        switch state {
        case "ready":
            return .green
        case "cooldown":
            return .orange
        case "blocked":
            return .red
        case "disabled":
            return .gray
        case "mixed":
            return .yellow
        default:
            return .secondary
        }
    }

    func providerKeyPoolStateText(_ state: String) -> String {
        switch state {
        case "ready":
            return HubUIStrings.Settings.ProviderKeys.ready
        case "cooldown":
            return HubUIStrings.Settings.ProviderKeys.cooldown
        case "blocked":
            return HubUIStrings.Settings.ProviderKeys.blocked
        case "disabled":
            return HubUIStrings.Settings.ProviderKeys.disabled
        case "stale":
            return HubUIStrings.Settings.ProviderKeys.stale
        case "degraded":
            return HubUIStrings.Settings.ProviderKeys.degraded
        case "mixed":
            return HubUIStrings.Settings.ProviderKeys.mixed
        default:
            return state
        }
    }

    func providerKeyMemberStateColor(_ member: ProviderKeyPoolMemberState) -> Color {
        switch member.state {
        case "ready":
            return .green
        case "degraded":
            return .yellow
        case "cooldown":
            return .orange
        case "blocked":
            return .red
        case "stale":
            return .red.opacity(0.75)
        case "disabled":
            return .gray
        default:
            return .secondary
        }
    }

    func providerKeyMemberTitle(_ member: ProviderKeyPoolMemberState) -> String {
        let account = member.account
        return account.email.isEmpty ? account.apiKeyRedacted : account.email
    }

    func providerKeyMemberSourceText(_ account: ProviderKeyAccount) -> String {
        let sourceRef = account.sourceRef.isEmpty ? "" : URL(fileURLWithPath: account.sourceRef).lastPathComponent
        return HubUIStrings.Settings.RemoteModels.sectionSummary([
            !account.accountId.isEmpty ? "id \(account.accountId)" : "",
            !account.sourceType.isEmpty ? account.sourceType : "",
            !sourceRef.isEmpty ? sourceRef : "",
            !account.runtimeAuthIndex.isEmpty ? "runtime \(String(account.runtimeAuthIndex.prefix(10)))" : "",
            account.authType == "oauth" && account.expiresAtMs > 0
                ? "过期 \(formattedProviderKeyImportSourceTime(account.expiresAtMs))"
                : ""
        ])
    }
}
