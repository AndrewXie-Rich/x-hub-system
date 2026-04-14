import Foundation

enum XTAutomationBlockerStage: String, Codable, Equatable, Sendable {
    case bootstrap
    case action
    case verification
    case policy
    case recovery
    case runtime
}

struct XTAutomationBlockerDescriptor: Codable, Equatable, Sendable {
    var code: String
    var summary: String
    var stage: XTAutomationBlockerStage
    var detail: String
    var nextSafeAction: String
    var retryEligible: Bool
    var currentStepID: String? = nil
    var currentStepTitle: String? = nil
    var currentStepState: XTAutomationRunStepState? = nil
    var currentStepSummary: String? = nil

    enum CodingKeys: String, CodingKey {
        case code
        case summary
        case stage
        case detail
        case nextSafeAction = "next_safe_action"
        case retryEligible = "retry_eligible"
        case currentStepID = "current_step_id"
        case currentStepTitle = "current_step_title"
        case currentStepState = "current_step_state"
        case currentStepSummary = "current_step_summary"
    }
}

enum XTAutomationRetryReasonCategory: String, Codable, Equatable, Sendable {
    case verification
    case actionFailure = "action_failure"
    case patchCheck = "patch_check"
    case resume
    case governance
    case recovery
    case unknown
}

struct XTAutomationRetryReasonDescriptor: Codable, Equatable, Sendable {
    var code: String
    var category: XTAutomationRetryReasonCategory
    var summary: String
    var strategy: String
    var blockerCode: String
    var planningMode: String? = nil
    var currentStepID: String? = nil
    var currentStepTitle: String? = nil
    var currentStepState: XTAutomationRunStepState? = nil
    var currentStepSummary: String? = nil

    enum CodingKeys: String, CodingKey {
        case code
        case category
        case summary
        case strategy
        case blockerCode = "blocker_code"
        case planningMode = "planning_mode"
        case currentStepID = "current_step_id"
        case currentStepTitle = "current_step_title"
        case currentStepState = "current_step_state"
        case currentStepSummary = "current_step_summary"
    }
}

enum XTAutomationRecoveryResumeMode: String, Codable, Equatable, Sendable {
    case inPlace = "in_place"
    case retryPackage = "retry_package"
}

struct XTAutomationRetryPackage: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.automation_retry_package.v1"

    var schemaVersion: String
    var generatedAt: TimeInterval
    var projectID: String
    var lineage: XTAutomationRunLineage?
    var deliveryRef: String? = nil
    var sourceRunID: String
    var sourceFinalState: XTAutomationRunState
    var sourceHoldReason: String
    var sourceHandoffArtifactPath: String
    var sourceBlocker: XTAutomationBlockerDescriptor? = nil
    var retryStrategy: String
    var retryReason: String
    var retryReasonDescriptor: XTAutomationRetryReasonDescriptor? = nil
    var suggestedNextActions: [String]
    var additionalEvidenceRefs: [String]
    var planningMode: String?
    var planningSummary: String?
    var runtimePatchOverlay: XTAutomationRuntimePatchOverlay?
    var revisedActionGraph: [XTAutomationRecipeAction]?
    var revisedVerifyCommands: [String]?
    var revisedVerificationContract: XTAutomationVerificationContract? = nil
    var planningArtifactPath: String?
    var recipeProposalArtifactPath: String?
    var retryRunID: String
    var retryArtifactPath: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case projectID = "project_id"
        case lineage
        case deliveryRef = "delivery_ref"
        case sourceRunID = "source_run_id"
        case sourceFinalState = "source_final_state"
        case sourceHoldReason = "source_hold_reason"
        case sourceHandoffArtifactPath = "source_handoff_artifact_path"
        case sourceBlocker = "source_blocker"
        case retryStrategy = "retry_strategy"
        case retryReason = "retry_reason"
        case retryReasonDescriptor = "retry_reason_descriptor"
        case suggestedNextActions = "suggested_next_actions"
        case additionalEvidenceRefs = "additional_evidence_refs"
        case planningMode = "planning_mode"
        case planningSummary = "planning_summary"
        case runtimePatchOverlay = "runtime_patch_overlay"
        case revisedActionGraph = "revised_action_graph"
        case revisedVerifyCommands = "revised_verify_commands"
        case revisedVerificationContract = "revised_verification_contract"
        case planningArtifactPath = "planning_artifact_path"
        case recipeProposalArtifactPath = "recipe_proposal_artifact_path"
        case retryRunID = "retry_run_id"
        case retryArtifactPath = "retry_artifact_path"
    }
}

