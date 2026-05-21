import SwiftUI
import RELFlowHubCore

struct ModelsDrawerUsageWindowDisplay: Identifiable {
    var id: String
    var title: String
    var percentText: String
    var resetText: String
    var progress: Double
    var tint: Color
}

struct ModelsDrawerPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ModelsDrawerStatusPill: View {
    var title: String
    var systemName: String
    var tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemName)
                .imageScale(.small)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(tint.opacity(0.10))
        .clipShape(Capsule())
    }
}

struct ModelsDrawerIconOnlyButton: View {
    var title: String
    var systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .imageScale(.medium)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(title)
        .accessibilityLabel(Text(title))
    }
}

struct ModelsDrawerActionChip: View {
    var title: String
    var systemName: String
    var tint: Color
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ModelsDrawerActionChipLabel(
                title: title,
                systemName: systemName,
                tint: tint,
                disabled: disabled
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct ModelsDrawerActionChipLabel: View {
    var title: String
    var systemName: String
    var tint: Color
    var disabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .imageScale(.small)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(disabled ? .secondary : tint)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(tint.opacity(disabled ? 0.05 : 0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(tint.opacity(disabled ? 0.10 : 0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct ModelsDrawerNoticeLine: View {
    var systemName: String
    var text: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemName)
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(text)
                .font(.caption2)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ModelsDrawerSectionHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct ModelsDrawerIconButton: View {
    var title: String
    var systemName: String
    var disabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .imageScale(.small)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(title)
        .accessibilityLabel(Text(title))
        .disabled(disabled)
    }
}

struct ModelsDrawerMetricPill: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ModelsDrawerPortfolioSignalCell: View {
    var title: String
    var value: String
    var systemName: String
    var tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .imageScale(.small)
                .foregroundStyle(tint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ModelsDrawerUsageWindowMiniBar: View {
    var window: ModelsDrawerUsageWindowDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(window.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(window.percentText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(window.tint)
            }
            ProgressView(value: window.progress)
                .tint(window.tint)
            if !window.resetText.isEmpty {
                Text(window.resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ModelsDrawerChipList: View {
    var chips: [String]
    var tint: Color

    var body: some View {
        if chips.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                ForEach(Array(chips.prefix(4)), id: \.self) { chip in
                    Text(chip)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.10))
                        .foregroundStyle(tint)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

struct ModelsDrawerEmptyStateLine: View {
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.dashed")
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ModelsDrawerRouteMatrixCell: View {
    var row: ModelsDrawerRouteMatrixRow

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(row.statusColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.title)
                        .font(.caption.weight(.semibold))
                    Text(row.statusText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(row.statusColor)
                }
                Text(row.modelName)
                    .font(.caption)
                    .lineLimit(1)
                Text([row.provider, row.reason].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ModelsDrawerPortfolioOverviewPanel: View {
    @Binding var routeTask: HubTaskType
    @Binding var routeAllowAutoLoad: Bool

    var decision: HubTaskRouteDecision
    var tint: Color
    var routeDetail: String
    var quotaSignalText: String
    var quotaSignalTint: Color
    var usablePoolCount: Int
    var poolCount: Int
    var readyAccountCount: Int
    var totalAccountCount: Int
    var runtimeLoadedInstanceCount: Int
    var preferenceLabel: String
    var availableModels: [HubModel]
    var routeCheckFeedback: String
    var routeCheckModelId: String
    var trialStatus: ModelTrialStatus?
    var onTestRoute: () -> Void
    var onPinRoute: () -> Void
    var onSetPreferred: (String?) -> Void

    private var hasRoute: Bool {
        !decision.modelId.isEmpty
    }

    var body: some View {
        ModelsDrawerPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tint.opacity(0.14))
                        Image(systemName: hasRoute ? "point.topleft.down.curvedto.point.bottomright.up" : "exclamationmark.triangle.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text("Route / Quota / Runtime")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(routeTask.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(tint.opacity(0.12))
                                .clipShape(Capsule())
                        }

                        Text(hasRoute ? decision.modelName : "暂无可用模型")
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)

                        Text(routeDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 10)

                    VStack(alignment: .trailing, spacing: 8) {
                        Picker("任务", selection: $routeTask) {
                            ForEach(HubTaskType.allCases) { task in
                                Text(task.label).tag(task)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 224)

                        Toggle("按需加载", isOn: $routeAllowAutoLoad)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        signalCells
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 120), spacing: 8),
                            GridItem(.flexible(minimum: 120), spacing: 8)
                        ],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        signalCells
                    }
                }

                HStack(spacing: 8) {
                    ModelsDrawerActionChip(
                        title: "测试当前路由",
                        systemName: "waveform.path.ecg",
                        tint: .teal,
                        disabled: !hasRoute,
                        action: onTestRoute
                    )

                    ModelsDrawerActionChip(
                        title: "设为 \(routeTask.label) 默认",
                        systemName: "pin.fill",
                        tint: .indigo,
                        disabled: !hasRoute,
                        action: onPinRoute
                    )

                    Menu {
                        Button("Auto") {
                            onSetPreferred(nil)
                        }
                        Divider()
                        ForEach(availableModels) { model in
                            Button(model.name) {
                                onSetPreferred(model.id)
                            }
                        }
                    } label: {
                        ModelsDrawerActionChipLabel(
                            title: preferenceLabel,
                            systemName: "slider.horizontal.3",
                            tint: .secondary,
                            disabled: false
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }

                if let trialStatus {
                    ModelTrialStatusLine(status: trialStatus)
                } else if !routeCheckFeedback.isEmpty && routeCheckModelId == decision.modelId {
                    ModelsDrawerNoticeLine(
                        systemName: "waveform.path.ecg",
                        text: routeCheckFeedback,
                        tint: .teal
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var signalCells: some View {
        ModelsDrawerPortfolioSignalCell(
            title: "资源池",
            value: "\(usablePoolCount)/\(poolCount)",
            systemName: "square.stack.3d.up",
            tint: usablePoolCount > 0 ? .green : .secondary
        )
        ModelsDrawerPortfolioSignalCell(
            title: "Key",
            value: "\(readyAccountCount)/\(max(totalAccountCount, 0))",
            systemName: "key.horizontal",
            tint: readyAccountCount > 0 ? .green : .secondary
        )
        ModelsDrawerPortfolioSignalCell(
            title: "额度",
            value: quotaSignalText,
            systemName: "chart.line.uptrend.xyaxis",
            tint: quotaSignalTint
        )
        ModelsDrawerPortfolioSignalCell(
            title: "本地常驻",
            value: "\(runtimeLoadedInstanceCount)",
            systemName: "memorychip",
            tint: runtimeLoadedInstanceCount > 0 ? .green : .secondary
        )
    }
}

struct ModelsDrawerTaskRouteControlRow: View {
    var task: HubTaskType
    var decision: HubTaskRouteDecision
    var preferredModelId: String
    var tint: Color
    var systemName: String
    var purposeText: String
    var detailText: String
    var stateText: String
    var preferenceLabel: String
    var availableModels: [HubModel]
    var routeCheckFeedback: String
    var routeCheckModelId: String
    var trialStatus: ModelTrialStatus?
    var onSetPreferred: (String?) -> Void
    var onTest: () -> Void

    private var hasRoute: Bool {
        !decision.modelId.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.12))
                    Image(systemName: systemName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(task.label)
                            .font(.subheadline.weight(.semibold))
                        Text(preferredModelId.isEmpty ? "Auto" : "Pinned")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(preferredModelId.isEmpty ? Color.secondary : Color.indigo)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background((preferredModelId.isEmpty ? Color.secondary : Color.indigo).opacity(0.10))
                            .clipShape(Capsule())
                    }

                    Text(hasRoute ? decision.modelName : "未路由")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)

                    Text("\(purposeText) · \(detailText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                Text(hasRoute ? (decision.willAutoLoad ? "按需加载" : stateText) : "阻断")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(tint.opacity(0.10))
                    .clipShape(Capsule())

                Menu {
                    Button("Auto") {
                        onSetPreferred(nil)
                    }
                    Divider()
                    ForEach(availableModels) { model in
                        Button(model.name) {
                            onSetPreferred(model.id)
                        }
                    }
                } label: {
                    ModelsDrawerActionChipLabel(
                        title: preferenceLabel,
                        systemName: "slider.horizontal.3",
                        tint: .secondary,
                        disabled: false
                    )
                }
                .buttonStyle(.plain)

                ModelsDrawerIconButton(
                    title: "测试 \(task.label)",
                    systemName: "waveform.path.ecg",
                    disabled: !hasRoute,
                    action: onTest
                )
            }

            if let trialStatus {
                ModelTrialStatusLine(status: trialStatus)
            } else if !routeCheckFeedback.isEmpty && routeCheckModelId == decision.modelId {
                ModelsDrawerNoticeLine(
                    systemName: "waveform.path.ecg",
                    text: routeCheckFeedback,
                    tint: .teal
                )
            }
        }
    }
}

struct ModelsDrawerResourcePoolRow: View {
    var pool: ModelsDrawerResourcePoolSummary
    var quotaTint: Color
    var usageWindows: [ModelsDrawerUsageWindowDisplay]
    var onDiscoverLocalModels: () -> Void
    var onAddLocalModel: () -> Void
    var onAddRemoteModel: () -> Void

    var body: some View {
        ModelsDrawerPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(pool.statusColor.opacity(0.13))
                        Image(systemName: pool.systemName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(pool.statusColor)
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(pool.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Text(pool.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 8)

                    Text(pool.statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(pool.statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(pool.statusColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    ModelsDrawerMetricPill(title: "账号", value: pool.accountText, tint: pool.statusColor)
                    ModelsDrawerMetricPill(title: "额度", value: pool.quotaText, tint: quotaTint)
                    ModelsDrawerMetricPill(title: "模型", value: pool.modelText, tint: .indigo)
                }

                if !usageWindows.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(usageWindows) { window in
                            ModelsDrawerUsageWindowMiniBar(window: window)
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 8) {
                        ModelsDrawerChipList(chips: pool.models, tint: pool.statusColor)
                        Spacer(minLength: 8)
                        actionButtons
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ModelsDrawerChipList(chips: pool.models, tint: pool.statusColor)
                        actionButtons
                    }
                }

                if !pool.detailText.isEmpty {
                    Text(pool.detailText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if pool.isLocal {
            HStack(spacing: 8) {
                ModelsDrawerActionChip(
                    title: "发现本地模型",
                    systemName: "magnifyingglass",
                    tint: .indigo,
                    action: onDiscoverLocalModels
                )
                ModelsDrawerActionChip(
                    title: "添加本地模型",
                    systemName: "plus",
                    tint: .green,
                    action: onAddLocalModel
                )
            }
        } else {
            ModelsDrawerActionChip(
                title: "添加远程模型",
                systemName: "plus",
                tint: .indigo,
                action: onAddRemoteModel
            )
        }
    }
}

struct ModelsDrawerLocalModelRow: View {
    var model: HubModel
    var stateText: String
    var stateColor: Color
    var detail: String
    var tags: [String]
    var trialStatus: ModelTrialStatus?
    var healthScanInProgress: Bool
    var onQuickCheck: () -> Void
    var onPin: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: model.state == .loaded ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(stateColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(stateText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(stateColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(stateColor.opacity(0.12))
                        .clipShape(Capsule())
                }
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ModelsDrawerChipList(chips: tags, tint: .indigo)

                if let trialStatus {
                    ModelTrialStatusLine(status: trialStatus)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ModelsDrawerIconButton(
                    title: "轻量预检",
                    systemName: "heart.text.square",
                    disabled: healthScanInProgress,
                    action: onQuickCheck
                )

                ModelsDrawerIconButton(
                    title: "设为当前任务默认",
                    systemName: "pin",
                    disabled: false,
                    action: onPin
                )
            }
            .fixedSize()
        }
    }
}

struct ModelsDrawerLibraryRow: View {
    var item: ModelsDrawerLibraryItem
    var trialStatus: ModelTrialStatus?
    var onPin: () -> Void
    var onTest: () -> Void
    var onSetRemoteEnabled: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: item.isLocal ? "internaldrive" : "cloud")
                .foregroundStyle(item.isLocal ? Color.indigo : Color.blue)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(item.statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(item.statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(item.statusColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text("\(item.provider) · \(item.detail)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ModelsDrawerChipList(chips: item.tags, tint: item.isLocal ? .indigo : .blue)

                if let trialStatus {
                    ModelTrialStatusLine(status: trialStatus)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ModelsDrawerIconButton(
                    title: "设为当前任务默认",
                    systemName: "pin",
                    disabled: !item.isReady,
                    action: onPin
                )
                ModelsDrawerIconButton(
                    title: "测试",
                    systemName: "waveform.path.ecg",
                    disabled: !item.isReady,
                    action: onTest
                )
                if let remoteEntry = item.remoteEntry {
                    if remoteEntry.enabled {
                        ModelsDrawerIconButton(
                            title: "停用",
                            systemName: "pause",
                            disabled: false
                        ) {
                            onSetRemoteEnabled(false)
                        }
                    } else {
                        ModelsDrawerIconButton(
                            title: "启用",
                            systemName: "play",
                            disabled: !item.isReady
                        ) {
                            onSetRemoteEnabled(true)
                        }
                    }
                }
            }
            .fixedSize()
        }
    }
}
