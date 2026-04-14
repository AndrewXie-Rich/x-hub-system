import Foundation

struct XTAutomationActionExecutionOutcome: Codable, Equatable, Identifiable, Sendable {
    var actionID: String
    var title: String
    var tool: ToolName
    var ok: Bool
    var denyCode: String
    var detail: String
    var expectationMet: Bool
    var continuedAfterFailure: Bool

    var id: String { actionID }
}

struct XTAutomationVerificationCommandOutcome: Codable, Equatable, Identifiable, Sendable {
    var commandID: String
    var command: String
    var ok: Bool
    var detail: String

    var id: String { commandID }
}

struct XTAutomationVerificationContract: Codable, Equatable, Sendable {
    var expectedState: String
    var verifyMethod: String
    var retryPolicy: String
    var holdPolicy: String
    var evidenceRequired: Bool
    var triggerActionIDs: [String]
    var verifyCommands: [String]

    enum CodingKeys: String, CodingKey {
        case expectedState = "expected_state"
        case verifyMethod = "verify_method"
        case retryPolicy = "retry_policy"
        case holdPolicy = "hold_policy"
        case evidenceRequired = "evidence_required"
        case triggerActionIDs = "trigger_action_ids"
        case verifyCommands = "verify_commands"
    }

    init(
        expectedState: String,
        verifyMethod: String,
        retryPolicy: String,
        holdPolicy: String,
        evidenceRequired: Bool,
        triggerActionIDs: [String],
        verifyCommands: [String]
    ) {
        self.expectedState = expectedState
        self.verifyMethod = verifyMethod
        self.retryPolicy = retryPolicy
        self.holdPolicy = holdPolicy
        self.evidenceRequired = evidenceRequired
        self.triggerActionIDs = triggerActionIDs
        self.verifyCommands = verifyCommands
    }
}

struct XTAutomationVerificationReport: Codable, Equatable, Sendable {
    var required: Bool
    var executed: Bool
    var commandCount: Int
    var passedCommandCount: Int
    var holdReason: String
    var detail: String
    var commandResults: [XTAutomationVerificationCommandOutcome]
    var contract: XTAutomationVerificationContract? = nil

    init(
        required: Bool,
        executed: Bool,
        commandCount: Int,
        passedCommandCount: Int,
        holdReason: String,
        detail: String,
        commandResults: [XTAutomationVerificationCommandOutcome],
        contract: XTAutomationVerificationContract? = nil
    ) {
        self.required = required
        self.executed = executed
        self.commandCount = commandCount
        self.passedCommandCount = passedCommandCount
        self.holdReason = holdReason
        self.detail = detail
        self.commandResults = commandResults
        self.contract = contract
    }

    var ok: Bool {
        guard required else { return true }
        return executed && holdReason.isEmpty && passedCommandCount == commandCount
    }
}

struct XTAutomationWorkspaceDiffReport: Codable, Equatable, Sendable {
    var attempted: Bool
    var captured: Bool
    var fileCount: Int
    var diffChars: Int
    var detail: String
    var excerpt: String
}

struct XTAutomationRunHandoffArtifact: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.automation_run_handoff.v1"

    var schemaVersion: String
    var generatedAt: TimeInterval
    var runID: String
    var lineage: XTAutomationRunLineage?
    var recipeRef: String
    var deliveryRef: String? = nil
    var finalState: XTAutomationRunState
    var holdReason: String
    var detail: String
    var actionResults: [XTAutomationActionExecutionOutcome]
    var verificationReport: XTAutomationVerificationReport?
    var workspaceDiffReport: XTAutomationWorkspaceDiffReport?
    var suggestedNextActions: [String]
    var structuredBlocker: XTAutomationBlockerDescriptor? = nil
    var currentStepID: String? = nil
    var currentStepTitle: String? = nil
    var currentStepState: XTAutomationRunStepState? = nil
    var currentStepSummary: String? = nil
}

struct XTAutomationRunExecutionReport: Equatable, Sendable {
    var runID: String
    var lineage: XTAutomationRunLineage? = nil
    var recipeRef: String
    var deliveryRef: String? = nil
    var totalActionCount: Int
    var executedActionCount: Int
    var succeededActionCount: Int
    var finalState: XTAutomationRunState
    var holdReason: String
    var detail: String
    var actionResults: [XTAutomationActionExecutionOutcome]
    var verificationReport: XTAutomationVerificationReport?
    var workspaceDiffReport: XTAutomationWorkspaceDiffReport?
    var handoffArtifactPath: String?
    var auditRef: String
    var structuredBlocker: XTAutomationBlockerDescriptor? = nil
    var currentStepID: String? = nil
    var currentStepTitle: String? = nil
    var currentStepState: XTAutomationRunStepState? = nil
    var currentStepSummary: String? = nil
}

private struct XTAutomationStepContextSnapshot: Equatable, Sendable {
    var stepID: String?
    var stepTitle: String?
    var stepState: XTAutomationRunStepState?
    var stepSummary: String?
}

final class XTAutomationRunExecutor {
    typealias ToolRunner = @Sendable (ToolCall, URL) async throws -> ToolResult

    private let toolRunner: ToolRunner

    init(toolRunner: @escaping ToolRunner = { call, root in
        try await ToolExecutor.execute(call: call, projectRoot: root)
    }) {
        self.toolRunner = toolRunner
    }