struct XTAutomationRetryRevision: Equatable, Sendable {
    var planningMode: String
    var planningSummary: String
    var revisedActionGraph: [XTAutomationRecipeAction]?
    var revisedVerifyCommands: [String]?
    var revisedVerificationContract: XTAutomationVerificationContract? = nil
    var additionalEvidenceRefs: [String]
}

struct XTAutomationRetryPlanPreview: Equatable, Sendable {
    var sourceRunID: String
    var sourceHandoffArtifactPath: String
    var retryStrategy: String
    var retryReason: String
    var retryReasonDescriptor: XTAutomationRetryReasonDescriptor?
    var planningMode: String
    var planningSummary: String
}

struct XTAutomationRetryPlanningArtifact: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.automation_retry_planning.v1"

    var schemaVersion: String
    var generatedAt: TimeInterval
    var projectID: String
    var lineage: XTAutomationRunLineage?
    var sourceRunID: String
    var sourceHandoffArtifactPath: String
    var baseRecipeRef: String
    var sourceBlocker: XTAutomationBlockerDescriptor? = nil
    var retryStrategy: String
    var retryReason: String
    var retryReasonDescriptor: XTAutomationRetryReasonDescriptor? = nil
    var planningMode: String
    var planningSummary: String
    var runtimePatchOverlay: XTAutomationRuntimePatchOverlay?
    var proposedActionGraph: [XTAutomationRecipeAction]
    var proposedVerifyCommands: [String]
    var proposedVerificationContract: XTAutomationVerificationContract? = nil
    var suggestedNextActions: [String]
    var additionalEvidenceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case projectID = "project_id"
        case lineage
        case sourceRunID = "source_run_id"
        case sourceHandoffArtifactPath = "source_handoff_artifact_path"
        case baseRecipeRef = "base_recipe_ref"
        case sourceBlocker = "source_blocker"
        case retryStrategy = "retry_strategy"
        case retryReason = "retry_reason"
        case retryReasonDescriptor = "retry_reason_descriptor"
        case planningMode = "planning_mode"
        case planningSummary = "planning_summary"
        case runtimePatchOverlay = "runtime_patch_overlay"
        case proposedActionGraph = "proposed_action_graph"
        case proposedVerifyCommands = "proposed_verify_commands"
        case proposedVerificationContract = "proposed_verification_contract"
        case suggestedNextActions = "suggested_next_actions"
        case additionalEvidenceRefs = "additional_evidence_refs"
    }
}

