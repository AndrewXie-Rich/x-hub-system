import SwiftUI

enum XTPrimarySurface: String, CaseIterable, Identifiable {
    case work
    case supervisor
    case review
    case control

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work:
            return "工作台"
        case .supervisor:
            return "Supervisor"
        case .review:
            return "审查"
        case .control:
            return "设置"
        }
    }

    var subtitle: String {
        switch self {
        case .work:
            return "项目与对话"
        case .supervisor:
            return "总控与队列"
        case .review:
            return "授权与回归"
        case .control:
            return "Hub、模型、技能"
        }
    }

    var systemImage: String {
        switch self {
        case .work:
            return "rectangle.stack.fill"
        case .supervisor:
            return "person.3.fill"
        case .review:
            return "checkmark.shield.fill"
        case .control:
            return "slider.horizontal.3"
        }
    }
}

struct XTPrimarySidebarView: View {
    @EnvironmentObject private var appModel: AppModel

    @Binding var selectedPrimarySurface: XTPrimarySurface

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            navigationRail
                .padding(12)

            Divider()

            Group {
                if selectedPrimarySurface == .work {
                    ProjectSidebarView()
                } else {
                    surfaceContextPanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            footerStatusCard
                .padding(12)
        }
        .frame(minWidth: 260, idealWidth: 280, maxWidth: 300, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("X-Terminal")
                .font(.headline)

            Text("工作、总控、审查和设置分开处理。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var navigationRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(XTPrimarySurface.allCases) { surface in
                Button {
                    select(surface)
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: surface.systemImage)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(surface.title)
                                .font(.subheadline.weight(.semibold))

                            Text(surface.subtitle)
                                .font(.caption)
                                .foregroundStyle(selectedPrimarySurface == surface ? .white.opacity(0.88) : .secondary)
                        }

                        Spacer(minLength: 8)

                        if let badge = badgeText(for: surface) {
                            Text(badge)
                                .font(.caption2.monospaced())
                                .foregroundStyle(selectedPrimarySurface == surface ? .white.opacity(0.92) : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(
                                            selectedPrimarySurface == surface
                                                ? Color.white.opacity(0.18)
                                                : Color.secondary.opacity(0.12)
                                        )
                                )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selectedPrimarySurface == surface ? Color.accentColor : Color.clear)
                    )
                    .foregroundStyle(selectedPrimarySurface == surface ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var surfaceContextPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox(selectedPrimarySurface.title) {
                    Text(surfaceContextText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }

                GroupBox("当前重点") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(currentPriorityHeadline)
                            .font(.subheadline.weight(.semibold))

                        Text(currentPriorityDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footerStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                statusChip(
                    title: "Hub",
                    value: hubStatusLabel,
                    tint: hubStatusColor
                )

                statusChip(
                    title: "Projects",
                    value: "\(appModel.sortedProjects.count)",
                    tint: .secondary
                )
            }

            if let selectedProjectName {
                Text("当前项目：\(selectedProjectName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("当前项目：未选中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var surfaceContextText: String {
        switch selectedPrimarySurface {
        case .work:
            return "只放项目、聊天和终端。"
        case .supervisor:
            return "处理总控、对话和队列。"
        case .review:
            return "集中看授权、审批和回归。"
        case .control:
            return "集中管理 Hub、模型、技能和诊断。"
        }
    }

    private var currentPriorityHeadline: String {
        switch selectedPrimarySurface {
        case .work:
            return appModel.hubInteractive ? "继续当前项目" : "先完成 Hub 连接"
        case .supervisor:
            return "看队列，再调度"
        case .review:
            return "处理待审查项"
        case .control:
            return "先修连接"
        }
    }

    private var currentPriorityDetail: String {
        switch selectedPrimarySurface {
        case .work:
            if appModel.hubInteractive {
                return "项目列表和主画布保留在这里。"
            }
            return "Hub 没接通时，先去设置完成连接。"
        case .supervisor:
            return "适合多项目总控和调度。"
        case .review:
            return "有 grant、高风险技能或候选审查时优先来这里。"
        case .control:
            return "连接、模型、技能和诊断在这里切换。"
        }
    }

    private var selectedProjectName: String? {
        guard let selectedProjectId = appModel.selectedProjectId,
              selectedProjectId != AXProjectRegistry.globalHomeId else {
            return nil
        }
        return appModel.registry.project(for: selectedProjectId)?.displayName
    }

    private var hubStatusLabel: String {
        if appModel.hubConnected {
            return "local"
        }
        if appModel.hubRemoteConnected {
            return "remote"
        }
        if appModel.hubRemoteLinking {
            return "linking"
        }
        return "off"
    }

    private var hubStatusColor: Color {
        if appModel.hubConnected {
            return .green
        }
        if appModel.hubRemoteConnected {
            return .orange
        }
        if appModel.hubRemoteLinking {
            return .orange
        }
        return .red
    }

    private func badgeText(for surface: XTPrimarySurface) -> String? {
        switch surface {
        case .work:
            return "\(appModel.sortedProjects.count)"
        case .supervisor:
            return nil
        case .review:
            return nil
        case .control:
            return appModel.hubInteractive ? "ready" : "fix"
        }
    }

    private func select(_ surface: XTPrimarySurface) {
        selectedPrimarySurface = surface
        if surface == .work, appModel.selectedProjectId == nil {
            appModel.selectedProjectId = AXProjectRegistry.globalHomeId
        }
    }

    private func statusChip(
        title: String,
        value: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }
}
