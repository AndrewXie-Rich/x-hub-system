import Foundation

struct AXProjectAIReviewEvidence: Equatable {
    var verdict: XTUIReviewVerdict
    var sufficientEvidence: Bool
    var objectiveReady: Bool
    var trendStatus: XTUIReviewTrendStatus?
}

struct AXProjectAIStrengthEvidence: Equatable {
    var recentActivities: [ProjectSkillActivityItem]
    var latestUIReview: AXProjectAIReviewEvidence?
    var recentUIReviewVerdicts: [XTUIReviewVerdict]
    var executionSnapshots: [AXRoleExecutionSnapshot]
}

enum AXProjectAIStrengthAssessor {
    private static let defaultAuditRef = "xt.project_ai_strength_assessor.v1"

    static func collectEvidence(
        ctx: AXProjectContext,
        activityLimit: Int = 10,
        reviewHistoryLimit: Int = 6
    ) -> AXProjectAIStrengthEvidence {
        let activities = AXProjectSkillActivityStore.loadRecentActivities(
            ctx: ctx,
            limit: max(1, activityLimit)
        )
        let latestUIReview = XTUIReviewPresentation.loadLatestBrowserPage(for: ctx).map {
            AXProjectAIReviewEvidence(
                verdict: $0.verdict,
                sufficientEvidence: $0.sufficientEvidence,
                objectiveReady: $0.objectiveReady,
                trendStatus: $0.trend?.status
            )
        }
        let recentUIReviewVerdicts = XTUIReviewPresentation.loadHistory(
            for: ctx,
            limit: max(1, reviewHistoryLimit)
        ).map(\.verdict)
        let executionSnapshots = AXRoleExecutionSnapshots.latestSnapshots(for: ctx)
            .values
            .filter { $0.role != .supervisor && $0.hasRecord }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.role.rawValue < rhs.role.rawValue
            }