struct XTAutomationRecipeProposalArtifact: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.automation_recipe_proposal.v1"

    var schemaVersion: String
    var generatedAt: TimeInterval
    var projectID: String
    var lineage: XTAutomationRunLineage?
    var sourceRunID: String
    var sourceHandoffArtifactPath: String
    var sourcePlanningArtifactPath: String?
    var baseRecipeRef: String
    var sourceBlocker: XTAutomationBlockerDescriptor? = nil
    var retryStrategy: String
    var retryReason: String
    var retryReasonDescriptor: XTAutomationRetryReasonDescriptor? = nil
    var proposalMode: String
    var proposalSummary: String
    var runtimePatchOverlay: XTAutomationRuntimePatchOverlay?
    var proposedActionGraph: [XTAutomationRecipeAction]
    var proposedVerifyCommands: [String]
    var proposedVerificationContract: XTAutomationVerificationContract? = nil
    var suggestedNextActions: [String]
    var additionalEvidenceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case projectID = "project_id"
        case lineage
        case sourceRunID = "source_run_id"
        case sourceHandoffArtifactPath = "source_handoff_artifact_path"
        case sourcePlanningArtifactPath = "source_planning_artifact_path"
        case baseRecipeRef = "base_recipe_ref"
        case sourceBlocker = "source_blocker"
        case retryStrategy = "retry_strategy"
        case retryReason = "retry_reason"
        case retryReasonDescriptor = "retry_reason_descriptor"
        case proposalMode = "proposal_mode"
        case proposalSummary = "proposal_summary"
        case runtimePatchOverlay = "runtime_patch_overlay"
        case proposedActionGraph = "proposed_action_graph"
        case proposedVerifyCommands = "proposed_verify_commands"
        case proposedVerificationContract = "proposed_verification_contract"
        case suggestedNextActions = "suggested_next_actions"
        case additionalEvidenceRefs = "additional_evidence_refs"
    }
}

func xtAutomationHandoffArtifactRelativePath(for runID: String) -> String {
    "build/reports/xt_automation_run_handoff_\(xtAutomationActionToken(runID, fallback: "run")).v1.json"
}

func xtAutomationRetryPackageRelativePath(for runID: String) -> String {
    "build/reports/xt_automation_retry_package_\(xtAutomationActionToken(runID, fallback: "run")).v1.json"
}

func xtAutomationRetryPlanningArtifactRelativePath(for runID: String) -> String {
    "build/reports/xt_automation_retry_planning_\(xtAutomationActionToken(runID, fallback: "run")).v1.json"
}

func xtAutomationRetryRecipeProposalArtifactRelativePath(for runID: String) -> String {
    "build/reports/xt_automation_recipe_proposal_\(xtAutomationActionToken(runID, fallback: "run")).v1.json"
}

func xtAutomationLoadHandoffArtifact(
    for runID: String,
    ctx: AXProjectContext,
    reportedRelativePath: String? = nil
) -> (artifact: XTAutomationRunHandoffArtifact, relativePath: String)? {
    let candidatePaths = xtAutomationOrderedUniqueStrings([
        reportedRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
        xtAutomationHandoffArtifactRelativePath(for: runID),
    ])

    for relativePath in candidatePaths {
        let url = ctx.root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path),
              let artifact = xtAutomationDecodeJSON(from: url, as: XTAutomationRunHandoffArtifact.self) else {
            continue
        }
        return (artifact, relativePath)
    }

    return nil
}

func xtAutomationLoadRetryPlanningArtifact(
    sourceRunID: String,
    ctx: AXProjectContext,
    reportedRelativePath: String? = nil
) -> (artifact: XTAutomationRetryPlanningArtifact, relativePath: String)? {
    let candidatePaths = xtAutomationOrderedUniqueStrings([
        reportedRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
        xtAutomationRetryPlanningArtifactRelativePath(for: sourceRunID),
    ])

    for relativePath in candidatePaths {
        let url = ctx.root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path),
              let artifact = xtAutomationDecodeJSON(from: url, as: XTAutomationRetryPlanningArtifact.self) else {
            continue
        }
        return (artifact, relativePath)
    }

    return nil
}

func xtAutomationLoadRetryRecipeProposalArtifact(
    sourceRunID: String,
    ctx: AXProjectContext,
    reportedRelativePath: String? = nil
) -> (artifact: XTAutomationRecipeProposalArtifact, relativePath: String)? {
    let candidatePaths = xtAutomationOrderedUniqueStrings([
        reportedRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
        xtAutomationRetryRecipeProposalArtifactRelativePath(for: sourceRunID),
    ])

    for relativePath in candidatePaths {
        let url = ctx.root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path),
              let artifact = xtAutomationDecodeJSON(from: url, as: XTAutomationRecipeProposalArtifact.self) else {
            continue
        }
        return (artifact, relativePath)
    }

    return nil
}

