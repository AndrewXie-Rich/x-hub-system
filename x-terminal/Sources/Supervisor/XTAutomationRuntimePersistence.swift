import Foundation

func xtAutomationReadRawLogRows(for ctx: AXProjectContext) -> [[String: Any]] {
    guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path),
          let data = try? Data(contentsOf: ctx.rawLogURL),
          let text = String(data: data, encoding: .utf8) else {
        return []
    }

    return text
        .split(separator: "\n", omittingEmptySubsequences: true)
        .compactMap { line in
            let rawLine = String(line)
            guard let lineData = rawLine.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                return nil
            }
            return object
        }
}

func xtAutomationLoadExecutionReport(
    for runID: String,
    ctx: AXProjectContext
) -> XTAutomationRunExecutionReport? {
    let normalizedRunID = runID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedRunID.isEmpty else { return nil }

    let rows = xtAutomationReadRawLogRows(for: ctx)
    let executionRow = rows.last(where: {
        ($0["type"] as? String) == "automation_execution"
            && ($0["phase"] as? String) == "completed"
            && ($0["run_id"] as? String) == normalizedRunID
    })

    let reportedHandoffPath = xtAutomationRuntimeString(executionRow?["handoff_artifact_path"])
    let handoff = xtAutomationLoadHandoffArtifact(
        for: normalizedRunID,
        ctx: ctx,
        reportedRelativePath: reportedHandoffPath
    )

    let handoffArtifact = handoff?.artifact
    let relativeHandoffPath = handoff?.relativePath
    let finalState = xtAutomationRuntimeState(executionRow?["final_state"])
        ?? handoffArtifact?.finalState
    guard let finalState else { return nil }
    let lineage = xtAutomationRuntimeLineage(
        from: executionRow,
        artifactLineage: handoffArtifact?.lineage,
        fallbackRunID: normalizedRunID
    )

    let recipeRef = xtAutomationRuntimeString(executionRow?["recipe_ref"])
        ?? handoffArtifact?.recipeRef ?? ""
    let totalActionCount = xtAutomationRuntimeInt(executionRow?["total_action_count"], fallback: handoffArtifact?.actionResults.count ?? 0)
    let executedActionCount = xtAutomationRuntimeInt(executionRow?["executed_action_count"], fallback: handoffArtifact?.actionResults.count ?? 0)
    let succeededActionCount = xtAutomationRuntimeInt(
        executionRow?["succeeded_action_count"],
        fallback: handoffArtifact?.actionResults.filter(\.ok).count ?? 0
    )
    let holdReason = xtAutomationRuntimeString(executionRow?["hold_reason"])
        ?? handoffArtifact?.holdReason ?? ""
    let detail = xtAutomationRuntimeString(executionRow?["detail"])
        ?? handoffArtifact?.detail ?? ""
    let verificationReport = xtAutomationRuntimeVerificationReport(from: executionRow?["verification"])
        ?? handoffArtifact?.verificationReport
    let workspaceDiffReport = xtAutomationRuntimeWorkspaceDiffReport(from: executionRow?["workspace_diff"])
        ?? handoffArtifact?.workspaceDiffReport
    let auditRef = xtAutomationRuntimeString(executionRow?["audit_ref"]) ?? ""

    return XTAutomationRunExecutionReport(
        runID: normalizedRunID,
        lineage: lineage,
        recipeRef: recipeRef,
        totalActionCount: totalActionCount,
        executedActionCount: executedActionCount,
        succeededActionCount: succeededActionCount,
        finalState: finalState,
        holdReason: holdReason,
        detail: detail,
        actionResults: handoffArtifact?.actionResults ?? [],
        verificationReport: verificationReport,
        workspaceDiffReport: workspaceDiffReport,
        handoffArtifactPath: relativeHandoffPath ?? reportedHandoffPath,
        auditRef: auditRef
    )
}

