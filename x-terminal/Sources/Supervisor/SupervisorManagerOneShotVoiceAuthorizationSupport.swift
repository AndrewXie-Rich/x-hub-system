import Foundation

extension SupervisorManager {
    func oneShotVoiceAuthorizationRequestID(
        requestID: String,
        authorizationTypes: [OneShotHumanAuthorizationType]
    ) -> String {
        let normalizedRequestID = requestID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let authKey = authorizationTypes
            .map(\.rawValue)
            .joined(separator: "_")
            .replacingOccurrences(of: "-", with: "_")
        return "voice_auth_\(normalizedRequestID)_\(authKey)"
    }

    func oneShotPrimaryVoiceAuthorizationType(
        _ authorizationTypes: [OneShotHumanAuthorizationType]
    ) -> OneShotHumanAuthorizationType {
        let priority: [OneShotHumanAuthorizationType] = [
            .payment,
            .externalSideEffect,
            .secretBinding,
            .connectorBinding,
            .scopeExpansion
        ]
        for candidate in priority where authorizationTypes.contains(candidate) {
            return candidate
        }
        return authorizationTypes.first ?? .externalSideEffect
    }

    func oneShotVoiceAuthorizationTemplateID(
        primaryAuthorizationType: OneShotHumanAuthorizationType,
        authorizationTypes: [OneShotHumanAuthorizationType]
    ) -> String {
        if authorizationTypes.count > 1 {
            return "voice.grant.guarded_one_shot_launch.v1"
        }

        switch primaryAuthorizationType {
        case .payment:
            return "voice.grant.payment.v1"
        case .externalSideEffect:
            return "voice.grant.external_side_effect.v1"
        case .connectorBinding:
            return "voice.grant.connector_binding.v1"
        case .secretBinding:
            return "voice.grant.secret_binding.v1"
        case .scopeExpansion:
            return "voice.grant.scope_expansion.v1"
        }
    }

    func oneShotVoiceAuthorizationActionText(
        primaryAuthorizationType: OneShotHumanAuthorizationType,
        authorizationTypes: [OneShotHumanAuthorizationType]
    ) -> String {
        if authorizationTypes.count > 1 {
            return "Approve guarded one-shot launch with multiple high-risk actions"
        }

        switch primaryAuthorizationType {
        case .payment:
            return "Approve guarded one-shot payment action"
        case .externalSideEffect:
            return "Approve guarded one-shot external side effect"
        case .connectorBinding:
            return "Approve guarded one-shot connector binding"
        case .secretBinding:
            return "Approve guarded one-shot secret binding"
        case .scopeExpansion:
            return "Approve one-shot scope expansion"
        }
    }

    func oneShotVoiceAuthorizationRiskTier(
        authorizationTypes: [OneShotHumanAuthorizationType],
        riskSurface: OneShotRiskSurface
    ) -> LaneRiskTier {
        var riskTier = laneRiskTier(from: riskSurface)
        if authorizationTypes.contains(.payment) {
            riskTier = .critical
        }
        if authorizationTypes.contains(.externalSideEffect)
            || authorizationTypes.contains(.connectorBinding)
            || authorizationTypes.contains(.secretBinding)
            || authorizationTypes.contains(.scopeExpansion) {
            riskTier = max(riskTier, .high)
        }
        return riskTier
    }

    func laneRiskTier(from riskSurface: OneShotRiskSurface) -> LaneRiskTier {
        switch riskSurface {
        case .low:
            return .low
        case .medium:
            return .medium
        case .high:
            return .high
        case .critical:
            return .critical
        }
    }

    func oneShotVoiceAuthorizationAmountText(userGoal: String) -> String? {
        let goal = userGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return nil }

        let patterns = [
            #"(?i)\b(?:usd|rmb|cny|eur|gbp|jpy)\s*[\d,]+(?:\.\d+)?\b"#,
            #"(?i)\b[\d,]+(?:\.\d+)?\s*(?:usd|rmb|cny|eur|gbp|jpy)\b"#,
            #"(?i)[¥$€£]\s*[\d,]+(?:\.\d+)?"#
        ]

        for pattern in patterns {
            if let range = goal.range(of: pattern, options: .regularExpression) {
                let token = goal[range].trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty {
                    return String(token)
                }
            }
        }

        return nil
    }
}