@discardableResult
func xtAutomationPersistRetryPackage(
    _ package: XTAutomationRetryPackage,
    ctx: AXProjectContext
) -> XTAutomationRetryPackage? {
    let runRef = package.retryRunID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? package.sourceRunID
        : package.retryRunID
    guard !runRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

    var persisted = package
    persisted.retryArtifactPath = xtAutomationRetryPackageRelativePath(for: runRef)
    let targetURL = ctx.root.appendingPathComponent(persisted.retryArtifactPath)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    guard let data = try? encoder.encode(persisted) else { return nil }

    do {
        try SupervisorStoreWriteSupport.writeSnapshotData(data, to: targetURL)
        return persisted
    } catch {
        return nil
    }
}

@discardableResult
func xtAutomationPersistRetryPlanningArtifact(
    _ artifact: XTAutomationRetryPlanningArtifact,
    ctx: AXProjectContext
) -> String? {
    let runRef = artifact.sourceRunID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !runRef.isEmpty else { return nil }

    let relativePath = xtAutomationRetryPlanningArtifactRelativePath(for: runRef)
    let targetURL = ctx.root.appendingPathComponent(relativePath)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    guard let data = try? encoder.encode(artifact) else { return nil }

    do {
        try SupervisorStoreWriteSupport.writeSnapshotData(data, to: targetURL)
        return relativePath
    } catch {
        return nil
    }
}

@discardableResult
func xtAutomationPersistRetryRecipeProposalArtifact(
    _ artifact: XTAutomationRecipeProposalArtifact,
    ctx: AXProjectContext
) -> String? {
    let runRef = artifact.sourceRunID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !runRef.isEmpty else { return nil }

    let relativePath = xtAutomationRetryRecipeProposalArtifactRelativePath(for: runRef)
    let targetURL = ctx.root.appendingPathComponent(relativePath)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    guard let data = try? encoder.encode(artifact) else { return nil }

    do {
        try SupervisorStoreWriteSupport.writeSnapshotData(data, to: targetURL)
        return relativePath
    } catch {
        return nil
    }
}

func xtAutomationDecodeJSON<T: Decodable>(from url: URL, as type: T.Type) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}

private func xtAutomationOrderedUniqueStrings(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []

    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
        ordered.append(trimmed)
    }

    return ordered
}