func xtAutomationLoadRetryPackage(
    forRetryRunID retryRunID: String,
    projectID: String,
    ctx: AXProjectContext
) -> XTAutomationRetryPackage? {
    let normalizedRunID = retryRunID.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedProjectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedRunID.isEmpty, !normalizedProjectID.isEmpty else { return nil }

    let rows = xtAutomationReadRawLogRows(for: ctx)
        .reversed()
    for row in rows {
        guard (row["type"] as? String) == "automation_retry",
              (row["status"] as? String) == "scheduled",
              xtAutomationRuntimeString(row["retry_run_id"]) == normalizedRunID else {
            continue
        }

        let artifactPath = xtAutomationRuntimeString(row["retry_artifact_path"])
            ?? xtAutomationRetryPackageRelativePath(for: normalizedRunID)
        let url = ctx.root.appendingPathComponent(artifactPath)
        if FileManager.default.fileExists(atPath: url.path),
           let package = xtAutomationDecodeJSON(from: url, as: XTAutomationRetryPackage.self),
           package.projectID == normalizedProjectID {
            let normalized = xtAutomationNormalizedRetryPackage(package, fallbackRetryRunID: normalizedRunID)
            return xtAutomationHydratedRetryPackage(
                normalized,
                ctx: ctx,
                row: row,
                fallbackRetryRunID: normalizedRunID
            )
        }

        let sourceRunID = xtAutomationRuntimeString(row["source_run_id"]) ?? ""
        let planningArtifactPath = xtAutomationRuntimeString(row["planning_artifact_path"])
        let planningArtifact = xtAutomationLoadRetryPlanningArtifact(
            sourceRunID: sourceRunID,
            ctx: ctx,
            reportedRelativePath: planningArtifactPath
        )
        let recipeProposalArtifactPath = xtAutomationRuntimeString(row["recipe_proposal_artifact_path"])
        let recipeProposalArtifact = xtAutomationLoadRetryRecipeProposalArtifact(
            sourceRunID: sourceRunID,
            ctx: ctx,
            reportedRelativePath: recipeProposalArtifactPath
        )
        let retryDepth = xtAutomationRuntimeIntOptional(row["retry_depth"])
        let lineage = xtAutomationRuntimeLineage(
            from: row,
            artifactLineage: recipeProposalArtifact?.artifact.lineage ?? planningArtifact?.artifact.lineage,
            fallbackRunID: normalizedRunID
        )
        let runtimePatchOverlay = xtAutomationRuntimeResolvedPatchOverlay(
            recipeProposalArtifact: recipeProposalArtifact?.artifact,
            planningArtifact: planningArtifact?.artifact,
            fallbackActionGraph: nil,
            fallbackVerifyCommands: nil
        )

        return XTAutomationRetryPackage(
            schemaVersion: XTAutomationRetryPackage.currentSchemaVersion,
            generatedAt: xtAutomationRuntimeDouble(row["created_at"]),
            projectID: normalizedProjectID,
            lineage: lineage.retryChild(
                parentRunID: sourceRunID,
                retryDepth: retryDepth
            ),
            sourceRunID: sourceRunID,
            sourceFinalState: .blocked,
            sourceHoldReason: "",
            sourceHandoffArtifactPath: xtAutomationRuntimeString(row["source_handoff_artifact_path"]) ?? "",
            retryStrategy: xtAutomationRuntimeString(row["retry_strategy"]) ?? "",
            retryReason: xtAutomationRuntimeString(row["retry_reason"]) ?? "",
            suggestedNextActions: [],
            additionalEvidenceRefs: xtAutomationRuntimeOrderedUniqueStrings(
                xtAutomationRuntimeStringArray(row["additional_evidence_refs"]) + [
                    (xtAutomationRuntimeString(row["retry_trigger"]).map { "retry://trigger/\($0)" }) ?? "",
                    (retryDepth.map { "retry://depth/\($0)" }) ?? ""
                ]
            ),
            planningMode: planningArtifact?.artifact.planningMode
                ?? recipeProposalArtifact?.artifact.proposalMode,
            planningSummary: planningArtifact?.artifact.planningSummary
                ?? recipeProposalArtifact?.artifact.proposalSummary,
            runtimePatchOverlay: runtimePatchOverlay,
            revisedActionGraph: xtAutomationRuntimeProposedActionGraph(
                runtimePatchOverlay: runtimePatchOverlay,
                recipeProposalArtifact: recipeProposalArtifact?.artifact,
                planningArtifact: planningArtifact?.artifact
            ),
            revisedVerifyCommands: xtAutomationRuntimeProposedVerifyCommands(
                runtimePatchOverlay: runtimePatchOverlay,
                recipeProposalArtifact: recipeProposalArtifact?.artifact,
                planningArtifact: planningArtifact?.artifact
            ),
            planningArtifactPath: planningArtifact?.relativePath ?? planningArtifactPath,
            recipeProposalArtifactPath: recipeProposalArtifact?.relativePath ?? recipeProposalArtifactPath,
            retryRunID: normalizedRunID,
            retryArtifactPath: artifactPath
        )
    }

    return nil
}