    func execute(
        runID: String,
        recipe: AXAutomationRecipeRuntimeBinding,
        ctx: AXProjectContext,
        lineage: XTAutomationRunLineage? = nil,
        verifyCommandsOverride: [String]? = nil,
        verificationContractOverride: XTAutomationVerificationContract? = nil,
        now: Date = Date()
    ) async -> XTAutomationRunExecutionReport {
        let auditRef = "audit-xt-auto-exec-\(xtAutomationActionToken(runID, fallback: "run"))-\(Int(now.timeIntervalSince1970))"
        let actions = recipe.actionGraph
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
        let resolvedLineage = xtAutomationResolvedLineage(lineage, fallbackRunID: runID)
        let deliveryRef = xtAutomationPersistedRunDeliveryRef(for: runID, ctx: ctx)

        let startRow: [String: Any] = [
            "type": "automation_execution",
            "phase": "started",
            "created_at": now.timeIntervalSince1970,
            "run_id": runID,
            "lineage_id": resolvedLineage.lineageID,
            "root_run_id": resolvedLineage.rootRunID,
            "parent_run_id": resolvedLineage.parentRunID.isEmpty ? NSNull() : resolvedLineage.parentRunID,
            "retry_depth": resolvedLineage.retryDepth,
            "recipe_ref": recipe.ref,
            "action_count": actions.count,
            "audit_ref": auditRef,
        ]
        AXProjectStore.appendRawLog(startRow, for: ctx)

        guard !actions.isEmpty else {
            return finalize(
                report: XTAutomationRunExecutionReport(
                    runID: runID,
                    lineage: resolvedLineage,
                    recipeRef: recipe.ref,
                    deliveryRef: deliveryRef,
                    totalActionCount: 0,
                    executedActionCount: 0,
                    succeededActionCount: 0,
                    finalState: .blocked,
                    holdReason: "recipe_action_graph_missing",
                    detail: "automation action graph is empty",
                    actionResults: [],
                    verificationReport: nil,
                    workspaceDiffReport: nil,
                    handoffArtifactPath: nil,
                    auditRef: auditRef,
                    currentStepSummary: "automation action graph is empty"
                ),
                ctx: ctx,
                createdAt: now
            )
        }

        var outcomes: [XTAutomationActionExecutionOutcome] = []
        var hadSuccessfulMutation = false

        for (index, action) in actions.enumerated() {
            if Task.isCancelled {
                let stepContext = xtAutomationActionStepContext(
                    action: action,
                    state: .blocked,
                    summary: "automation execution task cancelled"
                )
                let report = XTAutomationRunExecutionReport(
                    runID: runID,
                    lineage: resolvedLineage,
                    recipeRef: recipe.ref,
                    deliveryRef: deliveryRef,
                    totalActionCount: actions.count,
                    executedActionCount: outcomes.count,
                    succeededActionCount: outcomes.filter(\.ok).count,
                    finalState: .blocked,
                    holdReason: "automation_execution_cancelled",
                    detail: "automation execution task cancelled",
                    actionResults: outcomes,
                    verificationReport: nil,
                    workspaceDiffReport: nil,
                    handoffArtifactPath: nil,
                    auditRef: auditRef,
                    currentStepID: stepContext.stepID,
                    currentStepTitle: stepContext.stepTitle,
                    currentStepState: stepContext.stepState,
                    currentStepSummary: stepContext.stepSummary
                )
                return finalize(report: report, ctx: ctx, createdAt: Date())
            }

            let preflightFailure = await executeActionPreflightIfNeeded(
                runID: runID,
                recipe: recipe,
                action: action,
                actionIndex: index,
                config: config,
                ctx: ctx,
                now: now,
                auditRef: auditRef
            )
            if let preflightFailure {
                outcomes.append(preflightFailure)
                if !action.continueOnFailure {
                    let stepContext = xtAutomationActionStepContext(
                        action: action,
                        state: .blocked,
                        summary: preflightFailure.detail
                    )
                    let preflightHoldReason = preflightFailure.denyCode.trimmingCharacters(in: .whitespacesAndNewlines)
                    let preflightDetail: String
                    if preflightHoldReason == "automation_patch_check_failed" {
                        preflightDetail = "patch_check_failed:\(action.actionID)"
                    } else {
                        preflightDetail = "preflight_failed:\(action.actionID)"
                    }
                    let report = XTAutomationRunExecutionReport(
                        runID: runID,
                        lineage: resolvedLineage,
                        recipeRef: recipe.ref,
                        deliveryRef: deliveryRef,
                        totalActionCount: actions.count,
                        executedActionCount: outcomes.count,
                        succeededActionCount: outcomes.filter(\.ok).count,
                        finalState: .blocked,
                        holdReason: preflightHoldReason.isEmpty
                            ? "automation_action_preflight_failed"
                            : preflightHoldReason,
                        detail: preflightDetail,
                        actionResults: outcomes,
                        verificationReport: nil,
                        workspaceDiffReport: nil,
                        handoffArtifactPath: nil,
                        auditRef: auditRef,
                        currentStepID: stepContext.stepID,
                        currentStepTitle: stepContext.stepTitle,
                        currentStepState: stepContext.stepState,
                        currentStepSummary: stepContext.stepSummary
                    )
                    return finalize(report: report, ctx: ctx, createdAt: Date())
                }
                continue
            }

            let call = ToolCall(
                id: "xt_auto_\(runID)_\(action.actionID)",
                tool: action.tool,
                args: action.args
            )

            do {
                let result = try await toolRunner(call, ctx.root)
                let parsed = ToolExecutor.parseStructuredToolOutput(result.output)
                let summaryObject = xtAutomationJSONObject(parsed.summary)
                let body = xtAutomationTrimmedBody(parsed.body.isEmpty ? result.output : parsed.body)
                let expectationMet = action.successBodyContains.isEmpty
                    || body.localizedCaseInsensitiveContains(action.successBodyContains)
                let denyCode = xtAutomationJSONString(summaryObject?["deny_code"]) ?? ""
                let ok = result.ok && expectationMet
                let detail = xtAutomationActionDetail(
                    result: result,
                    body: body,
                    denyCode: denyCode,
                    expectationToken: action.successBodyContains,
                    ok: ok
                )
                let outcome = XTAutomationActionExecutionOutcome(
                    actionID: action.actionID,
                    title: action.title,
                    tool: action.tool,
                    ok: ok,
                    denyCode: denyCode,
                    detail: detail,
                    expectationMet: expectationMet,
                    continuedAfterFailure: !ok && action.continueOnFailure
                )
                outcomes.append(outcome)
                if ok && xtAutomationMutationTools.contains(action.tool) {
                    hadSuccessfulMutation = true
                }

                AXProjectStore.appendRawLog(
                    [
                        "type": "automation_action",
                        "created_at": Date().timeIntervalSince1970,
                        "run_id": runID,
                        "recipe_ref": recipe.ref,
                        "action_id": action.actionID,
                        "index": index + 1,
                        "title": action.title,
                        "tool": action.tool.rawValue,
                        "ok": ok,
                        "continue_on_failure": action.continueOnFailure,
                        "deny_code": denyCode,
                        "expectation_met": expectationMet,
                        "summary": xtAutomationFoundationValue(parsed.summary) ?? NSNull(),
                        "detail": xtAutomationTruncate(detail, maxChars: 800),
                        "audit_ref": auditRef,
                    ],
                    for: ctx
                )

                if !ok && !action.continueOnFailure {
                    let stepContext = xtAutomationActionStepContext(
                        action: action,
                        state: .blocked,
                        summary: detail
                    )
                    let report = XTAutomationRunExecutionReport(
                        runID: runID,
                        lineage: resolvedLineage,
                        recipeRef: recipe.ref,
                        deliveryRef: deliveryRef,
                        totalActionCount: actions.count,
                        executedActionCount: outcomes.count,
                        succeededActionCount: outcomes.filter(\.ok).count,
                        finalState: .blocked,
                        holdReason: denyCode.isEmpty ? "automation_action_failed" : denyCode,
                        detail: "action_failed:\(action.actionID)",
                        actionResults: outcomes,
                        verificationReport: nil,
                        workspaceDiffReport: nil,
                        handoffArtifactPath: nil,
                        auditRef: auditRef,
                        currentStepID: stepContext.stepID,
                        currentStepTitle: stepContext.stepTitle,
                        currentStepState: stepContext.stepState,
                        currentStepSummary: stepContext.stepSummary
                    )
                    return finalize(report: report, ctx: ctx, createdAt: Date())
                }
            } catch {
                let detail = xtAutomationTruncate(error.localizedDescription, maxChars: 240)
                let outcome = XTAutomationActionExecutionOutcome(
                    actionID: action.actionID,
                    title: action.title,
                    tool: action.tool,
                    ok: false,
                    denyCode: "",
                    detail: detail,
                    expectationMet: false,
                    continuedAfterFailure: action.continueOnFailure
                )
                outcomes.append(outcome)
                AXProjectStore.appendRawLog(
                    [
                        "type": "automation_action",
                        "created_at": Date().timeIntervalSince1970,
                        "run_id": runID,
                        "recipe_ref": recipe.ref,
                        "action_id": action.actionID,
                        "index": index + 1,
                        "title": action.title,
                        "tool": action.tool.rawValue,
                        "ok": false,
                        "continue_on_failure": action.continueOnFailure,
                        "deny_code": "",
                        "detail": detail,
                        "audit_ref": auditRef,
                    ],
                    for: ctx
                )

                if !action.continueOnFailure {
                    let stepContext = xtAutomationActionStepContext(
                        action: action,
                        state: .blocked,
                        summary: detail
                    )
                    let report = XTAutomationRunExecutionReport(
                        runID: runID,
                        lineage: resolvedLineage,
                        recipeRef: recipe.ref,
                        deliveryRef: deliveryRef,
                        totalActionCount: actions.count,
                        executedActionCount: outcomes.count,
                        succeededActionCount: outcomes.filter(\.ok).count,
                        finalState: .blocked,
                        holdReason: "automation_action_execution_error",
                        detail: "action_error:\(action.actionID)",
                        actionResults: outcomes,
                        verificationReport: nil,
                        workspaceDiffReport: nil,
                        handoffArtifactPath: nil,
                        auditRef: auditRef,
                        currentStepID: stepContext.stepID,
                        currentStepTitle: stepContext.stepTitle,
                        currentStepState: stepContext.stepState,
                        currentStepSummary: stepContext.stepSummary
                    )
                    return finalize(report: report, ctx: ctx, createdAt: Date())
                }
            }
        }

        let workspaceDiffReport = await captureWorkspaceDiffIfNeeded(
            runID: runID,
            recipe: recipe,
            ctx: ctx,
            didMutateWorkspace: hadSuccessfulMutation,
            auditRef: auditRef
        )
        let verificationReport = await executeProjectVerificationIfNeeded(
            runID: runID,
            recipe: recipe,
            ctx: ctx,
            config: config,
            actions: actions,
            actionOutcomes: outcomes,
            verifyCommandsOverride: verifyCommandsOverride,
            verificationContractOverride: verificationContractOverride,
            now: now,
            auditRef: auditRef
        )
        if let verificationReport, !verificationReport.ok {
            let stepContext = xtAutomationVerificationStepContext(
                report: verificationReport,
                state: .blocked
            )
            let report = XTAutomationRunExecutionReport(
                runID: runID,
                lineage: resolvedLineage,
                recipeRef: recipe.ref,
                deliveryRef: deliveryRef,
                totalActionCount: actions.count,
                executedActionCount: outcomes.count,
                succeededActionCount: outcomes.filter(\.ok).count,
                finalState: .blocked,
                holdReason: verificationReport.holdReason.isEmpty ? "automation_verification_failed" : verificationReport.holdReason,
                detail: verificationReport.detail,
                actionResults: outcomes,
                verificationReport: verificationReport,
                workspaceDiffReport: workspaceDiffReport,
                handoffArtifactPath: nil,
                auditRef: auditRef,
                currentStepID: stepContext.stepID,
                currentStepTitle: stepContext.stepTitle,
                currentStepState: stepContext.stepState,
                currentStepSummary: stepContext.stepSummary
            )
            return finalize(report: report, ctx: ctx, createdAt: Date())
        }

        let succeeded = outcomes.filter(\.ok).count
        let allOK = succeeded == actions.count
        let executionDetail = xtAutomationExecutionDetail(
            actionCount: outcomes.count,
            totalActionCount: actions.count,
            hadFailures: !allOK,
            verificationReport: verificationReport,
            workspaceDiffReport: workspaceDiffReport
        )
        let finalStepContext = xtAutomationCompletionStepContext(
            actions: actions,
            outcomes: outcomes,
            verificationReport: verificationReport,
            finalState: allOK ? .delivered : .blocked,
            detail: executionDetail
        )
        let report = XTAutomationRunExecutionReport(
            runID: runID,
            lineage: resolvedLineage,
            recipeRef: recipe.ref,
            deliveryRef: deliveryRef,
            totalActionCount: actions.count,
            executedActionCount: outcomes.count,
            succeededActionCount: succeeded,
            finalState: allOK ? .delivered : .blocked,
            holdReason: allOK ? "" : "automation_action_graph_completed_with_failures",
            detail: executionDetail,
            actionResults: outcomes,
            verificationReport: verificationReport,
            workspaceDiffReport: workspaceDiffReport,
            handoffArtifactPath: nil,
            auditRef: auditRef,
            currentStepID: finalStepContext.stepID,
            currentStepTitle: finalStepContext.stepTitle,
            currentStepState: finalStepContext.stepState,
            currentStepSummary: finalStepContext.stepSummary
        )
        return finalize(report: report, ctx: ctx, createdAt: Date())
    }

