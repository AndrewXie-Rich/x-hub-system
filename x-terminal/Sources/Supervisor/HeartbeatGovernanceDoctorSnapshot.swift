import Foundation

enum XTHeartbeatDigestVisibilityDecision: String, Codable, Equatable, Sendable {
    case shown
    case suppressed
}

struct XTHeartbeatDigestExplainability: Codable, Equatable, Sendable {
    var visibility: XTHeartbeatDigestVisibilityDecision
    var reasonCodes: [String]
    var whatChangedText: String
    var whyImportantText: String
    var systemNextStepText: String
}

struct XTProjectHeartbeatGovernanceDoctorSnapshot: Equatable, Sendable {
    var projectId: String
    var projectName: String
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

    func detailLines() -> [String] {
        detailLines(projectMemoryReadiness: projectMemoryReadiness)
    }

    func detailLines(
        projectMemoryReadiness: XTProjectMemoryAssemblyReadiness?
    ) -> [String] {
        var lines = [
            "heartbeat_project=\(sanitized(projectName)) (\(projectId))",
            "heartbeat_truth status_digest=\(sanitized(statusDigest, fallback: "(none)"))",
            "heartbeat_current_state=\(sanitized(currentStateSummary, fallback: "(none)"))",
            "heartbeat_next_step=\(sanitized(nextStepSummary, fallback: "(none)"))",
            "heartbeat_blocker=\(sanitized(blockerSummary, fallback: "(none)"))",
            "heartbeat_last_heartbeat_at_ms=\(max(0, lastHeartbeatAtMs))",
            "heartbeat_quality_band=\(latestQualityBand?.rawValue ?? "none")",
            "heartbeat_quality_score=\(latestQualityScore.map(String.init) ?? "none")",
            "heartbeat_quality_weak_reasons=\(csv(weakReasons))",
            "heartbeat_open_anomalies=\(csv(openAnomalyTypes.map(\.rawValue)))",
            "heartbeat_project_phase=\(projectPhase?.rawValue ?? "none")",
            "heartbeat_execution_status=\(executionStatus?.rawValue ?? "none")",
            "heartbeat_risk_tier=\(riskTier?.rawValue ?? "none")",
            "heartbeat_effective_cadence progress=\(cadence.progressHeartbeat.effectiveSeconds)s pulse=\(cadence.reviewPulse.effectiveSeconds)s brainstorm=\(cadence.brainstormReview.effectiveSeconds)s",
            "heartbeat_effective_cadence_reasons progress=\(csv(cadence.progressHeartbeat.effectiveReasonCodes)) pulse=\(csv(cadence.reviewPulse.effectiveReasonCodes)) brainstorm=\(csv(cadence.brainstormReview.effectiveReasonCodes))",
            "heartbeat_digest_visibility=\(digestExplainability.visibility.rawValue)",
            "heartbeat_digest_reason_codes=\(csv(digestExplainability.reasonCodes))",
            "heartbeat_digest_what_changed=\(sanitized(digestExplainability.whatChangedText, fallback: "(none)"))",
            "heartbeat_digest_why_important=\(sanitized(digestExplainability.whyImportantText, fallback: "(none)"))",
            "heartbeat_digest_system_next_step=\(sanitized(digestExplainability.systemNextStepText, fallback: "(none)"))",
            nextReviewDueLine()
        ]
        if let projectMemoryReadiness {
            lines += projectMemoryReadiness.detailLines(prefix: "heartbeat_project_memory")
        }
        if let projectMemoryContext {
            lines += projectMemoryContext.detailLines(prefix: "heartbeat_project_memory")
        }
        if let recoveryDecision {
            lines += recoveryDecision.detailLines()
        }
        return lines
    }

    private func nextReviewDueLine() -> String {
        let candidates = [cadence.reviewPulse, cadence.brainstormReview]
            .filter { $0.effectiveSeconds > 0 }
        guard let next = candidates.min(by: { compareDue(lhs: $0, rhs: $1) }) else {
            return "heartbeat_next_review_due kind=none due=false at_ms=0 reasons=cadence_disabled"
        }
        return "heartbeat_next_review_due kind=\(next.dimension.rawValue) due=\(next.isDue) at_ms=\(max(0, next.nextDueAtMs)) reasons=\(csv(next.nextDueReasonCodes))"
    }

    private func compareDue(
        lhs: SupervisorCadenceDimensionExplainability,
        rhs: SupervisorCadenceDimensionExplainability
    ) -> Bool {
        if lhs.isDue != rhs.isDue {
            return lhs.isDue && !rhs.isDue
        }
        if lhs.nextDueAtMs != rhs.nextDueAtMs {
            return lhs.nextDueAtMs < rhs.nextDueAtMs
        }
        return lhs.dimension.rawValue < rhs.dimension.rawValue
    }

