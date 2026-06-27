import SwiftUI

extension SettingsSheetView {
    func settingsSidebarBadge(for page: HubSettingsPage) -> String {
        switch page {
        case .overview:
            return hubStatusPresentation.title
        case .access:
            return "\(grpc.allowedClients.count) XT"
        case .models:
            if localCatalogModelCount == 0 && remoteModels.isEmpty && providerKeyDerivedSnapshot.totalAccounts == 0 {
                return "未配置"
            }
            return "本地 \(localCatalogModelCount) · 付费 \(remoteModels.count)"
        case .runtime:
            return totalRuntimeProviderCount > 0 ? "\(readyRuntimeProviderCount)/\(totalRuntimeProviderCount) 就绪" : "等待心跳"
        case .integrations:
            return "\(skillsIndex.skills.count) skills"
        case .diagnostics:
            return settingsIssueCount > 0 ? "\(settingsIssueCount) 项" : "稳定"
        }
    }

    func settingsSidebarDetail(for page: HubSettingsPage) -> String {
        switch page {
        case .overview:
            return "查看当前健康度、配置完成度和关键风险。"
        case .access:
            return "谁能连接 Hub，以及如何连接。"
        case .models:
            return "本地模型能力、付费模型能力与共享额度。"
        case .runtime:
            return "Provider、队列、实例与路由排障。"
        case .integrations:
            return "Operator、Skills、Calendar 与浮窗。"
        case .diagnostics:
            return "排障、日志、恢复动作与底层参数。"
        }
    }

