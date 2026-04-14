import Foundation

struct XTHeartbeatMemoryAssemblyRef: Equatable, Sendable {
    var refId: String
    var refKind: String
    var title: String
    var sourceScope: String
    var tokenCostHint: String
    var freshnessHint: String
}

enum XTHeartbeatMemoryAssemblySupport {
    static func loadProjection(for ctx: AXProjectContext) -> XTHeartbeatMemoryProjectionArtifact? {
        XTHeartbeatMemoryProjectionStore.load(for: ctx)
    }

    static func anchorLines(
        from artifact: XTHeartbeatMemoryProjectionArtifact?
    ) -> [String] {
        guard let artifact else { return [] }
        let record = artifact.canonicalProjection
        var lines = [
            "heartbeat_status_digest: \(normalized(record.statusDigest, fallback: "(none)"))",
            "heartbeat_current_state: \(normalized(record.currentStateSummary, fallback: "(none)"))",
            "heartbeat_next_step: \(normalized(record.nextStepSummary, fallback: "(none)"))",
            "heartbeat_blocker: \(normalized(record.blockerSummary, fallback: "(none)"))",
            "heartbeat_quality: band=\(record.latestQualityBand?.rawValue ?? "none") score=\(record.latestQualityScore.map(String.init) ?? "none")",
            "heartbeat_open_anomalies: \(joined(record.openAnomalyTypes.map(\.rawValue)))",
            "heartbeat_next_review: kind=\(record.nextReviewKind?.rawValue ?? "none") due=\(record.nextReviewDue) at_ms=\(max(Int64(0), record.nextReviewDueAtMs))",
            "heartbeat_digest_visibility: \(record.digestExplainability.visibility.rawValue)"
        ]
        let digestReasons = joined(record.digestExplainability.reasonCodes)
        if digestReasons != "none" {
            lines.append("heartbeat_digest_reason_codes: \(digestReasons)")
        }
        if let recoveryDecision = record.recoveryDecision {
            lines.append(
                "heartbeat_recovery: action=\(recoveryDecision.action.rawValue) urgency=\(recoveryDecision.urgency.rawValue) reason=\(normalized(recoveryDecision.reasonCode, fallback: "none"))"
            )
        }
        if let projectMemoryContext = artifact.rawPayload.projectMemoryContext {
            lines.append(contentsOf: projectMemoryAnchorLines(from: projectMemoryContext))
        }
        return lines
    }

    static func observationLines(
        from artifact: XTHeartbeatMemoryProjectionArtifact?
    ) -> [String] {
        guard let artifact else { return [] }
        return artifact.observationFacts
            .map { normalized($0) }
            .filter { !$0.isEmpty }
    }

    static func workingSetBlock(
        from artifact: XTHeartbeatMemoryProjectionArtifact?
    ) -> String {
        guard let artifact,
              artifact.workingSetProjection.eligible,
              let digest = artifact.workingSetProjection.digest else {
            return ""
        }
        let record = artifact.canonicalProjection
        var lines = [
            "[heartbeat_digest]",
            projectMemorySourceLine(from: artifact.rawPayload.projectMemoryContext),
            projectMemoryResolutionLine(from: artifact.rawPayload.projectMemoryContext),
            projectMemoryActualSelectionLine(from: artifact.rawPayload.projectMemoryContext),
            projectMemoryDigestLine(from: artifact.rawPayload.projectMemoryContext),
            "visibility: \(digest.visibility.rawValue)",
            "reason_codes: \(joined(artifact.workingSetProjection.reasonCodes))",
            "what_changed: \(normalized(digest.whatChangedText, fallback: "(none)"))",
            "why_important: \(normalized(digest.whyImportantText, fallback: "(none)"))",
            "system_next_step: \(normalized(digest.systemNextStepText, fallback: "(none)"))",
            "open_anomalies: \(joined(record.openAnomalyTypes.map(\.rawValue)))",
            "next_review: kind=\(record.nextReviewKind?.rawValue ?? "none") due=\(record.nextReviewDue) at_ms=\(max(Int64(0), record.nextReviewDueAtMs))"
        ]
        if let recoveryDecision = record.recoveryDecision {
            lines.append(
                "recovery: action=\(recoveryDecision.action.rawValue) urgency=\(recoveryDecision.urgency.rawValue) reason=\(normalized(recoveryDecision.reasonCode, fallback: "none"))"
            )
        }
        lines.append("[/heartbeat_digest]")
        return lines.joined(separator: "\n")
    }