func xtAutomationStructuredBlocker(
    finalState: XTAutomationRunState,
    holdReason: String,
    detail: String,
    verificationReport: XTAutomationVerificationReport? = nil,
    currentStepID: String? = nil,
    currentStepTitle: String? = nil,
    currentStepState: XTAutomationRunStepState? = nil,
    currentStepSummary: String? = nil
) -> XTAutomationBlockerDescriptor? {
    let verificationHoldReason = verificationReport?.holdReason.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let normalizedHoldReason = holdReason.trimmingCharacters(in: .whitespacesAndNewlines)
    let blockerCode = xtAutomationFirstNonEmpty([
        verificationHoldReason,
        normalizedHoldReason,
        finalState == .blocked || finalState == .failed ? finalState.rawValue : ""
    ])
    guard let blockerCode else { return nil }

    let lowered = blockerCode.lowercased()
    let stage: XTAutomationBlockerStage
    let nextSafeAction: String
    let retryEligible: Bool

    if !verificationHoldReason.isEmpty || lowered.hasPrefix("automation_verify_") {
        stage = .verification
        nextSafeAction = "rerun_focused_verification"
        retryEligible = true
    } else if lowered.contains("grant") || lowered.contains("authorization") || lowered.contains("policy") {
        stage = .policy
        nextSafeAction = "open_hub_grants"
        retryEligible = false
    } else if lowered.contains("patch_check") {
        stage = .action
        nextSafeAction = "repair_patch_and_retry"
        retryEligible = true
    } else if lowered.contains("input") || lowered.contains("instruction") || lowered.contains("review") {
        stage = .runtime
        nextSafeAction = "clarify_with_user"
        retryEligible = false
    } else if finalState == .takeover || finalState == .downgraded {
        stage = .recovery
        nextSafeAction = "apply_supervisor_replan"
        retryEligible = false
    } else if finalState == .failed {
        stage = .recovery
        nextSafeAction = "inspect_incident_and_replan"
        retryEligible = false
    } else if lowered.contains("action") || lowered.contains("tool") {
        stage = .action
        nextSafeAction = "resume_from_failed_action"
        retryEligible = true
    } else if lowered.contains("recipe") || lowered.contains("trigger") {
        stage = .bootstrap
        nextSafeAction = "repair_recipe_and_retry"
        retryEligible = false
    } else {
        stage = .runtime
        nextSafeAction = "inspect_incident_and_replan"
        retryEligible = finalState == .blocked
    }

    let summary = xtAutomationFirstNonEmpty([
        SupervisorBlockerPresentation.displayText(blockerCode),
        verificationReport?.detail.trimmingCharacters(in: .whitespacesAndNewlines),
        detail.trimmingCharacters(in: .whitespacesAndNewlines),
        blockerCode
    ]) ?? blockerCode

    return XTAutomationBlockerDescriptor(
        code: blockerCode,
        summary: summary,
        stage: stage,
        detail: xtAutomationFirstNonEmpty([
            detail.trimmingCharacters(in: .whitespacesAndNewlines),
            verificationReport?.detail.trimmingCharacters(in: .whitespacesAndNewlines),
            summary
        ]) ?? summary,
        nextSafeAction: nextSafeAction,
        retryEligible: retryEligible,
        currentStepID: xtAutomationNormalizedOptionalScalar(currentStepID),
        currentStepTitle: xtAutomationNormalizedOptionalScalar(currentStepTitle),
        currentStepState: currentStepState,
        currentStepSummary: xtAutomationNormalizedOptionalScalar(currentStepSummary)
    )
}

func xtAutomationStructuredRetryReason(
    strategy: String,
    reason: String,
    blocker: XTAutomationBlockerDescriptor?,
    planningMode: String? = nil
) -> XTAutomationRetryReasonDescriptor? {
    let normalizedStrategy = strategy.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    let code = xtAutomationFirstNonEmpty([
        normalizedReason,
        blocker?.code,
        normalizedStrategy
    ])
    guard let code else { return nil }

    let lowered = code.lowercased()
    let category: XTAutomationRetryReasonCategory
    if lowered.hasPrefix("automation_verify_") || normalizedStrategy.contains("verify") {
        category = .verification
    } else if lowered.contains("patch_check") {
        category = .patchCheck
    } else if lowered.contains("grant") || lowered.contains("authorization") || lowered.contains("policy") {
        category = .governance
    } else if lowered.contains("action") || lowered.contains("tool") {
        category = .actionFailure
    } else if lowered.contains("resume") {
        category = .resume
    } else if lowered.contains("recovery") || lowered.contains("stale") || lowered.contains("retry_budget") {
        category = .recovery
    } else {
        category = .unknown
    }

    let summary = xtAutomationFirstNonEmpty([
        blocker?.summary,
        planningMode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? "retry planned via \(planningMode!.trimmingCharacters(in: .whitespacesAndNewlines))"
            : nil,
        normalizedReason,
        normalizedStrategy
    ]) ?? code

    return XTAutomationRetryReasonDescriptor(
        code: code,
        category: category,
        summary: summary,
        strategy: normalizedStrategy,
        blockerCode: blocker?.code ?? code,
        planningMode: xtAutomationNormalizedOptionalScalar(planningMode),
        currentStepID: blocker?.currentStepID,
        currentStepTitle: blocker?.currentStepTitle,
        currentStepState: blocker?.currentStepState,
        currentStepSummary: blocker?.currentStepSummary
    )
}

