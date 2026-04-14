import Foundation

struct XTHeartbeatProjectMemoryContextSnapshot: Codable, Equatable, Sendable {
    var diagnosticsSource: String
    var projectMemoryPolicy: XTProjectMemoryPolicySnapshot? = nil
    var policyMemoryAssemblyResolution: XTMemoryAssemblyResolution? = nil
    var memoryAssemblyResolution: XTMemoryAssemblyResolution? = nil
    var heartbeatDigestWorkingSetPresent: Bool
    var heartbeatDigestVisibility: String = ""
    var heartbeatDigestReasonCodes: [String] = []

    enum CodingKeys: String, CodingKey {
        case diagnosticsSource = "diagnostics_source"
        case projectMemoryPolicy = "project_memory_policy"
        case policyMemoryAssemblyResolution = "policy_memory_assembly_resolution"
        case memoryAssemblyResolution = "memory_assembly_resolution"
        case heartbeatDigestWorkingSetPresent = "heartbeat_digest_working_set_present"
        case heartbeatDigestVisibility = "heartbeat_digest_visibility"
        case heartbeatDigestReasonCodes = "heartbeat_digest_reason_codes"
    }

    var effectiveResolution: XTMemoryAssemblyResolution? {
        memoryAssemblyResolution ?? policyMemoryAssemblyResolution
    }

    static func from(
        summary: AXProjectContextAssemblyDiagnosticsSummary
    ) -> XTHeartbeatProjectMemoryContextSnapshot? {
        let diagnosticsSource = summary.latestEvent == nil
            ? "config_only"
            : "latest_coder_usage"
        let projectMemoryPolicy = summary.projectMemoryPolicy
        let policyMemoryAssemblyResolution = summary.policyMemoryAssemblyResolution
        let memoryAssemblyResolution = summary.memoryAssemblyResolution
        let heartbeatDigestWorkingSetPresent = summary.latestEvent?.heartbeatDigestWorkingSetPresent ?? false
        let heartbeatDigestVisibility = compact(summary.latestEvent?.heartbeatDigestVisibility)
        let heartbeatDigestReasonCodes = summary.latestEvent?.heartbeatDigestReasonCodes ?? []

        guard !diagnosticsSource.isEmpty
                || projectMemoryPolicy != nil
                || policyMemoryAssemblyResolution != nil
                || memoryAssemblyResolution != nil
                || heartbeatDigestWorkingSetPresent
                || !heartbeatDigestVisibility.isEmpty
                || !heartbeatDigestReasonCodes.isEmpty else {
            return nil
        }

        return XTHeartbeatProjectMemoryContextSnapshot(
            diagnosticsSource: diagnosticsSource,
            projectMemoryPolicy: projectMemoryPolicy,
            policyMemoryAssemblyResolution: policyMemoryAssemblyResolution,
            memoryAssemblyResolution: memoryAssemblyResolution,
            heartbeatDigestWorkingSetPresent: heartbeatDigestWorkingSetPresent,
            heartbeatDigestVisibility: heartbeatDigestVisibility,
            heartbeatDigestReasonCodes: heartbeatDigestReasonCodes
        )
    }