    static func contextRefs(
        from artifact: XTHeartbeatMemoryProjectionArtifact?
    ) -> [XTHeartbeatMemoryAssemblyRef] {
        guard let artifact else { return [] }
        let freshnessHint = projectionFreshnessHint(updatedAtMs: artifact.canonicalProjection.updatedAtMs)
        var refs = [
            XTHeartbeatMemoryAssemblyRef(
                refId: hubHeartbeatSummaryRef(projectId: artifact.projectId),
                refKind: "canonical_ref",
                title: "project heartbeat summary",
                sourceScope: "heartbeat_projection",
                tokenCostHint: "low",
                freshnessHint: freshnessHint
            ),
            XTHeartbeatMemoryAssemblyRef(
                refId: localProjectionRef(projectRoot: artifact.projectRoot),
                refKind: "observation_ref",
                title: "heartbeat memory projection artifact",
                sourceScope: "heartbeat_projection_artifact",
                tokenCostHint: "medium",
                freshnessHint: freshnessHint
            )
        ]
        if let projectMemoryContext = artifact.rawPayload.projectMemoryContext,
           let policyAuditRef = normalizedAuditRef(projectMemoryContext.projectMemoryPolicy?.auditRef) {
            refs.append(
                XTHeartbeatMemoryAssemblyRef(
                    refId: policyAuditRef,
                    refKind: "policy_ref",
                    title: "project memory policy snapshot",
                    sourceScope: "project_memory_policy",
                    tokenCostHint: "low",
                    freshnessHint: freshnessHint
                )
            )
        }
        if let projectMemoryContext = artifact.rawPayload.projectMemoryContext,
           let policyResolutionAuditRef = normalizedAuditRef(
                projectMemoryContext.policyMemoryAssemblyResolution?.auditRef
           ) {
            refs.append(
                XTHeartbeatMemoryAssemblyRef(
                    refId: policyResolutionAuditRef,
                    refKind: "policy_ref",
                    title: "project memory policy resolution",
                    sourceScope: "project_memory_policy_resolution",
                    tokenCostHint: "low",
                    freshnessHint: freshnessHint
                )
            )
        }
        if let projectMemoryContext = artifact.rawPayload.projectMemoryContext,
           let memoryResolutionAuditRef = normalizedAuditRef(
                projectMemoryContext.memoryAssemblyResolution?.auditRef
           ) {
            refs.append(
                XTHeartbeatMemoryAssemblyRef(
                    refId: memoryResolutionAuditRef,
                    refKind: "observation_ref",
                    title: "project memory assembly resolution",
                    sourceScope: "project_memory_resolution",
                    tokenCostHint: "low",
                    freshnessHint: freshnessHint
                )
            )
        }

        var seen = Set<String>()
        return refs.filter { ref in
            let normalizedRef = ref.refId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedRef.isEmpty else { return false }
            return seen.insert(normalizedRef).inserted
        }
    }

    private static func hubHeartbeatSummaryRef(projectId: String) -> String {
        "hub://project/\(projectId)/canonical/xterminal.project.heartbeat.summary_json"
    }

    private static func localProjectionRef(projectRoot: String) -> String {
        URL(fileURLWithPath: projectRoot, isDirectory: true)
            .appendingPathComponent(".xterminal", isDirectory: true)
            .appendingPathComponent("heartbeat_memory_projection.json")
            .path
    }

    private static func projectionFreshnessHint(updatedAtMs: Int64) -> String {
        let updatedAt = Double(max(Int64(0), updatedAtMs)) / 1000.0
        return SupervisorProjectCapsuleBuilder.memoryFreshness(
            updatedAt: updatedAt,
            now: Date().timeIntervalSince1970
        ).rawValue
    }

