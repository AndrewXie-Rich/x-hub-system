import Foundation

enum XTGovernanceTruthPresentation {
    static func snapshotFields(
        from rawObject: [String: JSONValue]
    ) -> [String: JSONValue] {
        let governanceObject = jsonObjectValue(rawObject["governance"])
        var snapshot: [String: JSONValue] = [:]

        setSnapshotField(
            &snapshot,
            key: "execution_tier",
            value: preferredJSONValue(
                rawObject["execution_tier"],
                governanceObject["configured_execution_tier"]
            )
        )
        setSnapshotField(
            &snapshot,
            key: "effective_execution_tier",
            value: preferredJSONValue(
                rawObject["effective_execution_tier"],
                governanceObject["effective_execution_tier"]
            )
        )
        setSnapshotField(
            &snapshot,
            key: "supervisor_intervention_tier",
            value: preferredJSONValue(
                rawObject["supervisor_intervention_tier"],
                governanceObject["configured_supervisor_tier"]
            )
        )
        setSnapshotField(
            &snapshot,
            key: "effective_supervisor_intervention_tier",
            value: preferredJSONValue(
                rawObject["effective_supervisor_intervention_tier"],
                governanceObject["effective_supervisor_tier"]
            )
        )
        setSnapshotField(
            &snapshot,
            key: "review_policy_mode",
            value: preferredJSONValue(
                rawObject["review_policy_mode"],
                governanceObject["review_policy_mode"]
            )
        )
        setSnapshotField(
            &snapshot,
            key: "progress_heartbeat_sec",
            value: preferredJSONValue(
                rawObject["progress_heartbeat_sec"],
                governanceObject["progress_heartbeat_sec"]
            )
        )
        setSnapshotField(
            &snapshot,
            key: "review_pulse_sec",
            value: preferredJSONValue(
                rawObject["review_pulse_sec"],
                governanceObject["review_pulse_sec"]
            )
        )
        setSnapshotField(
            &snapshot,
            key: "brainstorm_review_sec",
            value: preferredJSONValue(
                rawObject["brainstorm_review_sec"],
                governanceObject["brainstorm_review_sec"]
            )
        )
        setSnapshotField(
            &snapshot,
            key: "governance_compat_source",
            value: preferredJSONValue(
                rawObject["governance_compat_source"],
                rawObject["compat_source"],
                governanceObject["compat_source"]
            )
        )

        return snapshot
    }

    static func truthLine(
        from rawObject: [String: JSONValue]
    ) -> String? {
        guard let summary = effectiveTierSummary(from: rawObject) else { return nil }
        return "治理真相：\(summary)。"
    }

    static func effectiveTierSummary(
        from rawObject: [String: JSONValue]
    ) -> String? {
        let snapshot = snapshotFields(from: rawObject)
        guard !snapshot.isEmpty else { return nil }
        return effectiveTierSummary(
            configuredExecutionTier: stringValue(snapshot["execution_tier"]),
            effectiveExecutionTier: stringValue(snapshot["effective_execution_tier"]),
            configuredSupervisorTier: stringValue(snapshot["supervisor_intervention_tier"]),
            effectiveSupervisorTier: stringValue(snapshot["effective_supervisor_intervention_tier"]),
            reviewPolicyMode: stringValue(snapshot["review_policy_mode"]),
            progressHeartbeatSeconds: intValue(snapshot["progress_heartbeat_sec"]),
            reviewPulseSeconds: intValue(snapshot["review_pulse_sec"]),
            brainstormReviewSeconds: intValue(snapshot["brainstorm_review_sec"]),
            compatSource: stringValue(snapshot["governance_compat_source"])
        )
    }

    static func effectiveTierSummary(
        configuredExecutionTier: String? = nil,
        effectiveExecutionTier: String?,
        configuredSupervisorTier: String? = nil,
        effectiveSupervisorTier: String?,
        reviewPolicyMode: String? = nil,
        progressHeartbeatSeconds: Int? = nil,
        reviewPulseSeconds: Int? = nil,
        brainstormReviewSeconds: Int? = nil,
        compatSource: String? = nil
    ) -> String? {
        let configuredExecution = executionTier(from: configuredExecutionTier)
        let effectiveExecution = executionTier(from: effectiveExecutionTier) ?? configuredExecution
        let configuredSupervisor = supervisorTier(from: configuredSupervisorTier)
        let effectiveSupervisor = supervisorTier(from: effectiveSupervisorTier) ?? configuredSupervisor

        guard let effectivePair = tierPairLabel(
            executionTier: effectiveExecution,
            supervisorTier: effectiveSupervisor
        ) else {
            return nil
        }

        var parts: [String] = []
        if let configuredPair = tierPairLabel(
            executionTier: configuredExecution,
            supervisorTier: configuredSupervisor
        ),
           configuredPair != effectivePair {
            parts.append("预设 \(configuredPair)")
            parts.append("当前生效 \(effectivePair)")
        } else {
            parts.append("当前生效 \(effectivePair)")
        }

        if let reviewMode = reviewPolicyModeValue(from: reviewPolicyMode) {
            parts.append("审查 \(reviewMode.shortLabel)")
        }
        if let cadenceSummary = cadenceSummary(
            progressHeartbeatSeconds: progressHeartbeatSeconds,
            reviewPulseSeconds: reviewPulseSeconds,
            brainstormReviewSeconds: brainstormReviewSeconds
        ) {
            parts.append(cadenceSummary)
        }
        if let compatSourceSummary = compatSourceSummary(from: compatSource) {
            parts.append("来源 \(compatSourceSummary)")
        }

        return parts.joined(separator: " · ")
    }

