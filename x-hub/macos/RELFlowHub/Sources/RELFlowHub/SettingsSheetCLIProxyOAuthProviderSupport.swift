import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func cliproxyOAuthProviderTint(
        _ provider: CLIProxyOAuthSourceSupport.OAuthProvider
    ) -> Color {
        switch provider {
        case .claude:
            return .orange
        case .codex:
            return .blue
        case .gemini:
            return .mint
        case .antigravity:
            return .purple
        case .kimi:
            return .red
        }
    }

    func cliproxyOAuthActionButton(
        title: String,
        systemName: String,
        tint: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            settingsActionChipLabel(
                title: title,
                systemName: systemName,
                tint: tint,
                disabled: disabled
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    func cliproxyOAuthProviderOverviewCard(
        _ summary: CLIProxyOAuthProviderInventorySummary
    ) -> some View {
        let tint = cliproxyOAuthProviderSummaryTint(summary)
        let readyFraction = summary.totalCount > 0
            ? CGFloat(summary.readyCount) / CGFloat(summary.totalCount)
            : 0

        return Button {
            focusProviderKeyVendor(
                cliproxyOAuthProviderVendorKey(summary.providerKey),
                displayName: summary.displayName
            )
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(summary.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("\(summary.readyCount)/\(summary.totalCount)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(tint)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(tint.opacity(0.14))

                        Capsule()
                            .fill(tint.opacity(0.78))
                            .frame(
                                width: readyFraction > 0
                                    ? max(12, proxy.size.width * readyFraction)
                                    : 0
                            )
                    }
                }
                .frame(height: 7)

                Text(cliproxyOAuthProviderSummaryText(summary))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(12)
        .background(tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .buttonStyle(.plain)
    }

    func cliproxyOAuthProviderSummaryTint(
        _ summary: CLIProxyOAuthProviderInventorySummary
    ) -> Color {
        if summary.blockedCount > 0 {
            return .red
        }
        if summary.coolingCount > 0 {
            return .orange
        }
        if summary.readyCount > 0 {
            return cliproxyOAuthProviderTintKey(summary.providerKey)
        }
        if summary.disabledCount == summary.totalCount {
            return .gray
        }
        return .secondary
    }

    func cliproxyOAuthProviderSummaryText(
        _ summary: CLIProxyOAuthProviderInventorySummary
    ) -> String {
        HubUIStrings.Settings.RemoteModels.sectionSummary([
            summary.readyCount > 0 ? "可用 \(summary.readyCount)" : "",
            summary.coolingCount > 0 ? "冷却 \(summary.coolingCount)" : "",
            summary.blockedCount > 0 ? "阻断 \(summary.blockedCount)" : "",
            summary.refreshingCount > 0 ? "刷新 \(summary.refreshingCount)" : "",
            summary.waitingCount > 0 ? "等待 \(summary.waitingCount)" : "",
            summary.disabledCount > 0 ? "停用 \(summary.disabledCount)" : ""
        ])
    }

    func cliproxyOAuthInventoryState(
        _ auth: CLIProxyOAuthSourceSupport.RemoteAuthFile
    ) -> CLIProxyOAuthInventoryState {
        if auth.disabled {
            return .disabled
        }
        if auth.quota.exceeded || auth.nextRetryAtMs > 0 {
            return .cooling
        }
        if auth.unavailable {
            return .blocked
        }

        let normalized = auth.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "active", "ok", "ready":
            return .ready
        case "refreshing":
            return .refreshing
        case "pending", "wait":
            return .waiting
        case "error", "blocked", "failed":
            return .blocked
        default:
            if normalized.contains("refresh") {
                return .refreshing
            }
            if normalized.contains("wait") || normalized.contains("pending") {
                return .waiting
            }
            if normalized.contains("error")
                || normalized.contains("block")
                || normalized.contains("fail") {
                return .blocked
            }
            return normalized.isEmpty ? .waiting : .blocked
        }
    }

    func cliproxyOAuthCanonicalProviderKey(_ rawProvider: String) -> String {
        let normalized = rawProvider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "anthropic", "claude":
            return "claude"
        case "chatgpt", "openai", "codex", "openai_compatible":
            return "codex"
        case "gemini", "gemini-cli", "google":
            return "gemini"
        case "antigravity":
            return "antigravity"
        case "kimi", "moonshot":
            return "kimi"
        default:
            return normalized.isEmpty ? "unknown" : normalized
        }
    }

    func cliproxyOAuthProviderVendorKey(_ providerKey: String) -> String {
        switch cliproxyOAuthCanonicalProviderKey(providerKey) {
        case "codex":
            return "openai"
        default:
            return cliproxyOAuthCanonicalProviderKey(providerKey)
        }
    }

    func cliproxyOAuthProviderDisplayName(_ providerKey: String) -> String {
        switch providerKey {
        case "claude":
            return "Claude"
        case "codex":
            return "Codex"
        case "gemini":
            return "Gemini"
        case "antigravity":
            return "Antigravity"
        case "kimi":
            return "Kimi"
        default:
            return providerKey.isEmpty ? "Unknown" : providerKey.capitalized
        }
    }

    func cliproxyOAuthProviderSortIndex(_ providerKey: String) -> Int {
        switch providerKey {
        case "claude":
            return 0
        case "codex":
            return 1
        case "gemini":
            return 2
        case "antigravity":
            return 3
        case "kimi":
            return 4
        default:
            return 99
        }
    }

    func cliproxyOAuthProviderTintKey(_ providerKey: String) -> Color {
        switch providerKey {
        case "claude":
            return .orange
        case "codex":
            return .blue
        case "gemini":
            return .mint
        case "antigravity":
            return .purple
        case "kimi":
            return .red
        default:
            return .secondary
        }
    }
}