    private static func joined(_ values: [String]) -> String {
        let normalizedValues = values
            .map { normalized($0) }
            .filter { !$0.isEmpty }
        return normalizedValues.isEmpty ? "none" : normalizedValues.joined(separator: ", ")
    }

    private static func projectMemoryAnchorLines(
        from context: XTHeartbeatProjectMemoryContextSnapshot
    ) -> [String] {
        var lines = [
            "heartbeat_project_memory_source: \(normalized(context.diagnosticsSource, fallback: "unknown"))"
        ]
        if let projectMemoryPolicy = context.projectMemoryPolicy {
            lines.append(
                "heartbeat_project_memory_policy: dialogue=\(projectMemoryPolicy.effectiveRecentProjectDialogueProfile.rawValue) depth=\(projectMemoryPolicy.effectiveProjectContextDepth.rawValue) ceiling=\(projectMemoryPolicy.aTierMemoryCeiling.rawValue)"
            )
        }
        if let effectiveResolution = context.effectiveResolution {
            lines.append(
                "heartbeat_project_memory_resolution: trigger=\(normalized(effectiveResolution.trigger, fallback: "none")) effective_depth=\(normalized(effectiveResolution.effectiveDepth, fallback: "none")) ceiling=\(normalized(effectiveResolution.ceilingFromTier, fallback: "none")) ceiling_hit=\(effectiveResolution.ceilingHit)"
            )
            lines.append(
                "heartbeat_project_memory_actual: serving_objects=\(joined(effectiveResolution.selectedServingObjects)) planes=\(joined(effectiveResolution.selectedPlanes)) slots=\(joined(effectiveResolution.selectedSlots))"
            )
            if !effectiveResolution.excludedBlocks.isEmpty {
                lines.append(
                    "heartbeat_project_memory_excluded: \(joined(effectiveResolution.excludedBlocks))"
                )
            }
        }
        lines.append(projectMemoryDigestLine(from: context, label: "heartbeat_project_memory_digest_in_project_ai"))
        return lines
    }

    private static func projectMemorySourceLine(
        from context: XTHeartbeatProjectMemoryContextSnapshot?
    ) -> String {
        guard let context else { return "project_memory_source: none" }
        return "project_memory_source: \(normalized(context.diagnosticsSource, fallback: "unknown"))"
    }

    private static func projectMemoryResolutionLine(
        from context: XTHeartbeatProjectMemoryContextSnapshot?
    ) -> String {
        guard let effectiveResolution = context?.effectiveResolution else {
            return "project_memory_resolution: none"
        }
        return "project_memory_resolution: trigger=\(normalized(effectiveResolution.trigger, fallback: "none")) effective_depth=\(normalized(effectiveResolution.effectiveDepth, fallback: "none")) ceiling=\(normalized(effectiveResolution.ceilingFromTier, fallback: "none")) ceiling_hit=\(effectiveResolution.ceilingHit)"
    }

    private static func projectMemoryActualSelectionLine(
        from context: XTHeartbeatProjectMemoryContextSnapshot?
    ) -> String {
        guard let effectiveResolution = context?.effectiveResolution else {
            return "project_memory_actual: none"
        }
        return "project_memory_actual: serving_objects=\(joined(effectiveResolution.selectedServingObjects)) planes=\(joined(effectiveResolution.selectedPlanes)) slots=\(joined(effectiveResolution.selectedSlots))"
    }

    private static func projectMemoryDigestLine(
        from context: XTHeartbeatProjectMemoryContextSnapshot?,
        label: String = "project_memory_digest_in_project_ai"
    ) -> String {
        guard let context else { return "\(label): none" }
        var parts = ["present=\(context.heartbeatDigestWorkingSetPresent)"]
        let visibility = normalized(context.heartbeatDigestVisibility)
        if !visibility.isEmpty {
            parts.append("visibility=\(visibility)")
        }
        let reasons = joined(context.heartbeatDigestReasonCodes)
        if reasons != "none" {
            parts.append("reason_codes=\(reasons)")
        }
        return "\(label): \(parts.joined(separator: " "))"
    }

    private static func normalizedAuditRef(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalized(
        _ raw: String,
        fallback: String = ""
    ) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
