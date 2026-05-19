import SwiftUI

struct XTControlSurfaceView: View {
    enum Section: String, CaseIterable, Identifiable {
        case overview
        case hub
        case models
        case skills
        case supervisor

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview:
                return "总览"
            case .hub:
                return "连接"
            case .models:
                return "模型"
            case .skills:
                return "技能"
            case .supervisor:
                return "Supervisor"
            }
        }
    }

    @EnvironmentObject private var navigationFocusStore: XTNavigationFocusStore

    let preferredSection: Section
    @Binding var selectedSection: Section

    init(
        preferredSection: Section = .overview,
        selectedSection: Binding<Section>
    ) {
        self.preferredSection = preferredSection
        _selectedSection = selectedSection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Picker("控制中心", selection: $selectedSection) {
                ForEach(Section.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            Group {
                switch selectedSection {
                case .overview:
                    XTControlOverviewSection(selectedSection: $selectedSection)
                case .hub:
                    SettingsView(embeddedInControlCenter: true)
                case .models:
                    ModelSettingsView(standaloneWindow: false)
                case .skills:
                    XTSkillLibrarySheet(embedded: true)
                case .supervisor:
                    SupervisorSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 900, minHeight: 700)
        .onAppear {
            syncFocusedSection()
        }
        .onChange(of: preferredSection) { section in
            selectedSection = section
        }
        .onChange(of: navigationFocusSnapshot.settingsFocusRequest?.nonce) { _ in
            selectedSection = .hub
        }
        .onChange(of: navigationFocusSnapshot.modelSettingsFocusRequest?.nonce) { _ in
            selectedSection = .models
        }
        .onChange(of: navigationFocusSnapshot.supervisorSettingsFocusRequest?.nonce) { _ in
            selectedSection = .supervisor
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("控制中心")
                .font(.title2.weight(.semibold))

            Text("系统级入口集中在这里；日常项目工作回到工作台。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private var navigationFocusSnapshot: XTNavigationFocusSnapshot {
        navigationFocusStore.snapshot
    }

    private func syncFocusedSection() {
        if navigationFocusSnapshot.modelSettingsFocusRequest != nil {
            selectedSection = .models
        } else if navigationFocusSnapshot.supervisorSettingsFocusRequest != nil {
            selectedSection = .supervisor
        } else if navigationFocusSnapshot.settingsFocusRequest != nil {
            selectedSection = .hub
        } else {
            selectedSection = preferredSection
        }
    }
}

private struct XTControlOverviewSection: View {
    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var hubConnectionStore: XTHubConnectionStore
    @EnvironmentObject private var globalHomeStore: XTGlobalHomeStore
    @EnvironmentObject private var controlSurfaceStore: XTControlSurfaceStore
    @Environment(\.openWindow) private var openWindow

    @Binding var selectedSection: XTControlSurfaceView.Section

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                PrimaryActionRail(
                    title: "主入口",
                    actions: overviewActions,
                    onTap: handleOverviewAction
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 220), spacing: 16),
                        GridItem(.flexible(minimum: 220), spacing: 16)
                    ],
                    alignment: .leading,
                    spacing: 16
                ) {
                    overviewCard(
                        title: "Hub",
                        badge: hubStatusBadge,
                        summary: hubStatusHeadline,
                        detail: hubStatusDetail,
                        actionTitle: hubConnectionSnapshot.interactive ? "查看连接" : "去连接",
                        systemImage: "link"
                    )

                    overviewCard(
                        title: "模型",
                        badge: hubConnectionSnapshot.interactive ? "ready" : "pending",
                        summary: roleAssignmentSummary,
                        detail: "角色绑定、模型替换和路由修复都在模型页处理。",
                        actionTitle: "打开模型",
                        systemImage: "brain.head.profile"
                    )

                    overviewCard(
                        title: "技能",
                        badge: "\(skillsSnapshot.installedSkillCount)",
                        summary: skillsHeadline,
                        detail: skillsDetail,
                        actionTitle: "打开技能",
                        systemImage: "square.stack.3d.up"
                    )

                    overviewCard(
                        title: "诊断",
                        badge: diagnosticsBadge,
                        summary: diagnosticsHeadline,
                        detail: diagnosticsDetail,
                        actionTitle: "看诊断",
                        systemImage: "waveform.path.ecg.rectangle"
                    )
                }
            }
            .padding(16)
        }
    }

    private var overviewActions: [PrimaryActionRailAction] {
        [
            PrimaryActionRailAction(
                id: "hub",
                title: hubConnectionSnapshot.interactive ? "查看 Hub 与诊断" : "连接 Hub",
                subtitle: hubConnectionSnapshot.interactive
                    ? "Hub 已接入；连接、授权和诊断都收口在这里"
                    : "先走 Hub 配对 / 连接主链",
                systemImage: hubConnectionSnapshot.interactive ? "link.circle.fill" : "link.badge.plus",
                style: .primary
            ),
            PrimaryActionRailAction(
                id: "models",
                title: "模型",
                subtitle: "统一编辑 Supervisor / Coder / Reviewer",
                systemImage: "brain.head.profile",
                style: .secondary
            ),
            PrimaryActionRailAction(
                id: "skills",
                title: "Skills",
                subtitle: "查看本地技能、governed skills 和导入状态",
                systemImage: "square.stack.3d.up",
                style: .secondary
            ),
            PrimaryActionRailAction(
                id: "supervisor",
                title: "Supervisor 设置",
                subtitle: "人格、语音、提醒和项目分配统一在这里",
                systemImage: "person.crop.circle.badge.checkmark",
                style: .secondary
            )
        ]
    }

    private var hubStatusBadge: String {
        if hubConnectionSnapshot.localConnected {
            return "local"
        }
        if hubConnectionSnapshot.remoteConnected {
            return "remote"
        }
        if hubConnectionSnapshot.remoteLinking {
            return "linking"
        }
        return "off"
    }

    private var hubStatusHeadline: String {
        if hubConnectionSnapshot.localConnected {
            return "Hub 当前走本机直连。"
        }
        if hubConnectionSnapshot.remoteConnected {
            return "Hub 当前走远端已配对路径。"
        }
        if hubConnectionSnapshot.remoteLinking {
            return "Hub 正在重连或恢复链路。"
        }
        return "Hub 还未接入，当前优先处理连接主链。"
    }

    private var hubStatusDetail: String {
        let summary = hubConnectionSnapshot.remoteSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            return summary
        }
        if hubConnectionSnapshot.interactive {
            return "如果只是想确认端口、配对和链路状态，直接切到 Hub 页即可。"
        }
        return "如果你已经有 Hub 邀请或固定目标主机，也可以直接打开 Hub 向导。"
    }

    private var roleAssignmentSummary: String {
        controlSurfaceSnapshot.roleAssignmentSummary
    }

    private var skillsHeadline: String {
        let snapshot = skillsSnapshot
        if snapshot.statusKind == .supported {
            return "Skills 兼容状态稳定。"
        }
        if snapshot.statusKind == .partial {
            return "当前仍有部分 skills 需要治理或补齐。"
        }
        if snapshot.statusKind == .blocked {
            return "Skills 当前有阻塞，建议先看 governed compatibility。"
        }
        return "还没有拿到可用的 skills 兼容快照。"
    }

    private var skillsDetail: String {
        let snapshot = skillsSnapshot
        let statusLine = snapshot.statusLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !statusLine.isEmpty {
            return statusLine
        }
        return "导入、启用和 governed surface 都统一收口到 Skills 页。"
    }

    private var diagnosticsBadge: String {
        hubConnectionSnapshot.interactive ? "live" : "fix"
    }

    private var diagnosticsHeadline: String {
        if hubConnectionSnapshot.interactive {
            return "诊断入口已与当前主链状态对齐。"
        }
        return "先修 Hub，再继续模型、授权和执行链路。"
    }

    private var diagnosticsDetail: String {
        if controlSurfaceSnapshot.bridgeEnabled {
            return "网络桥已启用；如果仍有异常，优先看 Hub 与诊断页的 failure code 和 repair entry。"
        }
        return "网络桥未启用或不可用时，不要在工作台猜原因，直接回 Hub / 诊断页处理。"
    }

    private func handleOverviewAction(_ action: PrimaryActionRailAction) {
        switch action.id {
        case "hub":
            selectedSection = .hub
            if !hubConnectionSnapshot.interactive {
                openWindow(id: "hub_setup")
            }
        case "models":
            selectedSection = .models
        case "skills":
            selectedSection = .skills
        case "supervisor":
            selectedSection = .supervisor
        default:
            break
        }
    }

    private func overviewCard(
        title: String,
        badge: String,
        summary: String,
        detail: String,
        actionTitle: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)

                Spacer(minLength: 8)

                Text(badge)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(Capsule())
            }

            Text(summary)
                .font(.subheadline.weight(.semibold))

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                switch title {
                case "Hub":
                    selectedSection = .hub
                case "模型":
                    selectedSection = .models
                case "技能":
                    selectedSection = .skills
                case "诊断":
                    selectedSection = .hub
                    appModel.requestSettingsFocus(sectionId: "diagnostics")
                default:
                    break
                }
            } label: {
                Label(actionTitle, systemImage: systemImage)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("XTControlOverviewSection requires xtAppModelReference")
        }
        return appModelReference
    }

    private var hubConnectionSnapshot: XTHubConnectionSnapshot {
        hubConnectionStore.snapshot
    }

    private var globalHomeSnapshot: XTGlobalHomeSnapshot {
        globalHomeStore.snapshot
    }

    private var skillsSnapshot: XTGlobalHomeSkillsSnapshot {
        globalHomeSnapshot.skills
    }

    private var controlSurfaceSnapshot: XTControlSurfaceSnapshot {
        controlSurfaceStore.snapshot
    }
}