    func detailLines(prefix: String = "heartbeat_project_memory") -> [String] {
        var lines = [
            "\(prefix)_source=\(Self.compact(diagnosticsSource, fallback: "unknown"))"
        ]

        if let projectMemoryPolicy {
            lines.append(
                "\(prefix)_policy_recent_dialogue=configured:\(projectMemoryPolicy.configuredRecentProjectDialogueProfile.rawValue) recommended:\(projectMemoryPolicy.recommendedRecentProjectDialogueProfile.rawValue) effective:\(projectMemoryPolicy.effectiveRecentProjectDialogueProfile.rawValue)"
            )
            lines.append(
                "\(prefix)_policy_context_depth=configured:\(projectMemoryPolicy.configuredProjectContextDepth.rawValue) recommended:\(projectMemoryPolicy.recommendedProjectContextDepth.rawValue) effective:\(projectMemoryPolicy.effectiveProjectContextDepth.rawValue) ceiling:\(projectMemoryPolicy.aTierMemoryCeiling.rawValue)"
            )
        }

        if let policyMemoryAssemblyResolution {
            lines.append(
                "\(prefix)_policy_resolution trigger=\(Self.compact(policyMemoryAssemblyResolution.trigger, fallback: "none")) effective_depth=\(Self.compact(policyMemoryAssemblyResolution.effectiveDepth, fallback: "none")) ceiling=\(Self.compact(policyMemoryAssemblyResolution.ceilingFromTier, fallback: "none")) ceiling_hit=\(policyMemoryAssemblyResolution.ceilingHit)"
            )
        }

        if let memoryAssemblyResolution,
           memoryAssemblyResolution != policyMemoryAssemblyResolution {
            lines.append(
                "\(prefix)_actual_resolution trigger=\(Self.compact(memoryAssemblyResolution.trigger, fallback: "none")) effective_depth=\(Self.compact(memoryAssemblyResolution.effectiveDepth, fallback: "none")) ceiling=\(Self.compact(memoryAssemblyResolution.ceilingFromTier, fallback: "none")) ceiling_hit=\(memoryAssemblyResolution.ceilingHit)"
            )
        }

        if let effectiveResolution {
            lines.append(
                "\(prefix)_actual_selection planes=\(Self.csv(effectiveResolution.selectedPlanes)) slots=\(Self.csv(effectiveResolution.selectedSlots)) serving_objects=\(Self.csv(effectiveResolution.selectedServingObjects))"
            )
            if !effectiveResolution.excludedBlocks.isEmpty {
                lines.append(
                    "\(prefix)_excluded_blocks=\(Self.csv(effectiveResolution.excludedBlocks))"
                )
            }
            if let budgetSummary = effectiveResolution.budgetSummary,
               !Self.compact(budgetSummary).isEmpty {
                lines.append(
                    "\(prefix)_budget_summary=\(Self.compact(budgetSummary))"
                )
            }
        }

        lines.append("\(prefix)_heartbeat_digest_present=\(heartbeatDigestWorkingSetPresent)")
        if !Self.compact(heartbeatDigestVisibility).isEmpty {
            lines.append(
                "\(prefix)_heartbeat_digest_visibility=\(Self.compact(heartbeatDigestVisibility))"
            )
        }
        if !heartbeatDigestReasonCodes.isEmpty {
            lines.append(
                "\(prefix)_heartbeat_digest_reason_codes=\(Self.csv(heartbeatDigestReasonCodes))"
            )
        }
        return lines
    }

    private static func csv(_ values: [String]) -> String {
        let normalized = values
            .map { compact($0) }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? "none" : normalized.joined(separator: ",")
    }