    private func csv(_ values: [String]) -> String {
        let normalized = values
            .map { sanitized($0) }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? "none" : normalized.joined(separator: ",")
    }

    private func sanitized(
        _ raw: String,
        fallback: String = ""
    ) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

enum XTProjectHeartbeatGovernanceDoctorBuilder {
    static func build(
        project: AXProjectEntry,
        context: AXProjectContext,
        config: AXProjectConfig,
        projectMemoryReadiness: XTProjectMemoryAssemblyReadiness? = nil,
        projectMemoryContext: XTHeartbeatProjectMemoryContextSnapshot? = nil,
        laneSnapshot: SupervisorLaneHealthSnapshot? = nil,
        now: Date = Date()
    ) -> XTProjectHeartbeatGovernanceDoctorSnapshot {
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let schedule = SupervisorReviewScheduleStore.load(for: context)
        let governance = xtResolveProjectGovernance(
            projectRoot: context.root,
            config: config,
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy()
        )
        let cadence = SupervisorReviewPolicyEngine.cadenceExplainability(
            governance: governance,
            schedule: schedule,
            nowMs: nowMs
        )
        let openAnomalies = SupervisorReviewPolicyEngine.runtimeOpenAnomalies(
            governance: governance,
            schedule: schedule,
            nowMs: nowMs,
            cadence: cadence
        )
        let blockerDetected = !(project.blockerSummary?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ?? true)
        let reviewCandidate = SupervisorReviewPolicyEngine.heartbeatCandidate(
            governance: governance,
            schedule: schedule,
            blockerDetected: blockerDetected,
            nowMs: nowMs
        )
        let recoveryDecision = SupervisorReviewPolicyEngine.recoveryDecision(
            schedule: schedule,
            laneSnapshot: laneSnapshot,
            reviewCandidate: reviewCandidate,
            openAnomalies: openAnomalies
        )
        let weakReasons = heartbeatWeakReasons(
            schedule: schedule,
            projectMemoryReadiness: projectMemoryReadiness
        )
        let digestExplainability = heartbeatDigestExplainability(
            project: project,
            schedule: schedule,
            cadence: cadence,
            weakReasons: weakReasons,
            openAnomalies: openAnomalies,
            reviewCandidate: reviewCandidate,
            recoveryDecision: recoveryDecision,
            projectMemoryReadiness: projectMemoryReadiness,
            projectMemoryContext: projectMemoryContext
        )

        return XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: project.projectId,
            projectName: project.displayName,
            statusDigest: project.statusDigest ?? "",
            currentStateSummary: project.currentStateSummary ?? "",
            nextStepSummary: project.nextStepSummary ?? "",
            blockerSummary: project.blockerSummary ?? "",
            lastHeartbeatAtMs: schedule.lastHeartbeatAtMs,
            latestQualityBand: schedule.latestQualitySnapshot?.overallBand,
            latestQualityScore: schedule.latestQualitySnapshot?.overallScore,
            weakReasons: weakReasons,
            openAnomalyTypes: openAnomalies.map(\.anomalyType),
            projectPhase: schedule.latestProjectPhase,
            executionStatus: schedule.latestExecutionStatus,
            riskTier: schedule.latestRiskTier,
            cadence: cadence,
            digestExplainability: digestExplainability,
            recoveryDecision: recoveryDecision,
            projectMemoryReadiness: projectMemoryReadiness,
            projectMemoryContext: projectMemoryContext
        )
    }

