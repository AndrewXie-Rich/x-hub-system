import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    @ViewBuilder
    var cliproxyRuntimeControlPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本地节点托管")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Hub 可以直接接管本机的 CLIProxy 发行包：自动探测目录、检查 8317 状态，并从这里一键启动。默认会带 `--local-model` 降低后台负担。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(cliproxyRuntimeStatusBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(cliproxyRuntimeStatusTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(cliproxyRuntimeStatusTint.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("发行包目录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(
                        "~/Documents/AX/source/CLIProxyAPI-main/CLIProxyAPI_6.9.30_darwin_amd64",
                        text: $cliproxyRuntimeSettings.packageDirectoryPath
                    )
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("低负担模式 (--local-model)", isOn: $cliproxyRuntimeSettings.useLocalModel)
                        .toggleStyle(.switch)
                    Toggle("优先使用自动探测目录", isOn: $cliproxyRuntimeSettings.preferDetectedPackage)
                        .toggleStyle(.switch)

                    if cliproxyRuntimeLastProbeAtMs > 0 {
                        Text("上次检查 \(formattedProviderKeyImportSourceTime(cliproxyRuntimeLastProbeAtMs))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("还没有本地节点检查记录")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 250, alignment: .leading)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    cliproxyOAuthActionButton(
                        title: "自动探测",
                        systemName: "scope",
                        tint: .indigo,
                        disabled: cliproxyRuntimeControlBusy
                    ) {
                        detectCLIProxyRuntimePackage()
                    }

                    cliproxyOAuthActionButton(
                        title: cliproxyRuntimeRefreshing ? "检查中" : "检查节点",
                        systemName: "bolt.horizontal.circle",
                        tint: .blue,
                        disabled: cliproxyRuntimeControlBusy
                    ) {
                        Task { await refreshCLIProxyRuntimeStatus(manual: true) }
                    }

                    cliproxyOAuthActionButton(
                        title: cliproxyRuntimeLaunching ? "启动中" : "启动本地节点",
                        systemName: "play.circle",
                        tint: .green,
                        disabled: cliproxyRuntimeControlBusy
                    ) {
                        Task { await startCLIProxyRuntime() }
                    }

                    Menu {
                        Button("打开发行包目录") {
                            openCLIProxyRuntimePackageDirectory()
                        }
                        Button("打开 config.yaml") {
                            openCLIProxyRuntimeConfigFile()
                        }
                        Button("打开管理页") {
                            openCLIProxyOAuthManagementConsole()
                        }
                    } label: {
                        settingsActionChipLabel(
                            title: "更多",
                            systemName: "ellipsis.circle",
                            tint: .secondary,
                            disabled: cliproxyRuntimeControlBusy
                        )
                    }
                    .disabled(cliproxyRuntimeControlBusy)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        cliproxyOAuthActionButton(
                            title: "自动探测",
                            systemName: "scope",
                            tint: .indigo,
                            disabled: cliproxyRuntimeControlBusy
                        ) {
                            detectCLIProxyRuntimePackage()
                        }

                        cliproxyOAuthActionButton(
                            title: cliproxyRuntimeRefreshing ? "检查中" : "检查节点",
                            systemName: "bolt.horizontal.circle",
                            tint: .blue,
                            disabled: cliproxyRuntimeControlBusy
                        ) {
                            Task { await refreshCLIProxyRuntimeStatus(manual: true) }
                        }
                    }

                    HStack(spacing: 8) {
                        cliproxyOAuthActionButton(
                            title: cliproxyRuntimeLaunching ? "启动中" : "启动本地节点",
                            systemName: "play.circle",
                            tint: .green,
                            disabled: cliproxyRuntimeControlBusy
                        ) {
                            Task { await startCLIProxyRuntime() }
                        }

                        Menu {
                            Button("打开发行包目录") {
                                openCLIProxyRuntimePackageDirectory()
                            }
                            Button("打开 config.yaml") {
                                openCLIProxyRuntimeConfigFile()
                            }
                            Button("打开管理页") {
                                openCLIProxyOAuthManagementConsole()
                            }
                        } label: {
                            settingsActionChipLabel(
                                title: "更多",
                                systemName: "ellipsis.circle",
                                tint: .secondary,
                                disabled: cliproxyRuntimeControlBusy
                            )
                        }
                        .disabled(cliproxyRuntimeControlBusy)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    cliproxyRuntimeStateChip(
                        title: "发行包",
                        value: cliproxyRuntimePackageChipText,
                        tint: cliproxyRuntimePackageChipTint,
                        systemName: "shippingbox"
                    )
                    cliproxyRuntimeStateChip(
                        title: "服务",
                        value: cliproxyRuntimeServiceChipText,
                        tint: cliproxyRuntimeServiceChipTint,
                        systemName: "dot.radiowaves.left.and.right"
                    )
                    cliproxyRuntimeStateChip(
                        title: "管理端",
                        value: cliproxyRuntimeManagementChipText,
                        tint: cliproxyRuntimeManagementChipTint,
                        systemName: "lock.shield"
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    cliproxyRuntimeStateChip(
                        title: "发行包",
                        value: cliproxyRuntimePackageChipText,
                        tint: cliproxyRuntimePackageChipTint,
                        systemName: "shippingbox"
                    )
                    cliproxyRuntimeStateChip(
                        title: "服务",
                        value: cliproxyRuntimeServiceChipText,
                        tint: cliproxyRuntimeServiceChipTint,
                        systemName: "dot.radiowaves.left.and.right"
                    )
                    cliproxyRuntimeStateChip(
                        title: "管理端",
                        value: cliproxyRuntimeManagementChipText,
                        tint: cliproxyRuntimeManagementChipTint,
                        systemName: "lock.shield"
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("配置建议")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(cliproxyRuntimeConfigSummaryText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            cliproxyOAuthActionButton(
                                title: cliproxyRuntimeKeyRotating ? "轮换中" : "轮换管理 Key",
                                systemName: "key.horizontal.fill",
                                tint: .indigo,
                                disabled: cliproxyRuntimeControlBusy
                            ) {
                                Task { await rotateCLIProxyRuntimeManagementKey() }
                            }

                            cliproxyOAuthActionButton(
                                title: cliproxyRuntimeConfigApplying ? "写入中" : "应用推荐修正",
                                systemName: "wand.and.stars",
                                tint: .orange,
                                disabled: cliproxyRuntimeControlBusy || cliproxyRuntimeConfigAudit.unresolvedCount == 0
                            ) {
                                Task { await applyCLIProxyRuntimeConfigRecommendations() }
                            }
                        }

                        VStack(alignment: .trailing, spacing: 8) {
                            cliproxyOAuthActionButton(
                                title: cliproxyRuntimeKeyRotating ? "轮换中" : "轮换管理 Key",
                                systemName: "key.horizontal.fill",
                                tint: .indigo,
                                disabled: cliproxyRuntimeControlBusy
                            ) {
                                Task { await rotateCLIProxyRuntimeManagementKey() }
                            }

                            cliproxyOAuthActionButton(
                                title: cliproxyRuntimeConfigApplying ? "写入中" : "应用推荐修正",
                                systemName: "wand.and.stars",
                                tint: .orange,
                                disabled: cliproxyRuntimeControlBusy || cliproxyRuntimeConfigAudit.unresolvedCount == 0
                            ) {
                                Task { await applyCLIProxyRuntimeConfigRecommendations() }
                            }
                        }
                    }
                }

                if cliproxyRuntimeConfigAudit.recommendations.isEmpty {
                    Text("定位到 config.yaml 后，这里会显示低负担和安全相关的推荐项。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cliproxyRuntimeConfigAudit.recommendations) { recommendation in
                        cliproxyRuntimeConfigRecommendationRow(recommendation)
                    }
                }
            }

            Text(cliproxyRuntimeSummaryText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !cliproxyRuntimeActionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                terminalAccessFeedbackBanner(
                    text: cliproxyRuntimeActionText,
                    tint: .blue,
                    systemName: "bolt.horizontal.circle"
                )
            }

            if !cliproxyRuntimeErrorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                terminalAccessFeedbackBanner(
                    text: cliproxyRuntimeErrorText,
                    tint: .red,
                    systemName: "exclamationmark.triangle"
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.46))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.indigo.opacity(0.10), lineWidth: 1)
        )
    }
}
