import Foundation

extension SupervisorManager {
    enum SupervisorReplyExecutionMode: String {
        case idle
        case localPreflight = "local_preflight"
        case localDirectReply = "local_direct_reply"
        case localDirectAction = "local_direct_action"
        case hubBriefProjection = "hub_brief_projection"
        case remoteModel = "remote_model"
        case hubDowngradedToLocal = "hub_downgraded_to_local"
        case localFallbackAfterRemoteError = "local_fallback_after_remote_error"
    }

    struct SupervisorVoiceSkillExecutionResult: Equatable, Sendable {
        var action: String
        var ok: Bool
        var reasonCode: String
        var detail: String
        var playbackPreference: String
        var persona: String
        var timbre: String
        var speechRateMultiplier: Double
        var localeIdentifier: String
        var resolution: VoicePlaybackResolution
        var activity: VoicePlaybackActivity
    }

    struct SupervisorEventLoopActivity: Identifiable, Equatable {
        var id: String
        var createdAt: Double
        var updatedAt: Double
        var triggerSource: String
        var status: String
        var reasonCode: String
        var dedupeKey: String
        var projectId: String
        var projectName: String
        var triggerSummary: String
        var resultSummary: String
        var policySummary: String
        var blockedSummary: String = ""
        var policyReason: String = ""
        var governanceTruth: String = ""
        var grantRequestId: String = ""
        var grantCapability: String = ""
    }

    struct HeartbeatFeedEntry: Identifiable, Equatable {
        var id: String
        var createdAt: Double
        var reason: String
        var projectCount: Int
        var changed: Bool
        var content: String
        var focusActionURL: String?
    }

    struct HeartbeatVoiceReadinessSignal: Equatable {
        var kind: VoiceReadinessCheckKind
        var readyForFirstTask: Bool
        var overallSummary: String
        var headline: String
        var nextStep: String
        var reasonCode: String
        var repairEntry: UITroubleshootDestination
        var actionURL: String?
    }

    struct HeartbeatGovernedReviewSignal: Equatable {
        var projectId: String
        var projectName: String
        var trigger: SupervisorReviewTrigger
        var runKind: SupervisorReviewRunKind
        var reviewLevel: SupervisorReviewLevel
        var causeLabel: String
        var summaryLine: String
        var detailLine: String
        var projectMemoryStatusLine: String? = nil
        var projectMemoryMetadataText: String? = nil
        var actionURL: String?
    }

    struct HeartbeatRecoveryFollowUpSignal: Equatable {
        var projectId: String
        var projectName: String
        var action: HeartbeatRecoveryAction
        var urgency: HeartbeatRecoveryUrgency
        var reasonCode: String
        var requiresUserAction: Bool
        var summaryLine: String
        var detailLine: String
        var priorityReasonLine: String? = nil
        var actionURL: String?
    }

    struct HeartbeatGovernedReviewSelectionCandidate {
        var project: AXProjectEntry
        var governance: AXProjectResolvedGovernanceState
        var candidate: SupervisorHeartbeatReviewCandidate
        var portfolioCard: SupervisorPortfolioProjectCard
    }

    struct HeartbeatRecoveryFollowUpSelectionCandidate {
        var project: AXProjectEntry
        var governance: AXProjectResolvedGovernanceState
        var decision: HeartbeatRecoveryDecision
        var laneSnapshot: SupervisorLaneHealthSnapshot?
        var portfolioCard: SupervisorPortfolioProjectCard
    }

    struct HeartbeatHubLoadSignal: Equatable {
        var severity: XHubLocalRuntimeHostMetricsSeverity
        var overallSummary: String
        var nextStep: String
        var detailLines: [String]
        var actionURL: String?
    }

    struct RuntimeActivityEntry: Identifiable, Equatable {
        var id: String
        var createdAt: Double
        var text: String
        var projectId: String? = nil
        var projectName: String? = nil
        var requiresKnownProjectMatch: Bool = false
    }

    struct SupervisorVoiceCallEntryPreflight: Equatable {
        enum Disposition: String, Equatable {
            case advisory
            case block
        }

        var disposition: Disposition
        var headline: String
        var detail: String
        var nextStep: String
        var reasonCode: String
        var repairDestination: UITroubleshootDestination? = nil
        var actionURL: String? = nil
        var actionLabel: String? = nil

        var blocksStart: Bool {
            disposition == .block
        }
    }

    struct SupervisorAfterTurnDerivedSummary: Equatable {
        enum Trend: String, Equatable {
            case idle
            case initialized
            case increased
            case reduced
            case cleared
            case stable
        }

        var replySource: String
        var trend: Trend
        var hasOverdueItems: Bool
        var reviewDueCount: Int
        var reviewOverdueCount: Int
        var followUpOpenCount: Int
        var followUpOverdueCount: Int
        var statusLine: String
        var detailLines: [String]
        var debugLine: String
    }

    struct CanonicalMemoryRetryFeedback: Equatable {
        var statusLine: String
        var detailLine: String?
        var metaLine: String?
        var tone: SupervisorHeaderControlTone
        var attemptStartedAt: TimeInterval?
        var lastStatusUpdatedAt: TimeInterval?

        init(
            statusLine: String,
            detailLine: String? = nil,
            metaLine: String? = nil,
            tone: SupervisorHeaderControlTone,
            attemptStartedAt: TimeInterval? = nil,
            lastStatusUpdatedAt: TimeInterval? = nil
        ) {
            self.statusLine = statusLine
            self.detailLine = detailLine
            self.metaLine = metaLine
            self.tone = tone
            self.attemptStartedAt = attemptStartedAt
            self.lastStatusUpdatedAt = lastStatusUpdatedAt
        }
    }

    enum SupervisorWindowSheet: String, Identifiable, Equatable {
        case supervisorSettings
        case modelSettings

        var id: String { rawValue }

        var windowID: String {
            switch self {
            case .supervisorSettings:
                return "supervisor_settings"
            case .modelSettings:
                return "model_settings"
            }
        }
    }
}

struct SupervisorMessage: Identifiable, Equatable {
    var id: String
    var role: SupervisorRole
    var content: String
    var isVoice: Bool
    var timestamp: Double
    var attachments: [AXChatAttachment] = []
    var projectId: String? = nil
    var projectName: String? = nil
    var requiresKnownProjectMatch: Bool = false

    enum SupervisorRole: String, Equatable {
        case user
        case assistant
        case system
    }
}

struct SupervisorTask: Identifiable {
    var id: String
    var projectId: String
    var title: String
    var status: String
    var createdAt: Double
}

enum SupervisorAutomationRuntimeError: Error, Equatable {
    case projectContextMissing(String)
    case projectSelectionMissing
    case projectNotFound(String)
    case projectAmbiguous(String, [String])
}
