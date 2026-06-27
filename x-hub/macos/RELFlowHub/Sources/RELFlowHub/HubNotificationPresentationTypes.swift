import Foundation
import RELFlowHubCore

final class HubNotificationPresentationCacheEntry: NSObject {
    let presentation: HubNotificationPresentation

    init(presentation: HubNotificationPresentation) {
        self.presentation = presentation
    }
}

enum HubNotificationPresentationCache {
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
