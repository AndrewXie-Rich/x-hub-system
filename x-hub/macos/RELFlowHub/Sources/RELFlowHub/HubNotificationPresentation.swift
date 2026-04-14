import AppKit
import SwiftUI
import RELFlowHubCore

private final class HubNotificationPresentationCacheEntry: NSObject {
    let presentation: HubNotificationPresentation

    init(presentation: HubNotificationPresentation) {
        self.presentation = presentation
    }
}

private enum HubNotificationPresentationCache {
    nonisolated(unsafe) static let cache: NSCache<NSString, HubNotificationPresentationCacheEntry> = {
        let cache = NSCache<NSString, HubNotificationPresentationCacheEntry>()
        cache.countLimit = 512
        return cache
    }()

    static func key(for notification: HubNotification) -> NSString {
        [
            notification.id,
            notification.source,
            notification.title,
            notification.body,
            notification.dedupeKey ?? "",
            notification.actionURL ?? "",
            notification.unread ? "1" : "0",
        ].joined(separator: "\u{1F}").trimmingCharacters(in: .whitespacesAndNewlines) as NSString
    }
}

enum HubNotificationPresentationGroup: Equatable {
    case actionRequired
    case advisory
    case background
}

enum HubNotificationPrimaryAction: Equatable {
    case inspect
    case openTarget
    case none
}

struct HubNotificationFact: Equatable {
    var label: String
    var value: String
}

struct HubNotificationQuickCopyAction: Equatable {
    var label: String
    var text: String
}

struct HubNotificationPresentation {
    var group: HubNotificationPresentationGroup
    var badge: String?
    var subline: String
    var relevance: String?
    var executionSurface: String? = nil
    var primaryLabel: String?
    var primarySystemImage: String
    var primaryAction: HubNotificationPrimaryAction
    var detailFacts: [HubNotificationFact] = []
    var displayTitle: String? = nil
    var recommendedNextStep: String? = nil
}

struct HubNotificationPairingContext: Equatable {
    var pairingRequestId: String
    var deviceTitle: String
    var appID: String
    var claimedDeviceID: String
    var sourceAddress: String
    var requestedScopesSummary: String
    var requestedAtText: String
    var queueStateText: String
    var isLivePending: Bool
}

func hubNotificationPresentation(for notification: HubNotification) -> HubNotificationPresentation {
    let cacheKey = HubNotificationPresentationCache.key(for: notification)
    if let cached = HubNotificationPresentationCache.cache.object(forKey: cacheKey) {
        return cached.presentation
    }

    let presentation = uncachedHubNotificationPresentation(for: notification)
    HubNotificationPresentationCache.cache.setObject(
        HubNotificationPresentationCacheEntry(presentation: presentation),
        forKey: cacheKey
    )
    return presentation
}

