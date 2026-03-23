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

    @EnvironmentObject private var appModel: AppModel
    @State private var selectedTab: Tab

    init(preferredTab: Tab = .supervisor) {
        self.preferredTab = preferredTab
        _selectedTab = State(initialValue: preferredTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Supervisor Control Center")
                    .font(.title2.weight(.semibold))

                Text("Supervisor 设置和 AI 模型设置统一收口在这里；默认只保留这一个稳定入口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .frame(minWidth: 900, minHeight: 700)
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
    }

    private func syncPreferredTab() {
        if appModel.modelSettingsFocusRequest != nil {
            selectedTab = .models
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
