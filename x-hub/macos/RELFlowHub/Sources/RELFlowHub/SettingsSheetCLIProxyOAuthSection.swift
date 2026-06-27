import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    var cliproxyOAuthOverviewSection: some View {
        Section("CLIProxy 库存雷达") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CLIProxy Free Tier Radar")
                            .font(.headline)
                        Text("把 CLIProxy 管理页里已经认证成功的账号，直接抬到总览层看库存健康、冷却恢复和厂家覆盖。")
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

                Text(cliproxyOAuthOverviewSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 168), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(cliproxyOAuthOverviewMetrics) { metric in
                        settingsMetricCard(metric, compact: false)
                    }
                }

                terminalAccessFeedbackBanner(
                    text: cliproxyOAuthOverviewNoticeText,
                    tint: cliproxyOAuthOverviewNoticeTint,
                    systemName: cliproxyOAuthOverviewNoticeSystemName
                )

                if !cliproxyOAuthProviderSummaries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("厂家库存条带")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("点任一厂家可直达模型页对应的厂家经营总账。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 180), spacing: 10)],
                            alignment: .leading,
                            spacing: 10
                        ) {
                            ForEach(cliproxyOAuthProviderSummaries) { summary in
                                cliproxyOAuthProviderOverviewCard(summary)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    cliproxyOAuthActionButton(
                        title: "管理库存",
                        systemName: "slider.horizontal.3",
                        tint: .indigo
                    ) {
                        openCLIProxyOAuthInventoryManager()
                    }

                    cliproxyOAuthActionButton(
                        title: "打开管理页",
                        systemName: "globe",
                        tint: .teal
                    ) {
                        openCLIProxyOAuthManagementConsole()
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
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [
                        Color.teal.opacity(0.12),
                        Color.blue.opacity(0.08),
                        Color.mint.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.teal.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

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
}