private func uncachedHubNotificationPresentation(for notification: HubNotification) -> HubNotificationPresentation {
    let facts = hubNotificationBodyFacts(notification)
    if let pairingRequestId = hubNotificationPairingRequestID(notification), !pairingRequestId.isEmpty {
        return HubNotificationPresentation(
            group: .actionRequired,
            badge: HubUIStrings.Notifications.Presentation.Pairing.badge,
            subline: hubNotificationFriendlySubline(notification, facts: facts, fallback: HubUIStrings.Notifications.Presentation.Pairing.fallbackSubline),
            relevance: HubUIStrings.Notifications.Presentation.Pairing.relevance,
            executionSurface: HubUIStrings.Notifications.Presentation.Pairing.executionSurface,
            primaryLabel: HubUIStrings.Notifications.Presentation.Generic.viewDetail,
            primarySystemImage: "link.badge.plus",
            primaryAction: .inspect,
            detailFacts: hubNotificationUserVisibleFacts(facts),
            displayTitle: HubUIStrings.Notifications.Presentation.Pairing.displayTitle,
            recommendedNextStep: HubUIStrings.Notifications.Presentation.Pairing.nextStep
        )
    }

    let source = notification.source.trimmingCharacters(in: .whitespacesAndNewlines)
    let displaySource = hubNotificationDisplaySource(notification)
    let title = notification.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let body = notification.body.trimmingCharacters(in: .whitespacesAndNewlines)
    let fromTerminal = hubNotificationSourceIsTerminal(notification)

    if source == "FAtracker" {
        let faSummary = hubNotificationFATrackerSummary(notification)
        return HubNotificationPresentation(
            group: .actionRequired,
            badge: HubUIStrings.Notifications.Presentation.FATracker.badge,
            subline: faSummary.subline,
            relevance: HubUIStrings.Notifications.Presentation.FATracker.relevance,
            executionSurface: HubUIStrings.Notifications.Presentation.FATracker.executionSurface,
            primaryLabel: HubUIStrings.Notifications.Presentation.FATracker.openLabel,
            primarySystemImage: "arrow.up.forward.app",
            primaryAction: .openTarget,
            detailFacts: hubNotificationUserVisibleFacts(faSummary.detailFacts),
            displayTitle: hubNotificationFATrackerDisplayTitle(notification),
            recommendedNextStep: HubUIStrings.Notifications.Presentation.FATracker.nextStep
        )
    }

    if fromTerminal || hubNotificationUsesTerminalDeepLink(notification) {
        if title.contains("grant_pending")
            || title.localizedCaseInsensitiveContains(HubUIStrings.Notifications.Presentation.Terminal.permissionRequestKeyword)
            || body.localizedCaseInsensitiveContains("grant_pending") {
            return HubNotificationPresentation(
                group: .actionRequired,
                badge: HubUIStrings.Notifications.Presentation.Terminal.badge,
                subline: hubNotificationFriendlySubline(notification, facts: facts),
                relevance: HubUIStrings.Notifications.Presentation.Terminal.grantRelevance,
                executionSurface: HubUIStrings.Notifications.Presentation.Terminal.executionSurface,
                primaryLabel: HubUIStrings.Notifications.Presentation.Terminal.grantPrimaryLabel,
                primarySystemImage: "doc.text.magnifyingglass",
                primaryAction: .inspect,
                detailFacts: hubNotificationUserVisibleFacts(facts),
                displayTitle: hubNotificationLaneIncidentDisplayTitle(title: title, facts: facts),
                recommendedNextStep: hubNotificationLaneIncidentNextStep(title: title, facts: facts)
            )
        }

        if hubNotificationLaneIncidentSummary(title: title, facts: facts) != nil {
            return HubNotificationPresentation(
                group: .advisory,
                badge: HubUIStrings.Notifications.Presentation.Terminal.badge,
                subline: hubNotificationFriendlySubline(notification, facts: facts),
                relevance: HubUIStrings.Notifications.Presentation.Terminal.advisoryRelevance,
                executionSurface: HubUIStrings.Notifications.Presentation.Terminal.executionSurface,
                primaryLabel: hubNotificationLaneIncidentPrimaryLabel(title: title, facts: facts),
                primarySystemImage: "doc.text.magnifyingglass",
                primaryAction: .inspect,
                detailFacts: hubNotificationUserVisibleFacts(facts),
                displayTitle: hubNotificationLaneIncidentDisplayTitle(title: title, facts: facts),
                recommendedNextStep: hubNotificationLaneIncidentNextStep(title: title, facts: facts)
            )
        }

        if title.hasPrefix(HubUIStrings.Notifications.MissingContext.titlePrefix) || body.contains(HubUIStrings.Notifications.MissingContext.bodyMarker) {
            return HubNotificationPresentation(
                group: .advisory,
                badge: HubUIStrings.Notifications.Presentation.Terminal.missingContextBadge,
                subline: hubNotificationFriendlySubline(notification, facts: facts),
                relevance: HubUIStrings.Notifications.Presentation.Terminal.missingContextRelevance,
                executionSurface: HubUIStrings.Notifications.Presentation.Terminal.executionSurface,
                primaryLabel: HubUIStrings.Notifications.Presentation.Terminal.missingContextPrimaryLabel,
                primarySystemImage: "text.bubble",
                primaryAction: .inspect,
                detailFacts: hubNotificationUserVisibleFacts(facts),
                displayTitle: hubNotificationMissingContextDisplayTitle(notification),
                recommendedNextStep: HubUIStrings.Notifications.Presentation.Terminal.missingContextNextStep
            )
        }

        if title.contains(HubUIStrings.Notifications.Presentation.Terminal.silentKeyword) || title.contains(HubUIStrings.Notifications.Presentation.Terminal.heartbeatKeyword) {
            return HubNotificationPresentation(
                group: .background,
                badge: HubUIStrings.Notifications.Presentation.Terminal.heartbeatBadge,
                subline: hubNotificationFriendlySubline(notification, facts: facts),
                relevance: HubUIStrings.Notifications.Presentation.Terminal.heartbeatRelevance,
                executionSurface: HubUIStrings.Notifications.Presentation.Terminal.heartbeatExecutionSurface,
                primaryLabel: HubUIStrings.Notifications.Presentation.Terminal.heartbeatPrimaryLabel,
                primarySystemImage: "waveform.path.ecg",
                primaryAction: .inspect,
                detailFacts: hubNotificationUserVisibleFacts(facts),
                displayTitle: HubUIStrings.Notifications.Presentation.Terminal.heartbeatDisplayTitle,
                recommendedNextStep: HubUIStrings.Notifications.Presentation.Terminal.heartbeatNextStep
            )
        }

        return HubNotificationPresentation(
            group: .advisory,
            badge: HubUIStrings.Notifications.Presentation.Terminal.badge,
            subline: hubNotificationFriendlySubline(
                notification,
                facts: facts,
                fallback: HubUIStrings.Notifications.Presentation.Terminal.genericFallback
            ),
            relevance: HubUIStrings.Notifications.Presentation.Terminal.genericRelevance,
            executionSurface: HubUIStrings.Notifications.Presentation.Terminal.executionSurface,
            primaryLabel: HubUIStrings.Notifications.Presentation.Terminal.genericPrimaryLabel,
            primarySystemImage: "doc.text.magnifyingglass",
            primaryAction: .inspect,
            detailFacts: hubNotificationUserVisibleFacts(facts),
            displayTitle: displaySource.isEmpty ? nil : HubUIStrings.Notifications.Presentation.Terminal.genericDisplayTitle(displaySource),
            recommendedNextStep: HubUIStrings.Notifications.Presentation.Terminal.genericNextStep
        )
    }

    if hubNotificationOpensLocalApp(notification) {
        let appName = hubNotificationLocalAppName(notification)
        return HubNotificationPresentation(
            group: .actionRequired,
            badge: source.isEmpty ? appName : source,
            subline: hubNotificationFriendlySubline(notification, facts: facts, fallback: HubUIStrings.Notifications.Presentation.LocalApp.fallback(appName)),
            relevance: HubUIStrings.Notifications.Presentation.LocalApp.relevance(appName),
            executionSurface: HubUIStrings.Notifications.Presentation.LocalApp.executionSurface,
            primaryLabel: hubNotificationLocalAppPrimaryLabel(notification),
            primarySystemImage: "arrow.up.forward.app",
            primaryAction: .openTarget,
            detailFacts: hubNotificationUserVisibleFacts(facts),
            displayTitle: displaySource.isEmpty ? nil : HubUIStrings.Notifications.Presentation.LocalApp.displayTitle(displaySource),
            recommendedNextStep: HubUIStrings.Notifications.Presentation.LocalApp.nextStep
        )
    }

    if hubNotificationUsesHubLocalAction(notification) {
        return HubNotificationPresentation(
            group: .actionRequired,
            badge: source.isEmpty ? HubUIStrings.Notifications.Source.hub : source,
            subline: hubNotificationFriendlySubline(notification, facts: facts, fallback: HubUIStrings.Notifications.Presentation.HubAction.fallback),
            relevance: HubUIStrings.Notifications.Presentation.HubAction.relevance,
            executionSurface: HubUIStrings.Notifications.Presentation.HubAction.executionSurface,
            primaryLabel: HubUIStrings.Notifications.Presentation.HubAction.primaryLabel,
            primarySystemImage: "sidebar.left",
            primaryAction: .openTarget,
            detailFacts: hubNotificationUserVisibleFacts(facts),
            displayTitle: displaySource.isEmpty ? nil : HubUIStrings.Notifications.Presentation.HubAction.displayTitle(displaySource),
            recommendedNextStep: HubUIStrings.Notifications.Presentation.HubAction.nextStep
        )
    }

    return HubNotificationPresentation(
        group: notification.unread ? .actionRequired : .advisory,
        badge: source.isEmpty ? nil : source,
        subline: hubNotificationFriendlySubline(notification, facts: facts),
        relevance: notification.unread ? HubUIStrings.Notifications.Presentation.Generic.unreadRelevance : nil,
        primaryLabel: notification.actionURL == nil ? HubUIStrings.Notifications.Presentation.Generic.viewDetail : HubUIStrings.Notifications.Presentation.Generic.open,
        primarySystemImage: notification.actionURL == nil ? "doc.text.magnifyingglass" : "arrow.up.forward.app",
        primaryAction: notification.actionURL == nil ? .inspect : .openTarget,
        detailFacts: hubNotificationUserVisibleFacts(facts)
    )
}

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