    private func executeActionPreflightIfNeeded(
        runID: String,
        recipe: AXAutomationRecipeRuntimeBinding,
        action: XTAutomationRecipeAction,
        actionIndex: Int,
        config: AXProjectConfig,
        ctx: AXProjectContext,
        now: Date,
        auditRef: String
    ) async -> XTAutomationActionExecutionOutcome? {
        let policyDecision = await xtAutomationRuntimePolicyDecision(
            recipe: recipe,
            action: action,
            config: config,
            projectRoot: ctx.root,
            now: now
        )
        if !policyDecision.allowed {
            let outcome = XTAutomationActionExecutionOutcome(
                actionID: action.actionID,
                title: action.title,
                tool: action.tool,
                ok: false,
                denyCode: policyDecision.denyCode,
                detail: policyDecision.detail,
                expectationMet: false,
                continuedAfterFailure: action.continueOnFailure
            )
            logActionPreflight(
                runID: runID,
                recipeRef: recipe.ref,
                action: action,
                actionIndex: actionIndex,
                preflightTool: policyDecision.preflightTool,
                ok: false,
                detail: policyDecision.detail,
                denyCode: policyDecision.denyCode,
                policySource: policyDecision.policySource,
                policyReason: policyDecision.policyReason,
                ctx: ctx,
                auditRef: auditRef
            )
            return outcome
        }

        guard action.tool == .git_apply else { return nil }

        let call = ToolCall(
            id: "xt_auto_preflight_\(runID)_\(action.actionID)",
            tool: .git_apply_check,
            args: action.args
        )

        do {
            let result = try await toolRunner(call, ctx.root)
            let parsed = ToolExecutor.parseStructuredToolOutput(result.output)
            let body = xtAutomationTrimmedBody(parsed.body.isEmpty ? result.output : parsed.body)
            logActionPreflight(
                runID: runID,
                recipeRef: recipe.ref,
                action: action,
                actionIndex: actionIndex,
                preflightTool: ToolName.git_apply_check.rawValue,
                ok: result.ok,
                detail: body.isEmpty ? "ok" : body,
                denyCode: result.ok ? "" : "automation_patch_check_failed",
                policySource: "git_apply_check",
                policyReason: result.ok ? "patch_validation_passed" : "patch_validation_failed",
                ctx: ctx,
                auditRef: auditRef
            )
            guard !result.ok else { return nil }
            return XTAutomationActionExecutionOutcome(
                actionID: action.actionID,
                title: action.title,
                tool: action.tool,
                ok: false,
                denyCode: "automation_patch_check_failed",
                detail: body.isEmpty ? "patch_check_failed" : xtAutomationTruncate(body, maxChars: 240),
                expectationMet: false,
                continuedAfterFailure: action.continueOnFailure
            )
        } catch {
            let detail = xtAutomationTruncate(error.localizedDescription, maxChars: 240)
            logActionPreflight(
                runID: runID,
                recipeRef: recipe.ref,
                action: action,
                actionIndex: actionIndex,
                preflightTool: ToolName.git_apply_check.rawValue,
                ok: false,
                detail: detail,
                denyCode: "automation_patch_check_failed",
                policySource: "git_apply_check",
                policyReason: "patch_validation_error",
                ctx: ctx,
                auditRef: auditRef
            )
            return XTAutomationActionExecutionOutcome(
                actionID: action.actionID,
                title: action.title,
                tool: action.tool,
                ok: false,
                denyCode: "automation_patch_check_failed",
                detail: detail,
                expectationMet: false,
                continuedAfterFailure: action.continueOnFailure
            )
        }
    }

