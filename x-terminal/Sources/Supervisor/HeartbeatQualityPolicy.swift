import Foundation

enum HeartbeatProjectPhase: String, Codable, CaseIterable, Sendable {
    case explore
    case plan
    case build
    case verify
    case release

    var displayName: String {
        rawValue.capitalized
    }
}

enum HeartbeatExecutionStatus: String, Codable, CaseIterable, Sendable {
    case active
    case blocked
    case stalled
    case doneCandidate = "done_candidate"

    var displayName: String {
        switch self {
        case .active:
            return "Active"
        case .blocked:
            return "Blocked"
        case .stalled:
            return "Stalled"
        case .doneCandidate:
            return "Done Candidate"
        }
    }
}

enum HeartbeatRiskTier: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case critical

    var displayName: String {
        rawValue.capitalized
    }

    var rank: Int {
        switch self {
        case .low:
            return 0
        case .medium:
            return 1
        case .high:
            return 2
        case .critical:
            return 3
        }
    }
}

enum HeartbeatQualityBand: String, Codable, CaseIterable, Sendable {
    case strong
    case usable
    case weak
    case hollow

    var displayName: String {
        switch self {
        case .strong:
            return "Strong"
        case .usable:
            return "Usable"
        case .weak:
            return "Weak"
        case .hollow:
            return "Hollow"
        }
    }

    var rank: Int {
        switch self {
        case .strong:
            return 3
        case .usable:
            return 2
        case .weak:
            return 1
        case .hollow:
            return 0
        }
    }

    fileprivate func clamped(toMaximum maximumBand: HeartbeatQualityBand) -> HeartbeatQualityBand {
        rank > maximumBand.rank ? maximumBand : self
    }
}

enum HeartbeatAnomalySeverity: String, Codable, CaseIterable, Sendable {
    case watch
    case concern
    case high
    case critical

    var displayName: String {
        switch self {
        case .watch:
            return "Watch"
        case .concern:
            return "Concern"
        case .high:
            return "High"
        case .critical:
            return "Critical"
        }
    }

    var rank: Int {
        switch self {
        case .watch:
            return 0
        case .concern:
            return 1
        case .high:
            return 2
        case .critical:
            return 3
        }
    }
}

enum HeartbeatAnomalyEscalation: String, Codable, CaseIterable, Sendable {
    case observe
    case pulseReview = "pulse_review"
    case strategicReview = "strategic_review"
    case rescueReview = "rescue_review"
    case replan
    case stop
}

enum HeartbeatAnomalyType: String, Codable, CaseIterable, Sendable {
    case missingHeartbeat = "missing_heartbeat"
    case staleRepeat = "stale_repeat"
    case hollowProgress = "hollow_progress"
    case queueStall = "queue_stall"
    case weakBlocker = "weak_blocker"
    case weakDoneClaim = "weak_done_claim"
    case routeFlaky = "route_flaky"
    case silentLane = "silent_lane"
    case driftSuspected = "drift_suspected"

    var displayName: String {
        switch self {
        case .missingHeartbeat:
            return "Missing Heartbeat"
        case .staleRepeat:
            return "Stale Repeat"
        case .hollowProgress:
            return "Hollow Progress"
        case .queueStall:
            return "Queue Stall"
        case .weakBlocker:
            return "Weak Blocker"
        case .weakDoneClaim:
            return "Weak Done Claim"
        case .routeFlaky:
            return "Route Flaky"
        case .silentLane:
            return "Silent Lane"
        case .driftSuspected:
            return "Drift Suspected"
        }
    }
}

struct HeartbeatQualitySnapshot: Equatable, Codable, Sendable {
    var overallScore: Int
    var overallBand: HeartbeatQualityBand
    var freshnessScore: Int
    var deltaSignificanceScore: Int
    var evidenceStrengthScore: Int
    var blockerClarityScore: Int
    var nextActionSpecificityScore: Int
    var executionVitalityScore: Int
    var completionConfidenceScore: Int
    var weakReasons: [String]
    var computedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case overallScore = "overall_score"
        case overallBand = "overall_band"
        case freshnessScore = "freshness_score"
        case deltaSignificanceScore = "delta_significance_score"
        case evidenceStrengthScore = "evidence_strength_score"
        case blockerClarityScore = "blocker_clarity_score"
        case nextActionSpecificityScore = "next_action_specificity_score"
        case executionVitalityScore = "execution_vitality_score"
        case completionConfidenceScore = "completion_confidence_score"
        case weakReasons = "weak_reasons"
        case computedAtMs = "computed_at_ms"
    }
}