private func xtAutomationNormalizedRetryPackage(
    _ package: XTAutomationRetryPackage,
    fallbackRetryRunID: String
) -> XTAutomationRetryPackage {
    var normalized = package
    let lineage = xtAutomationResolvedLineage(
        package.lineage,
        fallbackRunID: fallbackRetryRunID
    )
    let sourceRunID = package.sourceRunID.trimmingCharacters(in: .whitespacesAndNewlines)
    if sourceRunID.isEmpty {
        normalized.lineage = lineage
    } else if lineage.parentRunID == sourceRunID {
        normalized.lineage = lineage
    } else if lineage.retryDepth > 0 {
        normalized.lineage = XTAutomationRunLineage(
            lineageID: lineage.lineageID,
            rootRunID: lineage.rootRunID,
            parentRunID: sourceRunID,
            retryDepth: lineage.retryDepth
        )
    } else {
        normalized.lineage = lineage.retryChild(
            parentRunID: sourceRunID,
            retryDepth: automationRuntimeRetryDepthFallback(from: package)
        )
    }
    return normalized
}

private func xtAutomationHydratedRetryPackage(
    _ package: XTAutomationRetryPackage,
    ctx: AXProjectContext,
    row: [String: Any]?,
    fallbackRetryRunID: String
) -> XTAutomationRetryPackage {
    var hydrated = xtAutomationNormalizedRetryPackage(package, fallbackRetryRunID: fallbackRetryRunID)
    let sourceRunID = hydrated.sourceRunID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sourceRunID.isEmpty else { return hydrated }

    let planningArtifact = xtAutomationLoadRetryPlanningArtifact(
        sourceRunID: sourceRunID,
        ctx: ctx,
        reportedRelativePath: xtAutomationRuntimeString(row?["planning_artifact_path"]) ?? hydrated.planningArtifactPath
    )
    let recipeProposalArtifact = xtAutomationLoadRetryRecipeProposalArtifact(
        sourceRunID: sourceRunID,
        ctx: ctx,
        reportedRelativePath: xtAutomationRuntimeString(row?["recipe_proposal_artifact_path"]) ?? hydrated.recipeProposalArtifactPath
    )
    let runtimePatchOverlay = hydrated.runtimePatchOverlay
        ?? xtAutomationRuntimeResolvedPatchOverlay(
            recipeProposalArtifact: recipeProposalArtifact?.artifact,
            planningArtifact: planningArtifact?.artifact,
            fallbackActionGraph: hydrated.revisedActionGraph,
            fallbackVerifyCommands: hydrated.revisedVerifyCommands
        )

    if let planningArtifact {
        hydrated.planningArtifactPath = planningArtifact.relativePath
        if hydrated.planningMode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            hydrated.planningMode = planningArtifact.artifact.planningMode
        }
        if hydrated.planningSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            hydrated.planningSummary = planningArtifact.artifact.planningSummary
        }
    }
    if let recipeProposalArtifact {
        hydrated.recipeProposalArtifactPath = recipeProposalArtifact.relativePath
        if hydrated.planningMode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            hydrated.planningMode = recipeProposalArtifact.artifact.proposalMode
        }
        if hydrated.planningSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            hydrated.planningSummary = recipeProposalArtifact.artifact.proposalSummary
        }
    }
    if hydrated.runtimePatchOverlay == nil {
        hydrated.runtimePatchOverlay = runtimePatchOverlay
    }

    if hydrated.revisedActionGraph?.isEmpty != false {
        hydrated.revisedActionGraph = xtAutomationRuntimeProposedActionGraph(
            runtimePatchOverlay: runtimePatchOverlay,
            recipeProposalArtifact: recipeProposalArtifact?.artifact,
            planningArtifact: planningArtifact?.artifact
        )
    }
    if hydrated.revisedVerifyCommands?.isEmpty != false {
        hydrated.revisedVerifyCommands = xtAutomationRuntimeProposedVerifyCommands(
            runtimePatchOverlay: runtimePatchOverlay,
            recipeProposalArtifact: recipeProposalArtifact?.artifact,
            planningArtifact: planningArtifact?.artifact
        )
    }

    return hydrated
}