    private func logActionPreflight(
        runID: String,
        recipeRef: String,
        action: XTAutomationRecipeAction,
        actionIndex: Int,
        preflightTool: String,
        ok: Bool,
        detail: String,
        denyCode: String = "",
        policySource: String = "",
        policyReason: String = "",
        ctx: AXProjectContext,
        auditRef: String
    ) {
        AXProjectStore.appendRawLog(
            [
                "type": "automation_action_preflight",
                "created_at": Date().timeIntervalSince1970,
                "run_id": runID,
                "recipe_ref": recipeRef,
                "action_id": action.actionID,
                "index": actionIndex + 1,
                "tool": action.tool.rawValue,
                "preflight_tool": preflightTool,
                "ok": ok,
                "deny_code": denyCode,
                "policy_source": policySource,
                "policy_reason": policyReason,
                "detail": xtAutomationTruncate(detail.isEmpty ? "ok" : detail, maxChars: 800),
                "audit_ref": auditRef,
            ],
            for: ctx
        )
    }

    private func executeProjectVerificationIfNeeded(
        runID: String,
        recipe: AXAutomationRecipeRuntimeBinding,
        ctx: AXProjectContext,
        config: AXProjectConfig,
        actions: [XTAutomationRecipeAction],
        actionOutcomes: [XTAutomationActionExecutionOutcome],
        verifyCommandsOverride: [String]?,
        verificationContractOverride: XTAutomationVerificationContract?,
        now: Date,
        auditRef: String
    ) async -> XTAutomationVerificationReport? {
        let successfulActionIDs = Set(actionOutcomes.filter(\.ok).map(\.actionID))
        let verifyTriggers = actions.filter { action in
            successfulActionIDs.contains(action.actionID)
                && action.effectiveRequiresVerification(projectVerifyAfterChanges: config.verifyAfterChanges)
        }
        guard !verifyTriggers.isEmpty else { return nil }

        let configuredCommands = AXProjectStackDetector
            .filterApplicableVerifyCommands(
                verifyCommandsOverride?.isEmpty == false ? verifyCommandsOverride! : config.verifyCommands,
                forProjectRoot: ctx.root
            )
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let verificationContracts = verifyTriggers.compactMap { action in
            action.resolvedVerificationContract(
                projectVerifyAfterChanges: config.verifyAfterChanges,
                projectVerifyCommands: configuredCommands,
                verifyCommandsOverrideUsed: verifyCommandsOverride?.isEmpty == false,
                automationSelfIterateEnabled: config.automationSelfIterateEnabled
            )
        }
        guard !verificationContracts.isEmpty else { return nil }

        let mergedVerificationContract = xtAutomationResolvedVerificationContract(
            primary: verificationContractOverride,
            fallback: xtAutomationMergedVerificationContract(verificationContracts)
        )
        let commands = AXProjectStackDetector
            .filterApplicableVerifyCommands(mergedVerificationContract.verifyCommands, forProjectRoot: ctx.root)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let verificationContract = XTAutomationVerificationContract(
            expectedState: mergedVerificationContract.expectedState,
            verifyMethod: xtAutomationVerificationMethodAdjustedForResolvedCommands(
                mergedVerificationContract.verifyMethod,
                commands: commands
            ),
            retryPolicy: mergedVerificationContract.retryPolicy,
            holdPolicy: mergedVerificationContract.holdPolicy,
            evidenceRequired: mergedVerificationContract.evidenceRequired,
            triggerActionIDs: mergedVerificationContract.triggerActionIDs,
            verifyCommands: commands
        )

        AXProjectStore.appendRawLog(
            [
                "type": "automation_verification",
                "phase": "started",
                "created_at": Date().timeIntervalSince1970,
                "run_id": runID,
                "recipe_ref": recipe.ref,
                "trigger_action_ids": verificationContract.triggerActionIDs,
                "command_count": commands.count,
                "verification_contract": xtAutomationVerificationContractFoundationValue(verificationContract),
                "audit_ref": auditRef,
            ],
            for: ctx
        )

        guard !commands.isEmpty else {
            let report = XTAutomationVerificationReport(
                required: true,
                executed: false,
                commandCount: 0,
                passedCommandCount: 0,
                holdReason: "automation_verify_commands_missing",
                detail: "verification required but no verify commands are configured",
                commandResults: [],
                contract: verificationContract
            )
            logVerificationCompletion(runID: runID, recipeRef: recipe.ref, report: report, ctx: ctx, auditRef: auditRef)
            return report
        }

        var outcomes: [XTAutomationVerificationCommandOutcome] = []
        for (index, command) in commands.enumerated() {
            if Task.isCancelled {
                let report = XTAutomationVerificationReport(
                    required: true,
                    executed: true,
                    commandCount: commands.count,
                    passedCommandCount: outcomes.filter(\.ok).count,
                    holdReason: "automation_verification_cancelled",
                    detail: "verification cancelled",
                    commandResults: outcomes,
                    contract: verificationContract
                )
                logVerificationCompletion(runID: runID, recipeRef: recipe.ref, report: report, ctx: ctx, auditRef: auditRef)
                return report
            }

            let verificationAction = XTAutomationRecipeAction(
                actionID: "verify_\(index + 1)",
                title: "校验命令 \(index + 1)",
                tool: .run_command,
                args: [
                    "command": .string(command),
                    "timeout_sec": .number(300),
                ]
            )
            let policyDecision = await xtAutomationRuntimePolicyDecision(
                recipe: recipe,
                action: verificationAction,
                config: config,
                projectRoot: ctx.root,
                now: now
            )
            if !policyDecision.allowed {
                let detail = xtAutomationTruncate(
                    policyDecision.detail.isEmpty ? policyDecision.denyCode : policyDecision.detail,
                    maxChars: 240
                )
                let outcome = XTAutomationVerificationCommandOutcome(
                    commandID: "verify_\(index + 1)",
                    command: command,
                    ok: false,
                    detail: detail
                )
                outcomes.append(outcome)
                AXProjectStore.appendRawLog(
                    [
                        "type": "automation_verification_command",
                        "created_at": Date().timeIntervalSince1970,
                        "run_id": runID,
                        "recipe_ref": recipe.ref,
                        "index": index + 1,
                        "command": command,
                        "ok": false,
                        "deny_code": policyDecision.denyCode,
                        "policy_source": policyDecision.policySource,
                        "policy_reason": policyDecision.policyReason,
                        "detail": xtAutomationTruncate(detail, maxChars: 800),
                        "audit_ref": auditRef,
                    ],
                    for: ctx
                )
                let report = XTAutomationVerificationReport(
                    required: true,
                    executed: true,
                    commandCount: commands.count,
                    passedCommandCount: outcomes.filter(\.ok).count,
                    holdReason: policyDecision.denyCode.isEmpty
                        ? "automation_verify_preflight_failed"
                        : policyDecision.denyCode,
                    detail: "verify_preflight_failed:\(index + 1)/\(commands.count) \(command)",
                    commandResults: outcomes,
                    contract: verificationContract
                )
                logVerificationCompletion(runID: runID, recipeRef: recipe.ref, report: report, ctx: ctx, auditRef: auditRef)
                return report
            }

            let call = ToolCall(
                id: "xt_auto_verify_\(runID)_\(index + 1)",
                tool: .run_command,
                args: [
                    "command": .string(command),
                    "timeout_sec": .number(300),
                ]
            )

            do {
                let result = try await toolRunner(call, ctx.root)
                let parsed = ToolExecutor.parseStructuredToolOutput(result.output)
                let body = xtAutomationTrimmedBody(parsed.body.isEmpty ? result.output : parsed.body)
                let detail = xtAutomationTruncate(body.isEmpty ? "ok" : body, maxChars: 240)
                let outcome = XTAutomationVerificationCommandOutcome(
                    commandID: "verify_\(index + 1)",
                    command: command,
                    ok: result.ok,
                    detail: detail
                )
                outcomes.append(outcome)
                AXProjectStore.appendRawLog(
                    [
                        "type": "automation_verification_command",
                        "created_at": Date().timeIntervalSince1970,
                        "run_id": runID,
                        "recipe_ref": recipe.ref,
                        "index": index + 1,
                        "command": command,
                        "ok": result.ok,
                        "deny_code": "",
                        "detail": xtAutomationTruncate(detail, maxChars: 800),
                        "audit_ref": auditRef,
                    ],
                    for: ctx
                )

                if !result.ok {
                    let report = XTAutomationVerificationReport(
                        required: true,
                        executed: true,
                        commandCount: commands.count,
                        passedCommandCount: outcomes.filter(\.ok).count,
                        holdReason: "automation_verify_failed",
                        detail: "verify_failed:\(index + 1)/\(commands.count) \(command)",
                        commandResults: outcomes,
                        contract: verificationContract
                    )
                    logVerificationCompletion(runID: runID, recipeRef: recipe.ref, report: report, ctx: ctx, auditRef: auditRef)
                    return report
                }
            } catch {
                let detail = xtAutomationTruncate(error.localizedDescription, maxChars: 240)
                let outcome = XTAutomationVerificationCommandOutcome(
                    commandID: "verify_\(index + 1)",
                    command: command,
                    ok: false,
                    detail: detail
                )
                outcomes.append(outcome)
                AXProjectStore.appendRawLog(
                    [
                        "type": "automation_verification_command",
                        "created_at": Date().timeIntervalSince1970,
                        "run_id": runID,
                        "recipe_ref": recipe.ref,
                        "index": index + 1,
                        "command": command,
                        "ok": false,
                        "deny_code": "",
                        "detail": xtAutomationTruncate(detail, maxChars: 800),
                        "audit_ref": auditRef,
                    ],
                    for: ctx
                )
                let report = XTAutomationVerificationReport(
                    required: true,
                    executed: true,
                    commandCount: commands.count,
                    passedCommandCount: outcomes.filter(\.ok).count,
                    holdReason: "automation_verify_execution_error",
                    detail: "verify_error:\(index + 1)/\(commands.count) \(command)",
                    commandResults: outcomes,
                    contract: verificationContract
                )
                logVerificationCompletion(runID: runID, recipeRef: recipe.ref, report: report, ctx: ctx, auditRef: auditRef)
                return report
            }
        }

        let report = XTAutomationVerificationReport(
            required: true,
            executed: true,
            commandCount: commands.count,
            passedCommandCount: outcomes.count,
            holdReason: "",
            detail: "verify_passed:\(outcomes.count)/\(commands.count)",
            commandResults: outcomes,
            contract: verificationContract
        )
        logVerificationCompletion(runID: runID, recipeRef: recipe.ref, report: report, ctx: ctx, auditRef: auditRef)
        return report
    }