    static func truthLine(
        configuredExecutionTier: String? = nil,
        effectiveExecutionTier: String?,
        configuredSupervisorTier: String? = nil,
        effectiveSupervisorTier: String?,
        reviewPolicyMode: String? = nil,
        progressHeartbeatSeconds: Int? = nil,
        reviewPulseSeconds: Int? = nil,
        brainstormReviewSeconds: Int? = nil,
        compatSource: String? = nil
    ) -> String? {
        guard let summary = effectiveTierSummary(
            configuredExecutionTier: configuredExecutionTier,
            effectiveExecutionTier: effectiveExecutionTier,
            configuredSupervisorTier: configuredSupervisorTier,
            effectiveSupervisorTier: effectiveSupervisorTier,
            reviewPolicyMode: reviewPolicyMode,
            progressHeartbeatSeconds: progressHeartbeatSeconds,
            reviewPulseSeconds: reviewPulseSeconds,
            brainstormReviewSeconds: brainstormReviewSeconds,
            compatSource: compatSource
        ) else {
            return nil
        }
        return "治理真相：\(summary)。"
    }

    private static func executionTier(from raw: String?) -> AXProjectExecutionTier? {
        normalized(raw).flatMap(AXProjectExecutionTier.init(rawValue:))
    }

    private static func supervisorTier(from raw: String?) -> AXProjectSupervisorInterventionTier? {
        normalized(raw).flatMap(AXProjectSupervisorInterventionTier.init(rawValue:))
    }

    private static func reviewPolicyModeValue(from raw: String?) -> AXProjectReviewPolicyMode? {
        normalized(raw).flatMap(AXProjectReviewPolicyMode.init(rawValue:))
    }

    private static func tierPairLabel(
        executionTier: AXProjectExecutionTier?,
        supervisorTier: AXProjectSupervisorInterventionTier?
    ) -> String? {
        switch (executionTier, supervisorTier) {
        case let (.some(executionTier), .some(supervisorTier)):
            return "\(executionTier.shortToken)/\(supervisorTier.shortToken)"
        case let (.some(executionTier), .none):
            return executionTier.shortToken
        case let (.none, .some(supervisorTier)):
            return supervisorTier.shortToken
        case (.none, .none):
            return nil
        }
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cadenceSummary(
        progressHeartbeatSeconds: Int?,
        reviewPulseSeconds: Int?,
        brainstormReviewSeconds: Int?
    ) -> String? {
        var parts: [String] = []

        if let progressHeartbeatSeconds {
            parts.append("心跳 \(durationLabel(progressHeartbeatSeconds))")
        }
        if let reviewPulseSeconds {
            parts.append("脉冲 \(durationLabel(reviewPulseSeconds))")
        }
        if let brainstormReviewSeconds {
            parts.append("脑暴 \(durationLabel(brainstormReviewSeconds))")
        }

        guard !parts.isEmpty else { return nil }
        return "节奏 " + parts.joined(separator: " / ")
    }

    private static func compatSourceSummary(from raw: String?) -> String? {
        guard let normalized = normalized(raw) else { return nil }

        switch AXProjectGovernanceCompatSource(rawValue: normalized) {
        case .explicitDualDial:
            return nil
        case .legacyAutonomyLevel:
            return "兼容旧项目卡片档位"
        case .legacyAutonomyMode:
            return "兼容旧执行面预设"
        case .defaultConservative:
            return "默认保守基线"
        case nil:
            switch normalized {
            case "ui_draft", "multi_project_detail":
                return nil
            default:
                return normalized
            }
        }
    }

    private static func durationLabel(_ seconds: Int) -> String {
        guard seconds > 0 else { return "off" }
        if seconds % 3600 == 0 {
            return "\(seconds / 3600)h"
        }
        return "\(max(1, seconds / 60))m"
    }

    private static func preferredJSONValue(
        _ candidates: JSONValue?...
    ) -> JSONValue? {
        candidates
            .compactMap { $0 }
            .first(where: isMeaningful)
    }

    private static func setSnapshotField(
        _ snapshot: inout [String: JSONValue],
        key: String,
        value: JSONValue?
    ) {
        guard let value else { return }
        snapshot[key] = value
    }

    private static func isMeaningful(_ value: JSONValue?) -> Bool {
        switch value {
        case .string(let raw)?:
            return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .number?, .bool?, .array?, .object?:
            return true
        default:
            return false
        }
    }

    private static func stringValue(_ value: JSONValue?) -> String? {
        guard let trimmed = value?
            .stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func intValue(_ value: JSONValue?) -> Int? {
        switch value {
        case .number(let number):
            return Int(number)
        case .string(let raw):
            return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func jsonObjectValue(_ value: JSONValue?) -> [String: JSONValue] {
        guard case .object(let object)? = value else { return [:] }
        return object
    }
}
