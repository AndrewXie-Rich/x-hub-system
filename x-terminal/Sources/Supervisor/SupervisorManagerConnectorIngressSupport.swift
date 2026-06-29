import Foundation

extension SupervisorManager {
    @discardableResult
    func serviceHubConnectorIngressReceiptsForTesting(
        _ snapshot: HubIPCClient.ConnectorIngressSnapshot,
        now: Date = Date(),
        emitSystemMessage: Bool = false
    ) -> [SupervisorAutomationExternalTriggerResult] {
        connectorIngressSnapshot = snapshot
        connectorIngressLastSuccessAt = max(now.timeIntervalSince1970, snapshot.updatedAtMs / 1000.0)
        return serviceHubConnectorIngressReceipts(now: now, emitSystemMessage: emitSystemMessage)
    }

    @discardableResult
    func serviceHubConnectorIngressReceipts(
        now: Date = Date(),
        emitSystemMessage: Bool = false
    ) -> [SupervisorAutomationExternalTriggerResult] {
        guard let snapshot = connectorIngressSnapshot else { return [] }

        let snapshotUpdatedAtSec: TimeInterval = {
            let ms = max(0, snapshot.updatedAtMs)
            if ms > 0 {
                return ms / 1000.0
            }
            return connectorIngressLastSuccessAt
        }()
        if snapshotUpdatedAtSec > 0, now.timeIntervalSince1970 - snapshotUpdatedAtSec > schedulerSnapshotStaleSec {
            return []
        }

        let projectMap = knownProjects().reduce(into: [String: AXProjectEntry]()) { partialResult, project in
            partialResult[project.projectId] = project
        }
        guard !projectMap.isEmpty else { return [] }

        let receipts = snapshot.items.sorted { lhs, rhs in
            if lhs.receivedAtMs != rhs.receivedAtMs {
                return lhs.receivedAtMs < rhs.receivedAtMs
            }
            return lhs.receiptId.localizedCaseInsensitiveCompare(rhs.receiptId) == .orderedAscending
        }

        var results: [SupervisorAutomationExternalTriggerResult] = []
        var blockedProjects: Set<String> = []

        for receipt in receipts {
            let projectId = receipt.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !projectId.isEmpty else { continue }
            guard blockedProjects.contains(projectId) == false else { continue }
            guard let project = projectMap[projectId],
                  let ctx = projectContext(from: project) else {
                continue
            }
            let dedupeKey = hubConnectorIngressDedupeKey(for: receipt)
            if automationExternalTriggerReplaySeen(
                projectId: projectId,
                dedupeKey: dedupeKey,
                ctx: ctx
            ) {
                continue
            }
            let resolution = resolveHubConnectorIngressReceipt(receipt, ctx: ctx, fallbackNow: now)
            switch resolution {
            case .route(let ingress):
                let result = ingestAutomationExternalTrigger(
                    ingress,
                    for: project,
                    ctx: ctx,
                    auditRef: automationExternalTriggerAuditRef(
                        projectId: projectId,
                        triggerId: ingress.triggerId,
                        now: ingress.receivedAt
                    ),
                    emitSystemMessage: emitSystemMessage
                )
                results.append(result)
                announceHubConnectorIngressReceiptResult(
                    receipt,
                    result: result,
                    projectName: project.displayName
                )
                if result.decision == .run || result.decision == .hold {
                    blockedProjects.insert(projectId)
                }
            case .failClosed(let ingress, let reasonCode):
                let result = recordAutomationExternalTriggerDecision(
                    ingress: ingress,
                    decision: .failClosed,
                    reasonCode: reasonCode,
                    runId: nil,
                    auditRef: automationExternalTriggerAuditRef(
                        projectId: projectId,
                        triggerId: ingress.triggerId,
                        now: ingress.receivedAt
                    ),
                    ctx: ctx,
                    emitSystemMessage: emitSystemMessage
                )
                results.append(result)
                announceHubConnectorIngressReceiptResult(
                    receipt,
                    result: result,
                    projectName: project.displayName
                )
            }
        }

        return results
    }