func xtAutomationRetryPlanPreview(
    for sourceRunID: String,
    ctx: AXProjectContext
) -> XTAutomationRetryPlanPreview? {
    let normalizedSourceRunID = sourceRunID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedSourceRunID.isEmpty,
          let config = try? AXProjectStore.loadOrCreateConfig(for: ctx),
          let recipe = config.activeAutomationRecipe,
          !recipe.actionGraph.isEmpty,
          let handoff = xtAutomationLoadHandoffArtifact(
              for: normalizedSourceRunID,
              ctx: ctx
          ) else {
        return nil
    }

    let strategy = xtAutomationRetryStrategy(for: handoff.artifact)
    let revision = xtAutomationRetryRevision(recipe: recipe, artifact: handoff.artifact)
    let blocker = handoff.artifact.structuredBlocker
        ?? xtAutomationStructuredBlocker(
            finalState: handoff.artifact.finalState,
            holdReason: handoff.artifact.holdReason,
            detail: handoff.artifact.detail,
            verificationReport: handoff.artifact.verificationReport,
            currentStepID: handoff.artifact.currentStepID,
            currentStepTitle: handoff.artifact.currentStepTitle,
            currentStepState: handoff.artifact.currentStepState,
            currentStepSummary: handoff.artifact.currentStepSummary
        )

    return XTAutomationRetryPlanPreview(
        sourceRunID: normalizedSourceRunID,
        sourceHandoffArtifactPath: handoff.relativePath,
        retryStrategy: strategy.strategy,
        retryReason: strategy.reason,
        retryReasonDescriptor: xtAutomationStructuredRetryReason(
            strategy: strategy.strategy,
            reason: strategy.reason,
            blocker: blocker,
            planningMode: revision.planningMode
        ),
        planningMode: revision.planningMode,
        planningSummary: revision.planningSummary
    )
}

func xtAutomationRetryStrategy(
    for artifact: XTAutomationRunHandoffArtifact
) -> (strategy: String, reason: String) {
    let verificationHoldReason = artifact.verificationReport?.holdReason
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let holdReason = artifact.holdReason.trimmingCharacters(in: .whitespacesAndNewlines)

    if verificationHoldReason.hasPrefix("automation_verify_") || holdReason.hasPrefix("automation_verify_") {
        return ("verify_failed_retry", verificationHoldReason.isEmpty ? holdReason : verificationHoldReason)
    }
    if holdReason == "automation_patch_check_failed" {
        return ("patch_check_retry", "automation_patch_check_failed")
    }
    if holdReason == "automation_action_failed" || holdReason == "automation_action_execution_error" {
        return ("action_failure_retry", holdReason)
    }
    if holdReason.isEmpty {
        return ("resume_retry", artifact.finalState.rawValue)
    }
    return ("resume_retry", holdReason)
}

