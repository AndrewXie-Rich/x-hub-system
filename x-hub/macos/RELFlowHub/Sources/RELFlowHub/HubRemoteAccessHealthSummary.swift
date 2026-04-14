import Foundation

struct HubRemoteAccessHealthSummary: Equatable {
    enum State: String, Equatable {
        case ready
        case warning
        case critical
    }

    let state: State
    let badgeText: String
    let headline: String
    let detail: String
    let accessScopeText: String
    let operatorHintText: String
    let nextStep: String?
}

enum HubRemoteAccessHealthSummaryBuilder {
    static func build(
        autoStartEnabled: Bool,
        serverRunning: Bool,
        externalHost: String?,
        hasInviteToken: Bool,
        keepSystemAwakeWhileServing: Bool
    ) -> HubRemoteAccessHealthSummary {
        let accessEnabled = autoStartEnabled || serverRunning
        let host = HubRemoteAccessHostClassification.classify(externalHost)

        if !accessEnabled {
            return HubRemoteAccessHealthSummary(
                state: .critical,
                badgeText: HubUIStrings.Settings.GRPC.RemoteHealth.badgeBlocked,
                headline: HubUIStrings.Settings.GRPC.RemoteHealth.disabledHeadline,
                detail: HubUIStrings.Settings.GRPC.RemoteHealth.disabledDetail,
                accessScopeText: HubUIStrings.Settings.GRPC.RemoteHealth.scopeDisabled,
                operatorHintText: HubUIStrings.Settings.GRPC.RemoteHealth.hintDisabled,
                nextStep: HubUIStrings.Settings.GRPC.RemoteHealth.disabledNextStep
            )
        }

        if !serverRunning {
            let accessScopeText: String
            let operatorHintText: String
            switch host.kind {
            case .missing:
                accessScopeText = HubUIStrings.Settings.GRPC.RemoteHealth.scopeDisabled
                operatorHintText = HubUIStrings.Settings.GRPC.RemoteHealth.hintOfflineMissing
            case .lanOnly:
                accessScopeText = HubUIStrings.Settings.GRPC.RemoteHealth.scopeLANOnly
                operatorHintText = HubUIStrings.Settings.GRPC.RemoteHealth.hintOfflineLANOnly
            case .rawIP:
                accessScopeText = HubUIStrings.Settings.GRPC.RemoteHealth.scopeTemporaryRemote
                operatorHintText = HubUIStrings.Settings.GRPC.RemoteHealth.hintOfflineRawIP
            case .stableNamed:
                accessScopeText = HubUIStrings.Settings.GRPC.RemoteHealth.scopeRemoteOffline
                operatorHintText = HubUIStrings.Settings.GRPC.RemoteHealth.hintOfflineStableNamed
            }
            return HubRemoteAccessHealthSummary(
                state: .critical,
                badgeText: HubUIStrings.Settings.GRPC.RemoteHealth.badgeBlocked,
                headline: HubUIStrings.Settings.GRPC.RemoteHealth.offlineHeadline,
                detail: HubUIStrings.Settings.GRPC.RemoteHealth.offlineDetail(host.displayHost),
                accessScopeText: accessScopeText,
                operatorHintText: operatorHintText,
                nextStep: HubUIStrings.Settings.GRPC.RemoteHealth.offlineNextStep
            )
        }

        switch host.kind {
        case .missing:
            return HubRemoteAccessHealthSummary(
                state: .warning,
                badgeText: HubUIStrings.Settings.GRPC.RemoteHealth.badgeAttention,
                headline: HubUIStrings.Settings.GRPC.RemoteHealth.lanOnlyHeadline,
                detail: HubUIStrings.Settings.GRPC.RemoteHealth.lanOnlyDetail,
                accessScopeText: HubUIStrings.Settings.GRPC.RemoteHealth.scopeLANOnly,
                operatorHintText: HubUIStrings.Settings.GRPC.RemoteHealth.hintLANOnly,
                nextStep: HubUIStrings.Settings.GRPC.RemoteHealth.lanOnlyNextStep
            )
        case .lanOnly:
            let value = host.displayHost ?? ""
            return HubRemoteAccessHealthSummary(
                state: .warning,
                badgeText: HubUIStrings.Settings.GRPC.RemoteHealth.badgeAttention,
                headline: HubUIStrings.Settings.GRPC.RemoteHealth.lanOnlyHeadline,
                detail: HubUIStrings.Settings.GRPC.RemoteHealth.lanOnlyHostDetail(value),
                accessScopeText: HubUIStrings.Settings.GRPC.RemoteHealth.scopeLANOnly,
                operatorHintText: HubUIStrings.Settings.GRPC.RemoteHealth.hintLANOnly,
                nextStep: HubUIStrings.Settings.GRPC.RemoteHealth.lanOnlyNextStep
            )
        case .rawIP:
            let value = host.displayHost ?? ""
            return HubRemoteAccessHealthSummary(
                state: .warning,
                badgeText: HubUIStrings.Settings.GRPC.RemoteHealth.badgeTemporary,
                headline: HubUIStrings.Settings.GRPC.RemoteHealth.rawIPHeadline,
                detail: HubUIStrings.Settings.GRPC.RemoteHealth.rawIPDetail(value),
                accessScopeText: HubUIStrings.Settings.GRPC.RemoteHealth.scopeTemporaryRemote,
                operatorHintText: HubUIStrings.Settings.GRPC.RemoteHealth.hintRawIP,
                nextStep: HubUIStrings.Settings.GRPC.RemoteHealth.rawIPNextStep
            )
        case .stableNamed:
            let value = host.displayHost ?? ""
            if !hasInviteToken {
                return HubRemoteAccessHealthSummary(
                    state: .warning,
                    badgeText: HubUIStrings.Settings.GRPC.RemoteHealth.badgeNeedsToken,
                    headline: HubUIStrings.Settings.GRPC.RemoteHealth.tokenMissingHeadline,
                    detail: HubUIStrings.Settings.GRPC.RemoteHealth.tokenMissingDetail(value),
                    accessScopeText: HubUIStrings.Settings.GRPC.RemoteHealth.scopeRemotePending,
                    operatorHintText: HubUIStrings.Settings.GRPC.RemoteHealth.hintTokenMissing,
                    nextStep: HubUIStrings.Settings.GRPC.RemoteHealth.tokenMissingNextStep
                )
            }

            if !keepSystemAwakeWhileServing {
                return HubRemoteAccessHealthSummary(
                    state: .warning,
                    badgeText: HubUIStrings.Settings.GRPC.RemoteHealth.badgeAttention,
                    headline: HubUIStrings.Settings.GRPC.RemoteHealth.sleepRiskHeadline,
                    detail: HubUIStrings.Settings.GRPC.RemoteHealth.sleepRiskDetail(value),
                    accessScopeText: HubUIStrings.Settings.GRPC.RemoteHealth.scopeRemoteReady,
                    operatorHintText: HubUIStrings.Settings.GRPC.RemoteHealth.hintSleepRisk,
                    nextStep: HubUIStrings.Settings.GRPC.RemoteHealth.sleepRiskNextStep
                )
            }

            return HubRemoteAccessHealthSummary(
                state: .ready,
                badgeText: HubUIStrings.Settings.GRPC.RemoteHealth.badgeReady,
                headline: HubUIStrings.Settings.GRPC.RemoteHealth.readyHeadline,
                detail: HubUIStrings.Settings.GRPC.RemoteHealth.readyDetail(value),
                accessScopeText: HubUIStrings.Settings.GRPC.RemoteHealth.scopeRemoteReady,
                operatorHintText: HubUIStrings.Settings.GRPC.RemoteHealth.hintReady,
                nextStep: HubUIStrings.Settings.GRPC.RemoteHealth.readyNextStep
            )
        }
    }
}