    private static func compact(
        _ raw: String?,
        fallback: String = ""
    ) -> String {
        let trimmed = (raw ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct XTHeartbeatMemoryProjectionRawPayload: Codable, Equatable, Sendable {
    var statusDigest: String
    var currentStateSummary: String
    var nextStepSummary: String
    var blockerSummary: String
    var lastHeartbeatAtMs: Int64
    var latestQualityBand: HeartbeatQualityBand?
    var latestQualityScore: Int?
    var weakReasons: [String]
    var openAnomalyTypes: [HeartbeatAnomalyType]
    var projectPhase: HeartbeatProjectPhase?
    var executionStatus: HeartbeatExecutionStatus?
    var riskTier: HeartbeatRiskTier?
    var cadence: SupervisorCadenceExplainability
    var digestExplainability: XTHeartbeatDigestExplainability
    var recoveryDecision: HeartbeatRecoveryDecision?
    var projectMemoryReadiness: XTProjectMemoryAssemblyReadiness? = nil
    var projectMemoryContext: XTHeartbeatProjectMemoryContextSnapshot? = nil

    enum CodingKeys: String, CodingKey {
        case statusDigest = "status_digest"
        case currentStateSummary = "current_state_summary"
        case nextStepSummary = "next_step_summary"
        case blockerSummary = "blocker_summary"
        case lastHeartbeatAtMs = "last_heartbeat_at_ms"
        case latestQualityBand = "latest_quality_band"
        case latestQualityScore = "latest_quality_score"
        case weakReasons = "weak_reasons"
        case openAnomalyTypes = "open_anomaly_types"
        case projectPhase = "project_phase"
        case executionStatus = "execution_status"
        case riskTier = "risk_tier"
        case cadence
        case digestExplainability = "digest_explainability"
        case recoveryDecision = "recovery_decision"
        case projectMemoryReadiness = "project_memory_readiness"
        case projectMemoryContext = "project_memory_context"
    }
}

struct XTHeartbeatWorkingSetProjection: Codable, Equatable, Sendable {
    var eligible: Bool
    var reasonCodes: [String]
    var digest: XTHeartbeatDigestExplainability?

    enum CodingKeys: String, CodingKey {
        case eligible
        case reasonCodes = "reason_codes"
        case digest
    }
}

struct XTHeartbeatLongtermProjection: Codable, Equatable, Sendable {
    var promotionEligible: Bool
    var patternCodes: [String]
    var reasonCodes: [String]

    enum CodingKeys: String, CodingKey {
        case promotionEligible = "promotion_eligible"
        case patternCodes = "pattern_codes"
        case reasonCodes = "reason_codes"
    }
}

struct XTHeartbeatMemoryProjectionArtifact: Codable, Equatable, Sendable {
    static let schemaVersion = "xt.heartbeat_memory_projection.v1"

    var schemaVersion: String
    var projectId: String
    var projectRoot: String
    var projectName: String
    var createdAtMs: Int64
    var rawVaultRef: String
    var rawPayload: XTHeartbeatMemoryProjectionRawPayload
    var observationFacts: [String]
    var canonicalProjection: SupervisorProjectHeartbeatCanonicalRecord
    var workingSetProjection: XTHeartbeatWorkingSetProjection
    var longtermProjection: XTHeartbeatLongtermProjection
    var refs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case projectRoot = "project_root"
        case projectName = "project_name"
        case createdAtMs = "created_at_ms"
        case rawVaultRef = "raw_vault_ref"
        case rawPayload = "raw_payload"
        case observationFacts = "observation_facts"
        case canonicalProjection = "canonical_projection"
        case workingSetProjection = "working_set_projection"
        case longtermProjection = "longterm_projection"
        case refs
    }
}

enum XTHeartbeatMemoryProjectionStore {
    static func load(for ctx: AXProjectContext) -> XTHeartbeatMemoryProjectionArtifact? {
        guard let data = try? Data(contentsOf: ctx.heartbeatMemoryProjectionURL),
              let artifact = try? JSONDecoder().decode(XTHeartbeatMemoryProjectionArtifact.self, from: data) else {
            return nil
        }
        return artifact
    }

    @discardableResult
    static func record(
        ctx: AXProjectContext,
        snapshot: XTProjectHeartbeatGovernanceDoctorSnapshot,
        schedule: SupervisorReviewScheduleState,
        canonicalRecord: SupervisorProjectHeartbeatCanonicalRecord,
        generatedAtMs: Int64
    ) -> XTHeartbeatMemoryProjectionArtifact? {
        do {
            let candidateArtifact = buildArtifact(
                ctx: ctx,
                snapshot: snapshot,
                schedule: schedule,
                canonicalRecord: canonicalRecord,
                generatedAtMs: generatedAtMs
            )
            let artifact = resolvedArtifactForWrite(
                existing: load(for: ctx),
                candidate: candidateArtifact
            )
            appendRawVaultEntry(
                ctx: ctx,
                artifact: artifact,
                generatedAtMs: generatedAtMs
            )
            let data = try JSONEncoder().encode(artifact)
            try XTStoreWriteSupport.writeSnapshotData(data, to: ctx.heartbeatMemoryProjectionURL)
            return artifact
        } catch {
            AXProjectStore.appendRawLog(
                [
                    "type": "heartbeat_memory_projection",
                    "phase": "failed",
                    "created_at": Double(max(0, generatedAtMs)) / 1000.0,
                    "project_id": snapshot.projectId,
                    "error": String(describing: error)
                ],
                for: ctx
            )
            return nil
        }
    }

    private static func resolvedArtifactForWrite(
        existing: XTHeartbeatMemoryProjectionArtifact?,
        candidate: XTHeartbeatMemoryProjectionArtifact
    ) -> XTHeartbeatMemoryProjectionArtifact {
        guard let existing else { return candidate }
        guard existing.projectId == candidate.projectId,
              existing.projectRoot == candidate.projectRoot else {
            return candidate
        }
        guard shouldPreserveExistingProjection(existing, over: candidate) else {
            return candidate
        }
        return existing
    }

    private static func shouldPreserveExistingProjection(
        _ existing: XTHeartbeatMemoryProjectionArtifact,
        over candidate: XTHeartbeatMemoryProjectionArtifact
    ) -> Bool {
        hasMeaningfulHeartbeatTruth(existing.canonicalProjection) &&
            !hasMeaningfulHeartbeatTruth(candidate.canonicalProjection)
    }

    private static func hasMeaningfulHeartbeatTruth(
        _ record: SupervisorProjectHeartbeatCanonicalRecord
    ) -> Bool {
        meaningfulScalar(record.statusDigest) != nil ||
            meaningfulScalar(record.currentStateSummary) != nil ||
            meaningfulScalar(record.nextStepSummary) != nil ||
            meaningfulScalar(record.blockerSummary) != nil
    }

    private static func meaningfulScalar(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func buildArtifact(
        ctx: AXProjectContext,
        snapshot: XTProjectHeartbeatGovernanceDoctorSnapshot,
        schedule: SupervisorReviewScheduleState,
        canonicalRecord: SupervisorProjectHeartbeatCanonicalRecord,
        generatedAtMs: Int64
    ) -> XTHeartbeatMemoryProjectionArtifact {
        let rawPayload = XTHeartbeatMemoryProjectionRawPayload(
            statusDigest: normalizedScalar(snapshot.statusDigest),
            currentStateSummary: normalizedScalar(snapshot.currentStateSummary),
            nextStepSummary: normalizedScalar(snapshot.nextStepSummary),
            blockerSummary: normalizedScalar(snapshot.blockerSummary),
            lastHeartbeatAtMs: max(0, snapshot.lastHeartbeatAtMs),
            latestQualityBand: snapshot.latestQualityBand,
            latestQualityScore: snapshot.latestQualityScore,
            weakReasons: normalizedTokens(snapshot.weakReasons),
            openAnomalyTypes: snapshot.openAnomalyTypes,
            projectPhase: snapshot.projectPhase,
            executionStatus: snapshot.executionStatus,
            riskTier: snapshot.riskTier,
            cadence: snapshot.cadence,
            digestExplainability: snapshot.digestExplainability,
            recoveryDecision: snapshot.recoveryDecision,
            projectMemoryReadiness: snapshot.projectMemoryReadiness,
            projectMemoryContext: snapshot.projectMemoryContext
        )

        let workingSetProjection = buildWorkingSetProjection(snapshot: snapshot)
        let longtermProjection = buildLongtermProjection(snapshot: snapshot, repeatCount: schedule.lastHeartbeatRepeatCount)
        let refs = dedupeRefs([
            ctx.rawLogURL.path,
            ctx.heartbeatMemoryProjectionURL.path,
            ctx.xterminalDir.appendingPathComponent("supervisor_review_schedule.json").path,
            hubHeartbeatSummaryRef(projectId: snapshot.projectId),
            canonicalRecord.auditRef
        ])

        return XTHeartbeatMemoryProjectionArtifact(
            schemaVersion: XTHeartbeatMemoryProjectionArtifact.schemaVersion,
            projectId: snapshot.projectId,
            projectRoot: ctx.root.path,
            projectName: snapshot.projectName,
            createdAtMs: max(0, generatedAtMs),
            rawVaultRef: ctx.rawLogURL.path,
            rawPayload: rawPayload,
            observationFacts: observationFacts(snapshot: snapshot, canonicalRecord: canonicalRecord),
            canonicalProjection: canonicalRecord,
            workingSetProjection: workingSetProjection,
            longtermProjection: longtermProjection,
            refs: refs
        )
    }

    private static func appendRawVaultEntry(
        ctx: AXProjectContext,
        artifact: XTHeartbeatMemoryProjectionArtifact,
        generatedAtMs: Int64
    ) {
        var entry: [String: Any] = [
            "type": "heartbeat_memory_projection",
            "phase": "raw_vault_write",
            "created_at": Double(max(0, generatedAtMs)) / 1000.0,
            "project_id": artifact.projectId,
            "project_name": artifact.projectName,
            "last_heartbeat_at_ms": artifact.rawPayload.lastHeartbeatAtMs,
            "status_digest": artifact.rawPayload.statusDigest,
            "open_anomaly_types": artifact.rawPayload.openAnomalyTypes.map(\.rawValue),
            "digest_visibility": artifact.rawPayload.digestExplainability.visibility.rawValue,
            "working_set_eligible": artifact.workingSetProjection.eligible,
            "working_set_reason_codes": artifact.workingSetProjection.reasonCodes,
            "longterm_promotion_eligible": artifact.longtermProjection.promotionEligible,
            "longterm_pattern_codes": artifact.longtermProjection.patternCodes,
            "canonical_audit_ref": artifact.canonicalProjection.auditRef,
            "projection_ref": ctx.heartbeatMemoryProjectionURL.path
        ]
        if let latestQualityBand = artifact.rawPayload.latestQualityBand {
            entry["latest_quality_band"] = latestQualityBand.rawValue
        }
        if let latestQualityScore = artifact.rawPayload.latestQualityScore {
            entry["latest_quality_score"] = latestQualityScore
        }
        if let projectMemoryReadiness = artifact.rawPayload.projectMemoryReadiness {
            entry["project_memory_ready"] = projectMemoryReadiness.ready
            entry["project_memory_status_line"] = projectMemoryReadiness.statusLine
            if !projectMemoryReadiness.issueCodes.isEmpty {
                entry["project_memory_issue_codes"] = projectMemoryReadiness.issueCodes
            }
        }
        if let projectMemoryContext = artifact.rawPayload.projectMemoryContext {
            entry["project_memory_diagnostics_source"] = projectMemoryContext.diagnosticsSource
            if let effectiveResolution = projectMemoryContext.effectiveResolution {
                entry["project_memory_effective_depth"] = effectiveResolution.effectiveDepth
                entry["project_memory_resolution_trigger"] = effectiveResolution.trigger
                entry["project_memory_ceiling_from_tier"] = effectiveResolution.ceilingFromTier
                entry["project_memory_ceiling_hit"] = effectiveResolution.ceilingHit
                if !effectiveResolution.selectedPlanes.isEmpty {
                    entry["project_memory_selected_planes"] = effectiveResolution.selectedPlanes
                }
                if !effectiveResolution.selectedServingObjects.isEmpty {
                    entry["project_memory_selected_serving_objects"] = effectiveResolution.selectedServingObjects
                }
            }
            entry["project_memory_heartbeat_digest_present"] = projectMemoryContext.heartbeatDigestWorkingSetPresent
            if !projectMemoryContext.heartbeatDigestVisibility.isEmpty {
                entry["project_memory_heartbeat_digest_visibility"] = projectMemoryContext.heartbeatDigestVisibility
            }
            if !projectMemoryContext.heartbeatDigestReasonCodes.isEmpty {
                entry["project_memory_heartbeat_digest_reason_codes"] = projectMemoryContext.heartbeatDigestReasonCodes
            }
        }
        AXProjectStore.appendRawLog(entry, for: ctx)
    }

    private static func observationFacts(
        snapshot: XTProjectHeartbeatGovernanceDoctorSnapshot,
        canonicalRecord: SupervisorProjectHeartbeatCanonicalRecord
    ) -> [String] {
        var facts: [String] = []
        facts.append(
            "heartbeat_truth status_digest=\(normalizedScalar(snapshot.statusDigest, fallback: "(none)"))"
        )
        facts.append(
            "heartbeat_quality band=\(snapshot.latestQualityBand?.rawValue ?? "none") score=\(snapshot.latestQualityScore.map(String.init) ?? "none") weak_reasons=\(csv(snapshot.weakReasons))"
        )
        facts.append(
            "heartbeat_runtime phase=\(snapshot.projectPhase?.rawValue ?? "none") execution_status=\(snapshot.executionStatus?.rawValue ?? "none") risk_tier=\(snapshot.riskTier?.rawValue ?? "none")"
        )
        facts.append(
            "heartbeat_anomalies open=\(csv(snapshot.openAnomalyTypes.map(\.rawValue)))"
        )
        facts.append(
            "heartbeat_next_review kind=\(canonicalRecord.nextReviewKind?.rawValue ?? "none") at_ms=\(max(Int64(0), canonicalRecord.nextReviewDueAtMs)) due=\(canonicalRecord.nextReviewDue)"
        )
        if !normalizedScalar(snapshot.blockerSummary).isEmpty {
            facts.append(
                "heartbeat_blocker summary=\(normalizedScalar(snapshot.blockerSummary, fallback: "(none)"))"
            )
        }
        if let recoveryDecision = snapshot.recoveryDecision {
            facts.append(
                "heartbeat_recovery action=\(recoveryDecision.action.rawValue) urgency=\(recoveryDecision.urgency.rawValue) reason=\(normalizedScalar(recoveryDecision.reasonCode, fallback: "none"))"
            )
        }
        if let projectMemoryContext = snapshot.projectMemoryContext {
            facts.append(contentsOf: projectMemoryContext.detailLines())
        }
        if let projectMemoryReadiness = snapshot.projectMemoryReadiness {
            facts.append(contentsOf: projectMemoryReadiness.detailLines(prefix: "heartbeat_project_memory"))
        }
        return facts
    }

    private static func buildWorkingSetProjection(
        snapshot: XTProjectHeartbeatGovernanceDoctorSnapshot
    ) -> XTHeartbeatWorkingSetProjection {
        let eligible = snapshot.digestExplainability.visibility == .shown
        var reasonCodes = normalizedTokens(snapshot.digestExplainability.reasonCodes)
        if eligible {
            if reasonCodes.isEmpty {
                reasonCodes = ["digest_visible"]
            }
            return XTHeartbeatWorkingSetProjection(
                eligible: true,
                reasonCodes: reasonCodes,
                digest: snapshot.digestExplainability
            )
        }

        reasonCodes.append("digest_suppressed")
        return XTHeartbeatWorkingSetProjection(
            eligible: false,
            reasonCodes: orderedUnique(reasonCodes),
            digest: nil
        )
    }

    private static func buildLongtermProjection(
        snapshot: XTProjectHeartbeatGovernanceDoctorSnapshot,
        repeatCount: Int
    ) -> XTHeartbeatLongtermProjection {
        let sanitizedRepeatCount = max(0, repeatCount)
        var patternCodes: [String] = []

        if snapshot.latestQualityBand == .hollow, sanitizedRepeatCount >= 3 {
            patternCodes.append("recurring_hollow_progress")
        }
        if snapshot.openAnomalyTypes.contains(.routeFlaky), sanitizedRepeatCount >= 2 {
            patternCodes.append("recurring_route_flaky")
        }
        if snapshot.openAnomalyTypes.contains(.queueStall), sanitizedRepeatCount >= 2 {
            patternCodes.append("recurring_queue_stall")
        }
        if snapshot.openAnomalyTypes.contains(.silentLane), sanitizedRepeatCount >= 2 {
            patternCodes.append("recurring_silent_lane")
        }
        if snapshot.projectPhase == .verify,
           !snapshot.openAnomalyTypes.isEmpty,
           sanitizedRepeatCount >= 2 {
            patternCodes.append("verify_phase_recurring_anomalies")
        }

        patternCodes = orderedUnique(patternCodes)
        let promotionEligible = !patternCodes.isEmpty
        let reasonCodes = promotionEligible
            ? ["recurring_pattern_detected"]
            : ["routine_heartbeat_not_promoted"]

        return XTHeartbeatLongtermProjection(
            promotionEligible: promotionEligible,
            patternCodes: patternCodes,
            reasonCodes: reasonCodes
        )
    }

    private static func hubHeartbeatSummaryRef(projectId: String) -> String {
        "hub://project/\(projectId)/canonical/xterminal.project.heartbeat.summary_json"
    }

    private static func dedupeRefs(_ refs: [String]) -> [String] {
        var seen = Set<String>()
        return refs.filter { ref in
            guard !ref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return seen.insert(ref).inserted
        }
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func csv(_ values: [String]) -> String {
        let normalized = normalizedTokens(values)
        return normalized.isEmpty ? "none" : normalized.joined(separator: ",")
    }

    private static func normalizedTokens(_ values: [String]) -> [String] {
        values
            .map { normalizedScalar($0) }
            .filter { !$0.isEmpty }
    }

    private static func normalizedScalar(
        _ raw: String,
        fallback: String = ""
    ) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
