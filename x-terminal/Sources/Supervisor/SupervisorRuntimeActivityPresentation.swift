import Foundation

struct SupervisorRuntimeActivityRowPresentation: Equatable, Identifiable {
    var id: String
    var timeText: String
    var text: String
    var blockedSummaryText: String?
    var governanceTruthText: String?
    var governanceReasonText: String?
    var policyReasonText: String?
    var contractText: String?
    var nextSafeActionText: String?
    var actionDescriptors: [SupervisorCardActionDescriptor]
    var showsDivider: Bool
}

struct SupervisorRuntimeActivityBoardPresentation: Equatable {
    var iconName: String
    var iconTone: SupervisorHeaderControlTone
    var title: String
    var countText: String
    var emptyStateText: String?
    var rows: [SupervisorRuntimeActivityRowPresentation]

    var isEmpty: Bool {
        rows.isEmpty
    }
}

enum SupervisorRuntimeActivityPresentation {
    static func map(
        entries: [SupervisorManager.RuntimeActivityEntry],
        limit: Int = 8,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> SupervisorRuntimeActivityBoardPresentation {
        let displayedEntries = Array(entries.prefix(limit))
        return SupervisorRuntimeActivityBoardPresentation(
            iconName: displayedEntries.isEmpty
                ? "list.bullet.rectangle"
                : "list.bullet.rectangle.fill",
            iconTone: displayedEntries.isEmpty ? .neutral : .accent,
            title: "运行动态",
            countText: "\(entries.count) 条",
            emptyStateText: displayedEntries.isEmpty
                ? "当前还没有新的运行动态。后台事件、skill 失败、语音播放回退和治理侧告警会收敛到这里，不再插进聊天。"
                : nil,
            rows: displayedEntries.enumerated().map { index, entry in
                let contract = guidanceContract(for: entry.text)
                return SupervisorRuntimeActivityRowPresentation(
                    id: entry.id,
                    timeText: timeText(
                        entry.createdAt,
                        timeZone: timeZone,
                        locale: locale
                    ),
                    text: entry.text,
                    blockedSummaryText: blockedSummaryText(for: entry.text),
                    governanceTruthText: governanceTruthText(for: entry.text),
                    governanceReasonText: governanceReasonText(for: entry.text),
                    policyReasonText: policyReasonText(for: entry.text),
                    contractText: contract.map(SupervisorGuidanceContractLinePresentation.contractLine),
                    nextSafeActionText: contract.map(SupervisorGuidanceContractLinePresentation.nextSafeActionLine),
                    actionDescriptors: actionDescriptors(for: contract),
                    showsDivider: index < displayedEntries.count - 1
                )
            }
        )
    }

    static func timeText(
        _ timestamp: Double,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    static func guidanceContract(
        for text: String
    ) -> SupervisorGuidanceContractSummary? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.lowercased()
        let spaceTokens = keyValueTokens(trimmed, separators: CharacterSet(charactersIn: " "))
        let dotTokens = keyValueTokens(trimmed, separators: CharacterSet(charactersIn: "·"))

        if normalized.hasPrefix("voice_dispatch ") || normalized.hasPrefix("voice_playback ") {
            let reason = normalizedToken(spaceTokens["reason"])
            let state = normalizedToken(spaceTokens["state"])
            if let reason, isGrantReason(reason) {
                return SupervisorGuidanceContractSummary(
                    kind: .grantResolution,
                    trigger: normalized.hasPrefix("voice_dispatch ") ? "Voice Dispatch" : "Voice Playback",
                    reviewLevel: "",
                    verdict: "",
                    summary: trimmed,
                    primaryBlocker: reason,
                    currentState: state ?? "",
                    nextStep: "",
                    nextSafeAction: "open_hub_grants",
                    recommendedActions: [],
                    workOrderRef: "",
                    effectiveSupervisorTier: "",
                    effectiveWorkOrderDepth: ""
                )
            }

            if state == "failed",
               let reason, !reason.isEmpty {
                return SupervisorGuidanceContractSummary(
                    kind: .incidentRecovery,
                    trigger: normalized.hasPrefix("voice_dispatch ") ? "Voice Dispatch" : "Voice Playback",
                    reviewLevel: "",
                    verdict: "",
                    summary: trimmed,
                    primaryBlocker: reason,
                    currentState: state ?? "",
                    nextStep: "",
                    nextSafeAction: "inspect_incident_and_replan",
                    recommendedActions: [],
                    workOrderRef: "",
                    effectiveSupervisorTier: "",
                    effectiveWorkOrderDepth: ""
                )
            }
        }

        if normalized.hasPrefix("after_turn "),
           normalized.contains("project_memory_failed") {
            return SupervisorGuidanceContractSummary(
                kind: .incidentRecovery,
                trigger: "After Turn",
                reviewLevel: "",
                verdict: "",
                summary: normalizedToken(dotTokens["error"]) ?? trimmed,
                primaryBlocker: "project_memory_failed",
                currentState: "",
                nextStep: "",
                nextSafeAction: "inspect_incident_and_replan",
                recommendedActions: [],
                workOrderRef: "",
                effectiveSupervisorTier: "",
                effectiveWorkOrderDepth: ""
            )
        }

        if normalized.contains("failed closed")
            || normalized.contains("fail_closed") {
            return SupervisorGuidanceContractSummary(
                kind: .incidentRecovery,
                trigger: "Runtime",
                reviewLevel: "",
                verdict: "",
                summary: trimmed,
                primaryBlocker: "failed_closed",
                currentState: "",
                nextStep: "",
                nextSafeAction: "inspect_incident_and_replan",
                recommendedActions: [],
                workOrderRef: "",
                effectiveSupervisorTier: "",
                effectiveWorkOrderDepth: ""
            )
        }

        if normalized.contains("awaiting grant")
            || normalized.contains("grant pending")
            || normalized.contains("等待授权") {
            return SupervisorGuidanceContractSummary(
                kind: .grantResolution,
                trigger: "Runtime",
                reviewLevel: "",
                verdict: "",
                summary: trimmed,
                primaryBlocker: "grant_pending",
                currentState: "",
                nextStep: "",
                nextSafeAction: "open_hub_grants",
                recommendedActions: [],
                workOrderRef: "",
                effectiveSupervisorTier: "",
                effectiveWorkOrderDepth: ""
            )
        }

        return nil
    }

    private static func blockedSummaryText(for text: String) -> String? {
        labeledValue(in: text, key: "blocked_summary").map { "阻塞说明： \($0)" }
    }

    private static func governanceTruthText(for text: String) -> String? {
        labeledValue(in: text, key: "governance_truth").map(XTGovernanceTruthPresentation.displayText)
    }

    private static func governanceReasonText(for text: String) -> String? {
        labeledValue(in: text, key: "governance_reason").map { "治理原因： \($0)" }
    }

    private static func policyReasonText(for text: String) -> String? {
        labeledValue(in: text, key: "policy_reason").map { "策略原因： \($0)" }
    }

    private static func keyValueTokens(
        _ text: String,
        separators: CharacterSet
    ) -> [String: String] {
        let tokens = text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var out: [String: String] = [:]
        for token in tokens {
            guard let idx = token.firstIndex(of: "=") else { continue }
            let key = String(token[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = String(token[token.index(after: idx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            out[key] = value
        }
        return out
    }

    private static func labeledValue(
        in text: String,
        key: String
    ) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = "(?:^|\\n| · )\(escapedKey)=([\\s\\S]*?)(?=(?:\\n| · )[A-Za-z_]+=|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return normalizedToken(String(text[valueRange]))
    }

    private static func normalizedToken(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isGrantReason(_ reason: String) -> Bool {
        let normalized = reason.lowercased()
        return normalized.contains("authorization")
            || normalized.contains("grant")
            || normalized.contains("approve")
    }

    private static func actionDescriptors(
        for contract: SupervisorGuidanceContractSummary?
    ) -> [SupervisorCardActionDescriptor] {
        guard let contract else { return [] }

        switch contract.kind {
        case .grantResolution:
            guard let url = XTDeepLinkURLBuilder.hubSetupURL(
                sectionId: "review_grants",
                title: "Hub 授权与权限",
                detail: "查看待处理授权与授权阻塞。"
            )?.absoluteString else {
                return []
            }
            return [
                .init(
                    action: .openURL(label: "打开授权", url: url),
                    label: "打开授权",
                    style: .standard,
                    isEnabled: true
                )
            ]
        case .incidentRecovery:
            guard let url = XTDeepLinkURLBuilder.settingsURL(
                sectionId: "diagnostics",
                title: "XT Diagnostics",
                detail: "查看运行失败与修复线索。"
            )?.absoluteString else {
                return []
            }
            return [
                .init(
                    action: .openURL(label: "打开诊断", url: url),
                    label: "打开诊断",
                    style: .standard,
                    isEnabled: true
                )
            ]
        case .uiReviewRepair, .awaitingInstruction, .supervisorReplan:
            return []
        }
    }
}