private func hubNotificationPairingRequestedAtText(
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

func hubNotificationUsesHubLocalAction(_ notification: HubNotification) -> Bool {
    guard let actionURL = notification.actionURL,
          let url = URL(string: actionURL) else {
        return false
    }
    guard (url.scheme ?? "").lowercased() == "relflowhub" else {
        return false
    }
    return (url.host ?? "").lowercased() != "openapp"
}

func hubNotificationUsesTerminalDeepLink(_ notification: HubNotification) -> Bool {
    guard let actionURL = notification.actionURL,
          let url = URL(string: actionURL) else {
        return false
    }
    return (url.scheme ?? "").lowercased() == "xterminal"
}

func hubNotificationSourceIsTerminal(_ notification: HubNotification) -> Bool {
    notification.source
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() == "x-terminal"
}

func hubNotificationDisplaySource(_ notification: HubNotification) -> String {
    let trimmed = notification.source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    return HubUIStrings.Notifications.Source.displayName(trimmed)
}

func hubNotificationOpensLocalApp(_ notification: HubNotification) -> Bool {
    guard let actionURL = notification.actionURL,
          let url = URL(string: actionURL) else {
        return false
    }
    let scheme = (url.scheme ?? "").lowercased()
    let host = (url.host ?? "").lowercased()
    if scheme == "relflowhub" {
        return host == "openapp"
    }
    if scheme == "xterminal" {
        return false
    }
    if scheme == "rdar" {
        return true
    }
    let source = notification.source.lowercased()
    return source == "mail" || source == "messages" || source == "slack"
}

func hubNotificationReplySuggestion(_ notification: HubNotification) -> String? {
    let body = notification.body
    if let start = body.range(of: HubUIStrings.Notifications.MissingContext.directSayQuoted)?.upperBound,
       let end = body[start...].firstIndex(of: "”") {
        let suggestion = body[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return suggestion.isEmpty ? nil : suggestion
    }
    if let start = body.range(of: HubUIStrings.Notifications.MissingContext.directSayASCII)?.upperBound,
       let end = body[start...].firstIndex(of: "\"") {
        let suggestion = body[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return suggestion.isEmpty ? nil : suggestion
    }
    return nil
}

func hubNotificationSummaryText(_ notification: HubNotification) -> String {
    let presentation = hubNotificationPresentation(for: notification)
    var lines: [String] = []
    lines.append(presentation.displayTitle ?? notification.title)
    if !presentation.subline.isEmpty {
        lines.append(presentation.subline)
    }
    if let executionSurface = presentation.executionSurface, !executionSurface.isEmpty {
        lines.append(HubUIStrings.Notifications.Summary.executionSurface(executionSurface))
    }
    if let nextStep = presentation.recommendedNextStep, !nextStep.isEmpty {
        lines.append(HubUIStrings.Notifications.Summary.nextStep(nextStep))
    }
    if !presentation.detailFacts.isEmpty {
        lines.append(HubUIStrings.Notifications.Summary.extraInfo)
        lines.append(
            presentation.detailFacts
                .prefix(4)
                .map { "\($0.label): \($0.value)" }
                .joined(separator: "\n")
        )
    }
    if let suggestion = hubNotificationReplySuggestion(notification), !suggestion.isEmpty {
        lines.append(HubUIStrings.Notifications.Summary.suggestedReply(suggestion))
    }
    return lines.joined(separator: "\n")
}

func hubNotificationQuickCopyAction(_ notification: HubNotification) -> HubNotificationQuickCopyAction? {
    if let suggestion = hubNotificationReplySuggestion(notification),
       !suggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return HubNotificationQuickCopyAction(
            label: HubUIStrings.Menu.NotificationRow.copySuggestedReply,
            text: suggestion
        )
    }

    guard hubNotificationShouldOfferSummaryCopy(notification) else { return nil }
    let summary = hubNotificationSummaryText(notification).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !summary.isEmpty else { return nil }
    return HubNotificationQuickCopyAction(
        label: HubUIStrings.Menu.NotificationRow.copySummary,
        text: summary
    )
}

private func compactNotificationBody(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return HubUIStrings.Notifications.Summary.noExtraDetail }
    let collapsed = trimmed
        .replacingOccurrences(of: "\n\n", with: "\n")
        .replacingOccurrences(of: "\n", with: "  ")
    if collapsed.count <= 160 {
        return collapsed
    }
    return String(collapsed.prefix(157)) + "..."
}

private struct HubNotificationFATrackerSummary {
    var subline: String
    var detailFacts: [HubNotificationFact]
}

private struct HubNotificationFATrackerPayload {
    var projectName: String?
    var projectId: Int?
    var radarIds: [Int]
    var radarTitles: [Int: String]
}

private func hubNotificationBodyFacts(_ notification: HubNotification) -> [HubNotificationFact] {
    var facts: [HubNotificationFact] = []
    let source = notification.source.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = notification.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let body = notification.body.trimmingCharacters(in: .whitespacesAndNewlines)

    if let count = hubNotificationUnreadCount(notification),
       ["mail", "messages", "slack"].contains(source.lowercased()) {
        facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.unread, value: "\(count)"))
    }

    if let appName = hubNotificationOpenedBundleName(notification) {
        facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.app, value: appName))
    } else if hubNotificationOpensLocalApp(notification) {
        facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.app, value: hubNotificationLocalAppName(notification)))
    }

    if title.hasPrefix(HubUIStrings.Notifications.MissingContext.titlePrefix) || body.contains(HubUIStrings.Notifications.MissingContext.bodyMarker) {
        if let projectName = hubNotificationMissingContextProjectName(notification) {
            facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.project, value: projectName))
        }
        if let question = hubNotificationMissingContextQuestion(body) {
            facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.missingContext, value: question))
        }
        if let gap = hubNotificationMissingContextGap(body) {
            facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.currentGap, value: gap))
        }
        if let suggestion = hubNotificationReplySuggestion(notification) {
            facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.suggestedReply, value: suggestion))
        }
        return hubNotificationUserVisibleFacts(hubNotificationDedupedFacts(facts))
    }

    let structuredFacts = hubNotificationStructuredFacts(from: body)
    if hubNotificationUsesTerminalDeepLink(notification),
       let incidentFacts = hubNotificationLaneIncidentFacts(
           title: title,
           body: body,
           structuredFacts: structuredFacts
       ) {
        facts.append(contentsOf: incidentFacts)
        return hubNotificationUserVisibleFacts(hubNotificationDedupedFacts(facts))
    }

    facts.append(contentsOf: structuredFacts)

    if facts.isEmpty, !body.isEmpty {
        let lines = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.count == 1 {
            facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.detail, value: compactNotificationBody(body)))
        } else {
            for (index, line) in lines.prefix(4).enumerated() {
                facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.detail(index + 1), value: compactNotificationBody(line)))
            }
        }
    }

    return hubNotificationUserVisibleFacts(hubNotificationDedupedFacts(facts))
}