struct HeartbeatAnomalyNote: Equatable, Codable, Sendable, Identifiable {
    var anomalyId: String
    var projectId: String
    var anomalyType: HeartbeatAnomalyType
    var severity: HeartbeatAnomalySeverity
    var confidence: Double
    var reason: String
    var evidenceRefs: [String]
    var detectedAtMs: Int64
    var recommendedEscalation: HeartbeatAnomalyEscalation

    var id: String { anomalyId }

    enum CodingKeys: String, CodingKey {
        case anomalyId = "anomaly_id"
        case projectId = "project_id"
        case anomalyType = "anomaly_type"
        case severity
        case confidence
        case reason
        case evidenceRefs = "evidence_refs"
        case detectedAtMs = "detected_at_ms"
        case recommendedEscalation = "recommended_escalation"
    }
}

struct HeartbeatAssessmentResult: Equatable, Sendable {
    var meaningfulProgressAtMs: Int64?
    var qualitySnapshot: HeartbeatQualitySnapshot
    var openAnomalies: [HeartbeatAnomalyNote]
    var heartbeatFingerprint: String
    var repeatCount: Int
    var projectPhase: HeartbeatProjectPhase
    var executionStatus: HeartbeatExecutionStatus
    var riskTier: HeartbeatRiskTier

    init(
        meaningfulProgressAtMs: Int64? = nil,
        qualitySnapshot: HeartbeatQualitySnapshot,
        openAnomalies: [HeartbeatAnomalyNote],
        heartbeatFingerprint: String,
        repeatCount: Int,
        projectPhase: HeartbeatProjectPhase = .explore,
        executionStatus: HeartbeatExecutionStatus = .active,
        riskTier: HeartbeatRiskTier = .low
    ) {
        self.meaningfulProgressAtMs = meaningfulProgressAtMs
        self.qualitySnapshot = qualitySnapshot
        self.openAnomalies = openAnomalies
        self.heartbeatFingerprint = heartbeatFingerprint
        self.repeatCount = repeatCount
        self.projectPhase = projectPhase
        self.executionStatus = executionStatus
        self.riskTier = riskTier
    }
}

