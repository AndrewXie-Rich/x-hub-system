import SwiftUI

struct SupervisorControlCenterView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case supervisor
        case models

        var id: String { rawValue }

        var label: String {
            switch self {
            case .supervisor:
                return "Supervisor"
            case .models:
                return "AI 模型"
            }
        }

        var summary: String {
            switch self {
            case .supervisor:
                return "人格、语音、节奏"
            case .models:
                return "角色模型与路由"
            }
        }

        var iconName: String {
            switch self {
            case .supervisor:
                return "person.3.sequence"
            case .models:
                return "brain.head.profile"
            }
        }
    }

    let preferredTab: Tab
    let embedded: Bool
    let onClose: (() -> Void)?

    @EnvironmentObject private var navigationFocusStore: XTNavigationFocusStore
    @State private var selectedTab: Tab

    init(
        preferredTab: Tab = .supervisor,
        embedded: Bool = false,
        onClose: (() -> Void)? = nil
    ) {
        self.preferredTab = preferredTab
        self.embedded = embedded
        self.onClose = onClose
        _selectedTab = State(initialValue: preferredTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controlCenterHeader
            Divider()

            Group {
                switch selectedTab {
                case .supervisor:
                    SupervisorSettingsView()
                case .models:
                    ModelSettingsView()
                }
            }
        }
        .frame(
            minWidth: embedded ? nil : 900,
            maxWidth: .infinity,
            minHeight: embedded ? nil : 700,
            maxHeight: .infinity
        )
        .onAppear {
            syncPreferredTab()
        }
        .onChange(of: preferredTab) { _ in
            syncPreferredTab()
        }
        .onChange(of: navigationFocusSnapshot.modelSettingsFocusRequest?.nonce) { nonce in
            guard nonce != nil else { return }
            selectedTab = .models
        }
        .onChange(of: navigationFocusSnapshot.supervisorSettingsFocusRequest?.nonce) { nonce in
            guard nonce != nil else { return }
            selectedTab = .supervisor
        }
    }

    private var controlCenterHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Supervisor Control Center")
                        .font(.title2.weight(.semibold))

                    Text("Supervisor 设置与 AI 模型的统一入口。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                if let onClose {
                    Button("关闭") {
                        onClose()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                }
            }

            controlCenterTabBar
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var controlCenterTabBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(Tab.allCases) { tab in
                    controlCenterTabButton(tab)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Tab.allCases) { tab in
                    controlCenterTabButton(tab)
                }
            }
        }
    }

    private func controlCenterTabButton(_ tab: Tab) -> some View {
        let selected = selectedTab == tab

        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 9) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.label)
                        .font(.caption.weight(.semibold))
                    Text(tab.summary)
                        .font(.caption2)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(tab.summary)
    }

    private func syncPreferredTab() {
        if navigationFocusSnapshot.modelSettingsFocusRequest != nil {
            selectedTab = .models
        } else if navigationFocusSnapshot.supervisorSettingsFocusRequest != nil {
            selectedTab = .supervisor
        } else {
            selectedTab = preferredTab
        }
    }

    private var navigationFocusSnapshot: XTNavigationFocusSnapshot {
        navigationFocusStore.snapshot
    }
}

extension SupervisorManager.SupervisorWindowSheet {
    var controlCenterTab: SupervisorControlCenterView.Tab {
        switch self {
        case .supervisorSettings:
            return .supervisor
        case .modelSettings:
            return .models
        }
    }
}

struct SupervisorToolWindowRootView: View {
    let preferredTab: SupervisorControlCenterView.Tab

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SupervisorControlCenterView(
            preferredTab: preferredTab,
            embedded: false,
            onClose: { dismiss() }
        )
    }
}