private func hubNotificationFriendlySubline(
    _ notification: HubNotification,
    facts: [HubNotificationFact],
    fallback: String? = nil
) -> String {
    let source = notification.source.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = notification.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let body = notification.body.trimmingCharacters(in: .whitespacesAndNewlines)

    if let count = hubNotificationUnreadCount(notification) {
        switch source.lowercased() {
        case "mail":
            return HubUIStrings.Notifications.Unread.mail(count)
        case "messages":
            return HubUIStrings.Notifications.Unread.messages(count)
        case "slack":
            return HubUIStrings.Notifications.Unread.slack(count)
        default:
            break
        }
    }

    if title.hasPrefix(HubUIStrings.Notifications.MissingContext.titlePrefix) || body.contains(HubUIStrings.Notifications.MissingContext.bodyMarker) {
        if let question = hubNotificationMissingContextQuestion(body) {
            return HubUIStrings.Notifications.MissingContext.subline(question)
        }
    }

    if title.contains(HubUIStrings.Notifications.Presentation.Terminal.heartbeatKeyword) {
        let factMap = hubNotificationFactMap(facts)
        let reason = factMap[HubUIStrings.Notifications.Facts.reason] ?? factMap["Reason"]
        let blocked = hubNotificationIntFact(factMap[HubUIStrings.Notifications.Facts.blockedProjects] ?? factMap["Blocked Projects"])
        let queue = hubNotificationIntFact(factMap[HubUIStrings.Notifications.Facts.queuedProjects] ?? factMap["Queued Projects"])
        let pendingGrant = hubNotificationIntFact(factMap[HubUIStrings.Notifications.Facts.pendingGrants] ?? factMap["Pending Grants"])
        let repair = hubNotificationIntFact(factMap[HubUIStrings.Notifications.Facts.governanceRepairs] ?? factMap["Governance Repairs"])

        var parts: [String] = []
        if let reason, !reason.isEmpty {
            parts.append(reason)
        }
        if let blocked {
            parts.append(HubUIStrings.Notifications.Lane.blockedProjects(blocked))
        }
        if let queue, queue > 0 {
            parts.append(HubUIStrings.Notifications.Lane.queuedProjects(queue))
        }
        if let pendingGrant, pendingGrant > 0 {
            parts.append(HubUIStrings.Notifications.Lane.pendingGrants(pendingGrant))
        }
        if let repair, repair > 0 {
            parts.append(HubUIStrings.Notifications.Lane.governanceRepairs(repair))
        }
        if !parts.isEmpty {
            return HubUIStrings.Notifications.Lane.summary(parts)
        }
    }

    if hubNotificationUsesTerminalDeepLink(notification),
       let incidentSummary = hubNotificationLaneIncidentSummary(title: title, facts: facts) {
        return incidentSummary
    }

    if let primaryFact = hubNotificationPrimaryFactSummary(facts) {
        return primaryFact
    }

    if hubNotificationSourceIsTerminal(notification)
        && hubNotificationLooksLikeMachineReadableBody(body) {
        return fallback ?? HubUIStrings.Notifications.Presentation.Terminal.genericFallback
    }

    if !body.isEmpty {
        return compactNotificationBody(body)
    }

    return fallback ?? HubUIStrings.Notifications.Summary.noExtraDetail
}

private func hubNotificationShouldOfferSummaryCopy(_ notification: HubNotification) -> Bool {
    let title = notification.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let body = notification.body.trimmingCharacters(in: .whitespacesAndNewlines)

    if title.hasPrefix(HubUIStrings.Notifications.MissingContext.titlePrefix) || body.contains(HubUIStrings.Notifications.MissingContext.bodyMarker) {
        return false
    }

    guard hubNotificationSourceIsTerminal(notification) || hubNotificationUsesTerminalDeepLink(notification) else {
        return false
    }

    if title.contains(HubUIStrings.Notifications.Presentation.Terminal.silentKeyword)
        || title.contains(HubUIStrings.Notifications.Presentation.Terminal.heartbeatKeyword) {
        return false
    }

    let facts = hubNotificationBodyFacts(notification)
    if hubNotificationLaneIncidentSummary(title: title, facts: facts) != nil {
        return true
    }

    return false
}

private func hubNotificationLocalAppName(_ notification: HubNotification) -> String {
    if let actionURL = notification.actionURL,
       let url = URL(string: actionURL),
       (url.scheme ?? "").lowercased() == "rdar" {
        return HubUIStrings.Notifications.Source.radar
    }

    if let openedBundleName = hubNotificationOpenedBundleName(notification) {
        return openedBundleName
    }

    let source = notification.source.trimmingCharacters(in: .whitespacesAndNewlines)
    if !source.isEmpty {
        return source
    }

    return HubUIStrings.Notifications.Source.genericApp
}

private func hubNotificationLocalAppPrimaryLabel(_ notification: HubNotification) -> String {
    "\(HubUIStrings.Notifications.Presentation.Generic.open)\(hubNotificationLocalAppName(notification))"
}

private func hubNotificationFATrackerSummary(_ notification: HubNotification) -> HubNotificationFATrackerSummary {
    let payload = hubNotificationParseFATrackerPayload(notification)
    let projectName = payload.projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let projectLabel = (projectName?.isEmpty == false) ? projectName! : HubUIStrings.Notifications.FATracker.defaultProjectLabel
    let radarCount = payload.radarIds.count

    let subline: String
    if radarCount == 0 {
        subline = HubUIStrings.Notifications.FATracker.openInProject(projectLabel)
    } else if radarCount == 1, let radarId = payload.radarIds.first {
        if let title = payload.radarTitles[radarId], !title.isEmpty {
            subline = HubUIStrings.Notifications.FATracker.radarTitleLine(projectLabel: projectLabel, radarId: radarId, title: title)
        } else {
            subline = HubUIStrings.Notifications.FATracker.singleRadarLine(projectLabel)
        }
    } else {
        subline = HubUIStrings.Notifications.FATracker.radarCountLine(projectLabel: projectLabel, count: radarCount)
    }

    var detailFacts: [HubNotificationFact] = []
    if let projectName, !projectName.isEmpty {
        detailFacts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.project, value: projectName))
    }
    if !payload.radarIds.isEmpty {
        let preview = HubUIStrings.Formatting.commaSeparated(payload.radarIds.prefix(8).map(String.init))
        let suffix = payload.radarIds.count > 8 ? HubUIStrings.Notifications.FATracker.additionalRadar(payload.radarIds.count - 8) : ""
        detailFacts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.radarList, value: preview + suffix))
        detailFacts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.count, value: String(payload.radarIds.count)))
    }

    for (radarId, radarTitle) in payload.radarTitles
        .sorted(by: { $0.key < $1.key })
        .prefix(3) {
        detailFacts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.radar(radarId), value: radarTitle))
    }

    if detailFacts.isEmpty {
        detailFacts = hubNotificationBodyFacts(notification)
    }

    return HubNotificationFATrackerSummary(
        subline: subline,
        detailFacts: hubNotificationUserVisibleFacts(hubNotificationDedupedFacts(detailFacts))
    )
}