    private static func heartbeatDigestExplainability(
        project: AXProjectEntry,
        schedule: SupervisorReviewScheduleState,
        cadence: SupervisorCadenceExplainability,
        weakReasons: [String],
        openAnomalies: [HeartbeatAnomalyNote],
        reviewCandidate: SupervisorHeartbeatReviewCandidate?,
        recoveryDecision: HeartbeatRecoveryDecision?,
        projectMemoryReadiness: XTProjectMemoryAssemblyReadiness?,
        projectMemoryContext: XTHeartbeatProjectMemoryContextSnapshot?
    ) -> XTHeartbeatDigestExplainability {
        let blocker = meaningful(project.blockerSummary)
        let currentState = meaningful(project.currentStateSummary)
        let nextStep = meaningful(project.nextStepSummary)
        let statusDigest = meaningful(project.statusDigest)
        let anomalyTypes = openAnomalies.map(\.anomalyType)
        let qualityBand = schedule.latestQualitySnapshot?.overallBand
        let riskTier = schedule.latestRiskTier
        let reviewDue = cadence.reviewPulse.isDue || cadence.brainstormReview.isDue
        let projectMemoryNeedsAttention = projectMemoryReadiness?.ready == false

        var reasonCodes: [String] = []
        if blocker != nil {
            reasonCodes.append("blocker_present")
        }
        if anomalyTypes.contains(.weakDoneClaim) {
            reasonCodes.append("weak_done_claim")
        }
        if anomalyTypes.contains(.missingHeartbeat) {
            reasonCodes.append("missing_heartbeat")
        }
        if !anomalyTypes.isEmpty {
            reasonCodes.append("open_anomalies_present")
        }
        if reviewCandidate != nil {
            reasonCodes.append("review_candidate_active")
        }
        if reviewDue {
            reasonCodes.append("next_review_window_active")
        }
        if recoveryDecision != nil {
            reasonCodes.append("recovery_decision_active")
        }
        if riskTier == .high {
            reasonCodes.append("risk_high")
        }
        if qualityBand == .weak {
            reasonCodes.append("quality_weak")
        }
        if schedule.latestExecutionStatus == .doneCandidate {
            reasonCodes.append("done_candidate_status")
        }
        if let projectMemoryContext {
            switch meaningful(projectMemoryContext.diagnosticsSource) {
            case "latest_coder_usage":
                reasonCodes.append("project_memory_truth_latest_coder_usage")
            case "config_only":
                reasonCodes.append("project_memory_truth_config_only")
            case let source?:
                reasonCodes.append("project_memory_truth_\(source)")
            case nil:
                break
            }
            if projectMemoryContext.heartbeatDigestWorkingSetPresent {
                reasonCodes.append("project_memory_digest_in_project_ai")
            }
        }

        var advisoryReasonCodes: [String] = []
        if projectMemoryNeedsAttention {
            advisoryReasonCodes.append("project_memory_attention")
        }

        let visibility: XTHeartbeatDigestVisibilityDecision
        if reasonCodes.isEmpty {
            visibility = .suppressed
            reasonCodes = hasUserFacingTruth(
                statusDigest: statusDigest,
                currentState: currentState,
                nextStep: nextStep
            ) ? ["stable_runtime_update_suppressed"] : ["heartbeat_truth_sparse"]
        } else {
            visibility = .shown
        }
        reasonCodes = orderedUnique(reasonCodes + advisoryReasonCodes)

        let whatChangedText: String
        if let blocker {
            whatChangedText = blocker
        } else if anomalyTypes.contains(.weakDoneClaim) {
            whatChangedText = "项目已接近完成，但完成声明证据偏弱。"
        } else if anomalyTypes.contains(.missingHeartbeat) {
            whatChangedText = "最近 heartbeat 已超出预期窗口。"
        } else if let currentState {
            whatChangedText = currentState
        } else if let statusDigest {
            whatChangedText = statusDigest
        } else if let topIssue = projectMemoryReadiness?.topIssue, projectMemoryNeedsAttention {
            whatChangedText = topIssue.summary
        } else {
            whatChangedText = "当前项目状态没有新的高信号变化。"
        }

        let whyImportantText: String
        if blocker != nil {
            whyImportantText = "项目推进已经被 blocker 挡住，如果继续静默等待只会让阻塞累积。"
        } else if anomalyTypes.contains(.weakDoneClaim) {
            whyImportantText = "完成声明证据偏弱，系统不能把“快做完了”直接当成真实完成。"
        } else if anomalyTypes.contains(.missingHeartbeat) {
            whyImportantText = "这说明当前项目可能已静默、空转，或者运行链路本身出了问题。"
        } else if reviewCandidate != nil {
            whyImportantText = "Supervisor 已判断需要额外 review，当前不适合继续盲跑。"
        } else if recoveryDecision != nil {
            whyImportantText = "系统已判断需要恢复或补救动作，不能把当前状态当成正常推进。"
        } else if riskTier == .high {
            whyImportantText = "当前风险等级较高，就算表面稳定也不该完全静默。"
        } else if qualityBand == .weak {
            whyImportantText = "这次 heartbeat 质量偏弱，当前状态还缺足够强的证据支撑。"
        } else if projectMemoryNeedsAttention {
            whyImportantText = "Project AI 的 memory assembly truth 还不完整。Heartbeat 已把这条信号并入治理 explainability，但不会绕过既有 review / gate 链。"
        } else {
            whyImportantText = "当前没有新的高风险或高优先级治理信号，所以这条 digest 被压制。"
        }
        let whyImportantSuffix = projectMemoryContextWhyImportantSuffix(projectMemoryContext)
        let resolvedWhyImportantText = [whyImportantText, whyImportantSuffix]
            .compactMap { meaningful($0) }
            .joined(separator: " ")

        let systemNextStepText: String
        if let nextStep {
            systemNextStepText = nextStep
        } else if let recoveryDecision {
            systemNextStepText = recoveryDecision.userFacingSystemNextStepText()
        } else if let reviewCandidate {
            systemNextStepText = queuedReviewNextStep(reviewCandidate)
        } else if projectMemoryNeedsAttention {
            systemNextStepText = "系统会继续维持当前 heartbeat 节奏，并等待后续 coder usage 补齐 machine-readable memory assembly truth。"
        } else if visibility == .suppressed {
            systemNextStepText = "系统会继续观察当前项目，有实质变化再生成用户 digest。"
        } else {
            systemNextStepText = "系统会继续观察当前项目，并在下一次 heartbeat 再重新评估。"
        }
        let systemNextStepSuffix = projectMemoryContextNextStepSuffix(
            projectMemoryContext,
            reviewCandidate: reviewCandidate
        )
        let resolvedSystemNextStepText = [systemNextStepText, systemNextStepSuffix]
            .compactMap { meaningful($0) }
            .joined(separator: " ")

        return XTHeartbeatDigestExplainability(
            visibility: visibility,
            reasonCodes: reasonCodes,
            whatChangedText: whatChangedText,
            whyImportantText: resolvedWhyImportantText,
            systemNextStepText: resolvedSystemNextStepText
        )
    }

