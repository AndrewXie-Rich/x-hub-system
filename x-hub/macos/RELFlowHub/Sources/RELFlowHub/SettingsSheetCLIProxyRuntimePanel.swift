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

    @ViewBuilder
    func cliproxyRuntimeStateChip(
        title: String,
        value: String,
        tint: Color,
        systemName: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .imageScale(.small)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    func cliproxyRuntimeConfigRecommendationRow(
        _ recommendation: CLIProxyRuntimeSupport.ConfigRecommendation
    ) -> some View {
        let tint = cliproxyRuntimeRecommendationTint(recommendation)

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: recommendation.satisfied ? "checkmark.seal.fill" : "wrench.and.screwdriver.fill")
                .imageScale(.small)
                .foregroundStyle(tint)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(recommendation.kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(recommendation.satisfied ? "已满足" : "建议修正")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.10))
                        .clipShape(Capsule())
                }

                Text(recommendation.kind.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("当前 \(recommendation.currentValueDisplay) -> 推荐 \(recommendation.recommendedValueDisplay)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(tint)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    var cliproxyRuntimeControlBusy: Bool {
        cliproxyRuntimeRefreshing
            || cliproxyRuntimeLaunching
            || cliproxyRuntimeConfigApplying
            || cliproxyRuntimeKeyRotating
    }

    var cliproxyRuntimeStatusBadgeText: String {
        if cliproxyRuntimeLaunching {
            return "启动中"
        }
        if cliproxyRuntimeRefreshing {
            return "检查中"
        }
        if cliproxyRuntimeKeyRotating {
            return "轮换 key"
        }
        if cliproxyRuntimeConfigApplying {
            return "写入配置"
        }
        if cliproxyRuntimeConfigAudit.unresolvedCount > 0 {
            return "待修配置"
        }
        if cliproxyRuntimeProbe.serviceRunning {
            return "节点在线"
        }
        if cliproxyRuntimeProbe.packageStatus == .detected {
            return "待启动"
        }
        return "待接入"
    }

    var cliproxyRuntimeStatusTint: Color {
        if cliproxyRuntimeLaunching
            || cliproxyRuntimeRefreshing
            || cliproxyRuntimeConfigApplying
            || cliproxyRuntimeKeyRotating {
            return .blue
        }
        if !cliproxyRuntimeErrorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .red
        }
        if cliproxyRuntimeConfigAudit.unresolvedCount > 0 {
            return .orange
        }
        if cliproxyRuntimeProbe.serviceRunning {
            switch cliproxyRuntimeProbe.managementStatus {
            case .keyInvalid, .unavailable, .error:
                return .orange
            default:
                return .green
            }
        }
        return cliproxyRuntimeProbe.packageStatus == .detected ? .indigo : .secondary
    }

    var cliproxyRuntimeConfigSummaryText: String {
        guard !cliproxyRuntimeConfigAudit.recommendations.isEmpty else {
            return "config.yaml 就位后，这里会给出低负担和安全建议。"
        }
        if cliproxyRuntimeConfigAudit.unresolvedCount == 0 {
            return "当前 \(cliproxyRuntimeConfigAudit.recommendations.count) 项推荐都已满足，适合常驻给 Hub 做本地 OAuth 汇聚节点。"
        }
        return "还有 \(cliproxyRuntimeConfigAudit.unresolvedCount) 项建议未处理。Hub 只会修正本地监听、管理面板和轻量运行相关项。"
    }

    func cliproxyRuntimeRecommendationTint(
        _ recommendation: CLIProxyRuntimeSupport.ConfigRecommendation
    ) -> Color {
        recommendation.satisfied ? .green : .orange
    }

    var cliproxyRuntimePackageChipText: String {
        switch cliproxyRuntimeProbe.packageStatus {
        case .detected:
            return cliproxyRuntimeProbe.usedDetectedPackage ? "已发现" : "已选定"
        case .notFound:
            return "未找到"
        case .missingExecutable:
            return "缺可执行文件"
        case .missingConfig:
            return "缺 config"
        }
    }

    var cliproxyRuntimePackageChipTint: Color {
        switch cliproxyRuntimeProbe.packageStatus {
        case .detected:
            return .indigo
        case .notFound, .missingExecutable, .missingConfig:
            return .red
        }
    }

    var cliproxyRuntimeServiceChipText: String {
        cliproxyRuntimeProbe.serviceRunning ? "8317 在线" : "未启动"
    }

    var cliproxyRuntimeServiceChipTint: Color {
        cliproxyRuntimeProbe.serviceRunning ? .green : .secondary
    }

    var cliproxyRuntimeManagementChipText: String {
        switch cliproxyRuntimeProbe.managementStatus {
        case .unknown:
            return cliproxyRuntimeProbe.serviceRunning ? "待检查" : "离线"
        case .waitingForKey:
            return "待填 key"
        case .keyValid(let authCount):
            return authCount > 0 ? "已验证 · \(authCount) 账号" : "已验证"
        case .keyInvalid:
            return "key 错误"
        case .unavailable:
            return "不可用"
        case .error:
            return "检查失败"
        }
    }

    var cliproxyRuntimeManagementChipTint: Color {
        switch cliproxyRuntimeProbe.managementStatus {
        case .unknown:
            return .secondary
        case .waitingForKey:
            return .orange
        case .keyValid:
            return .green
        case .keyInvalid, .unavailable, .error:
            return .red
        }
    }

    var cliproxyRuntimeSummaryText: String {
        switch cliproxyRuntimeProbe.packageStatus {
        case .notFound where !cliproxyRuntimeProbe.serviceRunning:
            return "当前还没有定位到 CLIProxy 发行包。自动探测默认会看 ~/Documents/AX/source/CLIProxyAPI-main，也可以直接粘贴发行包目录。"
        case .missingExecutable:
            return "目录存在，但不是可直接启动的发行包：缺少 cli-proxy-api 可执行文件。"
        case .missingConfig:
            return "目录存在，但不是完整发行包：缺少 config.yaml。"
        default:
            break
        }

        if cliproxyRuntimeProbe.serviceRunning {
            switch cliproxyRuntimeProbe.managementStatus {
            case .waitingForKey:
                return "本地 CLIProxy 已运行。填好 management key 后，Hub 就能验证账号列表并把已认证免费额度同步进库存池。"
            case .keyValid(let authCount):
                return authCount > 0
                    ? "本地 CLIProxy 已连通，management key 已验证，当前看到 \(authCount) 个已认证账号。可以继续发起 OAuth，或直接同步到 Hub。"
                    : "本地 CLIProxy 已连通，management key 已验证，但当前还没有已认证账号。可直接打开管理页做 OAuth 登录。"
            case .keyInvalid:
                return "本地 CLIProxy 已运行，但 Hub 里保存的 management key 不正确。修正后再检查即可。"
            case .unavailable:
                return "CLIProxy 服务已启动，但管理端接口当前不可用。请确认 config.yaml 里的 remote-management.secret-key 已设置。"
            case .error(let detail):
                return detail.isEmpty ? "CLIProxy 管理端探测失败。" : "CLIProxy 管理端探测失败：\(detail)"
            case .unknown:
                return "CLIProxy 服务已运行，Hub 会继续做轻量探测。"
            }
        }

        if cliproxyRuntimeProbe.packageStatus == .detected {
            return "发行包已经就位。点“启动本地节点”后，Hub 会直接接管这颗 CLIProxy，并在服务起来后继续验证 management key 与账号列表。"
        }

        return "本机节点尚未接入。"
    }

    var cliproxyRuntimeDisclosureSummarySegment: String {
        if cliproxyRuntimeLaunching {
            return "本地节点启动中"
        }
        if cliproxyRuntimeKeyRotating {
            return "正在轮换管理 key"
        }
        if cliproxyRuntimeConfigApplying {
            return "正在写入本地配置"
        }
        if cliproxyRuntimeConfigAudit.unresolvedCount > 0 {
            return "本地配置待修 \(cliproxyRuntimeConfigAudit.unresolvedCount) 项"
        }
        if cliproxyRuntimeProbe.serviceRunning {
            switch cliproxyRuntimeProbe.managementStatus {
            case .keyValid(let authCount):
                return authCount > 0 ? "本地节点在线 · \(authCount) 账号" : "本地节点在线"
            case .waitingForKey:
                return "本地节点在线 · 待填 key"
            case .keyInvalid:
                return "本地节点在线 · key 错误"
            case .unavailable:
                return "本地节点在线 · 管理端不可用"
            case .error:
                return "本地节点在线 · 检查失败"
            case .unknown:
                return "本地节点在线"
            }
        }
        if cliproxyRuntimeProbe.packageStatus == .detected {
            return "本地节点待启动"
        }
        return ""
    }
}
