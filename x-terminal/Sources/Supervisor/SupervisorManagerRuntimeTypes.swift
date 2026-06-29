import Foundation

extension SupervisorManager {
    struct ParsedAutomationRuntimeCommand {
        enum Action {
            case help
            case status
            case start
            case recover
            case cancel
            case advance(XTAutomationRunState)
            case selfIterateStatus
            case selfIterateSet(Bool)
            case selfIterateMax(Int)
        }

        var action: Action
        var projectRef: String?
    }

    struct AutomationRetryPlanningMaterialization {
        var package: XTAutomationRetryPackage
        var planningArtifact: XTAutomationRetryPlanningArtifact?
        var recipeProposalArtifact: XTAutomationRecipeProposalArtifact?
    }

    struct HeartbeatVoiceTestEmission: Equatable {
        var path: String
        var outcome: String
        var script: [String]
    }

    enum HeartbeatProjectionVoiceResolution {
        case projection(SupervisorVoiceTTSJob)
        case unavailable(SupervisorVoiceTTSJob)
    }

    struct HeartbeatNotificationPresentation: Equatable {
        var title: String
        var body: String
        var unread: Bool
    }

    struct RouteAttentionReminderStatus: Equatable {
        var lastAlertAt: TimeInterval?
        var quietingCurrentIssue: Bool
        var cooldownRemainingSec: Int
    }

    struct HeartbeatRouteAttentionSignal: Equatable {
        var item: AXRouteRepairProjectWatchItem
        var alertToken: String
        var shouldAlertOnTimer: Bool
        var statusBarFollowUp: AXRouteRepairLogEvent?
    }

    struct SupervisorRuntimeState: Codable, Equatable {
        static let currentSchemaVersion = "xt.supervisor_runtime_state.v3"

        var schemaVersion: String
        var lastHeartbeatRouteAttentionAlertToken: String
        var lastHeartbeatRouteAttentionAlertAt: TimeInterval
        var focusPointerState: SupervisorFocusPointerState?
        var notificationCenterState: SupervisorProjectNotificationCenterState?
    }

    enum HubConnectorIngressResolution {
        case route(SupervisorAutomationExternalTriggerIngress)
        case failClosed(SupervisorAutomationExternalTriggerIngress, String)
    }

    struct SupervisorAutomationExternalTriggerIngress: Equatable, Sendable {
        var projectId: String
        var triggerId: String
        var triggerType: XTAutomationTriggerType
        var source: XTAutomationTriggerSource
        var payloadRef: String
        var dedupeKey: String
        var requiresGrant: Bool?
        var policyRef: String?
        var receivedAt: Date
        var ingressChannel: String

        init(
            projectId: String,
            triggerId: String,
            triggerType: XTAutomationTriggerType,
            source: XTAutomationTriggerSource,
            payloadRef: String,
            dedupeKey: String,
            requiresGrant: Bool? = nil,
            policyRef: String? = nil,
            receivedAt: Date = Date(),
            ingressChannel: String = "supervisor_bridge"
        ) {
            self.projectId = projectId
            self.triggerId = triggerId
            self.triggerType = triggerType
            self.source = source
            self.payloadRef = payloadRef
            self.dedupeKey = dedupeKey
            self.requiresGrant = requiresGrant
            self.policyRef = policyRef
            self.receivedAt = receivedAt
            self.ingressChannel = ingressChannel
        }
    }

    enum SupervisorAutomationExternalTriggerDecision: String, Equatable, Sendable {
        case run
        case drop
        case hold
        case failClosed = "fail_closed"
    }

    struct SupervisorAutomationExternalTriggerResult: Equatable, Sendable {
        var projectId: String
        var triggerId: String
        var triggerType: XTAutomationTriggerType
        var decision: SupervisorAutomationExternalTriggerDecision
        var reasonCode: String
        var runId: String?
        var auditRef: String
    }

    enum ProjectReferenceResolution {
        case matched(AXProjectEntry)
        case ambiguous([AXProjectEntry])
        case notFound
    }

    enum ProjectRuntimeState {
        case running
        case paused
        case blocked
    }

    enum GuardedOneShotLaunchResumeOutcome {
        case launched(LaneLaunchReport)
        case blocked(reason: String, report: LaneLaunchReport?)
        case failedClosed(reason: String)
    }

