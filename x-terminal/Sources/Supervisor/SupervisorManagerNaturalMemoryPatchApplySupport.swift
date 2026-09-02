import Foundation

extension SupervisorManager {
    func applySupervisorNaturalMemoryPatch(
        _ intent: SupervisorNaturalMemoryPatchIntent,
        project: AXProjectEntry,
        ctx: AXProjectContext
    ) throws -> SupervisorNaturalMemoryPatchApplyResult {
        let now = Date().timeIntervalSince1970
        let nowMs = Int64((now * 1000.0).rounded())
        let projectSuffix = String(project.projectId.prefix(8)).lowercased()
        var appliedKinds: [String] = []
        var replyLines: [String] = []
        var evidencePins: [SupervisorSelectedEvidencePin] = []
        var noChangeDetected = false

        let existingEvidencePinsByID = Dictionary(
            uniqueKeysWithValues: SupervisorSelectedEvidencePinStore.load(for: ctx).pins.map { ($0.pinId, $0) }
        )
        let existingDecisionEventsByID = Dictionary(
            uniqueKeysWithValues: SupervisorDecisionTrackStore.load(for: ctx).events.map { ($0.decisionId, $0) }
        )

        if !intent.selectedEvidence.isEmpty {
            var appendedEvidencePins: [SupervisorSelectedEvidencePin] = []
            for summary in intent.selectedEvidence.prefix(4) {
                let pinSuffix = supervisorNaturalMemoryPatchStableSuffix(
                    "\(project.projectId)|evidence|\(summary)"
                )
                let pin = SupervisorSelectedEvidencePinBuilder.build(
                    pinId: "manual_evidence_\(pinSuffix)",
                    projectId: project.projectId,
                    summary: summary,
                    sourceNote: "supervisor_user_confirmed",
                    whyItMatters: intent.decisionReason ?? intent.blockerSummary ?? "user_selected_evidence",
                    createdAtMs: nowMs,
                    auditRef: "audit-supervisor-evidence-pin-\(projectSuffix)-\(pinSuffix)-\(nowMs)"
                )
                if let existing = existingEvidencePinsByID[pin.pinId],
                   supervisorNaturalMemoryPatchEvidenceMatches(existing, pin) {
                    noChangeDetected = true
                    evidencePins.append(existing)
                    continue
                }
                _ = try SupervisorSelectedEvidencePinStore.upsert(pin, for: ctx)
                evidencePins.append(pin)
                appendedEvidencePins.append(pin)
            }
            if !appendedEvidencePins.isEmpty {
                appliedKinds.append("selected_evidence")
                let firstEvidence = appendedEvidencePins.first?.summary ?? ""
                replyLines.append(
                    "你刚确认的依据我已经先记成后续纠偏优先证据了：\(capped(firstEvidence, maxChars: 88))。"
                )
            }
        }

        let longtermAuditRef = "audit-supervisor-memory-longterm-\(projectSuffix)-\(nowMs)"
        var specCapsule = SupervisorProjectSpecCapsuleStore.load(for: ctx) ?? SupervisorProjectSpecCapsule(
            schemaVersion: SupervisorProjectSpecCapsule.schemaVersion,
            projectId: project.projectId,
            goal: "",
            mvpDefinition: "",
            nonGoals: [],
            approvedTechStack: [],
            techStackBlacklist: [],
            moduleMap: [],
            milestoneMap: [],
            decisionDefaults: [:],
            riskProfile: .medium,
            updatedAtMs: nowMs,
            sourceRefs: []
        )
        var longtermChanged = false
        if let goal = intent.goal, !goal.isEmpty, goal != specCapsule.goal {
            specCapsule.goal = goal
            longtermChanged = true
        }
        if let doneDefinition = intent.doneDefinition,
           !doneDefinition.isEmpty,
           doneDefinition != specCapsule.mvpDefinition {
            specCapsule.mvpDefinition = doneDefinition
            longtermChanged = true
        }
        let mergedNonGoals = orderedUniqueReviewScalars(specCapsule.nonGoals + intent.nonGoals)
        if mergedNonGoals != specCapsule.nonGoals {
            specCapsule.nonGoals = mergedNonGoals
            longtermChanged = true
        }
        let mergedTechStack = orderedUniqueReviewScalars(
            specCapsule.approvedTechStack + intent.approvedTechStack
        )
        if mergedTechStack != specCapsule.approvedTechStack {
            specCapsule.approvedTechStack = mergedTechStack
            longtermChanged = true
        }
        if longtermChanged {
            specCapsule.schemaVersion = SupervisorProjectSpecCapsule.schemaVersion
            specCapsule.projectId = project.projectId
            specCapsule.updatedAtMs = nowMs
            specCapsule.sourceRefs = orderedUniqueReviewScalars(
                specCapsule.sourceRefs + [longtermAuditRef]
            )
            _ = try SupervisorProjectSpecCapsuleStore.upsert(specCapsule, for: ctx)
            appliedKinds.append("longterm")

            var longtermBits: [String] = []
            if let goal = intent.goal, !goal.isEmpty {
                longtermBits.append("目标=\(capped(goal, maxChars: 42))")
            }
            if let doneDefinition = intent.doneDefinition, !doneDefinition.isEmpty {
                longtermBits.append("完成标准=\(capped(doneDefinition, maxChars: 42))")
            }
            if !intent.nonGoals.isEmpty {
                longtermBits.append("非目标=\(capped(intent.nonGoals.joined(separator: "、"), maxChars: 42))")
            }
            if !intent.approvedTechStack.isEmpty {
                longtermBits.append("技术栈=\(capped(intent.approvedTechStack.joined(separator: "、"), maxChars: 42))")
            }
            replyLines.append(
                "这段长期背景我已经记到《\(project.displayName)》的项目 anchor 里了" +
                (longtermBits.isEmpty ? "。" : "：\(longtermBits.joined(separator: "；"))。")
            )
        }

        if let decisionStatement = intent.decisionStatement, !decisionStatement.isEmpty {
            let decisionCategory = supervisorNaturalMemoryPatchDecisionCategory(
                statement: decisionStatement,
                reason: intent.decisionReason
            )
            let decisionSuffix = supervisorNaturalMemoryPatchStableSuffix(
                "\(project.projectId)|decision|\(decisionCategory.rawValue)|\(decisionStatement)"
            )
            let decisionEvent = SupervisorDecisionTrackBuilder.build(
                decisionId: "manual_decision_\(decisionSuffix)",
                projectId: project.projectId,
                category: decisionCategory,
                status: .approved,
                statement: decisionStatement,
                source: firstMeaningfulDigestValue(
                    [intent.decisionReason, "supervisor_direct_memory_patch"],
                    treatNoValueAsPlaceholder: false
                ),
                reversible: !containsAny(
                    normalizedSupervisorIntentText(decisionStatement),
                    ["锁定", "freeze", "固定", "必须", "only"]
                ),
                approvalRequired: false,
                approvedBy: "supervisor",
                auditRef: "audit-supervisor-memory-decision-\(projectSuffix)-\(decisionSuffix)-\(nowMs)",
                evidenceRefs: evidencePins.map(\.auditRef),
                createdAtMs: nowMs,
                updatedAtMs: nowMs
            )
            if let existing = existingDecisionEventsByID[decisionEvent.decisionId],
               supervisorNaturalMemoryPatchDecisionMatches(existing, decisionEvent) {
                noChangeDetected = true
            } else {
                _ = try SupervisorDecisionTrackStore.upsert(decisionEvent, for: ctx)
                appliedKinds.append("decision_lineage")
                let reasonTail: String
                if let reason = intent.decisionReason, !reason.isEmpty {
                    reasonTail = " 原因我也一起记下了：\(capped(reason, maxChars: 72))。"
                } else {
                    reasonTail = ""
                }
                replyLines.append(
                    "这条关键路径决策我已经记下了：\(capped(decisionStatement, maxChars: 88))。\n\(reasonTail)"
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }

        let hasBlockerFacts =
            (intent.blockerSummary?.isEmpty == false) ||
            !intent.attemptedActions.isEmpty ||
            (intent.currentStateSummary?.isEmpty == false) ||
            (intent.nextStepSummary?.isEmpty == false)
        let blockerSummary = supervisorNaturalMemoryPatchComposedBlockerSummary(
            blocker: intent.blockerSummary,
            attemptedActions: intent.attemptedActions
        )
        let currentStateSummary = firstMeaningfulDigestValue(
            [
                intent.currentStateSummary,
                intent.attemptedActions.isEmpty
                    ? nil
                    : "已试过：\(intent.attemptedActions.joined(separator: "；"))",
                project.currentStateSummary
            ],
            treatNoValueAsPlaceholder: false
        )
        let nextStepSummary = firstMeaningfulDigestValue(
            [intent.nextStepSummary, project.nextStepSummary],
            treatContinueCurrentTaskAsPlaceholder: true,
            treatNoValueAsPlaceholder: false
        )
        if hasBlockerFacts {
            let blockerChanged =
                normalizedLookupKey(project.blockerSummary ?? "") != normalizedLookupKey(blockerSummary) ||
                normalizedLookupKey(project.currentStateSummary ?? "") != normalizedLookupKey(currentStateSummary) ||
                normalizedLookupKey(project.nextStepSummary ?? "") != normalizedLookupKey(nextStepSummary)
            if blockerChanged {
                let registryUpdate = AXProjectRegistryStore.updateStatusDigest(
                    forRoot: ctx.root,
                    digest: firstMeaningfulDigestValue(
                        [
                            project.statusDigest,
                            currentStateSummary,
                            blockerSummary,
                            nextStepSummary
                        ],
                        treatContinueCurrentTaskAsPlaceholder: true,
                        treatNoValueAsPlaceholder: false
                    ),
                    lastSummaryAt: now,
                    currentState: currentStateSummary,
                    nextStep: nextStepSummary,
                    blocker: blockerSummary
                )
                if let entry = registryUpdate.entry {
                    appModel?.registry = registryUpdate.registry
                    HubIPCClient.syncProject(entry)
                }
                appliedKinds.append("blocker_lineage")

                var blockerBits: [String] = []
                if !blockerSummary.isEmpty {
                    blockerBits.append("卡点=\(capped(blockerSummary, maxChars: 52))")
                }
                if !nextStepSummary.isEmpty {
                    blockerBits.append("下一步=\(capped(nextStepSummary, maxChars: 52))")
                }
                replyLines.append(
                    "当前卡点我已经记进项目现状了" +
                    (blockerBits.isEmpty ? "。" : "：\(blockerBits.joined(separator: "；"))。")
                )
            } else {
                noChangeDetected = true
            }
        }

        guard !appliedKinds.isEmpty else {
            return SupervisorNaturalMemoryPatchApplyResult(
                replyText: noChangeDetected
                    ? ""
                    : naturalSupervisorMemoryPatchPrompt(projectName: project.displayName),
                appliedKinds: [],
                noChangeDetected: noChangeDetected
            )
        }

        AXProjectStore.appendRawLog(
            [
                "type": "supervisor_memory_patch",
                "action": "upsert",
                "source": "supervisor_direct_natural_language",
                "project_id": project.projectId,
                "patch_types": appliedKinds,
                "goal": intent.goal ?? "",
                "done_definition": intent.doneDefinition ?? "",
                "non_goals": intent.nonGoals,
                "approved_tech_stack": intent.approvedTechStack,
                "decision_statement": intent.decisionStatement ?? "",
                "decision_reason": intent.decisionReason ?? "",
                "blocker_summary": blockerSummary,
                "current_state": currentStateSummary,
                "next_step": nextStepSummary,
                "selected_evidence": intent.selectedEvidence,
                "evidence_refs": evidencePins.map(\.auditRef),
                "timestamp_ms": nowMs
            ],
            for: ctx
        )
        appendRecentEvent(
            "memory patch: \(project.displayName) -> \(appliedKinds.joined(separator: ","))",
            project: project
        )

        return SupervisorNaturalMemoryPatchApplyResult(
            replyText: replyLines.joined(separator: "\n"),
            appliedKinds: appliedKinds,
            noChangeDetected: noChangeDetected
        )
    }

    private func supervisorNaturalMemoryPatchEvidenceMatches(
        _ lhs: SupervisorSelectedEvidencePin,
        _ rhs: SupervisorSelectedEvidencePin
    ) -> Bool {
        let left = lhs.sanitizedForStorage
        let right = rhs.sanitizedForStorage
        return left.pinId == right.pinId &&
            left.projectId == right.projectId &&
            left.summary == right.summary &&
            left.sourceNote == right.sourceNote &&
            left.whyItMatters == right.whyItMatters
    }

    private func supervisorNaturalMemoryPatchDecisionMatches(
        _ lhs: SupervisorDecisionTrackEvent,
        _ rhs: SupervisorDecisionTrackEvent
    ) -> Bool {
        let left = lhs.sanitizedForStorage
        let right = rhs.sanitizedForStorage
        return left.decisionId == right.decisionId &&
            left.projectId == right.projectId &&
            left.category == right.category &&
            left.status == right.status &&
            left.statement == right.statement &&
            left.source == right.source &&
            left.reversible == right.reversible &&
            left.approvalRequired == right.approvalRequired &&
            left.approvedBy == right.approvedBy &&
            left.evidenceRefs == right.evidenceRefs
    }

    private func supervisorNaturalMemoryPatchDecisionCategory(
        statement: String,
        reason: String?
    ) -> SupervisorDecisionCategory {
        let normalized = normalizedSupervisorIntentText(
            "\(statement)\n\(reason ?? "")"
        )
        if containsAny(
            normalized,
            ["技术栈", "tech stack", "swiftui", "swift package", "react", "vue", "grpc", "typescript", "python"]
        ) {
            return .techStack
        }
        if containsAny(
            normalized,
            ["范围", "scope", "mvp", "先不做", "不做", "冻结", "freeze", "里程碑"]
        ) {
            return .scopeFreeze
        }
        if containsAny(
            normalized,
            ["风险", "risk", "授权", "grant", "安全", "上线", "部署", "production", "prod"]
        ) {
            return .riskPosture
        }
        if containsAny(
            normalized,
            ["批准", "同意", "驳回", "reject", "approve"]
        ) {
            return .approvalResult
        }
        if containsAny(
            normalized,
            ["界面", "ui", "视觉", "排版", "风格", "design"]
        ) {
            return .uiStyle
        }
        return SupervisorDecisionCategory(rawValue: "execution_path")
    }

    private func supervisorNaturalMemoryPatchComposedBlockerSummary(
        blocker: String?,
        attemptedActions: [String]
    ) -> String {
        let primary = sanitizeSupervisorNaturalMemoryPatchValue(blocker ?? "")
        guard !primary.isEmpty else { return "" }
        guard !attemptedActions.isEmpty else { return primary }
        return "\(primary)；已试过：\(attemptedActions.joined(separator: "、"))"
    }

    private func supervisorNaturalMemoryPatchStableSuffix(_ stable: String) -> String {
        let digest = normalizedLookupKey(supervisorDeterministicDigest(stable: stable))
        return String(digest.suffix(16))
    }
}