    func settingsPageMetrics(for page: HubSettingsPage) -> [HubSettingsMetric] {
        switch page {
        case .overview:
            return headerMetrics
        case .access:
            return [
                HubSettingsMetric(
                    title: "XT 设备",
                    value: "\(grpc.allowedClients.count)",
                    detail: grpc.statusText,
                    tint: .teal
                ),
                HubSettingsMetric(
                    title: "Terminal Key",
                    value: terminalAccessKeys.isEmpty ? "未签发" : "\(terminalAccessReadyCount)/\(terminalAccessKeys.count)",
                    detail: terminalAccessKeys.isEmpty ? "还没有普通 terminal key" : "可直接导出给普通 terminal",
                    tint: .blue
                ),
                HubSettingsMetric(
                    title: "远程接入",
                    value: grpcRemoteAccessHealthSummary.badgeText,
                    detail: grpcRemoteAccessHealthSummary.accessScopeText,
                    tint: grpcRemoteAccessHealthSummary.state == .ready ? .green : .orange
                ),
                HubSettingsMetric(
                    title: "Pairing",
                    value: "\(grpc.xtTerminalPairingPort)",
                    detail: grpc.xtTerminalInternetHost ?? "当前没有稳定外部地址",
                    tint: .indigo
                )
            ]
        case .models:
            let providerDerived = providerKeyDerivedSnapshot
            let importIssueCount = providerKeySnapshot.importSources.filter { source in
                source.state != "ready" || source.lastErrorCount > 0
            }.count
            return [
                HubSettingsMetric(
                    title: "本地模型",
                    value: localCatalogModelCount == 0 ? "未发现" : "\(loadedLocalModelCount)/\(localCatalogModelCount)",
                    detail: localCatalogModelCount == 0
                        ? "当前还没有发现可由 Hub 管理的本地模型"
                        : "已加载 / 全部 · 预检可用 \(localAvailableModelCount) · 待复核 \(localPendingModelCount)",
                    tint: localModelsCapabilityTint
                ),
                HubSettingsMetric(
                    title: "付费模型",
                    value: remoteModels.isEmpty
                        ? (providerDerived.totalAccounts > 0 ? "待编目" : "未配置")
                        : "\(loadedRemoteModelCount)/\(remoteModels.count)",
                    detail: remoteModels.isEmpty
                        ? (providerDerived.totalAccounts > 0
                            ? "已导入 \(providerDerived.totalAccounts) 个 key，可继续编入可执行付费模型"
                            : "当前还没有配置任何付费 / 远端模型")
                        : "已加载 / 全部 · 可执行 \(availableRemoteModelCount) · 待补齐 \(needsSetupRemoteModelCount)",
                    tint: needsSetupRemoteModelCount > 0 ? .orange : (loadedRemoteModelCount > 0 ? .green : .indigo)
                ),
                HubSettingsMetric(
                    title: "Key 健康",
                    value: "\(providerDerived.readyAccounts)/\(providerDerived.totalAccounts)",
                    detail: importIssueCount > 0
                        ? "就绪 / 全部 · 阻塞 \(providerDerived.blockedAccounts) · 导入源异常 \(importIssueCount)"
                        : "就绪 / 全部 · 阻塞 \(providerDerived.blockedAccounts)",
                    tint: providerDerived.blockedAccounts > 0 ? .orange : .green
                ),
                HubSettingsMetric(
                    title: "额度池",
                    value: "\(quotaPoolCount)",
                    detail: "按模型家族聚合后的共享库存",
                    tint: .blue
                ),
                HubSettingsMetric(
                    title: "物理池",
                    value: "\(providerDerived.keyPools.count)",
                    detail: "冷却 \(providerDerived.cooldownAccounts) · 阻塞 \(providerDerived.blockedAccounts)",
                    tint: .purple
                ),
                cliproxyOAuthHeaderMetric
            ]
        case .runtime:
            return [
                HubSettingsMetric(
                    title: rustLocalMLAuthorityMode ? "Rust ML" : "Runtime",
                    value: runtimeHeartbeatText,
                    detail: runtimeAuthorityDetailText,
                    tint: runtimeAuthorityTint
                ),
                HubSettingsMetric(
                    title: "已加载模型",
                    value: "\(loadedLocalModelCount)",
                    detail: "本地模型库里当前标记为 loaded 的条目",
                    tint: .orange
                ),
                HubSettingsMetric(
                    title: "驻留实例",
                    value: "\(loadedRuntimeInstanceCount)",
                    detail: "当前 runtime 里可直接复用的实例",
                    tint: .blue
                ),
                HubSettingsMetric(
                    title: "默认路由",
                    value: "\(store.routingSettings.hubDefaultModelIdByTaskKind.count)",
                    detail: "Hub 级 task-kind 默认模型覆盖",
                    tint: .indigo
                )
            ]
        case .integrations:
            return [
                HubSettingsMetric(
                    title: "Operator",
                    value: operatorChannelProviderReadiness.isEmpty ? "待检测" : "\(operatorReadyCount)/\(operatorChannelProviderReadiness.count)",
                    detail: operatorChannelProviderReadinessError.isEmpty ? "渠道投递 readiness 快照" : operatorChannelProviderReadinessError,
                    tint: operatorChannelProviderReadinessError.isEmpty ? .green : .orange
                ),
                HubSettingsMetric(
                    title: "Skills",
                    value: "\(skillsIndex.skills.count)",
                    detail: "当前可解析的技能包数量",
                    tint: .green
                ),
                HubSettingsMetric(
                    title: "Calendar",
                    value: store.calendarStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未配置" : store.calendarStatus,
                    detail: "日历与本地提醒接入状态",
                    tint: .blue
                ),
                HubSettingsMetric(
                    title: "Floating",
                    value: store.floatingMode.title,
                    detail: "当前浮窗展示模式",
                    tint: .teal
                )
            ]
        case .diagnostics:
            return [
                HubSettingsMetric(
                    title: "启动状态",
                    value: hubStatusPresentation.title,
                    detail: hubLaunchStatus?.rootCause?.errorCode ?? hubStatusDetailText,
                    tint: headerLaunchTint
                ),
                HubSettingsMetric(
                    title: "阻塞能力",
                    value: "\(blockedCapabilityCount)",
                    detail: blockedCapabilityCount == 0 ? "当前没有被降级的 capability" : "当前有 capability 被 fail-closed",
                    tint: blockedCapabilityCount > 0 ? .orange : .green
                ),
                HubSettingsMetric(
                    title: "拒绝记录",
                    value: "\(grpcDeniedAttempts.attempts.count)",
                    detail: grpcDeniedAttempts.attempts.isEmpty ? "最近没有新的 grant 拒绝" : "最近存在安全拒绝或权限问题",
                    tint: grpcDeniedAttempts.attempts.isEmpty ? .green : .orange
                ),
                HubSettingsMetric(
                    title: "诊断历史",
                    value: "\(hubLaunchHistory.launches.count)",
                    detail: "已保留的启动 / 降级历史条目",
                    tint: .red
                )
            ]
        }
    }

