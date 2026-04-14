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
    }

    let preferredTab: Tab
    let embedded: Bool
    let onClose: (() -> Void)?

    @EnvironmentObject private var appModel: AppModel
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Supervisor Control Center")
                        .font(.title2.weight(.semibold))

                    Text(
                        embedded
                            ? "Supervisor 设置和 AI 模型设置统一收口在当前主窗口里；默认只保留这一个稳定入口。"
                            : "Supervisor 设置和 AI 模型设置统一收口在这里；默认只保留这一个稳定入口。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if let onClose {
                    Button("关闭") {
                        onClose()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Picker("Control Center Tab", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

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
        .onChange(of: appModel.modelSettingsFocusRequest?.nonce) { nonce in
            guard nonce != nil else { return }
            selectedTab = .models
        }
        .onChange(of: appModel.supervisorSettingsFocusRequest?.nonce) { nonce in
            guard nonce != nil else { return }
            selectedTab = .supervisor
        }
    }

    private func syncPreferredTab() {
        if appModel.modelSettingsFocusRequest != nil {
            selectedTab = .models
        } else if appModel.supervisorSettingsFocusRequest != nil {
            selectedTab = .supervisor
        } else {
            selectedTab = preferredTab
        }
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
