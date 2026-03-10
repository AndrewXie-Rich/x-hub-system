import SwiftUI

struct HubSetupWizardView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hub 首次连接向导")
                .font(.title2)

            Text("三段式：Discover → Bootstrap → Connect。首次一键完成配对，后续自动重连并支持 LAN/Internet/Tunnel 切换。")
                .foregroundStyle(.secondary)

            GroupBox("连接参数") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Pairing Port")
                            .frame(width: 130, alignment: .leading)
                        TextField("50052", value: pairingPortBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    GridRow {
                        Text("gRPC Port")
                            .frame(width: 130, alignment: .leading)
                        TextField("50051", value: grpcPortBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    GridRow {
                        Text("Internet Host (optional)")
                            .frame(width: 130, alignment: .leading)
                        TextField("hub.example.com", text: internetHostBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("axhubctl Path")
                            .frame(width: 130, alignment: .leading)
                        TextField("auto detect", text: axhubctlPathBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(8)

                HStack(spacing: 10) {
                    Button("Auto Fill Path + Ports") {
                        appModel.autoFillHubSetupPathAndPorts()
                    }
                    .buttonStyle(.bordered)
                    .disabled(appModel.hubPortAutoDetectRunning || appModel.hubRemoteLinking)

                    Button(appModel.hubPortAutoDetectRunning ? "Detecting..." : "Auto Detect Ports") {
                        appModel.autoDetectHubPorts()
                    }
                    .buttonStyle(.bordered)
                    .disabled(appModel.hubPortAutoDetectRunning || appModel.hubRemoteLinking)

                    if !appModel.hubPortAutoDetectMessage.isEmpty {
                        Text(appModel.hubPortAutoDetectMessage)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
            }

            GroupBox("三段式进度") {
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: progressValue, total: 3.0)

                    stepRow(
                        title: "1) Discover",
                        subtitle: "发现 Hub（局域网优先）",
                        state: appModel.hubSetupDiscoverState
                    )
                    stepRow(
                        title: "2) Bootstrap",
                        subtitle: "配对 + 证书/凭据下发",
                        state: appModel.hubSetupBootstrapState
                    )
                    stepRow(
                        title: "3) Connect",
                        subtitle: "连接并启用自动重连（LAN/Internet/Tunnel）",
                        state: appModel.hubSetupConnectState
                    )
                }
                .padding(8)
            }

            HStack(spacing: 10) {
                Button(appModel.hubRemoteLinking ? "Linking..." : "Start One-Click Setup") {
                    appModel.startHubOneClickSetup()
                }
                .buttonStyle(.borderedProminent)

                Button("Reconnect Only") {
                    appModel.startHubReconnectOnly()
                }
                .buttonStyle(.bordered)

                Button("Reset Pairing + One-Click") {
                    appModel.resetPairingStateAndOneClickSetup()
                }
                .buttonStyle(.bordered)
                .disabled(appModel.hubPortAutoDetectRunning)

                Spacer()

                Text(connectionLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(connectionColor)
            }

            if !appModel.hubSetupFailureCode.isEmpty {
                Text("失败原因码：\(appModel.hubSetupFailureCode)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.red)
                if let hint = failureHint(for: appModel.hubSetupFailureCode) {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if !appModel.hubRemoteSummary.isEmpty {
                Text("Summary: \(appModel.hubRemoteSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GroupBox("连接日志") {
                ScrollView {
                    Text(appModel.hubRemoteLog.isEmpty ? "No log yet." : appModel.hubRemoteLog)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 180)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(8)
            }
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 640)
    }

    @ViewBuilder
    private func stepRow(title: String, subtitle: String, state: HubSetupStepState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: iconName(for: state))
                .foregroundStyle(iconColor(for: state))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(labelText(for: state))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(iconColor(for: state))
        }
    }

    private var progressValue: Double {
        stepScore(appModel.hubSetupDiscoverState)
            + stepScore(appModel.hubSetupBootstrapState)
            + stepScore(appModel.hubSetupConnectState)
    }

    private func stepScore(_ state: HubSetupStepState) -> Double {
        switch state {
        case .idle:
            return 0.0
        case .running:
            return 0.4
        case .success, .failed, .skipped:
            return 1.0
        }
    }

    private func iconName(for state: HubSetupStepState) -> String {
        switch state {
        case .idle:
            return "circle"
        case .running:
            return "clock.arrow.circlepath"
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .skipped:
            return "arrow.right.circle.fill"
        }
    }

    private func iconColor(for state: HubSetupStepState) -> Color {
        switch state {
        case .idle:
            return .secondary
        case .running:
            return .orange
        case .success:
            return .green
        case .failed:
            return .red
        case .skipped:
            return .gray
        }
    }

    private func labelText(for state: HubSetupStepState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .running:
            return "running"
        case .success:
            return "ok"
        case .failed:
            return "failed"
        case .skipped:
            return "skipped"
        }
    }

    private var connectionLabel: String {
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

    private var connectionColor: Color {
        if appModel.hubConnected { return .secondary }
        if appModel.hubRemoteLinking { return .orange }
        if appModel.hubRemoteConnected { return .orange }
        return .red
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

    private func failureHint(for rawCode: String) -> String? {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch code {
        case "source_ip_not_allowed":
            return "当前 Hub 处于 LAN/VPN 限制模式。首次配对请在同一局域网或 VPN 下进行，或在 Hub 侧放宽允许的 CIDR。"
        case "forbidden":
            return "Hub 拒绝了当前来源地址。请检查 Hub 的 allowed CIDRs 与当前网络是否匹配。"
        case "hub_unreachable", "connection_refused":
            return "当前 Host 无法连通 Hub 端口。请确认填写的是 Hub 电脑 IP（不是路由器地址，如 192.168.x.1），并检查 50053/50051 端口。"
        case "discovery_failed":
            return "未发现 Hub。可先填写 Internet Host，再重试 One-Click。"
        default:
            return nil
        }
    }
}
