import Foundation

extension SupervisorManager {
    func makeRetryAutomationRunRequest(
        for project: AXProjectEntry,
        ctx: AXProjectContext,
        retryPackage: XTAutomationRetryPackage,
        triggerMode: String
    ) throws -> XTAutomationRunRequest {
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        guard let recipe = config.activeAutomationRecipe else {
            throw XTAutomationRunCoordinatorError.activeRecipeMissing
        }
        let trustedAutomationStatus = config.trustedAutomationStatus(
            forProjectRoot: ctx.root,
            permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness.current(),
            requiredDeviceToolGroups: recipe.requiredDeviceToolGroups
        )

        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970)
        let projectToken = normalizedLookupKey(project.displayName).isEmpty
            ? normalizedLookupKey(project.projectId)
            : normalizedLookupKey(project.displayName)
        let requiresGrant = !recipe.grantPolicyRef.isEmpty
        let policyRef = requiresGrant ? recipe.grantPolicyRef : ""
        let sourceRunToken = xtAutomationActionToken(retryPackage.sourceRunID, fallback: "run")
        let normalizedTriggerMode = triggerMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? automationManualRetryTrigger
            : triggerMode.trimmingCharacters(in: .whitespacesAndNewlines)
        let triggerID = normalizedTriggerMode == automationAutoRetryTrigger ? "auto/retry" : "manual/recover"
        let blockedTaskID = normalizedTriggerMode == automationAutoRetryTrigger ? "XT-AUTO-SELF-ITERATE" : "XT-AUTO-RECOVER"
        let operatorConsoleEvidenceRef = normalizedTriggerMode == automationAutoRetryTrigger
            ? "build/reports/xt_auto_self_iterate_operator_console.v1.json"
            : "build/reports/xt_auto_recover_operator_console.v1.json"
        let latestDeltaRef = normalizedTriggerMode == automationAutoRetryTrigger
            ? "build/reports/xt_auto_self_iterate_delta.v1.json"
            : "build/reports/xt_auto_recover_delta.v1.json"
        let fallbackDeliveryRef = normalizedTriggerMode == automationAutoRetryTrigger
            ? "build/reports/xt_auto_self_iterate_delivery.v1.json"
            : "build/reports/xt_auto_recover_delivery.v1.json"
        let deliveryRef = xtAutomationPersistedRunDeliveryRef(
            for: retryPackage.sourceRunID,
            ctx: ctx
        ) ?? fallbackDeliveryRef
        let triggerEvidenceRef = normalizedTriggerMode == automationAutoRetryTrigger
            ? "automatic://self_iterate/retry"
            : "manual://supervisor_command/recover"
        let dedupePrefix = normalizedTriggerMode == automationAutoRetryTrigger ? "auto_recover" : "recover"
        let planningArtifact = xtAutomationResolvedRetryPlanningArtifact(
            from: retryPackage,
            ctx: ctx
        )
        let recipeProposalArtifact = xtAutomationResolvedRetryRecipeProposalArtifact(
            from: retryPackage,
            ctx: ctx
        )
        let runtimePatchOverlay = recipeProposalArtifact?.runtimePatchOverlay
            ?? retryPackage.runtimePatchOverlay
        let overlayOverrides = runtimePatchOverlay.map {
            xtAutomationApplyRuntimePatchOverlay(
                $0,
                baseRecipe: recipe,
                baseVerifyCommands: config.verifyCommands
            )
        }
        let retryLineage = automationRetryLineage(for: retryPackage)
        let recipeOverride = overlayOverrides?.recipeOverride
            ?? recipeProposalArtifact.flatMap { artifact in
            automationRetryRecipeOverride(
                recipeProposalArtifact: artifact,
                baseRecipe: recipe
            )
        } ?? planningArtifact.flatMap { artifact in
            automationRetryRecipeOverride(
                planningArtifact: artifact,
                baseRecipe: recipe
            )
        } ?? automationRetryRecipeOverride(
            from: retryPackage,
            baseRecipe: recipe
        )
        let verifyCommandsOverride: [String]? = {
            if let overlayCommands = overlayOverrides?.verifyCommandsOverride {
                return overlayCommands
            }
            if let proposalCommands = recipeProposalArtifact?.proposedVerifyCommands,
               !proposalCommands.isEmpty {
                return proposalCommands
            }
            if let planningCommands = planningArtifact?.proposedVerifyCommands,
               !planningCommands.isEmpty {
                return planningCommands
            }
            return retryPackage.revisedVerifyCommands
        }()
        let verificationContractOverride: XTAutomationVerificationContract? = {
            if let overlayContract = overlayOverrides?.verificationContractOverride {
                return overlayContract
            }
            if let proposalContract = recipeProposalArtifact?.proposedVerificationContract {
                return proposalContract
            }
            if let planningContract = planningArtifact?.proposedVerificationContract {
                return planningContract
            }
            return retryPackage.revisedVerificationContract
        }()

