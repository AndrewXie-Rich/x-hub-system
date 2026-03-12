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

struct XTAutomationVerificationReport: Codable, Equatable, Sendable {
    var required: Bool
    var executed: Bool
    var commandCount: Int
    var passedCommandCount: Int
    var holdReason: String
    var detail: String
    var commandResults: [XTAutomationVerificationCommandOutcome]

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
    var finalState: XTAutomationRunState
    var holdReason: String
    var detail: String
    var actionResults: [XTAutomationActionExecutionOutcome]
    var verificationReport: XTAutomationVerificationReport?
    var workspaceDiffReport: XTAutomationWorkspaceDiffReport?
    var suggestedNextActions: [String]
}

struct XTAutomationRunExecutionReport: Equatable, Sendable {
    var runID: String
    var lineage: XTAutomationRunLineage? = nil
    var recipeRef: String
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
        now: Date = Date()
    ) async -> XTAutomationRunExecutionReport {
        let auditRef = "audit-xt-auto-exec-\(xtAutomationActionToken(runID, fallback: "run"))-\(Int(now.timeIntervalSince1970))"
        let actions = recipe.actionGraph
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
        let resolvedLineage = xtAutomationResolvedLineage(lineage, fallbackRunID: runID)

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
                    auditRef: auditRef
                ),
                ctx: ctx,
                createdAt: now
            )
        }

        var outcomes: [XTAutomationActionExecutionOutcome] = []
        var hadSuccessfulMutation = false

        for (index, action) in actions.enumerated() {
            if Task.isCancelled {
                let report = XTAutomationRunExecutionReport(
                    runID: runID,
                    lineage: resolvedLineage,
                    recipeRef: recipe.ref,
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
                    auditRef: auditRef
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
                auditRef: auditRef
            )
            if let preflightFailure {
                outcomes.append(preflightFailure)
                if !action.continueOnFailure {
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
                        auditRef: auditRef
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
                let detail = ok
                    ? (body.isEmpty ? "ok" : xtAutomationTruncate(body, maxChars: 240))
                    : xtAutomationFailureDetail(
                        body: body,
                        denyCode: denyCode,
                        expectationToken: action.successBodyContains
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
                    let report = XTAutomationRunExecutionReport(
                        runID: runID,
                        lineage: resolvedLineage,
                        recipeRef: recipe.ref,
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
                        auditRef: auditRef
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
                    let report = XTAutomationRunExecutionReport(
                        runID: runID,
                        lineage: resolvedLineage,
                        recipeRef: recipe.ref,
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
                        auditRef: auditRef
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
            auditRef: auditRef
        )
        if let verificationReport, !verificationReport.ok {
            let report = XTAutomationRunExecutionReport(
                runID: runID,
                lineage: resolvedLineage,
                recipeRef: recipe.ref,
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
                auditRef: auditRef
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
        let report = XTAutomationRunExecutionReport(
            runID: runID,
            lineage: resolvedLineage,
            recipeRef: recipe.ref,
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
            auditRef: auditRef
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
        auditRef: String
    ) async -> XTAutomationActionExecutionOutcome? {
        let policyDecision = await xtAutomationRuntimePolicyDecision(
            recipe: recipe,
            action: action,
            config: config,
            projectRoot: ctx.root
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
        auditRef: String
    ) async -> XTAutomationVerificationReport? {
        let successfulActionIDs = Set(actionOutcomes.filter(\.ok).map(\.actionID))
        let verifyTriggers = actions.filter { action in
            successfulActionIDs.contains(action.actionID)
                && action.effectiveRequiresVerification(projectVerifyAfterChanges: config.verifyAfterChanges)
        }
        guard !verifyTriggers.isEmpty else { return nil }

        let configuredCommands = (verifyCommandsOverride?.isEmpty == false ? verifyCommandsOverride! : config.verifyCommands)
        let commands = AXProjectStackDetector
            .filterApplicableVerifyCommands(configuredCommands, forProjectRoot: ctx.root)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        AXProjectStore.appendRawLog(
            [
                "type": "automation_verification",
                "phase": "started",
                "created_at": Date().timeIntervalSince1970,
                "run_id": runID,
                "recipe_ref": recipe.ref,
                "trigger_action_ids": verifyTriggers.map(\.actionID),
                "command_count": commands.count,
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
                commandResults: []
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
                    commandResults: outcomes
                )
                logVerificationCompletion(runID: runID, recipeRef: recipe.ref, report: report, ctx: ctx, auditRef: auditRef)
                return report
            }

            let verificationAction = XTAutomationRecipeAction(
                actionID: "verify_\(index + 1)",
                title: "Verify command \(index + 1)",
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
                projectRoot: ctx.root
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
                    commandResults: outcomes
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
                        commandResults: outcomes
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
                    commandResults: outcomes
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
            commandResults: outcomes
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
            "final_state": finalizedReport.finalState.rawValue,
            "hold_reason": finalizedReport.holdReason,
            "detail": finalizedReport.detail,
            "executed_action_count": finalizedReport.executedActionCount,
            "succeeded_action_count": finalizedReport.succeededActionCount,
            "total_action_count": finalizedReport.totalActionCount,
            "verification": finalizedReport.verificationReport.map(xtAutomationVerificationFoundationValue) ?? NSNull(),
            "workspace_diff": finalizedReport.workspaceDiffReport.map(xtAutomationWorkspaceDiffFoundationValue) ?? NSNull(),
            "handoff_artifact_path": finalizedReport.handoffArtifactPath ?? NSNull(),
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
            finalState: report.finalState,
            holdReason: report.holdReason,
            detail: report.detail,
            actionResults: report.actionResults,
            verificationReport: report.verificationReport,
            workspaceDiffReport: report.workspaceDiffReport,
            suggestedNextActions: xtAutomationSuggestedNextActions(for: report)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(artifact) else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: targetURL, options: .atomic)
            return relativePath
        } catch {
            return nil
        }
    }
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

private func xtAutomationVerificationFoundationValue(_ report: XTAutomationVerificationReport) -> [String: Any] {
    [
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
