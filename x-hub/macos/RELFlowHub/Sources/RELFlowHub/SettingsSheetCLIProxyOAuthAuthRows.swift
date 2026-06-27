import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
@ViewBuilder
    func cliproxyOAuthAuthRow(
        _ auth: CLIProxyOAuthSourceSupport.RemoteAuthFile
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(cliproxyOAuthAuthStateColor(auth))
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(cliproxyOAuthAuthTitle(auth))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Text(cliproxyOAuthAuthStateText(auth))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(cliproxyOAuthAuthStateColor(auth))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(cliproxyOAuthAuthStateColor(auth).opacity(0.12))
                        .clipShape(Capsule())

                    if auth.quota.exceeded {
                        Text("额度受限")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if auth.runtimeOnly {
                        Text("runtime-only")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Text(cliproxyOAuthAuthMetaText(auth))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                let timingText = cliproxyOAuthAuthTimingText(auth)
                if !timingText.isEmpty {
                    Text(timingText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !auth.statusMessage.isEmpty && auth.statusMessage != auth.quota.reason {
                    Text(auth.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(cliproxyOAuthAuthStateColor(auth))
                        .fixedSize(horizontal: false, vertical: true)
                } else if !auth.quota.reason.isEmpty {
                    Text(auth.quota.reason)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(cliproxyOAuthAuthStateColor(auth).opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    func cliproxyOAuthAuthTitle(
        _ auth: CLIProxyOAuthSourceSupport.RemoteAuthFile
    ) -> String {
        if !auth.email.isEmpty {
            return auth.email
        }
        if !auth.label.isEmpty {
            return auth.label
        }
        return auth.name
    }

    func cliproxyOAuthAuthStateText(
        _ auth: CLIProxyOAuthSourceSupport.RemoteAuthFile
    ) -> String {
        if auth.disabled {
            return "禁用"
        }
        if auth.quota.exceeded || auth.nextRetryAtMs > 0 {
            return "冷却中"
        }

        switch auth.status.lowercased() {
        case "active", "ok", "ready":
            return "可用"
        case "refreshing":
            return "刷新中"
        case "pending", "wait":
            return "等待中"
        case "error":
            return "异常"
        default:
            return auth.status.isEmpty ? "未知" : auth.status
        }
    }

    func cliproxyOAuthAuthStateColor(
        _ auth: CLIProxyOAuthSourceSupport.RemoteAuthFile
    ) -> Color {
        if auth.disabled {
            return .gray
        }
        if auth.quota.exceeded || auth.nextRetryAtMs > 0 {
            return .orange
        }
        switch auth.status.lowercased() {
        case "active", "ok", "ready":
            return .green
        case "refreshing":
            return .blue
        case "pending", "wait":
            return .yellow
        case "error":
            return .red
        default:
            return .secondary
        }
    }

    func cliproxyOAuthAuthMetaText(
        _ auth: CLIProxyOAuthSourceSupport.RemoteAuthFile
    ) -> String {
        HubUIStrings.Settings.RemoteModels.sectionSummary([
            auth.provider.uppercased(),
            !auth.accountType.isEmpty && !auth.account.isEmpty ? "\(auth.accountType) \(auth.account)" : "",
            !auth.accountType.isEmpty && auth.account.isEmpty ? auth.accountType : "",
            !auth.account.isEmpty && auth.accountType.isEmpty ? auth.account : "",
            !auth.runtimeAuthIndex.isEmpty ? "runtime \(String(auth.runtimeAuthIndex.prefix(10)))" : "",
            auth.name
        ])
    }

    func cliproxyOAuthAuthTimingText(
        _ auth: CLIProxyOAuthSourceSupport.RemoteAuthFile
    ) -> String {
        var parts: [String] = []
        if auth.lastRefreshAtMs > 0 {
            parts.append("上次刷新 \(formattedProviderKeyImportSourceTime(auth.lastRefreshAtMs))")
        }
        if auth.nextRefreshAtMs > 0 {
            parts.append("下次刷新 \(formattedProviderKeyImportSourceTime(auth.nextRefreshAtMs))")
        }
        if auth.nextRetryAtMs > 0 {
            parts.append("重试 \(formattedProviderKeyImportSourceTime(auth.nextRetryAtMs))")
        }
        if auth.quota.nextRecoverAtMs > 0 {
            parts.append("额度恢复 \(formattedProviderKeyImportSourceTime(auth.quota.nextRecoverAtMs))")
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }
}
