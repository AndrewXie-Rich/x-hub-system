import Foundation

struct XTAutomationRetryPackage: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.automation_retry_package.v1"

    var schemaVersion: String
    var generatedAt: TimeInterval
    var projectID: String
    var lineage: XTAutomationRunLineage?
    var sourceRunID: String
    var sourceFinalState: XTAutomationRunState
    var sourceHoldReason: String
    var sourceHandoffArtifactPath: String
    var retryStrategy: String
    var retryReason: String
    var suggestedNextActions: [String]
    var additionalEvidenceRefs: [String]
    var planningMode: String?
    var planningSummary: String?
    var runtimePatchOverlay: XTAutomationRuntimePatchOverlay?
    var revisedActionGraph: [XTAutomationRecipeAction]?
    var revisedVerifyCommands: [String]?
    var planningArtifactPath: String?
    var recipeProposalArtifactPath: String?
    var retryRunID: String
    var retryArtifactPath: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case projectID = "project_id"
        case lineage
        case sourceRunID = "source_run_id"
        case sourceFinalState = "source_final_state"
        case sourceHoldReason = "source_hold_reason"
        case sourceHandoffArtifactPath = "source_handoff_artifact_path"
        case retryStrategy = "retry_strategy"
        case retryReason = "retry_reason"
        case suggestedNextActions = "suggested_next_actions"
        case additionalEvidenceRefs = "additional_evidence_refs"
        case planningMode = "planning_mode"
        case planningSummary = "planning_summary"
        case runtimePatchOverlay = "runtime_patch_overlay"
        case revisedActionGraph = "revised_action_graph"
        case revisedVerifyCommands = "revised_verify_commands"
        case planningArtifactPath = "planning_artifact_path"
        case recipeProposalArtifactPath = "recipe_proposal_artifact_path"
        case retryRunID = "retry_run_id"
        case retryArtifactPath = "retry_artifact_path"
    }
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
    var retryStrategy: String
    var retryReason: String
    var planningMode: String
    var planningSummary: String
    var runtimePatchOverlay: XTAutomationRuntimePatchOverlay?
    var proposedActionGraph: [XTAutomationRecipeAction]
    var proposedVerifyCommands: [String]
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
        case retryStrategy = "retry_strategy"
        case retryReason = "retry_reason"
        case planningMode = "planning_mode"
        case planningSummary = "planning_summary"
        case runtimePatchOverlay = "runtime_patch_overlay"
        case proposedActionGraph = "proposed_action_graph"
        case proposedVerifyCommands = "proposed_verify_commands"
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
    var retryStrategy: String
    var retryReason: String
    var proposalMode: String
    var proposalSummary: String
    var runtimePatchOverlay: XTAutomationRuntimePatchOverlay?
    var proposedActionGraph: [XTAutomationRecipeAction]
    var proposedVerifyCommands: [String]
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
        case retryStrategy = "retry_strategy"
        case retryReason = "retry_reason"
        case proposalMode = "proposal_mode"
        case proposalSummary = "proposal_summary"
        case runtimePatchOverlay = "runtime_patch_overlay"
        case proposedActionGraph = "proposed_action_graph"
        case proposedVerifyCommands = "proposed_verify_commands"
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