    private func captureWorkspaceDiffIfNeeded(
        runID: String,
        recipe: AXAutomationRecipeRuntimeBinding,
        ctx: AXProjectContext,
        didMutateWorkspace: Bool,
        auditRef: String
    ) async -> XTAutomationWorkspaceDiffReport? {
        guard didMutateWorkspace else { return nil }

        let call = ToolCall(
            id: "xt_auto_diff_\(runID)",
            tool: .git_diff,
            args: [:]
        )

        do {
            let result = try await toolRunner(call, ctx.root)
            let parsed = ToolExecutor.parseStructuredToolOutput(result.output)
            let body = xtAutomationTrimmedBody(parsed.body.isEmpty ? result.output : parsed.body)
            let normalizedBody = body == "(empty diff)" ? "" : body
            let fileCount = xtAutomationDiffFileCount(normalizedBody)
            let report = XTAutomationWorkspaceDiffReport(
                attempted: true,
                captured: result.ok,
                fileCount: fileCount,
                diffChars: normalizedBody.count,
                detail: result.ok
                    ? (normalizedBody.isEmpty ? "diff_empty" : "diff_captured:\(fileCount)_files")
                    : "git_diff_failed",
                excerpt: xtAutomationTruncate(normalizedBody, maxChars: 400)
            )
            AXProjectStore.appendRawLog(
                [
                    "type": "automation_workspace_diff",
                    "created_at": Date().timeIntervalSince1970,
                    "run_id": runID,
                    "recipe_ref": recipe.ref,
                    "ok": result.ok,
                    "file_count": fileCount,
                    "diff_chars": normalizedBody.count,
                    "detail": report.detail,
                    "excerpt": xtAutomationTruncate(report.excerpt, maxChars: 800),
                    "audit_ref": auditRef,
                ],
                for: ctx
            )
            return report
        } catch {
            let detail = xtAutomationTruncate(error.localizedDescription, maxChars: 240)
            let report = XTAutomationWorkspaceDiffReport(
                attempted: true,
                captured: false,
                fileCount: 0,
                diffChars: 0,
                detail: "git_diff_error",
                excerpt: detail
            )
            AXProjectStore.appendRawLog(
                [
                    "type": "automation_workspace_diff",
                    "created_at": Date().timeIntervalSince1970,
                    "run_id": runID,
                    "recipe_ref": recipe.ref,
                    "ok": false,
                    "file_count": 0,
                    "diff_chars": 0,
                    "detail": report.detail,
                    "excerpt": detail,
                    "audit_ref": auditRef,
                ],
                for: ctx
            )
            return report
        }
    }

