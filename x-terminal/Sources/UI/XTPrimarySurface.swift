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
            return "工作台 / Coder"
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
            return "项目 Coder 聊天"
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
    @Environment(\.xtAppModelReference) private var appModelReference

    @Binding var selectedPrimarySurface: XTPrimarySurface
    @State private var displayedPrimarySurfaceOverride: XTPrimarySurface? = nil
    @State private var selectionCommitTask: Task<Void, Never>? = nil
    @State private var retainedProjectSidebarAfterSurfaceSwitch: Bool = false
    @State private var projectSidebarReleaseTask: Task<Void, Never>? = nil

    private static let selectionCommitDelayNanoseconds: UInt64 = 16_000_000
    private static let projectSidebarReleaseDelayNanoseconds: UInt64 = 120_000_000

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            navigationRail
                .padding(12)

            Divider()

            ZStack(alignment: .topLeading) {
                if displayedPrimarySurface == .work || retainedProjectSidebarAfterSurfaceSwitch {
                    ProjectSidebarView(isActive: displayedPrimarySurface == .work)
                        .opacity(displayedPrimarySurface == .work ? 1 : 0)
                        .allowsHitTesting(displayedPrimarySurface == .work)
                        .accessibilityHidden(displayedPrimarySurface != .work)
                        .zIndex(displayedPrimarySurface == .work ? 2 : 0)
                }

                if displayedPrimarySurface != .work {
                    surfaceContextPanel
                        .zIndex(3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            footerStatusCard
                .padding(12)
        }
        .frame(minWidth: 260, idealWidth: 280, maxWidth: 300, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: selectedPrimarySurface) { newValue in
            guard let override = displayedPrimarySurfaceOverride else { return }
            if override == newValue {
                displayedPrimarySurfaceOverride = nil
            } else {
                selectionCommitTask?.cancel()
                selectionCommitTask = nil
                displayedPrimarySurfaceOverride = nil
            }
        }
        .onDisappear {
            selectionCommitTask?.cancel()
            selectionCommitTask = nil
            projectSidebarReleaseTask?.cancel()
            projectSidebarReleaseTask = nil
        }
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
        XTPrimaryNavigationRail(
            displayedPrimarySurface: displayedPrimarySurface,
            select: select
        )
    }

    private var surfaceContextPanel: some View {
        XTPrimarySurfaceContextPanel(displayedPrimarySurface: displayedPrimarySurface)
    }

    private var footerStatusCard: some View {
        XTPrimarySidebarFooterStatusCard()
    }

    private var displayedPrimarySurface: XTPrimarySurface {
        displayedPrimarySurfaceOverride ?? selectedPrimarySurface
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("XTPrimarySidebarView requires xtAppModelReference")
        }
        return appModelReference
    }

    private func select(_ surface: XTPrimarySurface) {
        let previous = displayedPrimarySurface
        XTPerformanceTrace.event(
            "XT Sidebar Surface Tap",
            "\(previous.rawValue)->\(surface.rawValue)"
        )
        if previous == .work, surface != .work {
            retainProjectSidebarDuringSurfaceSwitch()
        } else if surface == .work {
            releaseRetainedProjectSidebar()
        }
        displayedPrimarySurfaceOverride = surface
        selectionCommitTask?.cancel()
        selectionCommitTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: Self.selectionCommitDelayNanoseconds)
            guard !Task.isCancelled else {
                selectionCommitTask = nil
                return
            }
            XTPerformanceTrace.event(
                "XT Sidebar Surface Commit",
                "\(previous.rawValue)->\(surface.rawValue)"
            )
            selectedPrimarySurface = surface
            if surface == .work, appModel.projectListStore.snapshot.selectedProjectId == nil {
                appModel.selectProject(AXProjectRegistry.globalHomeId)
            }
            selectionCommitTask = nil
        }
    }

    private func retainProjectSidebarDuringSurfaceSwitch() {
        retainedProjectSidebarAfterSurfaceSwitch = true
        projectSidebarReleaseTask?.cancel()
        XTPerformanceTrace.event(
            "XT Project Sidebar Retain Scheduled",
            "delay_ms=120"
        )
        projectSidebarReleaseTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: Self.projectSidebarReleaseDelayNanoseconds)
            guard !Task.isCancelled else {
                projectSidebarReleaseTask = nil
                return
            }
            guard displayedPrimarySurface != .work else {
                releaseRetainedProjectSidebar()
                return
            }
            retainedProjectSidebarAfterSurfaceSwitch = false
            projectSidebarReleaseTask = nil
            XTPerformanceTrace.event("XT Project Sidebar Retain Released")
        }
    }

    private func releaseRetainedProjectSidebar() {
        projectSidebarReleaseTask?.cancel()
        projectSidebarReleaseTask = nil
        retainedProjectSidebarAfterSurfaceSwitch = false
    }
}

private struct XTPrimaryNavigationRail: View {
    let displayedPrimarySurface: XTPrimarySurface
    let select: (XTPrimarySurface) -> Void

