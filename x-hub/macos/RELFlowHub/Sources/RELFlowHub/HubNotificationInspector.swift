import AppKit
import SwiftUI
import RELFlowHubCore

struct HubNotificationInspector: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: HubStore

    let notification: HubNotification

    @State private var approvingPairingRequest: HubPairingRequest?

    private var presentation: HubNotificationPresentation {
        hubNotificationPresentation(for: notification)
    }

    private var pairingContext: HubNotificationPairingContext? {
        hubNotificationPairingContext(for: notification, pendingRequests: store.pendingPairingRequests)
    }

    private var pairingRequest: HubPairingRequest? {
        hubNotificationPairingRequest(for: notification, pendingRequests: store.pendingPairingRequests)
    }

    private var recentPairingOutcome: HubPairingApprovalOutcomeSnapshot? {
        hubNotificationRecentPairingApprovalOutcome(
            pairingRequestId: hubNotificationPairingRequestID(notification),
            latestOutcome: store.latestPairingApprovalOutcome
        )
    }

    private var inspectorTitle: String {
        if let pairingContext {
            return hubNotificationPairingDisplayDeviceTitle(pairingContext, recentOutcome: recentPairingOutcome)
        }
        let title = presentation.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty { return title }
        return notification.title
    }

    private var createdAtText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = HubUIStrings.Formatting.dateTimeWithoutSeconds
        return formatter.string(from: Date(timeIntervalSince1970: notification.createdAt))
    }

    private var summaryText: String {
        hubNotificationSummaryText(notification)
    }

    private var quickCopyAction: HubNotificationQuickCopyAction? {
        hubNotificationQuickCopyAction(notification)
    }

    private var shouldShowDedicatedSummaryCopy: Bool {
        guard let quickCopyAction else { return true }
        return quickCopyAction.text != summaryText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(inspectorTitle)
                        .font(.headline)
                    Text(HubUIStrings.Notifications.Inspector.sourceAndTime(source: hubNotificationDisplaySource(notification), time: createdAtText))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let badge = presentation.badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.10))
                        .clipShape(Capsule())
                }
            }

            if let pairingContext {
                pairingInspectorCard(pairingContext, recentOutcome: recentPairingOutcome)
                pairingActionBar(pairingContext, recentOutcome: recentPairingOutcome)
            } else {
                genericInspectorSections
                genericActionBar
            }
        }
        .padding(18)
        .frame(width: 560)
        .sheet(item: $approvingPairingRequest) { req in
            PairingApprovalPolicySheet(req: req) { approval in
                store.approvePairingRequest(req, approval: approval)
                store.markRead(notification.id)
            }
        }
    }

    @ViewBuilder
    private var genericInspectorSections: some View {
        if let executionSurface = presentation.executionSurface, !executionSurface.isEmpty {
            notificationInspectorCard(
                title: HubUIStrings.Notifications.Inspector.executionSurfaceTitle,
                systemName: "location",
                tint: .purple,
                text: executionSurface
            )
        }

        if let nextStep = presentation.recommendedNextStep, !nextStep.isEmpty {
            notificationInspectorCard(
                title: HubUIStrings.Notifications.Inspector.nextStepTitle,
                systemName: "arrow.turn.down.right",
                tint: .orange,
                text: nextStep
            )
        }

        if !presentation.detailFacts.isEmpty {
            detailFactsCard(presentation.detailFacts)
        }

        if let suggestion = hubNotificationReplySuggestion(notification), !suggestion.isEmpty {
            notificationInspectorCard(
                title: HubUIStrings.Notifications.Inspector.suggestedReplyTitle,
                systemName: "text.bubble",
                tint: .mint,
                text: suggestion
            )
        }
    }

    private var genericActionBar: some View {
        HStack(spacing: 10) {
            if presentation.primaryAction == .openTarget,
               let label = presentation.primaryLabel {
                HubNeutralActionChipButton(
                    title: label,
                    systemName: presentation.primarySystemImage,
                    width: nil,
                    help: label
                ) {
                    store.openNotificationAction(notification)
                    store.markRead(notification.id)
                    dismiss()
                }
            }

            if isGrantPendingNotification {
                HubNeutralActionChipButton(
                    title: grantPendingDeviceActionTitle,
                    systemName: "slider.horizontal.3",
                    width: nil,
                    help: grantPendingDeviceActionHelp
                ) {
                    store.openPairedDevicesSettings(
                        deviceID: grantPendingDeviceID,
                        capabilityKey: grantPendingCapabilityFocusKey
                    )
                    store.markRead(notification.id)
                    dismiss()
                }
            }

            if let quickCopyAction {
                HubNeutralActionChipButton(
                    title: quickCopyAction.label,
                    systemName: "doc.on.doc",
                    width: nil,
                    help: quickCopyAction.label
                ) {
                    copyNotificationText(quickCopyAction.text)
                }
            }

            if shouldShowDedicatedSummaryCopy {
                HubNeutralActionChipButton(
                    title: HubUIStrings.Notifications.Inspector.copySummary,
                    systemName: "text.alignleft",
                    width: nil,
                    help: HubUIStrings.Notifications.Inspector.copySummary
                ) {
                    copyNotificationText(summaryText)
                }
            }

            HubNeutralActionChipButton(
                title: notification.unread ? HubUIStrings.Menu.NotificationRow.markRead : HubUIStrings.Menu.NotificationRow.markUnread,
                systemName: notification.unread ? "checkmark.circle" : "arrow.uturn.backward.circle",
                width: nil,
                help: notification.unread ? HubUIStrings.Menu.NotificationRow.markRead : HubUIStrings.Menu.NotificationRow.markUnread
            ) {
                toggleRead()
            }

            Spacer()

            dismissNotificationButton
        }
    }

    private var isGrantPendingNotification: Bool {
        notification.title.contains("grant_pending")
            || presentation.detailFacts.contains(where: { fact in
                fact.label == HubUIStrings.Notifications.Facts.issueType
                    && fact.value == HubUIStrings.Notifications.Lane.waitingGrant
            })
            || presentation.detailFacts.contains(where: { fact in
                fact.label == HubUIStrings.Notifications.Facts.denyReason
                    && fact.value == HubUIStrings.Notifications.Lane.waitingGrant
            })
    }

    private var grantPendingDeviceActionHelp: String {
        let capability = hubNotificationGrantPendingCapabilityName(presentation.detailFacts)
        let deviceID = grantPendingDeviceID
        if let capability, !capability.isEmpty, let deviceID, !deviceID.isEmpty {
            return "直接打开设备 \(deviceID) 的策略页，继续调整“\(capability)”边界。"
        }
        if let capability, !capability.isEmpty {
            return "打开 Hub 设置里的已配对设备，继续调整这台 XT 的“\(capability)”边界。"
        }
        return "打开 Hub 设置里的已配对设备，检查这台 XT 的网页抓取或付费 AI 边界。"
    }

    private var grantPendingDeviceActionTitle: String {
        let capability = hubNotificationGrantPendingCapabilityName(presentation.detailFacts) ?? ""
        return capability.isEmpty ? "管理设备能力" : "管理\(capability)"
    }

    private var grantPendingCapabilityFocusKey: String? {
        hubNormalizedPairedDeviceCapabilityFocusKey(
            hubNotificationGrantPendingCapabilityName(presentation.detailFacts)
        )
    }

    private var grantPendingDeviceID: String? {
        hubNotificationGrantPendingDeviceID(presentation.detailFacts)
    }

    private func pairingActionBar(
        _ pairingContext: HubNotificationPairingContext,
        recentOutcome: HubPairingApprovalOutcomeSnapshot?
    ) -> some View {
        let liveRequest = pairingRequest
        let isAuthenticating = liveRequest.map(store.isPairingApprovalInFlight) ?? false
        return HStack(spacing: 10) {
            if pairingContext.isLivePending, let liveRequest {
                HubFilledActionChipButton(
                    title: isAuthenticating ? "批准中…" : HubUIStrings.MainPanel.PairingRequest.approveRecommended,
                    systemName: isAuthenticating ? "hourglass" : "checkmark.shield",
                    tint: .green,
                    disabled: isAuthenticating,
                    width: nil,
                    help: "按推荐最小接入先完成首配。"
                ) {
                    store.approvePairingRequestRecommended(liveRequest)
                    store.markRead(notification.id)
                }

                HubNeutralActionChipButton(
                    title: HubUIStrings.MainPanel.PairingRequest.customizePolicy,
                    systemName: "slider.horizontal.3",
                    width: nil,
                    help: "打开策略页，自定义这台设备的首配边界。"
                ) {
                    approvingPairingRequest = liveRequest
                    store.markRead(notification.id)
                }

                Button {
                    store.denyPairingRequest(liveRequest)
                    store.markRead(notification.id)
                } label: {
                    HubActionChipContent(
                        title: HubUIStrings.MainPanel.PairingRequest.deny,
                        systemName: "xmark",
                        foreground: isAuthenticating ? .secondary : .red,
                        background: isAuthenticating ? Color.white.opacity(0.06) : Color.red.opacity(0.10),
                        border: isAuthenticating ? Color.white.opacity(0.08) : Color.red.opacity(0.24),
                        width: nil
                    )
                }
                .buttonStyle(.plain)
                .disabled(isAuthenticating)
            } else {
                HubTonedActionChip(
                    title: hubNotificationPairingQueueStateLabel(pairingContext, recentOutcome: recentOutcome),
                    systemName: hubNotificationPairingStatusSystemImage(pairingContext, recentOutcome: recentOutcome),
                    tint: hubNotificationPairingStatusTint(pairingContext, recentOutcome: recentOutcome),
                    width: nil,
                    help: hubNotificationPairingStatusText(pairingContext, recentOutcome: recentOutcome)
                )
            }

            HubNeutralActionChipButton(
                title: notification.unread ? HubUIStrings.Menu.NotificationRow.markRead : HubUIStrings.Menu.NotificationRow.markUnread,
                systemName: notification.unread ? "checkmark.circle" : "arrow.uturn.backward.circle",
                width: nil,
                help: notification.unread ? HubUIStrings.Menu.NotificationRow.markRead : HubUIStrings.Menu.NotificationRow.markUnread
            ) {
                toggleRead()
            }

            Spacer()

            dismissNotificationButton
        }
    }

    private var dismissNotificationButton: some View {
        Button {
            store.dismiss(notification.id)
            dismiss()
        } label: {
            HubActionChipContent(
                title: HubUIStrings.Menu.NotificationRow.dismiss,
                systemName: "xmark.circle",
                foreground: .red,
                background: Color.red.opacity(0.10),
                border: Color.red.opacity(0.24),
                width: nil
            )
        }
        .buttonStyle(.plain)
        .help(HubUIStrings.Notifications.Inspector.removeNotification)
        .accessibilityLabel(Text(HubUIStrings.Notifications.Inspector.removeNotification))
    }

    @ViewBuilder
    private func notificationInspectorCard(
        title: String,
        systemName: String,
        tint: Color,
        text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailFactsCard(_ facts: [HubNotificationFact]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(.teal)
                Text(HubUIStrings.Notifications.Inspector.extraInfoTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.teal)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(facts.enumerated()), id: \.offset) { entry in
                    let fact = entry.element
                    HStack(alignment: .top, spacing: 10) {
                        Text(fact.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 108, alignment: .leading)
                        Text(fact.value)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(12)
            .background(Color.teal.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func pairingInspectorCard(
        _ pairingContext: HubNotificationPairingContext,
        recentOutcome: HubPairingApprovalOutcomeSnapshot?
    ) -> some View {
        let statusText = hubNotificationPairingStatusText(pairingContext, recentOutcome: recentOutcome)
        let deviceTitle = hubNotificationPairingDisplayDeviceTitle(pairingContext, recentOutcome: recentOutcome)
        let statusLabel = hubNotificationPairingQueueStateLabel(pairingContext, recentOutcome: recentOutcome)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "link.badge.plus")
                    .foregroundStyle(.blue)
                Text(HubUIStrings.Notifications.Pairing.detailTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
            }

            HStack(alignment: .top, spacing: 8) {
                HubTonedActionChip(
                    title: HubUIStrings.Notifications.Presentation.Pairing.badge,
                    systemName: "link.badge.plus",
                    tint: .blue,
                    width: nil,
                    help: "这是一条需要你确认的设备首配请求。"
                )
                HubTonedActionChip(
                    title: HubUIStrings.Notifications.Pairing.localNetworkBadge,
                    systemName: "wifi",
                    tint: .teal,
                    width: nil,
                    help: "当前只展示同一局域网内的首次配对请求。"
                )
                HubTonedActionChip(
                    title: HubUIStrings.Notifications.Pairing.ownerVerificationBadge,
                    systemName: "lock.shield",
                    tint: .green,
                    width: nil,
                    help: HubUIStrings.Notifications.Pairing.ownerVerificationHint
                )
                if pairingContext.isLivePending {
                    HubTonedActionChip(
                        title: HubUIStrings.Notifications.Pairing.pendingBadge,
                        systemName: "clock.badge.exclamationmark",
                        tint: .orange,
                        width: nil,
                        help: statusText
                    )
                } else if recentOutcome != nil {
                    HubTonedActionChip(
                        title: statusLabel,
                        systemName: hubNotificationPairingStatusSystemImage(pairingContext, recentOutcome: recentOutcome),
                        tint: hubNotificationPairingStatusTint(pairingContext, recentOutcome: recentOutcome),
                        width: nil,
                        help: statusText
                    )
                }
                Spacer(minLength: 0)
            }

            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)

            if pairingContext.isLivePending {
                Text("建议先按推荐最小接入完成首配；后续确实用到付费模型或网页抓取时再单独放开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                pairingFactRow(HubUIStrings.Notifications.Pairing.deviceTitle, deviceTitle)
                if !pairingContext.appID.isEmpty {
                    pairingFactRow(HubUIStrings.Notifications.Pairing.appIDTitle, pairingContext.appID)
                }
                if !pairingContext.claimedDeviceID.isEmpty {
                    pairingFactRow(HubUIStrings.Notifications.Pairing.claimedDeviceTitle, pairingContext.claimedDeviceID)
                }
                if pairingContext.isLivePending || recentOutcome == nil {
                    pairingFactRow(HubUIStrings.Notifications.Pairing.sourceTitle, pairingContext.sourceAddress)
                    pairingFactRow(HubUIStrings.Notifications.Pairing.scopesTitle, pairingContext.requestedScopesSummary)
                }
                pairingFactRow(HubUIStrings.Notifications.Pairing.requestedAtTitle, pairingContext.requestedAtText)
                pairingFactRow(HubUIStrings.Notifications.Pairing.requestIDTitle, pairingContext.pairingRequestId)
                pairingFactRow(HubUIStrings.Notifications.Pairing.queueStateTitle, statusLabel)
            }

            Text(HubUIStrings.Notifications.Pairing.ownerVerificationHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.blue.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func pairingFactRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func toggleRead() {
        if notification.unread {
            store.markRead(notification.id)
        } else {
            var updated = notification
            updated.unread = true
            store.push(updated)
        }
    }

    private func copyNotificationText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