func xtAutomationRetryRevision(
    recipe: AXAutomationRecipeRuntimeBinding,
    artifact: XTAutomationRunHandoffArtifact
) -> XTAutomationRetryRevision {
    let verificationHoldReason = artifact.verificationReport?.holdReason
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let holdReason = artifact.holdReason.trimmingCharacters(in: .whitespacesAndNewlines)
    let failedActionIDs = Set(artifact.actionResults.filter { !$0.ok }.map(\.actionID))
    let firstFailedIndex = recipe.actionGraph.firstIndex { failedActionIDs.contains($0.actionID) }

    if verificationHoldReason.hasPrefix("automation_verify_") || holdReason.hasPrefix("automation_verify_") {
        let revisedActionGraph = xtAutomationVerifyOnlyRetryActionGraph(
            includeWorkspaceDiff: artifact.workspaceDiffReport?.attempted == true
        )
        let revisedVerifyCommands = xtAutomationRetryVerifyCommands(from: artifact.verificationReport)
        let revisedVerificationContract = xtAutomationRetryVerificationContract(
            from: artifact.verificationReport,
            revisedVerifyCommands: revisedVerifyCommands
        )
        return XTAutomationRetryRevision(
            planningMode: "verify_only_retry",
            planningSummary: "skip successful mutation actions and rerun failing verification commands against current workspace",
            revisedActionGraph: revisedActionGraph,
            revisedVerifyCommands: revisedVerifyCommands,
            revisedVerificationContract: revisedVerificationContract,
            additionalEvidenceRefs: [
                "retry://planning_mode/verify_only_retry",
                "retry://planning_summary/skip_successful_mutations_and_rerun_verify",
                "retry://revised_action_graph/\(revisedActionGraph.count)",
                revisedVerifyCommands.isEmpty ? "" : "retry://revised_verify_commands/\(revisedVerifyCommands.count)",
                revisedVerificationContract == nil ? "" : "retry://revised_verification_contract/preserved"
            ]
        )
    }

    if let firstFailedIndex, firstFailedIndex > 0 {
        let failedActionID = recipe.actionGraph[firstFailedIndex].actionID
        let revisedActionGraph = Array(recipe.actionGraph[firstFailedIndex...])
        return XTAutomationRetryRevision(
            planningMode: "resume_from_failed_action",
            planningSummary: "skip \(firstFailedIndex) successful actions and resume from \(failedActionID)",
            revisedActionGraph: revisedActionGraph,
            revisedVerifyCommands: nil,
            revisedVerificationContract: nil,
            additionalEvidenceRefs: [
                "retry://planning_mode/resume_from_failed_action",
                "retry://resume_from_action/\(failedActionID)",
                "retry://revised_action_graph/\(revisedActionGraph.count)"
            ]
        )
    }

    let summary: String
    if holdReason == "automation_patch_check_failed" {
        summary = "patch precheck failed before a resumable suffix was found; replay same recipe with carried evidence"
    } else {
        summary = "no deterministic retry revision available; replay same recipe with carried evidence"
    }
    return XTAutomationRetryRevision(
        planningMode: "replay_same_recipe",
        planningSummary: summary,
        revisedActionGraph: nil,
        revisedVerifyCommands: nil,
        revisedVerificationContract: nil,
        additionalEvidenceRefs: [
            "retry://planning_mode/replay_same_recipe"
        ]
    )
}

private func xtAutomationRetryVerificationContract(
    from report: XTAutomationVerificationReport?,
    revisedVerifyCommands: [String]
) -> XTAutomationVerificationContract? {
    guard let contract = report?.contract else { return nil }
    let commands = revisedVerifyCommands.isEmpty ? contract.verifyCommands : revisedVerifyCommands
    return XTAutomationVerificationContract(
        expectedState: contract.expectedState,
        verifyMethod: contract.verifyMethod,
        retryPolicy: contract.retryPolicy,
        holdPolicy: contract.holdPolicy,
        evidenceRequired: contract.evidenceRequired,
        triggerActionIDs: contract.triggerActionIDs,
        verifyCommands: xtAutomationOrderedUniqueStrings(commands)
    )
}

private func xtAutomationRetryVerifyCommands(
    from report: XTAutomationVerificationReport?
) -> [String] {
    guard let report else { return [] }
    let commands = report.commandResults
        .filter { !$0.ok }
        .map(\.command)
    return xtAutomationOrderedUniqueStrings(commands)
}

private func xtAutomationVerifyOnlyRetryActionGraph(
    includeWorkspaceDiff: Bool
) -> [XTAutomationRecipeAction] {
    var actions: [XTAutomationRecipeAction] = [
        XTAutomationRecipeAction(
            actionID: "retry_verify_snapshot",
            title: "Retry Verify Snapshot",
            tool: .project_snapshot,
            args: [:],
            continueOnFailure: false,
            successBodyContains: "root=",
            requiresVerification: true
        )
    ]
    if includeWorkspaceDiff {
        actions.append(
            XTAutomationRecipeAction(
                actionID: "retry_verify_workspace_diff",
                title: "Retry Workspace Diff",
                tool: .git_diff,
                args: [:],
                continueOnFailure: true,
                successBodyContains: "",
                requiresVerification: false
            )
        )
    }
    return actions
}

func xtAutomationFirstNonEmpty(_ values: [String?]) -> String? {
    for value in values {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
    }
    return nil
}
