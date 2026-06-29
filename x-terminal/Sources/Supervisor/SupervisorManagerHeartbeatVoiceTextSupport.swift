import Foundation

extension SupervisorManager {
    func heartbeatGovernanceVoicePriority(
        _ signal: SupervisorGovernanceSignalVoicePresentation
    ) -> SupervisorVoiceJobPriority {
        switch signal.trigger {
        case .authorization:
            return .normal
        case .blocked:
            return .normal
        case .completed, .userQueryReply:
            return .quiet
        }
    }

    func heartbeatRecoveryVoiceTrigger(
        _ signal: HeartbeatRecoveryFollowUpSignal
    ) -> SupervisorVoiceJobTrigger {
        signal.action == .requestGrantFollowUp ? .authorization : .blocked
    }

    func heartbeatRecoveryVoicePriority(
        _ signal: HeartbeatRecoveryFollowUpSignal
    ) -> SupervisorVoiceJobPriority {
        switch signal.urgency {
        case .urgent:
            return .interrupt
        case .active:
            return .normal
        case .observe:
            return .quiet
        }
    }

    func heartbeatProjectName(
        for projectId: String,
        in projects: [AXProjectEntry]
    ) -> String? {
        projects.first(where: { $0.projectId == projectId })?.displayName
    }

    func heartbeatProjectionTrigger(
        reason: String,
        changed: Bool,
        blockerProjects: [(projectId: String, blocker: String)],
        blockerSignal: BlockerSignal,
        permissionSignals: [ProjectPermissionSignal],
        governedReviewSignal: HeartbeatGovernedReviewSignal?,
        governanceRepairSignals: [ProjectGovernanceRepairSignal],
        queueSignals: [ProjectQueueSignal],
        nextStepSummary: String
    ) -> String {
        if !permissionSignals.isEmpty {
            return "awaiting_authorization"
        }
        if !governanceRepairSignals.isEmpty {
            return "blocked"
        }
        if !blockerProjects.isEmpty {
            return "blocked"
        }
        if let governedReviewSignal {
            return governedReviewSignal.reviewLevel == .r3Rescue
                ? "blocked"
                : "critical_path_changed"
        }
        if changed || blockerSignal.escalated || !nextStepSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "critical_path_changed"
        }
        if reason == "timer" && !queueSignals.isEmpty {
            return "daily_digest"
        }
        return "daily_digest"
    }

    func conciseHeartbeatNextStep(_ text: String) -> String? {
        for rawLine in text.split(separator: "\n") {
            let line = heartbeatLineWithoutActionSuffix(
                rawLine
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "•", with: "")
                .replacingOccurrences(
                    of: #"^\d+\.\s*"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if !line.isEmpty {
                if let action = conciseHeartbeatRecommendedAction(from: line) {
                    return capped(action, maxChars: 40)
                }
                return capped(line, maxChars: 40)
            }
        }
        return nil
    }

    func conciseHeartbeatRecommendedAction(from line: String) -> String? {
        if line.contains("建议先清队列") {
            return "清队列"
        }
        if let target = conciseHeartbeatActionTarget(in: line, marker: "建议先查看") {
            return conciseHeartbeatActionPhrase(verb: "查看", target: target)
        }
        if let target = conciseHeartbeatActionTarget(in: line, marker: "建议先打开") {
            return conciseHeartbeatActionPhrase(verb: "打开", target: target)
        }
        if let target = conciseHeartbeatActionTarget(in: line, marker: "建议先看") {
            return conciseHeartbeatActionPhrase(verb: "看", target: target)
        }
        return nil
    }

    func conciseHeartbeatActionPhrase(
        verb: String,
        target: String
    ) -> String {
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty else { return verb }
        guard let firstScalar = trimmedTarget.unicodeScalars.first else {
            return verb
        }
        let separator = firstScalar.isASCII ? " " : ""
        return "\(verb)\(separator)\(trimmedTarget)"
    }

    func conciseHeartbeatActionTarget(
        in line: String,
        marker: String
    ) -> String? {
        guard let range = line.range(of: marker) else { return nil }
        var target = String(line[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }

        let separators: Set<Character> = ["。", "；", ";", "，", ",", "（", "("]
        if let boundary = target.firstIndex(where: { separators.contains($0) }) {
            target = String(target[..<boundary])
        }

        target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.hasPrefix("/") {
            target.removeFirst()
            target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !target.isEmpty else { return nil }
        return target
    }

    func heartbeatLineWithoutActionSuffix(_ line: String) -> String {
        let markers = ["（打开：", "(打开:"]
        let stripped = markers.reduce(line) { partial, marker in
            guard let range = partial.range(of: marker) else { return partial }
            return String(partial[..<range.lowerBound])
        }
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func conciseVoiceReplyScript(_ text: String) -> [String] {
        let cueLine = extractSupervisorCalendarCueLine(from: text)
        let baseText = removingSupervisorCalendarCueLine(from: text)
        var script = SupervisorVoiceScriptBuilder.conciseReplyScript(from: baseText)

        guard let cueLine else {
            return script
        }

        if script.isEmpty {
            return [cueLine]
        }
        if script.count == 1 {
            script.append(cueLine)
            return script
        }
        script[1] = cueLine
        return script
    }

    func extractSupervisorCalendarCueLine(from text: String) -> String? {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                line.hasPrefix("哦，对了，") || line.hasPrefix("Oh, one more thing,")
            }
    }

    func removingSupervisorCalendarCueLine(from text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.hasPrefix("哦，对了，") &&
                    !trimmed.hasPrefix("Oh, one more thing,")
            }
            .joined(separator: "\n")
    }
}