private func hubNotificationUnreadCount(_ notification: HubNotification) -> Int? {
    hubNotificationFirstInteger(in: notification.body) ?? hubNotificationFirstInteger(in: notification.title)
}

private func hubNotificationFirstInteger(in text: String) -> Int? {
    var digits = ""
    for character in text {
        if character.isNumber {
            digits.append(character)
        } else if !digits.isEmpty {
            break
        }
    }
    return digits.isEmpty ? nil : Int(digits)
}

private func hubNotificationStructuredFacts(from body: String) -> [HubNotificationFact] {
    let lines = body
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard !lines.isEmpty else { return [] }

    var facts: [HubNotificationFact] = []
    var index = 0
    while index < lines.count {
        let line = lines[index]
        defer { index += 1 }

        guard !line.isEmpty else { continue }

        if let fact = hubNotificationInlineFact(from: line) {
            facts.append(fact)
            continue
        }

        guard hubNotificationLooksLikeStandaloneLabel(line) else { continue }
        let label = hubNotificationDisplayLabel(String(line.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines))
        guard !label.isEmpty else { continue }

        var values: [String] = []
        var scanIndex = index + 1
        while scanIndex < lines.count {
            let candidate = lines[scanIndex]
            if candidate.isEmpty {
                if !values.isEmpty { break }
                scanIndex += 1
                continue
            }
            if hubNotificationInlineFact(from: candidate) != nil || hubNotificationLooksLikeStandaloneLabel(candidate) {
                break
            }
            values.append(candidate)
            scanIndex += 1
            if values.count >= 2 { break }
        }

        if !values.isEmpty {
            facts.append(HubNotificationFact(label: label, value: compactNotificationBody(values.joined(separator: " "))))
            index = max(index, scanIndex - 1)
        }
    }

    return hubNotificationDedupedFacts(facts)
}

private func hubNotificationInlineFact(from line: String) -> HubNotificationFact? {
    let separators: [Character] = ["：", ":", "="]
    guard let separatorIndex = line.firstIndex(where: { separators.contains($0) }) else {
        return nil
    }

    let rawLabel = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
    let label = hubNotificationDisplayLabel(String(rawLabel))
    let valueStart = line.index(after: separatorIndex)
    let rawValue = line[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
    let value = hubNotificationDisplayValue(rawLabel: String(rawLabel), rawValue: String(rawValue))

    guard !label.isEmpty, !value.isEmpty else { return nil }
    guard label.count <= 40 else { return nil }

    return HubNotificationFact(label: label, value: compactNotificationBody(value))
}

private func hubNotificationLooksLikeStandaloneLabel(_ line: String) -> Bool {
    guard let last = line.last else { return false }
    guard last == "：" || last == ":" else { return false }
    let label = String(line.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    return !label.isEmpty && label.count <= 40
}

private func hubNotificationDisplayLabel(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    let mapped: [String: String] = [
        "time": HubUIStrings.Notifications.Facts.time,
        "reason": HubUIStrings.Notifications.Facts.reason,
        "project_count": HubUIStrings.Notifications.Facts.projectCount,
        "blocked_projects": HubUIStrings.Notifications.Facts.blockedProjects,
        "queued_projects": HubUIStrings.Notifications.Facts.queuedProjects,
        "pending_grants": HubUIStrings.Notifications.Facts.pendingGrants,
        "governance_repairs": HubUIStrings.Notifications.Facts.governanceRepairs,
        "device_id": HubUIStrings.Notifications.Facts.deviceID,
        "project_id": HubUIStrings.Notifications.Facts.projectID,
        "capability": HubUIStrings.Notifications.Facts.capability,
        "required_capability": HubUIStrings.Notifications.Facts.capability,
        "grant_capability": HubUIStrings.Notifications.Facts.capability,
        "radars": HubUIStrings.Notifications.Facts.radarList,
        "bundle_id": HubUIStrings.Notifications.Facts.bundleID,
        "lane": HubUIStrings.Notifications.Facts.lane,
        "action": HubUIStrings.Notifications.Facts.action,
        "deny": HubUIStrings.Notifications.Facts.denyReason,
        "latency": HubUIStrings.Notifications.Facts.latency,
        "audit": HubUIStrings.Notifications.Facts.audit,
    ]

    let normalized = hubNotificationSemanticLabel(trimmed)

    if let mapped = mapped[normalized] {
        return mapped
    }

    return trimmed
}

private func hubNotificationDisplayValue(rawLabel: String, rawValue: String) -> String {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    let normalizedLabel = hubNotificationSemanticLabel(rawLabel)

    switch normalizedLabel {
    case "action":
        switch trimmed.lowercased() {
        case "notify_user":
            return HubUIStrings.Notifications.Lane.continueInSupervisor
        case "open_hub_grants":
            return HubUIStrings.Notifications.Lane.openHubGrants
        case "open_grant_pending_board":
            return HubUIStrings.Notifications.Lane.viewGrantPendingBoard
        case "replan_next_safe_point":
            return HubUIStrings.Notifications.Lane.replanNextSafePoint
        case "stop_immediately":
            return HubUIStrings.Notifications.Lane.stopImmediately
        default:
            return trimmed
        }
    case "deny", "reason":
        if let mapped = hubNotificationHumanizedReasonCode(trimmed) {
            return mapped
        }
        if trimmed.lowercased().hasPrefix("event") {
            return HubUIStrings.Notifications.Lane.backgroundEvent
        }
        return trimmed
    case "capability":
        return hubNotificationHumanizedCapabilityCode(trimmed) ?? trimmed
    case "latency":
        return trimmed == "-1ms" ? HubUIStrings.Notifications.Lane.notRecorded : trimmed
    default:
        if normalizedLabel.hasSuffix("reason"),
           let mapped = hubNotificationHumanizedReasonCode(trimmed) {
            return mapped
        }
        return trimmed
    }
}

private func hubNotificationSemanticLabel(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    let normalized = trimmed
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")

    let aliases: [String: String] = [
        HubUIStrings.Notifications.Facts.time: "time",
        HubUIStrings.Notifications.Facts.reason: "reason",
        HubUIStrings.Notifications.Facts.projectCount: "project_count",
        HubUIStrings.Notifications.Facts.blockedProjects: "blocked_projects",
        HubUIStrings.Notifications.Facts.queuedProjects: "queued_projects",
        HubUIStrings.Notifications.Facts.pendingGrants: "pending_grants",
        HubUIStrings.Notifications.Facts.governanceRepairs: "governance_repairs",
        HubUIStrings.Notifications.Facts.deviceID: "device_id",
        HubUIStrings.Notifications.Facts.projectID: "project_id",
        HubUIStrings.Notifications.Facts.projectIDLegacyAlias: "project_id",
        HubUIStrings.Notifications.Facts.capability: "capability",
        HubUIStrings.Notifications.Facts.lane: "lane",
        HubUIStrings.Notifications.Facts.action: "action",
        HubUIStrings.Notifications.Facts.suggestedAction: "action",
        HubUIStrings.Notifications.Facts.denyReason: "deny",
        HubUIStrings.Notifications.Facts.latency: "latency",
        HubUIStrings.Notifications.Facts.audit: "audit",
        "capability": "capability",
        "required_capability": "capability",
        "grant_capability": "capability",
    ]

    return aliases[trimmed] ?? normalized
}

private func hubNotificationMissingContextQuestion(_ body: String) -> String? {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let range = trimmed.range(of: HubUIStrings.Notifications.MissingContext.bodyLead) {
        let candidate = String(trimmed[range.upperBound...])
        let stopTokens = [" \(HubUIStrings.Notifications.MissingContext.currentGapMarker)", HubUIStrings.Notifications.MissingContext.directSayStop, "。"]
        return hubNotificationPrefix(beforeAnyOf: stopTokens, in: candidate)
    }

    return hubNotificationPrefix(beforeAnyOf: [" \(HubUIStrings.Notifications.MissingContext.currentGapMarker)", HubUIStrings.Notifications.MissingContext.directSayStop], in: trimmed)
}

private func hubNotificationMissingContextProjectName(_ notification: HubNotification) -> String? {
    let title = notification.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard title.hasPrefix(HubUIStrings.Notifications.MissingContext.titlePrefix) else { return nil }
    let projectName = String(title.dropFirst(HubUIStrings.Notifications.MissingContext.titlePrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    return projectName.isEmpty ? nil : projectName
}

private func hubNotificationMissingContextGap(_ body: String) -> String? {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let range = trimmed.range(of: HubUIStrings.Notifications.MissingContext.currentGapMarker) else { return nil }
    let candidate = String(trimmed[range.upperBound...])
    return hubNotificationPrefix(beforeAnyOf: [HubUIStrings.Notifications.MissingContext.directSayStop, HubUIStrings.Notifications.MissingContext.enoughSuffix], in: candidate)
}

private func hubNotificationMissingContextDisplayTitle(_ notification: HubNotification) -> String {
    HubUIStrings.Notifications.MissingContext.displayTitle(projectName: hubNotificationMissingContextProjectName(notification))
}

private func hubNotificationLaneIncidentFacts(
    title: String,
    body: String,
    structuredFacts: [HubNotificationFact]
) -> [HubNotificationFact]? {
    guard title.contains(HubUIStrings.Notifications.Lane.titleMarker) || body.contains("action=") || body.contains("deny=") else {
        return nil
    }

    let factMap = hubNotificationFactMap(structuredFacts)
    var facts: [HubNotificationFact] = []

    if let incident = hubNotificationTerminalIncidentCode(from: title),
       let mapped = hubNotificationHumanizedReasonCode(incident) {
        facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.issueType, value: mapped))
    }
    if let capability = factMap[HubUIStrings.Notifications.Facts.capability], !capability.isEmpty {
        facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.capability, value: capability))
    }
    if let deviceID = factMap[HubUIStrings.Notifications.Facts.deviceID], !deviceID.isEmpty {
        facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.deviceID, value: deviceID))
    }
    if let deny = factMap[HubUIStrings.Notifications.Facts.denyReason], !deny.isEmpty {
        facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.denyReason, value: deny))
    }
    if let action = factMap[HubUIStrings.Notifications.Facts.action], !action.isEmpty {
        facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.suggestedAction, value: action))
    }

    return facts.isEmpty ? nil : hubNotificationUserVisibleFacts(hubNotificationDedupedFacts(facts))
}

