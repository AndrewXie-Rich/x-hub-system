import SwiftUI
import RELFlowHubCore

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
    var quotaSignalText: String
    var quotaSignalTint: Color
    var usablePoolCount: Int
    var poolCount: Int
    var readyAccountCount: Int
    var totalAccountCount: Int
    var runtimeLoadedInstanceCount: Int
    var roleSummaries: [ModelsDrawerRoleRouteSummary]

    var body: some View {
        ModelsDrawerPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.indigo.opacity(0.14))
                        Image(systemName: "rectangle.3.group")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.indigo)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text("Portfolio / Quota / Runtime")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("\(usablePoolCount)/\(poolCount) 资源池可用")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(usablePoolCount > 0 ? Color.green : Color.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background((usablePoolCount > 0 ? Color.green : Color.secondary).opacity(0.12))
                                .clipShape(Capsule())
                        }

                        Text("模型资源组合")
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)

                        Text("先看资源池、额度和三个任务角色的路线；具体绑定和测试在下方任务路由里操作。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 10)
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

                if !roleSummaries.isEmpty {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 150), spacing: 8),
                            GridItem(.flexible(minimum: 150), spacing: 8),
                            GridItem(.flexible(minimum: 150), spacing: 8)
                        ],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(roleSummaries) { summary in
                            ModelsDrawerRoleRouteSummaryCard(summary: summary)
                        }
                    }
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

struct ModelsDrawerRoleRouteSummaryCard: View {
    var summary: ModelsDrawerRoleRouteSummary

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(summary.statusColor.opacity(0.12))
                Image(systemName: summary.systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(summary.statusColor)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(summary.title)
                        .font(.caption.weight(.semibold))
                    Text(summary.statusText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(summary.statusColor)
                }
                Text(summary.modelName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(summary.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(summary.statusColor.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(summary.statusColor.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