        return AXProjectAIStrengthEvidence(
            recentActivities: activities,
            latestUIReview: latestUIReview,
            recentUIReviewVerdicts: recentUIReviewVerdicts,
            executionSnapshots: executionSnapshots
        )
    }

    static func assess(
        ctx: AXProjectContext,
        adaptationPolicy: AXProjectSupervisorAdaptationPolicy = .default,
        now: Date = Date()
    ) -> AXProjectAIStrengthProfile {
        assess(
            evidence: collectEvidence(ctx: ctx),
            adaptationPolicy: adaptationPolicy,
            assessedAtMs: currentTimeMs(now)
        )
    }

    static func assess(
        evidence: AXProjectAIStrengthEvidence,
        adaptationPolicy: AXProjectSupervisorAdaptationPolicy = .default,
        assessedAtMs: Int64,
        auditRef: String = defaultAuditRef
    ) -> AXProjectAIStrengthProfile {
        let activityStats = ActivityStats(items: evidence.recentActivities)
        let routeStats = RouteStats(snapshots: evidence.executionSnapshots)
        let insufficientEvidenceStreak = leadingVerdictCount(
            evidence.recentUIReviewVerdicts,
            matching: .insufficientEvidence
        )
        let hasAnyEvidence =
            !evidence.recentActivities.isEmpty ||
            evidence.latestUIReview != nil ||
            !evidence.executionSnapshots.isEmpty

        var positiveSignals = 0
        var negativeSignals = 0
        var reasons: [String] = []

        if !hasAnyEvidence {
            reasons.append("recent project evidence is still sparse")
            return AXProjectAIStrengthProfile(
                strengthBand: .unknown,
                confidence: confidenceScore(
                    evidence: evidence,
                    band: .unknown,
                    hasAnyEvidence: false
                ),
                recommendedSupervisorFloor: .s0SilentAudit,
                recommendedWorkOrderDepth: .brief,
                reasons: reasons,
                assessedAtMs: assessedAtMs,
                auditRef: auditRef
            )
        }

        if activityStats.consecutiveNegativeTerminalCount >= adaptationPolicy.failureStreakRaiseThreshold {
            negativeSignals += 3
            reasons.append(
                "recent skill calls show \(activityStats.consecutiveNegativeTerminalCount) consecutive blocked/failed outcomes"
            )
        } else if activityStats.negativeTerminalCount >= 2 && activityStats.completedCount == 0 {
            negativeSignals += 2
            reasons.append("recent skill calls have not closed successfully yet")
        } else if activityStats.negativeTerminalCount > activityStats.completedCount && activityStats.negativeTerminalCount > 0 {
            negativeSignals += 1
            reasons.append("recent skill calls are still failure-heavy")
        }

        if activityStats.completedCount >= 3 && activityStats.negativeTerminalCount == 0 {
            positiveSignals += 2
            reasons.append("recent skill calls completed cleanly")
        } else if activityStats.completedCount >= 2 && activityStats.completedCount > activityStats.negativeTerminalCount {
            positiveSignals += 1
            reasons.append("recent skill calls mostly completed")
        }

        if activityStats.awaitingApprovalCount >= 2 && activityStats.completedCount == 0 {
            negativeSignals += 1
            reasons.append("recent work is still waiting on approval, so autonomous closure is not yet proven")
        }

        if activityStats.deniedCount >= 2 {
            negativeSignals += 1
            reasons.append("policy or approval denials remained elevated")
        }

        if let latestUIReview = evidence.latestUIReview {
            switch latestUIReview.verdict {
            case .ready:
                positiveSignals += latestUIReview.objectiveReady && latestUIReview.sufficientEvidence ? 2 : 1
                reasons.append(
                    latestUIReview.objectiveReady
                        ? "latest UI review is execution-ready"
                        : "latest UI review is ready"
                )
            case .attentionNeeded:
                negativeSignals += 2
                reasons.append("latest UI review still needs attention")
            case .insufficientEvidence:
                negativeSignals += 2
                reasons.append("latest UI review lacks enough evidence for safe execution")
            }

            if latestUIReview.verdict != .insufficientEvidence && !latestUIReview.sufficientEvidence {
                negativeSignals += 1
                reasons.append("UI evidence is still incomplete")
            }

            switch latestUIReview.trendStatus {
            case .improved:
                positiveSignals += 1
                reasons.append("UI review improved versus the previous checkpoint")
            case .regressed:
                negativeSignals += 1
                reasons.append("UI review regressed versus the previous checkpoint")
            case .stable, .none:
                break
            }
        }

        if insufficientEvidenceStreak >= adaptationPolicy.insufficientEvidenceRaiseThreshold {
            negativeSignals += 2
            reasons.append(
                "UI review stayed in insufficient_evidence for \(insufficientEvidenceStreak) checkpoints"
            )
        }

        if routeStats.unstableCount >= 2 {
            negativeSignals += 2
            reasons.append("model route fell back or downgraded \(routeStats.unstableCount) times recently")
        } else if routeStats.unstableCount == 1 {
            negativeSignals += 1
            reasons.append("model route required a fallback or downgrade recently")
        }

        if routeStats.remoteErrorCount > 0 && routeStats.remoteStableCount == 0 {
            negativeSignals += 1
            reasons.append("recent model execution failed before reaching a stable route")
        }

        if routeStats.retryCount >= 2 {
            negativeSignals += 1
            reasons.append("remote model routing needed repeated retries")
        }

        if routeStats.remoteStableCount >= 2 && routeStats.unstableCount == 0 {
            positiveSignals += 2
            reasons.append("model route remained stable on remote execution")
        } else if routeStats.remoteStableCount >= 1 && routeStats.unstableCount == 0 {
            positiveSignals += 1
            reasons.append("model route executed without fallback")
        }

        let latestUIVerdict = evidence.latestUIReview?.verdict
        let severeWeakSignals =
            activityStats.consecutiveNegativeTerminalCount >= adaptationPolicy.failureStreakRaiseThreshold ||
            (insufficientEvidenceStreak >= adaptationPolicy.insufficientEvidenceRaiseThreshold && latestUIVerdict != .ready) ||
            (activityStats.negativeTerminalCount >= 3 && latestUIVerdict != .ready) ||
            (routeStats.unstableCount >= 2 && activityStats.negativeTerminalCount >= 1)

        let strongSignals =
            positiveSignals >= 4 &&
            negativeSignals == 0 &&
            activityStats.completedCount >= 3 &&
            latestUIVerdict == .ready &&
            routeStats.remoteStableCount >= 1

        let band: AXProjectAIStrengthBand
        switch true {
        case severeWeakSignals:
            band = .weak
        case strongSignals:
            band = .strong
        case positiveSignals >= 2 && negativeSignals <= 1:
            band = .capable
        case negativeSignals > 0:
            band = .developing
        default:
            band = .unknown
        }

        let recommendation = recommendation(for: band)
        return AXProjectAIStrengthProfile(
            strengthBand: band,
            confidence: confidenceScore(
                evidence: evidence,
                band: band,
                hasAnyEvidence: true
            ),
            recommendedSupervisorFloor: recommendation.supervisorFloor,
            recommendedWorkOrderDepth: recommendation.workOrderDepth,
            reasons: reasons,
            assessedAtMs: assessedAtMs,
            auditRef: auditRef
        )
    }

    private static func recommendation(
        for band: AXProjectAIStrengthBand
    ) -> (supervisorFloor: AXProjectSupervisorInterventionTier, workOrderDepth: AXProjectSupervisorWorkOrderDepth) {
        switch band {
        case .unknown:
            return (.s0SilentAudit, .brief)
        case .weak:
            return (.s4TightSupervision, .stepLockedRescue)
        case .developing:
            return (.s3StrategicCoach, .executionReady)
        case .capable:
            return (.s0SilentAudit, .brief)
        case .strong:
            return (.s0SilentAudit, .none)
        }
    }

    private static func confidenceScore(
        evidence: AXProjectAIStrengthEvidence,
        band: AXProjectAIStrengthBand,
        hasAnyEvidence: Bool
    ) -> Double {
        var confidence = hasAnyEvidence ? 0.18 : 0.12

        if !evidence.recentActivities.isEmpty {
            confidence += 0.18
            confidence += min(0.18, Double(min(evidence.recentActivities.count, 8)) * 0.02)
        }

        if evidence.latestUIReview != nil {
            confidence += 0.22
        }

        if evidence.recentUIReviewVerdicts.count >= 2 {
            confidence += 0.05
        }

        if !evidence.executionSnapshots.isEmpty {
            confidence += 0.18
            confidence += min(0.12, Double(min(evidence.executionSnapshots.count, 4)) * 0.03)
        }

        if band == .strong || band == .weak {
            confidence += 0.07
        }

        if band == .unknown {
            return min(hasAnyEvidence ? 0.58 : 0.24, max(0.15, confidence))
        }

        return min(0.97, max(0.15, confidence))
    }

    private static func currentTimeMs(_ now: Date) -> Int64 {
        Int64((now.timeIntervalSince1970 * 1_000.0).rounded())
    }

    private static func leadingVerdictCount(
        _ verdicts: [XTUIReviewVerdict],
        matching target: XTUIReviewVerdict
    ) -> Int {
        var count = 0
        for verdict in verdicts {
            guard verdict == target else { break }
            count += 1
        }
        return count
    }
}