    struct ModelAssignmentResult {
        var ok: Bool
        var reasonCode: String
        var message: String
    }

    enum SupervisorCommandTriggerSource: String {
        case userTurn = "user_turn"
        case heartbeat
        case skillCallback = "skill_callback"
        case officialSkillsChannel = "official_skills_channel"
        case guidanceAck = "guidance_ack"
        case automationSafePoint = "automation_safe_point"
        case incident
        case externalTriggerIngress = "external_trigger_ingress"
        case grantResolution = "grant_resolution"
        case approvalResolution = "approval_resolution"

        static func parse(_ raw: String) -> SupervisorCommandTriggerSource {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return SupervisorCommandTriggerSource(rawValue: normalized) ?? .userTurn
        }

        var defaultJobSource: SupervisorJobSource {
            switch self {
            case .userTurn:
                return .user
            case .heartbeat:
                return .heartbeat
            case .skillCallback:
                return .skillCallback
            case .officialSkillsChannel:
                return .supervisor
            case .guidanceAck:
                return .supervisor
            case .automationSafePoint:
                return .supervisor
            case .incident:
                return .incident
            case .externalTriggerIngress:
                return .externalTrigger
            case .grantResolution:
                return .grantResolution
            case .approvalResolution:
                return .approvalResolution
            }
        }
    }

    struct SupervisorCreateJobPayload: Codable {
        var projectRef: String?
        var goal: String
        var priority: String?
        var source: String?
        var currentOwner: String?

        enum CodingKeys: String, CodingKey {
            case projectRef = "project_ref"
            case goal
            case priority
            case source
            case currentOwner = "current_owner"
        }
    }

    struct SupervisorUpsertPlanStepPayload: Codable {
        var stepId: String
        var title: String
        var kind: String?
        var status: String?
        var skillId: String?
        var currentOwner: String?
        var detail: String?
        var dependsOn: [String]?
        var timeoutMs: Int?
        var maxRetries: Int?
        var failurePolicy: String?

        enum CodingKeys: String, CodingKey {
            case stepId = "step_id"
            case title
            case kind
            case status
            case skillId = "skill_id"
            case currentOwner = "current_owner"
            case detail
            case dependsOn = "depends_on"
            case timeoutMs = "timeout_ms"
            case maxRetries = "max_retries"
            case failurePolicy = "failure_policy"
        }
    }

    struct SupervisorUpsertPlanPayload: Codable {
        var projectRef: String?
        var jobId: String
        var planId: String
        var currentOwner: String?
        var steps: [SupervisorUpsertPlanStepPayload]

        enum CodingKeys: String, CodingKey {
            case projectRef = "project_ref"
            case jobId = "job_id"
            case planId = "plan_id"
            case currentOwner = "current_owner"
            case steps
        }
    }

    struct SupervisorCallSkillPayload: Codable {
        var projectRef: String?
        var jobId: String
        var stepId: String
        var skillId: String
        var payload: [String: JSONValue]?

        enum CodingKeys: String, CodingKey {
            case projectRef = "project_ref"
            case jobId = "job_id"
            case stepId = "step_id"
            case skillId = "skill_id"
            case payload
        }
    }

    struct SupervisorCallGlobalSkillPayload: Codable {
        var skillId: String
        var payload: [String: JSONValue]?

        enum CodingKeys: String, CodingKey {
            case skillId = "skill_id"
            case payload
        }
    }

    struct SupervisorCancelSkillPayload: Codable {
        var projectRef: String?
        var requestId: String
        var reason: String?

        enum CodingKeys: String, CodingKey {
            case projectRef = "project_ref"
            case requestId = "request_id"
            case reason
        }
    }

    struct SupervisorJSONPayloadDecodeError: Error {
        var message: String
    }

    struct SupervisorActionLedgerEntry: Codable {
        var id: String
        var createdAt: Double
        var action: String
        var targetRef: String
        var projectId: String?
        var projectName: String?
        var role: String?
        var modelId: String?
        var status: String
        var reasonCode: String
        var detail: String
        var verifiedAt: Double?
        var triggerSource: String?
    }

    struct SupervisorSelfObservationSnapshot {
        var recentAssistantReplies: [String]
        var latestHeartbeatReason: String
        var latestHeartbeatSummary: String
        var latestRuntimeActivity: String
        var latestActionSummary: String
    }
}