private func hubNotificationUserVisibleFacts(_ facts: [HubNotificationFact]) -> [HubNotificationFact] {
    let hiddenLabels: Set<String> = [
        HubUIStrings.Notifications.Facts.audit,
        HubUIStrings.Notifications.Facts.lane,
        HubUIStrings.Notifications.Facts.latency,
        HubUIStrings.Notifications.Facts.projectID,
        HubUIStrings.Notifications.Facts.bundleID,
    ]

    return hubNotificationDedupedFacts(
        facts.filter { fact in
            let label = fact.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return !label.isEmpty
                && !hiddenLabels.contains(label)
                && !hubNotificationFactLabelLooksMachineGenerated(label)
        }
    )
}

private func hubNotificationFactLabelLooksMachineGenerated(_ label: String) -> Bool {
    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    return trimmed.range(of: #"^[a-z0-9_./-]+$"#, options: .regularExpression) != nil
}

private func hubNotificationLooksLikeMachineReadableBody(_ body: String) -> Bool {
    let lines = body
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard !lines.isEmpty else { return false }

    let machineReadableLines = lines.filter { line in
        line.contains("=") || line.range(of: #"^[a-z0-9_./-]+:[^\s].*$"#, options: .regularExpression) != nil
    }

    return machineReadableLines.count == lines.count
}

private func hubNotificationLaneIncidentSummary(title: String, facts: [HubNotificationFact]) -> String? {
    let factMap = hubNotificationFactMap(facts)
    let incidentCode = hubNotificationTerminalIncidentCode(from: title)
    let incidentLabel = incidentCode.flatMap(hubNotificationHumanizedReasonCode)
    let action = factMap[HubUIStrings.Notifications.Facts.suggestedAction] ?? factMap[HubUIStrings.Notifications.Facts.action]
    let capability = hubNotificationGrantPendingCapabilityName(facts)

    if incidentCode == "grant_pending" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.waitingGrant {
        return HubUIStrings.Notifications.Lane.grantPendingSummary(
            hubNotificationLaneCount(from: title),
            capability: capability
        )
    }

    if incidentCode == "awaiting_instruction" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.waitingNextInstruction {
        return HubUIStrings.Notifications.Lane.awaitingInstructionSummary
    }

    if incidentCode == "runtime_error" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.runtimeError {
        return HubUIStrings.Notifications.Lane.runtimeErrorSummary
    }

    if let incidentLabel {
        return HubUIStrings.Notifications.Lane.incidentSummary(incidentLabel: incidentLabel, action: action)
    }
    if let action, !action.isEmpty {
        return HubUIStrings.Notifications.Lane.actionOnlySummary(action)
    }
    return nil
}

private func hubNotificationLaneIncidentDisplayTitle(title: String, facts: [HubNotificationFact]) -> String? {
    let factMap = hubNotificationFactMap(facts)
    let incidentCode = hubNotificationTerminalIncidentCode(from: title)
    let capability = hubNotificationGrantPendingCapabilityName(facts)

    if incidentCode == "grant_pending" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.waitingGrant {
        return HubUIStrings.Notifications.Lane.grantPendingDisplayTitle(
            hubNotificationLaneCount(from: title),
            capability: capability
        )
    }

    if incidentCode == "awaiting_instruction" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.waitingNextInstruction {
        return HubUIStrings.Notifications.Lane.awaitingInstructionDisplayTitle
    }

    if incidentCode == "runtime_error" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.runtimeError {
        return HubUIStrings.Notifications.Lane.runtimeErrorDisplayTitle
    }

    if let incidentLabel = incidentCode.flatMap(hubNotificationHumanizedReasonCode) {
        return HubUIStrings.Notifications.Lane.incidentDisplayTitle(incidentLabel)
    }

    return nil
}

private func hubNotificationLaneIncidentNextStep(title: String, facts: [HubNotificationFact]) -> String? {
    let factMap = hubNotificationFactMap(facts)
    let incidentCode = hubNotificationTerminalIncidentCode(from: title)
    let action = factMap[HubUIStrings.Notifications.Facts.suggestedAction] ?? factMap[HubUIStrings.Notifications.Facts.action]
    let capability = hubNotificationGrantPendingCapabilityName(facts)

    if incidentCode == "grant_pending" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.waitingGrant {
        return HubUIStrings.Notifications.Lane.grantPendingNextStep(capability)
    }

    if incidentCode == "awaiting_instruction" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.waitingNextInstruction {
        return HubUIStrings.Notifications.Lane.awaitingInstructionNextStep
    }

    if incidentCode == "runtime_error" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.runtimeError {
        return HubUIStrings.Notifications.Lane.runtimeErrorNextStep
    }

    if let action, !action.isEmpty {
        return HubUIStrings.Notifications.Lane.actionNextStep(action)
    }

    return nil
}

private func hubNotificationLaneIncidentPrimaryLabel(title: String, facts: [HubNotificationFact]) -> String {
    let factMap = hubNotificationFactMap(facts)
    let incidentCode = hubNotificationTerminalIncidentCode(from: title)

    if incidentCode == "awaiting_instruction" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.waitingNextInstruction {
        return HubUIStrings.Notifications.Lane.awaitingInstructionPrimaryLabel
    }

    if incidentCode == "runtime_error" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.runtimeError {
        return HubUIStrings.Notifications.Lane.runtimeErrorPrimaryLabel
    }

    if incidentCode == "grant_pending" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.waitingGrant {
        return HubUIStrings.Notifications.Lane.grantPendingPrimaryLabel
    }

    return HubUIStrings.Notifications.Lane.genericPrimaryLabel
}

private func hubNotificationTerminalIncidentCode(from title: String) -> String? {
    guard let marker = title.lastIndex(of: "：") ?? title.lastIndex(of: ":") else { return nil }
    let code = title[title.index(after: marker)...].trimmingCharacters(in: .whitespacesAndNewlines)
    return code.isEmpty ? nil : String(code)
}

private func hubNotificationLaneCount(from title: String) -> Int? {
    guard title.contains("Lane") else { return nil }
    return hubNotificationFirstInteger(in: title)
}

private func hubNotificationHumanizedReasonCode(_ raw: String) -> String? {
    let normalized = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")
    guard !normalized.isEmpty else { return nil }

    switch normalized {
    case "grant_pending":
        return HubUIStrings.Notifications.Lane.waitingGrant
    case "grant_pending_connector_side_effect":
        return HubUIStrings.Notifications.Lane.waitingConnectorSideEffectGrant
    case "awaiting_instruction":
        return HubUIStrings.Notifications.Lane.waitingNextInstruction
    case "runtime_error":
        return HubUIStrings.Notifications.Lane.runtimeError
    case "allocation_blocked":
        return HubUIStrings.Notifications.Lane.allocationBlocked
    case "permission_denied":
        return HubUIStrings.Notifications.Lane.permissionDenied
    case "event", "event...", "event_update":
        return HubUIStrings.Notifications.Lane.backgroundEvent
    default:
        if normalized.hasPrefix("connector_event/") {
            let suffix = normalized.dropFirst("connector_event/".count)
            return HubUIStrings.Notifications.Lane.connectorEvent(String(suffix))
        }
        return nil
    }
}

private func hubNotificationHumanizedCapabilityCode(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let normalized: String = {
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("capability_") {
            return String(lowered.dropFirst("capability_".count))
        }
        return lowered
    }()

    switch normalized {
    case "web.fetch", "web_fetch":
        return HubUIStrings.MainPanel.PairingScope.webFetch
    case "ai.generate.paid", "ai_generate_paid":
        return HubUIStrings.MainPanel.PairingScope.paidAI
    case "ai.generate.local", "ai_generate_local":
        return HubUIStrings.MainPanel.PairingScope.localAI
    default:
        return nil
    }
}

private func hubNotificationGrantPendingCapabilityName(_ facts: [HubNotificationFact]) -> String? {
    let factMap = hubNotificationFactMap(facts)
    let capability = factMap[HubUIStrings.Notifications.Facts.capability]?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return capability.isEmpty ? nil : capability
}

private func hubNotificationGrantPendingDeviceID(_ facts: [HubNotificationFact]) -> String? {
    let factMap = hubNotificationFactMap(facts)
    let deviceID = factMap[HubUIStrings.Notifications.Facts.deviceID]?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return deviceID.isEmpty ? nil : deviceID
}

private func hubNotificationFATrackerDisplayTitle(_ notification: HubNotification) -> String {
    let payload = hubNotificationParseFATrackerPayload(notification)
    let projectName = payload.projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let projectLabel = (projectName?.isEmpty == false) ? projectName! : HubUIStrings.Notifications.FATracker.defaultProjectLabel
    let count = payload.radarIds.count

    if count <= 0 {
        return HubUIStrings.Notifications.FATracker.displayTitleNoRadar(projectLabel)
    }
    if count == 1 {
        return HubUIStrings.Notifications.FATracker.displayTitleOneRadar(projectLabel)
    }
    return HubUIStrings.Notifications.FATracker.displayTitleManyRadar(projectLabel, count: count)
}

private func hubNotificationPrefix(beforeAnyOf tokens: [String], in text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let endIndex = tokens.compactMap { token in
        trimmed.range(of: token).map(\.lowerBound)
    }.min() ?? trimmed.endIndex

    let result = trimmed[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? nil : String(result)
}

private func hubNotificationPrimaryFactSummary(_ facts: [HubNotificationFact]) -> String? {
    let summaryFacts = facts.filter { fact in
        let label = fact.label.lowercased()
        return label != "detail"
            && label != HubUIStrings.Notifications.Facts.detail
            && !label.hasPrefix("detail ")
            && !label.hasPrefix(HubUIStrings.Notifications.Facts.detail.lowercased() + " ")
            && label != HubUIStrings.Notifications.Facts.lane.lowercased()
            && label != HubUIStrings.Notifications.Facts.latency.lowercased()
            && label != HubUIStrings.Notifications.Facts.audit.lowercased()
    }

    let chosen = summaryFacts.isEmpty ? facts.prefix(2) : summaryFacts.prefix(2)
    let parts = chosen.compactMap { fact -> String? in
        let label = fact.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = fact.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if label.isEmpty
            || label == "Detail"
            || label == HubUIStrings.Notifications.Facts.detail
            || label.hasPrefix("Detail ")
            || label.hasPrefix(HubUIStrings.Notifications.Facts.detail + " ") {
            return value
        }
        return HubUIStrings.Notifications.Facts.labelValue(label, value: value)
    }

    guard !parts.isEmpty else { return nil }
    return HubUIStrings.Notifications.Lane.summary(parts)
}

private func hubNotificationFactMap(_ facts: [HubNotificationFact]) -> [String: String] {
    var map: [String: String] = [:]
    for fact in facts {
        map[fact.label] = fact.value
    }
    return map
}

private func hubNotificationIntFact(_ text: String?) -> Int? {
    guard let text else { return nil }
    return hubNotificationFirstInteger(in: text)
}

private func hubNotificationDedupedFacts(_ facts: [HubNotificationFact]) -> [HubNotificationFact] {
    var seen: Set<String> = []
    var deduped: [HubNotificationFact] = []
    for fact in facts {
        let label = fact.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = fact.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { continue }
        let key = "\(label)|\(value)"
        guard seen.insert(key).inserted else { continue }
        deduped.append(HubNotificationFact(label: label, value: value))
    }
    return deduped
}

private func hubNotificationOpenedBundleName(_ notification: HubNotification) -> String? {
    guard let actionURL = notification.actionURL,
          let url = URL(string: actionURL),
          (url.scheme ?? "").lowercased() == "relflowhub",
          (url.host ?? "").lowercased() == "openapp" else {
        return nil
    }

    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let bundleID = (items.first(where: { $0.name == "bundle_id" })?.value ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !bundleID.isEmpty else { return nil }

    if let knownName = HubUIStrings.Notifications.Source.bundleDisplayName(bundleID) {
        return knownName
    }

    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
       let bundle = Bundle(url: appURL),
       let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
       !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return appName
    }

    let suffix = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    return suffix.isEmpty ? nil : suffix
}

private func hubNotificationParseFATrackerPayload(_ notification: HubNotification) -> HubNotificationFATrackerPayload {
    guard notification.source == "FAtracker" else {
        return HubNotificationFATrackerPayload(projectName: nil, projectId: nil, radarIds: [], radarTitles: [:])
    }

    let lines = notification.body
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)

    let projectName = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines)
    var projectId: Int?
    var radarIds: [Int] = []

    if let actionURL = notification.actionURL,
       let url = URL(string: actionURL),
       (url.scheme ?? "").lowercased() == "relflowhub" {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        projectId = Int(items.first(where: { $0.name == "project_id" })?.value ?? "")
        radarIds = (items.first(where: { $0.name == "radars" })?.value ?? "")
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    if radarIds.isEmpty, lines.count >= 2 {
        radarIds = lines[1]
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    var radarTitles: [Int: String] = [:]
    if lines.count >= 3 {
        for line in lines.dropFirst(2) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let dashRange = trimmed.range(of: " - ") else { continue }
            let idText = trimmed[..<dashRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmed[dashRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let radarId = Int(idText), !title.isEmpty {
                radarTitles[radarId] = String(title)
            }
        }
    }

    return HubNotificationFATrackerPayload(
        projectName: projectName,
        projectId: projectId,
        radarIds: radarIds,
        radarTitles: radarTitles
    )
}

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

            Menu {
                Button(HubUIStrings.Menu.NotificationRow.tenMinutes) {
                    store.snooze(notification.id, minutes: 10)
                    dismiss()
                }
                Button(HubUIStrings.Menu.NotificationRow.thirtyMinutes) {
                    store.snooze(notification.id, minutes: 30)
                    dismiss()
                }
                Button(HubUIStrings.Menu.NotificationRow.oneHour) {
                    store.snooze(notification.id, minutes: 60)
                    dismiss()
                }
                Button(HubUIStrings.Menu.NotificationRow.laterToday) {
                    store.snoozeLaterToday(notification.id)
                    dismiss()
                }
            } label: {
                HubNeutralActionChipLabel(
                    title: HubUIStrings.Menu.NotificationRow.snooze,
                    systemName: "clock",
                    width: nil
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

            Menu {
                Button(HubUIStrings.Notifications.Inspector.removeNotification, role: .destructive) {
                    store.dismiss(notification.id)
                    dismiss()
                }
            } label: {
                HubNeutralActionChipLabel(
                    title: HubUIStrings.Menu.NotificationRow.more,
                    systemName: "ellipsis",
                    width: nil
                )
            }
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

            Menu {
                Button(HubUIStrings.Menu.NotificationRow.tenMinutes) {
                    store.snooze(notification.id, minutes: 10)
                    dismiss()
                }
                Button(HubUIStrings.Menu.NotificationRow.thirtyMinutes) {
                    store.snooze(notification.id, minutes: 30)
                    dismiss()
                }
                Button(HubUIStrings.Menu.NotificationRow.oneHour) {
                    store.snooze(notification.id, minutes: 60)
                    dismiss()
                }
                Button(HubUIStrings.Menu.NotificationRow.laterToday) {
                    store.snoozeLaterToday(notification.id)
                    dismiss()
                }
            } label: {
                HubNeutralActionChipLabel(
                    title: HubUIStrings.Menu.NotificationRow.snooze,
                    systemName: "clock",
                    width: nil
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

            Menu {
                Button(HubUIStrings.Notifications.Inspector.removeNotification, role: .destructive) {
                    store.dismiss(notification.id)
                    dismiss()
                }
            } label: {
                HubNeutralActionChipLabel(
                    title: HubUIStrings.Menu.NotificationRow.more,
                    systemName: "ellipsis",
                    width: nil
                )
            }
        }
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
