import Foundation

extension SupervisorManager {
    func latestCanonicalMemorySyncFailureAt() -> TimeInterval? {
        let items = HubIPCClient.canonicalMemorySyncStatusSnapshot(limit: 500)?.items ?? []
        guard let updatedAtMs = items
            .filter({ !$0.ok })
            .map(\.updatedAtMs)
            .max(),
              updatedAtMs > 0 else {
            return nil
        }
        return TimeInterval(updatedAtMs) / 1000.0
    }

    func supervisorSelfObservationSnapshot(
        messages sourceMessages: [SupervisorMessage]
    ) -> SupervisorSelfObservationSnapshot {
        let recentAssistantReplies = orderedUniqueSupervisorRefs(
            sourceMessages.reversed().compactMap { message in
                guard message.role == .assistant else { return nil }
                return firstNonEmptyLine(in: message.content)
            }
        )
        let latestHeartbeat = heartbeatHistory.first
        let latestHeartbeatSummary = latestHeartbeat.map {
            capped(firstNonEmptyLine(in: $0.content), maxChars: 150)
        } ?? ""
        let latestRuntimeActivity = runtimeActivityEntries.first.map {
            capped($0.text, maxChars: 150)
        } ?? ""
        let latestActionSummary = actionLedger.reversed().first.map { entry in
            [
                "action=\(entry.action)",
                entry.targetRef.isEmpty ? "" : "target=\(entry.targetRef)",
                "status=\(entry.status)",
                "reason=\(entry.reasonCode)",
                entry.detail.isEmpty ? "" : "detail=\(capped(entry.detail, maxChars: 120))"
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        } ?? ""
        return SupervisorSelfObservationSnapshot(
            recentAssistantReplies: Array(recentAssistantReplies.prefix(4)),
            latestHeartbeatReason: latestHeartbeat?.reason ?? "",
            latestHeartbeatSummary: latestHeartbeatSummary,
            latestRuntimeActivity: latestRuntimeActivity,
            latestActionSummary: latestActionSummary
        )
    }

    func renderSupervisorSelfObservationPromptBlock(
        messages sourceMessages: [SupervisorMessage]
    ) -> String {
        let snapshot = supervisorSelfObservationSnapshot(messages: sourceMessages)
        var lines = [
            "source=xt_runtime_projection",
            "truth_boundary=short_term_self_observation_only; Hub remains authority for memory/skills/model routing/grants/quota/audit.",
            "instruction=Before replying, compare with recent own replies/actions. Do not repeat prior confirmations or heartbeat progress verbatim; if nothing changed, say it was already handled and point to heartbeat/project chat."
        ]
        if !snapshot.recentAssistantReplies.isEmpty {
            lines.append("recent_own_replies:")
            lines.append(contentsOf: snapshot.recentAssistantReplies.map {
                "- \(sanitizeSupervisorPromptIdentifiers(capped($0, maxChars: 130)))"
            })
        }
        if !snapshot.latestHeartbeatSummary.isEmpty {
            let reason = snapshot.latestHeartbeatReason.isEmpty ? "unknown" : snapshot.latestHeartbeatReason
            lines.append("latest_heartbeat: reason=\(reason) summary=\(sanitizeSupervisorPromptIdentifiers(snapshot.latestHeartbeatSummary))")
        }
        if !snapshot.latestRuntimeActivity.isEmpty {
            lines.append("latest_runtime_activity: \(sanitizeSupervisorPromptIdentifiers(snapshot.latestRuntimeActivity))")
        }
        if !snapshot.latestActionSummary.isEmpty {
            lines.append("latest_action: \(sanitizeSupervisorPromptIdentifiers(capped(snapshot.latestActionSummary, maxChars: 180)))")
        }
        return lines.joined(separator: "\n")
    }

    func focusedProjectTranscriptObservationBlock(
        selection: SupervisorFocusedProjectSelection?
    ) -> String {
        guard let appModel, let selection else { return "" }
        let project = selection.project
        let ctx = supervisorMemoryContext(for: project)
        let session = appModel.session(for: ctx)
        session.ensureLoaded(ctx: ctx, limit: 200)
        let projection = XTProjectTranscriptProjection.build(
            projectId: project.projectId,
            projectName: project.displayName,
            messages: session.messages,
            pendingToolCallCount: session.pendingToolCalls.count,
            isSending: session.isSending,
            lastError: session.lastError
        )
        guard projection.hasUsefulContent else { return "" }
        return projection.promptBlock()
    }

    func supervisorAssistantReplyAfterSelfObservationGuard(
        _ response: String,
        context: SupervisorAfterTurnLifecycleContext
    ) -> String {
        guard context.triggerSource == .userTurn,
              !context.triggeredByVoice,
              !supervisorUserExplicitlyRequestedRepeat(context.userMessage),
              supervisorAssistantReplyLooksLikeRecentDuplicate(response) else {
            return response
        }
        let focusedProjectName = context.turnRoutingDecision?.focusedProjectName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !focusedProjectName.isEmpty {
            return "这点我刚才已经说过；当前没有观察到《\(focusedProjectName)》的新状态变化。进展看心跳和项目聊天。"
        }
        return "这点我刚才已经说过；当前没有新的状态变化。进展看心跳和项目聊天。"
    }

    func supervisorUserExplicitlyRequestedRepeat(_ userMessage: String) -> Bool {
        let normalized = normalizedSupervisorIntentText(userMessage)
            .replacingOccurrences(of: " ", with: "")
        return containsAny(
            normalized,
            ["重复一遍", "再说一遍", "重新说一遍", "原文", "照着", "repeat", "verbatim"]
        )
    }

    func supervisorAssistantReplyLooksLikeRecentDuplicate(_ response: String) -> Bool {
        let fingerprint = supervisorSelfObservationReplyFingerprint(response)
        guard fingerprint.count >= 24 else { return false }
        var inspected = 0
        for message in messages.reversed() where message.role == .assistant {
            let previous = supervisorSelfObservationReplyFingerprint(message.content)
            guard previous.count >= 24 else { continue }
            inspected += 1
            if supervisorSelfObservationFingerprintsLookDuplicate(fingerprint, previous) {
                return true
            }
            if inspected >= 6 {
                break
            }
        }
        return false
    }

    func supervisorSelfObservationReplyFingerprint(_ text: String) -> String {
        normalizedLookupKey(text)
    }

    func supervisorSelfObservationFingerprintsLookDuplicate(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        if lhs == rhs {
            return true
        }
        guard lhs.count >= 80, rhs.count >= 80 else {
            return false
        }
        let shorter = lhs.count <= rhs.count ? lhs : rhs
        let longer = lhs.count <= rhs.count ? rhs : lhs
        guard Double(shorter.count) / Double(longer.count) >= 0.82 else {
            return false
        }
        return longer.contains(shorter)
    }
}
