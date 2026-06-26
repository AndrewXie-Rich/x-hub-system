import SwiftUI

extension SettingsSheetView {
    var localModelsCapabilitySection: some View {
        Section("本地模型能力") {
            settingsOperationsPanelCard(
                systemName: "internaldrive.fill",
                title: "本地模型能力",
                summary: localModelsCapabilitySummaryText,
                badge: localModelsCapabilityBadgeText,
                tint: localModelsCapabilityTint
            ) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(localModelsCapabilityMetrics) { metric in
                        settingsMetricCard(metric, compact: false)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Button {
                            store.scanAllLocalModelHealth()
                        } label: {
                            settingsActionChipLabel(
                                title: store.localModelHealthScanInFlight
                                    ? HubUIStrings.Models.LocalHealth.scanningBadge
                                    : HubUIStrings.Models.LocalHealth.scanAll,
                                systemName: "waveform.path.ecg",
                                tint: .teal,
                                disabled: store.localModelHealthScanInFlight || localCatalogModels.isEmpty
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(store.localModelHealthScanInFlight || localCatalogModels.isEmpty)

                        Button {
                            modelStore.refresh()
                        } label: {
                            settingsActionChipLabel(
                                title: "刷新目录",
                                systemName: "arrow.clockwise",
                                tint: .indigo,
                                disabled: false
                            )
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button("查看运行时基础设施") {
                                selectSettingsPage(.runtime)
                            }
                            Button("查看任务路由") {
                                runtimeRoutingExpanded = true
                                selectSettingsPage(.runtime)
                            }
                            Button("自动扫描与保活策略") {
                                modelsAutoScanExpanded = true
                            }
                        } label: {
                            settingsActionChipLabel(
                                title: "更多动作",
                                systemName: "ellipsis.circle",
                                tint: .secondary
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Button {
                                store.scanAllLocalModelHealth()
                            } label: {
                                settingsActionChipLabel(
                                    title: store.localModelHealthScanInFlight
                                        ? HubUIStrings.Models.LocalHealth.scanningBadge
                                        : HubUIStrings.Models.LocalHealth.scanAll,
                                    systemName: "waveform.path.ecg",
                                    tint: .teal,
                                    disabled: store.localModelHealthScanInFlight || localCatalogModels.isEmpty
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(store.localModelHealthScanInFlight || localCatalogModels.isEmpty)

                            Button {
                                modelStore.refresh()
                            } label: {
                                settingsActionChipLabel(
                                    title: "刷新目录",
                                    systemName: "arrow.clockwise",
                                    tint: .indigo
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Menu {
                            Button("查看运行时基础设施") {
                                selectSettingsPage(.runtime)
                            }
                            Button("查看任务路由") {
                                runtimeRoutingExpanded = true
                                selectSettingsPage(.runtime)
                            }
                            Button("自动扫描与保活策略") {
                                modelsAutoScanExpanded = true
                            }
                        } label: {
                            settingsActionChipLabel(
                                title: "更多动作",
                                systemName: "ellipsis.circle",
                                tint: .secondary
                            )
                        }
                    }
                }

                if let notice = localModelsCapabilityNoticeText {
                    terminalAccessFeedbackBanner(
                        text: notice,
                        tint: localModelsCapabilityNoticeTint,
                        systemName: localModelsCapabilityNoticeSystemName
                    )
                }
            }

            Text("本地模型页只回答“能不能在 Hub 本地稳定执行”；更底层的 provider 心跳、实例与队列请去“运行时基础设施”。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    var remoteModelsSection: some View {
        Section("付费模型能力") {
            settingsOperationsPanelCard(
                systemName: "antenna.radiowaves.left.and.right",
                title: "付费模型能力",
                summary: remoteModelsSectionSummaryText,
                badge: remoteModelsOverviewBadgeText,
                tint: remoteModelsOverviewTint
            ) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(remoteModelsOverviewMetrics) { metric in
                        settingsMetricCard(metric, compact: false)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Button {
                            showAddRemoteModel = true
                        } label: {
                            settingsActionChipLabel(
                                title: HubUIStrings.Settings.RemoteModels.add,
                                systemName: "plus",
                                tint: .indigo
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.quickScanAllRemoteKeyHealth()
                        } label: {
                            settingsActionChipLabel(
                                title: store.remoteKeyHealthScanInFlight
                                    ? HubUIStrings.Settings.RemoteModels.healthCheckingBadge
                                    : HubUIStrings.Settings.RemoteModels.scanQuick,
                                systemName: "bolt.badge.clock",
                                tint: .teal,
                                disabled: store.remoteKeyHealthScanInFlight || remoteModels.isEmpty
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(store.remoteKeyHealthScanInFlight || remoteModels.isEmpty)

                        Menu {
                            Button(HubUIStrings.Settings.RemoteModels.importCatalog) {
                                showImportRemoteCatalog = true
                            }
                            Button(HubUIStrings.Settings.RemoteModels.scanFull) {
                                store.fullScanAllRemoteKeyHealth()
                            }
                            .disabled(store.remoteKeyHealthScanInFlight || remoteModels.isEmpty)
                        } label: {
                            settingsActionChipLabel(
                                title: "更多动作",
                                systemName: "ellipsis.circle",
                                tint: .secondary
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Button {
                                showAddRemoteModel = true
                            } label: {
                                settingsActionChipLabel(
                                    title: HubUIStrings.Settings.RemoteModels.add,
                                    systemName: "plus",
                                    tint: .indigo
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                store.quickScanAllRemoteKeyHealth()
                            } label: {
                                settingsActionChipLabel(
                                    title: store.remoteKeyHealthScanInFlight
                                        ? HubUIStrings.Settings.RemoteModels.healthCheckingBadge
                                        : HubUIStrings.Settings.RemoteModels.scanQuick,
                                    systemName: "bolt.badge.clock",
                                    tint: .teal,
                                    disabled: store.remoteKeyHealthScanInFlight || remoteModels.isEmpty
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(store.remoteKeyHealthScanInFlight || remoteModels.isEmpty)
                        }

                        Menu {
                            Button(HubUIStrings.Settings.RemoteModels.importCatalog) {
                                showImportRemoteCatalog = true
                            }
                            Button(HubUIStrings.Settings.RemoteModels.scanFull) {
                                store.fullScanAllRemoteKeyHealth()
                            }
                            .disabled(store.remoteKeyHealthScanInFlight || remoteModels.isEmpty)
                        } label: {
                            settingsActionChipLabel(
                                title: "更多动作",
                                systemName: "ellipsis.circle",
                                tint: .secondary
                            )
                        }
                    }
                }

                if let notice = remoteModelsAttentionBannerText {
                    terminalAccessFeedbackBanner(
                        text: notice,
                        tint: remoteModelsAttentionBannerTint,
                        systemName: remoteModelsAttentionBannerSystemName
                    )
                }
            }

            if remoteModels.isEmpty {
                Text(HubUIStrings.Settings.RemoteModels.empty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                settingsCollapsedSectionCard(
                    title: "付费模型组明细",
                    summary: "按 provider / key 聚合后的执行明细。展开后可继续加载、卸载、改组名或删除模型组。",
                    badge: remoteModelCatalogExpanded ? "已展开" : "\(remoteModelGroupCount) 个组",
                    tint: remoteModelsOverviewTint,
                    isExpanded: $remoteModelCatalogExpanded
                )
                if remoteModelCatalogExpanded {
                    ForEach(remoteModelGroups) { group in
                        remoteModelGroupCard(group)
                    }
                }
            }
            Text(HubUIStrings.Settings.RemoteModels.syncHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