    private func logVerificationCompletion(
        runID: String,
        recipeRef: String,
        report: XTAutomationVerificationReport,
        ctx: AXProjectContext,
        auditRef: String
    ) {
        AXProjectStore.appendRawLog(
            [
                "type": "automation_verification",
                "phase": "completed",
                "created_at": Date().timeIntervalSince1970,
                "run_id": runID,
                "recipe_ref": recipeRef,
                "required": report.required,
                "executed": report.executed,
                "command_count": report.commandCount,
                "passed_command_count": report.passedCommandCount,
                "hold_reason": report.holdReason,
                "detail": report.detail,
                "audit_ref": auditRef,
            ],
            for: ctx
        )
    }

    private func finalize(
        report: XTAutomationRunExecutionReport,
        ctx: AXProjectContext,
        createdAt: Date
    ) -> XTAutomationRunExecutionReport {
        var finalizedReport = report
        if finalizedReport.structuredBlocker == nil {
            finalizedReport.structuredBlocker = xtAutomationStructuredBlocker(
                finalState: finalizedReport.finalState,
                holdReason: finalizedReport.holdReason,
                detail: finalizedReport.detail,
                verificationReport: finalizedReport.verificationReport,
                currentStepID: finalizedReport.currentStepID,
                currentStepTitle: finalizedReport.currentStepTitle,
                currentStepState: finalizedReport.currentStepState,
                currentStepSummary: finalizedReport.currentStepSummary
            )
        }
        finalizedReport.handoffArtifactPath = persistHandoffArtifact(
            report: finalizedReport,
            ctx: ctx,
            createdAt: createdAt
        )
        let lineage = xtAutomationResolvedLineage(finalizedReport.lineage, fallbackRunID: finalizedReport.runID)
        let completionRow: [String: Any] = [
            "type": "automation_execution",
            "phase": "completed",
            "created_at": createdAt.timeIntervalSince1970,
            "run_id": finalizedReport.runID,
            "lineage_id": lineage.lineageID,
            "root_run_id": lineage.rootRunID,
            "parent_run_id": lineage.parentRunID.isEmpty ? NSNull() : lineage.parentRunID,
            "retry_depth": lineage.retryDepth,
            "recipe_ref": finalizedReport.recipeRef,
            "delivery_ref": finalizedReport.deliveryRef ?? NSNull(),
            "final_state": finalizedReport.finalState.rawValue,
            "hold_reason": finalizedReport.holdReason,
            "detail": finalizedReport.detail,
            "executed_action_count": finalizedReport.executedActionCount,
            "succeeded_action_count": finalizedReport.succeededActionCount,
            "total_action_count": finalizedReport.totalActionCount,
            "verification": finalizedReport.verificationReport.map(xtAutomationVerificationFoundationValue) ?? NSNull(),
            "workspace_diff": finalizedReport.workspaceDiffReport.map(xtAutomationWorkspaceDiffFoundationValue) ?? NSNull(),
            "handoff_artifact_path": finalizedReport.handoffArtifactPath ?? NSNull(),
            "blocker": finalizedReport.structuredBlocker.map(xtAutomationBlockerFoundationValue) ?? NSNull(),
            "blocker_code": finalizedReport.structuredBlocker?.code ?? NSNull(),
            "blocker_summary": finalizedReport.structuredBlocker?.summary ?? NSNull(),
            "blocker_stage": finalizedReport.structuredBlocker?.stage.rawValue ?? NSNull(),
            "blocker_next_safe_action": finalizedReport.structuredBlocker?.nextSafeAction ?? NSNull(),
            "blocker_retry_eligible": finalizedReport.structuredBlocker?.retryEligible ?? NSNull(),
            "current_step_id": finalizedReport.currentStepID ?? NSNull(),
            "current_step_title": finalizedReport.currentStepTitle ?? NSNull(),
            "current_step_state": finalizedReport.currentStepState?.rawValue ?? NSNull(),
            "current_step_summary": finalizedReport.currentStepSummary ?? NSNull(),
            "audit_ref": finalizedReport.auditRef,
        ]
        AXProjectStore.appendRawLog(completionRow, for: ctx)
        return finalizedReport
    }

