import Foundation

extension SupervisorManager {
    func recentSupervisorSkillGovernanceEvidenceByRequestID(
        ctx: AXProjectContext,
        maxBytes: Int = 256 * 1024
    ) -> [String: SupervisorRecentSkillActivity.GovernanceEvidence] {
        guard let raw = AXProjectSkillActivityStore.loadTailRawLogText(ctx: ctx, maxBytes: maxBytes) else {
            return [:]
        }

        struct LatestEvidence {
            var timestampMs: Int64
            var lineIndex: Int
            var evidence: SupervisorRecentSkillActivity.GovernanceEvidence
        }

        var latestByRequestID: [String: LatestEvidence] = [:]
        for (lineIndex, line) in raw.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            guard let data = line.data(using: .utf8),
                  let value = try? JSONDecoder().decode(JSONValue.self, from: data),
                  case .object(let object) = value,
                  let type = normalizedSupervisorSkillPolicyScalar(object["type"]?.stringValue),
                  type == "supervisor_skill_call" || type == "supervisor_skill_result",
                  let requestID = normalizedSupervisorSkillPolicyScalar(object["request_id"]?.stringValue) else {
                continue
            }

            let toolToken = normalizedSupervisorSkillPolicyScalar(object["tool"]?.stringValue)
                ?? normalizedSupervisorSkillPolicyScalar(object["tool_name"]?.stringValue)
                ?? ""
            let tool = ToolName(rawValue: toolToken)
            let persistedFields = XTGuardrailMessagePresentation.governanceEvidenceFields(
                from: object,
                tool: tool,
                toolLabelOverride: XTPendingApprovalPresentation.displayToolName(raw: toolToken, tool: tool)
            )
            let policySource = normalizedSupervisorSkillPolicyScalar(object["policy_source"]?.stringValue) ?? ""
            let runtimeSurfacePolicyReason = normalizedSupervisorSkillPolicyScalar(
                object["runtime_surface_policy_reason"]?.stringValue
            ) ?? ""
            let policyReason = policySource == "project_autonomy_policy" && !runtimeSurfacePolicyReason.isEmpty
                ? runtimeSurfacePolicyReason
                : (normalizedSupervisorSkillPolicyScalar(object["policy_reason"]?.stringValue) ?? "")
            let evidence = SupervisorRecentSkillActivity.GovernanceEvidence(
                policyReason: policyReason,
                governanceReason: normalizedSupervisorSkillPolicyScalar(persistedFields["governance_reason"]?.stringValue) ?? "",
                blockedSummary: normalizedSupervisorSkillPolicyScalar(persistedFields["blocked_summary"]?.stringValue) ?? "",
                governanceTruth: normalizedSupervisorSkillPolicyScalar(persistedFields["governance_truth"]?.stringValue) ?? "",
                repairAction: normalizedSupervisorSkillPolicyScalar(persistedFields["repair_action"]?.stringValue) ?? ""
            )
            guard evidence.hasAnyValue else { continue }

            let timestampMs = recentSupervisorSkillEvidenceTimestampMs(object: object)
            if let existing = latestByRequestID[requestID] {
                if existing.timestampMs > timestampMs
                    || (existing.timestampMs == timestampMs && existing.lineIndex > lineIndex) {
                    continue
                }
            }
            latestByRequestID[requestID] = LatestEvidence(
                timestampMs: timestampMs,
                lineIndex: lineIndex,
                evidence: evidence
            )
        }