    var body: some View {
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
                                .foregroundStyle(displayedPrimarySurface == surface ? .white.opacity(0.88) : .secondary)
                        }

                        Spacer(minLength: 8)

                        XTPrimarySurfaceBadgeView(
                            surface: surface,
                            isSelected: displayedPrimarySurface == surface
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(displayedPrimarySurface == surface ? Color.accentColor : Color.clear)
                    )
                    .foregroundStyle(displayedPrimarySurface == surface ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct XTInactiveProjectSidebarPlaceholder: View {
    var body: some View {
        Color.clear
            .frame(minWidth: 220, maxWidth: 320, maxHeight: .infinity)
    }
}

private struct XTPrimarySurfaceBadgeView: View {
    let surface: XTPrimarySurface
    let isSelected: Bool

    var body: some View {
        switch surface {
        case .work:
            XTPrimaryProjectCountBadge(isSelected: isSelected)
        case .control:
            XTPrimaryHubStatusBadge(isSelected: isSelected)
        case .supervisor, .review:
            EmptyView()
        }
    }
}

private struct XTPrimaryProjectCountBadge: View {
    @EnvironmentObject private var projectListStore: XTProjectListStore

    let isSelected: Bool

    var body: some View {
        XTPrimarySurfaceBadgeText(
            text: "\(projectListStore.snapshot.projectCount)",
            isSelected: isSelected
        )
    }
}

private struct XTPrimaryHubStatusBadge: View {
    @EnvironmentObject private var hubConnectionStore: XTHubConnectionStore

    let isSelected: Bool

    var body: some View {
        XTPrimarySurfaceBadgeText(
            text: hubConnectionStore.snapshot.interactive ? "ready" : "fix",
            isSelected: isSelected
        )
    }
}

private struct XTPrimarySurfaceBadgeText: View {
    let text: String
    let isSelected: Bool

    var body: some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(isSelected ? .white.opacity(0.92) : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.18) : Color.secondary.opacity(0.12))
            )
    }
}

private struct XTPrimarySurfaceContextPanel: View {
    let displayedPrimarySurface: XTPrimarySurface

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox(displayedPrimarySurface.title) {
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

    private var surfaceContextText: String {
        switch displayedPrimarySurface {
        case .work:
            return "这里是项目 Coder 聊天入口：先选项目，再在右侧底部输入框让 Coder 改文件、跑测试或继续任务。"
        case .supervisor:
            return "处理总控、对话和队列。"
        case .review:
            return "集中看授权、审批和回归。"
        case .control:
            return "集中管理 Hub、模型、技能和诊断。"
        }
    }

    private var currentPriorityHeadline: String {
        switch displayedPrimarySurface {
        case .work:
            return "找 Coder 输入框"
        case .supervisor:
            return "看队列，再调度"
        case .review:
            return "处理待审查项"
        case .control:
            return "先修连接"
        }
    }

    private var currentPriorityDetail: String {
        switch displayedPrimarySurface {
        case .work:
            return "左边选具体项目；右侧主画布底部就是当前项目 Coder 的聊天框。Supervisor 任务请切到 Supervisor。"
        case .supervisor:
            return "适合多项目总控和调度。"
        case .review:
            return "有 grant、高风险技能或候选审查时优先来这里。"
        case .control:
            return "连接、模型、技能和诊断在这里切换。"
        }
    }
}

private struct XTPrimarySidebarFooterStatusCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                XTPrimarySidebarHubStatusChip()
                XTPrimarySidebarProjectCountChip()
            }

            XTPrimarySidebarSelectedProjectLabel()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct XTPrimarySidebarHubStatusChip: View {
    @EnvironmentObject private var hubConnectionStore: XTHubConnectionStore

    var body: some View {
        XTPrimarySidebarStatusChip(
            title: "Hub",
            value: hubStatusLabel,
            tint: hubStatusColor
        )
    }

    private var hubStatusLabel: String {
        XTHubConnectionPresentation.statusLabel(for: hubConnectionSnapshot)
    }

    private var hubConnectionSnapshot: XTHubConnectionSnapshot {
        hubConnectionStore.snapshot
    }

    private var hubStatusColor: Color {
        switch XTHubConnectionPresentation.statusTone(for: hubConnectionSnapshot) {
        case .localReady:
            return .green
        case .remoteReady, .linking:
            return .orange
        case .offline:
            return .red
        }
    }
}

private struct XTPrimarySidebarProjectCountChip: View {
    @EnvironmentObject private var projectListStore: XTProjectListStore

    var body: some View {
        XTPrimarySidebarStatusChip(
            title: "Projects",
            value: "\(projectListStore.snapshot.projectCount)",
            tint: .secondary
        )
    }
}

private struct XTPrimarySidebarSelectedProjectLabel: View {
    @EnvironmentObject private var projectListStore: XTProjectListStore

    var body: some View {
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

    private var selectedProjectName: String? {
        projectListStore.snapshot.selectedProjectName
    }
}

private struct XTPrimarySidebarStatusChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
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
