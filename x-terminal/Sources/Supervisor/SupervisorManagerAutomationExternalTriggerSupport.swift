import Foundation

extension SupervisorManager {
    @discardableResult
    func ingestAutomationExternalTrigger(
        _ ingress: SupervisorAutomationExternalTriggerIngress,
        emitSystemMessage: Bool = false
    ) -> SupervisorAutomationExternalTriggerResult {
        let projectId = ingress.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let triggerId = ingress.triggerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let auditRef = automationExternalTriggerAuditRef(
            projectId: projectId,
            triggerId: triggerId,
            now: ingress.receivedAt
        )

        guard !projectId.isEmpty else {
            return SupervisorAutomationExternalTriggerResult(
                projectId: "",
                triggerId: triggerId,
                triggerType: ingress.triggerType,
                decision: .failClosed,
                reasonCode: "project_id_missing",
                runId: nil,
                auditRef: auditRef
            )
        }

        guard let project = knownProjects().first(where: { $0.projectId == projectId }),
              let ctx = projectContext(from: project) else {
            return SupervisorAutomationExternalTriggerResult(
                projectId: projectId,
                triggerId: triggerId,
                triggerType: ingress.triggerType,
                decision: .failClosed,
                reasonCode: "project_context_missing",
                runId: nil,
                auditRef: auditRef
            )
        }

        return ingestAutomationExternalTrigger(
            ingress,
            for: project,
            ctx: ctx,
            auditRef: auditRef,
            emitSystemMessage: emitSystemMessage
        )
    }

    @discardableResult
    func serviceAutomationScheduleTriggers(
        now: Date = Date(),
        emitSystemMessage: Bool = false
    ) -> [SupervisorAutomationExternalTriggerResult] {
        let projects = knownProjects()
        guard !projects.isEmpty else { return [] }

        var results: [SupervisorAutomationExternalTriggerResult] = []
        for project in projects {
            guard let ctx = projectContext(from: project) else { continue }
            guard automationProjectHasBlockingRun(ctx) == false else { continue }
            guard let config = try? AXProjectStore.loadOrCreateConfig(for: ctx),
                  let recipe = config.activeAutomationRecipe,
                  recipe.lifecycleState == .ready else {
                continue
            }

            let scheduleTriggerIds = automationTriggerIds(from: recipe.triggerRefs, matching: .schedule)
            guard !scheduleTriggerIds.isEmpty else { continue }

            let projectToken = normalizedLookupKey(project.displayName).isEmpty
                ? normalizedLookupKey(project.projectId)
                : normalizedLookupKey(project.displayName)

            for triggerId in scheduleTriggerIds {
                let intervalSec = automationScheduleMinimumInterval(for: triggerId)
                let windowStart = Int(floor(now.timeIntervalSince1970 / Double(intervalSec)) * Double(intervalSec))
                let dedupeKey = automationExternalTriggerDeterministicDigest(
                    stable: "schedule|\(project.projectId)|\(triggerId)|\(windowStart)"
                )
                if automationExternalTriggerReplaySeen(
                    projectId: project.projectId,
                    dedupeKey: dedupeKey,
                    ctx: ctx
                ) {
                    continue
                }
                if let lastAcceptedAt = automationExternalTriggerLastAcceptedAt(
                    projectId: project.projectId,
                    triggerId: triggerId,
                    ctx: ctx
                ),
                   now.timeIntervalSince1970 - lastAcceptedAt < Double(intervalSec) {
                    continue
                }

                let triggerToken = xtAutomationActionToken(triggerId, fallback: "schedule")
                let ingress = SupervisorAutomationExternalTriggerIngress(
                    projectId: project.projectId,
                    triggerId: triggerId,
                    triggerType: .schedule,
                    source: .timer,
                    payloadRef: "local://supervisor/scheduler_poll/\(projectToken)/\(triggerToken)/\(windowStart)",
                    dedupeKey: dedupeKey,
                    receivedAt: now,
                    ingressChannel: "scheduler_poll"
                )
                let result = ingestAutomationExternalTrigger(
                    ingress,
                    for: project,
                    ctx: ctx,
                    auditRef: automationExternalTriggerAuditRef(
                        projectId: project.projectId,
                        triggerId: triggerId,
                        now: now
                    ),
                    emitSystemMessage: emitSystemMessage
                )
                results.append(result)
                if result.decision == .run {
                    break
                }
            }
        }

        return results
    }