enum HeartbeatQualityPolicy {
    static func assess(
        project: AXProjectEntry,
        previousState: SupervisorReviewScheduleState,
        blockerDetected: Bool,
        nowMs: Int64
    ) -> HeartbeatAssessmentResult {
        let digest = normalizedText(project.statusDigest)
        let currentState = normalizedText(project.currentStateSummary, fallback: digest)
        let nextStep = normalizedText(project.nextStepSummary)
        let blocker = normalizedText(project.blockerSummary)
        let combined = [digest, currentState, nextStep, blocker]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let combinedLower = combined.lowercased()

        let progressAtMs = projectObservedProgressAtMs(project)
        let observedProgressAdvanced = progressAtMs > previousState.lastObservedProgressAtMs
        let fingerprint = [digest, currentState, nextStep, blocker]
            .map { normalizedFingerprintToken($0) }
            .joined(separator: "|")
        let contentChanged = !fingerprint.isEmpty && fingerprint != previousState.lastHeartbeatFingerprint
        let repeatCount: Int
        if !fingerprint.isEmpty && fingerprint == previousState.lastHeartbeatFingerprint && !observedProgressAdvanced {
            repeatCount = previousState.lastHeartbeatRepeatCount + 1
        } else {
            repeatCount = 0
        }

        let doneClaim = looksLikeDoneClaim(combinedLower)
        let evidenceStrong = containsEvidenceSignal(combinedLower)
        let queueStallCue = containsQueueStallCue(blocker.lowercased(), combinedLower)
        let freshnessBaseMs = max(progressAtMs, previousState.lastObservedProgressAtMs)
        let progressAgeMs = freshnessBaseMs > 0 ? max(0, nowMs - freshnessBaseMs) : Int64.max

        let freshnessScore = freshnessScore(progressAgeMs: progressAgeMs)
        let deltaSignificanceScore: Int
        if observedProgressAdvanced {
            deltaSignificanceScore = 95
        } else if contentChanged {
            deltaSignificanceScore = genericNextStep(nextStep) ? 45 : 72
        } else if repeatCount > 0 {
            deltaSignificanceScore = 12
        } else {
            deltaSignificanceScore = 28
        }

        let evidenceStrengthScore: Int
        if evidenceStrong {
            evidenceStrengthScore = 88
        } else if doneClaim {
            evidenceStrengthScore = 18
        } else if observedProgressAdvanced {
            evidenceStrengthScore = 58
        } else {
            evidenceStrengthScore = 26
        }

        let blockerClarityScore: Int
        if blocker.isEmpty {
            blockerClarityScore = 72
        } else if genericBlocker(blocker) {
            blockerClarityScore = 24
        } else if blocker.count >= 18 || blocker.contains("需要") || blocker.contains("waiting") || blocker.contains("grant") {
            blockerClarityScore = 82
        } else {
            blockerClarityScore = 58
        }

        let nextActionSpecificityScore: Int
        if nextStep.isEmpty {
            nextActionSpecificityScore = 18
        } else if genericNextStep(nextStep) {
            nextActionSpecificityScore = 18
        } else if containsSpecificActionCue(nextStep.lowercased()) {
            nextActionSpecificityScore = 84
        } else {
            nextActionSpecificityScore = 62
        }

        let executionVitalityScore: Int
        if observedProgressAdvanced {
            executionVitalityScore = 92
        } else if repeatCount >= 2 {
            executionVitalityScore = 8
        } else if blockerDetected {
            executionVitalityScore = 44
        } else if contentChanged {
            executionVitalityScore = 56
        } else {
            executionVitalityScore = 18
        }

        let completionConfidenceScore: Int
        if doneClaim {
            completionConfidenceScore = evidenceStrong ? 86 : 14
        } else if evidenceStrong && (combinedLower.contains("verify") || combinedLower.contains("验证")) {
            completionConfidenceScore = 76
        } else {
            completionConfidenceScore = 60
        }

        var weakReasons: [String] = []
        if freshnessScore < 40 { weakReasons.append("freshness_low") }
        if deltaSignificanceScore < 40 { weakReasons.append("delta_low") }
        if evidenceStrengthScore < 40 { weakReasons.append("evidence_weak") }
        if blockerClarityScore < 40 { weakReasons.append("blocker_unclear") }
        if nextActionSpecificityScore < 40 { weakReasons.append("next_action_generic") }
        if executionVitalityScore < 40 { weakReasons.append("execution_vitality_low") }
        if completionConfidenceScore < 40 { weakReasons.append("completion_confidence_low") }

        let overallScore = Int(
            (
                freshnessScore
                + deltaSignificanceScore
                + evidenceStrengthScore
                + blockerClarityScore
                + nextActionSpecificityScore
                + executionVitalityScore
                + completionConfidenceScore
            ) / 7
        )

        var overallBand: HeartbeatQualityBand
        switch overallScore {
        case 80...:
            overallBand = .strong
        case 60...:
            overallBand = .usable
        case 40...:
            overallBand = .weak
        default:
            overallBand = .hollow
        }

        if repeatCount >= 3 {
            overallBand = overallBand.clamped(toMaximum: .hollow)
        } else if repeatCount >= 2 {
            overallBand = overallBand.clamped(toMaximum: .weak)
        }
        if genericNextStep(nextStep) && !observedProgressAdvanced {
            overallBand = overallBand.clamped(toMaximum: .weak)
        }
        if doneClaim && !evidenceStrong {
            overallBand = overallBand.clamped(toMaximum: .weak)
        }
        if blockerDetected && blockerClarityScore < 40 {
            overallBand = overallBand.clamped(toMaximum: .weak)
        }

        let evidenceRefs = buildEvidenceRefs(
            projectId: project.projectId,
            summaryAtMs: progressAtMs,
            hasDigest: !digest.isEmpty,
            hasNextStep: !nextStep.isEmpty,
            hasBlocker: !blocker.isEmpty
        )
        var openAnomalies: [HeartbeatAnomalyNote] = []

        if repeatCount >= 2 {
            openAnomalies.append(
                HeartbeatAnomalyNote(
                    anomalyId: anomalyID(projectId: project.projectId, type: .staleRepeat, detectedAtMs: nowMs),
                    projectId: project.projectId,
                    anomalyType: .staleRepeat,
                    severity: repeatCount >= 4 ? .critical : (repeatCount >= 3 ? .high : .concern),
                    confidence: repeatCount >= 3 ? 0.9 : 0.76,
                    reason: "Heartbeat content repeated \(repeatCount + 1) times without meaningful progress.",
                    evidenceRefs: evidenceRefs,
                    detectedAtMs: nowMs,
                    recommendedEscalation: repeatCount >= 3 ? .strategicReview : .pulseReview
                )
            )
        }

        if (overallBand == .hollow || (deltaSignificanceScore <= 20 && nextActionSpecificityScore <= 25 && executionVitalityScore <= 20)) && !doneClaim {
            openAnomalies.append(
                HeartbeatAnomalyNote(
                    anomalyId: anomalyID(projectId: project.projectId, type: .hollowProgress, detectedAtMs: nowMs),
                    projectId: project.projectId,
                    anomalyType: .hollowProgress,
                    severity: repeatCount >= 2 ? .high : .concern,
                    confidence: repeatCount >= 2 ? 0.84 : 0.72,
                    reason: "Heartbeat still looks active, but delta, next action, and evidence are too weak.",
                    evidenceRefs: evidenceRefs,
                    detectedAtMs: nowMs,
                    recommendedEscalation: repeatCount >= 2 ? .strategicReview : .pulseReview
                )
            )
        }

        if doneClaim && !evidenceStrong {
            openAnomalies.append(
                HeartbeatAnomalyNote(
                    anomalyId: anomalyID(projectId: project.projectId, type: .weakDoneClaim, detectedAtMs: nowMs),
                    projectId: project.projectId,
                    anomalyType: .weakDoneClaim,
                    severity: .high,
                    confidence: 0.9,
                    reason: "Project claims done_candidate or completion without verification evidence.",
                    evidenceRefs: evidenceRefs,
                    detectedAtMs: nowMs,
                    recommendedEscalation: .rescueReview
                )
            )
        }

        if queueStallCue && (progressAgeMs >= 15 * 60 * 1000 || repeatCount >= 1 || blockerDetected) {
            openAnomalies.append(
                HeartbeatAnomalyNote(
                    anomalyId: anomalyID(projectId: project.projectId, type: .queueStall, detectedAtMs: nowMs),
                    projectId: project.projectId,
                    anomalyType: .queueStall,
                    severity: progressAgeMs >= 45 * 60 * 1000 ? .high : .concern,
                    confidence: progressAgeMs >= 45 * 60 * 1000 ? 0.86 : 0.74,
                    reason: "Queue or wait indicators stayed open while observed progress did not advance.",
                    evidenceRefs: evidenceRefs,
                    detectedAtMs: nowMs,
                    recommendedEscalation: .strategicReview
                )
            )
        }

        if blockerDetected && !blocker.isEmpty && blockerClarityScore < 40 {
            let severity: HeartbeatAnomalySeverity
            let confidence: Double
            let escalation: HeartbeatAnomalyEscalation
            if progressAgeMs >= 30 * 60 * 1000 || repeatCount >= 2 {
                severity = .high
                confidence = 0.86
                escalation = .strategicReview
            } else {
                severity = .concern
                confidence = 0.74
                escalation = .pulseReview
            }

            openAnomalies.append(
                HeartbeatAnomalyNote(
                    anomalyId: anomalyID(projectId: project.projectId, type: .weakBlocker, detectedAtMs: nowMs),
                    projectId: project.projectId,
                    anomalyType: .weakBlocker,
                    severity: severity,
                    confidence: confidence,
                    reason: "Blocker is still present, but the heartbeat does not explain what is missing or how to unblock next.",
                    evidenceRefs: evidenceRefs,
                    detectedAtMs: nowMs,
                    recommendedEscalation: escalation
                )
            )
        }

        let executionStatus: HeartbeatExecutionStatus
        if doneClaim {
            executionStatus = .doneCandidate
        } else if queueStallCue || repeatCount >= 2 {
            executionStatus = .stalled
        } else if blockerDetected || !blocker.isEmpty {
            executionStatus = .blocked
        } else {
            executionStatus = .active
        }

        let projectPhase = inferredProjectPhase(
            combinedLower: combinedLower,
            nextStepLower: nextStep.lowercased(),
            executionStatus: executionStatus,
            evidenceStrong: evidenceStrong
        )
        let riskTier = inferredRiskTier(
            combinedLower: combinedLower,
            blockerLower: blocker.lowercased(),
            projectPhase: projectPhase,
            executionStatus: executionStatus,
            blockerDetected: blockerDetected,
            doneClaim: doneClaim,
            evidenceStrong: evidenceStrong
        )

        openAnomalies.sort { lhs, rhs in
            if lhs.severity.rank != rhs.severity.rank {
                return lhs.severity.rank > rhs.severity.rank
            }
            if lhs.detectedAtMs != rhs.detectedAtMs {
                return lhs.detectedAtMs > rhs.detectedAtMs
            }
            return lhs.anomalyType.rawValue < rhs.anomalyType.rawValue
        }

        let qualitySnapshot = HeartbeatQualitySnapshot(
            overallScore: max(0, min(100, overallScore)),
            overallBand: overallBand,
            freshnessScore: freshnessScore,
            deltaSignificanceScore: deltaSignificanceScore,
            evidenceStrengthScore: evidenceStrengthScore,
            blockerClarityScore: blockerClarityScore,
            nextActionSpecificityScore: nextActionSpecificityScore,
            executionVitalityScore: executionVitalityScore,
            completionConfidenceScore: completionConfidenceScore,
            weakReasons: weakReasons,
            computedAtMs: nowMs
        )

        let meaningfulProgressAtMs: Int64?
        if observedProgressAdvanced {
            meaningfulProgressAtMs = progressAtMs > 0 ? progressAtMs : nowMs
        } else if contentChanged && deltaSignificanceScore >= 60 && nextActionSpecificityScore >= 50 {
            meaningfulProgressAtMs = nowMs
        } else {
            meaningfulProgressAtMs = nil
        }

        return HeartbeatAssessmentResult(
            meaningfulProgressAtMs: meaningfulProgressAtMs,
            qualitySnapshot: qualitySnapshot,
            openAnomalies: openAnomalies,
            heartbeatFingerprint: fingerprint,
            repeatCount: repeatCount,
            projectPhase: projectPhase,
            executionStatus: executionStatus,
            riskTier: riskTier
        )
    }