        return latestByRequestID.mapValues(\.evidence)
    }

    func recentSupervisorSkillEvidenceTimestampMs(
        object: [String: JSONValue]
    ) -> Int64 {
        if case .number(let value)? = object["timestamp_ms"] {
            return Int64(value.rounded())
        }
        if case .number(let value)? = object["updated_at_ms"] {
            return Int64(value.rounded())
        }
        if case .string(let text)? = object["timestamp_ms"],
           let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return Int64(value.rounded())
        }
        if case .string(let text)? = object["updated_at_ms"],
           let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return Int64(value.rounded())
        }
        if case .number(let value)? = object["created_at"] {
            return Int64((value * 1000.0).rounded())
        }
        if case .string(let text)? = object["created_at"],
           let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return Int64((value * 1000.0).rounded())
        }
        return 0
    }

    func normalizedSupervisorSkillActivityGovernanceSummary(
        latestReview: SupervisorReviewNoteRecord?,
        latestGuidance: SupervisorGuidanceInjectionRecord?,
        pendingAckGuidance: SupervisorGuidanceInjectionRecord?,
        resolvedGovernance: AXProjectResolvedGovernanceState?
    ) -> SupervisorRecentSkillActivity.GovernanceSummary? {
        let activeGuidance = pendingAckGuidance ?? latestGuidance
        let workOrderRef = normalizedSupervisorGovernanceScalar(
            latestReview?.workOrderRef
                ?? pendingAckGuidance?.workOrderRef
                ?? latestGuidance?.workOrderRef
        )
        let followUpRhythmSummary = resolvedGovernance.map {
            SupervisorReviewPolicyEngine.eventFollowUpCadenceLabel(governance: $0)
        } ?? ""
        let latestReviewId = normalizedSupervisorGovernanceScalar(latestReview?.reviewId)
        let latestGuidanceId = normalizedSupervisorGovernanceScalar(latestGuidance?.injectionId)
        let latestGuidanceSummary = latestGuidance.map {
            SupervisorGuidanceTextPresentation.summary($0.guidanceText, maxChars: 220)
        } ?? ""
        let pendingGuidanceId = normalizedSupervisorGovernanceScalar(pendingAckGuidance?.injectionId)
        let pendingGuidanceSummary = pendingAckGuidance.map {
            SupervisorGuidanceTextPresentation.summary($0.guidanceText, maxChars: 220)
        } ?? ""
        let guidanceReview: SupervisorReviewNoteRecord? = {
            guard let activeGuidance,
                  latestReview?.reviewId == activeGuidance.reviewId else {
                return nil
            }
            return latestReview
        }()
        let guidanceContract = activeGuidance.flatMap { guidance in
            SupervisorGuidanceContractResolver.resolve(
                guidance: guidance,
                reviewNote: guidanceReview
            )
        }
        let hasAnyContext = latestReview != nil
            || latestGuidance != nil
            || pendingAckGuidance != nil
            || !followUpRhythmSummary.isEmpty
            || !workOrderRef.isEmpty
        guard hasAnyContext else { return nil }

        return SupervisorRecentSkillActivity.GovernanceSummary(
            latestReviewId: latestReviewId,
            latestReviewVerdict: latestReview?.verdict,
            latestReviewLevel: latestReview?.reviewLevel,
            configuredExecutionTier: resolvedGovernance?.configuredBundle.executionTier,
            effectiveExecutionTier: resolvedGovernance?.effectiveBundle.executionTier,
            configuredSupervisorTier: resolvedGovernance?.configuredBundle.supervisorInterventionTier,
            effectiveSupervisorTier: latestReview?.effectiveSupervisorTier
                ?? pendingAckGuidance?.effectiveSupervisorTier
                ?? latestGuidance?.effectiveSupervisorTier
                ?? resolvedGovernance?.effectiveBundle.supervisorInterventionTier,
            reviewPolicyMode: resolvedGovernance?.effectiveBundle.reviewPolicyMode,
            progressHeartbeatSeconds: resolvedGovernance?.effectiveBundle.schedule.progressHeartbeatSeconds,
            reviewPulseSeconds: resolvedGovernance?.effectiveBundle.schedule.reviewPulseSeconds,
            brainstormReviewSeconds: resolvedGovernance?.effectiveBundle.schedule.brainstormReviewSeconds,
            compatSource: resolvedGovernance?.compatSource,
            effectiveWorkOrderDepth: latestReview?.effectiveWorkOrderDepth
                ?? pendingAckGuidance?.effectiveWorkOrderDepth
                ?? latestGuidance?.effectiveWorkOrderDepth,
            followUpRhythmSummary: followUpRhythmSummary,
            workOrderRef: workOrderRef,
            latestGuidanceId: latestGuidanceId,
            latestGuidanceDeliveryMode: latestGuidance?.deliveryMode,
            latestGuidanceSummary: latestGuidanceSummary,
            pendingGuidanceId: pendingGuidanceId,
            pendingGuidanceAckStatus: pendingAckGuidance?.ackStatus,
            pendingGuidanceRequired: pendingAckGuidance?.ackRequired ?? false,
            pendingGuidanceSummary: pendingGuidanceSummary,
            guidanceContract: guidanceContract
        )
    }

    func normalizedSupervisorGovernanceScalar(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
