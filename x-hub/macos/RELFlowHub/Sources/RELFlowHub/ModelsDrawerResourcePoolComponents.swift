import SwiftUI
import RELFlowHubCore

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