    private func persistHandoffArtifact(
        report: XTAutomationRunExecutionReport,
        ctx: AXProjectContext,
        createdAt: Date
    ) -> String? {
        let relativePath = xtAutomationHandoffArtifactRelativePath(for: report.runID)
        let targetURL = ctx.root.appendingPathComponent(relativePath)
        let artifact = XTAutomationRunHandoffArtifact(
            schemaVersion: XTAutomationRunHandoffArtifact.currentSchemaVersion,
            generatedAt: createdAt.timeIntervalSince1970,
            runID: report.runID,
            lineage: report.lineage,
            recipeRef: report.recipeRef,
            deliveryRef: report.deliveryRef,
            finalState: report.finalState,
            holdReason: report.holdReason,
            detail: report.detail,
            actionResults: report.actionResults,
            verificationReport: report.verificationReport,
            workspaceDiffReport: report.workspaceDiffReport,
            suggestedNextActions: xtAutomationSuggestedNextActions(for: report),
            structuredBlocker: report.structuredBlocker,
            currentStepID: report.currentStepID,
            currentStepTitle: report.currentStepTitle,
            currentStepState: report.currentStepState,
            currentStepSummary: report.currentStepSummary
        )
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
}

private func xtAutomationActionStepContext(
    action: XTAutomationRecipeAction,
    state: XTAutomationRunStepState,
    summary: String
) -> XTAutomationStepContextSnapshot {
    XTAutomationStepContextSnapshot(
        stepID: xtAutomationNormalizedOptionalStepValue(action.actionID),
        stepTitle: xtAutomationResolvedStepTitle(action.title, fallback: action.actionID),
        stepState: state,
        stepSummary: xtAutomationNormalizedOptionalStepValue(summary)
    )
}

private func xtAutomationVerificationStepContext(
    report: XTAutomationVerificationReport,
    state: XTAutomationRunStepState
) -> XTAutomationStepContextSnapshot {
    XTAutomationStepContextSnapshot(
        stepID: "verification",
        stepTitle: "Run project verification",
        stepState: state,
        stepSummary: xtAutomationNormalizedOptionalStepValue(report.detail)
            ?? (report.ok ? "verification passed" : "verification blocked")
    )
}

private func xtAutomationCompletionStepContext(
    actions: [XTAutomationRecipeAction],
    outcomes: [XTAutomationActionExecutionOutcome],
    verificationReport: XTAutomationVerificationReport?,
    finalState: XTAutomationRunState,
    detail: String
) -> XTAutomationStepContextSnapshot {
    if let verificationReport {
        return xtAutomationVerificationStepContext(
            report: verificationReport,
            state: finalState == .delivered ? .done : .blocked
        )
    }

    if let failedOutcome = outcomes.last(where: { !$0.ok }),
       let action = actions.first(where: { $0.actionID == failedOutcome.actionID }) {
        return xtAutomationActionStepContext(
            action: action,
            state: .blocked,
            summary: failedOutcome.detail
        )
    }

    if let lastOutcome = outcomes.last,
       let action = actions.first(where: { $0.actionID == lastOutcome.actionID }) {
        return xtAutomationActionStepContext(
            action: action,
            state: finalState == .delivered ? .done : .blocked,
            summary: lastOutcome.detail
        )
    }

    return XTAutomationStepContextSnapshot(
        stepID: nil,
        stepTitle: nil,
        stepState: finalState == .delivered ? .done : .blocked,
        stepSummary: xtAutomationNormalizedOptionalStepValue(detail)
    )
}

private func xtAutomationResolvedStepTitle(_ rawTitle: String, fallback: String) -> String {
    let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedTitle.isEmpty {
        return trimmedTitle
    }
    return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func xtAutomationNormalizedOptionalStepValue(_ rawValue: String?) -> String? {
    let trimmed = (rawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func xtAutomationJSONObject(_ value: JSONValue?) -> [String: JSONValue]? {
    guard case .object(let object)? = value else { return nil }
    return object
}

private func xtAutomationJSONString(_ value: JSONValue?) -> String? {
    guard case .string(let string)? = value else { return nil }
    return string
}

private func xtAutomationFoundationValue(_ value: JSONValue?) -> Any? {
    guard let value else { return nil }
    switch value {
    case .string(let string):
        return string
    case .number(let number):
        return number
    case .bool(let bool):
        return bool
    case .object(let object):
        return object.reduce(into: [String: Any]()) { partial, item in
            partial[item.key] = xtAutomationFoundationValue(item.value) ?? NSNull()
        }
    case .array(let array):
        return array.map { xtAutomationFoundationValue($0) ?? NSNull() }
    case .null:
        return NSNull()
    }
}

private func xtAutomationTrimmedBody(_ body: String) -> String {
    body.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func xtAutomationTruncate(_ string: String, maxChars: Int) -> String {
    guard string.count > maxChars else { return string }
    return String(string.prefix(maxChars)) + "..."
}

private func xtAutomationFailureDetail(
    body: String,
    denyCode: String,
    expectationToken: String
) -> String {
    if !denyCode.isEmpty {
        return denyCode
    }
    if !expectationToken.isEmpty,
       !body.localizedCaseInsensitiveContains(expectationToken) {
        return "expected_body_missing:\(expectationToken)"
    }
    let trimmed = xtAutomationTrimmedBody(body)
    return trimmed.isEmpty ? "tool_failed" : xtAutomationTruncate(trimmed, maxChars: 240)
}

private func xtAutomationActionDetail(
    result: ToolResult,
    body: String,
    denyCode: String,
    expectationToken: String,
    ok: Bool
) -> String {
    if ok, let specialized = ToolResultHumanSummary.specializedSummary(for: result) {
        return xtAutomationTruncate(specialized, maxChars: 240)
    }
    if !ok, !expectationToken.isEmpty,
       !body.localizedCaseInsensitiveContains(expectationToken) {
        return "expected_body_missing:\(expectationToken)"
    }
    if !ok, let specialized = ToolResultHumanSummary.specializedSummary(for: result) {
        return xtAutomationTruncate(specialized, maxChars: 240)
    }
    if ok {
        return body.isEmpty ? "ok" : xtAutomationTruncate(body, maxChars: 240)
    }
    return xtAutomationFailureDetail(
        body: body,
        denyCode: denyCode,
        expectationToken: expectationToken
    )
}

private func xtAutomationExecutionDetail(
    actionCount: Int,
    totalActionCount: Int,
    hadFailures: Bool,
    verificationReport: XTAutomationVerificationReport?,
    workspaceDiffReport: XTAutomationWorkspaceDiffReport?
) -> String {
    let actionDetail = hadFailures
        ? "executed \(actionCount)/\(totalActionCount) actions with failures"
        : "executed \(actionCount)/\(totalActionCount) actions"
    let diffDetail: String? = {
        guard let workspaceDiffReport, workspaceDiffReport.attempted else { return nil }
        if workspaceDiffReport.captured {
            return workspaceDiffReport.fileCount > 0
                ? "diff \(workspaceDiffReport.fileCount) files"
                : "diff empty"
        }
        return workspaceDiffReport.detail
    }()
    let base = [actionDetail, diffDetail].compactMap { $0 }.joined(separator: "; ")
    guard let verificationReport, verificationReport.required else {
        return base
    }
    let verifyDetail = verificationReport.executed
        ? "verify \(verificationReport.passedCommandCount)/\(verificationReport.commandCount)"
        : "verify pending"
    return [base, verifyDetail].joined(separator: "; ")
}

private func xtAutomationMergedVerificationContract(
    _ contracts: [XTAutomationVerificationContract]
) -> XTAutomationVerificationContract {
    guard let first = contracts.first else {
        return XTAutomationVerificationContract(
            expectedState: "post_change_verification_passes",
            verifyMethod: "project_verify_commands_missing",
            retryPolicy: "manual_retry_or_replan",
            holdPolicy: "block_run_and_emit_structured_blocker",
            evidenceRequired: true,
            triggerActionIDs: [],
            verifyCommands: []
        )
    }

    let methods = xtAutomationNormalizedVerificationScalars(contracts.map(\.verifyMethod))
    let verifyCommands = xtAutomationNormalizedVerificationScalars(contracts.flatMap(\.verifyCommands))
    let hasProjectMethod = methods.contains(where: xtAutomationIsProjectVerificationMethod)
    let hasRecipeMethod = methods.contains(where: { !xtAutomationIsProjectVerificationMethod($0) })
    let verifyMethod: String = {
        if methods.count == 1, let only = methods.first {
            return xtAutomationVerificationMethodAdjustedForResolvedCommands(only, commands: verifyCommands)
        }
        if hasProjectMethod && hasRecipeMethod {
            return verifyCommands.isEmpty ? "mixed_verify_commands_missing" : "mixed_verify_commands"
        }
        if hasRecipeMethod {
            return verifyCommands.isEmpty ? "recipe_action_verify_commands_missing" : "recipe_action_verify_commands"
        }
        if let firstProjectMethod = methods.first(where: xtAutomationIsProjectVerificationMethod) {
            return xtAutomationVerificationMethodAdjustedForResolvedCommands(firstProjectMethod, commands: verifyCommands)
        }
        return verifyCommands.isEmpty ? "project_verify_commands_missing" : "project_verify_commands"
    }()
    let retryPolicy: String = {
        let policies = Set(xtAutomationNormalizedVerificationScalars(contracts.map(\.retryPolicy)))
        if policies.contains("manual_retry_or_replan") {
            return "manual_retry_or_replan"
        }
        if policies.contains("retry_failed_verify_commands_within_budget") {
            return "retry_failed_verify_commands_within_budget"
        }
        return xtAutomationNormalizedVerificationScalars(contracts.map(\.retryPolicy)).first ?? first.retryPolicy
    }()

    return XTAutomationVerificationContract(
        expectedState: xtAutomationNormalizedVerificationScalars(contracts.map(\.expectedState)).first ?? first.expectedState,
        verifyMethod: verifyMethod,
        retryPolicy: retryPolicy,
        holdPolicy: xtAutomationNormalizedVerificationScalars(contracts.map(\.holdPolicy)).first ?? first.holdPolicy,
        evidenceRequired: contracts.contains(where: \.evidenceRequired),
        triggerActionIDs: xtAutomationNormalizedVerificationScalars(contracts.flatMap(\.triggerActionIDs)),
        verifyCommands: verifyCommands
    )
}

private func xtAutomationResolvedVerificationContract(
    primary: XTAutomationVerificationContract?,
    fallback: XTAutomationVerificationContract
) -> XTAutomationVerificationContract {
    guard let primary else { return fallback }

    let expectedState = primary.expectedState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? fallback.expectedState
        : primary.expectedState
    let verifyMethod = primary.verifyMethod.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? fallback.verifyMethod
        : primary.verifyMethod
    let retryPolicy = primary.retryPolicy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? fallback.retryPolicy
        : primary.retryPolicy
    let holdPolicy = primary.holdPolicy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? fallback.holdPolicy
        : primary.holdPolicy
    let triggerActionIDs = primary.triggerActionIDs.isEmpty
        ? fallback.triggerActionIDs
        : xtAutomationNormalizedVerificationScalars(primary.triggerActionIDs)
    let verifyCommands = primary.verifyCommands.isEmpty
        ? fallback.verifyCommands
        : xtAutomationNormalizedVerificationScalars(primary.verifyCommands)

    return XTAutomationVerificationContract(
        expectedState: expectedState,
        verifyMethod: verifyMethod,
        retryPolicy: retryPolicy,
        holdPolicy: holdPolicy,
        evidenceRequired: primary.evidenceRequired,
        triggerActionIDs: triggerActionIDs,
        verifyCommands: verifyCommands
    )
}

private func xtAutomationVerificationMethodAdjustedForResolvedCommands(
    _ method: String,
    commands: [String]
) -> String {
    let normalized = method.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
        return commands.isEmpty ? "project_verify_commands_missing" : "project_verify_commands"
    }
    if xtAutomationIsProjectVerificationMethod(normalized) {
        let usesOverride = normalized.contains("override")
        return commands.isEmpty
            ? (usesOverride ? "project_verify_commands_override_missing" : "project_verify_commands_missing")
            : (usesOverride ? "project_verify_commands_override" : "project_verify_commands")
    }
    if normalized == "recipe_action_verify_commands" || normalized == "recipe_action_verify_commands_missing" {
        return commands.isEmpty ? "recipe_action_verify_commands_missing" : "recipe_action_verify_commands"
    }
    if normalized == "mixed_verify_commands" || normalized == "mixed_verify_commands_missing" {
        return commands.isEmpty ? "mixed_verify_commands_missing" : "mixed_verify_commands"
    }
    return normalized
}

private func xtAutomationIsProjectVerificationMethod(_ method: String) -> Bool {
    method.hasPrefix("project_verify_commands")
}

private func xtAutomationNormalizedVerificationScalars(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var normalized: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
        normalized.append(trimmed)
    }
    return normalized
}

private func xtAutomationVerificationContractFoundationValue(
    _ contract: XTAutomationVerificationContract
) -> [String: Any] {
    [
        "expected_state": contract.expectedState,
        "verify_method": contract.verifyMethod,
        "retry_policy": contract.retryPolicy,
        "hold_policy": contract.holdPolicy,
        "evidence_required": contract.evidenceRequired,
        "trigger_action_ids": contract.triggerActionIDs,
        "verify_commands": contract.verifyCommands,
    ]
}

private func xtAutomationVerificationFoundationValue(_ report: XTAutomationVerificationReport) -> [String: Any] {
    var object: [String: Any] = [
        "required": report.required,
        "executed": report.executed,
        "command_count": report.commandCount,
        "passed_command_count": report.passedCommandCount,
        "hold_reason": report.holdReason,
        "detail": report.detail,
        "command_results": report.commandResults.map { outcome in
            [
                "command_id": outcome.commandID,
                "command": outcome.command,
                "ok": outcome.ok,
                "detail": outcome.detail,
            ]
        }
    ]
    if let contract = report.contract {
        object["verification_contract"] = xtAutomationVerificationContractFoundationValue(contract)
    }
    return object
}

private func xtAutomationWorkspaceDiffFoundationValue(_ report: XTAutomationWorkspaceDiffReport) -> [String: Any] {
    [
        "attempted": report.attempted,
        "captured": report.captured,
        "file_count": report.fileCount,
        "diff_chars": report.diffChars,
        "detail": report.detail,
        "excerpt": report.excerpt,
    ]
}

private func xtAutomationBlockerFoundationValue(_ blocker: XTAutomationBlockerDescriptor) -> [String: Any] {
    [
        "code": blocker.code,
        "summary": blocker.summary,
        "stage": blocker.stage.rawValue,
        "detail": blocker.detail,
        "next_safe_action": blocker.nextSafeAction,
        "retry_eligible": blocker.retryEligible,
        "current_step_id": blocker.currentStepID ?? NSNull(),
        "current_step_title": blocker.currentStepTitle ?? NSNull(),
        "current_step_state": blocker.currentStepState?.rawValue ?? NSNull(),
        "current_step_summary": blocker.currentStepSummary ?? NSNull(),
    ]
}

private func xtAutomationDiffFileCount(_ diff: String) -> Int {
    diff
        .split(separator: "\n")
        .filter { $0.hasPrefix("diff --git ") }
        .count
}

private let xtAutomationMutationTools: Set<ToolName> = [
    .write_file,
    .git_apply,
]

private func xtAutomationSuggestedNextActions(for report: XTAutomationRunExecutionReport) -> [String] {
    var actions: [String] = []
    if report.holdReason == "automation_patch_check_failed" {
        actions.append("review_patch_and_rerun_precheck")
    }
    if let verification = report.verificationReport,
       !verification.ok {
        actions.append("inspect_verify_failure_and_fix_forward")
    }
    if let workspaceDiff = report.workspaceDiffReport,
       workspaceDiff.captured,
       workspaceDiff.fileCount > 0 {
        actions.append("inspect_workspace_diff")
    }
    if report.finalState == .blocked && actions.isEmpty {
        actions.append("inspect_blocked_run_and_prepare_retry")
    }
    if report.finalState == .delivered {
        actions.append("review_delivery_and_decide_next_iteration")
    }
    return actions
}
