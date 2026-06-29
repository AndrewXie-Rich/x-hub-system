import Foundation

extension SupervisorManager {
    struct DirectSupervisorPendingSkillApprovalReplyContext {
        var mode: SupervisorPendingSkillAuthorizationMode
        var displaySummary: String
        var deltaHeadline: String?
        var gateLine: String?
        var digestContext: String?
        var nextStep: String?
    }

    struct SupervisorProjectCoderDispatchWatchContext {
        var project: AXProjectEntry
        var ctx: AXProjectContext
        var userMessage: String
        var workflowContext: String?
        var dispatchId: String
        var baselineMessageCount: Int
        var dispatchDedupeKey: String
        var projectCount: Int
    }

    struct SupervisorProjectCoderDispatchObservation {
        var stepStatus: SupervisorPlanStepStatus?
        var heartbeatReason: String
        var headline: String
        var boardStatus: String
        var summary: String
        var updateWorkflow: Bool
    }

    struct SupervisorProjectScopeResolution {
        var project: AXProjectEntry
        var ctx: AXProjectContext
    }

    struct SupervisorWorkflowStepResolution {
        var project: AXProjectEntry
        var ctx: AXProjectContext
        var job: SupervisorJobRecord
        var plan: SupervisorPlanRecord
        var stepIndex: Int
        var step: SupervisorPlanStepRecord
    }

    struct SupervisorSkillCallResolution {
        var project: AXProjectEntry
        var ctx: AXProjectContext
        var record: SupervisorSkillCallRecord
    }

    struct SupervisorMappedSkillDispatch {
        var toolCall: ToolCall
        var toolName: String
    }

    struct SupervisorCommandResolutionFailure: Error {
        var reasonCode: String
        var message: String
        var projectId: String?
        var projectName: String?
    }

    struct SupervisorSkillMappingFailure: Error {
        var reasonCode: String
    }

    struct SupervisorMissingMultimodalWrapperHint {
        var wrapperSkillId: String
        var suggestedQuery: String
        var capabilityLabel: String
    }
}