private func xtAutomationRuntimeProposedActionGraph(
    runtimePatchOverlay: XTAutomationRuntimePatchOverlay?,
    recipeProposalArtifact: XTAutomationRecipeProposalArtifact?,
    planningArtifact: XTAutomationRetryPlanningArtifact?
) -> [XTAutomationRecipeAction]? {
    if let runtimePatchOverlay,
       let value = runtimePatchOverlay.normalized().mergePatch["action_graph"],
       let decoded = xtAutomationDecodedJSONValue(value, as: [XTAutomationRecipeAction].self),
       !decoded.isEmpty {
        return decoded
    }
    if let proposed = recipeProposalArtifact?.proposedActionGraph,
       !proposed.isEmpty {
        return proposed
    }
    if let proposed = planningArtifact?.proposedActionGraph,
       !proposed.isEmpty {
        return proposed
    }
    return nil
}

private func xtAutomationRuntimeProposedVerifyCommands(
    runtimePatchOverlay: XTAutomationRuntimePatchOverlay?,
    recipeProposalArtifact: XTAutomationRecipeProposalArtifact?,
    planningArtifact: XTAutomationRetryPlanningArtifact?
) -> [String]? {
    if let runtimePatchOverlay,
       let value = runtimePatchOverlay.normalized().mergePatch["verify_commands"],
       let commands = xtAutomationRuntimeStringArray(from: value),
       !commands.isEmpty {
        return commands
    }
    if let commands = recipeProposalArtifact?.proposedVerifyCommands,
       !commands.isEmpty {
        return commands
    }
    if let commands = planningArtifact?.proposedVerifyCommands,
       !commands.isEmpty {
        return commands
    }
    return nil
}

private func xtAutomationRuntimeResolvedPatchOverlay(
    recipeProposalArtifact: XTAutomationRecipeProposalArtifact?,
    planningArtifact: XTAutomationRetryPlanningArtifact?,
    fallbackActionGraph: [XTAutomationRecipeAction]?,
    fallbackVerifyCommands: [String]?
) -> XTAutomationRuntimePatchOverlay? {
    if let overlay = recipeProposalArtifact?.runtimePatchOverlay {
        return overlay.normalized()
    }
    if let overlay = planningArtifact?.runtimePatchOverlay {
        return overlay.normalized()
    }
    return xtAutomationRuntimePatchOverlay(
        revisedActionGraph: recipeProposalArtifact?.proposedActionGraph
            ?? planningArtifact?.proposedActionGraph
            ?? fallbackActionGraph,
        revisedVerifyCommands: recipeProposalArtifact?.proposedVerifyCommands
            ?? planningArtifact?.proposedVerifyCommands
            ?? fallbackVerifyCommands
    )
}

private func xtAutomationRuntimeLineage(
    from row: [String: Any]?,
    artifactLineage: XTAutomationRunLineage?,
    fallbackRunID: String
) -> XTAutomationRunLineage {
    if let artifactLineage {
        let merged = XTAutomationRunLineage(
            lineageID: xtAutomationRuntimeString(row?["lineage_id"]) ?? artifactLineage.lineageID,
            rootRunID: xtAutomationRuntimeString(row?["root_run_id"]) ?? artifactLineage.rootRunID,
            parentRunID: xtAutomationRuntimeString(row?["parent_run_id"]) ?? artifactLineage.parentRunID,
            retryDepth: xtAutomationRuntimeIntOptional(row?["retry_depth"]) ?? artifactLineage.retryDepth
        )
        return xtAutomationResolvedLineage(merged, fallbackRunID: fallbackRunID)
    }

    let lineage = XTAutomationRunLineage(
        lineageID: xtAutomationRuntimeString(row?["lineage_id"]) ?? "",
        rootRunID: xtAutomationRuntimeString(row?["root_run_id"]) ?? "",
        parentRunID: xtAutomationRuntimeString(row?["parent_run_id"]) ?? "",
        retryDepth: xtAutomationRuntimeIntOptional(row?["retry_depth"]) ?? 0
    )
    return xtAutomationResolvedLineage(lineage, fallbackRunID: fallbackRunID)
}

private func automationRuntimeRetryDepthFallback(from package: XTAutomationRetryPackage) -> Int {
    if let retryDepth = package.lineage?.retryDepth,
       retryDepth > 0 {
        return retryDepth
    }
    for ref in package.additionalEvidenceRefs where ref.hasPrefix("retry://depth/") {
        if let token = ref.split(separator: "/").last,
           let depth = Int(token) {
            return max(1, depth)
        }
    }
    return 1
}