        return XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: triggerID,
                    triggerType: .manual,
                    source: .hub,
                    payloadRef: "local://supervisor/\(normalizedTriggerMode)/\(projectToken)/\(timestamp)/\(sourceRunToken)",
                    requiresGrant: requiresGrant,
                    policyRef: policyRef,
                    dedupeKey: "\(dedupePrefix)|\(project.projectId)|\(retryPackage.sourceRunID)|\(timestamp)"
                )
            ],
            lineage: retryLineage,
            trustedAutomationReady: trustedAutomationStatus.trustedAutomationReady,
            permissionOwnerReady: trustedAutomationStatus.permissionOwnerReady,
            currentOwner: trustedAutomationStatus.permissionOwnerReady ? "XT-TRUSTED" : "XT-L2",
            blockedTaskID: blockedTaskID,
            operatorConsoleEvidenceRef: operatorConsoleEvidenceRef,
            latestDeltaRef: latestDeltaRef,
            deliveryRef: deliveryRef,
            additionalEvidenceRefs: xtAutomationMergeEvidenceRefs(
                [
                    triggerEvidenceRef,
                    "recipe://\(recipe.ref)",
                    "trusted_automation://\(trustedAutomationStatus.state.rawValue)"
                ] + trustedAutomationStatus.missingPrerequisites.map {
                    "trusted_automation_issue://\($0)"
                },
                retryPackage.additionalEvidenceRefs
            ),
            recipeOverride: recipeOverride,
            verifyCommandsOverride: verifyCommandsOverride,
            verificationContractOverride: verificationContractOverride,
            now: now
        )
    }

    func buildAutomationRetryPackage(
        for project: AXProjectEntry,
        ctx: AXProjectContext,
        sourceRunID: String,
        triggerMode: String
    ) -> AutomationRetryPlanningMaterialization? {
        let config = try? AXProjectStore.loadOrCreateConfig(for: ctx)
        guard let recipe = config?.activeAutomationRecipe,
              !recipe.actionGraph.isEmpty else {
            return nil
        }

        let reportedHandoffPath = automationLatestExecutionReport?.runID == sourceRunID
            ? automationLatestExecutionReport?.handoffArtifactPath
            : nil
        guard let handoff = xtAutomationLoadHandoffArtifact(
            for: sourceRunID,
            ctx: ctx,
            reportedRelativePath: reportedHandoffPath
        ) else {
            return nil
        }

        let strategy = xtAutomationRetryStrategy(for: handoff.artifact)
        let sourceHoldReason = handoff.artifact.holdReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let verificationHoldReason = handoff.artifact.verificationReport?.holdReason
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let diffFileCount = handoff.artifact.workspaceDiffReport?.fileCount ?? 0
        let revision = xtAutomationRetryRevision(
            recipe: recipe,
            artifact: handoff.artifact
        )
        let previousRetryPackage = xtAutomationLoadRetryPackage(
            forRetryRunID: sourceRunID,
            projectID: project.projectId,
            ctx: ctx
        )
        let sourceLineage = xtAutomationResolvedLineage(
            previousRetryPackage?.lineage
                ?? handoff.artifact.lineage
                ?? (automationLatestExecutionReport?.runID == sourceRunID
                    ? automationLatestExecutionReport?.lineage
                    : nil),
            fallbackRunID: handoff.artifact.runID
        )
        let retryLineage = sourceLineage.retryChild(parentRunID: handoff.artifact.runID)
        let nextRetryDepth = retryLineage.retryDepth
        let additionalEvidenceRefs = xtAutomationMergeEvidenceRefs(
            [
                handoff.relativePath,
                "retry://source_run/\(handoff.artifact.runID)",
                "retry://source_state/\(handoff.artifact.finalState.rawValue)",
                "retry://strategy/\(strategy.strategy)",
                "retry://trigger/\(normalizedLookupKey(triggerMode))",
                "retry://depth/\(nextRetryDepth)"
            ],
            [
                sourceHoldReason.isEmpty ? "" : "retry://hold_reason/\(sourceHoldReason)",
                verificationHoldReason.isEmpty ? "" : "retry://verify_hold_reason/\(verificationHoldReason)",
                diffFileCount > 0 ? "retry://workspace_diff/\(diffFileCount)_files" : "",
                strategy.reason.isEmpty ? "" : "retry://reason/\(strategy.reason)"
            ] + revision.additionalEvidenceRefs + handoff.artifact.suggestedNextActions.prefix(4).map {
                "retry://suggested/\(xtAutomationActionToken($0, fallback: "step"))"
            }
        )
        let runtimePatchOverlay = xtAutomationRuntimePatchOverlay(
            revisedActionGraph: revision.revisedActionGraph,
            revisedVerifyCommands: revision.revisedVerifyCommands,
            revisedVerificationContract: revision.revisedVerificationContract
        )
        let sourceBlocker = handoff.artifact.structuredBlocker
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
        let retryReasonDescriptor = xtAutomationStructuredRetryReason(
            strategy: strategy.strategy,
            reason: strategy.reason,
            blocker: sourceBlocker,
            planningMode: revision.planningMode
        )

        let planningArtifact = XTAutomationRetryPlanningArtifact(
            schemaVersion: XTAutomationRetryPlanningArtifact.currentSchemaVersion,
            generatedAt: Date().timeIntervalSince1970,
            projectID: project.projectId,
            lineage: retryLineage,
            sourceRunID: handoff.artifact.runID,
            sourceHandoffArtifactPath: handoff.relativePath,
            baseRecipeRef: recipe.ref,
            sourceBlocker: sourceBlocker,
            retryStrategy: strategy.strategy,
            retryReason: strategy.reason,
            retryReasonDescriptor: retryReasonDescriptor,
            planningMode: revision.planningMode,
            planningSummary: revision.planningSummary,
            runtimePatchOverlay: runtimePatchOverlay,
            proposedActionGraph: revision.revisedActionGraph ?? [],
            proposedVerifyCommands: revision.revisedVerifyCommands ?? [],
            proposedVerificationContract: revision.revisedVerificationContract,
            suggestedNextActions: handoff.artifact.suggestedNextActions,
            additionalEvidenceRefs: additionalEvidenceRefs
        )
        let planningArtifactPath = xtAutomationPersistRetryPlanningArtifact(planningArtifact, ctx: ctx) ?? ""
        let recipeProposalArtifact = XTAutomationRecipeProposalArtifact(
            schemaVersion: XTAutomationRecipeProposalArtifact.currentSchemaVersion,
            generatedAt: Date().timeIntervalSince1970,
            projectID: project.projectId,
            lineage: retryLineage,
            sourceRunID: handoff.artifact.runID,
            sourceHandoffArtifactPath: handoff.relativePath,
            sourcePlanningArtifactPath: planningArtifactPath.isEmpty ? nil : planningArtifactPath,
            baseRecipeRef: recipe.ref,
            sourceBlocker: sourceBlocker,
            retryStrategy: strategy.strategy,
            retryReason: strategy.reason,
            retryReasonDescriptor: retryReasonDescriptor,
            proposalMode: revision.planningMode,
            proposalSummary: revision.planningSummary,
            runtimePatchOverlay: runtimePatchOverlay,
            proposedActionGraph: revision.revisedActionGraph ?? [],
            proposedVerifyCommands: revision.revisedVerifyCommands ?? [],
            proposedVerificationContract: revision.revisedVerificationContract,
            suggestedNextActions: handoff.artifact.suggestedNextActions,
            additionalEvidenceRefs: additionalEvidenceRefs
        )
        let recipeProposalArtifactPath = xtAutomationPersistRetryRecipeProposalArtifact(recipeProposalArtifact, ctx: ctx) ?? ""

        let package = XTAutomationRetryPackage(
            schemaVersion: XTAutomationRetryPackage.currentSchemaVersion,
            generatedAt: Date().timeIntervalSince1970,
            projectID: project.projectId,
            lineage: retryLineage,
            deliveryRef: handoff.artifact.deliveryRef,
            sourceRunID: handoff.artifact.runID,
            sourceFinalState: handoff.artifact.finalState,
            sourceHoldReason: sourceHoldReason,
            sourceHandoffArtifactPath: handoff.relativePath,
            sourceBlocker: sourceBlocker,
            retryStrategy: strategy.strategy,
            retryReason: strategy.reason,
            retryReasonDescriptor: retryReasonDescriptor,
            suggestedNextActions: handoff.artifact.suggestedNextActions,
            additionalEvidenceRefs: additionalEvidenceRefs,
            planningMode: revision.planningMode,
            planningSummary: revision.planningSummary,
            runtimePatchOverlay: runtimePatchOverlay,
            revisedActionGraph: revision.revisedActionGraph,
            revisedVerifyCommands: revision.revisedVerifyCommands,
            revisedVerificationContract: revision.revisedVerificationContract,
            planningArtifactPath: planningArtifactPath.isEmpty ? nil : planningArtifactPath,
            recipeProposalArtifactPath: recipeProposalArtifactPath.isEmpty ? nil : recipeProposalArtifactPath,
            retryRunID: "",
            retryArtifactPath: ""
        )
        return AutomationRetryPlanningMaterialization(
            package: package,
            planningArtifact: planningArtifactPath.isEmpty ? nil : planningArtifact,
            recipeProposalArtifact: recipeProposalArtifactPath.isEmpty ? nil : recipeProposalArtifact
        )
    }

    func automationRetryRecipeOverride(
        from retryPackage: XTAutomationRetryPackage,
        baseRecipe: AXAutomationRecipeRuntimeBinding
    ) -> AXAutomationRecipeRuntimeBinding? {
        if let runtimePatchOverlay = retryPackage.runtimePatchOverlay,
           let patched = xtAutomationApplyRuntimePatchOverlay(
                runtimePatchOverlay,
                baseRecipe: baseRecipe,
                baseVerifyCommands: []
           ).recipeOverride {
            return patched
        }
        guard let revisedActionGraph = retryPackage.revisedActionGraph,
              !revisedActionGraph.isEmpty else {
            return nil
        }
        var revised = baseRecipe
        revised.actionGraph = revisedActionGraph
        return revised.normalized()
    }

    func automationRetryRecipeOverride(
        planningArtifact: XTAutomationRetryPlanningArtifact,
        baseRecipe: AXAutomationRecipeRuntimeBinding
    ) -> AXAutomationRecipeRuntimeBinding? {
        guard !planningArtifact.proposedActionGraph.isEmpty else { return nil }
        var revised = baseRecipe
        revised.actionGraph = planningArtifact.proposedActionGraph
        return revised.normalized()
    }

    func automationRetryRecipeOverride(
        recipeProposalArtifact: XTAutomationRecipeProposalArtifact,
        baseRecipe: AXAutomationRecipeRuntimeBinding
    ) -> AXAutomationRecipeRuntimeBinding? {
        if let runtimePatchOverlay = recipeProposalArtifact.runtimePatchOverlay,
           let patched = xtAutomationApplyRuntimePatchOverlay(
                runtimePatchOverlay,
                baseRecipe: baseRecipe,
                baseVerifyCommands: []
           ).recipeOverride {
            return patched
        }
        guard !recipeProposalArtifact.proposedActionGraph.isEmpty else { return nil }
        var revised = baseRecipe
        revised.actionGraph = recipeProposalArtifact.proposedActionGraph
        return revised.normalized()
    }

    func xtAutomationResolvedRetryPlanningArtifact(
        from retryPackage: XTAutomationRetryPackage,
        ctx: AXProjectContext
    ) -> XTAutomationRetryPlanningArtifact? {
        if let artifact = xtAutomationLoadRetryPlanningArtifact(
            sourceRunID: retryPackage.sourceRunID,
            ctx: ctx,
            reportedRelativePath: retryPackage.planningArtifactPath
        )?.artifact {
            return artifact
        }

        guard let planningMode = retryPackage.planningMode,
              let planningSummary = retryPackage.planningSummary else {
            return nil
        }

        return XTAutomationRetryPlanningArtifact(
            schemaVersion: XTAutomationRetryPlanningArtifact.currentSchemaVersion,
            generatedAt: retryPackage.generatedAt,
            projectID: retryPackage.projectID,
            lineage: retryPackage.lineage,
            sourceRunID: retryPackage.sourceRunID,
            sourceHandoffArtifactPath: retryPackage.sourceHandoffArtifactPath,
            baseRecipeRef: "",
            sourceBlocker: retryPackage.sourceBlocker,
            retryStrategy: retryPackage.retryStrategy,
            retryReason: retryPackage.retryReason,
            retryReasonDescriptor: retryPackage.retryReasonDescriptor,
            planningMode: planningMode,
            planningSummary: planningSummary,
            runtimePatchOverlay: retryPackage.runtimePatchOverlay,
            proposedActionGraph: retryPackage.revisedActionGraph ?? [],
            proposedVerifyCommands: retryPackage.revisedVerifyCommands ?? [],
            proposedVerificationContract: retryPackage.revisedVerificationContract,
            suggestedNextActions: retryPackage.suggestedNextActions,
            additionalEvidenceRefs: retryPackage.additionalEvidenceRefs
        )
    }

    func xtAutomationResolvedRetryRecipeProposalArtifact(
        from retryPackage: XTAutomationRetryPackage,
        ctx: AXProjectContext
    ) -> XTAutomationRecipeProposalArtifact? {
        if var artifact = xtAutomationLoadRetryRecipeProposalArtifact(
            sourceRunID: retryPackage.sourceRunID,
            ctx: ctx,
            reportedRelativePath: retryPackage.recipeProposalArtifactPath
        )?.artifact {
            if artifact.runtimePatchOverlay == nil {
                artifact.runtimePatchOverlay = xtAutomationRuntimePatchOverlay(
                    revisedActionGraph: artifact.proposedActionGraph,
                    revisedVerifyCommands: artifact.proposedVerifyCommands,
                    revisedVerificationContract: artifact.proposedVerificationContract
                )
            }
            return artifact
        }

        let planningArtifact = xtAutomationResolvedRetryPlanningArtifact(
            from: retryPackage,
            ctx: ctx
        )
        let proposalMode = planningArtifact?.planningMode
            ?? retryPackage.planningMode?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        let proposalSummary = planningArtifact?.planningSummary
            ?? retryPackage.planningSummary?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let proposalMode,
              !proposalMode.isEmpty,
              let proposalSummary,
              !proposalSummary.isEmpty else {
            return nil
        }

        return XTAutomationRecipeProposalArtifact(
            schemaVersion: XTAutomationRecipeProposalArtifact.currentSchemaVersion,
            generatedAt: retryPackage.generatedAt,
            projectID: retryPackage.projectID,
            lineage: retryPackage.lineage,
            sourceRunID: retryPackage.sourceRunID,
            sourceHandoffArtifactPath: retryPackage.sourceHandoffArtifactPath,
            sourcePlanningArtifactPath: retryPackage.planningArtifactPath,
            baseRecipeRef: planningArtifact?.baseRecipeRef ?? "",
            sourceBlocker: retryPackage.sourceBlocker,
            retryStrategy: retryPackage.retryStrategy,
            retryReason: retryPackage.retryReason,
            retryReasonDescriptor: retryPackage.retryReasonDescriptor,
            proposalMode: proposalMode,
            proposalSummary: proposalSummary,
            runtimePatchOverlay: retryPackage.runtimePatchOverlay
                ?? xtAutomationRuntimePatchOverlay(
                    revisedActionGraph: planningArtifact?.proposedActionGraph ?? retryPackage.revisedActionGraph,
                    revisedVerifyCommands: planningArtifact?.proposedVerifyCommands ?? retryPackage.revisedVerifyCommands,
                    revisedVerificationContract: planningArtifact?.proposedVerificationContract ?? retryPackage.revisedVerificationContract
                ),
            proposedActionGraph: planningArtifact?.proposedActionGraph ?? retryPackage.revisedActionGraph ?? [],
            proposedVerifyCommands: planningArtifact?.proposedVerifyCommands ?? retryPackage.revisedVerifyCommands ?? [],
            proposedVerificationContract: planningArtifact?.proposedVerificationContract ?? retryPackage.revisedVerificationContract,
            suggestedNextActions: retryPackage.suggestedNextActions,
            additionalEvidenceRefs: retryPackage.additionalEvidenceRefs
        )
    }
}
