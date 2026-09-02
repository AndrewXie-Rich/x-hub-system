import Foundation

extension SupervisorManager {
    func supervisorExecutionPath(_ mode: SupervisorReplyExecutionMode) -> String {
        switch mode {
        case .remoteModel:
            return "remote_model"
        case .hubDowngradedToLocal:
            return "hub_downgraded_to_local"
        case .localFallbackAfterRemoteError:
            return "local_fallback_after_remote_error"
        case .localPreflight:
            return "local_preflight"
        case .localDirectReply:
            return "local_direct_reply"
        case .localDirectAction:
            return "local_direct_action"
        case .hubBriefProjection:
            return "hub_brief_projection"
        case .idle:
            return "no_record"
        }
    }

    func supervisorRuntimeProvider(_ mode: SupervisorReplyExecutionMode) -> String {
        switch mode {
        case .remoteModel:
            return "Hub (Remote)"
        case .hubDowngradedToLocal, .localFallbackAfterRemoteError:
            return "Hub (Local)"
        case .localPreflight, .localDirectReply, .localDirectAction, .hubBriefProjection, .idle:
            return ""
        }
    }

    func supervisorRouteTruthLines(
        configuredModelId: String,
        actualModelId: String,
        mode: SupervisorReplyExecutionMode,
        failureReason: String,
        denyCode: String,
        auditRef: String,
        includeConfiguredRoute: Bool = true,
        includeRouteState: Bool = true
    ) -> [String] {
        let executionPath = supervisorExecutionPath(mode)
        guard executionPath != "no_record" else { return [] }

        let configuredTarget = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "auto"
            : configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveFailureReason: String = {
            switch mode {
            case .remoteModel, .hubDowngradedToLocal, .localFallbackAfterRemoteError:
                return effectiveSupervisorFailureReasonCode(
                    failureReason: failureReason,
                    denyCode: denyCode
                )
            case .localPreflight, .localDirectReply, .localDirectAction, .hubBriefProjection, .idle:
                return ""
            }
        }()
        let actualRoute = XTRouteTruthPresentation.actualRouteText(
            executionPath: executionPath,
            runtimeProvider: supervisorRuntimeProvider(mode),
            actualModelId: actualModelId
        )

        return [
            includeConfiguredRoute ? XTRouteTruthPresentation.configuredRouteLine(configuredTarget) : nil,
            XTRouteTruthPresentation.actualRouteLine(actualRoute),
            effectiveFailureReason.isEmpty
                ? nil
                : XTRouteTruthPresentation.fallbackReasonLine(
                    XTRouteTruthPresentation.routeReasonDisplayText(effectiveFailureReason) ?? effectiveFailureReason
                ),
            includeRouteState
                ? XTRouteTruthPresentation.routeStateLine(
                    XTRouteTruthPresentation.routeStateText(
                        executionPath: executionPath,
                        routeReasonCode: effectiveFailureReason
                    )
                )
                : nil,
            denyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : XTRouteTruthPresentation.denyCodeLine(
                    XTRouteTruthPresentation.denyCodeText(denyCode) ?? denyCode
                ),
            auditRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "audit_ref=\(auditRef)"
        ]
        .compactMap { line in
            let trimmed = line?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    func currentSupervisorRouteTruthLines(
        includeConfiguredRoute: Bool = false,
        includeRouteState: Bool = false
    ) -> [String] {
        let configured = currentPreferredModelID(for: .supervisor)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let actualModelId = lastSupervisorActualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let failureReason = lastSupervisorRemoteFailureReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let denyCode = lastSupervisorDenyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let auditRef = lastSupervisorAuditRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = SupervisorReplyExecutionMode(rawValue: lastSupervisorReplyExecutionMode) ?? .idle

        return supervisorRouteTruthLines(
            configuredModelId: configured,
            actualModelId: actualModelId,
            mode: mode,
            failureReason: failureReason,
            denyCode: denyCode,
            auditRef: auditRef,
            includeConfiguredRoute: includeConfiguredRoute,
            includeRouteState: includeRouteState
        )
    }
}
