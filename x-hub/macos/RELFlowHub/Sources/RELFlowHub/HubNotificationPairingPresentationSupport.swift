import Foundation
import SwiftUI
import RELFlowHubCore

func hubNotificationPairingRequestID(_ notification: HubNotification) -> String? {
    let key = (notification.dedupeKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard key.hasPrefix("pairing_request:") else { return nil }
    let value = key.dropFirst("pairing_request:".count).trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : String(value)
}

func hubNotificationPairingRequest(
    for notification: HubNotification,
    pendingRequests: [HubPairingRequest]
) -> HubPairingRequest? {
    guard let pairingRequestId = hubNotificationPairingRequestID(notification) else {
        return nil
    }
    return pendingRequests.first { request in
        request.pairingRequestId.trimmingCharacters(in: .whitespacesAndNewlines) == pairingRequestId
    }
}

func hubNotificationPairingContext(
    for notification: HubNotification,
    pendingRequests: [HubPairingRequest]
) -> HubNotificationPairingContext? {
    guard let pairingRequestId = hubNotificationPairingRequestID(notification) else {
        return nil
    }

    let liveRequest = hubNotificationPairingRequest(for: notification, pendingRequests: pendingRequests)
    let requestedAt = hubNotificationPairingRequestedAtText(
        request: liveRequest,
        fallbackTimestamp: notification.createdAt
    )

    if let liveRequest {
        return HubNotificationPairingContext(
            pairingRequestId: pairingRequestId,
            deviceTitle: HubFirstPairApprovalSummaryBuilder.displayDeviceTitle(for: liveRequest),
            appID: liveRequest.appId.trimmingCharacters(in: .whitespacesAndNewlines),
            claimedDeviceID: liveRequest.claimedDeviceId.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceAddress: HubFirstPairApprovalSummaryBuilder.sourceAddress(for: liveRequest),
            requestedScopesSummary: HubFirstPairApprovalSummaryBuilder.requestedScopesSummary(for: liveRequest),
            requestedAtText: requestedAt,
            queueStateText: HubUIStrings.Notifications.Pairing.pendingState,
            isLivePending: true
        )
    }

    return HubNotificationPairingContext(
        pairingRequestId: pairingRequestId,
        deviceTitle: HubUIStrings.Notifications.Pairing.unknownDevice,
        appID: "",
        claimedDeviceID: "",
        sourceAddress: HubUIStrings.Notifications.Pairing.fallbackSource,
        requestedScopesSummary: HubUIStrings.Notifications.Pairing.fallbackScopeSummary,
        requestedAtText: requestedAt,
        queueStateText: HubUIStrings.Notifications.Pairing.staleState,
        isLivePending: false
    )
}

func hubNotificationRecentPairingApprovalOutcome(
    pairingRequestId: String?,
    latestOutcome: HubPairingApprovalOutcomeSnapshot?,
    now: TimeInterval = Date().timeIntervalSince1970
) -> HubPairingApprovalOutcomeSnapshot? {
    let normalizedRequestId = pairingRequestId?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !normalizedRequestId.isEmpty else { return nil }
    guard let latestOutcome, latestOutcome.isFresh(at: now) else { return nil }
    let outcomeRequestId = latestOutcome.requestID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard outcomeRequestId == normalizedRequestId else { return nil }
    return latestOutcome
}

func hubNotificationPairingDisplayDeviceTitle(
    _ pairingContext: HubNotificationPairingContext,
    recentOutcome: HubPairingApprovalOutcomeSnapshot?
) -> String {
    HubGRPCClientEntry.normalizedStrings([
        recentOutcome?.deviceTitle ?? "",
        pairingContext.deviceTitle,
    ]).first ?? pairingContext.deviceTitle
}

func hubNotificationPairingStatusText(
    _ pairingContext: HubNotificationPairingContext,
    recentOutcome: HubPairingApprovalOutcomeSnapshot?
) -> String {
    let outcomeSummary = recentOutcome?.summaryText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !outcomeSummary.isEmpty {
        return outcomeSummary
    }
    return pairingContext.queueStateText
}

func hubNotificationPairingQueueStateLabel(
    _ pairingContext: HubNotificationPairingContext,
    recentOutcome: HubPairingApprovalOutcomeSnapshot?
) -> String {
    if let recentOutcome {
        return recentOutcome.titleText
    }
    return pairingContext.isLivePending ? "待处理" : "等待刷新"
}

func hubNotificationPairingStatusTint(
    _ pairingContext: HubNotificationPairingContext,
    recentOutcome: HubPairingApprovalOutcomeSnapshot?
) -> Color {
    if let recentOutcome {
        switch recentOutcome.kind {
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
    return pairingContext.isLivePending ? .orange : .secondary
}

func hubNotificationPairingStatusSystemImage(
    _ pairingContext: HubNotificationPairingContext,
    recentOutcome: HubPairingApprovalOutcomeSnapshot?
) -> String {
    if let recentOutcome {
        return recentOutcome.kind.systemImageName
    }
    return pairingContext.isLivePending ? "clock.badge.exclamationmark" : "arrow.clockwise"
}

func hubNotificationPairingRequestedAtText(
    request: HubPairingRequest?,
    fallbackTimestamp: TimeInterval
) -> String {
    let timestamp: TimeInterval
    if let request, request.createdAtMs > 0 {
        timestamp = Double(request.createdAtMs) / 1000.0
    } else {
        timestamp = fallbackTimestamp
    }
    let formatter = DateFormatter()
    formatter.dateFormat = HubUIStrings.Formatting.dateTimeWithoutSeconds
    return formatter.string(from: Date(timeIntervalSince1970: timestamp))
}