private struct ActivityStats {
    var completedCount: Int = 0
    var failedCount: Int = 0
    var blockedCount: Int = 0
    var awaitingApprovalCount: Int = 0
    var deniedCount: Int = 0
    var consecutiveNegativeTerminalCount: Int = 0

    var negativeTerminalCount: Int {
        failedCount + blockedCount
    }

    init(items: [ProjectSkillActivityItem]) {
        let ordered = items.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.requestID > rhs.requestID
        }

        for item in ordered {
            switch normalizedStatus(item.status) {
            case "completed":
                completedCount += 1
            case "failed":
                failedCount += 1
            case "blocked":
                blockedCount += 1
                if !normalizedDisposition(item.authorizationDisposition).isEmpty || !item.denyCode.isEmpty {
                    deniedCount += 1
                }
            case "awaiting_approval":
                awaitingApprovalCount += 1
            default:
                break
            }
        }

        for item in ordered {
            let status = normalizedStatus(item.status)
            if status == "failed" || status == "blocked" {
                consecutiveNegativeTerminalCount += 1
                continue
            }
            if status == "awaiting_approval" || status == "resolved" {
                continue
            }
            break
        }
    }

    private func normalizedStatus(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedDisposition(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct RouteStats {
    var remoteStableCount: Int = 0
    var downgradedCount: Int = 0
    var fallbackCount: Int = 0
    var remoteErrorCount: Int = 0
    var retryCount: Int = 0

    var unstableCount: Int {
        downgradedCount + fallbackCount + remoteErrorCount
    }

    init(snapshots: [AXRoleExecutionSnapshot]) {
        for snapshot in snapshots {
            switch snapshot.executionPath {
            case "remote_model":
                remoteStableCount += 1
                if snapshot.remoteRetryAttempted {
                    retryCount += 1
                }
            case "hub_downgraded_to_local":
                downgradedCount += 1
            case "local_fallback_after_remote_error":
                fallbackCount += 1
            case "remote_error":
                remoteErrorCount += 1
            default:
                break
            }
        }
    }
}