    func settingsPageSections(for page: HubSettingsPage) -> some View {
        Group {
            switch page {
            case .overview:
                setupCenterSection
                cliproxyOAuthOverviewSection
                firstRunFastPathSection
                quickTroubleshootSection
            case .access:
                grpcServerSection
                terminalAccessSection
            case .models:
                modelResourcePoolsSection
                settingsCollapsedSectionCard(
                    title: "模型编目与运行明细",
                    summary: "导入本地模型、维护付费模型目录、运行快速预检和健康扫描。",
                    badge: modelCatalogDetailsExpanded
                        ? "已展开"
                        : "本地 \(localCatalogModelCount) · 付费 \(remoteModels.count)",
                    tint: .indigo,
                    isExpanded: $modelCatalogDetailsExpanded
                )
                if modelCatalogDetailsExpanded {
                    localModelsCapabilitySection
                    remoteModelsSection
                }
                settingsCollapsedSectionCard(
                    title: "高级配额运营",
                    summary: providerQuotaOperationsSummaryText,
                    badge: providerQuotaOperationsExpanded ? "已展开" : providerQuotaOperationsBadgeText,
                    tint: providerQuotaOperationsTint,
                    isExpanded: $providerQuotaOperationsExpanded
                )
                if providerQuotaOperationsExpanded {
                    providerKeySection
                }
                settingsCollapsedSectionCard(
                    title: "自动扫描与保活策略",
                    summary: modelHealthAutoScanSummaryText,
                    badge: modelsAutoScanExpanded ? "已展开" : "低频项",
                    tint: .indigo,
                    isExpanded: $modelsAutoScanExpanded
                )
                if modelsAutoScanExpanded {
                    modelHealthAutoScanSection
                }
            case .runtime:
                rustHubKernelSection
                runtimeMonitorSection
                settingsCollapsedSectionCard(
                    title: "任务路由映射",
                    summary: routingSummaryText,
                    badge: runtimeRoutingExpanded ? "已展开" : "按需配置",
                    tint: .orange,
                    isExpanded: $runtimeRoutingExpanded
                )
                if runtimeRoutingExpanded {
                    routingSection
                }
            case .integrations:
                operatorChannelReadinessSection
                settingsCollapsedSectionCard(
                    title: "扩展接入与低频维护",
                    summary: integrationsAuxSummaryText,
                    badge: integrationsAuxExpanded ? "已展开" : "低频项",
                    tint: .green,
                    isExpanded: $integrationsAuxExpanded
                )
                if integrationsAuxExpanded {
                    operatorChannelOnboardingSection
                    skillsSection
                    calendarSection
                    floatingModeSection
                }
            case .diagnostics:
                doctorSection
                settingsCollapsedSectionCard(
                    title: "启动链路明细",
                    summary: diagnosticsLaunchSummaryText,
                    badge: currentLaunchStateLabel,
                    tint: headerLaunchTint,
                    isExpanded: $diagnosticsLaunchExpanded
                )
                if diagnosticsLaunchExpanded {
                    diagnosticsSection
                }
                settingsCollapsedSectionCard(
                    title: "网络授权与桥接",
                    summary: diagnosticsNetworkSummaryText,
                    badge: diagnosticsNetworkExpanded
                        ? "已展开"
                        : (store.pendingNetworkRequests.isEmpty ? "干净" : "\(store.pendingNetworkRequests.count) 待处理"),
                    tint: store.pendingNetworkRequests.isEmpty ? .teal : .orange,
                    isExpanded: $diagnosticsNetworkExpanded
                )
                if diagnosticsNetworkExpanded {
                    networkPoliciesSection
                    networkingSection
                }
                settingsCollapsedSectionCard(
                    title: "高级参数",
                    summary: diagnosticsAdvancedSummaryText,
                    badge: diagnosticsAdvancedExpanded ? "已展开" : "专家项",
                    tint: .secondary,
                    isExpanded: $diagnosticsAdvancedExpanded
                )
                if diagnosticsAdvancedExpanded {
                    advancedSection
                }
            }
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(HubUIStrings.Settings.title)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(HubUIStrings.Settings.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    Label(hubStatusBadgeText, systemImage: hubStatusPresentation.systemName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(headerLaunchTint.opacity(0.12))
                        .foregroundStyle(headerLaunchTint)
                        .clipShape(Capsule())
                    Text(HubUIStrings.Settings.validationChain)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(headerLaunchTint.opacity(0.12))
                        .foregroundStyle(headerLaunchTint)
                        .clipShape(Capsule())
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(headerMetrics) { metric in
                    settingsMetricCard(metric, compact: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor),
                            headerLaunchTint.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    var formContent: some View {
        HStack(alignment: .top, spacing: 18) {
            settingsSidebar
            settingsPageSurface
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Control Center")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(HubSettingsPage.allCases) { page in
                Button {
                    selectSettingsPage(page)
                } label: {
                    settingsSidebarRow(page)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 10) {
                Text("App")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                let ver = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
                let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
                Text(HubUIStrings.Settings.Quit.version(ver, build))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Button(HubUIStrings.Settings.Quit.quitApp) {
                    quitApp()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(18)
        .frame(width: 252, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    func settingsSidebarRow(_ page: HubSettingsPage) -> some View {
        let isSelected = selectedSettingsPage == page
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(page.tint.opacity(isSelected ? 0.22 : 0.12))
                Image(systemName: page.systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(page.tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(page.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(settingsSidebarBadge(for: page))
                        .font(.caption2.monospaced())
                        .foregroundStyle(isSelected ? page.tint : .secondary)
                }
                Text(settingsSidebarDetail(for: page))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? page.tint.opacity(0.10) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? page.tint.opacity(0.35) : Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    var settingsPageSurface: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    settingsPageHero(selectedSettingsPage)
                    settingsPageSections(for: selectedSettingsPage)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .id(selectedSettingsPage.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                scrollToSettingsTargetIfNeeded(proxy)
            }
            .onChange(of: settingsScrollTarget) { _ in
                scrollToSettingsTargetIfNeeded(proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    func settingsPageHero(_ page: HubSettingsPage) -> some View {
        let metrics = settingsPageMetrics(for: page)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    page.tint.opacity(0.22),
                                    page.tint.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: page.systemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(page.tint)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 5) {
                    Text(page.title)
                        .font(.title3.weight(.semibold))
                    Text(page.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(settingsSidebarBadge(for: page))
                    .font(.caption.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(page.tint.opacity(0.12))
                    .foregroundStyle(page.tint)
                    .clipShape(Capsule())
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(metrics) { metric in
                    settingsMetricCard(metric, compact: false)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            page.tint.opacity(0.12),
                            Color.primary.opacity(0.025)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    func settingsMetricCard(_ metric: HubSettingsMetric, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            Text(metric.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(metric.value)
                .font(compact ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
            Text(metric.detail)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(compact ? 2 : 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 12 : 14)
        .background(metric.tint.opacity(compact ? 0.08 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 18, style: .continuous))
    }
}