    func announceHubConnectorIngressReceiptResult(
        _ receipt: HubIPCClient.ConnectorIngressReceipt,
        result: SupervisorAutomationExternalTriggerResult,
        projectName: String
    ) {
        let provider = remoteChannelProviderDisplayName(receipt.connector)
        let projectToken = operatorChannelProjectDisplayName(projectName, projectID: result.projectId)
        let ingress = hubConnectorIngressDisplayName(receipt, triggerType: result.triggerType)
        let reasonToken = result.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasonDisplay = hubConnectorIngressReasonDisplayName(reasonToken)
        let reasonSummary = annotatedUserVisibleReason(
            raw: reasonToken,
            display: reasonDisplay,
            fallback: "未知原因"
        )

        let systemMessage: String
        let voiceText: String
        let title: String
        let body: String
        let voiceTrigger: SupervisorVoiceJobTrigger
        let voicePriority: SupervisorVoiceJobPriority

        switch result.decision {
        case .run:
            let runToken = result.runId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            systemMessage = "已接收来自 \(provider) 的 Hub 入口：\(projectToken) -> \(ingress) 已转入 XT automation（run=\(runToken.isEmpty ? "n/a" : runToken)）。"
            voiceText = "\(provider) 的远程入口我已经接进 XT 继续处理了。项目是 \(projectToken)，入口是\(ingress)。"
            title = "🛰️ \(provider) 入口已转入 XT"
            body = """
项目=\(projectToken)
入口=\(ingress)
决策=\(result.decision.rawValue)
运行=\(runToken.isEmpty ? "n/a" : runToken)
审计=\(result.auditRef)
"""
            voiceTrigger = .completed
            voicePriority = .normal
        case .hold:
            let voiceReason = reasonDisplay.isEmpty ? "项目已有进行中的 automation" : reasonDisplay
            systemMessage = "来自 \(provider) 的 Hub 入口暂缓：\(projectToken) -> \(ingress)。原因：\(reasonSummary)。"
            voiceText = "\(provider) 的远程入口我先暂缓了。\(projectToken) 这边还有自动流程在跑。原因：\(voiceReason)。"
            title = "⏸️ \(provider) 入口在 XT 暂缓"
            body = """
项目=\(projectToken)
入口=\(ingress)
决策=\(result.decision.rawValue)
原因=\(reasonSummary)
审计=\(result.auditRef)
"""
            voiceTrigger = .blocked
            voicePriority = .interrupt
        case .failClosed:
            systemMessage = "来自 \(provider) 的 Hub 入口失败闭锁：\(projectToken) -> \(ingress)。原因：\(reasonSummary)。"
            voiceText = "\(provider) 的远程入口我先按失败闭锁拦下了。\(projectToken) 暂时不能接这个\(ingress)。原因：\(reasonDisplay)。"
            title = "⛔️ \(provider) 入口在 XT 失败闭锁"
            body = """
项目=\(projectToken)
入口=\(ingress)
决策=\(result.decision.rawValue)
原因=\(reasonSummary)
审计=\(result.auditRef)
"""
            voiceTrigger = .blocked
            voicePriority = .interrupt
        case .drop:
            return
        }

        guard projectVisibleInCurrentSupervisorJurisdiction(projectId: result.projectId) else { return }

        addSystemMessage(
            systemMessage,
            projectId: result.projectId,
            projectName: projectName,
            requiresKnownProjectMatch: true
        )
        _ = speakHubConnectorIngressUpdate(
            text: voiceText,
            trigger: voiceTrigger,
            priority: voicePriority,
            receiptId: receipt.receiptId,
            detailToken: result.runId ?? reasonToken
        )

        guard backgroundSupervisorServicesEnabled else { return }
        let dedupeKey = "x_terminal_hub_connector_ingress_\(receipt.receiptId)_\(result.decision.rawValue)_\(reasonToken)"
        let actionURL = resumeProjectActionURL(projectId: result.projectId)
        guard shouldMirrorNotificationToHub(actionURL: actionURL) else {
            HubIPCClient.removeNotification(dedupeKey: dedupeKey)
            return
        }
        HubIPCClient.pushNotification(
            source: "X-Terminal",
            title: title,
            body: body,
            dedupeKey: dedupeKey,
            actionURL: actionURL,
            unread: true
        )
    }

    @discardableResult
    func speakHubConnectorIngressUpdate(
        text: String,
        trigger: SupervisorVoiceJobTrigger,
        priority: SupervisorVoiceJobPriority,
        receiptId: String,
        detailToken: String
    ) -> SupervisorSpeechSynthesizer.Outcome {
        let script = conciseVoiceReplyScript(text)
        guard !script.isEmpty else { return .suppressed("empty_script") }
        let detail = detailToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let dedupeKey = "connector-ingress:\(receiptId):\(trigger.rawValue):\(detail.isEmpty ? "none" : detail)"
        let job = SupervisorVoiceTTSJob(
            trigger: trigger,
            priority: priority,
            script: script,
            dedupeKey: dedupeKey
        )
        return dispatchSupervisorVoiceJob(
            job,
            preferences: currentVoicePreferences(),
            source: "connector_ingress:\(receiptId)",
            suppressRapidSameSourceRepeat: true,
            cancelPendingHeartbeat: true
        )
    }