    private static func projectObservedProgressAtMs(_ project: AXProjectEntry) -> Int64 {
        let summaryMs = Int64(((project.lastSummaryAt ?? 0) * 1000.0).rounded())
        let eventMs = Int64(((project.lastEventAt ?? 0) * 1000.0).rounded())
        return max(summaryMs, eventMs)
    }

    private static func anomalyID(
        projectId: String,
        type: HeartbeatAnomalyType,
        detectedAtMs: Int64
    ) -> String {
        "hb-anomaly:\(projectId):\(type.rawValue):\(max(0, detectedAtMs))"
    }

    private static func buildEvidenceRefs(
        projectId: String,
        summaryAtMs: Int64,
        hasDigest: Bool,
        hasNextStep: Bool,
        hasBlocker: Bool
    ) -> [String] {
        var refs: [String] = []
        if summaryAtMs > 0 {
            refs.append("project_summary:\(projectId):\(summaryAtMs)")
        }
        if hasDigest {
            refs.append("project_digest:\(projectId)")
        }
        if hasNextStep {
            refs.append("project_next_step:\(projectId)")
        }
        if hasBlocker {
            refs.append("project_blocker:\(projectId)")
        }
        return refs
    }

    private static func normalizedText(
        _ value: String?,
        fallback: String = ""
    ) -> String {
        let trimmed = (value ?? fallback).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback.trimmingCharacters(in: .whitespacesAndNewlines) }
        return trimmed
    }

    private static func normalizedFingerprintToken(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func freshnessScore(progressAgeMs: Int64) -> Int {
        guard progressAgeMs != Int64.max else { return 15 }
        switch progressAgeMs {
        case ..<Int64(5 * 60 * 1000):
            return 96
        case ..<Int64(15 * 60 * 1000):
            return 84
        case ..<Int64(30 * 60 * 1000):
            return 68
        case ..<Int64(60 * 60 * 1000):
            return 48
        default:
            return 24
        }
    }

    private static func genericNextStep(_ value: String) -> Bool {
        let text = value.lowercased()
        if text.isEmpty {
            return true
        }
        return [
            "继续推进",
            "继续当前任务",
            "继续执行",
            "继续观察",
            "处理中",
            "持续推进",
            "follow up",
            "continue execution",
            "continue current task",
            "keep going",
            "watch"
        ].contains(where: { text.contains($0) })
    }

    private static func genericBlocker(_ value: String) -> Bool {
        let text = value.lowercased()
        if text.isEmpty {
            return false
        }
        return [
            "blocked",
            "卡住",
            "待处理",
            "问题待查",
            "unknown",
            "needs attention",
            "有问题"
        ].contains(where: { text.contains($0) })
    }

    private static func looksLikeDoneClaim(_ lowercasedText: String) -> Bool {
        [
            "done candidate",
            "done_candidate",
            "done",
            "completed",
            "ready to ship",
            "ship",
            "release ready",
            "已完成",
            "完成",
            "收口",
            "可交付",
            "验证通过"
        ].contains(where: { lowercasedText.contains($0) })
    }

    private static func containsEvidenceSignal(_ lowercasedText: String) -> Bool {
        [
            "test",
            "build",
            "diff",
            "patch",
            "verify",
            "verification",
            "evidence",
            "audit",
            "log",
            "proof",
            "screenshot",
            "passed",
            "compiled",
            "benchmark",
            "trace",
            "reviewed",
            "验收",
            "验证",
            "测试",
            "构建",
            "证据",
            "日志",
            "截图"
        ].contains(where: { lowercasedText.contains($0) })
    }

    private static func containsSpecificActionCue(_ lowercasedText: String) -> Bool {
        [
            "run ",
            "fix ",
            "verify",
            "review",
            "grant",
            "route",
            "repair",
            "build",
            "test",
            "patch",
            "diff",
            "ship",
            "release",
            "resume",
            "rehydrate",
            "修复",
            "验证",
            "测试",
            "构建",
            "授权",
            "路由",
            "恢复"
        ].contains(where: { lowercasedText.contains($0) })
    }

    private static func containsQueueStallCue(
        _ blockerLowercased: String,
        _ combinedLowercased: String
    ) -> Bool {
        let cues = [
            "queue",
            "queued",
            "queue starvation",
            "queue_depth",
            "oldest wait",
            "排队",
            "队列",
            "queue_starvation"
        ]
        return cues.contains(where: { blockerLowercased.contains($0) || combinedLowercased.contains($0) })
    }

    private static func inferredProjectPhase(
        combinedLower: String,
        nextStepLower: String,
        executionStatus: HeartbeatExecutionStatus,
        evidenceStrong: Bool
    ) -> HeartbeatProjectPhase {
        if containsAny(
            combinedLower,
            [
                "release",
                "ship",
                "shipping",
                "deploy",
                "publish",
                "rollout",
                "上线",
                "发布"
            ]
        ) || executionStatus == .doneCandidate {
            return .release
        }

        if containsAny(
            combinedLower,
            [
                "verify",
                "verification",
                "validate",
                "validation",
                "smoke",
                "qa",
                "regression",
                "test",
                "tests",
                "验收",
                "验证",
                "回归"
            ]
        ) || (evidenceStrong && containsAny(nextStepLower, ["verify", "validate", "test", "验证"])) {
            return .verify
        }

        if containsAny(
            combinedLower,
            [
                "implement",
                "implementation",
                "build",
                "coding",
                "patch",
                "fix",
                "refactor",
                "integration",
                "编写",
                "开发",
                "实现",
                "修复"
            ]
        ) {
            return .build
        }

        if containsAny(
            combinedLower,
            [
                "plan",
                "planning",
                "spec",
                "design",
                "breakdown",
                "milestone",
                "roadmap",
                "方案",
                "规划",
                "拆分"
            ]
        ) {
            return .plan
        }

        return .explore
    }

    private static func inferredRiskTier(
        combinedLower: String,
        blockerLower: String,
        projectPhase: HeartbeatProjectPhase,
        executionStatus: HeartbeatExecutionStatus,
        blockerDetected: Bool,
        doneClaim: Bool,
        evidenceStrong: Bool
    ) -> HeartbeatRiskTier {
        let criticalSignals = containsAny(
            combinedLower,
            [
                "production",
                "prod",
                "database migration",
                "schema migration",
                "security",
                "payment",
                "billing",
                "customer data",
                "delete",
                "drop table",
                "rm -rf",
                "发布生产",
                "生产发布",
                "数据库迁移",
                "安全"
            ]
        )
        if criticalSignals {
            return .critical
        }

        let highSignals = containsAny(
            combinedLower,
            [
                "grant_pending",
                "grant required",
                "permission",
                "approval",
                "deploy",
                "release",
                "connector",
                "browser",
                "device",
                "extension",
                "pre-done",
                "高风险",
                "授权",
                "审批",
                "部署",
                "发布"
            ]
        ) || containsAny(
            blockerLower,
            [
                "grant",
                "permission",
                "approval",
                "auth"
            ]
        )
        if highSignals
            || projectPhase == .release
            || executionStatus == .doneCandidate
            || (doneClaim && !evidenceStrong) {
            return .high
        }

        if blockerDetected || projectPhase == .verify || projectPhase == .build {
            return .medium
        }

        return .low
    }

    private static func containsAny(
        _ haystack: String,
        _ needles: [String]
    ) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