    func recordAutomationExternalTriggerDecision(
        ingress: SupervisorAutomationExternalTriggerIngress,
        decision: SupervisorAutomationExternalTriggerDecision,
        reasonCode: String,
        runId: String?,
        auditRef: String,
        ctx: AXProjectContext,
        emitSystemMessage: Bool
    ) -> SupervisorAutomationExternalTriggerResult {
        let projectId = ingress.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let triggerId = ingress.triggerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let dedupeKey = ingress.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let acceptedAt = ingress.receivedAt.timeIntervalSince1970
        let projectDisplayName = projectDisplayName(for: ctx)

        appendAutomationExternalTriggerRouteLog(
            ingress: ingress,
            decision: decision,
            reasonCode: reasonCode,
            runId: runId,
            auditRef: auditRef,
            ctx: ctx
        )

        if decision != .hold, !dedupeKey.isEmpty {
            let replayKey = automationExternalTriggerReplayLedgerKey(projectId: projectId, dedupeKey: dedupeKey)
            automationExternalTriggerReplayLedger[replayKey] = max(
                acceptedAt,
                automationExternalTriggerReplayLedger[replayKey] ?? 0
            )
        }
        if decision == .run, !triggerId.isEmpty {
            let acceptedKey = automationExternalTriggerAcceptedLedgerKey(projectId: projectId, triggerId: triggerId)
            automationExternalTriggerAcceptedLedger[acceptedKey] = max(
                acceptedAt,
                automationExternalTriggerAcceptedLedger[acceptedKey] ?? 0
            )
            appendRecentEvent(
                "automation trigger run: \(projectDisplayName) -> \(triggerId)",
                projectId: projectId,
                projectName: projectDisplayName
            )
        } else if decision == .hold {
            appendRecentEvent(
                "automation trigger hold: \(projectDisplayName) -> \(triggerId) (\(reasonCode))",
                projectId: projectId,
                projectName: projectDisplayName
            )
        } else if decision == .failClosed {
            appendRecentEvent(
                "automation trigger fail-closed: \(projectDisplayName) -> \(triggerId) (\(reasonCode))",
                projectId: projectId,
                projectName: projectDisplayName
            )
        }

        if emitSystemMessage &&
            decision != .run &&
            ingress.ingressChannel != "hub_connector_receipt_snapshot" &&
            projectVisibleInCurrentSupervisorJurisdiction(projectId: projectId) {
            addSystemMessage(
                "automation 外部触发未执行：\(projectDisplayName) -> \(triggerId) (\(reasonCode))",
                projectId: projectId,
                projectName: projectDisplayName,
                requiresKnownProjectMatch: true
            )
        }

        return SupervisorAutomationExternalTriggerResult(
            projectId: projectId,
            triggerId: triggerId,
            triggerType: ingress.triggerType,
            decision: decision,
            reasonCode: reasonCode,
            runId: runId,
            auditRef: auditRef
        )
    }

