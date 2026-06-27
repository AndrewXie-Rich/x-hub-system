import AppKit
import SwiftUI
import RELFlowHubCore

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