private func xtAutomationRuntimeVerificationReport(from value: Any?) -> XTAutomationVerificationReport? {
    guard let object = value as? [String: Any] else { return nil }
    let commandRows = object["command_results"] as? [Any] ?? []
    let commandResults = commandRows.compactMap { item -> XTAutomationVerificationCommandOutcome? in
        guard let row = item as? [String: Any] else { return nil }
        return XTAutomationVerificationCommandOutcome(
            commandID: xtAutomationRuntimeString(row["command_id"]) ?? "",
            command: xtAutomationRuntimeString(row["command"]) ?? "",
            ok: xtAutomationRuntimeBool(row["ok"]),
            detail: xtAutomationRuntimeString(row["detail"]) ?? ""
        )
    }

    return XTAutomationVerificationReport(
        required: xtAutomationRuntimeBool(object["required"]),
        executed: xtAutomationRuntimeBool(object["executed"]),
        commandCount: xtAutomationRuntimeInt(object["command_count"], fallback: commandResults.count),
        passedCommandCount: xtAutomationRuntimeInt(
            object["passed_command_count"],
            fallback: commandResults.filter(\.ok).count
        ),
        holdReason: xtAutomationRuntimeString(object["hold_reason"]) ?? "",
        detail: xtAutomationRuntimeString(object["detail"]) ?? "",
        commandResults: commandResults
    )
}

private func xtAutomationRuntimeWorkspaceDiffReport(from value: Any?) -> XTAutomationWorkspaceDiffReport? {
    guard let object = value as? [String: Any] else { return nil }
    return XTAutomationWorkspaceDiffReport(
        attempted: xtAutomationRuntimeBool(object["attempted"]),
        captured: xtAutomationRuntimeBool(object["captured"]),
        fileCount: xtAutomationRuntimeInt(object["file_count"], fallback: 0),
        diffChars: xtAutomationRuntimeInt(object["diff_chars"], fallback: 0),
        detail: xtAutomationRuntimeString(object["detail"]) ?? "",
        excerpt: xtAutomationRuntimeString(object["excerpt"]) ?? ""
    )
}

private func xtAutomationRuntimeState(_ value: Any?) -> XTAutomationRunState? {
    guard let rawValue = xtAutomationRuntimeString(value) else { return nil }
    return XTAutomationRunState(rawValue: rawValue)
}

private func xtAutomationRuntimeString(_ value: Any?) -> String? {
    if value is NSNull { return nil }
    if let stringValue = value as? String {
        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    return nil
}

private func xtAutomationRuntimeStringArray(_ value: Any?) -> [String] {
    guard let array = value as? [Any] else { return [] }
    return array.compactMap { xtAutomationRuntimeString($0) }
}

private func xtAutomationRuntimeOrderedUniqueStrings(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
        ordered.append(trimmed)
    }
    return ordered
}

private func xtAutomationRuntimeInt(_ value: Any?, fallback: Int) -> Int {
    if let intValue = value as? Int {
        return intValue
    }
    if let doubleValue = value as? Double {
        return Int(doubleValue)
    }
    if let stringValue = value as? String,
       let intValue = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return intValue
    }
    return fallback
}

private func xtAutomationRuntimeIntOptional(_ value: Any?) -> Int? {
    if value is NSNull { return nil }
    if let intValue = value as? Int {
        return intValue
    }
    if let doubleValue = value as? Double {
        return Int(doubleValue)
    }
    if let stringValue = value as? String,
       let intValue = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return intValue
    }
    return nil
}

private func xtAutomationRuntimeDouble(_ value: Any?) -> TimeInterval {
    if let doubleValue = value as? Double {
        return doubleValue
    }
    if let intValue = value as? Int {
        return TimeInterval(intValue)
    }
    if let stringValue = value as? String,
       let doubleValue = Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return doubleValue
    }
    return Date().timeIntervalSince1970
}

private func xtAutomationRuntimeBool(_ value: Any?) -> Bool {
    if let boolValue = value as? Bool {
        return boolValue
    }
    if let intValue = value as? Int {
        return intValue != 0
    }
    if let stringValue = value as? String {
        return ["1", "true", "yes"].contains(stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
    return false
}
