import SwiftUI
import AppKit
import RELFlowHubCore

struct FirstPairApprovalCard: View {
    let summary: HubFirstPairApprovalSummary
    let onApproveRecommended: () -> Void
    let onCustomize: () -> Void
    let onReview: () -> Void
    let onDeny: () -> Void

    private var isAuthenticating: Bool {
        summary.state == .authenticating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                HubTonedActionChip(
                    title: "首次配对",
                    systemName: "wifi",
                    tint: .blue,
                    width: nil,
                    help: "这里只显示同一局域网内的首次配对请求。"
                )
                HubTonedActionChip(
                    title: "本机确认",
                    systemName: "lock.shield",
                    tint: .green,
                    width: nil,
                    help: "批准前一定会要求 Touch ID / Face ID / 本机密码确认。"
                )
                if isAuthenticating {
                    HubTonedActionChip(
                        title: "正在认证",
                        systemName: "touchid",
                        tint: .orange,
                        width: nil,
                        help: "Hub 正在等待本机 owner 验证完成。"
                    )
                }
                Spacer(minLength: 12)
                Text(summary.pendingCount == 1 ? "1 个待处理" : "\(summary.pendingCount) 个待处理")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(summary.headline)
                .font(.title3.weight(.semibold))

            Text(summary.leadDeviceTitle)
                .font(.headline)

            Text(summary.statusLine)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                infoPill(label: "申请范围", value: summary.requestedScopesSummary)
                infoPill(label: "来源", value: summary.sourceAddress)
                infoPill(label: "接入面", value: "同网首次配对")
                infoPill(label: "建议", value: "先最小接入")
            }

            if let queueHint = summary.queueHint,
               !queueHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(queueHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let recentOutcome = summary.recentOutcome {
                FirstPairApprovalOutcomeBanner(outcome: recentOutcome)
            }

            HStack(spacing: 10) {
                HubFilledActionChipButton(
                    title: summary.approveRecommendedButtonTitle,
                    systemName: isAuthenticating ? "hourglass" : "checkmark.shield",
                    tint: .green,
                    disabled: isAuthenticating,
                    width: nil,
                    help: "按推荐最小接入先完成首配。",
                    action: onApproveRecommended
                )

                HubNeutralActionChipButton(
                    title: summary.customizeButtonTitle,
                    systemName: "slider.horizontal.3",
                    width: nil,
                    help: "打开策略页，自定义这台设备的首配边界。",
                    action: onCustomize
                )

                HubNeutralActionChipButton(
                    title: summary.reviewButtonTitle,
                    systemName: "list.bullet.clipboard",
                    width: nil,
                    help: "打开首次配对审批队列。",
                    action: onReview
                )

                Button(action: onDeny) {
                    HubActionChipContent(
                        title: summary.denyButtonTitle,
                        systemName: "xmark",
                        foreground: isAuthenticating ? .secondary : .red,
                        background: isAuthenticating ? Color.white.opacity(0.06) : Color.red.opacity(0.10),
                        border: isAuthenticating ? Color.white.opacity(0.08) : Color.red.opacity(0.24),
                        width: nil
                    )
                }
                .buttonStyle(.plain)
                .disabled(isAuthenticating)
                .help("拒绝最新的首次配对请求。")

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func infoPill(label: String, value: String) -> some View {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedValue.isEmpty {
            HStack(spacing: 4) {
                Text(label)
                    .foregroundStyle(.secondary)
                Text(trimmedValue)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
        }
    }
}

struct FirstPairApprovalOutcomeCard: View {
    @EnvironmentObject var store: HubStore
    let outcome: HubPairingApprovalOutcomeSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HubTonedActionChip(
                title: outcome.titleText,
                systemName: outcome.kind.systemImageName,
                tint: bannerTint,
                width: nil,
                help: "最近一次首次配对审批结果。"
            )
            FirstPairApprovalOutcomeBanner(outcome: outcome)
            if outcome.kind == .approved {
                HStack(spacing: 10) {
                    HubNeutralActionChipButton(
                        title: pairedDeviceActionTitle,
                        systemName: "slider.horizontal.3",
                        width: nil,
                        help: pairedDeviceActionHelp
                    ) {
                        store.openPairedDevicesSettings(deviceID: outcome.deviceID)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var bannerTint: Color {
        switch outcome.kind {
        case .approved:
            return .green
        case .denied:
            return .red
        case .ownerAuthenticationCancelled:
            return .orange
        case .ownerAuthenticationFailed, .approvalFailed, .denyFailed:
            return .yellow
        }
    }

    private var pairedDeviceActionTitle: String {
        let deviceID = outcome.deviceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return deviceID.isEmpty ? "打开设备列表" : "管理这台设备"
    }

    private var pairedDeviceActionHelp: String {
        let deviceID = outcome.deviceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if deviceID.isEmpty {
            return "打开 Hub 设置里的已配对设备列表。"
        }
        return "直接打开这台已配对设备的策略页，继续调整网页抓取、付费 AI 或预算边界。"
    }
}

struct FirstPairApprovalOutcomeBanner: View {
    let outcome: HubPairingApprovalOutcomeSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: outcome.kind.systemImageName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(iconTint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(outcome.titleText)
                    .font(.subheadline.weight(.semibold))
                Text(outcome.summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(outcome.nextStepText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let detail = outcome.detailText,
                   !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   detail != outcome.summaryText {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(backgroundTint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(backgroundTint.opacity(0.20), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var iconTint: Color {
        switch outcome.kind {
        case .approved:
            return .green
        case .denied:
            return .red
        case .ownerAuthenticationCancelled:
            return .orange
        case .ownerAuthenticationFailed, .approvalFailed, .denyFailed:
            return .yellow
        }
    }

    private var backgroundTint: Color {
        switch outcome.kind {
        case .approved:
            return .green
        case .denied:
            return .red
        case .ownerAuthenticationCancelled:
            return .orange
        case .ownerAuthenticationFailed, .approvalFailed, .denyFailed:
            return .yellow
        }
    }
}

struct FirstPairApprovalQueueSheet: View {
    @EnvironmentObject var store: HubStore
    @Environment(\.dismiss) private var dismiss

    let reviewRequest: (HubPairingRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("首次配对审批队列")
                        .font(.headline)
                    Text("只显示首配需要的最少信息。真正批准前仍会先做 Touch ID / Face ID / 本机密码验证。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(store.pendingPairingRequests.count == 1 ? "1 个待处理" : "\(store.pendingPairingRequests.count) 个待处理")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Button("关闭") { dismiss() }
            }

            if store.pendingPairingRequests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前没有待处理的首次配对请求。")
                        .font(.subheadline.weight(.semibold))
                    Text("如果 XT 再次从同一 Wi-Fi 发起首配，这里会自动出现。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(store.pendingPairingRequests.prefix(20)) { request in
                            PairingRequestRow(req: request) { selected in
                                reviewRequest(selected)
                            }
                            .environmentObject(store)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 440)
    }
}
