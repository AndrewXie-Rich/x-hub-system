import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    @ViewBuilder
    var cliproxyOAuthSourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hub OAuth")
                        .font(.subheadline.weight(.semibold))
                    Text("直接从 Hub 发起 Codex / Claude / Gemini / Antigravity OAuth，登录完成后凭证会进入 Hub Provider Key 额度池。CLIProxy 只保留为旧账号导入来源。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(cliproxyOAuthStatusBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(cliproxyOAuthStatusTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(cliproxyOAuthStatusTint.opacity(0.12))
                    .clipShape(Capsule())
            }

            cliproxyRuntimeControlPanel

            Rectangle()
                .fill(Color.indigo.opacity(0.08))
                .frame(height: 1)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CLIProxy 地址")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("http://127.0.0.1:8317", text: $cliproxyOAuthSettings.baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Management Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("Bearer 管理 key", text: $cliproxyOAuthManagementKey)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 12) {
                Toggle("自动同步", isOn: $cliproxyOAuthSettings.autoSync)
                    .toggleStyle(.switch)

                if cliproxyOAuthSettings.lastSyncAtMs > 0 {
                    Text("上次成功同步 \(formattedProviderKeyImportSourceTime(cliproxyOAuthSettings.lastSyncAtMs))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("还没有成功同步记录")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            terminalAccessFeedbackBanner(
                text: cliproxyOAuthHubRoutingStatusText,
                tint: cliproxyOAuthHubRoutingStatusTint,
                systemName: cliproxyOAuthHubRoutingStatusSystemName
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("常用动作")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        cliproxyOAuthActionButton(
                            title: "保存",
                            systemName: "square.and.arrow.down",
                            tint: .blue
                        ) {
                            persistCLIProxyRuntimeConfiguration()
                            persistCLIProxyOAuthConfiguration()
                            cliproxyOAuthActionText = "CLIProxy 接入设置已保存。"
                            cliproxyOAuthErrorText = ""
                        }

                        cliproxyOAuthActionButton(
                            title: cliproxyOAuthSyncing ? "同步中" : "同步到 Hub",
                            systemName: "shippingbox.and.arrow.backward",
                            tint: .green,
                            disabled: cliproxyOAuthSyncing
                        ) {
                            Task { await syncCLIProxyOAuthAccounts(manual: true) }
                        }

                        Menu {
                            ForEach(HubProviderOAuthHTTPClient.Provider.allCases) { provider in
                                Button(provider.title) {
                                    Task { await startCLIProxyOAuth(provider) }
                                }
                            }
                        } label: {
                            settingsActionChipLabel(
                                title: "发起 OAuth",
                                systemName: "person.badge.key",
                                tint: .indigo,
                                disabled: cliproxyOAuthSyncing
                            )
                        }
                        .disabled(cliproxyOAuthSyncing)

                        Menu {
                            Button("打开管理页") {
                                openCLIProxyOAuthManagementConsole()
                            }
                            Button(cliproxyOAuthRefreshing ? "刷新中" : "刷新账号") {
                                Task { await refreshCLIProxyOAuthRemoteAuths(manual: true) }
                            }
                            .disabled(cliproxyOAuthRefreshing || cliproxyOAuthSyncing)
                        } label: {
                            settingsActionChipLabel(
                                title: "维护",
                                systemName: "ellipsis.circle",
                                tint: .secondary
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            cliproxyOAuthActionButton(
                                title: "保存",
                                systemName: "square.and.arrow.down",
                                tint: .blue
                            ) {
                                persistCLIProxyRuntimeConfiguration()
                                persistCLIProxyOAuthConfiguration()
                                cliproxyOAuthActionText = "CLIProxy 接入设置已保存。"
                                cliproxyOAuthErrorText = ""
                            }

                            cliproxyOAuthActionButton(
                                title: cliproxyOAuthSyncing ? "同步中" : "同步到 Hub",
                                systemName: "shippingbox.and.arrow.backward",
                                tint: .green,
                                disabled: cliproxyOAuthSyncing
                            ) {
                                Task { await syncCLIProxyOAuthAccounts(manual: true) }
                            }
                        }

                        HStack(spacing: 8) {
                            Menu {
                                ForEach(HubProviderOAuthHTTPClient.Provider.allCases) { provider in
                                    Button(provider.title) {
                                        Task { await startCLIProxyOAuth(provider) }
                                    }
                                }
                            } label: {
                                settingsActionChipLabel(
                                    title: "发起 OAuth",
                                    systemName: "person.badge.key",
                                    tint: .indigo,
                                    disabled: cliproxyOAuthSyncing
                                )
                            }
                            .disabled(cliproxyOAuthSyncing)

                            Menu {
                                Button("打开管理页") {
                                    openCLIProxyOAuthManagementConsole()
                                }
                                Button(cliproxyOAuthRefreshing ? "刷新中" : "刷新账号") {
                                    Task { await refreshCLIProxyOAuthRemoteAuths(manual: true) }
                                }
                                .disabled(cliproxyOAuthRefreshing || cliproxyOAuthSyncing)
                            } label: {
                                settingsActionChipLabel(
                                    title: "维护",
                                    systemName: "ellipsis.circle",
                                    tint: .secondary
                                )
                            }
                        }
                    }
                }

                Text("新登录直接由 Hub 接管；保存、同步、刷新和管理页只用于旧 CLIProxy 账号导入。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !cliproxyOAuthActionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                terminalAccessFeedbackBanner(
                    text: cliproxyOAuthActionText,
                    tint: .blue,
                    systemName: "person.crop.circle.badge.checkmark"
                )
            }

            if !cliproxyOAuthErrorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                terminalAccessFeedbackBanner(
                    text: cliproxyOAuthErrorText,
                    tint: .red,
                    systemName: "exclamationmark.triangle"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("已认证账号")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if cliproxyOAuthLastRemoteFetchAtMs > 0 {
                        Text("列表刷新 \(formattedProviderKeyImportSourceTime(cliproxyOAuthLastRemoteFetchAtMs))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if cliproxyOAuthRemoteAuths.isEmpty {
                    Text("当前还没有旧 CLIProxy 已认证账号。新账号直接点上面的 OAuth 按钮由 Hub 接管。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cliproxyOAuthRemoteAuths) { auth in
                        cliproxyOAuthAuthRow(auth)
                    }
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.10),
                    Color.blue.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.indigo.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    var cliproxyOAuthStatusBadgeText: String {
        if cliproxyOAuthSyncing {
            return "同步中"
        }
        if cliproxyOAuthRefreshing {
            return "刷新中"
        }
        if let provider = cliproxyOAuthActiveProvider,
           !cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(provider.title) 登录中"
        }
        if cliproxyOAuthSettings.autoSync {
            return "自动同步开"
        }
        return "手动同步"
    }

    var cliproxyOAuthStatusTint: Color {
        if cliproxyOAuthSyncing || cliproxyOAuthRefreshing {
            return .blue
        }
        if !cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .orange
        }
        return cliproxyOAuthSettings.autoSync ? .green : .secondary
    }

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

    func minimumPositiveTimestamp(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        let values = [lhs, rhs].filter { $0 > 0 }
        return values.min()
    }

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
