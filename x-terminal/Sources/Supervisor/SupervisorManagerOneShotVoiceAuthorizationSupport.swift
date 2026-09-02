import Foundation

extension SupervisorManager {
    func normalizedOneShotFailureReason(_ raw: String?, fallback: String) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return fallback }
        let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        let sanitized = singleLine
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return sanitized.isEmpty ? fallback : sanitized.lowercased()
    }

    func primaryBlockedReason(from report: LaneLaunchReport) -> String {
        let candidates = report.blockedLaneReasons
            .values
            .map { normalizedOneShotFailureReason($0, fallback: "lane_launch_blocked") }
            .sorted()
        return candidates.first ?? "lane_launch_blocked"
    }

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

    func makeVoiceAuthorizationRequestForGuardedOneShotLaunch(
        request: SupervisorOneShotIntakeRequest,
        planDecision: AdaptivePoolPlanDecision
    ) -> SupervisorVoiceAuthorizationRequest {
        let authorizationTypes = request.requiresHumanAuthorizationTypes
        let requestId = oneShotVoiceAuthorizationRequestID(
            requestID: request.requestID,
            authorizationTypes: authorizationTypes
        )
        let riskTier = oneShotVoiceAuthorizationRiskTier(
            authorizationTypes: authorizationTypes,
            riskSurface: planDecision.riskSurface
        )
        let primaryAuthorizationType = oneShotPrimaryVoiceAuthorizationType(authorizationTypes)
        let templateId = oneShotVoiceAuthorizationTemplateID(
            primaryAuthorizationType: primaryAuthorizationType,
            authorizationTypes: authorizationTypes
        )
        let goalSummary = capped(
            request.userGoal.replacingOccurrences(of: "\n", with: " "),
            maxChars: 160
        )
        let poolSummary = planDecision.poolPlan.map(\.poolID).joined(separator: ",")
        let laneSummary = planDecision.poolPlan.flatMap(\.laneIDs).joined(separator: ",")
        let authSummary = authorizationTypes.map(\.rawValue).joined(separator: ",")

        return SupervisorVoiceAuthorizationRequest(
            requestId: requestId,
            projectId: request.projectID,
            templateId: templateId,
            actionText: oneShotVoiceAuthorizationActionText(
                primaryAuthorizationType: primaryAuthorizationType,
                authorizationTypes: authorizationTypes
            ),
            scopeText: [
                "goal=\(goalSummary)",
                "auth_types=\(authSummary)",
                "pools=\(poolSummary.isEmpty ? "none" : poolSummary)",
                "lanes=\(laneSummary.isEmpty ? "none" : laneSummary)"
            ].joined(separator: "; "),
            amountText: oneShotVoiceAuthorizationAmountText(userGoal: request.userGoal),
            riskTier: riskTier,
            boundDeviceId: preferredVoiceBoundDeviceId(for: request.projectID),
            mobileTerminalId: nil,
            challengeCode: nil,
            ttlMs: riskTier >= .high ? 180_000 : 120_000
        )
    }

    func guardedOneShotVoiceAuthorizationFollowUpReply(
        resolution: SupervisorVoiceAuthorizationResolution,
        request: SupervisorVoiceAuthorizationRequest
    ) async -> SupervisorVoiceFollowUpReply? {
        guard resolution.state == .verified,
              isCurrentGuardedOneShotVoiceAuthorization(request),
              let intakeRequest = oneShotIntakeRequest else {
            return nil
        }

        let projectName = heartbeatProjectName(
            for: intakeRequest.projectID,
            in: allProjects()
        ) ?? "当前项目"

        guard let runState = oneShotRunState else {
            let replyText = "语音授权已验证，但 \(projectName) 的 guarded one-shot 当前状态未知；我先不宣称它已经继续执行。"
            return SupervisorVoiceFollowUpReply(
                text: replyText,
                spokenOutcome: speakSupervisorVoiceReply(replyText),
                replySource: "voice_auth_guarded_one_shot_unknown"
            )
        }

        switch runState.state {
        case .running:
            return await guardedOneShotRunningVoiceAuthorizationFollowUpReply(
                intakeRequest: intakeRequest,
                runState: runState,
                projectName: projectName
            )

        case .blocked:
            let blocker = runState.topBlocker.trimmingCharacters(in: .whitespacesAndNewlines)
            let blockerText = blockerReasonText(blocker)
            let replyText = "语音授权已验证，但 \(projectName) 的 guarded one-shot 还没有进入执行；当前阻塞是 \(blockerText)。"
            return SupervisorVoiceFollowUpReply(
                text: replyText,
                spokenOutcome: speakSupervisorVoiceReply(replyText),
                replySource: "voice_auth_guarded_one_shot_blocked"
            )

        case .failedClosed:
            let reason = runState.topBlocker.trimmingCharacters(in: .whitespacesAndNewlines)
            let reasonText = blockerReasonText(reason)
            let replyText = "语音授权已验证，但 \(projectName) 的 guarded one-shot 在恢复启动时已失败闭锁。原因：\(reasonText)。"
            return SupervisorVoiceFollowUpReply(
                text: replyText,
                spokenOutcome: speakSupervisorVoiceReply(replyText),
                replySource: "voice_auth_guarded_one_shot_fail_closed"
            )

        default:
            let summary = runState.userVisibleSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            let replyText: String
            if summary.isEmpty {
                replyText = "语音授权已验证，\(projectName) 的 guarded one-shot 正在接入真实启动链路。"
            } else {
                replyText = "语音授权已验证，\(projectName) 的 guarded one-shot 当前状态：\(summary)。"
            }
            return SupervisorVoiceFollowUpReply(
                text: replyText,
                spokenOutcome: speakSupervisorVoiceReply(replyText),
                replySource: "voice_auth_guarded_one_shot_state"
            )
        }
    }

    func guardedOneShotRunningVoiceAuthorizationFollowUpReply(
        intakeRequest: SupervisorOneShotIntakeRequest,
        runState: OneShotRunStateSnapshot,
        projectName: String
    ) async -> SupervisorVoiceFollowUpReply {
        let request = HubIPCClient.SupervisorBriefProjectionRequestPayload(
            requestId: "voice_guarded_one_shot_follow_up_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.lowercased())",
            projectId: intakeRequest.projectID,
            runId: runState.runID,
            missionId: nil,
            projectionKind: "progress_brief",
            trigger: "critical_path_changed",
            includeTtsScript: true,
            includeCardSummary: true,
            maxEvidenceRefs: 4
        )
        let fetcher = supervisorBriefProjectionRequestOverride
            ?? { payload in
                await HubIPCClient.requestSupervisorBriefProjection(payload)
            }
        let projectionResult = await fetcher(request)
        if projectionResult.ok, let projection = projectionResult.projection {
            let replyText = renderSupervisorBriefProjectionVoiceReply(
                projection,
                projectName: projectName
            )
            let script = projectionVoiceScript(from: projection)
            let spokenOutcome: SupervisorSpeechSynthesizer.Outcome
            if script.isEmpty {
                spokenOutcome = speakSupervisorVoiceReply(replyText)
            } else {
                let job = SupervisorVoiceTTSJob(
                    trigger: projectionVoiceTrigger(from: projection),
                    priority: .normal,
                    script: script,
                    dedupeKey: "guarded-one-shot-follow-up:\(projectionVoiceDedupeKey(from: projection))"
                )
                spokenOutcome = dispatchSupervisorVoiceJob(
                    job,
                    preferences: currentVoicePreferences(),
                    source: "voice_auth_guarded_one_shot_follow_up",
                    suppressRapidSameSourceRepeat: false,
                    cancelPendingHeartbeat: true
                )
            }
            return SupervisorVoiceFollowUpReply(
                text: replyText,
                spokenOutcome: spokenOutcome,
                replySource: "voice_auth_guarded_one_shot_follow_up"
            )
        }

        let presentation = supervisorBriefProjectionUnavailablePresentation(
            projectName: projectName,
            reasonCode: projectionResult.reasonCode,
            localSignal: heartbeatGovernanceVoicePresentation(),
            contextLines: ["guarded one-shot 已进入真实执行。"],
            contextScript: ["guarded one-shot 已进入真实执行。"],
            dedupePrefix: "guarded-one-shot-follow-up"
        )
        return SupervisorVoiceFollowUpReply(
            text: presentation.text,
            spokenOutcome: dispatchSupervisorBriefProjectionUnavailablePresentation(
                presentation,
                trigger: .authorization,
                source: "voice_auth_guarded_one_shot_follow_up"
            ),
            replySource: "voice_auth_guarded_one_shot_follow_up"
        )
    }

    func isCurrentGuardedOneShotVoiceAuthorization(
        _ request: SupervisorVoiceAuthorizationRequest?
    ) -> Bool {
        guard let request,
              let intakeRequest = oneShotIntakeRequest else {
            return false
        }
        let expectedRequestID = oneShotVoiceAuthorizationRequestID(
            requestID: intakeRequest.requestID,
            authorizationTypes: intakeRequest.requiresHumanAuthorizationTypes
        )
        guard request.requestId == expectedRequestID else { return false }
        let projectID = request.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !projectID.isEmpty, projectID == intakeRequest.projectID else {
            return false
        }
        return true
    }
}