    func resolveHubConnectorIngressReceipt(
        _ receipt: HubIPCClient.ConnectorIngressReceipt,
        ctx: AXProjectContext,
        fallbackNow: Date
    ) -> HubConnectorIngressResolution {
        let projectId = receipt.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let triggerType = hubConnectorIngressTriggerType(for: receipt)
        let receivedAt = hubConnectorIngressReceivedAt(receipt, fallbackNow: fallbackNow)
        let payloadRef = hubConnectorIngressPayloadRef(for: receipt)
        let dedupeKey = hubConnectorIngressDedupeKey(for: receipt)
        let resolvedSource = hubConnectorIngressSource(for: receipt.connector)
        let fallbackIngress = SupervisorAutomationExternalTriggerIngress(
            projectId: projectId,
            triggerId: hubConnectorIngressFallbackTriggerId(for: receipt),
            triggerType: triggerType,
            source: resolvedSource ?? .hub,
            payloadRef: payloadRef,
            dedupeKey: dedupeKey,
            receivedAt: receivedAt,
            ingressChannel: "hub_connector_receipt_snapshot"
        )

        guard let source = resolvedSource else {
            return .failClosed(fallbackIngress, "hub_ingress_source_unsupported")
        }
        guard let config = try? AXProjectStore.loadOrCreateConfig(for: ctx),
              let recipe = config.activeAutomationRecipe,
              recipe.lifecycleState == .ready else {
            return .failClosed(fallbackIngress, "hub_ingress_recipe_unavailable")
        }

        let candidates = automationTriggerIds(from: recipe.triggerRefs, matching: triggerType)
        guard let triggerId = resolveHubConnectorTriggerID(
            candidates: candidates,
            connector: receipt.connector,
            channelScope: receipt.channelScope,
            targetId: receipt.targetId,
            sourceId: receipt.sourceId
        ) else {
            return .failClosed(fallbackIngress, "hub_ingress_trigger_unresolved")
        }

        return .route(
            SupervisorAutomationExternalTriggerIngress(
                projectId: projectId,
                triggerId: triggerId,
                triggerType: triggerType,
                source: source,
                payloadRef: payloadRef,
                dedupeKey: dedupeKey,
                receivedAt: receivedAt,
                ingressChannel: "hub_connector_receipt_snapshot"
            )
        )
    }

    func hubConnectorIngressDedupeKey(
        for receipt: HubIPCClient.ConnectorIngressReceipt
    ) -> String {
        let provided = receipt.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !provided.isEmpty {
            return provided
        }
        return automationExternalTriggerDeterministicDigest(
            stable: [
                "hub_connector_receipt",
                receipt.receiptId,
                receipt.projectId,
                receipt.connector,
                receipt.messageId,
                receipt.sourceId,
            ].joined(separator: "|")
        )
    }

    func hubConnectorIngressTriggerType(
        for receipt: HubIPCClient.ConnectorIngressReceipt
    ) -> XTAutomationTriggerType {
        normalizedLookupKey(receipt.ingressType) == XTAutomationTriggerType.webhook.rawValue
            ? .webhook
            : .connectorEvent
    }

    func hubConnectorIngressSource(for connector: String) -> XTAutomationTriggerSource? {
        switch normalizedLookupKey(connector) {
        case XTAutomationTriggerSource.github.rawValue:
            return .github
        case XTAutomationTriggerSource.slack.rawValue:
            return .slack
        case XTAutomationTriggerSource.telegram.rawValue:
            return .telegram
        default:
            return nil
        }
    }

    func hubConnectorIngressReceivedAt(
        _ receipt: HubIPCClient.ConnectorIngressReceipt,
        fallbackNow: Date
    ) -> Date {
        let receivedAtMs = max(0, receipt.receivedAtMs)
        guard receivedAtMs > 0 else { return fallbackNow }
        return Date(timeIntervalSince1970: receivedAtMs / 1000.0)
    }

    func hubConnectorIngressPayloadRef(
        for receipt: HubIPCClient.ConnectorIngressReceipt
    ) -> String {
        let connectorToken = xtAutomationActionToken(receipt.connector, fallback: "connector")
        let receiptToken = xtAutomationActionToken(receipt.receiptId, fallback: "receipt")
        return "hub://connector_ingress/\(connectorToken)/\(receiptToken)"
    }

    func hubConnectorIngressFallbackTriggerId(
        for receipt: HubIPCClient.ConnectorIngressReceipt
    ) -> String {
        let connectorToken = xtAutomationActionToken(receipt.connector, fallback: "connector")
        let receiptToken = xtAutomationActionToken(receipt.receiptId, fallback: "receipt")
        return "hub_receipt/\(connectorToken)/\(receiptToken)"
    }

    func resolveHubConnectorTriggerID(
        candidates: [String],
        connector: String,
        channelScope: String,
        targetId: String,
        sourceId: String
    ) -> String? {
        let normalizedCandidates = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedCandidates.isEmpty else { return nil }
        if normalizedCandidates.count == 1 {
            return normalizedCandidates[0]
        }

        let connectorToken = normalizedLookupKey(connector)
        let channelToken = normalizedLookupKey(channelScope)
        let targetToken = normalizedLookupKey(targetId)
        let sourceToken = normalizedLookupKey(sourceId)

        let scored = normalizedCandidates.map { candidate -> (candidate: String, score: Int) in
            let key = normalizedLookupKey(candidate)
            var score = 0
            if !connectorToken.isEmpty, key.contains(connectorToken) {
                score += 8
            }
            if !channelToken.isEmpty, key.contains(channelToken) {
                score += 4
            }
            if !targetToken.isEmpty, key.contains(targetToken) {
                score += 2
            }
            if !sourceToken.isEmpty, key.contains(sourceToken) {
                score += 1
            }
            return (candidate, score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.candidate.localizedCaseInsensitiveCompare(rhs.candidate) == .orderedAscending
        }

        guard let best = scored.first, best.score > 0 else { return nil }
        if scored.count > 1, best.score == scored[1].score {
            return nil
        }
        return best.candidate
    }
}
