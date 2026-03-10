import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Role Routing") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("Role")
                                .foregroundStyle(.secondary)
                            Text("Model (Hub)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(.caption, design: .monospaced))

                        ForEach(AXRole.allCases) { role in
                            GridRow {
                                Text(role.rawValue)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 90, alignment: .leading)

                                TextField("model id", text: bindingModel(role))
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 320)
                            }
                        }
                    }
                    .padding(8)

                    Text("All roles run via Hub. Set a preferred model id per role if needed.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }

                GroupBox("Hub Pairing & Auto Reconnect") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("首次点击 One-Click Setup 会执行 discover → bootstrap → connect。后续会自动重连，并在 LAN 不可达时尝试互联网路由。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                Text("Pairing Port")
                                    .frame(width: 140, alignment: .leading)
                                TextField("50052", value: pairingPortBinding, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                            }
                            GridRow {
                                Text("gRPC Port")
                                    .frame(width: 140, alignment: .leading)
                                TextField("50051", value: grpcPortBinding, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                            }
                            GridRow {
                                Text("Internet Host")
                                    .frame(width: 140, alignment: .leading)
                                TextField("hub.example.com", text: internetHostBinding)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("axhubctl Path")
                                    .frame(width: 140, alignment: .leading)
                                TextField("auto detect", text: axhubctlPathBinding)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        HStack(spacing: 10) {
                            Button(appModel.hubRemoteLinking ? "Linking..." : "One-Click Setup") {
                                appModel.startHubOneClickSetup()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Reconnect Now") {
                                appModel.startHubReconnectOnly()
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Text(connectionStateLabel)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(connectionStateColor)
                        }

                        if !appModel.hubRemoteSummary.isEmpty {
                            Text("Summary: \(appModel.hubRemoteSummary)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ScrollView {
                            Text(appModel.hubRemoteLog.isEmpty ? "No remote link log yet." : appModel.hubRemoteLog)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(minHeight: 120, maxHeight: 200)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .padding(8)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 780, idealWidth: 820, minHeight: 640)
    }

    private func bindingModel(_ role: AXRole) -> Binding<String> {
        Binding(
            get: { appModel.settingsStore.settings.assignment(for: role).model ?? "" },
            set: { s in
                let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
                appModel.settingsStore.settings = appModel.settingsStore.settings.setting(role: role, providerKind: .hub, model: v.isEmpty ? nil : v)
                appModel.settingsStore.save()
            }
        )
    }

    private var pairingPortBinding: Binding<Int> {
        Binding(
            get: { appModel.hubPairingPort },
            set: { value in
                appModel.hubPairingPort = max(1, min(65_535, value))
                appModel.saveHubRemotePrefsNow()
            }
        )
    }

    private var grpcPortBinding: Binding<Int> {
        Binding(
            get: { appModel.hubGrpcPort },
            set: { value in
                appModel.hubGrpcPort = max(1, min(65_535, value))
                appModel.saveHubRemotePrefsNow()
            }
        )
    }

    private var internetHostBinding: Binding<String> {
        Binding(
            get: { appModel.hubInternetHost },
            set: { value in
                appModel.hubInternetHost = value
                appModel.saveHubRemotePrefsNow()
            }
        )
    }

    private var axhubctlPathBinding: Binding<String> {
        Binding(
            get: { appModel.hubAxhubctlPath },
            set: { value in
                appModel.hubAxhubctlPath = value
                appModel.saveHubRemotePrefsNow()
            }
        )
    }

    private var connectionStateLabel: String {
        if appModel.hubConnected {
            return "local"
        }
        if appModel.hubRemoteLinking {
            return "linking"
        }
        if appModel.hubRemoteConnected {
            switch appModel.hubRemoteRoute {
            case .lan:
                return "remote:lan"
            case .internet:
                return "remote:internet"
            case .internetTunnel:
                return "remote:tunnel"
            case .none:
                return "remote"
            }
        }
        return "disconnected"
    }

    private var connectionStateColor: Color {
        if appModel.hubConnected { return .secondary }
        if appModel.hubRemoteLinking { return .orange }
        if appModel.hubRemoteConnected { return .orange }
        return .red
    }
}