    func ingestAutomationExternalTrigger(
        _ ingress: SupervisorAutomationExternalTriggerIngress,
        for project: AXProjectEntry,
        ctx: AXProjectContext,
        auditRef: String,
        emitSystemMessage: Bool
    ) -> SupervisorAutomationExternalTriggerResult {
        let projectId = project.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let triggerId = ingress.triggerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let dedupeKey = ingress.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = ingress.receivedAt

        func finalize(
            _ decision: SupervisorAutomationExternalTriggerDecision,
            reasonCode: String,
            runId: String? = nil
        ) -> SupervisorAutomationExternalTriggerResult {
            return recordAutomationExternalTriggerDecision(
                ingress: ingress,
                decision: decision,
                reasonCode: reasonCode,
                runId: runId,
                auditRef: auditRef,
                ctx: ctx,
                emitSystemMessage: emitSystemMessage
            )
        }

        primeAutomationExternalTriggerHistoryIfNeeded(projectId: projectId, ctx: ctx)

        guard !triggerId.isEmpty else {
            return finalize(.failClosed, reasonCode: "trigger_id_missing")
        }
        guard !dedupeKey.isEmpty || ingress.triggerType == .manual else {
            return finalize(.failClosed, reasonCode: "external_trigger_dedupe_key_missing")
        }
        if !dedupeKey.isEmpty,
           automationExternalTriggerReplaySeen(projectId: projectId, dedupeKey: dedupeKey, ctx: ctx) {
            return finalize(.drop, reasonCode: "external_trigger_replay_detected")
        }
        if automationProjectHasBlockingRun(ctx) {
            return finalize(.hold, reasonCode: "automation_active_run_present")
        }

        let cooldownWindowSec = automationTriggerCooldownWindowSeconds(
            triggerId: triggerId,
            triggerType: ingress.triggerType
        )
        if let lastAcceptedAt = automationExternalTriggerLastAcceptedAt(
            projectId: projectId,
            triggerId: triggerId,
            ctx: ctx
        ),
           now.timeIntervalSince1970 - lastAcceptedAt < Double(cooldownWindowSec) {
            return finalize(.drop, reasonCode: "trigger_cooldown_active")
        }

        do {
            let request = try makeExternalTriggerAutomationRunRequest(
                ctx: ctx,
                ingress: ingress
            )
            let prepared = try startAutomationRun(
                for: ctx,
                request: request,
                emitSystemMessage: emitSystemMessage
            )
            return finalize(.run, reasonCode: "trigger_route_allowed", runId: prepared.launchRef)
        } catch {
            return finalize(
                .failClosed,
                reasonCode: automationExternalTriggerReasonCode(from: error)
            )
        }
    }