    private static func projectMemoryContextWhyImportantSuffix(
        _ context: XTHeartbeatProjectMemoryContextSnapshot?
    ) -> String? {
        guard let context else { return nil }

        var parts: [String] = []
        switch meaningful(context.diagnosticsSource) {
        case "latest_coder_usage":
            parts.append("这次治理判断已对齐到 Project AI 最近一轮 latest coder usage memory truth。")
        case "config_only":
            parts.append("当前还只有 config-only baseline，这次治理判断后续还会继续等待 recent coder usage 把 memory truth 补齐。")
        case let source?:
            parts.append("这次治理判断已附带 Project AI 的 memory truth 来源：\(source)。")
        case nil:
            break
        }

        if let effectiveDepth = context.effectiveResolution.flatMap({ meaningful($0.effectiveDepth) }) {
            parts.append("当前 effective depth=\(effectiveDepth)。")
        }
        if context.heartbeatDigestWorkingSetPresent {
            parts.append("heartbeat digest 已在 Project AI working set 中。")
        }

        let merged = parts.joined(separator: " ")
        return meaningful(merged)
    }

    private static func projectMemoryContextNextStepSuffix(
        _ context: XTHeartbeatProjectMemoryContextSnapshot?,
        reviewCandidate: SupervisorHeartbeatReviewCandidate?
    ) -> String? {
        guard let context else { return nil }
        if context.heartbeatDigestWorkingSetPresent, reviewCandidate != nil {
            return "系统会沿这份 memory truth 在 safe point 注入 guidance，不再额外重复灌入同一份 heartbeat digest。"
        }
        if reviewCandidate != nil,
           meaningful(context.heartbeatDigestVisibility) != nil,
           !context.heartbeatDigestWorkingSetPresent {
            return "系统会继续沿当前治理链把 heartbeat digest 补进 Project AI working set，而不是绕过既有 review / gate 边界。"
        }
        return nil
    }

    private static func hasUserFacingTruth(
        statusDigest: String?,
        currentState: String?,
        nextStep: String?
    ) -> Bool {
        [statusDigest, currentState, nextStep].contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func meaningful(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered
    }

    private static func heartbeatWeakReasons(
        schedule: SupervisorReviewScheduleState,
        projectMemoryReadiness: XTProjectMemoryAssemblyReadiness?
    ) -> [String] {
        var reasons = schedule.latestQualitySnapshot?.weakReasons ?? []
        if projectMemoryReadiness?.ready == false {
            reasons.append("project_memory_attention")
        }
        return orderedUnique(reasons)
    }

    private static func queuedReviewNextStep(
        _ candidate: SupervisorHeartbeatReviewCandidate
    ) -> String {
        HeartbeatRecoveryUserFacingText.queuedReviewNextStep(
            reviewLevel: candidate.reviewLevel,
            trigger: candidate.trigger,
            runKind: candidate.runKind
        )
    }
}