    func automationTriggerIds(
        from triggerRefs: [String],
        matching triggerType: XTAutomationTriggerType? = nil
    ) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for ref in triggerRefs {
            let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let triggerId: String = {
                guard let separator = trimmed.lastIndex(of: ":") else { return trimmed }
                let suffix = trimmed[trimmed.index(after: separator)...]
                return String(suffix).trimmingCharacters(in: .whitespacesAndNewlines)
            }()
            guard !triggerId.isEmpty else { continue }
            if let triggerType {
                let prefix = "\(triggerType.rawValue)/"
                if triggerId != triggerType.rawValue && !triggerId.hasPrefix(prefix) {
                    continue
                }
            }
            if seen.insert(triggerId).inserted {
                ordered.append(triggerId)
            }
        }
        return ordered
    }

    private func makeExternalTriggerAutomationRunRequest(
        ctx: AXProjectContext,
        ingress: SupervisorAutomationExternalTriggerIngress
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

        let triggerId = ingress.triggerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requiresGrant = ingress.requiresGrant ?? !recipe.grantPolicyRef.isEmpty
        let preferredPolicyRef = ingress.policyRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let policyRef = requiresGrant
            ? (preferredPolicyRef.isEmpty ? recipe.grantPolicyRef : preferredPolicyRef)
            : ""
        let triggerToken = xtAutomationActionToken(triggerId, fallback: ingress.triggerType.rawValue)
        let triggerClass = xtAutomationActionToken(ingress.triggerType.rawValue, fallback: "trigger")

        return XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: triggerId,
                    triggerType: ingress.triggerType,
                    source: ingress.source,
                    payloadRef: ingress.payloadRef,
                    requiresGrant: requiresGrant,
                    policyRef: policyRef,
                    dedupeKey: ingress.dedupeKey
                )
            ],
            trustedAutomationReady: trustedAutomationStatus.trustedAutomationReady,
            permissionOwnerReady: trustedAutomationStatus.permissionOwnerReady,
            currentOwner: trustedAutomationStatus.permissionOwnerReady ? "XT-TRUSTED" : "XT-L2",
            blockedTaskID: "XT-AUTO-TRIGGER-\(triggerClass.uppercased())",
            operatorConsoleEvidenceRef: "build/reports/xt_auto_\(triggerClass)_trigger_operator_console.v1.json",
            latestDeltaRef: "build/reports/xt_auto_\(triggerClass)_trigger_delta.v1.json",
            deliveryRef: "build/reports/xt_auto_\(triggerClass)_trigger_delivery.v1.json",
            additionalEvidenceRefs: [
                "trigger://\(ingress.ingressChannel)/\(triggerClass)/\(triggerToken)",
                "payload://\(ingress.payloadRef)",
                "dedupe://\(ingress.dedupeKey)"
            ] + trustedAutomationStatus.missingPrerequisites.map {
                "trusted_automation_issue://\($0)"
            },
            now: ingress.receivedAt
        )
    }

    private func automationScheduleMinimumInterval(for triggerId: String) -> Int {
        let lowered = triggerId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.contains("weekly") {
            return 7 * 24 * 60 * 60
        }
        if lowered.contains("nightly") || lowered.contains("daily") {
            return 24 * 60 * 60
        }
        if lowered.contains("hourly") {
            return 60 * 60
        }
        if lowered.contains("minutely") {
            return 60
        }
        return max(automationDefaultTriggerCooldownSeconds(for: .schedule), 300)
    }

    private func automationTriggerCooldownWindowSeconds(
        triggerId: String,
        triggerType: XTAutomationTriggerType
    ) -> Int {
        switch triggerType {
        case .schedule:
            return max(automationDefaultTriggerCooldownSeconds(for: .schedule), automationScheduleMinimumInterval(for: triggerId))
        case .webhook, .connectorEvent, .manual:
            return automationDefaultTriggerCooldownSeconds(for: triggerType)
        }
    }

    private func automationDefaultTriggerCooldownSeconds(
        for triggerType: XTAutomationTriggerType
    ) -> Int {
        switch triggerType {
        case .schedule:
            return 300
        case .webhook:
            return 30
        case .connectorEvent:
            return 45
        case .manual:
            return 0
        }
    }

    func automationExternalTriggerAuditRef(
        projectId: String,
        triggerId: String,
        now: Date
    ) -> String {
        let projectToken = xtAutomationActionToken(projectId, fallback: "project")
        let triggerToken = xtAutomationActionToken(triggerId, fallback: "trigger")
        return "audit-xt-auto-trigger-\(projectToken)-\(triggerToken)-\(Int(now.timeIntervalSince1970))"
    }

    private func primeAutomationExternalTriggerHistoryIfNeeded(projectId: String, ctx: AXProjectContext) {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectId.isEmpty else { return }
        guard automationExternalTriggerHistoryLoadedProjects.contains(normalizedProjectId) == false else { return }

        for row in automationRawLogEntries(for: ctx) {
            guard (row["type"] as? String) == "automation_external_trigger_route" else { continue }
            let decisionRaw = (row["decision"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if decisionRaw == SupervisorAutomationExternalTriggerDecision.hold.rawValue {
                continue
            }
            let createdAt = row["created_at"] as? Double ?? 0
            let triggerId = (row["trigger_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let dedupeKey = (row["dedupe_key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !dedupeKey.isEmpty {
                let key = automationExternalTriggerReplayLedgerKey(projectId: normalizedProjectId, dedupeKey: dedupeKey)
                automationExternalTriggerReplayLedger[key] = max(createdAt, automationExternalTriggerReplayLedger[key] ?? 0)
            }
            if decisionRaw == SupervisorAutomationExternalTriggerDecision.run.rawValue, !triggerId.isEmpty {
                let key = automationExternalTriggerAcceptedLedgerKey(projectId: normalizedProjectId, triggerId: triggerId)
                automationExternalTriggerAcceptedLedger[key] = max(createdAt, automationExternalTriggerAcceptedLedger[key] ?? 0)
            }
        }

        automationExternalTriggerHistoryLoadedProjects.insert(normalizedProjectId)
    }

    func automationExternalTriggerReplaySeen(
        projectId: String,
        dedupeKey: String,
        ctx: AXProjectContext
    ) -> Bool {
        primeAutomationExternalTriggerHistoryIfNeeded(projectId: projectId, ctx: ctx)
        let key = automationExternalTriggerReplayLedgerKey(projectId: projectId, dedupeKey: dedupeKey)
        return automationExternalTriggerReplayLedger[key] != nil
    }

    private func automationExternalTriggerLastAcceptedAt(
        projectId: String,
        triggerId: String,
        ctx: AXProjectContext
    ) -> TimeInterval? {
        primeAutomationExternalTriggerHistoryIfNeeded(projectId: projectId, ctx: ctx)
        let key = automationExternalTriggerAcceptedLedgerKey(projectId: projectId, triggerId: triggerId)
        return automationExternalTriggerAcceptedLedger[key]
    }

    private func appendAutomationExternalTriggerRouteLog(
        ingress: SupervisorAutomationExternalTriggerIngress,
        decision: SupervisorAutomationExternalTriggerDecision,
        reasonCode: String,
        runId: String?,
        auditRef: String,
        ctx: AXProjectContext
    ) {
        AXProjectStore.appendRawLog(
            [
                "type": "automation_external_trigger_route",
                "created_at": ingress.receivedAt.timeIntervalSince1970,
                "trigger_id": ingress.triggerId,
                "trigger_type": ingress.triggerType.rawValue,
                "source": ingress.source.rawValue,
                "ingress_channel": ingress.ingressChannel,
                "payload_ref": ingress.payloadRef,
                "dedupe_key": ingress.dedupeKey,
                "cooldown_sec": automationTriggerCooldownWindowSeconds(
                    triggerId: ingress.triggerId,
                    triggerType: ingress.triggerType
                ),
                "decision": decision.rawValue,
                "reason_code": reasonCode,
                "run_id": runId ?? NSNull(),
                "external_trigger_ingress_schema_version": XTAutomationExternalTriggerIngressEnvelope.currentSchemaVersion,
                "audit_ref": auditRef
            ],
            for: ctx
        )
    }

    func automationExternalTriggerReasonCode(from error: Error) -> String {
        if let coordinatorError = error as? XTAutomationRunCoordinatorError {
            switch coordinatorError {
            case .activeRecipeMissing:
                return "active_recipe_missing"
            case .triggerSeedsMissing:
                return "trigger_seeds_missing"
            case .triggerIngressNotAllowed:
                return "trigger_ingress_not_allowed"
            case .triggerIngressReplayDetected:
                return "external_trigger_replay_detected"
            case .triggerIngressPolicyMissing:
                return "trigger_ingress_policy_missing"
            case .runNotFound:
                return "run_not_found"
            }
        }
        if let runtimeError = error as? SupervisorAutomationRuntimeError {
            switch runtimeError {
            case .projectSelectionMissing:
                return "project_selection_missing"
            case .projectNotFound:
                return "project_not_found"
            case .projectAmbiguous:
                return "project_ambiguous"
            case .projectContextMissing:
                return "project_context_missing"
            }
        }
        return "automation_external_trigger_failed_closed"
    }

    func automationProjectHasBlockingRun(_ ctx: AXProjectContext) -> Bool {
        guard let runId = effectiveAutomationRunRef(
                for: ctx,
                allowedStates: automationBlockingRunStates
              ),
              let checkpoint = try? automationRunCoordinator.latestCheckpoint(for: runId, in: ctx) else {
            return false
        }

        switch checkpoint.state {
        case .queued, .running, .blocked, .takeover:
            return true
        case .delivered, .failed, .downgraded:
            return false
        }
    }

    private func automationRawLogEntries(for ctx: AXProjectContext) -> [[String: Any]] {
        xtAutomationReadRawLogRows(for: ctx)
    }
}
